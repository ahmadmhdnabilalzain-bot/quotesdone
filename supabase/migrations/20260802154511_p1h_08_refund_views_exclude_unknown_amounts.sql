-- FINAL ACTION 2, continued - unknown amounts are excluded from every financial total, counted
-- separately, and held in the reconciliation queue until resolved.
--
-- sum() already ignores NULL, so the totals below are correct the moment amount_fils can be NULL.
-- What was missing is the honesty: a total that quietly omits three refunds looks identical to a
-- total that had nothing to omit. Every money figure now carries the number of refunds it could not
-- include, so a reader can see the difference.
--
-- Both views are dropped and recreated rather than replaced: the column list changes, and Postgres
-- will not let CREATE OR REPLACE reshape one.

drop view if exists public.v_refund_metrics;
drop view if exists public.v_refunds_unreconciled;

create view public.v_refunds_unreconciled as
select r.id, r.settled_at, r.amount_fils,
       case when r.amount_fils is null then null else round(r.amount_fils::numeric / 100.0, 2) end as amount_aed,
       r.amount_fils is null as amount_unknown,
       r.amount_source, r.currency, r.reason_code, r.status,
       r.stripe_refund_id, r.stripe_payment_intent, r.inquiry_id, r.customer_id, r.decided_by,
       r.reconciliation_note,
       case when r.amount_fils is null then 'amount unknown - resolve before reconciling'
            when r.settled_at is null  then 'settled_at missing'
            else 'awaiting reconciliation' end as blocker
  from public.refunds r
 where r.reconciled_at is null
   and (r.status = 'succeeded' or r.amount_fils is null)
 order by r.amount_fils is null desc, r.settled_at nulls first;

comment on view public.v_refunds_unreconciled is
  'The finance queue. A refund stays here until it is reconciled - and a refund whose amount is unknown stays here whatever its status, because it cannot be reconciled at all.';

create view public.v_refund_metrics as
select
  count(*) as refunds_total,
  count(*) filter (where status = 'requested') as awaiting_decision,
  count(*) filter (where status = 'approved')  as approved_not_settled,
  count(*) filter (where status = 'succeeded') as settled,
  count(*) filter (where status = 'failed')    as failed,
  count(*) filter (where status = 'rejected')  as rejected,
  count(*) filter (where status = 'cancelled') as cancelled,
  count(*) filter (where within_auto_window)   as inside_auto_window,

  -- Money. NULL amounts are excluded by sum(); the count beside each total says how many.
  coalesce(round(sum(amount_fils) filter (where status = 'succeeded') / 100.0, 2), 0::numeric) as refunded_aed,
  count(*) filter (where status = 'succeeded' and amount_fils is null) as settled_amount_unknown,
  count(*) filter (where amount_fils is null)                          as amount_unknown_total,

  (select coalesce(round(sum(r2.amount_fils) / 100.0, 2), 0::numeric) from public.refunds r2
    where r2.status = 'succeeded' and r2.settled_at > now() - interval '30 days') as refunded_aed_30d,
  (select count(*) from public.refunds r3
    where r3.status = 'succeeded' and r3.settled_at > now() - interval '30 days'
      and r3.amount_fils is null) as refunded_aed_30d_amount_unknown,

  (select count(*) from public.v_refunds_unreconciled) as unreconciled,
  (select count(*) from public.refund_event_quarantine where resolved_at is null) as quarantined_events,

  (select coalesce(jsonb_object_agg(t.reason_code, t.c), '{}'::jsonb)
     from (select reason_code, count(*) as c from public.refunds
            where status = 'succeeded' group by reason_code) t) as by_reason,

  -- One flag a dashboard can act on without reading the columns above.
  (count(*) filter (where amount_fils is null) > 0
   or (select count(*) from public.refund_event_quarantine where resolved_at is null) > 0) as needs_attention
from public.refunds;

comment on view public.v_refund_metrics is
  'Refund totals. Amounts that are unknown are NOT included in any money figure; the count beside each figure says how many were left out. needs_attention is true whenever a total is incomplete.';

-- Resolving an unknown amount by hand, with the correction on the record rather than in a chat.
create or replace function public.fn_refund_amount_resolve(
  p_stripe_refund_id text, p_amount_fils bigint, p_by text, p_source text default 'manual', p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare r public.refunds;
begin
  if coalesce(p_amount_fils, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error', 'amount_must_be_positive');
  end if;
  select * into r from public.refunds where stripe_refund_id = p_stripe_refund_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'refund_not_found'); end if;

  update public.refunds
     set amount_fils = p_amount_fils,
         amount_source = coalesce(p_source, 'manual'),
         reconciliation_note = left('amount resolved by ' || coalesce(p_by,'unknown') || ' on '
             || to_char(now(),'YYYY-MM-DD') || coalesce(': ' || p_note, ''), 500),
         updated_at = now()
   where id = r.id;

  update public.refund_event_quarantine
     set resolved_at = now(), resolved_by = p_by,
         resolution_note = 'amount supplied: ' || p_amount_fils || ' fils'
   where stripe_refund_id = p_stripe_refund_id and resolved_at is null and reason like 'amount unknown%';

  if r.transaction_id is not null then
    update public.transactions set refund_amount_aed = round(p_amount_fils/100.0, 2) where id = r.transaction_id;
  end if;

  return jsonb_build_object('ok', true, 'refund_id', r.id, 'amount_fils', p_amount_fils);
end $fn$;

revoke all on function public.fn_refund_amount_resolve(text, bigint, text, text, text) from public, anon, authenticated;

create or replace view public.v_refund_quarantine_open as
select id, stripe_refund_id, event_type, reason, created_at,
       now() - created_at as waiting,
       payload
  from public.refund_event_quarantine
 where resolved_at is null
 order by created_at;
