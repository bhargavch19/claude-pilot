#!/usr/bin/env bash
# Remove pilot's bundled MCP servers from Claude Code's MCP registry.
# Mirrors wire-mcps.sh. Only removes entries whose registered command
# still matches plugin.json's declaration — so a user's own MCP using
# the same name (e.g. their own context7) won't get clobbered.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$PLUGIN_DIR/.claude-plugin/plugin.json"

if [[ ! -f "$MANIFEST" ]]; then
  echo "ERROR: $MANIFEST not found." >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "ERROR: claude CLI not on PATH." >&2
  exit 1
fi

# Match signature: stdio entries → "command args"; remote entries → the URL.
jq -r '.mcpServers // {} | to_entries[]
       | [.key,
          (if (.value.type // "stdio") == "stdio"
           then ((.value.command // "") + " " + ((.value.args // []) | join(" ")))
           else (.value.url // "") end)]
       | @tsv' \
  "$MANIFEST" \
  | while IFS=$'\t' read -r name sig; do
      [[ -n "$name" ]] || continue
      if ! claude mcp get "$name" >/dev/null 2>&1; then
        echo "SKIP $name (not registered)"
        continue
      fi
      # Guard: only remove if the registered command/URL still matches
      # what plugin.json declared. Avoids stomping on a user override.
      info=$(claude mcp get "$name" 2>/dev/null || true)
      if printf '%s' "$info" | grep -qF "$sig"; then
        if claude mcp remove "$name" >/dev/null 2>&1; then
          echo "REMOVED $name"
        else
          echo "FAIL removing $name — try: claude mcp remove $name" >&2
        fi
      else
        echo "SKIP $name (command diverged from plugin.json — left alone)"
      fi
    done

echo
echo "(Re-add via bash $PLUGIN_DIR/dev/wire-mcps.sh)"
