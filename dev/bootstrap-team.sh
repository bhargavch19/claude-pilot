#!/usr/bin/env bash
# One-command team bootstrap: install pilot's recommended skill constellation
# at PINNED versions from dev/skills-lock.json. No self-updaters, no curl|bash
# — git clones at exact SHAs and npm installs at exact versions, so every
# teammate runs the same constellation and upgrades are deliberate (edit the
# lock file, re-run).
#
# Usage:
#   dev/bootstrap-team.sh            install anything missing (idempotent)
#   dev/bootstrap-team.sh --check    report install/drift status, change nothing
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LOCK="$HERE/skills-lock.json"
CHECK=0
[[ "${1:-}" == "--check" ]] && CHECK=1

command -v jq >/dev/null || { echo "bootstrap-team: jq is required"; exit 1; }
[[ -f "$LOCK" ]] || { echo "bootstrap-team: $LOCK missing"; exit 1; }

expand() { printf '%s' "${1/#\~/$HOME}"; }

fail=0
n=$(jq '.skills | length' "$LOCK")
for i in $(seq 0 $((n - 1))); do
  e() { jq -r ".skills[$i].$1 // empty" "$LOCK"; }
  NAME=$(e name); KIND=$(e kind)
  case "$KIND" in
    vendored)
      echo "OK   $NAME (vendored — ships with pilot)" ;;
    git)
      SRC=$(e source); REF=$(e ref); TGT=$(expand "$(e target)")
      if [[ -d "$TGT/.git" ]]; then
        HAVE=$(git -C "$TGT" rev-parse HEAD 2>/dev/null || echo unknown)
        if [[ "$HAVE" == "$REF" ]]; then
          echo "OK   $NAME @ ${REF:0:12}"
        else
          echo "DRIFT $NAME: installed ${HAVE:0:12}, lock ${REF:0:12}"
          if [[ "$CHECK" == "0" ]]; then
            git -C "$TGT" fetch -q origin "$REF" && git -C "$TGT" checkout -q "$REF" \
              && echo "  -> pinned to ${REF:0:12}" || { echo "  -> FAILED to pin"; fail=1; }
          else
            fail=1
          fi
        fi
      elif [[ -d "$TGT" ]]; then
        # Present but not a git clone (manual/other install) — usable, just
        # unpinnable. Never clone over it.
        echo "OK   $NAME (present at $TGT, not a git clone — ref unverifiable)"
      elif [[ "$CHECK" == "1" ]]; then
        echo "MISS $NAME (would clone $SRC @ ${REF:0:12} -> $TGT)"; fail=1
      else
        git clone -q "$SRC" "$TGT" && git -C "$TGT" checkout -q "$REF" \
          && echo "OK   $NAME cloned @ ${REF:0:12}" || { echo "FAIL $NAME clone"; fail=1; }
      fi ;;
    npm)
      SRC=$(e source); REF=$(e ref); CHK=$(e check)
      BIN="${CHK%% *}"
      if command -v "$BIN" >/dev/null 2>&1; then
        HAVE=$($CHK 2>/dev/null | head -1 || echo unknown)
        if [[ "$HAVE" == "$REF" ]]; then echo "OK   $NAME @ $REF"
        else echo "DRIFT $NAME: installed $HAVE, lock $REF"; [[ "$CHECK" == "1" ]] && fail=1 \
          || { npm install -g --prefix "$HOME/.local" "$SRC@$REF" >/dev/null 2>&1 \
               && echo "  -> pinned to $REF" || { echo "  -> FAILED"; fail=1; }; }
        fi
      elif [[ "$CHECK" == "1" ]]; then
        echo "MISS $NAME (would npm install $SRC@$REF)"; fail=1
      else
        npm install -g --prefix "$HOME/.local" "$SRC@$REF" >/dev/null 2>&1 \
          && echo "OK   $NAME installed @ $REF" || { echo "FAIL $NAME npm install"; fail=1; }
      fi ;;
    marketplace)
      # Version/SHA drift detection against Claude Code's installed_plugins.json.
      # We can detect drift but not force a version — surface it for a human.
      PID=$(e plugin_id); REF=$(e ref)
      IPJ="$HOME/.claude/plugins/installed_plugins.json"
      REC=""
      [[ -f "$IPJ" && -n "$PID" ]] \
        && REC=$(jq -r --arg id "$PID" '.plugins[$id][0] // empty | "\(.version // "unknown") \(.gitCommitSha // "-")"' "$IPJ" 2>/dev/null || true)
      if [[ -z "$REC" ]]; then
        echo "MISS $NAME — run: $(e install)"; fail=1
      else
        VER="${REC%% *}"; SHA="${REC##* }"
        if [[ -z "$REF" || "$VER" == "$REF" || "$SHA" == "$REF" ]]; then
          echo "OK   $NAME (marketplace @ ${VER}${SHA:+ / ${SHA:0:12}})"
        else
          echo "DRIFT $NAME: installed $VER/${SHA:0:12}, lock $REF — align via the marketplace, or update skills-lock.json"
          fail=1
        fi
      fi ;;
    *)
      echo "SKIP $NAME (unknown kind '$KIND')" ;;
  esac
done

if [[ "$fail" == "0" ]]; then
  echo "bootstrap-team: constellation matches skills-lock.json"
else
  [[ "$CHECK" == "1" ]] && echo "bootstrap-team: drift/missing found (run without --check to fix the git/npm entries)"
fi
exit "$fail"
