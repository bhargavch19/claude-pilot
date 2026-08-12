#!/usr/bin/env bash
# Replace <github-user> placeholders in README.md with your actual
# GitHub handle. Run this once before publishing the marketplace repo.
#
# Detection order:
#   1. $1 (explicit) — `bash dev/finalize-readme.sh thisisbhargavc`
#   2. `gh api user --jq .login` (requires gh auth login)
#   3. Bail with usage.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
README="$ROOT/README.md"

if [[ ! -f "$README" ]]; then
  echo "finalize-readme.sh: $README not found." >&2
  exit 1
fi

HANDLE="${1:-}"
if [[ -z "$HANDLE" ]]; then
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    HANDLE=$(gh api user --jq .login 2>/dev/null || true)
  fi
fi

if [[ -z "$HANDLE" ]]; then
  cat >&2 <<EOF
finalize-readme.sh: couldn't determine a GitHub handle.

Provide one explicitly:
  bash dev/finalize-readme.sh <handle>

Or authenticate gh first:
  gh auth login
  bash dev/finalize-readme.sh
EOF
  exit 1
fi

if ! grep -q '<github-user>' "$README"; then
  echo "No <github-user> placeholder remaining in $README."
  echo "Looks like it's already been finalized (or someone hand-edited it)."
  exit 0
fi

# Portable in-place edit: macOS sed needs an empty ext arg; GNU sed
# accepts -i with no ext. Use a tmp file to sidestep the difference.
tmp=$(mktemp)
sed "s|<github-user>|$HANDLE|g" "$README" > "$tmp"
mv "$tmp" "$README"
echo "Replaced <github-user> → $HANDLE in $README"
echo
echo "Next steps:"
echo "  git add README.md && git commit -m 'docs: set marketplace handle to $HANDLE'"
echo "  gh repo create pilot --public --source=. --push"
