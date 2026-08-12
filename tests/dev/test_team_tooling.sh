#!/usr/bin/env bash
# Team tooling: skills-lock.json schema, bootstrap-team.sh --check behavior,
# and outcome-report.sh aggregation over a fixture ledger.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Case 1: scripts parse (bash -n) and are executable.
for s in bootstrap-team.sh outcome-report.sh; do
  bash -n "$ROOT/dev/$s" || { echo "FAIL: dev/$s does not parse"; exit 1; }
  [[ -x "$ROOT/dev/$s" ]] || { echo "FAIL: dev/$s not executable"; exit 1; }
done
echo "PASS: team tooling scripts parse and are executable"

# Case 2: skills-lock.json is valid and every entry has name+kind, with the
# kind-specific required fields.
LOCK="$ROOT/dev/skills-lock.json"
jq empty "$LOCK" || { echo "FAIL: skills-lock.json invalid"; exit 1; }
jq -e '.skills | length > 0 and all(.name and .kind)' "$LOCK" >/dev/null \
  || { echo "FAIL: every lock entry needs name+kind"; exit 1; }
jq -e '[.skills[] | select(.kind=="git")] | all(.source and .ref and .target)' "$LOCK" >/dev/null \
  || { echo "FAIL: git entries need source+ref+target"; exit 1; }
jq -e '[.skills[] | select(.kind=="npm")] | all(.source and .ref and .check)' "$LOCK" >/dev/null \
  || { echo "FAIL: npm entries need source+ref+check"; exit 1; }
jq -e '[.skills[] | select(.kind=="marketplace")] | all(.install and .plugin_id and .ref)' "$LOCK" >/dev/null \
  || { echo "FAIL: marketplace entries need install+plugin_id+ref"; exit 1; }
echo "PASS: skills-lock.json schema valid"

# Case 3: bootstrap --check in an empty HOME reports missing without changing
# anything, and exits nonzero (drift signal). Vendored entries stay OK.
cp "$ROOT/dev/bootstrap-team.sh" "$TMP/"
jq '{comment, skills: [.skills[] | select(.kind=="vendored" or .kind=="marketplace")]}' \
  "$LOCK" > "$TMP/skills-lock.json"
set +e
OUT=$(cd "$TMP" && HOME="$TMP/fakehome" bash bootstrap-team.sh --check 2>&1)
RC=$?
set -e
[[ "$RC" != "0" ]] || { echo "FAIL: --check with missing marketplace plugins should exit nonzero"; exit 1; }
[[ "$OUT" == *"OK   office-hours"* ]] || { echo "FAIL: vendored entry should be OK, got: $OUT"; exit 1; }
[[ "$OUT" == *"MISS superpowers"* ]] || { echo "FAIL: missing marketplace should be MISS, got: $OUT"; exit 1; }
[[ ! -d "$TMP/fakehome/.claude" ]] || { echo "FAIL: --check must not create anything"; exit 1; }
echo "PASS: bootstrap-team --check reports without mutating"

# Case 4: outcome-report aggregates a fixture ledger correctly.
git init -q "$TMP/repo"
GITREPO=$(git -C "$TMP/repo" rev-parse --show-toplevel)   # macOS: /var vs /private/var
NOW=$(date +%s)
for r in pass pass blocked; do
  jq -cn --argjson ts "$NOW" --arg repo "$GITREPO" --arg r "$r" --arg u "dev1" \
    '{ts:$ts, session:"s", repo:$repo, result:$r, user:$u}'
done > "$TMP/repo/ledger.jsonl"
REPORT=$(cd "$TMP/repo" && bash "$ROOT/dev/outcome-report.sh" ledger.jsonl)
echo "$REPORT" | jq -e 'select(.total) | .total==3 and .pass==2 and .blocked==1 and .first_pass_verified_rate==66' >/dev/null 2>&1 \
  || RATE_OK=0
# jq -e over multi-doc output: validate first doc explicitly instead.
FIRST=$(echo "$REPORT" | sed -n '/^{/,/^}/p' | jq -s '.[0]')
[[ "$(echo "$FIRST" | jq '.total')" == "3" && "$(echo "$FIRST" | jq '.pass')" == "2" ]] \
  || { echo "FAIL: outcome-report totals wrong: $FIRST"; exit 1; }
[[ "$(echo "$FIRST" | jq '.first_pass_verified_rate')" == "66" ]] \
  || { echo "FAIL: rate wrong: $FIRST"; exit 1; }
echo "$REPORT" | grep -q "per user" || { echo "FAIL: per-user breakdown missing"; exit 1; }
echo "PASS: outcome-report aggregates pass/blocked and per-user"

echo "ALL team-tooling tests passed."
