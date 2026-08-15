# Vendored — story board

This directory is a **copy**, not a submodule, not a dependency, not a pin.

| | |
|---|---|
| Source repo | `appbuild-structure` (`~/Workspace/appbuild-structure`) |
| Source subdirectory | `factory-board/` |
| Commit SHA copied from | `24a02b0ddc1178373affa2b946bf4eb0552a33c8` |
| Date copied | 2026-07-30 |
| Excluded from the copy | `node_modules/`, `board.json` (a build artifact) |

`appbuild-structure/factory-board/` **stays exactly as it is** — no move, no
deletion, no new repo. That is the decision recorded in the integration design
§7.1, revised 2026-07-30.

## What this costs, stated plainly

**Two copies of the same code that will drift.** There is no mechanism here that
prevents it. An earlier draft of the design extracted the board into its own repo
and pinned it by SHA specifically to avoid this; that was rejected because it
meant a repo to publish, a pin to maintain, and churn in a working repo. The
mitigations below are deliberately weak and honest rather than strong and
fictional:

- This file records the source repo, path, SHA, and date, so a reader can always
  tell what this is a copy *of*.
- Pilot's CI runs the vendored copy's own suite, so the copy is at least
  known-good on its own terms.

**Neither of these detects `appbuild-structure` moving ahead.** Nothing here
watches the source. Nothing warns when the SHA above goes stale. Do not read the
CI job as drift protection — it proves this copy passes its own tests, nothing
about whether it matches upstream.

## Re-syncing is a deliberate human act

There is no automation. When you decide to re-sync:

1. Re-copy `appbuild-structure/factory-board/` over this directory, excluding
   `node_modules/` and `board.json`.
2. Update the SHA and date in the table above.
3. Re-run the suite: `npm install && npm test`.

## One thing the copy genuinely fixes

`ci/run-check.mjs` resolves `../../tdd`. That path is wrong in
`appbuild-structure/factory-board/` and **correct** once this copy is scaffolded
into an app repo as `board/`. The naming split left open at the end of the
board's Phase 1 stays open upstream — that repo is explicitly being left alone —
but it does not propagate to app repos.

## Not for app repos

Bootstrap step 6 copies this directory into an app repo as `board/` and
**excludes this file**. It documents the vendoring into pilot; inside an app repo
it would be meaningless and misleading.
