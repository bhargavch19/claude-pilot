# Playbook: Refactor

**Trigger:** "messy", "hard to change", "clean up", "this file is too big".

**Sequence:**
1. **Scope** — `zoom-out` first: explain the file in whole-system context. Confirm refactor scope is local.
2. **Audit** — `improve-codebase-architecture` finds deepening opportunities.
3. **Plan** — `superpowers:writing-plans` with atomic slices. Each slice keeps tests green.
4. **Execute** — slice by slice. Run tests after every slice.
5. **Verify** — full suite green; behavior unchanged (no new tests, no new features).
6. **Review** — `simplify` skill for code-quality review.
7. **Ship** — separate PR from feature work.

**Guardrails active:** G1, G3, G5 (no scope creep — refactor only), G6, G10, G14.

**Hard rule:** no behavior changes. If you find a bug during refactor, file a follow-up; don't fix in the same PR.
