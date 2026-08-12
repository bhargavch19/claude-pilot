#!/usr/bin/env bash
# Demo harness for the verify-gate GIF (driven by demo/demo.tape via vhs).
#
# Everything the gate does here is REAL: the actual hook scripts run against
# a scratch project, the test run is a real `node --test`, and the captured
# exit code is what clears the gate. The only simulated part is the agent's
# transcript line — this harness plays the role of Claude Code's Stop event.
#
# Source me from the repo root:  source demo/scene.sh

HOOKS="$(pwd)/plugins/verify-gate/hooks"

DEMO_TMP=$(mktemp -d)
export XDG_CACHE_HOME="$DEMO_TMP/cache"   # isolated gate state, nothing global
DEMO_SESSION="demo-$(date +%s)"
TRANSCRIPT="$DEMO_TMP/transcript.jsonl"

# A scratch project with an (uncommitted) source change — the situation the
# gate cares about.
PROJ="$DEMO_TMP/acme-app"
mkdir -p "$PROJ"
cd "$PROJ" || return
git init -q
cat > parser.js <<'EOF'
export const parse = (s) => s.trim().split(/\s+/);
EOF
cat > parser.test.mjs <<'EOF'
import { test } from 'node:test';
import assert from 'node:assert';
import { parse } from './parser.js';
test('splits on whitespace', () => assert.deepEqual(parse(' a  b '), ['a', 'b']));
test('handles single token', () => assert.deepEqual(parse('x'), ['x']));
EOF
cat > package.json <<'EOF'
{ "name": "acme-app", "type": "module" }
EOF

BOLD=$'\e[1m'; RED=$'\e[31m'; GREEN=$'\e[32m'; DIM=$'\e[2m'; CYAN=$'\e[36m'; R=$'\e[0m'

clear
echo "${BOLD}verify-gate${R} ${DIM}— your agent says \"tests pass\". Did they?${R}"
echo "${DIM}scratch project: acme-app (parser.js changed, tests not yet run)${R}"

# The agent ends its turn with a claim → Claude Code fires the Stop hook.
agent_says() {
  local text="$1"
  echo
  echo "${CYAN}🤖 claude:${R} \"$text\""
  jq -cn --arg t "$text" \
    '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:$t}]}}' \
    >> "$TRANSCRIPT"
  local out
  out=$(jq -cn --arg tp "$TRANSCRIPT" --arg s "$DEMO_SESSION" \
        '{transcript_path:$tp, stop_hook_active:true, session_id:$s}' \
        | bash "$HOOKS/verify-gate.sh" 2>&1)
  if [[ -n "$out" ]]; then
    local reason
    reason=$(printf '%s' "$out" | jq -r '.reason // empty' 2>/dev/null || true)
    [[ -n "$reason" ]] || reason="$out"
    echo "${RED}${BOLD}⛔ BLOCKED by Stop hook${R}"
    echo "${RED}${reason}${R}" | fold -s -w 92 | sed 's/^/   /'
  else
    echo "${GREEN}${BOLD}✅ verify-gate: real captured pass found — claim allowed${R}"
  fi
}

# A real test run → Claude Code fires PostToolUse(Bash) → the hook records
# the ACTUAL result to the fact file.
run_tests() {
  echo
  echo "${DIM}\$ node --test${R}"
  local out rc
  out=$(node --test 2>&1); rc=$?
  echo "$out" | grep -E '✔|✖|^. (tests|pass|fail) ' | head -6 | sed 's/^/   /'
  jq -cn --arg c "node --test" --arg o "$out" --arg w "$PWD" --arg s "$DEMO_SESSION" \
    '{tool_input:{command:$c}, tool_response:{stdout:$o, isError:false}, cwd:$w, session_id:$s}' \
    | bash "$HOOKS/capture-test-run.sh"
  echo "${GREEN}📼 capture-test-run: recorded real result → ok=$(jq -r '.ok' "$XDG_CACHE_HOME/pilot/last-test-run") (exit $rc, session-bound)${R}"
}
