#!/usr/bin/env bash
# Test autopilot-gate.sh: BLOCKS a Stop while an autopilot cycle is active and
# mid-phase; ALLOWS checkpoint/terminal states, honors bypass markers and
# .pilot.json {"autopilot":{"gate":...}}, anti-traps after 3 same-state blocks,
# and resets its counter when the phase advances.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/autopilot-gate.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
cd "$TMP"

export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$XDG_CACHE_HOME/pilot"
CNT="$XDG_CACHE_HOME/pilot/autopilot-gate-blocks"
RESET() { rm -f "$CNT" "$XDG_CACHE_HOME"/pilot/bypass-session \
                 "$XDG_CACHE_HOME"/pilot/off-rails .pilot.json; }

mk_input() { jq -n '{session_id:"sess-test", stop_hook_active:true}'; }
mk_cycle() { # $1=status  [$2=current_phase (default build)]
  mkdir -p .pilot
  jq -n --arg st "$1" --arg ph "${2:-build}" '{
    version:1, id:"cyc-test-0001", requirement:"test req", spine:"superpowers",
    status:$st, current_phase:$ph, fix_rounds:0, max_fix_rounds:3,
    phases:[{id:"build",skill:"tdd",status:"active"},
            {id:"verify",skill:"verify",status:"pending"},
            {id:"ship",skill:"gsd-ship",status:"pending"}],
    checkpoints:{plan_approved:true, plan_approved_at:"t", ship_approved:false, ship_approved_at:null}
  }' > .pilot/cycle.json
}

# Case 1: no cycle.json → silent allow.
RESET; rm -rf .pilot
OUT=$(mk_input | "$HOOK" 2>&1 || true)
[[ -z "$OUT" ]] || { echo "FAIL: no cycle should be silent, got: $OUT"; exit 1; }
echo "PASS: no cycle.json is silent"

# Case 2: invalid JSON cycle → allow with stderr diagnostic (fail-open).
RESET; mkdir -p .pilot; echo "{broken" > .pilot/cycle.json
OUT=$(mk_input | "$HOOK" 2>&1 || true)
[[ "$OUT" == *"not valid JSON"* ]] || { echo "FAIL: invalid cycle should warn on stderr"; exit 1; }
[[ "$OUT" != *'"decision"'* ]] || { echo "FAIL: invalid cycle must not block"; exit 1; }
echo "PASS: invalid cycle.json fails open with a diagnostic"

# Case 3: active mid-phase status → block, reason cites id + phase + next.
RESET; mk_cycle executing build
OUT=$(mk_input | "$HOOK" 2>/dev/null || true)
[[ "$OUT" == *'"decision":"block"'* ]] || { echo "FAIL: executing must block, got: $OUT"; exit 1; }
[[ "$OUT" == *"cyc-test-0001"* && "$OUT" == *"phase=build"* && "$OUT" == *"next: verify"* ]] \
  || { echo "FAIL: block reason must cite cycle id, phase, next; got: $OUT"; exit 1; }
echo "PASS: mid-phase stop is blocked with id/phase/next in the reason"

# Case 4+5: checkpoint states → allow.
for st in awaiting_plan_approval awaiting_ship_approval; do
  RESET; mk_cycle "$st"
  OUT=$(mk_input | "$HOOK" 2>&1 || true)
  [[ -z "$OUT" ]] || { echo "FAIL: $st must be an allow-state, got: $OUT"; exit 1; }
  echo "PASS: $st allows the stop (checkpoint)"
done

# Case 6: terminal states → allow.
for st in done halted aborted; do
  RESET; mk_cycle "$st"
  OUT=$(mk_input | "$HOOK" 2>&1 || true)
  [[ -z "$OUT" ]] || { echo "FAIL: $st must be an allow-state, got: $OUT"; exit 1; }
done
echo "PASS: done/halted/aborted allow the stop (terminal)"

# Case 7: bypass-session marker → warn (stderr), never block.
RESET; mk_cycle executing; touch "$XDG_CACHE_HOME/pilot/bypass-session"
OUT=$(mk_input | "$HOOK" 2>&1 || true)
[[ "$OUT" == *"autopilot-gate"* ]] || { echo "FAIL: bypass should still warn"; exit 1; }
[[ "$OUT" != *'"decision"'* ]] || { echo "FAIL: bypass must not block"; exit 1; }
echo "PASS: bypass marker downgrades to warn"

# Case 8: off-rails marker → warn, never block.
RESET; mk_cycle executing; touch "$XDG_CACHE_HOME/pilot/off-rails"
OUT=$(mk_input | "$HOOK" 2>&1 || true)
[[ "$OUT" != *'"decision"'* ]] || { echo "FAIL: off-rails must not block"; exit 1; }
echo "PASS: off-rails downgrades to warn"

# Case 9: .pilot.json gate:warn → warn; gate:off → fully silent.
RESET; mk_cycle executing; echo '{"autopilot":{"gate":"warn"}}' > .pilot.json
OUT=$(mk_input | "$HOOK" 2>&1 || true)
[[ "$OUT" == *"autopilot-gate"* && "$OUT" != *'"decision"'* ]] \
  || { echo "FAIL: gate:warn should warn without blocking, got: $OUT"; exit 1; }
echo '{"autopilot":{"gate":"off"}}' > .pilot.json
OUT=$(mk_input | "$HOOK" 2>&1 || true)
[[ -z "$OUT" ]] || { echo "FAIL: gate:off should be silent, got: $OUT"; exit 1; }
echo "PASS: .pilot.json gate warn/off respected"

