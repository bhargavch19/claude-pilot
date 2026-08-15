import { test } from 'node:test';
import assert from 'node:assert/strict';
import { slugify, branchNameFor } from '../lib/slug.mjs';
import { branchMatchesId } from '../lib/match.mjs';

test('lowercases and hyphenates', () => {
  assert.equal(slugify('Chart Reveal + Dasha Timeline'), 'chart-reveal-dasha-timeline');
});

test('strips punctuation and collapses separators', () => {
  assert.equal(slugify('Paywall (RevenueCat) — daily cron!'), 'paywall-revenuecat-daily-cron');
});

test('truncates on a word boundary at 40 chars', () => {
  const s = slugify('a'.repeat(20) + ' ' + 'b'.repeat(30));
  assert.ok(s.length <= 40);
  assert.ok(!s.endsWith('-'));
});

test('honours an explicit max', () => {
  const s = slugify('one two three four five', 10);
  assert.ok(s.length <= 10);
  assert.ok(!s.endsWith('-'));
  assert.equal(s, 'one-two');
});

// A single word with no internal hyphen has no separator to back up to
// (lastDash === -1), so the truncation path falls through to a hard cut at
// `max` instead of the word-boundary path exercised above. That branch had
// no direct assertion — pin it so a future regression there is visible.
test('a single word longer than max hard-truncates at the limit', () => {
  const s = slugify('a'.repeat(60));
  assert.equal(s.length, 40);
  assert.ok(!s.includes('-'));
  assert.ok(!s.endsWith('-'));
});

test('a whitespace-only title slugifies to empty', () => {
  assert.equal(slugify('   '), '');
});

test('a whitespace-only title falls back to the bare id, like an empty title', () => {
  assert.equal(branchNameFor('JYO-4', '   '), 'JYO-4');
});

test('builds the canonical branch name', () => {
  assert.equal(branchNameFor('JYO-4', 'Chart reveal'), 'JYO-4-chart-reveal');
});

test('an empty title still yields a usable branch', () => {
  assert.equal(branchNameFor('JYO-4', ''), 'JYO-4');
});

// The board only tracks a story once its branch satisfies branchMatchesId.
// If branchNameFor ever produced something that id-matching rejected, the
// board would silently never move the card whose branch it just told the
// developer to create — so pin the relationship directly rather than
// trusting it stays true as each function evolves independently.
test('branchNameFor always produces a name branchMatchesId accepts for that id', () => {
  assert.equal(branchMatchesId(branchNameFor('JYO-4', 'Chart reveal'), 'JYO-4'), true);
  assert.equal(branchMatchesId(branchNameFor('JYO-4', ''), 'JYO-4'), true);
  assert.equal(branchMatchesId(branchNameFor('JYO-40', 'Payment sheet'), 'JYO-40'), true);
  assert.equal(
    branchMatchesId(branchNameFor('JYO-4', 'a'.repeat(20) + ' ' + 'b'.repeat(30)), 'JYO-4'),
    true,
  );
  // The two title shapes added later, whose own behaviour is pinned above but
  // which never reached this invariant: the 60-char single word takes
  // slugify's hard-truncation branch, and the whitespace-only title takes the
  // empty-slug branch that yields a bare id.
  assert.equal(branchMatchesId(branchNameFor('JYO-4', 'a'.repeat(60)), 'JYO-4'), true);
  assert.equal(branchMatchesId(branchNameFor('JYO-4', '   '), 'JYO-4'), true);
});
