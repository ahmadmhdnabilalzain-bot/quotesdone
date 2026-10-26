-- CORRECTION, found by the first test: public.transactions ALREADY carries refund_status,
-- refund_reason, refund_requested_at, refund_resolved_at, refund_note, refund_stripe_id,
-- refund_amount_aed, refund_confirmed_at and refund_deadline. My first cut referenced a
-- non-existent stripe_transactions table and, worse, would have become a SECOND place refunds live -
-- exactly the duplicate source of truth the standing rules forbid. transactions.id and quote_id are
-- uuid, not bigint, which the foreign key then caught.
--
-- Resolution. transactions.refund_* stays as the per-reveal STATE the existing os_api refund_resolve
-- flow and customer UI already read. public.refunds is the LEDGER: what a column set on one row
-- structurally cannot hold - more than one partial refund against the same reveal, who approved it
-- and why, the Stripe refund id, settlement, failure reason and reconciliation to finance. The
-- functions keep the two in step, so neither drifts and no existing reader breaks.
alter table public.refunds drop column if exists quote_id;
alter table public.refunds
  add column if not exists transaction_id uuid references public.transactions(id) on delete set null,
  add column if not exists quote_id uuid;
create index if not exists refunds_transaction_idx on public.refunds (transaction_id);

comment on column public.refunds.transaction_id is
  'The reveal this refund is against. transactions.refund_* remains the state the existing UI reads; this ledger holds what a column set cannot - partial refunds, approver, Stripe ids, settlement and reconciliation.';

