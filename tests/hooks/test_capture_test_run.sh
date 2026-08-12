#!/usr/bin/env bash
# Test capture-test-run.sh: the PostToolUse(Bash) hook that records the REAL
# result of test-runner commands to a fact file ($CACHE/last-test-run), so
# verify-gate can require a genuine captured run instead of trusting the
# transcript. Runner recognition (incl. per-repo .pilot.json test_patterns)
# lives here now.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/plugins/pilot/hooks/capture-test-run.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
cd "$TMP"

export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$XDG_CACHE_HOME/pilot"
FACT="$XDG_CACHE_HOME/pilot/last-test-run"

# Build a PostToolUse(Bash) payload.
#   $1 command  $2 stdout  $3 stderr(optional)  $4 isError(optional, json bool)
mk() {
  jq -cn \
    --arg c "$1" --arg o "${2:-}" --arg e "${3:-}" \
    --argjson err "${4:-false}" --arg s "sess-1" --arg w "$TMP" \
    '{session_id:$s, cwd:$w, tool_name:"Bash",
      tool_input:{command:$c},
      tool_response:{stdout:$o, stderr:$e, isError:$err, interrupted:false}}'
}

# Case 1: passing pytest run → fact written, ok:true, command+session recorded.
rm -f "$FACT"
mk "pytest -q" "12 passed in 0.5s" | "$HOOK" >/dev/null 2>&1 || true
[[ -f "$FACT" ]] || { echo "FAIL: no fact file written for a real test run"; exit 1; }
jq -e '.ok == true' "$FACT" >/dev/null || { echo "FAIL: passing run should record ok:true"; exit 1; }
jq -e '.command == "pytest -q"' "$FACT" >/dev/null || { echo "FAIL: command not recorded"; exit 1; }
jq -e '.session_id == "sess-1"' "$FACT" >/dev/null || { echo "FAIL: session_id not recorded"; exit 1; }
echo "PASS: passing pytest run recorded ok:true"

# Case 2: failing run (real output shows failures) → ok:false.
rm -f "$FACT"
mk "pytest" "3 failed, 9 passed in 0.6s" | "$HOOK" >/dev/null 2>&1 || true
jq -e '.ok == false' "$FACT" >/dev/null || { echo "FAIL: failing run should record ok:false"; exit 1; }
echo "PASS: failing run recorded ok:false"

# Case 3: non-runner command → NO fact file written (and never clobbers one).
rm -f "$FACT"
mk "ls -la" "a.ts b.ts" | "$HOOK" >/dev/null 2>&1 || true
[[ ! -f "$FACT" ]] || { echo "FAIL: non-runner command wrote a fact file"; exit 1; }
echo "PASS: non-runner command writes nothing"

# Case 3b: a non-runner command must not clobber a prior valid pass.
mk "pytest -q" "10 passed" | "$HOOK" >/dev/null 2>&1 || true
mk "echo hi" "hi" | "$HOOK" >/dev/null 2>&1 || true
jq -e '.ok == true and .command == "pytest -q"' "$FACT" >/dev/null \
  || { echo "FAIL: non-runner command clobbered a valid capture"; exit 1; }
echo "PASS: non-runner command leaves prior capture intact"

# Case 4: tool error (non-zero exit surfaced as isError) → ok:false even if
# stdout happens to contain pass-like words.
rm -f "$FACT"
mk "pytest" "collected 5 items ... passed" "Traceback" true | "$HOOK" >/dev/null 2>&1 || true
jq -e '.ok == false' "$FACT" >/dev/null || { echo "FAIL: isError run should be ok:false"; exit 1; }
echo "PASS: tool-error run recorded ok:false"

# Case 5: many built-in runners are recognised (bun/vitest/nx/make/node --test).
for r in "bun test" "vitest run" "nx test web" "make test" "node --test"; do
  rm -f "$FACT"
  mk "$r" "All tests passed — 0 failed" | "$HOOK" >/dev/null 2>&1 || true
  [[ -f "$FACT" ]] && jq -e '.ok == true' "$FACT" >/dev/null \
    || { echo "FAIL: runner not recognised: $r"; exit 1; }
done
echo "PASS: built-in runners recognised (bun/vitest/nx/make/node --test)"

# Case 6: per-repo .pilot.json test_patterns extends the runner set, resolved
# from the git root even when the command runs in a subdirectory.
GITREPO="$TMP/gitrepo"
mkdir -p "$GITREPO/sub"
( cd "$GITREPO" && git init -q )
echo '{"test_patterns":["custom-suite"]}' > "$GITREPO/.pilot.json"
rm -f "$FACT"
jq -cn --arg c "custom-suite" --arg o "ok 5 — 0 failed" --arg s "sess-1" --arg w "$GITREPO/sub" \
  '{session_id:$s, cwd:$w, tool_name:"Bash", tool_input:{command:$c},
    tool_response:{stdout:$o, stderr:"", isError:false, interrupted:false}}' \
  | "$HOOK" >/dev/null 2>&1 || true
[[ -f "$FACT" ]] && jq -e '.ok == true' "$FACT" >/dev/null \
  || { echo "FAIL: .pilot.json test_patterns custom runner not captured from subdir"; exit 1; }
echo "PASS: .pilot.json custom runner captured (git-root resolution from subdir)"

# Case 7: malformed / empty stdin → no crash, no fact file.
rm -f "$FACT"
echo "" | "$HOOK" >/dev/null 2>&1 || true
echo "not json" | "$HOOK" >/dev/null 2>&1 || true
[[ ! -f "$FACT" ]] || { echo "FAIL: malformed input produced a fact file"; exit 1; }
echo "PASS: malformed input handled safely"

echo "ALL capture-test-run tests passed."
