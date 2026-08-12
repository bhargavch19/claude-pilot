---
description: Disable pilot hooks for the rest of the session.
allowed-tools: Bash
---

Activate session-long pilot bypass. Run:

```bash
BYPASS_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pilot"
mkdir -p "$BYPASS_DIR"
touch "$BYPASS_DIR/bypass-session"
echo "pilot off rails: session bypass active. Re-engage with /pilot-back-on."
```

The plan-gate and pre-commit hooks will short-circuit until the marker is
removed (`/pilot-back-on`). Use sparingly — guardrails exist for a reason.
