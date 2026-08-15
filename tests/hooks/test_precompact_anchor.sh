#!/usr/bin/env bash
# Test precompact-anchor.sh: outputs routing essentials, includes
# version, bypass state, and recent routing log when present.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/plugins/pilot/hooks/precompact-anchor.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
export XDG_CACHE_HOME="$TMP/.cache"
mkdir -p "$XDG_CACHE_HOME/pilot"

# Case 1: bare invocation, no bypass, no routing log → core sections.
OUT=$(echo '{"trigger":"manual"}' | bash "$HOOK")
echo "$OUT" | grep -q '\[pilot v' || { echo "FAIL: missing version header"; exit 1; }
echo "$OUT" | grep -q 'registry.md' || { echo "FAIL: missing registry.md pointer (replaces inline routing rules)"; exit 1; }
echo "$OUT" | grep -q 'Guardrails:' || { echo "FAIL: missing guardrails line"; exit 1; }
echo "$OUT" | grep -q 'Bypass state: none' || { echo "FAIL: bypass state should be 'none'"; exit 1; }
echo "$OUT" | grep -q 'Recent routing' && { echo "FAIL: routing log shouldn't be shown when empty"; exit 1; }
echo "PASS: bare invocation prints core anchor"

# Case 2: bypass-once armed → 'one-shot armed' state.
touch "$XDG_CACHE_HOME/pilot/bypass-once"
OUT=$(echo '{"trigger":"auto"}' | bash "$HOOK")
echo "$OUT" | grep -q 'one-shot armed' || { echo "FAIL: one-shot not detected: $OUT"; exit 1; }
rm "$XDG_CACHE_HOME/pilot/bypass-once"
echo "PASS: one-shot bypass surfaced in anchor"

# Case 3: bypass-session active → 'session-active' state with re-engage hint.
touch "$XDG_CACHE_HOME/pilot/bypass-session"
OUT=$(echo '{"trigger":"manual"}' | bash "$HOOK")
echo "$OUT" | grep -q 'session-active' || { echo "FAIL: session-active not detected"; exit 1; }
echo "$OUT" | grep -q '/pilot-back-on' || { echo "FAIL: re-engage hint missing"; exit 1; }
rm "$XDG_CACHE_HOME/pilot/bypass-session"
echo "PASS: session-active bypass surfaced"

# Case 4: routing log with entries → shown.
cat > "$XDG_CACHE_HOME/pilot/routing.log" <<'EOF'
2026-05-20T10:00:00Z phase=2.plan skill=superpowers:writing-plans trigger=plan
2026-05-20T10:05:00Z phase=3.build skill=tdd trigger=implement
EOF
OUT=$(echo '{"trigger":"manual"}' | bash "$HOOK")
echo "$OUT" | grep -q 'Recent routing' || { echo "FAIL: routing log section missing"; exit 1; }
echo "$OUT" | grep -q 'tdd' || { echo "FAIL: log entry not included"; exit 1; }
echo "PASS: routing log surfaced when populated"

# Case 5: trigger field reflected in output.
OUT=$(echo '{"trigger":"auto"}' | bash "$HOOK")
echo "$OUT" | grep -q 'trigger: auto' || { echo "FAIL: trigger=auto not in output"; exit 1; }
echo "PASS: trigger field surfaced"

# Case 6: malformed input still produces something (graceful degrade).
OUT=$(echo 'not json' | bash "$HOOK")
echo "$OUT" | grep -q 'trigger: unknown' || { echo "FAIL: malformed input not handled: $OUT"; exit 1; }
echo "PASS: malformed input degrades gracefully"

echo "ALL precompact-anchor tests passed."
