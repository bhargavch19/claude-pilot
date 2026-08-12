// Pure string helpers for turning a story title into the slug half of a
// branch name. No fs/child_process here — see scripts/start-story.mjs for
// the I/O and git invocation that consumes these.

export function slugify(title, max = 40) {
  const base = String(title)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');

  if (base.length <= max) return base;

  // Cut at the limit, then back up to the last separator so we never split
  // a word mid-way through — a slug that trails off ("...timel") reads as
  // broken, a slug that stops on a whole word doesn't.
  const cut = base.slice(0, max);
  const lastDash = cut.lastIndexOf('-');
  return (lastDash > 0 ? cut.slice(0, lastDash) : cut).replace(/-+$/, '');
}

// The canonical branch form is `<id>-<slug>`: id first (so branchMatchesId's
// hyphen/end-of-string boundary always holds), no `feat/`-style prefix, slug
// derived from the title. A title that slugifies to nothing (blank, or pure
// punctuation) still has to yield a branch worth checking out, so fall back
// to the bare id rather than leaving a trailing "-".
export function branchNameFor(id, title) {
  const slug = slugify(title);
  return slug ? `${id}-${slug}` : id;
}
