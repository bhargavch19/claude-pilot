#!/usr/bin/env bash
# Install the 4 Pocock skills missing from current Claude Code session.
# Verified missing as of 2026-05-04: zoom-out, setup-matt-pocock-skills,
# git-guardrails-claude-code, setup-pre-commit.
set -euo pipefail

echo "Installing Matt Pocock missing skills..."
echo "Run interactively and select these 4:"
echo "  - engineering/zoom-out"
echo "  - engineering/setup-matt-pocock-skills"
echo "  - misc/git-guardrails-claude-code"
echo "  - misc/setup-pre-commit"
echo ""
read -p "Press Enter to launch the skills installer..."

npx skills@latest add mattpocock/skills

echo ""
echo "Verify installation:"
echo "  ls ~/.claude/skills/ | grep -E 'zoom-out|git-guardrails|setup-pre-commit|setup-matt-pocock'"
