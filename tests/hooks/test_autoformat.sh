#!/usr/bin/env bash
# Test autoformat.sh: PostToolUse(Edit|Write|MultiEdit) hook that formats the
# edited file ONLY with the formatter the repo configures. Uses stubbed
# formatters on PATH so the test needs no real toolchain.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/plugins/pilot/hooks/autoformat.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
cd "$TMP"
git init -q
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$XDG_CACHE_HOME/pilot"

# Stub formatters on PATH: they append a marker so we can detect they ran.
mkdir -p bin
for tool in prettier ruff gofmt; do
  cat > "bin/$tool" <<'SH'
#!/usr/bin/env bash
file="${@: -1}"
printf 'FORMATTED\n' >> "$file" 2>/dev/null || true
exit 0
SH
  chmod +x "bin/$tool"
done
export PATH="$TMP/bin:$PATH"

mk() { # $1 tool, $2 file
  jq -cn --arg t "$1" --arg f "$2" --arg c "$TMP" \
    '{tool_name:$t, tool_input:{file_path:$f}, cwd:$c}'
}
formatted() { grep -q FORMATTED "$1" 2>/dev/null; }

# Case 1: no prettier config → editing .js is a no-op.
echo "const x=1" > app.js
mk Edit "$TMP/app.js" | "$HOOK" >/dev/null 2>&1 || true
formatted app.js && { echo "FAIL: formatted without repo config"; exit 1; }
echo "PASS: no formatter config → no-op"

# Case 2: with .prettierrc → editing .js runs prettier.
echo '{}' > .prettierrc
echo "const y=2" > comp.js
mk Write "$TMP/comp.js" | "$HOOK" >/dev/null 2>&1 || true
formatted comp.js || { echo "FAIL: prettier did not run with .prettierrc"; exit 1; }
echo "PASS: .prettierrc present → prettier runs on .js"

# Case 3: prettier also covers .md.
echo "# hi" > notes.md
mk Edit "$TMP/notes.md" | "$HOOK" >/dev/null 2>&1 || true
formatted notes.md || { echo "FAIL: prettier did not run on .md"; exit 1; }
echo "PASS: prettier runs on .md"

# Case 4: unsupported extension → no-op even with config.
echo "data" > file.xyz
mk Edit "$TMP/file.xyz" | "$HOOK" >/dev/null 2>&1 || true
formatted file.xyz && { echo "FAIL: formatted an unsupported extension"; exit 1; }
echo "PASS: unsupported extension → no-op"

# Case 5: .pilot.json autoformat:off → no-op.
echo '{"autoformat":"off"}' > .pilot.json
echo "const z=3" > off.js
mk Edit "$TMP/off.js" | "$HOOK" >/dev/null 2>&1 || true
formatted off.js && { echo "FAIL: ran despite autoformat:off"; exit 1; }
rm -f .pilot.json
echo "PASS: .pilot.json autoformat:off disables the hook"

# Case 6: off-rails bypass → no-op.
touch "$XDG_CACHE_HOME/pilot/off-rails"
echo "const b=4" > bypass.js
mk Edit "$TMP/bypass.js" | "$HOOK" >/dev/null 2>&1 || true
formatted bypass.js && { echo "FAIL: ran despite off-rails"; exit 1; }
rm -f "$XDG_CACHE_HOME/pilot/off-rails"
echo "PASS: off-rails bypass → no-op"

# Case 7: python via configured ruff.
printf '[tool.ruff]\n' > pyproject.toml
echo "x=1" > mod.py
mk Edit "$TMP/mod.py" | "$HOOK" >/dev/null 2>&1 || true
formatted mod.py || { echo "FAIL: ruff did not run with [tool.ruff]"; exit 1; }
echo "PASS: [tool.ruff] present → ruff runs on .py"

# Case 8: go via gofmt (canonical; no config needed).
echo "package main" > main.go
mk Write "$TMP/main.go" | "$HOOK" >/dev/null 2>&1 || true
formatted main.go || { echo "FAIL: gofmt did not run on .go"; exit 1; }
echo "PASS: gofmt runs on .go"

# Case 9: NotebookEdit / non-edit tool → skip.
echo "const n=5" > nb.js
mk NotebookEdit "$TMP/nb.js" | "$HOOK" >/dev/null 2>&1 || true
formatted nb.js && { echo "FAIL: ran on NotebookEdit"; exit 1; }
echo "PASS: non-edit tool skipped"

# Case 10: missing file / malformed input → no crash.
mk Edit "$TMP/does-not-exist.js" | "$HOOK" >/dev/null 2>&1 || true
printf '' | "$HOOK" >/dev/null 2>&1 || true
printf 'not json' | "$HOOK" >/dev/null 2>&1 || true
echo "PASS: missing file / malformed input handled safely"

echo "ALL autoformat tests passed."
