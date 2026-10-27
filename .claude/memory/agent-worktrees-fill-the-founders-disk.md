---
name: agent-worktrees-fill-the-founders-disk
description: "22 Sep 2026 — 341 agent worktrees (~1 GB each) left the founder's laptop with 46 GB free; remove each worktree as soon as its work is merged"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-22T07:15:04.664Z
---

On 22 Sep 2026 the founder's C: drive dropped to 46 GB free of 952 GB and he feared the laptop would freeze. The cause was `.claude/worktrees/`: 341 agent, review and workflow worktrees, each about 1 GB, and none had ever been removed. On his "delete quickly" I removed 309 of them: the clean ones, the ones whose branch had merged, and the detached review copies. I kept the 5 active ones and 27 that still held uncommitted work.

**Why:** isolation "worktree" creates a full repo copy for every agent and every reviewer, and nothing cleans it up automatically once the work merges.

**How to apply:**
- After a PR merges, remove its worktree with `git worktree remove --force --force <path>` and then `git worktree prune`.
- Launch reviewers (read-only) WITHOUT worktree isolation. They can read the PR's author worktree or `gh pr diff`.
- Check the free space on `/c` (`df -h /c`) at every checkpoint. Clean up when it falls below 100 GB.
- Related: [[parallel-agents-must-not-do-git-in-a-shared-tree]], [[always-max-parallel-agents]].
