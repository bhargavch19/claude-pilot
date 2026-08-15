---
description: Apply pilot's production-quality floor (CI + pre-commit blocking gates) to this project.
allowed-tools: Bash
---

The user wants to activate pilot's production-quality floor in the current
project. The floor is the blocking layer (tests+coverage, types, lint, SAST,
secret scan, dependency audit) that makes output production-grade — see
`skills/pilot/playbooks/production-floor.md`.

1. Run the applier (idempotent — never overwrites an existing file):
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT:-$HOME/Workspace/claude-pilot/plugins/pilot}/skills/pilot/playbooks/apply-floor.sh" "$PWD"
   ```

2. Report which files were **added** vs **already present** from the output,
   then list the human-confirmed next steps the script printed (expose
   `test`/`typecheck`/`lint` scripts; `pre-commit install`; install
   `gitleaks`/`semgrep`/`osv-scanner`; record thresholds in `CLAUDE.md`).

3. Remind the user the floor is **blocking** at Verify/Ship, and that pilot
   already enforces two local gates regardless: the capture-based
   `verify-gate` (a "done" claim needs a real captured test run) and the
   fail-closed `safety-gate` (blocks destructive commands).

Be terse. Tune templates to the project's stack; delete the language block it
doesn't use. Do NOT edit `package.json`/`pyproject.toml` without explicit
confirmation.
