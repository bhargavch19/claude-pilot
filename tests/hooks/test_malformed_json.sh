#!/usr/bin/env bash
# All three gate hooks must decline gracefully on malformed JSON input
# instead of silently exiting 0 — a future stdin schema change shouldn't
# make the gates invisible.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
export XDG_CACHE_HOME="$TMP/.cache"

assert_declines() {
  local hook="$1" payload="$2"
  set +e
  err=$(printf '%s' "$payload" | "$ROOT/plugins/pilot/hooks/$hook" 2>&1 >/dev/null)
  rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || { echo "FAIL: $hook should exit 0 on bad JSON, got $rc"; exit 1; }
  echo "$err" | grep -qiE 'not valid JSON|parse error|declining to enforce' \
    || { echo "FAIL: $hook stderr missing decline message: $err"; exit 1; }
  echo "PASS: $hook declines on bad JSON ($payload)"
}

assert_declines plan-gate.sh 'not json at all'
assert_declines plan-gate.sh '{"unclosed":'
assert_declines plan-gate.sh ''

assert_declines pre-commit.sh 'not json at all'
assert_declines pre-commit.sh '{"unclosed":'
assert_declines pre-commit.sh ''

assert_declines verify-gate.sh 'not json at all'
assert_declines verify-gate.sh '{"unclosed":'
assert_declines verify-gate.sh ''

echo "ALL malformed-JSON tests passed."
