---
name: work-after-the-response-never-ran
description: "An edge function's cleanup handed to EdgeRuntime.waitUntil after the response did not execute at all (dr_drill, 234,047 rows untouched); do state-changing work before answering, bounded per statement, and move bulk clears server-side (one bounded DELETE per pass)"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-03T23:28:19.874Z
---

dr_drill (3 Sep 2026 version) wrote its verdict, returned the response, and deleted its own
234,047 staging rows in a fire-and-forget promise handed to `EdgeRuntime.waitUntil`. On 4 Sep the
table still held every one of those rows: the after-response work never ran, and the next drill
would have met the residue, run out of pre-clear passes and called its own verdict untrustworthy
(exactly what run 43341 reported on 3 Sep: "cleared 200000 row(s) in 200 passes and 34047 still
remain").

**Why:** a promise that runs after the response has no proof of execution — no row, no log the
check reads — so "the drill cleans up after itself" was a claim ([[connected-is-a-claim-not-a-measurement]]).
The measurement is `select count(*) from dr_restore` after the run. The PostgREST route was also
the wrong tool for bulk deletes: every select is capped at 1,000 rows regardless of `.limit`, and
the authenticator role carries `statement_timeout=8s`, so a JS loop of select/delete pairs reaches
40,000 rows in 40 passes while one drill leaves ~234,000.

**How to apply:** in an edge function, do state-changing housekeeping BEFORE `return`, bounded per
statement, and read the effect back. For bulk deletes write one SQL routine that deletes up to N
rows chosen by ctid under the load-bearing predicate (fn_dr_restore_clear: 20,000 rows in 1.4s)
and loop on it from the function until it returns 0. Keep the predicate (age cutoff or run_id) so
a concurrently running chain's rows survive — TRUNCATE races the check-then-act guard.
