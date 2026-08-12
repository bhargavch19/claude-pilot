# pre-deploy-checklist

A structured gate to run immediately before any production deploy: secret
scan, env-var completeness, feature-flag default state, smoke test plan, and
an identified rollback path. Triggers on "deploy", "release", "ship to prod",
"production", "go live".

Currently a structured scaffold: it registers the phase, runs the documented
checklist, and redirects to a working fallback where depth is still queued.

## Install

```
/plugin marketplace add bhargavch19/claude-pilot
/plugin install pre-deploy-checklist@pilot
```

Wires no hooks and no MCP servers — adds one skill. Works standalone;
[pilot](../../README.md) routes to it automatically at phase 7.75
(Pre-deploy), required before Ship on a release branch.
