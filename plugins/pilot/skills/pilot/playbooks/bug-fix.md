# Playbook: Bug fix

**Trigger:** "bug", "broken", "throws", "fails", "regression", "not working".

**Sequence:**
1. **Reproduce** — `diagnose` step 1: minimal repro. Block fix attempts until repro is concrete.
2. **Hypothesise** — `diagnose` step 2: 1-3 candidate causes ranked by likelihood.
3. **Instrument** — `diagnose` step 3: add logging or breakpoints to confirm.
4. **Fix** — write a regression test first (red), then minimal patch (green).
5. **Verify** — `superpowers:verification-before-completion`. Run full suite.
6. **Commit** — atomic: regression test + fix in one commit. Message: `fix: <description>`.

**Guardrails active:** G3, G6, G10, G11, G12, G14.

**Anti-pattern blocked:** "fix the symptom" without root cause. If patching symptom, flag root cause as follow-up (G5).
