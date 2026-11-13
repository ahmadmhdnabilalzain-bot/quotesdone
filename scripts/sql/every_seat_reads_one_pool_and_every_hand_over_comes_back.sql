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
--   * The CEO DECIDED NOTHING: its reply to an it.finding was fn_seat_answers_it_finding, one line of SQL ("acknowledged ...
--     no deterministic remedy", replied_at = created_at); app_secrets has no ceo_model_slot row, so ceo_agent's judgement
--     returns "skipped"; the CEO's only model work was scheduled reviews and a knowledge quiz (think.answer: 323 on 19 Oct,
--     6 on 27 Oct, 5 on 1-2 Nov, then none). 216 it.finding open, 105 to the CEO.
--
-- WHAT THIS CHANGES (second iteration, after the review of 13 Nov):
--   1. THE CEO JUDGES. The it.finding hand-over to the CEO no longer gets a code acknowledgement: fn_ceo_takes_it_finding
--      leaves it to the CEO's model. One duty (ceo.company_pool) files at most N a tick, under a DAILY CAP held as data
--      (decision_policy 'ceo_daily_judgements': 30 a day, AED 0.50), a held question on surface ceo.it_finding with four
--      fixed choices; the existing replay (resilience_ping -> think() on the seat's routine route, the model hold and the
--      demo rules as for every held question) reasons it, and fn_reason_apply_ceo__it_finding writes the decision on the
--      hand-over where the it_engineer reads it and files the it_engineer's next step as a hand-over (ceo.decision_closed).
--   2. ESCALATION IS WORK: a hand-over past its window (due in the WHERE) is escalated once; to the CEO as a held question
--      on surface ceo.overdue_handoff (chase / wait / needs the founder), to the founder (the CEO's own) by one deduplicated
--      e-mail a day through fn_notify_founder. The silent seat is the one that owes the next move.
--   3. ONE SUBJECT RESOLVER (fn_pool_keys): a hand-over or an event is linked to every subject it is about (transaction ->
--      request, customer, supplier; quote -> request, supplier; support_case -> its party; notification -> its person ...)
--      in public.subject_link, filled by triggers and back-filled in batches. The timeline reads it; an external reader sees
--      only its OWN rows in neutral words; the actor printed is the one recorded, else "the platform (automatic)".
--   4. THE BLOCK IS ORDERED BY IMPORTANCE: your hand-overs, then the subject, then the company today, inside 1,200
--      characters (the TS header makes it at most 1,300). The context never builds the digest; the digest is incremental.
--   5. THE SEED: owners are the seats that PRODUCE each type; every type has an audience or "nobody: <reason>"; a re-run
--      never overwrites a row someone edited; request.step_failed and supplier.applied file a hand-over (event.act).
--   6. A REVIEWED DELIBERATION closes only on an agreeing verdict; a revise or reject goes back to its author as work.
-- WHAT THIS DOES NOT CHANGE: fn_seat_handoff and the IT loop (owned by the money-side branch), so an it.finding is still
-- CLOSED by the it_engineer (its originator) when its fault clears; fn_founder_brief (the same branch: the two lines it
-- should add are in docs/runbooks/apply-the-shared-pool.md).
-- prevented by: scripts/checks/every_seat_reads_one_pool.test.mjs, scripts/checks/every_report_and_handoff_comes_back.test.mjs,
-- supabase/functions/_shared/seat_pool.test.ts, supabase/functions/_shared/ceo_judges_it_findings.test.ts
--
-- LOCKS: the tables this file alters are empty or new; added columns are nullable or constant-default (no rewrite). The
-- statements on busy tables (the link triggers on company_event and agent_actions, the old trigger's drop) are the LAST
-- statements, so their locks are held only for the commit; lock_timeout makes the apply fail fast and be re-run rather than
-- queue writers behind it. No index is built on a busy table: the pool reads its own subject_link and primary-key ranges.
set local lock_timeout = '1500ms';

-- ── 1. THE POOL IS OWNED: event_subscription is data the founder can edit ─────────────────────────────────────────
-- One row per (seat, event type). owns = this seat PRODUCES the type (exactly one per type). delivery = how THIS seat hears
-- of it: 'digest' (the company-today block), 'handover' (fn_event_dispatch files a hand-over of kind action_class from the
-- owner to this seat: only where it must act), 'none' (said, with the reason). edited_by is null while a row is as seeded;
-- any other write stamps it, and a re-run of this file never overwrites a stamped row.
alter table public.event_subscription add column if not exists owns boolean not null default false;
alter table public.event_subscription add column if not exists delivery text not null default 'digest';
alter table public.event_subscription add column if not exists updated_at timestamptz not null default now();
alter table public.event_subscription add column if not exists edited_by text;
alter table public.event_subscription drop constraint if exists event_subscription_delivery_is_known;
alter table public.event_subscription add constraint event_subscription_delivery_is_known check (delivery in ('digest', 'handover', 'none'));
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

create or replace function public.trg_event_subscription_marks_an_edit()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  new.updated_at := now();
  if coalesce(current_setting('qd.pool_seed', true), '') <> 'on' then
    new.edited_by := coalesce(nullif(current_setting('qd.edited_by', true), ''), session_user);
  end if;
  return new;
end $fn$;
revoke execute on function public.trg_event_subscription_marks_an_edit() from public, anon, authenticated;
drop trigger if exists trg_event_subscription_marks_an_edit on public.event_subscription;
create trigger trg_event_subscription_marks_an_edit before insert or update on public.event_subscription
  for each row execute function public.trg_event_subscription_marks_an_edit();

-- The seed (full table and reasons: docs/architecture/the-office.md). MERGED, never wiped: a row someone edited stays as
-- they left it; an unedited row takes the seed's reading; a missing row is added.
create temp table pool_seed (event_type text, agent_key text, owns boolean, delivery text, reason text) on commit drop;
insert into pool_seed (event_type, agent_key, owns, delivery, reason) values
  ('customer.registered', 'sales_engineer', true, 'digest', 'intake is the sales engineer''s (org_role); the customer registers himself'),
  ('customer.registered', 'customer_support', false, 'digest', 'he may write in next; support answers knowing he is new'),
  ('customer.registered', 'marketing', false, 'digest', 'registrations are what marketing is measured on'),
  ('customer.registered', 'ceo', false, 'digest', 'a number the CEO reads every day'),
  ('customer.registered', 'accountant', false, 'none', 'nobody: a registration moves no money'),
  ('customer.registered', 'it_engineer', false, 'none', 'nobody: sign-up faults reach IT as findings, not as this event'),
  ('deploy.completed', 'it_engineer', true, 'digest', 'the IT engineer watches what the estate runs'),
  ('deploy.completed', 'ceo', false, 'none', 'nobody: an engineering fact; a failed deploy reaches him as a finding'),
  ('test.failed', 'it_engineer', true, 'digest', 'a scheduled check failed; IT diagnoses it (its duties read scheduled_run)'),
  ('test.failed', 'ceo', false, 'none', 'nobody: IT files a finding when it matters'),
  ('quote.received', 'sales_engineer', true, 'digest', 'the sales engineer reads every quotation (hold gate, comparison)'),
  ('quote.received', 'customer_support', false, 'digest', 'the customer may ask about it'),
  ('quote.received', 'ceo', false, 'digest', 'quotations in is a daily number'),
  ('quote.received', 'accountant', false, 'none', 'nobody until it is paid (reveal.paid)'),
  ('invoice.received', 'accountant', true, 'digest', 'an expense invoice is the accountant''s to capture and book'),
  ('invoice.received', 'ceo', false, 'digest', 'spend is a CEO number (break-even)'),
  ('supplier.approved', 'sales_engineer', true, 'digest', 'supplier verification is the sales engineer''s (org_role); the row is written by code (fn_emit_supplier_approved, actor system), so the timeline says who approved only when it is recorded'),
  ('supplier.approved', 'it_engineer', false, 'digest', 'founder 1688: IT must know a supplier was approved (his portal, his alerts)'),
  ('supplier.approved', 'customer_support', false, 'digest', 'the supplier may write in next'),
  ('supplier.approved', 'marketing', false, 'digest', 'an invited supplier approved is marketing''s conversion'),
  ('supplier.approved', 'ceo', false, 'digest', 'suppliers approved is a daily number'),
  ('supplier.applied', 'sales_engineer', true, 'handover', 'the sales engineer verifies the application; a hand-over makes the verification owed, not a duty that may skip it (the sales engineer verifies every application)'),
  ('supplier.applied', 'customer_support', false, 'digest', 'the applicant may write in while he waits'),
  ('supplier.applied', 'marketing', false, 'digest', 'an application is the campaign''s result'),
  ('supplier.applied', 'it_engineer', false, 'digest', 'registration is a surface IT certifies'),
  ('supplier.applied', 'ceo', false, 'digest', 'applications are a daily number'),
  ('rfq.classified', 'sales_engineer', true, 'digest', 'the sales engineer classified the request'),
  ('rfq.classified', 'customer_support', false, 'digest', 'the customer may ask where it stands'),
  ('rfq.classified', 'ceo', false, 'digest', 'requests are a daily number'),
  ('rfq.created', 'sales_engineer', true, 'digest', 'a request is the sales engineer''s to qualify and dispatch'),
  ('rfq.created', 'customer_support', false, 'digest', 'the customer may ask where it stands'),
  ('rfq.created', 'ceo', false, 'digest', 'requests are a daily number'),
  ('rfq.created', 'marketing', false, 'digest', 'demand is what marketing is measured on'),
  ('request.reveal_outcome', 'sales_engineer', true, 'digest', 'the sales engineer closes a paid request (sales_engineer branch)'),
  ('request.reveal_outcome', 'accountant', false, 'digest', 'the refund window runs from the payment'),
  ('request.reveal_outcome', 'customer_support', false, 'digest', 'the customer may ask what happens next'),
  ('request.reveal_outcome', 'ceo', false, 'digest', 'a sale''s outcome is a CEO number'),
  ('request.reveal_period_ended', 'sales_engineer', true, 'digest', 'the sales engineer ends the reveal period'),
  ('request.reveal_period_ended', 'accountant', false, 'digest', 'the refund window and the period end together'),
  ('request.reveal_period_ended', 'customer_support', false, 'digest', 'the customer may ask why he can no longer reveal'),
  ('request.reveal_period_ended', 'ceo', false, 'digest', 'a closed request is a CEO number'),
  ('request.reopened', 'sales_engineer', true, 'digest', 'the sales engineer reopens a paid request'),
  ('request.reopened', 'accountant', false, 'digest', 'a reopened request moves the refund window'),
  ('request.reopened', 'customer_support', false, 'digest', 'the customer may ask about it'),
  ('request.reopened', 'ceo', false, 'digest', 'a reopened sale is an exception the CEO should see'),
  ('request.step_failed', 'sales_engineer', true, 'handover', 'the sales engineer re-runs the failed step of a paid request; a hand-over makes it work with a deadline, not a count (a step of a paid request failed and the sales engineer must re-run it)'),
  ('request.step_failed', 'it_engineer', false, 'digest', 'a failed step is a fault (the branch also files a finding)'),
  ('request.step_failed', 'ceo', false, 'digest', 'a failed step on a paid request is an exception'),
  ('handoff.overdue.escalated', 'ceo', true, 'digest', 'a hand-over past its window, escalated once to the sender''s superior (this file); the CEO decides it (ceo.overdue_handoff)'),
  ('handoff.overdue.escalated', 'it_engineer', false, 'none', 'nobody: the IT engineer reads its own overdue hand-overs in YOUR HAND-OVERS'),
  ('handoff.adspend.booked.sent', 'accountant', true, 'none', 'the one seat that sends adspend.booked; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.adspend.booked.sent', 'marketing', false, 'none', 'marketing holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.adspend.booked.waiting', 'accountant', true, 'none', 'the one seat that sends adspend.booked; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.adspend.booked.waiting', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.adspend.booked.done', 'accountant', true, 'none', 'the one seat that sends adspend.booked; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.adspend.booked.done', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.adspend.booked.failed', 'accountant', true, 'digest', 'the one seat that sends adspend.booked; a failed hand-over is the sender''s to re-send'),
  ('handoff.adspend.booked.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.adspend.recorded.sent', 'marketing', true, 'none', 'the one seat that sends adspend.recorded; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.adspend.recorded.sent', 'accountant', false, 'none', 'accountant holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.adspend.recorded.waiting', 'marketing', true, 'none', 'the one seat that sends adspend.recorded; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.adspend.recorded.waiting', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.adspend.recorded.done', 'marketing', true, 'none', 'the one seat that sends adspend.recorded; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.adspend.recorded.done', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.adspend.recorded.failed', 'marketing', true, 'digest', 'the one seat that sends adspend.recorded; a failed hand-over is the sender''s to re-send'),
  ('handoff.adspend.recorded.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.backup.refile.sent', 'it_engineer', true, 'none', 'the one seat that sends backup.refile; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.backup.refile.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.backup.refile.waiting', 'it_engineer', true, 'none', 'the one seat that sends backup.refile; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.backup.refile.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.backup.refile.done', 'it_engineer', true, 'none', 'the one seat that sends backup.refile; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.backup.refile.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.backup.refile.failed', 'it_engineer', true, 'digest', 'the one seat that sends backup.refile; a failed hand-over is the sender''s to re-send; nobody else: the IT engineer is the owner and watches its own faults'),
  ('handoff.backup.remediate.sent', 'ceo', true, 'none', 'the one seat that sends backup.remediate; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.backup.remediate.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.backup.remediate.waiting', 'ceo', true, 'none', 'the one seat that sends backup.remediate; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.backup.remediate.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.backup.remediate.done', 'ceo', true, 'none', 'the one seat that sends backup.remediate; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.backup.remediate.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.backup.remediate.failed', 'ceo', true, 'digest', 'the one seat that sends backup.remediate; a failed hand-over is the sender''s to re-send'),
  ('handoff.backup.remediate.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.billing.answer.sent', 'accountant', true, 'none', 'the one seat that sends billing.answer; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.billing.answer.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.billing.answer.waiting', 'accountant', true, 'none', 'the one seat that sends billing.answer; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.billing.answer.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.billing.answer.done', 'accountant', true, 'none', 'the one seat that sends billing.answer; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.billing.answer.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.billing.answer.failed', 'accountant', true, 'digest', 'the one seat that sends billing.answer; a failed hand-over is the sender''s to re-send'),
  ('handoff.billing.answer.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.billing.question.sent', 'sales_engineer', true, 'none', 'the one seat that sends billing.question; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.billing.question.sent', 'accountant', false, 'none', 'accountant holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.billing.question.waiting', 'sales_engineer', true, 'none', 'the one seat that sends billing.question; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.billing.question.waiting', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.billing.question.done', 'sales_engineer', true, 'none', 'the one seat that sends billing.question; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.billing.question.done', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.billing.question.failed', 'sales_engineer', true, 'digest', 'the one seat that sends billing.question; a failed hand-over is the sender''s to re-send'),
  ('handoff.billing.question.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.ceo.decision_closed.sent', 'ceo', true, 'none', 'the one seat that sends ceo.decision_closed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.decision_closed.sent', 'customer_support', false, 'none', 'customer_support holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.decision_closed.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.decision_closed.sent', 'accountant', false, 'none', 'accountant holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.decision_closed.sent', 'it_engineer', false, 'none', 'it_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.decision_closed.sent', 'marketing', false, 'none', 'marketing holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.decision_closed.waiting', 'ceo', true, 'none', 'the one seat that sends ceo.decision_closed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.decision_closed.waiting', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.ceo.decision_closed.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.ceo.decision_closed.waiting', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.ceo.decision_closed.waiting', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.ceo.decision_closed.waiting', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.ceo.decision_closed.done', 'ceo', true, 'none', 'the one seat that sends ceo.decision_closed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.decision_closed.done', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.ceo.decision_closed.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.ceo.decision_closed.done', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.ceo.decision_closed.done', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.ceo.decision_closed.done', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.ceo.decision_closed.failed', 'ceo', true, 'digest', 'the one seat that sends ceo.decision_closed; a failed hand-over is the sender''s to re-send'),
  ('handoff.ceo.decision_closed.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.ceo.decision_owed.sent', 'it_engineer', true, 'none', 'sent most of the ceo.decision_owed hand-overs in the last 30 days (1 of 1); the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.decision_owed.sent', 'ceo', false, 'none', 'ceo holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.decision_owed.waiting', 'it_engineer', true, 'none', 'sent most of the ceo.decision_owed hand-overs in the last 30 days (1 of 1); the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.decision_owed.waiting', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.ceo.decision_owed.done', 'it_engineer', true, 'none', 'sent most of the ceo.decision_owed hand-overs in the last 30 days (1 of 1); the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.decision_owed.done', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.ceo.decision_owed.failed', 'it_engineer', true, 'digest', 'sent most of the ceo.decision_owed hand-overs in the last 30 days (1 of 1); a failed hand-over is the sender''s to re-send; nobody else: the IT engineer is the owner and watches its own faults'),
  ('handoff.ceo.directive.sent', 'ceo', true, 'none', 'the one seat that sends ceo.directive; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.directive.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.directive.sent', 'customer_support', false, 'none', 'customer_support holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.directive.sent', 'accountant', false, 'none', 'accountant holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.directive.sent', 'it_engineer', false, 'none', 'it_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.directive.sent', 'marketing', false, 'none', 'marketing holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.directive.waiting', 'ceo', true, 'none', 'the one seat that sends ceo.directive; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.directive.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.ceo.directive.waiting', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.ceo.directive.waiting', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.ceo.directive.waiting', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.ceo.directive.waiting', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.ceo.directive.done', 'ceo', true, 'none', 'the one seat that sends ceo.directive; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.directive.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.ceo.directive.done', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.ceo.directive.done', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.ceo.directive.done', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.ceo.directive.done', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.ceo.directive.failed', 'ceo', true, 'digest', 'the one seat that sends ceo.directive; a failed hand-over is the sender''s to re-send'),
  ('handoff.ceo.directive.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.ceo.improvement.sent', 'ceo', true, 'none', 'the one seat that sends ceo.improvement; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.improvement.sent', 'accountant', false, 'none', 'accountant holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.improvement.sent', 'it_engineer', false, 'none', 'it_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.improvement.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.improvement.sent', 'customer_support', false, 'none', 'customer_support holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.improvement.sent', 'marketing', false, 'none', 'marketing holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.improvement.waiting', 'ceo', true, 'none', 'the one seat that sends ceo.improvement; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.improvement.waiting', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.ceo.improvement.waiting', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.ceo.improvement.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.ceo.improvement.waiting', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.ceo.improvement.waiting', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.ceo.improvement.done', 'ceo', true, 'none', 'the one seat that sends ceo.improvement; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.improvement.done', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.ceo.improvement.done', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.ceo.improvement.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.ceo.improvement.done', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.ceo.improvement.done', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.ceo.improvement.failed', 'ceo', true, 'digest', 'the one seat that sends ceo.improvement; a failed hand-over is the sender''s to re-send'),
  ('handoff.ceo.improvement.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.ceo.lesson_reapproval_overdue.sent', 'it_engineer', true, 'none', 'the one seat that sends ceo.lesson_reapproval_overdue; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.lesson_reapproval_overdue.sent', 'ceo', false, 'none', 'ceo holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.lesson_reapproval_overdue.waiting', 'it_engineer', true, 'none', 'the one seat that sends ceo.lesson_reapproval_overdue; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.lesson_reapproval_overdue.waiting', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.ceo.lesson_reapproval_overdue.done', 'it_engineer', true, 'none', 'the one seat that sends ceo.lesson_reapproval_overdue; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.lesson_reapproval_overdue.done', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.ceo.lesson_reapproval_overdue.failed', 'it_engineer', true, 'digest', 'the one seat that sends ceo.lesson_reapproval_overdue; a failed hand-over is the sender''s to re-send; nobody else: the IT engineer is the owner and watches its own faults'),
  ('handoff.ceo.month_directive.sent', 'ceo', true, 'none', 'the one seat that sends ceo.month_directive; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.month_directive.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.month_directive.sent', 'customer_support', false, 'none', 'customer_support holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.month_directive.sent', 'marketing', false, 'none', 'marketing holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.month_directive.sent', 'accountant', false, 'none', 'accountant holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.month_directive.sent', 'it_engineer', false, 'none', 'it_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.month_directive.waiting', 'ceo', true, 'none', 'the one seat that sends ceo.month_directive; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.month_directive.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.ceo.month_directive.waiting', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.ceo.month_directive.waiting', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.ceo.month_directive.waiting', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.ceo.month_directive.waiting', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.ceo.month_directive.done', 'ceo', true, 'none', 'the one seat that sends ceo.month_directive; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.month_directive.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.ceo.month_directive.done', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.ceo.month_directive.done', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.ceo.month_directive.done', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.ceo.month_directive.done', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.ceo.month_directive.failed', 'ceo', true, 'digest', 'the one seat that sends ceo.month_directive; a failed hand-over is the sender''s to re-send'),
  ('handoff.ceo.month_directive.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.ceo.revise.sent', 'ceo', true, 'none', 'the one seat that sends ceo.revise; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.revise.sent', 'customer_support', false, 'none', 'customer_support holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.revise.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.revise.sent', 'accountant', false, 'none', 'accountant holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.revise.sent', 'it_engineer', false, 'none', 'it_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.revise.sent', 'marketing', false, 'none', 'marketing holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.revise.waiting', 'ceo', true, 'none', 'the one seat that sends ceo.revise; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.revise.waiting', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.ceo.revise.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.ceo.revise.waiting', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.ceo.revise.waiting', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.ceo.revise.waiting', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.ceo.revise.done', 'ceo', true, 'none', 'the one seat that sends ceo.revise; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.revise.done', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.ceo.revise.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.ceo.revise.done', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.ceo.revise.done', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.ceo.revise.done', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.ceo.revise.failed', 'ceo', true, 'digest', 'the one seat that sends ceo.revise; a failed hand-over is the sender''s to re-send'),
  ('handoff.ceo.revise.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.ceo.root_cause.sent', 'ceo', true, 'none', 'the one seat that sends ceo.root_cause; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.root_cause.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.root_cause.sent', 'customer_support', false, 'none', 'customer_support holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.root_cause.sent', 'accountant', false, 'none', 'accountant holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.root_cause.sent', 'it_engineer', false, 'none', 'it_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.root_cause.sent', 'marketing', false, 'none', 'marketing holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.ceo.root_cause.waiting', 'ceo', true, 'none', 'the one seat that sends ceo.root_cause; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.root_cause.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.ceo.root_cause.waiting', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.ceo.root_cause.waiting', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.ceo.root_cause.waiting', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.ceo.root_cause.waiting', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.ceo.root_cause.done', 'ceo', true, 'none', 'the one seat that sends ceo.root_cause; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.ceo.root_cause.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.ceo.root_cause.done', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.ceo.root_cause.done', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.ceo.root_cause.done', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.ceo.root_cause.done', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.ceo.root_cause.failed', 'ceo', true, 'digest', 'the one seat that sends ceo.root_cause; a failed hand-over is the sender''s to re-send'),
  ('handoff.ceo.root_cause.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.charge.corrected.sent', 'accountant', true, 'none', 'the one seat that sends charge.corrected; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.charge.corrected.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.charge.corrected.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.charge.corrected.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.charge.corrected.waiting', 'accountant', true, 'none', 'the one seat that sends charge.corrected; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.charge.corrected.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.charge.corrected.done', 'accountant', true, 'none', 'the one seat that sends charge.corrected; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.charge.corrected.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.charge.corrected.failed', 'accountant', true, 'digest', 'the one seat that sends charge.corrected; a failed hand-over is the sender''s to re-send'),
  ('handoff.charge.corrected.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.charge.dispute_answer.sent', 'accountant', true, 'none', 'the one seat that sends charge.dispute_answer; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.charge.dispute_answer.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.charge.dispute_answer.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.charge.dispute_answer.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.charge.dispute_answer.waiting', 'accountant', true, 'none', 'the one seat that sends charge.dispute_answer; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.charge.dispute_answer.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.charge.dispute_answer.done', 'accountant', true, 'none', 'the one seat that sends charge.dispute_answer; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.charge.dispute_answer.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.charge.dispute_answer.failed', 'accountant', true, 'digest', 'the one seat that sends charge.dispute_answer; a failed hand-over is the sender''s to re-send'),
  ('handoff.charge.dispute_answer.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.charge.disputed.sent', 'sales_engineer', true, 'none', 'the one seat that sends charge.disputed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.charge.disputed.sent', 'accountant', false, 'none', 'accountant holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.charge.disputed.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.charge.disputed.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.charge.disputed.waiting', 'sales_engineer', true, 'none', 'the one seat that sends charge.disputed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.charge.disputed.waiting', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.charge.disputed.done', 'sales_engineer', true, 'none', 'the one seat that sends charge.disputed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.charge.disputed.done', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.charge.disputed.failed', 'sales_engineer', true, 'digest', 'the one seat that sends charge.disputed; a failed hand-over is the sender''s to re-send'),
  ('handoff.charge.disputed.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.complaint.due.sent', 'customer_support', true, 'none', 'the one seat that sends complaint.due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.complaint.due.waiting', 'customer_support', true, 'none', 'the one seat that sends complaint.due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat''s hand-over to itself; its own queue is the record'),
  ('handoff.complaint.due.done', 'customer_support', true, 'none', 'the one seat that sends complaint.due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat''s hand-over to itself; its own queue is the record'),
  ('handoff.complaint.due.failed', 'customer_support', true, 'digest', 'the one seat that sends complaint.due; a failed hand-over is the sender''s to re-send'),
  ('handoff.complaint.due.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.data.correction.sent', 'customer_support', true, 'none', 'the one seat that sends data.correction; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.data.correction.sent', 'it_engineer', false, 'none', 'it_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.data.correction.waiting', 'customer_support', true, 'none', 'the one seat that sends data.correction; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.data.correction.waiting', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.data.correction.done', 'customer_support', true, 'none', 'the one seat that sends data.correction; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.data.correction.done', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.data.correction.failed', 'customer_support', true, 'digest', 'the one seat that sends data.correction; a failed hand-over is the sender''s to re-send'),
  ('handoff.data.correction.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.deliberation.review.sent', 'ceo', true, 'none', 'sent most of the deliberation.review hand-overs in the last 30 days (4 of 13); the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.deliberation.review.sent', 'marketing', false, 'none', 'marketing holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.deliberation.review.sent', 'accountant', false, 'none', 'accountant holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.deliberation.review.waiting', 'ceo', true, 'none', 'sent most of the deliberation.review hand-overs in the last 30 days (4 of 13); the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.deliberation.review.waiting', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.deliberation.review.waiting', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.deliberation.review.done', 'ceo', true, 'none', 'sent most of the deliberation.review hand-overs in the last 30 days (4 of 13); the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.deliberation.review.done', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.deliberation.review.done', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.deliberation.review.failed', 'ceo', true, 'digest', 'sent most of the deliberation.review hand-overs in the last 30 days (4 of 13); a failed hand-over is the sender''s to re-send'),
  ('handoff.deliberation.review.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.deliberation.review.reviewed', 'ceo', true, 'none', 'sent most of the deliberation.review hand-overs in the last 30 days (4 of 13); the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.deliberation.review.reviewed', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.deliberation.review.reviewed', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.deliberation.rework.sent', 'ceo', true, 'none', 'the one seat that sends deliberation.rework; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.deliberation.rework.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.deliberation.rework.sent', 'customer_support', false, 'none', 'customer_support holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.deliberation.rework.sent', 'marketing', false, 'none', 'marketing holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.deliberation.rework.sent', 'accountant', false, 'none', 'accountant holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.deliberation.rework.sent', 'it_engineer', false, 'none', 'it_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.deliberation.rework.waiting', 'ceo', true, 'none', 'the one seat that sends deliberation.rework; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.deliberation.rework.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.deliberation.rework.waiting', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.deliberation.rework.waiting', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.deliberation.rework.waiting', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.deliberation.rework.waiting', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.deliberation.rework.done', 'ceo', true, 'none', 'the one seat that sends deliberation.rework; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.deliberation.rework.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.deliberation.rework.done', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.deliberation.rework.done', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.deliberation.rework.done', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.deliberation.rework.done', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.deliberation.rework.failed', 'ceo', true, 'digest', 'the one seat that sends deliberation.rework; a failed hand-over is the sender''s to re-send'),
  ('handoff.deliberation.rework.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.deliverability.inbox_placement.sent', 'it_engineer', true, 'none', 'the one seat that sends deliverability.inbox_placement; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.deliverability.inbox_placement.sent', 'marketing', false, 'none', 'marketing holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.deliverability.inbox_placement.waiting', 'it_engineer', true, 'none', 'the one seat that sends deliverability.inbox_placement; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.deliverability.inbox_placement.waiting', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.deliverability.inbox_placement.done', 'it_engineer', true, 'none', 'the one seat that sends deliverability.inbox_placement; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.deliverability.inbox_placement.done', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.deliverability.inbox_placement.failed', 'it_engineer', true, 'digest', 'the one seat that sends deliverability.inbox_placement; a failed hand-over is the sender''s to re-send; nobody else: the IT engineer is the owner and watches its own faults'),
  ('handoff.delivery.remediate.sent', 'ceo', true, 'none', 'the one seat that sends delivery.remediate; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.delivery.remediate.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.delivery.remediate.waiting', 'ceo', true, 'none', 'the one seat that sends delivery.remediate; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.delivery.remediate.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.delivery.remediate.done', 'ceo', true, 'none', 'the one seat that sends delivery.remediate; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.delivery.remediate.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.delivery.remediate.failed', 'ceo', true, 'digest', 'the one seat that sends delivery.remediate; a failed hand-over is the sender''s to re-send'),
  ('handoff.delivery.remediate.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.delivery.request.sent', 'sales_engineer', true, 'none', 'sent most of the delivery.request hand-overs in the last 30 days (4365 of 9105); the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.delivery.request.sent', 'customer_support', false, 'none', 'customer_support holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.delivery.request.waiting', 'sales_engineer', true, 'none', 'sent most of the delivery.request hand-overs in the last 30 days (4365 of 9105); the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.delivery.request.waiting', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.delivery.request.done', 'sales_engineer', true, 'none', 'sent most of the delivery.request hand-overs in the last 30 days (4365 of 9105); the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.delivery.request.done', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.delivery.request.failed', 'sales_engineer', true, 'digest', 'sent most of the delivery.request hand-overs in the last 30 days (4365 of 9105); a failed hand-over is the sender''s to re-send'),
  ('handoff.delivery.request.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.delivery.result.sent', 'customer_support', true, 'none', 'the one seat that sends delivery.result; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.delivery.result.sent', 'marketing', false, 'none', 'marketing holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.delivery.result.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.delivery.result.sent', 'accountant', false, 'none', 'accountant holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.delivery.result.sent', 'ceo', false, 'none', 'ceo holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.delivery.result.sent', 'it_engineer', false, 'none', 'it_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.delivery.result.waiting', 'customer_support', true, 'none', 'the one seat that sends delivery.result; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.delivery.result.waiting', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.delivery.result.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.delivery.result.waiting', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.delivery.result.waiting', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.delivery.result.waiting', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.delivery.result.done', 'customer_support', true, 'none', 'the one seat that sends delivery.result; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.delivery.result.done', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.delivery.result.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.delivery.result.done', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.delivery.result.done', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.delivery.result.done', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.delivery.result.failed', 'customer_support', true, 'digest', 'the one seat that sends delivery.result; a failed hand-over is the sender''s to re-send'),
  ('handoff.delivery.result.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.event.act.sent', 'sales_engineer', true, 'none', 'the one seat that sends event.act; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat''s hand-over to itself; its own queue is the record'),
  ('handoff.event.act.waiting', 'sales_engineer', true, 'none', 'the one seat that sends event.act; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat''s hand-over to itself; its own queue is the record'),
  ('handoff.event.act.done', 'sales_engineer', true, 'none', 'the one seat that sends event.act; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat''s hand-over to itself; its own queue is the record'),
  ('handoff.event.act.failed', 'sales_engineer', true, 'digest', 'the one seat that sends event.act; a failed hand-over is the sender''s to re-send'),
  ('handoff.event.act.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.fraud.money_held.sent', 'accountant', true, 'none', 'the one seat that sends fraud.money_held; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.fraud.money_held.sent', 'customer_support', false, 'none', 'customer_support holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.fraud.money_held.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.fraud.money_held.sent', 'sales_engineer', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.fraud.money_held.waiting', 'accountant', true, 'none', 'the one seat that sends fraud.money_held; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.fraud.money_held.waiting', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.fraud.money_held.done', 'accountant', true, 'none', 'the one seat that sends fraud.money_held; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.fraud.money_held.done', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.fraud.money_held.failed', 'accountant', true, 'digest', 'the one seat that sends fraud.money_held; a failed hand-over is the sender''s to re-send'),
  ('handoff.fraud.money_held.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.fraud.money_released.sent', 'accountant', true, 'none', 'the one seat that sends fraud.money_released; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.fraud.money_released.sent', 'customer_support', false, 'none', 'customer_support holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.fraud.money_released.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.fraud.money_released.sent', 'sales_engineer', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.fraud.money_released.waiting', 'accountant', true, 'none', 'the one seat that sends fraud.money_released; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.fraud.money_released.waiting', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.fraud.money_released.done', 'accountant', true, 'none', 'the one seat that sends fraud.money_released; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.fraud.money_released.done', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.fraud.money_released.failed', 'accountant', true, 'digest', 'the one seat that sends fraud.money_released; a failed hand-over is the sender''s to re-send'),
  ('handoff.fraud.money_released.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.incident.fix.sent', 'ceo', true, 'none', 'the one seat that sends incident.fix; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.incident.fix.sent', 'accountant', false, 'none', 'accountant holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.incident.fix.waiting', 'ceo', true, 'none', 'the one seat that sends incident.fix; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.incident.fix.waiting', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.incident.fix.done', 'ceo', true, 'none', 'the one seat that sends incident.fix; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.incident.fix.done', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.incident.fix.failed', 'ceo', true, 'digest', 'the one seat that sends incident.fix; a failed hand-over is the sender''s to re-send'),
  ('handoff.incident.fix.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.inquiry.status_chase.sent', 'customer_support', true, 'none', 'the one seat that sends inquiry.status_chase; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.inquiry.status_chase.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.inquiry.status_chase.waiting', 'customer_support', true, 'none', 'the one seat that sends inquiry.status_chase; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.inquiry.status_chase.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.inquiry.status_chase.done', 'customer_support', true, 'none', 'the one seat that sends inquiry.status_chase; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.inquiry.status_chase.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.inquiry.status_chase.failed', 'customer_support', true, 'digest', 'the one seat that sends inquiry.status_chase; a failed hand-over is the sender''s to re-send'),
  ('handoff.inquiry.status_chase.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.invite.reply.sent', 'marketing', true, 'none', 'the one seat that sends invite.reply; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.invite.reply.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.invite.reply.waiting', 'marketing', true, 'none', 'the one seat that sends invite.reply; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.invite.reply.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.invite.reply.done', 'marketing', true, 'none', 'the one seat that sends invite.reply; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.invite.reply.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.invite.reply.failed', 'marketing', true, 'digest', 'the one seat that sends invite.reply; a failed hand-over is the sender''s to re-send'),
  ('handoff.invite.reply.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.invoice.issued.sent', 'accountant', true, 'none', 'the one seat that sends invoice.issued; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.invoice.issued.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.invoice.issued.waiting', 'accountant', true, 'none', 'the one seat that sends invoice.issued; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.invoice.issued.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.invoice.issued.done', 'accountant', true, 'none', 'the one seat that sends invoice.issued; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.invoice.issued.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.invoice.issued.failed', 'accountant', true, 'digest', 'the one seat that sends invoice.issued; a failed hand-over is the sender''s to re-send'),
  ('handoff.invoice.issued.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.it.finding.sent', 'it_engineer', true, 'none', 'the one seat that sends it.finding; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.it.finding.sent', 'marketing', false, 'none', 'marketing holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.it.finding.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.it.finding.sent', 'accountant', false, 'none', 'accountant holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.it.finding.sent', 'customer_support', false, 'none', 'customer_support holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.it.finding.sent', 'ceo', false, 'none', 'ceo holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.it.finding.waiting', 'it_engineer', true, 'none', 'the one seat that sends it.finding; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.it.finding.waiting', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.it.finding.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.it.finding.waiting', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.it.finding.waiting', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.it.finding.waiting', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.it.finding.done', 'it_engineer', true, 'none', 'the one seat that sends it.finding; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.it.finding.done', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.it.finding.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.it.finding.done', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.it.finding.done', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.it.finding.done', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.it.finding.failed', 'it_engineer', true, 'digest', 'the one seat that sends it.finding; a failed hand-over is the sender''s to re-send; nobody else: the IT engineer is the owner and watches its own faults'),
  ('handoff.knowledge.request.sent', 'customer_support', true, 'none', 'the one seat that sends knowledge.request; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.knowledge.request.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.knowledge.request.sent', 'ceo', false, 'none', 'ceo holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.knowledge.request.waiting', 'customer_support', true, 'none', 'the one seat that sends knowledge.request; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.knowledge.request.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.knowledge.request.waiting', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.knowledge.request.done', 'customer_support', true, 'none', 'the one seat that sends knowledge.request; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.knowledge.request.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.knowledge.request.done', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.knowledge.request.failed', 'customer_support', true, 'digest', 'the one seat that sends knowledge.request; a failed hand-over is the sender''s to re-send'),
  ('handoff.knowledge.request.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.mailbox.supplier_reply.sent', 'marketing', true, 'none', 'the one seat that sends mailbox.supplier_reply; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.mailbox.supplier_reply.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.mailbox.supplier_reply.waiting', 'marketing', true, 'none', 'the one seat that sends mailbox.supplier_reply; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.mailbox.supplier_reply.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.mailbox.supplier_reply.done', 'marketing', true, 'none', 'the one seat that sends mailbox.supplier_reply; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.mailbox.supplier_reply.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.mailbox.supplier_reply.failed', 'marketing', true, 'digest', 'the one seat that sends mailbox.supplier_reply; a failed hand-over is the sender''s to re-send'),
  ('handoff.mailbox.supplier_reply.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.marketing.lead_sourcing.sent', 'marketing', true, 'none', 'the one seat that sends marketing.lead_sourcing; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.marketing.lead_sourcing.sent', 'ceo', false, 'none', 'ceo holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.marketing.lead_sourcing.waiting', 'marketing', true, 'none', 'the one seat that sends marketing.lead_sourcing; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.marketing.lead_sourcing.waiting', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.marketing.lead_sourcing.done', 'marketing', true, 'none', 'the one seat that sends marketing.lead_sourcing; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.marketing.lead_sourcing.done', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.marketing.lead_sourcing.failed', 'marketing', true, 'digest', 'the one seat that sends marketing.lead_sourcing; a failed hand-over is the sender''s to re-send'),
  ('handoff.marketing.lead_sourcing.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.marketing.report.sent', 'marketing', true, 'none', 'the one seat that sends marketing.report; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.marketing.report.sent', 'ceo', false, 'none', 'ceo holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.marketing.report.waiting', 'marketing', true, 'none', 'the one seat that sends marketing.report; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.marketing.report.waiting', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.marketing.report.done', 'marketing', true, 'none', 'the one seat that sends marketing.report; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.marketing.report.done', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.marketing.report.failed', 'marketing', true, 'digest', 'the one seat that sends marketing.report; a failed hand-over is the sender''s to re-send'),
  ('handoff.marketing.report.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.marketing.review.sent', 'marketing', true, 'none', 'the one seat that sends marketing.review; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.marketing.review.sent', 'ceo', false, 'none', 'ceo holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.marketing.review.waiting', 'marketing', true, 'none', 'the one seat that sends marketing.review; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.marketing.review.waiting', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.marketing.review.done', 'marketing', true, 'none', 'the one seat that sends marketing.review; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.marketing.review.done', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.marketing.review.failed', 'marketing', true, 'digest', 'the one seat that sends marketing.review; a failed hand-over is the sender''s to re-send'),
  ('handoff.marketing.review.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.nonresponse.charge_raised.sent', 'accountant', true, 'none', 'the one seat that sends nonresponse.charge_raised; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.nonresponse.charge_raised.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.nonresponse.charge_raised.waiting', 'accountant', true, 'none', 'the one seat that sends nonresponse.charge_raised; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.nonresponse.charge_raised.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.nonresponse.charge_raised.done', 'accountant', true, 'none', 'the one seat that sends nonresponse.charge_raised; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.nonresponse.charge_raised.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.nonresponse.charge_raised.failed', 'accountant', true, 'digest', 'the one seat that sends nonresponse.charge_raised; a failed hand-over is the sender''s to re-send'),
  ('handoff.nonresponse.charge_raised.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.nonresponse.charge_reminder.sent', 'accountant', true, 'none', 'the one seat that sends nonresponse.charge_reminder; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.nonresponse.charge_reminder.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.nonresponse.charge_reminder.waiting', 'accountant', true, 'none', 'the one seat that sends nonresponse.charge_reminder; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.nonresponse.charge_reminder.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.nonresponse.charge_reminder.done', 'accountant', true, 'none', 'the one seat that sends nonresponse.charge_reminder; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.nonresponse.charge_reminder.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.nonresponse.charge_reminder.failed', 'accountant', true, 'digest', 'the one seat that sends nonresponse.charge_reminder; a failed hand-over is the sender''s to re-send'),
  ('handoff.nonresponse.charge_reminder.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.nonresponse.final_demand.sent', 'accountant', true, 'none', 'the one seat that sends nonresponse.final_demand; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.nonresponse.final_demand.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.nonresponse.final_demand.waiting', 'accountant', true, 'none', 'the one seat that sends nonresponse.final_demand; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.nonresponse.final_demand.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.nonresponse.final_demand.done', 'accountant', true, 'none', 'the one seat that sends nonresponse.final_demand; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.nonresponse.final_demand.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.nonresponse.final_demand.failed', 'accountant', true, 'digest', 'the one seat that sends nonresponse.final_demand; a failed hand-over is the sender''s to re-send'),
  ('handoff.nonresponse.final_demand.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.overcharge.customer_notice.sent', 'accountant', true, 'none', 'the one seat that sends overcharge.customer_notice; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.overcharge.customer_notice.sent', 'customer_support', false, 'none', 'customer_support holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.overcharge.customer_notice.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.overcharge.customer_notice.sent', 'sales_engineer', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.overcharge.customer_notice.waiting', 'accountant', true, 'none', 'the one seat that sends overcharge.customer_notice; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.overcharge.customer_notice.waiting', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.overcharge.customer_notice.done', 'accountant', true, 'none', 'the one seat that sends overcharge.customer_notice; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.overcharge.customer_notice.done', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.overcharge.customer_notice.failed', 'accountant', true, 'digest', 'the one seat that sends overcharge.customer_notice; a failed hand-over is the sender''s to re-send'),
  ('handoff.overcharge.customer_notice.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.payment.exception.sent', 'accountant', true, 'none', 'the one seat that sends payment.exception; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.payment.exception.sent', 'ceo', false, 'none', 'ceo holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.payment.exception.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.payment.exception.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.payment.exception.waiting', 'accountant', true, 'none', 'the one seat that sends payment.exception; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.payment.exception.waiting', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.payment.exception.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.payment.exception.done', 'accountant', true, 'none', 'the one seat that sends payment.exception; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.payment.exception.done', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.payment.exception.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.payment.exception.failed', 'accountant', true, 'digest', 'the one seat that sends payment.exception; a failed hand-over is the sender''s to re-send'),
  ('handoff.payment.exception.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.payment.failed.sent', 'accountant', true, 'none', 'the one seat that sends payment.failed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.payment.failed.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.payment.failed.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.payment.failed.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.payment.failed.waiting', 'accountant', true, 'none', 'the one seat that sends payment.failed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.payment.failed.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.payment.failed.done', 'accountant', true, 'none', 'the one seat that sends payment.failed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.payment.failed.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.payment.failed.failed', 'accountant', true, 'digest', 'the one seat that sends payment.failed; a failed hand-over is the sender''s to re-send'),
  ('handoff.payment.failed.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.payment.received.sent', 'accountant', true, 'none', 'the one seat that sends payment.received; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.payment.received.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.payment.received.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.payment.received.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.payment.received.waiting', 'accountant', true, 'none', 'the one seat that sends payment.received; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.payment.received.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.payment.received.done', 'accountant', true, 'none', 'the one seat that sends payment.received; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.payment.received.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.payment.received.failed', 'accountant', true, 'digest', 'the one seat that sends payment.received; a failed hand-over is the sender''s to re-send'),
  ('handoff.payment.received.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.payment.unrecorded.sent', 'accountant', true, 'none', 'the one seat that sends payment.unrecorded; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.payment.unrecorded.sent', 'it_engineer', false, 'none', 'it_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.payment.unrecorded.sent', 'customer_support', false, 'none', 'customer_support holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.payment.unrecorded.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.payment.unrecorded.sent', 'sales_engineer', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.payment.unrecorded.waiting', 'accountant', true, 'none', 'the one seat that sends payment.unrecorded; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.payment.unrecorded.waiting', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.payment.unrecorded.waiting', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.payment.unrecorded.done', 'accountant', true, 'none', 'the one seat that sends payment.unrecorded; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.payment.unrecorded.done', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.payment.unrecorded.done', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.payment.unrecorded.failed', 'accountant', true, 'digest', 'the one seat that sends payment.unrecorded; a failed hand-over is the sender''s to re-send'),
  ('handoff.payment.unrecorded.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.refund.declined.sent', 'accountant', true, 'none', 'the one seat that sends refund.declined; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.refund.declined.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.refund.declined.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.refund.declined.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.refund.declined.waiting', 'accountant', true, 'none', 'the one seat that sends refund.declined; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.refund.declined.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.refund.declined.done', 'accountant', true, 'none', 'the one seat that sends refund.declined; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.refund.declined.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.refund.declined.failed', 'accountant', true, 'digest', 'the one seat that sends refund.declined; a failed hand-over is the sender''s to re-send'),
  ('handoff.refund.declined.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.refund.in_progress.sent', 'accountant', true, 'none', 'the one seat that sends refund.in_progress; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.refund.in_progress.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.refund.in_progress.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.refund.in_progress.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.refund.in_progress.waiting', 'accountant', true, 'none', 'the one seat that sends refund.in_progress; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.refund.in_progress.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.refund.in_progress.done', 'accountant', true, 'none', 'the one seat that sends refund.in_progress; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.refund.in_progress.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.refund.in_progress.failed', 'accountant', true, 'digest', 'the one seat that sends refund.in_progress; a failed hand-over is the sender''s to re-send'),
  ('handoff.refund.in_progress.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.refund.paid.sent', 'accountant', true, 'none', 'the one seat that sends refund.paid; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.refund.paid.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.refund.paid.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.refund.paid.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.refund.paid.waiting', 'accountant', true, 'none', 'the one seat that sends refund.paid; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.refund.paid.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.refund.paid.done', 'accountant', true, 'none', 'the one seat that sends refund.paid; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.refund.paid.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.refund.paid.failed', 'accountant', true, 'digest', 'the one seat that sends refund.paid; a failed hand-over is the sender''s to re-send'),
  ('handoff.refund.paid.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.refund.remediate.sent', 'ceo', true, 'none', 'the one seat that sends refund.remediate; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.refund.remediate.sent', 'accountant', false, 'none', 'accountant holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.refund.remediate.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.refund.remediate.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.refund.remediate.waiting', 'ceo', true, 'none', 'the one seat that sends refund.remediate; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.refund.remediate.waiting', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.refund.remediate.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.refund.remediate.done', 'ceo', true, 'none', 'the one seat that sends refund.remediate; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.refund.remediate.done', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.refund.remediate.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.refund.remediate.failed', 'ceo', true, 'digest', 'the one seat that sends refund.remediate; a failed hand-over is the sender''s to re-send'),
  ('handoff.refund.remediate.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.refund.request_checked.sent', 'accountant', true, 'none', 'the one seat that sends refund.request_checked; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.refund.request_checked.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.refund.request_checked.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.refund.request_checked.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.refund.request_checked.waiting', 'accountant', true, 'none', 'the one seat that sends refund.request_checked; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.refund.request_checked.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.refund.request_checked.done', 'accountant', true, 'none', 'the one seat that sends refund.request_checked; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.refund.request_checked.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.refund.request_checked.failed', 'accountant', true, 'digest', 'the one seat that sends refund.request_checked; a failed hand-over is the sender''s to re-send'),
  ('handoff.refund.request_checked.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.refund.requested.sent', 'sales_engineer', true, 'none', 'the one seat that sends refund.requested; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.refund.requested.sent', 'accountant', false, 'none', 'accountant holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.refund.requested.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.refund.requested.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.refund.requested.waiting', 'sales_engineer', true, 'none', 'the one seat that sends refund.requested; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.refund.requested.waiting', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.refund.requested.done', 'sales_engineer', true, 'none', 'the one seat that sends refund.requested; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.refund.requested.done', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.refund.requested.failed', 'sales_engineer', true, 'digest', 'the one seat that sends refund.requested; a failed hand-over is the sender''s to re-send'),
  ('handoff.refund.requested.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.renewal.due.sent', 'it_engineer', true, 'none', 'the one seat that sends renewal.due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.renewal.due.sent', 'accountant', false, 'none', 'accountant holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.renewal.due.waiting', 'it_engineer', true, 'none', 'the one seat that sends renewal.due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.renewal.due.waiting', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.renewal.due.done', 'it_engineer', true, 'none', 'the one seat that sends renewal.due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.renewal.due.done', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.renewal.due.failed', 'it_engineer', true, 'digest', 'the one seat that sends renewal.due; a failed hand-over is the sender''s to re-send; nobody else: the IT engineer is the owner and watches its own faults'),
  ('handoff.report.five_numbers.sent', 'ceo', true, 'none', 'the one seat that sends report.five_numbers; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat''s hand-over to itself; its own queue is the record'),
  ('handoff.report.five_numbers.waiting', 'ceo', true, 'none', 'the one seat that sends report.five_numbers; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat''s hand-over to itself; its own queue is the record'),
  ('handoff.report.five_numbers.done', 'ceo', true, 'none', 'the one seat that sends report.five_numbers; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat''s hand-over to itself; its own queue is the record'),
  ('handoff.report.five_numbers.failed', 'ceo', true, 'digest', 'the one seat that sends report.five_numbers; a failed hand-over is the sender''s to re-send'),
  ('handoff.report.five_numbers.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.reveal.paid.sent', 'accountant', true, 'none', 'the one seat that sends reveal.paid; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.reveal.paid.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.reveal.paid.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.reveal.paid.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.reveal.paid.waiting', 'accountant', true, 'none', 'the one seat that sends reveal.paid; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.reveal.paid.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.reveal.paid.done', 'accountant', true, 'none', 'the one seat that sends reveal.paid; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.reveal.paid.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.reveal.paid.failed', 'accountant', true, 'digest', 'the one seat that sends reveal.paid; a failed hand-over is the sender''s to re-send'),
  ('handoff.reveal.paid.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.reveal.reconcile.sent', 'sales_engineer', true, 'none', 'the one seat that sends reveal.reconcile; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.reveal.reconcile.sent', 'accountant', false, 'none', 'accountant holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.reveal.reconcile.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.reveal.reconcile.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.reveal.reconcile.waiting', 'sales_engineer', true, 'none', 'the one seat that sends reveal.reconcile; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.reveal.reconcile.waiting', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.reveal.reconcile.done', 'sales_engineer', true, 'none', 'the one seat that sends reveal.reconcile; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.reveal.reconcile.done', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.reveal.reconcile.failed', 'sales_engineer', true, 'digest', 'the one seat that sends reveal.reconcile; a failed hand-over is the sender''s to re-send'),
  ('handoff.reveal.reconcile.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.review.requested.sent', 'customer_support', true, 'none', 'the one seat that sends review.requested; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.review.requested.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.review.requested.sent', 'ceo', false, 'none', 'ceo holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.review.requested.sent', 'it_engineer', false, 'none', 'it_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.review.requested.sent', 'accountant', false, 'none', 'accountant holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.review.requested.waiting', 'customer_support', true, 'none', 'the one seat that sends review.requested; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.review.requested.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.review.requested.waiting', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.review.requested.waiting', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.review.requested.waiting', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.review.requested.done', 'customer_support', true, 'none', 'the one seat that sends review.requested; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.review.requested.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.review.requested.done', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.review.requested.done', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.review.requested.done', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.review.requested.failed', 'customer_support', true, 'digest', 'the one seat that sends review.requested; a failed hand-over is the sender''s to re-send'),
  ('handoff.review.requested.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.sale.made.sent', 'accountant', true, 'none', 'the one seat that sends sale.made; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.sale.made.sent', 'ceo', false, 'none', 'ceo holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.sale.made.sent', 'sales_engineer', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.sale.made.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.sale.made.waiting', 'accountant', true, 'none', 'the one seat that sends sale.made; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.sale.made.waiting', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.sale.made.done', 'accountant', true, 'none', 'the one seat that sends sale.made; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.sale.made.done', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.sale.made.failed', 'accountant', true, 'digest', 'the one seat that sends sale.made; a failed hand-over is the sender''s to re-send'),
  ('handoff.sale.made.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.sales.escalation.sent', 'sales_engineer', true, 'none', 'the one seat that sends sales.escalation; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.sales.escalation.sent', 'ceo', false, 'none', 'ceo holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.sales.escalation.waiting', 'sales_engineer', true, 'none', 'the one seat that sends sales.escalation; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.sales.escalation.waiting', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.sales.escalation.done', 'sales_engineer', true, 'none', 'the one seat that sends sales.escalation; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.sales.escalation.done', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.sales.escalation.failed', 'sales_engineer', true, 'digest', 'the one seat that sends sales.escalation; a failed hand-over is the sender''s to re-send'),
  ('handoff.sales.escalation.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.social.escalation.sent', 'marketing', true, 'none', 'the one seat that sends social.escalation; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.social.escalation.sent', 'customer_support', false, 'none', 'customer_support holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.social.escalation.waiting', 'marketing', true, 'none', 'the one seat that sends social.escalation; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.social.escalation.waiting', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.social.escalation.done', 'marketing', true, 'none', 'the one seat that sends social.escalation; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.social.escalation.done', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.social.escalation.failed', 'marketing', true, 'digest', 'the one seat that sends social.escalation; a failed hand-over is the sender''s to re-send'),
  ('handoff.social.escalation.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.social.lead.sent', 'marketing', true, 'none', 'the one seat that sends social.lead; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.social.lead.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.social.lead.waiting', 'marketing', true, 'none', 'the one seat that sends social.lead; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.social.lead.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.social.lead.done', 'marketing', true, 'none', 'the one seat that sends social.lead; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.social.lead.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.social.lead.failed', 'marketing', true, 'digest', 'the one seat that sends social.lead; a failed hand-over is the sender''s to re-send'),
  ('handoff.social.lead.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.spec.not_sure.sent', 'customer_support', true, 'none', 'the one seat that sends spec.not_sure; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.spec.not_sure.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.spec.not_sure.waiting', 'customer_support', true, 'none', 'the one seat that sends spec.not_sure; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.spec.not_sure.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.spec.not_sure.done', 'customer_support', true, 'none', 'the one seat that sends spec.not_sure; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.spec.not_sure.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.spec.not_sure.failed', 'customer_support', true, 'digest', 'the one seat that sends spec.not_sure; a failed hand-over is the sender''s to re-send'),
  ('handoff.spec.not_sure.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.subscription.due.sent', 'accountant', true, 'none', 'the one seat that sends subscription.due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.subscription.due.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.subscription.due.waiting', 'accountant', true, 'none', 'the one seat that sends subscription.due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.subscription.due.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.subscription.due.done', 'accountant', true, 'none', 'the one seat that sends subscription.due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.subscription.due.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.subscription.due.failed', 'accountant', true, 'digest', 'the one seat that sends subscription.due; a failed hand-over is the sender''s to re-send'),
  ('handoff.subscription.due.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.subscription.dunning.sent', 'accountant', true, 'none', 'the one seat that sends subscription.dunning; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.subscription.dunning.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.subscription.dunning.waiting', 'accountant', true, 'none', 'the one seat that sends subscription.dunning; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.subscription.dunning.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.subscription.dunning.done', 'accountant', true, 'none', 'the one seat that sends subscription.dunning; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.subscription.dunning.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.subscription.dunning.failed', 'accountant', true, 'digest', 'the one seat that sends subscription.dunning; a failed hand-over is the sender''s to re-send'),
  ('handoff.subscription.dunning.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.subscription.payment_failed.sent', 'accountant', true, 'none', 'the one seat that sends subscription.payment_failed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.subscription.payment_failed.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.subscription.payment_failed.sent', 'ceo', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.subscription.payment_failed.sent', 'customer_support', false, 'digest', 'money moved: founder 1685, every seat with a step knows a payment, a refund or a sale'),
  ('handoff.subscription.payment_failed.waiting', 'accountant', true, 'none', 'the one seat that sends subscription.payment_failed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.subscription.payment_failed.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.subscription.payment_failed.done', 'accountant', true, 'none', 'the one seat that sends subscription.payment_failed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.subscription.payment_failed.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.subscription.payment_failed.failed', 'accountant', true, 'digest', 'the one seat that sends subscription.payment_failed; a failed hand-over is the sender''s to re-send'),
  ('handoff.subscription.payment_failed.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.subscription.renewal_reminder.sent', 'accountant', true, 'none', 'the one seat that sends subscription.renewal_reminder; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.subscription.renewal_reminder.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.subscription.renewal_reminder.waiting', 'accountant', true, 'none', 'the one seat that sends subscription.renewal_reminder; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.subscription.renewal_reminder.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.subscription.renewal_reminder.done', 'accountant', true, 'none', 'the one seat that sends subscription.renewal_reminder; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.subscription.renewal_reminder.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.subscription.renewal_reminder.failed', 'accountant', true, 'digest', 'the one seat that sends subscription.renewal_reminder; a failed hand-over is the sender''s to re-send'),
  ('handoff.subscription.renewal_reminder.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.supplier.portfolio_incomplete.sent', 'sales_engineer', true, 'none', 'the one seat that sends supplier.portfolio_incomplete; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.supplier.portfolio_incomplete.sent', 'customer_support', false, 'none', 'customer_support holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.supplier.portfolio_incomplete.waiting', 'sales_engineer', true, 'none', 'the one seat that sends supplier.portfolio_incomplete; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.supplier.portfolio_incomplete.waiting', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.supplier.portfolio_incomplete.done', 'sales_engineer', true, 'none', 'the one seat that sends supplier.portfolio_incomplete; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.supplier.portfolio_incomplete.done', 'customer_support', false, 'none', 'nobody else: customer_support wrote this answer itself'),
  ('handoff.supplier.portfolio_incomplete.failed', 'sales_engineer', true, 'digest', 'the one seat that sends supplier.portfolio_incomplete; a failed hand-over is the sender''s to re-send'),
  ('handoff.supplier.portfolio_incomplete.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.support.case_open.sent', 'customer_support', true, 'none', 'the one seat that sends support.case_open; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.support.case_open.waiting', 'customer_support', true, 'none', 'the one seat that sends support.case_open; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat''s hand-over to itself; its own queue is the record'),
  ('handoff.support.case_open.done', 'customer_support', true, 'none', 'the one seat that sends support.case_open; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat''s hand-over to itself; its own queue is the record'),
  ('handoff.support.case_open.failed', 'customer_support', true, 'digest', 'the one seat that sends support.case_open; a failed hand-over is the sender''s to re-send'),
  ('handoff.support.case_open.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.support.decision_objection.sent', 'customer_support', true, 'none', 'the one seat that sends support.decision_objection; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.support.decision_objection.sent', 'ceo', false, 'none', 'ceo holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.support.decision_objection.waiting', 'customer_support', true, 'none', 'the one seat that sends support.decision_objection; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.support.decision_objection.waiting', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.support.decision_objection.done', 'customer_support', true, 'none', 'the one seat that sends support.decision_objection; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.support.decision_objection.done', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.support.decision_objection.failed', 'customer_support', true, 'digest', 'the one seat that sends support.decision_objection; a failed hand-over is the sender''s to re-send'),
  ('handoff.support.decision_objection.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.support.human_requested.sent', 'customer_support', true, 'none', 'the one seat that sends support.human_requested; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.support.human_requested.waiting', 'customer_support', true, 'none', 'the one seat that sends support.human_requested; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat''s hand-over to itself; its own queue is the record'),
  ('handoff.support.human_requested.done', 'customer_support', true, 'none', 'the one seat that sends support.human_requested; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat''s hand-over to itself; its own queue is the record'),
  ('handoff.support.human_requested.failed', 'customer_support', true, 'digest', 'the one seat that sends support.human_requested; a failed hand-over is the sender''s to re-send'),
  ('handoff.support.human_requested.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.support.promise_due.sent', 'customer_support', true, 'none', 'the one seat that sends support.promise_due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.support.promise_due.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.support.promise_due.waiting', 'customer_support', true, 'none', 'the one seat that sends support.promise_due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.support.promise_due.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.support.promise_due.done', 'customer_support', true, 'none', 'the one seat that sends support.promise_due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.support.promise_due.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.support.promise_due.failed', 'customer_support', true, 'digest', 'the one seat that sends support.promise_due; a failed hand-over is the sender''s to re-send'),
  ('handoff.support.promise_due.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.support.root_cause.sent', 'customer_support', true, 'none', 'the one seat that sends support.root_cause; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.support.root_cause.sent', 'sales_engineer', false, 'none', 'sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.support.root_cause.sent', 'accountant', false, 'none', 'accountant holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.support.root_cause.sent', 'it_engineer', false, 'none', 'it_engineer holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.support.root_cause.sent', 'marketing', false, 'none', 'marketing holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.support.root_cause.sent', 'ceo', false, 'none', 'ceo holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.support.root_cause.waiting', 'customer_support', true, 'none', 'the one seat that sends support.root_cause; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.support.root_cause.waiting', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.support.root_cause.waiting', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.support.root_cause.waiting', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.support.root_cause.waiting', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.support.root_cause.waiting', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.support.root_cause.done', 'customer_support', true, 'none', 'the one seat that sends support.root_cause; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.support.root_cause.done', 'sales_engineer', false, 'none', 'nobody else: sales_engineer wrote this answer itself'),
  ('handoff.support.root_cause.done', 'accountant', false, 'none', 'nobody else: accountant wrote this answer itself'),
  ('handoff.support.root_cause.done', 'it_engineer', false, 'none', 'nobody else: it_engineer wrote this answer itself'),
  ('handoff.support.root_cause.done', 'marketing', false, 'none', 'nobody else: marketing wrote this answer itself'),
  ('handoff.support.root_cause.done', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.support.root_cause.failed', 'customer_support', true, 'digest', 'the one seat that sends support.root_cause; a failed hand-over is the sender''s to re-send'),
  ('handoff.support.root_cause.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.complaint.due.sent', 'sales_engineer', false, 'digest', 'a complaint is about a request the sales engineer owns; he must know before he next speaks to that customer'),
  ('handoff.complaint.due.sent', 'ceo', false, 'digest', 'complaints are a CEO number and may need his decision'),
  ('handoff.support.human_requested.sent', 'ceo', false, 'digest', 'a person asked for a person: the CEO sees how often the seats could not help'),
  ('handoff.support.case_open.sent', 'sales_engineer', false, 'digest', 'an open support case on a customer or supplier he serves; the timeline shows it when he works that subject');
select set_config('qd.pool_seed', 'on', true);
-- an unedited owner row whose type the seed now gives to another seat steps down first (one owner per type)
update public.event_subscription s set owns = false
 where s.owns and s.edited_by is null
   and exists (select 1 from pool_seed p where p.event_type = s.event_type and p.owns and p.agent_key <> s.agent_key);
insert into public.event_subscription as s (event_type, agent_key, owns, delivery, reason, action_class)
select p.event_type, p.agent_key,
       p.owns and not exists (select 1 from public.event_subscription o where o.event_type = p.event_type and o.owns and o.agent_key <> p.agent_key),
       p.delivery, p.reason, case when p.delivery = 'handover' then 'event.act' end
  from pool_seed p
on conflict (agent_key, event_type) do update
   set owns = excluded.owns, delivery = excluded.delivery, reason = excluded.reason, action_class = excluded.action_class
 where s.edited_by is null;
select set_config('qd.pool_seed', '', true);

-- ── 2. ONE SUBJECT RESOLVER ───────────────────────────────────────────────────────────────────────────────────────
-- Measured 13 Nov (SELECT, 30 days): of 24,4xx hand-overs only 20 named a subject table the first version understood. Their
-- subject is named in the sender's own terms: agent_actions (a delivery's result), notifications, transactions, refunds,
-- support_case by its case_ref, it_engineer_finding by issue_key, 'tx#<id>' ... and most carry customer_id / inquiry_id /
-- lead_id in detail. fn_pool_keys turns any of them into the subjects a seat thinks in, '<kind>:<id>', one hop deep:
-- a transaction is also its request, its customer and its supplier; a quote its request and supplier; a request its
-- customer; a refund its transaction, request, customer and supplier; a support case its party; a notification its person
-- and request. An IT finding is 'finding:<issue_key>', a CEO report or task its own subject.
create or replace function public.fn_pool_kind(p_name text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case
    when lower(coalesce(p_name, '')) in ('lead', 'leads', 'supplier', 'suppliers', 'supplier_id', 'lead_id', 'supplier_lead_id') then 'supplier'
    when lower(coalesce(p_name, '')) in ('customer', 'customers', 'customer_id') then 'customer'
    when lower(coalesce(p_name, '')) in ('inquiry', 'inquiries', 'rfq', 'request', 'requests', 'inquiry_id', 'request_id', 'rfq_id') then 'inquiry'
    when lower(coalesce(p_name, '')) in ('quote', 'quotes', 'quote_id') then 'quote'
    when lower(coalesce(p_name, '')) in ('transaction', 'transactions', 'payment', 'payments', 'transaction_id', 'tx_id', 'original_txn_id') then 'transaction'
    when lower(coalesce(p_name, '')) in ('refund', 'refunds', 'refund_requests', 'refund_id') then 'refund'
    when lower(coalesce(p_name, '')) in ('support_case', 'case_ref', 'case_id') then 'case'
    when lower(coalesce(p_name, '')) in ('notifications', 'notification', 'notification_id') then 'notification'
    when lower(coalesce(p_name, '')) in ('it_engineer_finding', 'issue_key') then 'finding'
    when lower(coalesce(p_name, '')) in ('support_ceo_report') then 'report'
    when lower(coalesce(p_name, '')) in ('ceo_task') then 'task'
    when lower(coalesce(p_name, '')) in ('seat_deliberation') then 'deliberation'
    when lower(coalesce(p_name, '')) in ('agent_actions', 'handoff_id') then 'handoff'
  end
$fn$;
revoke execute on function public.fn_pool_kind(text) from public, anon, authenticated;

-- the table name fn_seat_work_is_demo understands, for an event's entity_type
create or replace function public.fn_pool_table(p_entity_type text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case public.fn_pool_kind(p_entity_type)
    when 'supplier' then 'leads' when 'customer' then 'customers' when 'inquiry' then 'inquiries'
    when 'transaction' then 'transactions' when 'quote' then 'quotes' when 'refund' then 'refunds'
    else p_entity_type end
$fn$;
revoke execute on function public.fn_pool_table(text) from public, anon, authenticated;

create or replace function public.fn_pool_keys(p_table text, p_id text, p_detail jsonb default '{}'::jsonb)
returns text[] language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare k text[] := '{}'; v_kind text := public.fn_pool_kind(p_table);
        v_id text := btrim(coalesce(case when p_id like '%#%' then split_part(p_id, '#', 2) else p_id end, ''));
        d jsonb := case when jsonb_typeof(p_detail) = 'object' then p_detail else '{}'::jsonb end;
        r record; x text; v_handoff bigint;
begin
  if v_kind = 'handoff' and v_id ~ '^\d+$' then
    -- a hand-over about another hand-over (a delivery's result): its subjects are the first one's
    select a.detail into r from public.agent_actions a where a.id = v_id::bigint;
    if found then d := coalesce(r.detail, '{}'::jsonb) || d;
      if coalesce(r.detail->>'subject_table', '') not in ('', 'agent_actions') then
        k := k || public.fn_pool_keys(r.detail->>'subject_table', r.detail->>'subject_id', '{}'::jsonb); end if; end if;
    v_kind := null;
  end if;
  if v_kind is not null and v_id <> '' then k := k || (v_kind || ':' || v_id); end if;
  foreach x in array array['customer_id', 'supplier_id', 'lead_id', 'supplier_lead_id', 'inquiry_id', 'transaction_id', 'quote_id', 'refund_id', 'issue_key', 'case_ref'] loop
    if nullif(btrim(d->>x), '') is not null and jsonb_typeof(d->x) in ('string', 'number') then
      k := k || (public.fn_pool_kind(x) || ':' || btrim(d->>x));
    end if;
  end loop;
  -- one hop: what each key is also about
  foreach x in array k loop
    begin
      case split_part(x, ':', 1)
        when 'transaction' then
          for r in select t.inquiry_id::text i, t.customer_id::text c, t.supplier_id::text s, t.quote_id::text q from public.transactions t where t.id::text = substr(x, 13) loop
            k := k || array_remove(array['inquiry:' || r.i, 'customer:' || r.c, 'supplier:' || r.s, 'quote:' || r.q], null); end loop;
        when 'quote' then
          for r in select q.inquiry_id::text i, q.supplier_id::text s from public.quotes q where q.id::text = substr(x, 7) loop
            k := k || array_remove(array['inquiry:' || r.i, 'supplier:' || r.s], null); end loop;
        when 'refund' then
          for r in select f.inquiry_id::text i, f.customer_id::text c, f.supplier_lead_id::text s, coalesce(f.transaction_id, f.original_txn_id)::text t
                     from public.refunds f where f.id::text = substr(x, 8) loop
            k := k || array_remove(array['inquiry:' || r.i, 'customer:' || r.c, 'supplier:' || r.s, 'transaction:' || r.t], null); end loop;
        when 'case' then
          for r in select c.party_kind, c.party_id::text p from public.support_case c where c.case_ref = substr(x, 6) or c.case_id::text = substr(x, 6) loop
            if public.fn_pool_kind(r.party_kind) is not null and r.p is not null then k := k || (public.fn_pool_kind(r.party_kind) || ':' || r.p); end if; end loop;
        when 'notification' then
          for r in select n.lead_id::text l, n.inquiry_id::text i, n.quote_id::text q from public.notifications n where n.id::text = substr(x, 14) loop
            k := k || array_remove(array['supplier:' || r.l, 'inquiry:' || r.i, 'quote:' || r.q], null); end loop;
        when 'report' then
          for r in select s.verified_evidence->>'issue_key' ik from public.support_ceo_report s where s.id::text = substr(x, 8) loop
            if r.ik is not null then k := k || ('finding:' || r.ik); end if; end loop;
        else null;
      end case;
    exception when invalid_text_representation then null;
    end;
  end loop;
  -- a request is also its customer's
  foreach x in array k loop
    if x like 'inquiry:%' then
      for r in select i.customer_id::text c from public.inquiries i where i.id::text = substr(x, 9) loop
        if r.c is not null then k := k || ('customer:' || r.c); end if; end loop;
    end if;
  end loop;
  return (select coalesce(array_agg(distinct y), '{}') from unnest(k) y where y !~ ':$');
end $fn$;
revoke execute on function public.fn_pool_keys(text, text, jsonb) from public, anon, authenticated;

-- The asked subject, as keys: {supplier_id}, {inquiry_id}, {table, id} ... (a seat's own words).
create or replace function public.fn_pool_subject_keys(p_subject jsonb)
returns text[] language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(array_agg(distinct x), '{}') from (
    select public.fn_pool_kind(e.key) || ':' || btrim(e.value #>> '{}') as x
      from jsonb_each(case when jsonb_typeof(p_subject) = 'object' then p_subject else '{}'::jsonb end) e
     where jsonb_typeof(e.value) in ('string', 'number') and public.fn_pool_kind(e.key) is not null and btrim(e.value #>> '{}') <> ''
    union all
    select public.fn_pool_kind(coalesce(p_subject->>'table', p_subject->>'subject_table')) || ':' || coalesce(p_subject->>'id', p_subject->>'subject_id')
     where jsonb_typeof(p_subject) = 'object' and public.fn_pool_kind(coalesce(p_subject->>'table', p_subject->>'subject_table')) is not null
       and coalesce(p_subject->>'id', p_subject->>'subject_id') is not null) s
$fn$;
revoke execute on function public.fn_pool_subject_keys(jsonb) from public, anon, authenticated;

-- Every hand-over, event and judgement, linked to every subject it is about. Filled at insert by the triggers at the end
-- of this file, and back-filled in batches by fn_pool_link_backfill (the last 30 days), never by a bulk update of the
-- source tables (no lock on agent_actions or company_event, no export trigger fired).
create table if not exists public.subject_link (
  src text not null check (src in ('event', 'handoff', 'judgement')),
  src_id bigint not null,
  key text not null,
  primary key (src, src_id, key));
create index if not exists subject_link_key_idx on public.subject_link (key, src, src_id);
comment on table public.subject_link is 'Which subjects (customer:, supplier:, inquiry:, quote:, transaction:, refund:, case:, finding: ...) each hand-over, event and judgement is about; fn_pool_keys decides; the shared pool reads it (every_seat_reads_one_pool_and_every_hand_over_comes_back.sql).';
alter table public.subject_link enable row level security;
drop policy if exists subject_link_service_role_only on public.subject_link;
create policy subject_link_service_role_only on public.subject_link as permissive for all to public using (false) with check (false);
revoke all on public.subject_link from anon, authenticated;

-- A row about nothing the resolver knows is linked to 'unresolved', so the back-fill does not pick it up again and the
-- coverage measure can count it.
create or replace function public.fn_pool_keys_or_unresolved(p_keys text[])
returns text[] language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case when cardinality(coalesce(p_keys, '{}')) = 0 then array['unresolved'] else p_keys end
$fn$;
revoke execute on function public.fn_pool_keys_or_unresolved(text[]) from public, anon, authenticated;

create or replace function public.fn_pool_link_event(p_id bigint, p_entity_type text, p_entity_id text, p_payload jsonb, p_event_type text)
returns void language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if p_event_type like 'handoff.%' then return; end if;   -- an echo: the hand-over row itself is linked
  insert into public.subject_link (src, src_id, key)
  select 'event', p_id, unnest(public.fn_pool_keys_or_unresolved(public.fn_pool_keys(p_entity_type, p_entity_id, p_payload))) on conflict do nothing;
end $fn$;
revoke execute on function public.fn_pool_link_event(bigint, text, text, jsonb, text) from public, anon, authenticated;

create or replace function public.fn_pool_link_handoff(p_id bigint)
returns void language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a record;
begin
  select id, detail, target_table, target_id into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then return; end if;
  insert into public.subject_link (src, src_id, key)
  select 'handoff', a.id, unnest(public.fn_pool_keys_or_unresolved(public.fn_pool_keys(coalesce(a.detail->>'subject_table', a.target_table), a.detail->>'subject_id', a.detail)))
  on conflict do nothing;
end $fn$;
revoke execute on function public.fn_pool_link_handoff(bigint) from public, anon, authenticated;

create or replace function public.trg_pool_link()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  -- never in the writer's way: a resolver failure leaves the row unlinked (the back-fill retries it)
  begin
    if tg_table_name = 'company_event' then
      perform public.fn_pool_link_event(new.id, new.entity_type, new.entity_id, new.payload, new.event_type);
    elsif tg_table_name = 'agent_actions' then
      perform public.fn_pool_link_handoff(new.id);
    else
      insert into public.subject_link (src, src_id, key)
      select 'judgement', new.id, unnest(public.fn_pool_keys_or_unresolved(public.fn_pool_keys(new.subject_table, new.subject_id, '{}'::jsonb))) on conflict do nothing;
    end if;
  exception when others then null;
  end;
  return null;
end $fn$;
revoke execute on function public.trg_pool_link() from public, anon, authenticated;

-- Batches, newest first, bounded per call, DOWNWARD from the oldest row already linked (the triggers link every new row),
-- so each call reads a primary-key range and the back-fill ends once it passes 30 days: no full scan, no update of the
-- source tables (no lock on agent_actions or company_event, no export trigger fired).
create or replace function public.fn_pool_link_backfill(p_limit integer default 2000)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare n_h int := 0; n_e int := 0; n_j int := 0; r record; v_lim int := greatest(coalesce(p_limit, 2000), 1); v_below bigint;
begin
  v_below := coalesce((select min(src_id) from public.subject_link where src = 'handoff'), (select max(id) + 1 from public.agent_actions));
  for r in select a.id from public.agent_actions a
            where a.id < v_below and a.kind = 'handoff' and a.created_at > now() - interval '30 days'
            order by a.id desc limit v_lim loop
    perform public.fn_pool_link_handoff(r.id); n_h := n_h + 1;
  end loop;
  v_below := coalesce((select min(src_id) from public.subject_link where src = 'event'), (select max(id) + 1 from public.company_event));
  for r in select e.id, e.entity_type, e.entity_id, e.payload, e.event_type from public.company_event e
            where e.id < v_below and e.occurred_at > now() - interval '30 days' and e.event_type not like 'handoff.%'
            order by e.id desc limit v_lim loop
    perform public.fn_pool_link_event(r.id, r.entity_type, r.entity_id, r.payload, r.event_type); n_e := n_e + 1;
  end loop;
  v_below := coalesce((select min(src_id) from public.subject_link where src = 'judgement'), (select max(id) + 1 from public.seat_judgement));
  for r in select j.id, j.subject_table, j.subject_id from public.seat_judgement j
            where j.id < v_below and j.made_at > now() - interval '30 days' and j.subject_table is not null
            order by j.id desc limit v_lim loop
    insert into public.subject_link (src, src_id, key)
    select 'judgement', r.id, unnest(public.fn_pool_keys_or_unresolved(public.fn_pool_keys(r.subject_table, r.subject_id, '{}'::jsonb))) on conflict do nothing;
    n_j := n_j + 1;
  end loop;
  return jsonb_build_object('handoffs', n_h, 'events', n_e, 'judgements', n_j);
end $fn$;
revoke execute on function public.fn_pool_link_backfill(integer) from public, anon, authenticated;

-- ── 3. WHO ACTED, IN WHAT WORDS ───────────────────────────────────────────────────────────────────────────────────
-- The actor PRINTED is the one RECORDED: a seat in actor; a seat the payload names (by / approved_by / decided_by / seat);
-- the seat that wrote the event this one was caused by; a person (an e-mail in actor) only as "the supplier" / "the
-- customer"; and otherwise "the platform (automatic)". Never the type's owner seat: fn_emit_supplier_approved fires with
-- actor 'system' whoever approved, and "the sales engineer verified him" would be a claim nobody recorded (review, 13 Nov).
create or replace function public.fn_pool_who(p_actor text, p_payload jsonb, p_causation_id bigint, p_entity_type text)
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v text; seats text[] := (select array_agg(role_id) from public.org_role where status = 'active');
begin
  if p_actor = any (seats) then return p_actor; end if;
  if coalesce(p_actor, '') like '%@%' then return 'the ' || coalesce(nullif(public.fn_pool_kind(p_entity_type), 'inquiry'), 'other party'); end if;
  if jsonb_typeof(p_payload) = 'object' then
    foreach v in array array['by', 'approved_by', 'decided_by', 'verified_by', 'seat'] loop
      if p_payload->>v = any (seats) then return p_payload->>v; end if;
    end loop;
  end if;
  if p_causation_id is not null then
    select e.actor into v from public.company_event e where e.id = p_causation_id;
    if v = any (seats) then return v; end if;
  end if;
  return 'the platform (automatic)';
end $fn$;
revoke execute on function public.fn_pool_who(text, jsonb, bigint, text) from public, anon, authenticated;

-- What a person would say about an event, for the internal digest and timeline: amounts rounded, the request's trade and
-- emirate, no person's name, phone or e-mail. 'with_name' adds a supplier's company name (the subject's own timeline only).
create or replace function public.fn_pool_say(p_type text, p_entity_type text, p_entity_id text, p_payload jsonb, p_with_name boolean default false)
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare d jsonb := case when jsonb_typeof(p_payload) = 'object' then p_payload else '{}'::jsonb end;
        v_tx text; v_inq text; v_amt numeric; v_req text := ''; v_fee numeric; v_refund numeric; v_tinq text;
        v_cat text; v_emi text; v_rfq text; v_sector text; v_lemi text; v_company text;
begin
  if p_type like 'handoff.%' and p_entity_type = 'agent_actions' and p_entity_id ~ '^\d+$' then
    select a.detail into d from public.agent_actions a where a.id = p_entity_id::bigint;
    d := coalesce(d, '{}'::jsonb);
  end if;
  v_tx := coalesce(d->>'transaction_id', case when coalesce(d->>'subject_table', p_entity_type) in ('transactions', 'transaction')
                                               then split_part(coalesce(d->>'subject_id', p_entity_id), '#', 2) end);
  if v_tx = '' then v_tx := coalesce(d->>'subject_id', p_entity_id); end if;
  select coalesce(t.reveal_fee, t.app_fee), t.refund_amount_aed, t.inquiry_id::text into v_fee, v_refund, v_tinq
    from public.transactions t where t.id::text = v_tx;
  if v_tinq is null and public.fn_pool_kind(p_entity_type) = 'quote' then
    select q.inquiry_id::text into v_tinq from public.quotes q where q.id::text = p_entity_id;
  end if;
  v_inq := coalesce(d->>'inquiry_id', v_tinq, case when public.fn_pool_kind(p_entity_type) = 'inquiry' then p_entity_id end);
  if v_inq is not null then
    select i.category, i.emirate, i.rfq_no::text into v_cat, v_emi, v_rfq from public.inquiries i where i.id::text = v_inq;
    v_req := ' on request ' || coalesce(v_rfq, left(v_inq, 8)) || coalesce(' (' || nullif(concat_ws(', ', v_cat, v_emi), '') || ')', '');
  end if;
  case
    when p_type in ('supplier.approved', 'supplier.applied') then
      select l.sector, l.emirate, l.company_name into v_sector, v_lemi, v_company from public.leads l where l.id::text = p_entity_id;
      return case when p_type = 'supplier.approved' then 'a supplier was approved' else 'a supplier applied' end
        || case when p_with_name and v_company is not null then ': ' || v_company else '' end
        || coalesce(' (' || nullif(concat_ws(', ', nullif(v_sector, ''), nullif(v_lemi, '')), '') || ')', '')
        || case when d->>'verified' = 'false' then ', licence not verified' else '' end;
    when p_type = 'customer.registered' then return 'a customer registered';
    when p_type in ('payment.received', 'payment.failed') then return replace(p_type, '.', ' ') || v_req;
    when p_type in ('rfq.created', 'rfq.classified') then return 'a request was ' || case when p_type = 'rfq.created' then 'posted' else 'classified' end || v_req;
    when p_type = 'quote.received' then
      return 'a quotation' || coalesce(' of AED ' || to_char(round(coalesce((d->>'customer_price')::numeric, (d->>'quote_amount')::numeric)), 'FM999,999,990'), '') || ' arrived' || v_req;
    when p_type like 'handoff.reveal.paid.%' or p_type like 'handoff.reveal.reconcile.%' then
      v_amt := v_fee;
      return 'a customer paid the reveal fee' || coalesce(' of AED ' || to_char(v_amt, 'FM999,990.00'), '') || v_req;
    when p_type like 'handoff.refund.%' then
      return 'refund ' || split_part(p_type, '.', 3) || coalesce(': AED ' || to_char(v_refund, 'FM999,990.00'), '') || v_req;
    when p_type like 'handoff.sale.made.%' then
      return 'a sale was booked' || coalesce(': AED ' || to_char(v_fee, 'FM999,990.00'), '') || v_req;
    when p_type like 'handoff.payment.%' then
      return 'a payment needs a decision (' || split_part(p_type, '.', 3) || ')' || v_req;
    when p_type like 'request.%' then
      return 'request ' || replace(split_part(p_type, '.', 2), '_', ' ') || coalesce(': ' || nullif(concat_ws(', ', d->>'state', d->>'outcome'), ''), '') || v_req;
    when p_type = 'handoff.overdue.escalated' then
      return coalesce(d->>'type', 'a hand-over') || ' from ' || coalesce(d->>'from', '?') || ' to ' || coalesce(d->>'to', '?')
             || ' is overdue; ' || coalesce(d->>'silent_seat', '?') || ' owes the next move';
    else return replace(regexp_replace(p_type, '^handoff\.(.*)\.sent$', '\1'), '_', ' ');
  end case;
end $fn$;
revoke execute on function public.fn_pool_say(text, text, text, jsonb, boolean) from public, anon, authenticated;

-- What a customer or a supplier may read about his OWN matter: neutral words, no seat, no hand-over name, no other party.
create or replace function public.fn_pool_neutral(p_type text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case
    when p_type = 'quote.received' then 'a quotation was received'
    when p_type in ('rfq.created', 'rfq.classified') then 'the request was registered'
    when p_type = 'supplier.approved' then 'the account was approved'
    when p_type = 'supplier.applied' then 'the application was received'
    when p_type = 'customer.registered' then 'the account was created'
    when p_type like 'handoff.reveal.paid.%' or p_type like 'reveal.paid%' then 'the reveal fee was paid'
    when p_type like 'handoff.refund.%' or p_type like 'request.%' then 'the request was updated'
    else 'our team worked on it' end
$fn$;
revoke execute on function public.fn_pool_neutral(text) from public, anon, authenticated;

-- ── 4. THE SUBJECT'S TIMELINE ACROSS SEATS ────────────────────────────────────────────────────────────────────────
-- Internal: every row linked to the subject (subject_link), newest first: when, who (recorded), what, outcome.
-- External (a customer's or supplier's reply): only EVENTS linked to THAT party (customer:<id> / supplier:<id>), in neutral
-- words, never a hand-over or a seat's name. A rival's quotation on a shared request is linked to the rival, not to him, so it
-- never reaches his prompt; a supplier is not told the customer's money (reveal, refund) through this block.
create or replace function public.fn_seat_pool_timeline(p_seat text, p_subject jsonb, p_audience text default 'internal', p_limit integer default 6)
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_keys text[] := public.fn_pool_subject_keys(p_subject); v_ext boolean := coalesce(p_audience, 'internal') <> 'internal';
begin
  if v_ext then
    -- the party's own key only
    v_keys := array(select k from unnest(v_keys) k
                     where (p_audience = 'supplier' and k like 'supplier:%') or (p_audience = 'customer' and k like 'customer:%'));
  end if;
  if cardinality(v_keys) = 0 then return ''; end if;
  return (
  with ids as (select distinct src, src_id from public.subject_link where key = any (v_keys)),
  ev as (
    select e.occurred_at as at, public.fn_pool_who(e.actor, e.payload, e.causation_id, e.entity_type) as who, e.event_type as what,
           public.fn_pool_say(e.event_type, e.entity_type, e.entity_id, e.payload, true) as said, null::text as outcome
      from ids join public.company_event e on ids.src = 'event' and e.id = ids.src_id),
  ho as (
    select a.created_at as at, coalesce(a.detail->>'from', 'the platform (automatic)') as who,
           'handoff.' || coalesce(a.detail->>'type', '?') || '.sent' as what,
           coalesce(a.detail->>'type', 'hand-over') || ' to ' || a.agent as said,
           case
             when a.status = 'done' then 'answered: ' || left(coalesce(a.evidence->'ceo_decision'->>'choice', a.evidence->>'verdict', a.evidence->>'outcome',
                    a.evidence->>'result', a.evidence->>'decision', a.evidence->>'reply', a.evidence->>'note',
                    case when a.evidence ? 'notification_id' then 'sent (notification ' || (a.evidence->>'notification_id') || ')' end, 'done'), 90)
             when a.status = 'failed' then 'FAILED: ' || left(coalesce(a.detail->>'error', 'no reason recorded'), 70)
             when a.evidence ? 'ceo_decision' then 'the CEO decided ' || (a.evidence->'ceo_decision'->>'choice') || '; waiting on ' || coalesce(a.detail->>'awaiting', '?')
             when a.detail ? 'replied_at' and coalesce(a.detail->>'awaiting', '') <> 'ceo judgement'
               then 'answered, waiting on ' || left(coalesce(a.detail->>'awaiting', a.detail->>'from'), 60)
             when now() > coalesce(case when a.detail->>'due_at' ~ '^\d{4}-\d{2}-\d{2}' then (a.detail->>'due_at')::timestamptz end, a.created_at)
                          + coalesce(k.reply_within, interval '1 day')
               then 'NO ANSWER YET from ' || a.agent || ' since ' || to_char(a.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI')
             else 'open with ' || a.agent end
           || case when a.detail ? 'silence' then ' (escalated to ' || (a.detail->'silence'->>'escalated_to') || ')'
                   when a.detail ? 'escalated_report_id' then ' (escalated to the CEO)' else '' end as outcome
      from ids join public.agent_actions a on ids.src = 'handoff' and a.id = ids.src_id
      left join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent),
  jd as (
    select coalesce(j.decided_at, j.made_at) as at, j.seat as who, 'judgement' as what, 'judged ' || j.surface as said,
           left(coalesce(j.decision, '') || coalesce(' -> ' || j.outcome, ''), 90) as outcome
      from ids join public.seat_judgement j on ids.src = 'judgement' and j.id = ids.src_id
     where j.decision is not null),
  -- an external reader gets his own EVENTS only: no hand-over (internal work), no judgement, and a supplier no money event
  -- (a reveal or a refund is the customer's money, told to the supplier by its own notice)
  allx as (select * from ev where not v_ext or p_audience <> 'supplier' or what !~ '(reveal|refund|payment|sale)'
           union all select * from ho where not v_ext union all select * from jd where not v_ext
           order by at desc limit greatest(coalesce(p_limit, 6), 1))
  select coalesce(string_agg(left(regexp_replace(
           to_char(x.at at time zone 'Asia/Dubai', 'DD Mon HH24:MI')
           || case when v_ext then ': ' || public.fn_pool_neutral(x.what)
                   else ' ' || x.who || ': ' || x.said || coalesce(' -- ' || x.outcome, '') end, '\s+', ' ', 'g'), 160),
           E'\n' order by x.at desc), '')
    from allx x);
end $fn$;
revoke execute on function public.fn_seat_pool_timeline(text, jsonb, text, integer) from public, anon, authenticated;

-- ── 5. THE COMPANY TODAY: INCREMENTAL, BOUNDED, CACHED ────────────────────────────────────────────────────────────
-- Measured (LOCAL, review of 13 Nov): on a busy day (5,000 heard events) the first version took 2,082 ms, because every
-- event of the 24 hours was classed demo or real again on every build. Each event is now classed ONCE, when the duty first
-- sees it (pool_event_class, at most 1,000 a tick), and the build only counts.
create table if not exists public.seat_pool_digest (
  seat text not null,
  scope text not null check (scope in ('real', 'demo')),
  built_at timestamptz not null default now(),
  window_from timestamptz not null,
  body text not null,
  counts jsonb not null default '{}'::jsonb,
  primary key (seat, scope));
comment on table public.seat_pool_digest is 'The company-today block each seat reads (fn_seat_pool_context), rebuilt by the ceo.company_pool duty every 15 minutes. Demo and real are separate rows.';
alter table public.seat_pool_digest enable row level security;
drop policy if exists seat_pool_digest_service_role_only on public.seat_pool_digest;
create policy seat_pool_digest_service_role_only on public.seat_pool_digest as permissive for all to public using (false) with check (false);
revoke all on public.seat_pool_digest from anon, authenticated;

create table if not exists public.pool_event_class (
  event_id bigint primary key,
  demo boolean not null,
  occurred_at timestamptz not null);
create index if not exists pool_event_class_at_idx on public.pool_event_class (occurred_at);
comment on table public.pool_event_class is 'Each event the company-today digest counts, classed demo or real once (fn_seat_work_is_demo); kept two days.';
alter table public.pool_event_class enable row level security;
drop policy if exists pool_event_class_service_role_only on public.pool_event_class;
create policy pool_event_class_service_role_only on public.pool_event_class as permissive for all to public using (false) with check (false);
revoke all on public.pool_event_class from anon, authenticated;

-- The parties and requests an event is about, as fn_seat_work_is_demo reads them ([{customer_id}, {inquiry_id} ...]): a
-- hand-over echo carries only the hand-over's id, so without its links a demo payment was classed real (review, 13 Nov).
create or replace function public.fn_pool_ref(p_event_id bigint, p_entity_type text, p_entity_id text)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(jsonb_agg(jsonb_build_object(
           case split_part(l.key, ':', 1) when 'customer' then 'customer_id' when 'supplier' then 'supplier_id'
                when 'inquiry' then 'inquiry_id' else 'transaction_id' end, substr(l.key, position(':' in l.key) + 1))), '[]'::jsonb)
    from public.subject_link l
   where split_part(l.key, ':', 1) in ('customer', 'supplier', 'inquiry', 'transaction')
     and ((p_entity_type = 'agent_actions' and l.src = 'handoff' and l.src_id = case when p_entity_id ~ '^\d+$' then p_entity_id::bigint end)
          or (l.src = 'event' and l.src_id = p_event_id))
$fn$;
revoke execute on function public.fn_pool_ref(bigint, text, text) from public, anon, authenticated;

create or replace function public.fn_seat_pool_digest_build(p_scope text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_scope text; v_n int := 0; v_classed int; v_t0 timestamptz := clock_timestamp();
begin
  delete from public.pool_event_class where occurred_at < now() - interval '2 days';
  insert into public.pool_event_class (event_id, demo, occurred_at)
  select e.id, public.fn_seat_work_is_demo(e.payload::text, coalesce(case when jsonb_typeof(e.payload) = 'object' then e.payload end, '{}'::jsonb)
                                             || jsonb_build_object('pool', public.fn_pool_ref(e.id, e.entity_type, e.entity_id)),
                                           public.fn_pool_table(e.entity_type), e.entity_id), e.occurred_at
    from public.company_event e
   where e.occurred_at > now() - interval '24 hours'
     and exists (select 1 from public.event_subscription es where es.event_type = e.event_type and es.active and es.delivery = 'digest')
     -- a primary-key range from the last event classed (no scan of the table; no index on occurred_at is needed)
     and e.id > coalesce((select max(c.event_id) from public.pool_event_class c), (select max(id) - 20000 from public.company_event))
   order by e.id limit 1000
  on conflict do nothing;
  get diagnostics v_classed = row_count;
  for v_scope in select unnest(case when p_scope in ('real', 'demo') then array[p_scope] else array['real', 'demo'] end) loop
    with evs as (
      select e.id, e.event_type, e.entity_type, e.entity_id, e.payload, e.occurred_at
        from public.pool_event_class c join public.company_event e on e.id = c.event_id
       where c.occurred_at > now() - interval '24 hours' and c.demo = (v_scope = 'demo')),
    heard as (select es.agent_key as seat, e.* from evs e
                join public.event_subscription es on es.event_type = e.event_type and es.active and es.delivery = 'digest'),
    cnt as (select seat, jsonb_object_agg(label, n) as counts, string_agg(n || ' ' || label, ', ' order by n desc, label) as line
              from (select seat, replace(regexp_replace(event_type, '^handoff\.(.*)\.sent$', '\1'), '_', ' ') as label, count(*) as n
                      from heard group by 1, 2) c group by seat),
    notable as (select seat, string_agg(line, '; ' order by at desc) as line from (
                  select seat, occurred_at as at, row_number() over (partition by seat order by occurred_at desc) as rn,
                         public.fn_pool_say(event_type, entity_type, entity_id, payload, false)
                           || ' (' || to_char(occurred_at at time zone 'Asia/Dubai', 'HH24:MI') || ')' as line
                    from heard
                   where event_type ~ '^(supplier\.|request\.|rfq\.created|handoff\.(reveal\.paid|refund\.|sale\.made|payment\.)[a-z_.]*sent$|handoff\.overdue)') n
                 where rn <= 3 group by seat)
    insert into public.seat_pool_digest as d (seat, scope, built_at, window_from, body, counts)
    select st.role_id, v_scope, now(), now() - interval '24 hours',
           left('Last 24 h' || case when v_scope = 'demo' then ' (rehearsal traffic only)' else '' end || ': '
                || coalesce(c.line, 'nothing you follow happened') || '.' || coalesce(' Notable: ' || n.line || '.', ''), 700),
           jsonb_build_object('heard', coalesce(c.counts, '{}'::jsonb))
      from public.org_role st left join cnt c on c.seat = st.role_id left join notable n on n.seat = st.role_id
     where st.status = 'active'
    on conflict (seat, scope) do update set built_at = excluded.built_at, window_from = excluded.window_from,
                                            body = excluded.body, counts = excluded.counts;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('scopes', v_n, 'classed', v_classed, 'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end $fn$;
revoke execute on function public.fn_seat_pool_digest_build(text) from public, anon, authenticated;

-- What waits on a seat, read live (agent_actions_status_idx): it must be fresh and it is the first thing the seat reads.
create or replace function public.fn_seat_pool_waiting(p_seat text)
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with p as (
    select a.id, a.agent, a.created_at, a.detail, a.evidence,
           now() > coalesce(case when a.detail->>'due_at' ~ '^\d{4}-\d{2}-\d{2}' then (a.detail->>'due_at')::timestamptz end, a.created_at)
                   + coalesce(k.reply_within, interval '1 day') as late, coalesce(k.originator_closes, false) as oc
      from public.agent_actions a
      left join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
     where a.status = 'pending' and a.kind = 'handoff' and not coalesce((a.detail->>'demo')::boolean, false)),
  mine_late as (select * from p where detail->>'from' = p_seat and agent <> p_seat and late and not (detail ? 'replied_at') order by created_at),
  c as (select
     (select count(*) from p where agent = p_seat and (not (detail ? 'replied_at') or detail->>'awaiting' = 'ceo judgement')) as to_me,
     (select min(created_at) from p where agent = p_seat and (not (detail ? 'replied_at') or detail->>'awaiting' = 'ceo judgement')) as oldest,
     (select count(*) from p where detail->>'from' = p_seat and detail ? 'replied_at' and oc and detail->>'awaiting' is distinct from 'ceo judgement') as owe,
     (select count(*) from p where detail->'silence'->>'escalated_to' = p_seat) as esc,
     (select count(*) from mine_late) as late_n)
  select concat_ws(' ',
    (select 'NO ANSWER YET: ' || string_agg(m.agent || ' on ' || (m.detail->>'type') || ' #' || m.id || ' since '
              || to_char(m.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || coalesce(' (escalated to ' || (m.detail->'silence'->>'escalated_to') || ')', ''), '; ')
              || case when max(c.late_n) > 2 then ' (+' || (max(c.late_n) - 2) || ' more)' else '' end || '.'
       from (select * from mine_late limit 2) m, c having count(*) > 0),
    (select 'Waiting on you: ' || concat_ws('; ',
              case when c.to_me > 0 then c.to_me || ' hand-over(s) to answer, oldest since ' || to_char(c.oldest at time zone 'Asia/Dubai', 'DD Mon') end,
              case when c.owe > 0 then c.owe || ' answered hand-over(s) you sent and must close' end,
              case when c.esc > 0 then c.esc || ' overdue hand-over(s) escalated to you' end) || '.'
       from c where c.to_me + c.owe + c.esc > 0))
$fn$;
revoke execute on function public.fn_seat_pool_waiting(text) from public, anon, authenticated;

-- ── 6. THE ONE VIEW EVERY SEAT'S MODEL PATH READS ─────────────────────────────────────────────────────────────────
-- ORDER BY IMPORTANCE inside p_budget characters (1,200: the TS header brings it to at most 1,300, about 300 tokens):
-- 1. your hand-overs (no answer yet; what waits on you), 2. the subject's timeline, newest first, as many lines as fit,
-- 3. the company today, cut to what is left. Never builds the digest: no row yet is an empty part (the duty builds it).
create or replace function public.fn_seat_pool_context(p_seat text, p_subject jsonb default null, p_audience text default 'internal', p_budget integer default 1200)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_internal boolean := coalesce(p_audience, 'internal') = 'internal'; v_scope text := 'real';
        v_tl text := ''; v_today text; v_built timestamptz; v_wait text; v_block text := ''; v_line text; v_lines int := 0;
        v_budget int := least(greatest(coalesce(p_budget, 1200), 200), 1200);
begin
  if not exists (select 1 from public.org_role where role_id = p_seat and status = 'active') then
    return jsonb_build_object('seat', p_seat, 'block', '', 'chars', 0, 'reason', 'not a live seat');
  end if;
  if jsonb_typeof(p_subject) = 'object' and p_subject <> '{}'::jsonb then
    if public.fn_seat_work_is_demo(p_subject::text, p_subject) then v_scope := 'demo'; end if;
    v_tl := public.fn_seat_pool_timeline(p_seat, p_subject, p_audience, 20);   -- as many as fit, below
  end if;
  if v_internal then
    v_wait := public.fn_seat_pool_waiting(p_seat);   -- the seat's own hand-overs (demo ones are never filed)
    select d.body, d.built_at into v_today, v_built from public.seat_pool_digest d where d.seat = p_seat and d.scope = v_scope;
  end if;
  if coalesce(v_wait, '') <> '' then v_block := left('YOUR HAND-OVERS: ' || v_wait, v_budget); end if;
  if coalesce(v_tl, '') <> '' and length(v_block) + 60 < v_budget then
    v_block := v_block || case when v_block = '' then '' else E'\n' end || 'THIS SUBJECT (newest first):';
    foreach v_line in array string_to_array(v_tl, E'\n') loop
      exit when length(v_block) + 1 + length(v_line) > v_budget;
      v_block := v_block || E'\n' || v_line; v_lines := v_lines + 1;
    end loop;
  end if;
  if coalesce(v_today, '') <> '' and length(v_block) + 80 < v_budget then
    v_block := v_block || case when v_block = '' then '' else E'\n' end
               || left('THE COMPANY TODAY (built ' || to_char(v_built at time zone 'Asia/Dubai', 'HH24:MI') || ' Dubai): ' || v_today,
                       v_budget - length(v_block) - 1);
  end if;
  return jsonb_build_object('seat', p_seat, 'scope', v_scope, 'block', v_block, 'chars', length(v_block),
                            'timeline_lines', v_lines, 'digest_built_at', v_built);
end $fn$;
revoke execute on function public.fn_seat_pool_context(text, jsonb, text, integer) from public, anon, authenticated;
grant execute on function public.fn_seat_pool_context(text, jsonb, text, integer) to service_role;

-- ── 7. THE DISPATCHER FILES ONLY WHAT MUST BE ANSWERED ────────────────────────────────────────────────────────────
-- Same name and signature as the department dispatcher it replaces, new body: no org_tasks, no departments. For each event
-- whose type has a 'handover' row, the owner files a hand-over of kind action_class to that seat through fn_seat_handoff
-- (which runs the receiver's handler, refuses a demo payload, reports an unregistered kind). event_delivery records it once.
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

-- event.act: the seat that owns an event must act on it. A supplier's application that is already verified is answered at
-- once with that outcome; anything else waits in the seat's queue (its pool's "Waiting on you"), and past its window it is
-- escalated once to the CEO, who decides it (ceo.overdue_handoff). delivery.result failures are NOT routed here: a failed
-- delivery's result already carries retry_request_id and escalation (fn_delivery_result_acts), measured in evidence.
create or replace function public.fn_seat_takes_event_act(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; v_verified boolean;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  if a.detail->>'event_type' = 'supplier.applied' and coalesce(a.detail->>'subject_id', '') ~ '^\d+$' then
    select l.verified into v_verified from public.leads l where l.id = (a.detail->>'subject_id')::bigint;
    if coalesce(v_verified, false) then
      return jsonb_build_object('outcome', 'already verified', 'reply', a.agent || ': the applicant''s licence is already verified');
    end if;
  end if;
  return jsonb_build_object('waiting', a.agent || ' acts on ' || coalesce(a.detail->>'event_type', 'the event'),
    'reply', a.agent || ' owes the next step on ' || coalesce(a.detail->>'event_type', 'the event') || ' (event #' || coalesce(a.detail->>'event_id', '?') || ')');
end $fn$;
revoke execute on function public.fn_seat_takes_event_act(bigint) from public, anon, authenticated;

-- ── 8. THE CEO JUDGES (founder ledger 1688: "we need the judgment, the logic, the reasonability") ──────────────────
-- Before: the CEO's answer to every it.finding was fn_seat_answers_it_finding, code that wrote "acknowledged ... no
-- deterministic remedy" in 0 s, and the CEO's model judgement waited on app_secrets.ceo_model_slot, a key that does not
-- exist. Now the CEO's it.finding is LEFT to the CEO's model: fn_ceo_takes_it_finding answers only "waiting: ceo judgement"
-- (fn_seat_handoff_act stamps replied_at on any waiting answer; the decision moves it to the real time), and the
-- ceo.company_pool duty files at most N a tick, oldest and most severe first, as held questions the existing replay reasons
-- with think() on the CEO's ROUTINE route (_shared/think/routing.ts EASY_DUTY_SURFACE: routine_employee_reasoning, measured
-- AED 0.0106 a call for the CEO over 30 days; never the Opus route at AED 0.42). Not gated on ceo_model_slot. The model hold
-- holds it (fn_reason_held_resolve keeps a 'model_hold' row held); a demo finding is never filed (ruling 1199).
-- THE DAILY CAP IS DATA: decision_policy 'ceo_daily_judgements' = 30 questions and AED 0.50 a day, 5 a tick; the unit cost
-- is read from ai_cost_log (the CEO's routine calls, 7 days) at every tick. 216 it.findings open on 13 Nov: about seven days
-- and AED 2.3 to clear the backlog, then AED 0.10-0.30 a day.
insert into public.decision_policy (key, value, description) values
  ('ceo_daily_judgements', '{"items": 30, "aed": 0.5, "per_tick": 5, "unit_aed_default": 0.0106}'::jsonb,
   'The CEO''s model triage of IT findings and overdue hand-overs (ceo.it_finding, ceo.overdue_handoff): at most items questions and aed AED a day, per_tick a tick. every_seat_reads_one_pool_and_every_hand_over_comes_back.sql')
on conflict (key) do nothing;
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role) values
  ('ceo_needs_the_founder', true, 'Once a day, deduplicated: what only the founder can decide (money, a destructive production change, a fact only he holds) and the CEO''s own overdue hand-overs, which have no superior but him (founder ledger 1688).', 'ceo')
on conflict (kind) do nothing;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file) values
  ('event.act', 'sales_engineer', 'sales_engineer', 'An event the sales engineer owns needs his action (a failed step of a paid request, a supplier application): event_subscription delivery ''handover''.', 'fn_seat_takes_event_act', interval '1 day', false, 'scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql'),
  ('deliberation.rework', 'ceo', 'sales_engineer', 'The review of the seat''s deliberation said revise or reject: the author reworks it by the deadline.', 'fn_seat_takes_deliberation_rework', interval '3 days', false, 'scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql'),
  ('deliberation.rework', 'ceo', 'customer_support', 'The review of the seat''s deliberation said revise or reject: the author reworks it by the deadline.', 'fn_seat_takes_deliberation_rework', interval '3 days', false, 'scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql'),
  ('deliberation.rework', 'ceo', 'marketing', 'The review of the seat''s deliberation said revise or reject: the author reworks it by the deadline.', 'fn_seat_takes_deliberation_rework', interval '3 days', false, 'scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql'),
  ('deliberation.rework', 'ceo', 'accountant', 'The review of the seat''s deliberation said revise or reject: the author reworks it by the deadline.', 'fn_seat_takes_deliberation_rework', interval '3 days', false, 'scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql'),
  ('deliberation.rework', 'ceo', 'it_engineer', 'The review of the seat''s deliberation said revise or reject: the author reworks it by the deadline.', 'fn_seat_takes_deliberation_rework', interval '3 days', false, 'scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql')
on conflict (type, from_seat, to_seat) do update set meaning = excluded.meaning, handler = excluded.handler,
  reply_within = excluded.reply_within, originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;

create or replace function public.fn_ceo_takes_it_finding(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' <> 'it.finding' then raise exception 'fn_ceo_takes_it_finding: % is not an it.finding hand-over', p_id; end if;
  -- no acknowledgement that decides nothing: the CEO's model decides it (ceo.it_finding), the decision is the answer
  return jsonb_build_object('waiting', 'ceo judgement', 'seat', 'ceo',
    'reply', 'Queued for the CEO''s decision (surface ceo.it_finding): fix now, accept the risk, a duplicate, or the founder.');
end $fn$;
revoke execute on function public.fn_ceo_takes_it_finding(bigint) from public, anon, authenticated;
update public.seat_handoff_kind set handler = 'fn_ceo_takes_it_finding'
 where type = 'it.finding' and from_seat = 'it_engineer' and to_seat = 'ceo';

-- How many more questions the CEO may be asked today (Dubai day), by count and by money.
create or replace function public.fn_ceo_judgement_room()
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare p jsonb := coalesce((select value from public.decision_policy where key = 'ceo_daily_judgements'), '{}'::jsonb);
        v_items int := coalesce((p->>'items')::int, 30); v_aed numeric := coalesce((p->>'aed')::numeric, 0.5);
        v_tick int := coalesce((p->>'per_tick')::int, 5); v_unit numeric; v_today int;
begin
  select avg(cost_aed) into v_unit from public.ai_cost_log
   where coalesce(seat, agent_key) = 'ceo' and task_class = 'routine_employee_reasoning' and occurred_at > now() - interval '7 days';
  v_unit := greatest(coalesce(v_unit, (p->>'unit_aed_default')::numeric, 0.0106), 0.0001);
  select count(*) into v_today from public.reasoning_held_question
   where surface in ('ceo.it_finding', 'ceo.overdue_handoff')
     and created_at >= (date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai');
  return jsonb_build_object('room', greatest(0, least(v_items - v_today, floor((v_aed - v_today * v_unit) / v_unit)::int, v_tick)),
    'asked_today', v_today, 'items_cap', v_items, 'aed_cap', v_aed, 'unit_aed', round(v_unit, 4), 'per_tick', v_tick);
end $fn$;
revoke execute on function public.fn_ceo_judgement_room() from public, anon, authenticated;

-- One held question for the CEO. ONCE per (surface, hand-over, round): a refused or failed answer is asked again after a day.
create or replace function public.fn_ceo_ask(p_surface text, p_handoff_id bigint, p_round int, p_question text, p_case jsonb, p_options jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint; v_key text := p_surface || ':' || p_handoff_id || ':' || p_round;
begin
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key, expires_at)
  values ('ceo', p_surface, left(p_question, 4000),
          jsonb_build_object('seat', 'ceo', 'surface', p_surface, 'question', left(p_question, 4000),
            'context', jsonb_build_object('audience', 'internal', 'case', p_case),
            'decision', jsonb_build_object('name', p_surface, 'options', p_options),
            'plan', jsonb_build_object('steps', '[]'::jsonb), 'research', false, 'stakes', 'normal',
            'subject', jsonb_build_object('handoff_id', p_handoff_id, 'round', p_round), 'dedupeKey', v_key),
          jsonb_build_object('pending', jsonb_build_array('decide'), 'filed_by', 'fn_ceo_ask'),
          jsonb_build_object('handoff_id', p_handoff_id, 'round', p_round), 'awaiting_reasoning', v_key, now() + interval '7 days')
  on conflict (dedupe_key) do update set status = 'held', attempts = 0, last_attempt_at = null, expires_at = now() + interval '7 days'
   where reasoning_held_question.status in ('expired', 'failed', 'reasoned', 'applied')
     and coalesce(reasoning_held_question.last_attempt_at, reasoning_held_question.created_at) < now() - interval '24 hours'
  returning id into v_id;
  return v_id;
end $fn$;
revoke execute on function public.fn_ceo_ask(text, bigint, int, text, jsonb, jsonb) from public, anon, authenticated;

create or replace function public.fn_ceo_founder_options()
returns jsonb language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  -- the founder decides only money, a destructive production change, or a fact only he holds (it_founder_decision_class)
  select jsonb_build_array(
    jsonb_build_object('id', 'needs_founder:money', 'meaning', 'only the founder can decide it because it commits money; your answer is the one-sentence question to him'),
    jsonb_build_object('id', 'needs_founder:destructive_production_change', 'meaning', 'only the founder can decide it because it destroys or rewrites production data; your answer is the one-sentence question to him'),
    jsonb_build_object('id', 'needs_founder:fact_only_he_holds', 'meaning', 'only the founder holds the fact that decides it; your answer is the one-sentence question to him'))
$fn$;
revoke execute on function public.fn_ceo_founder_options() from public, anon, authenticated;

-- The duty step: the CEO's open it.findings first, oldest and most severe first, then the hand-overs escalated to him.
create or replace function public.fn_ceo_files_judgements()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_room jsonb := public.fn_ceo_judgement_room(); n int := (v_room->>'room')::int; r record; v_opts jsonb; v_case jsonb;
        n_f int := 0; n_o int := 0; v_round int; v_id bigint;
begin
  if n <= 0 then return v_room || jsonb_build_object('filed', 0); end if;
  for r in select a.*, f.title ftitle, f.where_it_is, f.affected, f.seen_count, f.started_at fstart, f.last_seen_at, f.closed_at fclosed, f.evidence fev
             from public.agent_actions a
             left join public.it_engineer_finding f on f.issue_key = a.detail->>'issue_key'
            where a.kind = 'handoff' and a.agent = 'ceo' and a.status = 'pending' and a.detail->>'type' = 'it.finding'
              and not coalesce((a.detail->>'demo')::boolean, false) and coalesce(a.title, '') not ilike '%ZZ DEMO%'
              and not public.fn_seat_work_is_demo(a.detail::text, a.detail, a.target_table, a.detail->>'subject_id')
              and (not (a.evidence ? 'ceo_decision')
                   or (a.evidence->'ceo_decision'->>'review_at')::timestamptz < now())
              and not exists (select 1 from public.reasoning_held_question q
                               where q.dedupe_key = 'ceo.it_finding:' || a.id || ':' || (coalesce((a.evidence->'ceo_decision'->>'round')::int, 0) + 1)
                                 and (q.status = 'held' or coalesce(q.last_attempt_at, q.created_at) > now() - interval '24 hours'))
            order by case lower(coalesce(a.detail->>'severity', '')) when 'critical' then 0 when 'high' then 1 when 'serious' then 2 when 'moderate' then 3 else 4 end,
                     a.created_at
            limit n loop
    v_round := coalesce((r.evidence->'ceo_decision'->>'round')::int, 0) + 1;
    v_opts := jsonb_build_array(
      jsonb_build_object('id', 'fix_now:sales_engineer', 'meaning', 'the sales engineer fixes it within 7 days (data, configuration or process it controls)'),
      jsonb_build_object('id', 'fix_now:customer_support', 'meaning', 'customer support fixes it within 7 days'),
      jsonb_build_object('id', 'fix_now:accountant', 'meaning', 'the accountant fixes it within 7 days'),
      jsonb_build_object('id', 'fix_now:marketing', 'meaning', 'marketing fixes it within 7 days'),
      jsonb_build_object('id', 'fix_now:it_engineer', 'meaning', 'the IT engineer prepares the code or configuration change within 7 days'),
      jsonb_build_object('id', 'accept_risk', 'meaning', 'accept the risk for 14 days; your answer is the reason; it comes back to you on the review date'))
      || coalesce((select jsonb_agg(jsonb_build_object('id', 'duplicate_of:' || d.id, 'meaning', 'the same fault as open finding #' || d.id || ': ' || left(coalesce(d.detail->>'title', d.detail->>'issue_key'), 80)))
                     from (select x.id, x.detail from public.agent_actions x
                            where x.kind = 'handoff' and x.detail->>'type' = 'it.finding' and x.status = 'pending' and x.id <> r.id
                              and split_part(x.detail->>'issue_key', ':', 1) || ':' || split_part(x.detail->>'issue_key', ':', 2)
                                  = split_part(r.detail->>'issue_key', ':', 1) || ':' || split_part(r.detail->>'issue_key', ':', 2)
                            order by x.id limit 3) d), '[]'::jsonb)
      || public.fn_ceo_founder_options();
    v_case := jsonb_build_object('handoff_id', r.id, 'issue_key', r.detail->>'issue_key', 'title', coalesce(r.ftitle, r.detail->>'title'),
      'severity', r.detail->>'severity', 'where', coalesce(r.where_it_is, r.detail->>'where_it_is'), 'duty', r.detail->>'duty',
      'open_since', r.fstart, 'last_seen', r.last_seen_at, 'seen_count', r.seen_count, 'affected', r.affected,
      'still_open', r.fclosed is null, 'evidence', left(coalesce(r.fev::text, (r.detail->'finding_evidence')::text, ''), 1200),
      'previous_decision', r.evidence->'ceo_decision');
    v_id := public.fn_ceo_ask('ceo.it_finding', r.id, v_round,
      'IT finding #' || r.id || ': "' || left(coalesce(r.ftitle, r.detail->>'title', r.detail->>'issue_key'), 200) || '" ('
        || coalesce(r.detail->>'severity', 'severity not recorded') || ', open since ' || coalesce(to_char(r.fstart at time zone 'Asia/Dubai', 'DD Mon'), '?')
        || ', seen ' || coalesce(r.seen_count::text, '?') || ' times). As CEO, decide what happens next and give the reason in one or two sentences.',
      v_case, v_opts);
    if v_id is not null then n_f := n_f + 1; end if;
  end loop;
  n := n - n_f;
  for r in select a.* from public.agent_actions a
            where n > 0 and a.kind = 'handoff' and a.status = 'pending' and a.detail->'silence'->>'escalated_to' = 'ceo'
              and not (a.detail->'silence' ? 'ceo_decision' and coalesce((a.detail->'silence'->'ceo_decision'->>'review_at')::timestamptz, 'infinity') > now())
              and not exists (select 1 from public.reasoning_held_question q
                               where q.dedupe_key = 'ceo.overdue_handoff:' || a.id || ':' || (coalesce((a.detail->'silence'->'ceo_decision'->>'round')::int, 0) + 1)
                                 and (q.status = 'held' or coalesce(q.last_attempt_at, q.created_at) > now() - interval '24 hours'))
            order by (a.detail->'silence'->>'since')::timestamptz limit greatest(n, 0) loop
    v_round := coalesce((r.detail->'silence'->'ceo_decision'->>'round')::int, 0) + 1;
    v_id := public.fn_ceo_ask('ceo.overdue_handoff', r.id, v_round,
      'Hand-over #' || r.id || ' (' || (r.detail->>'type') || ' from ' || (r.detail->>'from') || ' to ' || r.agent || ') is past its window: '
        || (r.detail->'silence'->>'silent_seat') || ' owes ' || (r.detail->'silence'->>'owes') || ' since '
        || to_char((r.detail->'silence'->>'since')::timestamptz at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || '. As CEO, decide and give the reason.',
      jsonb_build_object('handoff_id', r.id, 'type', r.detail->>'type', 'from', r.detail->>'from', 'to', r.agent, 'silence', r.detail->'silence',
                         'awaiting', r.detail->>'awaiting', 'summary', r.detail->'summary', 'reply', left(coalesce(r.evidence::text, ''), 600)),
      jsonb_build_array(
        jsonb_build_object('id', 'chase', 'meaning', 'hand it back to ' || (r.detail->'silence'->>'silent_seat') || ' with a 2-day deadline; your answer says what is owed'),
        jsonb_build_object('id', 'wait', 'meaning', 'accept the delay for 7 days; your answer is the reason'))
      || public.fn_ceo_founder_options());
    if v_id is not null then n_o := n_o + 1; end if;
  end loop;
  return v_room || jsonb_build_object('filed_it_findings', n_f, 'filed_overdue', n_o);
end $fn$;
revoke execute on function public.fn_ceo_files_judgements() from public, anon, authenticated;

-- Applied by fn_reason_held_resolve when the CEO's model answered (surface ceo.it_finding). An answer that does not decide (no
-- reason, a choice without its seat or id) writes no decision, only detail.ceo_judgement_refused; fn_reason_held_resolve still
-- marks the question applied, so the duty asks it again a day later because the hand-over carries no decision.
create or replace function public.fn_reason_apply_ceo__it_finding(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare q public.reasoning_held_question; h public.agent_actions; v_choice text := p_result->'decision'->>'choice';
        v_base text; v_arg text; v_reason text := btrim(coalesce(p_result->>'answer', '')); v_dec jsonb; v_round int; v_next text;
        v_it bigint; v_seat bigint;
begin
  select * into q from public.reasoning_held_question where id = p_id;
  select * into h from public.agent_actions where id = (q.subject->>'handoff_id')::bigint and kind = 'handoff' for update;
  if not found or h.status <> 'pending' then return jsonb_build_object('skipped', 'the hand-over is no longer open'); end if;
  v_base := split_part(coalesce(v_choice, ''), ':', 1); v_arg := nullif(split_part(coalesce(v_choice, ''), ':', 2), '');
  if v_base not in ('fix_now', 'accept_risk', 'duplicate_of', 'needs_founder') or length(v_reason) < 12
     or (v_base in ('fix_now', 'duplicate_of', 'needs_founder') and v_arg is null) then
    update public.agent_actions set detail = detail || jsonb_build_object('ceo_judgement_refused',
      jsonb_build_object('held_id', p_id, 'choice', v_choice, 'at', now())) where id = h.id;
    return null;
  end if;
  v_round := coalesce((q.subject->>'round')::int, 1);
  v_dec := jsonb_build_object('choice', v_choice, 'reason', left(v_reason, 600), 'model', p_result->>'model', 'held_id', p_id,
             'decided_at', now(), 'round', v_round, 'by', 'ceo (model, surface ceo.it_finding)')
           || case v_base when 'accept_risk' then jsonb_build_object('review_at', now() + interval '14 days')
                          when 'fix_now' then jsonb_build_object('seat', v_arg, 'due_at', now() + interval '7 days')
                          when 'duplicate_of' then jsonb_build_object('duplicate_of', v_arg)
                          else jsonb_build_object('founder_category', v_arg, 'founder_question', left(v_reason, 400)) end;
  v_next := case v_base
    when 'fix_now' then case when v_arg = 'it_engineer' then 'prepare the code or configuration change by ' else 'keep re-checking; ' || v_arg || ' fixes it by ' end
                        || to_char((now() + interval '7 days') at time zone 'Asia/Dubai', 'DD Mon')
    when 'accept_risk' then 'keep watching; the CEO reviews it again on ' || to_char((now() + interval '14 days') at time zone 'Asia/Dubai', 'DD Mon')
    when 'duplicate_of' then 'close it as the same fault as #' || v_arg || ' when you re-verify'
    else 'keep it open; the founder is asked once, in the CEO''s daily note' end;
  update public.agent_actions
     set evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('ceo_decision', v_dec,
           'reply', 'The CEO decided ' || v_choice || ': ' || left(v_reason, 300)),
         detail = detail || jsonb_build_object('replied_at', now(), 'awaiting', 'it_engineer re-verification', 'ceo_next_step', v_next)
   where id = h.id;
  -- the it_engineer's next step, as a hand-over it reads (ceo.decision_closed); the owning seat's too, for fix_now
  v_it := public.fn_seat_handoff('ceo', 'it_engineer', 'ceo.decision_closed', 'agent_actions', h.id || ':' || v_round,
    jsonb_build_object('decision', v_choice, 'reasons', left(v_reason, 600), 'finding_handoff_id', h.id,
                       'issue_key', h.detail->>'issue_key', 'next_step', v_next, 'path', 'it_finding'));
  if v_base = 'fix_now' and v_arg <> 'it_engineer' then
    v_seat := public.fn_seat_handoff('ceo', v_arg, 'ceo.decision_closed', 'agent_actions', h.id || ':' || v_round,
      jsonb_build_object('decision', v_choice, 'reasons', left(v_reason, 600), 'finding_handoff_id', h.id,
                         'issue_key', h.detail->>'issue_key', 'due_at', now() + interval '7 days', 'path', 'it_finding'));
  end if;
  return jsonb_build_object('decided', v_choice, 'handoff_id', h.id, 'it_engineer_handoff', v_it, 'seat_handoff', v_seat);
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__it_finding(bigint, jsonb) from public, anon, authenticated;

create or replace function public.fn_reason_apply_ceo__overdue_handoff(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare q public.reasoning_held_question; h public.agent_actions; v_choice text := p_result->'decision'->>'choice';
        v_base text; v_arg text; v_reason text := btrim(coalesce(p_result->>'answer', '')); v_dec jsonb; v_silent text; v_round int; v_h bigint;
begin
  select * into q from public.reasoning_held_question where id = p_id;
  select * into h from public.agent_actions where id = (q.subject->>'handoff_id')::bigint and kind = 'handoff' for update;
  if not found or h.status <> 'pending' then return jsonb_build_object('skipped', 'the hand-over is no longer open'); end if;
  v_base := split_part(coalesce(v_choice, ''), ':', 1); v_arg := nullif(split_part(coalesce(v_choice, ''), ':', 2), '');
  if v_base not in ('chase', 'wait', 'needs_founder') or length(v_reason) < 12 or (v_base = 'needs_founder' and v_arg is null) then return null; end if;
  v_silent := h.detail->'silence'->>'silent_seat'; v_round := coalesce((q.subject->>'round')::int, 1);
  if v_base = 'chase' and v_silent not in (select role_id from public.org_role where status = 'active' and role_id <> 'ceo') then v_base := 'wait'; end if;
  v_dec := jsonb_build_object('choice', v_choice, 'reason', left(v_reason, 600), 'held_id', p_id, 'decided_at', now(), 'round', v_round,
             'review_at', now() + case v_base when 'wait' then interval '7 days' when 'chase' then interval '2 days' else interval '7 days' end)
           || case when v_base = 'needs_founder' then jsonb_build_object('founder_category', v_arg, 'founder_question', left(v_reason, 400)) else '{}'::jsonb end;
  update public.agent_actions set detail = jsonb_set(detail, '{silence}', coalesce(detail->'silence', '{}'::jsonb) || jsonb_build_object('ceo_decision', v_dec))
   where id = h.id;
  if v_base = 'chase' then
    v_h := public.fn_seat_handoff('ceo', v_silent, 'ceo.decision_closed', 'agent_actions', h.id || ':chase:' || v_round,
      jsonb_build_object('decision', 'chase', 'reasons', left(v_reason, 600), 'overdue_handoff_id', h.id,
                         'due_at', now() + interval '2 days', 'path', 'overdue_handoff'));
  end if;
  return jsonb_build_object('decided', v_choice, 'handoff_id', h.id, 'chase_handoff', v_h);
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__overdue_handoff(bigint, jsonb) from public, anon, authenticated;

-- What only the founder can answer, and the CEO's own overdue hand-overs, once a day, deduplicated, through the founder
-- channel (fn_notify_founder, kind ceo_needs_the_founder). Until fn_founder_brief prints fn_founder_brief_overdue_handoffs
-- (the money-side branch owns that brief), this is how those lines reach him.
create or replace function public.fn_founder_brief_overdue_handoffs(p_limit integer default 8)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with x as (
    select a.id, coalesce(a.evidence->'ceo_decision'->>'decided_at', a.detail->'silence'->>'since') as at,
           case when a.evidence->'ceo_decision'->>'choice' like 'needs_founder:%'
                then 'The CEO asks (' || replace(split_part(a.evidence->'ceo_decision'->>'choice', ':', 2), '_', ' ') || ', IT finding #' || a.id || '): '
                     || (a.evidence->'ceo_decision'->>'founder_question')
                when a.detail->'silence'->'ceo_decision'->>'choice' like 'needs_founder:%'
                then 'The CEO asks (hand-over #' || a.id || '): ' || (a.detail->'silence'->'ceo_decision'->>'founder_question')
                else 'The CEO is late: ' || (a.detail->>'type') || ' to ' || a.agent || ' (#' || a.id || '), '
                     || (a.detail->'silence'->>'silent_seat') || ' owes ' || (a.detail->'silence'->>'owes') || ' since '
                     || to_char((a.detail->'silence'->>'since')::timestamptz at time zone 'Asia/Dubai', 'DD Mon') end as line
      from public.agent_actions a
     where a.kind = 'handoff' and a.status = 'pending'
       and (a.detail->'silence'->>'escalated_to' = 'founder'
            or a.evidence->'ceo_decision'->>'choice' like 'needs_founder:%'
            or a.detail->'silence'->'ceo_decision'->>'choice' like 'needs_founder:%'))
  select jsonb_build_object('count', (select count(*) from x),
    'lines', coalesce((select jsonb_agg(line order by at) from (select * from x order by at limit greatest(coalesce(p_limit, 8), 1)) y), '[]'::jsonb),
    'ids', coalesce((select jsonb_agg(id) from x), '[]'::jsonb))
$fn$;
revoke execute on function public.fn_founder_brief_overdue_handoffs(integer) from public, anon, authenticated;

create or replace function public.fn_ceo_tells_the_founder_daily()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb := public.fn_founder_brief_overdue_handoffs(10);
        v_key text := 'ceo_needs_the_founder:' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD'); v_r jsonb;
begin
  if (v->>'count')::int = 0 then return jsonb_build_object('told', false, 'reason', 'nothing for the founder'); end if;
  if exists (select 1 from public.founder_alerts f where f.dedupe_key = v_key) then
    return jsonb_build_object('told', false, 'reason', 'already told today');
  end if;
  v_r := public.fn_notify_founder('The CEO needs you on ' || (v->>'count') || ' item(s)',
           (select string_agg('- ' || l, E'\n') from jsonb_array_elements_text(v->'lines') l)
             || case when (v->>'count')::int > 10 then E'\n(+' || ((v->>'count')::int - 10) || ' more)' else '' end,
           'high', 'ceo_needs_the_founder', v_key, 'ceo');
  return jsonb_build_object('told', true, 'count', v->>'count', 'result', v_r);
end $fn$;
revoke execute on function public.fn_ceo_tells_the_founder_daily() from public, anon, authenticated;

-- ── 9. A HAND-OVER PAST ITS WINDOW IS ESCALATED ONCE, AS WORK ─────────────────────────────────────────────────────
-- Due is in the WHERE (the first version took the first 100 ids and skipped the ones not yet due: starvation). The silent
-- seat is the one that owes the next move: the seat its own "awaiting" names (our stored text, e.g. "it_engineer
-- re-verification"); else the sender when the receiver answered and the kind is closed by its originator; else the
-- receiver. The escalation goes to the SENDER's superior (org_reporting_edge); for the CEO it is a held question his duty
-- decides (ceo.overdue_handoff), for the founder (the CEO's own) the daily note. ONCE: escalated and detail.silence are set
-- together, and rows another loop escalated (escalated_report_id, fn_ceo_queue_work's flag) are not escalated again.
create or replace function public.fn_handoff_overdue_escalate()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare h record; v_sup text; v_silent text; v_since timestamptz; n_seat int := 0; n_founder int := 0; v_ids bigint[] := '{}';
begin
  for h in select * from (
             select a.id, a.agent, a.detail, a.created_at, coalesce(k.originator_closes, false) as oc,
                    coalesce(case when a.detail->>'due_at' ~ '^\d{4}-\d{2}-\d{2}' then (a.detail->>'due_at')::timestamptz end, a.created_at)
                      + coalesce(k.reply_within, interval '1 day') as due
               from public.agent_actions a
               left join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
              where a.kind = 'handoff' and a.status = 'pending' and not coalesce(a.escalated, false)
                and not (a.detail ? 'escalated_report_id') and not (a.detail ? 'silence')
                and coalesce(a.detail->>'awaiting', '') <> 'ceo judgement'
                and a.created_at > now() - interval '60 days'
                and not coalesce((a.detail->>'demo')::boolean, false) and coalesce(a.title, '') not ilike '%ZZ DEMO%') x
            where x.due < now()
            order by x.due limit 100 loop
    v_silent := (select r.role_id from public.org_role r
                  where r.status = 'active' and coalesce(h.detail->>'awaiting', '') ~ ('(^|[^a-z_])' || r.role_id || '([^a-z_]|$)')
                  order by position(r.role_id in h.detail->>'awaiting') limit 1);
    v_silent := coalesce(v_silent, case when h.detail ? 'replied_at' and h.oc then h.detail->>'from' else h.agent end);
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
             'owes', case when v_silent = h.agent and not (h.detail ? 'replied_at') then 'an answer'
                          when v_silent = h.detail->>'from' then 'the close of an answered hand-over'
                          else coalesce(h.detail->>'awaiting', 'the next step') end))
     where id = h.id;
    insert into public.company_event (event_type, entity_type, entity_id, actor, payload, dedupe_key)
    values ('handoff.overdue.escalated', 'agent_actions', h.id::text, coalesce(h.detail->>'from', 'system'),
            jsonb_build_object('handoff_id', h.id, 'type', h.detail->>'type', 'from', h.detail->>'from', 'to', h.agent,
                               'silent_seat', v_silent, 'since', v_since, 'escalated_to', v_sup,
                               'subject_table', h.detail->>'subject_table', 'subject_id', h.detail->>'subject_id'),
            'handoff.overdue.escalated:' || h.id)
    on conflict (dedupe_key) where dedupe_key is not null do nothing;
    if v_sup = 'founder' then n_founder := n_founder + 1; else n_seat := n_seat + 1; end if;
    v_ids := v_ids || h.id;
  end loop;
  return jsonb_build_object('escalated_to_a_seat', n_seat, 'escalated_to_the_founder', n_founder, 'ids', to_jsonb(v_ids));
end $fn$;
revoke execute on function public.fn_handoff_overdue_escalate() from public, anon, authenticated;

-- ── 10. A REVIEWED DELIBERATION: CLOSED ON AGREEMENT, RETURNED ON REVISE OR REJECT ────────────────────────────────
-- fn_ceo_closes_answered_handoffs closes only deliberations the CEO wrote; an author seat's waited with no closer. But on
-- 13 Nov the 36 compare verdicts of 60 days were 30 revise, 1 reject, 5 none, and no agree: closing them as "review read"
-- would bury the reviewer's objection. So: an agreeing verdict on a task that is done closes it; a revise or a reject goes
-- back to the author as work with a deadline (deliberation.rework), once.
create or replace function public.fn_authors_close_reviewed_deliberations()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; n_closed int := 0; n_back int := 0; v_err jsonb := '[]'::jsonb; v_rule text; v_h bigint;
begin
  for r in select d.id as did, d.author_seat, a.id as hid, t.task_id, t.state, t.closed_at,
                  (select x.verdict from public.seat_deliberation_turn x where x.deliberation_id = d.id and x.phase = 'compare'
                    order by x.round desc, x.id desc limit 1) as verdict
             from public.agent_actions a
             join public.seat_deliberation d on d.id = (case when a.detail->>'subject_id' ~ '^[0-9]+$' then (a.detail->>'subject_id')::bigint end)
             left join public.ceo_task t on d.subject_table = 'ceo_task' and t.task_id = (case when d.subject_id ~ '^[0-9]+$' then d.subject_id::bigint end)
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'deliberation.review'
              and a.detail ? 'replied_at' and d.author_seat <> 'ceo'
              and d.status in ('reviewed', 'no_independent_reviewer')
              and not coalesce((a.detail->>'demo')::boolean, false)
            order by a.id limit 50 loop
    begin
      if lower(coalesce(r.verdict, '')) in ('agree', 'agreed', 'approve', 'approved') and r.state = 'done' then
        v_rule := 'the reviewer agreed and the ceo_task ' || r.task_id || ' it deliberated is done';
        perform public.fn_seat_deliberation_close(r.did, r.author_seat, 'Review agreed; closed because ' || v_rule || '.');
        perform set_config('qd.handoff_closer', '', true);
        insert into public.originator_close_record (seat, handoff_id, handoff_type, rule, reading)
        values (r.author_seat, r.hid, 'deliberation.review', v_rule, jsonb_build_object('deliberation_id', r.did, 'verdict', r.verdict, 'task_id', r.task_id));
        n_closed := n_closed + 1;
      elsif lower(coalesce(r.verdict, '')) in ('revise', 'reject') then
        v_h := public.fn_seat_handoff('ceo', r.author_seat, 'deliberation.rework', 'seat_deliberation', r.did::text,
          jsonb_build_object('deliberation_id', r.did, 'verdict', r.verdict, 'review_handoff_id', r.hid,
                             'due_at', now() + interval '3 days', 'task_id', r.task_id));
        if v_h is not null then n_back := n_back + 1; end if;
      end if;
    exception when others then
      v_err := v_err || jsonb_build_object('handoff', r.hid, 'error', left(sqlerrm, 300));
    end;
  end loop;
  return jsonb_build_object('closed', n_closed, 'returned_to_author', n_back, 'errors', v_err);
end $fn$;
revoke execute on function public.fn_authors_close_reviewed_deliberations() from public, anon, authenticated;

create or replace function public.fn_seat_takes_deliberation_rework(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  return jsonb_build_object('waiting', a.agent || ' reworks deliberation ' || coalesce(a.detail->>'deliberation_id', '?'),
    'reply', a.agent || ' owes a reworked deliberation ' || coalesce(a.detail->>'deliberation_id', '?') || ' on the reviewer''s '
             || coalesce(a.detail->>'verdict', '?') || ' by ' || coalesce(to_char((a.detail->>'due_at')::timestamptz at time zone 'Asia/Dubai', 'DD Mon'), '?'));
end $fn$;
revoke execute on function public.fn_seat_takes_deliberation_rework(bigint) from public, anon, authenticated;

-- ── 11. ONE DUTY RUNS THE POOL ────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_company_pool_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb := '{}'::jsonb;
begin
  begin v := v || jsonb_build_object('links', public.fn_pool_link_backfill(2000));
  exception when others then v := v || jsonb_build_object('links_error', left(sqlerrm, 300)); end;
  begin v := v || jsonb_build_object('digest', public.fn_seat_pool_digest_build(null));
  exception when others then v := v || jsonb_build_object('digest_error', left(sqlerrm, 300)); end;
  begin v := v || jsonb_build_object('dispatch', public.fn_event_dispatch(0));
  exception when others then v := v || jsonb_build_object('dispatch_error', left(sqlerrm, 300)); end;
  begin v := v || jsonb_build_object('overdue', public.fn_handoff_overdue_escalate());
  exception when others then v := v || jsonb_build_object('overdue_error', left(sqlerrm, 300)); end;
  begin v := v || jsonb_build_object('ceo', public.fn_ceo_files_judgements());
  exception when others then v := v || jsonb_build_object('ceo_error', left(sqlerrm, 300)); end;
  begin v := v || jsonb_build_object('deliberations', public.fn_authors_close_reviewed_deliberations());
  exception when others then v := v || jsonb_build_object('deliberations_error', left(sqlerrm, 300)); end;
  begin v := v || jsonb_build_object('founder', public.fn_ceo_tells_the_founder_daily());
  exception when others then v := v || jsonb_build_object('founder_error', left(sqlerrm, 300)); end;
  return v;
end $fn$;
revoke execute on function public.fn_company_pool_tick() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.company_pool', 'ceo', interval '15 minutes', 'fn_company_pool_tick',
   'The shared pool and the CEO''s judgement: link new rows to their subjects, rebuild each seat''s company-today digest, file the hand-overs event_subscription asks for, escalate once every hand-over past its window, file the CEO''s held questions under the daily cap, send deliberations back on revise, and tell the founder once a day.',
   'scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- ── 12. LAST: THE STATEMENTS THAT LOCK BUSY TABLES ────────────────────────────────────────────────────────────────
-- Held only from here to the commit (milliseconds), under lock_timeout: the link triggers (SHARE ROW EXCLUSIVE on
-- company_event, agent_actions and seat_judgement) and the department dispatcher's trigger drop (ACCESS EXCLUSIVE on
-- company_event; it ran fn_event_dispatch on every insert statement and now the duty does).
drop trigger if exists zz_pool_link on public.company_event;
create trigger zz_pool_link after insert on public.company_event for each row execute function public.trg_pool_link();
drop trigger if exists zz_pool_link on public.agent_actions;
create trigger zz_pool_link after insert on public.agent_actions for each row when (new.kind = 'handoff') execute function public.trg_pool_link();
drop trigger if exists zz_pool_link on public.seat_judgement;
create trigger zz_pool_link after insert on public.seat_judgement for each row when (new.subject_table is not null) execute function public.trg_pool_link();
drop trigger if exists trg_company_event_dispatch on public.company_event;
drop function if exists public.trg_company_event_dispatch();
