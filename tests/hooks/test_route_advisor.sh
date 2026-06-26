#!/usr/bin/env bash
# Test route-advisor.sh (UserPromptSubmit): deterministic hard-routes for
# distinctive literal skill names + project-state spine; silence on common
# words, fuzzy intent, and bypass.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/route-advisor.sh"
export CLAUDE_PLUGIN_ROOT="$ROOT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"   # isolate bypass markers

# ctx <prompt> [cwd] → prints injected additionalContext, or "" if silent.
ctx() {
  local prompt="$1" dir="${2:-$TMP}"
  ( cd "$dir" && printf '{"prompt":%s}' "$(jq -Rs . <<<"$prompt")" | bash "$HOOK" 2>/dev/null ) \
    | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true
}

# 1. Distinctive literal name → hard route.
out=$(ctx "plan it then use tdd")
[[ "$out" == *'`tdd`'* ]] || { echo "FAIL: distinctive literal 'tdd' not routed"; exit 1; }
echo "PASS: distinctive literal name routed"

# 2. Multi-mention → phase chain, registry order.
out=$(ctx "use tdd then improve-codebase-architecture")
[[ "$out" == *'`tdd`'* && "$out" == *'`improve-codebase-architecture`'* ]] \
  || { echo "FAIL: multi-mention chain incomplete"; exit 1; }
echo "PASS: multi-mention produces a chain"

# 3. Namespaced skill matched via bare alias.
out=$(ctx "plan via writing-plans")
[[ "$out" == *'writing-plans'* ]] || { echo "FAIL: bare alias 'writing-plans' not matched"; exit 1; }
echo "PASS: bare alias resolves to namespaced skill"

# 4. Common-English skill names → SILENT (deferred to model).
for p in "review this code" "run it and verify it works" "init the value"; do
  out=$(ctx "$p")
  [[ -z "$out" ]] || { echo "FAIL: common-word prompt hard-routed (should defer): '$p' → $out"; exit 1; }
done
echo "PASS: common-word skill names deferred to model (silent)"

# 5. Fuzzy intent → SILENT.
out=$(ctx "this code feels messy and might be broken")
[[ -z "$out" ]] || { echo "FAIL: fuzzy intent should be silent, got: $out"; exit 1; }
echo "PASS: fuzzy intent left to model (silent)"

# 6. Project-state spine.
gp="$TMP/gsd"; mkdir -p "$gp/.planning" && ( cd "$gp" && git init -q )
out=$(ctx "do the next thing" "$gp")
[[ "$out" == *"GSD is active"* ]] || { echo "FAIL: .planning/ did not yield GSD spine"; exit 1; }
echo "PASS: .planning/ → GSD spine"

pp="$TMP/paul"; mkdir -p "$pp/.paul" && ( cd "$pp" && git init -q )
out=$(ctx "do the next thing" "$pp")
[[ "$out" == *"PAUL is active"* ]] || { echo "FAIL: .paul/ did not yield PAUL spine"; exit 1; }
echo "PASS: .paul/ → PAUL spine"

# 7. Bypass marker → SILENT even with a literal name.
mkdir -p "$XDG_CACHE_HOME/pilot"; touch "$XDG_CACHE_HOME/pilot/off-rails"
out=$(ctx "use tdd")
[[ -z "$out" ]] || { echo "FAIL: bypass marker should silence routing, got: $out"; exit 1; }
rm -f "$XDG_CACHE_HOME/pilot/off-rails"
echo "PASS: bypass marker silences routing"

echo "ALL route-advisor tests passed."
