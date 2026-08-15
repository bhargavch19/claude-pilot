#!/usr/bin/env bash
# Test the Phase 8 feedback loop: verify-gate writes a repo-scoped outcome
# ledger, and route-advisor nudges when the recent first-pass-verified rate is
# poor (and stays quiet when it's healthy).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VG="$ROOT/plugins/pilot/hooks/verify-gate.sh"
ADV="$ROOT/plugins/pilot/hooks/route-advisor.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
export XDG_CACHE_HOME="$TMP/cache"; mkdir -p "$XDG_CACHE_HOME/pilot"
export CLAUDE_PLUGIN_ROOT="$ROOT/plugins/pilot"
LEDGER="$XDG_CACHE_HOME/pilot/outcomes.jsonl"

REPO="$TMP/repo"; mkdir -p "$REPO"
( cd "$REPO" && git init -q && echo "const x = 1;" > a.ts )
BASE=$(git -C "$REPO" rev-parse --show-toplevel)

mk_tx() { local f="$TMP/t.jsonl"; jq -n --arg t "$1" \
  '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' > "$f"; printf '%s' "$f"; }
mk_in() { jq -n --arg p "$1" --arg s "$2" '{transcript_path:$p, session_id:$s}'; }

# 1. A blocking Stop (done claim, changed code, no capture) → "blocked" recorded.
t=$(mk_tx "All done. Shipping.")
( cd "$REPO" && mk_in "$t" sess-1 | "$VG" >/dev/null 2>&1 || true )
grep -q '"result":"blocked"' "$LEDGER" || { echo "FAIL: blocked outcome not recorded"; exit 1; }
grep -Fq "\"repo\":\"$BASE\"" "$LEDGER" || { echo "FAIL: repo not recorded in ledger"; exit 1; }
echo "PASS: verify-gate records a blocked outcome (repo-scoped)"

# 2. A passing Stop (a real captured pass this session) → "pass" recorded.
jq -cn --arg s "sess-2" '{ts:9999999999, session_id:$s, ok:true, command:"x"}' > "$XDG_CACHE_HOME/pilot/last-test-run"
( cd "$REPO" && mk_in "$t" sess-2 | "$VG" >/dev/null 2>&1 || true )
grep -q '"result":"pass"' "$LEDGER" || { echo "FAIL: pass outcome not recorded"; exit 1; }
echo "PASS: verify-gate records a pass outcome"

# 3. route-advisor nudges when the recent rate is poor (>= half blocked).
: > "$LEDGER"
for _ in 1 2 3 4; do jq -cn --arg r "$BASE" '{ts:1,session:"s",repo:$r,result:"blocked"}' >> "$LEDGER"; done
out=$( cd "$REPO" && jq -cn '{prompt:"keep working on the thing"}' | "$ADV" 2>/dev/null \
       | jq -r '.hookSpecificOutput.additionalContext // ""' )
echo "$out" | grep -q "Feedback: verify-gate blocked" || { echo "FAIL: no nudge on poor rate, got: [$out]"; exit 1; }
echo "PASS: route-advisor nudges on a poor first-pass-verified rate"

# 4. A healthy ledger → no nudge (silent on a fuzzy prompt).
: > "$LEDGER"
for _ in 1 2 3 4; do jq -cn --arg r "$BASE" '{ts:1,session:"s",repo:$r,result:"pass"}' >> "$LEDGER"; done
out=$( cd "$REPO" && jq -cn '{prompt:"keep working on the thing"}' | "$ADV" 2>/dev/null \
       | jq -r '.hookSpecificOutput.additionalContext // ""' )
[ -z "$out" ] || { echo "FAIL: should be silent on a healthy ledger, got: [$out]"; exit 1; }
echo "PASS: no nudge when the first-pass rate is healthy"

# 5. Too few data points (< 3) → no nudge even if all blocked.
: > "$LEDGER"
for _ in 1 2; do jq -cn --arg r "$BASE" '{ts:1,session:"s",repo:$r,result:"blocked"}' >> "$LEDGER"; done
out=$( cd "$REPO" && jq -cn '{prompt:"keep working on the thing"}' | "$ADV" 2>/dev/null \
       | jq -r '.hookSpecificOutput.additionalContext // ""' )
[ -z "$out" ] || { echo "FAIL: should not nudge with <3 data points, got: [$out]"; exit 1; }
echo "PASS: no nudge below the minimum sample size"

echo "ALL outcome-feedback tests passed."
