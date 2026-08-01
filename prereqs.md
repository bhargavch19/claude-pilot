# Pilot prerequisites

Pilot itself only needs `jq` and `bash` (both ubiquitous). What it routes *to*
is a set of other Claude Code skills and plugins. None are strictly required —
pilot will fall back through the registry's `fallbacks` column — but a friend
running pilot on a fresh box gets the best experience by installing the
recommended set first.

Run `bash dev/check-prereqs.sh` (or `/pilot-doctor` from a Claude Code session)
to see what's installed and what's missing.

## Tools (must be on PATH)

| Tool | Why |
|---|---|
| `bash` ≥ 4 | All hooks. |
| `jq`        | Hook stdin/stdout parsing, settings.json merging. |
| `git`       | plan-gate uses `git merge-base` for plan-freshness checks. |
| `node` + `npx` | Pulls the bundled `context7` MCP server on first invocation. Soft prereq — pilot still loads without it; only the docs-lookup phase degrades. |

## Bundled MCP servers

Pilot's `plugin.json` declares one MCP server. Claude Code starts it
automatically on plugin install.

| Server | Version | Purpose |
|---|---|---|
| `context7` (`@upstash/context7-mcp`) | pinned `@2.2.5` | Up-to-date library docs (`resolve-library-id` + `query-docs` tools). |
| `playwright` (`@playwright/mcp`) | pinned `@0.0.75` | Browser-driving tools (navigate, snapshot, click, evaluate, screenshot) for real UI verification in the Verify phase. First-run downloads its own Chromium (~300MB). |
| `github` (hosted) | `https://api.githubcopilot.com/mcp` (official GitHub endpoint) | GitHub REST as MCP tools (PRs, reviews, CI status, issues). Used in Review/Ship phases. Requires `GITHUB_TOKEN` — for reads too. |

**Env vars** for bundled MCP servers are read from Claude Code's process
environment (no per-plugin env block). To pass an API key, export it in
your shell **before** launching Claude Code:

```bash
export CONTEXT7_API_KEY="…"   # optional — free tier works without
export GITHUB_TOKEN="…"        # required for the hosted github MCP (reads too)
# then start claude code as usual
```

**Per-server opt-outs:** set any of these env vars to disable the
matching MCP routing in pilot's SKILL.md guidance:

| Env var | Effect |
|---|---|
| `PILOT_DISABLE_CONTEXT7=1` | Skip docs-lookup phase; use training-data knowledge. |
| `PILOT_DISABLE_PLAYWRIGHT=1` | Skip browser-driven verification; rely on test-runner output. |
| `PILOT_DISABLE_GITHUB=1` | Skip GitHub MCP; fall back to `gh` CLI. |

**Preferred over the playwright MCP: `playwright-cli`** (Microsoft's CLI for
coding agents — token-efficient, no tool schemas or verbose a11y trees in
context). Pilot's UI-verify phase uses it first when installed and falls back
to the bundled MCP otherwise:

```bash
npm install -g @playwright/cli@latest   # (or --prefix ~/.local without sudo)
playwright-cli install --skills          # per-project agent skill
```

**Alternative to playwright:** `chrome-devtools-mcp` is lighter (no
Chromium download, attaches to your existing Chrome). Drop the playwright
entry in `plugin.json` and add a chrome-devtools one if you prefer.

## Recommended companion hooks (not routed — enforcement)

| Tool | What it adds on top of pilot |
|---|---|
| [`tdd-guard`](https://github.com/nizos/tdd-guard) | PreToolUse hook that blocks Write/Edit violating red-green-refactor, judged against framework-native test reporters (vitest/jest/pytest/go/rust/…). Complements pilot: tdd-guard enforces TDD *during* Build; pilot's verify-gate enforces evidence *at* "done". Its reporter files are also more robust than `capture-test-run.sh`'s command-pattern matching — a future pilot version may read them directly. Install per its README, then keep pilot's `--skip-tdd` unused. |

## Skills / plugins

Pilot routes phase → primary skill, with fallbacks. Categories:

### Recommended (covers most phases)
| Plugin / skill | Covers phases |
|---|---|
| `superpowers` (official marketplace) | Plan, Build (TDD), Verify, Review, Brainstorming, Debug |
| `frontend-design` (official marketplace) | UI build |
| `claude-mem` | Recall (session start), Capture (post-ship) |

### Optional (sharper routing when present)
| Plugin / skill | Covers |
|---|---|
| `grill-me`, `grill-with-docs`, `to-prd`, `to-issues` | Frame (code & non-code) |
| `tdd` | Drop-in for Build (Pocock tracer-bullet TDD) |
| `diagnose` | Drop-in for Debug |
| `improve-codebase-architecture` | Refactor |
| `simplify` | Pre-PR cleanup pass |
| `skill-creator` | Meta: authoring/editing skills |
| `context-mode` | Token-budget hygiene on long outputs |
| `caveman` ([JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman)) | Always-on terse communication style (~65% fewer output tokens; keeps code/commands byte-exact) |
| `typescript-lsp` (official marketplace) | Symbol-level code intelligence for Build/Debug/Refactor — go-to-def, references, safe renames (swap for your stack's LSP plugin) |
| `semgrep` (official marketplace) | Maintained SAST rules — activates the production floor's SAST gate + 6.5 Security fallback |
| `expo` (official marketplace) | Framework skills for React Native / Expo repos (Build UI fallback) |
| `pr-review-toolkit` (official marketplace) | PR-native review workflows for Review/Ship (pairs with the `github` MCP) |

Vendored with pilot (no separate install): `office-hours` (product
interrogation) and `ceo-review` (strategic plan challenge) — the two
methodology skills cherry-picked from
[garrytan/gstack](https://github.com/garrytan/gstack) (MIT). The rest of
gstack is deliberately **not** integrated: it's a parallel workflow spine
(routing ambiguity vs the one-spine decision) with a self-updating
installer (supply-chain surface pilot's hardening plan warns about).

### GSD suite (only if you use it)
Pilot's registry has a `.planning/`-aware path that prefers GSD skills
(`gsd-spec-phase`, `gsd-plan-phase`, `gsd-execute-phase`, `gsd-debug`,
`gsd-ship`, ...) when `.planning/` exists in the cwd. Without GSD installed,
pilot routes through the superpowers / Pocock path instead.

## Editing the registry

When you install a new skill, append a row to `skills/pilot/registry.md`. No
code change needed — the registry is the single source of truth.
