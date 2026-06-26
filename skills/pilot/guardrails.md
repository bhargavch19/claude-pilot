# Pilot Guardrails

15 rules from `~/.claude/CLAUDE.md` and the user's auto-memory, mapped to
how pilot enforces them. The Soft layer is skill content — Claude reads it
and obeys. The Hard layer is shell hooks wired into Claude Code; they cannot
be silently ignored.

## Soft layer (skill content — Claude obeys)

| # | Rule | Trigger | Action |
|---|---|---|---|
| G2 | Explain trade-offs (1 alternative + why rejected) | In Frame/Plan output | Plan template requires `## Alternative considered`. |
| G4 | One focused clarifying question, not 3 invented assumptions | In Frame phase | Max 1 question per turn. |
| G5 | No silent scope creep | Edit on file unrelated to current task | Add to `out-of-scope-followups.md` instead of fixing inline. |
| G6 | Read every diff (user reads, AI explains) | Before commit | Print diff + 1-line "what changed, why this approach" before `git commit`. |
| G9 | Async boundaries have explicit error handling | TDD red phase | Test includes error path before implementation. |
| G10 | Tests for non-trivial logic | Build phase | TDD mandatory unless `/pilot-bypass --skip-tdd`. |
| G11 | Hypothesis before editing (debug) | Debug phase | `diagnose` skill's reproduce → hypothesise step non-skippable. |
| G13 | Direct communication, no filler | Always | Fragments OK, technical exact, fluff dies. |

## Hard layer (shell hooks — enforced by Claude Code)

All four hooks are declared in `.claude-plugin/plugin.json` and auto-wired
on plugin install. For dev installs, `bash dev/wire-hooks.sh` writes them
into `~/.claude/settings.json` using absolute paths.

| # | Rule | Hook script | Trigger | Action |
|---|---|---|---|---|
| G1 | Plan before coding (>20 LOC) | `hooks/plan-gate.sh` | `PreToolUse: Edit\|Write` | Block when `new_string`/`content` > 20 lines and no plan found for the current branch. |
| G3 | Atomic commits, conventional messages | `hooks/pre-commit.sh` | `PreToolUse: Bash` matching `git commit` | Block on missing `feat:`/`fix:`/`chore:`/... prefix or WIP message. Skipped for HEREDOC / `-F file` / editor-mode commits. |
| G7 | TS strict, no `any` without comment | `hooks/pre-commit.sh` | `PreToolUse: Bash` matching `git commit` | Block on `: any` in staged TS/TSX without `// any: <reason>` on same line. |
| G8 | No dead code, no `console.log` | `hooks/pre-commit.sh` | `PreToolUse: Bash` matching `git commit` | Block on `console.log(` in staged TS/JS/TSX/JSX. |
| G12 | No `sleep`/timeout patches for flaky tests | `hooks/pre-commit.sh` | `PreToolUse: Bash` matching `git commit` | Block on new `sleep(` or `setTimeout(` in staged files matching `*test*`/`*spec*`. |
| G14 | Verify before claiming done | `hooks/verify-gate.sh` (+ `hooks/capture-test-run.sh`) | `Stop`, `SubagentStop` (capture: `PostToolUse: Bash`) | **Block** a "done"/"ready"/"passing" claim on changed source unless a real test run was captured this session. Downgrades to warn via bypass markers / `.pilot.json {"verify_gate":"warn"}`; auto-releases after 2 blocks. |
| —  | Routing telemetry (observability, not a guard) | `hooks/log-skill-invocation.sh` | `PostToolUse: Skill` | Append one line per Skill invocation to `~/.cache/pilot/routing.log` (capped at 500 lines). Surfaced by `/pilot-status`. |

`G15` (dangerous git ops — `push --force`, `reset --hard`, `clean -f`,
`branch -D`) is not part of pilot itself. Install the dedicated
`git-guardrails-claude-code` skill if you want this layer.

## Plan-gate hook (G1) — detailed behavior

`hooks/plan-gate.sh` runs on `PreToolUse: Edit|Write`:

1. Skip when `Edit`/`Write` content is ≤ 20 lines.
2. **Bypass check** — short-circuit if any of:
   - marker `${XDG_CACHE_HOME:-~/.cache}/pilot/bypass-once`
     (consumed after this gate fire), or
   - marker `bypass-no-plan-once` (consumed), or
   - marker `bypass-session` (persists until `/pilot-back-on`), or
   - last user message contains `pilot off`, `pilot off rails`, or
     `pilot --no-plan`, or
   - most-recent off-rails toggle is "off" (not yet flipped back on).
