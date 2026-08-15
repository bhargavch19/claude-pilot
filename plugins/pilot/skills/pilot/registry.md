# Pilot Registry

> The single source of truth pilot consults to route user intent → underlying skill.
> To add a new skill: append a row. No code change required.

## One spine (decision)

Pilot runs **one** structured-workflow spine: **GSD**. It is the default for any
multi-session / multi-file work because it carries the production-quality surface
pilot depends on — dedicated `gsd-secure-phase`, `gsd-eval-review`,
`gsd-validate-phase`, `gsd-code-review`, `gsd-ui-review`.

**PAUL is kept as an opt-in lean alternative**, not a co-equal spine. Use it only
when the user explicitly enters it (a literal `/paul:*` command or an existing
`.paul/` directory). Do not promote PAUL over GSD on inferred intent. Two of PAUL's
ideas are better than GSD's defaults and are imported as pilot invariants for
*every* spine — see **Production-quality floor** below:

1. **Acceptance-criteria-first** — define AC before tasks; every task links to one.
2. **Mandatory loop-closure** — no Build cycle ends without plan-vs-actual reconciliation.

> Superpowers remains the single-session lightweight path. Running GSD **and** PAUL
> as parallel primaries is explicitly rejected (routing ambiguity + hook bloat).

## Literal-name routing wins (highest priority)

If the user's prompt literally contains a skill id from the **Primary** or **Fallbacks** column below — or one of the bundled MCP names (`context7`, `playwright`, `github`) — pilot routes to it **immediately**, without keyword scoring. Multi-mention prompts produce a sequenced chain of phases.

Any literal `/paul:*` slash command (`/paul:plan`, `/paul:apply`, `/paul:unify`, …) is honored directly — the user is explicitly opting into the lean PAUL loop for this work. Once inside it, stay in PAUL's commands rather than re-routing to GSD/superpowers mid-loop. This is the *only* way PAUL becomes active; pilot never infers it.

See `SKILL.md` → "Literal-name shortcut" for the exact rule (scanning conventions, namespace handling, edge cases). The phase table below applies only when no literal hit is found.

## Phase table

