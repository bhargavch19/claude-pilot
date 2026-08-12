#!/usr/bin/env bash
# End-to-end validation of the story board against a REAL git repo with a REAL
# remote. Every prior test injected `run` and `readLocalCycle`; nothing had ever
# exercised defaultRun or defaultReadLocalCycle. This does.
#
# Layout is the vendored one (board/ inside an app repo), not this workspace's
# factory-board/ exception, so it also validates what Bootstrap step 6 produces.
#
# Not covered here, and deliberately: real `gh` PR data. That needs a GitHub
# repo with real pull requests. The gh-unavailable path IS covered — it is what
# a fresh clone with no remote PRs actually hits.
set -euo pipefail

ROOT="${TMPDIR:-/tmp}/story-board-e2e"
SRC="$(cd "$(dirname "$0")/.." && pwd)"

rm -rf "$ROOT"; mkdir -p "$ROOT"
cd "$ROOT"

git init -q --bare origin.git
git clone -q origin.git work
cd work
git config user.email e2e@example.com
git config user.name "E2E"
git config commit.gpgsign false

# --- the app repo's own content -------------------------------------------
cat > BRD.md <<'MD'
# Product

## Onboarding and chart reveal
<!-- epic: onboarding -->

Stories about first-run.

## Billing
<!-- epic: billing -->
MD

mkdir -p tdd prompts
cat > prompts/chart.md <<'MD'
Render the D1 wheel.
MD

cat > tdd/JYO-1.md <<'MD'
---
id: JYO-1
title: Ephemeris service
epic: onboarding
points: 3
points_initial: 3
---

## Acceptance criteria

- [ ] Positions resolve for any date
MD

cat > tdd/JYO-2.md <<'MD'
---
id: JYO-2
title: Chart reveal
epic: onboarding
points: 8
points_initial: 3
owner: ravi
prompt: prompts/chart.md
depends_on: [JYO-1]
adjustments:
  - at: '2026-07-30'
    from: 3
    to: 8
    by: ravi
    why: native build needed
---

## Acceptance criteria

- [x] Wheel renders D1
- [ ] Dasha timeline scrolls
MD

cat > tdd/JYO-3.md <<'MD'
---
id: JYO-3
title: Invoice export
epic: billing
points: 2
points_initial: 2
---

## Acceptance criteria

- [ ] CSV downloads
MD

# A deliberately broken one — the board must survive it.
cat > tdd/JYO-9.md <<'MD'
---
id: JYO-9
title: Broken
  bad: [unclosed
---
MD

# --- the vendored board ----------------------------------------------------
mkdir -p board
rsync -a --exclude node_modules --exclude board.json --exclude VENDORED.md "$SRC/" board/
# Offline: reuse the already-installed dependency rather than hitting the network.
cp -R "$SRC/node_modules" board/node_modules

cat > .gitignore <<'MD'
board/node_modules/
board/board.json
MD

git add -A
git commit -qm "seed app repo with board"
git branch -M main
git push -q -u origin main

# --- JYO-2: branch pushed to origin WITH a committed cycle (remote tier) ----
git checkout -q -b JYO-2-chart-reveal
mkdir -p .pilot/cycles
cat > .pilot/cycles/JYO-2-chart-reveal.json <<'JSON'
{
  "version": 1,
  "id": "cyc-20260731-aa01",
  "requirement": "chart reveal",
  "spine": "superpowers",
  "status": "fixing",
  "phases": [{"id": "verify", "skill": "verify", "status": "active"}],
  "current_phase": "verify",
  "fix_rounds": 2,
  "max_fix_rounds": 3,
  "checkpoints": {"plan_approved": true},
  "artifacts": {},
  "halt_reason": null,
  "created": "2026-07-30T09:00:00Z",
  "updated": "2026-07-31T09:12:04Z",
  "session_last": "abcd1234"
}
JSON
echo "work" >> tdd/JYO-2.md
git add -A
git commit -qm "JYO-2: work in progress"
git push -q -u origin JYO-2-chart-reveal

# --- JYO-3: local branch, cycle NOT committed (local tier) -----------------
git checkout -q main
git checkout -q -b JYO-3-invoice-export
echo "work" >> tdd/JYO-3.md
git add tdd/JYO-3.md
git commit -qm "JYO-3: work in progress"
# uncommitted, untracked cycle — exactly what a dev has with publish_cycles off
mkdir -p .pilot/cycles
cat > .pilot/cycles/JYO-3-invoice-export.json <<'JSON'
{
  "version": 1,
  "id": "cyc-20260731-bb02",
  "status": "awaiting_plan_approval",
  "phases": [{"id": "plan", "skill": "writing-plans", "status": "active"}],
  "current_phase": "plan",
  "fix_rounds": 0,
  "max_fix_rounds": 3,
  "halt_reason": null,
  "updated": "2026-07-31T10:00:00Z"
}
JSON

# Build from main so nothing depends on which branch happens to be checked out.
git checkout -q main
git fetch -q origin

echo "=================== BUILD (verbose) ==================="
node board/scripts/build-board.mjs . --verbose

echo
echo "=================== board.json ==================="
node -e '
const b = require("./board/board.json");
console.log("project:", b.project.key, "|", b.project.name);
console.log("epics:", b.epics.map(e => e.slug).join(", "));
for (const s of b.stories) {
  console.log(`\n${s.id} ${s.title}`);
  console.log(`  status      ${s.status}  (${s.statusSource})`);
  console.log(`  branch      ${s.branch}`);
  console.log(`  points      ${s.pointsInitial} -> ${s.points}`);
  console.log(`  pilot       ${s.pilot ? s.pilot.phase + "/" + s.pilot.status : "null"}`);
  console.log(`  pilotSource ${s.pilotSource}`);
  console.log(`  acceptance  ${s.acceptance.map(a => (a.checked ? "x" : " ")).join("")} (${s.acceptance.length})`);
  console.log(`  promptBody  ${s.promptBody ? JSON.stringify(s.promptBody.trim()) : "null"}`);
}
console.log("\nwarnings:"); for (const w of b.warnings) console.log("  -", w);
console.log("broken:");   for (const x of b.broken)   console.log("  -", x.file, "::", x.error.split("\n")[0]);
'

echo
echo "=================== CI branch check ==================="
for br in JYO-2-chart-reveal chore/bump-deps nonsense-branch; do
  printf '%-24s ' "$br"
  HEAD_REF="$br" node board/ci/run-check.mjs && echo "  -> exit 0" || echo "  -> exit $?"
done
