#!/usr/bin/env bash
# Full pilot dev install in one command:
#   1. Symlink skills/pilot → ~/.claude/skills/pilot (live editing)
#   2. Wire hooks → ~/.claude/settings.json (via wire-hooks.sh)
#   3. Register MCPs (context7, playwright, github) via wire-mcps.sh
#
# Use this for a clean contributor setup. Each step is also runnable
# atomically — symlink-pilot.sh just chains them.
#
# Skip the wiring with: SKIP_WIRE=1 bash dev/symlink-pilot.sh
#   (useful if you've wired previously and only want to refresh the
#   symlink, or if you're testing one of the atomic scripts in isolation.)
set -euo pipefail

DEV_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_SRC="$(cd "$DEV_DIR/.." && pwd)/skills"

echo "==> [1/3] Symlinking skill dirs..."

mkdir -p "$HOME/.claude/skills"

# Symlink every immediate subdirectory of skills/ — pilot's own skill plus
# any bundled scaffolds (migration-safety, pre-deploy-checklist, etc.) the
# marketplace install would pick up automatically via plugin.json's
# "skills": "./skills/" declaration.
for skill_dir in "$SKILLS_SRC"/*/; do
  [[ -d "$skill_dir" ]] || continue
  name=$(basename "$skill_dir")
  target="$HOME/.claude/skills/$name"

  if [[ -L "$target" ]]; then
    rm "$target"
  elif [[ -e "$target" ]]; then
    backup="$target.bak.$(date +%s)"
    echo "Backing up existing dir to $backup"
    mv "$target" "$backup"
  fi

  ln -s "${skill_dir%/}" "$target"
  echo "  ✓ $name → $target"
done

if [[ "${SKIP_WIRE:-}" == "1" ]]; then
  echo
  echo "SKIP_WIRE=1 set — skipping hook + MCP wiring."
  echo "Run separately when needed:"
  echo "  bash $DEV_DIR/wire-hooks.sh"
  echo "  bash $DEV_DIR/wire-mcps.sh"
  exit 0
fi

echo
echo "==> [2/3] Wiring hooks into ~/.claude/settings.json..."
bash "$DEV_DIR/wire-hooks.sh"

echo
echo "==> [3/3] Registering MCPs (context7, playwright, github)..."
if ! command -v claude >/dev/null 2>&1; then
  echo "WARN: claude CLI not on PATH — skipping MCP registration."
  echo "      Install Claude Code first, then re-run: bash $DEV_DIR/wire-mcps.sh"
else
  bash "$DEV_DIR/wire-mcps.sh"
fi

echo
echo "==> Pilot dev install complete."
echo "    Restart Claude Code so the freshly wired hooks load."
echo "    Verify with: /pilot-doctor"
