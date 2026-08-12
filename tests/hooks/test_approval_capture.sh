#!/usr/bin/env bash
# Test approval-capture.sh (UserPromptSubmit): witnesses REAL user approval for
# a waiting autopilot checkpoint — and nothing else. Conservative matching,
# marker keyed to cycle id + gate, silent no-ops everywhere else.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/approval-capture.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
cd "$TMP"

export XDG_CACHE_HOME="$TMP/cache"
APPROVALS="$XDG_CACHE_HOME/pilot/approvals"

mk_cycle() { # $1=status
  mkdir -p .pilot
  jq -n --arg st "$1" '{version:1, id:"cyc-wit-0001", status:$st, current_phase:"plan",
    phases:[{id:"plan",skill:"x",status:"active"}]}' > .pilot/cycle.json
}
run() { jq -n --arg p "$1" '{prompt:$p, session_id:"s"}' | "$HOOK" 2>&1 || true; }
RESET() { rm -rf "$APPROVALS" .pilot; }

# Case 1: approving prompt at plan checkpoint → marker + context.
RESET; mk_cycle awaiting_plan_approval
OUT=$(run "approved")
[[ -f "$APPROVALS/cyc-wit-0001.plan" ]] || { echo "FAIL: plan marker not written"; exit 1; }
[[ "$OUT" == *"approval witnessed"* ]] || { echo "FAIL: expected witness context, got: $OUT"; exit 1; }
echo "PASS: 'approved' at plan checkpoint writes the witness marker"

# Case 2: variants that should count (prompt-initial).
for p in "Approve" "yes, go ahead" "go" "ship it" "LGTM" "proceed with the plan"; do
  RESET; mk_cycle awaiting_plan_approval
  run "$p" > /dev/null
  [[ -f "$APPROVALS/cyc-wit-0001.plan" ]] || { echo "FAIL: '$p' should witness"; exit 1; }
done
echo "PASS: prompt-initial approval variants witness"

# Case 3: approval words mid-sentence do NOT count (no self-poisoning).
for p in "the plan was approved by legal last week" "I have not approved this" "what does approved mean here"; do
  RESET; mk_cycle awaiting_plan_approval
  run "$p" > /dev/null
  [[ ! -f "$APPROVALS/cyc-wit-0001.plan" ]] || { echo "FAIL: '$p' must not witness"; exit 1; }
done
echo "PASS: mid-sentence / negated approval words ignored"

# Case 4: not at a checkpoint → no marker even for "approved".
RESET; mk_cycle executing
run "approved" > /dev/null
[[ ! -d "$APPROVALS" || -z "$(ls -A "$APPROVALS" 2>/dev/null)" ]] \
  || { echo "FAIL: non-checkpoint status must not witness"; exit 1; }
echo "PASS: no witnessing outside checkpoint states"

# Case 5: ship checkpoint writes the .ship marker.
RESET; mk_cycle awaiting_ship_approval
run "yes" > /dev/null
[[ -f "$APPROVALS/cyc-wit-0001.ship" ]] || { echo "FAIL: ship marker not written"; exit 1; }
echo "PASS: ship checkpoint writes the ship marker"

# Case 6: no cycle file → silent no-op.
RESET
OUT=$(run "approved")
[[ -z "$OUT" ]] || { echo "FAIL: no cycle should be silent, got: $OUT"; exit 1; }
echo "PASS: silent without a cycle"

echo "ALL approval-capture tests passed."
