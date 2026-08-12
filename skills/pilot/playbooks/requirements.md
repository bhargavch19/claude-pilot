# Playbook: Requirements — clarify, trace, analyze, verify

> Mechanics ported from GitHub spec-kit's `/speckit.clarify` + `/speckit.analyze`
> (MIT), adapted to pilot's phase loop. This is the front half of the AC ledger:
> the ledger only catches requirements that were *written down* — this playbook
> makes sure they get written down.

## 1. Clarify (Frame phase, before any plan)

Scan the user's ask across these ambiguity dimensions. For each one that is
unclear AND materially changes the design, resolve it — one focused question
per turn (G4); everything else becomes an explicit stated assumption in the plan:

- **Scope boundary** — what is explicitly out of scope?
- **Inputs/outputs** — formats, ranges, encodings, empty/huge cases.
- **Error behavior** — what does the user see on each failure path? (G9)
- **Non-functionals** — performance, security, accessibility, offline.
- **Integration points** — what existing code/contracts does this touch?
- **Done criteria** — how will the user judge it works?

Do NOT proceed to Plan with an unstated material ambiguity. Unresolved
minor ones go in the plan under `## Assumptions`.

## 2. Trace (Plan phase)

Assign every requirement a stable ID and write the ledger the verify-gate
enforces:

```markdown
# Acceptance criteria — <feature> (<date>)
- [ ] AC-001: <observable behavior> — task: <plan task #>, test: <test name>
- [ ] AC-002: ...
```

File: `.pilot/acceptance.md` at the repo root. Rules:
- Every AC names the plan task that delivers it and the test that proves it.
- Every plan task references ≥1 AC. A task with no AC is scope creep (G5) —
  cut it or add the missing requirement.
- Write ACs as observable behavior ("returns 400 on malformed id"), never
  implementation ("add a try/catch").

## 3. Analyze (gate between Plan and Build)

Before the first Build edit, run the coverage matrix over the plan + ledger:

| Check | Failure means |
|---|---|
| AC with no covering task | a requirement will silently drop |
| Task with no AC | scope creep or a missing requirement |
| AC with no named test | it will be "done" without proof |
| AC not testable as written | rewrite it as observable behavior |

Any failure → fix the plan/ledger first. This costs one pass and prevents
the class of bug where the build faithfully implements an incomplete plan.

## 4. Verify (close-out)

Check an AC off only with evidence attached in the transcript: the named
test's captured result, or the observed behavior (playwright snapshot, CLI
output). `verify-gate.sh` blocks any "done" claim while a box is unchecked —
if an AC is genuinely dead, move it to an `## Out of scope` section in the
ledger with one line of why (that is auditable; deleting it is not).
