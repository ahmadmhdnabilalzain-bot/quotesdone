---
name: expenses-email-source-of-truth
description: "The founder forwards all receipts to expenses@quotesdone... — that inbox is the source of truth for expenses."
metadata: 
  node_type: memory
  type: reference
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-01T01:11:00.635Z
---

Founder, 1 Sep 2026: "all expenses are shared on the email btw. the one we made before
(expenses@quotesdone....) so that's the source of truth as i forward all receipts there."

So the authoritative upstream record of company expenses is the **expenses@quotesdone…** mailbox
(he forwards every receipt there), NOT any in-DB table by itself. In the database, expenses land in
the GL (`gl_account_balances` / `gl_journal` / `ap_bills`), which [[a-30-day-total-is-not-a-run-rate]]
and `fn_ws_finance` read. The email is the human feed UPSTREAM of the GL.

Founder, same day: "the revenue is basically from stripe. those are the only two sources for in and
out flows." So the company has exactly **two cashflow sources: Stripe (inflows/revenue) and the
expenses@ inbox (outflows/costs)**. The GL must reconcile to those two and nothing else.

**How to apply:** when building finance measurement/ingestion, treat the expenses inbox + Stripe as
the two sources that must reconcile into the GL. An email→GL ingestion connector is a separate
capability (needs a mail connector + parsing) and was explicitly out of scope for the
launch-readiness wiring pass; the in-DB reader is `fn_ws_finance`. Do not invent expense/revenue
numbers — reconcile to Stripe + that inbox. This is exactly why `break_even` and `cash_reserve` keep
a `no_measure_reason` ("numerator/denominator is a business decision") rather than a fabricated
measure_sql — the true opex/burn is not yet fully in-DB. Full address not stated verbatim (he wrote
"expenses@quotesdone…."); confirm the exact domain before wiring anything that reads/sends to it.
