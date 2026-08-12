#!/usr/bin/env bash
# End-to-end dry-run of every pilot hook with realistic Claude Code
# payloads. Closes the gap between unit fixtures and "does this actually
# behave the same way Claude Code drives it?"
#
# Spins up an isolated temp repo + cache dir, feeds each hook the JSON
# shape Claude Code documents (transcript_path, tool_name, tool_input,
# etc.), and reports a pass/fail per scenario. Returns non-zero if any
# scenario behaves unexpectedly.
#
# Run anytime — does NOT touch ~/.claude/settings.json, the real cache,
# or your working repo. Safe to wire into CI as a smoke test.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d -t pilot-dryrun-XXXXXX)
trap "rm -rf $TMP" EXIT
cd "$TMP"

export XDG_CACHE_HOME="$TMP/.cache"
mkdir -p "$XDG_CACHE_HOME/pilot"

# Minimal git repo so plan-gate's merge-base logic has something to
# work with.
git init -q -b main
git config user.email t@t.t
git config user.name t
echo "seed" > seed.txt
git add seed.txt
git commit -q -m "feat: seed"

# Fake JSONL transcript so transcript_path-aware hooks have something to
# point at (empty user-message history; no bypass phrases).
TRANSCRIPT="$TMP/transcript.jsonl"
: > "$TRANSCRIPT"

pass=0
fail=0
say() { printf "%s %s\n" "$1" "$2"; }
ok()   { say "✓" "$1"; pass=$((pass+1)); }
fail() { say "✗" "$1"; fail=$((fail+1)); }

assert_exit() {
  # $1 = expected exit, $2 = label, rest = command
  local want="$1" label="$2"; shift 2
  set +e
  "$@" >/dev/null 2>&1
  local got=$?
  set -e
  if [[ "$got" == "$want" ]]; then ok "$label (exit $got)"; else fail "$label (want $want, got $got)"; fi
}

mk_input() { jq -n --argjson payload "$1" --arg tp "$TRANSCRIPT" '$payload + {transcript_path: $tp}'; }

# ---- SessionStart banner ----
echo
echo "=== SessionStart banner ==="
out=$(bash "$ROOT/hooks/sessionstart-banner.sh")
if echo "$out" | grep -q '\[pilot active\] v'; then
  ok "emits versioned banner"
else
  fail "banner missing version header"
fi
echo "$out" | head -1 | sed 's/^/    /'

# ---- PreCompact anchor ----
echo
echo "=== PreCompact anchor ==="
out=$(echo '{"trigger":"manual"}' | bash "$ROOT/hooks/precompact-anchor.sh")
if echo "$out" | grep -q 'Routing' && echo "$out" | grep -q 'Bypass state'; then
  ok "emits routing anchor"
else
  fail "anchor missing routing/bypass sections"
fi

# ---- plan-gate (Edit ≤20 LOC) ----
echo
echo "=== plan-gate ==="
payload='{"tool_name":"Edit","tool_input":{"file_path":"a.ts","new_string":"line"}}'
assert_exit 0 "Edit ≤20 LOC allowed" bash -c "echo '$payload' | bash '$ROOT/hooks/plan-gate.sh'"

# ---- plan-gate (Edit >20 LOC, no plan) ----
big=$(printf 'line\n%.0s' {1..25})
payload=$(jq -n --arg s "$big" '{tool_name:"Edit",tool_input:{file_path:"a.ts",new_string:$s}}')
assert_exit 1 "Edit >20 LOC w/o plan blocked" bash -c "echo '$payload' | bash '$ROOT/hooks/plan-gate.sh'"

# ---- plan-gate (MultiEdit summing big) ----
chunk=$(printf 'line\n%.0s' {1..15})
payload=$(jq -n --arg s "$chunk" '{tool_name:"MultiEdit",tool_input:{edits:[{old_string:"a",new_string:$s},{old_string:"b",new_string:$s}]}}')
assert_exit 1 "MultiEdit summed >20 LOC blocked" bash -c "echo '$payload' | bash '$ROOT/hooks/plan-gate.sh'"

# ---- plan-gate (MultiEdit w/ plan present) ----
mkdir -p .planning/phase-1
echo "plan body" > .planning/phase-1/PLAN.md
git add .planning
git commit -q -m "docs: plan"
assert_exit 0 "MultiEdit big total allowed with plan" bash -c "echo '$payload' | bash '$ROOT/hooks/plan-gate.sh'"
# Clean up: hard reset back to the seed commit so the .planning history
# doesn't leak into subsequent scenarios.
git reset -q --hard HEAD~1
rm -rf .planning

# ---- plan-gate (NotebookEdit big) ----
payload=$(jq -n --arg s "$big" '{tool_name:"NotebookEdit",tool_input:{notebook_path:"n.ipynb",cell_id:"c1",new_source:$s,edit_mode:"replace"}}')
assert_exit 1 "NotebookEdit big new_source blocked" bash -c "echo '$payload' | bash '$ROOT/hooks/plan-gate.sh'"

