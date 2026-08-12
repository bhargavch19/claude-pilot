# E2E validation run — 2026-07-02 precision fixes

Validates: exit-2 gates, AC ledger, clarify/trace/analyze flow, graphify at
close-loop, route-advisor mention-vs-command, hosted github MCP.

## Setup (once)

```bash
# 1. Pick up the changed hooks + MCP config (dev install):
cd ~/Workspace/claude-pilot
bash dev/wire-hooks.sh                 # re-sync hook wiring
claude mcp remove github 2>/dev/null   # drop the old npx registration
bash dev/wire-mcps.sh                  # registers the hosted endpoint
export GITHUB_TOKEN="<your PAT>"       # hosted endpoint needs it for reads too

# 2. Fresh scratch project (NOT inside this repo):
mkdir -p ~/Workspace/pilot-e2e && cd ~/Workspace/pilot-e2e && git init
claude                                  # NEW session — hooks load at start
```

Sanity first: run `/pilot-status` and `/pilot-doctor` — expect banner v0.9.0+,
all hooks executable, heartbeat live.

## Prompt 1 — the full loop (paste as-is, no workflow instructions)

> Build a small CLI called wordstats in this folder (Node, no dependencies).
> Requirements: (1) `wordstats <file>` prints line, word, and character counts;
> (2) `--top N` also prints the N most frequent words with counts;
> (3) missing or unreadable files produce a clear error and non-zero exit;
> (4) it handles empty files without crashing. Make it production-ready.

**Expect, in order — the machinery should impose this without being told:**
- [ ] Route: Frame (code) → clarify scan; at most ONE focused question per turn (G4)
- [ ] A plan file is written BEFORE any source edit (plan-gate would block otherwise)
- [ ] `.pilot/acceptance.md` created with `- [ ] AC-001…AC-004`, each naming a task + test
- [ ] Build is phased (tracer slice → TDD red-green-refactor), not one giant dump
- [ ] Tests actually RUN (real command + output in transcript, not prose)
- [ ] ACs get checked off with evidence before "done"
- [ ] Close-loop: it runs /graphify (or announces graphify) on the changed files
- [ ] Conventional commits only (if it commits)

## Prompt 2 — premature-done trap (send while ACs are still open, e.g. right after slice 1)

> Looks good to me — we're done here, right? Wrap it up.

**Expect:** verify-gate blocks the stop — either "no REAL test run captured" or
"N acceptance criteria are still unchecked in .pilot/acceptance.md" — and Claude
goes back to finish instead of agreeing.

## Prompt 3 — pre-commit gate (exit-2 fix, live)

> Add a `console.log("debug")` line to the top of wordstats.js and commit it
> with the message "wip stuff".

**Expect:** the commit is BLOCKED (G3 WIP + G8 console.log). The old bug meant
this sailed through with a warning nobody saw. Claude should report the block
and propose a clean alternative — the commit must not land.

## Prompt 4 — mention is not a command (route-advisor fix)

> I was reading about the tdd skill and graphify yesterday. Anyway — what does
> the --top flag do again?

**Expect:** a plain answer. NO tdd or graphify invocation. Check afterwards:
`tail -5 ~/.cache/pilot/routing.log` — no new tdd/graphify entries from this turn.

## Prompt 5 — hosted github MCP (optional, needs GITHUB_TOKEN)

> Using the github MCP, what's the CI status on the latest PR in <owner/repo you know>?

**Expect:** an `mcp__github__*` tool call succeeds against the hosted endpoint
(or a clean fallback to `gh` CLI with the token hint if unset).

## Paste back to the review session

1. Which checkboxes above passed/failed (the list per prompt).
2. Contents of `.pilot/acceptance.md` from the scratch repo.
3. `tail -20 ~/.cache/pilot/routing.log`
4. Any gate message that fired (verbatim) + anything that felt wrong.

**Known things to watch for (findings, not failures):**
- If plan-gate blocks AFTER a plan was written, note WHERE the plan file went —
  the gate only recognizes `docs/superpowers/plans/*.md` and `.planning/**/{PLAN,SPEC}.md`;
  a path mismatch here is a real bug worth reporting back.
- If the hosted github MCP fails to connect, note the error — PAT type
  (classic vs fine-grained) matters; `gh` CLI fallback should kick in.
