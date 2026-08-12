---
description: Re-engage pilot after /pilot-off-rails.
allowed-tools: Bash
---

Remove any session bypass marker. Run:

```bash
BYPASS_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pilot"
rm -f "$BYPASS_DIR/bypass-session" "$BYPASS_DIR/bypass-once" "$BYPASS_DIR/bypass-no-plan-once"
echo "pilot back on: gates re-engaged."
```

Confirm to the user and continue with whatever they asked for next.
