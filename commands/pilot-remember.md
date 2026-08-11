---
description: Append a durable note to this project's pilot memory (.pilot/memory.md).
allowed-tools: Bash
---

The user wants to remember something durably for this repo — a decision,
convention, or gotcha that should survive across sessions. It's surfaced at the
start of every future session by the `memory-surface` hook.

Append their note (the command arguments) to `.pilot/memory.md`, creating the
file with a header if missing, then confirm what was saved:

```bash
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
mkdir -p "$ROOT/.pilot"
MEM="$ROOT/.pilot/memory.md"
[ -f "$MEM" ] || printf '# Pilot project memory\n\n> Durable decisions, conventions, and gotchas — surfaced at SessionStart.\n\n' > "$MEM"
printf -- '- %s\n' "$ARGUMENTS" >> "$MEM"
echo "remembered → ${MEM}"
tail -5 "$MEM"
```

Keep each note to one decision-oriented line. If the note is vague, sharpen it
into a concrete, durable statement before saving. Confirm the saved line.
