# Triggering pilot — a prompt cheat-sheet

Two ways anything in pilot gets triggered:

1. **Literal name (deterministic).** Type a *distinctive* skill name and the
   `route-advisor` hook hard-routes it before the model even reads the prompt —
   no guessing. "Distinctive" = has a hyphen/colon/digit (`gsd-debug`,
   `paul:plan`, `improve-codebase-architecture`) **or** is one of the safe
   single words: `tdd`, `graphify`, `caveman`, `playwright`.
2. **Natural phrasing (model-routed).** For everything else — including
   common-word skills like `review`, `run`, `verify` — the advisor stays silent
   and the model routes via `skills/pilot/registry.md` using the trigger words
   below. (Common words aren't hard-routed on purpose: "review this" is a
   sentence, not necessarily the Review skill.)

Plus a **spine**: if the repo has `.planning/` the model prefers `gsd-*`; if it
has `.paul/` it prefers `paul:*`.

---

## A. Phase cheat-sheet — say this to get that

| You want… | Natural prompt (model routes) | Or name it directly |
|---|---|---|
| Pick up where you left off | "where were we?", "did we already do X?" | `gsd-resume-work` |
| Decide what to work on | "triage the inbox", "what should I work on?" | `gsd-inbox` |
| Start a fresh project | "new project", "init this repo" | `gsd-new-project` |
| Do N independent things at once | "fan out and review these 6 files", "in parallel…" | `superpowers:dispatching-parallel-agents` |
| Map a codebase / notes | "map this folder", "what's in here?" | `graphify` |
| Think through an idea | "I'm thinking about…", "what if we…", "explore…" | `gsd-explore` / `superpowers:brainstorming` |
| Plan a change | "plan this", "how should we build X?" | `gsd-plan-phase` / `superpowers:writing-plans` |
| Build logic (TDD) | "build/implement/add <feature>" | `tdd` |
| Build UI | "design a dashboard", "build this component/screen" | `ui-ux-pro-max` / `frontend-design` |
| Fix a bug | "X is broken / throws / fails / regressed" | `diagnose` / `superpowers:systematic-debugging` |
| Fix slowness | "this is slow", "profile the bottleneck" | `diagnose` |
| Confirm it works | "actually test it", "confirm it works" | `verify` |
| Review before merge | "review this", "is this ready?" | `code-review` / `simplify` |
| Security pass | "security review", "check for injection/OWASP" | `security-review` / `gsd-secure-phase` |
| Write docs | "document this", "update the README", "API docs" | `init` (CLAUDE.md) / `to-prd` |
| Untangle messy code | "this is messy / hard to change", "clean up" | `improve-codebase-architecture` |
| Schema / dep migration | "schema change", "upgrade dep", "breaking change" | `migration-safety` |
| Dependency audit | "update deps", "outdated packages", "CVE" | `migration-safety` |
| Pre-deploy gate | "deploy", "ship to prod", "go live" | `pre-deploy-checklist` |
| Ship it | "merge", "open a PR", "ship it" | `gsd-ship` |
| Cut a release | "version bump", "cut a release", "changelog" | `gsd-complete-milestone` |
| After a deploy | "monitor the deploy", "did anything break?", "rollback" | `post-deploy-monitor` |
| Close the loop | "reconcile", "unify", "extract learnings" | `gsd-extract-learnings` / `paul:unify` |

> Multiple names in one prompt → a **phase chain**, e.g.
> "graphify the repo then paul:plan the work" routes both, in order.

---

## B. Spine triggers (project state)

- A repo with **`.planning/`** → the model uses the `gsd-*` variant of each phase
  (e.g. `gsd-plan-phase`, `gsd-execute-phase`, `gsd-ship`). Start one with
  `/gsd-new-project`.
- A repo with **`.paul/`** → the model uses `paul:*` and closes with `paul:unify`.
  Any literal `paul:<cmd>` (e.g. `paul:plan`, `paul:apply`) hard-routes.

---

## C. Pilot's own commands (type these directly)

| Command | What it does |
|---|---|
| `/pilot-status` | Wired hooks, bypass state, routing log, **outcomes** (first-pass-verified rate), prereqs |
| `/pilot-doctor` | Deep health check — hooks executable + wired, MCPs, **PreToolUse liveness**, skill availability |
| `/pilot-trace` | The current session's phase chain in order |
| `/pilot-floor` | Apply the production-quality floor (CI + pre-commit) to this project |
| `/pilot-remember <note>` | Save a durable decision/convention to `.pilot/memory.md` (surfaced every session) |
| `/pilot-off` | Bypass the next gate fire (one-shot) |
| `/pilot-bypass --no-plan` | Bypass the next plan-gate fire only |
| `/pilot-off-rails` | Bypass all gates until `/pilot-back-on` |
| `/pilot-back-on` | Re-engage all gates |

Plain-language bypass also works in a prompt: **"pilot off"**, **"pilot off
rails"**, **"pilot --no-plan"**.

---

## D. What fires automatically (no prompt needed)

These are hooks, not prompts — they run on their own:

- **plan-gate** — blocks a >20-line write (Edit/Write **or** `cat >`/`tee`/heredoc
  via Bash) when no plan exists. Trigger it by trying a big change with no plan;
  satisfy it with a plan or `pilot --no-plan`.
- **safety-gate** — blocks `rm -rf` on home/root/system, force-push / hard reset /
  forced clean / branch -D, and secret reads/exfil. Trigger by running one.
- **verify-gate** — at end of turn, blocks a "done" claim on changed code unless a
  **real test run was captured** this session (`capture-test-run` records it).
  Satisfy it by actually running the tests.
- **autoformat** — formats the edited file *if* the repo configures a formatter.
- **integrity-check** / **memory-surface** — at SessionStart: warn on untrusted
  project hooks; surface `.pilot/memory.md`.
- **route-advisor feedback** — if this repo's recent first-pass-verified rate is
  poor, it nudges you to run tests before claiming done.

---

## E. Quick recipes

- **Force a specific skill, skip the guessing:** name it literally —
  `tdd: add a debounce util`, `graphify ./src`, `gsd-debug the failing test`,
  `paul:plan the next phase`.
- **Whole feature, the pilot way:** "build a <feature>" → brainstorm → plan
  (plan-gate) → `tdd` → run tests (capture) → "done" (verify-gate clears) →
  "review this" → "ship it".
- **Just answer me, no ceremony:** "pilot off" then ask, or `/pilot-off-rails`
  for a whole session.
