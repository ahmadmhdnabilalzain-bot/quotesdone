# Brief: w1_final_review — fourth and FINAL independent review of the money-side workflow fix
Read `SP/briefs/COMMON.md` first. You are an INDEPENDENT reviewer; earlier reviewers are gone; their reviews are your map.
Worktree: /tmp/claude-0/review-w1-final from `origin/accountant-a-payment-is-known-booked-and-timed-from-the-moment-it-is-paid`
(head 5747d5f62). Local database: /tmp/pg-w1-final, port 55481.
Read: `SP/workflow/FIX_COMMON.md` (founder rulings 1685, 1687, 1688) and `SP/workflow/REPORT.md`; REVIEW.md sections
"WORKFLOW W1 MONEY 1/2/3"; the author's last account `SP/handbacks/W1_AUTHOR.md`; `supabase/functions/_shared/reveal_fee.ts`
(the customer pays the 3% fee and nothing else; Stripe's cost is our expense; we collect no VAT); `git diff origin/main...HEAD`.
Files: main SQL `scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid.sql`
+ probe; the owner file `the_it_engineer_closes_every_loop_it_opens.sql`; the index file
`the_it_loop_reads_handoffs_by_kind_type_and_sender_on_an_index_built_concurrently.sql`; the redact owner file
`every_handoff_note_states_context_decision_open_asks_and_deadline_and_its_receiver_cites_it.sql`; two FOUNDER-GATED files
never applied without his word (`the_company_recovers_no_input_vat_so_1150_is_moved_into_cost.sql`,
`the_ceo_may_let_the_accountant_return_an_overcharge_itself.sql`); runbook `docs/runbooks/a_paid_reveal_release_13_nov_2026.md`;
functions stripe_webhook, stripe_checkout, stripe_confirm, accountant, reveal_invoice, messages_api, supplier_api.
RULINGS THE BUILD MUST OBEY: Stripe's livemode alone decides real vs test (live always booked; live on a demo identity
booked AND flagged; test never touches the real ledger, invoice sequence or brief; unknown mode waits unbooked); no accrual
of Stripe's Invoicing fee; the dispute fee is booked; refunds at the amount refunded; one journal per event; the journal is
written BEFORE any notice and a failed notice never undoes it; a live sale with no journal never resolves silently, but one
that can never be booked (zero fee; fully refunded before Stripe's figures) ends as "nothing to book"; one window source
`fn_reveal_window` (five working days Mon–Fri skipping `public_holidays`, ending 23:59:59 Dubai); money charged above the
fee: the CEO's yes (or the founder's grant), NO second-seat review, the customer told only after the refund is actually
submitted, any failure goes back to the CEO as blocked.
VERIFY LOCALLY:
1. Apply main + owner + index + redact + 1150 files twice in a row (clean re-apply); run every probe.
2. Recompute by hand and compare the journals: normal domestic sale AED 777.60; a sale of exactly AED 135.00 with a month
   total ending .00; an international card; an overcharge of AED 38.77 and its return for a NON-demo customer end to end,
   then its three failure branches (decision refused, Stripe fails, refund cancelled: each hands back to the CEO, task
   'blocked'); full refund; partial refund; dispute opened/won/lost; refunded then disputed; zero-fee sale; a test-mode
   payment by a non-demo account; a live payment on a demo-flagged customer; a payment of unknown mode.
3. Replay: duplicate and out-of-order Stripe events and the hourly reconcile racing the webhook: one journal, one invoice
   number, one receipt per channel.
4. Eleven mutants of your own, one per ruling: caught by verdict / only by an error / survive.
5. `fn_handoff_redact`: nested objects, arrays, keys, numbers, numeric strings ("135.000000000" must stay), a phone and
   an e-mail inside a long note.
6. The "full refund before Stripe's figures" branch of nothing_to_book has no probe: test it.
7. Grants: `fn_reveal_window`, `fn_reveal_clock_start` service_role only; every new routine revoked from
   public/anon/authenticated; RLS + policy on `demo_shadow_trace` and `accountant_reveal_payment_check`.
8. THE REAL APPLY: the lock table of each file (statement, table, lock mode) with `lock_timeout = 1500ms`; that
   `scripts/apply_sql.mjs` sends a file as ONE transaction; read the runbook line by line against the code and correct it
   (order: main → owner → index (CONCURRENTLY, alone, outside a transaction, `indisvalid` checked) → deploy the seven
   functions → the sibling's file → the redact owner file → founder-gated files only on his word); what happens to a
   payment made between the apply and the deploy.
9. The sibling `origin/sales_engineer-a-paid-request-is-closed-and-everyone-on-it-is-told` (head 5acacfaf2): apply its SQL
   after these and run its probe: the last reviewer found it FAILS locally because `quote_quality_hold.accepted_md5` is NOT
   NULL with no default: confirm, and write the exact lines its probe must change; give that file's lock table too (it has
   no lock_timeout yet).
10. Deno suites of the seven functions and the money tests in `_shared`; the OFFLINE node checks on payments and
    hand-overs (never the production-replaying halves).
VERDICT: MERGE or FIX (numbered: file:line, scenario, smallest fix), most harmful first; the corrected release procedure;
the accounting choices for the founder in plain words; under 55 lines. Append the full review to `SP/show/REVIEW.md` under
"WORKFLOW W1 MONEY 4 (FINAL)".
