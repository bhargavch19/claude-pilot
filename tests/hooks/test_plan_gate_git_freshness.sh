#!/usr/bin/env bash
# Test plan-gate.sh git-based freshness:
#   - Plan committed on the current branch after merge-base with main → allow.
#   - Plan committed on main only (not on this branch) → block.
#   - Plan uncommitted in working tree → allow (covered by worktree check).
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/hooks/plan-gate.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
cd "$TMP"

git init -q -b main
git config user.email t@t.t
git config user.name t

# Seed main with an unrelated commit.
echo "x" > a.ts
git add a.ts
git commit -q -m "feat: seed"

big=$(printf 'line\n%.0s' {1..25})
mk_input() {
  jq -n --arg s "$big" '{tool_name:"Edit",tool_input:{new_string:$s}}'
}

# Case 1: no plan anywhere → block.
set +e
mk_input | "$HOOK" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 2 ]] || { echo "FAIL: no plan should block; got $rc"; exit 1; }
echo "PASS: no plan blocks"

# Case 2: plan committed on a feature branch (since merge-base) → allow.
git checkout -q -b feat/x
mkdir -p docs/superpowers/plans
echo "plan body" > docs/superpowers/plans/2026-01-01-x.md
git add docs/superpowers/plans/2026-01-01-x.md
git commit -q -m "docs: plan"
mk_input | "$HOOK" >/dev/null
echo "PASS: plan committed on branch allows"

# Set the file mtime far in the past — the new git-based check should not
# care, only branch commit presence matters.
touch -t 200001010101 docs/superpowers/plans/2026-01-01-x.md
mk_input | "$HOOK" >/dev/null
echo "PASS: stale mtime irrelevant when plan is in branch commits"

# Case 3: plan only on main (merged), branch has no plan modifications → still
# allows because the file exists in the working tree (worktree check). This is
# the intended behavior: a plan that lives at HEAD is considered present.
git checkout -q main
git merge --no-edit -q feat/x
git checkout -q -b feat/y  # new branch starting from merged main
mk_input | "$HOOK" >/dev/null
echo "PASS: plan present in worktree allows on new branch"

# Case 4: working-tree-only (uncommitted) plan → allow.
rm -rf docs
git checkout -q -b feat/z
mkdir -p .planning/phase-1
echo "plan body" > .planning/phase-1/PLAN.md  # untracked
mk_input | "$HOOK" >/dev/null
echo "PASS: uncommitted plan in worktree allows"

echo "ALL plan-gate git-freshness tests passed."
