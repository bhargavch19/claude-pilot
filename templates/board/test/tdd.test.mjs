import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseTdd, serializeTdd, TddParseError } from '../lib/tdd.mjs';

const SRC = `---
id: JYO-4
title: Chart reveal
points: 3
weird_future_key: keep me
adjustments:
  - at: '2026-08-03'
    from: 3
    to: 8
---

## Context

Some prose with --- dashes inside it.
`;

test('parses frontmatter into data and leaves body untouched', () => {
  const { data, body } = parseTdd(SRC, 'tdd/JYO-4.md');
  assert.equal(data.id, 'JYO-4');
  assert.equal(data.points, 3);
  assert.equal(data.adjustments[0].to, 8);
  assert.match(body, /^\n## Context/);
  assert.match(body, /--- dashes inside it/);
});

test('preserves unknown keys through a round trip', () => {
  const parsed = parseTdd(SRC);
  const out = serializeTdd(parsed);
  const again = parseTdd(out);
  assert.equal(again.data.weird_future_key, 'keep me');
  assert.equal(again.body, parsed.body);

  // The quoted date-like string is the value class most likely to be
  // silently coerced (e.g. into a Date) by a YAML dump/load round trip.
  assert.equal(typeof again.data.adjustments[0].at, 'string');
  assert.equal(again.data.adjustments[0].at, '2026-08-03');
  assert.equal(typeof again.data.adjustments[0].to, 'number');
  assert.equal(again.data.adjustments[0].to, 8);
});

test('normalises CRLF body line endings to LF on serialize', () => {
  const crlfSrc = SRC.replace(/\n/g, '\r\n');
  const parsed = parseTdd(crlfSrc, 'tdd/JYO-4.md');
  const out = serializeTdd(parsed);
  assert.equal(out.includes('\r'), false);
});

test('throws a located error on malformed YAML', () => {
  const bad = '---\nid: JYO-4\n  bad: [unclosed\n---\nbody\n';
  assert.throws(() => parseTdd(bad, 'tdd/JYO-9.md'), (e) => {
    assert.ok(e instanceof TddParseError);
    assert.match(e.message, /tdd\/JYO-9\.md/);
    return true;
  });
});

test('throws when frontmatter is absent', () => {
  assert.throws(() => parseTdd('# just markdown\n', 'tdd/JYO-2.md'), TddParseError);
});

// Windows editors and several Microsoft tools write a UTF-8 BOM by default.
// The BOM sits before the opening `---`, so the frontmatter regex missed it
// and the file was quarantined as "missing YAML frontmatter" — an error that
// names the wrong cause and sends the author looking at frontmatter that is
// perfectly correct.
test('a UTF-8 BOM before the frontmatter is stripped, not treated as missing', () => {
  const { data, body } = parseTdd('﻿---\nid: JYO-1\n---\nbody\n', 'tdd/JYO-1.md');
  assert.equal(data.id, 'JYO-1');
  assert.equal(body, 'body\n');
});

test('a BOM on a file that genuinely lacks frontmatter still reports that', () => {
  assert.throws(
    () => parseTdd('﻿just prose\n', 'tdd/x.md'),
    /missing YAML frontmatter/,
  );
});

test('a BOM mid-document is left alone — only a leading one is a byte-order mark', () => {
  const { body } = parseTdd('---\nid: JYO-1\n---\nbefore﻿after\n', 'tdd/JYO-1.md');
  assert.equal(body, 'before﻿after\n');
});
