# Brief: w1_w2_fix — round 5 of the money-side workflow fix, and the small fix of its sibling
Read `SP/briefs/COMMON.md` first. You are the FIX author on TWO branches (two worktrees, one local database):
- MONEY: `accountant-a-payment-is-known-booked-and-timed-from-the-moment-it-is-paid` (head 5747d5f62), worktree
  /tmp/claude-0/fix-w1-r5, commit prefix `accountant:`.
- SALES: `sales_engineer-a-paid-request-is-closed-and-everyone-on-it-is-told` (head 5acacfaf2), worktree
  /tmp/claude-0/fix-w2-r2, commit prefix `sales_engineer:`.
Local database: /tmp/pg-w1w2, port 55511.
Read: `SP/workflow/FIX_COMMON.md` (rulings); the LAST TWO sections of `SP/show/REVIEW.md` about "WORKFLOW W1 MONEY 4
(FINAL)" (the review and its re-verification of this evening: exact lines, exact SQL text for the sibling's probe);
scenario outputs in `SP/w1f/`; the runbook `docs/runbooks/a_paid_reveal_release_13_nov_2026.md` on the money branch.

## MONEY branch: every item is decided; do them all
1. An approved overcharge return must NOT tell the customer anything before Stripe holds the refund. In
   `fn_refund_request_hands_to_accountant` add `and NEW.reason_code is distinct from 'overcharge_return'`; the probe runs
   `fn_seat_handoff_act` on the payment's hand-overs and asserts NO customer delivery.request exists before
   `stripe_refund_id` is set, and exactly one after.
2. `the_company_recovers_no_input_vat_so_1150_is_moved_into_cost.sql` must be safe to apply twice (it reversed itself:
   54 reclass journals, 1150 back to 284.41): add `and j.source <> 'vat_input_reclass'`; its probe applies the file's body
   twice and asserts the same balances.
3. A sale refunded in full before Stripe's figures arrive: "nothing to book" must mean refunded in full with NO
   reveal_fee journal; `fn_gl_post_reveal_fee` returns null there; only Stripe's own fee is booked when Stripe reports
   it; a later dispute on that sale books NO revenue. Add the missing probe (the reviewer's mutant M14 must now be caught).
4. A guard refusal of the return is handed back to the CEO: move lines :904-908 inside the begin/exception block at :912
   so the task ends 'blocked' and the CEO's decision is not lost. Probe it.
5. The check `every_alarm_is_quiet_on_a_healthy_day` test #5: add the REGISTER/relay entry for
   `fn_accountant_reconciles_reveal`, AND the entry origin/main itself lacks (`fn_notifications_the_same_message_is_sent_once`:
   read what that routine does and register it truthfully). Run the whole check file.
6. Smaller, all to do:
   a. when the CEO records a new decision, the earlier blocked task on the same payment is closed (one open task);
   b. lock order: the advisory lock is taken BEFORE the check row is locked, everywhere (no deadlock between the
      webhook path and the hourly reconcile);
   c. a refund made in the Stripe dashboard (no transaction_id on the event): match it by payment_intent/charge to the
      transaction and book it like any refund; when no match exists, hand it to the accountant as an unbooked refund
      (never silent). Probe both;
   d. `fn_handoff_redact`: keys that collide are not collapsed; "00 971 50 123 4567" is redacted; "PO 0012345678" is
      NOT redacted; a phone stored as a JSON number is redacted;
   e. a zero-fee reveal takes NO invoice number and produces no invoice (an invoice for AED 0 is not an invoice);
   f. `the_ceo_may_let_the_accountant_return_an_overcharge_itself.sql` gets `set local lock_timeout = '1500ms'`.
7. The runbook: correct it as the review says (no probe is ever run on production: lines 72, 138, 144; line 116; line
   148), and state the order: main → owner → index (CONCURRENTLY, alone; check indisvalid; if false drop concurrently and
   re-run) → deploy the seven functions → verify parity → the sibling's SQL → its functions → redact → founder-gated
   files only on his word; timing rule (not 21:30–23:30 UTC, not minutes :08/:23/:38/:53, pg_stat_activity first, retry
   3 × 30 s); what happens to a payment made between apply and deploy.
PROVE (LOCAL): all files applied twice; every probe OK; the reviewer's 15 mutants re-run where you touched (M14 caught,
M08 caught by verdict if cheap); deno suites of stripe_webhook, stripe_checkout, accountant, reveal_invoice,
messages_api, supplier_api and the `_shared` money tests; the offline node checks on payments and hand-overs.

## SALES branch
1. The probe `scripts/sql/a_paid_reveal_closes_the_request_and_everyone_on_it_is_told_probe.sql` lines 59-60: the insert
   into `quote_quality_hold` sets `supplier_id` and `accepted_md5 = public.fn_quote_quality_content_md5(q)` taken from
   quotes (exact text is in REVIEW.md). 2. `set local lock_timeout = '1500ms'` at the top of the SQL file.
3. :383-384 and :408-409 become CREATE OR REPLACE TRIGGER. 4. :88-89: add the CHECK as NOT VALID, then VALIDATE
   CONSTRAINT in a separate statement (short lock). 5. Apply AFTER the money branch's files locally, twice; probe OK;
   the money probes still OK after it.
Do NOT touch `supabase/functions/customer_api/actions/inquiry_lifecycle.ts` (another branch changes it first).

Push small commits to each branch; progress notes in `SP/progress/w1_w2_fix.md`.
HAND-BACK (under 50 lines; also to `SP/handbacks/W1_W2_FIX.md`): each item DONE (file:line, probe/test) / NOT DONE (why);
probe and test counts; both heads; the lock table of each SQL file for the real apply; what you are unsure of.
