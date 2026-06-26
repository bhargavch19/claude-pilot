#!/usr/bin/env bash
# Idempotently remove pilot hook entries from ~/.claude/settings.json.
# Mirrors dev/wire-hooks.sh. Backs up to settings.json.bak.<timestamp>.
#
# Use after `bash dev/wire-hooks.sh` if you want to disable the dev
# install — for marketplace installs, prefer `/plugin uninstall pilot`.
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ ! -f "$SETTINGS" ]]; then
  echo "No settings.json at $SETTINGS — nothing to unwire."
  exit 0
fi

cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"

# Drop any hook entry whose command ends in one of pilot's hook script
# names AND whose path lives under this plugin dir (idempotent dedup).
jq --arg pd "$PLUGIN_DIR" '
  # Match by basename only so stale-path entries get cleaned up too.
  def is_pilot($name): .command? // "" | endswith("/hooks/" + $name);
  def drop_pilot($name): map(select((.hooks[]? | is_pilot($name)) | not));

  if .hooks == null then . else
    .hooks |=
      ( (.PreToolUse   // [] | drop_pilot("plan-gate.sh") | drop_pilot("pre-commit.sh")) as $p
      | (.PostToolUse  // [] | drop_pilot("log-skill-invocation.sh") | drop_pilot("capture-test-run.sh")) as $po
      | (.Stop         // [] | drop_pilot("verify-gate.sh"))                             as $s
      | (.SubagentStop // [] | drop_pilot("verify-gate.sh"))                             as $sa
      | (.SessionStart // [] | drop_pilot("sessionstart-banner.sh"))                     as $ss
      | (.PreCompact   // [] | drop_pilot("precompact-anchor.sh"))                       as $pc
      | (.UserPromptSubmit // [] | drop_pilot("route-advisor.sh"))                       as $up
      | { PreToolUse: $p, PostToolUse: $po, Stop: $s, SubagentStop: $sa, SessionStart: $ss, PreCompact: $pc, UserPromptSubmit: $up }
        + (del(.PreToolUse, .PostToolUse, .Stop, .SubagentStop, .SessionStart, .PreCompact, .UserPromptSubmit))
      )
    # Drop now-empty hook arrays for cleanliness.
    | .hooks |= with_entries(select(.value | length > 0))
    # If hooks ended up empty, drop the key entirely.
    | if (.hooks | length) == 0 then del(.hooks) else . end
  end
' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"

echo "Unwired pilot hooks from $SETTINGS."
if jq -e '.hooks' "$SETTINGS" >/dev/null 2>&1; then
  echo "Remaining hooks:"
  jq '.hooks' "$SETTINGS"
else
  echo "(no hooks remain)"
fi
