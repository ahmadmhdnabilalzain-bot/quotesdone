---
name: an-apply-can-lock-sign-in
description: A long SQL apply locked the login table for 75 s on 21 Sep and signed a real customer out; freeze applies during a campaign hour
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-21T16:52:26.633Z
---

Measured 21 Sep 2026 10:04 UTC: a 75-second SQL apply held a lock that login routines needed; sign-in returned 12 time-out errors, and a real customer on Chrome at 10:05 waited ~35 s and was told they were signed out (the edge functions turned "auth did not answer" into 401 — fixed by the signed_in_user helper, PR #785).

**Why:** an apply that touches or rewrites routines used by sign-in (or holds a lock on leads/auth-adjacent tables) blocks every sign-in for its whole duration.

**How to apply:**
- No SQL applies during a campaign or launch hour. Batch them before or after.
- A long apply (the purge, big rewrites) runs outside UAE business hours.
- Before any apply in a busy window, check pg_stat_activity for sign-in traffic.
Related: [[two-applied-prs-deadlock-each-others-database-check]].
