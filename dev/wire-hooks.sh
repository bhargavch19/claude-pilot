#!/usr/bin/env bash
# Idempotently wire pilot hooks into ~/.claude/settings.json (dev install only).
# Backs up original to settings.json.bak.<timestamp> if present.
#
# Prefer marketplace install: see top-level README. This script is for
# contributors hacking on pilot via the symlink-pilot.sh workflow.
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ ! -d "$PLUGIN_DIR/hooks" ]]; then
  echo "ERROR: $PLUGIN_DIR/hooks not found. Are you in the pilot repo?" >&2
  exit 1
fi

if [[ ! -f "$PLUGIN_DIR/.claude-plugin/plugin.json" ]]; then
  echo "ERROR: $PLUGIN_DIR/.claude-plugin/plugin.json not found." >&2
  exit 1
fi

if [[ -f "$SETTINGS" ]]; then
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
else
  echo '{}' > "$SETTINGS"
fi

# Merge hooks. Use jq for safety. Idempotent dedup of pilot entries by
# basename ONLY — not by current PLUGIN_DIR. If a previous wire-hooks run
# wrote an entry from a different path (e.g. a moved/stale symlink), this
# still catches it so we don't accumulate duplicates.
jq --arg pd "$PLUGIN_DIR" '
  def is_pilot($name): .command? // "" | endswith("/hooks/" + $name);
  def drop_pilot($name): map(select(([.hooks[]? | is_pilot($name)] | any) | not));
  .hooks = (.hooks // {}) |
  .hooks.PreToolUse = ((.hooks.PreToolUse // []) | drop_pilot("plan-gate.sh") | drop_pilot("pre-commit.sh") | drop_pilot("safety-gate.sh"))
    + [
        {"matcher":"Edit|Write|MultiEdit|NotebookEdit","hooks":[{"type":"command","command":($pd + "/hooks/plan-gate.sh")}]},
        {"matcher":"Bash","hooks":[
          {"type":"command","command":($pd + "/hooks/safety-gate.sh")},
          {"type":"command","command":($pd + "/hooks/pre-commit.sh")}
        ]}
      ] |
  .hooks.PostToolUse = ((.hooks.PostToolUse // []) | drop_pilot("log-skill-invocation.sh") | drop_pilot("capture-test-run.sh") | drop_pilot("autoformat.sh"))
    + [
        {"matcher":"Skill","hooks":[{"type":"command","command":($pd + "/hooks/log-skill-invocation.sh")}]},
        {"matcher":"Bash","hooks":[{"type":"command","command":($pd + "/hooks/capture-test-run.sh")}]},
        {"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":($pd + "/hooks/autoformat.sh")}]}
      ] |
  .hooks.Stop = ((.hooks.Stop // []) | drop_pilot("verify-gate.sh"))
    + [{"hooks":[{"type":"command","command":($pd + "/hooks/verify-gate.sh")}]}] |
  .hooks.SubagentStop = ((.hooks.SubagentStop // []) | drop_pilot("verify-gate.sh"))
    + [{"hooks":[{"type":"command","command":($pd + "/hooks/verify-gate.sh")}]}] |
  .hooks.SessionStart = ((.hooks.SessionStart // []) | drop_pilot("sessionstart-banner.sh") | drop_pilot("integrity-check.sh"))
    + [{"hooks":[
        {"type":"command","command":($pd + "/hooks/sessionstart-banner.sh")},
        {"type":"command","command":($pd + "/hooks/integrity-check.sh")}
      ]}] |
  .hooks.PreCompact = ((.hooks.PreCompact // []) | drop_pilot("precompact-anchor.sh"))
    + [{"hooks":[{"type":"command","command":($pd + "/hooks/precompact-anchor.sh")}]}] |
  .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | drop_pilot("route-advisor.sh"))
    + [{"hooks":[{"type":"command","command":($pd + "/hooks/route-advisor.sh")}]}]
' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"

echo "Wired pilot hooks (dev install) into $SETTINGS:"
jq '.hooks' "$SETTINGS"
echo
echo "To remove: bash $PLUGIN_DIR/dev/unwire-hooks.sh"
