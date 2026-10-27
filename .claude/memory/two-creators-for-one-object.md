---
name: two-creators-for-one-object
description: fn_kernel_workflow_start and fn_kernel_step_complete both created the same handoff run; ask which OTHER routine also creates this object.
metadata: 
  node_type: memory
  type: project
  originSessionId: d03d8dc0-fc44-4c8d-9d4f-dcc32e8613c6
  modified: 2026-08-17T00:13:19.805Z
---

`fn_kernel_workflow_start` block (e) created the entry step's **outgoing** handoff run at start
time; `fn_kernel_step_complete` created the same edge again when that step actually completed. Two
open handoff runs on one registry edge. Accepting the second is refused forever ("already has a
live step run"), so the run sits in `waiting_handoff` and its workflow can never close. **16 of 30**
entry steps carry an outgoing edge.

Found 17 Aug 2026 by *driving a run end to end* in an aborted transaction, not by any of the 25
watchers. Production showed 7 handoff runs, 0 duplicated edges, 0 runs waiting — zero because no
run had ever completed an entry step with an outgoing edge. See
[[a-rehearsal-proves-creation-not-execution]] and [[guarded-by-a-condition-that-cannot-occur]].

**Why:** the author knew and wrote it in a comment — "the hash is over what actually exists at
start: the trigger, not a work product". The answer to "there is no output to hash" is not "hash
the trigger instead", it is that there is no handoff yet.

**How to apply:** for any object the kernel creates, grep for every routine that inserts into that
table and ask whether two of them can fire for the same key. Fix by deletion — leave the creator
that has the real evidence to record. Fixed in `scripts/sql/kernel_k14_start_does_not_pre_hand_off.sql`,
generated from the live `prosrc` so nothing but that block could move.
