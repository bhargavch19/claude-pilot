#!/usr/bin/env bash
# Test marker-file bypass in plan-gate.sh (used by /pilot-off,
# /pilot-bypass --no-plan, /pilot-off-rails slash commands).
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/hooks/plan-gate.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
cd "$TMP"

# Isolate cache dir so we don't touch real markers.
export XDG_CACHE_HOME="$TMP/.cache"

big=$(printf 'line\n%.0s' {1..25})
input=$(jq -n --arg s "$big" '{tool_name:"Edit",tool_input:{new_string:$s}}')

# Baseline: no markers, no plan → block.
set +e
echo "$input" | "$HOOK" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 2 ]] || { echo "FAIL: baseline should block (got $rc)"; exit 1; }
echo "PASS: baseline blocks"

# bypass-once → allow, then auto-consume.
mkdir -p "$XDG_CACHE_HOME/pilot"
touch "$XDG_CACHE_HOME/pilot/bypass-once"
echo "$input" | "$HOOK" >/dev/null
echo "PASS: bypass-once allows"
[[ -f "$XDG_CACHE_HOME/pilot/bypass-once" ]] && { echo "FAIL: bypass-once not consumed"; exit 1; }
echo "PASS: bypass-once consumed"

# After consumption, next fire blocks again.
set +e
echo "$input" | "$HOOK" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 2 ]] || { echo "FAIL: gate should block after consumption (got $rc)"; exit 1; }
echo "PASS: gate re-engages after one-shot consumed"

# bypass-no-plan-once → allow, then auto-consume.
touch "$XDG_CACHE_HOME/pilot/bypass-no-plan-once"
echo "$input" | "$HOOK" >/dev/null
[[ -f "$XDG_CACHE_HOME/pilot/bypass-no-plan-once" ]] && { echo "FAIL: bypass-no-plan-once not consumed"; exit 1; }
echo "PASS: bypass-no-plan-once allows and is consumed"

# bypass-session → allow, NOT consumed.
touch "$XDG_CACHE_HOME/pilot/bypass-session"
echo "$input" | "$HOOK" >/dev/null
echo "$input" | "$HOOK" >/dev/null  # second fire still allowed
[[ -f "$XDG_CACHE_HOME/pilot/bypass-session" ]] || { echo "FAIL: bypass-session was consumed"; exit 1; }
echo "PASS: bypass-session persists across fires"

# Remove session marker → gate re-engages.
rm "$XDG_CACHE_HOME/pilot/bypass-session"
set +e
echo "$input" | "$HOOK" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 2 ]] || { echo "FAIL: gate should block after session marker removed (got $rc)"; exit 1; }
echo "PASS: removing session marker re-engages gate"

echo "ALL marker bypass tests passed."
