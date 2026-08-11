#!/usr/bin/env bash
# Team mode: verify-gate's outcome ledger dual-writes to the repo-scoped
# .pilot/outcomes.jsonl when .pilot.json {"team":{"shared_outcomes":true}} —
# and does NOT when the flag is absent.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/verify-gate.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$XDG_CACHE_HOME/pilot"

mk_repo() { # $1=dir — git repo with a changed source file (trips the code gate)
  git init -q "$1" && ( cd "$1" && echo "let x: any = 1" > f.ts )
}
mk_transcript() { local f="$TMP/t.jsonl"
  jq -n '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:"All done and ready."}]}}' > "$f"
  printf '%s' "$f"
}
run_gate() { ( cd "$1" && jq -n --arg p "$(mk_transcript)" \
  '{transcript_path:$p, session_id:"sess-team", stop_hook_active:true}' | "$HOOK" 2>&1 || true ); }

# Case 1: shared_outcomes true → repo ledger written with the blocked outcome.
mk_repo "$TMP/team"
echo '{"team":{"shared_outcomes":true}}' > "$TMP/team/.pilot.json"
OUT=$(run_gate "$TMP/team")
[[ "$OUT" == *"verify-gate"* ]] || { echo "FAIL: expected the gate to fire"; exit 1; }
[[ -f "$TMP/team/.pilot/outcomes.jsonl" ]] \
  || { echo "FAIL: repo-scoped outcomes.jsonl not written in team mode"; exit 1; }
jq -e 'select(.result=="blocked") | .user != null' "$TMP/team/.pilot/outcomes.jsonl" >/dev/null \
  || { echo "FAIL: team ledger row missing result/user fields"; exit 1; }
echo "PASS: team mode dual-writes the repo-scoped outcome ledger"

# Case 2: no team flag → no repo ledger (cache-only, unchanged default).
rm -f "$XDG_CACHE_HOME"/pilot/verify-gate-blocks
mk_repo "$TMP/solo"
OUT=$(run_gate "$TMP/solo")
[[ ! -f "$TMP/solo/.pilot/outcomes.jsonl" ]] \
  || { echo "FAIL: repo ledger must not be written without the team flag"; exit 1; }
echo "PASS: default stays cache-only (no repo ledger)"

# Case 3: local cache ledger got both rows regardless.
N=$(grep -c '"result"' "$XDG_CACHE_HOME/pilot/outcomes.jsonl")
[[ "$N" -ge 2 ]] || { echo "FAIL: cache ledger expected >=2 rows, got $N"; exit 1; }
echo "PASS: local cache ledger unaffected by team mode"

echo "ALL team-outcomes tests passed."
