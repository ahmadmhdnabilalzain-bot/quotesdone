---
name: check-a-prs-base-before-merging
description: "A stacked PR merges into its base branch, not main — check baseRefName before merging and after \"MERGED\""
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-14T17:47:52.500Z
---

14 Sep 2026: PR #655 was opened on top of #653's branch (base `sales-engineer-split-request-parent-id`). `gh pr merge 655` reported MERGED, but the squash commit 41aac27 landed on that branch, not main. That branch's push then ran "deploy edge functions" and put #655's edge code in production outside main, and main's next deploy would have rolled it back. Found only because main's head (c53092f) didn't match the merge commit. Fixed with #658: the same reviewed head, onto main.

**Why:** "MERGED" only means merged into the PR's base. A stacked PR whose parent was squash-merged is left pointing at a dead branch.
**How to apply:** before merging, run `gh pr view N --json baseRefName`; if it isn't main, retarget it (`gh pr edit N --base main`) or open a new PR from the same head. After merging, confirm `git ls-remote origin refs/heads/main` equals the merge commit. Related: [[stage-paths-never-git-add-all]], [[code-extremely-well-built]].
