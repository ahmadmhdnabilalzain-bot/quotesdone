W1_W2_FIX hand-back (13 Nov 2026). [L]=local PG16 /tmp/pg-w1w2:55511 (now deleted), [R]=code/offline. No production write, rehearsal, deploy, apply, merge or PR. No model or Stripe call.
Heads: MONEY accountant-a-payment-is-known-booked-and-timed-from-the-moment-it-is-paid = ea9c25c62 (7 commits on 5747d5f62). SALES sales_engineer-a-paid-request-is-closed-and-everyone-on-it-is-told = 75f60e2d3 (1 commit on 5acacfaf2). Both worktrees were removed.
All commits carry `accountant:`/`sales_engineer:` as briefed. The redact file belongs to the it_engineer, but its fix was committed as `accountant:`.

MONEY. Every item is DONE. File = main a_paid_reveal_is_reconciled_..._paid.sql; its probe = P.
1 DONE: main fn_refund_request_hands_to_accountant (z30) now has `and NEW.reason_code is distinct from 'overcharge_return'`. P section E runs fn_seat_handoff_act on every open hand-over of the payment, 4 rounds. Before stripe_refund_id it asserts 0 customer deliveries, after it exactly 1. The fixture has no e-mail, so the old chain cannot write the message itself. P therefore also asserts there is no refund.requested or refund.request_checked hand-over for the return. Mutant N01 is caught by that assertion only.
2 DONE: the 1150 loop is now fn_accountant_moves_input_vat_into_cost(), with `and j.source <> 'vat_input_reclass'`. It is revoked from public, anon and authenticated. Its probe runs it a second time and asserts it posted 0 journals and every balance is unchanged. The unfixed loop fails the probe: 27→54 journals, 1150 0→284.41.
3 DONE: fn_reveal_nothing_to_book is now "refunded in full AND no reveal_fee journal". fn_gl_post_reveal_fee returns null when that holds. In fn_gl_sync_business 1b, an unbooked sale's refund books only Stripe's stripe_fee_fils, and waits (`continue`) while it is unknown; the estimate is removed in both union branches. An open dispute keeps the check open with the CEO. a10 lets a check close when nothing_to_book holds. P section G: full dashboard refund before the figures → nothing_to_book, nothing booked before the figures; then refund_paid 6100 34.48/1050; then a dispute → 1100, never a 4000 line or a reveal_fee journal. M14 (new text) and 3 variants are caught.
4 DONE: fn_payment_check_returns_difference: the request and the check update are inside the begin/exception block. A rolled-back refund id is cleared. P section I: a00 refuses the return through fn_reason_apply_ceo__payment_exception. Result: no raise, a blocked task with the guard's reason, occurrence 2, a new CEO hand-over, the old one done.
5 DONE: scripts/checks/every_alarm_is_quiet_on_a_healthy_day.test.mjs gains relay entries for fn_accountant_reconciles_reveal, fn_notifications_the_same_message_is_sent_once (its own insert-guard cancellation) and fn_refund_settle (new refund:unbooked: finding). The sweep's entry now states the holiday-calendar finding from 4 Dec 2026. Whole file offline: 8 pass, 0 fail, 4 production tests skipped (base: 7/1).
6a DONE: a new decision closes the earlier blocked task on the same payment (P section E, step 2).
6b DONE: the payment's advisory lock ('reveal_invoice_no:'||tx) is taken before the check row in snapshot, reconcile, gl_post_reveal_fee, escalate, returns_difference, return_blocked, both reason_apply routines, z59, z60-close, dispute, and two sweep loops. [L] race, 7 sessions × 150 calls (snapshot, reconcile, webhook, gl_sync, sweep): old code 524 deadlock lines, new code 0. Both left exactly 1 journal.
6c DONE: fn_refund_settle matches a refund with no transaction by PaymentIntent or charge, sets transaction_id and the transactions refund fields, and re-matches on later events. With no match it raises an accountant finding refund:unbooked:<id>. 1b and nothing_to_book also match by PaymentIntent. P sections G and J: matched, booked (6900 100.00), and the unmatched finding.
6d DONE (redact file): colliding keys keep both values ("[email] (2)"). 00 may take one space or dash and needs 10–14 digits after it. Numbers under a contact key, or of 11–15 digits (not 13 starting with 1), are redacted. "PO 0012345678" is left alone. Probe g2; every_handoff_note_is_cited check 6/0. The redact probe fails on the old function.
6e DONE: fn_reveal_invoice_number returns null for a zero fee (P section F). reveal_invoice answers 409 zero_fee_no_invoice (EN/AR); invoiceIsDue has a test.
6f DONE: the grant file sets lock_timeout 1500ms.
7 DONE: runbook. No probe on production. Order: main → owner → index alone (check indisvalid; if false, drop concurrently and re-run) → deploy 7 → parity → sibling SQL → its functions → redact → founder-gated files. Timing rule. The apply-to-deploy gap is described. The main pending note is updated.
PROVE [L]: all six money files applied twice; main P, redact and 1150 probes all PROBE OK. Mutants: 10 new all caught. Of the review's 15, the 14 that still apply are caught (M08 now by verdict); M14 is replaced by N03. deno [R]: stripe_webhook 11/0, stripe_checkout 11/0, accountant 53/0, reveal_invoice 17/0, messages_api 3/0, supplier_api 244/0, _shared money tests (19 files) 132/0; deno check reveal_invoice passes. node offline [R], 53 payment/hand-over files: 164 pass, 12 fail (all in the gaps check, 5/12, fixture-based and identical at base), 43 skipped. One more file, the refund-ladder .probe.mjs, needs a production token and was not run.

