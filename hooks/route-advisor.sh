#!/usr/bin/env bash
# Pilot deterministic route advisor — UserPromptSubmit hook.
#
# Moves the *unambiguous* part of routing out of the model's hands and into
# code: it runs on every prompt and injects a code-computed route directive
# for the two cases where determinism is achievable and safe:
#
#   1. Literal skill names — but ONLY distinctive ones (hyphen/colon/digit, or
#      a tiny safe allowlist). Common-English skill names like "review"/"run"/
#      "verify" are deliberately NOT hard-routed — those are left to the model,
#      because "review this" is a sentence, not necessarily the Review skill.
#   2. Project-state spine — .planning/ → GSD, .paul/ → PAUL.
#
# Everything fuzzy is left to the model (no keyword scoring here). Stays silent
# when nothing matches. Honors pilot bypass markers. Never blocks (exit 0).
set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
printf '%s' "$INPUT" | jq empty >/dev/null 2>&1 || exit 0
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
[ -n "$PROMPT" ] || exit 0

# Bypass markers (pilot off / off-rails) → stay out of the way.
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pilot"
if compgen -G "$CACHE_DIR/bypass*" >/dev/null 2>&1 || [ -e "$CACHE_DIR/off-rails" ]; then
  exit 0
fi

# Locate the registry (single source of truth for the skill vocabulary).
ROOT="${CLAUDE_PLUGIN_ROOT:-}"
[ -n "$ROOT" ] || ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REG="$ROOT/skills/pilot/registry.md"
[ -f "$REG" ] || exit 0

PROMPT_LC=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Distinctive single-word skill names that are safe to hard-route on even
# without a hyphen/colon/digit (not English words).
SAFE_SINGLE=" tdd graphify caveman playwright "

seen=" "
chain=""
nchain=0

# phase<TAB>skill for every Primary+Fallback backticked token, in registry order.
while IFS="$(printf '\t')" read -r phase tok; do
  [ -n "$tok" ] || continue
  [ "$tok" = "gh" ] && continue            # CLI, not a skill
  case "$seen" in *" $tok "*) continue ;; esac

  # Match the token or its bare (post-colon) alias as a whole word — but only
  # count an alias that is itself distinctive (has - : or digit, or is in the
  # safe allowlist). This stops a namespaced command's bare alias from
  # reintroducing a common-word collision (e.g. paul:init → bare "init", which
  # must NOT hard-route — but the literal "paul:init" still does).
  matched=0
  for a in "$tok" "${tok#*:}"; do
    elig=0
    case "$a" in *[-:0-9]*) elig=1 ;; esac
    case "$SAFE_SINGLE" in *" $a "*) elig=1 ;; esac
    [ "$elig" = "1" ] || continue
    a_lc=$(printf '%s' "$a" | tr '[:upper:]' '[:lower:]')
    if printf '%s' "$PROMPT_LC" | grep -Eq "(^|[^a-z0-9_-])$a_lc([^a-z0-9_-]|$)"; then
      matched=1; break
    fi
  done
  [ "$matched" = "1" ] || continue

  seen="$seen$tok "
  [ "$nchain" -gt 0 ] && chain="$chain; "
  chain="$chain$phase → \`$tok\`"
  nchain=$((nchain + 1))
done <<EOF
$(awk -F'|' '
  /^\| [0-9]|^\| Meta\.|^\| Docs lookup|^\| UI verify|^\| GitHub ops/ {
    phase=$2; gsub(/^ +| +$/, "", phase)
    line=$4 "`" $5
    while (match(line, /`[a-zA-Z][a-zA-Z0-9_:-]*`/)) {
      printf "%s\t%s\n", phase, substr(line, RSTART+1, RLENGTH-2)
      line=substr(line, RSTART+RLENGTH)
    }
  }
' "$REG")
EOF

# PAUL is a first-class spine namespace: any literal `paul:<cmd>` the user types
# is unambiguous intent and routes deterministically — even if that specific
# command isn't enumerated in registry.md (PAUL ships ~25 of them; the registry
# only lists paul:init at Bootstrap). The colon makes it impossible to confuse
# with prose, so this is safe. Bare "paul" stays deferred to the model.
for tok in $(printf '%s' "$PROMPT_LC" | grep -oE 'paul:[a-z][a-z0-9-]+' | sort -u); do
  case "$seen" in *" $tok "*) continue ;; esac
  seen="$seen$tok "
  [ "$nchain" -gt 0 ] && chain="$chain; "
  chain="$chain PAUL → \`$tok\`"
  nchain=$((nchain + 1))
done

# Project-state spine (deterministic): .planning/ → GSD, .paul/ → PAUL.
GITROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
BASE="${GITROOT:-$PWD}"
SPINE=""
if [ -d "$BASE/.planning" ]; then
  SPINE="GSD is active (.planning/ present) — use the gsd-* variant for this phase."
elif [ -d "$BASE/.paul" ]; then
  SPINE="PAUL is active (.paul/ present) — use paul:* and close the loop with paul:unify."
fi

# Nothing deterministic to say → stay silent, let the model route fuzzily.
[ "$nchain" -eq 0 ] && [ -z "$SPINE" ] && exit 0

MSG="Pilot deterministic route (computed from registry.md, not inferred):"
if [ "$nchain" -gt 0 ]; then
  MSG="$MSG you literally named — $chain. Invoke these directly via the Skill tool (literal-name route); sequence as a phase chain if more than one."
fi
[ -n "$SPINE" ] && MSG="$MSG Spine: $SPINE"
MSG="$MSG Any other (unnamed/ambiguous) intent in the prompt is left to your judgment using registry.md."

jq -cn --arg c "$MSG" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$c}}'
exit 0
