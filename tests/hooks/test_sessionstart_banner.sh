#!/usr/bin/env bash
# Test sessionstart-banner.sh — first-run hint + upgrade notification.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/plugins/pilot/hooks/sessionstart-banner.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
export XDG_CACHE_HOME="$TMP/.cache"

# Case 1: fresh cache → first-run line shown, no upgrade line.
OUT=$(bash "$HOOK")
echo "$OUT" | grep -q '\[pilot active\] v' || { echo "FAIL: missing banner"; exit 1; }
echo "$OUT" | grep -q 'first run' || { echo "FAIL: missing first-run hint"; exit 1; }
echo "$OUT" | grep -q 'upgraded' && { echo "FAIL: upgrade line shown on first run"; exit 1; }
echo "PASS: first run shows welcome, no upgrade line"

# Case 2: second invocation with same version → no first-run line, no upgrade line.
OUT=$(bash "$HOOK")
echo "$OUT" | grep -q 'first run' && { echo "FAIL: first-run hint repeated"; exit 1; }
echo "$OUT" | grep -q 'upgraded' && { echo "FAIL: upgrade line on same-version rerun"; exit 1; }
echo "PASS: second invocation is quiet"

# Case 3: forge a different last-version → upgrade line shown.
echo "0.0.1" > "$XDG_CACHE_HOME/pilot/last-version"
OUT=$(bash "$HOOK")
echo "$OUT" | grep -qE 'upgraded 0\.0\.1 . v?[0-9]' \
  || { echo "FAIL: missing upgrade line: $OUT"; exit 1; }
echo "PASS: version transition triggers upgrade line"

# Case 4: rerun after upgrade → no upgrade line (already noted).
OUT=$(bash "$HOOK")
echo "$OUT" | grep -q 'upgraded' && { echo "FAIL: upgrade line repeated"; exit 1; }
echo "PASS: upgrade line shown only once per transition"

# Case 5: bypass-session marker → banner shows session-active note.
touch "$XDG_CACHE_HOME/pilot/bypass-session"
OUT=$(bash "$HOOK")
echo "$OUT" | grep -q 'bypass: session-active' \
  || { echo "FAIL: bypass session not shown"; exit 1; }
echo "PASS: session-bypass indicator shown"
rm "$XDG_CACHE_HOME/pilot/bypass-session"

echo "ALL sessionstart-banner tests passed."
