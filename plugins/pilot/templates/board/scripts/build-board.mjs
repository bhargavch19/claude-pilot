import { readFile, readdir, writeFile } from 'node:fs/promises';
import { join, dirname, basename, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseTdd, TddParseError } from '../lib/tdd.mjs';
import { parseEpicsWithDuplicates } from '../lib/epics.mjs';
import { validateStories } from '../lib/validate.mjs';
import { deriveStatus } from '../lib/status.mjs';
import { readGitFacts, bareBranch } from '../lib/github.mjs';
import { createTrace, traceEnabled, NOOP } from '../lib/trace.mjs';
import { parseCycle, projectPilot } from '../lib/pilot.mjs';

const CHECKBOX = /^\s*-\s+\[([ xX])\]\s+(.*)$/;
const FENCE = /^(```|~~~)/;

// Technical Design Documents routinely show an example checklist inside a
// fenced code block (e.g. to specify UI copy). Scanning every line blindly
// would turn that sample into phantom acceptance criteria on the board, with
// no way for a reader to trace the wrong card back to a code sample in the
// source. Track fence state and skip checkbox matching while inside one. An
// unterminated fence is treated as "still inside" through the end of the
// document — safer than falling back out and emitting whatever garbage
// follows.
export function parseAcceptance(body) {
  const acceptance = [];
  let inFence = false;

  for (const line of body.split('\n')) {
    if (FENCE.test(line.trim())) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;

    const m = CHECKBOX.exec(line);
    if (m) acceptance.push({ text: m[2].trim(), checked: m[1].toLowerCase() === 'x' });
  }

  return acceptance;
}

// project.key used to be `stories[0]?.id.split('-')[0]`, which depended on
// filename sort order — an accident of directory listing, not a real
// signal. Instead, derive it from the most frequent id prefix across all
// stories (ties broken alphabetically, so the result never depends on story
// or file order). A repo is meant to hold one project's stories, so more
// than one distinct prefix is a real condition worth a board warning, not
// something to silently paper over by picking one.
export function deriveProjectKey(stories) {
  if (!stories.length) return { key: 'APP', warning: null };

  const counts = new Map();
  for (const s of stories) {
    const prefix = s.id.split('-')[0];
    counts.set(prefix, (counts.get(prefix) ?? 0) + 1);
  }

  const [key] = [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0];

  let warning = null;
  if (counts.size > 1) {
    const prefixes = [...counts.keys()].sort().join(', ');
    warning = `multiple story-id prefixes found (${prefixes}); using "${key}" as the project key`;
  }

  return { key, warning };
}

// board.json is the deployed artifact: whatever `promptBody` holds gets
// published with the board. A `prompt:` value is author-controlled text from a
// Technical Design Document, so it has to be confined to the repo before it is
// read — `prompt: ../../../../.ssh/id_rsa` was previously read and embedded
// verbatim.
//
// Compares against `repoRoot + sep` so a sibling directory whose name merely
// starts with the root's (`/work/repo-backup` next to `/work/repo`) does not
// count as inside. Symlinks are NOT resolved: a symlink pointing out of the
// repo is a committed file, visible in the PR that adds it, and following it
// with realpath would also break legitimately symlinked prompt directories.
export function resolvePromptPath(repoRoot, promptPath) {
  const root = resolve(repoRoot);
  const full = resolve(join(root, promptPath));
  return full === root || full.startsWith(root + sep) ? full : null;
}

// Joins a story to pilot's cycle for the branch the board already resolved.
// Never re-derives a branch of its own: two independent branch derivations is
// how the board and the cycle map would disagree about whose cycle this is.
//
// A `done` story drops its cycle silently (spec §3). The work merged, so
// whatever phase the cycle last claimed stopped being true at merge — and that
// is history, not a defect to report.
//
// Returns warnings rather than pushing them, so the caller keeps one warning
// list and this stays a function of its inputs.
export function resolvePilot(story, derived, cycles) {
  const none = { pilot: null, pilotSource: null, warnings: [] };

  const branch = derived.branch ?? derived.pr?.headBranch ?? null;
  if (!branch || derived.status === 'done') return none;
  if (!(cycles instanceof Map)) return none;

  const entry = cycles.get(bareBranch(branch));
  if (!entry) return none;

  // Warnings name the file, not just the story (spec §5). "JYO-4: pilot cycle
  // unreadable" tells a reader something is broken but not where to go and fix
  // it — and for a `local` source there is no other way to find the file.
  const where = entry.path ? ` (${entry.path})` : '';

  const { cycle, error: parseError } = parseCycle(entry.text);
  if (parseError) {
    return { ...none, warnings: [`${story.id}: pilot cycle unreadable — ${parseError}${where}`] };
  }

  const { pilot, error: projectError } = projectPilot(cycle);
  if (projectError) {
    return { ...none, warnings: [`${story.id}: pilot cycle ignored — ${projectError}${where}`] };
  }

  return { pilot, pilotSource: entry.source, warnings: [] };
}

export async function buildBoard({ repoRoot, gitFacts, trace = NOOP }) {
  trace('build.begin', { repoRoot });

  const brd = await readFile(join(repoRoot, 'BRD.md'), 'utf8').catch(() => '');
  const { epics, duplicates: duplicateEpics } = parseEpicsWithDuplicates(brd);
  trace('brd.parsed', { bytes: brd.length, epics: epics.length, duplicates: duplicateEpics.length });

  const tddDir = join(repoRoot, 'tdd');
  let entries;
  try {
    entries = await readdir(tddDir);
  } catch (e) {
    // ci/run-check.mjs already gives a friendly message for this identical
    // condition; a raw ENOENT stack here would just be a second, worse answer
    // to the same question.
    if (e.code === 'ENOENT') {
      throw new Error(
        `tdd/ not found under ${repoRoot}. Run this from the repo root ` +
          '(the directory that contains tdd/), or pass it as the first argument.',
      );
    }
    throw e;
  }
  const files = entries.filter((f) => f.endsWith('.md')).sort();
  trace('tdd.scanned', { dir: tddDir, files: files.length });

  const raw = [];
  const broken = [];

  for (const f of files) {
    const path = join(tddDir, f);
    const rel = `tdd/${f}`;
    const source = await readFile(path, 'utf8');
    try {
      const { data, body } = parseTdd(source, rel);
      raw.push({ ...data, file: rel, body });
    } catch (e) {
      // A malformed Technical Design Document must not take the whole
      // board down — it goes into broken[] with its parse error, and the
      // build still succeeds. Anything that isn't a recognised parse
      // failure is a real bug and should still surface.
      if (e instanceof TddParseError) {
        broken.push({ file: rel, error: e.message });
        trace('tdd.broken', { file: rel, error: e.message });
      } else throw e;
    }
  }

  const { errors, warnings, invalid } = validateStories(raw, epics.map((e) => e.slug));
  trace('validate.done', {
    parsed: raw.length, errors: errors.length,
    invalid: invalid.length, warnings: warnings.length,
  });
  if (errors.length) {
    const err = new Error(`board build failed:\n  ${errors.join('\n  ')}`);
    err.errors = errors;
    throw err;
  }

  // A story that fails schema validation is quarantined exactly like one that
  // fails to parse: same broken[] shape, same "Needs attention" lane, and it
  // never reaches deriveStatus — a story with no id or no points has nothing
  // meaningful to derive.
  for (const { file, reason } of invalid) broken.push({ file, error: reason });
  const quarantined = new Set(invalid.map((i) => i.file));
  for (const { file, reason } of invalid) trace('story.quarantined', { file, reason });
  const valid = raw.filter((s) => !quarantined.has(s.file));

  const allWarnings = [...warnings];
  for (const slug of duplicateEpics) {
    allWarnings.push(`BRD.md declares epic "${slug}" more than once; using the first`);
  }
  // Not gated on `degraded`: a git read can be complete enough to trust and
  // still have something to say (the PR list hitting its cap, for instance).
  // Gating on degraded dropped those warnings on the floor.
  if (gitFacts.warning) allWarnings.push(gitFacts.warning);

  const stories = [];
  for (const s of valid) {
    const d = deriveStatus(s, gitFacts);
    trace('story.status', {
      id: s.id, status: d.status, source: d.source,
      branch: d.branch ?? d.pr?.headBranch ?? null,
    });
    if (d.warning) allWarnings.push(d.warning);

    // The detail panel renders the prompt with a copy button, so the body has
    // to travel in board.json — the static UI cannot read the repo. A broken
    // path is a warning, not a quarantine (spec §11): the story itself is
    // fine, only its prompt link is stale.
    let promptBody = null;
    if (s.prompt) {
      const promptPath = resolvePromptPath(repoRoot, s.prompt);
      if (!promptPath) {
        allWarnings.push(
          `${s.id} references a prompt file outside the repo ("${s.prompt}") — ignored`,
        );
      } else {
        try {
          promptBody = await readFile(promptPath, 'utf8');
        } catch {
          allWarnings.push(`${s.id} references a missing prompt file "${s.prompt}"`);
        }
      }
    }

    const { pilot, pilotSource, warnings: pilotWarnings } =
      resolvePilot(s, d, gitFacts.cycles);
    trace('story.pilot', {
      id: s.id, source: pilotSource,
      phase: pilot ? pilot.phase : null, cycleStatus: pilot ? pilot.status : null,
    });
    allWarnings.push(...pilotWarnings);

    stories.push({
      id: s.id,
      title: s.title,
      epic: s.epic,
      points: s.points,
      pointsInitial: s.points_initial,
      adjustments: s.adjustments ?? [],
      owner: s.owner ?? null,
      prompt: s.prompt ?? null,
      promptBody,
      dependsOn: s.depends_on ?? [],
      labels: s.labels ?? [],
      status: d.status,
      statusSource: d.source,
      branch: d.branch ?? d.pr?.headBranch ?? null,
      pr: d.pr ? { number: d.pr.number, url: d.pr.url, state: d.pr.state, draft: d.pr.draft } : null,
      pilot,
      pilotSource,
      acceptance: parseAcceptance(s.body),
      body: s.body,
      file: s.file,
    });
  }

  const { key, warning: keyWarning } = deriveProjectKey(stories);
  if (keyWarning) allWarnings.push(keyWarning);
  trace('build.end', {
    key, stories: stories.length,
    warnings: allWarnings.length, broken: broken.length,
  });

  return {
    generatedAt: new Date().toISOString(),
    // Resolved first: `basename('.')` is '.', so `npm run build -- .` used to
    // name the project ".". A relative root is the normal thing to pass, both
    // by hand and from a CI working directory.
    project: { key, name: basename(resolve(repoRoot)) },
    epics,
    stories,
    warnings: allWarnings,
    broken,
  };
}

// Spec §4 puts the artifact at `board/board.json`, beside the board it feeds —
// not at the app repo root. Resolving from this script's own location keeps
// that true regardless of the directory the build was invoked from, and
// matches the `.gitignore` that ships next to it.
const BOARD_JSON = join(dirname(fileURLToPath(import.meta.url)), '..', 'board.json');

// Flags are stripped before the positional argument is read. Without this,
// `npm run build -- --verbose` would take "--verbose" as the repo root and fail
// with a confusing "tdd/ not found under --verbose".
export const TRACE_FLAGS = new Set(['--verbose', '-v']);

export function parseArgv(argv) {
  const rest = argv.filter((a) => !TRACE_FLAGS.has(a));
  return { repoRoot: rest[0] ?? null };
}

async function main() {
  const argv = process.argv.slice(2);
  const { repoRoot: given } = parseArgv(argv);
  const repoRoot = given ?? process.cwd();
  const trace = createTrace({ enabled: traceEnabled(argv, process.env) });

  try {
    const gitFacts = await readGitFacts({ cwd: repoRoot, trace });
    const board = await buildBoard({ repoRoot, gitFacts, trace });
    // The write is the last statement on purpose: a build that fails must
    // leave no board.json rather than a partial one, and must not overwrite a
    // good previous build with wreckage.
    await writeFile(BOARD_JSON, JSON.stringify(board, null, 2));
    console.log(`${BOARD_JSON}: ${board.stories.length} stories, ` +
      `${board.warnings.length} warnings, ${board.broken.length} broken`);
  } catch (err) {
    // Without this, a fatal validation error surfaced as a raw Node stack and
    // the previous board.json sat there looking current. Print the list
    // legibly, write nothing, exit non-zero.
    if (err.errors?.length) {
      console.error('board build failed:');
      for (const e of err.errors) console.error(`  ${e}`);
    } else {
      console.error(`board build failed: ${err.message}`);
    }
    process.exitCode = 1;
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await main();
}
