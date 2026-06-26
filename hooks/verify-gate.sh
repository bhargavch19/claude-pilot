#!/usr/bin/env bash
# G14 enforcement: BLOCK when the assistant claims work is "done" / "ready" /
# "passing" with source files changed but NO real test run was captured this
# session. Trust is anchored on capture-test-run.sh's fact file (the Bash
# tool's actual output), not transcript prose — prose can be fabricated, a
# captured exit/result cannot. Runs on Stop and SubagentStop.
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

# Require a REAL captured test run, not transcript prose. capture-test-run.sh
# (PostToolUse/Bash) records the actual result of test commands to this fact
# file at execution time. The model can write "tests passed" into the
# transcript without running anything; it cannot fake the tool's own captured
# output. So we trust the fact file, not the prose.
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pilot"
CNT_FILE="$CACHE_DIR/verify-gate-blocks"
FACT="$CACHE_DIR/last-test-run"
mkdir -p "$CACHE_DIR" 2>/dev/null || true

SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)

# A capture clears the gate only when it passed AND belongs to this run:
# match by session_id when both sides have one, else fall back to a recency
# window (the Stop payload may omit session_id in older schemas / fixtures).
CAPTURE_OK=0
if [[ -f "$FACT" ]] && jq empty "$FACT" 2>/dev/null; then
  F_OK=$(jq -r '(.ok // false) | tostring' "$FACT" 2>/dev/null || echo false)
  F_SESS=$(jq -r '.session_id // empty' "$FACT" 2>/dev/null || true)
  F_TS=$(jq -r '.ts // 0' "$FACT" 2>/dev/null || echo 0)
  [[ "$F_TS" =~ ^[0-9]+$ ]] || F_TS=0
  if [[ "$F_OK" == "true" ]]; then
    if [[ -n "$SESSION" && -n "$F_SESS" ]]; then
      [[ "$SESSION" == "$F_SESS" ]] && CAPTURE_OK=1
    else
      NOW=$(date +%s 2>/dev/null || echo 0)
      [[ "$NOW" =~ ^[0-9]+$ ]] || NOW=0
      if [[ "$NOW" -gt 0 && $((NOW - F_TS)) -lt 14400 ]]; then CAPTURE_OK=1; fi
    fi
  fi
fi

if [[ "$CAPTURE_OK" == "1" ]]; then
  : > "$CNT_FILE" 2>/dev/null || true   # real captured pass → reset block counter
  exit 0
fi

# --- No real captured test run for a "done" claim on changed code: ENFORCE ---
MODE="block"

# Resolve .pilot.json: cwd first, else the git repo root. The Stop hook can run
# from a subdirectory (e.g. the shell was left in tests/), so a cwd-only lookup
# silently drops per-repo config. Walk up to the git root as a fallback.
PILOT_JSON=""
GITROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -f .pilot.json ]]; then
  PILOT_JSON=".pilot.json"
elif [[ -n "$GITROOT" && -f "$GITROOT/.pilot.json" ]]; then
  PILOT_JSON="$GITROOT/.pilot.json"
fi

VG_MODE=""
[[ -n "$PILOT_JSON" ]] && VG_MODE=$(jq -r '.verify_gate // empty' "$PILOT_JSON" 2>/dev/null || true)

# Session-wide bypass markers (pilot off / off-rails). Detected once here so
# run mode also respects them (don't execute a suite when the user bypassed).
BYPASSED=0
if compgen -G "$CACHE_DIR/bypass*" >/dev/null 2>&1 || [[ -e "$CACHE_DIR/off-rails" ]]; then
  BYPASSED=1
fi

# Portable command timeout: prefer timeout/gtimeout, fall back to perl's alarm
# (macOS ships perl but not GNU timeout). Last resort: run without a cap.
_vg_run_with_timeout() {
  local secs="$1" cmd="$2"
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" bash -c "$cmd"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" bash -c "$cmd"
  elif command -v perl >/dev/null 2>&1; then
    perl -e 'alarm shift @ARGV; exec @ARGV or exit 127' "$secs" bash -c "$cmd"
  else
    bash -c "$cmd"
  fi
}

RUN_NOTE=""

# Opt-in run mode: rather than trust any capture, the gate executes the repo's
# own test command and uses the REAL exit code — un-fakeable. Runs only on the
# enforce path (a "done" claim with no valid capture), so the suite runs lazily
# and at most once per session (a pass is recorded as a capture below).
#   .pilot.json: { "verify_gate":"run",
#                  "test_command":"bash tests/run.sh", "test_timeout":120 }
if [[ "$VG_MODE" == "run" && "$BYPASSED" == "0" ]]; then
  TEST_CMD=$(jq -r '.test_command // empty' "$PILOT_JSON" 2>/dev/null || true)
  if [[ -n "$TEST_CMD" ]]; then
    TIMEOUT=$(jq -r '.test_timeout // 120' "$PILOT_JSON" 2>/dev/null || echo 120)
    [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || TIMEOUT=120
    RUNROOT="${GITROOT:-$PWD}"
    if ( cd "$RUNROOT" && _vg_run_with_timeout "$TIMEOUT" "$TEST_CMD" >/dev/null 2>&1 ); then
      RC=0
    else
      RC=$?
    fi
    if [[ "$RC" == "0" ]]; then
      NOW=$(date +%s 2>/dev/null || echo 0)
      jq -cn --argjson ts "$NOW" --arg s "$SESSION" --arg w "$RUNROOT" --arg c "$TEST_CMD" \
        '{ts:$ts, session_id:$s, cwd:$w, command:$c, ok:true}' > "$FACT" 2>/dev/null || true
      : > "$CNT_FILE" 2>/dev/null || true   # real pass → reset block counter
      exit 0
    fi
    RUN_NOTE=" (verify_gate:run executed \`$TEST_CMD\` → exit $RC)"
  else
    RUN_NOTE=" (verify_gate:run set but no test_command in .pilot.json — cannot self-verify)"
  fi
fi

# Per-repo downgrade and session bypass both soften block → warn.
[[ "$VG_MODE" == "warn" ]] && MODE="warn"
[[ "$BYPASSED" == "1" ]] && MODE="warn"

# Anti-trap: release after 2 consecutive blocks so the gate can never loop.
CNT=0; [[ -f "$CNT_FILE" ]] && CNT=$(cat "$CNT_FILE" 2>/dev/null || echo 0)
[[ "$CNT" =~ ^[0-9]+$ ]] || CNT=0
if [[ "$MODE" == "block" && "$CNT" -ge 2 ]]; then
  MODE="warn"
fi

MSG='verify-gate: G14 — "done"/"ready" claimed and source changed, but no REAL test run was captured this session (transcript prose does not count). Actually run the project tests so their result is captured, then stop. Bypass: type "pilot off", or set {"verify_gate":"warn"} in .pilot.json.'
MSG="$MSG$RUN_NOTE"

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
