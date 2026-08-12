import { branchMatchesId, titleMatchesId } from './match.mjs';

// A missing/null/non-string updatedAt must never win a recency tie-break, so
// it sorts as the oldest possible value rather than however String() happens
// to stringify it (e.g. String(null) === 'null', which sorts after real
// ISO-8601 timestamps and would otherwise look "newest").
function recencyKey(pr) {
  return typeof pr.updatedAt === 'string' ? pr.updatedAt : '';
}

function byRecency(a, b) {
  return recencyKey(b).localeCompare(recencyKey(a));
}

export function deriveStatus(story, git) {
  const prs = (git && git.prs) || [];
  const branches = (git && git.branches) || [];

  if (story.status_override === 'blocked') {
    return { status: 'blocked', source: 'override' };
  }

  const matched = prs.filter(
    (p) => branchMatchesId(p.headBranch, story.id) || titleMatchesId(p.title, story.id),
  );

  // The wording has to describe the rule actually applied below. It used to
  // read "using the most recently updated", which contradicted merged-wins:
  // with an older merged PR and a newer open one the board correctly said
  // `done` while the warning claimed it had picked the newest.
  let warning;
  if (matched.length > 1) {
    warning = `${story.id}: ${matched.length} pull requests match; ` +
      'a merged one wins, otherwise the most recently updated';
  }

  // Merging is terminal and irreversible, so it outranks recency: if any
  // matched PR has been merged, the story is done, even if a newer matched
  // PR is open or closed. Recency only breaks ties among the merged PRs
  // themselves (or, below, among non-merged PRs when none is merged).
  const mergedMatches = matched.filter((p) => p.state === 'merged');
  if (mergedMatches.length > 0) {
    const pr = mergedMatches.slice().sort(byRecency)[0];
    return { status: 'done', source: `pr#${pr.number} merged`, pr, warning };
  }

  const pr = matched.slice().sort(byRecency)[0];

  if (pr) {
    if (pr.state === 'open') {
      return pr.draft
        ? { status: 'in_progress', source: `pr#${pr.number} draft`, pr, warning }
        : { status: 'in_review', source: `pr#${pr.number} open`, pr, warning };
    }
    // 'closed' without merge falls through — the work was abandoned,
    // so the branch (if any) is the better signal.
  }

  const branch = branches.find((b) => branchMatchesId(b.name, story.id));
  if (branch && branch.ahead > 0) {
    return { status: 'in_progress', source: `branch ${branch.name}`, branch: branch.name, warning };
  }

  return { status: 'todo', source: 'no branch', warning };
}
