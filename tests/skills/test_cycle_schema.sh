#!/usr/bin/env bash
# Validate the .pilot/cycle.json contract documented in skills/pilot/autopilot.md:
# the schema example round-trips, the enums are closed sets, and the jq edit
# idioms the driver prescribes (status flip, fix_rounds bump, checkpoint stamp)
# produce valid state.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPEC="$ROOT/skills/pilot/autopilot.md"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
cd "$TMP"

STATUSES="framing planning awaiting_plan_approval executing verifying fixing reviewing awaiting_ship_approval shipping capturing done halted aborted"
PHASE_STATUSES="pending active done failed"

# Case 1: the driver spec documents every status in the enum (and no drift).
for st in $STATUSES; do
  grep -q "$st" "$SPEC" || { echo "FAIL: status '$st' missing from autopilot.md"; exit 1; }
done
echo "PASS: autopilot.md documents the full status enum"

# Case 2: a canonical cycle document round-trips through jq intact.
jq -n '{
  version:1, id:"cyc-20260720-0001", requirement:"add dark mode",
  spine:"superpowers", status:"framing",
  phases:[{id:"frame",skill:"grill-with-docs",status:"pending"},
          {id:"plan",skill:"superpowers:writing-plans",status:"pending"},
          {id:"build",skill:"tdd",status:"pending"},
          {id:"verify",skill:"verify",status:"pending"},
          {id:"review",skill:"superpowers:requesting-code-review",status:"pending"},
          {id:"ship",skill:"superpowers:finishing-a-development-branch",status:"pending"},
          {id:"capture",skill:"graphify",status:"pending"}],
  current_phase:"frame", fix_rounds:0, max_fix_rounds:3,
  checkpoints:{plan_approved:false, plan_approved_at:null,
               ship_approved:false, ship_approved_at:null},
  artifacts:{plan:null, acceptance:".pilot/acceptance.md", pr:null},
  halt_reason:null, created:"2026-07-20T00:00:00Z",
  updated:"2026-07-20T00:00:00Z", session_last:"abcd1234"
}' > cycle.json
jq empty cycle.json || { echo "FAIL: canonical cycle.json invalid"; exit 1; }
N=$(jq '.phases | length' cycle.json)
[[ "$N" == "7" ]] || { echo "FAIL: expected 7 phases, got $N"; exit 1; }
echo "PASS: canonical cycle.json round-trips"

# Case 3: every phases[].status stays inside its enum.
BAD=$(jq -r --arg ok "$PHASE_STATUSES" \
  '[.phases[].status as $s | select(((" "+$ok+" ") | contains(" "+$s+" ")) | not)] | length' cycle.json)
[[ "$BAD" == "0" ]] || { echo "FAIL: phase status outside enum"; exit 1; }
echo "PASS: phase statuses within enum"

# Case 4: the driver's transition idioms produce valid state.
#   status flip + phase activation (frame → planning)
jq '.status="planning" | .current_phase="plan"
    | (.phases[] | select(.id=="frame") | .status)="done"
    | (.phases[] | select(.id=="plan") | .status)="active"
    | .updated="2026-07-20T00:01:00Z"' cycle.json > c2.json
[[ $(jq -r '.status' c2.json) == "planning" ]] || { echo "FAIL: status flip"; exit 1; }
[[ $(jq -r '.phases[0].status' c2.json) == "done" ]] || { echo "FAIL: phase done flip"; exit 1; }
#   fix_rounds bump + halt on exhaustion
jq '.fix_rounds+=1' c2.json > c3.json
[[ $(jq -r '.fix_rounds' c3.json) == "1" ]] || { echo "FAIL: fix_rounds bump"; exit 1; }
jq 'if .fix_rounds > .max_fix_rounds then .status="halted" | .halt_reason="fix rounds exhausted" else . end' \
  c3.json > c4.json
[[ $(jq -r '.status' c4.json) == "planning" ]] || { echo "FAIL: premature halt"; exit 1; }
#   checkpoint stamp
jq '.checkpoints.plan_approved=true | .checkpoints.plan_approved_at="2026-07-20T00:02:00Z"
    | .status="executing"' c4.json > c5.json
[[ $(jq -r '.checkpoints.plan_approved' c5.json) == "true" ]] || { echo "FAIL: checkpoint stamp"; exit 1; }
echo "PASS: driver transition idioms produce valid state"

# Case 5: allow-states named in the hook match the spec's allow-state list.
HOOK="$ROOT/hooks/autopilot-gate.sh"
for st in awaiting_plan_approval awaiting_ship_approval halted done aborted; do
  grep -q "$st" "$HOOK" || { echo "FAIL: allow-state '$st' missing from autopilot-gate.sh"; exit 1; }
done
echo "PASS: hook allow-states match the spec"

echo "ALL cycle-schema tests passed."
