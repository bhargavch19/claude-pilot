import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createTrace, traceEnabled, NOOP } from '../lib/trace.mjs';

test('tracing is off unless asked for', () => {
  const lines = [];
  const trace = createTrace({ enabled: false, sink: (l) => lines.push(l) });
  trace('anything', { a: 1 });
  assert.deepEqual(lines, []);
});

test('a disabled trace is the shared no-op, not a fresh closure per build', () => {
  assert.equal(createTrace({ enabled: false }), NOOP);
  assert.equal(createTrace(), NOOP);
});

test('an enabled trace emits one line per event, in order, numbered', () => {
  const lines = [];
  const trace = createTrace({ enabled: true, sink: (l) => lines.push(l) });
  trace('brd.read');
  trace('tdd.parsed');
  assert.equal(lines.length, 2);
  assert.match(lines[0], /^\[board 001\] brd\.read$/);
  assert.match(lines[1], /^\[board 002\] tdd\.parsed$/);
});

test('detail is rendered as flat key=value, not as JSON soup', () => {
  const lines = [];
  const trace = createTrace({ enabled: true, sink: (l) => lines.push(l) });
  trace('cycle.hit', { branch: 'JYO-4-chart', tier: 'remote' });
  assert.equal(lines[0], '[board 001] cycle.hit branch=JYO-4-chart tier=remote');
});

test('a value containing a space is quoted so the line stays parseable', () => {
  const lines = [];
  const trace = createTrace({ enabled: true, sink: (l) => lines.push(l) });
  trace('story.warn', { why: 'two pull requests match' });
  assert.equal(lines[0], '[board 001] story.warn why="two pull requests match"');
});

test('null and undefined detail values are rendered, not silently dropped', () => {
  const lines = [];
  const trace = createTrace({ enabled: true, sink: (l) => lines.push(l) });
  trace('pilot.none', { source: null, pilot: undefined });
  assert.equal(lines[0], '[board 001] pilot.none source=null pilot=undefined');
});

test('the default sink is stderr, so a trace never contaminates stdout', () => {
  // build-board prints its summary to stdout and a caller may parse it.
  const original = console.error;
  const seen = [];
  console.error = (l) => seen.push(l);
  try {
    createTrace({ enabled: true })('probe');
  } finally {
    console.error = original;
  }
  assert.equal(seen.length, 1);
  assert.match(seen[0], /probe/);
});

test('traceEnabled reads --verbose and -v from argv', () => {
  assert.equal(traceEnabled(['node', 'build', '--verbose'], {}), true);
  assert.equal(traceEnabled(['node', 'build', '-v'], {}), true);
  assert.equal(traceEnabled(['node', 'build'], {}), false);
});

test('traceEnabled reads BOARD_DEBUG from the environment', () => {
  assert.equal(traceEnabled([], { BOARD_DEBUG: '1' }), true);
  assert.equal(traceEnabled([], { BOARD_DEBUG: 'true' }), true);
  // An explicit off switch must actually switch it off. `BOARD_DEBUG=0` reading
  // as "on" because the string is truthy is the classic version of this bug.
  assert.equal(traceEnabled([], { BOARD_DEBUG: '0' }), false);
  assert.equal(traceEnabled([], { BOARD_DEBUG: 'false' }), false);
  assert.equal(traceEnabled([], { BOARD_DEBUG: '' }), false);
  assert.equal(traceEnabled([], {}), false);
});

test('traceEnabled tolerates missing argv and env', () => {
  assert.equal(traceEnabled(), false);
});

test('a repo path in a value is not mangled', () => {
  const lines = [];
  const trace = createTrace({ enabled: true, sink: (l) => lines.push(l) });
  trace('cycle.read', { path: 'origin/JYO-4:.pilot/cycles/JYO-4.json' });
  assert.equal(lines[0], '[board 001] cycle.read path=origin/JYO-4:.pilot/cycles/JYO-4.json');
});
