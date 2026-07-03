---
name: pilot
description: Unified AI coding conductor. Auto-routes intent to the right skill (grill, plan, TDD, debug, verify, ship), enforces CLAUDE.md quality gates, and stays extensible via registry.md. Use whenever starting work, debugging, refactoring, or shipping. Triggers on: "build", "fix", "ship", "explore", "messy", "broken", "review", session start, or any code change >20 LOC. Bypass per-turn with "pilot off"; per-session with "pilot off rails".
---

# Pilot

You are conducting Bhargav's coding session. Your job is to:
1. **Detect the phase** of work from the user's prompt and project state.
2. **Invoke the right underlying skill** per `registry.md`.
3. **Enforce guardrails** per `guardrails.md`.
4. **Stay out of the way** — don't repeat what the underlying skill already does.

## Activation banner

The SessionStart hook (`hooks/sessionstart-banner.sh`) owns the `[pilot active]` banner — it prints the version, bypass syntax, and diagnostics pointers. **Do not emit your own banner**; it would duplicate the hook's.

The only exception: if pilot is invoked mid-session (not at SessionStart, so the hook never fired), you may emit one line:

```
[pilot active] phase routing on — bypass with "pilot off" / "pilot off rails" or /pilot-off, /pilot-off-rails.
```

## Literal-name shortcut (highest priority)

**If the user's prompt literally names a skill or MCP, route to it directly — skip phase detection.** Phase detection is for *inferring* intent. Literal naming is an *explicit command*. Respect it.

### Scan for these tokens in the user prompt

- Any **Primary** or **Fallback** skill id from `registry.md` — e.g. `tdd`, `diagnose`, `ui-ux-pro-max`, `frontend-design`, `improve-codebase-architecture`, `writing-plans`, `gsd-plan-phase`, `superpowers:test-driven-development`, etc.
- Any **bundled MCP**: `context7`, `playwright`, `github`.

Multi-word skill names must appear as the one hyphenated token (`improve-codebase-architecture`, not "improve codebase architecture"). Namespace prefixes are **optional** in user prompts — `frontend-design` resolves to `frontend-design:frontend-design`, `writing-plans` to `superpowers:writing-plans`, etc. Match case-insensitively.

### How to route on a literal hit

- **Skill name** → invoke via the `Skill` tool with the canonical id, immediately.
- **MCP name** → use its `mcp__<name>__*` tools proactively when the relevant phase arrives. Don't pre-call them; just commit to using them when the phase reaches them.

### Multi-mention prompts → sequenced chain

If the prompt names several skills/MCPs, treat each as a phase in a chain. Execute in the order they appear. Example user prompt:

> "Use context7 for the docs, plan with writing-plans, TDD it, then verify with playwright. Finally, run improve-codebase-architecture."

→ pre-resolves to:

| Phase | Routed to |
|---|---|
| Docs lookup | `context7` MCP |
| Plan | `superpowers:writing-plans` |
| Build (logic) | `tdd` |
| Verify (UI) | `playwright` MCP |
| Refactor | `improve-codebase-architecture` |

No keyword scoring needed — every phase has an explicit owner.

### Edge cases

- **Short identifier (`tdd`):** match when used as the skill ("TDD this", "use tdd", "tdd skill") — not when it appears inside a longer word.
- **Generic vocabulary:** "design the UI" does **not** match `frontend-design` — the literal hyphenated token is absent. "Design" alone is a phase trigger (Build UI), routed by phase detection.
- **Paraphrase, not literal:** "the formal plan skill" does **not** match `writing-plans` — falls through to phase detection (which still routes to `superpowers:writing-plans` for the Plan phase, so the outcome is identical).
- **Unknown literal:** if a token looks like a skill name but isn't in the registry (e.g. `magic-fixer`), don't invent — fall through to phase detection and surface the gap once.

## Cross-turn phase awareness

Pilot doesn't carry explicit phase state across turns — but the routing telemetry already is the state. **Before** running phase detection, glance at the last ~5 entries of `${XDG_CACHE_HOME:-~/.cache}/pilot/routing.log`:

```bash
tail -5 "${XDG_CACHE_HOME:-$HOME/.cache}/pilot/routing.log" 2>/dev/null
```

Use those entries as **context** for the current routing decision:

- If the latest entries show a chain in progress (`pilot → writing-plans → tdd → ...`), the user's "go" / "continue" / "next" usually means **advance to the next phase**, not start over. Look at the chain shape and pick the natural successor (Build → Verify, Verify → Review, Review → Ship).
- If the latest entry was `skill=gsd-ship` or another terminal, the work is done. A fresh prompt should route to Recall / Triage / Frame.
- If there are no entries from the last ~10 minutes, treat the session as fresh and re-run phase detection from scratch.
- If the chain shows the same skill repeated multiple times (`pilot → tdd → tdd → tdd`), the user is iterating — don't re-engage routing, just continue.

This is **observation**, not control flow. The LLM uses it as a hint to break ties or pick natural successors. The registry's resolution rules still govern actual phase selection.

## Phase detection algorithm

Run this **only after the Literal-name shortcut produced no match.**

