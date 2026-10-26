-- PHASE 1 HARDENING 3 - REFUND SETTLEMENT SURVIVES OUT-OF-ORDER AND DUPLICATE DELIVERY
--
-- Stripe guarantees at-least-once delivery, not ordering. The Phase 1 version applied whatever
-- status arrived last, so this sequence lost money-truth:
--     refund.updated  (succeeded)   -> refunds.status = succeeded, settled_at set
--     refund.created  (pending)     -> refunds.status = processing        <-- regression
-- A refund that has completed then reads as still in flight, the reconciliation view lists it as
-- outstanding, and finance chases a payment that already left. Nothing in the old function stopped
-- it, and it needs no unusual conditions: two events emitted milliseconds apart routinely arrive
-- reversed.
--
-- Status now moves in one direction only, by rank:
--     processing (1) -> cancelled (2) -> failed (3) -> succeeded (4)
-- A lower-ranked arrival is recorded as out-of-order and discarded. An equal one is idempotent.
-- succeeded is absorbing: once Stripe has confirmed the money moved, nothing downgrades it.

create or replace function public.fn_refund_status_rank(p_status text)
returns int language sql immutable as $fn$
  select case lower(coalesce(p_status,''))
           when 'succeeded' then 4 when 'failed' then 3
           when 'cancelled' then 2 when 'canceled' then 2
           else 1 end;
$fn$;

create or replace function public.fn_refund_settle(
  p_stripe_refund_id text, p_status text, p_amount_fils bigint default null,
  p_payment_intent text default null, p_charge_id text default null, p_failure_reason text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare r public.refunds; v_status text; v_new_rank int; v_old_rank int; v_amount bigint; v_note text;
begin
  if coalesce(btrim(p_stripe_refund_id),'') = '' then
    return jsonb_build_object('ok', false, 'error', 'stripe_refund_id_required');
  end if;

  v_status := case lower(coalesce(p_status,''))
                when 'succeeded' then 'succeeded' when 'failed' then 'failed'
                when 'canceled' then 'cancelled'  when 'cancelled' then 'cancelled'
                else 'processing' end;
  v_new_rank := public.fn_refund_status_rank(v_status);

  select * into r from public.refunds where stripe_refund_id = p_stripe_refund_id for update;

  if found then
    v_old_rank := public.fn_refund_status_rank(r.status);
    -- Same state twice: duplicate delivery. Cheap, silent, correct.
    if r.status = v_status then
      return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', r.status,
                                'idempotent', true, 'applied', false);
    end if;
    -- An older state arriving late. Recorded, not applied.
    if v_new_rank < v_old_rank then
      update public.refunds
         set reconciliation_note = left(coalesce(reconciliation_note || ' | ', '')
             || 'out-of-order ' || v_status || ' event ignored at ' || to_char(now(),'YYYY-MM-DD HH24:MI') , 500)
       where id = r.id;
      return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', r.status,
                                'out_of_order', true, 'applied', false, 'ignored_status', v_status);
    end if;
  else
    -- Not seen before. Attach it to an in-platform request for the same payment intent if one is
    -- waiting; otherwise it was issued straight from the Stripe dashboard.
    select * into r from public.refunds
     where stripe_refund_id is null and p_payment_intent is not null
       and stripe_payment_intent = p_payment_intent and status in ('approved','processing')
     order by created_at limit 1 for update;

    if found then
      update public.refunds set stripe_refund_id = p_stripe_refund_id,
             stripe_charge_id = coalesce(p_charge_id, stripe_charge_id) where id = r.id;
      v_old_rank := public.fn_refund_status_rank(r.status);
    else
      -- amount_fils carries a CHECK (> 0), so a missing amount cannot simply be stored as zero.
      -- It is stored as 1 fils and said so in writing, because a refund recorded with an obviously
      -- wrong amount and a note gets fixed, while a refund that was never recorded does not.
      v_amount := nullif(coalesce(p_amount_fils, 0), 0);
      v_note := case when v_amount is null
                then 'Issued outside QuotesDone (Stripe dashboard or API). THE EVENT CARRIED NO AMOUNT - the 1 fils here is a placeholder, check Stripe and correct it.'
                else 'Issued outside QuotesDone (Stripe dashboard or API). Recorded by the webhook.' end;
      insert into public.refunds (stripe_refund_id, stripe_payment_intent, stripe_charge_id,
                                  amount_fils, reason_code, reason_note, requested_by, status,
                                  decided_by, decided_at, decision_note, reconciliation_note)
      values (p_stripe_refund_id, p_payment_intent, p_charge_id, coalesce(v_amount, 1), 'other',
              v_note, 'stripe_webhook', 'processing', 'stripe_dashboard', now(),
              'No in-platform request existed for this refund.',
              case when v_amount is null then 'amount missing from the Stripe event' else null end)
      returning * into r;
      v_old_rank := 1;
      if v_new_rank < v_old_rank then v_new_rank := v_old_rank; end if;
    end if;
  end if;

  update public.refunds
     set status = v_status,
         amount_fils = case when coalesce(p_amount_fils,0) > 0 then p_amount_fils else amount_fils end,
         stripe_charge_id = coalesce(p_charge_id, stripe_charge_id),
         stripe_payment_intent = coalesce(p_payment_intent, stripe_payment_intent),
         settled_at = case when v_status = 'succeeded' then coalesce(settled_at, now()) else settled_at end,
         failure_reason = case when v_status = 'failed' then p_failure_reason else failure_reason end,
         updated_at = now()
   where id = r.id;

  if r.transaction_id is not null then
    update public.transactions
       set refund_status = v_status, refund_stripe_id = p_stripe_refund_id,
           refund_amount_aed = case when coalesce(p_amount_fils,0) > 0
                                    then round(p_amount_fils/100.0, 2) else refund_amount_aed end,
           refund_confirmed_at = case when v_status = 'succeeded' then coalesce(refund_confirmed_at, now())
                                      else refund_confirmed_at end
     where id = r.transaction_id;
  end if;

  return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', v_status, 'applied', true);
end $fn$;

revoke all on function public.fn_refund_settle(text, text, bigint, text, text, text) from public, anon, authenticated;
revoke all on function public.fn_refund_status_rank(text) from public, anon, authenticated;

comment on function public.fn_refund_settle(text, text, bigint, text, text, text) is
  'Applies a Stripe refund event. Idempotent on repeat delivery and monotonic in status, so out-of-order events cannot walk a settled refund backwards.';
