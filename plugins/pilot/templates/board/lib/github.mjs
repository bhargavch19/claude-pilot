import { execFile } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { NOOP } from './trace.mjs';
import { join } from 'node:path';

const defaultRun = (cmd, args, cwd) =>
  new Promise((resolve) => {
    execFile(cmd, args, { cwd, maxBuffer: 16 * 1024 * 1024 }, (err, stdout) => {
      resolve({ stdout: stdout ?? '', code: err ? (err.code ?? 1) : 0 });
    });
  });

const PR_FIELDS = 'number,title,headRefName,state,isDraft,updatedAt,url,mergedAt';

// `gh pr list --limit N` returns the N most recent pull requests and reports
// nothing about what it dropped. On a long-lived repo an old merged PR falling
// off the end silently reverts its story from `done` to `todo` — the board
// contradicting shipped work with no way to tell that is what happened. A full
// page is therefore reported, since it is indistinguishable from a truncated
// one. Exported so the warning and the tests cannot drift from the flag.
export const PR_LIMIT = 500;

// Candidates tried, in order, when the remote doesn't tell us its default
// branch outright.
const DEFAULT_BRANCH_CANDIDATES = ['origin/main', 'origin/master', 'main', 'master'];

// The injectable `run` contract only promises `(cmd, args) => Promise<{stdout, code}>`;
// it doesn't promise the promise never rejects. Treat a rejection exactly
// like a non-zero exit so every call site degrades instead of throwing.
async function safeRun(run, cmd, args, cwd) {
  try {
    return await run(cmd, args, cwd);
  } catch {
    return { stdout: '', code: 1 };
  }
}

// Resolves the ref that `ahead` counts must be measured against. Comparing
// against whatever happens to be checked out (plain `HEAD`) would make the
// board's status depend on operator/CI state rather than branch content —
// running the build from a feature branch or a detached-HEAD checkout would
// silently change every `ahead` count. Resolving an explicit default ref
// keeps the comparison stable regardless of what's checked out.
async function resolveDefaultRef(run, cwd) {
  const symRes = await safeRun(run, 'git', ['symbolic-ref', '--short', 'refs/remotes/origin/HEAD'], cwd);
  if (symRes.code === 0) {
    const ref = symRes.stdout.trim();
    if (ref) return ref;
  }

  for (const candidate of DEFAULT_BRANCH_CANDIDATES) {
    const verifyRes = await safeRun(run, 'git', ['rev-parse', '--verify', '--quiet', candidate], cwd);
    if (verifyRes.code === 0) return candidate;
  }

  return null;
}

