W1 round 4 is done and pushed to accountant-a-payment-is-known-booked-and-timed-from-the-moment-it-is-paid: ca42e051c (accountant:), then 5747d5f62 (it_engineer:). No pull request, nothing applied or deployed. Tags: [L] local Postgres, [R] repo/offline, [P] SELECT-only production read. No rehearsal touched production.

1. Overcharge return:
   - fn_refund_decide skips fn_high_stakes_gate for `overcharge_return` and nothing else; the CEO's approval or the grant is still needed.
   - The CEO's task stays 'working' after the decision. New trigger z59 on refunds closes it, with the Stripe refund id as evidence, and files the customer notice only once `stripe_refund_id` is set and status is processing or succeeded.
   - Any failure (decision refused or raised, Stripe failed or cancelled) runs fn_payment_check_return_blocked: task set to 'blocked' with the reason (a new blocked task if the old one is already done), unsubmitted refund cancelled, CEO decision cleared, CEO asked again as a new occurrence.
   - Probe E [L] uses a non-demo fixture with no contact details at all (any example/invalid address counts as demo). It covers: refused → blocked and handed back; approved → second seat skipped, customer notified only after submission; Stripe failure → handed back.
2. Locks:
   - lock_timeout 1500ms in the main, owner, 1150 and redact files.
   - All DROP+CREATE triggers are now CREATE OR REPLACE TRIGGER, z61 included.
   - The two NOT VALID+VALIDATE pairs are one plain ADD each.
   - The owner file's index moved to the new `the_it_loop_reads_handoffs_by_kind_type_and_sender_on_an_index_built_concurrently.sql` (CONCURRENTLY, with a pending note). Production already has it [P].
3. The sibling's file is untouched.
4. fn_handoff_redact (redact owner file, it_engineer):
   - It walks the value: keys and string values are redacted at any depth; numbers, booleans and null come back untouched. Patterns are in a new helper, fn_handoff_redact_text.
   - Both phone patterns now carry `(?<![0-9.])`.
   - Canonical check: production md5 matched the file applied locally [P][L] for every routine except fn_handoff_citation_gaps, which MANIFEST line 2149 supersedes; it is removed from this file.
   - Probe section g covers keys, nesting, arrays, numbers and numeric strings. The HEAD file and 4 mutants are caught [L]. The citation check is updated and passes [R].
5. nothing_to_book is a terminal verdict for a zero fee, or a full refund before Stripe's figures:
   - a10 lets it close, and the CEO sees a done ceo_task.
   - It drops out of the hourly re-read and the "not yet booked" brief line, and gets its own brief line.
   - Probe F tests the zero-fee case only; the full-refund branch has no probe.
   - fn_reveal_window and fn_reveal_clock_start are now service_role only.
6. Runbook: `docs/runbooks/a_paid_reveal_release_13_nov_2026.md`, indexed in the runbooks README. It has the timing, the pg_stat_activity read, the retry rule, checks per step, and the order: main → owner → index → deploy 7 → sibling → redact → founder-gated. It states 1 tx / 4 quotes / 4 inquiries / 215 gl_journal; my later read showed 5 quotes [P].

Verification:
- Main + owner + 1150 + redact files in one rolled-back transaction: all three probes PROBE OK [L].
- All files applied for real twice in a row (clean re-apply), then the probes alone: PROBE OK [L].
- Mutants: 11 of 11 caught [L], including M10 (second seat applied to an overcharge return) and M11 (customer told before submission). M1, M7 and M11 were caught by an error rather than a probe verdict.
- Deno suites: stripe_webhook 11, accountant 53, stripe_checkout 11, reveal_invoice 16, messages_api 3, supplier_api 244, all OK; _shared 2267 OK [R]. The one _shared failure was timed_fetch, which only needs network permission; it passes with it. stripe_confirm has no tests.
- Offline node checks pass [R]. About 110 production-reading checks failed with 401 identically at HEAD and were not run.

For the local seed I added `org_agents`; the sequences also had to be advanced past the seeded ids. The local cluster and the worktree are deleted.