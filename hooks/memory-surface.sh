#!/usr/bin/env bash
# Pilot memory-surface — SessionStart hook.
#
# Surfaces the project's persistent memory (.pilot/memory.md) at session start so
# durable decisions, conventions, and gotchas survive across sessions and
# compaction. The model writes it via /pilot-remember; this hook reads it back.
# Silent when absent/empty. Read-only; never blocks. The digest is capped so a
# long memory file can't blow up the context window.
set -uo pipefail

cat >/dev/null 2>&1 || true   # drain the SessionStart payload

PROJ="${CLAUDE_PROJECT_DIR:-}"
[ -n "$PROJ" ] || PROJ=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$PROJ" ] || PROJ="$PWD"

MEM="$PROJ/.pilot/memory.md"
[ -f "$MEM" ] || exit 0

body=$(grep -v '^[[:space:]]*$' "$MEM" 2>/dev/null | head -40 || true)
[ -n "$body" ] || exit 0

printf 'pilot project memory (.pilot/memory.md) — durable context for this repo (edit via /pilot-remember):\n%s\n' "$body"
exit 0
