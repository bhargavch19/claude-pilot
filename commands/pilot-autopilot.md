---
description: "Run a requirement end-to-end on autopilot: frame → plan → build → verify → fix → review → ship, pausing only at plan + ship approval. Args: <requirement> | off | (none = cycle status)"
allowed-tools: Bash, Read
---

The user invoked `/pilot-autopilot` with arguments: `$ARGUMENTS`

Read `skills/pilot/autopilot.md` (next to this plugin's pilot skill) — it is
the driver spec. Then act on the arguments:

Cycle-file resolution (used by every mode below): repo root via
`git rev-parse --show-toplevel` (else cwd); branch slug via
`git rev-parse --abbrev-ref HEAD` with `/` → `-`; the cycle file is
`.pilot/cycles/<slug>.json`, falling back to legacy `.pilot/cycle.json`.

**`off`** — abort the active cycle. If the resolved cycle file exists and
is non-terminal, set `status=aborted` and `updated` via jq, confirm in one line
(`[autopilot] cycle <id> aborted.`). No cycle → say so.

**No arguments** — show cycle status:
```bash
REPO=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
SLUG=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr '/' '-')
C="$REPO/.pilot/cycles/$SLUG.json"; [[ -f "$C" ]] || C="$REPO/.pilot/cycle.json"
[[ -f "$C" ]] && jq '{id, status, current_phase, fix_rounds, checkpoints, halt_reason}' "$C" \
  || echo '(no autopilot cycle on this branch)'
```
If the cycle is at an `awaiting_*` checkpoint, re-present the pending approval
ask. If non-terminal and mid-phase, offer to continue it.

**Anything else** — the arguments are the requirement. Start a cycle per the
driver spec: if a non-terminal cycle already exists, ask whether to resume it
or abandon it for the new requirement (never silently overwrite live state);
otherwise capture the requirement verbatim, choose the spine, materialize the
phases, write `.pilot/cycle.json` with `status=framing`, announce the one-line
banner, and begin the frame phase. From here the autopilot-gate (G16) keeps
the cycle advancing; the only stops are the plan and ship checkpoints.
