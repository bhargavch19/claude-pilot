---
description: Bypass a specific pilot gate once. Args: --no-plan | --no-precommit | --skip-tdd
argument-hint: --no-plan | --no-precommit | --skip-tdd
allowed-tools: Bash
---

The user invoked `/pilot-bypass $ARGUMENTS`. Parse `$ARGUMENTS` and act:

- `--no-plan` → arm a one-shot plan-gate bypass:
  ```bash
  BYPASS_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pilot"
  mkdir -p "$BYPASS_DIR"
  touch "$BYPASS_DIR/bypass-no-plan-once"
  echo "pilot --no-plan: plan-gate skipped on next Edit/Write/MultiEdit/NotebookEdit."
  ```

- `--no-precommit` → arm a one-shot pre-commit bypass (the `git commit`
  G3/G7/G8/G12 checks will be skipped exactly once):
  ```bash
  BYPASS_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pilot"
  mkdir -p "$BYPASS_DIR"
  touch "$BYPASS_DIR/bypass-precommit-once"
  echo "pilot --no-precommit: pre-commit skipped on next git commit."
  ```

- `--skip-tdd` → no hook enforces TDD (it's a soft rule), so this is purely
  conversational. Acknowledge it ("`--skip-tdd` noted — I'll proceed without
  red-green-refactor for this slice"), and continue. The user is on the hook
  for verifying their own work.

- No arguments or unknown flag → print usage:
  ```
  /pilot-bypass --no-plan       # one-shot plan-gate skip
  /pilot-bypass --no-precommit  # one-shot pre-commit skip
  /pilot-bypass --skip-tdd      # acknowledge TDD skip (soft)
  ```
  Then stop. Mention that `/pilot-off` skips whichever gate fires first
  (use that when you don't care which one is in the way).

After arming a bypass, continue with whatever the user asked for next.
