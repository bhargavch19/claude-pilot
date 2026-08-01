# Pilot hardening plan (research-driven)

> Next-steps plan for making the `pilot` plugin more reliable, grounded in research into how
> people make LLM coding agents reliable. Created 2026-06-26 after the v0.7 feature set
> (GSD spine, blocking verify-gate, route-advisor, production floor, docs/deps/release phases).
> Paste the "Handoff prompt" section into a fresh session to execute.

## Repo facts to respect

- **Tests:** `bash tests/run.sh` (plain bash + jq, no deps). Must stay green; add tests for every
  change under `tests/{hooks,dev,skills}/test_*.sh` (~122 passing as of this plan).
- **Hooks** live in `hooks/*.sh` and are wired in THREE places that must stay in sync:
  `.claude-plugin/plugin.json`, `~/.claude/settings.json` (dev install, absolute paths), and
  `dev/wire-hooks.sh` + `dev/unwire-hooks.sh`. Any new hook must ALSO be added to
  `commands/pilot-doctor.md` (the executable-check list + the settings-wiring grep regex) and the
  README hooks inventory.
- **verify-gate.sh** — BLOCKING Stop/SubagentStop hook. Honors bypass markers
  (`~/.cache/pilot/bypass*`, `off-rails`), a per-repo `.pilot.json {"verify_gate":"warn"}` downgrade,
  and auto-releases after 2 consecutive blocks. Resolves `.pilot.json` from the git root. The repo's
  `.pilot.json` lists `test_patterns` so `bash tests/run.sh` is recognized.
- **route-advisor.sh** — UserPromptSubmit hook. Deterministic routing for distinctive literal skill
  names (hyphen/colon/digit, or safe-list `tdd`/`graphify`/`caveman`/`playwright`) + project-state
  spine (`.planning/`=GSD, `.paul/`=PAUL). Silent on fuzzy/common-word prompts. Eligibility checked
  per-alias.
- **Conventions:** plan before any change >1 file or >20 LOC and WAIT for approval; small atomic
  conventional commits; commit ONLY when asked; end commit messages with
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

## Research findings driving this (verified, with sources)

- **TDD Guard** (https://github.com/nizos/tdd-guard) persists REAL test-run output to a file and
  validates against it, rather than trusting transcript text. Captured exit codes can't be
  hallucinated; transcript lines can.
- Most-cited community hooks are fail-closed `exit 2` safety blocks (`rm -rf`, force-push,
  `.env`/secret/prod reads) — after a real `rm -rf ~/` incident.
  (https://github.com/karanb192/claude-code-hooks, https://github.com/ithiria894/awesome-claude-code-hooks)
- A PyPI worm planted a malicious SessionStart hook via repo `settings.json` (RCE on project open) —
  treat `settings.json`/`registry.md` like CI config.
- There is NO controlled study that hooks/routing improve outcomes; it's first-principles +
  testimonials. METR RCT: experienced devs **19% slower** with AI while feeling faster
  (https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/). So measurement matters.
- Eval best practice: binary 0/1 pass-fail judging beats 0.0–1.0; criteria-based beats raw LLM-judge.
- Hook convention is industry-convergent (Cursor, OpenAI Codex, Gemini CLI copied JSON-on-stdin +
  `exit 2` to block). `PreToolUse` hooks can fail silently (Claude Code issue #31250).

## Phased plan (execute top-down; plan each phase, get approval, TDD)

### Phase 1 — Close the verify-gate trust hole (HIGHEST; on-thesis)
**Problem:** verify-gate decides "done OK" by grepping the transcript for runner+result words — the
model can fabricate "tests passed" without running anything. **Fix:** rely on a REAL captured test
result, not prose.
- Preferred design (brainstorm alternatives first): a `PostToolUse(Bash)` hook that detects
  test-runner commands and records their actual exit code + timestamp to
  `~/.cache/pilot/last-test-run`; verify-gate then requires a recent (this-session) zero-exit captured
  run, instead of / in addition to the transcript regex.
- Consider an opt-in `.pilot.json {"verify_gate":"run"}` mode where the gate executes the test command
  itself (with timeout + guardrails).
- Keep all existing bypass/anti-trap behavior.
- Tests: prove the gate BLOCKS a fabricated "tests passed" claim with no captured run, and ALLOWS a
  real captured pass.

### Phase 2 — Destructive-action safety gate (HIGH; cheap, huge blast radius)
New fail-closed `PreToolUse` hook (e.g. `hooks/safety-gate.sh`, matcher `Bash`) blocking `rm -rf` on
`$HOME`/root paths, `git push --force` to protected branches, and reads/writes of `.env`/secrets/prod
config. Fold in the posture of the installed `git-guardrails-claude-code` skill. Honor pilot bypass
markers. Wire everywhere + tests.

### Phase 3 — Eval / measurement harness (HIGH; nobody else has proof)
Golden set of labeled prompts → expected phase/route, scored binary 0/1, runnable via `tests/` or a
`dev/` script; plus a documented A/B method (pilot on vs off) to measure lift. Goal: MEASURE that
pilot helps, not assert it.

### Phase 4 — PostToolUse auto-format/lint after edits (MED-HIGH)
Most popular community hook; near-zero risk. Format/lint changed files after Write/Edit.

### Phase 5 — Activate the production floor live (MED)
Wire the scaffolded semgrep/gitleaks/coverage templates (`skills/pilot/playbooks/templates/` +
`production-floor.md`) as real blocking gates, not just docs.

### Phase 6 — Settings/registry integrity (MED; security)
Warn on untrusted project-level hooks; verify `settings.json`/`registry.md` integrity. (The self-heal
hook `dedupe-settings-hooks.mjs` already runs at SessionStart.)

### Phase 7 — Router robustness (LOWER)
Low-confidence → defer-to-model fallback for novel phrasings; a "did the PreToolUse hook actually run"
check (issue #31250).

## Definition of done (each phase)
- New/changed behavior covered by tests; `bash tests/run.sh` green (run it, quote output).
- Any new hook synced across `plugin.json` + `~/.claude/settings.json` + `dev/wire-hooks.sh` +
  `dev/unwire-hooks.sh` + `commands/pilot-doctor.md` + README.
- Update `CHANGELOG.md`; consider a version bump to 0.8.0 (Release phase) at the end.
- Atomic conventional commit per phase, only when approved.

## Handoff prompt (paste into a fresh session)

> You are working on the "pilot" Claude Code plugin at /Users/bhargavchellu/Workspace/claude-skill.
> Read `docs/pilot-hardening-plan.md` for full context, repo facts, research, and the phased plan.
> Start by reading `hooks/verify-gate.sh`, `hooks/route-advisor.sh`, `.claude-plugin/plugin.json`, and
> `tests/hooks/`, then give me the **Phase 1** plan (design options for capturing real test results
> instead of trusting the transcript) and wait for approval. Respect the conventions in the doc:
> plan-before-coding, TDD, keep `bash tests/run.sh` green, sync any new hook across all wiring points,
> commit only when I ask.
