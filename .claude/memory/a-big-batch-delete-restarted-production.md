---
name: a-big-batch-delete-restarted-production
description: "21 Sep 17:44 UTC: a 50k-row purge batch scanned the whole 2.6M-row kb_chunks, the driver retried on top of it, memory passed 4 GB and production was hard-killed"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-21T18:09:52.084Z
---

Measured 21 Sep 2026: fn_kb_purge_batch(50000) switched from an id-index walk to a full seq scan (the planner guessed 6,989 matches), ran ~210 s per call, outlived the ~100 s API gateway (524), and the driver RETRIED on 5xx — starting another full-table delete while the first still ran. Committed memory passed 2.87 GB → ~4.2 GB on the Medium (4 GB) instance; Postgres was hard-killed and restarted (~2 min outage). Nothing was deleted.

**Why:** a gateway 524 does not mean the statement stopped; a retry on a long write stacks load. Batch size changes the plan, not just the duration.

**How to apply:**
- Never retry a long write on 5xx; cap each statement well under the gateway (~30 s).
- Measure a batch in a rolled-back transaction at several sizes and check EXPLAIN before running at scale.
- Bulk deletes run only at UAE night hours, with a load guard (WAL, free disk, active sessions) between batches.
- Statement-level export triggers multiply writes; for a purge force a full export instead of logging every id.
Related: [[an-apply-can-lock-sign-in]], [[an-edge-function-has-a-cpu-cap-a-deadline-does-not-bound]].
