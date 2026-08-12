#!/usr/bin/env bash
# Test plan-gate.sh Bash coverage: a large code write done through Bash
# (cat >, tee, heredoc) is gated like an Edit/Write, closing the gap where
# shell-authored files bypassed the plan gate. Non-code / small writes pass.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/plugins/pilot/hooks/plan-gate.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
cd "$TMP"
git init -q
export XDG_CACHE_HOME="$TMP/cache"; mkdir -p "$XDG_CACHE_HOME/pilot"
RESET() { rm -f "$XDG_CACHE_HOME"/pilot/bypass-* "$XDG_CACHE_HOME"/pilot/off-rails; }

mk() { jq -cn --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}'; }
rc_of() { local rc=0; mk "$1" | "$HOOK" >/dev/null 2>&1 || rc=$?; echo "$rc"; }

# Build a >20-line heredoc that writes a .js file.
big_body=$(for i in $(seq 1 25); do echo "const v$i = $i;"; done)
BIG_JS=$(printf 'cat > app.js <<%sEOF%s\n%s\nEOF\n' "'" "'" "$big_body")
# A small (<20 line) code write.
SMALL_JS=$'cat > tiny.js <<EOF\nconst a = 1;\nEOF'
# A big NON-code write (docs).
BIG_MD=$(printf 'cat > notes.md <<EOF\n%s\nEOF\n' "$big_body")

# Case 1: big code write, no plan → BLOCK (exit 2) with G1.
RESET
[[ "$(rc_of "$BIG_JS")" == "2" ]] || { echo "FAIL: big Bash code write should block without a plan"; exit 1; }
out=$(mk "$BIG_JS" | "$HOOK" 2>&1 || true)
echo "$out" | grep -q "G1" || { echo "FAIL: expected G1 message, got: $out"; exit 1; }
echo "PASS: large code write via Bash heredoc is gated"

# Case 2: same write but a plan exists → ALLOW.
RESET
mkdir -p docs/superpowers/plans && echo "# plan" > docs/superpowers/plans/x.md
[[ "$(rc_of "$BIG_JS")" == "0" ]] || { echo "FAIL: should allow when a plan exists"; exit 1; }
rm -rf docs/superpowers
echo "PASS: large Bash code write allowed when a plan exists"

# Case 3: small code write → ALLOW (under the 20-line threshold).
RESET
[[ "$(rc_of "$SMALL_JS")" == "0" ]] || { echo "FAIL: small code write should pass"; exit 1; }
echo "PASS: small code write is not gated"

# Case 4: big NON-code write (docs) → ALLOW (plan-gate guards code, not prose).
RESET
[[ "$(rc_of "$BIG_MD")" == "0" ]] || { echo "FAIL: docs write should not be gated"; exit 1; }
echo "PASS: large non-code write is not gated"

# Case 5: a long Bash pipeline that writes no code file → ALLOW.
RESET
PIPE=$(printf 'echo start\n%s\nls -la | sort | uniq\n' "$big_body")
[[ "$(rc_of "$PIPE")" == "0" ]] || { echo "FAIL: non-writing pipeline should pass"; exit 1; }
echo "PASS: long pipeline without a code-file write is not gated"

# Case 6: bypass marker → ALLOW even for a big code write.
RESET; touch "$XDG_CACHE_HOME/pilot/bypass-session"
[[ "$(rc_of "$BIG_JS")" == "0" ]] || { echo "FAIL: bypass-session should allow"; exit 1; }
echo "PASS: bypass marker lets a big Bash code write through"

# Case 7: redirect to stderr / /dev/null is not a code write → ALLOW.
RESET
[[ "$(rc_of "$(printf 'for i in 1 2 3; do\necho hi >&2\ndone\n%s\necho done > /dev/null\n' "$big_body")")" == "0" ]] \
  || { echo "FAIL: stderr/devnull redirects should not gate"; exit 1; }
echo "PASS: non-file redirects do not trip the gate"

echo "ALL plan-gate Bash tests passed."
