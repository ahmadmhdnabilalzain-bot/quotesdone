-- EVERY SEAT READS ONE POOL, AND EVERY HAND-OVER COMES BACK. Seat: ceo. 13 Nov 2026, founder ledger 1688:
--   "there is like a shared pool where they all know what's going on around. So it can't be like the case where a sales
--    engineer is done verifying a customer or whatever, and then the IT is not aware of that ... everyone should know."
--
-- MEASURED ON PRODUCTION (read-only, 13 Nov 2026):
--   * company_event took 59,933 rows of 84 types in 30 days; 75 of the 84 are hand-over echoes (handoff.<kind>.<status>).
--     event_subscription had 0 rows, event_delivery 0, and the dispatcher had no schedule: it ran from a per-statement
--     trigger on company_event into the department-era org_tasks machinery, with nobody subscribed, so it delivered nothing.
--   * supplier.approved (12 in 30 days) is written with actor 'system'; nothing read it, so the it_engineer could not know
--     a supplier had been verified (the founder's own example).
--   * A seat's model context was the company brief, one person's case and fn_case_recall of similar past cases. No seat saw
--     what the OTHER seats did with the same customer, supplier or request, or what happened across the company today.
--   * 196 hand-overs open past their reply window (the audit said 208); 6 are due later (detail.due_at). EVERY ONE had
--     been answered by its receiver. What was open:
--       162 it.finding: the fault is still there (finding open), the it_engineer escalated each to the CEO (170 reports,
--           all 'accepted' = the founder e-mailed as a new bug), and the CEO's queue sweep relists them every day on a
--           "CEO queue overdue" task that nothing decides: the CEO's model path never sees its queue.
--       8 cleared it.finding wait for an incident's cause/fix/regression check (fn_it_loop_reverify, a human's part).
--       8 deliberation.review written by sales_engineer, marketing or customer_support: fn_ceo_closes_answered_handoffs
--           closes only deliberations the CEO wrote, so an author seat's reviewed deliberation had NO closer.
--       12 more (support.case_open, a lesson reapproval, ceo.root_cause, knowledge.request, ceo.revise): the seat or
--           the CEO owes the next move and nothing escalated it. 6 were not late at all (due_at in November).
--   * 15,110 hand-overs closed within 2 s by the receiving SQL; every one carries its outcome in evidence (verdict,
--     result, notification id, ...), but the SENDER had no reader of it.
--
-- WHAT THIS CHANGES:
--   1. event_subscription becomes the pool's data: per event type one OWNER seat and the seats that hear of it, and how
--      ('digest' = the company-today block; 'handover' = a hand-over that needs an answer; 'none' = said, with the reason).
--      Seeded for the 84 live types, the sales_engineer and accountant branches' new types, and this file's own.
--   2. fn_seat_pool_context(seat, subject, audience) is the ONE view every seat's model path reads: the subject's timeline
--      across seats (events, hand-overs and their outcomes, judgements; newest first, who/what/when/outcome) and, for an
--      internal audience, the company today (cached per window by fn_seat_pool_digest_build) plus "no answer yet from <seat>"
--      for this seat's own unanswered hand-overs. Hard cap 1,300 characters (about 300 tokens). Demo and real never mix.
--   3. fn_event_dispatch is no longer the department dispatcher: it files the 'handover' subscriptions through fn_seat_handoff,
--      once per (event, seat) in event_delivery. The trigger is dropped; one scheduled duty (ceo.company_pool, 15 min) runs
--      the digest, the dispatch, the overdue escalation and the author close. One mechanism.
--   4. fn_handoff_overdue_escalate: a hand-over past its window (due_at honoured) is escalated ONCE to the sender's superior
--      (public.org_reporting_edge); the CEO's own go to the founder's brief through fn_founder_brief_overdue_handoffs
--      (a separate function: fn_founder_brief is redefined on the accountant branch, which can call it).
--   5. fn_authors_close_reviewed_deliberations: the missing closer above, for a ceo_task deliberation whose task is done.
-- WHAT THIS DOES NOT CHANGE: fn_seat_handoff, the IT loop (the_it_engineer_closes_every_loop_it_opens.sql), the CEO's model
-- slot, and no hand-over kind's handler. Seeded 'handover' rows: none; every event that needs an answer already has a hand-over
-- filed by its producer (reveal.paid, sale.made, payment.exception ...). The founder can set one; the dispatch is tested.
-- prevented by: scripts/checks/every_seat_reads_one_pool.test.mjs, scripts/checks/every_report_and_handoff_comes_back.test.mjs

-- LOCKS, AND WHY THE APPLY STAYS SHORT: every table this file alters is empty or new (event_subscription 0 rows,
-- event_delivery 0, seat_pool_digest new); the added columns have constant defaults (no rewrite). The one lock on a busy
-- table is the trigger drop on company_event (ACCESS EXCLUSIVE, an instant catalogue change): lock_timeout makes the apply
-- fail fast and be re-run, rather than queue behind a writer and make every later writer queue behind it.
set local lock_timeout = '3s';

-- ── 0. THE DEPARTMENT DISPATCHER STOPS FIRST ───────────────────────────────────────────────────────────────────────
-- Before any subscription row exists: the old body (fn_event_dispatch -> org_tasks per department) ran from this
-- per-statement trigger on every company_event insert. With rows seeded and the old body still live it would mint
-- department tasks. The trigger goes; fn_event_dispatch is redefined below and runs from the ceo.company_pool duty.
drop trigger if exists trg_company_event_dispatch on public.company_event;
drop function if exists public.trg_company_event_dispatch();

-- ── 1. THE POOL IS OWNED: event_subscription is data the founder can edit ─────────────────────────────────────────
-- One row per (seat, event type). owns = this seat owns the type (exactly one per type). delivery = how THIS seat hears
-- of it: 'digest' (the company-today block), 'handover' (fn_event_dispatch files a hand-over of kind action_class from the
-- owner to this seat: only where the seat must act or judge), 'none' (said, with the reason). reason is never empty.
alter table public.event_subscription add column if not exists owns boolean not null default false;
alter table public.event_subscription add column if not exists delivery text not null default 'digest';
alter table public.event_subscription add column if not exists updated_at timestamptz not null default now();
alter table public.event_subscription drop constraint if exists event_subscription_delivery_is_known;
alter table public.event_subscription add constraint event_subscription_delivery_is_known
  check (delivery in ('digest', 'handover', 'none'));
