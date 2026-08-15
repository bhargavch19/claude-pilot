#!/usr/bin/env bash
# Test memory-surface.sh: SessionStart hook that injects .pilot/memory.md so
# project memory survives across sessions. Silent when absent; capped digest.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/plugins/pilot/hooks/memory-surface.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
PROJ="$TMP/proj"; mkdir -p "$PROJ/.pilot"
export CLAUDE_PROJECT_DIR="$PROJ"

run() { printf '{}' | "$HOOK" 2>/dev/null || true; }

# 1. No memory file → silent.
OUT=$(run)
[[ -z "$OUT" ]] || { echo "FAIL: should be silent with no memory file, got: $OUT"; exit 1; }
echo "PASS: silent when no memory file"

# 2. Memory present → surfaced, content included.
printf '# Pilot project memory\n\n- always run the suite with bash tests/run.sh\n- div guards against zero\n' > "$PROJ/.pilot/memory.md"
OUT=$(run)
echo "$OUT" | grep -q "pilot project memory" || { echo "FAIL: missing memory header line"; exit 1; }
echo "$OUT" | grep -q "always run the suite" || { echo "FAIL: memory content not surfaced"; exit 1; }
echo "$OUT" | grep -q "div guards against zero" || { echo "FAIL: second note not surfaced"; exit 1; }
echo "PASS: memory file is surfaced at SessionStart"

# 3. Blank-only file → silent.
printf '\n\n   \n' > "$PROJ/.pilot/memory.md"
OUT=$(run)
[[ -z "$OUT" ]] || { echo "FAIL: blank memory should be silent, got: $OUT"; exit 1; }
echo "PASS: blank memory is silent"

# 4. Long memory → digest is capped (<= ~41 lines: header + 40).
: > "$PROJ/.pilot/memory.md"
for i in $(seq 1 100); do echo "- note $i" >> "$PROJ/.pilot/memory.md"; done
lines=$(run | wc -l | tr -d ' ')
[ "$lines" -le 41 ] || { echo "FAIL: digest not capped ($lines lines)"; exit 1; }
echo "PASS: long memory digest is capped"

echo "ALL memory-surface tests passed."
