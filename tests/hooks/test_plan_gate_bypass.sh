#!/usr/bin/env bash
# Test plan-gate.sh bypass via transcript_path:
#   - "pilot --no-plan" in last user message → allow
#   - "pilot off"        in last user message → allow
#   - "pilot off rails"  active (most recent off-rails toggle) → allow
#   - "pilot back on"    most recent → block again (off-rails inactive)
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/hooks/plan-gate.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
cd "$TMP"  # isolate from the repo's own plan files / git history

big=$(printf 'line\n%.0s' {1..25})

mk_transcript() {
  # $@ = lines for transcript; one user message each, in order.
  local f="$TMP/transcript.jsonl"
  : > "$f"
  for msg in "$@"; do
    jq -n --arg c "$msg" '{type:"user", message:{role:"user", content:$c}}' >> "$f"
  done
  printf '%s' "$f"
}

mk_input() {
  # $1 = transcript path
  jq -n --arg s "$big" --arg t "$1" '{
    tool_name:"Edit",
    tool_input:{file_path:"a.ts", new_string:$s},
    transcript_path:$t
  }'
}

# Baseline: no transcript → block (sanity).
input=$(jq -n --arg s "$big" '{tool_name:"Edit",tool_input:{new_string:$s}}')
set +e
echo "$input" | "$HOOK" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL: baseline (no bypass) should still block; got $rc"
  exit 1
fi
echo "PASS: baseline blocks without bypass"

# Case A: "pilot --no-plan" in last user msg → allow.
t=$(mk_transcript "first msg" "pilot --no-plan, just do it")
input=$(mk_input "$t")
echo "$input" | "$HOOK" >/dev/null 2>&1
echo "PASS: --no-plan bypass allows"

# Case B: "pilot off" in last user msg → allow.
t=$(mk_transcript "first msg" "pilot off")
input=$(mk_input "$t")
echo "$input" | "$HOOK" >/dev/null 2>&1
echo "PASS: pilot off bypass allows"

# Case C: "pilot off rails" earlier, no "back on" since → allow.
t=$(mk_transcript "pilot off rails" "now doing some stuff" "more stuff")
input=$(mk_input "$t")
echo "$input" | "$HOOK" >/dev/null 2>&1
echo "PASS: off rails active allows"

# Case D: "pilot off rails" then "pilot back on" → block.
t=$(mk_transcript "pilot off rails" "pilot back on" "more stuff")
input=$(mk_input "$t")
set +e
echo "$input" | "$HOOK" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL: back-on should re-engage gate; got $rc"
  exit 1
fi
echo "PASS: back on re-engages gate"

# Case E: random user msg, no bypass phrases → block.
t=$(mk_transcript "hi" "build something")
input=$(mk_input "$t")
set +e
echo "$input" | "$HOOK" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL: random msgs should not bypass; got $rc"
  exit 1
fi
echo "PASS: irrelevant transcript does not bypass"

# Case F: substring without leading word boundary → should NOT bypass.
# "shutdownpilot off rails" contains the phrase but `pilot` isn't a
# standalone word; the leading-boundary anchor must prevent the bypass.
t=$(mk_transcript "hi" "shutdownpilot off rails")
input=$(mk_input "$t")
set +e
echo "$input" | "$HOOK" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL: glued-prefix 'shutdownpilot off rails' should not bypass; got $rc"
  exit 1
fi
echo "PASS: leading word-boundary blocks substring false positive"

# Case G: legitimate leading punctuation ("(pilot off)") → bypass allowed.
t=$(mk_transcript "first" "(pilot off) for this one")
input=$(mk_input "$t")
echo "$input" | "$HOOK" >/dev/null 2>&1
echo "PASS: leading punctuation allows bypass"

echo "ALL plan-gate bypass tests passed."
