import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  readGitFacts as readGitFactsReal, PR_LIMIT, bareBranch, cycleSlug,
} from '../lib/github.mjs';

// Every test goes through this wrapper so none of them can touch the real
// filesystem. Without an explicit `readLocalCycle` the production default reads
// `<cwd>/.pilot/cycles/<slug>.json`, so running the suite inside a repo that
// happened to hold a matching cycle file would quietly change what these tests
// assert — they would still pass, just about something else. Nineteen call sites
// had that exposure; fixing it here rather than at each one means a test added
// later inherits the safe default instead of re-introducing the hole.
//
// `...opts` comes last on purpose: a test that is *about* the local tier passes
// its own reader and overrides this.
const readGitFacts = (opts = {}) =>
  readGitFactsReal({ readLocalCycle: async () => null, ...opts });

const GH_JSON = JSON.stringify([
  { number: 42, title: 'JYO-4: chart', headRefName: 'JYO-4-chart',
    state: 'OPEN', isDraft: false, updatedAt: '2026-08-05T00:00:00Z',
    url: 'https://x/42', mergedAt: null },
  { number: 43, title: 'JYO-2: setup', headRefName: 'JYO-2-setup',
    state: 'MERGED', isDraft: false, updatedAt: '2026-08-02T00:00:00Z',
    url: 'https://x/43', mergedAt: '2026-08-02T00:00:00Z' },
  { number: 44, title: 'JYO-9: abandoned', headRefName: 'JYO-9-abandoned',
    state: 'CLOSED', isDraft: false, updatedAt: '2026-08-01T00:00:00Z',
    url: 'https://x/44', mergedAt: null },
]);

// A fake `run` that dispatches on (cmd, args[0]) with per-hook responses.
// `revParse`, `forEachRef` and `show` may be functions so a test can inspect the
// exact args a call received (e.g. which candidate ref was verified, or
// which ref reached the ahead-behind format string). Anything not given a
// hook fails with a non-zero exit, matching a real missing/unauthenticated
// `gh` or an old `git`.
function fakeRun({ gh, symbolicRef, revParse, forEachRef, show } = {}) {
  const fail = { stdout: '', code: 1 };
  return async (cmd, args) => {
    if (cmd === 'gh' && args[0] === 'pr') return gh ?? fail;
    if (cmd === 'git' && args[0] === 'symbolic-ref') return symbolicRef ?? fail;
    if (cmd === 'git' && args[0] === 'rev-parse') {
      if (!revParse) return fail;
      const candidate = args[args.length - 1];
      return typeof revParse === 'function' ? revParse(candidate) : (revParse[candidate] ?? fail);
    }
    if (cmd === 'git' && args[0] === 'for-each-ref') {
      if (!forEachRef) return fail;
      return typeof forEachRef === 'function' ? forEachRef(args) : forEachRef;
    }
    if (cmd === 'git' && args[0] === 'show') {
      if (!show) return fail;
      return typeof show === 'function' ? show(args) : show;
    }
    return fail;
  };
}

const OK = (stdout) => ({ stdout, code: 0 });

test('normalises gh output into PR facts', async () => {
  const facts = await readGitFacts({
    run: fakeRun({ gh: OK(GH_JSON), symbolicRef: OK('origin/main\n'), forEachRef: OK('') }),
  });
  assert.equal(facts.degraded, false);
  assert.equal(facts.prs.length, 3);
  assert.deepEqual(facts.prs[0], {
    number: 42, title: 'JYO-4: chart', headBranch: 'JYO-4-chart',
    state: 'open', draft: false, updatedAt: '2026-08-05T00:00:00Z',
    url: 'https://x/42',
  });
  assert.equal(facts.prs[1].state, 'merged');
});

test('a closed, unmerged PR maps to closed, not merged', async () => {
  const facts = await readGitFacts({
    run: fakeRun({ gh: OK(GH_JSON), symbolicRef: OK('origin/main\n'), forEachRef: OK('') }),
  });
  assert.equal(facts.prs[2].state, 'closed');
});

test('parses branch names and ahead counts from realistic two-number ahead-behind output', async () => {
  const facts = await readGitFacts({
    run: fakeRun({
      gh: OK('[]'),
      symbolicRef: OK('origin/main\n'),
      // Real `%(ahead-behind:<ref>)` output is "<ahead> <behind>", not one
      // number — assert we read the first (ahead), not the second (behind).
      forEachRef: OK('JYO-4-chart 3 0\nJYO-2-setup 0 1\n'),
    }),
  });
  assert.deepEqual(facts.branches, [
    { name: 'JYO-4-chart', ahead: 3 },
    { name: 'JYO-2-setup', ahead: 0 },
  ]);
});

