#!/usr/bin/env bash
# G16 approval witness (UserPromptSubmit): when an autopilot cycle is waiting
# at a checkpoint and the USER's prompt approves it, record a witness marker.
# This is the un-fakeable half of checkpoint integrity: UserPromptSubmit input
# is real user text — the model cannot synthesize this event, so a marker here
# proves a human said yes. autopilot-gate.sh cross-checks cycle.json's
# checkpoint flags against these markers and calls out self-approval.
#
# Conservative by design: only clear, prompt-initial approval phrases count.
# Anything fuzzier → no marker; the conductor re-asks for an explicit
# "approved" (or /pilot-approve). Never blocks, always exit 0.
set -euo pipefail

INPUT=$(cat)
printf '%s' "$INPUT" | jq empty 2>/dev/null || exit 0
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
[[ -n "$PROMPT" ]] || exit 0

# Cheap pre-filter before any git/file work.
printf '%s' "$PROMPT" | grep -iqE '^[[:space:]]*(approved?|yes|go|ship it|lgtm|proceed)([[:space:].,!]|$)' || exit 0

# Resolve the cycle file (same branch-scoped-then-legacy logic as the gate).
GITROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
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
jq empty "$CYCLE" 2>/dev/null || exit 0

STATUS=$(jq -r '.status // empty' "$CYCLE" 2>/dev/null || true)
case "$STATUS" in
  awaiting_plan_approval) GATE="plan" ;;
  awaiting_ship_approval) GATE="ship" ;;
  *) exit 0 ;;
esac

ID=$(jq -r '.id // empty' "$CYCLE" 2>/dev/null || true)
[[ -n "$ID" ]] || exit 0

APPROVALS="${XDG_CACHE_HOME:-$HOME/.cache}/pilot/approvals"
mkdir -p "$APPROVALS" 2>/dev/null || true
date -u +%FT%TZ > "$APPROVALS/$ID.$GATE" 2>/dev/null || exit 0

jq -cn --arg c "approval-capture: user approval witnessed for cycle $ID ($GATE checkpoint) — the conductor may now set ${GATE}_approved=true and advance." \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$c}}'
exit 0
