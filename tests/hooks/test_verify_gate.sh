#!/usr/bin/env bash
# Test verify-gate.sh: warns when assistant claims "done" without test
# output evidence. Uses both the inline-transcript fallback (old fixtures)
# and the real transcript_path JSONL format.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/hooks/verify-gate.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
cd "$TMP"

# Isolate the gate's state dir (block counter + bypass markers) so tests are
# deterministic and never touch the real ~/.cache/pilot.
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$XDG_CACHE_HOME/pilot"
RESET() { rm -f "$XDG_CACHE_HOME"/pilot/verify-gate-blocks \
                 "$XDG_CACHE_HOME"/pilot/bypass-session \
                 "$XDG_CACHE_HOME"/pilot/off-rails; }

# ---- inline-transcript fallback (legacy fixture format) -----------------

# Case 1: claim of done WITH test output → no warning.
INPUT='{"transcript":[{"role":"assistant","content":"I ran pytest and it passed: 12 passed in 0.5s. Done."}]}'
OUT=$(echo "$INPUT" | "$HOOK" 2>&1)
if [[ "$OUT" == *"verify-gate"* ]]; then
  echo "FAIL: false positive on done with evidence"
  exit 1
fi
echo "PASS: done with evidence not flagged (inline)"

# Case 2: claim of done WITHOUT test output → warning.
INPUT='{"transcript":[{"role":"assistant","content":"All done. Ready to ship."}]}'
OUT=$(echo "$INPUT" | "$HOOK" 2>&1 || true)
if [[ "$OUT" != *"verify-gate"* ]]; then
  echo "FAIL: missed claim of done without evidence"
  exit 1
fi
echo "PASS: bare done flagged (inline)"

# Case 3: no claim → no warning.
INPUT='{"transcript":[{"role":"assistant","content":"Working on it."}]}'
OUT=$(echo "$INPUT" | "$HOOK" 2>&1)
if [[ "$OUT" == *"verify-gate"* ]]; then
  echo "FAIL: false positive on neutral message"
  exit 1
fi
echo "PASS: neutral not flagged (inline)"

# ---- transcript_path (real Claude Code format) --------------------------

mk_transcript() {
  # $1 = assistant text content
  local f="$TMP/transcript.jsonl"
  : > "$f"
  jq -n --arg t "$1" '{
    type:"assistant",
    message:{role:"assistant", content:[{type:"text", text:$t}]}
  }' >> "$f"
  printf '%s' "$f"
}

mk_input() {
  jq -n --arg p "$1" '{transcript_path:$p, stop_hook_active:true}'
}

# Case 4: real transcript with done + bun test evidence → allow.
t=$(mk_transcript "Ran bun test — 42 passed. Done.")
OUT=$(mk_input "$t" | "$HOOK" 2>&1)
if [[ "$OUT" == *"verify-gate"* ]]; then
  echo "FAIL: bun test evidence not recognised"
  exit 1
fi
echo "PASS: bun test evidence allowed (transcript_path)"

# Case 5: real transcript with done + vitest evidence → allow.
t=$(mk_transcript "vitest passed all tests, ready to merge.")
OUT=$(mk_input "$t" | "$HOOK" 2>&1)
[[ "$OUT" != *"verify-gate"* ]] || { echo "FAIL: vitest not recognised"; exit 1; }
echo "PASS: vitest evidence allowed"

# Case 6: nx test evidence → allow.
t=$(mk_transcript "nx test ran — All tests passed. Done.")
OUT=$(mk_input "$t" | "$HOOK" 2>&1)
[[ "$OUT" != *"verify-gate"* ]] || { echo "FAIL: nx test not recognised"; exit 1; }
echo "PASS: nx test evidence allowed"

# Case 7: make test evidence → allow.
t=$(mk_transcript "make test — 0 failed, 0 errors. Complete.")
OUT=$(mk_input "$t" | "$HOOK" 2>&1)
[[ "$OUT" != *"verify-gate"* ]] || { echo "FAIL: make test not recognised"; exit 1; }
echo "PASS: make test evidence allowed"