create or replace function public.fn_refund_request(
  p_amount_fils bigint, p_reason_code text, p_requested_by text,
  p_inquiry_id uuid default null, p_customer_id uuid default null,
  p_supplier_lead_id bigint default null, p_quote_id uuid default null,
  p_payment_intent text default null, p_charge_id text default null,
  p_note text default null, p_transaction_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_auto boolean := false; t public.transactions;
begin
  if p_amount_fils is null or p_amount_fils <= 0 then
    return jsonb_build_object('ok', false, 'error', 'amount_required');
  end if;

  select * into t from public.transactions
   where (p_transaction_id is not null and id = p_transaction_id)
      or (p_transaction_id is null and p_quote_id is not null and quote_id = p_quote_id)
      or (p_transaction_id is null and p_quote_id is null and p_payment_intent is not null and payment_ref = p_payment_intent)
   order by revealed_at desc nulls last limit 1;

  -- Inside the window the customer was promised at reveal, a refund is a commitment already made,
  -- so it does not need a human to agree to it again. Reusing transactions.refund_deadline - which
  -- fn_add_working_days already computed at reveal time - means the window here cannot disagree
  -- with what the customer was told.
  if t.id is not null and t.refund_deadline is not null and t.refund_deadline >= now() then
    v_auto := true;
  end if;

  insert into public.refunds (transaction_id, inquiry_id, customer_id, supplier_lead_id, quote_id,
                              stripe_payment_intent, stripe_charge_id,
                              amount_fils, reason_code, reason_note, requested_by,
                              within_auto_window, status)
  values (t.id, coalesce(p_inquiry_id, t.inquiry_id), coalesce(p_customer_id, t.customer_id),
          coalesce(p_supplier_lead_id, t.supplier_id), coalesce(p_quote_id, t.quote_id),
          coalesce(p_payment_intent, t.payment_ref), p_charge_id,
          p_amount_fils, p_reason_code, p_note, p_requested_by,
          v_auto, case when v_auto then 'approved' else 'requested' end)
  returning id into v_id;

  if v_auto then
    update public.refunds set decided_by = 'policy:auto_window', decided_at = now(),
           decision_note = 'Inside the refund window promised to the customer at reveal (transactions.refund_deadline)'
     where id = v_id;
  end if;

  if t.id is not null then
    update public.transactions
       set refund_status = case when v_auto then 'approved' else 'requested' end,
           refund_reason = coalesce(refund_reason, p_reason_code),
           refund_requested_at = coalesce(refund_requested_at, now()),
           refund_note = coalesce(p_note, refund_note)
     where id = t.id;
  end if;

  return jsonb_build_object('ok', true, 'refund_id', v_id, 'transaction_id', t.id,
                            'status', case when v_auto then 'approved' else 'requested' end,
                            'within_auto_window', v_auto);
end $$;

create or replace function public.fn_refund_decide(
  p_refund_id bigint, p_approve boolean, p_decided_by text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.refunds; v_new text;
begin
  select * into r from public.refunds where id = p_refund_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status <> 'requested' then
    return jsonb_build_object('ok', false, 'error', 'not_decidable', 'status', r.status);
  end if;
  if coalesce(btrim(p_decided_by),'') = '' then
    return jsonb_build_object('ok', false, 'error', 'decider_required');
  end if;
  v_new := case when p_approve then 'approved' else 'rejected' end;
  update public.refunds set status = v_new, decided_by = p_decided_by, decided_at = now(), decision_note = p_note
   where id = p_refund_id;
  if r.transaction_id is not null then
    update public.transactions set refund_status = v_new, refund_resolved_at = now(),
           refund_note = coalesce(p_note, refund_note) where id = r.transaction_id;
  end if;
  return jsonb_build_object('ok', true, 'refund_id', p_refund_id, 'status', v_new);
end $$;

create or replace function public.fn_refund_settle(
  p_stripe_refund_id text, p_status text, p_amount_fils bigint default null,
  p_payment_intent text default null, p_charge_id text default null,
  p_failure_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.refunds; v_status text;
begin
  v_status := case lower(coalesce(p_status,''))
                when 'succeeded' then 'succeeded' when 'failed' then 'failed'
                when 'canceled' then 'cancelled'  when 'cancelled' then 'cancelled'
                else 'processing' end;

  select * into r from public.refunds where stripe_refund_id = p_stripe_refund_id;
  if found and r.status = v_status then
    return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', r.status, 'idempotent', true);
  end if;

  if not found then
    select * into r from public.refunds
     where stripe_refund_id is null and p_payment_intent is not null
       and stripe_payment_intent = p_payment_intent and status in ('approved','processing')
     order by created_at limit 1;
    if found then
      update public.refunds set stripe_refund_id = p_stripe_refund_id,
             stripe_charge_id = coalesce(p_charge_id, stripe_charge_id) where id = r.id;
    else
      -- A refund issued straight from the Stripe dashboard with no request here. Recorded rather
      -- than dropped: an unrecorded refund is precisely the money that never reconciles.
      insert into public.refunds (stripe_refund_id, stripe_payment_intent, stripe_charge_id,
                                  amount_fils, reason_code, reason_note, requested_by, status,
                                  decided_by, decided_at, decision_note)
      values (p_stripe_refund_id, p_payment_intent, p_charge_id, coalesce(p_amount_fils, 1), 'other',
              'Issued outside QuotesDone (Stripe dashboard or API). Recorded by the webhook.',
              'stripe_webhook', 'processing', 'stripe_dashboard', now(),
              'No in-platform request existed for this refund.')
      returning * into r;
    end if;
  end if;

  update public.refunds
     set status = v_status,
         settled_at = case when v_status='succeeded' then coalesce(settled_at, now()) else settled_at end,
         failure_reason = case when v_status='failed' then p_failure_reason else failure_reason end
   where id = r.id;

  if r.transaction_id is not null then
    update public.transactions
       set refund_status = v_status, refund_stripe_id = p_stripe_refund_id,
           refund_amount_aed = round(coalesce(p_amount_fils, 0)/100.0, 2),
           refund_confirmed_at = case when v_status='succeeded' then now() else refund_confirmed_at end
     where id = r.transaction_id;
  end if;

  return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', v_status);
end $$;

-- Backfill whatever the column-only model already recorded, so the ledger is complete from day one
-- rather than starting from now. transactions is empty today; the mechanism is what matters.
insert into public.refunds (transaction_id, inquiry_id, customer_id, supplier_lead_id, quote_id,
                            stripe_payment_intent, stripe_refund_id, amount_fils, reason_code,
                            reason_note, requested_by, requested_at, status, decided_by, decided_at,
                            settled_at, reconciliation_note)
select t.id, t.inquiry_id, t.customer_id, t.supplier_id, t.quote_id, t.payment_ref, t.refund_stripe_id,
       greatest(1, round(coalesce(t.refund_amount_aed, t.reveal_fee, 0) * 100)::bigint),
       'other', coalesce(t.refund_reason, 'backfilled from transactions.refund_*'), 'backfill',
       coalesce(t.refund_requested_at, t.revealed_at, now()),
       case lower(coalesce(t.refund_status,''))
         when 'refunded' then 'succeeded' when 'succeeded' then 'succeeded'
         when 'approved' then 'approved'  when 'rejected'  then 'rejected'
         else 'requested' end,
       case when t.refund_resolved_at is not null then 'backfill:unknown' end,
       t.refund_resolved_at, t.refund_confirmed_at,
       'Backfilled 2 Aug 2026 from transactions.refund_* when the ledger was introduced.'
from public.transactions t
where coalesce(t.refund_status,'') <> ''
  and not exists (select 1 from public.refunds r where r.transaction_id = t.id)
on conflict (stripe_refund_id) do nothing;

revoke all on function public.fn_refund_request(bigint,text,text,uuid,uuid,bigint,uuid,text,text,text,uuid) from public, anon, authenticated;
grant execute on function public.fn_refund_request(bigint,text,text,uuid,uuid,bigint,uuid,text,text,text,uuid) to service_role;
drop function if exists public.fn_refund_request(bigint,text,text,uuid,uuid,bigint,bigint,text,text,text);
