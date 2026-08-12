#!/usr/bin/env bash
# Run all hook + dev integration tests.
set -euo pipefail
cd "$(dirname "$0")"
fail=0
for d in hooks dev skills; do
  # Hard-fail on a missing/empty suite dir: a botched restructure must not
  # skip a whole suite and still exit green.
  compgen -G "$d/test_*.sh" >/dev/null \
    || { echo "FATAL: no tests found in tests/$d — layout broken?"; exit 1; }
  for t in "$d"/test_*.sh; do
    echo "=== $t ==="
    if ! bash "$t"; then
      fail=$((fail + 1))
      echo "--- $t FAILED ---"
    fi
  done
done
echo ""
echo "=== Dogfood prompts (manual) ==="
echo "See dogfood/sample_prompts.md and run them in a Claude Code session."
exit "$fail"