test('degrades gracefully when gh is missing', async () => {
  const facts = await readGitFacts({
    run: fakeRun({ symbolicRef: OK('origin/main\n'), forEachRef: OK('JYO-4-chart 1 0\n') }),
  });
  assert.equal(facts.degraded, true);
  assert.deepEqual(facts.prs, []);
  assert.equal(facts.branches.length, 1);
  assert.match(facts.warning, /gh auth login/);
});

test('degrades gracefully when gh output cannot be parsed as JSON', async () => {
  const facts = await readGitFacts({
    run: fakeRun({ gh: OK('not json'), symbolicRef: OK('origin/main\n'), forEachRef: OK('') }),
  });
  assert.equal(facts.degraded, true);
  assert.deepEqual(facts.prs, []);
  assert.match(facts.warning, /could not parse/);
});

test('resolves ahead counts against the remote default branch, not HEAD', async () => {
  let capturedArgs;
  const facts = await readGitFacts({
    run: fakeRun({
      gh: OK('[]'),
      symbolicRef: OK('origin/main\n'),
      forEachRef: (args) => {
        capturedArgs = args;
        return OK('');
      },
    }),
  });
  assert.equal(facts.degraded, false);
  assert.ok(
    capturedArgs.some((a) => a === '--format=%(refname:short) %(ahead-behind:origin/main)'),
    `expected for-each-ref to use origin/main, got: ${JSON.stringify(capturedArgs)}`,
  );
});

test('falls back through origin/main, origin/master, main, master when symbolic-ref fails', async () => {
  const verifiedCandidates = [];
  let capturedArgs;
  const facts = await readGitFacts({
    run: fakeRun({
      gh: OK('[]'),
      // symbolic-ref not stubbed -> fails.
      revParse: (candidate) => {
        verifiedCandidates.push(candidate);
        // Only the local `main` exists in this fake repo.
        return candidate === 'main' ? OK('') : { stdout: '', code: 1 };
      },
      forEachRef: (args) => {
        capturedArgs = args;
        return OK('');
      },
    }),
  });

  assert.deepEqual(verifiedCandidates, ['origin/main', 'origin/master', 'main']);
  assert.ok(capturedArgs.some((a) => a === '--format=%(refname:short) %(ahead-behind:main)'));
  assert.equal(facts.degraded, false);
});

test('degrades with a named warning when no default branch can be resolved', async () => {
  const facts = await readGitFacts({
    run: fakeRun({ gh: OK('[]') }), // symbolic-ref and every rev-parse candidate fail
  });
  assert.equal(facts.degraded, true);
  assert.deepEqual(facts.branches, []);
  assert.match(facts.warning, /default branch/);
});

// A colleague pushes JYO-4-chart with commits and opens no PR. On their own
// machine the branch is local and the board is right; on everyone else's it
// exists only as origin/JYO-4-chart, and listing refs/heads/ alone showed the
// story as todo for the whole team.
test('scans remote branches as well as local ones', async () => {
  let capturedArgs;
  const facts = await readGitFacts({
    run: fakeRun({
      gh: OK('[]'),
      symbolicRef: OK('origin/main\n'),
      forEachRef: (args) => {
        capturedArgs = args;
        return OK('origin/JYO-4-chart 3 0\n');
      },
    }),
  });

  assert.ok(capturedArgs.includes('refs/heads/'));
  assert.ok(capturedArgs.includes('refs/remotes/origin/'));
  assert.deepEqual(facts.branches, [{ name: 'origin/JYO-4-chart', ahead: 3 }]);
});

test('a branch present both locally and remotely appears once, at the higher ahead', async () => {
  const facts = await readGitFacts({
    run: fakeRun({
      gh: OK('[]'),
      symbolicRef: OK('origin/main\n'),
      forEachRef: OK(
        'JYO-4-chart 1 0\n' +
        'origin/JYO-4-chart 3 0\n' +
        'JYO-2-setup 5 0\n' +
        'origin/JYO-2-setup 2 0\n',
      ),
    }),
  });

  assert.deepEqual(facts.branches, [
    { name: 'origin/JYO-4-chart', ahead: 3 },
    { name: 'JYO-2-setup', ahead: 5 },
  ]);
});

test('an equal-ahead duplicate keeps the local name', async () => {
  const facts = await readGitFacts({
    run: fakeRun({
      gh: OK('[]'),
      symbolicRef: OK('origin/main\n'),
      forEachRef: OK('origin/JYO-4-chart 2 0\nJYO-4-chart 2 0\n'),
    }),
  });
  assert.deepEqual(facts.branches, [{ name: 'JYO-4-chart', ahead: 2 }]);
});

