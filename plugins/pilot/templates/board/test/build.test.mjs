import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { buildBoard, parseAcceptance, deriveProjectKey, parseArgv } from '../scripts/build-board.mjs';
import { createTrace } from '../lib/trace.mjs';
import { parseEpics, parseEpicsWithDuplicates } from '../lib/epics.mjs';

const FIXTURES = join(dirname(fileURLToPath(import.meta.url)), 'fixtures');
const REPO = join(FIXTURES, 'repo');
const QUARANTINE_REPO = join(FIXTURES, 'quarantine-repo');

const GIT = {
  prs: [{ number: 42, title: 'JYO-4: chart', headBranch: 'JYO-4-chart-reveal',
          state: 'open', draft: false, updatedAt: '2026-08-05T00:00:00Z', url: 'u' }],
  branches: [{ name: 'JYO-1-ephemeris', ahead: 2 }],
  degraded: false,
};

test('parses epic slugs from explicit markers', () => {
  const epics = parseEpics('## Onboarding\n<!-- epic: onboarding -->\n\n## Billing\n<!-- epic: billing -->\n');
  assert.deepEqual(epics, [
    { slug: 'onboarding', title: 'Onboarding', order: 1 },
    { slug: 'billing', title: 'Billing', order: 2 },
  ]);
});

test('registers a marker with no preceding heading, titled by its slug', () => {
  const epics = parseEpics('<!-- epic: standalone -->\n');
  assert.deepEqual(epics, [{ slug: 'standalone', title: 'standalone', order: 1 }]);
});

test('captures two markers under a single heading', () => {
  const epics = parseEpics('## Growth\n<!-- epic: a -->\n<!-- epic: b -->\n');
  assert.deepEqual(epics, [
    { slug: 'a', title: 'Growth', order: 1 },
    { slug: 'b', title: 'b', order: 2 },
  ]);
});

test('tolerates unusual internal whitespace in the marker', () => {
  const epics = parseEpics('## Heading\n<!--   epic:   spaced-slug   -->\n');
  assert.deepEqual(epics, [{ slug: 'spaced-slug', title: 'Heading', order: 1 }]);
});

test('order is 1-based and follows document order', () => {
  const epics = parseEpics(
    '## One\n<!-- epic: one -->\n\n<!-- epic: two -->\n\n## Three\n<!-- epic: three -->\n',
  );
  assert.deepEqual(epics.map((e) => e.order), [1, 2, 3]);
  assert.deepEqual(epics.map((e) => e.slug), ['one', 'two', 'three']);
});

test('builds a board with derived statuses', async () => {
  const board = await buildBoard({ repoRoot: REPO, gitFacts: GIT });
  const byId = Object.fromEntries(board.stories.map((s) => [s.id, s]));
  assert.equal(byId['JYO-1'].status, 'in_progress');
  assert.equal(byId['JYO-4'].status, 'in_review');
  assert.equal(byId['JYO-4'].pr.number, 42);
});

test('carries points, initial points and adjustments through', async () => {
  const board = await buildBoard({ repoRoot: REPO, gitFacts: GIT });
  const s = board.stories.find((x) => x.id === 'JYO-4');
  assert.equal(s.points, 8);
  assert.equal(s.pointsInitial, 3);
  assert.equal(s.adjustments.length, 1);
});

test('extracts acceptance criteria with checked state', async () => {
  const board = await buildBoard({ repoRoot: REPO, gitFacts: GIT });
  const s = board.stories.find((x) => x.id === 'JYO-1');
  assert.deepEqual(s.acceptance, [
    { text: 'Computes sidereal positions', checked: true },
    { text: 'Handles timezone edge cases', checked: false },
  ]);
});

test('extracts an uppercase [X] checkbox as checked', () => {
  assert.deepEqual(parseAcceptance('- [X] Shout case'), [{ text: 'Shout case', checked: true }]);
});

