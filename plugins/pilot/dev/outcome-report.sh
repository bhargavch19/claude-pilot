#!/usr/bin/env bash
# Outcome report: aggregate the verify-gate outcome ledger(s) into the numbers
# that tell you whether pilot is helping — first-pass-verified rate, block
# rate, and (team ledger) per-user breakdown. This is the measurement half of
# docs/ab-method.md: run it over pilot-on vs pilot-off periods and compare.
#
# Usage:
#   dev/outcome-report.sh                 # this repo: team ledger if present, else local cache
#   dev/outcome-report.sh <ledger.jsonl>  # explicit ledger file
#   dev/outcome-report.sh --days 14       # restrict to a window
set -euo pipefail

command -v jq >/dev/null || { echo "outcome-report: jq is required"; exit 1; }

DAYS=0; LEDGER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --days) DAYS="${2:-0}"; shift 2 ;;
    *) LEDGER="$1"; shift ;;
  esac
done

REPO=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
if [[ -z "$LEDGER" ]]; then
  if [[ -f "$REPO/.pilot/outcomes.jsonl" ]]; then
    LEDGER="$REPO/.pilot/outcomes.jsonl"; SCOPE="team (repo ledger)"
  else
    LEDGER="${XDG_CACHE_HOME:-$HOME/.cache}/pilot/outcomes.jsonl"; SCOPE="local (this machine)"
  fi
else
  SCOPE="explicit"
fi
[[ -f "$LEDGER" ]] || { echo "outcome-report: no ledger at $LEDGER"; exit 1; }

CUTOFF=0
if [[ "$DAYS" =~ ^[1-9][0-9]*$ ]]; then
  NOW=$(date +%s); CUTOFF=$((NOW - DAYS * 86400))
fi

jq -s --arg repo "$REPO" --argjson cutoff "$CUTOFF" --arg scope "$SCOPE" '
  map(select(.repo == $repo and (.ts >= $cutoff)))
  | {scope: $scope,
     total: length,
     pass:    map(select(.result=="pass"))    | length,
     blocked: map(select(.result=="blocked")) | length,
     warn:    map(select(.result=="warn"))    | length}
  | .first_pass_verified_rate =
      (if .total > 0 then ((.pass / .total * 100) | floor) else null end)
' "$LEDGER"

# Per-user breakdown when the ledger carries user fields (team mode).
if jq -e -s 'map(select(.user // "" | length > 0)) | length > 0' "$LEDGER" >/dev/null 2>&1; then
  echo "--- per user ---"
  jq -s --arg repo "$REPO" --argjson cutoff "$CUTOFF" '
    map(select(.repo == $repo and (.ts >= $cutoff) and ((.user // "") != "")))
    | group_by(.user)
    | map({user: .[0].user, total: length,
           pass: map(select(.result=="pass")) | length,
           blocked: map(select(.result=="blocked")) | length})
  ' "$LEDGER"
fi
