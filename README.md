# pilot

Unified AI coding conductor for Claude Code. Auto-routes the user's intent
to the right underlying skill (grill → plan → TDD → debug → verify → ship),
enforces a configurable set of CLAUDE.md quality gates via shell hooks, and
stays extensible through a one-line registry edit.

- **Repository structure:** Claude Code single-plugin marketplace
  (`.claude-plugin/marketplace.json` + `.claude-plugin/plugin.json` at root).
- **Skill source:** `skills/pilot/` — `SKILL.md` (routing playbook) + `registry.md` (single-source-of-truth phase table) + `guardrails.md` (CLAUDE.md → hook mapping) + `playbooks/`.
- **Hooks:** `hooks/{plan-gate,pre-commit,safety-gate,pretooluse-heartbeat,verify-gate,autopilot-gate,capture-test-run,autoformat,sessionstart-banner,integrity-check,memory-surface,precompact-anchor,log-skill-invocation,route-advisor}.sh` — wired across PreToolUse, PostToolUse, Stop, SubagentStop, SessionStart, PreCompact, UserPromptSubmit.
- **MCPs (bundled):** `context7` (docs) · `playwright` (UI verify) · `github` (review / ship).
- **Bundled skills (this plugin's own):** `migration-safety`, `pre-deploy-checklist`, `post-deploy-monitor` (all under `skills/`). Currently scaffolds — see `docs/superpowers/plans/2026-05-20-production-hardening.md` for completion queue.
- **Production-quality floor:** `skills/pilot/playbooks/production-floor.md` + `templates/` (CI workflow + pre-commit config) + `apply-floor.sh` — the blocking gates (tests, types, lint, SAST, secret scan, dep audit) the Bootstrap phase wires into new projects.
- **Routing spine:** GSD is the default for multi-session/multi-file work; PAUL is opt-in (literal `/paul:*` or an existing `.paul/`); graphify is the sole codebase mapper. See `registry.md` → "One spine".
- **Slash commands:** `commands/pilot-{status,off,off-rails,back-on,bypass,doctor,trace}.md`.

See [`CHANGELOG.md`](./CHANGELOG.md) for what shipped in each version and
[`prereqs.md`](./prereqs.md) for what plugins/skills pilot prefers to route
into.

## Quick install (marketplace path — recommended)

> **Before publishing:** replace `bhargavch19` below with your actual
> GitHub handle. Run `bash dev/finalize-readme.sh` to substitute it
> automatically (uses `gh api user` if you're authed, or pass it as an
> argument: `bash dev/finalize-readme.sh <handle>`). The repo must be
> pushed to a public (or accessible) GitHub URL — pilot is a
> single-plugin marketplace, so the repo IS the marketplace.

In Claude Code:

```
/plugin marketplace add bhargavch19/pilot
/plugin install pilot@pilot
```

Restart Claude Code. All five hook events (PreToolUse on Edit/Write/
MultiEdit/NotebookEdit + Bash, Stop, SubagentStop, SessionStart, PreCompact)
wire automatically via the plugin manifest. The slash commands become
available, the SessionStart banner shows the active version + a first-run
hint pointing at `/pilot-doctor`, and the bundled MCP servers start in the
background for on-demand tools.

**Bundled MCP servers** (all pinned, all start automatically):

| Server | Pinned version | First-run cost | Used in phases |
|---|---|---|---|
| `context7` | `@2.2.5` | ~3MB npx fetch | Docs lookup (any) |
| `playwright` | `@0.0.75` | ~3MB npx + ~300MB Chromium on first navigate | Verify (UI) |
| `github` | hosted (`api.githubcopilot.com/mcp`) | none — remote HTTP | Review · Ship |

**API keys + opt-outs** — export in your shell before launching Claude Code:

```bash
export CONTEXT7_API_KEY="…"      # optional — raises context7 rate limits
export GITHUB_TOKEN="…"          # required for the hosted github MCP (reads too)

# Per-server opt-outs (set to 1 to skip that MCP's routing):
export PILOT_DISABLE_CONTEXT7=1
export PILOT_DISABLE_PLAYWRIGHT=1
export PILOT_DISABLE_GITHUB=1
```

Run `/pilot-doctor` after install to confirm all three MCP commands are
on PATH and to see which env vars are set.

Verify with `/pilot-doctor` in any session.

## Dev install (one command — symlink + live edit)

For hacking on pilot without going through marketplace publishing:

```bash
git clone https://github.com/bhargavch19/pilot ~/Workspace/claude-skill
bash ~/Workspace/claude-skill/dev/symlink-pilot.sh    # does all 3 steps
# restart Claude Code, then run /pilot-doctor
```

`symlink-pilot.sh` chains three idempotent steps:

1. **Symlink** `skills/pilot` → `~/.claude/skills/pilot` (live edits show up immediately).
2. **Wire hooks** — `wire-hooks.sh` merges pilot's 6 hook entries into `~/.claude/settings.json` via `jq` (auto-backed up to `settings.json.bak.<ts>`).
3. **Register MCPs** — `wire-mcps.sh` reads `mcpServers` from `.claude-plugin/plugin.json` and registers `context7` / `playwright` / `github` via `claude mcp add` (skips entries that already exist).

Each step is also runnable atomically (`bash dev/wire-hooks.sh`, `bash dev/wire-mcps.sh`). Use `SKIP_WIRE=1 bash dev/symlink-pilot.sh` to refresh only the symlink without re-running the wiring.

To remove:

```bash
bash ~/Workspace/claude-skill/dev/unwire-hooks.sh      # idempotent
bash ~/Workspace/claude-skill/dev/unwire-mcps.sh       # idempotent
rm ~/.claude/skills/pilot                              # only if you symlinked
```

## What pilot does

1. **Literal-name shortcut.** If your prompt literally names a skill or MCP (`context7`, `playwright`, `tdd`, `frontend-design`, `improve-codebase-architecture`, etc.), pilot routes there immediately — skipping keyword-based phase detection. Multi-mention prompts produce a sequenced phase chain. See "How to invoke pilot" below.
2. **Phase routing.** When no literal name is present, pilot reads `skills/pilot/registry.md`, scans the user message for trigger keywords, inspects project state (`.planning/`, `git status`, `git log`), and invokes the right underlying skill via the Skill tool.
   - **Deterministic route advisor (`route-advisor.sh`, UserPromptSubmit).** Before the model sees the prompt, this hook computes — in code, from `registry.md` — the *unambiguous* part of the route and injects it: distinctive literal skill names (hyphen/colon/digit names, e.g. `tdd`, `improve-codebase-architecture`, `gsd-*`, `paul:*`) and project-state spine (`.planning/`→GSD, `.paul/`→PAUL). Common-English skill names (`review`, `run`, `verify`) and all fuzzy intent are deliberately left to the model — the hook only hard-routes what code can decide correctly, so routing is deterministic where it can be and model-judged where it must be.
3. **Quality gates.** `plan-gate`, `pre-commit`, and the **blocking** `verify-gate` enforce CLAUDE.md-aligned rules — see `skills/pilot/guardrails.md`. `verify-gate` no longer trusts transcript prose: a companion `capture-test-run` hook (PostToolUse/Bash) records the *actual* result of test-runner commands to a fact file, and the gate clears a "done" claim only when a real captured pass exists for this session — closing the hole where a model could write "tests passed" without running anything. Two more hooks add deterministic routing (`route-advisor`, UserPromptSubmit) and settings self-healing (`dedupe-settings-hooks`, SessionStart).
4. **Bundled MCPs.** `context7` (docs lookup), `playwright` (UI verify), and `github` (review / ship) start automatically and are surfaced to the Skill tool as `mcp__<name>__*` tools. For UI verify, pilot prefers **`playwright-cli`** (Microsoft's token-efficient CLI for coding agents — `npm i -g @playwright/cli`) when installed, falling back to the playwright MCP.
5. **Autopilot (v0.10).** Hand pilot one requirement and it conducts the entire loop hands-off — frame → phased plan → **stop for your plan approval** → build (TDD) → verify → bounded fix loop (3 rounds, then halt + report) → review → **stop for your ship approval** → ship → capture. Start with `/pilot-autopilot <requirement>`, the word `autopilot`, or a requirement plus "take this end to end". Durable state in `.pilot/cycle.json` survives session death (`continue` resumes); `hooks/autopilot-gate.sh` (G16, Stop hook) keeps the cycle advancing between checkpoints; abort anytime with `/pilot-autopilot off`. Each phase still routes to its registry skill and every gate still applies.
6. **Stay extensible.** Adding a new skill is a one-line append to `registry.md`. Adding a new guardrail is a hook script plus a test under `tests/hooks/`.

## How to invoke pilot

Three invocation tiers, in order of explicit-ness:

### Tier 1 — just describe the work

Pilot's `description` frontmatter contains trigger keywords that Claude Code auto-matches: **build, fix, ship, explore, messy, broken, review**. A normal work prompt is enough — pilot auto-engages on session start and infers the phase from your prompt + project state.

```
build a scientific-mode toggle for the calc app
```

### Tier 2 — name your tools explicitly (recommended)

If your prompt literally contains a skill id or MCP name, pilot pre-resolves every named token to a phase on parse — no keyword scoring, no ambiguity. This is the most reliable invocation pattern.

```
Build feature X.
Use context7 to confirm the library docs.
Plan via writing-plans, then TDD it.
Verify with playwright. Screenshot the result.
Finally run improve-codebase-architecture.
```

→ pilot resolves to:

| Prompt token | Routes to |
|---|---|
| `context7` | `context7` MCP |
| `writing-plans` | `superpowers:writing-plans` |
| `TDD` | `tdd` |
| `playwright` | `playwright` MCP |
| `improve-codebase-architecture` | that skill |

Five-phase chain, no clarifying questions.

**Match rules:**
- Multi-word skill names must appear as one hyphenated token (`improve-codebase-architecture`, not "improve codebase architecture").
- Namespace prefixes are optional — `frontend-design` resolves to `frontend-design:frontend-design`; `writing-plans` to `superpowers:writing-plans`.
- Case-insensitive (`TDD`, `tdd`, `Tdd` all match).
- Generic vocabulary doesn't count: "design the UI" does not match `frontend-design` because the literal hyphenated token is absent.

### Tier 3 — force-prefix with `pilot:`

When the work has no obvious trigger keywords but you still want pilot to engage:

```
pilot: think through whether to extract this into a separate package
```

The literal `pilot:` prefix overrides phase ambiguity and pushes pilot to route even on exploratory prompts.

## Production phases (v0.7+)

Beyond the core Frame → Plan → Build → Verify → Review → Ship → Capture cycle, pilot routes 7 production-oriented phases at decimal slots:

| Slot | Phase | Primary skill | Fires when |
|---|---|---|---|
| 0.5 | Triage | `triage` | "what to work on", incoming bugs, PR queue |
| 0.75 | Bootstrap | `init` | repo has no CLAUDE.md |
| 4.5 | Performance | `diagnose` | "slow", "latency", "profile", "regression" |
| 6.5 | Security | `security-review` | "audit", "OWASP", diff touches auth/crypto/network |
| 6.75 | Documentation | `gsd-docs-update` | "document", "update README", "API docs", "docstrings" |
| 7.5 | Migration | `migration-safety`* | diff touches `migrations/` or lockfile |
| 7.6 | Dependencies | `migration-safety`* | "update deps", "outdated packages", "CVE", "npm audit" |
| 7.75 | Pre-deploy | `pre-deploy-checklist`* | immediately before Ship on a release branch |
| 8.25 | Release | `claude-mem:version-bump` | "release", "version bump", "changelog", "tag" |
| 8.5 | Post-deploy | `post-deploy-monitor`* | after Ship completes |

`*` Scaffold — registers and redirects to a working fallback. Full content in queue (see `docs/superpowers/plans/2026-05-20-production-hardening.md`).

Each phase appears as a row in `skills/pilot/registry.md` with its triggers and fallbacks. Phase ordering is enforced by the **Resolution rule** column — e.g., `7.5 Migration` is required before `7.75 Pre-deploy` if migrations/lockfile changed.

## Bypass

| When you want to… | Use |
|---|---|
| Skip the next gate fire | `/pilot-off` |
| Skip only plan-gate | `/pilot-bypass --no-plan` |
| Turn pilot off for the session | `/pilot-off-rails` |
| Turn pilot back on | `/pilot-back-on` |
| Diagnose what's wired and what isn't | `/pilot-doctor` |
| Quick wired-hooks view | `/pilot-status` |
| Inspect current session's routing chain | `/pilot-trace` |

Bypass also works via free-text phrases in the user message (`pilot off`,
`pilot off rails`, `pilot --no-plan`) — handy when typing in a deep
sub-conversation.

## Known limitations

Honest list of edges that bite — surfaced via cross-setup audit, not theoretical.

| Area | Limitation | Workaround / status |
|---|---|---|
| **Platform** | All hooks are bash. Windows PowerShell users can't run them natively. | Use WSL or Git Bash; full PowerShell port queued. |
| **macOS cache** | Hooks write to `~/.cache/pilot/` (XDG convention), not `~/Library/Caches/` (macOS convention). | Set `XDG_CACHE_HOME=~/Library/Caches` in your shell if you want native macOS location. |
| **Web app** | Claude Code's web surface (claude.ai/code) doesn't fire local hooks. | Hooks only enforce in CLI/desktop sessions. Skill-level routing still works (model-driven). |
| **Pre-commit on amend** | The `pre-commit.sh` hook only inspects the current `-m`/`--message`. Interactive-rebase amends of mid-history commits bypass the conventional-commit check. | Run `bash tests/run.sh` locally before pushing if your branch contains amended-via-rebase commits. |
| **Plan-gate freshness** | Plan-existence check is permissive: ANY plan file matching `docs/superpowers/plans/*.md` OR `.planning/*/PLAN.md` satisfies the gate, even if the plan is 6+ months old. | Treat as a soft guard, not a contract. Use `/pilot-bypass --no-plan` if a stale plan is blocking a small unrelated edit. |
| **PreCompact token cost** | Re-anchor injection consumes ~10 lines post-compact. Linear in the number of phases in the registry. | Mitigated in v0.7.0 — registry list collapsed to a pointer ("21 phases, see registry.md"). Token cost ~constant as registry grows. |
| **Concurrent sessions** | Pre-v0.7.0, `routing.log` interleaved entries from concurrent Claude Code sessions. | v0.7.0 added a `session=<8char>` field per entry; `/pilot-trace` scopes to the current session_id. Older entries fall back to last `skill=pilot` boundary. |
| **Built-in skill detection** | `/pilot-doctor` can't file-probe Claude Code built-in skills (`init`, `verify`, `run`, `simplify`, `review`, `security-review`). They're loaded by the Claude Code binary, not stored on disk. | Doctor marks them as `• built-in — file probe N/A` instead of `✗`. |
| **Wire-hooks dedup** | `wire-hooks.sh` dedups pilot entries by hook-script basename, not by absolute path. Two pilot installs in different repos would collide. | Don't run two pilot installs concurrently. Use `bash dev/unwire-hooks.sh` before switching install paths. |

Each limitation surfaces in `/pilot-doctor` when it matters.

## Configuration

Per-repo config for `verify-gate.sh` via `.pilot.json` at the repo root
(resolved from cwd or the git root, so it works from any subdirectory):

```json
{
  "test_patterns": ["rake test", "my-custom-runner"],
  "verify_gate": "run",
  "test_command": "bash tests/run.sh",
  "test_timeout": 120
}
```

`test_patterns` are regex strings, unioned with pilot's built-in runner list
(pytest, bun test, vitest, nx test, make test, ...) when `capture-test-run.sh`
decides whether a Bash command is a test run. `verify_gate` controls
enforcement: by default the gate **blocks** a "done"/"ready" claim on a turn
that changed source unless a real test run was captured this session. Modes:

- `"warn"` — downgrade to a non-blocking warning for that repo.
- `"run"` — the gate executes `test_command` itself (with `test_timeout`
  seconds, default 120) and uses the **real exit code** — un-fakeable. It runs
  lazily (only when a "done" claim would otherwise block) and records a passing
  run as a capture so it runs at most once per session. Requires `test_command`.

The gate also honors the session bypass markers (`/pilot-off`,
`/pilot-off-rails` — which also skip run mode) and auto-releases after two
consecutive blocks so it can never trap a session.

Autopilot config lives under an `"autopilot"` key in the same file:

```json
{
  "autopilot": {
    "gate": "warn",
    "max_fix_rounds": 3,
    "checkpoints": ["plan", "ship"]
  }
}
```

- `gate` — `"warn"` downgrades the autopilot-gate to advisory; `"off"` disables
  it (the driver still works, it just can't force continuation).
- `max_fix_rounds` — verify-failure fix attempts before the cycle halts with a
  report (default 3).
- `checkpoints` — which approval pauses the cycle takes (default both `plan`
  and `ship`).

The autopilot-gate honors the same bypass markers and anti-traps after three
consecutive blocks on an unchanged cycle state.

## Team mode

Pilot started as a single-developer system; these pieces make it shareable:

- **Branch-scoped autopilot cycles** — cycle state lives at
  `.pilot/cycles/<branch-slug>.json`, so parallel developers on one repo never
  clobber each other (legacy `.pilot/cycle.json` still honored).
- **Profiles** — `.pilot.json {"profile": {"style": "caveman"|"standard",
  "strictness": "solo"|"team"}}` sets the communication register and scope
  discipline per repo instead of inheriting one developer's CLAUDE.md taste.
- **Shared outcomes** — `.pilot.json {"team": {"shared_outcomes": true}}` makes
  verify-gate append every pass/blocked outcome (with user) to the repo-scoped
  `.pilot/outcomes.jsonl`; `dev/outcome-report.sh [--days N]` turns it into a
  first-pass-verified rate with per-user breakdown.
- **Published cycle state** — `.pilot.json {"board": {"publish_cycles": true}}`
  makes the autopilot conductor stage the branch-scoped cycle file
  (`.pilot/cycles/<branch-slug>.json`) with the change it describes, so it rides
  the Build/Ship commits onto the story branch and a story board built from any
  clone reads the same cycle state. Off by default for the same reason as shared
  outcomes: committing an agent's working state is a per-team decision. With it
  off, a board sees cycle state only in the developer's own working copy.
- **Pinned bootstrap** — `dev/bootstrap-team.sh` installs the recommended
  skill constellation at the exact SHAs/versions in `dev/skills-lock.json`
  (`--check` for drift reporting). No self-updaters, no `curl | bash`.
- **Measurement** — `docs/ab-method.md` documents the pilot-on/off A/B
  protocol so adoption is argued from numbers, not vibes.
- **Witnessed approvals** — autopilot checkpoint approvals are machine-checked:
  `hooks/approval-capture.sh` (UserPromptSubmit) records the user's actual
  approving prompt (or `/pilot-approve`) as a witness marker; the Stop gate
  flags any checkpoint crossed without one as self-approval. The model cannot
  synthesize a UserPromptSubmit event, so a witness proves a human said yes.
- **Marketplace drift detection** — `dev/skills-lock.json` pins marketplace
  plugins by version/SHA; `bootstrap-team.sh --check` compares against Claude
  Code's `installed_plugins.json` and reports drift (alignment stays a human
  action — the marketplace owns installs).
- **Onboarding** — `docs/team-onboarding.md` is the 10-minute mental model
  for a new teammate.

## Tests

```bash
bash tests/run.sh    # unit-style fixture tests for every hook
bash dev/dry-run.sh  # end-to-end simulation with realistic Claude Code JSON
```

Plain bash + jq; no extra deps. CI runs both on ubuntu-latest and
macos-latest plus shellcheck on `hooks/` and `dev/`.

## Project context

- Design: `docs/superpowers/specs/2026-05-04-pilot-design.md`
- Plan: `docs/superpowers/plans/2026-05-04-pilot.md`
