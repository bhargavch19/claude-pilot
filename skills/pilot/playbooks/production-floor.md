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

## Activation (the parts that need an explicit human go)

These are **outward / behavior-changing** and are NOT auto-applied:

- **Flip `verify-gate.sh` from warn → block** so a "done" claim on a source-touching
  turn is refused until verification ran. High value, but a buggy block can trap you —
  enable deliberately.
- **`hookify` (official, `anthropics/claude-code`)** — author markdown-defined blocking
  hooks wrapping the CLIs above, instead of hand-writing hook JSON.
- **`semgrep` PreToolUse** (vendor `semgrep/guardian`) — only third-party blocking hook
  worth considering; Semgrep is the vendor. Vet before trusting it with edit-time exec.
- **`langfuse-observability`** (optional) — telemetry/tracing pipeline for the
  Post-deploy phase.

## What pilot already has (don't duplicate)

`verify`, `security-review`, `migration-safety`, `pre-deploy-checklist`,
`post-deploy-monitor`, `gsd-secure-phase`, `gsd-eval-review`, `gsd-validate-phase`,
`git-guardrails`. The floor's job is to make these **blocking** where today they advise.
