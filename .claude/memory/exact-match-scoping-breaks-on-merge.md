---
name: exact-match-scoping-breaks-on-merge
description: "Merging a key that a WHERE clause matches EXACTLY empties every reader of that clause; scope the read, do not rewrite the corpus."
metadata: 
  node_type: memory
  type: project
  originSessionId: fd0754be-8798-4bcf-aec6-6ae1c72265c4
  modified: 2026-08-14T13:05:24.004Z
---

Retrieval scoped `where dept_key = agent.department`. Merging 25 departments into 10 on 14 Aug 2026
would have made every moved employee retrieve **nothing** from the 5,775 `ops_knowledge` rows tagged
with its predecessor's key — silently, with no error and no failed check.

The fix is a scope function, never a corpus rewrite: `fn_dept_scope(dept)` returns the department
plus everything whose `merged_into` points at it, and every reader uses `= any(...)`. Same shape
applies to authority, live-data bindings and the tool list.

**Why:** an exact-match filter is invisible until the value it matches stops existing. Nothing
fails; the result set just becomes empty, which reads as "this agent has no department knowledge".

**How to apply:** before renaming or merging ANY key, grep for `= <that column>` in every routine
that reads it. Then add the scope arm and prove it by measuring the retrieved count for a moved row
before and after — `marketing` assembled 72 knowledge records both sides of the merge.

Related: [[instruments-report-on-the-wrong-subject]], [[a-filter-whose-values-a-path-never-wrote]].
