#!/usr/bin/env bash
# Test verify-gate.sh AC-ledger enforcement: a "done" claim with unchecked
# `- [ ]` items in .pilot/acceptance.md blocks EVEN WITH a valid test capture.
# No ledger file → behavior unchanged (opt-in). Bypass markers still downgrade.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/plugins/pilot/hooks/verify-gate.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$XDG_CACHE_HOME/pilot"
FACT="$XDG_CACHE_HOME/pilot/last-test-run"
RESET() { rm -f "$XDG_CACHE_HOME"/pilot/verify-gate-blocks \
                 "$XDG_CACHE_HOME"/pilot/bypass-session \
                 "$XDG_CACHE_HOME"/pilot/off-rails \
                 "$FACT"; }

SESSION="sess-ac-test"

mk_transcript() {
  local f="$TMP/transcript.jsonl"
  : > "$f"
  jq -n --arg t "$1" '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:$t}]}}' >> "$f"
  printf '%s' "$f"
}
mk_input() {
  jq -n --arg p "$1" --arg s "$SESSION" '{transcript_path:$p, session_id:$s, stop_hook_active:true}'
}
mk_fact() {
  jq -cn --arg s "$SESSION" --argjson ts "$(date +%s)" \
    '{ts:$ts, session_id:$s, command:"bash tests/run.sh", ok:true}' > "$FACT"
}

# Git repo with a changed source file so the gate is in scope.
REPO="$TMP/repo"
mkdir -p "$REPO/.pilot"
( cd "$REPO" && git init -q && echo "export const x = 1;" > mod.ts )
tdone=$(mk_transcript "All done. Shipping.")

# Case 1: capture OK + unchecked ACs → block, message names the ledger.
RESET; mk_fact
cat > "$REPO/.pilot/acceptance.md" <<'EOF'
# Acceptance criteria
- [x] AC1: parser handles empty input
- [ ] AC2: error path returns 400
- [ ] AC3: audit log entry written
EOF
OUT=$( cd "$REPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
[[ "$OUT" == *'"decision":"block"'* ]] || { echo "FAIL: unchecked ACs with capture should block, got: $OUT"; exit 1; }
[[ "$OUT" == *'acceptance.md'* ]] || { echo "FAIL: block reason should name the ledger, got: $OUT"; exit 1; }
[[ "$OUT" == *'AC2'* ]] || { echo "FAIL: block reason should list an open item, got: $OUT"; exit 1; }
echo "PASS: unchecked ACs block a done claim despite a valid capture"

# Case 2: capture OK + all ACs checked → allow.
RESET; mk_fact
cat > "$REPO/.pilot/acceptance.md" <<'EOF'
- [x] AC1: parser handles empty input
- [x] AC2: error path returns 400
EOF
OUT=$( cd "$REPO" && mk_input "$tdone" | "$HOOK" 2>&1 || true )
[[ "$OUT" != *"verify-gate"* ]] || { echo "FAIL: fully checked ledger should allow, got: $OUT"; exit 1; }
echo "PASS: fully checked ledger + capture allows"

# Case 3: no ledger file → allow (opt-in; unchanged behavior).
RESET; mk_fact
rm -f "$REPO/.pilot/acceptance.md"
OUT=$( cd "$REPO" && mk_input "$tdone" | "$HOOK" 2>&1 || true )
[[ "$OUT" != *"verify-gate"* ]] || { echo "FAIL: absent ledger should not gate, got: $OUT"; exit 1; }
echo "PASS: no ledger file → no AC gating"

# Case 4: no capture + unchecked ACs → block message carries the AC note too.
RESET
cat > "$REPO/.pilot/acceptance.md" <<'EOF'
- [ ] AC1: parser handles empty input
EOF
OUT=$( cd "$REPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
[[ "$OUT" == *'"decision":"block"'* ]] || { echo "FAIL: no capture + open ACs should block"; exit 1; }
[[ "$OUT" == *'acceptance criteria remain unchecked'* ]] || { echo "FAIL: missing AC note on no-capture block, got: $OUT"; exit 1; }
echo "PASS: no-capture block message includes the AC note"

# Case 5: bypass marker downgrades AC block → warn.
RESET; mk_fact; touch "$XDG_CACHE_HOME/pilot/off-rails"
OUT=$( cd "$REPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
[[ "$OUT" != *'"decision":"block"'* ]] || { echo "FAIL: off-rails should downgrade AC block to warn"; exit 1; }
echo "PASS: bypass downgrades AC block to warn"

# Case 6: nested/indented and asterisk checkboxes count as open.
RESET; mk_fact
cat > "$REPO/.pilot/acceptance.md" <<'EOF'
- [x] AC1: top level done
  - [ ] AC1a: nested still open
* [ ] AC2: asterisk style
EOF
OUT=$( cd "$REPO" && mk_input "$tdone" | "$HOOK" 2>/dev/null )
[[ "$OUT" == *'"decision":"block"'* ]] || { echo "FAIL: nested/asterisk open boxes should block"; exit 1; }
echo "PASS: nested and asterisk checkboxes are counted"

rm -f "$REPO/.pilot/acceptance.md"
echo "ALL verify-gate AC-ledger tests passed."
