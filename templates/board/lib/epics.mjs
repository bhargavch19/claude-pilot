const HEADING = /^##\s+(.+)$/;
const MARKER = /^<!--\s*epic:\s*([a-z0-9-]+)\s*-->$/;

// Epic slugs come from an explicit `<!-- epic: slug -->` marker beneath a
// heading, never derived from the heading text itself. Heading text gets
// edited for readability, and deriving slugs from it would silently
// reparent every story under that heading whenever the wording changes.
//
// A slug repeated in the BRD is a mistake, not a request for two lanes: the
// board groups stories by slug, so a second epic with the same slug renders
// an identical lane that nothing can ever be sorted into. The first wins
// (document order is the only thing separating them) and the repeat is
// reported so the BRD gets fixed. `order` is assigned after de-duplication
// so it stays contiguous.
export function parseEpicsWithDuplicates(brdSource) {
  const bySlug = new Map();
  const duplicates = [];
  let pendingTitle = null;

  for (const raw of brdSource.split('\n')) {
    const line = raw.trim();
    const h = HEADING.exec(line);
    if (h) { pendingTitle = h[1].trim(); continue; }
    const m = MARKER.exec(line);
    if (!m) continue;

    const slug = m[1];
    if (bySlug.has(slug)) {
      if (!duplicates.includes(slug)) duplicates.push(slug);
    } else {
      bySlug.set(slug, { slug, title: pendingTitle ?? slug, order: bySlug.size + 1 });
    }
    pendingTitle = null;
  }

  return { epics: [...bySlug.values()], duplicates };
}

export function parseEpics(brdSource) {
  return parseEpicsWithDuplicates(brdSource).epics;
}
