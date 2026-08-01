# Story Board

A Jira-style board for one app repo, where **nothing is clicked into a
status**. The board reads your Technical Design Documents and your git
history, and works out where every story stands. There is no database, no
login, and no "move the card" button — you open a PR, and the card moves.

> **"TDD" here means Technical Design Document.** It never means
> test-driven development. Every reference to `tdd/`, a TDD file, or "the
> TDD" in this repo is about a story's design document.

---

## The idea in one picture

```
BRD.md                    one business requirements doc
   │                      split by hand into…
   ▼
tdd/JYO-4.md              one Technical Design Document per story
   │                      you run `npm run start-story JYO-4`
   ▼
branch JYO-4-chart-reveal you write the code
   │                      you open a PR
   ▼
board.json  ──▶  the card moves to "In review" by itself
```

The important property: **status is never stored.** It is recomputed from
your TDD files plus git every time the board is built. There is no state
to drift, nothing to forget to update, and no way for the board to be
"stale but looking current".

---

## For a developer picking up a story

```bash
npm install                     # once
npm run start-story -- JYO-4    # reads tdd/JYO-4.md, creates the branch
```

That puts you on `JYO-4-chart-reveal`. Then work as normal:

```bash
git commit ...                  # board shows JYO-4 as "In progress"
gh pr create --draft            # still "In progress"
gh pr ready                     # board shows "In review"
                                # PR merged → "Done"
```

**Always use `start-story`.** Typing the branch name by hand is the one way
to make a story silently never show progress — the board matches branches to
stories by name, and a name it does not recognise matches nothing. The CI
check (below) is a safety net for when you forget, not the mechanism.

To rebuild the board locally:

```bash
npm run build                   # writes board.json
```

---

## Writing a Technical Design Document

One file per story in `tdd/`. YAML frontmatter, then free-form markdown.

```markdown
---
id: JYO-4                       # required. Quote it if it looks numeric.
title: Chart reveal             # required
epic: onboarding                # required. Must match a slug in BRD.md.
points: 8                       # required. One of 1, 2, 3, 5, 8.
points_initial: 3               # required. What it was estimated at first.
owner: ravi                     # optional
prompt: prompts/chart-reveal.md # optional. Must be inside the repo.
depends_on: [JYO-1]             # optional list
labels: [mobile]                # optional list
status_override: blocked        # optional. "blocked" is the only value.
adjustments:                    # optional. Scope-creep audit trail.
  - at: '2026-08-03'
    from: 3
    to: 8
    by: ravi
    why: native build needed
---

## Acceptance criteria

- [ ] Wheel renders D1
- [ ] Tapping a house opens the detail sheet
```

Checkboxes anywhere in the body become the story's acceptance criteria on
the board. Checkboxes inside fenced code blocks are ignored, so you can show
an example checklist without it turning into phantom criteria.

**Epics** come from `BRD.md`, and only from explicit markers:

```markdown
## Onboarding
<!-- epic: onboarding -->
```

The slug comes from the marker, never from the heading text — so you can
reword a heading without silently reparenting every story under it.

**Changing a requirement** means editing the TDD file. That is the whole
mechanism: the file is the source of truth, the board is a projection of it.

---

## How status is worked out

Applied in order; the first rule that matches wins.

| # | Condition | Status |
|---|-----------|--------|
| 1 | `status_override: blocked` in the TDD | **Blocked** |
| 2 | A matching PR is merged | **Done** |
| 3 | A matching PR is open and ready | **In review** |
| 4 | A matching PR is open and draft | **In progress** |
| 5 | A matching branch is ahead of the default branch | **In progress** |
| 6 | Nothing matches | **To do** |

A PR matches a story if its **head branch** or its **title** contains the
story id. **A merged PR always wins** — merging is terminal and
irreversible, so an old merged PR outranks a newer closed one. Recency only
breaks ties among PRs of equal standing.

Matching is boundary-aware: `JYO-4` never matches `JYO-40`.

---

## Pilot phase (optional)

If a story's branch carries a pilot autopilot cycle, the board publishes it
alongside the story as a **sub-status** — the phase the work is in, whether it
is waiting on a plan or ship approval, and how many fix rounds have burned.

