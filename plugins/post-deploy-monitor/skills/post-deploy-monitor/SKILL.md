---
name: post-deploy-monitor
description: After a production deploy completes, monitor error rate, latency, and log output for the first 15-60 minutes. Surface regressions before they become incidents. Use immediately after Ship phase. Triggers on "monitor", "after deploy", "did the deploy work", "rollback", "post-deploy", "did anything break".
---

# Post-deploy Monitor

## Status: scaffold (full implementation queued)

This skill is registered in pilot's routing table (Phase 8.5 Post-deploy) but its full content is queued. Until then, redirect per use case.

### Redirect for now

- **Manual log scrape** → use `diagnose` to investigate any reported anomaly post-deploy.
- **Error rate / latency check** → if your team has a Grafana / Datadog / Sentry dashboard, open it manually; pilot doesn't yet wrap those APIs.
- **Rollback decision** → use `diagnose` to assess whether a rollback is warranted, then run your team's documented rollback procedure.

State to the user: "post-deploy-monitor is scaffold-only; using `diagnose` for any anomaly investigation."

## When the full skill is implemented, it will cover

### 1. Pre-deploy baseline capture

- Before Ship completes, record:
  - 7-day p50 / p95 / p99 latency for the affected routes
  - 7-day error rate for the affected routes
  - 7-day log-volume baseline
- Store baseline in `.pilot/post-deploy/<commit-sha>.json`

### 2. Post-deploy delta watch

- For 15 / 30 / 60 minutes post-deploy, poll the metrics source
- Compute deltas against baseline
- Threshold alerts:
  - Error rate > baseline × 1.5 → CAUTION
  - Error rate > baseline × 3 → BLOCK (auto-suggest rollback)
  - p99 latency > baseline + 100ms → CAUTION
  - p99 latency > baseline × 2 → BLOCK

### 3. Log diff

- Sample logs from the affected services pre- and post-deploy
- Surface any new error patterns (ERROR / FATAL log lines not present in baseline)

### 4. Rollback recommendation

- Combine signals from sections 2 and 3
- Output one of: `STABLE` (no action), `WATCH` (continue monitoring), `ROLLBACK` (revert immediately)

## Output artifact

Full skill writes `POST-DEPLOY.md` with the deltas, log diffs, and recommendation. Updated every 5 minutes for the first hour.

## Acceptance criteria for the full skill

- Reads metrics from at least: Prometheus, Datadog, Sentry, CloudWatch, Grafana (configurable per-project via `.pilot.json`).
- Reads logs from at least: stdout via `kubectl logs`, CloudWatch Logs, Datadog Logs, Loki.
- Surfaces a recommendation within 15 minutes of deploy completion.
- Has fixture tests covering: baseline-vs-spike error rate, latency regression, new error pattern in logs.

## Triggers (final list)

- Literal: "monitor", "after deploy", "did the deploy work", "rollback", "post-deploy", "did anything break"
- Phase ordering: fires automatically after Phase 8 Ship completes; runs for 60 minutes by default

---

*Full content scheduled for a follow-up session.*
