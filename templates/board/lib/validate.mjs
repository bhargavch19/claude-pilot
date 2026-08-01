const POINTS = new Set([1, 2, 3, 5, 8]);
const REQUIRED = ['id', 'title', 'epic', 'points', 'points_initial'];

// YAML is not a string format: `id: 2024` is a number, `id: yes` is a boolean,
// and `epic: 2` is a number. Every one of those used to flow straight through
// validation into the board, where a numeric id reached deriveProjectKey and
// threw `s.id.split is not a function` — one story taking the whole build down.
//
// Coercing with String() was the alternative, and it is worse: it invents an id
// the developer never wrote, so their branch silently never matches and the
// story sits at `todo` forever with nothing to explain why. Quarantine is the
// honest failure.
const TEXT_FIELDS = ['id', 'title', 'epic'];

// Optional list fields. `depends_on` is checked separately because it also
// feeds cycle detection. These two are pure passthrough to board.json, where a
// scalar would reach a `.map()` in the UI and crash the page that is supposed
// to be reporting the problem.
const LIST_FIELDS = ['labels', 'adjustments'];

// deriveStatus honours exactly one override value. Any other spelling used to
// be a silent no-op: the developer believes the story is flagged, the board
// disagrees, and nothing anywhere says so.
const OVERRIDES = ['blocked'];

// Spec §11's governing rule is "every failure mode must leave a working
// board", and it nominates exactly two fatal conditions: a duplicate id and a
// dependency cycle. Both are genuinely ambiguous — the build cannot guess
// which file owns an id, or which edge to drop from a cycle.
//
// Everything else is a defect in ONE story, so it quarantines that story
// instead: it lands in `invalid` and the build carries on. One developer
// adding a story without `points_initial` must not blank the board for the
// entire team.
//
// `errors`   -> fatal, build stops.
// `invalid`  -> per-story quarantine, {file, id, reason}.
// `warnings` -> rendered on the board, story still shown.
export function validateStories(stories, epicSlugs = []) {
  const errors = [];
  const warnings = [];
  const invalid = [];

  const byId = new Map();
  for (const s of stories) {
    if (!s.id) continue;
    if (byId.has(s.id)) {
      errors.push(`duplicate id ${s.id} in ${byId.get(s.id).file} and ${s.file}`);
    } else {
      byId.set(s.id, s);
    }
  }

  for (const s of stories) {
    const reasons = [];

    for (const field of REQUIRED) {
      if (s[field] === undefined || s[field] === null || s[field] === '') {
        reasons.push(`${s.file}: missing required field "${field}"`);
      }
    }
    for (const field of TEXT_FIELDS) {
      if (s[field] !== undefined && s[field] !== null && typeof s[field] !== 'string') {
        reasons.push(
          `${s.file}: "${field}" must be text, got ${typeof s[field]} (${s[field]}) — ` +
            'quote it in the frontmatter, e.g. id: "2024"',
        );
      }
    }
    for (const field of ['points', 'points_initial']) {
      if (s[field] !== undefined && !POINTS.has(s[field])) {
        reasons.push(`${s.file}: ${field} is ${s[field]}, must be one of 1, 2, 3, 5, 8`);
      }
    }
    for (const field of LIST_FIELDS) {
      if (s[field] !== undefined && s[field] !== null && !Array.isArray(s[field])) {
        reasons.push(`${s.file}: ${field} must be a list, e.g. [${field === 'labels' ? 'urgent' : ''}] (got ${typeof s[field]})`);
      }
    }
    const depsMalformed =
      s.depends_on !== undefined && s.depends_on !== null && !Array.isArray(s.depends_on);
    if (depsMalformed) {
      reasons.push(`${s.file}: depends_on must be a list of ids, e.g. [JYO-2] (got ${typeof s.depends_on})`);
    }

    if (reasons.length) {
      for (const reason of reasons) invalid.push({ file: s.file, id: s.id ?? null, reason });
      // A quarantined story never reaches the board, so warnings about its
      // epic or its dependencies would point at a card nobody can see. An
      // id-less story would additionally render as literal "undefined
      // references unknown epic".
      continue;
    }

    if (s.epic && !epicSlugs.includes(s.epic)) {
      warnings.push(`${s.id} references unknown epic "${s.epic}"`);
    }
    if (s.status_override !== undefined && s.status_override !== null
        && !OVERRIDES.includes(s.status_override)) {
      warnings.push(
        `${s.id} sets status_override "${s.status_override}", which does nothing — ` +
          `the only supported value is "blocked"`,
      );
    }
    for (const dep of s.depends_on ?? []) {
      if (!byId.has(dep)) warnings.push(`${s.id} depends on unknown story ${dep}`);
    }
  }

  // Cycle detection deliberately still spans quarantined stories: a cycle is
  // a property of the dependency graph as written, and hiding it because one
  // member also has a bad points value would let it survive to the next build.
  const cycle = findCycle(byId);
  if (cycle) errors.push(`dependency cycle: ${cycle.join(' -> ')}`);

  return { errors, warnings, invalid };
}

function findCycle(byId) {
  const WHITE = 0, GREY = 1, BLACK = 2;
  const colour = new Map([...byId.keys()].map((k) => [k, WHITE]));
  const stack = [];
  let found = null;

  function visit(id) {
    if (found) return;
    colour.set(id, GREY);
    stack.push(id);
    const deps = byId.get(id)?.depends_on;
    for (const dep of Array.isArray(deps) ? deps : []) {
      if (!byId.has(dep)) continue;
      if (colour.get(dep) === GREY) {
        found = [...stack.slice(stack.indexOf(dep)), dep];
        return;
      }
      if (colour.get(dep) === WHITE) visit(dep);
      if (found) return;
    }
    stack.pop();
    colour.set(id, BLACK);
  }

  for (const id of byId.keys()) {
    if (colour.get(id) === WHITE) visit(id);
    if (found) break;
  }
  return found;
}
