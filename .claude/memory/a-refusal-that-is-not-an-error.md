---
name: a-refusal-that-is-not-an-error
description: "A BEFORE trigger returning NULL refuses the row without raising; PostgREST answers 201 with no row, so `if (!error)` counts the refusal as a success."
metadata: 
  node_type: memory
  type: project
  originSessionId: 951680f6-998d-4578-b818-e62f587f57e4
  modified: 2026-08-15T02:17:37.115Z
---

A Postgres `BEFORE INSERT` trigger that `return null` **refuses the row and raises nothing**.
PostgREST answers **201 with no row**, so `supabase-js` gives back `{ data: null, error: null }`.

Any caller shaped like `if (!error) { inserted++ }` therefore counts a deliberate refusal as a
successful write.

Found 15 Aug 2026 in `dispatch_inquiry`: `a00_unsafe_match_eligibility` re-validates each supplier
at assignment (banned / matching_blocked / permanently_closed / expired licence) and refuses by
returning null. The dispatcher counted those as notified, so `routing.fanout` over-reported the
RFQ's reach — and because `fn_rfq_redispatch_sweep` only retries a fanout **recorded as 0**, an RFQ
whose every match was refused looked dispatched and could never be retried.

**How to detect it:** `select ... from pg_proc` for trigger functions containing `return null`, then
grep their tables' writers for `if (!error)`.

**The fix is one call:** `.insert(...).select('id')` and count `rows.length`, not the absence of an
error. Keep the refusals — they are the exclusion ledger, and "why did this one not get it" is
usually the question being asked.

Same family as [[instruments-report-on-the-wrong-subject]] and
[[error-and-empty-must-not-return-the-same-value]]: two different outcomes collapsing into one
indistinguishable value.
