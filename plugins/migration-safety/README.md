# migration-safety

Analyze proposed schema migrations, dependency upgrades, and breaking changes
for production safety — before they ship. Produces a `MIGRATION-SAFETY.md`
assessment. Triggers on "migration", "schema change", "upgrade dep",
"breaking change", "lockfile bump", or a diff touching `migrations/` or a
lockfile.

Currently a structured scaffold: it registers the phase, runs the documented
checklist, and redirects to a working fallback where depth is still queued.

## Install

```
/plugin marketplace add bhargavch19/claude-pilot
/plugin install migration-safety@pilot
```

Wires no hooks and no MCP servers — adds one skill. Works standalone;
[pilot](../../README.md) routes to it automatically at phases 7.5 (Migration)
and 7.6 (Dependencies).
