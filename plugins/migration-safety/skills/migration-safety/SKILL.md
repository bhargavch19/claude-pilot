---
name: migration-safety
description: Analyze proposed schema migrations, dependency upgrades, and breaking changes for production safety. Use when adding or changing DB migrations, bumping major versions of dependencies, modifying APIs that have external consumers, or touching lockfiles. Triggers on "migration", "schema change", "upgrade dep", "breaking change", "lockfile bump", and on any diff that touches `migrations/`, `package.json`, `requirements.txt`, `Cargo.lock`, `Gemfile.lock`, `go.sum`, or `**/*.migration.sql`.
---

# Migration Safety

## Status: scaffold (full implementation queued)

This skill is registered in pilot's routing table (Phase 7.5 Migration) but its full content is queued for a follow-up session. Until then, this file performs the role of a **transparent redirect**: when pilot routes here, hand off to a working fallback that covers the same use case, and document what the full skill will do so the redirect feels honest, not broken.

### Redirect for now

- **Schema migration** → use `to-issues` to break the migration into a tracer-bullet sequence: write the forward migration, write the reverse migration, dry-run the forward on a snapshot of prod data, write the rollback playbook, ship the forward with a feature flag.
- **Dep upgrade (major version bump)** → use `diagnose` to assess regression risk: read the dep's CHANGELOG, identify every `BREAKING` entry, grep the codebase for callsites, surface what's likely to break.
- **API contract change** → use `to-prd` to make the contract change explicit, then `superpowers:requesting-code-review` to gate external-consumer impact.

State explicitly to the user: "migration-safety is scaffold-only; using `<fallback>` for this turn."

## When the full skill is implemented, it will cover

### 1. Concurrent-write safety (DB migrations)

For each migration touching live tables:
- Identify locks acquired (`ACCESS EXCLUSIVE`, `SHARE`, etc.)
- Estimate lock duration as a function of table size
- Suggest concurrent alternatives (`CREATE INDEX CONCURRENTLY`, two-step add-column-with-default, etc.)
- Flag operations that block writes for >100ms on tables >1M rows

### 2. Rollback plan

- Every forward migration must have a documented reverse migration OR a feature-flag-toggle to disable the new code path.
- For irreversible migrations (drop column, drop table), require explicit acknowledgment in a `MIGRATION-SAFETY.md` block.

### 3. Downtime estimate

- Read row count from `information_schema` / equivalent
- Apply known per-operation timing (ALTER TABLE adds ~1ms/row for many operations)
- Output an estimated window with a confidence interval

### 4. Dep upgrade breaking-change scan

- Resolve the changelog of the bumped dep (npm package CHANGELOG.md, GitHub releases, Cargo crate metadata)
- Filter to `BREAKING` / `MAJOR` entries between the current and target version
- For each, grep the codebase for callsites of the affected API
- Output a `BREAKING-IMPACT.md` with a table: API → callsite count → suggested migration

### 5. Feature-flag wrapping

- For changes deemed risky by the above checks, propose a feature flag with:
  - Default state (off for new code, on for existing behavior)
  - Documented removal date (default: 30 days after deploy)
  - Rollback procedure that doesn't require redeploy

## Output artifact

Full skill writes `MIGRATION-SAFETY.md` to the phase artifact directory (`.planning/phase-XX/MIGRATION-SAFETY.md` when GSD project state exists, else `docs/migration-safety/<branch>.md`).

The report sections mirror sections 1-5 above. Each section has a verdict: `PASS` / `CAUTION` / `BLOCK`. Any `BLOCK` halts the Pre-deploy phase until resolved.

## Acceptance criteria for the full skill

- Can parse migrations in at least: PostgreSQL (`ALTER TABLE`), MySQL, SQLite, Rails ActiveRecord, Django, Alembic.
- Can read at least: `package.json`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `requirements.txt`, `Pipfile.lock`, `Cargo.lock`, `Gemfile.lock`, `go.sum`.
- Produces a `MIGRATION-SAFETY.md` artifact with all 5 sections populated.
- Integrates with `/pilot-doctor` — a "branch ship-readiness" check that surfaces any `BLOCK` verdicts.
- Has fixture tests under `tests/skills/migration-safety/` covering at least: lock-blocking migration, missing reverse migration, major dep bump with breaking-change scan.

## Triggers (final list; may grow)

- Literal: "migration", "schema change", "upgrade dep", "breaking change", "lockfile bump"
- Project-state probe: `git diff` includes paths matching `migrations/`, `package.json`, `requirements.txt`, `Cargo.lock`, `Gemfile.lock`, `go.sum`, `**/*.migration.sql`
- Phase ordering: required before Phase 7.75 Pre-deploy if any of the above are present in the diff

---

*Full content scheduled for a follow-up session. See `docs/superpowers/plans/2026-05-20-production-hardening.md` for the implementation queue. Until then, the redirect above keeps users unblocked.*
