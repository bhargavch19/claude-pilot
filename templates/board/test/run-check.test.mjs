import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { collectStoryIds } from '../ci/run-check.mjs';

async function withTddDir(files, fn) {
  const dir = await mkdtemp(join(tmpdir(), 'run-check-'));
  try {
    for (const [name, contents] of Object.entries(files)) {
      await writeFile(join(dir, name), contents);
    }
    await fn(dir);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

test('the frontmatter id wins over a divergent filename', async () => {
  await withTddDir(
    { 'JYO-9-broken.md': '---\nid: JYO-9\ntitle: Real\n---\n\nBody.\n' },
    async (dir) => {
      const ids = await collectStoryIds(dir);
      assert.deepEqual(ids, ['JYO-9']);
    }
  );
});

test('a malformed file is skipped, not thrown', async () => {
  await withTddDir(
    {
      'JYO-1.md': '---\nid: JYO-1\ntitle: Fine\n---\n\nBody.\n',
      'JYO-9-broken.md': '---\nid: JYO-9\ntitle: Broken\n  bad: [unclosed\n---\n\nBody.\n',
    },
    async (dir) => {
      const ids = await collectStoryIds(dir);
      assert.deepEqual(ids, ['JYO-1']);
    }
  );
});

// This used to fall back to the filename. It was the only place left that
// accepted a filename as a story id, and it disagreed with lib/validate.mjs,
// which quarantines an id-less story off the board — so a branch could pass
// CI by naming a story the board refuses to display.
test('a file with no frontmatter id is skipped, not named after its filename', async () => {
  await withTddDir(
    {
      'JYO-1.md': '---\nid: JYO-1\ntitle: Fine\n---\n\nBody.\n',
      'JYO-7.md': '---\ntitle: Forgot the id\n---\n\nBody.\n',
    },
    async (dir) => {
      const ids = await collectStoryIds(dir);
      assert.deepEqual(ids, ['JYO-1']);
    }
  );
});

test('an empty directory yields no ids', async () => {
  await withTddDir({}, async (dir) => {
    const ids = await collectStoryIds(dir);
    assert.deepEqual(ids, []);
  });
});

test('a missing directory throws a clear error, not a raw ENOENT stack', async () => {
  await assert.rejects(
    () => collectStoryIds(join(tmpdir(), 'run-check-does-not-exist-xyz')),
    (err) => {
      assert.match(err.message, /not found/);
      assert.doesNotMatch(err.message, /ENOENT/);
      return true;
    }
  );
});
