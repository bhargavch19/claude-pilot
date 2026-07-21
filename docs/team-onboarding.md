# Pilot in 10 minutes — team onboarding

The mental model a new teammate needs. Everything else is discoverable via
`/pilot-status`, `/pilot-doctor`, and `skills/pilot/registry.md`.

## The one idea

Pilot is a **conductor**: it routes every prompt to the right phase-specific
skill and lets **hooks** — not promises — enforce quality. You never invoke it;
it engages on its trigger words or on session start. Naming a skill literally
(`tdd`, `diagnose`, `graphify`) always routes straight there.

## The loop you're inside

```
Frame → Plan → Build → Verify → Review → Ship → Capture
```

Every phase has a primary skill and fallbacks (see `registry.md` — it's a
table; the row is the truth). Three gates matter day-to-day:

| Gate | When it fires | What it wants |
|---|---|---|
| plan-gate (G1) | you edit >20 lines with no plan artifact | a plan file or `.pilot/acceptance.md` first |
| pre-commit (G3/7/8/12) | `git commit` | conventional message, no `: any`, no console.log, no sleep-in-tests |
| verify-gate (G14) | you claim "done" with changed code | a REAL captured test run this session — prose never counts |

Gates warn-then-yield rather than trap (2–3 blocks max), and every one has a
bypass: `pilot off` (one fire), `pilot off rails` (session). Bypasses are
visible in `/pilot-status` — use them, don't game them.

## Autopilot (the hands-off mode)

`/pilot-autopilot "<requirement>"` runs the whole loop and stops exactly twice:

1. **Plan checkpoint** — you approve the phased plan + acceptance criteria.
2. **Ship checkpoint** — you approve the reviewed, test-evidenced diff.

Reply **`approved`** (or run `/pilot-approve`) — your actual prompt is what
counts: a UserPromptSubmit hook witnesses it, and the Stop gate rejects any
checkpoint the model "approved" on its own. Cycle state is per-branch
(`.pilot/cycles/<branch>.json`), so parallel teammates don't collide.
`continue` resumes a cycle after any interruption; `autopilot off` aborts.
Three failed fix rounds → the cycle halts with a report instead of thrashing.

## Team knobs (`.pilot.json` at the repo root)

```json
{
  "profile":  { "style": "standard", "strictness": "team" },
  "team":     { "shared_outcomes": true },
  "autopilot": { "max_fix_rounds": 3 },
  "test_patterns": ["<your runner command>"]
}
```

`shared_outcomes` feeds `.pilot/outcomes.jsonl`; `dev/outcome-report.sh`
turns it into the team's first-pass-verified rate. `test_patterns` teaches
the capture hook your test runner so verify-gate can see real runs.

## Day one

```bash
bash dev/bootstrap-team.sh --check   # what's missing/drifted vs the pinned lock
/pilot-doctor                        # is everything wired
```

Then just work. When a gate blocks you and you think it's wrong, say so in the
team channel instead of bypassing silently — the gates are supposed to earn
their keep (`docs/ab-method.md` is how we check that they do).
