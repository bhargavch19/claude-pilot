#!/usr/bin/env bash
# Pilot routing eval — scores the deterministic route-advisor against a golden
# set of labeled prompts.
#
# Scoring is binary 0/1 per case (research: binary pass/fail beats 0.0–1.0) and
# criteria-based, not LLM-judged: a case passes iff the expected skill token
# appears in the computed route, or — for NONE — the advisor stays silent. The
# advisor is deterministic, so a correct golden set should score 100%; a drop
# is a real routing regression.
#
# Usage: bash dev/eval-routes.sh [golden.tsv]
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The golden set lives at the repo root (tests/), two levels above the
# pilot plugin dir (plugins/pilot/).
GOLDEN="${1:-$(cd "$ROOT/../.." && pwd)/tests/eval/golden_routes.tsv}"
ADVISOR="$ROOT/hooks/route-advisor.sh"
[ -f "$GOLDEN" ] || { echo "eval: golden set not found: $GOLDEN" >&2; exit 2; }
[ -x "$ADVISOR" ] || { echo "eval: route-advisor not executable: $ADVISOR" >&2; exit 2; }

# Isolate from real bypass markers and pin the registry to this repo. Run each
# case from an empty dir so project-state spine (.planning/.paul) never fires.
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
export XDG_CACHE_HOME="$WORK/cache"; mkdir -p "$XDG_CACHE_HOME/pilot"
export CLAUDE_PLUGIN_ROOT="$ROOT"

pass=0; total=0; fails=""
while IFS=$'\t' read -r prompt expected || [ -n "$prompt" ]; do
  case "$prompt" in ''|'#'*) continue ;; esac
  [ -n "${expected:-}" ] || continue
  total=$((total + 1))
  input=$(jq -cn --arg p "$prompt" '{prompt:$p}')
  out=$( cd "$WORK" && printf '%s' "$input" | "$ADVISOR" 2>/dev/null )
  ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)
  ok=0
  if [ "$expected" = "NONE" ]; then
    [ -z "$ctx" ] && ok=1
  else
    printf '%s' "$ctx" | grep -Fq "\`$expected\`" && ok=1
  fi
  if [ "$ok" = "1" ]; then
    pass=$((pass + 1))
  else
    fails="$fails"$'\n'"  ✗ [$prompt] expected=$expected got=[${ctx:-<silent>}]"
  fi
done < "$GOLDEN"

acc=0
[ "$total" -gt 0 ] && acc=$(( pass * 100 / total ))
echo "pilot routing eval: $pass/$total correct (${acc}%)"
[ -n "$fails" ] && printf '%s\n' "$fails" >&2
[ "$pass" = "$total" ]
