#!/usr/bin/env bash
# Test floor-check.sh: the executable production floor. Passes a clean repo,
# fails on a planted secret or a failing test suite, and skips absent tools.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/plugins/pilot/dev/floor-check.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

mkrepo() { # $1 dir, $2 test-exit-code
  local d="$1"; mkdir -p "$d/tests"
  cat > "$d/tests/run.sh" <<SH
#!/usr/bin/env bash
exit ${2:-0}
SH
  chmod +x "$d/tests/run.sh"
  echo "const x = 1;" > "$d/app.js"
  ( cd "$d" && git init -q && git add -A )
}

# 1. Clean repo with passing tests → floor PASSES.
mkrepo "$TMP/clean" 0
if bash "$SCRIPT" "$TMP/clean" >/dev/null 2>&1; then
  echo "PASS: floor passes a clean repo"
else
  echo "FAIL: floor should pass a clean repo"; bash "$SCRIPT" "$TMP/clean"; exit 1
fi

# 2. Planted secret → floor FAILS. (Build the key at runtime so this test file
#    itself contains no matching pattern — otherwise it would trip the floor.)
mkrepo "$TMP/secret" 0
printf 'const k = "AKIA%s";\n' "IOSFODNN7EXAMPLE" > "$TMP/secret/config.js"
( cd "$TMP/secret" && git add -A )
if bash "$SCRIPT" "$TMP/secret" >/dev/null 2>&1; then
  echo "FAIL: floor should fail on a planted secret"; exit 1
else
  echo "PASS: floor fails on a planted secret"
fi

# 3. Failing test suite → floor FAILS.
mkrepo "$TMP/badtest" 1
if bash "$SCRIPT" "$TMP/badtest" >/dev/null 2>&1; then
  echo "FAIL: floor should fail on a failing test suite"; exit 1
else
  echo "PASS: floor fails on a failing test suite"
fi

# 4. Honors .pilot.json test_command.
mkrepo "$TMP/custom" 0
rm -f "$TMP/custom/tests/run.sh"
echo '{"test_command":"exit 0"}' > "$TMP/custom/.pilot.json"
( cd "$TMP/custom" && git add -A )
bash "$SCRIPT" "$TMP/custom" >/dev/null 2>&1 && echo "PASS: floor honors .pilot.json test_command" \
  || { echo "FAIL: custom test_command not honored"; exit 1; }

# 5. Non-directory target → error exit.
rc=0; bash "$SCRIPT" "$TMP/nope" >/dev/null 2>&1 || rc=$?
[ "$rc" != "0" ] && echo "PASS: floor errors on a missing target" || { echo "FAIL: should error"; exit 1; }

echo "ALL floor-check tests passed."