test('a checkbox inside a fenced code block is excluded', () => {
  const body = [
    '- [ ] before',
    '```',
    '- [ ] inside fence',
    '```',
    '- [x] after',
  ].join('\n');
  assert.deepEqual(parseAcceptance(body), [
    { text: 'before', checked: false },
    { text: 'after', checked: true },
  ]);
});

test('a tilde fence also excludes checkboxes inside it', () => {
  const body = [
    '- [ ] before',
    '~~~',
    '- [ ] inside fence',
    '~~~',
    '- [x] after',
  ].join('\n');
  assert.deepEqual(parseAcceptance(body), [
    { text: 'before', checked: false },
    { text: 'after', checked: true },
  ]);
});

test('an unterminated fence swallows the rest of the document', () => {
  const body = [
    '- [ ] before',
    '```',
    '- [ ] never closes',
    '- [x] also swallowed',
  ].join('\n');
  assert.deepEqual(parseAcceptance(body), [{ text: 'before', checked: false }]);
});

test('derives the project key from the single id prefix present', () => {
  const r = deriveProjectKey([{ id: 'JYO-1' }, { id: 'JYO-2' }]);
  assert.equal(r.key, 'JYO');
  assert.equal(r.warning, null);
});

test('derives the project key from the most frequent prefix and warns on multiple prefixes', () => {
  const r = deriveProjectKey([{ id: 'JYO-1' }, { id: 'JYO-2' }, { id: 'ABC-1' }]);
  assert.equal(r.key, 'JYO');
  assert.match(r.warning, /JYO/);
  assert.match(r.warning, /ABC/);
});

test('falls back to APP with no warning when there are no stories', () => {
  const r = deriveProjectKey([]);
  assert.equal(r.key, 'APP');
  assert.equal(r.warning, null);
});

test('wires the derived project key onto the board', async () => {
  const board = await buildBoard({ repoRoot: REPO, gitFacts: GIT });
  assert.equal(board.project.key, 'JYO');
});

test('a malformed file lands in broken[] without failing the build', async () => {
  const board = await buildBoard({ repoRoot: REPO, gitFacts: GIT });
  assert.equal(board.broken.length, 1);
  assert.match(board.broken[0].file, /JYO-9-broken\.md/);
  assert.equal(board.stories.length, 2);
});

// Spec §6 documents board.json field by field, and two of those fields were
// implemented nowhere and noticed by nothing, because every other test reaches
// for one property at a time. Pin the whole shape so the next field to go
// missing takes a test with it.
test('the board emits exactly the top-level keys spec §6 documents', async () => {
  const board = await buildBoard({ repoRoot: REPO, gitFacts: GIT });
  assert.deepEqual(Object.keys(board).sort(), [
    'broken', 'epics', 'generatedAt', 'project', 'stories', 'warnings',
  ]);
  // `project.repo` is spec'd but deliberately absent — it needs a git-remote
  // lookup, deferred to Phase 2. See the plan's "Deferred to Phase 2".
  assert.deepEqual(Object.keys(board.project).sort(), ['key', 'name']);
});

test('a story emits exactly the keys spec §6 documents', async () => {
  const board = await buildBoard({ repoRoot: REPO, gitFacts: GIT });
  assert.deepEqual(Object.keys(board.stories[0]).sort(), [
    'acceptance', 'adjustments', 'body', 'branch', 'dependsOn', 'epic', 'file',
    'id', 'labels', 'owner', 'pilot', 'pilotSource', 'points', 'pointsInitial',
    'pr', 'prompt', 'promptBody', 'status', 'statusSource', 'title',
  ]);
});

test('promptBody carries the contents of the prompt file', async () => {
  const board = await buildBoard({ repoRoot: REPO, gitFacts: GIT });
  const s = board.stories.find((x) => x.id === 'JYO-4');
  assert.equal(s.prompt, 'prompts/chart-reveal.md');
  assert.match(s.promptBody, /Render the D1 wheel/);
});

