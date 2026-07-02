#!/usr/bin/env bash
# G1 enforcement: block large file-mutating tool calls unless a plan exists.
# Blocks with exit 2 — the Claude Code PreToolUse blocking convention (stderr
# is fed back to the model); any other non-zero exit would NOT stop the call.
# Reads JSON tool invocation from stdin (Claude Code PreToolUse format).
# Handles Edit, Write, MultiEdit, NotebookEdit — AND large code writes done
# through Bash (`cat > file`, `tee file`, heredocs), which would otherwise slip
# past a tool-only gate.
set -euo pipefail

INPUT=$(cat)
if [[ -z "$INPUT" ]] || ! printf '%s' "$INPUT" | jq empty 2>/dev/null; then
  echo "plan-gate: stdin missing or not valid JSON — gate declining to enforce." >&2
  exit 0
fi
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // .tool // empty' 2>/dev/null || echo "")

# Pick the right line-count expression per tool shape. For MultiEdit we
# concatenate every edit's new_string so the total counts toward the gate.
case "$TOOL" in
  Edit)
    NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // .input.new_string // ""' 2>/dev/null || echo "")
    ;;
  Write)
    NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.content // .input.content // ""' 2>/dev/null || echo "")
    ;;
  MultiEdit)
    NEW_STRING=$(echo "$INPUT" | jq -r '[.tool_input.edits[]?.new_string // empty] | join("\n")' 2>/dev/null || echo "")
    ;;
  NotebookEdit)
    NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_source // .tool_input.content // ""' 2>/dev/null || echo "")
    ;;
  Bash)
    # Only gate Bash that WRITES A CODE FILE via redirect/tee/heredoc. Other
    # Bash (reads, pipelines, git) is none of plan-gate's business → exit fast.
    # The command-line length is the size proxy: a big heredoc/printf inlines
    # its body, so a >20-line command writing a source file is a large change.
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
    code_ext='(ts|tsx|js|jsx|mjs|cjs|py|go|rs|rb|java|kt|swift|m|c|cc|cpp|h|hpp|cs|php|ex|exs|scala|clj|sh|sql|vue|svelte)'
    if ! printf '%s' "$CMD" | grep -Eq "(>>?|[[:space:]]tee[[:space:]])[^|&;<]*\.${code_ext}([[:space:]]|\"|'|$)"; then
      exit 0
    fi
    NEW_STRING="$CMD"
    ;;
  *)
    exit 0
    ;;
esac

LINE_COUNT=$(echo -n "$NEW_STRING" | grep -c '^' || true)

if [[ "$LINE_COUNT" -le 20 ]]; then
  exit 0
fi

# Bypass via marker files (written by /pilot-off, /pilot-off-rails,
# /pilot-bypass slash commands). One-shot markers are consumed.
BYPASS_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pilot"
for m in bypass-no-plan-once bypass-once; do
  if [[ -f "$BYPASS_DIR/$m" ]]; then
    rm -f "$BYPASS_DIR/$m"
    echo "plan-gate: bypassed ($m consumed)." >&2
    exit 0
  fi
done
if [[ -f "$BYPASS_DIR/bypass-session" ]]; then
  echo "plan-gate: bypassed (session bypass active — /pilot-back-on to re-engage)." >&2
  exit 0
fi

# Bypass: respect "pilot off", "pilot off rails", "pilot --no-plan" in the
# last user message, or an active "off rails" state.
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
  USER_MSGS=$(jq -r 'select(.type=="user") | (.message.content // .message | tostring)' "$TRANSCRIPT" 2>/dev/null | tail -30 || true)
  LAST_USER=$(printf '%s' "$USER_MSGS" | tail -1)
  if printf '%s' "$LAST_USER" | grep -qiE '(^|[[:space:]]|[[:punct:]])pilot[[:space:]]+(off([[:space:]]+rails)?|--no-plan)([[:space:]]|$|[[:punct:]])'; then
    echo "plan-gate: bypassed (pilot off / --no-plan in last user message)." >&2
    exit 0
  fi
  STATE=$(printf '%s' "$USER_MSGS" | grep -iE '(^|[[:space:]]|[[:punct:]])pilot[[:space:]]+(off[[:space:]]+rails|back[[:space:]]+on)' | tail -1 || true)
  if [[ "$STATE" =~ off[[:space:]]+rails ]]; then
    echo "plan-gate: bypassed (pilot off rails active)." >&2
    exit 0
  fi
fi

# Plan-existence check (git-based):
#   1. Any plan file present in the working tree (committed or staged or
#      untracked) — covers fresh plans not yet committed.
#   2. Any plan file modified in the current branch's commits since
#      merge-base with its upstream / main / master.
# Fallback when outside git: simple working-tree existence check.
plan_paths_re='^(docs/superpowers/plans/.*\.md|\.planning/.*/(PLAN|SPEC)\.md)$'

plan_in_worktree() {
  local f
  for d in docs/superpowers/plans .planning; do
    [[ -d "$d" ]] || continue
    f=$(find "$d" -type f -name '*.md' 2>/dev/null \
      | grep -E "$plan_paths_re" | head -1 || true)
    [[ -n "$f" ]] && return 0
  done
  return 1
}

plan_in_branch() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  local base upstream
  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
  if [[ -z "$upstream" ]]; then
    for b in main master; do
      if git rev-parse --verify "$b" >/dev/null 2>&1; then
        upstream="$b"; break
      fi
    done
  fi
  [[ -z "$upstream" ]] && return 1
  base=$(git merge-base HEAD "$upstream" 2>/dev/null || true)
  [[ -z "$base" ]] && return 1
  git log --name-only --pretty=format: "$base..HEAD" 2>/dev/null \
    | grep -E "$plan_paths_re" | head -1 | grep -q . && return 0
  return 1
}

if plan_in_worktree || plan_in_branch; then
  exit 0
fi

cat <<EOF >&2
plan-gate: G1 — write a plan first.

Proposed change: $LINE_COUNT lines (>20 threshold).
No plan found for this branch in:
  - docs/superpowers/plans/*.md   (working tree or branch commits)
  - .planning/**/PLAN.md|SPEC.md  (working tree or branch commits)

Run the writing-plans skill (superpowers) or gsd-plan-phase, save the plan,
then retry.
Bypass: say "pilot --no-plan" or "pilot off" (use sparingly).
EOF
exit 2
