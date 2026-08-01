// Opt-in build tracing. Silent unless asked for, so a normal build still prints
// exactly one summary line and `board.json`'s warnings stay the signal rather
// than something to scroll past.
//
// Tracing lives at the pipeline's boundaries — `scripts/build-board.mjs`
// (orchestration) and `lib/github.mjs` (the only module that shells out). It is
// deliberately absent from the pure modules: `lib/pilot.mjs` is pure by
// contract, `lib/status.mjs` may not be modified at all, and threading a logger
// through `parseTdd`/`validateStories`/`deriveStatus` would put an I/O concern
// in a signature whose whole value is that it takes data and returns data. Their
// behaviour is fully visible in the boundary traces that record what went in and
// what came out.

// One shared no-op rather than a fresh closure per build, so a disabled trace is
// a single monomorphic call the engine can inline away.
export const NOOP = () => {};

const OFF = new Set(['0', 'false', 'no', 'off', '']);

// Pure predicate over argv and env, so the decision is testable without a
// process. An explicit `BOARD_DEBUG=0` must switch tracing OFF — treating any
// non-empty string as truthy is the classic way that stops being true.
export function traceEnabled(argv = [], env = {}) {
  if (argv.includes('--verbose') || argv.includes('-v')) return true;
  const flag = env.BOARD_DEBUG;
  if (flag === undefined || flag === null) return false;
  return !OFF.has(String(flag).trim().toLowerCase());
}

// Values are rendered flat as key=value because a trace line is read in a
// terminal, usually next to `grep`. JSON.stringify of the whole detail object
// would be correct and unreadable. Only values containing whitespace are
// quoted — quoting everything would bury paths and branch names in noise.
function render(value) {
  const s = value === undefined ? 'undefined' : value === null ? 'null' : String(value);
  return /\s/.test(s) ? JSON.stringify(s) : s;
}

function format(detail) {
  return Object.entries(detail)
    .map(([k, v]) => `${k}=${render(v)}`)
    .join(' ');
}

// `sink` defaults to stderr: `build-board.mjs` prints its summary to stdout and
// a caller may parse it, so a trace must never land in the same stream.
export function createTrace({ enabled = false, sink = (line) => console.error(line) } = {}) {
  if (!enabled) return NOOP;

  let seq = 0;
  return (event, detail) => {
    seq += 1;
    const n = String(seq).padStart(3, '0');
    const tail = detail === undefined ? '' : ` ${format(detail)}`;
    sink(`[board ${n}] ${event}${tail}`);
  };
}