# ---- plan-gate (bypass-once consumed) ----
touch "$XDG_CACHE_HOME/pilot/bypass-once"
payload=$(jq -n --arg s "$big" '{tool_name:"Edit",tool_input:{new_string:$s}}')
assert_exit 0 "bypass-once allows + consumes" bash -c "echo '$payload' | bash '$ROOT/hooks/plan-gate.sh'"
if [[ -f "$XDG_CACHE_HOME/pilot/bypass-once" ]]; then
  fail "bypass-once not consumed"
else
  ok "bypass-once consumed"
fi

# ---- pre-commit (Bash, non-git) ----
echo
echo "=== pre-commit ==="
payload='{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
assert_exit 0 "non-git Bash ignored" bash -c "echo '$payload' | bash '$ROOT/hooks/pre-commit.sh'"

# ---- pre-commit (clean staging, conventional msg) ----
echo "export const x = 1" > clean.ts
git add clean.ts
payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: x\""}}'
assert_exit 0 "clean staging + conventional msg allowed" bash -c "echo '$payload' | bash '$ROOT/hooks/pre-commit.sh'"
git reset clean.ts >/dev/null && rm clean.ts

# ---- pre-commit (WIP message blocked) ----
echo "export const y = 1" > y.ts
git add y.ts
payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"WIP: stuff\""}}'
assert_exit 1 "WIP msg blocked (G3)" bash -c "echo '$payload' | bash '$ROOT/hooks/pre-commit.sh'"
git reset y.ts >/dev/null && rm y.ts

# ---- pre-commit (console.log staged) ----
echo "console.log('bad')" > bad.ts
git add bad.ts
payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: bad\""}}'
assert_exit 1 "console.log blocked (G8)" bash -c "echo '$payload' | bash '$ROOT/hooks/pre-commit.sh'"
git reset bad.ts >/dev/null && rm bad.ts

# ---- pre-commit (per-gate bypass) ----
touch "$XDG_CACHE_HOME/pilot/bypass-precommit-once"
echo "console.log('still bad')" > b.ts
git add b.ts
payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: x\""}}'
assert_exit 0 "bypass-precommit-once allows" bash -c "echo '$payload' | bash '$ROOT/hooks/pre-commit.sh'"
[[ -f "$XDG_CACHE_HOME/pilot/bypass-precommit-once" ]] \
  && fail "bypass-precommit-once not consumed" \
  || ok "bypass-precommit-once consumed"
git reset b.ts >/dev/null && rm b.ts

# ---- verify-gate (done + evidence → silent) ----
echo
echo "=== verify-gate ==="
TR2="$TMP/t2.jsonl"
jq -n '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:"Ran bun test — 42 passed. Done."}]}}' > "$TR2"
out=$(echo "{\"transcript_path\":\"$TR2\",\"stop_hook_active\":true}" | bash "$ROOT/hooks/verify-gate.sh" 2>&1)
if echo "$out" | grep -q 'verify-gate'; then
  fail "false positive on done+evidence"
else
  ok "done + evidence → silent"
fi

# ---- verify-gate (done w/o evidence → warns) ----
# The gate only engages on turns that touched source files, so stage a
# code change first (it ignores analysis/docs-only turns).
echo "export const z = 1" > nag.ts && git add nag.ts
TR3="$TMP/t3.jsonl"
jq -n '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:"All done. Ready to ship."}]}}' > "$TR3"
out=$(echo "{\"transcript_path\":\"$TR3\",\"stop_hook_active\":true}" | bash "$ROOT/hooks/verify-gate.sh" 2>&1)
if echo "$out" | grep -q 'verify-gate'; then
  ok "bare done → warn"
else
  fail "missed bare-done"
fi
git reset nag.ts >/dev/null && rm -f nag.ts

# ---- verify-gate (done on docs-only turn → silent) ----
# Regression guard for the code-change gate: a bare "done" with only a
# non-source file changed must NOT warn.
echo "notes" > nag.md && git add nag.md
out=$(echo "{\"transcript_path\":\"$TR3\",\"stop_hook_active\":true}" | bash "$ROOT/hooks/verify-gate.sh" 2>&1)
if echo "$out" | grep -q 'verify-gate'; then
  fail "false positive on docs-only done"
else
  ok "bare done, docs-only change → silent"
fi
git reset nag.md >/dev/null && rm -f nag.md

# ---- Summary ----
echo
echo "================================"
total=$((pass + fail))
echo "Dry-run: $pass/$total passed, $fail failed."
if [[ $fail -gt 0 ]]; then
  echo "Real Claude Code invocation may behave differently — investigate failures above."
  exit 1
fi
echo "All hooks behaved as expected against realistic Claude Code payloads."
