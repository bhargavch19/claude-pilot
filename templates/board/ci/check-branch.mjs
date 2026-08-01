import { branchMatchesId } from '../lib/match.mjs';

// Case-sensitive and deliberately narrow: exactly these three lowercase
// prefixes are the escape hatch, not a loose "starts with chore" guess.
// `Chore/x` or `HOTFIX/x` are not exempt — a typo'd or spoofed prefix
// should not silently bypass the check.
const EXEMPT = /^(chore|hotfix|docs)\//;

// Safety net for hand-made branches. The primary mechanism is
// `npm run start-story`, which generates a name branchMatchesId always
// accepts — this check only needs to catch the occasional manual branch
// whose name doesn't resolve to any known story.
export function checkBranch(branch, storyIds) {
  if (EXEMPT.test(branch)) return { ok: true, exempt: true };

  const id = storyIds.find((sid) => branchMatchesId(branch, sid));
  if (id) return { ok: true, exempt: false, id };

  return {
    ok: false,
    exempt: false,
    message:
      `Branch "${branch}" does not match any story in tdd/.\n` +
      `Create branches with: npm run start-story <STORY-ID>\n` +
      `Or prefix with chore/, hotfix/ or docs/ if this is not story work.`,
  };
}