It never changes the story's status. Status stays derived from branches and
pull requests, which are facts other people can see; a cycle is one agent's
self-report and outlives the session that wrote it. A story that has merged
drops its cycle entirely.

Cycles are read from the story's own branch first
(`.pilot/cycles/<branch>.json`, committed when pilot's
`.pilot.json {"board": {"publish_cycles": true}}` is set), falling back to the
local working tree. `pilotSource` on each story records which. With neither,
`pilot` is `null` and nothing else changes — pilot is entirely optional.

---

## Branch naming

```
JYO-4-chart-reveal
└──┬─┘ └─────┬────┘
   id       slug from the title, kebab-case, ≤40 chars
```

Id first, no `feat/` prefix. `npm run start-story` generates exactly this.

Branches starting `chore/`, `hotfix/` or `docs/` are exempt — that is work
which does not belong to a story. The prefixes are case-sensitive and exact,
so a typo cannot accidentally exempt a branch.

There is deliberately **no local git hook** enforcing this. Git hooks are not
cloned, and `--no-verify` skips them, so they enforce nothing you can rely
on. The real safety net is `ci/branch-name.yml`, a GitHub Actions workflow
that runs `ci/run-check.mjs` on every PR. It ships here as an inert template
— copy it to `.github/workflows/` in the app repo to turn it on.

---

## Failure behaviour

The governing rule is **every failure mode must leave a working board.** One
person's mistake must never blank the board for the team.

| What went wrong | What happens |
|---|---|
| A TDD file has broken frontmatter | That story alone goes to "Needs attention" |
| A required field is missing, or a field has the wrong type | That story alone is quarantined |
| A story points at an unknown epic | The board shows a warning; the card renders |
| A `prompt:` path is missing or escapes the repo | Warning; the card renders without its prompt |
| `gh` is not authenticated | Branch state only, with a banner saying so |
| git is older than 2.41 | PR state only, with a banner saying so |
| More than 500 PRs exist | Warning that older PRs are not visible |
| **Two stories share an id** | **Build fails** — nothing can guess which file owns it |
| **The dependency graph has a cycle** | **Build fails** — nothing can guess which edge to drop |

Only those last two are fatal, because only those two are genuinely
ambiguous. A failed build writes no `board.json` at all rather than
overwriting a good one with wreckage.

---

## Layout

```
board/                  ← this folder, vendored into each app repo
├── lib/                pure logic, no I/O (one documented exception)
│   ├── tdd.mjs         frontmatter parse / serialize
│   ├── epics.mjs       epic markers out of BRD.md
│   ├── match.mjs       story-id ↔ branch/title matching
│   ├── slug.mjs        title → branch slug
│   ├── validate.mjs    schema rules; fatal vs quarantine vs warning
│   ├── status.mjs      the precedence table above
│   ├── pilot.mjs       pilot cycle → the published sub-status
│   └── github.mjs      the exception: shells out to gh + git
├── scripts/
│   ├── build-board.mjs assembles board.json
│   └── start-story.mjs the developer CLI
├── ci/
│   ├── check-branch.mjs   pure branch-name rule
│   ├── run-check.mjs      CI entrypoint
│   └── branch-name.yml    workflow template (inert until copied)
└── test/               node:test, one suite per module
```

`lib/` stays free of `fs` and `child_process` so every rule can be tested
without a repo on disk. `lib/github.mjs` is the single adapter that touches
the outside world, and it takes an injectable `run` so its tests do too.

Sibling directories in the app repo:

```
BRD.md          the business requirements document
tdd/            one Technical Design Document per story
prompts/        optional prompt files referenced by TDDs
board/          this folder
```

`board.json` is a build artifact. It is git-ignored and rebuilt on demand —
never commit it, never hand-edit it.

---

## Requirements

- Node 22+
- git 2.41+ for branch status (`%(ahead-behind:...)`)
- `gh` authenticated for PR status

Both degrade rather than fail: without `gh` you get branch state, without a
new enough git you get PR state, and the board says which it is missing.

## Tests

```bash
npm test
```
