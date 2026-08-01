import { test } from 'node:test';
import assert from 'node:assert/strict';
import { deriveStatus } from '../lib/status.mjs';

const pr = (o) => ({
  number: 1, title: '', headBranch: '', state: 'open',
  draft: false, updatedAt: '2026-08-01T00:00:00Z', url: 'u', ...o,
});
const NO_GIT = { prs: [], branches: [] };

test('no branch, no PR is todo', () => {
  assert.equal(deriveStatus({ id: 'JYO-4' }, NO_GIT).status, 'todo');
});

test('branch with commits is in_progress', () => {
  const git = { prs: [], branches: [{ name: 'JYO-4-chart', ahead: 2 }] };
  assert.equal(deriveStatus({ id: 'JYO-4' }, git).status, 'in_progress');
});

test('branch with zero commits ahead is still todo', () => {
  const git = { prs: [], branches: [{ name: 'JYO-4-chart', ahead: 0 }] };
  assert.equal(deriveStatus({ id: 'JYO-4' }, git).status, 'todo');
});

test('open non-draft PR is in_review', () => {
  const git = { prs: [pr({ headBranch: 'JYO-4-chart' })], branches: [] };
  assert.equal(deriveStatus({ id: 'JYO-4' }, git).status, 'in_review');
});

test('open draft PR is in_progress', () => {
  const git = { prs: [pr({ headBranch: 'JYO-4-chart', draft: true })], branches: [] };
  assert.equal(deriveStatus({ id: 'JYO-4' }, git).status, 'in_progress');
});

test('merged PR is done', () => {
  const git = { prs: [pr({ headBranch: 'JYO-4-chart', state: 'merged' })], branches: [] };
  assert.equal(deriveStatus({ id: 'JYO-4' }, git).status, 'done');
});

test('blocked override beats a merged PR', () => {
  const git = { prs: [pr({ headBranch: 'JYO-4-chart', state: 'merged' })], branches: [] };
  const r = deriveStatus({ id: 'JYO-4', status_override: 'blocked' }, git);
  assert.equal(r.status, 'blocked');
  assert.equal(r.source, 'override');
});

test('PR wins over a bare branch', () => {
  const git = {
    prs: [pr({ headBranch: 'JYO-4-chart', state: 'merged' })],
    branches: [{ name: 'JYO-4-chart', ahead: 3 }],
  };
  assert.equal(deriveStatus({ id: 'JYO-4' }, git).status, 'done');
});

test('two matching PRs, neither merged: most recently updated wins, with a warning', () => {
  const git = {
    prs: [
      pr({ number: 1, headBranch: 'JYO-4-old', state: 'closed', updatedAt: '2026-08-01T00:00:00Z' }),
      pr({ number: 2, headBranch: 'JYO-4-new', state: 'open', updatedAt: '2026-08-05T00:00:00Z' }),
    ],
    branches: [],
  };
  const r = deriveStatus({ id: 'JYO-4' }, git);
  assert.equal(r.status, 'in_review');
  assert.equal(r.pr.number, 2);
  assert.match(r.warning, /2 pull requests/);
});

// Rule change (authorised in fix round 1): merging is terminal and
// irreversible, so a merged PR outranks a more recently updated PR that
// isn't merged. Recency only breaks ties among merged PRs (or, separately,
// among non-merged PRs when nothing is merged).
test('older merged PR beats a more recently updated open PR — merge is terminal', () => {
  const git = {
    prs: [
      pr({ number: 1, headBranch: 'JYO-4-old', state: 'merged', updatedAt: '2026-08-01T00:00:00Z' }),
      pr({ number: 2, headBranch: 'JYO-4-new', state: 'open', updatedAt: '2026-08-05T00:00:00Z' }),
    ],
    branches: [],
  };
  const r = deriveStatus({ id: 'JYO-4' }, git);
  assert.equal(r.status, 'done');
  assert.equal(r.pr.number, 1);
  assert.match(r.warning, /2 pull requests/);
  // The warning has to describe the rule that was actually applied. This is
  // the exact case where "using the most recently updated" was a lie: the
  // board says done from PR 1 while PR 2 is the newest.
  assert.match(r.warning, /merged one wins/);
  assert.doesNotMatch(r.warning, /using the most recently updated/);
});

