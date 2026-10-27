---
name: parallel-helpers-need-their-own-scratch-folders
description: "Parallel helpers sharing one scratchpad overwrite each other's same-named scripts (q.mjs); give every helper its own subfolder and read a script back before any write"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-14T22:24:37.732Z
---

**What happened, 14 Sep 2026.** About ten helpers ran in parallel, all writing scripts into the one session
scratchpad. Several used the same names (`q.mjs`, `close.mjs`). One helper found that its `q.mjs` had been rewritten
to post its argument as SQL to the write endpoint, and that a script it built ran an accountant dry run instead. It
was name collision, not an attack. But a helper running someone else's script against the production database is
exactly how an unintended write happens.

**How to apply:**
- Every helper brief names a unique scratch subfolder (`scratchpad/<task-slug>/`) and says to use only that one.
- Before running any script that writes, read it back and confirm it is the one you wrote. Never reuse a generic name
  from the scratchpad root.
- Same principle as [[parallel-agents-must-not-do-git-in-a-shared-tree]]: shared mutable space plus parallel agents
  means silent collisions.

Related: [[two-applied-prs-deadlock-each-others-database-check]].
