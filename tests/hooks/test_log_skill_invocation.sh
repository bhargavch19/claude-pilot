#!/usr/bin/env bash
# Test log-skill-invocation.sh: appends a routing entry per Skill call.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/plugins/pilot/hooks/log-skill-invocation.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
export XDG_CACHE_HOME="$TMP/.cache"
LOG="$XDG_CACHE_HOME/pilot/routing.log"

# Case 1: valid Skill invocation → line appended.
INPUT='{"tool_name":"Skill","tool_input":{"skill":"tdd","args":"build x"}}'
printf '%s' "$INPUT" | "$HOOK"
[[ -f "$LOG" ]] || { echo "FAIL: log not created"; exit 1; }
grep -q 'skill=tdd' "$LOG" || { echo "FAIL: log missing skill name"; exit 1; }
echo "PASS: appends routing line"

# Case 2: missing skill field → silent no-op (no new line).
LINES_BEFORE=$(wc -l < "$LOG")
INPUT='{"tool_name":"Skill","tool_input":{}}'
printf '%s' "$INPUT" | "$HOOK"
LINES_AFTER=$(wc -l < "$LOG")
[[ "$LINES_BEFORE" -eq "$LINES_AFTER" ]] || { echo "FAIL: missing-skill field still wrote"; exit 1; }
echo "PASS: silent no-op on missing skill field"

# Case 3: malformed JSON → silent no-op, exit 0.
set +e
echo "garbage not json" | "$HOOK"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || { echo "FAIL: malformed JSON should exit 0, got $rc"; exit 1; }
echo "PASS: malformed JSON does not error"

# Case 4: cap at 500 lines.
: > "$LOG"
for i in $(seq 1 510); do echo "line $i" >> "$LOG"; done
INPUT='{"tool_name":"Skill","tool_input":{"skill":"diagnose"}}'
printf '%s' "$INPUT" | "$HOOK"
LINE_COUNT=$(wc -l < "$LOG")
(( LINE_COUNT <= 500 )) || { echo "FAIL: cap not enforced (got $LINE_COUNT lines)"; exit 1; }
echo "PASS: truncates to 500 lines"

# Case 5: session_id field is captured when present (truncated to 8 chars).
: > "$LOG"
INPUT='{"session_id":"abc12345-def6-7890-1234-567890abcdef","tool_input":{"skill":"diagnose"}}'
printf '%s' "$INPUT" | "$HOOK"
grep -q 'session=abc12345 skill=diagnose' "$LOG" || { echo "FAIL: session_id not captured"; exit 1; }
echo "PASS: session_id captured (truncated to 8 chars)"

# Case 6: missing session_id → entry still written, no session= field.
: > "$LOG"
INPUT='{"tool_input":{"skill":"tdd"}}'
printf '%s' "$INPUT" | "$HOOK"
grep -q '^[^ ]* skill=tdd$' "$LOG" || { echo "FAIL: missing session_id should produce session-less line, got: $(cat "$LOG")"; exit 1; }
echo "PASS: missing session_id produces session-less entry"

echo "ALL log-skill-invocation tests passed."
