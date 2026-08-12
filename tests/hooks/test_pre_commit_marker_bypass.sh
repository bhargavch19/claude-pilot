#!/usr/bin/env bash
# Test pre-commit.sh marker-file bypass: bypass-precommit-once (own
# marker) is consumed before bypass-once (shared marker), so a
# /pilot-bypass --no-precommit doesn't accidentally swallow a /pilot-off
# intended for the next plan-gate fire in the same turn.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/hooks/pre-commit.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
cd "$TMP"
export XDG_CACHE_HOME="$TMP/.cache"
mkdir -p "$XDG_CACHE_HOME/pilot"

git init -q
git config user.email t@t.t
git config user.name t

call_hook() {
  jq -n --arg cmd "$1" '{tool_name:"Bash", tool_input:{command:$cmd}}' | "$HOOK"
}

# Stage a file with console.log so G8 would normally block.
echo "console.log('bad')" > bad.ts
git add bad.ts

# Baseline: gate active, no markers → block on G8.
set +e
call_hook 'git commit -m "feat: x"' >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 2 ]] || { echo "FAIL: baseline should block on G8 (got $rc)"; exit 1; }
echo "PASS: baseline blocks on G8"

# bypass-precommit-once → allow + consume.
touch "$XDG_CACHE_HOME/pilot/bypass-precommit-once"
call_hook 'git commit -m "feat: x"' >/dev/null
echo "PASS: bypass-precommit-once allows"
[[ -f "$XDG_CACHE_HOME/pilot/bypass-precommit-once" ]] \
  && { echo "FAIL: bypass-precommit-once not consumed"; exit 1; }
echo "PASS: bypass-precommit-once consumed"

# After consumption, gate re-engages.
set +e
call_hook 'git commit -m "feat: x"' >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 2 ]] || { echo "FAIL: gate should block after consumption"; exit 1; }
echo "PASS: gate re-engages after per-gate marker consumed"

# bypass-once → allow + consume (still works as catch-all).
touch "$XDG_CACHE_HOME/pilot/bypass-once"
call_hook 'git commit -m "feat: x"' >/dev/null
[[ -f "$XDG_CACHE_HOME/pilot/bypass-once" ]] && { echo "FAIL: bypass-once not consumed"; exit 1; }
echo "PASS: bypass-once still works as catch-all"

# Per-gate marker is preferred over shared marker (we set both — only
# bypass-precommit-once should be consumed, leaving bypass-once for
# plan-gate to pick up in this turn).
touch "$XDG_CACHE_HOME/pilot/bypass-precommit-once"
touch "$XDG_CACHE_HOME/pilot/bypass-once"
call_hook 'git commit -m "feat: x"' >/dev/null
[[ -f "$XDG_CACHE_HOME/pilot/bypass-precommit-once" ]] \
  && { echo "FAIL: per-gate marker not consumed"; exit 1; }
[[ -f "$XDG_CACHE_HOME/pilot/bypass-once" ]] \
  || { echo "FAIL: shared bypass-once eaten when per-gate marker available"; exit 1; }
echo "PASS: per-gate marker consumed before shared bypass-once"

echo "ALL pre-commit marker bypass tests passed."
