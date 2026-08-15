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

# NO transcript phrase-sniffing — markers only (see plan-gate.sh for why:
# skill/tool content lands as user-type transcript entries, so any doc that
# mentions "pilot off rails" — including pilot's own SKILL.md — would
# permanently poison a phrase grep). Typed phrases route via the model to
# /pilot-off | /pilot-off-rails, which write the markers checked above.

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

# --- Content gates (G7/G8/G12) -------------------------------------------
# TOCTOU: this hook runs BEFORE the command, so for `git add X && git commit`
# the index is still empty at check time. Two file sets are scanned:
#   STAGED  — already in the index (plain `git commit` flow), read via git show
#   PENDING — about to be staged by THIS command (`git add` in the same
#             command line, or `git commit -a`), read from the working tree
scan_content() { # $1 = path, $2 = content (full file text)
  local f="$1" content="$2" line
  case "$f" in
    *.ts|*.tsx|*.js|*.jsx)
      if printf '%s' "$content" | grep -qE '(^|[^.])console\.log\('; then
        echo "pre-commit: G8 — console.log in $f. Remove or use a logger." >&2
        return 1
      fi
      ;;
  esac
  case "$f" in
    *.ts|*.tsx)
      while IFS= read -r line; do
        if [[ "$line" =~ :\ *any([^a-zA-Z]|$) ]] && ! [[ "$line" =~ //.*any: ]]; then
          echo "pre-commit: G7 — bare \`: any\` in $f. Add explanatory \`// any: <reason>\` comment." >&2
          echo "  $line" >&2
          return 1
        fi
      done <<< "$content"
      ;;
  esac
  case "$f" in
    *test*|*spec*)
      if printf '%s' "$content" | grep -qE '(^|[^a-zA-Z_])(sleep|setTimeout)\('; then
        echo "pre-commit: G12 — sleep/setTimeout in test $f. Fix root cause, don't paper over flakes." >&2
        return 1
      fi
      ;;
  esac
  return 0
}

STAGED=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)

# PENDING: files this same command line is about to stage.
PENDING=""
PENDING_ALL=0
# `git add <pathspecs>` segments in the command (up to a separator).
while IFS= read -r seg; do
  [[ -n "$seg" ]] || continue
  seg=$(printf '%s' "$seg" | sed -E 's/^git[[:space:]]+add[[:space:]]+//')
  for tok in $seg; do
    case "$tok" in
      -A|--all|-u|--update) PENDING_ALL=1 ;;
      -*) ;;                                   # other flags — ignore
      *)
        if [[ -d "$tok" || "$tok" == "." ]]; then
          # Directory / dot pathspec: expand to its changed+untracked files.
          PENDING+=$(git status --porcelain 2>/dev/null \
            | awk -v p="$tok" '{f=$NF} p=="." || index(f, p)==1 {print f}')$'\n'
        else
          PENDING+="$tok"$'\n'
        fi
        ;;
    esac
  done
done < <(printf '%s' "$CMD" | grep -oE 'git[[:space:]]+add[[:space:]]+[^;&|]*' || true)
# `git commit -a` / `--all`: stages every modified tracked file. Flag scan
# runs on the command with quoted strings stripped, so "-a" inside a commit
# message can't false-positive.
FLAGSTR=$(printf '%s' "$CMD" | sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g")
if printf '%s' "$FLAGSTR" | grep -qE 'git[[:space:]]+commit[^;&|]*[[:space:]](-[a-zA-Z]*a[a-zA-Z]*|--all)([[:space:]]|$)'; then
  PENDING_ALL=1
fi
if [[ "$PENDING_ALL" == "1" ]]; then
  PENDING+=$(git status --porcelain 2>/dev/null | awk '{print $NF}')$'\n'
fi

[[ -n "$STAGED" || -n "${PENDING//[$'\n' ]/}" ]] || exit 0

while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  scan_content "$f" "$(git show ":$f" 2>/dev/null || true)" || exit 2
done <<< "$STAGED"

seen=$'\n'
while IFS= read -r f; do
  [[ -z "$f" || ! -f "$f" ]] && continue
  case "$seen" in *$'\n'"$f"$'\n'*) continue ;; esac
  seen+="$f"$'\n'
  scan_content "$f" "$(cat "$f" 2>/dev/null || true)" || exit 2
done <<< "$PENDING"

exit 0
