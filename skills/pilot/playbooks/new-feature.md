# Playbook: New feature

**Trigger:** "build", "add", "feature for", "implement X" with code intent.

**Sequence:**
1. **Recall** — `claude-mem:mem-search "<feature topic>"`. Anything similar before?
2. **Frame** — `grill-with-docs`. Output: shared understanding + success criteria.
3. **PRD** — `to-prd`. Output: `docs/superpowers/specs/<date>-<feature>.md`.
4. **Plan** — `superpowers:writing-plans` (single sess) OR `gsd-plan-phase` (multi).
   Write the acceptance criteria to `.pilot/acceptance.md` as `- [ ]` checkboxes —
   the verify-gate blocks "done" while any are unchecked.
5. **Tracer slice 1** — pick thinnest E2E. `tdd` runs red-green-refactor-commit.
6. **Subsequent slices** — `superpowers:subagent-driven-development` if >3 slices, else inline.
7. **Verify** — `superpowers:verification-before-completion`. Check off each AC
   in `.pilot/acceptance.md` as its evidence lands.
8. **Review** — `superpowers:requesting-code-review`.
9. **Ship** — `gsd-ship` or `superpowers:finishing-a-development-branch`.
10. **Capture** — auto via claude-mem. Then `graphify` the changed files
    (`git diff --name-only <base>...HEAD`) so the new code is in the knowledge
    graph for future debugging.

**Guardrails active:** G1, G2, G3, G4, G5, G6, G7, G8, G9, G10, G14.

**Bypass:** `pilot --skip-tdd` (rare), `pilot --no-plan` (only for <20 LOC).