// A branch usually exists on exactly one clone — the author's — and as
// `origin/<branch>` everywhere else. Listing only `refs/heads/` therefore made
// a colleague's pushed work invisible: a story with commits and no PR showed
// `todo` on every machine except the one that owned the branch, which is
// exactly why nobody noticed.
//
// Scanning both ref namespaces means the same branch can arrive twice, so
// collapse on the name with any `origin/` prefix removed. The higher `ahead`
// wins because it is the one that reflects all the work that exists: a local
// branch not yet pushed is ahead of its remote, and a remote branch fetched
// but not merged locally is ahead of the stale local copy. Ties keep the local
// name, which is what the developer actually typed.
// Exported because scripts/build-board.mjs must strip the prefix the same way
// when it looks a story's branch up in `cycles`. Two independent copies of this
// rule is how the board and the cycle map would quietly disagree about which
// cycle belongs to which story — the same reason PR_LIMIT is exported.
export const bareBranch = (name) => String(name).replace(/^origin\//, '');

// Pilot slugs a branch by replacing `/` with `-`; the cycle file for branch
// `feat/dark-mode` is `.pilot/cycles/feat-dark-mode.json`.
export const cycleSlug = (branch) => bareBranch(branch).replace(/\//g, '-');

const isRemote = (name) => name.startsWith('origin/');

function dedupeBranches(branches) {
  const byName = new Map();
  for (const branch of branches) {
    const key = bareBranch(branch.name);
    const seen = byName.get(key);
    if (!seen) {
      byName.set(key, branch);
    } else if (branch.ahead > seen.ahead) {
      byName.set(key, branch);
    } else if (branch.ahead === seen.ahead && isRemote(seen.name) && !isRemote(branch.name)) {
      byName.set(key, branch);
    }
  }
  return [...byName.values()];
}

const defaultReadLocalCycle = async (cwd, slug) =>
  readFile(join(cwd, '.pilot', 'cycles', `${slug}.json`), 'utf8').catch(() => null);

// One `git show` per candidate branch. Reading only the branches a story
// actually matched would be cheaper, but matching happens in build-board.mjs —
// and moving a shell-out there would put a second impure module in a lib/ that
// has exactly one on purpose. The cost is the same order as the `gh` read above
// and bounded by candidate count.
//
// Remote first: a cycle file committed on its own story branch is visible from
// every clone and from CI, where a local one is visible only to its author. That
// is the same lesson as the refs/heads/ bug — local-only state made a
// colleague's work invisible everywhere but their own machine.
//
// Each entry records the `path` it came from, because spec §5 promises the
// malformed-cycle warning names the file. Without it the warning can only name
// the story, which tells a reader a cycle is broken but not where to go and fix
// it.
//
// A failure at any tier is silent. Pilot is optional, most branches have no
// cycle, and a warning per branch would bury the warnings that matter.
async function readCycles(run, readLocalCycle, cwd, candidates, trace) {
  const cycles = new Map();
  trace('cycles.begin', { candidates: candidates.length });

  for (const candidate of candidates) {
    // A PR's headRefName can be null, and `bareBranch(null)` would stringify to
    // "null" and go looking for `.pilot/cycles/null.json`.
    if (typeof candidate !== 'string' || !candidate) continue;

    const bare = bareBranch(candidate);
    if (!bare || cycles.has(bare)) continue;

    const path = `.pilot/cycles/${cycleSlug(bare)}.json`;
    const remoteRef = `origin/${bare}:${path}`;

    const remote = await safeRun(run, 'git', ['show', remoteRef], cwd);
    if (remote.code === 0 && remote.stdout.trim()) {
      cycles.set(bare, {
        text: remote.stdout, source: `remote:origin/${bare}`, path: remoteRef,
      });
      trace('cycle.hit', { branch: bare, tier: 'remote', path: remoteRef });
      continue;
    }

    // The injected reader only promises to resolve; like `run`, it does not
    // promise never to reject.
    let local = null;
    try {
      local = await readLocalCycle(cwd, cycleSlug(bare));
    } catch {
      local = null;
    }
    if (typeof local === 'string' && local.trim()) {
      cycles.set(bare, { text: local, source: 'local', path });
      trace('cycle.hit', { branch: bare, tier: 'local', path });
    } else {
      trace('cycle.miss', { branch: bare, remote: remoteRef, local: path });
    }
  }

  trace('cycles.end', { found: cycles.size });
  return cycles;
}

export async function readGitFacts({
  cwd = process.cwd(),
  run = defaultRun,
  readLocalCycle = defaultReadLocalCycle,
  trace = NOOP,
} = {}) {
  trace('git.begin', { cwd });
  const prRes = await safeRun(run, 'gh', ['pr', 'list', '--state', 'all', '--limit', String(PR_LIMIT),
    '--json', PR_FIELDS], cwd);

  let prs = [];
  let degraded = false;
  const warnings = [];

  trace('gh.pr-list', { exit: prRes.code, limit: PR_LIMIT });

  if (prRes.code !== 0) {
    degraded = true;
    warnings.push('PR status unavailable — run `gh auth login`. Showing branch state only.');
  } else {
    try {
      prs = JSON.parse(prRes.stdout || '[]').map((p) => ({
        number: p.number,
        title: p.title,
        headBranch: p.headRefName,
        state: p.mergedAt ? 'merged' : String(p.state).toLowerCase(),
        draft: Boolean(p.isDraft),
        updatedAt: p.updatedAt,
        url: p.url,
      }));
      // Not `degraded`: every PR read is real and usable, so branch state
      // needs no fallback. Only the completeness of the set is in doubt.
      trace('gh.prs', { count: prs.length, capped: prs.length >= PR_LIMIT });
      if (prs.length >= PR_LIMIT) {
        warnings.push(
          `Only the ${PR_LIMIT} most recent pull requests were read; older pull requests ` +
          'are not visible, so a long-finished story may show as todo.',
        );
      }
    } catch {
      degraded = true;
      warnings.push('PR status unavailable — could not parse `gh pr list` output.');
    }
  }

  let branches = [];
  const defaultRef = await resolveDefaultRef(run, cwd);
  trace('git.default-ref', { ref: defaultRef });

  if (!defaultRef) {
    degraded = true;
    warnings.push(
      'Branch status unavailable — could not resolve a default branch ' +
      '(tried origin/HEAD, origin/main, origin/master, main, master).',
    );
  } else {
    const brRes = await safeRun(run, 'git', ['for-each-ref',
      `--format=%(refname:short) %(ahead-behind:${defaultRef})`,
      'refs/heads/', 'refs/remotes/origin/'], cwd);

    if (brRes.code !== 0) {
      degraded = true;
      warnings.push(
        'Branch status unavailable — `git for-each-ref` failed (the ' +
        'ahead-behind atom requires git 2.41+). Showing PR state only.',
      );
    } else {
      const parsed = brRes.stdout
        .split('\n')
        .filter(Boolean)
        .map((line) => {
          const [name, ahead] = line.trim().split(/\s+/);
          return { name, ahead: Number(ahead) || 0 };
        })
        // `refs/remotes/origin/HEAD` is a symbolic alias for the default
        // branch, not a branch a story could ever be named after.
        .filter((b) => b.name !== 'origin/HEAD');

      branches = dedupeBranches(parsed);
      trace('git.branches', { scanned: parsed.length, deduped: branches.length });
    }
  }

  // Candidates are branch refs AND pull-request head branches. Branch refs alone
  // missed every story whose branch this clone never fetched — a fork PR, or a
  // colleague's branch on a shallow clone. `deriveStatus` resolves such a story
  // from `pr.headBranch`, so a prefetch keyed only on `for-each-ref` output never
  // even attempted the lookup and the story silently lost its pilot data. Spec
  // §4.2 says the resolution runs "for each story"; covering both sources is how
  // a branch-keyed prefetch delivers that.
  const cycles = await readCycles(run, readLocalCycle, cwd, [
    ...branches.map((b) => b.name),
    ...prs.map((p) => p.headBranch),
  ], trace);

  trace('git.end', {
    prs: prs.length, branches: branches.length, cycles: cycles.size,
    degraded, warnings: warnings.length,
  });

  return {
    prs, branches, cycles, degraded,
    warning: warnings.length ? warnings.join(' ') : undefined,
  };
}
