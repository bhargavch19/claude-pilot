#!/usr/bin/env bash
# Test plan-gate.sh handles MultiEdit and NotebookEdit tool shapes.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/plugins/pilot/hooks/plan-gate.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
cd "$TMP"
export XDG_CACHE_HOME="$TMP/.cache"

small="line1\nline2"
big_chunk=$(printf 'line\n%.0s' {1..15})  # 15 lines per chunk

# MultiEdit Case 1: two small edits summing to <=20 LOC → allow.
input=$(jq -n --arg s "$small" '{
  tool_name:"MultiEdit",
  tool_input:{edits:[
    {old_string:"a",new_string:$s},
    {old_string:"b",new_string:$s}
  ]}
}')
echo "$input" | "$HOOK" >/dev/null
echo "PASS: MultiEdit small total allowed"

# MultiEdit Case 2: two big edits summing >20 LOC → block (no plan).
input=$(jq -n --arg s "$big_chunk" '{
  tool_name:"MultiEdit",
  tool_input:{edits:[
    {old_string:"a",new_string:$s},
    {old_string:"b",new_string:$s}
  ]}
}')
set +e
err=$(echo "$input" | "$HOOK" 2>&1 >/dev/null)
rc=$?
set -e
[[ "$rc" -eq 2 ]] || { echo "FAIL: MultiEdit big total should block; got $rc"; exit 1; }
echo "$err" | grep -q 'plan-gate: G1' || { echo "FAIL: missing G1 message"; exit 1; }
echo "PASS: MultiEdit big total blocked with G1"

# MultiEdit Case 3: big total with plan present → allow.
mkdir -p docs/superpowers/plans
touch docs/superpowers/plans/x.md
echo "$input" | "$HOOK" >/dev/null
echo "PASS: MultiEdit big total allowed with plan"
rm -rf docs

# NotebookEdit Case 1: small new_source → allow.
input=$(jq -n --arg s "$small" '{
  tool_name:"NotebookEdit",
  tool_input:{notebook_path:"n.ipynb",cell_id:"c1",new_source:$s,edit_mode:"replace"}
}')
echo "$input" | "$HOOK" >/dev/null
echo "PASS: NotebookEdit small allowed"

# NotebookEdit Case 2: 25-line new_source, no plan → block.
big=$(printf 'line\n%.0s' {1..25})
input=$(jq -n --arg s "$big" '{
  tool_name:"NotebookEdit",
  tool_input:{notebook_path:"n.ipynb",cell_id:"c1",new_source:$s,edit_mode:"replace"}
}')
set +e
echo "$input" | "$HOOK" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 2 ]] || { echo "FAIL: NotebookEdit big should block; got $rc"; exit 1; }
echo "PASS: NotebookEdit big blocked"

# Unknown tool → ignored.
echo '{"tool_name":"Read","tool_input":{"file_path":"x"}}' | "$HOOK" >/dev/null
echo "PASS: unknown tool ignored"

echo "ALL plan-gate MultiEdit/NotebookEdit tests passed."