# Case 8: node --test evidence → allow.
t=$(mk_transcript "ran node --test — ℹ tests 18 ℹ pass 18 ℹ fail 0. Done.")
OUT=$(mk_input "$t" | "$HOOK" 2>&1)
[[ "$OUT" != *"verify-gate"* ]] || { echo "FAIL: node --test not recognised"; exit 1; }
echo "PASS: node --test evidence allowed"

# Case 8b: node --test-only also recognised.
t=$(mk_transcript "node --test-only ran — All tests passed. Complete.")
OUT=$(mk_input "$t" | "$HOOK" 2>&1)
[[ "$OUT" != *"verify-gate"* ]] || { echo "FAIL: node --test-only not recognised"; exit 1; }
echo "PASS: node --test-only evidence allowed"

# Case 9: per-repo .pilot.json extends runners.
echo '{"test_patterns":["another-runner"]}' > .pilot.json
t=$(mk_transcript "another-runner — 12 passed. Done.")
OUT=$(mk_input "$t" | "$HOOK" 2>&1)
[[ "$OUT" != *"verify-gate"* ]] || { echo "FAIL: .pilot.json extra pattern not picked up"; exit 1; }
echo "PASS: .pilot.json extra runner allowed"
rm -f .pilot.json

# Case 10: bare done in real transcript → warning.
t=$(mk_transcript "All done. Shipping.")
OUT=$(mk_input "$t" | "$HOOK" 2>&1 || true)
[[ "$OUT" == *"verify-gate"* ]] || { echo "FAIL: bare done not flagged"; exit 1; }
echo "PASS: bare done flagged (transcript_path)"

# Case 11: schema-drift detection — non-empty transcript that doesn't match
# the expected jq path should surface a diagnostic instead of silent pass.
FAKE_TRANSCRIPT="$TMP/schema-drift.jsonl"
cat > "$FAKE_TRANSCRIPT" <<'EOF'
{"type":"unknown","payload":{"weird_field":"some text we cannot parse"}}
{"type":"unknown","payload":{"weird_field":"another line"}}
EOF
STDERR=$(jq -n --arg t "$FAKE_TRANSCRIPT" '{transcript_path: $t}' | "$HOOK" 2>&1 1>/dev/null || true)
echo "$STDERR" | grep -q 'schema may have changed' || { echo "FAIL: schema-drift diagnostic missing, got: $STDERR"; exit 1; }
echo "PASS: schema-drift surfaced on unparseable transcript"

# ---- code-change gating -------------------------------------------------
# A "done" claim on a turn that touched no source files should not trip the
# gate. Exercised inside a real git repo so `git status` is meaningful.
# (The cases above run from a non-git temp dir, hitting the fallback path.)
GITREPO="$TMP/gitrepo"
mkdir -p "$GITREPO"
( cd "$GITREPO" && git init -q )

# Case 12: bare done, clean working tree (no code changed) → NO warning.
t=$(mk_transcript "All done. Shipping.")
OUT=$( cd "$GITREPO" && mk_input "$t" | "$HOOK" 2>&1 || true )
[[ "$OUT" != *"verify-gate"* ]] || { echo "FAIL: flagged done on a no-code-change turn"; exit 1; }
echo "PASS: done on clean repo (no source touched) not flagged"

# Case 13: bare done with a changed source file → warning returns.
( cd "$GITREPO" && echo "export const x = 1;" > mod.ts )
t=$(mk_transcript "All done. Shipping.")
OUT=$( cd "$GITREPO" && mk_input "$t" | "$HOOK" 2>&1 || true )
[[ "$OUT" == *"verify-gate"* ]] || { echo "FAIL: missed done with source changed"; exit 1; }
echo "PASS: done with source changed flagged"

