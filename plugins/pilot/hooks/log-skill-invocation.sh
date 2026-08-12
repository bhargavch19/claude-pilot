#!/usr/bin/env bash
# Append a one-line routing entry to routing.log when the model invokes a
# Skill. Surfaces via /pilot-status. Bounded at 500 lines. Never blocks.
#
# Earlier versions asked the model to write this line itself from inside
# the pilot skill. That instruction was routinely skipped — making the
# routing log empty in production. Moving it into a PostToolUse hook
# guarantees one line per Skill invocation regardless of model behavior.
set -euo pipefail

INPUT=$(cat)

if [[ -z "$INPUT" ]] || ! printf '%s' "$INPUT" | jq empty 2>/dev/null; then
  exit 0
fi

SKILL=$(printf '%s' "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null || true)
[[ -z "$SKILL" ]] && exit 0

# Capture session_id when Claude Code provides it. Lets /pilot-trace scope to
# a single session even when concurrent sessions interleave in the log.
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
SESSION_FIELD=""
[[ -n "$SESSION" ]] && SESSION_FIELD=" session=${SESSION:0:8}"

LOG="${XDG_CACHE_HOME:-$HOME/.cache}/pilot/routing.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || exit 0

printf '%s%s skill=%s\n' "$(date -u +%FT%TZ)" "$SESSION_FIELD" "$SKILL" >> "$LOG" 2>/dev/null || exit 0

# Bound the log so it doesn't grow without limit.
if [[ -f "$LOG" ]] && (( $(wc -l < "$LOG") > 500 )); then
  tail -500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
fi

exit 0
