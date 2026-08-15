#!/usr/bin/env bash
# Test pre-commit.sh as a Claude Code PreToolUse hook on Bash.
# Feeds JSON over stdin; asserts allow (exit 0) vs block (exit 1).
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/plugins/pilot/hooks/pre-commit.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
cd "$TMP"
git init -q
git config user.email t@t.t
git config user.name t

call_hook() {
  # $1 = git commit command string
  local cmd="$1"
  jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}' | "$HOOK"
}

# Seed initial commit so HEAD exists.
echo "export const x = 1" > a.ts
git add a.ts
git -c core.hooksPath=/dev/null commit -q -m "feat: seed"

# Case 1: clean code + conventional msg → allow.
git mv a.ts b.ts
call_hook 'git commit -m "feat: rename"' >/dev/null
echo "PASS: clean code allowed"
git -c core.hooksPath=/dev/null commit -q -m "feat: rename"

# Case 2: WIP message → block.
echo "export const y = 1" > y.ts
git add y.ts
if call_hook 'git commit -m "WIP: stuff"' >/dev/null 2>&1; then
  echo "FAIL: WIP not blocked"
  exit 1
fi
echo "PASS: WIP blocked"

# Case 2b: non-conventional message → block.
if call_hook 'git commit -m "just stuff"' >/dev/null 2>&1; then
  echo "FAIL: non-conventional prefix not blocked"
  exit 1
fi
echo "PASS: non-conventional msg blocked"
git reset y.ts >/dev/null
rm y.ts

# Case 3: console.log in staged TS → block.
echo "console.log('x')" > c.ts
git add c.ts
if call_hook 'git commit -m "feat: c"' >/dev/null 2>&1; then
  echo "FAIL: console.log not blocked"
  exit 1
fi
git reset c.ts >/dev/null
rm c.ts
echo "PASS: console.log blocked"

# Case 4: `: any` without comment → block.
echo "const x: any = 1" > d.ts
git add d.ts
if call_hook 'git commit -m "feat: d"' >/dev/null 2>&1; then
  echo "FAIL: bare any not blocked"
  exit 1
fi
git reset d.ts >/dev/null
rm d.ts
echo "PASS: bare any blocked"

# Case 5: `: any` WITH comment → allow.
echo "const x: any = 1 // any: legacy lib" > e.ts
git add e.ts
call_hook 'git commit -m "feat: e"' >/dev/null
echo "PASS: documented any allowed"
git reset e.ts >/dev/null
rm e.ts

# Case 6: sleep() in test file → block.
mkdir -p tests
echo "test('x', () => sleep(100))" > tests/foo.test.ts
git add tests/foo.test.ts
if call_hook 'git commit -m "test: foo"' >/dev/null 2>&1; then
  echo "FAIL: sleep in test not blocked"
  exit 1
fi
git reset tests/foo.test.ts >/dev/null
rm -rf tests
echo "PASS: sleep in test blocked"

# Case 7: non-git Bash command → ignored (allow).
echo "ignored" > z.txt
git add z.txt
echo '{"tool_name":"Bash","tool_input":{"command":"echo hi"}}' | "$HOOK" >/dev/null
echo "PASS: non-git command ignored"

# Case 8: HEREDOC commit msg → G3 skipped, file checks still run.
# Stage a clean file; commit with heredoc-style command should pass.
echo "export const ok = 1" > ok.ts
git add ok.ts
HEREDOC_CMD='git commit -m "$(cat <<EOF
feat: heredoc
EOF
)"'
call_hook "$HEREDOC_CMD" >/dev/null
echo "PASS: HEREDOC commit allowed (G3 skipped, files clean)"

# Case 8b: bare `<<<` (here-string) in non-conventional msg → G3 still
# applies (heredoc detector must require <<-?ident, not just <<).
git reset bad.ts ok.ts >/dev/null 2>&1 || true
rm -f bad.ts ok.ts
echo "export const z = 1" > z2.ts
git add z2.ts
if call_hook "git commit -m 'just<<<stuff'" >/dev/null 2>&1; then
  echo "FAIL: false-heredoc bypass — '<<<' shouldn't trip the heredoc detector"
  exit 1
fi
git reset z2.ts >/dev/null
rm z2.ts
echo "PASS: bare '<<<' does not trip heredoc detector"

# Case 8c: escaped quotes in -m → G3 skipped (sed can't parse safely),
# file checks still run. Clean staging should pass.
echo "export const clean = 1" > clean.ts
git add clean.ts
call_hook 'git commit -m "say \"hi\" feat"' >/dev/null
echo "PASS: escaped-quote -m skips G3 with clean staging"
git reset clean.ts >/dev/null
rm clean.ts

# Case 9: HEREDOC commit msg + console.log staged → G8 still blocks.
echo "console.log('bad')" > bad.ts
git add bad.ts
if call_hook "$HEREDOC_CMD" >/dev/null 2>&1; then
  echo "FAIL: HEREDOC bypassed G8"
  exit 1
fi
echo "PASS: HEREDOC still enforces G8"

echo "ALL pre-commit tests passed."
