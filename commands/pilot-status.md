---
description: Show pilot status — wired hooks, bypass state, prereq health.
allowed-tools: Bash
---

The user wants a status snapshot of pilot. Print, in this order:

1. **Wired hooks** — run:
   ```bash
   jq '.hooks // {}' "$HOME/.claude/settings.json" 2>/dev/null \
     || echo '(no settings.json)'
   ```
   Then briefly say which of the four pilot hooks (plan-gate, pre-commit,
   verify-gate, sessionstart-banner) are present.

2. **Bypass markers** — run:
   ```bash
   ls -la "${XDG_CACHE_HOME:-$HOME/.cache}/pilot" 2>/dev/null \
     || echo '(no bypass markers)'
   ```
   Interpret:
   - `bypass-once` → one-shot bypass armed for next gate fire.
   - `bypass-no-plan-once` → next plan-gate fire only.
   - `bypass-session` → session-long bypass active.

3. **Recent routing decisions** — run:
   ```bash
   LOG="${XDG_CACHE_HOME:-$HOME/.cache}/pilot/routing.log"
   [[ -f "$LOG" ]] && tail -10 "$LOG" || echo '(no routing log yet)'
   ```

4. **Outcomes (first-pass-verified rate)** — the Phase 8 feedback ledger:
   ```bash
   L="${XDG_CACHE_HOME:-$HOME/.cache}/pilot/outcomes.jsonl"
   REPO=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
   if [[ -f "$L" ]]; then
     rows=$(grep -F "\"repo\":\"$REPO\"" "$L" | tail -50)
     n=$(printf '%s\n' "$rows" | grep -c .)
     p=$(printf '%s' "$rows" | grep -c '"result":"pass"')
     b=$(printf '%s' "$rows" | grep -c '"result":"blocked"')
     [[ "$n" -gt 0 ]] && echo "last $n 'done' claims here: $p verified, $b blocked" \
                      || echo "(no outcomes recorded for this repo yet)"
   else echo "(no outcome ledger yet)"; fi
   ```
   A high blocked count means "done" is being claimed without running tests —
   the router nudges automatically when it crosses half.

5. **Prereqs** — run `bash ${CLAUDE_PLUGIN_ROOT:-$HOME/Workspace/claude-skill}/dev/check-prereqs.sh`
   and quote the bottom-line result.

Be terse. End with one line telling the user how to bypass
(`/pilot-off`, `/pilot-bypass --no-plan`, `/pilot-off-rails`) and how
to re-engage (`/pilot-back-on`).
