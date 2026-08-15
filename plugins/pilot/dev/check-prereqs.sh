#!/usr/bin/env bash
# Print a status table of pilot's prereqs.
# Returns 0 if all "tools" are present (jq/git/bash); plugins/skills are
# advisory and never block.
set -euo pipefail

if [[ -t 1 ]]; then
  GREEN=$(tput setaf 2 2>/dev/null || echo "")
  YELLOW=$(tput setaf 3 2>/dev/null || echo "")
  RED=$(tput setaf 1 2>/dev/null || echo "")
  DIM=$(tput dim 2>/dev/null || echo "")
  RESET=$(tput sgr0 2>/dev/null || echo "")
else
  GREEN="" YELLOW="" RED="" DIM="" RESET=""
fi

mark_ok()   { printf "%s✓%s" "$GREEN" "$RESET"; }
mark_warn() { printf "%s○%s" "$YELLOW" "$RESET"; }
mark_miss() { printf "%s✗%s" "$RED" "$RESET"; }

PLUGINS_JSON="$HOME/.claude/plugins/installed_plugins.json"
SKILLS_DIR="$HOME/.claude/skills"
PLUGINS_CACHE="$HOME/.claude/plugins/cache"

plugin_installed() {
  # $1 = plugin name (without marketplace suffix).
  [[ -f "$PLUGINS_JSON" ]] || return 1
  jq -e --arg n "$1" '
    .plugins | to_entries
    | any(.key | split("@")[0] == $n)
  ' "$PLUGINS_JSON" >/dev/null 2>&1
}

skill_installed() {
  # $1 = skill name. Looks for ~/.claude/skills/<name>/SKILL.md OR a
  # plugin-bundled skills/<name>/SKILL.md under any cached plugin.
  [[ -f "$SKILLS_DIR/$1/SKILL.md" ]] && return 0
  if [[ -d "$PLUGINS_CACHE" ]]; then
    # No maxdepth — some plugins nest skills deeper than the default 5/8.
    find "$PLUGINS_CACHE" -type f -path "*/skills/$1/SKILL.md" 2>/dev/null \
      | grep -q . && return 0
  fi
  return 1
}

tool_installed() {
  command -v "$1" >/dev/null 2>&1
}

echo "=== Pilot prereqs ==="
echo

# --- Tools ---
echo "Tools:"
tool_fail=0
for t in bash jq git; do
  if tool_installed "$t"; then
    printf "  %s %s\n" "$(mark_ok)" "$t"
  else
    printf "  %s %s%s (required)%s\n" "$(mark_miss)" "$t" "$RED" "$RESET"
    tool_fail=$((tool_fail + 1))
  fi
done
# node/npx — soft prereq for the bundled context7 MCP.
if tool_installed npx; then
  printf "  %s npx%s (context7 MCP)%s\n" "$(mark_ok)" "$DIM" "$RESET"
else
  printf "  %s npx%s (soft — context7 docs-lookup MCP will be unavailable)%s\n" "$(mark_warn)" "$DIM" "$RESET"
fi
echo

# --- Bundled MCP servers ---
echo "Bundled MCP servers:"
# context7
if [[ -n "${PILOT_DISABLE_CONTEXT7:-}" ]]; then
  printf "  %s context7%s (PILOT_DISABLE_CONTEXT7 set — routing skipped)%s\n" "$(mark_warn)" "$DIM" "$RESET"
elif [[ -n "${CONTEXT7_API_KEY:-}" ]]; then
  printf "  %s context7%s (CONTEXT7_API_KEY set — higher rate limits)%s\n" "$(mark_ok)" "$DIM" "$RESET"
else
  printf "  %s context7%s (free tier — set CONTEXT7_API_KEY for higher limits)%s\n" "$(mark_warn)" "$DIM" "$RESET"
fi
# playwright
if [[ -n "${PILOT_DISABLE_PLAYWRIGHT:-}" ]]; then
  printf "  %s playwright%s (PILOT_DISABLE_PLAYWRIGHT set — UI verify disabled)%s\n" "$(mark_warn)" "$DIM" "$RESET"
else
  printf "  %s playwright%s (browser auto-downloads on first navigate, ~300MB)%s\n" "$(mark_ok)" "$DIM" "$RESET"
fi
# github
if [[ -n "${PILOT_DISABLE_GITHUB:-}" ]]; then
  printf "  %s github%s (PILOT_DISABLE_GITHUB set — falling back to gh CLI)%s\n" "$(mark_warn)" "$DIM" "$RESET"
elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
  printf "  %s github%s (GITHUB_TOKEN set — full write access)%s\n" "$(mark_ok)" "$DIM" "$RESET"
else
  printf "  %s github%s (no GITHUB_TOKEN — public reads only, writes 401)%s\n" "$(mark_warn)" "$DIM" "$RESET"
fi
echo

# --- Recommended plugins ---
echo "Recommended plugins:"
for p in superpowers frontend-design claude-mem; do
  if plugin_installed "$p"; then
    printf "  %s %s\n" "$(mark_ok)" "$p"
  else
    printf "  %s %s%s (recommended — install for full coverage)%s\n" "$(mark_warn)" "$p" "$DIM" "$RESET"
  fi
done
echo

# --- Optional skills ---
echo "Optional skills (sharper routing when present):"
for s in grill-me grill-with-docs to-prd to-issues tdd diagnose \
         improve-codebase-architecture simplify skill-creator context-mode; do
  if skill_installed "$s"; then
    printf "  %s %s\n" "$(mark_ok)" "$s"
  else
    printf "  %s %s%s (optional)%s\n" "$(mark_warn)" "$s" "$DIM" "$RESET"
  fi
done
echo

# --- GSD suite (one-shot check) ---
echo "GSD suite:"
gsd_count=0
if [[ -d "$SKILLS_DIR" ]]; then
  gsd_count=$(find "$SKILLS_DIR" -maxdepth 1 -type d -name 'gsd-*' 2>/dev/null | wc -l | tr -d ' ')
fi
if [[ "$gsd_count" -gt 0 ]]; then
  printf "  %s %d gsd-* skill(s) detected — .planning/-aware routing enabled.\n" "$(mark_ok)" "$gsd_count"
else
  printf "  %s no gsd-* skills detected — pilot falls back to superpowers / Pocock path.\n" "$(mark_warn)"
fi
echo

if [[ "$tool_fail" -gt 0 ]]; then
  echo "${RED}Missing required tools — install them before using pilot.${RESET}"
  exit "$tool_fail"
fi
echo "${GREEN}Required tools present.${RESET} Plugin/skill gaps are advisory."
