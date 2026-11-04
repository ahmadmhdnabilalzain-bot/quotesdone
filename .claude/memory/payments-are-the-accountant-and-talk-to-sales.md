---
name: payments-are-the-accountant-and-talk-to-sales
description: "Founder 14 Sep 2026 — every payment path is the accountant's; accountant and sales engineer hand off both ways; only the sales engineer speaks in the portals"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-14T11:08:41.688Z
---

Founder, 14 Sep 2026: "anything related to payment is under the accountant agent. and the accountant need to be in
communication back and forth with the sales agent. its one company eventually."
Same day: "its always the sales agent. no other agent is involved in customer or supplier portal."

- Payment paths (reveal checkout/confirm/webhook, Stripe invoices, refunds, non-response charges, supplier
  subscription/dues) → owner `accountant` in function_owner and actor columns. Refunds still need the CEO.
- Customer/supplier-facing words in either portal → `sales_engineer` only ("QuotesDone sales engineer").
- Two-way handoffs through the estate's existing inter-seat mechanism, recorded: e.g. reveal paid → accountant
  files invoice → sales engineer tells the customer; customer asks about a charge → sales engineer → accountant.
- OTP/auth/role_guard are platform services, not agents.
- CEO refund approval (14 Sep): verifies every step; on failure REJECTS WITH REASONS → remediation tasks to the
  accountant/sales engineer → they act and report back → CEO re-checks → approves only when all green; loops
  repeat; after 3 cycles/overdue → founder WhatsApp summary. On a post-execution mismatch: pause refunds,
  incident, fix by type, re-check, founder summary.
- Inner loop (14 Sep): the sales engineer asks customer_support (who owns channel delivery) to deliver the chase/
  final-call messages and watch for the supplier's reply; support returns PROOF OF RESPONSE or NO-RESPONSE
  CONFIRMATION with delivery evidence; that evidence feeds the CEO checklist. Loops nest: CEO ⇄ accountant/sales,
  sales ⇄ support, support ⇄ supplier.
- 14 Sep: "the only agent who uses the whatsapp and email is the customer support agent. so he should be always
  up to date" — every outbound WhatsApp/email (incl. CEO founder summaries) is a delivery request to
  customer_support via the outbox; support reads a live per-contact case timeline. OTP = platform service.

**Why:** one company — money is the accountant's job, the customer relationship is sales'.
**How to apply:** new payment code gets accountant ownership + a handoff to sales for anything the customer sees.
Related: [[payments-are-held-for-the-accountant-agent]], [[sales-and-support-divide-by-surface-and-by-truth]],
[[refunds-belong-to-the-ceo]].