test('origin/HEAD is not reported as a branch', async () => {
  const facts = await readGitFacts({
    run: fakeRun({
      gh: OK('[]'),
      symbolicRef: OK('origin/main\n'),
      forEachRef: OK('origin/HEAD 0 0\norigin/JYO-4-chart 1 0\n'),
    }),
  });
  assert.deepEqual(facts.branches, [{ name: 'origin/JYO-4-chart', ahead: 1 }]);
});

test('degrades with a named warning when for-each-ref itself fails (e.g. git < 2.41)', async () => {
  const facts = await readGitFacts({
    run: fakeRun({ gh: OK('[]'), symbolicRef: OK('origin/main\n') }), // forEachRef not stubbed -> fails
  });
  assert.equal(facts.degraded, true);
  assert.deepEqual(facts.branches, []);
  assert.match(facts.warning, /for-each-ref/);
});

test('treats a rejecting run like a failed command instead of throwing', async () => {
  const run = async () => {
    throw new Error('spawn ENOENT');
  };

  const facts = await readGitFacts({ run });

  assert.equal(facts.degraded, true);
  assert.deepEqual(facts.prs, []);
  assert.deepEqual(facts.branches, []);
});

// --- the PR list is capped -----------------------------------------------
// `gh pr list --limit N` returns the N most recent PRs and says nothing about
// what it dropped. On a long-lived repo, an old merged PR falling off the end
// silently reverts its story from `done` to `todo` — the board contradicting
// shipped work, with no way to tell that is what happened.
const manyPrs = (n) => JSON.stringify(
  Array.from({ length: n }, (_, i) => ({
    number: i + 1, title: `JYO-${i + 1}`, headRefName: `JYO-${i + 1}-x`,
    state: 'MERGED', isDraft: false, updatedAt: '2026-08-01T00:00:00Z',
    url: `https://x/${i + 1}`, mergedAt: '2026-08-01T00:00:00Z',
  })),
);

test('a PR list that fills the cap warns that older PRs may be missing', async () => {
  const facts = await readGitFacts({ run: fakeRun({ gh: OK(manyPrs(PR_LIMIT)) }) });
  assert.equal(facts.prs.length, PR_LIMIT);
  assert.match(facts.warning ?? '', /older pull requests/i);
  assert.match(facts.warning ?? '', new RegExp(String(PR_LIMIT)));
});

test('a PR list short of the cap says nothing about truncation', async () => {
  const facts = await readGitFacts({ run: fakeRun({ gh: OK(manyPrs(PR_LIMIT - 1)) }) });
  assert.ok(!/older pull requests/i.test(facts.warning ?? ''));
});

test('hitting the cap is a warning, not a degraded read — the PRs are still usable', async () => {
  const facts = await readGitFacts({ run: fakeRun({ gh: OK(manyPrs(PR_LIMIT)), symbolicRef: OK('origin/main\n'), forEachRef: OK('') }) });
  assert.equal(facts.degraded, false);
  assert.equal(facts.prs[0].state, 'merged');
});

// --- pilot cycle reads ----------------------------------------------------

const CYCLE_TEXT = JSON.stringify({ status: 'fixing', current_phase: 'verify' });

test('bareBranch strips a leading origin/ and leaves anything else alone', () => {
  assert.equal(bareBranch('origin/JYO-4-chart'), 'JYO-4-chart');
  assert.equal(bareBranch('JYO-4-chart'), 'JYO-4-chart');
  // Only a *leading* origin/ is a remote prefix. A branch genuinely named
  // "feat/origin/x" keeps its path.
  assert.equal(bareBranch('feat/origin/x'), 'feat/origin/x');
});

test('cycleSlug matches pilot slugging: origin stripped, slashes to dashes', () => {
  assert.equal(cycleSlug('origin/feat/dark-mode'), 'feat-dark-mode');
  assert.equal(cycleSlug('JYO-4-chart'), 'JYO-4-chart');
});

test('reads a cycle from the story branch on the remote', async () => {
  const seen = [];
  const facts = await readGitFacts({
    run: fakeRun({
      gh: OK('[]'),
      symbolicRef: OK('origin/main\n'),
      forEachRef: OK('origin/JYO-4-chart 3 0\n'),
      show: (args) => { seen.push(args[1]); return OK(CYCLE_TEXT); },
    }),
    readLocalCycle: async () => null,
  });
  assert.deepEqual(seen, ['origin/JYO-4-chart:.pilot/cycles/JYO-4-chart.json']);
  assert.deepEqual(facts.cycles.get('JYO-4-chart'), {
    text: CYCLE_TEXT, source: 'remote:origin/JYO-4-chart',
    path: 'origin/JYO-4-chart:.pilot/cycles/JYO-4-chart.json',
  });
});

