# Pilot Workflow — the embedded Pocock loop

The default flow for a new feature. Pilot follows this unless the user's prompt clearly indicates a different phase (debug, refactor, etc.).

## The loop

```
Recall → Frame → PRD → Plan → Tracer → TDD → AFK execute → Verify → Review → Ship → Capture
```

### 1. Recall (auto, SessionStart)
- Run `claude-mem:mem-search` with query derived from cwd + last commit subject.
- Surface 2–3 most relevant prior decisions, not full content.

### 2. Frame
- Code: `grill-with-docs` (challenges plan against domain model + ADRs).
- Non-code: `grill-me`.
- Run the **clarify scan** (`playbooks/requirements.md` §1): scope boundary,
  inputs/outputs, error behavior, non-functionals, integration points, done
  criteria. Material ambiguity → one focused question; the rest → stated
  assumptions.
- Output: shared understanding of what + why + success criteria.

### 3. PRD
- `to-prd` — produces a PRD that quizzes about which modules are touched (Pocock: prevents ball-of-mud).
- For GSD-tracked projects: `gsd-spec-phase` instead.

### 4. Plan
- `superpowers:writing-plans` — bite-sized TDD tasks.
- Or `to-issues` — splits PRD into independently-grabbable tracer-bullet vertical slices.
- Single session: writing-plans. Multi-session/multi-day: GSD `gsd-plan-phase`.
- **Write the AC ledger**: distill the plan's acceptance criteria into
  `.pilot/acceptance.md` as `- [ ]` checkboxes with stable IDs (`AC-001`),
  each linked to the task that delivers it and the test that proves it —
  then run the analyze coverage check before the first Build edit
  (`playbooks/requirements.md` §2–3). The verify-gate blocks "done" while
  any box is unchecked — this is how requirements can't silently drop.

### 5. Tracer
- Pick the thinnest end-to-end vertical slice that delivers value.
- One file per slice when possible.
- Slice 1 should ship to staging if applicable.

### 6. TDD (per tracer slice)
- `tdd` (Pocock) — red → green → refactor → commit.
- Each tracer = one commit (G3).

### 7. AFK execute
- For multi-slice plans, `superpowers:subagent-driven-development` dispatches a fresh subagent per slice.
- Bhargav reviews diff between slices (G6).

### 8. Verify
- `superpowers:verification-before-completion` — runs the test suite, captures output, asserts green.
- Or `gsd-verify-work` for GSD projects.
- Hook `verify-gate.sh` **blocks** a "done" claim unless a real test run was
  captured this session AND `.pilot/acceptance.md` (when present) is fully
  checked. Check each AC off as its evidence lands.

### 9. Review
- `superpowers:requesting-code-review` — independent read.
- Or `gsd-code-review` for GSD projects.
- Address findings before Ship.

### 10. Ship
- `gsd-ship` (creates PR, runs review, merges).
- Or `superpowers:finishing-a-development-branch` for ad-hoc.

### 11. Capture
- `claude-mem` auto-captures observations.
- For GSD: `gsd-extract-learnings`.
- **Graphify the delta**: run `graphify` on the files changed this cycle
  (`git diff --name-only <base>...HEAD`) so the new code is in the knowledge
  graph before the next debugging session needs it.

## Smart vs dumb context zones (per Pocock)

- **Smart zone** = where pilot + grilling + planning happens. High agent involvement.
- **Dumb zone** = where AFK execution runs against a written plan. Low context, high speed.
- Move work from smart → dumb only after Plan is written and approved.
