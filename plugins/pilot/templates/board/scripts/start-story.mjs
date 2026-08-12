// Developer-facing CLI: `npm run start-story -- <STORY-ID>`. Reads the story's
// Technical Design Document, derives the canonical branch name, and checks it
// out. This is the primary enforcement mechanism for the whole board — typing
// the branch name by hand is how a story silently never shows progress. All
// fs and git I/O lives here rather than in lib/, which stays pure.
import { readFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { join } from 'node:path';
import { parseTdd, TddParseError } from '../lib/tdd.mjs';
import { branchNameFor } from '../lib/slug.mjs';

const id = process.argv[2];
if (!id) {
  console.error('usage: npm run start-story -- <STORY-ID>');
  process.exit(1);
}

const rel = join('tdd', `${id}.md`);

let source;
try {
  source = await readFile(rel, 'utf8');
} catch {
  console.error(`no such story: ${rel}`);
  process.exit(1);
}

let data;
try {
  ({ data } = parseTdd(source, rel));
} catch (e) {
  if (e instanceof TddParseError) {
    console.error(`could not read ${rel}: ${e.message}`);
    process.exit(1);
  }
  throw e;
}

// The frontmatter id wins over the requested id — it's what the board
// itself matches branches against, so preferring it keeps the branch
// consistent with how the story is tracked. But a mismatch usually means a
// copy-paste slip in the Technical Design Document, and silently branching
// under a different id than the one typed would be exactly the kind of
// invisible failure this whole tool exists to prevent. Say so plainly.
if (data.id && data.id !== id) {
  console.log(`note: ${rel} declares id "${data.id}", not "${id}" — using "${data.id}".`);
}

const resolvedId = data.id ?? id;
const branch = branchNameFor(resolvedId, data.title ?? '');

try {
  // stdio: 'inherit' lets git's own fatal messages (branch already exists,
  // dirty working tree, detached HEAD, etc.) reach the developer directly —
  // they're clearer than anything we'd write ourselves. We only need to stop
  // a thrown non-zero exit from surfacing as a raw Node stack trace.
  execFileSync('git', ['checkout', '-b', branch], { stdio: 'inherit' });
} catch (e) {
  if (e.code === 'ENOENT') {
    console.error('\ncould not run git — is it installed and on your PATH?');
  } else {
    console.error(`\ncould not create branch "${branch}" — see git output above.`);
  }
  process.exit(1);
}

console.log(`\non ${branch} — the board will show ${resolvedId} as in progress once you commit.`);
