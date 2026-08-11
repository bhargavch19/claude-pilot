#!/usr/bin/env bash
# Test verify-gate.sh: BLOCKS a "done" claim on changed source unless a REAL
# test run was captured this session (capture-test-run.sh writes the fact file).
# Transcript prose no longer clears the gate — that was the trust hole this
# phase closes. Runner-variety recognition now lives in test_capture_test_run.sh.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/hooks/verify-gate.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
cd "$TMP"

# Isolate the gate's state dir (block counter, bypass markers, fact file).
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$XDG_CACHE_HOME/pilot"
FACT="$XDG_CACHE_HOME/pilot/last-test-run"
RESET() { rm -f "$XDG_CACHE_HOME"/pilot/verify-gate-blocks \
                 "$XDG_CACHE_HOME"/pilot/bypass-session \
                 "$XDG_CACHE_HOME"/pilot/off-rails \
                 "$FACT"; }

SESSION="sess-test"

mk_transcript() { # $1 = assistant text → JSONL transcript, returns path
  local f="$TMP/transcript.jsonl"
  : > "$f"
  jq -n --arg t "$1" '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:$t}]}}' >> "$f"
  printf '%s' "$f"
}
mk_input() { # $1 = transcript path
  jq -n --arg p "$1" --arg s "$SESSION" '{transcript_path:$p, session_id:$s, stop_hook_active:true}'
}
mk_fact() { # $1=ok(true|false)  [$2=session (default current)]  [$3=ts (default now)]
  local sess="${2-$SESSION}" ts="${3:-$(date +%s)}"
  jq -cn --arg s "$sess" --argjson ok "$1" --argjson ts "$ts" \
    '{ts:$ts, session_id:$s, command:"bash tests/run.sh", ok:$ok}' > "$FACT"
}

# ---- core contract: capture required, prose insufficient ----------------

# Case 1: done claim + valid captured pass (this session) → allow.
RESET; mk_fact true
t=$(mk_transcript "All done. Shipping.")
OUT=$(mk_input "$t" | "$HOOK" 2>&1 || true)
[[ "$OUT" != *"verify-gate"* ]] || { echo "FAIL: valid capture should clear the gate, got: $OUT"; exit 1; }
echo "PASS: done with a real captured pass is allowed"

# Case 2: done claim, fabricated prose, NO capture → flagged (the hole closed).
RESET
t=$(mk_transcript "I ran pytest and it passed: 12 passed. Done.")
OUT=$(mk_input "$t" | "$HOOK" 2>&1 || true)
[[ "$OUT" == *"verify-gate"* ]] || { echo "FAIL: prose-only 'tests passed' must NOT clear the gate"; exit 1; }
echo "PASS: fabricated 'tests passed' prose with no capture is flagged"

# Case 3: no done claim → not flagged (capture irrelevant).
RESET
t=$(mk_transcript "Working on it.")
OUT=$(mk_input "$t" | "$HOOK" 2>&1 || true)
[[ "$OUT" != *"verify-gate"* ]] || { echo "FAIL: false positive on neutral message"; exit 1; }
echo "PASS: neutral message not flagged"

# Case 4: done claim + captured FAILURE (ok:false) → flagged.
RESET; mk_fact false
t=$(mk_transcript "All done. Shipping.")
OUT=$(mk_input "$t" | "$HOOK" 2>&1 || true)
[[ "$OUT" == *"verify-gate"* ]] || { echo "FAIL: a failing captured run must not clear the gate"; exit 1; }
echo "PASS: captured failing run is flagged"

# Case 5: done claim + capture from a DIFFERENT session → flagged.
RESET; mk_fact true "some-other-session"
t=$(mk_transcript "All done. Shipping.")
OUT=$(mk_input "$t" | "$HOOK" 2>&1 || true)
[[ "$OUT" == *"verify-gate"* ]] || { echo "FAIL: another session's capture must not clear the gate"; exit 1; }
echo "PASS: cross-session capture is flagged"

# Case 6: recency fallback — capture has no session id but is fresh → allow.
RESET; mk_fact true ""
t=$(mk_transcript "All done.")
OUT=$(mk_input "$t" | "$HOOK" 2>&1 || true)
[[ "$OUT" != *"verify-gate"* ]] || { echo "FAIL: fresh session-less capture should clear via recency"; exit 1; }
echo "PASS: fresh session-less capture cleared via recency fallback"

# Case 7: recency fallback — session-less capture older than the window → flagged.
RESET; mk_fact true "" "$(( $(date +%s) - 20000 ))"
t=$(mk_transcript "All done.")
OUT=$(mk_input "$t" | "$HOOK" 2>&1 || true)
[[ "$OUT" == *"verify-gate"* ]] || { echo "FAIL: stale session-less capture must not clear the gate"; exit 1; }
echo "PASS: stale session-less capture is flagged"

# ---- inline-transcript fallback (legacy .transcript[] payloads) ----------

