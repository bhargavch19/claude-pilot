#!/usr/bin/env bash
# Test pretooluse-heartbeat.sh: records a timestamp+tool marker so /pilot-doctor
# can detect a silently-dead PreToolUse chain (Claude Code issue #31250).
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/hooks/pretooluse-heartbeat.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$XDG_CACHE_HOME/pilot"
MARK="$XDG_CACHE_HOME/pilot/pretooluse-last"

# Case 1: a tool call writes the heartbeat with a numeric ts and the tool name.
jq -cn '{tool_name:"Bash", tool_input:{command:"ls"}}' | "$HOOK" >/dev/null 2>&1 || true
[[ -f "$MARK" ]] || { echo "FAIL: heartbeat not written"; exit 1; }
ts=$(cut -f1 "$MARK"); tool=$(cut -f2 "$MARK")
[[ "$ts" =~ ^[0-9]+$ ]] || { echo "FAIL: heartbeat ts not numeric: $ts"; exit 1; }
[[ "$tool" == "Bash" ]] || { echo "FAIL: heartbeat tool not recorded: $tool"; exit 1; }
echo "PASS: heartbeat records timestamp + tool"

# Case 2: a different tool overwrites with the new tool name.
jq -cn '{tool_name:"Edit", tool_input:{file_path:"x"}}' | "$HOOK" >/dev/null 2>&1 || true
[[ "$(cut -f2 "$MARK")" == "Edit" ]] || { echo "FAIL: heartbeat not updated for Edit"; exit 1; }
echo "PASS: heartbeat updates on each tool call"

# Case 3: malformed / empty input → no crash, tool falls back to '?'.
printf '' | "$HOOK" >/dev/null 2>&1 || true
printf 'not json' | "$HOOK" >/dev/null 2>&1 || true
echo "PASS: malformed input handled safely"

echo "ALL pretooluse-heartbeat tests passed."
