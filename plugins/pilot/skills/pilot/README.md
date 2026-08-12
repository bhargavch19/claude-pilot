# pilot

User-level Claude Code skill that routes intent → underlying skill, enforces CLAUDE.md guardrails, and stays extensible.

## Install

1. Build dir: `~/Workspace/claude-skill/pilot/` (this repo).
2. Symlink: `ln -sfn ~/Workspace/claude-skill/pilot ~/.claude/skills/pilot`.
3. Wire hooks: `bash ~/Workspace/claude-skill/dev/wire-hooks.sh`.
4. Restart Claude Code.

## Files

- `SKILL.md` — entry point, routing logic.
- `registry.md` — phase → skill table (extensibility surface).
- `guardrails.md` — 15 enforced rules.
- `workflow.md` — Pocock loop.
- `playbooks/*.md` — phase-combination scripts.
- `hooks/*.sh` — shell hooks.

## Extending

Add a new skill:
1. Append a row to `registry.md`.
2. (Optional) Add a playbook in `playbooks/`.
3. Restart session.

Add a guardrail:
1. Append a row to `guardrails.md`.
2. If hard layer: write hook in `hooks/`, add test in `tests/hooks/`, wire in `dev/wire-hooks.sh`.
3. Run `bash tests/run.sh` until green.

## Bypass

| Phrase | Effect |
|---|---|
| `pilot off` | disable for next turn |
| `pilot off rails` | disable for session |
| `pilot --skip-tdd` | skip TDD for this build |
| `pilot --no-plan` | skip plan gate |
| `pilot back on` | resume after `off rails` |
