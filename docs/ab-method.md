# Measuring pilot's lift — the A/B method

> Hardening-plan Phase 3 deliverable. The METR RCT found experienced devs were
> **19% slower** with AI assistance while *feeling* faster — so pilot must be
> measured, not asserted. Routing accuracy is already scored
> (`dev/eval-routes.sh`, golden set, binary 0/1). This doc covers the harder
> question: does pilot improve *outcomes*?

## The metric

**First-pass-verified rate**: of the turns where "done" was claimed on changed
code, how many had a real captured passing test run at claim time (verify-gate
`pass`) vs were blocked for having none (`blocked`)? Recorded automatically in
the outcome ledger by `verify-gate.sh`; aggregated by `dev/outcome-report.sh`.

It is a *quality* proxy, deliberately: "how often is claimed work actually
verified" is harder to game than speed feelings and is the failure mode pilot
exists to prevent. Pair it with cycle time from git history if you also want a
speed axis (`git log --format='%ct %s'` between first commit and merge per
branch).

## Protocol (per developer or per team)

1. **Baseline (pilot off):** run `/pilot-off-rails` at session start for one
   work week. Hooks record nothing while bypassed, so baseline data instead
   comes from git + PR history: count PRs/branches where CI failed after the
   author declared ready (review "fix tests" rounds are the manual analogue of
   a `blocked`).
2. **Treatment (pilot on):** normal pilot operation for the following week.
   `dev/outcome-report.sh --days 7` gives pass/blocked/warn and the rate.
3. **Alternate A/B/A/B weekly** for at least four weeks before concluding
   anything — single-week deltas are noise (workload mix dominates).
4. **Team mode:** set `.pilot.json {"team": {"shared_outcomes": true}}` so
   every member's outcomes land in `.pilot/outcomes.jsonl` (repo-scoped,
   committable or gitignored per team policy). The report then breaks down
   per user.

## Scoring rules (binary, criteria-based — no LLM judging)

- A period's score is its first-pass-verified rate. Higher = fewer unverified
  "done" claims escaped toward review.
- Declare lift only if the on-period rate beats the off-period baseline across
  **both** on-weeks, and the block count isn't achieved by simply claiming
  "done" less often (check `total` is comparable across periods).
- Publish the numbers either way. A null or negative result is a finding, not
  a failure — it tells you which gates earn their keep.

## Caveats

- Self-measurement by the same person configuring the gates has obvious bias;
  for team decisions, have someone who didn't build the config read the
  numbers.
- The ledger only sees sessions where hooks ran. Off-rails periods are
  invisible to it by design — that's why the baseline uses git/PR history.
- n will be small. Treat this as a decision aid, not a paper.
