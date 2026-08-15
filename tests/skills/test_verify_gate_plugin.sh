#!/usr/bin/env bash
# The standalone verify-gate plugin vendors byte-identical copies of pilot's
# verify-gate.sh + capture-test-run.sh. This test is the drift gate: if the
# pilot copies evolve, the standalone copies must be re-synced in the same
# change, or this fails.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PILOT="$ROOT/plugins/pilot/hooks"
STANDALONE="$ROOT/plugins/verify-gate/hooks"

for h in verify-gate.sh capture-test-run.sh; do
  [[ -f "$STANDALONE/$h" ]] || { echo "FAIL: standalone copy missing: $h"; exit 1; }
  cmp -s "$PILOT/$h" "$STANDALONE/$h" \
    || { echo "FAIL: $h drifted — re-sync: cp plugins/pilot/hooks/$h plugins/verify-gate/hooks/"; exit 1; }
  [[ -x "$STANDALONE/$h" ]] || { echo "FAIL: $h not executable"; exit 1; }
  echo "PASS: $h byte-identical to pilot's copy"
done

# The plugin manifest wires exactly the three expected hook events and no MCPs.
MANIFEST="$ROOT/plugins/verify-gate/.claude-plugin/plugin.json"
jq -e '.hooks | keys | sort == ["PostToolUse", "Stop", "SubagentStop"]' "$MANIFEST" >/dev/null \
  || { echo "FAIL: manifest hook events != PostToolUse/Stop/SubagentStop"; exit 1; }
jq -e '(.mcpServers // null) == null' "$MANIFEST" >/dev/null \
  || { echo "FAIL: standalone plugin must not bundle MCP servers"; exit 1; }
echo "PASS: manifest wires 3 hook events, no MCP servers"

echo "ALL verify-gate plugin tests passed."
