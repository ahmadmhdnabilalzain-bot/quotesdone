---
name: apply-at-merge-never-before
description: "SQL reaches production only when its PR merges (release operator). Agents prove with rolled-back probes. Applying before merge turns 'the database is running what this repository says' red on EVERY PR"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-09-28T18:24:26.454Z
---

28 Sep 2026: builders applied their SQL to production to prove it, then opened PRs (#1014–#1018, #1024, #1025). Production then ran routines main lacked, so the drift check went red on every open PR, including their own. That was a deadlock: from about 13:30 to 16:30 UTC almost nothing merged, and the founder asked twice why the count never dropped.

**Why:** the drift check compares production with main. Anything applied before merge is drift for every branch.

**How to apply:**
- Builders prove their work with an aborted-transaction probe only, and leave the file under scripts/sql/pending/.
- Only the single release operator applies, at merge time, one PR at a time.
- A drift finding on a branch cut from an old main is resolved by merging origin/main first, before it is treated as real.
- If a deadlock happens anyway, merge the applied PRs as one drift-unblock release. That is the only allowed exception to no-batching.

Related: [[two-applied-prs-deadlock-each-others-database-check]], [[never-merge-on-a-red-check]].
