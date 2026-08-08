-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727085409   name: payment_health_views_and_wiring_v2
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Correct signature: 6 parameters, not 5. The first revoke silently targeted a
-- function that does not exist, which is why anon still held execute on it.
revoke execute on function public.fn_dispute_open(text,text,text,numeric,text,timestamptz) from anon, authenticated, public;

create or replace view public.v_payment_health as
select
  (select count(*) from transactions where revealed_at is not null)                       as reveals_paid,
  (select coalesce(sum(reveal_fee),0) from transactions where revealed_at is not null)    as reveal_revenue_aed,
  (select count(*) from transactions where refund_status is not null and refund_status <> 'none') as refunds,
  (select count(*) from payment_dispute)                                                  as disputes_total,
  (select count(*) from payment_dispute where status = 'needs_response')                  as disputes_open,
  (select count(*) from payment_dispute where status='needs_response' and evidence_due_by < now() + interval '3 days') as disputes_due_soon,
  (select count(*) from payment_dispute where status='lost')                              as disputes_lost,
  case when (select count(*) from transactions where revealed_at is not null) > 0
       then round(100.0 * (select count(*) from payment_dispute)
                       / (select count(*) from transactions where revealed_at is not null), 2) end as dispute_rate_pct,
  case
    when (select count(*) from payment_dispute where status='needs_response' and evidence_due_by < now()) > 0
      then 'OVERDUE DISPUTE - evidence deadline passed, that money is lost'
    when (select count(*) from payment_dispute where status='needs_response') > 0
      then 'DISPUTE AWAITING RESPONSE'
    when (select count(*) from transactions where revealed_at is not null) = 0
      then 'NO PAYMENTS YET - Stripe is live and has processed nothing'
    else 'OK'
  end as state;

create or replace view public.v_payment_reconciliation as
select r.started_at, r.status, r.counts, r.note
from agent_runs r
where r.agent = 'stripe_webhook'
  and (r.status = 'error' or r.note ilike '%PAID BUT NOT RECORDED%')
order by r.started_at desc;

insert into public.org_action_executor (action_class, kind, target, params, active, note, advisory_safe, department)
values ('dispute_open','rpc','fn_dispute_open','{}'::jsonb, true,
        'Records a card dispute, alerts the founder and stores the evidence deadline. Must be called from a Stripe charge.dispute.created webhook once that event is subscribed.', false, 'finance')
on conflict do nothing;

insert into public.critical_capability (capability_key, capability, why_critical, owner_dept, test_kind, test_ref)
values ('dispute_response','Every card dispute is recorded with its evidence deadline and raised to the founder',
        'An unanswered dispute is lost automatically, costs a fee, and a rising dispute rate freezes the Stripe account.',
        'finance','rpc_selftest','fn_dispute_open')
on conflict (capability_key) do update set capability=excluded.capability, why_critical=excluded.why_critical;