1. **Read `registry.md`** (it lives next to this file).
2. **Scan the user prompt** for trigger keywords from the registry.
3. **Read project state** to inform resolution priority:
   - `ls .planning/ 2>/dev/null` — GSD project state present?
   - `git status --short 2>/dev/null` — uncommitted work?
   - `git log --oneline -5 2>/dev/null` — recent commits suggest mid-task?
   - `test -f CLAUDE.md && echo yes || echo no` — repo has been bootstrapped?
4. **Pick one phase** with the highest signal. If ambiguous, ask one focused question (per CLAUDE.md G4).
5. **Invoke the primary skill** for that phase via the Skill tool. Do NOT inline the underlying skill's logic.
6. **Apply guardrails** before any code action — see `guardrails.md`.

## Fallback when a routed skill is missing

The registry lists a `primary` skill plus `fallbacks` per phase. The user's
environment may not have every skill installed (pilot ships with no hard
dependencies). Before invoking, check the available-skills list:

1. **Primary present** → invoke it.
2. **Primary missing, fallbacks present** → invoke the first available fallback.
   Briefly say which fallback you picked and why ("`gsd-plan-phase` not
   installed, using `superpowers:writing-plans`").
3. **All missing** → explain the gap to the user and point at `prereqs.md`.
   Do **not** attempt to inline the skill's logic from memory — it's safer
   to ask the user to install the skill than to wing it.

For `claude-mem:*` and other plugin-bundled skills, the namespace prefix
(`claude-mem:`) must be present in the available-skills list before invoking.

## context7 — bundled docs lookup MCP

Pilot ships with the `context7` MCP server (declared in `plugin.json`).
Use it **proactively** — don't wait for the user to ask:

- Before writing code against a library you didn't see in the file's
  imports / lockfile, or whose API may have changed.
- When the user names a library + version ("how does this work in React 19").
- When the user explicitly says "use context7" / "check the latest docs".

Two MCP tools:
- `mcp__context7__resolve-library-id` — find the canonical library id.
- `mcp__context7__query-docs` — fetch focused excerpts for that id
  (context7 v2 renamed `get-library-docs` → `query-docs`).

When you invoke context7, mention it once ("Pulling current React 19 server
component docs via context7…") so the user knows where the info came from.
Skip if the user is mid-flow and the cost would be more disruptive than the
risk of stale knowledge.

**Opt-out:** if the env var `PILOT_DISABLE_CONTEXT7` is set (any non-empty
value), skip the docs-lookup phase entirely. Acknowledge the limitation
briefly ("docs-lookup disabled — using training-data knowledge for this
library; you can `unset PILOT_DISABLE_CONTEXT7` to re-enable").

## playwright — bundled browser-driving MCP

Pilot ships with the `@playwright/mcp` MCP server. Use it **proactively
in the Verify phase whenever a Build (UI) phase preceded it**. The whole
point of the verify-gate is "claim done only with evidence"; for UI work,
the evidence has to be a real interaction, not just a passing test.

Common tools:
- `mcp__playwright__browser_navigate` — open a URL.
- `mcp__playwright__browser_snapshot` — accessibility-tree dump of the page.
- `mcp__playwright__browser_click` / `browser_type` / `browser_fill_form`.
- `mcp__playwright__browser_evaluate` — run JS in the page (assertions, state).
- `mcp__playwright__browser_take_screenshot` — capture a visual record.

Workflow for UI Verify: navigate to the dev server URL → snapshot → click
through the new flow → assert via `browser_evaluate` or another snapshot.
Then state the verification result in the transcript so verify-gate finds
the evidence and stays silent.

**First-run cost:** Playwright auto-downloads its own Chromium (~300MB)
the first time `browser_navigate` is called. Warn the user once if you
detect a slow first invocation, then proceed.

**Opt-out:** if `PILOT_DISABLE_PLAYWRIGHT` is set, skip browser-driven
verification and fall back to test-runner output only.

## github — bundled GitHub-API MCP

Pilot connects to GitHub's **official hosted MCP endpoint**
(`https://api.githubcopilot.com/mcp` — the deprecated
`@modelcontextprotocol/server-github` npm package was retired in 2025).
Use it in **Review and Ship phases** when you need real GitHub state
instead of inferring from local git: PR review status, CI check results,
merge eligibility, issue/PR threads, branch protection.

Tool names vary across server releases — do NOT assume a name from
memory; check the `mcp__github__*` tools actually available in-session
(PR read/review, issue comment, CI status, and code/issue search are
always covered in some form).

Workflow for Ship: read PR review state → confirm checks green →
post final summary comment → merge (with user confirmation).

**Auth:** the hosted endpoint requires `GITHUB_TOKEN` (a PAT) exported
in the shell before launching Claude Code — for reads too, unlike the
old npm server. If the server fails to connect or returns 401/403,
surface the token hint and fall back to the `gh` CLI via Bash.

**Opt-out:** if `PILOT_DISABLE_GITHUB` is set, skip GitHub MCP calls
and fall back to `gh` CLI invocations via Bash.

## Phase recognition cheatsheet

| Signal | Phase |
|---|---|
| Session opens; user typed nothing yet | 0. Recall |
| "triage"; "what to work on"; "review the inbox" | 0.5 Triage |
| no CLAUDE.md; "new project"; "init" | 0.75 Bootstrap |
| "what if", "idea", "explore" — no code intent | 1. Frame (non-code) |
| "build X", "add Y", "feature for Z" | 1. Frame (code) → 2. Plan |
| User has a frame + says "go" or "plan" | 2. Plan |
| Plan exists; user says "build" / "implement" | 3. Build |
| User mentions UI / component / screen | 3. Build (UI) |
| "bug", "broken", "throws", "fails" | 4. Debug |
| "slow", "latency", "perf", "profile", "benchmark" | 4.5 Performance |
| User says "done" / "ready" before tests run | 5. Verify (gate) |
| Tests green, user wants merge | 6. Review → 8. Ship |
| "security review", "audit", "OWASP", diff touches auth/crypto/network | 6.5 Security (mandatory before Ship) |
| "messy", "hard to change", code smell | 7. Refactor |
| "migration", "schema change", "upgrade dep", diff touches migrations/ or lockfile | 7.5 Migration |
| "deploy", "release", "ship to prod" | 7.75 Pre-deploy (mandatory before Ship) |
| "monitor", "after deploy", "rollback", "did the deploy work" | 8.5 Post-deploy |
| Phase complete | 9. Capture (auto) |
| "how do I X", "is there a skill for", "find a skill" | Meta. Skill discovery |

## Playbooks

For multi-step phase combinations, see:
- `playbooks/new-feature.md` — Frame → Plan → Build → Verify → Review → Ship
- `playbooks/requirements.md` — clarify → trace (AC ledger) → analyze → verify; runs inside Frame/Plan on every code feature
- `playbooks/bug-fix.md` — Debug → Verify
- `playbooks/refactor.md` — Refactor → Verify → Review
- `playbooks/exploration.md` — Frame (non-code) → Spike
- `playbooks/ui-work.md` — Frame → Build (UI) → Review

## Bypass syntax

Marker files in `${XDG_CACHE_HOME:-~/.cache}/pilot/` are the **only** mechanism the gate hooks check — the hooks never grep the transcript for phrases (a mention of a phrase in any document would poison such a grep; this table itself contains the phrases). The **slash commands** write the markers. When the user *types* a natural-language form, you (the conductor) invoke the matching slash command for them — the phrase is a request to you, not a signal to the hooks.

| Intent | Natural language | Slash command | Enforced by |
|---|---|---|---|
| Disable gates for the next turn only | `pilot off` | `/pilot-off` | plan-gate, pre-commit |
| Disable gates for the rest of the session | `pilot off rails` | `/pilot-off-rails` | plan-gate, pre-commit |
| Proceed without a written plan | `pilot --no-plan` | `/pilot-bypass --no-plan` | plan-gate |
| Re-engage after `off rails` | `pilot back on` | `/pilot-back-on` | — |
| Proceed without TDD | `pilot --skip-tdd` | — | advisory only |

`--skip-tdd` has **no enforcing hook** — there is no TDD gate. It's a signal to the conductor to skip the Build-phase TDD step, not a guardrail bypass. Use sparingly.

## What pilot does NOT do

- Does not write code itself for code phases — it invokes Build skills (tdd / superpowers:test-driven-development / ui-ux-pro-max / frontend-design:frontend-design).
- Does not duplicate underlying skill logic. Trust them.
- Does not bypass guardrails silently. Always announce when a guardrail blocks.

## When to ask vs route

- **Ask** when: phase is ambiguous between two with similar signal strength; user hasn't stated success criteria; scope is unclear.
- **Route** when: phase is clear from keywords + project state; trigger matches one row in registry decisively.

Default: route. Ask only when a guardrail forces it (e.g., G1 needs scope to be known before plan vs build).

## Relationship with Claude Code Auto Memory + Auto Dream

Pilot does **not** ship its own memory consolidation. Claude Code already provides:

- **Auto Memory** (`~/.claude/projects/<x>/memory/`) — captures patterns each session.
- **Auto Dream** — Anthropic's built-in consolidation pass; runs automatically every 24h + 5 sessions, or manually via `/dream` (rollout in progress) / "dream" / "consolidate my memory files". Sandboxed, lock-protected, background.

Pilot's **Phase 0 Recall** primary (`claude-mem:mem-search`) reads from the same memory dir Auto Dream maintains. Better-consolidated memories → better Recall → better routing on subsequent prompts. Pilot doesn't write to that directory directly — Auto Memory owns capture, Auto Dream owns maintenance.

If memory feels stale (e.g. after a big refactor), tell Claude "dream" / "consolidate my memory files" before resuming work — the next Recall will benefit.

## Routing telemetry

`hooks/log-skill-invocation.sh` runs on `PostToolUse: Skill` and appends
one line per Skill invocation to `${XDG_CACHE_HOME:-~/.cache}/pilot/routing.log`
(bounded at 500 lines). You don't have to write to that file yourself —
the hook fires whenever you invoke the Skill tool. `/pilot-status`
surfaces the recent entries for debugging.
