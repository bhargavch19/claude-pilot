#!/usr/bin/env bash
# Emits the pilot active banner at SessionStart.
# Stdout is appended to the assistant's context as system-reminder text.
#
# Also: detects first-run install and version upgrades, prepending a one-
# line hint about /pilot-doctor or the new CHANGELOG entry respectively.
set -euo pipefail

# Resolve plugin root: prefer CLAUDE_PLUGIN_ROOT (set by marketplace
# install), else walk up from this script's own dir.
ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -z "$ROOT" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

VERSION="?"
if [[ -f "$ROOT/.claude-plugin/plugin.json" ]] && command -v jq >/dev/null 2>&1; then
  VERSION=$(jq -r '.version // "?"' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null || echo "?")
fi

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pilot"
mkdir -p "$CACHE_DIR" 2>/dev/null || true

WELCOMED="$CACHE_DIR/welcomed"
LAST_VERSION_FILE="$CACHE_DIR/last-version"

# Detect active bypass markers.
BYPASS=""
if [[ -f "$CACHE_DIR/bypass-session" ]]; then
  BYPASS=" (bypass: session-active)"
elif [[ -f "$CACHE_DIR/bypass-once" || -f "$CACHE_DIR/bypass-no-plan-once" ]]; then
  BYPASS=" (bypass: one-shot armed)"
fi

# First-run hint: shown once per cache lifetime.
FIRST_RUN_LINE=""
if [[ ! -f "$WELCOMED" ]]; then
  FIRST_RUN_LINE=$'\nfirst run — try /pilot-doctor to verify the install.'
  touch "$WELCOMED" 2>/dev/null || true
fi

# Upgrade hint: shown once per version transition.
UPGRADE_LINE=""
LAST_VERSION=""
if [[ -f "$LAST_VERSION_FILE" ]]; then
  LAST_VERSION=$(cat "$LAST_VERSION_FILE" 2>/dev/null || true)
fi
if [[ -n "$LAST_VERSION" && "$LAST_VERSION" != "$VERSION" ]]; then
  UPGRADE_LINE=$'\nupgraded '"$LAST_VERSION"' → '"$VERSION"$' — see CHANGELOG.md.'
fi
if [[ "$LAST_VERSION" != "$VERSION" ]]; then
  echo "$VERSION" > "$LAST_VERSION_FILE" 2>/dev/null || true
fi

cat <<EOF
[pilot active] v${VERSION} phase routing on${BYPASS}.
registry: skills/pilot/registry.md.
bypass: /pilot-off | /pilot-off-rails | /pilot-bypass --no-plan | /pilot-back-on.
diagnostics: /pilot-status | /pilot-doctor.${FIRST_RUN_LINE}${UPGRADE_LINE}
EOF
