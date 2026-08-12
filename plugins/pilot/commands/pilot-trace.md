---
description: Show the current session's pilot routing chain — phases visited in order since the last SessionStart.
allowed-tools: Bash
---

Print a compact trace of every Skill invocation belonging to the current
Claude Code session. Resolution preference:

1. **By session_id** (preferred) — entries in `routing.log` carry a
   `session=<8char>` field since v0.7.0. Scope to the most recent
   session_id and show every entry sharing it. Concurrent Claude Code
   sessions stay disambiguated.
2. **Fallback: by `skill=pilot` boundary** — for log entries from before
   the session_id rollout, scope to entries since the most recent
   `skill=pilot` row.

Steps:

1. **Locate the log:**

   ```bash
   LOG="${XDG_CACHE_HOME:-$HOME/.cache}/pilot/routing.log"
   if [[ ! -f "$LOG" ]]; then
     echo "No routing log yet (~/.cache/pilot/routing.log not found)."
     echo "If pilot is wired but hasn't fired, run any work-prompt to seed the log."
     exit 0
   fi
   ```

2. **Prefer session_id scoping:**

   ```bash
   LAST_SESSION=$(grep -oE 'session=[a-z0-9]+' "$LOG" | tail -1 | cut -d= -f2)

   if [[ -n "$LAST_SESSION" ]]; then
     echo "Pilot session chain (session_id: ${LAST_SESSION}):"
     echo
     grep -E "session=${LAST_SESSION} " "$LOG" \
       | awk -F'skill=' '{n++; arrow = (n == 1) ? "  " : "→ "; printf "%2d. %s %s\n", n, arrow, $0}'
     CHAIN_LEN=$(grep -cE "session=${LAST_SESSION} " "$LOG")
     LAST_SKILL=$(grep -E "session=${LAST_SESSION} " "$LOG" | tail -1 | awk -F'skill=' '{print $2}')
     echo
     echo "Chain length: $CHAIN_LEN phases. Most recent: $LAST_SKILL."
     exit 0
   fi
   ```

3. **Fallback to skill=pilot boundary (legacy entries):**

   ```bash
   BOUNDARY=$(grep -n 'skill=pilot$' "$LOG" | tail -1 | cut -d: -f1)
   if [[ -z "$BOUNDARY" ]]; then
     echo "No 'skill=pilot' boundary and no session_id in log — showing last 10 entries:"
     tail -10 "$LOG"
     exit 0
   fi

   echo "Pilot session chain (since line $BOUNDARY of routing.log, legacy mode):"
   echo
   tail -n +"$BOUNDARY" "$LOG" \
     | awk -F'skill=' '{n++; arrow = (n == 1) ? "  " : "→ "; printf "%2d. %s %s\n", n, arrow, $0}'
   echo

   CHAIN_LEN=$(tail -n +"$BOUNDARY" "$LOG" | wc -l | tr -d ' ')
   LAST_SKILL=$(tail -1 "$LOG" | awk -F'skill=' '{print $2}')
   if [[ "$CHAIN_LEN" -le 1 ]]; then
     echo "Chain length: 1 — pilot engaged but no phase fired yet."
   else
     echo "Chain length: $CHAIN_LEN phases. Most recent: $LAST_SKILL."
   fi
   ```

The two-tier strategy means concurrent Claude Code sessions stay
separable while older log entries still produce useful traces.
