#!/usr/bin/env bash
# Pre-commit gate (G3 conventional msg, G7 `: any` w/ comment, G8 no
# console.log, G12 no sleep/setTimeout in test files).
#
# Runs as a Claude Code PreToolUse hook on Bash. Activates when the
# command invokes `git commit` (any flags). Blocks the tool call on
# violation (exit 2 — the PreToolUse blocking convention; other non-zero
# exits do NOT block). For commits whose message can't be parsed from
# the command line (HEREDOC, -F, plain `git commit` opening editor),
# G3 is skipped; G7/G8/G12 still enforced against the staged diff.
set -euo pipefail

INPUT=$(cat)

if [[ -z "$INPUT" ]] || ! printf '%s' "$INPUT" | jq empty 2>/dev/null; then
  echo "pre-commit: stdin missing or not valid JSON — gate declining to enforce." >&2
  exit 0
fi

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
[[ "$TOOL" == "Bash" ]] || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[[ -n "$CMD" ]] || exit 0

# Only act on `git commit` (matches `git commit`, `... -m ...`, `--amend`).
if ! [[ "$CMD" =~ (^|[^a-zA-Z])git[[:space:]]+commit([[:space:]]|$) ]]; then
  exit 0
fi

# Bypass via marker files. Per-gate markers (bypass-precommit-once) are
# checked first so a /pilot-bypass --no-precommit doesn't accidentally
# eat a /pilot-off intended for the next plan-gate fire in the same turn.
BYPASS_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pilot"
for m in bypass-precommit-once bypass-once; do
  if [[ -f "$BYPASS_DIR/$m" ]]; then
    rm -f "$BYPASS_DIR/$m"
    echo "pre-commit: bypassed ($m consumed)." >&2
    exit 0
  fi
done
if [[ -f "$BYPASS_DIR/bypass-session" ]]; then
  echo "pre-commit: bypassed (session bypass active)." >&2
  exit 0
fi

# Bypass: respect "pilot off" / "pilot off rails" in last user msg.
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
  USER_MSGS=$(jq -r 'select(.type=="user") | (.message.content // .message | tostring)' "$TRANSCRIPT" 2>/dev/null | tail -30 || true)
  LAST_USER=$(printf '%s' "$USER_MSGS" | tail -1)
  if printf '%s' "$LAST_USER" | grep -qiE '(^|[[:space:]]|[[:punct:]])pilot[[:space:]]+off([[:space:]]+rails)?([[:space:]]|$|[[:punct:]])'; then
    echo "pre-commit: bypassed (pilot off in last user message)." >&2
    exit 0
  fi
  STATE=$(printf '%s' "$USER_MSGS" | grep -iE '(^|[[:space:]]|[[:punct:]])pilot[[:space:]]+(off[[:space:]]+rails|back[[:space:]]+on)' | tail -1 || true)
  if [[ "$STATE" =~ off[[:space:]]+rails ]]; then
    echo "pre-commit: bypassed (pilot off rails active)." >&2
    exit 0
  fi
fi

# Extract commit message from -m / --message= when reliably parsable.
# Skip G3 when the message comes from HEREDOC, -F file, editor, or when
# the command contains escaped quotes (sed can't disambiguate safely).
MSG=""
heredoc_re='(^|[[:space:]]|\()<<-?[[:space:]]*["'"'"']?[A-Za-z_][A-Za-z0-9_]*'
has_heredoc=0
if printf '%s' "$CMD" | grep -qE "$heredoc_re"; then
  has_heredoc=1
fi
has_escaped_quotes=0
if printf '%s' "$CMD" | grep -q '\\"'; then
  has_escaped_quotes=1
fi
if [[ $has_heredoc -eq 0 && $has_escaped_quotes -eq 0 \
   && "$CMD" != *"-F "* && "$CMD" != *"--file="* ]]; then
  MSG=$(printf '%s' "$CMD" | sed -nE 's/.*-m[[:space:]]+"([^"]*)".*/\1/p')
  if [[ -z "$MSG" ]]; then
    MSG=$(printf '%s' "$CMD" | sed -nE "s/.*-m[[:space:]]+'([^']*)'.*/\\1/p")
  fi
  if [[ -z "$MSG" ]]; then
    MSG=$(printf '%s' "$CMD" | sed -nE 's/.*--message="([^"]*)".*/\1/p')
  fi
fi

# G3: conventional prefix + no WIP (when we have a parseable message).
if [[ -n "$MSG" ]]; then
  wip_re='^[Ww][Ii][Pp]([[:space:]]|:|$)'
  conv_re='^(feat|fix|chore|docs|refactor|test|style|perf|build|ci|revert)(\([^)]+\))?: '
  if [[ "$MSG" =~ $wip_re ]] || [[ "$MSG" =~ [Ww][Ii][Pp]$ ]]; then
    echo "pre-commit: G3 — WIP commits forbidden. Squash or rewrite." >&2
    exit 2
  fi
  if ! [[ "$MSG" =~ $conv_re ]]; then
    echo "pre-commit: G3 — commit message needs a conventional prefix (feat:, fix:, chore:, docs:, refactor:, test:, style:, perf:, build:, ci:, revert:)." >&2
    echo "  got: ${MSG:0:80}" >&2
    exit 2
  fi
fi

STAGED=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
[[ -n "$STAGED" ]] || exit 0

# G8: no console.log in staged TS/JS/TSX/JSX.
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  case "$f" in
    *.ts|*.tsx|*.js|*.jsx)
      if git show ":$f" 2>/dev/null | grep -nE '(^|[^.])console\.log\(' >/dev/null; then
        echo "pre-commit: G8 — console.log in $f. Remove or use a logger." >&2
        exit 2
      fi
      ;;
  esac
done <<< "$STAGED"

# G7: `: any` requires `// any:` comment on same line.
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  case "$f" in
    *.ts|*.tsx)
      while IFS= read -r line; do
        if [[ "$line" =~ :\ *any([^a-zA-Z]|$) ]] && ! [[ "$line" =~ //.*any: ]]; then
          echo "pre-commit: G7 — bare \`: any\` in $f. Add explanatory \`// any: <reason>\` comment." >&2
          echo "  $line" >&2
          exit 2
        fi
      done < <(git show ":$f" 2>/dev/null || true)
      ;;
  esac
done <<< "$STAGED"

# G12: no sleep/setTimeout in staged test files.
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  case "$f" in
    *test*|*spec*|*.test.*|*.spec.*)
      if git show ":$f" 2>/dev/null | grep -nE '(^|[^a-zA-Z_])(sleep|setTimeout)\(' >/dev/null; then
        echo "pre-commit: G12 — sleep/setTimeout in test $f. Fix root cause, don't paper over flakes." >&2
        exit 2
      fi
      ;;
  esac
done <<< "$STAGED"

exit 0
