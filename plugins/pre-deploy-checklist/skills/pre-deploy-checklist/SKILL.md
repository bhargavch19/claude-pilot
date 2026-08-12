---
name: pre-deploy-checklist
description: Run a structured pre-deploy gate before shipping to production. Covers secret scan, env-var completeness, feature-flag default state, smoke test plan, and identified rollback path. Use immediately before any production deploy. Triggers on "deploy", "release", "ship to prod", "production", "go live", "tagging a release".
---

# Pre-deploy Checklist

## Status: scaffold (full implementation queued)

This skill is registered in pilot's routing table (Phase 7.75 Pre-deploy) but its full content is queued. Until then, redirect to working fallbacks per the use case.

### Redirect for now

- **Code-review readiness** → use `superpowers:requesting-code-review` to confirm the diff is review-ready, then check the merge protection rules manually.
- **Security pass** → use `security-review` for OWASP-style checks (this also runs in Phase 6.5 Security).
- **Smoke test plan** → use `verify` to drive the app through the new feature manually before deploying.
- **Secret scan** → run `gitleaks detect` or equivalent locally; pilot doesn't yet wrap it.

State to the user: "pre-deploy-checklist is scaffold-only; using `<fallback>` for this turn."

## When the full skill is implemented, it will cover

### 1. Secret scan

- Run `gitleaks detect` (or equivalent) on the diff
- Block on any high-severity finding
- For low-severity findings, request explicit acknowledgment

### 2. Env-var completeness

- Diff `.env.example` against required env vars referenced in code (`process.env.X`, `os.environ['X']`, etc.)
- Block if any required env var is undocumented
- Surface to the user before deploy: "the following env vars must be set in production: …"

### 3. Feature-flag default state

- Find every newly-added feature flag in the diff
- Confirm its production default (off for new behavior, on for existing)
- Surface flags that default-on for new behavior — these are usually wrong

### 4. Smoke test plan

- For the change set, propose a 3-5 step manual smoke test
- Each step has a "what to click" and a "what to observe"
- The user runs the smoke test and confirms before proceeding

### 5. Rollback identification

- Confirm the deploy mechanism has a documented rollback procedure for this change
- For DB migrations, confirm Migration phase (7.5) produced a `MIGRATION-SAFETY.md` with rollback steps
- For new infrastructure, confirm Terraform / IaC has a `destroy` path

## Output artifact

Full skill writes `PRE-DEPLOY.md` to the phase artifact directory. Each of the 5 sections has a `PASS` / `CAUTION` / `BLOCK` verdict. Any `BLOCK` halts the Ship phase.

## Acceptance criteria for the full skill

- Wraps `gitleaks` (or `trufflehog` as alternative) for secret scanning.
- Diffs the project's env-var documentation against code references.
- Reads feature flag declarations from at least: GrowthBook, LaunchDarkly, ConfigCat, custom env-var flags.
- Has fixture tests covering: missing env var, default-on feature flag, missing rollback documentation.

## Triggers (final list)

- Literal: "deploy", "release", "ship to prod", "production", "go live", "tag release"
- Phase ordering: fires automatically before Phase 8 Ship when the target branch is `main` / `production` / `release/*`

---

*Full content scheduled for a follow-up session.*
