#!/usr/bin/env bash
# Test plan-gate.sh: blocks edits >20 LOC unless plan exists in last 24h.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/plugins/pilot/hooks/plan-gate.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Case 1: small change (<=20 LOC, 1 file) → allow.
input='{"tool_name":"Edit","tool_input":{"file_path":"a.ts","new_string":"x"}}'
echo "$input" | "$HOOK" >/dev/null
echo "PASS: small change allowed"

# Case 2: large change (>20 LOC), no plan → block (exit 2) with G1 message.
big=$(printf 'line\n%.0s' {1..25})
input=$(jq -n --arg s "$big" '{tool_name:"Edit",tool_input:{file_path:"a.ts",new_string:$s}}')
set +e
err=$(cd "$TMP" && echo "$input" | "$HOOK" 2>&1 >/dev/null)
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL: large change should exit 2, got $rc"
  exit 1
fi
if ! echo "$err" | grep -q 'plan-gate: G1'; then
  echo "FAIL: stderr missing G1 message: $err"
  exit 1
fi
echo "PASS: large change blocked with G1 message"

# Case 3: large change with recent superpowers plan → allow.
mkdir -p "$TMP/docs/superpowers/plans"
touch "$TMP/docs/superpowers/plans/some-plan.md"
( cd "$TMP" && echo "$input" | "$HOOK" >/dev/null )
echo "PASS: large change allowed with recent superpowers plan"
rm -rf "$TMP/docs"

# Case 4: large change with recent GSD plan (.planning/<phase>/PLAN.md) → allow.
mkdir -p "$TMP/.planning/phase-1"
touch "$TMP/.planning/phase-1/PLAN.md"
( cd "$TMP" && echo "$input" | "$HOOK" >/dev/null )
echo "PASS: large change allowed with recent GSD plan"
rm -rf "$TMP/.planning"

# Case 5: GSD SPEC.md (without PLAN.md) also satisfies the gate.
mkdir -p "$TMP/.planning/phase-1"
touch "$TMP/.planning/phase-1/SPEC.md"
( cd "$TMP" && echo "$input" | "$HOOK" >/dev/null )
echo "PASS: large change allowed with recent GSD SPEC.md"
rm -rf "$TMP/.planning"

# Case 6: .pilot/acceptance.md (AC ledger) also satisfies the gate — the
# AC-first invariant mandates it at Plan time, so it IS a plan artifact.
mkdir -p "$TMP/.pilot"
echo "- [ ] AC-001: something" > "$TMP/.pilot/acceptance.md"
( cd "$TMP" && echo "$input" | "$HOOK" >/dev/null )
echo "PASS: large change allowed with AC ledger present"
rm -rf "$TMP/.pilot"

echo "ALL plan-gate tests passed."
