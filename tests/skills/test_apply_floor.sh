#!/usr/bin/env bash
# Test apply-floor.sh: drops the production-quality floor templates into a
# target project idempotently, never overwriting existing files. Also asserts
# the templates are structurally valid (dependency-free checks — no python/yaml).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/skills/pilot/playbooks/apply-floor.sh"
TPL="$ROOT/skills/pilot/playbooks/templates"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

[ -x "$SCRIPT" ] || { echo "FAIL: apply-floor.sh not executable"; exit 1; }

# Templates present and structurally valid.
grep -q '^name: quality-floor' "$TPL/ci-quality-floor.yml" || { echo "FAIL: CI template missing workflow name"; exit 1; }
grep -q '^jobs:' "$TPL/ci-quality-floor.yml" || { echo "FAIL: CI template missing jobs"; exit 1; }
grep -q 'gitleaks' "$TPL/ci-quality-floor.yml" || { echo "FAIL: CI template missing secret scan"; exit 1; }
grep -q '^repos:' "$TPL/pre-commit-config.yaml" || { echo "FAIL: pre-commit template missing repos"; exit 1; }
grep -q 'gitleaks' "$TPL/pre-commit-config.yaml" || { echo "FAIL: pre-commit template missing gitleaks"; exit 1; }
echo "PASS: floor templates present and structurally valid"

# Apply into an empty target → both configs dropped.
bash "$SCRIPT" "$TMP" >/dev/null
[ -f "$TMP/.github/workflows/quality-floor.yml" ] || { echo "FAIL: CI workflow not dropped"; exit 1; }
[ -f "$TMP/.pre-commit-config.yaml" ] || { echo "FAIL: pre-commit config not dropped"; exit 1; }
echo "PASS: apply-floor drops CI + pre-commit configs"

# Idempotent: re-run keeps files and reports them, no error, no duplicate.
out=$(bash "$SCRIPT" "$TMP")
echo "$out" | grep -q 'exists, kept' || { echo "FAIL: re-run should report kept files"; exit 1; }
echo "PASS: apply-floor is idempotent on re-run"

# Never overwrites a customized file.
printf 'CUSTOM-DO-NOT-CLOBBER\n' > "$TMP/.pre-commit-config.yaml"
bash "$SCRIPT" "$TMP" >/dev/null
grep -q 'CUSTOM-DO-NOT-CLOBBER' "$TMP/.pre-commit-config.yaml" || { echo "FAIL: apply-floor overwrote a user file"; exit 1; }
echo "PASS: apply-floor never overwrites an existing file"

# Non-directory target → error exit.
rc=0; bash "$SCRIPT" "$TMP/does-not-exist" >/dev/null 2>&1 || rc=$?
[ "$rc" != "0" ] || { echo "FAIL: should error on a missing target dir"; exit 1; }
echo "PASS: apply-floor errors on a non-directory target"

echo "ALL apply-floor tests passed."
