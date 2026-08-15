#!/usr/bin/env bash
# Test the three scaffold skills (migration-safety, pre-deploy-checklist,
# post-deploy-monitor) follow the scaffold contract:
#   1. Valid SKILL.md with YAML frontmatter (name + description).
#   2. "Status: scaffold" marker present.
#   3. "Redirect for now" section present (so the LLM has something to do).
#   4. "Acceptance criteria" section present (so the full-skill spec is documented).
#   5. Description names at least one trigger word.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

scaffolds=(migration-safety pre-deploy-checklist post-deploy-monitor)

for name in "${scaffolds[@]}"; do
  file="$ROOT/plugins/$name/skills/$name/SKILL.md"

  # 1. File exists.
  [[ -f "$file" ]] || { echo "FAIL: $name — SKILL.md missing"; exit 1; }

  # 2. Frontmatter has name + description.
  head -10 "$file" | grep -q "^name: $name$" \
    || { echo "FAIL: $name — frontmatter 'name:' wrong or missing"; exit 1; }
  head -10 "$file" | grep -q '^description: ' \
    || { echo "FAIL: $name — frontmatter 'description:' missing"; exit 1; }

  # 3. Status: scaffold marker.
  grep -q '^## Status: scaffold' "$file" \
    || { echo "FAIL: $name — '## Status: scaffold' marker missing"; exit 1; }

  # 4. Redirect-for-now section.
  grep -q '^### Redirect for now' "$file" \
    || { echo "FAIL: $name — '### Redirect for now' section missing"; exit 1; }

  # 5. Acceptance criteria section.
  grep -q '^## Acceptance criteria' "$file" \
    || { echo "FAIL: $name — '## Acceptance criteria' section missing"; exit 1; }

  # 6. Description names at least one trigger word.
  desc=$(awk '/^description: /{sub(/^description: /,""); print; exit}' "$file")
  echo "$desc" | grep -qi 'trigger' \
    || { echo "FAIL: $name — description doesn't mention triggers (got: $desc)"; exit 1; }

  echo "PASS: $name scaffold contract"
done

# Pilot's registry must reference each scaffold as a Primary skill, using the
# plugin-qualified name it has when installed from the marketplace.
REG="$ROOT/plugins/pilot/skills/pilot/registry.md"
for name in "${scaffolds[@]}"; do
  grep -q "\`$name:$name\`" "$REG" \
    || { echo "FAIL: registry.md doesn't reference $name:$name as Primary"; exit 1; }
  echo "PASS: registry.md routes to $name:$name"
done

echo "ALL scaffold-redirect contract tests passed."
