#!/usr/bin/env bash
# Pilot PreToolUse liveness heartbeat.
#
# PreToolUse hooks can fail silently (Claude Code issue #31250) — if the chain
# stops firing, gates like plan-gate / safety-gate quietly stop protecting and
# nothing tells you. This records that PreToolUse fired (timestamp + tool) so
# /pilot-doctor can prove the chain is live: doctor's own Bash command triggers
# this hook, so a fresh heartbeat after running doctor means PreToolUse works;
# a missing/stale one means it does not. Never blocks; near-zero cost.
set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // "?"' 2>/dev/null || echo "?")
[ -n "$TOOL" ] || TOOL="?"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pilot"
mkdir -p "$CACHE_DIR" 2>/dev/null || true
TS=$(date +%s 2>/dev/null || echo 0)
printf '%s\t%s\n' "$TS" "$TOOL" > "$CACHE_DIR/pretooluse-last" 2>/dev/null || true

exit 0
