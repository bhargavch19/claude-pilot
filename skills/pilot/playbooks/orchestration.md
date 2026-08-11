# Playbook: Orchestrate (parallel) — phase 0.8

> The process model for an agentic OS: when work decomposes into independent
> subtasks, run them concurrently instead of one-at-a-time. Routed from
> registry → **0.8 Orchestrate (parallel)**.

## When this phase applies

Use it **only** when subtasks are genuinely independent:
- no sequential dependency (task B doesn't need task A's output), and
- no shared mutable state (they don't edit the same files / rows).

Good fits: "review these 6 modules", "migrate every call site", "research these
4 options", "add tests to each of these files". Bad fits: a single feature built
step-by-step, or edits that touch the same file — those stay in the normal phase
loop (Plan → Build → Verify).

## The pattern

1. **Decompose** — write the work-list explicitly (one line per independent unit).
   If you can't list them without "then", it's sequential — don't fan out.
2. **Dispatch** — one subagent per unit, in a single batch so they run
   concurrently (`superpowers:dispatching-parallel-agents`). Give each a tight,
   self-contained brief and the exact return shape you need.
3. **Join** — collect results, dedupe/merge, and reconcile conflicts in the main
   thread. The join is where cross-unit decisions happen, not inside the workers.
4. **Verify** — the production floor still applies to the merged result: a "done"
   claim after a fan-out needs a real captured test run like any other (the
   `verify-gate` doesn't care how the work was produced).

## Isolation

When workers mutate files in parallel, give each its own git worktree so they
can't clobber each other (`superpowers:using-git-worktrees`); merge at the join.
Read-only fan-outs (review, research) need no isolation.

## Guardrails

- Cap concurrency to something sane; a fan-out of 50 agents is rarely worth it.
- Prefer `superpowers:subagent-driven-development` when the units share a plan
  but are independently implementable.
- If a worker's result is uncertain, verify it adversarially before merging —
  parallelism multiplies plausible-but-wrong outputs as fast as correct ones.
