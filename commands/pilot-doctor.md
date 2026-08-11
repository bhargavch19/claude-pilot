---
description: Diagnose pilot installation — prereqs, hook paths, jq, symlink, settings.json wiring.
allowed-tools: Bash
---

Run a top-to-bottom pilot health check. Steps:

1. **Prereq table** — run `bash ${CLAUDE_PLUGIN_ROOT:-$HOME/Workspace/claude-skill}/dev/check-prereqs.sh`.

2. **Hook scripts executable + present** — run:
   ```bash
   ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/Workspace/claude-skill}"
   for h in plan-gate.sh pre-commit.sh safety-gate.sh pretooluse-heartbeat.sh verify-gate.sh autopilot-gate.sh capture-test-run.sh autoformat.sh sessionstart-banner.sh integrity-check.sh memory-surface.sh precompact-anchor.sh route-advisor.sh approval-capture.sh log-skill-invocation.sh; do
     if [[ -x "$ROOT/hooks/$h" ]]; then
       echo "✓ $h"
     elif [[ -f "$ROOT/hooks/$h" ]]; then
       echo "○ $h (present but not executable — chmod +x needed)"
     else
       echo "✗ $h (missing)"
     fi
   done
   ```

3. **settings.json wiring** — list each wired pilot hook AND verify the
   command actually resolves to an executable file (catches stale paths
   left behind by a moved/renamed plugin dir):
   ```bash
   jq -r '
     .hooks // {}
     | to_entries[]
     | .key as $k
     | .value[]?
     | .hooks[]?
     | "\($k)\t\(.command)"
   ' "$HOME/.claude/settings.json" 2>/dev/null \
     | grep -E '/hooks/(plan-gate|pre-commit|safety-gate|pretooluse-heartbeat|verify-gate|autopilot-gate|capture-test-run|autoformat|sessionstart-banner|integrity-check|memory-surface|precompact-anchor|route-advisor|approval-capture|log-skill-invocation)\.sh' \
     | while IFS=$'\t' read -r event cmd; do
         path="${cmd%% *}"  # strip any args
         path="${path#\"}"; path="${path%\"}"  # strip quotes if present
         if [[ -x "$path" ]]; then
           echo "✓ $event → $path"
         elif [[ -f "$path" ]]; then
           echo "○ $event → $path (present, not executable)"
         else
           echo "✗ $event → $path (BROKEN — file missing; run dev/unwire-hooks then dev/wire-hooks)"
         fi
       done
   # If nothing matched at all:
   jq -e '.hooks // {} | [.. | objects | .command? // empty] | any(test("/hooks/(plan-gate|pre-commit|safety-gate|pretooluse-heartbeat|verify-gate|autopilot-gate|capture-test-run|autoformat|sessionstart-banner|integrity-check|memory-surface|precompact-anchor|route-advisor|approval-capture|log-skill-invocation)\\.sh"))' \
     "$HOME/.claude/settings.json" >/dev/null 2>&1 \
     || echo '(no pilot hooks wired — run dev/wire-hooks.sh or install via marketplace)'
   ```

