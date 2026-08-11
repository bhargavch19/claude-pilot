#!/usr/bin/env bash
# Pilot autoformat — PostToolUse(Edit|Write|MultiEdit) hook.
#
# Formats the just-edited file using the formatter the REPO ALREADY CONFIGURES.
# No matching config → no-op. This keeps it near-zero-risk: it never imposes a
# style the repo didn't opt into, and never reformats files in a repo with no
# formatter set up. Best-effort, never blocks (PostToolUse can't anyway).
#
# Disable per-repo with .pilot.json {"autoformat":"off"}; honors bypass markers.
set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
printf '%s' "$INPUT" | jq empty >/dev/null 2>&1 || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
case "$TOOL" in Edit|Write|MultiEdit) ;; *) exit 0 ;; esac

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
if [ -n "$CWD" ] && [ -d "$CWD" ]; then cd "$CWD" 2>/dev/null || true; fi

# Honor bypass markers (don't silently rewrite when the user went off-rails).
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pilot"
if compgen -G "$CACHE_DIR/bypass*" >/dev/null 2>&1 || [ -e "$CACHE_DIR/off-rails" ]; then
  exit 0
fi

# Resolve repo root for config detection.
GITROOT=$(git -C "$(dirname "$FILE")" rev-parse --show-toplevel 2>/dev/null || true)
ROOT="${GITROOT:-$(dirname "$FILE")}"

# Per-repo disable.
if [ -f "$ROOT/.pilot.json" ]; then
  AF=$(jq -r '.autoformat // empty' "$ROOT/.pilot.json" 2>/dev/null || true)
  if [ "$AF" = "off" ] || [ "$AF" = "false" ]; then exit 0; fi
fi

have() { command -v "$1" >/dev/null 2>&1; }

run_prettier() {
  local cfg=0 c
  for c in .prettierrc .prettierrc.json .prettierrc.js .prettierrc.cjs \
           .prettierrc.yaml .prettierrc.yml .prettierrc.json5 .prettierrc.toml \
           prettier.config.js prettier.config.cjs prettier.config.mjs; do
    if [ -f "$ROOT/$c" ]; then cfg=1; break; fi
  done
  if [ "$cfg" = "0" ] && [ -f "$ROOT/package.json" ]; then
    jq -e 'has("prettier")' "$ROOT/package.json" >/dev/null 2>&1 && cfg=1
  fi
  [ "$cfg" = "1" ] || return 1
  local bin=""
  [ -x "$ROOT/node_modules/.bin/prettier" ] && bin="$ROOT/node_modules/.bin/prettier"
  [ -z "$bin" ] && have prettier && bin="prettier"
  [ -z "$bin" ] && have npx && bin="npx --no-install prettier"
  [ -n "$bin" ] || return 1
  $bin --write "$FILE" >/dev/null 2>&1 || true
  echo "autoformat: prettier $FILE" >&2
  return 0
}

run_python() {
  local ruff=0 black=0
  { [ -f "$ROOT/ruff.toml" ] || [ -f "$ROOT/.ruff.toml" ]; } && ruff=1
  if [ -f "$ROOT/pyproject.toml" ]; then
    grep -q '\[tool\.ruff' "$ROOT/pyproject.toml" 2>/dev/null && ruff=1
    grep -q '\[tool\.black\]' "$ROOT/pyproject.toml" 2>/dev/null && black=1
  fi
  if [ "$ruff" = "1" ] && have ruff; then
    ruff format "$FILE" >/dev/null 2>&1 || true
    echo "autoformat: ruff $FILE" >&2; return 0
  fi
  if [ "$black" = "1" ] && have black; then
    black "$FILE" >/dev/null 2>&1 || true
    echo "autoformat: black $FILE" >&2; return 0
  fi
  return 1
}

ext="${FILE##*.}"
case "$ext" in
  js|jsx|ts|tsx|mjs|cjs|json|json5|css|scss|less|md|mdx|html|vue|yaml|yml)
    run_prettier || true ;;
  py)
    run_python || true ;;
  go)
    if have gofmt; then gofmt -w "$FILE" >/dev/null 2>&1 || true; echo "autoformat: gofmt $FILE" >&2; fi ;;
  rs)
    if [ -f "$ROOT/Cargo.toml" ] && have rustfmt; then rustfmt "$FILE" >/dev/null 2>&1 || true; echo "autoformat: rustfmt $FILE" >&2; fi ;;
esac

exit 0
