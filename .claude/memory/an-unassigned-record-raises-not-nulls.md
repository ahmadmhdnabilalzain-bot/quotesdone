---
name: an-unassigned-record-raises-not-nulls
description: "A plpgsql RECORD assigned only inside an if-branch raises 55000 on field access when the branch is skipped — 20 of the founder's 27 decisions were unresolvable this way."
metadata: 
  node_type: memory
  type: project
  originSessionId: 0f302c30-995c-49f2-be5e-72182155ebd1
  modified: 2026-08-16T04:53:03.221Z
---

In PL/pgSQL a `record` that was never assigned is NOT a record of nulls: any field reference raises
`55000 record "d" is not assigned yet`. A `SELECT INTO` matching **no rows** leaves it
assigned-with-nulls (safe). A `SELECT INTO` that **never runs** leaves it unassigned (raises).
The two are a line apart in source and behave completely differently — and the `if x is not null`
guard meant to make a lookup safe is exactly what skips the assignment.

Found 16 Aug 2026 in `fn_agent_actions_fill_alternatives`, the BEFORE INSERT OR UPDATE trigger on
`agent_actions`. Blast radius: 2,109 of 2,828 rows un-updatable, including **20 of the 27 decisions
waiting on the founder**, oldest 9 Jul. The screen said "27 waiting, oldest 38 days" and twenty of
them could not be actioned at all. Nothing reported it — a raise inside a trigger surfaces only to
whoever tried, so the queue just never went down. See [[guarded-by-a-condition-that-cannot-occur]]
and [[select-into-no-rows-nulls-every-target]].

**Why:** the failure is invisible to every watcher, and it hides in the oldest rows because newer
inserts happened to populate the column the guard tests.

**How to apply:** declare scalars, not a record, whenever the assignment is conditional — a declared
scalar with no assignment is null, and null is a value. When a queue is not going down, try the
actual write path on its oldest row in an aborted transaction before believing the queue is merely
neglected.
