---
name: parallel-agents-must-not-do-git-in-a-shared-tree
description: "Fan out freely for reads and applies, but never let concurrent agents run git checkout/add/commit in one working tree — HEAD moves under everyone"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-09T01:29:49.915Z
---

9 Sep 2026. Three agents were briefed to "commit on a branch, push, open a PR" while all working
in `C:\Users\Opera\quotesdone`. Within minutes:

- `git branch --show-current` returned a different branch on two consecutive calls —
  `restore-five-document-functions`, then `ceo-end-of-day-digest`.
- A `git add` of three of my own files staged **eight**, sweeping in another agent's five restored
  edge functions.
- Earlier the same day, my own commit swept in a knowledge agent's `MANIFEST.txt` line and its
  taxonomy report; that agent noticed and said so in its report.

**The index and HEAD are per-worktree, not per-agent.** Every `checkout` moves the tree under
everyone else, and every `add` sees whatever the others have left staged.

**How to fan out safely:**

- **Reads, audits, and production applies parallelise fine.** Eleven read-only audits ran
  concurrently with no interference at all; `apply_sql.mjs` is safe because the database, not the
  tree, is the shared resource — and it guards itself.
- **Give exactly ONE actor the git.** Agents edit files and report; the main session stages by
  explicit pathspec and commits. This is what worked for the phase removal (five PRs, no collisions).
- **If an agent must own a branch, give it `isolation: "worktree"`** so it gets its own checkout.
- **Never `git add -A`** in a shared tree — see [[stage-paths-never-git-add-all]]. Even explicit
  pathspecs are not enough when HEAD itself is moving.

**Recovering from it:** do not race to fix the index — unstaging can strip a file from an agent that
is about to commit. Stop git work, let the agents finish, then reconcile from the branches they
left. Applied SQL is unaffected either way, because production already has it.
