#!/usr/bin/env bash
# Apply the pilot production-quality floor to a project (idempotent).
# Run during Phase 0.75 Bootstrap, or manually: apply-floor.sh [target-dir]
#
# Drops the CI workflow + pre-commit config, then prints the remaining
# (human-confirmed) activation steps. Never overwrites an existing file.
set -euo pipefail

TARGET="${1:-$PWD}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$HERE/templates"

[[ -d "$TARGET" ]] || { echo "apply-floor: target '$TARGET' is not a directory" >&2; exit 1; }

copy_once() {
  local src="$1" dst="$2"
  if [[ -e "$dst" ]]; then
    echo "  = exists, kept: ${dst#"$TARGET"/}"
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "  + added:        ${dst#"$TARGET"/}"
  fi
}

echo "Applying production-quality floor → $TARGET"
copy_once "$TPL/ci-quality-floor.yml"   "$TARGET/.github/workflows/quality-floor.yml"
copy_once "$TPL/pre-commit-config.yaml" "$TARGET/.pre-commit-config.yaml"

cat <<'EOF'

Next (human-confirmed) steps:
  1. Ensure package.json / pyproject exposes: test, typecheck, lint
  2. pre-commit install            # activates local blocking hooks
  3. Install CLIs as needed:       gitleaks, semgrep, osv-scanner
  4. Record thresholds in CLAUDE.md so the floor is discoverable
Tune the templates to your stack; delete the language block you don't use.
EOF
