import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CYCLE_STATUSES, CYCLE_PHASES } from '../lib/pilot.mjs';

// Transcribed from pilot's skills/pilot/autopilot.md, "Cycle state" section, at
// pilot v0.10.0. Pilot is a separate repo, so this cannot import the real
// contract — it pins what we transcribed so a change to lib/pilot.mjs cannot
// silently drift from it.
//
// This does NOT detect pilot changing its own contract. When you upgrade the
// pinned pilot ref, re-read that section and update both lists here — and the
// DOCUMENTED_STATUSES / DOCUMENTED_PHASES copies in pilot.test.mjs, which exist
// separately because they also drive that file's acceptance loop. The test
// exists to make that a deliberate edit to a failing test rather than a silent
// shape change — the same reason PR_LIMIT is exported in lib/github.mjs.
const PILOT_V0_10_STATUSES = [
  'framing', 'planning', 'awaiting_plan_approval', 'executing', 'verifying',
  'fixing', 'reviewing', 'awaiting_ship_approval', 'shipping', 'capturing',
  'done', 'halted', 'aborted',
];

const PILOT_V0_10_PHASES = [
  'frame', 'plan', 'build', 'verify', 'review', 'ship', 'capture',
];

test('the published status enum matches pilot v0.10.0 exactly', () => {
  assert.deepEqual([...CYCLE_STATUSES].sort(), [...PILOT_V0_10_STATUSES].sort());
});

test('the published phase enum matches pilot v0.10.0 exactly', () => {
  assert.deepEqual([...CYCLE_PHASES].sort(), [...PILOT_V0_10_PHASES].sort());
});

test('every allow-state pilot documents is a status we can publish', () => {
  // Pilot's Stop gate lets a turn end only in these states. They are the ones a
  // reader most needs to see on the board, so losing one to a typo would be
  // worse than losing any other.
  for (const s of ['awaiting_plan_approval', 'awaiting_ship_approval', 'halted', 'done', 'aborted']) {
    assert.ok(CYCLE_STATUSES.includes(s), `allow-state ${s} is not publishable`);
  }
});
