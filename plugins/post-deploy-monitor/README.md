# post-deploy-monitor

After a production deploy completes, monitor error rate, latency, and log
output for the first 15–60 minutes — surface regressions before they become
incidents. Triggers on "monitor", "after deploy", "did the deploy work",
"rollback", "post-deploy".

Currently a structured scaffold: it registers the phase, runs the documented
checklist, and redirects to a working fallback where depth is still queued.

## Install

```
/plugin marketplace add bhargavch19/claude-pilot
/plugin install post-deploy-monitor@pilot
```

Wires no hooks and no MCP servers — adds one skill. Works standalone;
[pilot](../../README.md) routes to it automatically at phase 8.5
(Post-deploy), after Ship completes.
