#!/usr/bin/env bash
# G16 enforcement: while an autopilot cycle (.pilot/cycle.json) is active and
# not at a checkpoint or terminal state, BLOCK the Stop and tell the model to
# advance the cycle per skills/pilot/autopilot.md. Checkpoint states
# (awaiting_plan_approval / awaiting_ship_approval) and terminal states
# (done / halted / aborted) are allow-states — that is how the conductor can
# stop to ask for approval or deliver a halt report.
#
# Runs on Stop ONLY (not SubagentStop — delegated subagents must be able to
# finish their slice). Composes with verify-gate.sh: verify-gate owns "done"
# claims need test evidence; this hook owns "keep the cycle moving". The two
# block reasons are complementary, never contradictory.
#
# Safety rails (cannot trap the user):
#   - Honors pilot bypass markers ($CACHE/bypass*, $CACHE/off-rails) → warn.
#   - Per-repo config: .pilot.json { "autopilot": { "gate": "warn"|"off" } }.
#   - Anti-trap: 3 consecutive blocks on the SAME status/phase → warn. Any
#     status or phase change resets the counter.
set -euo pipefail

INPUT=$(cat)

if [[ -z "$INPUT" ]] || ! printf '%s' "$INPUT" | jq empty 2>/dev/null; then
  echo "autopilot-gate: stdin missing or not valid JSON — gate declining to enforce." >&2
  exit 0
fi

# Resolve the cycle file. Branch-scoped first (.pilot/cycles/<branch-slug>.json
# — two devs on different branches of one repo never fight over cycle state),
# then the legacy single-cycle path (.pilot/cycle.json). Each checked in cwd
# then the git root — same idiom as verify-gate's .pilot.json lookup.
GITROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
# symbolic-ref works before the first commit; rev-parse covers detached HEAD.
BRANCH=$(git symbolic-ref --short -q HEAD 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
SLUG=$(printf '%s' "$BRANCH" | tr '/' '-' | tr -cd 'a-zA-Z0-9._-')
CYCLE=""
for c in \
  ${SLUG:+".pilot/cycles/$SLUG.json"} \
  ${SLUG:+"${GITROOT:+$GITROOT/.pilot/cycles/$SLUG.json}"} \
  ".pilot/cycle.json" \
  "${GITROOT:+$GITROOT/.pilot/cycle.json}"; do
  [[ -n "$c" && -f "$c" ]] && { CYCLE="$c"; break; }
done
[[ -n "$CYCLE" ]] || exit 0

if ! jq empty "$CYCLE" 2>/dev/null; then
  echo "autopilot-gate: $CYCLE is not valid JSON — cycle treated as inactive." >&2
  exit 0
fi

STATUS=$(jq -r '.status // empty' "$CYCLE" 2>/dev/null || true)
case "$STATUS" in
  awaiting_plan_approval|awaiting_ship_approval|halted|done|aborted|"") exit 0 ;;
esac

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pilot"
CNT_FILE="$CACHE_DIR/autopilot-gate-blocks"
mkdir -p "$CACHE_DIR" 2>/dev/null || true

# Per-repo config: .pilot.json { "autopilot": { "gate": "warn" | "off" } }.
PILOT_JSON=""
if [[ -f .pilot.json ]]; then
  PILOT_JSON=".pilot.json"
elif [[ -n "$GITROOT" && -f "$GITROOT/.pilot.json" ]]; then
  PILOT_JSON="$GITROOT/.pilot.json"
fi
AP_MODE=""
[[ -n "$PILOT_JSON" ]] && AP_MODE=$(jq -r '.autopilot.gate // empty' "$PILOT_JSON" 2>/dev/null || true)
[[ "$AP_MODE" == "off" ]] && exit 0

MODE="block"
[[ "$AP_MODE" == "warn" ]] && MODE="warn"

# Session-wide bypass markers (pilot off / off-rails) soften block → warn.
if compgen -G "$CACHE_DIR/bypass*" >/dev/null 2>&1 || [[ -e "$CACHE_DIR/off-rails" ]]; then
  MODE="warn"
fi

ID=$(jq -r '.id // "?"' "$CYCLE" 2>/dev/null || echo "?")
PHASE=$(jq -r '.current_phase // "?"' "$CYCLE" 2>/dev/null || echo "?")
NEXT=$(jq -r '[.phases[]? | select(.status=="pending") | .id] | first // empty' "$CYCLE" 2>/dev/null || true)

# Anti-trap: counter keyed on status/phase; a change of either resets it, and
# 3 consecutive blocks on the same key downgrade to warn so the gate can never
# loop even if the model stops updating cycle.json.
KEY="$STATUS/$PHASE"
CNT=0
if [[ -f "$CNT_FILE" ]]; then
  STORED_KEY=$(cut -d' ' -f1 "$CNT_FILE" 2>/dev/null || true)
  STORED_CNT=$(cut -d' ' -f2 "$CNT_FILE" 2>/dev/null || echo 0)
  [[ "$STORED_CNT" =~ ^[0-9]+$ ]] || STORED_CNT=0
  [[ "$STORED_KEY" == "$KEY" ]] && CNT=$STORED_CNT
fi
if [[ "$MODE" == "block" && "$CNT" -ge 3 ]]; then
  MODE="warn"
fi

MSG="autopilot-gate: G16 — cycle $ID is active (status=$STATUS, phase=$PHASE). Do not stop: advance the cycle (next: ${NEXT:-finish $PHASE}) per skills/pilot/autopilot.md, updating .pilot/cycle.json at each transition. If you are pausing for a checkpoint, first set status=awaiting_plan_approval or awaiting_ship_approval. If the cycle is stuck, set status=halted with a halt_reason and deliver the halt report. To abort: user says \"autopilot off\" → set status=aborted."

# Approval witness (G16 integrity): a checkpoint flag in cycle.json only counts
# when approval-capture.sh witnessed it from REAL user input (marker file the
# model cannot synthesize). A flag without a marker = self-approval → say so.
# Disable per repo: .pilot.json { "autopilot": { "approval_witness": "off" } }.
WITNESS=""
[[ -n "$PILOT_JSON" ]] && WITNESS=$(jq -r '.autopilot.approval_witness // empty' "$PILOT_JSON" 2>/dev/null || true)
if [[ "$WITNESS" != "off" ]]; then
  APPROVALS="${XDG_CACHE_HOME:-$HOME/.cache}/pilot/approvals"
  need=""
  case "$STATUS" in
    executing|verifying|fixing|reviewing) need="plan" ;;
    shipping|capturing)                   need="ship" ;;
  esac
  if [[ -n "$need" ]]; then
    FLAG=$(jq -r ".checkpoints.${need}_approved // false" "$CYCLE" 2>/dev/null || echo false)
    if [[ "$FLAG" == "true" && ! -f "$APPROVALS/$ID.$need" ]]; then
      MSG="$MSG WITNESS: ${need}_approved=true but no user approval was witnessed for cycle $ID (approval-capture saw no approving user prompt). Do not proceed past this checkpoint — set status=awaiting_${need}_approval, re-present the ask, and have the user reply 'approved' (or run /pilot-approve)."
    fi
  fi
fi

if [[ "$MODE" == "block" ]]; then
  echo "$KEY $((CNT + 1))" > "$CNT_FILE" 2>/dev/null || true
  jq -cn --arg r "$MSG" '{decision:"block", reason:$r}'
  exit 0
fi

: > "$CNT_FILE" 2>/dev/null || true       # warn path → reset counter
echo "$MSG" >&2
exit 0
