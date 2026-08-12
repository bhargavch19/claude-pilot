#!/usr/bin/env bash
# Regression gate: the deterministic route-advisor must score 100% on the
# golden routing set. A drop means routing behavior changed — investigate
# before shipping. (The eval itself lives in dev/eval-routes.sh.)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if ! out=$(bash "$ROOT/plugins/pilot/dev/eval-routes.sh" 2>&1); then
  echo "$out"
  echo "FAIL: routing eval did not reach 100%"
  exit 1
fi
echo "$out" | grep -q '(100%)' || { echo "$out"; echo "FAIL: expected 100% routing accuracy"; exit 1; }
echo "PASS: golden routing eval at 100%"

echo "ALL eval-routes tests passed."
