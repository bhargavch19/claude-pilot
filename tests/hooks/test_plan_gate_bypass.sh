#!/usr/bin/env bash
# Test plan-gate.sh bypass contract: MARKER FILES are the only bypass
# mechanism. Transcript phrases must NEVER bypass — skill launches and tool
# results land in the transcript as user-type entries, so a phrase grep is
# poisoned by any document that mentions its own trigger (pilot's SKILL.md
# literally contains "pilot off rails"; that must not disarm the gate).
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/plugins/pilot/hooks/plan-gate.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
cd "$TMP"  # isolate from the repo's own plan files / git history

# Isolate marker dir so the real user's bypass state can't leak in.
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$XDG_CACHE_HOME/pilot"

big=$(printf 'line\n%.0s' {1..25})

mk_transcript() {
  # $@ = lines for transcript; one user-type entry each, in order.
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

expect_block() { # $1 = input json, $2 = case label
  local rc=0
  set +e
  echo "$1" | "$HOOK" >/dev/null 2>&1
  rc=$?
  set -e
  if [[ "$rc" -ne 2 ]]; then
    echo "FAIL: $2 should block (exit 2); got $rc"
    exit 1
  fi
}

# Baseline: no transcript → block (sanity).
input=$(jq -n --arg s "$big" '{tool_name:"Edit",tool_input:{new_string:$s}}')
expect_block "$input" "baseline (no bypass)"
echo "PASS: baseline blocks without bypass"

# Case A: "pilot off" typed in last user msg → STILL BLOCKS. The phrase is
# a request the model routes to /pilot-off (which writes a marker); the
# phrase itself is not a mechanism.
t=$(mk_transcript "first msg" "pilot off")
expect_block "$(mk_input "$t")" "typed 'pilot off' phrase"
echo "PASS: transcript phrase 'pilot off' does not bypass"

# Case B: "pilot off rails" earlier in transcript → STILL BLOCKS.
t=$(mk_transcript "pilot off rails" "now doing some stuff" "more stuff")
expect_block "$(mk_input "$t")" "'pilot off rails' in transcript"
echo "PASS: transcript phrase 'pilot off rails' does not bypass"

# Case C (poisoning regression): a skill launch lands SKILL.md-style content
# in the transcript as a user-type entry that MENTIONS the bypass phrases.
# This exact vector silently disarmed the gate for a whole session.
skill_doc='## Bypass syntax: say "pilot off" for one turn or "pilot off rails" for the session. Re-engage with "pilot back on".'
t=$(mk_transcript "build the feature" "$skill_doc" "keep going")
expect_block "$(mk_input "$t")" "SKILL.md-style doc mentioning bypass phrases"
echo "PASS: documentation mentioning bypass phrases does not poison the gate"

# Case D: marker file bypasses regardless of transcript content (the one
# true mechanism, written by the slash commands).
touch "$XDG_CACHE_HOME/pilot/bypass-session"
t=$(mk_transcript "hi" "irrelevant")
echo "$(mk_input "$t")" | "$HOOK" >/dev/null 2>&1
echo "PASS: bypass-session marker allows"
rm -f "$XDG_CACHE_HOME/pilot/bypass-session"

# Case E: after marker removal (= /pilot-back-on), gate re-engages.
t=$(mk_transcript "pilot off rails" "pilot back on" "more stuff")
expect_block "$(mk_input "$t")" "post back-on (no marker)"
echo "PASS: without a marker the gate is engaged"

echo "ALL plan-gate bypass tests passed."