test('a missing prompt file is a warning naming the story and path, not a failure', async () => {
  const board = await buildBoard({ repoRoot: REPO, gitFacts: GIT });
  const s = board.stories.find((x) => x.id === 'JYO-1');
  assert.equal(s.prompt, 'prompts/does-not-exist.md');
  assert.equal(s.promptBody, null);
  assert.ok(
    board.warnings.some((w) => /JYO-1/.test(w) && /prompts\/does-not-exist\.md/.test(w)),
    `expected a warning naming JYO-1 and its path, got: ${JSON.stringify(board.warnings)}`,
  );
});

test('a story with no prompt gets a null promptBody and no warning', async () => {
  const board = await buildBoard({ repoRoot: QUARANTINE_REPO, gitFacts: GIT });
  assert.equal(board.stories[0].prompt, null);
  assert.equal(board.stories[0].promptBody, null);
  assert.ok(!board.warnings.some((w) => /prompt/.test(w)));
});

// The whole point of narrowing the fatal set: one developer omitting
// points_initial costs that story its card and nothing else. Before this, the
// build threw and the entire team saw yesterday's board or none at all.
test('a story missing points_initial is quarantined, leaving a working board', async () => {
  const board = await buildBoard({ repoRoot: QUARANTINE_REPO, gitFacts: GIT });

  assert.deepEqual(board.stories.map((s) => s.id), ['JYO-1', 'JYO-2']);
  assert.equal(board.broken.length, 1);
  assert.match(board.broken[0].file, /JYO-3-no-initial\.md/);
  assert.match(board.broken[0].error, /missing required field "points_initial"/);
});

test('a quarantined story never reaches deriveStatus', async () => {
  const board = await buildBoard({
    repoRoot: QUARANTINE_REPO,
    gitFacts: { ...GIT, branches: [{ name: 'JYO-3-dasha', ahead: 4 }] },
  });
  assert.equal(board.stories.find((s) => s.id === 'JYO-3'), undefined);
});

// ci/run-check.mjs already answers this condition with a sentence. The build
// answering it with a raw ENOENT stack is the same question, worse.
test('a missing tdd/ directory gives a clear error, not a raw ENOENT stack', async () => {
  await assert.rejects(
    () => buildBoard({ repoRoot: join(FIXTURES, 'no-such-repo-xyz'), gitFacts: GIT }),
    (err) => {
      assert.match(err.message, /tdd\/ not found/);
      assert.doesNotMatch(err.message, /ENOENT/);
      return true;
    },
  );
});

test('surfaces the degraded-gh warning on the board', async () => {
  const board = await buildBoard({
    repoRoot: REPO,
    gitFacts: { ...GIT, degraded: true, warning: 'PR status unavailable — run `gh auth login`.' },
  });
  assert.ok(board.warnings.some((w) => /gh auth login/.test(w)));
});

// --- prompt paths must not escape the repo -------------------------------
// board.json is the deployed artifact. Before this, `prompt: ../../../x` was
// read and its contents embedded verbatim — anything reachable from the
// build machine could be published by editing one line of frontmatter.
const ESCAPE_REPO = join(FIXTURES, 'escape-repo');
const DUP_EPIC_REPO = join(FIXTURES, 'dup-epic-repo');

test('a prompt path that climbs out of the repo is refused, not read', async () => {
  const board = await buildBoard({ repoRoot: ESCAPE_REPO, gitFacts: GIT });
  const s = board.stories.find((x) => x.id === 'JYO-1');
  assert.equal(s.promptBody, null, 'contents outside the repo must never reach board.json');
  assert.ok(
    board.warnings.some((w) => /JYO-1/.test(w) && /outside the repo/.test(w)),
    `expected an escape warning naming JYO-1, got: ${JSON.stringify(board.warnings)}`,
  );
});

