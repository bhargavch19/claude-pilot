#!/usr/bin/env bash
# Pin the registry's phase coverage so missing/renamed phases fail loudly.
# Asserts each expected phase row exists AND routes to its expected Primary.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REG="$ROOT/plugins/pilot/skills/pilot/registry.md"
[[ -f "$REG" ]] || { echo "FAIL: registry.md not found at $REG"; exit 1; }

# phase-label  |  expected primary skill id (backticked in the row)
checks=(
  "6.75 Documentation|gsd-docs-update"
  "7.6 Dependencies|migration-safety:migration-safety"
  "8.25 Release|claude-mem:version-bump"
)

for c in "${checks[@]}"; do
  label="${c%%|*}"
  primary="${c##*|}"
  row=$(grep -F "| $label " "$REG" || true)
  [[ -n "$row" ]] || { echo "FAIL: phase row '$label' missing from registry.md"; exit 1; }
  echo "$row" | grep -qF "\`$primary\`" \
    || { echo "FAIL: phase '$label' does not route to Primary \`$primary\`"; exit 1; }
  echo "PASS: $label → $primary"
done

# Guard the consolidation decision: GSD is the spine; PAUL is opt-in only.
grep -q "One spine" "$REG" \
  || { echo "FAIL: 'One spine' decision section missing (GSD-spine consolidation)"; exit 1; }
echo "PASS: one-spine decision documented"

echo "ALL registry-phase coverage tests passed."
