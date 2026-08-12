#!/usr/bin/env bash
# Integration test: wire-hooks.sh then unwire-hooks.sh leaves a clean
# settings.json. Uses HOME override so the real ~/.claude/settings.json
# is never touched.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
mkdir -p "$TMP/.claude"

# Seed: settings.json with a non-pilot hook that must survive both ops.
cat > "$TMP/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "/some/other/hook.sh"}]}
    ]
  }
}
EOF

# Wire.
HOME="$TMP" bash "$ROOT/plugins/pilot/dev/wire-hooks.sh" >/dev/null

# Assert: pilot hooks present, non-pilot hook still present.
if ! jq -e '.hooks.PreToolUse | map(.hooks[].command) | map(endswith("/hooks/plan-gate.sh")) | any' "$TMP/.claude/settings.json" >/dev/null; then
  echo "FAIL: plan-gate.sh not wired"
  exit 1
fi
if ! jq -e '.hooks.PreToolUse | map(.hooks[].command) | map(endswith("/hooks/pre-commit.sh")) | any' "$TMP/.claude/settings.json" >/dev/null; then
  echo "FAIL: pre-commit.sh not wired"
  exit 1
fi
if ! jq -e '.hooks.PreToolUse | map(.hooks[].command) | map(endswith("/hooks/safety-gate.sh")) | any' "$TMP/.claude/settings.json" >/dev/null; then
  echo "FAIL: safety-gate.sh not wired"
  exit 1
fi
if ! jq -e '.hooks.PreToolUse | map(.hooks[].command) | map(endswith("/hooks/pretooluse-heartbeat.sh")) | any' "$TMP/.claude/settings.json" >/dev/null; then
  echo "FAIL: pretooluse-heartbeat.sh not wired"
  exit 1
fi
if ! jq -e '.hooks.PreToolUse | map(select(.matcher == "Bash" and (.hooks[].command | endswith("/hooks/safety-gate.sh")))) | length > 0' "$TMP/.claude/settings.json" >/dev/null; then
  echo "FAIL: safety-gate matcher not set to Bash"
  exit 1
fi
if ! jq -e '.hooks.Stop | map(.hooks[].command) | map(endswith("/hooks/verify-gate.sh")) | any' "$TMP/.claude/settings.json" >/dev/null; then
  echo "FAIL: verify-gate.sh not wired"
  exit 1
fi
if ! jq -e '.hooks.SubagentStop | map(.hooks[].command) | map(endswith("/hooks/verify-gate.sh")) | any' "$TMP/.claude/settings.json" >/dev/null; then
  echo "FAIL: verify-gate.sh not wired on SubagentStop"
  exit 1
fi
if ! jq -e '.hooks.SessionStart | map(.hooks[].command) | map(endswith("/hooks/sessionstart-banner.sh")) | any' "$TMP/.claude/settings.json" >/dev/null; then
  echo "FAIL: sessionstart-banner.sh not wired"
  exit 1
fi
if ! jq -e '.hooks.SessionStart | map(.hooks[].command) | map(endswith("/hooks/integrity-check.sh")) | any' "$TMP/.claude/settings.json" >/dev/null; then
  echo "FAIL: integrity-check.sh not wired"
  exit 1
fi
if ! jq -e '.hooks.SessionStart | map(.hooks[].command) | map(endswith("/hooks/memory-surface.sh")) | any' "$TMP/.claude/settings.json" >/dev/null; then
  echo "FAIL: memory-surface.sh not wired"
  exit 1
fi
if ! jq -e '.hooks.PreCompact | map(.hooks[].command) | map(endswith("/hooks/precompact-anchor.sh")) | any' "$TMP/.claude/settings.json" >/dev/null; then
  echo "FAIL: precompact-anchor.sh not wired"
  exit 1
fi
if ! jq -e '.hooks.PostToolUse | map(.hooks[].command) | map(endswith("/hooks/log-skill-invocation.sh")) | any' "$TMP/.claude/settings.json" >/dev/null; then
  echo "FAIL: log-skill-invocation.sh not wired on PostToolUse"
  exit 1
fi
if ! jq -e '.hooks.PostToolUse | map(.hooks[].command) | map(endswith("/hooks/capture-test-run.sh")) | any' "$TMP/.claude/settings.json" >/dev/null; then
  echo "FAIL: capture-test-run.sh not wired on PostToolUse"
  exit 1
fi
if ! jq -e '.hooks.PostToolUse | map(.hooks[].command) | map(endswith("/hooks/autoformat.sh")) | any' "$TMP/.claude/settings.json" >/dev/null; then
  echo "FAIL: autoformat.sh not wired on PostToolUse"
  exit 1
fi
if ! jq -e '.hooks.PostToolUse | map(select(.matcher == "Edit|Write|MultiEdit" and (.hooks[].command | endswith("/hooks/autoformat.sh")))) | length > 0' "$TMP/.claude/settings.json" >/dev/null; then
  echo "FAIL: autoformat matcher not set to Edit|Write|MultiEdit"
  exit 1
fi
if ! jq -e '.hooks.PostToolUse | map(select(.matcher == "Bash" and (.hooks[].command | endswith("/hooks/capture-test-run.sh")))) | length > 0' "$TMP/.claude/settings.json" >/dev/null; then
  echo "FAIL: capture-test-run matcher not set to Bash"
  exit 1