// join() already neutralises a leading slash by treating it as relative, so
// this never escaped. Pin it so a future switch to resolve() — which does NOT
// neutralise it — cannot quietly reopen the hole.
test('an absolute prompt path is resolved under the repo, not from the filesystem root', async () => {
  const board = await buildBoard({ repoRoot: ESCAPE_REPO, gitFacts: GIT });
  const s = board.stories.find((x) => x.id === 'JYO-2');
  assert.equal(s.promptBody, null);
  assert.ok(board.warnings.some((w) => /JYO-2/.test(w)));
});

test('a well-behaved prompt inside the repo is unaffected by the check', async () => {
  const board = await buildBoard({ repoRoot: ESCAPE_REPO, gitFacts: GIT });
  const s = board.stories.find((x) => x.id === 'JYO-3');
  assert.match(s.promptBody, /lives inside the repo/);
  assert.ok(!board.warnings.some((w) => /JYO-3/.test(w)));
});

test('an escaping prompt costs the story its prompt, not its card', async () => {
  const board = await buildBoard({ repoRoot: ESCAPE_REPO, gitFacts: GIT });
  assert.equal(board.stories.length, 3);
  assert.deepEqual(board.broken, []);
});

// --- duplicate epic slugs ------------------------------------------------
// Two markers with the same slug used to produce two epics silently, which
// renders as two identical lanes on the board with the stories split between
// them by nothing the reader can see.
test('a repeated epic slug keeps the first and warns, rather than emitting two lanes', () => {
  const epics = parseEpics('## Core\n<!-- epic: core -->\n\n## Core Again\n<!-- epic: core -->\n');
  assert.deepEqual(epics.map((e) => e.slug), ['core']);
  assert.equal(epics[0].title, 'Core');
});

test('duplicate epic slugs are reported so the BRD can be fixed', () => {
  const { epics, duplicates } = parseEpicsWithDuplicates(
    '<!-- epic: a -->\n<!-- epic: b -->\n<!-- epic: a -->\n',
  );
  assert.deepEqual(epics.map((e) => e.slug), ['a', 'b']);
  assert.deepEqual(duplicates, ['a']);
});

test('order stays contiguous after a duplicate is dropped', () => {
  const epics = parseEpics('<!-- epic: a -->\n<!-- epic: a -->\n<!-- epic: b -->\n');
  assert.deepEqual(epics.map((e) => [e.slug, e.order]), [['a', 1], ['b', 2]]);
});

test('a duplicate epic slug in BRD.md surfaces as a board warning', async () => {
  const board = await buildBoard({ repoRoot: DUP_EPIC_REPO, gitFacts: GIT });
  assert.deepEqual(board.epics.map((e) => e.slug), ['core']);
  assert.ok(
    board.warnings.some((w) => /epic "core" more than once/.test(w)),
    `expected a duplicate-epic warning, got: ${JSON.stringify(board.warnings)}`,
  );
  assert.equal(board.stories.length, 1, 'the story still lands on the surviving lane');
});

const cycleText = (over = {}) => JSON.stringify({
  status: 'fixing', current_phase: 'verify',
  fix_rounds: 2, max_fix_rounds: 3, updated: '2026-07-29T09:12:04Z',
  ...over,
});

// JYO-4 is in progress on branch JYO-4-chart-reveal in the fixture repo.
const inProgress = (cycles = new Map()) => ({
  prs: [], degraded: false, cycles,
  branches: [{ name: 'JYO-4-chart-reveal', ahead: 3 }],
});

const story = (board, id) => board.stories.find((s) => s.id === id);

test('a story with a cycle on its branch publishes the projected view and its source', async () => {
  const cycles = new Map([['JYO-4-chart-reveal',
    { text: cycleText(), source: 'remote:origin/JYO-4-chart-reveal' }]]);
  const board = await buildBoard({ repoRoot: REPO, gitFacts: inProgress(cycles) });

  const s = story(board, 'JYO-4');
  assert.equal(s.status, 'in_progress');
  assert.equal(s.pilotSource, 'remote:origin/JYO-4-chart-reveal');
  assert.deepEqual(s.pilot, {
    phase: 'verify', status: 'fixing', fixRounds: 2, maxFixRounds: 3,
    awaiting: null, halted: false, haltReason: null,
    updated: '2026-07-29T09:12:04Z',
  });
});

