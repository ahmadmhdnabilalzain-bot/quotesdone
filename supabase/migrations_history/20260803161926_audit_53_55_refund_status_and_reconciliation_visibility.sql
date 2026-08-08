-- AUDIT 5.3 + 5.5 — a refund can be paid and appear in no total, no queue and no flag.
--
-- 5.3: fn_refund_settle's create-new-row path hard-codes 'processing' and discards the v_status it
--      just computed, so a first-seen event carrying succeeded lands as in-flight.
-- 5.5: and once it is in-flight-but-actually-paid, every reader loses it — refunded_aed filters
--      succeeded; v_refunds_unreconciled's predicate is (succeeded OR amount unknown);
--      v_refund_metrics has no counter for processing at all; needs_attention is (amount unknown)
--      OR (quarantine), neither of which is true. Real money leaves and nothing says so.
--
-- No customers yet, so nothing is currently mis-stated. That is exactly why now: the first real
-- refund is the worst possible moment to discover this.

-- 5.3 — surgical patch, asserted rather than assumed. Rewriting a 7 kB function by hand to change
-- one token is how unrelated behaviour gets lost.
do $mig$
declare
  d text;
  before_frag constant text := $f$'stripe_webhook', 'processing', 'stripe_dashboard', now(),$f$;
  after_frag  constant text := $f$'stripe_webhook', coalesce(v_status, 'processing'), 'stripe_dashboard', now(),$f$;
  n int;
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n2 on n2.oid = p.pronamespace
   where n2.nspname = 'public' and p.proname = 'fn_refund_settle';
  if d is null then raise exception 'fn_refund_settle not found'; end if;
  if position('v_status' in d) = 0 then
    raise exception 'fn_refund_settle does not declare v_status - the assumption behind this patch is wrong, refusing';
  end if;
  n := (length(d) - length(replace(d, before_frag, ''))) / length(before_frag);
  if n <> 1 then raise exception 'expected exactly 1 hard-coded status literal, found % - refusing to guess', n; end if;
  execute replace(d, before_frag, after_frag);
end $mig$;

-- settled_at as a table invariant rather than surgery on every writer: a refund that is succeeded
-- HAS a settlement time, whatever path set the status.
create or replace function public.fn_refunds_settled_at()
returns trigger language plpgsql as $fn$
begin
  if new.status = 'succeeded' and new.settled_at is null then new.settled_at := now(); end if;
  return new;
end $fn$;
drop trigger if exists trg_refunds_settled_at on public.refunds;
create trigger trg_refunds_settled_at
  before insert or update on public.refunds
  for each row execute function public.fn_refunds_settled_at();

-- 5.5 — make in-flight money visible everywhere it was invisible.
-- v_refund_metrics is dropped rather than replaced because a column is being INSERTED into the
-- middle of the list, which CREATE OR REPLACE VIEW cannot do. No CASCADE: if something depends on
-- it, that should stop this migration and be looked at, not be silently dropped too.
drop view if exists public.v_refund_metrics;

create or replace view public.v_refunds_unreconciled as
select id, settled_at, amount_fils,
       case when amount_fils is null then null::numeric else round(amount_fils::numeric / 100.0, 2) end as amount_aed,
       amount_fils is null as amount_unknown,
       amount_source, currency, reason_code, status, stripe_refund_id, stripe_payment_intent,
       inquiry_id, customer_id, decided_by, reconciliation_note,
       case
         when amount_fils is null then 'amount unknown - resolve before reconciling'
         when status = 'processing' then 'stuck in processing - Stripe may already have paid it; confirm and settle'
         when settled_at is null then 'settled_at missing'
         else 'awaiting reconciliation'
       end as blocker
  from public.refunds r
 where reconciled_at is null
   -- 'processing' added: it was the one status that could hold a KNOWN amount and still match
   -- nothing here, which is how a paid refund became invisible.
   and (status in ('succeeded', 'processing') or amount_fils is null)
 order by (amount_fils is null) desc, settled_at nulls first;

create view public.v_refund_metrics as
select
  count(*) as refunds_total,
  count(*) filter (where status = 'requested')  as awaiting_decision,
  count(*) filter (where status = 'approved')   as approved_not_settled,
  count(*) filter (where status = 'processing') as processing,
  count(*) filter (where status = 'succeeded')  as settled,
  count(*) filter (where status = 'failed')     as failed,
  count(*) filter (where status = 'rejected')   as rejected,
  count(*) filter (where status = 'cancelled')  as cancelled,
  count(*) filter (where within_auto_window)    as inside_auto_window,
  coalesce(round(sum(amount_fils) filter (where status = 'succeeded') / 100.0, 2), 0) as refunded_aed,
  coalesce(round(sum(amount_fils) filter (where status = 'processing') / 100.0, 2), 0) as in_flight_aed,
  count(*) filter (where status = 'processing' and created_at < now() - interval '24 hours') as processing_over_24h,
  count(*) filter (where status = 'succeeded' and amount_fils is null) as settled_amount_unknown,
  count(*) filter (where amount_fils is null) as amount_unknown_total,
  (select coalesce(round(sum(r2.amount_fils) / 100.0, 2), 0) from public.refunds r2
    where r2.status = 'succeeded' and r2.settled_at > now() - interval '30 days') as refunded_aed_30d,
  (select count(*) from public.refunds r3
    where r3.status = 'succeeded' and r3.settled_at > now() - interval '30 days' and r3.amount_fils is null) as refunded_aed_30d_amount_unknown,
  (select count(*) from public.v_refunds_unreconciled) as unreconciled,
  (select count(*) from public.refund_event_quarantine where resolved_at is null) as quarantined_events,
  (select coalesce(jsonb_object_agg(t.reason_code, t.c), '{}'::jsonb)
     from (select reason_code, count(*) c from public.refunds where status = 'succeeded' group by 1) t) as by_reason,
  -- needs_attention now also fires on money stuck in flight. It was (amount unknown) OR (quarantine),
  -- so a paid-but-'processing' refund with a KNOWN amount left it false and the dashboard read
  -- healthy while the money was gone.
  (count(*) filter (where amount_fils is null) > 0)
  or ((select count(*) from public.refund_event_quarantine where resolved_at is null) > 0)
  or (count(*) filter (where status = 'processing' and created_at < now() - interval '24 hours') > 0)
    as needs_attention
from public.refunds;

comment on view public.v_refund_metrics is
  'Refund scoreboard. processing / in_flight_aed / processing_over_24h exist because audit 5.5 found '
  'a refund Stripe had already paid could sit in processing and appear in no total, no queue and no '
  'flag - needs_attention included.';;
