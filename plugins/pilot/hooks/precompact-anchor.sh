#!/usr/bin/env bash
# Re-anchor pilot's routing rules through context compaction.
#
# SKILL.md's routing logic drops out of context as the session grows.
# After /compact, Claude no longer has the registry rules in memory and
# pilot silently stops routing. This hook fires on PreCompact; its stdout
# is injected into the post-compact context as system-reminder text, so
# the routing essentials survive the squeeze.
#
# Keep the output terse — every token costs against the new context window.
set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
TRIGGER=$(printf '%s' "$INPUT" | jq -r '.trigger // "unknown"' 2>/dev/null || echo "unknown")

ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -z "$ROOT" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

VERSION="?"
if [[ -f "$ROOT/.claude-plugin/plugin.json" ]] && command -v jq >/dev/null 2>&1; then
  VERSION=$(jq -r '.version // "?"' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null || echo "?")
fi

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pilot"
LOG="$CACHE_DIR/routing.log"

# Active bypass detection.
BYPASS_STATE="none"
if [[ -f "$CACHE_DIR/bypass-session" ]]; then
  BYPASS_STATE="session-active (/pilot-back-on to re-engage)"
elif [[ -f "$CACHE_DIR/bypass-once" \
      || -f "$CACHE_DIR/bypass-no-plan-once" \
      || -f "$CACHE_DIR/bypass-precommit-once" ]]; then
  BYPASS_STATE="one-shot armed"
fi

# Last 3 routing decisions (if any). Truncated from 5 to keep post-compact
# context cost ~constant as the registry grows.
RECENT_ROUTES=""
if [[ -f "$LOG" ]]; then
  RECENT_ROUTES=$(tail -3 "$LOG" 2>/dev/null | sed 's/^/  /')
fi

# Terse re-anchor: registry has 17+ phases, can't enumerate inline post-compact
# without burning tokens. Point at registry.md instead and surface only the
# session-relevant operational state (bypass + recent routes).
cat <<EOF
[pilot v${VERSION}] re-anchored post-compact (trigger: ${TRIGGER}).
Routing → \`skills/pilot/registry.md\` (17 phases, literal-name shortcut active).
Guardrails: G1 plan-gate · G3/G7/G8/G12 pre-commit · G14 verify-gate.
Bypass: /pilot-off · /pilot-off-rails · /pilot-bypass [--no-plan|--no-precommit].
Bypass state: ${BYPASS_STATE}.
EOF

if [[ -n "$RECENT_ROUTES" ]]; then
  echo
  echo "Recent routing (last 3):"
  echo "$RECENT_ROUTES"
fi