test('a story with no cycle publishes explicit nulls, not missing keys', async () => {
  const board = await buildBoard({ repoRoot: REPO, gitFacts: inProgress() });
  const s = story(board, 'JYO-4');
  assert.equal(s.pilot, null);
  assert.equal(s.pilotSource, null);
  assert.ok('pilot' in s && 'pilotSource' in s);
});

test('a cycle is looked up under the bare branch name even when the branch is a remote ref', async () => {
  const cycles = new Map([['JYO-4-chart-reveal',
    { text: cycleText(), source: 'remote:origin/JYO-4-chart-reveal' }]]);
  const board = await buildBoard({
    repoRoot: REPO,
    gitFacts: { prs: [], degraded: false, cycles,
      branches: [{ name: 'origin/JYO-4-chart-reveal', ahead: 3 }] },
  });
  assert.equal(story(board, 'JYO-4').pilot.phase, 'verify');
});

test('a merged story drops its cycle: shipped work outranks an agent self-report', async () => {
  const cycles = new Map([['JYO-4-chart-reveal',
    { text: cycleText(), source: 'local' }]]);
  const board = await buildBoard({
    repoRoot: REPO,
    gitFacts: {
      branches: [], degraded: false, cycles,
      prs: [{ number: 42, title: 'JYO-4 chart', headBranch: 'JYO-4-chart-reveal',
        state: 'merged', draft: false, updatedAt: '2026-08-05T00:00:00Z', url: 'https://x/42' }],
    },
  });
  const s = story(board, 'JYO-4');
  assert.equal(s.status, 'done');
  assert.equal(s.pilot, null);
  assert.equal(s.pilotSource, null);
  // Silent by design — the cycle is history, not a problem to report.
  assert.ok(!board.warnings.some((w) => w.includes('JYO-4') && w.includes('pilot')));
});

test('pilot state never changes the derived status', async () => {
  // A cycle claiming `done` on a story with only a branch must not promote it.
  const cycles = new Map([['JYO-4-chart-reveal',
    { text: cycleText({ status: 'done', current_phase: 'capture' }), source: 'local' }]]);
  const board = await buildBoard({ repoRoot: REPO, gitFacts: inProgress(cycles) });
  const s = story(board, 'JYO-4');
  assert.equal(s.status, 'in_progress');
  assert.equal(s.pilot.status, 'done');
});

test('a malformed cycle warns and leaves the story otherwise intact', async () => {
  const cycles = new Map([['JYO-4-chart-reveal', { text: '{"status": ', source: 'local' }]]);
  const board = await buildBoard({ repoRoot: REPO, gitFacts: inProgress(cycles) });
  const s = story(board, 'JYO-4');
  assert.equal(s.pilot, null);
  assert.equal(s.pilotSource, null);
  assert.equal(s.status, 'in_progress');
  assert.equal(s.title, 'Chart reveal');
  assert.ok(board.warnings.some((w) => /JYO-4.*pilot cycle unreadable/.test(w)));
});

test('a cycle with an unknown status warns and is not published', async () => {
  const cycles = new Map([['JYO-4-chart-reveal',
    { text: cycleText({ status: 'vibing' }), source: 'local' }]]);
  const board = await buildBoard({ repoRoot: REPO, gitFacts: inProgress(cycles) });
  assert.equal(story(board, 'JYO-4').pilot, null);
  assert.ok(board.warnings.some((w) => /JYO-4.*unknown cycle status/.test(w)));
});

