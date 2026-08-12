# verify-gate

Un-fakeable verification for Claude Code. Your agent says "done, tests
pass" — did they? This plugin makes the claim checkable in code:

- A **PostToolUse hook** records the *actual exit codes* of test-runner
  commands to a session fact file.
- A **blocking Stop hook** refuses "done" / "ready" / "tests pass" claims on
  code-changing turns unless a real captured pass exists for this session.
  Transcript prose does not count. The model cannot write "tests passed"
  without having run them.
- `verify_gate: "run"` mode goes further: the gate executes your
  `test_command` itself and trusts only the real exit code.

This is the standalone extraction of the [pilot](../../README.md)
conductor's most-asked-about pair of hooks — same scripts, byte-identical
(CI enforces it), none of pilot's routing or other gates.

## Install

```
/plugin marketplace add bhargavch19/claude-pilot
/plugin install verify-gate@pilot
```

Restart Claude Code. Wires exactly three hook entries (PostToolUse on Bash,
Stop, SubagentStop) and no MCP servers. Configure per repo via `.pilot.json`
— see [`skills/verify-gate/SKILL.md`](./skills/verify-gate/SKILL.md).

Safety valves: `{"verify_gate": "warn"}` downgrades to advisory for a repo,
and the gate auto-releases after two consecutive blocks so it can never trap
a session.

Already running the full `pilot` plugin? You have these hooks — don't
install both, or the gate fires twice.