# Case 14: bare done, only a non-code file changed → NO warning.
( cd "$GITREPO" && rm -f mod.ts && echo "# notes" > NOTES.md )
t=$(mk_transcript "All done. Shipping.")
OUT=$( cd "$GITREPO" && mk_input "$t" | "$HOOK" 2>&1 || true )
[[ "$OUT" != *"verify-gate"* ]] || { echo "FAIL: flagged done on a docs-only change"; exit 1; }
echo "PASS: done on docs-only change not flagged"

# ---- block vs warn contract (the enforcement behavior) ------------------
# A flagged turn must BLOCK (emit a Stop decision on stdout), unless a bypass
# downgrades it to warn. These distinguish block from warn — the substring
# checks above do not.
BLOCKREPO="$TMP/blockrepo"
mkdir -p "$BLOCKREPO"
( cd "$BLOCKREPO" && git init -q && echo "export const y = 1;" > a.ts )
tdone=$(mk_transcript "All done. Shipping.")

# Case 15: bare done + changed source, no bypass → decision:block on stdout.
RESET
OUT=$( cd "$BLOCKREPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
[[ "$OUT" == *'"decision":"block"'* ]] || { echo "FAIL: expected decision:block on stdout, got: $OUT"; exit 1; }
echo "PASS: flagged turn emits Stop block decision"

# Case 16: bypass-session marker → warn, never blocks.
RESET; touch "$XDG_CACHE_HOME/pilot/bypass-session"
OUT=$( cd "$BLOCKREPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
[[ "$OUT" != *'"decision":"block"'* ]] || { echo "FAIL: bypass-session should downgrade block→warn"; exit 1; }
echo "PASS: bypass-session downgrades block→warn"

# Case 17: off-rails marker → warn, never blocks.
RESET; touch "$XDG_CACHE_HOME/pilot/off-rails"
OUT=$( cd "$BLOCKREPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
[[ "$OUT" != *'"decision":"block"'* ]] || { echo "FAIL: off-rails should downgrade block→warn"; exit 1; }
echo "PASS: off-rails downgrades block→warn"

# Case 18: per-repo .pilot.json verify_gate:warn → warn, never blocks.
RESET; echo '{"verify_gate":"warn"}' > "$BLOCKREPO/.pilot.json"
OUT=$( cd "$BLOCKREPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
[[ "$OUT" != *'"decision":"block"'* ]] || { echo "FAIL: .pilot.json verify_gate:warn should downgrade"; exit 1; }
echo "PASS: .pilot.json verify_gate:warn downgrades block→warn"
rm -f "$BLOCKREPO/.pilot.json"

# Case 19: anti-trap — first two block, third auto-releases to warn.
RESET
b1=$( cd "$BLOCKREPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
b2=$( cd "$BLOCKREPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
b3=$( cd "$BLOCKREPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
{ [[ "$b1" == *'"decision":"block"'* ]] && [[ "$b2" == *'"decision":"block"'* ]]; } \
  || { echo "FAIL: first two turns should block"; exit 1; }
[[ "$b3" != *'"decision":"block"'* ]] || { echo "FAIL: anti-trap should release on 3rd consecutive block"; exit 1; }
echo "PASS: anti-trap releases after 2 consecutive blocks"

# Case 20: .pilot.json at the git root is honored even when the Stop hook runs
# from a SUBDIRECTORY (regression: cwd-only lookup silently dropped per-repo
# runners when the shell was left in e.g. tests/).
RESET
echo '{"test_patterns":["custom-suite"]}' > "$BLOCKREPO/.pilot.json"
mkdir -p "$BLOCKREPO/sub/dir"
tcustom=$(mk_transcript "Ran custom-suite — All tests passed. Done.")
OUT=$( cd "$BLOCKREPO/sub/dir" && mk_input "$tcustom" | "$HOOK" 2>&1 )
[[ "$OUT" != *"verify-gate"* ]] || { echo "FAIL: git-root .pilot.json not honored from subdir, got: $OUT"; exit 1; }
echo "PASS: .pilot.json resolved from git root when cwd is a subdirectory"
rm -f "$BLOCKREPO/.pilot.json"

echo "ALL verify-gate tests passed."