alter table public.event_subscription drop constraint if exists event_subscription_says_why;
alter table public.event_subscription add constraint event_subscription_says_why check (nullif(btrim(reason), '') is not null);
alter table public.event_subscription drop constraint if exists event_subscription_handover_names_its_kind;
alter table public.event_subscription add constraint event_subscription_handover_names_its_kind
  check (delivery <> 'handover' or nullif(btrim(action_class), '') is not null);
create unique index if not exists event_subscription_one_owner on public.event_subscription (event_type) where owns;
alter table public.event_subscription enable row level security;
drop policy if exists event_subscription_service_role_only on public.event_subscription;
create policy event_subscription_service_role_only on public.event_subscription as permissive for all to public using (false) with check (false);
revoke all on public.event_subscription from anon, authenticated;
alter table public.event_delivery enable row level security;
drop policy if exists event_delivery_service_role_only on public.event_delivery;
create policy event_delivery_service_role_only on public.event_delivery as permissive for all to public using (false) with check (false);
revoke all on public.event_delivery from anon, authenticated;

-- The seed: my reading of each live type (full table and reasons: docs/architecture/the-office.md). 0 rows existed.
delete from public.event_subscription;
insert into public.event_subscription (event_type, agent_key, owns, delivery, reason) values
  ('customer.registered', 'sales_engineer', true, 'digest', 'a new customer is the start of customer intake (org_role: the sales engineer owns intake)'),
  ('customer.registered', 'customer_support', false, 'digest', 'the customer may write in next; support answers knowing he is new'),
  ('customer.registered', 'marketing', false, 'digest', 'registrations are the result marketing is measured on'),
  ('customer.registered', 'ceo', false, 'digest', 'a count the CEO reads every day'),
  ('deploy.completed', 'it_engineer', true, 'digest', 'the IT engineer watches what the estate runs; a deploy is an engineering fact'),
  ('handoff.ceo.decision_closed.done', 'accountant', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.ceo.decision_closed.sent', 'accountant', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.ceo.decision_owed.done', 'ceo', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.ceo.decision_owed.sent', 'ceo', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.ceo.decision_owed.waiting', 'ceo', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.ceo.directive.done', 'accountant', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.ceo.directive.sent', 'accountant', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.ceo.directive.waiting', 'accountant', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.ceo.improvement.done', 'accountant', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.ceo.improvement.sent', 'accountant', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.ceo.improvement.waiting', 'accountant', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.ceo.lesson_reapproval_overdue.sent', 'ceo', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.ceo.lesson_reapproval_overdue.waiting', 'ceo', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.ceo.month_directive.done', 'accountant', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.ceo.month_directive.sent', 'accountant', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.ceo.month_directive.waiting', 'accountant', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.ceo.revise.done', 'accountant', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.ceo.revise.sent', 'accountant', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.ceo.revise.waiting', 'accountant', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.ceo.root_cause.done', 'accountant', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.ceo.root_cause.sent', 'accountant', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.ceo.root_cause.waiting', 'accountant', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.deliberation.review.done', 'ceo', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.deliberation.review.reviewed', 'ceo', true, 'none', 'the reviewed echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.deliberation.review.sent', 'ceo', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.deliberation.review.waiting', 'ceo', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.delivery.request.done', 'customer_support', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.delivery.request.sent', 'customer_support', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.delivery.request.waiting', 'customer_support', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.delivery.result.done', 'accountant', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.delivery.result.sent', 'accountant', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.invite.reply.done', 'sales_engineer', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.invite.reply.sent', 'sales_engineer', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.invite.reply.waiting', 'sales_engineer', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.invoice.issued.done', 'sales_engineer', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.invoice.issued.sent', 'sales_engineer', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.it.finding.done', 'accountant', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.it.finding.sent', 'accountant', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.it.finding.waiting', 'accountant', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.knowledge.request.done', 'ceo', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.knowledge.request.sent', 'ceo', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.knowledge.request.waiting', 'ceo', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.mailbox.supplier_reply.done', 'sales_engineer', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.mailbox.supplier_reply.sent', 'sales_engineer', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.mailbox.supplier_reply.waiting', 'sales_engineer', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.marketing.report.done', 'ceo', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.marketing.report.sent', 'ceo', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.marketing.review.done', 'ceo', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.marketing.review.sent', 'ceo', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.nonresponse.charge_raised.done', 'sales_engineer', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.nonresponse.charge_raised.sent', 'sales_engineer', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.overdue.escalated', 'ceo', true, 'digest', 'a hand-over past its reply window, escalated once to the sender''s superior (this file)'),
  ('handoff.payment.exception.done', 'ceo', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.payment.exception.sent', 'ceo', true, 'none', 'a hand-over: the receiver already holds it as work; its answer reaches the sender through the sender''s subject timeline'),
  ('handoff.payment.exception.sent', 'sales_engineer', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.payment.exception.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.payment.exception.waiting', 'ceo', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.payment.unrecorded.done', 'it_engineer', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.payment.unrecorded.sent', 'it_engineer', true, 'none', 'a hand-over: the receiver already holds it as work; its answer reaches the sender through the sender''s subject timeline'),
  ('handoff.payment.unrecorded.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.payment.unrecorded.sent', 'sales_engineer', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.payment.unrecorded.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.payment.unrecorded.waiting', 'it_engineer', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.refund.paid.done', 'sales_engineer', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.refund.paid.sent', 'sales_engineer', true, 'none', 'a hand-over: the receiver already holds it as work; its answer reaches the sender through the sender''s subject timeline'),
  ('handoff.refund.paid.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.refund.paid.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.refund.request_checked.done', 'sales_engineer', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.refund.request_checked.sent', 'sales_engineer', true, 'none', 'a hand-over: the receiver already holds it as work; its answer reaches the sender through the sender''s subject timeline'),
  ('handoff.refund.request_checked.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.refund.request_checked.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.refund.request_checked.waiting', 'sales_engineer', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.refund.requested.done', 'accountant', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.refund.requested.sent', 'accountant', true, 'none', 'a hand-over: the receiver already holds it as work; its answer reaches the sender through the sender''s subject timeline'),
  ('handoff.refund.requested.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.refund.requested.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.refund.requested.waiting', 'accountant', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.report.five_numbers.done', 'ceo', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.report.five_numbers.sent', 'ceo', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.reveal.paid.done', 'sales_engineer', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.reveal.paid.sent', 'sales_engineer', true, 'none', 'a hand-over: the receiver already holds it as work; its answer reaches the sender through the sender''s subject timeline'),
  ('handoff.reveal.paid.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.reveal.paid.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.reveal.paid.waiting', 'sales_engineer', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.reveal.reconcile.done', 'accountant', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.reveal.reconcile.sent', 'accountant', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.reveal.reconcile.waiting', 'accountant', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.review.requested.sent', 'accountant', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.review.requested.waiting', 'accountant', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.sale.made.done', 'ceo', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.sale.made.sent', 'ceo', true, 'none', 'a hand-over: the receiver already holds it as work; its answer reaches the sender through the sender''s subject timeline'),
  ('handoff.sale.made.sent', 'sales_engineer', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.sale.made.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.sale.made.waiting', 'ceo', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.spec.not_sure.done', 'sales_engineer', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.spec.not_sure.sent', 'sales_engineer', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.spec.not_sure.waiting', 'sales_engineer', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.support.case_open.done', 'customer_support', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.support.case_open.sent', 'customer_support', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.support.case_open.waiting', 'customer_support', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.support.root_cause.done', 'accountant', true, 'none', 'the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('handoff.support.root_cause.sent', 'accountant', true, 'none', 'a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise'),
  ('handoff.support.root_cause.waiting', 'accountant', true, 'none', 'the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line)'),
  ('invoice.received', 'accountant', true, 'digest', 'an expense invoice is the accountant''s to capture and book'),
  ('invoice.received', 'ceo', false, 'digest', 'spend is a CEO number (break-even)'),
  ('quote.received', 'sales_engineer', true, 'digest', 'the sales engineer reads every quotation (hold gate, comparison)'),
  ('quote.received', 'customer_support', false, 'digest', 'the customer may ask about the quotation he just received'),
  ('quote.received', 'ceo', false, 'digest', 'quotations in is one of the day''s numbers'),
  ('request.reopened', 'sales_engineer', true, 'digest', 'the sales engineer reopens a paid request'),
  ('request.reopened', 'accountant', false, 'digest', 'a reopened request moves the refund window'),
  ('request.reopened', 'customer_support', false, 'digest', 'the customer may ask about the reopening'),
  ('request.reveal_outcome', 'sales_engineer', true, 'digest', 'the sales engineer closes a paid request (sales_engineer branch, 13 Nov)'),
  ('request.reveal_outcome', 'accountant', false, 'digest', 'the refund window runs from the payment; the accountant must know the request''s state'),
  ('request.reveal_outcome', 'customer_support', false, 'digest', 'the customer may ask what happens next'),
  ('request.reveal_outcome', 'ceo', false, 'digest', 'a sale''s outcome is a CEO number'),
  ('request.reveal_period_ended', 'sales_engineer', true, 'digest', 'the sales engineer ends the reveal period'),
  ('request.reveal_period_ended', 'accountant', false, 'digest', 'the refund window and the period end together'),
  ('request.reveal_period_ended', 'customer_support', false, 'digest', 'the customer may ask why he can no longer reveal'),
  ('request.reveal_period_ended', 'ceo', false, 'digest', 'a closed request is a CEO number'),
  ('request.step_failed', 'sales_engineer', true, 'digest', 'a step of a paid request failed; the sales engineer re-runs it'),
  ('request.step_failed', 'it_engineer', false, 'digest', 'a failed step is a fault; the sales_engineer branch also files an IT finding, so this is a digest line, not a second hand-over'),
  ('request.step_failed', 'ceo', false, 'digest', 'a failed step on a paid request is an exception the CEO should see'),
  ('rfq.classified', 'sales_engineer', true, 'digest', 'the sales engineer classified the request'),
  ('rfq.classified', 'customer_support', false, 'digest', 'the customer may ask where his request stands'),
  ('rfq.classified', 'ceo', false, 'digest', 'requests are one of the day''s numbers'),
  ('rfq.created', 'sales_engineer', true, 'digest', 'a customer request is the sales engineer''s to qualify and dispatch'),
  ('rfq.created', 'customer_support', false, 'digest', 'the customer may ask where his request stands'),
  ('rfq.created', 'ceo', false, 'digest', 'requests are one of the day''s numbers'),
  ('supplier.applied', 'sales_engineer', true, 'digest', 'a supplier application is the sales engineer''s to verify'),
  ('supplier.applied', 'customer_support', false, 'digest', 'the applicant may write in while he waits'),
  ('supplier.applied', 'marketing', false, 'digest', 'an application is the result of the supplier campaign'),
  ('supplier.applied', 'it_engineer', false, 'digest', 'registration is a surface the IT engineer certifies'),
  ('supplier.applied', 'ceo', false, 'digest', 'applications are one of the day''s numbers'),
  ('supplier.approved', 'sales_engineer', true, 'digest', 'the sales engineer verified the supplier''s licence and capability (org_role: supplier identity and capability verification)'),
  ('supplier.approved', 'it_engineer', false, 'digest', 'founder 1688: the IT engineer must know a supplier was verified (his portal, his alerts, his registration checks)'),
  ('supplier.approved', 'customer_support', false, 'digest', 'the supplier may write in next; support answers knowing he is approved'),
  ('supplier.approved', 'marketing', false, 'digest', 'an invited supplier who is approved is marketing''s conversion'),
  ('supplier.approved', 'ceo', false, 'digest', 'suppliers approved is one of the day''s numbers'),
  ('test.failed', 'it_engineer', true, 'digest', 'a scheduled check failed: the IT engineer diagnoses it (its own duties already read scheduled_run)');

-- ── 2. WHAT A SUBJECT IS, IN EVERY TABLE'S WORDS ──────────────────────────────────────────────────────────────────
-- A seat names its subject the way its own code does ({supplier_id}, {inquiry_id}, {table:'leads', id}). Events say
-- entity_type 'lead', hand-overs subject_table 'leads', judgements 'leads' or 'suppliers': one kind, several names.
create or replace function public.fn_pool_kind(p_name text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case
    when lower(coalesce(p_name, '')) in ('lead', 'leads', 'supplier', 'suppliers', 'supplier_id', 'lead_id') then 'supplier'
    when lower(coalesce(p_name, '')) in ('customer', 'customers', 'customer_id') then 'customer'
    when lower(coalesce(p_name, '')) in ('inquiry', 'inquiries', 'rfq', 'request', 'requests', 'inquiry_id', 'request_id', 'rfq_id') then 'inquiry'
    when lower(coalesce(p_name, '')) in ('quote', 'quotes', 'quote_id') then 'quote'
    when lower(coalesce(p_name, '')) in ('transaction', 'transactions', 'payment', 'payments', 'transaction_id', 'tx_id', 'payment_ref') then 'transaction'
    when lower(coalesce(p_name, '')) in ('refund', 'refunds', 'refund_requests', 'refund_id') then 'refund'
  end
$fn$;
revoke execute on function public.fn_pool_kind(text) from public, anon, authenticated;

create or replace function public.fn_pool_names(p_kind text)
returns text[] language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case p_kind
    when 'supplier' then array['lead', 'leads', 'supplier', 'suppliers']
    when 'customer' then array['customer', 'customers']
    when 'inquiry' then array['inquiry', 'inquiries', 'rfq', 'request']
    when 'quote' then array['quote', 'quotes']
    when 'transaction' then array['transaction', 'transactions', 'payment', 'payments']
    when 'refund' then array['refund', 'refunds', 'refund_requests']
    else array[]::text[] end
$fn$;
revoke execute on function public.fn_pool_names(text) from public, anon, authenticated;

-- the table name fn_seat_work_is_demo understands, for an event's entity_type
create or replace function public.fn_pool_table(p_entity_type text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case public.fn_pool_kind(p_entity_type)
    when 'supplier' then 'leads' when 'customer' then 'customers' when 'inquiry' then 'inquiries'
    when 'transaction' then 'transactions' when 'quote' then 'quotes' when 'refund' then 'refunds'
    else p_entity_type end
$fn$;
revoke execute on function public.fn_pool_table(text) from public, anon, authenticated;

create or replace function public.fn_pool_subject(p_subject jsonb)
returns table (kind text, id text) language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select distinct k.kind, k.id from (
    select public.fn_pool_kind(e.key) as kind, e.value #>> '{}' as id
      from jsonb_each(case when jsonb_typeof(p_subject) = 'object' then p_subject else '{}'::jsonb end) e
     where jsonb_typeof(e.value) in ('string', 'number')
    union all
    select public.fn_pool_kind(coalesce(p_subject->>'table', p_subject->>'subject_table')), coalesce(p_subject->>'id', p_subject->>'subject_id')
     where jsonb_typeof(p_subject) = 'object') k
   where k.kind is not null and nullif(btrim(k.id), '') is not null
   limit 6
$fn$;
revoke execute on function public.fn_pool_subject(jsonb) from public, anon, authenticated;

-- The reads below go by subject on three indexes built CONCURRENTLY, each in its own file applied BEFORE this one
-- (every_seat_reads_one_pool_index_*.sql): built inside this file's transaction they held a SHARE lock on company_event and
-- agent_actions for the whole apply, and live writers waited (a rehearsal on 13 Nov did exactly that).

-- ── 3. THE SUBJECT'S TIMELINE ACROSS SEATS ────────────────────────────────────────────────────────────────────────
-- Newest first, one line each: when (Dubai), who, what, outcome. Events (not the hand-over echoes: the hand-over row is
-- read directly, with its outcome), hand-overs either way, and the seats' recorded judgements. An event written by
-- 'system' is said in the name of its OWNER seat (event_subscription.owns): supplier.approved is the sales engineer's
-- verification. An external audience (a customer or supplier reply) gets the kinds and the states only: no payload text,
-- no name, so nothing about another party can reach a customer's or a supplier's prompt through this block.
create or replace function public.fn_seat_pool_timeline(p_seat text, p_subject jsonb, p_audience text default 'internal', p_limit integer default 6)
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
-- ARRAYS, NOT A JOIN TO A SET-RETURNING FUNCTION (measured in the rehearsal, 13 Nov): joined to fn_pool_subject the planner
-- assumed 1,000 subjects and scanned company_event whole, 715 ms a call; with = any(array) every read is an index probe.
declare v_ids text[]; v_names text[]; v_keys text[]; v_inq text[];
begin
  select coalesce(array_agg(distinct x.id), '{}'), coalesce(array_agg(distinct n.name), '{}'),
         coalesce(array_agg(distinct n.name || chr(31) || x.id), '{}'),
         coalesce(array_agg(distinct x.id) filter (where x.kind = 'inquiry'), '{}')
    into v_ids, v_names, v_keys, v_inq
    from public.fn_pool_subject(p_subject) x cross join lateral unnest(public.fn_pool_names(x.kind)) n(name);
  if cardinality(v_ids) = 0 then return ''; end if;
  return (
  with ext as (select coalesce(p_audience, 'internal') <> 'internal' as yes),
  seats as (select role_id from public.org_role where status = 'active'),
  ev as (
    select e.occurred_at as at,
           -- a seat by name; a person (an e-mail in actor) only as "the supplier" / "the customer", never the address;
           -- code ('system', 'route_inquiry', 'deploy_functions') in the name of the type's owner seat
           case when e.actor in (select role_id from seats) then e.actor
                when e.actor like '%@%' then 'the ' || coalesce(public.fn_pool_kind(e.entity_type), 'other party')
                else coalesce((select o.agent_key from public.event_subscription o where o.event_type = e.event_type and o.owns), 'system') end as who,
           e.event_type as what,
           nullif(concat_ws(' ', e.payload->>'company', e.payload->>'status', 'verified='||(e.payload->>'verified'),
                            e.payload->>'outcome', e.payload->>'state', e.payload->>'note'), '') as outcome,
           'recorded'::text as state
      from public.company_event e
     where e.entity_type = any (v_names) and e.entity_id = any (v_ids) and (e.entity_type || chr(31) || e.entity_id) = any (v_keys)
       and e.event_type not like 'handoff.%'
    union
    select e.occurred_at,
           case when e.actor in (select role_id from seats) then e.actor when e.actor like '%@%' then 'the other party'
                else coalesce((select o.agent_key from public.event_subscription o where o.event_type = e.event_type and o.owns), 'system') end,
           e.event_type,
           nullif(concat_ws(' ', e.payload->>'state', e.payload->>'outcome', e.payload->>'note'), ''), 'recorded'
      from public.company_event e
     where e.payload ? 'inquiry_id' and (e.payload->>'inquiry_id') = any (v_inq) and e.event_type not like 'handoff.%'),
  ho as (
    select a.created_at as at, coalesce(a.detail->>'from', 'system') as who,
           coalesce(a.detail->>'type', 'hand-over') || ' to ' || a.agent as what,
           case
             when a.status = 'done' then 'answered: ' || left(coalesce(a.evidence->>'verdict', a.evidence->>'outcome', a.evidence->>'result',
                    a.evidence->>'decision', a.evidence->>'reply', a.evidence->>'note',
                    case when a.evidence ? 'notification_id' then 'sent (notification ' || (a.evidence->>'notification_id') || ')' end, 'done'), 90)
             when a.status = 'failed' then 'FAILED: ' || left(coalesce(a.detail->>'error', 'no reason recorded'), 70)
             when a.detail ? 'replied_at' then 'answered, waiting on ' || left(coalesce(a.detail->>'awaiting', a.detail->>'from'), 60)
             when now() > coalesce(case when a.detail->>'due_at' ~ '^\d{4}-\d{2}-\d{2}' then (a.detail->>'due_at')::timestamptz end, a.created_at)
                          + coalesce(k.reply_within, interval '1 day')
               then 'NO ANSWER YET from ' || a.agent || ' since ' || to_char(a.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI')
             else 'open with ' || a.agent end
           || case when a.detail ? 'silence' then ' (escalated to ' || (a.detail->'silence'->>'escalated_to') || ')'
                   when a.detail ? 'escalated_report_id' then ' (escalated to the CEO)' else '' end as outcome,
           case when a.status = 'done' then 'answered' when a.status = 'failed' then 'failed' else 'open' end as state
      from public.agent_actions a
      left join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
     where a.kind = 'handoff' and (a.detail->>'subject_id') = any (v_ids)
       and (coalesce(a.detail->>'subject_table', a.target_table) || chr(31) || (a.detail->>'subject_id')) = any (v_keys)),
  jd as (
    select coalesce(j.decided_at, j.made_at) as at, j.seat as who, 'judged ' || j.surface as what,
           left(coalesce(j.decision, '') || coalesce(' -> ' || j.outcome, ''), 90) as outcome, 'decided' as state
      from public.seat_judgement j
     where j.subject_table = any (v_names) and j.subject_id = any (v_ids) and (j.subject_table || chr(31) || j.subject_id) = any (v_keys)
       and j.decision is not null),
  allx as (select * from ev union all select * from ho union all select * from jd order by at desc limit greatest(coalesce(p_limit, 6), 1))
  select coalesce(string_agg(
           left(regexp_replace(to_char(x.at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' ' || x.who || ': ' || x.what
             || case when (select yes from ext) then coalesce(' (' || x.state || ')', '')
                     else coalesce(' -- ' || x.outcome, '') end, '\s+', ' ', 'g'), 150),
           E'\n' order by x.at desc), '')
    from allx x);
end $fn$;
revoke execute on function public.fn_seat_pool_timeline(text, jsonb, text, integer) from public, anon, authenticated;

-- ── 4. THE COMPANY TODAY, COMPUTED ONCE PER WINDOW AND CACHED ─────────────────────────────────────────────────────
create table if not exists public.seat_pool_digest (
  seat text not null,
  scope text not null check (scope in ('real', 'demo')),
  built_at timestamptz not null default now(),
  window_from timestamptz not null,
  body text not null,
  counts jsonb not null default '{}'::jsonb,
  primary key (seat, scope));
comment on table public.seat_pool_digest is 'The company-today block each seat reads (fn_seat_pool_context), rebuilt by the ceo.company_pool duty every 15 minutes from company_event x event_subscription. Demo and real are separate rows: a rehearsal never reaches a real seat''s digest.';
alter table public.seat_pool_digest enable row level security;
drop policy if exists seat_pool_digest_service_role_only on public.seat_pool_digest;
create policy seat_pool_digest_service_role_only on public.seat_pool_digest as permissive for all to public using (false) with check (false);
revoke all on public.seat_pool_digest from anon, authenticated;

-- One pass over the last 24 hours of events some seat hears by digest; each event is classed demo or real ONCE
-- (fn_seat_work_is_demo, the same test fn_seat_handoff uses), then counted per seat. "Waiting on you" counts the live
-- hand-overs: unanswered ones addressed to the seat, answered ones it sent and still owes the close of, escalations sent
-- to it, and open promises due within a day. A demo digest carries no hand-over counts: ruling 1199 files none for demo.
create or replace function public.fn_seat_pool_digest_build(p_scope text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_scope text; v_n int := 0; v_t0 timestamptz := clock_timestamp();
begin
  for v_scope in select unnest(case when p_scope in ('real', 'demo') then array[p_scope] else array['real', 'demo'] end) loop
    with ev as materialized (
      select e.id, e.event_type, e.payload, e.occurred_at,
             public.fn_seat_work_is_demo(e.payload::text, e.payload, public.fn_pool_table(e.entity_type), e.entity_id) as demo
        from public.company_event e
       where e.occurred_at > now() - interval '24 hours'
         and exists (select 1 from public.event_subscription es where es.event_type = e.event_type and es.active and es.delivery = 'digest')),
    evs as (select * from ev where demo = (v_scope = 'demo')),
    seats as (select role_id as seat from public.org_role where status = 'active'),
    heard as (select es.agent_key as seat, e.* from evs e
                join public.event_subscription es on es.event_type = e.event_type and es.active and es.delivery = 'digest'),
    cnt as (select seat, jsonb_object_agg(label, n) as counts,
                   string_agg(n || ' ' || label, ', ' order by n desc, label) as line
              from (select seat, regexp_replace(event_type, '^handoff\.(.*)\.sent$', '\1') as label, count(*) as n
                      from heard group by 1, 2) c group by seat),
    notable as (select seat, string_agg(line, '; ' order by at desc) as line from (
                  select seat, occurred_at as at,
                         row_number() over (partition by seat order by occurred_at desc) as rn,
                         regexp_replace(event_type, '^handoff\.(.*)\.sent$', '\1')
                           || coalesce(' ' || left(coalesce(payload->>'company', payload->>'name', payload->>'subject_id'), 40), '')
                           || ' ' || to_char(occurred_at at time zone 'Asia/Dubai', 'HH24:MI') as line
                    from heard
                   where event_type ~ '^(supplier\.|request\.|handoff\.(reveal\.paid|refund\.|sale\.made|payment\.)|handoff\.overdue)') n
                 where rn <= 3 group by seat),
    open_to as (select a.agent as seat, count(*) as n, min(a.created_at) as oldest from public.agent_actions a
                 where v_scope = 'real' and a.kind = 'handoff' and a.status = 'pending' and not (a.detail ? 'replied_at') group by 1),
    owe as (select a.detail->>'from' as seat, count(*) as n from public.agent_actions a
              join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
             where v_scope = 'real' and a.kind = 'handoff' and a.status = 'pending' and a.detail ? 'replied_at' and k.originator_closes group by 1),
    esc as (select a.detail->'silence'->>'escalated_to' as seat, count(*) as n from public.agent_actions a
             where v_scope = 'real' and a.kind = 'handoff' and a.status = 'pending' and a.detail ? 'silence' group by 1),
    prom as (select p.owner_seat as seat, count(*) as n from public.support_case_promise p
              where p.status = 'open' and p.due_at < now() + interval '1 day' and p.is_demo = (v_scope = 'demo') group by 1)
    insert into public.seat_pool_digest as d (seat, scope, built_at, window_from, body, counts)
    select st.seat, v_scope, now(), now() - interval '24 hours',
           left(concat_ws(' ',
             'Last 24 h' || case when v_scope = 'demo' then ' (rehearsal traffic only)' else '' end || ': '
               || coalesce(c.line, 'nothing you follow happened') || '.',
             case when n.line is not null then 'Notable: ' || n.line || '.' end,
             case when coalesce(o.n, 0) + coalesce(w.n, 0) + coalesce(x.n, 0) + coalesce(p.n, 0) > 0 then
               'Waiting on you: ' || concat_ws('; ',
                 case when o.n > 0 then o.n || ' hand-over(s) unanswered, oldest since ' || to_char(o.oldest at time zone 'Asia/Dubai', 'DD Mon HH24:MI') end,
                 case when w.n > 0 then w.n || ' answered hand-over(s) you sent and have not closed' end,
                 case when x.n > 0 then x.n || ' overdue hand-over(s) escalated to you' end,
                 case when p.n > 0 then p.n || ' promise(s) to a customer due within a day' end) || '.' end), 700),
           jsonb_build_object('heard', coalesce(c.counts, '{}'::jsonb), 'unanswered_to_you', coalesce(o.n, 0), 'you_owe_close', coalesce(w.n, 0),
                              'escalated_to_you', coalesce(x.n, 0), 'promises_due', coalesce(p.n, 0))
      from seats st
      left join cnt c on c.seat = st.seat left join notable n on n.seat = st.seat left join open_to o on o.seat = st.seat
      left join owe w on w.seat = st.seat left join esc x on x.seat = st.seat left join prom p on p.seat = st.seat
    on conflict (seat, scope) do update set built_at = excluded.built_at, window_from = excluded.window_from,
                                            body = excluded.body, counts = excluded.counts;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('scopes', v_n, 'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end $fn$;
revoke execute on function public.fn_seat_pool_digest_build(text) from public, anon, authenticated;

-- ── 5. THE ONE VIEW EVERY SEAT'S MODEL PATH READS ─────────────────────────────────────────────────────────────────
-- Called by _shared/seat_pool.ts from think() (every seat's reasoning: replies, decisions, the CEO's reviews, the IT
-- postmortems) and from aiReply (customer and supplier replies). Never one model call per event: the digest is the cache
-- above; this reads it (building it inline only when no row exists yet) and the subject's timeline by index.
-- BUDGET (ruling 1619, the prompt diet): the block is cut at 1,300 characters, about 300 tokens; scripts/checks measures it.
create or replace function public.fn_seat_pool_context(p_seat text, p_subject jsonb default null, p_audience text default 'internal')
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_internal boolean := coalesce(p_audience, 'internal') = 'internal'; v_scope text := 'real';
        v_tl text := ''; v_today text; v_built timestamptz; v_wait text; v_block text;
begin
  if not exists (select 1 from public.org_role where role_id = p_seat and status = 'active') then
    return jsonb_build_object('seat', p_seat, 'block', '', 'chars', 0, 'reason', 'not a live seat');
  end if;
  if jsonb_typeof(p_subject) = 'object' and p_subject <> '{}'::jsonb then
    if public.fn_seat_work_is_demo(p_subject::text, p_subject) then v_scope := 'demo'; end if;
    v_tl := public.fn_seat_pool_timeline(p_seat, p_subject, p_audience, 6);
  end if;
  if v_internal then
    select d.body, d.built_at into v_today, v_built from public.seat_pool_digest d where d.seat = p_seat and d.scope = v_scope;
    if v_built is null then
      perform public.fn_seat_pool_digest_build(v_scope);
      select d.body, d.built_at into v_today, v_built from public.seat_pool_digest d where d.seat = p_seat and d.scope = v_scope;
    end if;
    -- THE SENDER IS NEVER BLIND: this seat's own hand-overs that nobody answered within their window, read live.
    if v_scope = 'real' then
      select string_agg('no answer yet from ' || q.agent || ' since ' || to_char(q.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI')
                        || ' (' || q.t || ' #' || q.id || coalesce(', escalated to ' || q.esc, '') || ')', '; ' order by q.created_at)
               || case when max(q.total) > 2 then ' (+' || (max(q.total) - 2) || ' more)' else '' end
        into v_wait
        from (select a.id, a.agent, a.created_at, a.detail->>'type' as t, a.detail->'silence'->>'escalated_to' as esc,
                     count(*) over () as total, row_number() over (order by a.created_at) as rn
                from public.agent_actions a
                left join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
               where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'from' = p_seat and a.agent <> p_seat
                 and not (a.detail ? 'replied_at')
                 and now() > coalesce(case when a.detail->>'due_at' ~ '^\d{4}-\d{2}-\d{2}' then (a.detail->>'due_at')::timestamptz end, a.created_at)
                             + coalesce(k.reply_within, interval '1 day')) q
       where q.rn <= 2;
    end if;
  end if;
  v_block := left(concat_ws(E'\n',
    case when coalesce(v_tl, '') <> '' then 'WHAT EVERY SEAT DID ON THIS SUBJECT (newest first):' || E'\n' || v_tl end,
    case when coalesce(v_today, '') <> '' then 'THE COMPANY TODAY (built ' || to_char(v_built at time zone 'Asia/Dubai', 'HH24:MI') || ' Dubai): ' || v_today end,
    case when coalesce(v_wait, '') <> '' then 'YOUR HAND-OVERS: ' || v_wait end), 1300);
  return jsonb_build_object('seat', p_seat, 'scope', v_scope, 'block', coalesce(v_block, ''), 'chars', length(coalesce(v_block, '')),
                            'timeline_lines', case when coalesce(v_tl, '') = '' then 0 else array_length(string_to_array(v_tl, E'\n'), 1) end,
                            'digest_built_at', v_built);
end $fn$;
revoke execute on function public.fn_seat_pool_context(text, jsonb, text) from public, anon, authenticated;
grant execute on function public.fn_seat_pool_context(text, jsonb, text) to service_role;

-- ── 6. THE DISPATCHER FILES ONLY WHAT MUST BE ANSWERED ────────────────────────────────────────────────────────────
-- Same name and signature, new body: no org_tasks, no departments. For each event whose type has a 'handover' row, the
-- owner seat files a hand-over of kind action_class to that seat through fn_seat_handoff (which runs the receiver's
-- handler, refuses a demo payload, and reports an unregistered kind as an IT finding). event_delivery records it once.
-- p_lookback_minutes <= 0 means the last day.
create or replace function public.fn_event_dispatch(p_lookback_minutes integer default 0)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; v_h bigint; n_filed int := 0; n_demo int := 0; n_failed int := 0;
begin
  for r in select e.id, e.event_type, e.entity_type, e.entity_id, e.payload, s.agent_key, s.action_class,
                  (select o.agent_key from public.event_subscription o where o.event_type = e.event_type and o.owns) as owner
             from public.company_event e
             join public.event_subscription s on s.event_type = e.event_type and s.active and s.delivery = 'handover'
             left join public.event_delivery d on d.event_id = e.id and d.agent_key = s.agent_key
            where d.id is null
              and e.occurred_at > now() - make_interval(mins => case when coalesce(p_lookback_minutes, 0) <= 0 then 1440 else p_lookback_minutes end)
            order by e.id limit 200 loop
    begin
      v_h := public.fn_seat_handoff(coalesce(r.owner, 'ceo'), r.agent_key, r.action_class,
               coalesce(public.fn_pool_table(r.entity_type), 'company_event'), coalesce(r.entity_id, r.id::text),
               coalesce(case when jsonb_typeof(r.payload) = 'object' then r.payload end, '{}'::jsonb)
                 || jsonb_build_object('event_id', r.id, 'event_type', r.event_type));
      insert into public.event_delivery (event_id, agent_key, event_type, result)
      values (r.id, r.agent_key, r.event_type, case when v_h is null then 'not filed: a demo event (ruling 1199)' else 'handoff ' || v_h end);
      if v_h is null then n_demo := n_demo + 1; else n_filed := n_filed + 1; end if;
    exception when others then
      insert into public.event_delivery (event_id, agent_key, event_type, unroutable_reason, closed_at)
      values (r.id, r.agent_key, r.event_type, left(sqlerrm, 300), now()) on conflict (event_id, agent_key) do nothing;
      n_failed := n_failed + 1;
    end;
  end loop;
  return jsonb_build_object('filed', n_filed, 'demo_not_filed', n_demo, 'failed', n_failed);
end $fn$;
revoke execute on function public.fn_event_dispatch(integer) from public, anon, authenticated;

-- ── 7. A HAND-OVER PAST ITS WINDOW IS ESCALATED ONCE ──────────────────────────────────────────────────────────────
-- Whoever owes the next move is the silent seat: the receiver when it has not replied, the sender when it was answered
-- and the kind is closed by its originator. The escalation goes to the SENDER's superior (public.org_reporting_edge, the
-- line fn_support_report_to_ceo reads); the CEO has none, so the CEO's own go to the founder's brief. ONCE: the row is
-- marked escalated with detail.silence; rows another loop already escalated (escalated_report_id from the IT loop or the
-- originators' sweep, escalated from fn_ceo_queue_work) are not escalated a second time. The window honours detail.due_at
-- (a month directive is due at month end), which the 208 of the audit did not.
create or replace function public.fn_handoff_overdue_escalate()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare h record; v_sup text; v_silent text; v_since timestamptz; n_seat int := 0; n_founder int := 0;
begin
  for h in select a.id, a.agent, a.detail, a.created_at, k.originator_closes,
                  coalesce(case when a.detail->>'due_at' ~ '^\d{4}-\d{2}-\d{2}' then (a.detail->>'due_at')::timestamptz end, a.created_at)
                    + coalesce(k.reply_within, interval '1 day') as due
             from public.agent_actions a
             left join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
            where a.kind = 'handoff' and a.status = 'pending' and not coalesce(a.escalated, false)
              and not (a.detail ? 'escalated_report_id') and not (a.detail ? 'silence')
              and a.created_at > now() - interval '60 days'
              and not coalesce((a.detail->>'demo')::boolean, false) and coalesce(a.title, '') not ilike '%ZZ DEMO%'
            order by a.id limit 100 loop
    if now() <= h.due then continue; end if;
    v_silent := case when h.detail ? 'replied_at' and coalesce(h.originator_closes, false) then h.detail->>'from' else h.agent end;
    v_since := case when h.detail ? 'replied_at' and (h.detail->>'replied_at') ~ '^\d{4}-\d{2}-\d{2}'
                    then (h.detail->>'replied_at')::timestamptz else h.created_at end;
    v_sup := null;
    select e.parent_role_id into v_sup from public.org_reporting_edge e
      join public.org_role r on r.role_id = e.parent_role_id and r.status = 'active'
     where e.child_role_id = h.detail->>'from';
    v_sup := coalesce(v_sup, 'founder');
    update public.agent_actions
       set escalated = true,
           escalation_reason = left('Past its reply window (due ' || to_char(h.due at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai): '
             || v_silent || ' owes the next move since ' || to_char(v_since at time zone 'Asia/Dubai', 'DD Mon HH24:MI')
             || '; escalated to ' || v_sup || ' (fn_handoff_overdue_escalate)', 500),
           detail = detail || jsonb_build_object('silence', jsonb_build_object(
             'silent_seat', v_silent, 'since', v_since, 'due', h.due, 'escalated_to', v_sup, 'escalated_at', now(),
             'owes', case when v_silent = h.agent then 'an answer' else 'the close of an answered hand-over' end))
     where id = h.id;
    insert into public.company_event (event_type, entity_type, entity_id, actor, payload, dedupe_key)
    values ('handoff.overdue.escalated', 'agent_actions', h.id::text, coalesce(h.detail->>'from', 'system'),
            jsonb_build_object('handoff_id', h.id, 'type', h.detail->>'type', 'from', h.detail->>'from', 'to', h.agent,
                               'silent_seat', v_silent, 'since', v_since, 'escalated_to', v_sup,
                               'subject_table', h.detail->>'subject_table', 'subject_id', h.detail->>'subject_id'),
            'handoff.overdue.escalated:' || h.id)
    on conflict (dedupe_key) where dedupe_key is not null do nothing;
    if v_sup = 'founder' then n_founder := n_founder + 1; else n_seat := n_seat + 1; end if;
  end loop;
  return jsonb_build_object('escalated_to_a_seat', n_seat, 'escalated_to_the_founder', n_founder);
end $fn$;
revoke execute on function public.fn_handoff_overdue_escalate() from public, anon, authenticated;

-- The CEO's own overdue hand-overs, as lines the founder's brief can print. A SEPARATE function on purpose: fn_founder_brief
-- is redefined on the accountant branch (13 Nov); that brief, or its next owner, calls this and prints what it returns.
create or replace function public.fn_founder_brief_overdue_handoffs(p_limit integer default 8)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    'count', (select count(*) from public.agent_actions a where a.kind = 'handoff' and a.status = 'pending'
               and a.detail->'silence'->>'escalated_to' = 'founder'),
    'lines', coalesce((select jsonb_agg(x.line order by x.since) from (
       select a.detail->'silence'->>'since' as since,
              (a.detail->>'type') || ' from ' || (a.detail->>'from') || ' to ' || a.agent || ' (#' || a.id || '): '
              || (a.detail->'silence'->>'silent_seat') || ' owes ' || (a.detail->'silence'->>'owes') || ' since '
              || to_char((a.detail->'silence'->>'since')::timestamptz at time zone 'Asia/Dubai', 'DD Mon HH24:MI') as line
         from public.agent_actions a
        where a.kind = 'handoff' and a.status = 'pending' and a.detail->'silence'->>'escalated_to' = 'founder'
        order by a.id limit greatest(coalesce(p_limit, 8), 1)) x), '[]'::jsonb));
$fn$;
revoke execute on function public.fn_founder_brief_overdue_handoffs(integer) from public, anon, authenticated;

-- ── 8. THE MISSING CLOSER: AN AUTHOR SEAT'S REVIEWED DELIBERATION ─────────────────────────────────────────────────
-- fn_ceo_closes_answered_handoffs closes a deliberation.review only when the CEO wrote the deliberation. Eight written
-- by sales_engineer, marketing or customer_support about a ceo_task waited with no closer at all (13 Nov). The author
-- closes it, by its rule, when the task it deliberated is done; the review's verdict travels into the close.
create or replace function public.fn_authors_close_reviewed_deliberations()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; n int := 0; v_err jsonb := '[]'::jsonb; v_rule text;
begin
  for r in select d.id as did, d.author_seat, a.id as hid, t.task_id, t.state, t.closed_at
             from public.agent_actions a
             join public.seat_deliberation d on d.id = (case when a.detail->>'subject_id' ~ '^[0-9]+$' then (a.detail->>'subject_id')::bigint end)
             join public.ceo_task t on t.task_id = (case when d.subject_id ~ '^[0-9]+$' then d.subject_id::bigint end)
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'deliberation.review'
              and a.detail ? 'replied_at' and d.author_seat <> 'ceo' and d.subject_table = 'ceo_task'
              and d.status in ('reviewed', 'no_independent_reviewer') and t.state = 'done'
              and not coalesce((a.detail->>'demo')::boolean, false)
            order by a.id limit 50 loop
    begin
      v_rule := 'the ceo_task ' || r.task_id || ' it deliberated is done'
                || coalesce(' since ' || to_char(r.closed_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI'), '');
      perform public.fn_seat_deliberation_close(r.did, r.author_seat, 'Review read; closed because ' || v_rule || '.');
      perform set_config('qd.handoff_closer', '', true);
      insert into public.originator_close_record (seat, handoff_id, handoff_type, rule, reading)
      values (r.author_seat, r.hid, 'deliberation.review', v_rule, jsonb_build_object('deliberation_id', r.did, 'task_id', r.task_id, 'state', r.state));
      n := n + 1;
    exception when others then
      v_err := v_err || jsonb_build_object('handoff', r.hid, 'error', left(sqlerrm, 300));
    end;
  end loop;
  return jsonb_build_object('closed', n, 'errors', v_err);
end $fn$;
revoke execute on function public.fn_authors_close_reviewed_deliberations() from public, anon, authenticated;

-- ── 9. ONE DUTY RUNS THE POOL ─────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_company_pool_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb := '{}'::jsonb;
begin
  begin v := v || jsonb_build_object('digest', public.fn_seat_pool_digest_build(null));
  exception when others then v := v || jsonb_build_object('digest_error', left(sqlerrm, 300)); end;
  begin v := v || jsonb_build_object('dispatch', public.fn_event_dispatch(0));
  exception when others then v := v || jsonb_build_object('dispatch_error', left(sqlerrm, 300)); end;
  begin v := v || jsonb_build_object('overdue', public.fn_handoff_overdue_escalate());
  exception when others then v := v || jsonb_build_object('overdue_error', left(sqlerrm, 300)); end;
  begin v := v || jsonb_build_object('authors_closed', public.fn_authors_close_reviewed_deliberations());
  exception when others then v := v || jsonb_build_object('authors_close_error', left(sqlerrm, 300)); end;
  return v;
end $fn$;
revoke execute on function public.fn_company_pool_tick() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.company_pool', 'ceo', interval '15 minutes', 'fn_company_pool_tick',
   'The shared pool: rebuild every seat''s company-today digest, file the hand-overs event_subscription asks for, escalate once every hand-over past its window, and close an author seat''s reviewed deliberation whose task is done.',
   'scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;
