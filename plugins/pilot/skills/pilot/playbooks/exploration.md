# Playbook: Exploration

**Trigger:** "what if", "idea", "thinking about", "explore X".

**Sequence:**
1. **Grill** — `grill-me` (Pocock). Resolve every branch of the decision tree.
2. **Spike** — `gsd-spike` for throwaway code experiment, OR `gsd-sketch` for UI mockup.
3. **Decide** — promote to feature (→ new-feature playbook) OR archive as ADR.
4. **Capture** — claude-mem auto-captures the decision.

**Guardrails active:** G2, G4, G5, G13.

**Hard rule:** spike code is throwaway. If it ends up shipped, it must be rewritten with TDD.
