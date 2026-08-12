# Changelog

All notable changes to the `pilot` plugin are documented here. Format roughly
follows [Keep a Changelog](https://keepachangelog.com/); versions follow
[Semantic Versioning](https://semver.org/) once 1.0 ships.

## [Unreleased]

## [0.11.0] - 2026-08-12

### Changed
- **BREAKING: multi-plugin marketplace restructure.** The repo (renamed
  `bhargavch19/claude-pilot`) now publishes six independently installable
  plugins under `plugins/`: `pilot` (flagship — hooks + MCPs + routing skill,
  moved to `plugins/pilot/` with its `hooks/`, `commands/`, `dev/`, and
  `templates/` intact) plus standalone `migration-safety`,
  `pre-deploy-checklist`, `post-deploy-monitor`, `ceo-review`, and
  `office-hours` (one skill each, no hooks, no MCP servers). Install strings
  are `/plugin install <name>@pilot` after
  `/plugin marketplace add bhargavch19/claude-pilot`.
- Registry routes to the bundled skills by plugin-qualified name
  (`migration-safety:migration-safety`, …) — their name when installed from
  the marketplace.
- `integrity-check.sh` trusts pilot's own hooks by the repo-name-agnostic
  `*/plugins/pilot/hooks/*` path.
- CI validates every `plugins/*/.claude-plugin/plugin.json` and requires
  hooks/mcpServers only for pilot; `tests/run.sh` hard-fails when a suite
  directory contains no tests.

### Added
- Per-plugin READMEs, root plugin catalog, and `CONTRIBUTING.md`.
- **Marketplace picks integrated (research-driven).** Four official plugins
  wired as registry fallbacks/always-on and pinned in `skills-lock.json`:
  `typescript-lsp` (symbol-level intelligence — always-on note for
  Build/Debug/Refactor; grep for text, LSP for symbols, graphify for
  architecture), `semgrep` (activates the floor's SAST row; 6.5 Security
  fallback), `expo` (RN/Expo Build fallback), `pr-review-toolkit`
  (Review/Ship fallback beside the github MCP). Deliberately skipped:
  `feature-dev` (competing spine), SaaS reviewers, `ralph-loop` — rationale
  in prereqs/registry.

## [0.10.0] - 2026-07-20

### Added
- **Autopilot mode — requirement in, shipped change out.** One requirement →
  pilot conducts the entire loop hands-off (frame → phased plan → build/TDD →
  verify → bounded fix loop → review → ship → capture), pausing only at two
  checkpoints: plan approval and ship approval.
  - `skills/pilot/autopilot.md` — driver spec + `.pilot/cycle.json` state
    contract (repo-scoped, survives session death; `continue` resumes).
  - `hooks/autopilot-gate.sh` (G16, Stop only) — blocks ending the turn while
    a cycle is mid-phase; checkpoint/terminal states allow the stop. Honors
    bypass markers, `.pilot.json {"autopilot":{"gate":"warn"|"off"}}`, and
    anti-traps after 3 consecutive same-state blocks. Composes with
    verify-gate (complementary reasons, independent counters); does not touch
    verify-gate internals — no overlap with the hardening plan.
  - `/pilot-autopilot <requirement> | off | (status)` command; cycle block in
    `/pilot-status`; `autopilot` literal token in route-advisor SAFE_SINGLE +
    `Meta. Autopilot` registry row; G16 in guardrails.md.
  - Fix loop bounded by `max_fix_rounds` (default 3) → `status=halted` + halt
    report, never an infinite loop.
  - Tests: `tests/hooks/test_autopilot_gate.sh` (13 cases),
    `tests/skills/test_cycle_schema.sh` (5 cases), route-advisor autopilot
    cases, 3 new golden routes (32/32 eval).
- **playwright-cli as the primary UI-verify vehicle.** The `UI verify` phase
  now routes to `playwright-cli` (Microsoft's token-efficient CLI for coding
  agents — terse Bash commands instead of MCP tool schemas + a11y trees) with
  the bundled `playwright` MCP as fallback. Registry row + SKILL.md verify
  flow + prereqs install instructions (`npm i -g @playwright/cli`,
  `playwright-cli install --skills`); autopilot's verify phase uses the same
  preference order.

- **Witnessed checkpoint approvals (G16 integrity).** New
  `hooks/approval-capture.sh` (UserPromptSubmit) records the user's actual
  approving prompt for a waiting checkpoint as a marker the model cannot
  synthesize; `autopilot-gate.sh` flags checkpoint flags lacking a witness as
  self-approval and sends the conductor back to re-ask. `/pilot-approve`
  command as the explicit form. Conservative prompt-initial matching only —
  mid-sentence/negated approval words never count. Opt-out:
  `{"autopilot":{"approval_witness":"off"}}`.
- **Marketplace drift detection.** `skills-lock.json` marketplace entries pin
  `plugin_id` + version/SHA; `bootstrap-team.sh --check` resolves installed
  versions from `~/.claude/plugins/installed_plugins.json` and reports drift.
  Git-entry check no longer misreports non-git manual installs as missing.
- **`docs/team-onboarding.md`** — 10-minute mental model for new teammates.
- **Team readiness.** Branch-scoped autopilot cycles
  (`.pilot/cycles/<branch-slug>.json`, legacy path honored); `.pilot.json`
  `profile` block (style/strictness) replacing the hardcoded single-user
  persona in SKILL.md/registry/workflow; opt-in repo-scoped shared outcome
  ledger (`team.shared_outcomes`) + `dev/outcome-report.sh` (first-pass-verified
  rate, per-user); `dev/bootstrap-team.sh` + `dev/skills-lock.json` pinned
  constellation install; `docs/ab-method.md` A/B measurement protocol
  (hardening-plan Phase 3 method). CI: fixed the mcpServers manifest check to
  accept hosted (`type:"http"`) servers — it failed on the github MCP entry.
  Site (`web/index.html`) refreshed to v0.10: autopilot, G15/G16 rows, team
  pair, new commands, playwright-cli preference.
- **Vendored `office-hours` + `ceo-review` (from garrytan/gstack, MIT).**
  The two standalone methodology skills — product interrogation ("is this
  worth building") and strategic plan challenge (scope up/down/kill) — copied
  verbatim minus upstream promo/branding, wired as Frame (non-code) and Plan
  fallbacks. The rest of gstack deliberately not adopted (parallel spine →
  routing ambiguity; self-updating installer → supply-chain surface).
  `caveman` documented in prereqs (already an always-on integration).

### Fixed
- **pre-commit TOCTOU: `git add X && git commit` skipped G7/G8/G12 (found
  live in e2e dogfooding — a console.log landed in a real commit).** The
  hook runs before the command, so the index was empty at check time and
  the staged-content scan matched nothing. It now also scans the files the
  command is about to stage — `git add` pathspecs (incl. `.`/-A/-u
  expansion via git status) and `git commit -a` — from the working tree,
  with quoted-string stripping so "-a" in a commit message isn't read as
  the flag. The production floor's real `.git/hooks/pre-commit` (commit-
  time, sees the final index) remains the structural backstop. New tests:
  `tests/hooks/test_pre_commit_toctou.sh`.
- **Gates no longer sniff the transcript for bypass phrases (self-poisoning
  fix, found in e2e dogfooding).** Skill launches land in the transcript as
  user-type entries, and pilot's own SKILL.md contains the literal phrase
  "pilot off rails" — so invoking the pilot skill silently disarmed
  plan-gate (and pre-commit) for the rest of the session. Marker files
  written by the slash commands are now the only bypass mechanism; when the
  user types a phrase, the conductor invokes the matching slash command.
  Regression test: a SKILL.md-style doc in the transcript must not bypass.
- **plan-gate now accepts `.pilot/acceptance.md` as a plan artifact.** The
  AC-first invariant mandates the ledger at Plan time, but the gate only
  recognized superpowers/GSD plan paths — following the registry's own flow
  would have been blocked. Gate and invariant now agree.
- **Phase 9 (Capture): graphify promoted to the Primary column.** It lived
  only in resolution-rule prose while Primary said "claude-mem auto-hook,
  not skill-invokable" — which reads as "nothing to do", and the e2e run
  skipped it. The conductor's action is now explicit.
- **plan-gate and pre-commit now actually block (exit 1 → exit 2).** The Claude
  Code PreToolUse protocol only blocks a tool call on exit 2 (or a deny
  decision); any other non-zero exit shows stderr but lets the call proceed.
  Both gates exited 1, so G1 (plan-before-code) and G3/G7/G8/G12 (commit
  quality) were decorative. `safety-gate.sh` already used exit 2 and was
  unaffected. All gate tests updated to assert exit 2.
- **MCP tool-name drift.** context7 v2 renamed `get-library-docs` →
  `query-docs`; the github server's review/comment tools are
  `get_pull_request_reviews` / `get_pull_request_comments` /
  `add_issue_comment`. SKILL.md, registry.md, and prereqs.md now name the
  tools the pinned servers actually expose.
- **route-advisor no longer orders invocation on a bare mention.** The injected
  directive told the model to "invoke directly" whenever a skill name appeared
  in the prompt — including descriptive mentions ("...should be graphified").
  It now flags the literal hit but tells the model to ignore it unless the
  prompt is actually requesting that work.
- Doc drift: workflow.md said verify-gate "warns" (it blocks);
  guardrails.md documented the old exit-1 behavior.

### Added
- **Requirements playbook (spec-kit mechanics, MIT-ported).**
  `playbooks/requirements.md` — clarify scan (Frame), stable `AC-001` IDs +
  task/test linkage in the ledger (Plan), analyze coverage-matrix gate before
  the first Build edit, evidence-only check-off (Verify). Wired into the
  registry Frame/Plan rows and workflow.md.
- **github MCP → official hosted endpoint.** Replaced the deprecated
  `@modelcontextprotocol/server-github` npm server with GitHub's maintained
  remote (`https://api.githubcopilot.com/mcp`, HTTP + `${GITHUB_TOKEN}`
  header). `dev/wire-mcps.sh`/`unwire-mcps.sh` now handle remote entries via
  `claude mcp add-json` (match-on-URL for safe unwire). Note: the hosted
  endpoint needs `GITHUB_TOKEN` for reads too; no token → `gh` CLI fallback.
- **Review-phase fallback: official `code-review` plugin** added to the
  registry (prefer maintained review prompts when installed).
- **tdd-guard documented as a recommended companion** in prereqs.md (blocks
  red-green-refactor violations during Build; complements the verify-gate).
- Removed the over-broad `"run.sh"` entry from this repo's `.pilot.json`
  `test_patterns` — it let any command *mentioning* `run.sh` (e.g. a grep of
  hook sources) be captured as a passing test run and clear G14.
- **AC ledger — requirement traceability (opt-in).** The Plan phase writes
  acceptance criteria as `- [ ]` checkboxes to `.pilot/acceptance.md`;
  `verify-gate.sh` now blocks a "done" claim while any box is unchecked, even
  with a passing test capture. No ledger file → no AC gating. Same
  bypass/warn/anti-trap rails as the test-run check. New tests in
  `tests/hooks/test_verify_gate_ac_ledger.sh`.
- **Graphify at close-loop.** Phase 9 (Capture) now includes running
  `graphify` on the cycle's changed files (delta map) so new code lands in
  the knowledge graph for future debugging — Phase 0.9 maps inputs, Phase 9
  maps outputs. Registry, workflow.md, and the new-feature playbook updated.

### Changed
- **plan-gate now also covers Bash code writes (Phase 11).** A large source file
  written through the shell (`cat > file`, `tee`, heredoc) previously slipped
  past plan-gate, which only matched the Edit/Write tools — surfaced while
  dogfooding a calculator build. plan-gate now also runs on `PreToolUse: Bash`
  and blocks a >20-line write to a code file when no plan exists. Non-code/small
  writes, reads, pipelines, and `>&2`/`/dev/null` redirects pass untouched.

## [0.9.0] — 2026-06-26

Agentic-OS release. Adds the OS primitives on top of the 0.8 hardening: a
feedback loop (outcome ledger → router nudge), an executable production floor
(blocking CI gate), persistent project memory across sessions, and a parallel
orchestration phase. Pilot hooks: 12 → 13.

### Added
- **Persistent project memory (Phase 10).** `hooks/memory-surface.sh`
  (SessionStart) injects a capped digest of `.pilot/memory.md` so durable
  decisions/conventions/gotchas survive across sessions and compaction;
  `/pilot-remember <note>` appends to it. Silent when absent.
- **Parallel orchestration (Phase 10).** New registry phase **0.8 Orchestrate
  (parallel)** + `playbooks/orchestration.md`: decompose → dispatch one subagent
  per independent unit (`superpowers:dispatching-parallel-agents`) → join, with
  worktree isolation for parallel mutations. The process model an OS needs.
- **Executable production floor (Phase 9).** `dev/floor-check.sh` runs the
  applicable floor gates and exits non-zero on any failure — tests, `shellcheck`
  (when present), and a secret scan (`gitleaks` when present, else a conservative
  built-in regex). Absent tools are skipped, never failed. Wired into pilot's own
  CI as a blocking `floor` job (dogfood) and documented alongside
  `verify_gate:"run"` for per-turn local enforcement. The floor now *executes*,
  not just ships as templates.
- **Feedback loop (learning, Phase 8).** `verify-gate.sh` now appends every
  meaningful Stop result to a repo-scoped ledger `~/.cache/pilot/outcomes.jsonl`
  (`pass` / `blocked` / `warn`). `route-advisor.sh` reads it and injects a
  one-line nudge when this repo's recent first-pass-verified rate is poor
  (≥ half of the last ≤10 "done" claims blocked, min 3 samples) — behavioral
  feedback, not auto-rerouting. `/pilot-status` gains an Outcomes section. The
  measurement stick from Phase 3 now feeds something.

## [0.8.0] — 2026-06-26

Hardening release. Closes the verify-gate trust hole (real captured test runs),
adds a fail-closed destructive-command safety gate, a routing eval + A/B
measurement harness, repo-config-gated auto-format, a live production-floor
applier, project-hook integrity warnings, and a PreToolUse liveness heartbeat.
Pilot hooks: 7 → 12.

### Added
- **`pretooluse-heartbeat.sh`** — a `PreToolUse` (all-tools) hook that records
  each PreToolUse fire so `/pilot-doctor` can prove the chain is live. PreToolUse
  hooks can fail silently (Claude Code issue #31250); doctor's own Bash command
  triggers the heartbeat, so a fresh mark confirms PreToolUse works and a
  missing/stale one flags a dead chain. New `/pilot-doctor` liveness section +
  tests. The golden routing set also gains novel-phrasing `NONE` cases asserting
  the advisor defers fuzzy intent to the model rather than mis-hard-routing.
- **`integrity-check.sh`** — a `SessionStart` hook that warns when the opened
  project ships its own Claude Code hooks in `.claude/settings.json` /
  `settings.local.json` (the SessionStart-hook RCE vector — a real PyPI-worm
  incident). Lists each foreign hook command to vet; pilot's own global hooks
  are not flagged; also warns if the routing registry is missing. Informational,
  never blocks. Wired across all sync points with tests.
- **`/pilot-floor` command** — applies the production-quality floor (CI
  workflow + pre-commit config) to the current project via the now-tested
  `apply-floor.sh` (idempotent, never overwrites). New
  `tests/skills/test_apply_floor.sh` covers the applier and template validity.
- **`autoformat.sh`** — a `PostToolUse: Edit|Write|MultiEdit` hook that formats
  the just-edited file using the formatter the repo **already configures**
  (prettier/ruff/black/gofmt/rustfmt). No matching config → no-op, so it never
  imposes a style the repo didn't opt into. Disable per-repo with
  `.pilot.json {"autoformat":"off"}`; honors bypass markers. Wired across all
  sync points with stubbed-formatter tests.
- **Routing eval / measurement harness.** `dev/eval-routes.sh` scores the
  deterministic route-advisor against a golden set
  (`tests/eval/golden_routes.tsv`) — binary 0/1 per case, criteria-based (not
  LLM-judged), expecting 100% since the advisor is deterministic. A suite gate
  (`tests/dev/test_eval_routes.sh`) fails the build on any routing regression.
  `docs/measuring-pilot.md` documents the eval plus a manual A/B protocol
  (pilot on vs off) for end-to-end lift, with the METR "feel faster / be
  slower" caveat front and center.
- **`safety-gate.sh` (G15)** — a fail-closed `PreToolUse: Bash` hook that
  **blocks (exit 2)** destructive commands with catastrophic blast radius:
  `rm` recursive-force on `$HOME`/root/system paths and top-level home dirs
  (`~/projects`, `~/Documents`) — while still allowing nested build dirs
  (`~/app/dist`) — destructive git (force
  push, `reset --hard`, `clean -f`, `branch -D`, `checkout/restore .` — folding
  in the `git-guardrails-claude-code` posture), and secret reads/copies/exfil
  (`.env`, private keys, cloud credentials). Safe, targeted variants pass
  (`rm -rf ./build`, `git push --force-with-lease`, `cat .env.example`). Honors
  pilot bypass markers; `.pilot.json {"safety_gate":"warn"|"off"}` downgrades or
  disables. Wired across all sync points with full tests.
- **`capture-test-run.sh`** — a `PostToolUse: Bash` hook that records the
  *actual* result of test-runner commands (built-in set + per-repo
  `.pilot.json test_patterns`) to `~/.cache/pilot/last-test-run` as JSON
  (`{ts, session_id, cwd, command, ok}`). The result is derived from the Bash
  tool's own captured output, not the transcript. Best-effort; PostToolUse
  cannot block. Wired across `plugin.json`, `dev/wire-hooks.sh` /
  `dev/unwire-hooks.sh`, `commands/pilot-doctor.md`, and the README inventory.

### Changed
- **Production floor reconciled.** `production-floor.md` now reflects that
  `verify-gate` (capture-based block) and `safety-gate` (G15) ship enabled —
  they're no longer listed as pending manual activation — and points to
  `/pilot-floor` for applying the CI/pre-commit templates.
- **verify-gate now requires a REAL captured test run, closing the trust
  hole.** It previously cleared a "done"/"ready" claim by grepping the
  transcript for runner+result words — which the model can fabricate without
  running anything. The gate now clears only when `capture-test-run.sh`
  recorded a passing run for this session (session-id match, with a recency
  fallback when the Stop payload omits a session id). Transcript prose alone
  no longer counts. All existing rails are preserved: bypass markers
  (`bypass*`/`off-rails` → warn), per-repo `.pilot.json {"verify_gate":"warn"}`,
  auto-release after 2 consecutive blocks, schema-drift safe-exit, and the
  "no code changed → skip" gate. Runner-variety recognition moved out of
  verify-gate into the capture hook.
- **Opt-in `verify_gate:"run"` mode.** Set
  `.pilot.json {"verify_gate":"run","test_command":"...","test_timeout":120}`
  and the gate executes the repo's own test command and uses the **real exit
  code** instead of any capture — un-fakeable. Runs lazily (only when a "done"
  claim would otherwise block), respects bypass markers (won't run a suite when
  bypassed), enforces a portable timeout (`timeout`/`gtimeout`/perl-`alarm`
  fallback), and records a passing run as a capture so it runs at most once per
  session.

## [0.7.0] — 2026-05-20

Production-phases release. Extends the phase loop past Ship to cover the
release lifecycle, makes routing observable, and keeps the post-compact
anchor cost constant as the registry grows.

### Added
- **Three production phases** in `registry.md` (17 total): `7.5 Migration`
  (`migration-safety`), `7.75 Pre-deploy` (`pre-deploy-checklist`), and
  `8.5 Post-deploy` (`post-deploy-monitor`). These ship as **scaffolds** —
  each registers and redirects to a working fallback; full content is
  queued (see `docs/superpowers/plans/2026-05-20-production-hardening.md`).
- **Routing telemetry.** A `PostToolUse: Skill` hook
  (`log-skill-invocation.sh`) appends one line per routed skill to
  `~/.cache/pilot/routing.log`, each tagged with a `session=<8char>` field
  so concurrent Claude Code sessions don't interleave ambiguously.
- **`/pilot-trace`** slash command — prints the current session's phase
  chain in order, scoped by session id.
- **Landing page + README** updated with the production-phases section and
  the v0.7.0 version chip.

### Changed
- **PreCompact anchor cost is now ~constant.** The re-anchor injection
  collapses the per-phase list to a single pointer ("17 phases, see
  registry.md") instead of enumerating every phase, so token cost no
  longer grows linearly with the registry.

## [0.6.1] — 2026-05-20

First-real-dogfood patch — fixes a silent hook-wiring bug found by
actually running v0.6.0 against a live `~/.claude/settings.json`.

### Fixed
- **wire-hooks.sh / unwire-hooks.sh dedup was path-prefix sensitive.**
  After v0.2.0 restructured the repo, old entries in settings.json
  (pointing at the pre-restructure paths) didn't get cleaned up on
  rewire — they accumulated as silent dupes. Now dedup matches by
  basename only.
- **`/pilot-doctor` now does `test -x` on each wired hook command.**
  Future stale-path bugs surface as a clear "BROKEN — file missing"
  line instead of silently passing the existence check.

## [0.6.0] — 2026-05-20

Production-grade MCP bundle. Pilot now ships three MCP servers covering
the highest-value gaps in the verify-and-ship loop.

### Added
- **`@playwright/mcp@0.0.75` bundled.** Browser-driving tools — navigate,
  snapshot, click, fill, evaluate, screenshot. Pilot's Verify phase now
  has a real way to prove a UI change works, not just "tests pass."
  First-run downloads Chromium (~300MB).
- **`@modelcontextprotocol/server-github@2025.4.8` bundled.** GitHub REST
  as MCP tools — PRs, reviews, CI status, issues, code/issue search.
  Pilot's Review/Ship phases can read real GitHub state instead of
  inferring from local git. Writes require `GITHUB_TOKEN`.
- **Registry routing rows for both.** New "UI verify" row routes to
  playwright; new "GitHub ops" row routes to github MCP with `gh` CLI
  fallback.
- **SKILL.md sections for both MCPs.** Document the proactive-use
  pattern: playwright in Verify-after-Build-UI; github MCP in
  Review/Ship for real PR/CI state. Common tools listed, recommended
  workflow, first-run/auth caveats.
- **Per-server opt-out env vars:** `PILOT_DISABLE_PLAYWRIGHT`,
  `PILOT_DISABLE_GITHUB` (matching the existing `PILOT_DISABLE_CONTEXT7`).
- **`check-prereqs.sh`** reports a status row per bundled MCP honoring
  opt-out env vars and surfacing `GITHUB_TOKEN` presence.

### Documented (not bundled)
- `chrome-devtools-mcp` as a lighter alternative to playwright (no
  Chromium download — attaches to your existing Chrome).

## [0.5.1] — 2026-05-20

Patch follow-up on 0.5.0 — closes the open audit findings on the
context7 bundling and a couple of older deferred items.

### Fixed
- **Dropped ambiguous `${CONTEXT7_API_KEY:-}` env block.** Bash-style
  defaults aren't part of Claude Code's plugin-manifest interpolator
  (other working plugins don't pass user env vars via the manifest at
  all). MCP servers now inherit Claude Code's process env; users
  `export` keys in their shell before launching.
- **Pinned `@upstash/context7-mcp@2.2.5`.** Was resolving to *latest*
  on every npx invocation — any future major release would land
  unannounced. Manual bumps from here on.
- **`dev/dry-run.sh` cleanup fixed.** The MultiEdit-with-plan scenario
  used `git rm + git commit --amend --no-edit -m "..."` (contradictory
  flags, didn't actually undo the `.planning` commit). Replaced with
  `git reset --hard HEAD~1`.

### Added
- **`PILOT_DISABLE_CONTEXT7` opt-out.** Set the env var to any
  non-empty value and pilot's SKILL.md tells Claude to skip the
  docs-lookup phase entirely (for restricted-network setups).
- **`routing.log` cap at 500 lines.** Telemetry instruction in
  SKILL.md now tails the log when it grows past 500 entries.
- **`/pilot-doctor` checks MCP server health.** New section reads
  `mcpServers` from plugin.json, verifies each command is on PATH,
  reports `CONTEXT7_API_KEY` + `PILOT_DISABLE_CONTEXT7` state. Also
  picks up `precompact-anchor.sh` in the hook checks (was missed).
- **CI validates `mcpServers` shape.** plugin-manifest job now jq-
  asserts every server has a string command and well-formed args.
- **`web/index.html` updated for v0.5.1 + context7.** New scene 05
  walks through the resolve-library-id → get-library-docs flow.
  "Five hooks" copy bumped to "six" (PreCompact was missed in 0.4.0).

## [0.5.0] — 2026-05-20

First bundled MCP server. Pilot now ships with `context7` so Claude can
fetch current library docs on demand without extra setup.

### Added
- **`context7` MCP server bundled.** `plugin.json` declares
  `mcpServers.context7` pointing at `@upstash/context7-mcp` via `npx`,
  so installing pilot auto-starts the server. Two tools become available:
  `mcp__context7__resolve-library-id` and
  `mcp__context7__get-library-docs`. Free tier works without an API key;
  set `CONTEXT7_API_KEY` for higher rate limits.
- **Registry entry for docs lookup.** `skills/pilot/registry.md` gains a
  "Docs lookup" row routed to context7, plus an always-on layer bullet.
  Triggers: library + version names, "use latest docs", "context7", or
  any phase where the agent is about to touch an unfamiliar API.
- **SKILL.md routing guidance for context7.** Tells Claude to invoke
  context7 *proactively* in Plan/Build/Debug phases, mention once that
  it's pulling fresh docs, and skip when the disruption cost is high.
- **prereqs.md "Bundled MCP servers" section.** Documents context7
  + API key + the new soft `node`/`npx` requirement.
- **`dev/check-prereqs.sh`** checks `npx` and reports
  `CONTEXT7_API_KEY` presence.

### Changed
- README install paragraph now mentions PreCompact (was missed in 0.4.0)
  and the bundled context7 MCP.

## [0.4.0] — 2026-05-20

Resolves the four items deferred from the 0.3.0 audit pass: bypass
semantics, compaction survival, real-payload verification, and the
publishing placeholder.

### Added
- **PreCompact anchor hook.** `hooks/precompact-anchor.sh` fires on
  context compaction and prints routing rules, active guardrails,
  current bypass state, and the last 5 routing log entries. The
  output is injected as system-reminder text into the post-compact
  context, so pilot's routing logic survives `/compact` and
  auto-compaction. Wired in plugin.json + dev/wire-hooks.sh.
- **Per-gate bypass markers.** `bypass-precommit-once` (mirrors the
  existing `bypass-no-plan-once`) lets `/pilot-bypass --no-precommit`
  skip exactly one pre-commit fire without disturbing a concurrent
  `/pilot-off` aimed at the next plan-gate. Each hook now consumes
  its own marker before the shared `bypass-once`.
- **`/pilot-bypass --no-precommit`** slash command flag.
- **`dev/dry-run.sh`** — end-to-end simulation that stands up a
  throwaway repo + cache dir, feeds each hook the documented Claude
  Code payload shape, and verifies the expected decision. 17
  scenarios. Wired into CI right after `tests/run.sh`.
- **`dev/finalize-readme.sh`** — substitutes the `<github-user>`
  placeholder in the README. Uses `gh api user --jq .login` when
  authed, or accepts the handle as an argument.

### Changed
- guardrails.md bypass table now lists both `--no-plan` and
  `--no-precommit`, and explains the per-gate-before-shared
  consumption order.

## [0.3.0] — 2026-05-20

Second audit pass. Closes the gaps the first cleanup missed: matcher
coverage, distribution polish, and onboarding signals.

### Added
- **MultiEdit + NotebookEdit gating.** plan-gate matcher is now
  `Edit|Write|MultiEdit|NotebookEdit`. plan-gate sums all
  `edits[].new_string` lines for MultiEdit and reads `new_source`
  for NotebookEdit.
- **SubagentStop hook.** verify-gate now runs on both `Stop` and
  `SubagentStop`, so long-running subagents claiming "done" without
  test evidence get the same nudge.
- **First-run welcome.** SessionStart banner appends
  "first run — try /pilot-doctor" on the first install, self-dismisses.
- **Upgrade notification.** Banner detects a version transition
  (stored in `${XDG_CACHE_HOME:-~/.cache}/pilot/last-version`) and
  shows a one-line CHANGELOG pointer.
- **Routing telemetry.** SKILL.md instructs Claude to append one
  terse line per routing decision to
  `${XDG_CACHE_HOME:-~/.cache}/pilot/routing.log`. `/pilot-status`
  tails the last 10 entries.
- **CI.** `.github/workflows/test.yml` runs hook tests on
  ubuntu-latest + macos-latest, shellcheck on `hooks/` and `dev/`,
  and JSON validation on plugin manifests.
- **LICENSE.** MIT.

### Fixed
- **HEREDOC false positive** in pre-commit. `<<<stuff` was tripping
  the heredoc-bypass detector via overlapping substring match.
  Tightened regex to require leading boundary + identifier follow.
- **Escaped-quote handling** in pre-commit. `-m "foo \\"bar\\""` made
  sed truncate the message; G3 was applied to a bogus prefix. Now
  the hook detects `\\"` and skips G3 (file checks still run).
- **Substring-match bypass** in plan-gate / pre-commit phrase
  detection. `"shutdownpilot off"` should never trip bypass —
  added `(^|[[:space:]]|[[:punct:]])` leading anchor on every
  `pilot off / pilot --no-plan / pilot back on` grep.
- **TTY-escape-code leak** in check-prereqs. tput colors were set
  unconditionally; piped/captured output had raw ANSI codes. Guard
  on `[[ -t 1 ]]`.
- **PLUGINS_CACHE maxdepth** in check-prereqs. Hardcoded `-maxdepth 8`
  silently missed plugins that nest skills deeper. Removed limit.

### Changed
- **Dropped YAML config.** `.pilot.yml` support removed from
  verify-gate; the awk-based parser was fragile. `.pilot.json` is
  the only per-repo config surface now. Breaking change with zero
  external users (pre-1.0).
- plugin.json: added `license: "MIT"`, `skills: "./skills/"`, fixed
  author surname.
- Banner now reports active bypass state (one-shot armed vs session-active).

### Distribution
- `.gitignore` hardened for `settings.local.json`, `settings.json.bak.*`,
  and `.cache/pilot/`.
- README: dropped YAML config example; `.pilot.json` only.

## [0.2.0] — 2026-05-19

Audit-driven cleanup. The pre-1.0 release where every advertised behavior
is actually wired.

### Added
- Real Claude Code plugin layout: `.claude-plugin/plugin.json` declares all
  four hooks via `${CLAUDE_PLUGIN_ROOT}`, `.claude-plugin/marketplace.json`
  exposes pilot as a single-plugin marketplace. Install via
  `/plugin marketplace add <repo>` → `/plugin install pilot@pilot`.
- Slash commands: `/pilot-status`, `/pilot-off`, `/pilot-off-rails`,
  `/pilot-back-on`, `/pilot-bypass`, `/pilot-doctor`.
- Marker-file bypass under `${XDG_CACHE_HOME:-~/.cache}/pilot`:
  `bypass-once`, `bypass-no-plan-once`, `bypass-session`. Slash commands
  write them; hooks honor them.
- `dev/unwire-hooks.sh` — clean removal of pilot hook entries from
  `~/.claude/settings.json`. Idempotent. Backs up.
- `dev/check-prereqs.sh` and `prereqs.md` — surface what plugins/skills
  pilot would prefer routing into, with required/recommended/optional
  buckets.
- Pre-repo config for verify-gate runners via `.pilot.yml` /
  `.pilot.json` `test_patterns:` list.
- `tests/dev/test_wire_unwire.sh` — wire/unwire integration test that
  proves foreign hooks are preserved.

### Fixed
- **pre-commit was never wired.** It existed as a git-native script with a
  `MSG="$1"` signature but `wire-hooks.sh` never installed it, so G3 / G7
  / G8 / G12 were advertised but unenforced. Rewritten as a Claude Code
  `PreToolUse` hook on `Bash` matching `git commit`; now part of the
  default wired set.
- **plan-gate missed GSD plans.** Registry's resolution rule prefers GSD
  when `.planning/` exists, but plan-gate only ever looked in
  `docs/superpowers/plans/`. Now checks both, plus `.planning/**/SPEC.md`.
- **Documented bypasses weren't real.** `pilot --no-plan`, `pilot off`,
  `pilot off rails` are now actually parsed from the transcript and from
  marker files.
- **24-hour mtime freshness was arbitrary.** Replaced with a git-aware
  check: plan exists in working tree OR was modified in the current
  branch's commits since merge-base.
- **verify-gate runner regex too narrow.** Added bun/pnpm/yarn/nx/vitest
  /mocha/make/gradle/mvn/dotnet/rspec/mix. Result token list widened.
- **Hook paths were absolute and machine-bound.** Plugin install uses
  `${CLAUDE_PLUGIN_ROOT}`; dev install (via `wire-hooks.sh`) resolves
  paths from the script's own location.
- SessionStart banner now includes the plugin version and any active
  bypass marker.

### Changed
- Repo restructured: `pilot/` → `skills/pilot/`, hooks moved to top-level
  `hooks/`, commands added under `commands/`. Existing dev installs must
  rerun `bash dev/wire-hooks.sh` once.
- `tests/run.sh` now discovers tests in both `tests/hooks/` and
  `tests/dev/` and exits non-zero if any test fails (previously masked
  failures because the loop's `set -e` only catches the last test).

### Documentation
- `skills/pilot/guardrails.md` now reflects the actually-wired enforcement
  layer (no more pre-commit-hook lies).
- `skills/pilot/SKILL.md` adds a "Fallback when a routed skill is missing"
  section so Claude degrades gracefully instead of erroring.
- `README.md` rewritten for marketplace install as the primary path.

---

## Releasing a new version

1. Bump `version` in `.claude-plugin/plugin.json`.
2. Prepend a new `## [X.Y.Z] — YYYY-MM-DD` section to this file.
3. Run `bash tests/run.sh` — must be green.
4. Commit with `chore(release): vX.Y.Z`.
5. `git tag vX.Y.Z && git push --tags`.
6. (Optional, if installed) `/claude-mem:version-bump` automates
   plugin.json + CHANGELOG + tag + GitHub release in one step.