SALES. Every item is DONE.
1: the probe's quality-hold insert is the review's exact text. 2: lock_timeout 1500ms. 3: z33 and a05 are CREATE OR REPLACE TRIGGER; the check asserts this and that there is no drop. 4: the quotes CHECK is added NOT VALID, then VALIDATE runs separately. 5 [L]: applied twice after the money files: sibling PROBE OK, all three money probes still OK. Check 9/0. inquiry_lifecycle.ts untouched.

LOCKS (strong locks each file holds to commit; one transaction per file, measured locally):
main 82ms: AccessExclusive on transactions, stripe_dispute, refunds, accountant_reveal_reconcile_item, accountant_reveal_payment_check, demo_shadow_trace; Share on gl_journal, reveal_invoices (unique indexes).
owner 70ms: agent_actions ShareRowExclusive (in-place trigger), seat_handoff_kind AccessExclusive.
index: agent_actions ShareUpdateExclusive, CONCURRENTLY, alone.
redact 52ms: agent_actions AccessExclusive (CHECK NOT VALID, no scan) + ShareRowExclusive.
1150 48ms / grant 54ms: row locks only.
sibling 59ms: inquiries AccessExclusive (ADD COLUMN); quotes AccessExclusive (ADD CHECK NOT VALID, DROP NOT NULL) + ShareRowExclusive (triggers); request_reveal_outcome (new). It no longer locks transactions.
All files now set lock_timeout 1500ms.

UNSURE:
(a) Inside one file, the sibling's separate VALIDATE saves nothing: the ADD's AccessExclusive is held until commit anyway. quotes has 5 rows.
(b) Item 1 is proved through the hand-over chain, not an actual e-mail. No probe identity can carry a non-demo address.
(c) The redact shape rule hides an 11–15 digit number anywhere in a hand-over, and "ref 0012345678901" is now taken for a phone.
(d) refund:unbooked findings are not closed automatically when a later event matches the refund.
(e) The legacy 1b branch (refund recorded only on the transaction) now also waits for Stripe's fee.
(f) The sibling's deploy list is broad: every function importing reveal_guard, stated_price or line_specs. Its author should name it.
