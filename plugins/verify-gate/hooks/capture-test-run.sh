#!/usr/bin/env bash
# Pilot capture-test-run — PostToolUse(Bash) hook.
#
# Records the REAL result of test-runner commands to a fact file so verify-gate
# can require a genuine captured run instead of trusting transcript prose (which
# the model can fabricate). This is the trust anchor for G14: the result comes
# from the Bash tool's own output at execution time, not model-authored text.
#
# PostToolUse cannot block — this hook only observes and records. Best-effort:
# any error path exits 0 without touching the fact file.
#
# Fact file: $XDG_CACHE_HOME/pilot/last-test-run (JSON):
#   { "ts": <epoch>, "session_id": "...", "cwd": "...",
#     "command": "...", "ok": true|false }
#
# Runner recognition (incl. per-repo .pilot.json test_patterns) lives here.
set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
[[ -n "$INPUT" ]] || exit 0
printf '%s' "$INPUT" | jq empty >/dev/null 2>&1 || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[[ -n "$CMD" ]] || exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
if [[ -n "$CWD" && -d "$CWD" ]]; then cd "$CWD" 2>/dev/null || true; fi

# Built-in test runners. Keep conservative (bare command + word boundary) to
# avoid matching `make test-fixtures` etc. Mirrors verify-gate's historical set.
DEFAULT_RUNNERS='(pytest|npm test|npm run test|bun( run)? test|pnpm( run)? test|yarn( run)? test|cargo test|cargo nextest|go test|jest|vitest|nx test|mocha|tap|make test|gradle test|mvn test|sbt test|cabal test|stack test|dotnet test|phpunit|rspec|elixir test|mix test|node --test(-only)?)\b'

# Resolve .pilot.json: cwd first, else the git repo root (the command may run
# from a subdirectory). Used here only for runner extensions.
PILOT_JSON=""
if [[ -f .pilot.json ]]; then
  PILOT_JSON=".pilot.json"
else
  GITROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
  [[ -n "$GITROOT" && -f "$GITROOT/.pilot.json" ]] && PILOT_JSON="$GITROOT/.pilot.json"
fi

EXTRA_PATTERNS=""
if [[ -n "$PILOT_JSON" ]]; then
  EXTRA_PATTERNS=$(jq -r '.test_patterns[]? // empty' "$PILOT_JSON" 2>/dev/null | paste -sd'|' - 2>/dev/null || true)
fi

if [[ -n "$EXTRA_PATTERNS" ]]; then
  CORE=${DEFAULT_RUNNERS#(}
  CORE=${CORE%)\\b}
  RUNNERS="(${CORE}|${EXTRA_PATTERNS})\b"
else
  RUNNERS="$DEFAULT_RUNNERS"
fi

# Not a test run → nothing to record (and never clobber a prior capture).
printf '%s' "$CMD" | grep -Eq "$RUNNERS" || exit 0

# Pull the REAL command output + error signals from the tool response.
OUT=$(printf '%s' "$INPUT" | jq -r '
  (.tool_response // {}) as $r
  | if ($r | type) == "string" then $r
    else ([$r.stdout?, $r.stderr?] | map(select(. != null)) | join("\n")) end
' 2>/dev/null || true)
ISERR=$(printf '%s' "$INPUT" | jq -r '(.tool_response.isError // false) | tostring' 2>/dev/null || echo false)
INTR=$(printf '%s' "$INPUT" | jq -r '(.tool_response.interrupted // false) | tostring' 2>/dev/null || echo false)

# Pass / fail determination from the ACTUAL output.
# `^OK$` covers Python unittest's clean pass, which prints a bare OK on its own
# line — `OK \(` only matches the qualified form (`OK (skipped=1)`), so without
# it a fully green unittest suite was scored as a failure.
RESULTS='(passed|PASS|✓|✔|All tests pass|tests passed|0 failed|0 failures|0 errors|ok [0-9]+|^OK$|OK \(|pass [0-9]+|fail 0)'
# A non-zero count of failures/errors is a definite fail, even when the same
# line also says "N passed". `0 failed` won't match ([1-9] guard).
FAILED='([1-9][0-9]*) (failed|failures|errors)|FAILED|✗|✖|Traceback \(most recent'

ok=false
if [[ "$ISERR" != "true" && "$INTR" != "true" ]]; then
  if printf '%s' "$OUT" | grep -Eq "$FAILED"; then
    ok=false
  elif printf '%s' "$OUT" | grep -Eq "$RESULTS"; then
    ok=true
  fi
fi

SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
TS=$(date +%s 2>/dev/null || echo 0)

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pilot"
mkdir -p "$CACHE_DIR" 2>/dev/null || true
FACT="$CACHE_DIR/last-test-run"

jq -cn \
  --argjson ts "$TS" --arg s "$SESSION" --arg w "$CWD" --arg c "$CMD" --argjson ok "$ok" \
  '{ts:$ts, session_id:$s, cwd:$w, command:$c, ok:$ok}' \
  > "$FACT" 2>/dev/null || true

exit 0
