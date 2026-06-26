#!/usr/bin/env bash
# G14 enforcement: BLOCK when the assistant claims work is "done" / "ready" /
# "passing" without visible test-suite evidence in the transcript AND source
# files changed. Runs on Stop and SubagentStop.
#
# Safety rails (cannot trap the user):
#   - Honors pilot bypass markers ($CACHE/bypass*, $CACHE/off-rails) → warn.
#   - Per-repo downgrade: .pilot.json { "verify_gate": "warn" } → warn.
#   - Auto-releases after 2 consecutive blocks so it can never loop.
#
# Per-repo overrides: add `.pilot.json` at the repo root with extra
# runner regexes:
#   { "test_patterns": ["rake test", "my-custom-runner"], "verify_gate": "warn" }
set -euo pipefail

INPUT=$(cat)

if [[ -z "$INPUT" ]] || ! printf '%s' "$INPUT" | jq empty 2>/dev/null; then
  echo "verify-gate: stdin missing or not valid JSON — gate declining to enforce." >&2
  exit 0
fi

# Stop hook input includes transcript_path; the JSONL file holds the
# message history. Older inline `.transcript[]` payloads are supported
# as a fallback so existing fixtures keep working.
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)

if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
  LAST=$(jq -r '
    select(.type=="assistant")
    | (.message.content // [])
    | if type=="array" then (map(select(.type=="text") | .text) | join("\n"))
      else (. | tostring) end
  ' "$TRANSCRIPT" 2>/dev/null | tail -200 || true)

  # Schema-drift detection: transcript exists and is non-empty, but our jq
  # expression yielded nothing. Either Claude Code's JSONL schema changed or
  # this turn was tool-only (no text). The second case is benign; the first
  # is silent rot. Surface a diagnostic so failures are visible early.
  if [[ -z "$LAST" ]]; then
    TRANSCRIPT_LINES=$(wc -l < "$TRANSCRIPT" 2>/dev/null || echo 0)
    if (( TRANSCRIPT_LINES > 0 )); then
      # Re-try with a permissive fallback: grab any `text` field anywhere in
      # the last 50 lines. Catches schema variants where .message.content
      # was renamed (e.g., to .content or .delta.text).
      LAST=$(tail -50 "$TRANSCRIPT" 2>/dev/null \
        | jq -r '[.. | objects | .text? // empty] | join("\n")' 2>/dev/null \
        | tail -200 || true)

      if [[ -z "$LAST" ]]; then
        echo "verify-gate: transcript has $TRANSCRIPT_LINES lines but yielded no text — schema may have changed; gate inactive this turn." >&2
        exit 0
      fi
    fi
  fi
else
  LAST=$(echo "$INPUT" | jq -r '[.transcript[]? | select(.role=="assistant") | .content] | .[-5:] | join("\n")' 2>/dev/null || true)
fi

[[ -n "$LAST" ]] || exit 0

# Detect a "done" claim.
if ! echo "$LAST" | grep -iqE '\b(done|complete|completed|ready|fixed|passing|all green)\b'; then
  exit 0
fi

# Only nag when code actually changed in the working tree. A "done" claim on
# a pure analysis / docs / planning turn (no source touched) shouldn't trip
# the test gate. Inside a git repo with no changed code files → skip.
# Outside git (or on git error) → fall through to the original behavior.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  CODE_CHANGED=$(git status --porcelain 2>/dev/null \
    | grep -iE '\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|rb|java|kt|swift|m|c|cc|cpp|h|hpp|cs|php|ex|exs|scala|clj|sh)$' \
    | head -1 || true)
  if [[ -z "$CODE_CHANGED" ]]; then
    exit 0
  fi
fi

# Built-in test runners. Conservative regex: bare command followed by space
# or end-of-line to avoid matching `make test-fixtures` etc.
DEFAULT_RUNNERS='(pytest|npm test|npm run test|bun( run)? test|pnpm( run)? test|yarn( run)? test|cargo test|cargo nextest|go test|jest|vitest|nx test|mocha|tap|make test|gradle test|mvn test|sbt test|cabal test|stack test|dotnet test|phpunit|rspec|elixir test|mix test|node --test(-only)?)\b'

# Resolve .pilot.json: cwd first, else the git repo root. The Stop hook can run
# from a subdirectory (e.g. the shell was left in tests/), so a cwd-only lookup
# silently drops per-repo config. Walk up to the git root as a fallback.
PILOT_JSON=""
if [[ -f .pilot.json ]]; then
  PILOT_JSON=".pilot.json"
else
  GITROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
  [[ -n "$GITROOT" && -f "$GITROOT/.pilot.json" ]] && PILOT_JSON="$GITROOT/.pilot.json"
fi

# Per-repo runner extensions via .pilot.json. (YAML support dropped in 0.3.0:
# the awk-based parser couldn't handle quoted values, multi-key files, or
# indented blocks reliably. Use jq + JSON.)
EXTRA_PATTERNS=""
if [[ -n "$PILOT_JSON" ]]; then
  EXTRA_PATTERNS=$(jq -r '.test_patterns[]? // empty' "$PILOT_JSON" 2>/dev/null | paste -sd'|' - 2>/dev/null || true)
fi

if [[ -n "$EXTRA_PATTERNS" ]]; then
  # Strip the leading `(` and trailing `)\b` from DEFAULT_RUNNERS, then union.
  CORE=${DEFAULT_RUNNERS#(}
  CORE=${CORE%)\\b}
  RUNNERS="(${CORE}|${EXTRA_PATTERNS})\b"
else
  RUNNERS="$DEFAULT_RUNNERS"
fi

RESULTS='(passed|PASS|✓|✔|All tests pass|tests passed|0 failed|0 failures|0 errors|ok [0-9]+|OK \(|pass [0-9]+|fail 0)'

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pilot"
CNT_FILE="$CACHE_DIR/verify-gate-blocks"
mkdir -p "$CACHE_DIR" 2>/dev/null || true

if echo "$LAST" | grep -qE "$RUNNERS" && echo "$LAST" | grep -qE "$RESULTS"; then
  : > "$CNT_FILE" 2>/dev/null || true   # evidence present → reset block counter
  exit 0
fi

# --- No evidence for a "done" claim on changed code: ENFORCE ---
MODE="block"

# Per-repo downgrade (uses the resolved .pilot.json, cwd or git root).
if [[ -n "$PILOT_JSON" ]]; then
  M=$(jq -r '.verify_gate // empty' "$PILOT_JSON" 2>/dev/null || true)
  [[ "$M" == "warn" ]] && MODE="warn"
fi

# Session-wide bypass markers (pilot off / off-rails). Uses compgen (no pipe)
# so it stays correct under `set -o pipefail` even when a glob has no match.
if compgen -G "$CACHE_DIR/bypass*" >/dev/null 2>&1 || [[ -e "$CACHE_DIR/off-rails" ]]; then
  MODE="warn"
fi

# Anti-trap: release after 2 consecutive blocks so the gate can never loop.
CNT=0; [[ -f "$CNT_FILE" ]] && CNT=$(cat "$CNT_FILE" 2>/dev/null || echo 0)
[[ "$CNT" =~ ^[0-9]+$ ]] || CNT=0
if [[ "$MODE" == "block" && "$CNT" -ge 2 ]]; then
  MODE="warn"
fi

MSG='verify-gate: G14 — "done"/"ready" claimed, source changed, but no test-suite evidence in the transcript. Run the project tests and quote the result (or superpowers:verification-before-completion). Bypass: type "pilot off", or set {"verify_gate":"warn"} in .pilot.json.'

if [[ "$MODE" == "block" ]]; then
  echo $((CNT + 1)) > "$CNT_FILE" 2>/dev/null || true
  # Stop-hook block: refuse the stop and feed the reason back to the model.
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg r "$MSG" '{decision:"block", reason:$r}'
  else
    printf '{"decision":"block","reason":"%s"}\n' "$MSG"
  fi
  exit 0
fi

: > "$CNT_FILE" 2>/dev/null || true       # warn path → reset counter
echo "$MSG" >&2
exit 0
