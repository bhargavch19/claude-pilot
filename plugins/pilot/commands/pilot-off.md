---
description: Bypass pilot's hooks for the next tool call only.
allowed-tools: Bash
---

Arm a one-shot pilot bypass. Run:

```bash
BYPASS_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pilot"
mkdir -p "$BYPASS_DIR"
touch "$BYPASS_DIR/bypass-once"
echo "pilot off: one-shot bypass armed. Next plan-gate or pre-commit fire will be skipped."
```

Then proceed with whatever the user asked for. After the next gate fires
and consumes the marker, pilot re-engages automatically.

If the user wants the bypass to last the whole session instead, point them
at `/pilot-off-rails`. To bypass just plan-gate (not pre-commit), use
`/pilot-bypass --no-plan`.
