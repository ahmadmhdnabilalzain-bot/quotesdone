---
name: a-502-can-commit-after-the-count-that-cleared-the-retry
description: "10-11 Nov 2026: a management-API insert answered HTTP 502 while its transaction was still running; a count read 0, the guarded retry inserted a second 129-row GlockApps seed batch, and 6 duplicates were sent before it was seen"
metadata:
  type: feedback
  modified: 2026-11-11
---

**What happened (it_engineer, GlockApps test 2026-11-10-21:29:37:367t, founder ledger 1617).** The seed insert (one
statement, 129 `notifications` rows, kind `invite_m365_seed`) went through `scripts/lib/db.mjs` and answered
**HTTP 502 "upstream request failed"**. A count straight after it read **0 rows**, so the same statement was sent again.
That one was guarded with `not exists` on (address, marker), and it also answered 502. Both transactions then committed:
batch A at 21:30:57Z (ids 137248-137376) and batch B at 21:31:39Z (ids 137377-137505). The guard could not see A because
A had not committed yet when B began. A verification query run moments later still showed one batch of 129. B committed
after it.

It was found four hours later, when a count by marker read 258. By then 6 B rows were sent; two seeds had two copies,
and the other four had queued A copies. 123 queued B rows and the 4 redundant A rows were cancelled, each with a
`last_error` that says why.

**Rule:**
- **A 502 or 524 from the management API is "unknown", not "failed".** The statement may still be running, so a count
  of 0 straight after it proves nothing. Retrying a non-idempotent write on a 5xx was already forbidden
  (`quotesdone-apply-discipline` §9, 21 Sep). A `not exists` guard does NOT make it safe: two transactions that
  overlap cannot see each other's rows.
- **Wait, then count by the business key, twice, a minute apart, before any retry.** For a mail insert, the key is
  (address, marker), not an id range you assumed.
- **Better: give a batch insert a natural unique key** (e.g. `dedupe_key = '<test id>:<address>'`). The database then
  refuses the duplicate, whatever the timing.
- **Watch progress by the business key, never by the id range of the rows you think you inserted.** The watcher here
  tracked ids 137248-137376 and could not see batch B.

Related: [[the-invitation-gate-reads-the-glockapps-verdict]], [[a-status-column-is-not-a-delivery-record]]