| Phase | Triggers | Primary skill | Fallbacks | Resolution rule |
|---|---|---|---|---|
| 0. Recall | session start; "where were we"; "did we already" | `claude-mem:mem-search` | `gsd-resume-work`, `claude-mem:learn-codebase`, `paul:resume` (opt-in) | always run on SessionStart; if mem-search returns nothing AND repo is unfamiliar (no prior `claude-mem` index), use `learn-codebase` to prime; `gsd-resume-work` is the structured-resume default; `paul:resume` only if `.paul/` exists |
| 0.5 Triage | "triage"; "what to work on"; "incoming bugs"; "review the inbox"; "issue queue" | `triage` | `gsd-inbox` | fires before Frame when work source is an issue tracker / PR queue |
| 0.75 Bootstrap | "new project"; "init"; "fresh repo"; no CLAUDE.md present | `init` → `gsd-new-project` | `claude-mem:learn-codebase`, `paul:init` (opt-in) | auto-fire when `[ ! -f CLAUDE.md ]` AND no `.planning/` AND no prior pilot routing in this repo. **Every new project gets the Production-quality floor scaffolded** (see playbook). `gsd-new-project` is the structured bootstrap; `paul:init` only if the user explicitly wants the lean loop |
| 0.8 Orchestrate (parallel) | "in parallel"; "fan out"; "do these N things at once"; "audit/migrate every X"; 2+ independent subtasks with no shared state | `superpowers:dispatching-parallel-agents` | `superpowers:subagent-driven-development` | only when subtasks are genuinely independent (no sequential dependency / shared mutable state). Decompose → dispatch one subagent per task → join results. Sequential or interdependent work stays in the normal phase loop. See `playbooks/orchestration.md` |
| 0.9 Map (knowledge graph) | "graphify"; "knowledge graph"; "map this folder"; "what's in here"; "connect these notes/papers"; "understand the structure"; a `/raw`-style drop folder | `graphify` | `gsd-map-codebase` (GSD-spine codebase docs only) | graphify is the **single** mapper for pilot; literal `/graphify` always routes here. `gsd-map-codebase` is used only inside an active GSD phase that needs `.planning/codebase/` docs. `claude-mem:learn-codebase`/`pathfinder` and `gsd-graphify` are not part of the primary map path |
| 1. Frame (non-code) | "idea"; "what if"; "explore"; "thinking about"; "is this worth building" | `grill-me` | `office-hours:office-hours` (product interrogation — is the problem real, who has it, vendored from gstack), `gsd-explore` | non-code keywords; use `office-hours:office-hours` when the question is product viability rather than design |
| 1. Frame (code) | "build"; "add"; "feature"; "change <thing>" | `grill-with-docs` → `to-prd` | `superpowers:brainstorming` → `gsd-spec-phase` | if `.planning/` exists, use the GSD path (`gsd-spec-phase`); `.paul/` → `paul:discuss`/`paul:discover` only when already in the PAUL loop. **Run the clarify scan first** (`playbooks/requirements.md` §1) — material ambiguities resolved or stated as assumptions before Plan |
| 2. Plan | post-frame; "plan this"; >1 file or >20 LOC | `superpowers:writing-plans` | `gsd-plan-phase`, `to-issues`, `ceo-review:ceo-review` (strategic challenge of a drafted plan — scope up/down/kill, vendored from gstack) | multi-session → GSD (`gsd-plan-phase`); single-session → superpowers; tracer slicing → to-issues. **Plan MUST define acceptance criteria before Build (AC-first invariant)** — stable IDs (`AC-001`) as `- [ ]` checkboxes in `.pilot/acceptance.md`, each linked to a task + test; run the analyze coverage check before the first Build edit (`playbooks/requirements.md` §2–3). verify-gate blocks any "done" claim while boxes remain unchecked. `paul:plan` only inside the PAUL loop |
| 3. Build (logic) | post-plan; code work begins; "implement" | `tdd` | `superpowers:test-driven-development`, `gsd-execute-phase` | always TDD unless `--skip-tdd`; multi-session execution → `gsd-execute-phase`. **Every Build task references an AC; the cycle is not done until loop-closure runs (Phase 9).** `paul:apply` only inside the PAUL loop |
| 3. Build (UI) | "UI"; "design"; "component"; "screen"; "page" | `ui-ux-pro-max` | `frontend-design:frontend-design`, `expo` (RN/Expo projects), `gsd-sketch`, `gsd-ui-phase` | UI-specific keywords. `ui-ux-pro-max` ships design intelligence (67 styles, 161 palettes, font pairings, a11y); falls back to `frontend-design` when not installed; on an Expo/React Native repo (app.json + expo dep), bring in the `expo` plugin's framework skills |
| 4. Debug | "bug"; "broken"; "throws"; "fails"; "regression" | `diagnose` | `superpowers:systematic-debugging`, `gsd-debug` | hypothesis-first non-skippable |
| 4.5 Performance | "slow"; "latency"; "perf"; "profile"; "benchmark"; "bottleneck"; "regression"; "p99" | `diagnose` | `superpowers:systematic-debugging` | reproduce-then-measure non-skippable; same primary as Debug but explicit phase keeps perf invariants visible |
| 5. Verify | claim of "done"; before commit/PR; "actually test it"; "confirm it works" | `verify` | `playwright` (UI cases), `superpowers:verification-before-completion`, `gsd-verify-work`, `gsd-validate-phase` | run the app + observe behavior; gate enforced via `verify-gate.sh` hook regardless of primary — requires a real captured test run AND a fully checked `.pilot/acceptance.md` (when the ledger exists). **The Production-quality floor (tests/types/lint/SAST/secrets) is blocking here, not advisory** (see playbook); `paul:verify` only inside the PAUL loop |
| 6. Review | pre-merge; "review this" | `superpowers:requesting-code-review` | `code-review` (official/built-in), `pr-review-toolkit` (PR-native flows), `gsd-code-review`, `simplify` | mandatory before Ship; prefer the official `code-review` when installed — maintained review prompts beat home-grown ones; `pr-review-toolkit` when the unit of review is a GitHub PR (pairs with the `github` MCP) |
| 6.5 Security | "security review"; "audit"; "OWASP"; "vulnerability"; "sanitize"; "injection"; diff touches auth/crypto/network paths | `security-review` | `semgrep` (plugin — maintained SAST rules), `gsd-secure-phase` | always before Ship if any sensitive-path change; backed by SAST + secret-scan gates from the floor — the `semgrep` plugin is what makes the floor's SAST row live rather than scaffolded |
| 6.75 Documentation | "document"; "write docs"; "update README"; "API docs"; "docstrings"; "doc this"; "explain in the docs" | `gsd-docs-update` | `init` (CLAUDE.md), `to-prd`, `claude-mem:timeline-report` | generate/update project docs verified against the codebase; `gsd-docs-update` checks claims vs code; `init` for an initial CLAUDE.md, `to-prd` to capture product intent. Changelog/release notes belong to Release (8.25), not here |
| 7. Refactor | "messy"; "hard to change"; "clean up" | `improve-codebase-architecture` | `claude-mem:pathfinder`, `gsd-map-codebase` | single-file deepening → improve-codebase-architecture; cross-system unification → pathfinder; scope to current task only |
| 7.5 Migration | "migration"; "schema change"; "upgrade dep"; "breaking change"; "lockfile bump" | `migration-safety:migration-safety` | `to-issues`, `diagnose` | required before Pre-deploy if `migrations/` or lockfile changed; produces `MIGRATION-SAFETY.md`; backed by the SCA/dependency-audit gate |
| 7.6 Dependencies | "update deps"; "upgrade dependencies"; "outdated packages"; "dependency audit"; "CVE"; "npm audit"; "supply chain" | `migration-safety:migration-safety` | `context7`, `diagnose` | proactive dependency currency + supply-chain safety — distinct from schema Migration (7.5); backed by the SCA/dependency-audit gate in the Production-quality floor; use `context7` for target-version docs before a major bump |
| 7.75 Pre-deploy | "deploy"; "release"; "ship to prod"; "production"; "go live"; immediately before Ship on a release branch | `pre-deploy-checklist:pre-deploy-checklist` | `superpowers:requesting-code-review` | fires automatically before Ship for production-targeted branches; produces `PRE-DEPLOY.md` |
| 8. Ship | "merge"; "PR"; "ship it" | `gsd-ship` | `superpowers:finishing-a-development-branch`, `pr-review-toolkit` | only after Verify + Review + green floor; `pr-review-toolkit` for PR-workflow mechanics alongside the `github` MCP |
| 8.25 Release | "release"; "version bump"; "cut a release"; "changelog"; "release notes"; "tag"; "semver" | `claude-mem:version-bump` | `gsd-complete-milestone`, `gsd-ship` | version + changelog + tag artifacts — distinct from Ship (PR/merge, 8) and Deploy; run after Verify + Review pass. `version-bump` handles semver bump, changelog, and git tag for plugins/packages |
| 8.5 Post-deploy | "monitor"; "after deploy"; "did the deploy work"; "rollback"; "post-deploy"; "did anything break" | `post-deploy-monitor:post-deploy-monitor` | `diagnose` | fires after Ship completes; checks error rate + latency + logs; produces `POST-DEPLOY.md` |
| 9. Capture / Close the loop | post-ship; end of phase; "close the loop"; "reconcile"; "unify" | `graphify` (delta: `git diff --name-only <base>...HEAD`) | `gsd-extract-learnings`, `paul:unify` (PAUL loop) | **Graphify the delta is the conductor's action here** — map the cycle's changed files so new code lands in the knowledge graph for future debugging (Phase 0.9 maps inputs; this maps outputs). claude-mem's auto-hook captures observations on its own (not skill-invokable — never wait on it). **Mandatory loop-closure invariant:** no Build cycle is "done" until plan-vs-actual is reconciled — GSD via `gsd-verify`/`gsd-extract-learnings`, PAUL via `paul:unify`. Never leave an execute step un-reconciled |
| Meta. Autopilot | "autopilot"; "take this end to end"; "handle this requirement fully"; "don't stop until it ships"; requirement + explicit hands-off intent | `autopilot` (pilot conductor per `autopilot.md` — not a separate skill) | `gsd-autonomous` (GSD execute stretch only) | Requirement in → shipped change out with exactly two checkpoints: plan approval and ship approval. Bounded verify→`diagnose`→fix loop (default 3 rounds, then `halted` + report). Durable state in `.pilot/cycle.json`; enforced by `hooks/autopilot-gate.sh` (G16). A requirement WITHOUT hands-off intent is normal phase routing — never infer autopilot |
| Meta. Skill authoring | "create skill"; "new skill"; "write a skill"; "edit skill" | `skill-creator:skill-creator` | `write-a-skill` (superpowers), `superpowers:writing-skills` | meta-tooling — runs outside phase loop |
| Meta. Skill discovery | "how do I X"; "is there a skill for"; "find a skill"; "what skill does Y"; "discover skills"; "/coding-hub:search" | `find-skills` | pilot self-enumerates `registry.md` Primary column | meta-tooling — runs outside phase loop; complements the literal-name shortcut for users who don't know skill names |
| Docs lookup | "use latest docs"; "how does X work in vY.Z"; "context7"; library name + version | `context7` MCP (`mcp__context7__resolve-library-id` + `query-docs`) | training-data fallback (acknowledge cutoff) | invoke any time the agent is about to use an unfamiliar API or the user names a library + version |
| UI verify | UI tasks reaching Verify phase; "test in browser"; "does it actually work"; "screenshot the change" | `playwright-cli` (Bash: `playwright-cli open/goto/snapshot/click/type/eval/screenshot`) | `playwright` MCP (`mcp__playwright__browser_*`), `run`, `superpowers:verification-before-completion` (test-runner only — no browser) | invoke proactively after Build (UI) completes, before claiming the change works. CLI first (token-efficient — no MCP schemas or verbose a11y trees in context; Microsoft's recommended fit for coding agents); fall back to the bundled `playwright` MCP when `playwright-cli` isn't installed or the flow needs persistent introspective browser state |
| GitHub ops | "PR"; "CI status"; "review state"; "merge readiness"; "post comment"; "list issues" | `github` MCP (hosted endpoint; discover exact `mcp__github__*` tool names in-session — they vary by server release) | `gh` CLI via Bash | when Review/Ship phase needs real GitHub data instead of inferring from local git; requires `GITHUB_TOKEN` |

## Production-quality floor (enforcement invariants)

> This is the part that actually makes output production-grade. Planning skills clarify
> intent; only an enforced, non-bypassable floor guarantees the output. See
> `playbooks/production-floor.md` for the concrete gates, commands, and bootstrap
> scaffolding (CI workflow + pre-commit config templates).

The floor is the standing set of **blocking** checks every project carries:

| Gate | Tool (you control) | Where it blocks | Status |
|---|---|---|---|
| Tests + coverage threshold | project test runner + coverage | pre-commit (fast subset) + CI (full + threshold) | scaffolded; opt-in to activate |
| Type check | `tsc --noEmit` / `mypy` / etc. | pre-commit + CI | scaffolded |
| Lint / format | eslint+prettier / ruff / etc. | pre-commit + CI | scaffolded |
| SAST | `semgrep` (CLI you run; not a third-party hook plugin) | CI; optional PreToolUse | scaffolded |
| Secret scan | `gitleaks` | pre-commit + CI | scaffolded |
| Dependency / SCA audit | `osv-scanner` / `npm audit` / `pip-audit` | CI | scaffolded |
| "Done" claim gate | `verify-gate.sh` | Stop hook | live (currently warns; flip to block to enforce) |

Invariants applied to every spine:
- **AC-first** — Plan defines acceptance criteria before Build; tasks link to them.
- **Loop-closure** — Build cycles end with plan-vs-actual reconciliation (Phase 9).
- **Prefer CLIs you control over third-party blocking hooks** — a third-party
  `PreToolUse` hook executes on every edit; that's a supply-chain surface. Wrap
  trusted CLIs (semgrep, gitleaks, osv-scanner) via `hookify`/CI instead.

## Always-on layer

- `context-mode` — output discipline (large tool output → sandbox). No opt-in needed.
- `caveman` — communication style (terse, no filler). Active when `.pilot.json {"profile":{"style":"caveman"}}` or the user's CLAUDE.md asks for it; `"standard"` disables it per-repo (a teammate shouldn't inherit another dev's register).
- **Production-quality floor** — the blocking gates above run underneath every Build→Ship path once activated. The floor is what enforces production quality; the phase table only routes intent toward it.
- `context7` MCP — bundled with pilot. Use proactively whenever a Plan/Build/Debug phase touches a library the agent might be hazy on. Free tier works without an API key; set `CONTEXT7_API_KEY` for higher rate limits.
- `typescript-lsp` — symbol-level code intelligence on TS/JS repos (go-to-definition, find-references, safe renames). Use it in Build/Debug/Refactor instead of grep when the question is about a *symbol* ("who calls this", "rename safely", "where is this defined"); graphify stays the tool for *architecture* questions. Other stacks: install the matching official LSP plugin (`pyright-lsp`, `gopls-lsp`, `rust-analyzer-lsp`, ...).
- `playwright-cli` — preferred UI-verify vehicle when installed (`command -v playwright-cli`). Drive the browser through terse Bash commands (`open`, `goto`, `snapshot`, `click <ref>`, `eval`, `screenshot`) instead of MCP tool calls — same evidence, far fewer tokens. Install: `npm i -g @playwright/cli` + `playwright-cli install --skills`.
- `playwright` MCP — bundled with pilot as the fallback browser driver. Use in the Verify phase after any UI change when `playwright-cli` is unavailable, or when the flow needs persistent browser state with rich introspection. Drive the browser, snapshot, click through the new flow, then claim done with the evidence in the transcript.
- `github` MCP — pilot connects to GitHub's official hosted endpoint (`api.githubcopilot.com/mcp`). Use in Review and Ship phases whenever you need real GitHub state (PR status, review approvals, CI checks, issue threads). Requires `GITHUB_TOKEN` in the shell env (reads too); no token → fall back to `gh` CLI.

## Resolution priority (when multiple options apply)

1. If `.planning/` exists in cwd → GSD is active; use the GSD variant for the phase (the spine).
2. Else if `.paul/` exists in cwd → the user opted into the lean PAUL loop; use `paul:*` and honor loop integrity (a `paul:apply` must be closed by `paul:unify`).
3. Else if work is multi-session or multi-file → default to **GSD** (the spine). Use superpowers only for genuinely single-session work.
4. Else → superpowers tracer-bullet path (fastest) for small single-session tasks.
5. Always: `context-mode` + the **Production-quality floor** run underneath.

> `.planning/` (GSD) and `.paul/` (PAUL) are mutually exclusive — a repo runs one
> structured workflow at a time. If both exist, ask the user which is authoritative.
> Default new structured projects to GSD; reach for PAUL only on explicit request.

## Extending

To add a new skill:
1. Append a row to the phase table above with: phase, triggers, primary, fallbacks, resolution rule.
2. If the skill needs a dedicated playbook, create `playbooks/<topic>.md` and reference it.
3. Reload: `claude --restart-skills` or new session.
