# Measuring pilot

There is **no controlled study** that hooks/routing improve coding outcomes —
the design is first-principles plus testimonials. The
[METR RCT](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/)
found experienced devs were **19% slower** with AI while *feeling* faster. So
pilot does not assert it helps; it ships the means to **measure** whether it
does. Two layers:

## 1. Routing correctness (automated, in-suite)

The deterministic route-advisor is the one surface where "correct" is
objective. `dev/eval-routes.sh` scores it against a golden set
(`tests/eval/golden_routes.tsv`):

```bash
bash dev/eval-routes.sh          # prints "pilot routing eval: N/N correct (100%)"
```

- **Binary 0/1 per case**, not a 0.0–1.0 score (research: binary pass/fail is
  more reliable than graded judging).
- **Criteria-based**, not LLM-judged: a case passes iff the expected skill
  token appears in the computed route, or — for `NONE` — the advisor stays
  silent on fuzzy/common-word prompts.
- The advisor is deterministic, so the set must score **100%**; the suite gate
  (`tests/dev/test_eval_routes.sh`) fails the build otherwise. A drop is a
  routing regression, not noise.

**Extend it:** add `<prompt><TAB><expected-token-or-NONE>` rows to the golden
set. Use `NONE` for prompts that *should* be left to the model (common-English
skill names, fuzzy intent). Re-run the eval; if a new row fails, either the
label is wrong or the routing changed.

## 2. End-to-end lift (manual A/B protocol)

Routing accuracy is necessary, not sufficient — it does not prove pilot makes
*you* faster or more correct. To estimate that, run the same task set with
pilot on vs off and compare. Suggested protocol:

1. **Task set.** Pick 8–12 representative tasks (a bug fix, a small feature, a
   refactor, a doc update, a risky migration). Freeze them in writing so both
   arms run the identical prompts.
2. **Arms.**
   - *Pilot on:* hooks wired (`bash dev/wire-hooks.sh`), normal session.
   - *Pilot off:* `bash dev/unwire-hooks.sh` (or `/pilot-off-rails` for the
     session). Same model, same repo state.
   - Alternate arm order per task to cancel ordering/learning effects.
3. **Outcome metrics** (record per task):
   - **Correctness** — did the change pass its tests / acceptance check on the
     first "done" claim? (binary)
   - **Rework** — number of follow-up turns after the first "done".
   - **Wall-clock** and **turns to green**.
   - **Guardrail events** — verify-gate blocks, safety-gate blocks, plan-gate
     fires (from `~/.cache/pilot/routing.log` and hook stderr).
4. **Read it honestly.** Small N means trends, not proof. Watch specifically
   for the METR effect: feeling faster while being slower. Trust the
   first-pass-correctness and rework numbers over your perception.

This file is the measurement contract. If a future change claims pilot "helps,"
it should cite numbers produced this way — not vibes.
