# Pilot tests

```bash
bash tests/run.sh
```

Runs every hook + dev integration test. Each test script is hermetic
(uses `mktemp -d` and overrides `XDG_CACHE_HOME`), so re-running won't
touch your real settings or bypass markers.

## Layout

- `tests/hooks/` — one script per hook surface (plan-gate, pre-commit,
  verify-gate, sessionstart-banner, precompact-anchor, log-skill-invocation,
  malformed-json).
- `tests/dev/` — integration tests for `plugins/pilot/dev/wire-hooks.sh` and
  `plugins/pilot/dev/wire-mcps.sh` (wire-mcps uses a mock `claude` CLI shim).
- `tests/dogfood/sample_prompts.md` — manual routing prompts to paste
  into a live Claude Code session.

## Hand-testing hooks from an interactive shell

The bundled scripts all start with `#!/usr/bin/env bash`, so they run
under bash regardless of your login shell. If you want to pipe a JSON
payload to a hook from your own terminal, **don't use `echo`** —
zsh's `echo` interprets `\n` as a real newline and corrupts the JSON
before it reaches the hook. Use `printf '%s'` instead:

```bash
# CORRECT
printf '%s' '{"tool_name":"Edit","tool_input":{"new_string":"line1\nline2"}}' \
  | hooks/plan-gate.sh

# BROKEN in zsh — \n becomes a real newline → invalid JSON
echo '{"tool_name":"Edit","tool_input":{"new_string":"line1\nline2"}}' \
  | hooks/plan-gate.sh
```

(The hooks themselves now decline cleanly on invalid JSON — they log to
stderr and exit 0 — so this footgun no longer silently disables the
gates. But the resulting "gate skipped" stderr is still confusing.)