3. **Plan existence** — allow if a plan file is present for this branch:
   - any `docs/superpowers/plans/*.md` in the working tree, OR
   - any `.planning/*/PLAN.md` or `SPEC.md` in the working tree, OR
   - any of the above modified in commits since `git merge-base HEAD <upstream>`.
4. Otherwise block (exit 1) with a G1 message naming both plan locations.

## Pre-commit hook (G3/G7/G8/G12) — detailed behavior

`hooks/pre-commit.sh` runs on `PreToolUse: Bash`:

1. Acts only when the command invokes `git commit` (matches with or without
   `-m`, `--amend`, etc.).
2. Bypass check — same one-shot/session marker logic as plan-gate, plus
   `pilot off` / `pilot off rails` transcript phrases.
3. Parses commit message from `-m "..."` / `-m '...'` / `--message="..."`.
   HEREDOC, `-F <file>`, and editor-mode commits skip G3 only.
4. G3: block on WIP or missing conventional prefix.
5. G7/G8/G12: scan staged files (`git diff --cached`).
6. Exit 1 on violation; otherwise exit 0.

## Verify-gate hook (G14) — detailed behavior

`hooks/verify-gate.sh` runs on `Stop` (end of assistant turn):

1. Reads transcript via `transcript_path` (real Claude Code format) or
   inline `.transcript[]` (legacy fixtures).
2. Greps last assistant messages for done/ready/passing/fixed claims.
3. Skips when no source file changed in the working tree (analysis/docs
   turns don't trip the gate).
4. Requires a **real captured test run**, not transcript prose: the
   companion `capture-test-run.sh` (`PostToolUse: Bash`) records the actual
   result of test-runner commands to `~/.cache/pilot/last-test-run`. The
   gate clears the claim only when that fact file shows a passing run for
   this session (session-id match, with a recency fallback when the Stop
   payload omits a session id). A model writing "tests passed" without
   running anything no longer clears the gate.
5. Per-repo extension: `.pilot.json` `test_patterns:` (JSON array of regex
   strings) extends which commands `capture-test-run.sh` treats as runners.
6. **Blocking** — emits a `{"decision":"block"}` Stop decision by default.
   Downgraded to warn by bypass markers (`bypass*`/`off-rails`) or per-repo
   `.pilot.json {"verify_gate":"warn"}`, and auto-releases after 2
   consecutive blocks so it can never trap the session.
7. **Opt-in run mode** — `.pilot.json {"verify_gate":"run","test_command":
   "...","test_timeout":120}` makes the gate execute the repo's test command
   on the enforce path and use the real exit code (un-fakeable). Lazy (runs
   only when it would otherwise block), bypass-aware (won't run when
   bypassed), timeout-guarded, and records a pass as a capture so it runs at
   most once per session.

## Bypass mechanisms

| Form | Effect | Implementation |
|---|---|---|
| `/pilot-off` | Next gate fire of any kind | Writes `bypass-once`; whichever gate (plan-gate or pre-commit) fires first consumes it. |
| `/pilot-bypass --no-plan` | Next plan-gate fire only | Writes `bypass-no-plan-once`. Plan-gate consumes this before `bypass-once`. |
| `/pilot-bypass --no-precommit` | Next pre-commit fire only | Writes `bypass-precommit-once`. Pre-commit consumes this before `bypass-once`. |
| `/pilot-off-rails` | Until `/pilot-back-on` | Writes `bypass-session`; hooks honor without consuming. |
| `/pilot-back-on` | Re-engage | Removes every marker. |
| `pilot off` in user msg | Next gate fire | Transcript-grep fallback. |
| `pilot off rails` in user msg | Until "pilot back on" | Transcript-grep with state tracking. |

Per-gate markers are preferred over the shared `bypass-once` when both
are armed — so a `--no-precommit` doesn't accidentally swallow a
`/pilot-off` intended for the next plan-gate fire in the same turn.

The marker-file path can be overridden via `XDG_CACHE_HOME`.

`G14` blocks by default but honors the bypass markers above (they downgrade
it to warn) and auto-releases after 2 consecutive blocks. The intended way to
clear it is to actually run your test suite — `capture-test-run.sh` records the
result and the gate releases on the next stop.