# Case 8: legacy inline format, done + valid capture → allow.
RESET; mk_fact true
INPUT=$(jq -n --arg s "$SESSION" '{session_id:$s, transcript:[{role:"assistant", content:"All done. Ready to ship."}]}')
OUT=$(printf '%s' "$INPUT" | "$HOOK" 2>&1 || true)
[[ "$OUT" != *"verify-gate"* ]] || { echo "FAIL: legacy inline + capture should allow"; exit 1; }
echo "PASS: legacy inline done with capture allowed"

# Case 9: legacy inline format, done + no capture → flagged.
RESET
INPUT=$(jq -n --arg s "$SESSION" '{session_id:$s, transcript:[{role:"assistant", content:"All done. Ready to ship."}]}')
OUT=$(printf '%s' "$INPUT" | "$HOOK" 2>&1 || true)
[[ "$OUT" == *"verify-gate"* ]] || { echo "FAIL: legacy inline done without capture should flag"; exit 1; }
echo "PASS: legacy inline done without capture flagged"

# ---- schema-drift diagnostic (independent of capture) --------------------

# Case 10: non-empty transcript our jq can't parse → surface a diagnostic.
RESET
FAKE_TRANSCRIPT="$TMP/schema-drift.jsonl"
cat > "$FAKE_TRANSCRIPT" <<'EOF'
{"type":"unknown","payload":{"weird_field":"some text we cannot parse"}}
{"type":"unknown","payload":{"weird_field":"another line"}}
EOF
STDERR=$(jq -n --arg t "$FAKE_TRANSCRIPT" '{transcript_path:$t}' | "$HOOK" 2>&1 1>/dev/null || true)
echo "$STDERR" | grep -q 'schema may have changed' || { echo "FAIL: schema-drift diagnostic missing, got: $STDERR"; exit 1; }
echo "PASS: schema-drift surfaced on unparseable transcript"

# ---- code-change gating --------------------------------------------------
# A "done" claim on a turn that touched no source files should not trip the
# gate even with no capture. Exercised inside a real git repo.
GITREPO="$TMP/gitrepo"
mkdir -p "$GITREPO"
( cd "$GITREPO" && git init -q )

# Case 11: done, clean working tree (no code changed) → not flagged.
RESET
t=$(mk_transcript "All done. Shipping.")
OUT=$( cd "$GITREPO" && mk_input "$t" | "$HOOK" 2>&1 || true )
[[ "$OUT" != *"verify-gate"* ]] || { echo "FAIL: flagged done on a no-code-change turn"; exit 1; }
echo "PASS: done on clean repo (no source touched) not flagged"

# Case 12: done + changed source, no capture → flagged.
RESET
( cd "$GITREPO" && echo "export const x = 1;" > mod.ts )
t=$(mk_transcript "All done. Shipping.")
OUT=$( cd "$GITREPO" && mk_input "$t" | "$HOOK" 2>&1 || true )
[[ "$OUT" == *"verify-gate"* ]] || { echo "FAIL: missed done with source changed"; exit 1; }
echo "PASS: done with source changed (no capture) flagged"

# Case 13: done, only a non-code file changed → not flagged.
RESET
( cd "$GITREPO" && rm -f mod.ts && echo "# notes" > NOTES.md )
t=$(mk_transcript "All done. Shipping.")
OUT=$( cd "$GITREPO" && mk_input "$t" | "$HOOK" 2>&1 || true )
[[ "$OUT" != *"verify-gate"* ]] || { echo "FAIL: flagged done on a docs-only change"; exit 1; }
echo "PASS: done on docs-only change not flagged"
( cd "$GITREPO" && rm -f NOTES.md )

# ---- block vs warn contract ----------------------------------------------
BLOCKREPO="$TMP/blockrepo"
mkdir -p "$BLOCKREPO"
( cd "$BLOCKREPO" && git init -q && echo "export const y = 1;" > a.ts )
tdone=$(mk_transcript "All done. Shipping.")

