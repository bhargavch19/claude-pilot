#!/usr/bin/env bash
# Pilot safety-gate — fail-closed PreToolUse(Bash) hook.
#
# Blocks (exit 2 — the Claude Code blocking convention for PreToolUse) the
# handful of commands with catastrophic, irreversible blast radius:
#   1. `rm` recursive+force on $HOME / root / system paths
#   2. destructive git (force push, reset --hard, clean -f, branch -D,
#      checkout . / restore .) — folds in the git-guardrails posture
#   3. secret reads / copies / exfil (.env, private keys, cloud credentials)
#
# Safe, targeted variants pass (rm -rf ./build, git push, --force-with-lease,
# cat .env.example). Honors pilot bypass markers and a per-repo downgrade:
#   .pilot.json { "safety_gate": "warn" }  → warn instead of block
#   .pilot.json { "safety_gate": "off"  }  → disable entirely
set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
printf '%s' "$INPUT" | jq empty >/dev/null 2>&1 || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
[[ "$TOOL" == "Bash" ]] || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[[ -n "$CMD" ]] || exit 0

# --- Bypass markers (one-shot consumed; session-wide honored) -------------
BYPASS_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pilot"
for m in bypass-safety-once bypass-once; do
  if [[ -f "$BYPASS_DIR/$m" ]]; then
    rm -f "$BYPASS_DIR/$m"
    echo "safety-gate: bypassed ($m consumed)." >&2
    exit 0
  fi
done
if [[ -f "$BYPASS_DIR/bypass-session" ]] || [[ -e "$BYPASS_DIR/off-rails" ]]; then
  echo "safety-gate: bypassed (session bypass active)." >&2
  exit 0
fi

# --- Per-repo downgrade via .pilot.json (cwd or git root) -----------------
PILOT_JSON=""
if [[ -f .pilot.json ]]; then
  PILOT_JSON=".pilot.json"
else
  GITROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
  [[ -n "$GITROOT" && -f "$GITROOT/.pilot.json" ]] && PILOT_JSON="$GITROOT/.pilot.json"
fi
ACTION="block"
if [[ -n "$PILOT_JSON" ]]; then
  SG=$(jq -r '.safety_gate // empty' "$PILOT_JSON" 2>/dev/null || true)
  [[ "$SG" == "off" ]] && exit 0
  [[ "$SG" == "warn" ]] && ACTION="warn"
fi

# In warn mode, report and keep scanning; in block mode, refuse the tool call.
emit() {
  if [[ "$ACTION" == "warn" ]]; then
    echo "safety-gate: WARN — $1" >&2
    return 0
  fi
  echo "safety-gate: BLOCKED — $1 Bypass: type \"pilot off\" (one-shot) or \"pilot off rails\" (session), or set {\"safety_gate\":\"warn\"} in .pilot.json." >&2
  exit 2
}

# Pad with spaces so leading/trailing argument tokens match like interior ones.
C=" $CMD "

# Command-boundary prefix. A real command starts at a line start or after a
# shell control operator (; | & (), optionally via a wrapper like sudo/xargs).
# Anchoring the *verb* here keeps the gate from firing on prose — e.g. a commit
# message or echo string that merely mentions "rm -rf $HOME". grep works
# line-by-line, so `^` anchors to each command line of a multi-line command.
CB='(^|[;&|(])[[:space:]]*((sudo|doas|xargs|exec|env|time|nohup|nice)[[:space:]]+)*'

