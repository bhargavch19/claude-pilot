# Contributing

This repo is a Claude Code plugin marketplace: each directory under
`plugins/` is an independently installable plugin, and
`.claude-plugin/marketplace.json` is the catalog. CI validates every
manifest, runs the full hook test suite on Linux + macOS, shellchecks all
scripts, and runs the vendored board suite.

## Adding a skill to an existing plugin

1. Create `plugins/<plugin>/skills/<skill-name>/SKILL.md` with YAML
   frontmatter (`name:` + `description:` — put the trigger words in the
   description; that's what Claude Code matches on).
2. If pilot should route to it, append one row to
   `plugins/pilot/skills/pilot/registry.md`. Use the plugin-qualified name
   (`<plugin>:<skill>`) in the Primary/Fallback columns.
3. Add or extend a test under `tests/skills/`.

## Adding a new plugin

1. `mkdir -p plugins/<name>/skills/<name>` — add `SKILL.md` as above.
2. Add `plugins/<name>/.claude-plugin/plugin.json` with `name`, `version`,
   `description`, `license`, and `"skills": "./skills/"`. Standalone plugins
   wire no hooks and no MCP servers — that's the point of the split.
3. Add the plugin to `.claude-plugin/marketplace.json` (CI fails if a
   `plugins/` dir is missing from the catalog).
4. Add a short `plugins/<name>/README.md` (what / install / how pilot uses it).

## Adding a guardrail (pilot hooks)

1. Add the hook script under `plugins/pilot/hooks/` (bash + jq only — no
   other runtime deps).
2. Wire it in `plugins/pilot/.claude-plugin/plugin.json` under the right hook
   event, using `${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh`.
3. Add a fixture test under `tests/hooks/test_<name>.sh` — see the existing
   tests for the pattern (fixtures in a mktemp dir, JSON piped on stdin).
4. Document the guardrail in `plugins/pilot/skills/pilot/guardrails.md`.

## Running the checks locally

```bash
bash tests/run.sh                      # every hook/dev/skill test
bash plugins/pilot/dev/dry-run.sh      # end-to-end hook simulation
bash plugins/pilot/dev/eval-routes.sh  # deterministic routing eval (must be 100%)
```

## Conventions

- Conventional-commit messages (`feat:`, `fix:`, `docs:`, `chore:`, …).
- Hooks must be informational or fail-safe: a hook that can block must have a
  bypass and an anti-trap (see `guardrails.md`).
- No new runtime dependencies beyond bash + jq.
