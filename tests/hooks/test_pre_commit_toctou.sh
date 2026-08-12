#!/usr/bin/env bash
# Regression: PreToolUse runs BEFORE the command, so `git add X && git commit`
# has an empty index at check time — G7/G8/G12 sailed through (found live in
# e2e dogfooding: a console.log landed in a real commit). The hook must also
# scan the files the command is ABOUT to stage (git add in the same command
# line, git commit -a) from the working tree.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/plugins/pilot/hooks/pre-commit.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

export XDG_CACHE_HOME="$TMP/cache"   # isolate bypass markers
mkdir -p "$XDG_CACHE_HOME/pilot"

REPO="$TMP/repo"
mkdir -p "$REPO"
( cd "$REPO" && git init -q )

run_hook() { # $1 = command string; runs from the repo; returns hook rc
  local rc=0
  set +e
  ( cd "$REPO" && jq -n --arg cmd "$1" \
      '{tool_name:"Bash", tool_input:{command:$cmd}}' | "$HOOK" ) >/dev/null 2>&1
  rc=$?
  set -e
  echo "$rc"
}

# Case 1: add && commit with unstaged console.log → block (the live e2e hole).
echo 'console.log("debug"); export const x = 1;' > "$REPO/app.js"
rc=$(run_hook 'git add app.js && git commit -m "feat: add app"')
[[ "$rc" -eq 2 ]] || { echo "FAIL: add&&commit with console.log should block, got $rc"; exit 1; }
echo "PASS: git add && git commit scans the about-to-be-staged file (G8)"

# Case 2: same shape, clean file → allow.
echo 'export const x = 1;' > "$REPO/app.js"
rc=$(run_hook 'git add app.js && git commit -m "feat: add app"')
[[ "$rc" -eq 0 ]] || { echo "FAIL: clean add&&commit should pass, got $rc"; exit 1; }
echo "PASS: clean add && commit passes"

# Case 3: `git add .` expands to changed files → violating file blocks.
echo 'console.log("x")' > "$REPO/other.js"
rc=$(run_hook 'git add . && git commit -m "feat: everything"')
[[ "$rc" -eq 2 ]] || { echo "FAIL: git add . should catch violating file, got $rc"; exit 1; }
rm -f "$REPO/other.js"
echo "PASS: git add . expands and scans untracked files"

# Case 4: `git commit -am` scans modified tracked files.
( cd "$REPO" && git add app.js && git commit -qm "feat: base" )
echo 'console.log("sneaky")' >> "$REPO/app.js"
rc=$(run_hook 'git commit -am "fix: tweak"')
[[ "$rc" -eq 2 ]] || { echo "FAIL: commit -am with dirty tracked file should block, got $rc"; exit 1; }
echo "PASS: git commit -am scans modified tracked files"

# Case 5: "-a"-looking text inside the quoted message is NOT a flag.
git -C "$REPO" checkout -q -- app.js
echo 'console.log("still dirty")' > "$REPO/unrelated.js"   # untracked, NOT added
rc=$(run_hook 'git commit -m "feat: support -a flag parsing"')
[[ "$rc" -eq 0 ]] || { echo "FAIL: '-a' inside message must not trigger PENDING_ALL, got $rc"; exit 1; }
rm -f "$REPO/unrelated.js"
echo "PASS: quoted '-a' in message is not treated as the -a flag"

# Case 6: G12 through the TOCTOU path — a sleep call in a test file being
# added. The literal is split ('slee''p') so THIS file — whose name matches
# the *test* glob — doesn't itself trip G12 when committed; the fixture
# written to disk still contains the real call.
printf 'it("x", () => { slee''p(100); });\n' > "$REPO/foo.test.js"
rc=$(run_hook 'git add foo.test.js && git commit -m "test: add foo"')
[[ "$rc" -eq 2 ]] || { echo "FAIL: sleep call in added test file should block (G12), got $rc"; exit 1; }
rm -f "$REPO/foo.test.js"
echo "PASS: G12 enforced on about-to-be-staged test files"

# Case 7: G7 through the TOCTOU path — bare `: any` in an added .ts file.
printf 'export const f = (x: any) => x;\n' > "$REPO/util.ts"
rc=$(run_hook 'git add util.ts && git commit -m "feat: util"')
[[ "$rc" -eq 2 ]] || { echo "FAIL: bare ': any' in added .ts should block (G7), got $rc"; exit 1; }
echo "PASS: G7 enforced on about-to-be-staged .ts files"

# Case 8: bypass marker still honored on the TOCTOU path.
touch "$XDG_CACHE_HOME/pilot/bypass-session"
echo 'console.log("debug")' > "$REPO/app2.js"
rc=$(run_hook 'git add app2.js && git commit -m "feat: bypassed"')
[[ "$rc" -eq 0 ]] || { echo "FAIL: bypass marker should allow, got $rc"; exit 1; }
rm -f "$XDG_CACHE_HOME/pilot/bypass-session"
echo "PASS: bypass markers honored on the pending-files path"

echo "ALL pre-commit TOCTOU tests passed."
