# Pilot → agentic OS plan (Phases 8–10)

> Builds on `docs/pilot-hardening-plan.md` (Phases 1–7, shipped on `pilot-hardening`).
> Adds the OS primitives still missing: a feedback loop, a live production floor, and
> persistent memory + parallel orchestration. Same conventions: TDD, keep
> `bash tests/run.sh` green, sync any new hook across all wiring points, atomic commits.

## Phase 8 — Close the learning loop (outcome ledger + feedback)
**Problem:** the eval *measures* routing but nothing *collects* real outcomes or *acts* on
them. **Fix:** a repo-scoped outcome ledger that the gate writes and the router reads.
- `verify-gate.sh` appends one JSON line per meaningful Stop (a "done" claim on changed
  code) to `~/.cache/pilot/outcomes.jsonl`: `{ts, session, repo, result: pass|blocked}`.
  `pass` = a real captured/verified run cleared it; `blocked` = no evidence, refused.
- `route-advisor.sh` reads the ledger for the current repo and, when the recent
  first-pass-verified rate is poor, injects a one-line nudge ("verify-gate blocked N of
  last M 'done' claims here — run tests before claiming done"). Behavioral feedback, not
  auto-rerouting (that stays a documented future step — too risky to flip blindly).
- `/pilot-stats` gains an **Outcomes** section (first-pass-verified rate per repo).
- Tests: ledger written on pass/block; reporter aggregates; advisory fires past threshold.

## Phase 9 — Live production floor (executing gates, not templates)
**Problem:** the floor is wireable (`/pilot-floor`, run-mode) but not *executing*.
**Fix:** a real floor check that runs and blocks, dogfooded on pilot's own repo.
- `dev/floor-check.sh`: runs the test suite + shellcheck (if present) + a conservative
  built-in **secret scan** (uses `gitleaks` when available, else a safe regex fallback).
  Non-zero exit on any gate failure. Runnable locally and in CI.
- Wire `floor-check.sh` into the repo's own CI as a blocking job (dogfood).
- Document `verify_gate:"run"` as the local enforcement path.
- Tests: floor-check passes clean tree, fails on a planted secret, skips absent tools.

## Phase 10 — Persistent memory + parallel orchestration
**Problem:** no cross-session project memory; one skill per phase (no fan-out).
**Fix (memory):**
- `.pilot/memory.md` — a project memory of decisions/conventions/gotchas.
- `hooks/memory-surface.sh` (SessionStart) injects a digest so it survives sessions;
  `/pilot-remember <note>` appends to it; precompact already re-anchors.
**Fix (orchestration):**
- New registry phase **0.8 Orchestrate (parallel)** + `playbooks/orchestration.md`:
  route work that decomposes into independent subtasks to the `Task`/`Agent` fan-out
  pattern with a dependency-aware join. Route-advisor + eval cover the trigger.
- Tests: memory round-trips and is surfaced; registry phase routes; eval stays 100%.

## Definition of done (each phase)
Tests green (quote output); new hooks synced across plugin.json + settings.json +
wire/unwire + pilot-doctor + README; CHANGELOG updated; atomic conventional commit.
Bump to 0.9.0 at the end.