test('bad pilot data never fails the build', async () => {
  const cycles = new Map([['JYO-4-chart-reveal', { text: 'not json at all', source: 'local' }]]);
  const board = await buildBoard({ repoRoot: REPO, gitFacts: inProgress(cycles) });
  assert.ok(board.stories.length > 0);
  assert.ok(Array.isArray(board.warnings));
});

test('a gitFacts without cycles at all still builds', async () => {
  // Pilot is optional, and an older caller may not supply the key.
  const board = await buildBoard({
    repoRoot: REPO,
    gitFacts: { prs: [], branches: [{ name: 'JYO-4-chart-reveal', ahead: 3 }], degraded: false },
  });
  assert.equal(story(board, 'JYO-4').pilot, null);
});

test('a story with no branch and no PR never looks a cycle up', async () => {
  const cycles = new Map([['JYO-4-chart-reveal', { text: cycleText(), source: 'local' }]]);
  const board = await buildBoard({
    repoRoot: REPO,
    gitFacts: { prs: [], branches: [], degraded: false, cycles },
  });
  const s = story(board, 'JYO-4');
  assert.equal(s.status, 'todo');
  assert.equal(s.pilot, null);
});

// Spec §5 says the malformed-cycle warning names *the file*. Naming only the
// story tells a reader something is broken but not where to go and fix it, and
// for a `local` source there is no other way to find the file.
test('the unreadable-cycle warning names the file it came from', async () => {
  const cycles = new Map([['JYO-4-chart-reveal',
    { text: '{"status": ', source: 'local', path: '.pilot/cycles/JYO-4-chart-reveal.json' }]]);
  const board = await buildBoard({ repoRoot: REPO, gitFacts: inProgress(cycles) });
  const warning = board.warnings.find((w) => w.includes('unreadable'));
  assert.ok(warning, 'expected an unreadable-cycle warning');
  assert.ok(warning.includes('.pilot/cycles/JYO-4-chart-reveal.json'),
    `warning does not name the file: ${warning}`);
  assert.ok(warning.includes('JYO-4'), 'warning should still name the story');
});

test('the ignored-cycle warning names the file it came from', async () => {
  const cycles = new Map([['JYO-4-chart-reveal',
    { text: cycleText({ status: 'vibing' }), source: 'remote:origin/JYO-4-chart-reveal',
      path: 'origin/JYO-4-chart-reveal:.pilot/cycles/JYO-4-chart-reveal.json' }]]);
  const board = await buildBoard({ repoRoot: REPO, gitFacts: inProgress(cycles) });
  const warning = board.warnings.find((w) => w.includes('ignored'));
  assert.ok(warning, 'expected an ignored-cycle warning');
  assert.ok(warning.includes('origin/JYO-4-chart-reveal:.pilot/cycles/JYO-4-chart-reveal.json'),
    `warning does not name the file: ${warning}`);
});

// A story with no local or remote ref still resolves its branch from the PR's
// head branch. Before readCycles considered PR head branches, this story's cycle
// was never even looked for.
test('a story resolved only from a PR head branch still publishes its cycle', async () => {
  const cycles = new Map([['JYO-4-chart-reveal',
    { text: cycleText(), source: 'remote:origin/JYO-4-chart-reveal',
      path: 'origin/JYO-4-chart-reveal:.pilot/cycles/JYO-4-chart-reveal.json' }]]);
  const board = await buildBoard({
    repoRoot: REPO,
    gitFacts: {
      branches: [], degraded: false, cycles,
      prs: [{ number: 42, title: 'JYO-4 chart', headBranch: 'JYO-4-chart-reveal',
        state: 'open', draft: false, updatedAt: '2026-08-05T00:00:00Z', url: 'u' }],
    },
  });
  const s = story(board, 'JYO-4');
  assert.equal(s.status, 'in_review');
  assert.equal(s.pilot.phase, 'verify');
  assert.equal(s.pilotSource, 'remote:origin/JYO-4-chart-reveal');
});