// The two tiers in contention. Without this, the remote test (which stubs
// readLocalCycle to null) and the fallback test (which omits the `show` hook)
// each exercise one tier alone, so inverting the order in readCycles — trying
// local first and falling back to `git show` — left the suite green. The tier
// order is the whole point of reading remote-first, so it gets its own case.
test('remote wins when the same branch has both a committed and a local cycle', async () => {
  const LOCAL_TEXT = JSON.stringify({ status: 'building', current_phase: 'apply' });
  const facts = await readGitFacts({
    run: fakeRun({
      gh: OK('[]'),
      symbolicRef: OK('origin/main\n'),
      forEachRef: OK('origin/JYO-4-chart 3 0\n'),
      show: () => OK(CYCLE_TEXT),
    }),
    readLocalCycle: async () => LOCAL_TEXT,
  });
  assert.deepEqual(facts.cycles.get('JYO-4-chart'), {
    text: CYCLE_TEXT, source: 'remote:origin/JYO-4-chart',
    path: 'origin/JYO-4-chart:.pilot/cycles/JYO-4-chart.json',
  });
});

// The remote read must reconstruct `origin/<bare>` rather than reuse
// branch.name. Asserting that on a branch whose deduped name already starts
// with `origin/` makes the prefixing a no-op, so the ref is pinned here on the
// common real shape instead: a local branch ahead of its remote, which
// dedupeBranches resolves to the bare name. Reusing branch.name there would
// read the local tree and silently defeat remote-first.
test('reads the origin ref even when the deduped branch name is the local one', async () => {
  const seen = [];
  const facts = await readGitFacts({
    run: fakeRun({
      gh: OK('[]'),
      symbolicRef: OK('origin/main\n'),
      forEachRef: OK('JYO-4-chart 3 0\norigin/JYO-4-chart 1 0\n'),
      show: (args) => { seen.push(args[1]); return OK(CYCLE_TEXT); },
    }),
    readLocalCycle: async () => null,
  });
  assert.deepEqual(seen, ['origin/JYO-4-chart:.pilot/cycles/JYO-4-chart.json']);
  assert.deepEqual(facts.cycles.get('JYO-4-chart'), {
    text: CYCLE_TEXT, source: 'remote:origin/JYO-4-chart',
    path: 'origin/JYO-4-chart:.pilot/cycles/JYO-4-chart.json',
  });
});

test('falls back to the local cycle when the branch has none committed', async () => {
  const asked = [];
  const facts = await readGitFacts({
    run: fakeRun({
      gh: OK('[]'),
      symbolicRef: OK('origin/main\n'),
      forEachRef: OK('JYO-4-chart 3 0\n'),
      // no `show` hook -> git show exits non-zero, as it does for a branch
      // whose author has not enabled publish_cycles
    }),
    readLocalCycle: async (_cwd, slug) => { asked.push(slug); return CYCLE_TEXT; },
  });
  assert.deepEqual(asked, ['JYO-4-chart']);
  assert.deepEqual(facts.cycles.get('JYO-4-chart'), {
    text: CYCLE_TEXT, source: 'local', path: '.pilot/cycles/JYO-4-chart.json',
  });
});

test('a branch with no cycle anywhere simply has no entry', async () => {
  const facts = await readGitFacts({
    run: fakeRun({ gh: OK('[]'), symbolicRef: OK('origin/main\n'),
      forEachRef: OK('JYO-4-chart 3 0\n') }),
    readLocalCycle: async () => null,
  });
  assert.equal(facts.cycles.has('JYO-4-chart'), false);
  assert.equal(facts.degraded, false);
});

test('an empty or whitespace-only cycle file is treated as absent, not as a cycle', async () => {
  const facts = await readGitFacts({
    run: fakeRun({ gh: OK('[]'), symbolicRef: OK('origin/main\n'),
      forEachRef: OK('JYO-4-chart 3 0\n'), show: () => OK('   \n') }),
    readLocalCycle: async () => '',
  });
  assert.equal(facts.cycles.has('JYO-4-chart'), false);
});

test('a throwing readLocalCycle degrades like any other failed read', async () => {
  const facts = await readGitFacts({
    run: fakeRun({ gh: OK('[]'), symbolicRef: OK('origin/main\n'),
      forEachRef: OK('JYO-4-chart 3 0\n') }),
    readLocalCycle: async () => { throw new Error('EACCES'); },
  });
  assert.equal(facts.cycles.has('JYO-4-chart'), false);
  assert.equal(facts.degraded, false);
});

