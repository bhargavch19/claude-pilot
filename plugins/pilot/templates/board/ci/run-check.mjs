import { readdir, readFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseTdd } from '../lib/tdd.mjs';
import { checkBranch } from './check-branch.mjs';

// Story ids come from tdd/*.md frontmatter, never from the filename — this
// mirrors build-board.mjs and start-story.mjs, which both treat frontmatter
// `id` as canonical (start-story.mjs explicitly prefers it over the id the
// developer typed on the command line). A check that derived ids from
// filenames instead would reject branches that `npm run start-story` — the
// tool this check exists to back up — had just generated, the moment a
// file's name and its own frontmatter id diverge.
//
// A file with no frontmatter `id` is skipped for the same reason, rather than
// falling back to its filename. This was the last place in the codebase that
// would accept a filename as a story id, and lib/validate.mjs now quarantines
// an id-less story off the board entirely — so the fallback would have let a
// branch pass CI by naming a story that the board itself refuses to show.
//
// A file that fails to parse is skipped rather than raised: a malformed
// Technical Design Document is already surfaced as an error on the board
// itself, and one bad file must not be able to take the check down for
// every other branch on every other PR.
export async function collectStoryIds(tddDir = 'tdd') {
  let entries;
  try {
    entries = await readdir(tddDir);
  } catch (e) {
    if (e.code === 'ENOENT') {
      // The caller no longer resolves this from the cwd, so "run it from the
      // repo root" would be advice that cannot fix anything. The real cause is
      // a board vendored somewhere without a sibling tdd/.
      throw new Error(
        `${tddDir} not found. The board expects a tdd/ directory alongside it ` +
          '(spec §4: the board is vendored into each app repo at board/).'
      );
    }
    throw e;
  }

  const ids = [];
  for (const file of entries) {
    if (!file.endsWith('.md')) continue;
    const path = join(tddDir, file);
    try {
      const source = await readFile(path, 'utf8');
      const { data } = parseTdd(source, path);
      if (!data?.id) continue;
      ids.push(data.id);
    } catch {
      continue;
    }
  }
  return ids;
}

// The board is vendored into each app repo at `board/` (spec §4), so `tdd/`
// is two levels up from this file. Resolving from import.meta.url rather than
// the cwd means the check behaves identically whether the workflow runs it
// from the repo root, from board/, or via an absolute path.
const TDD_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'tdd');

async function main() {
  let ids;
  try {
    ids = await collectStoryIds(TDD_DIR);
  } catch (e) {
    console.error(e.message);
    process.exitCode = 1;
    return;
  }

  const result = checkBranch(process.env.HEAD_REF, ids);
  if (!result.ok) {
    console.error(result.message);
    process.exitCode = 1;
    return;
  }
  console.log(result.exempt ? 'exempt' : `ok (matches ${result.id})`);
}

// Only run as a CLI entrypoint — importing this module (e.g. from tests)
// must not have side effects.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((e) => {
    console.error(e.stack ?? String(e));
    process.exitCode = 1;
  });
}