# Case 10: anti-trap — 3 consecutive blocks on the same status/phase → 4th warns.
RESET; mk_cycle executing build
for i in 1 2 3; do
  OUT=$(mk_input | "$HOOK" 2>/dev/null || true)
  [[ "$OUT" == *'"decision":"block"'* ]] || { echo "FAIL: block $i expected"; exit 1; }
done
OUT=$(mk_input | "$HOOK" 2>&1 || true)
[[ "$OUT" != *'"decision"'* && "$OUT" == *"autopilot-gate"* ]] \
  || { echo "FAIL: 4th same-state stop must warn not block, got: $OUT"; exit 1; }
echo "PASS: anti-trap releases after 3 consecutive same-state blocks"

# Case 11: counter resets when the phase changes between stops.
RESET; mk_cycle executing build
mk_input | "$HOOK" >/dev/null 2>&1 || true
mk_input | "$HOOK" >/dev/null 2>&1 || true
mk_input | "$HOOK" >/dev/null 2>&1 || true          # 3 blocks on build
mk_cycle verifying verify                            # phase advanced
OUT=$(mk_input | "$HOOK" 2>/dev/null || true)
[[ "$OUT" == *'"decision":"block"'* ]] \
  || { echo "FAIL: fresh phase must block again (counter reset), got: $OUT"; exit 1; }
echo "PASS: counter resets on phase change"

# Case 12: cycle.json at git root honored from a subdirectory.
RESET
git init -q repo12 && cd repo12
mk_cycle executing build
mkdir -p sub && cd sub
OUT=$(mk_input | "$HOOK" 2>/dev/null || true)
[[ "$OUT" == *'"decision":"block"'* ]] \
  || { echo "FAIL: git-root cycle.json should be found from subdir, got: $OUT"; exit 1; }
cd "$TMP"; rm -rf repo12
echo "PASS: git-root cycle.json resolved from a subdirectory"

# Case 13: coexistence — verify-gate and autopilot-gate keep separate counters.
RESET; mk_cycle executing build
mk_input | "$HOOK" >/dev/null 2>&1 || true           # autopilot counter = 1
[[ -f "$CNT" ]] || { echo "FAIL: autopilot counter file expected"; exit 1; }
VG_CNT="$XDG_CACHE_HOME/pilot/verify-gate-blocks"
[[ ! -f "$VG_CNT" ]] || { echo "FAIL: autopilot-gate must not touch verify-gate's counter"; exit 1; }
grep -q "executing/build" "$CNT" || { echo "FAIL: counter keyed on status/phase"; exit 1; }
echo "PASS: counters are independent of verify-gate"

# Case 14: branch-scoped cycle file (.pilot/cycles/<slug>.json) is found and
# takes precedence; a cycle for a DIFFERENT branch stays invisible.
RESET
git init -q repo14 && cd repo14
git checkout -q -b feat/dark-mode 2>/dev/null || git switch -qc feat/dark-mode
mkdir -p .pilot/cycles
jq -n '{version:1, id:"cyc-branch-a", status:"executing", current_phase:"build",
        phases:[{id:"verify",skill:"verify",status:"pending"}]}' \
  > .pilot/cycles/feat-dark-mode.json
OUT=$(mk_input | "$HOOK" 2>/dev/null || true)
[[ "$OUT" == *'"decision":"block"'* && "$OUT" == *"cyc-branch-a"* ]] \
  || { echo "FAIL: branch-scoped cycle should block on its own branch, got: $OUT"; exit 1; }
rm -f "$CNT"
git checkout -q -b other/branch 2>/dev/null || git switch -qc other/branch
OUT=$(mk_input | "$HOOK" 2>&1 || true)
[[ -z "$OUT" ]] || { echo "FAIL: another branch's cycle must be invisible, got: $OUT"; exit 1; }
cd "$TMP"; rm -rf repo14
echo "PASS: cycle state is branch-scoped (own branch blocks, other branch silent)"

# Case 15: approval witness — plan_approved=true but NO witnessed marker →
# block reason calls out the self-approval; with the marker → no callout;
# with approval_witness off → no callout.
RESET; mk_cycle executing build      # mk_cycle sets plan_approved:true
OUT=$(mk_input | "$HOOK" 2>/dev/null || true)
[[ "$OUT" == *"WITNESS"* && "$OUT" == *"awaiting_plan_approval"* ]] \
  || { echo "FAIL: unwitnessed approval should be called out, got: $OUT"; exit 1; }
echo "PASS: unwitnessed checkpoint approval is called out"

RESET; mk_cycle executing build
mkdir -p "$XDG_CACHE_HOME/pilot/approvals"
date -u +%FT%TZ > "$XDG_CACHE_HOME/pilot/approvals/cyc-test-0001.plan"
OUT=$(mk_input | "$HOOK" 2>/dev/null || true)
[[ "$OUT" == *'"decision":"block"'* && "$OUT" != *"WITNESS"* ]] \
  || { echo "FAIL: witnessed approval should not be called out, got: $OUT"; exit 1; }
rm -rf "$XDG_CACHE_HOME/pilot/approvals"
echo "PASS: witnessed approval passes the integrity check"

RESET; mk_cycle executing build
echo '{"autopilot":{"approval_witness":"off"}}' > .pilot.json
OUT=$(mk_input | "$HOOK" 2>/dev/null || true)
[[ "$OUT" == *'"decision":"block"'* && "$OUT" != *"WITNESS"* ]] \
  || { echo "FAIL: approval_witness=off should suppress the callout, got: $OUT"; exit 1; }
rm -f .pilot.json
echo "PASS: approval_witness=off suppresses the integrity check"

echo "ALL autopilot-gate tests passed."