# --- 1. rm recursive-force on a dangerous path ----------------------------
# Scope the flag + path checks to each rm invocation's OWN arguments (rm up to
# the next shell separator). A global scan over the whole command line would
# false-positive when an unrelated rm and an unrelated path (e.g. a `/` inside a
# sed/echo elsewhere in the command) merely coexist.
RM_INVOCS=$(printf '%s\n' "$CMD" | grep -oE "${CB}rm[[:space:]][^;&|)]*" 2>/dev/null || true)
if [ -n "$RM_INVOCS" ]; then
  while IFS= read -r inv; do
    [ -n "$inv" ] || continue
    # recursive flag (…r/R…) AND force flag (…f…) within THIS invocation.
    printf '%s' "$inv" | grep -Eq '(^|[[:space:]])-([a-zA-Z]*[rR])|--recursive' || continue
    printf '%s' "$inv" | grep -Eq '(^|[[:space:]])-([a-zA-Z]*f)|--force' || continue
    inv=" $inv "
    danger=0
    # root, bare home, home wildcard, and a top-level home child (~/projects,
    # ~/Documents — precious) — but NOT a deeper path (~/app/dist, a build dir).
    printf '%s' "$inv" | grep -Eq '[[:space:]](/|/\*|~|~/|~/\*|~/[^/[:space:]]+|\$HOME|\$\{HOME\}|\$HOME/\*|\$\{HOME\}/\*|\$HOME/[^/[:space:]]+|\$\{HOME\}/[^/[:space:]]+)([[:space:]]|$)' && danger=1
    # absolute system directories (bare, trailing slash, or /*)
    printf '%s' "$inv" | grep -Eq '[[:space:]]/(usr|etc|var|bin|sbin|lib|lib64|opt|boot|dev|sys|proc|root|home|System|Library|Applications|private|Users)(/\*|/?)([[:space:]]|$)' && danger=1
    # bare current / parent directory
    printf '%s' "$inv" | grep -Eq '[[:space:]](\.|\.\.)([[:space:]]|$)' && danger=1
    if [ "$danger" = "1" ]; then
      emit "\`rm\` recursive-force on a home/root/system path is irreversible and high-blast-radius."
    fi
  done <<EOF
$RM_INVOCS
EOF
fi

# --- 2. destructive git ---------------------------------------------------
if printf '%s' "$CMD" | grep -Eq "${CB}git[[:space:]]+push"; then
  if printf '%s' "$C" | grep -Eq -- '--force-with-lease'; then
    :  # safe: lease-guarded force, allow
  elif printf '%s' "$C" | grep -Eq -- '(--force([[:space:]]|=|$)|[[:space:]]-[a-zA-Z]*f([[:space:]]|$))'; then
    emit "force-push can overwrite remote history; prefer \`--force-with-lease\`."
  fi
fi
printf '%s' "$CMD" | grep -Eq "${CB}git[[:space:]]+reset[[:space:]]+--hard" && emit "\`git reset --hard\` discards uncommitted work irreversibly."
printf '%s' "$CMD" | grep -Eq "${CB}git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f" && emit "\`git clean -f\` permanently deletes untracked files."
printf '%s' "$CMD" | grep -Eq "${CB}git[[:space:]]+branch[[:space:]]+-D" && emit "\`git branch -D\` force-deletes a branch (may lose unmerged commits)."
printf '%s' "$CMD" | grep -Eq "${CB}git[[:space:]]+(checkout|restore)[[:space:]]+\.([[:space:]]|\$)" && emit "\`git checkout/restore .\` discards all uncommitted changes in the tree."

# --- 3. secrets: reads / copies / exfil -----------------------------------
SECRET_FILE='(\.env([[:space:]]|$|[^a-zA-Z.])|\.env\.(local|production|prod|dev|development|staging)|id_rsa|id_ed25519|id_dsa|\.pem([[:space:]]|$|"|'\'')|\.ssh/id_|\.aws/credentials|\.npmrc|\.pypirc)'
if printf '%s' "$C" | grep -Eq "$SECRET_FILE"; then
  if printf '%s' "$CMD" | grep -Eq "${CB}(cat|less|more|head|tail|bat|nl|xxd|od|strings|cp|mv|scp|rsync|sftp)[[:space:]]"; then
    emit "reading or copying a secret file (.env, private key, or cloud credentials) risks leaking it into context or elsewhere."
  fi
  if printf '%s' "$CMD" | grep -Eq "${CB}(curl|wget|nc|netcat|sftp|scp|ftp)[[:space:]]"; then
    emit "a secret file appears alongside a network command — possible exfiltration."
  fi
fi

exit 0
