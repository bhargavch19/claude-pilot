import { test } from 'node:test';
import assert from 'node:assert/strict';
import { branchMatchesId, titleMatchesId } from '../lib/match.mjs';

test('branch matches on exact id with a hyphen boundary', () => {
  assert.equal(branchMatchesId('JYO-4-chart-reveal', 'JYO-4'), true);
  assert.equal(branchMatchesId('JYO-4', 'JYO-4'), true);
});

test('branch matches after a path prefix', () => {
  assert.equal(branchMatchesId('feat/JYO-4-chart-reveal', 'JYO-4'), true);
});

test('branch is case-insensitive', () => {
  assert.equal(branchMatchesId('jyo-4-chart-reveal', 'JYO-4'), true);
});

test('JYO-4 never matches JYO-40 — the digit boundary bug', () => {
  assert.equal(branchMatchesId('JYO-40-payment-sheet', 'JYO-4'), false);
  assert.equal(branchMatchesId('JYO-40-payment-sheet', 'JYO-40'), true);
  assert.equal(branchMatchesId('JYO-4-chart', 'JYO-40'), false);
});

// readGitFacts now reports remote-only branches as `origin/<name>`. The
// existing `(^|/)` boundary already accepts that form and still rejects the
// digit-boundary case — pin both, since the branch scan depends on it.
test('a remote-qualified branch matches, and still respects the digit boundary', () => {
  assert.equal(branchMatchesId('origin/JYO-4-chart', 'JYO-4'), true);
  assert.equal(branchMatchesId('origin/JYO-4', 'JYO-4'), true);
  assert.equal(branchMatchesId('origin/JYO-40-x', 'JYO-4'), false);
});

test('id embedded mid-word does not match', () => {
  assert.equal(branchMatchesId('refactorJYO-4-thing', 'JYO-4'), false);
});

test('PR titles match on non-alphanumeric boundaries', () => {
  assert.equal(titleMatchesId('JYO-4: chart reveal', 'JYO-4'), true);
  assert.equal(titleMatchesId('fix (JYO-4) wheel', 'JYO-4'), true);
  assert.equal(titleMatchesId('JYO-40: payments', 'JYO-4'), false);
  assert.equal(titleMatchesId('no id here', 'JYO-4'), false);
});

test('title matching discriminates in both directions', () => {
  assert.equal(titleMatchesId('JYO-4: chart reveal', 'JYO-40'), false);
});

test('title matching accepts a title ending exactly at the id', () => {
  assert.equal(titleMatchesId('Fixes JYO-4', 'JYO-4'), true);
});

test('branchMatchesId returns false for a non-string id instead of throwing', () => {
  assert.equal(branchMatchesId('JYO-4-chart-reveal', 4), false);
  assert.equal(branchMatchesId('JYO-4-chart-reveal', { id: 'JYO-4' }), false);
});

test('titleMatchesId returns false for a non-string id instead of throwing', () => {
  assert.equal(titleMatchesId('JYO-4: chart reveal', 4), false);
  assert.equal(titleMatchesId('JYO-4: chart reveal', { id: 'JYO-4' }), false);
});