fi
if ! jq -e '.hooks.UserPromptSubmit | map(.hooks[].command) | map(endswith("/hooks/route-advisor.sh")) | any' "$TMP/.claude/settings.json" >/dev/null; then
  echo "FAIL: route-advisor.sh not wired on UserPromptSubmit"
  exit 1
fi
if ! jq -e '.hooks.PostToolUse | map(select(.matcher == "Skill")) | length > 0' "$TMP/.claude/settings.json" >/dev/null; then
  echo "FAIL: log-skill-invocation matcher not set to Skill"
  exit 1
fi
# matcher should include MultiEdit and NotebookEdit
if ! jq -e '.hooks.PreToolUse | map(select((.matcher // "") | contains("MultiEdit") and contains("NotebookEdit"))) | length > 0' "$TMP/.claude/settings.json" >/dev/null; then
  echo "FAIL: plan-gate matcher missing MultiEdit/NotebookEdit"
  exit 1
fi
if ! jq -e '.hooks.PreToolUse | map(.hooks[].command) | index("/some/other/hook.sh")' "$TMP/.claude/settings.json" >/dev/null; then
  echo "FAIL: non-pilot hook lost during wire"
  exit 1
fi
echo "PASS: wire installs 13 pilot hooks (incl. pretooluse-heartbeat, safety-gate, capture-test-run, autoformat, integrity-check, memory-surface, route-advisor) and preserves foreign hook"

# Wire again — must be idempotent. plan-gate is wired in TWO matchers
# (Edit|Write|MultiEdit|NotebookEdit and Bash), so expect exactly 2 — and the
# re-wire must not grow that.
HOME="$TMP" bash "$ROOT/plugins/pilot/dev/wire-hooks.sh" >/dev/null
plan_count=$(jq '[.hooks.PreToolUse[].hooks[] | select(.command | endswith("/hooks/plan-gate.sh"))] | length' "$TMP/.claude/settings.json")
if [[ "$plan_count" != "2" ]]; then
  echo "FAIL: re-wiring changed plan-gate.sh count (expected 2: Edit + Bash, got $plan_count)"
  exit 1
fi
echo "PASS: wire is idempotent (plan-gate in Edit + Bash matchers)"

# Unwire.
HOME="$TMP" bash "$ROOT/plugins/pilot/dev/unwire-hooks.sh" >/dev/null

# Assert: no pilot hooks, non-pilot hook still there.
if jq -e '..|.command? | strings | endswith("/hooks/plan-gate.sh")' "$TMP/.claude/settings.json" 2>/dev/null | grep -q true; then
  echo "FAIL: pilot hook remained after unwire"
  exit 1
fi
if jq -e '..|.command? | strings | endswith("/hooks/log-skill-invocation.sh")' "$TMP/.claude/settings.json" 2>/dev/null | grep -q true; then
  echo "FAIL: log-skill-invocation.sh remained after unwire"
  exit 1
fi
if jq -e '..|.command? | strings | endswith("/hooks/capture-test-run.sh")' "$TMP/.claude/settings.json" 2>/dev/null | grep -q true; then
  echo "FAIL: capture-test-run.sh remained after unwire"
  exit 1
fi
if jq -e '..|.command? | strings | endswith("/hooks/safety-gate.sh")' "$TMP/.claude/settings.json" 2>/dev/null | grep -q true; then
  echo "FAIL: safety-gate.sh remained after unwire"
  exit 1
fi
if jq -e '..|.command? | strings | endswith("/hooks/autoformat.sh")' "$TMP/.claude/settings.json" 2>/dev/null | grep -q true; then
  echo "FAIL: autoformat.sh remained after unwire"
  exit 1
fi
if jq -e '..|.command? | strings | endswith("/hooks/integrity-check.sh")' "$TMP/.claude/settings.json" 2>/dev/null | grep -q true; then
  echo "FAIL: integrity-check.sh remained after unwire"
  exit 1
fi
if jq -e '..|.command? | strings | endswith("/hooks/pretooluse-heartbeat.sh")' "$TMP/.claude/settings.json" 2>/dev/null | grep -q true; then
  echo "FAIL: pretooluse-heartbeat.sh remained after unwire"
  exit 1
fi
if jq -e '..|.command? | strings | endswith("/hooks/memory-surface.sh")' "$TMP/.claude/settings.json" 2>/dev/null | grep -q true; then
  echo "FAIL: memory-surface.sh remained after unwire"
  exit 1
fi
if jq -e '..|.command? | strings | endswith("/hooks/route-advisor.sh")' "$TMP/.claude/settings.json" 2>/dev/null | grep -q true; then
  echo "FAIL: route-advisor.sh remained after unwire"
  exit 1
fi
if ! jq -e '..|.command? | strings | . == "/some/other/hook.sh"' "$TMP/.claude/settings.json" 2>/dev/null | grep -q true; then
  echo "FAIL: non-pilot hook lost during unwire"
  exit 1
fi
echo "PASS: unwire removes all pilot hooks and preserves foreign hook"

# Unwire again — must be idempotent (no error).
HOME="$TMP" bash "$ROOT/plugins/pilot/dev/unwire-hooks.sh" >/dev/null
echo "PASS: unwire is idempotent"

echo "ALL wire/unwire tests passed."
