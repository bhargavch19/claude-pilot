function escapeRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// Matches at start of string or immediately after a "/", and must be
// followed by "-" or end of string. The trailing boundary is what stops
// JYO-4 from matching JYO-40.
export function branchMatchesId(branch, id) {
  if (!branch || !id || typeof id !== 'string') return false;
  return new RegExp(`(^|/)${escapeRe(id)}(-|$)`, 'i').test(branch);
}

// Looser: the id may sit anywhere in a PR title, but must be bounded by
// non-alphanumerics on both sides.
export function titleMatchesId(title, id) {
  if (!title || !id || typeof id !== 'string') return false;
  return new RegExp(`(^|[^A-Za-z0-9])${escapeRe(id)}([^A-Za-z0-9]|$)`, 'i').test(title);
}
