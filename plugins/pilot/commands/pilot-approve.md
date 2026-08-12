---
description: "Record the user's approval for the autopilot checkpoint currently waiting (plan or ship). Writes the witness marker autopilot-gate verifies."
allowed-tools: Bash
---

The user explicitly invoked `/pilot-approve` — that invocation IS the approval
signal for the checkpoint the current cycle is waiting at.

Run:

```bash
REPO=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
SLUG=$(git symbolic-ref --short -q HEAD 2>/dev/null | tr '/' '-')
C="$REPO/.pilot/cycles/$SLUG.json"; [[ -f "$C" ]] || C="$REPO/.pilot/cycle.json"
if [[ ! -f "$C" ]]; then echo "no autopilot cycle on this branch"; exit 0; fi
ID=$(jq -r '.id' "$C"); ST=$(jq -r '.status' "$C")
case "$ST" in
  awaiting_plan_approval) G=plan ;;
  awaiting_ship_approval) G=ship ;;
  *) echo "cycle $ID is not waiting at a checkpoint (status=$ST) — nothing to approve"; exit 0 ;;
esac
A="${XDG_CACHE_HOME:-$HOME/.cache}/pilot/approvals"; mkdir -p "$A"
date -u +%FT%TZ > "$A/$ID.$G"
echo "witnessed: $G approval for cycle $ID"
```

If a marker was written: set `checkpoints.<gate>_approved=true` +
`<gate>_approved_at` in the cycle file, flip `status` to the next phase
(`executing` after plan, `shipping` after ship), and continue the cycle.
If not (no cycle / not at a checkpoint), just relay the message.