# Case 14: done + changed source, no capture, no bypass → decision:block.
RESET
OUT=$( cd "$BLOCKREPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
[[ "$OUT" == *'"decision":"block"'* ]] || { echo "FAIL: expected decision:block on stdout, got: $OUT"; exit 1; }
echo "PASS: flagged turn emits Stop block decision"

# Case 15: bypass-session marker → warn, never blocks.
RESET; touch "$XDG_CACHE_HOME/pilot/bypass-session"
OUT=$( cd "$BLOCKREPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
[[ "$OUT" != *'"decision":"block"'* ]] || { echo "FAIL: bypass-session should downgrade block→warn"; exit 1; }
echo "PASS: bypass-session downgrades block→warn"

# Case 16: off-rails marker → warn, never blocks.
RESET; touch "$XDG_CACHE_HOME/pilot/off-rails"
OUT=$( cd "$BLOCKREPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
[[ "$OUT" != *'"decision":"block"'* ]] || { echo "FAIL: off-rails should downgrade block→warn"; exit 1; }
echo "PASS: off-rails downgrades block→warn"

# Case 17: per-repo .pilot.json verify_gate:warn → warn, never blocks.
RESET; echo '{"verify_gate":"warn"}' > "$BLOCKREPO/.pilot.json"
OUT=$( cd "$BLOCKREPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
[[ "$OUT" != *'"decision":"block"'* ]] || { echo "FAIL: .pilot.json verify_gate:warn should downgrade"; exit 1; }
echo "PASS: .pilot.json verify_gate:warn downgrades block→warn"
rm -f "$BLOCKREPO/.pilot.json"

# Case 18: anti-trap — first two block, third auto-releases to warn.
RESET
b1=$( cd "$BLOCKREPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
b2=$( cd "$BLOCKREPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
b3=$( cd "$BLOCKREPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
{ [[ "$b1" == *'"decision":"block"'* ]] && [[ "$b2" == *'"decision":"block"'* ]]; } \
  || { echo "FAIL: first two turns should block"; exit 1; }
[[ "$b3" != *'"decision":"block"'* ]] || { echo "FAIL: anti-trap should release on 3rd consecutive block"; exit 1; }
echo "PASS: anti-trap releases after 2 consecutive blocks"

# Case 19: .pilot.json at the git root honored from a SUBDIRECTORY (the warn
# downgrade must still resolve config when the Stop hook runs from a subdir).
RESET
echo '{"verify_gate":"warn"}' > "$BLOCKREPO/.pilot.json"
mkdir -p "$BLOCKREPO/sub/dir"
OUT=$( cd "$BLOCKREPO/sub/dir" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
[[ "$OUT" != *'"decision":"block"'* ]] || { echo "FAIL: git-root .pilot.json not honored from subdir, got: $OUT"; exit 1; }
echo "PASS: .pilot.json resolved from git root when cwd is a subdirectory"
rm -f "$BLOCKREPO/.pilot.json"

# ---- opt-in run mode: gate executes the test command itself --------------

# Case 20: verify_gate:run + passing command → allow AND record a capture.
RESET; echo '{"verify_gate":"run","test_command":"true"}' > "$BLOCKREPO/.pilot.json"
OUT=$( cd "$BLOCKREPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
[[ "$OUT" != *'"decision":"block"'* ]] || { echo "FAIL: run mode passing command should allow"; exit 1; }
jq -e '.ok == true' "$FACT" >/dev/null || { echo "FAIL: run mode should record a passing capture"; exit 1; }
echo "PASS: run mode executes the command and a real pass allows"
rm -f "$BLOCKREPO/.pilot.json"

# Case 21: verify_gate:run + failing command → block, message cites exit code.
RESET; echo '{"verify_gate":"run","test_command":"false"}' > "$BLOCKREPO/.pilot.json"
OUT=$( cd "$BLOCKREPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
[[ "$OUT" == *'"decision":"block"'* ]] || { echo "FAIL: run mode failing command should block"; exit 1; }
[[ "$OUT" == *"verify_gate:run executed"* ]] || { echo "FAIL: block message should cite the run, got: $OUT"; exit 1; }
echo "PASS: run mode failing command blocks with exit-code note"
rm -f "$BLOCKREPO/.pilot.json"

# Case 22: verify_gate:run with no test_command → cannot self-verify → block.
RESET; echo '{"verify_gate":"run"}' > "$BLOCKREPO/.pilot.json"
OUT=$( cd "$BLOCKREPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
[[ "$OUT" == *'"decision":"block"'* ]] || { echo "FAIL: run mode w/o test_command should block"; exit 1; }
echo "PASS: run mode without a command blocks (cannot self-verify)"
rm -f "$BLOCKREPO/.pilot.json"

# Case 23: verify_gate:run + slow command over the timeout → block.
RESET; echo '{"verify_gate":"run","test_command":"sleep 5","test_timeout":1}' > "$BLOCKREPO/.pilot.json"
OUT=$( cd "$BLOCKREPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
[[ "$OUT" == *'"decision":"block"'* ]] || { echo "FAIL: run mode should block when the suite times out"; exit 1; }
echo "PASS: run mode enforces the test_timeout"
rm -f "$BLOCKREPO/.pilot.json"

# Case 24: bypass marker present → run mode does NOT execute (warn, no block).
RESET; touch "$XDG_CACHE_HOME/pilot/off-rails"
echo '{"verify_gate":"run","test_command":"false"}' > "$BLOCKREPO/.pilot.json"
OUT=$( cd "$BLOCKREPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
[[ "$OUT" != *'"decision":"block"'* ]] || { echo "FAIL: bypass should skip run mode and downgrade to warn"; exit 1; }
echo "PASS: bypass skips run mode (no suite executed, warn only)"
rm -f "$BLOCKREPO/.pilot.json"

echo "ALL verify-gate tests passed."