// §5 row 1: no .pilot/ anywhere means no warning at all, not just no data.
test('a story with no cycle produces no pilot warning', async () => {
  const board = await buildBoard({ repoRoot: REPO, gitFacts: inProgress() });
  assert.equal(board.warnings.filter((w) => w.includes('pilot')).length, 0);
});

// Tracing is diagnostics, so the one thing it must never do is change the
// artifact. If a trace call ever mutates what it reports, this catches it.
test('tracing does not change the board it reports on', async () => {
  const cycles = new Map([['JYO-4-chart-reveal',
    { text: cycleText(), source: 'local', path: '.pilot/cycles/JYO-4-chart-reveal.json' }]]);
  const quiet = await buildBoard({ repoRoot: REPO, gitFacts: inProgress(cycles) });
  const lines = [];
  const loud = await buildBoard({
    repoRoot: REPO, gitFacts: inProgress(cycles),
    trace: createTrace({ enabled: true, sink: (l) => lines.push(l) }),
  });
  quiet.generatedAt = loud.generatedAt = 'pinned';
  assert.deepEqual(loud, quiet);
  assert.ok(lines.length > 0, 'expected the loud build to have traced something');
});

test('the trace narrates the pipeline in execution order', async () => {
  const lines = [];
  await buildBoard({
    repoRoot: REPO, gitFacts: inProgress(),
    trace: createTrace({ enabled: true, sink: (l) => lines.push(l) }),
  });
  const events = lines.map((l) => l.replace(/^\[board \d+\] /, '').split(' ')[0]);
  for (const expected of ['build.begin', 'brd.parsed', 'tdd.scanned', 'validate.done',
    'story.status', 'story.pilot', 'build.end']) {
    assert.ok(events.includes(expected), `missing trace event ${expected}: ${events.join(',')}`);
  }
  assert.equal(events[0], 'build.begin');
  assert.equal(events[events.length - 1], 'build.end');
});

test('a story that never reaches the board still traces why', async () => {
  const lines = [];
  await buildBoard({
    repoRoot: QUARANTINE_REPO, gitFacts: { prs: [], branches: [], degraded: false },
    trace: createTrace({ enabled: true, sink: (l) => lines.push(l) }),
  });
  assert.ok(lines.some((l) => l.includes('story.quarantined')),
    `no quarantine trace in: ${lines.join('\n')}`);
});

test('build stays silent by default', async () => {
  const lines = [];
  const original = console.error;
  console.error = (l) => lines.push(l);
  try {
    await buildBoard({ repoRoot: REPO, gitFacts: inProgress() });
  } finally {
    console.error = original;
  }
  assert.deepEqual(lines, []);
});

test('parseArgv strips trace flags so they are not read as the repo root', () => {
  assert.equal(parseArgv(['--verbose']).repoRoot, null);
  assert.equal(parseArgv(['-v']).repoRoot, null);
  assert.equal(parseArgv(['/some/repo', '--verbose']).repoRoot, '/some/repo');
  assert.equal(parseArgv(['--verbose', '/some/repo']).repoRoot, '/some/repo');
  assert.equal(parseArgv([]).repoRoot, null);
});

// `basename('.')` is '.', so building with a relative repo root — which is what
// `npm run build -- .` and the CI working-directory idiom both produce — named
// the project ".". Every other test passes an absolute fixture path, which is
// exactly why 209 of them missed it; it took an end-to-end run to surface.
test('the project name survives a relative repo root', async () => {
  const cwd = process.cwd();
  process.chdir(REPO);
  try {
    const board = await buildBoard({ repoRoot: '.', gitFacts: inProgress() });
    assert.equal(board.project.name, 'repo');
  } finally {
    process.chdir(cwd);
  }
});

test('the project name survives a trailing slash', async () => {
  const board = await buildBoard({ repoRoot: `${REPO}/`, gitFacts: inProgress() });
  assert.equal(board.project.name, 'repo');
});
