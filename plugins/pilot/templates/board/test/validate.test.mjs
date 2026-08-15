import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateStories } from '../lib/validate.mjs';

const story = (o) => ({
  id: 'JYO-1', title: 'T', epic: 'onboarding',
  points: 3, points_initial: 3, file: 'tdd/JYO-1.md', ...o,
});
const EPICS = ['onboarding', 'billing'];

test('a well-formed set produces nothing', () => {
  const r = validateStories([story()], EPICS);
  assert.deepEqual(r.errors, []);
  assert.deepEqual(r.warnings, []);
  assert.deepEqual(r.invalid, []);
});

test('duplicate ids are a fatal error naming both files', () => {
  const r = validateStories(
    [story({ file: 'tdd/a.md' }), story({ file: 'tdd/b.md' })],
    EPICS,
  );
  assert.equal(r.errors.length, 1);
  assert.match(r.errors[0], /tdd\/a\.md/);
  assert.match(r.errors[0], /tdd\/b\.md/);
});

// These three used to be fatal. Spec §11 requires every failure mode to leave
// a working board, and only duplicate ids and cycles are genuinely ambiguous,
// so a schema defect in one story now quarantines that story alone. The
// message wording is unchanged — the precision was the point; only the blast
// radius moved.
test('a missing required field quarantines the story instead of failing the build', () => {
  const r = validateStories([story({ title: undefined })], EPICS);
  assert.deepEqual(r.errors, []);
  assert.equal(r.invalid.length, 1);
  assert.deepEqual(r.invalid[0], {
    file: 'tdd/JYO-1.md',
    id: 'JYO-1',
    reason: 'tdd/JYO-1.md: missing required field "title"',
  });
});

test('a non-Fibonacci points value quarantines the story instead of failing the build', () => {
  const r = validateStories([story({ points: 4 })], EPICS);
  assert.deepEqual(r.errors, []);
  assert.equal(r.invalid.length, 1);
  assert.match(r.invalid[0].reason, /points is 4, must be one of 1, 2, 3, 5, 8/);
});

test('a story with no id at all is quarantined with a null id', () => {
  const r = validateStories([story({ id: undefined })], EPICS);
  assert.deepEqual(r.errors, []);
  assert.equal(r.invalid[0].id, null);
  assert.match(r.invalid[0].reason, /missing required field "id"/);
});

test('a quarantined story emits no epic or dependency warnings about itself', () => {
  const r = validateStories([story({ id: undefined, epic: 'nope', depends_on: ['JYO-99'] })], EPICS);
  assert.deepEqual(r.warnings, []);
});

test('one story quarantined leaves the others validated normally', () => {
  const r = validateStories(
    [
      story({ id: 'JYO-1', file: 'a.md' }),
      story({ id: 'JYO-2', file: 'b.md', points_initial: undefined }),
      story({ id: 'JYO-3', file: 'c.md', epic: 'nope' }),
    ],
    EPICS,
  );
  assert.deepEqual(r.errors, []);
  assert.deepEqual(r.invalid.map((i) => i.file), ['b.md']);
  assert.equal(r.warnings.length, 1);
  assert.match(r.warnings[0], /JYO-3/);
});

test('a story with several defects reports each one', () => {
  const r = validateStories([story({ points: 4, points_initial: 7 })], EPICS);
  assert.equal(r.invalid.length, 2);
  assert.match(r.invalid[0].reason, /points is 4/);
  assert.match(r.invalid[1].reason, /points_initial is 7/);
});

test('an unknown epic is a warning, not an error', () => {
  const r = validateStories([story({ epic: 'nope' })], EPICS);
  assert.deepEqual(r.errors, []);
  assert.match(r.warnings[0], /nope/);
});

test('an unresolvable dependency is a warning', () => {
  const r = validateStories([story({ depends_on: ['JYO-99'] })], EPICS);
  assert.deepEqual(r.errors, []);
  assert.match(r.warnings[0], /JYO-99/);
});

test('a dependency cycle is fatal and names the cycle', () => {
  const r = validateStories(
    [
      story({ id: 'JYO-1', depends_on: ['JYO-2'], file: 'a.md' }),
      story({ id: 'JYO-2', depends_on: ['JYO-1'], file: 'b.md' }),
    ],
    EPICS,
  );
  assert.equal(r.errors.length, 1);
  assert.match(r.errors[0], /cycle/i);
  assert.match(r.errors[0], /JYO-1/);
});

test('a self-dependency is a cycle', () => {
  const r = validateStories([story({ id: 'JYO-1', depends_on: ['JYO-1'] })], EPICS);
  assert.match(r.errors[0], /cycle/i);
});

test('depends_on as a scalar string quarantines the story, not bogus character warnings', () => {
  const r = validateStories([story({ depends_on: 'JYO-2' })], EPICS);
  assert.deepEqual(r.errors, []);
  assert.equal(r.invalid.length, 1);
  assert.match(r.invalid[0].reason, /depends_on/);
  assert.match(r.invalid[0].reason, /tdd\/JYO-1\.md/);
  assert.deepEqual(r.warnings, []);
});

test('depends_on: null means no dependencies and produces nothing', () => {
  const r = validateStories([story({ depends_on: null })], EPICS);
  assert.deepEqual(r.errors, []);
  assert.deepEqual(r.warnings, []);
  assert.deepEqual(r.invalid, []);
});

