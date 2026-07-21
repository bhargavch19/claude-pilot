# Autopilot — requirement in, shipped change out

The driver spec for pilot's hands-off mode. One requirement → pilot conducts the
entire loop (frame → plan → build → verify → fix → review → ship → capture),
pausing only at two checkpoints: **plan approval** and **ship approval**.
Everything else advances without asking. Enforced by `hooks/autopilot-gate.sh`
(G16): while a cycle is active and not at a checkpoint or terminal state, the
Stop hook blocks ending the turn and tells you to advance.

Autopilot changes *when* phases run, not *how*. Every phase still routes to the
registry's skill for that phase; every gate (plan-gate, verify-gate, pre-commit,
safety-gate) still applies. Never bypass a gate on the cycle's behalf.

## Activation

Start a cycle when any of these hold (and no non-terminal cycle exists):

- Literal `autopilot` in the prompt (route-advisor hard-routes it).
- `/pilot-autopilot <requirement>`.
- A requirement plus explicit hands-off intent: "take this end to end",
  "handle this requirement fully", "don't stop until it ships".

A requirement *without* hands-off intent is normal phase routing — do not
infer autopilot. If `.pilot/cycle.json` exists with a non-terminal status,
the prompt is a **resume** (see below), not a new cycle.

## Cycle state — `.pilot/cycles/<branch-slug>.json`

**Branch-scoped**: the cycle file lives at `.pilot/cycles/<branch-slug>.json`
where the slug is the current branch with `/` → `-` (e.g. branch
`feat/dark-mode` → `.pilot/cycles/feat-dark-mode.json`). Two developers on
different branches of one repo never fight over cycle state. Outside a git
repo — or for cycles created before v0.10 — the legacy single-file path
`.pilot/cycle.json` is honored (the gate checks branch-scoped first, then
legacy). Survives session death; enables resume. You (the conductor) are
the only writer — hooks only read it. Update it at every transition, **before**
invoking the phase skill; the Stop gate reads it, so stale state causes
spurious blocks. Write with small `jq` edits via Bash.

```json
{
  "version": 1,
  "id": "cyc-YYYYMMDD-xxxx",
  "requirement": "<the user's requirement, verbatim>",
  "spine": "gsd | superpowers | paul",
  "status": "framing",
  "phases": [
    {"id": "frame",   "skill": "<per spine table>", "status": "pending"},
    {"id": "plan",    "skill": "...", "status": "pending"},
    {"id": "build",   "skill": "...", "status": "pending"},
    {"id": "verify",  "skill": "...", "status": "pending"},
    {"id": "review",  "skill": "...", "status": "pending"},
    {"id": "ship",    "skill": "...", "status": "pending"},
    {"id": "capture", "skill": "...", "status": "pending"}
  ],
  "current_phase": "frame",
  "fix_rounds": 0,
  "max_fix_rounds": 3,
  "checkpoints": {
    "plan_approved": false, "plan_approved_at": null,
    "ship_approved": false, "ship_approved_at": null
  },
  "artifacts": {"plan": null, "acceptance": ".pilot/acceptance.md", "pr": null},
  "halt_reason": null,
  "created": "<ISO8601>", "updated": "<ISO8601>",
  "session_last": "<first 8 chars of session id>"
}
```

`status` enum: `framing | planning | awaiting_plan_approval | executing |
verifying | fixing | reviewing | awaiting_ship_approval | shipping |
capturing | done | halted | aborted`. `phases[].status` enum:
`pending | active | done | failed`.

`awaiting_plan_approval`, `awaiting_ship_approval`, `halted`, `done`, and
`aborted` are **allow-states**: the Stop gate lets the turn end. Every other
status blocks stopping. **Before ending a turn to ask for approval, set the
awaiting status first** — that is what makes the ask deliverable.

`.pilot.json` overrides: `{"autopilot": {"max_fix_rounds": N,
"checkpoints": ["plan","ship"], "gate": "warn"|"off"}}`. Defaults:
3 rounds, both checkpoints, blocking gate.

## Cycle start

1. Capture the requirement **verbatim** into `requirement`.
2. Choose the spine per registry Resolution priority: `.planning/` → GSD;
   `.paul/` → PAUL (only if the user already opted in); multi-session or
   multi-file work → GSD; small single-session → superpowers.
3. Materialize `phases[]` from the spine table below.
4. Write cycle.json with `status=framing`, announce one line:
   `[autopilot] cycle <id> started — checkpoints at plan + ship.`

## Phase machine

