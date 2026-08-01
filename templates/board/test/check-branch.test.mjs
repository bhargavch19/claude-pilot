import { test } from 'node:test';
import assert from 'node:assert/strict';
import { checkBranch } from '../ci/check-branch.mjs';

const IDS = ['JYO-1', 'JYO-4', 'JYO-40'];

test('a canonical branch passes', () => {
  assert.equal(checkBranch('JYO-4-chart-reveal', IDS).ok, true);
});

test('an unknown story id fails with a helpful message', () => {
  const r = checkBranch('JYO-77-mystery', IDS);
  assert.equal(r.ok, false);
  assert.match(r.message, /start-story/);
  assert.match(r.message, /JYO-77-mystery/);
});

test('a branch with no id at all fails', () => {
  assert.equal(checkBranch('quick-fix', IDS).ok, false);
});

test('chore, hotfix and docs branches are exempt', () => {
  for (const b of ['chore/deps', 'hotfix/prod-down', 'docs/readme']) {
    const r = checkBranch(b, IDS);
    assert.equal(r.ok, true);
    assert.equal(r.exempt, true);
  }
});

test('near-miss prefixes are not exempt', () => {
  for (const b of ['chores/x', 'hotfix-urgent', 'feat/chore/x', 'chore']) {
    const r = checkBranch(b, IDS);
    assert.equal(r.exempt, false, `${b} should not be exempt`);
  }
});

test('the exemption prefixes are case-sensitive', () => {
  for (const b of ['Chore/x', 'HOTFIX/x', 'Docs/x']) {
    const r = checkBranch(b, IDS);
    assert.equal(r.exempt, false, `${b} should not be exempt`);
  }
});

test('JYO-40 resolves to JYO-40 and not JYO-4', () => {
  const r = checkBranch('JYO-40-payments', IDS);
  assert.equal(r.ok, true);
  assert.equal(r.id, 'JYO-40');
});
