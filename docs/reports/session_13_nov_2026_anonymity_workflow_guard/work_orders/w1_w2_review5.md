# Brief: w1_w2_review5 — independent review of round 5 of the money side and the sales side's small fix
Read `SP/briefs/COMMON.md` first. You are an INDEPENDENT reviewer; you wrote none of this.
Worktrees: /tmp/claude-0/review-w1-r5 from `origin/accountant-a-payment-is-known-booked-and-timed-from-the-moment-it-is-paid`
(head ea9c25c62; round 5 = the 7 commits after 5747d5f62) and /tmp/claude-0/review-w2-r2 from
`origin/sales_engineer-a-paid-request-is-closed-and-everyone-on-it-is-told` (head 75f60e2d3; 1 commit after 5acacfaf2).
Local database: /tmp/pg-w1w2-rev, port 55531.
Read: `SP/workflow/FIX_COMMON.md` (rulings 1685, 1687, 1688); REVIEW.md "WORKFLOW W1 MONEY 4 (FINAL)" and its
"re-verification" (the five FIX items and 6a–f that round 5 answers); the author's account `SP/handbacks/W1_W2_FIX.md`;
the work order it was given `SP/briefs/w1_w2_fix.md`; `git diff 5747d5f62..ea9c25c62` and `git diff 5acacfaf2..75f60e2d3`.
VERIFY LOCALLY (money files in the runbook's order, then the sales file; everything twice):
1. Each of items 1–5, 6a–6f and the runbook (7): DONE-AND-PROVEN / NOT, by your own run, not the author's probe alone.
   For item 1 walk the overcharge return yourself for a NON-demo customer row you seed locally: at which exact moment is
   anything addressed to the customer created (delivery.request, notification row, hand-over to customer support)?
   It must be only after `stripe_refund_id` is set. Then the three failure branches.
2. Item 3 by hand: a sale refunded in full before Stripe's figures; then the figures arrive; then a dispute opens, is
   lost; and separately is won. Write the journals you expect first, then compare. No 4000 line, ever.
3. Item 6b: re-run a race of your own (webhook path × hourly reconcile × sweep, 6+ sessions): deadlocks, journals = 1,
   invoice numbers = 1.
4. Item 6c: a dashboard refund with no transaction id: matched by PaymentIntent, by charge, unmatched (finding raised);
   a later event that matches: is the earlier `refund:unbooked` finding closed or left open forever (author's unsure d)?
   If left open, that is a FIX (a finding nobody can close is noise the CEO learns to ignore): give the smallest fix.
5. Item 6d: `fn_handoff_redact`: the author's unsure (c): an 11–15 digit number anywhere is hidden, "ref 0012345678901"
   is taken for a phone. Try 30 values a hand-over really carries (Stripe ids pi_/ch_/re_, invoice numbers QD-INV-…,
   inquiry and quote ids, amounts in fils like 77760, 13-digit epoch milliseconds, order references, IBAN, a UAE phone
   in six spellings, an e-mail). List every wrong hide and every miss; a wrong hide of an id a seat needs is a FIX.
6. Item 6e: zero-fee reveal: no number, no invoice, the customer's page says something true (read reveal_invoice's 409
   text and where the portal shows it).
7. New since round 4: `fn_accountant_moves_input_vat_into_cost` (founder-gated): safe twice, revoked, balances by hand.
8. The author's unsure (e): the legacy branch (refund recorded only on the transaction) now waits for Stripe's fee: can
   a refund then stay unbooked forever when Stripe never reports a fee (a test-mode or zero-fee charge)? Seed it and see.
9. 10 mutants of your own on round 5's changes: caught by verdict / only by an error / survive.
10. THE REAL APPLY: your own lock table per file from pg_locks (the author's is in the hand-back: main takes ACCESS
    EXCLUSIVE on transactions, refunds, stripe_dispute for ~80 ms): with `lock_timeout 1500ms`, what does a live payment
    webhook arriving during those 80 ms experience (it waits; is its own statement_timeout long enough; is the webhook
    idempotent if Stripe retries)? Read the runbook line by line once more against the code.
11. The sales file: applied after the money files, twice; probe OK; money probes still OK; its lock table; the
    author's note (a) that VALIDATE in the same transaction saves nothing: is the simplest right form used?
    Its DEPLOY LIST (author's unsure f): derive it from the import graph: every function whose bundle changes on the
    sales branch, and the same for the money branch; give both lists exactly.
12. Suites: deno stripe_webhook, stripe_checkout, stripe_confirm, accountant, reveal_invoice, messages_api,
    supplier_api, quote_extract, supplier_portal, the `_shared` money and line_specs tests; the offline node checks on
    payments, refunds, hand-overs and `every_alarm_is_quiet_on_a_healthy_day`.
VERDICT per branch: MERGE or FIX (numbered: file:line, scenario, smallest fix), most harmful first; the final release
steps for both; what the founder must decide, in plain words; under 55 lines. Append the full review to
`SP/show/REVIEW.md` under "WORKFLOW W1 MONEY 5 AND W2 SALES 4". Progress notes: `SP/progress/w1_w2_review5.md`.
Delete your cluster and worktrees at the end.
