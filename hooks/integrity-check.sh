#!/usr/bin/env bash
# Pilot integrity-check — SessionStart hook.
#
# Warns when the OPENED PROJECT ships its own Claude Code hooks in
# .claude/settings.json / settings.local.json. A repo-defined hook runs
# automatically the moment you open or work in the repo — the SessionStart-hook
# RCE vector (a real PyPI-worm incident planted exactly this). Treat repo
# settings like CI config: vet before trusting. Pilot's own hooks are installed
# globally and are NOT flagged.
#
# Also does a light routing-integrity check: warns if the registry the
# route-advisor reads is missing (routing silently degrades without it).
# Informational only — never blocks.
set -uo pipefail

cat >/dev/null 2>&1 || true   # drain the SessionStart payload on stdin
command -v jq >/dev/null 2>&1 || exit 0

PROJ="${CLAUDE_PROJECT_DIR:-}"
[ -n "$PROJ" ] || PROJ=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$PROJ" ] || PROJ="$PWD"

findings=""

for f in "$PROJ/.claude/settings.json" "$PROJ/.claude/settings.local.json"; do
  [ -f "$f" ] || continue
  rel="${f#"$PROJ"/}"
  if ! jq empty "$f" >/dev/null 2>&1; then
    findings="$findings
  ⚠ $rel — not valid JSON (could not inspect for hooks)"
    continue
  fi
  cmds=$(jq -r '[(.hooks? // {}) | .. | objects | .command? // empty] | .[]' "$f" 2>/dev/null || true)
  [ -n "$cmds" ] || continue
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    case "$c" in
      *"/claude-skill/hooks/"*) continue ;;   # pilot's own — trusted
    esac
    findings="$findings
  • $rel → $c"
  done <<EOF
$cmds
EOF
done

# Routing integrity: the registry the advisor reads should exist.
ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -n "$ROOT" ] && [ ! -f "$ROOT/skills/pilot/registry.md" ]; then
  findings="$findings
  ⚠ routing degraded — registry.md not found at \$CLAUDE_PLUGIN_ROOT/skills/pilot/"
fi

[ -n "$findings" ] || exit 0

cat <<EOF
pilot integrity-check: this project defines its own Claude Code hooks — they run
automatically as you work in the repo (a known RCE vector). Vet before trusting:$findings
If any are unexpected, inspect the script before continuing; don't assume the repo
is safe just because it opened. (Pilot's own hooks are global and not listed here.)
EOF
exit 0