test('depends_on as a valid array still works', () => {
  const r = validateStories(
    [
      story({ id: 'JYO-1', depends_on: ['JYO-2'], file: 'a.md' }),
      story({ id: 'JYO-2', file: 'b.md' }),
    ],
    EPICS,
  );
  assert.deepEqual(r.errors, []);
  assert.deepEqual(r.warnings, []);
  assert.deepEqual(r.invalid, []);
});

test('a cycle is still fatal even when one member is also quarantined', () => {
  const r = validateStories(
    [
      story({ id: 'JYO-1', depends_on: ['JYO-2'], file: 'a.md' }),
      story({ id: 'JYO-2', depends_on: ['JYO-1'], file: 'b.md', points: 4 }),
    ],
    EPICS,
  );
  assert.equal(r.errors.length, 1);
  assert.match(r.errors[0], /cycle/i);
  assert.equal(r.invalid.length, 1);
});

test('a non-root cycle is reported without the uninvolved root', () => {
  const r = validateStories(
    [
      story({ id: 'JYO-1', depends_on: ['JYO-2'], file: 'a.md' }),
      story({ id: 'JYO-2', depends_on: ['JYO-3'], file: 'b.md' }),
      story({ id: 'JYO-3', depends_on: ['JYO-2'], file: 'c.md' }),
    ],
    EPICS,
  );
  assert.equal(r.errors.length, 1);
  assert.match(r.errors[0], /cycle/i);
  assert.match(r.errors[0], /JYO-2/);
  assert.match(r.errors[0], /JYO-3/);
  assert.doesNotMatch(r.errors[0], /JYO-1/);
});

test('a diamond dependency shape is not a false-positive cycle', () => {
  const r = validateStories(
    [
      story({ id: 'A', depends_on: ['B', 'C'], file: 'a.md' }),
      story({ id: 'B', depends_on: ['D'], file: 'b.md' }),
      story({ id: 'C', depends_on: ['D'], file: 'c.md' }),
      story({ id: 'D', file: 'd.md' }),
    ],
    EPICS,
  );
  assert.deepEqual(r.errors, []);
});

test('an omitted epicSlugs argument defaults cleanly instead of throwing', () => {
  const r = validateStories([story()], undefined);
  assert.deepEqual(r.errors, []);
  assert.match(r.warnings[0], /onboarding/);
});

// --- type discipline on frontmatter values -------------------------------
// YAML is not a string format. `id: 2024`, `id: yes` and `points: 3.0` all
// arrive as non-strings, and a numeric id used to reach deriveProjectKey and
// crash the whole build on `.split()` — one story blanking the board for
// everyone, the exact failure spec §11 forbids.

test('a numeric id is quarantined rather than crashing the build', () => {
  const r = validateStories([story({ id: 2024 })], EPICS);
  assert.deepEqual(r.errors, []);
  assert.equal(r.invalid.length, 1);
  assert.match(r.invalid[0].reason, /"id" must be text/);
  assert.match(r.invalid[0].reason, /quote it/i);
});

test('a boolean id — YAML `id: yes` — is quarantined too', () => {
  const r = validateStories([story({ id: true })], EPICS);
  assert.equal(r.invalid.length, 1);
  assert.match(r.invalid[0].reason, /"id" must be text/);
});

test('a non-string title is quarantined', () => {
  const r = validateStories([story({ title: 7 })], EPICS);
  assert.equal(r.invalid.length, 1);
  assert.match(r.invalid[0].reason, /"title" must be text/);
});

test('a non-string epic is quarantined', () => {
  const r = validateStories([story({ epic: 12 })], EPICS);
  assert.equal(r.invalid.length, 1);
  assert.match(r.invalid[0].reason, /"epic" must be text/);
});

test('a scalar labels value is quarantined, not passed through to the UI', () => {
  const r = validateStories([story({ labels: 'urgent' })], EPICS);
  assert.equal(r.invalid.length, 1);
  assert.match(r.invalid[0].reason, /labels must be a list/);
});

test('a scalar adjustments value is quarantined', () => {
  const r = validateStories([story({ adjustments: 'grew' })], EPICS);
  assert.equal(r.invalid.length, 1);
  assert.match(r.invalid[0].reason, /adjustments must be a list/);
});

test('omitted labels and adjustments are fine — they are optional', () => {
  const r = validateStories([story({ labels: undefined, adjustments: undefined })], EPICS);
  assert.deepEqual(r.invalid, []);
});

test('empty-array labels and adjustments are fine', () => {
  const r = validateStories([story({ labels: [], adjustments: [] })], EPICS);
  assert.deepEqual(r.invalid, []);
});

// deriveStatus honours exactly one override value. Anything else used to do
// nothing at all and say nothing — the developer believes they flagged the
// story and the board quietly disagrees.
test('an unrecognised status_override warns instead of silently doing nothing', () => {
  const r = validateStories([story({ status_override: 'done' })], EPICS);
  assert.deepEqual(r.errors, []);
  assert.deepEqual(r.invalid, []);
  assert.equal(r.warnings.length, 1);
  assert.match(r.warnings[0], /status_override "done"/);
  assert.match(r.warnings[0], /blocked/);
});

test('status_override: blocked is accepted without a warning', () => {
  const r = validateStories([story({ status_override: 'blocked' })], EPICS);
  assert.deepEqual(r.warnings, []);
});

test('a quarantined story reports every type defect it has at once', () => {
  const r = validateStories([story({ id: 5, title: 6 })], EPICS);
  assert.equal(r.invalid.length, 2);
  assert.equal(r.invalid.every((i) => i.file === 'tdd/JYO-1.md'), true);
});
