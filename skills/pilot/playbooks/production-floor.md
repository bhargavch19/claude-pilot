# Playbook: Production-quality floor

> The enforcement layer that turns "an agentic OS that plans well" into "an agentic OS
> that ships production-grade code." Referenced by registry → **Production-quality floor**
> and the **0.75 Bootstrap** phase.

## Principle

Planning skills clarify *intent*. They do not guarantee *output*. Output quality is
guaranteed only by **blocking, non-bypassable checks**. Pilot's floor is a small set of
gates wired at two layers:

- **pre-commit** — fast checks on changed files; blocks the commit locally.
- **CI** — full suite + thresholds; blocks the merge.

Prefer **CLIs you control** (semgrep, gitleaks, osv-scanner) wrapped in your own
hooks/CI over importing third-party blocking-hook plugins. A third-party `PreToolUse`
hook runs on every edit in every repo — that's a supply-chain surface you don't need.

## The gates

| Gate | JS/TS | Python | Blocks at |
|---|---|---|---|
| Tests | `vitest` / `jest` | `pytest` | pre-commit (subset) + CI (full) |
| Coverage threshold | `--coverage` + `coverageThreshold` | `pytest --cov --cov-fail-under=N` | CI |
| Type check | `tsc --noEmit` | `mypy` / `pyright` | pre-commit + CI |
| Lint / format | `eslint` + `prettier --check` | `ruff check` + `ruff format --check` | pre-commit + CI |
| SAST | `semgrep --config auto` | same | CI (optional PreToolUse) |
| Secret scan | `gitleaks protect --staged` | same | pre-commit + CI |
| Dependency / SCA | `npm audit --audit-level=high` / `osv-scanner` | `pip-audit` / `osv-scanner` | CI |

Tune thresholds per project; start strict on new projects (coverage ≥ 70%, fail on
high-severity SCA, zero secrets, zero semgrep ERROR).

## Bootstrap checklist (new project → floor pre-wired)

Run during **Phase 0.75 Bootstrap**, after `gsd-new-project` / `init`:

1. Drop `templates/ci-quality-floor.yml` → `.github/workflows/quality-floor.yml`.
2. Drop `templates/pre-commit-config.yaml` → `.pre-commit-config.yaml`; run
   `pre-commit install` (and `pre-commit install --hook-type pre-push` if desired).
3. Ensure the project's `package.json`/`pyproject.toml` exposes the script names the
   templates call (`test`, `typecheck`, `lint`); add them if missing.
4. Install CLIs the project lacks: `gitleaks`, `semgrep`, `osv-scanner` (document in
   `CONTRIBUTING.md`; CI installs them itself).
5. Record the activated thresholds in `CLAUDE.md` so the floor is discoverable.

Idempotent: re-running must not duplicate files or workflow jobs.

## Applying the floor

Run `/pilot-floor` (or `skills/pilot/playbooks/apply-floor.sh [target-dir]`) to drop the
CI workflow + pre-commit config idempotently. It never overwrites an existing file and
prints the remaining human-confirmed steps. Tune the templates to your stack.

## Already activated in pilot itself (local blocking gates)

These ship enabled — no manual flip needed:

- **`verify-gate.sh` blocks by default** and is **capture-based**: a "done"/"ready"
  claim on a source-touching turn is refused unless a *real* test run was captured this
  session (`capture-test-run.sh`), not just claimed in prose. Auto-releases after 2
  blocks so it can't trap you; downgrade per-repo with `.pilot.json {"verify_gate":"warn"}`
  or have the gate run the suite itself with `{"verify_gate":"run"}`.
- **`safety-gate.sh` (G15)** fail-closed blocks destructive commands (`rm -rf` on
  home/root/system, force push / `reset --hard` / `clean -f` / `branch -D`, secret
  reads/exfil) — folds in the `git-guardrails` posture.

## Activation that still needs an explicit human go

These are **outward / behavior-changing** and are NOT auto-applied:

- **`hookify` (official, `anthropics/claude-code`)** — author markdown-defined blocking
  hooks wrapping the CLIs above, instead of hand-writing hook JSON.
- **`semgrep` PreToolUse** (vendor `semgrep/guardian`) — only third-party blocking hook
  worth considering; Semgrep is the vendor. Vet before trusting it with edit-time exec.
- **`langfuse-observability`** (optional) — telemetry/tracing pipeline for the
  Post-deploy phase.

## What pilot already has (don't duplicate)

`verify`, `security-review`, `migration-safety`, `pre-deploy-checklist`,
`post-deploy-monitor`, `gsd-secure-phase`, `gsd-eval-review`, `gsd-validate-phase`,
`git-guardrails`, plus the local `verify-gate`/`safety-gate` hooks above. The floor's job
is to make these **blocking** where today they advise.
