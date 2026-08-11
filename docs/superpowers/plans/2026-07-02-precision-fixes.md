# Precision fixes — make the gates real, close the requirement-coverage gap

> From the 2026-07-02 repo review. Goal state: a prompt never loses a requirement,
> plans orchestrate the build, coding is phase-wise, testing is enforced, and new
> code is graphified at close-loop.

## Acceptance criteria

- AC1: plan-gate and pre-commit actually block tool calls (exit 2 per the Claude
  Code PreToolUse protocol; exit 1 is non-blocking). Tests assert exit 2.
- AC2: route-advisor's injected directive no longer orders the model to invoke a
  skill on a bare *mention* — it flags the literal hit but leaves intent
  confirmation to the model.
- AC3: documented MCP tool names match the pinned servers (`query-docs` for
  context7 v2; `get_pull_request_reviews` / `add_issue_comment` etc. for github).
- AC4: verify-gate blocks a "done" claim while `.pilot/acceptance.md` has
  unchecked `- [ ]` items, even when a test capture exists. Covered by tests.
- AC5: registry Phase 9 (Capture) includes `graphify` on the changed files;
  workflow.md/new-feature playbook reference it.
- AC6: doc drift fixed — guardrails.md exit codes, workflow.md "warns"→"blocks".
- AC7: `bash tests/run.sh` fully green.

## Tasks

1. hooks/plan-gate.sh, hooks/pre-commit.sh → exit 2 on block (AC1).
2. Update 8 test files asserting exit 1 for blocks (AC1).
3. hooks/route-advisor.sh directive wording (AC2).
4. SKILL.md + registry.md MCP tool names (AC3).
5. verify-gate.sh AC-ledger check + new test file (AC4).
6. registry.md Phase 9 + Plan-row ledger note; workflow.md; playbooks/new-feature.md (AC5).
7. guardrails.md + workflow.md drift (AC6).
8. Run suite (AC7). CHANGELOG entry. No commit until asked.

## Alternative considered

Enforcing AC coverage via a new PreToolUse hook on `git commit` instead of the
Stop-hook verify-gate — rejected: "done" claims happen at turn end, not only at
commit time, and verify-gate already owns done-claim semantics + anti-trap rails.
