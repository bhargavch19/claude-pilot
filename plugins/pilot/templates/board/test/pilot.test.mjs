import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseCycle, projectPilot, CYCLE_STATUSES, CYCLE_PHASES } from '../lib/pilot.mjs';

const CYCLE = {
  version: 1,
  id: 'cyc-20260729-ab12',
  requirement: 'chart reveal + dasha timeline',
  spine: 'superpowers',
  status: 'fixing',
  phases: [
    { id: 'frame', skill: 'x', status: 'done' },
    { id: 'verify', skill: 'y', status: 'active' },
  ],
  current_phase: 'verify',
  fix_rounds: 2,
  max_fix_rounds: 3,
  checkpoints: { plan_approved: true, plan_approved_at: '2026-07-28T10:00:00Z' },
  artifacts: { plan: 'docs/x.md' },
  halt_reason: null,
  created: '2026-07-28T09:00:00Z',
  updated: '2026-07-29T09:12:04Z',
  session_last: 'abcd1234',
};

test('projects every published field from a valid cycle', () => {
  const { pilot, error } = projectPilot(CYCLE);
  assert.equal(error, null);
  assert.deepEqual(pilot, {
    phase: 'verify',
    status: 'fixing',
    fixRounds: 2,
    maxFixRounds: 3,
    awaiting: null,
    halted: false,
    haltReason: null,
    updated: '2026-07-29T09:12:04Z',
  });
});

test('publishes exactly the documented field set and nothing else', () => {
  // Pinned so a future cycle field cannot leak into board.json — the deployed
  // artifact — without someone deciding to publish it.
  const { pilot } = projectPilot(CYCLE);
  assert.deepEqual(Object.keys(pilot).sort(), [
    'awaiting', 'fixRounds', 'haltReason', 'halted',
    'maxFixRounds', 'phase', 'status', 'updated',
  ]);
});

test('awaiting_plan_approval surfaces as awaiting: plan', () => {
  const { pilot } = projectPilot({ ...CYCLE, status: 'awaiting_plan_approval' });
  assert.equal(pilot.awaiting, 'plan');
  assert.equal(pilot.halted, false);
});

test('awaiting_ship_approval surfaces as awaiting: ship', () => {
  const { pilot } = projectPilot({ ...CYCLE, status: 'awaiting_ship_approval' });
  assert.equal(pilot.awaiting, 'ship');
});

test('halted carries its reason', () => {
  const { pilot } = projectPilot({
    ...CYCLE, status: 'halted', halt_reason: 'fix rounds exhausted',
  });
  assert.equal(pilot.halted, true);
  assert.equal(pilot.haltReason, 'fix rounds exhausted');
});

test('a non-string halt_reason is dropped rather than stringified', () => {
  const { pilot } = projectPilot({ ...CYCLE, status: 'halted', halt_reason: { why: 'x' } });
  assert.equal(pilot.haltReason, null);
});

test('an unknown status is refused, not passed through', () => {
  const { pilot, error } = projectPilot({ ...CYCLE, status: 'vibing' });
  assert.equal(pilot, null);
  assert.match(error, /unknown cycle status "vibing"/);
});

test('an unknown phase is refused so a future pilot phase cannot reach the board unreviewed', () => {
  const { pilot, error } = projectPilot({ ...CYCLE, current_phase: 'deploy' });
  assert.equal(pilot, null);
  assert.match(error, /unknown cycle phase "deploy"/);
});

// Transcribed by hand from the cycle contract in pilot's skills/pilot/autopilot.md,
// deliberately NOT imported: looping over the exported enums to feed projectPilot —
// whose only check is `CYCLE_STATUSES.includes(status)` — can never notice a value
// missing from the enum, because a missing value is also missing from the loop.
// Dropping 'capturing' left the whole file green. These literals are the second
// copy that makes a dropped value fail.
const DOCUMENTED_STATUSES = [
  'framing', 'planning', 'awaiting_plan_approval', 'executing', 'verifying',
  'fixing', 'reviewing', 'awaiting_ship_approval', 'shipping', 'capturing',
  'done', 'halted', 'aborted',
];

const DOCUMENTED_PHASES = [
  'frame', 'plan', 'build', 'verify', 'review', 'ship', 'capture',
];

test('the accepted statuses and phases are exactly the documented ones', () => {
  assert.deepEqual(CYCLE_STATUSES, DOCUMENTED_STATUSES);
  assert.deepEqual(CYCLE_PHASES, DOCUMENTED_PHASES);
});

test('every documented status and phase is accepted', () => {
  for (const status of DOCUMENTED_STATUSES) {
    const { pilot, error } = projectPilot({ ...CYCLE, status });
    assert.equal(error, null, `status ${status} rejected: ${error}`);
    assert.equal(pilot.status, status);
  }
  for (const current_phase of DOCUMENTED_PHASES) {
    const { pilot, error } = projectPilot({ ...CYCLE, current_phase });
    assert.equal(error, null, `phase ${current_phase} rejected: ${error}`);
    assert.equal(pilot.phase, current_phase);
  }
});

test('halted is derived from status, never from a stray halted key', () => {
  const { pilot } = projectPilot({ ...CYCLE, status: 'fixing', halted: true });
  assert.equal(pilot.halted, false);
});

test('non-objects are refused', () => {
  for (const bad of [null, undefined, 'fixing', 42, [CYCLE]]) {
    const { pilot, error } = projectPilot(bad);
    assert.equal(pilot, null);
    assert.match(error, /not an object/);
  }
});

test('a missing fix_rounds reads as zero, a missing max reads as null', () => {
  const { fix_rounds, max_fix_rounds, ...rest } = CYCLE;
  const { pilot } = projectPilot(rest);
  assert.equal(pilot.fixRounds, 0);
  assert.equal(pilot.maxFixRounds, null);
});

test('a negative or non-integer fix_rounds falls back rather than publishing nonsense', () => {
  assert.equal(projectPilot({ ...CYCLE, fix_rounds: -1 }).pilot.fixRounds, 0);
  assert.equal(projectPilot({ ...CYCLE, fix_rounds: 1.5 }).pilot.fixRounds, 0);
  assert.equal(projectPilot({ ...CYCLE, fix_rounds: '2' }).pilot.fixRounds, 0);
});

test('a non-string updated is dropped, so the reader is never shown a fake timestamp', () => {
  assert.equal(projectPilot({ ...CYCLE, updated: 1753780324 }).pilot.updated, null);
});

test('parseCycle reads valid JSON', () => {
  const { cycle, error } = parseCycle(JSON.stringify(CYCLE));
  assert.equal(error, null);
  assert.equal(cycle.status, 'fixing');
});

test('parseCycle reports malformed JSON instead of throwing', () => {
  const { cycle, error } = parseCycle('{"status": ');
  assert.equal(cycle, null);
  assert.match(error, /malformed JSON/);
});

test('parseCycle rejects empty and non-string input', () => {
  for (const bad of ['', '   ', null, undefined, 7]) {
    const { cycle, error } = parseCycle(bad);
    assert.equal(cycle, null);
    assert.ok(error);
  }
});