3.5. **PreToolUse liveness (issue #31250)** — PreToolUse hooks can fail
   silently; if they stop firing, plan-gate/safety-gate quietly stop
   protecting. `pretooluse-heartbeat.sh` records each PreToolUse fire. Because
   this very command runs via the Bash tool, a *fresh* heartbeat proves the
   chain is live; a missing/stale one means PreToolUse is not firing:
   ```bash
   MARK="${XDG_CACHE_HOME:-$HOME/.cache}/pilot/pretooluse-last"
   if [[ -f "$MARK" ]]; then
     ts=$(cut -f1 "$MARK"); now=$(date +%s)
     age=$(( now - ts ))
     if (( age <= 120 )); then
       echo "✓ PreToolUse fired ${age}s ago (tool: $(cut -f2 "$MARK")) — chain live"
     else
       echo "⚠ PreToolUse last fired ${age}s ago — running this command should have refreshed it; PreToolUse may be disabled (issue #31250)"
     fi
   else
     echo "⚠ no PreToolUse heartbeat — hooks may not be firing (issue #31250); re-wire with dev/wire-hooks.sh or reinstall the plugin"
   fi
   ```

4. **MCP servers** — for each entry in plugin.json's mcpServers, verify the
   command is runnable, AND each declared server is actually registered
   with Claude Code (marketplace install does this for you; dev installs
   need `bash dev/wire-mcps.sh`):
   ```bash
   ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/Workspace/claude-skill}"
   unregistered=0
   jq -r '.mcpServers // {} | to_entries[] | "\(.key)\t\(.value.command)\t\((.value.args // []) | join(" "))"' \
     "$ROOT/.claude-plugin/plugin.json" \
     | while IFS=$'\t' read -r name cmd args; do
         runnable="✗"; command -v "$cmd" >/dev/null 2>&1 && runnable="✓"
         registered="✗"
         if command -v claude >/dev/null 2>&1 && claude mcp get "$name" >/dev/null 2>&1; then
           registered="✓"
         fi
         echo "$runnable runnable, $registered registered — $name ($cmd $args)"
       done
   # If any are runnable-but-unregistered, point at the dev wiring script.
   if command -v claude >/dev/null 2>&1; then
     missing=$(jq -r '.mcpServers // {} | keys[]' "$ROOT/.claude-plugin/plugin.json" \
       | while read -r n; do claude mcp get "$n" >/dev/null 2>&1 || echo "$n"; done)
     if [[ -n "$missing" ]]; then
       echo
       echo "⚠ declared MCPs not registered with Claude Code:"
       echo "$missing" | sed 's/^/    /'
       echo "  Fix (dev install): bash $ROOT/dev/wire-mcps.sh"
       echo "  Fix (marketplace install): /plugin reinstall pilot"
     fi
   fi
   ```
   Then check env vars that affect bundled servers:
   ```bash
   [[ -n "${CONTEXT7_API_KEY:-}" ]] && echo "✓ CONTEXT7_API_KEY set" || echo "○ CONTEXT7_API_KEY unset (context7 on free tier)"
   [[ -n "${PILOT_DISABLE_CONTEXT7:-}" ]] && echo "○ PILOT_DISABLE_CONTEXT7 set — docs-lookup disabled"
   ```

4.5. **Skill availability matrix (registry.md Primary + Fallback columns)** —
   walks every Primary skill listed in `registry.md` (full status) and every
   Fallback reference (surfaced only when it resolves to nothing). Catches both
   "primary missing → silent fallback" surprises and "fallback ID rotted →
   dead-end route" drift:
   ```bash
   ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/Workspace/claude-skill}"
   REG="$ROOT/skills/pilot/registry.md"
   [[ -f "$REG" ]] || { echo "(registry.md not found at $REG)"; }

   # Extract referenced skill IDs, tagged by role: the Primary (4th col, first
   # backtick) and ALL Fallback (5th col) backticked identifiers.
   refs=$(awk -F'|' '
     /^\| [0-9]|^\| Meta\.|^\| Docs lookup|^\| UI verify|^\| GitHub ops/ {
       p = $4
       if (match(p, /`[a-zA-Z][a-zA-Z0-9_:-]*`/)) print "primary\t" substr(p, RSTART+1, RLENGTH-2)
       fb = $5
       while (match(fb, /`[a-zA-Z][a-zA-Z0-9_:.-]*`/)) {
         print "fallback\t" substr(fb, RSTART+1, RLENGTH-2)
         fb = substr(fb, RSTART+RLENGTH)
       }
     }
   ' "$REG" | sort -u)

   # Resolve a skill id to a source label, or empty if it resolves to nothing.
   resolve() {
     local skill="$1" bare
     case "$skill" in
       context7|playwright|github|gh) echo "mcp/cli"; return ;;
       init|verify|run|simplify|review|security-review|claude-api|loop|schedule|fewer-permission-prompts|update-config|keybindings-help|find-skills|write-a-skill|git-guardrails-claude-code|to-prd|to-issues|deep-research|code-review)
         echo "built-in"; return ;;
     esac
     if [[ -f "$HOME/.claude/skills/$skill/SKILL.md" ]]; then echo "user-installed"; return; fi
     if find "$HOME/.claude/plugins/cache" -maxdepth 6 -type f -path "*/skills/$skill/SKILL.md" 2>/dev/null | head -1 | grep -q .; then echo "plugin-bundled"; return; fi
     if [[ "$skill" == *":"* ]]; then
       bare="${skill#*:}"
       if find "$HOME/.claude/plugins/cache" -maxdepth 6 -type f -path "*/skills/$bare/SKILL.md" 2>/dev/null | head -1 | grep -q .; then echo "plugin-bundled (namespaced)"; return; fi
     fi
     echo ""
   }

   missing_count=0; drift_count=0
   echo "Skill availability (registry.md Primary column):"
   while IFS=$'\t' read -r role skill; do
     [[ "$role" == "primary" && -n "$skill" ]] || continue
     src=$(resolve "$skill")
     case "$src" in
       mcp/cli) ;;  # MCPs surface in section 4
       built-in) printf "  • %-45s (built-in — file probe N/A)\n" "$skill" ;;
       "")       printf "  ✗ %-45s (PRIMARY missing — pilot uses fallback if registered)\n" "$skill"; missing_count=$((missing_count + 1)) ;;
       *)        printf "  ✓ %-45s (%s)\n" "$skill" "$src" ;;
     esac
   done <<< "$refs"

   # Fallback references — only surface ones that resolve to NOTHING (drift).
   while IFS=$'\t' read -r role skill; do
     [[ "$role" == "fallback" && -n "$skill" ]] || continue
     [[ -z "$(resolve "$skill")" ]] || continue
     printf "  ⚠ %-45s (fallback reference resolves to nothing — registry drift?)\n" "$skill"
     drift_count=$((drift_count + 1))
   done <<< "$refs"

   if (( missing_count > 0 )); then
     echo
     echo "⚠ $missing_count primary skill(s) missing on disk. Pilot routes via"
     echo "  fallbacks if registered. Install the missing primaries to enable"
     echo "  preferred routing. Common cause for pilot-bundled scaffolds:"
     echo "  re-run \`bash dev/symlink-pilot.sh\` after a v0.7+ pull."
   fi
   if (( drift_count > 0 )); then
     echo
     echo "⚠ $drift_count fallback reference(s) resolve to nothing — likely a"
     echo "  renamed/removed skill. Fix the ID in registry.md or install the skill."
   fi
   ```

5. **Bypass state** — run:
   ```bash
   ls -la "${XDG_CACHE_HOME:-$HOME/.cache}/pilot" 2>/dev/null \
     || echo '(no bypass markers — gates active)'
   ```

6. **Summary** — one-line green/yellow/red verdict:
   - **Green** if all hooks executable, wired in settings.json, required tools present, MCP commands runnable.
   - **Yellow** if tools OK but some hooks unwired, some recommended plugins missing, or an MCP command (e.g. npx) is missing.
   - **Red** if a required tool (jq, git, bash) is missing.

Be terse. Suggest the one fix that'd flip the verdict to green.