test('the same branch seen local and remote is read once, under its bare name', async () => {
  let shows = 0;
  const facts = await readGitFacts({
    run: fakeRun({
      gh: OK('[]'),
      symbolicRef: OK('origin/main\n'),
      // dedupeBranches already collapses these to one entry; this pins that the
      // cycle read never re-expands them into two lookups.
      forEachRef: OK('JYO-4-chart 3 0\norigin/JYO-4-chart 1 0\n'),
      show: () => { shows += 1; return OK(CYCLE_TEXT); },
    }),
    readLocalCycle: async () => null,
  });
  assert.equal(shows, 1);
  assert.deepEqual([...facts.cycles.keys()], ['JYO-4-chart']);
});

test('cycles is empty rather than absent when no default branch resolves', async () => {
  // Branch discovery failed, so there are no branches to look cycles up for.
  // An empty Map keeps every consumer on one code path.
  const facts = await readGitFacts({ run: fakeRun({ gh: OK('[]') }) });
  assert.equal(facts.degraded, true);
  assert.equal(facts.cycles.size, 0);
});

// A story can resolve its branch from a pull request's head branch rather than
// from a local or remote ref — a fork PR, or any branch this clone never
// fetched. Prefetching cycles from `for-each-ref` output alone never attempted
// those, so the story silently lost its pilot data even though `git show` on the
// PR's head branch would have found it. Spec §4.2 says "for each story"; these
// pin that every branch a story can actually resolve to gets a lookup.
test('a cycle is read for a PR head branch that no ref reported', async () => {
  const seen = [];
  const facts = await readGitFacts({
    run: fakeRun({
      gh: OK(GH_JSON),
      symbolicRef: OK('origin/main\n'),
      forEachRef: OK(''),
      show: (args) => { seen.push(args[1]); return OK(CYCLE_TEXT); },
    }),
  });
  assert.ok(seen.includes('origin/JYO-4-chart:.pilot/cycles/JYO-4-chart.json'));
  assert.deepEqual(facts.cycles.get('JYO-4-chart'), {
    text: CYCLE_TEXT,
    source: 'remote:origin/JYO-4-chart',
    path: 'origin/JYO-4-chart:.pilot/cycles/JYO-4-chart.json',
  });
});

test('a PR head branch also reaches the local tier', async () => {
  const facts = await readGitFacts({
    run: fakeRun({ gh: OK(GH_JSON), symbolicRef: OK('origin/main\n'), forEachRef: OK('') }),
    readLocalCycle: async (_cwd, slug) => (slug === 'JYO-2-setup' ? CYCLE_TEXT : null),
  });
  assert.deepEqual(facts.cycles.get('JYO-2-setup'), {
    text: CYCLE_TEXT, source: 'local', path: '.pilot/cycles/JYO-2-setup.json',
  });
});

test('a branch and a PR naming it are read once, not twice', async () => {
  let shows = 0;
  await readGitFacts({
    run: fakeRun({
      gh: OK(GH_JSON),
      symbolicRef: OK('origin/main\n'),
      forEachRef: OK('JYO-4-chart 3 0\n'),
      show: (args) => { shows += args[1].includes('JYO-4-chart') ? 1 : 0; return OK(CYCLE_TEXT); },
    }),
  });
  assert.equal(shows, 1);
});

test('a PR with a null head branch is skipped rather than read as "undefined"', async () => {
  const seen = [];
  const facts = await readGitFacts({
    run: fakeRun({
      gh: OK(JSON.stringify([{ number: 9, title: 'JYO-9', headRefName: null,
        state: 'OPEN', isDraft: false, updatedAt: '2026-08-01T00:00:00Z',
        url: 'u', mergedAt: null }])),
      symbolicRef: OK('origin/main\n'),
      forEachRef: OK(''),
      show: (args) => { seen.push(args[1]); return OK(CYCLE_TEXT); },
    }),
  });
  assert.deepEqual(seen, []);
  assert.equal(facts.cycles.size, 0);
});

// Spec §5 promises the malformed-cycle warning names *the file*. The entry has
// to carry its own path for that to be possible at warning time.
test('a cycle entry records the path it was read from', async () => {
  const facts = await readGitFacts({
    run: fakeRun({ gh: OK('[]'), symbolicRef: OK('origin/main\n'),
      forEachRef: OK('JYO-4-chart 3 0\n') }),
    readLocalCycle: async () => CYCLE_TEXT,
  });
  assert.equal(facts.cycles.get('JYO-4-chart').path, '.pilot/cycles/JYO-4-chart.json');
});
