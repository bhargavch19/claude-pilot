#!/usr/bin/env bash
# Pilot production-quality floor — the EXECUTABLE gate (not just templates).
#
# Runs the applicable floor gates against a repo and exits non-zero if any fail,
# so it can block locally and in CI. Gates whose tool is absent are skipped and
# reported (never a false failure). Dogfooded on pilot's own repo via CI.
#
#   1. Tests       — bash tests/run.sh (or .pilot.json test_command)
#   2. Lint        — shellcheck on hooks/ + dev/ (if shellcheck present)
#   3. Secret scan — gitleaks if present, else a conservative built-in regex
#
# Usage: bash dev/floor-check.sh [repo-dir]
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" 2>/dev/null || { echo "floor-check: not a directory: $ROOT" >&2; exit 2; }
fails=0
echo "== production-quality floor: $ROOT =="

# 1. Tests -----------------------------------------------------------------
TEST_CMD=""
if [ -f .pilot.json ]; then TEST_CMD=$(jq -r '.test_command // empty' .pilot.json 2>/dev/null || true); fi
[ -z "$TEST_CMD" ] && [ -f tests/run.sh ] && TEST_CMD="bash tests/run.sh"
if [ -n "$TEST_CMD" ]; then
  if bash -c "$TEST_CMD" >/dev/null 2>&1; then echo "  ✓ tests ($TEST_CMD)"
  else echo "  ✗ tests ($TEST_CMD)"; fails=$((fails + 1)); fi
else
  echo "  - tests (no runner found)"
fi

# 2. Lint (shellcheck) -----------------------------------------------------
shfiles=$(ls hooks/*.sh dev/*.sh 2>/dev/null || true)
if [ -z "$shfiles" ]; then
  echo "  - shellcheck (no shell scripts)"
elif command -v shellcheck >/dev/null 2>&1; then
  # Same severity as the dedicated CI shellcheck job: warnings block the
  # floor, style/info notes don't.
  # shellcheck disable=SC2086  # intentional word-split of the file list
  if shellcheck -S warning $shfiles >/dev/null 2>&1; then echo "  ✓ shellcheck"
  else echo "  ✗ shellcheck"; fails=$((fails + 1)); fi
else
  echo "  - shellcheck (not installed; CI runs it)"
fi

# 3. Secret scan -----------------------------------------------------------
SECRET_RE='(-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|xox[baprs]-[0-9A-Za-z-]{10,}|ghp_[0-9A-Za-z]{36}|AIza[0-9A-Za-z_-]{35})'
if command -v gitleaks >/dev/null 2>&1; then
  if gitleaks detect --no-banner --redact >/dev/null 2>&1; then echo "  ✓ secret scan (gitleaks)"
  else echo "  ✗ secret scan (gitleaks found secrets)"; fails=$((fails + 1)); fi
else
  hits=$(git grep -nIE "$SECRET_RE" -- . 2>/dev/null | grep -vF 'floor-check.sh' || true)
  if [ -z "$hits" ]; then echo "  ✓ secret scan (built-in regex)"
  else echo "  ✗ secret scan — possible secrets:"; printf '%s\n' "$hits" | sed 's/^/      /'; fails=$((fails + 1)); fi
fi

echo "== floor: $([ "$fails" -eq 0 ] && echo PASS || echo "FAIL ($fails gate(s))") =="
[ "$fails" -eq 0 ]
