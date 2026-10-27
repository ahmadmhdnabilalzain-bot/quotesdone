---
name: clearing-a-queue-releases-its-own-suppression
description: "Deleting or closing escalations does NOT clear them — every raiser dedupes on \"is an open row present\", so clearing releases the suppression and 36 of 27 items returned on the next cron cycle."
metadata: 
  node_type: memory
  type: project
  originSessionId: 0f302c30-995c-49f2-be5e-72182155ebd1
  modified: 2026-08-16T05:59:06.797Z
---

Measured 16 Aug 2026 when the founder asked to wipe escalation history. Every raiser in this
codebase — `leg_flag()`, `sec_incident()`, the agents' `queue()` and the rest — dedupes on
*"is an open row already present"*. **Deleting or closing an open row RELEASES that suppression.**
Proved by deleting all 27 founder-queue rows and re-running five of the 186 active cron jobs in one
aborted transaction: 7 came straight back; over the full cycle, 36.

A destructive clear-out also fails three other ways here: `decision_log` is append-only by trigger
with 721 dependent `agent_actions` rows; **18 routines use `public.notifications` as their own
send-dedupe**, so wiping it re-sends real customer email; and it drops `fn_os_portals_gates` from
23/23 to 20/23 with evidence collapsing to "0 of 0".

The working mechanism is a **dated watermark** (`public.os_fresh_start` + `fn_os_fresh_start_at()`)
that the surfaces read forward from. Nothing deleted, no gate moved, reversible. Re-raise then
becomes the feature: stale conditions stay gone, live ones re-appear.
See [[a-list-with-no-third-answer]] and [[guarded-by-a-condition-that-cannot-occur]].

**Why:** "clear the queue" sounds like a data operation and is actually a suppression operation.
The rows are not the state — the open-row predicate is.

**How to apply:** before clearing any queue, find what the raiser dedupes on and force one cron
cycle in an aborted transaction. Also count the surfaces first — this OS had **eight**, not the
three that were known, so patching three leaves boards still showing last month.
