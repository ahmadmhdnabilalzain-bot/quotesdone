---
name: reading-who-you-are-must-not-create-it
description: Delete a row and watch whether it comes back — an endpoint that auto-vivifies its own subject makes cleanup futile and hands accounts to identities that should not have them.
metadata: 
  node_type: memory
  type: project
  originSessionId: 4ca61bec-f10b-4b3c-a015-46d98c25918e
  modified: 2026-08-13T21:39:04.618Z
---

13 Aug 2026. `customer_api` opened every request with
`if (!cust) insert({ email })`, so **any authenticated identity that read the endpoint became a
customer**. Found not by reading code but by deleting the duplicate
`management@quotesdone.com` row at 20:30 and seeing a NEW one at 21:01:05 — different id,
`full_name` null, the exact shape of that insert.

**The lens: after you delete something, look again later.** A cleanup that does not stick means a
writer you have not found. "Which line could have written this row?" is answerable from the row's
own shape — nulls everywhere except the one column the insert names.

The fallback was redundant on the legitimate path (`login_otp` already inserts on verify, and a
customer JWT can only come from `mintSession` there), so all it still did was serve the case it
must not: staff sessions acquiring buyer accounts by loading a page. Now 403 `No customer profile`,
matching what `stripe_checkout`/`stripe_confirm` already answer.

Related: [[a-phone-may-confirm-never-select]] — the same session, same subject. A buyer account
under the company's own admin address is what made that defect read as "wrong e-mail" instead of
"wrong account".

**And the harness was wrong before the code was.** See the `qd-cust-auth` trap now in SKILL.md §7:
the hand sign-in recipe sets two keys and the Supabase client persists a third, so a reload restores
the previous account. That looked like a product account-mixup bug and was not one. Cf.
[[harness-seeds-an-order-reality-cannot-produce]].
