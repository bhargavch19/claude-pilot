---
name: verify-gate
description: Use when configuring or troubleshooting the verify-gate — the blocking Stop hook that refuses "done"/"ready"/"tests pass" claims unless a real test run was captured this session. Covers .pilot.json options (verify_gate warn/run modes, test_command, test_patterns, test_timeout), why a claim was blocked, and how to bypass or downgrade the gate.
---

# verify-gate

Two hooks that make Claude Code prove its work instead of narrating it:

1. **`capture-test-run.sh`** (PostToolUse on Bash) — recognizes test-runner
   commands (pytest, vitest, bun test, go test, cargo test, make test, …,
   plus per-repo `test_patterns`) and records their **real exit code** to a
   session-scoped fact file.
2. **`verify-gate.sh`** (Stop + SubagentStop) — when the turn changed source
   files and the reply claims "done" / "ready" / "tests pass", the gate
   blocks unless the fact file holds a real captured pass for this session.
   Transcript prose does not count.

## Per-repo configuration — `.pilot.json` at the repo root

```json
{
  "test_patterns": ["rake test", "my-custom-runner"],
  "verify_gate": "run",
  "test_command": "bash tests/run.sh",
  "test_timeout": 120
}
```

- Default (no config): the gate **blocks** unverified "done" claims on
  code-changing turns.
- `"verify_gate": "warn"` — downgrade to a non-blocking warning for this repo.
- `"verify_gate": "run"` — the gate executes `test_command` itself (bounded
  by `test_timeout`, default 120s) and uses the real exit code; runs lazily,
  at most once per session. Requires `test_command`.
- `test_patterns` — extra regexes unioned with the built-in runner list when
  deciding whether a Bash command was a test run.

## When the gate blocks you

Run the project's real test suite so the pass is captured, then finish the
turn. If the block is wrong (docs-only change misdetected, spike work),
either set `"verify_gate": "warn"` for the repo or rely on the anti-trap:
the gate auto-releases after two consecutive blocks so it can never trap a
session.

## AC ledger (optional)

If `.pilot/acceptance.md` exists with `- [ ]` checkboxes, the gate also
refuses "done" while acceptance criteria remain unchecked — check each box
as it's delivered or explicitly mark it out of scope.

## Note when installed standalone

The free-text bypass phrase ("pilot off") is written by the full
[pilot](https://github.com/bhargavch19/claude-pilot) plugin's
UserPromptSubmit hook; standalone installs bypass via `.pilot.json`
(`"verify_gate": "warn"`) or the two-block auto-release.
