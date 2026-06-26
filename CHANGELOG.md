# Changelog

All notable changes to the `pilot` plugin are documented here. Format roughly
follows [Keep a Changelog](https://keepachangelog.com/); versions follow
[Semantic Versioning](https://semver.org/) once 1.0 ships.

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
