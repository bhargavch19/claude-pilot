// Projects pilot's autopilot cycle (`.pilot/cycles/<branch-slug>.json`) into the
// narrow view board.json publishes. Pure: no fs, no child_process, no network —
// reading the cycle is lib/github.mjs's job, the one module here that shells out.
//
// Nothing in this file participates in status derivation. A cycle is one agent's
// self-report and outlives the session that wrote it; board status stays derived
// from facts other people can independently see. See spec §3.

// Closed against the cycle contract in pilot's skills/pilot/autopilot.md. Closed
// rather than pass-through on purpose: board.json is the deployed artifact, and a
// status or phase pilot adds in a later version should reach it by someone
// deciding to publish it, not by arriving unannounced through a projection.
export const CYCLE_STATUSES = [
  'framing', 'planning', 'awaiting_plan_approval', 'executing', 'verifying',
  'fixing', 'reviewing', 'awaiting_ship_approval', 'shipping', 'capturing',
  'done', 'halted', 'aborted',
];

export const CYCLE_PHASES = [
  'frame', 'plan', 'build', 'verify', 'review', 'ship', 'capture',
];

// The two statuses that mean "stopped, waiting on a human" — the single most
// useful thing the board can say about an in-flight story, because it is the
// only state a reader can act on themselves.
const AWAITING = {
  awaiting_plan_approval: 'plan',
  awaiting_ship_approval: 'ship',
};

// A count that isn't a non-negative integer is a malformed cycle, not a number
// to coerce. `Number('2')` would publish a count nobody wrote, and the whole
// point of closing the enums above is that board.json only carries values its
// author intended.
function countOr(value, fallback) {
  return Number.isInteger(value) && value >= 0 ? value : fallback;
}

const stringOrNull = (value) => (typeof value === 'string' ? value : null);

export function parseCycle(text) {
  if (typeof text !== 'string' || !text.trim()) {
    return { cycle: null, error: 'cycle file is empty' };
  }
  try {
    const cycle = JSON.parse(text);
    return { cycle, error: null };
  } catch (e) {
    return { cycle: null, error: `malformed JSON (${e.message})` };
  }
}

export function projectPilot(cycle) {
  if (cycle === null || typeof cycle !== 'object' || Array.isArray(cycle)) {
    return { pilot: null, error: 'cycle is not an object' };
  }

  const { status, current_phase: phase } = cycle;

  if (!CYCLE_STATUSES.includes(status)) {
    return { pilot: null, error: `unknown cycle status ${JSON.stringify(status)}` };
  }
  if (!CYCLE_PHASES.includes(phase)) {
    return { pilot: null, error: `unknown cycle phase ${JSON.stringify(phase)}` };
  }

  return {
    pilot: {
      phase,
      status,
      fixRounds: countOr(cycle.fix_rounds, 0),
      maxFixRounds: countOr(cycle.max_fix_rounds, null),
      awaiting: AWAITING[status] ?? null,
      // Derived from status, never read from the cycle: `halted` is not a field
      // in the contract, so trusting one would let a hand-edited cycle claim a
      // state the status enum contradicts.
      halted: status === 'halted',
      haltReason: stringOrNull(cycle.halt_reason),
      updated: stringOrNull(cycle.updated),
    },
    error: null,
  };
}