| Cycle phase | superpowers spine | GSD spine (`.planning/`) |
|---|---|---|
| frame | `grill-with-docs` in assumption-stating mode: do NOT grill interactively mid-cycle — resolve what the codebase/docs can answer, turn material ambiguities into **stated assumptions** listed in the plan for checkpoint 1 | `gsd-spec-phase` |
| plan | `superpowers:writing-plans` → phased plan with tracer slices; write `.pilot/acceptance.md` (AC-first: `- [ ] AC-001 …` linked to task + test) — this is the plan artifact that satisfies plan-gate | `gsd-plan-phase` + the same AC ledger |
| **checkpoint 1** | set `status=awaiting_plan_approval`, present the phased plan + AC ledger + stated assumptions, stop. On approval: `plan_approved=true` + timestamp, `status=executing`, proceed without further prompting | same |
| build | `tdd` per tracer slice (red-green-refactor-commit); >3 independent slices → `superpowers:subagent-driven-development` | `gsd-autonomous` for the execute stretch (or `gsd-execute-phase` per phase); pilot resumes control at verify |
| verify | `verify` / `superpowers:verification-before-completion` — a **real captured test run** (capture-test-run.sh writes the fact file verify-gate checks) + check off each AC in `.pilot/acceptance.md`. UI changes: drive the browser too — `playwright-cli` first, `playwright` MCP fallback (SKILL.md → browser-driven verify) | `gsd-verify-work` + the same captured run + AC checkoff |
| fix loop | on verify failure: `fix_rounds += 1`. If `fix_rounds > max_fix_rounds`: `status=halted`, write `halt_reason`, deliver a halt report (what failed, what was tried, suspected root cause), stop. Else `status=fixing`, route `diagnose` (hypothesis-first), apply the fix, back to verify | same; `gsd-debug` as fallback |
| review | `superpowers:requesting-code-review`; add `security-review` when the diff touches auth/crypto/network paths (registry 6.5) | `gsd-code-review` |
| **checkpoint 2** | set `status=awaiting_ship_approval`, summarize: diff stat, test evidence, review findings + resolutions, AC ledger state. Stop. On approval: `ship_approved=true` + timestamp, `status=shipping` | same |
| ship | `superpowers:finishing-a-development-branch` | `gsd-ship`; record PR URL in `artifacts.pr` |
| capture | `graphify` the delta (`git diff --name-only <base>...HEAD`) + reconcile plan-vs-actual (loop-closure invariant); `status=done`, final one-paragraph cycle summary | + `gsd-extract-learnings` |

Mark each phase `active` on entry and `done`/`failed` on exit;
`current_phase` always names the phase in flight.

## Resume

On "continue" / "go" / a fresh session with a non-terminal cycle.json:

- **cycle.json outranks the routing.log glance** in SKILL.md's cross-turn
  phase awareness — read it first.
- Re-enter at `current_phase` with the recorded `status`.
- `awaiting_*` states: re-present the approval ask (the user may have
  answered in a dead session; never assume approval that isn't recorded).
- Update `session_last`.

## Abort and halt

- "autopilot off" / `/pilot-autopilot off` → set `status=aborted`, confirm in
  one line. Keep the file for post-mortem; the next cycle overwrites it.
- `halted` (fix-loop exhaustion) requires the halt report before stopping.
  The user can resume with more guidance ("continue, try X") — reset
  `fix_rounds` to 0 and `status=fixing` when they do.

## Approval integrity — witnessed, not asserted

Approvals are machine-witnessed: `hooks/approval-capture.sh` (UserPromptSubmit)
watches the **user's actual prompt** while a cycle waits at a checkpoint and
writes a witness marker (`$CACHE/pilot/approvals/<cycle-id>.<plan|ship>`) on a
clear, prompt-initial approval ("approved", "yes", "go", "ship it", "lgtm",
"proceed") or on `/pilot-approve`. You flip the checkpoint flag + timestamp
only after the witness exists (the hook's additionalContext tells you it
fired). The Stop gate cross-checks: a checkpoint flag with **no** witness
marker is self-approval — it directs you back to the awaiting status to
re-ask. UserPromptSubmit input is real user text the model cannot synthesize;
transcripts are never sniffed (the v0.9 lesson). If the user approves in
fuzzier words the hook didn't catch, ask them to reply `approved` or run
`/pilot-approve` — do not flip the flag on interpretation. The other hard
gates apply regardless: plan-gate demands the plan artifact before code,
verify-gate demands captured test evidence before "done".