test('older merged PR beats a more recently updated closed-unmerged PR', () => {
  const git = {
    prs: [
      pr({ number: 1, headBranch: 'JYO-4-old', state: 'merged', updatedAt: '2026-08-01T00:00:00Z' }),
      pr({ number: 2, headBranch: 'JYO-4-new', state: 'closed', updatedAt: '2026-08-05T00:00:00Z' }),
    ],
    branches: [],
  };
  const r = deriveStatus({ id: 'JYO-4' }, git);
  assert.equal(r.status, 'done');
  assert.equal(r.pr.number, 1);
});

test('two merged PRs: done, reporting the more recently updated one as pr', () => {
  const git = {
    prs: [
      pr({ number: 1, headBranch: 'JYO-4-old', state: 'merged', updatedAt: '2026-08-01T00:00:00Z' }),
      pr({ number: 2, headBranch: 'JYO-4-new', state: 'merged', updatedAt: '2026-08-05T00:00:00Z' }),
    ],
    branches: [],
  };
  const r = deriveStatus({ id: 'JYO-4' }, git);
  assert.equal(r.status, 'done');
  assert.equal(r.pr.number, 2);
});

test('a PR with a null updatedAt never wins a recency tie-break', () => {
  const git = {
    prs: [
      pr({ number: 1, headBranch: 'JYO-4-a', state: 'open', draft: false, updatedAt: null }),
      pr({ number: 2, headBranch: 'JYO-4-b', state: 'open', draft: true, updatedAt: '2026-08-05T00:00:00Z' }),
    ],
    branches: [],
  };
  const r = deriveStatus({ id: 'JYO-4' }, git);
  // If the null-updatedAt PR incorrectly won, this would be in_review (non-draft).
  assert.equal(r.status, 'in_progress');
  assert.equal(r.pr.number, 2);
});

test('PR matches only by title, not by branch, and is picked up', () => {
  const git = {
    prs: [pr({ headBranch: 'random-branch', title: 'JYO-4: chart reveal', state: 'open' })],
    branches: [],
  };
  assert.equal(deriveStatus({ id: 'JYO-4' }, git).status, 'in_review');
});

test('title near-miss on a different id does not match via title', () => {
  const git = {
    prs: [pr({ headBranch: 'random-branch', title: 'JYO-40: payments', state: 'merged' })],
    branches: [],
  };
  assert.equal(deriveStatus({ id: 'JYO-4' }, git).status, 'todo');
});

test('a merged draft PR is still done — merged is checked before draft', () => {
  const git = {
    prs: [pr({ headBranch: 'JYO-4-chart', state: 'merged', draft: true })],
    branches: [],
  };
  assert.equal(deriveStatus({ id: 'JYO-4' }, git).status, 'done');
});

test('missing prs/branches on the git object default to empty, not a throw', () => {
  assert.equal(deriveStatus({ id: 'JYO-4' }, {}).status, 'todo');
});

test('status_override is case-sensitive: "Blocked" does not trigger the override', () => {
  const git = { prs: [], branches: [] };
  const r = deriveStatus({ id: 'JYO-4', status_override: 'Blocked' }, git);
  assert.equal(r.status, 'todo');
  assert.notEqual(r.source, 'override');
});

test('closed unmerged PR falls through to branch state', () => {
  const git = {
    prs: [pr({ headBranch: 'JYO-4-chart', state: 'closed' })],
    branches: [{ name: 'JYO-4-chart', ahead: 1 }],
  };
  assert.equal(deriveStatus({ id: 'JYO-4' }, git).status, 'in_progress');
});

test('JYO-40 PR does not move JYO-4', () => {
  const git = { prs: [pr({ headBranch: 'JYO-40-payments', state: 'merged' })], branches: [] };
  assert.equal(deriveStatus({ id: 'JYO-4' }, git).status, 'todo');
});
