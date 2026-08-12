#!/usr/bin/env bash
# Test wire-mcps.sh / unwire-mcps.sh against a mock `claude` CLI shim that
# records every invocation. Confirms each MCP declared in plugin.json gets
# the right `claude mcp add` args, and that re-running is idempotent.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Shim: claude CLI that records argv and exits per env-controlled status.
cat > "$TMP/claude" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$CLAUDE_MOCK_LOG"
case "$2" in
  get) exit "${CLAUDE_GET_EXIT:-1}" ;;   # 1 = not registered (fresh state)
  add|add-json|remove) exit 0 ;;
esac
exit 0
EOF
chmod +x "$TMP/claude"
export CLAUDE_MOCK_LOG="$TMP/calls.log"
: > "$CLAUDE_MOCK_LOG"

# --- wire-mcps: fresh state, all 3 should get `add` ---
CLAUDE_GET_EXIT=1 PATH="$TMP:$PATH" bash "$ROOT/plugins/pilot/dev/wire-mcps.sh" >/dev/null

grep -q 'mcp add --scope user context7 npx -- -y @upstash/context7-mcp@2.2.5' "$CLAUDE_MOCK_LOG" \
  || { echo "FAIL: context7 add args wrong"; cat "$CLAUDE_MOCK_LOG"; exit 1; }
grep -q 'mcp add --scope user playwright npx -- -y @playwright/mcp@0.0.75' "$CLAUDE_MOCK_LOG" \
  || { echo "FAIL: playwright add args wrong"; cat "$CLAUDE_MOCK_LOG"; exit 1; }
# github is a remote (http) entry → registered via add-json with the URL.
grep -qF 'mcp add-json --scope user github' "$CLAUDE_MOCK_LOG" \
  || { echo "FAIL: github should register via add-json"; cat "$CLAUDE_MOCK_LOG"; exit 1; }
grep -qF 'https://api.githubcopilot.com/mcp' "$CLAUDE_MOCK_LOG" \
  || { echo "FAIL: github add-json missing hosted URL"; cat "$CLAUDE_MOCK_LOG"; exit 1; }
echo "PASS: all 3 declared MCPs added at user scope with correct args"

# --- idempotency: `get` succeeds, so wire should skip every entry ---
: > "$CLAUDE_MOCK_LOG"
out=$(CLAUDE_GET_EXIT=0 PATH="$TMP:$PATH" bash "$ROOT/plugins/pilot/dev/wire-mcps.sh")
skip_count=$(echo "$out" | grep -c '^SKIP')
[[ "$skip_count" -eq 3 ]] || { echo "FAIL: expected 3 SKIPs, got $skip_count"; echo "$out"; exit 1; }
grep -q ' add ' "$CLAUDE_MOCK_LOG" && { echo "FAIL: idempotent run still called add"; exit 1; }
echo "PASS: idempotent re-run skips existing entries"

# --- unwire-mcps: when registered and command matches, remove ---
# Replace shim so `get` prints a matching command line.
cat > "$TMP/claude" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$CLAUDE_MOCK_LOG"
case "$2" in
  get)
    case "$3" in
      context7)  echo "command: npx -y @upstash/context7-mcp@2.2.5" ;;
      playwright) echo "command: npx -y @playwright/mcp@0.0.75" ;;
      github)    echo "url: https://api.githubcopilot.com/mcp" ;;
    esac
    exit 0 ;;
  remove) exit 0 ;;
esac
exit 0
EOF
chmod +x "$TMP/claude"
: > "$CLAUDE_MOCK_LOG"

PATH="$TMP:$PATH" bash "$ROOT/plugins/pilot/dev/unwire-mcps.sh" >/dev/null

for name in context7 playwright github; do
  grep -q "mcp remove $name" "$CLAUDE_MOCK_LOG" \
    || { echo "FAIL: $name was not removed"; cat "$CLAUDE_MOCK_LOG"; exit 1; }
done
echo "PASS: unwire removes all 3 declared MCPs"

# --- unwire safety: if registered command DIVERGED from plugin.json, leave alone ---
cat > "$TMP/claude" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$CLAUDE_MOCK_LOG"
case "$2" in
  get) echo "command: npx -y some/other-thing@1.0.0" ; exit 0 ;;
  remove) exit 0 ;;
esac
exit 0
EOF
chmod +x "$TMP/claude"
: > "$CLAUDE_MOCK_LOG"

out=$(PATH="$TMP:$PATH" bash "$ROOT/plugins/pilot/dev/unwire-mcps.sh")
diverged_skips=$(echo "$out" | grep -c 'command diverged from plugin.json — left alone')
[[ "$diverged_skips" -eq 3 ]] || { echo "FAIL: diverged MCPs should be left alone (got $diverged_skips)"; echo "$out"; exit 1; }
grep -q ' remove ' "$CLAUDE_MOCK_LOG" && { echo "FAIL: diverged user MCP got removed anyway"; exit 1; }
echo "PASS: user-overridden MCPs not clobbered on unwire"

echo "ALL wire-mcps / unwire-mcps tests passed."
