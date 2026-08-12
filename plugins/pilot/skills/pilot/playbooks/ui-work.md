# Playbook: UI work

**Trigger:** "UI", "design", "component", "screen", "page", "layout".

**Sequence:**
1. **Frame** — `grill-with-docs` if integrating with backend; `grill-me` if pure design.
2. **Sketch** — `gsd-sketch` (throwaway HTML mockup) OR `ui-ux-pro-max` / `frontend-design` for production.
3. **Spec** — `gsd-ui-phase` produces `UI-SPEC.md` with design contract.
4. **Build** — `ui-ux-pro-max` (primary: 67 styles, palettes, font pairings, a11y guidelines); falls back to `frontend-design` for distinctive components. Avoid generic AI aesthetics.
5. **Test** — interaction tests + accessibility checks. Visual regression if Playwright set up.
6. **Review** — `gsd-ui-review` (6-pillar visual audit).
7. **Ship** — same as new-feature.

**Guardrails active:** G1, G3, G4, G6, G10, G14.

**Hard rule:** start dev server and use the feature in a browser before claiming done (per CLAUDE.md UI rule).
