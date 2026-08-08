-- FOUNDER DECISION, 4 August 2026.
--
-- "Auto-approve AND auto-pay inside the window, with a hard ceiling of AED 2,000. Above the
--  ceiling, BOTH the approval and the payment wait for a human."
--
-- WHY THE OLD SHAPE WAS WRONG. fn_refund_request auto-approved any in-window refund at any size
-- (decided_by='policy:auto_window'), while refunds_api's Stripe execution required a live Control
-- Mode session. So the liability was recorded automatically and the payment was gated - which does
-- not protect the money, it only delays a debt already accepted, and turns a published "3 working
-- days" promise into "whenever the founder opens Control Mode". The real control point is the
-- approval. This migration moves the ceiling there.
--
-- The reveal fee is 3% of the quote amount with the cap set to 99,999,999 - effectively uncapped -
-- so exposure scales with the job: AED 1,500 on a 50k quote, 15,000 on a 500k fit-out, 60,000 on a
-- 2M project. Meanwhile finance/money_move was already gated above AED 10,000. A 60,000 AED refund
-- was autonomous while a 10,001 AED payment was gated, in the same table.
--
-- ONE NUMBER IN ONE PLACE. The ceiling lives in org_authority.threshold_aed and is READ here rather
-- than hardcoded, so raising it later is an UPDATE and not a migration - and fn_org_authority_guard
-- will demand a stated reason for that UPDATE, which is exactly right.
--
-- FAIL CLOSED. If no threshold is declared the function auto-approves NOTHING. An absent policy must
-- never read as unlimited authority.
--
-- within_auto_window keeps its literal meaning: the request arrived inside the window the customer
-- was promised. It is no longer a synonym for "auto-approved", because those are now two different
-- facts and conflating them is how a column starts lying.
set local app.change_reason = 'Founder decision 4 Aug 2026: declare the missing ceiling on automatic in-window reveal-fee refunds. This threshold was NULL, which the runtime read as unlimited - a 60,000 AED refund on a 2M quote was autonomous while a 10,001 AED payment was gated. Setting it to 2,000 AED is a restriction, not a widening.';

update public.org_authority
   set threshold_aed = 2000
 where dept_key = 'customer_success' and action_class = 'refund_within_window';

create or replace function public.fn_refund_request(
  p_amount_fils bigint, p_reason_code text, p_requested_by text,
  p_inquiry_id uuid default null, p_customer_id uuid default null,
  p_supplier_lead_id bigint default null, p_quote_id uuid default null,
  p_payment_intent text default null, p_charge_id text default null,
  p_note text default null, p_transaction_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_id bigint; v_in_window boolean := false; v_auto boolean := false;
        v_thr numeric; v_thr_fils bigint; t public.transactions;
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
    v_in_window := true;
  end if;

  select threshold_aed into v_thr from public.org_authority
   where dept_key = 'customer_success' and action_class = 'refund_within_window';
  v_thr_fils := case when v_thr is null then null else (v_thr * 100)::bigint end;

  v_auto := v_in_window and v_thr_fils is not null and p_amount_fils <= v_thr_fils;

  insert into public.refunds (transaction_id, inquiry_id, customer_id, supplier_lead_id, quote_id,
                              stripe_payment_intent, stripe_charge_id,
                              amount_fils, reason_code, reason_note, requested_by,
                              within_auto_window, status, reconciliation_note)
  values (t.id, coalesce(p_inquiry_id, t.inquiry_id), coalesce(p_customer_id, t.customer_id),
          coalesce(p_supplier_lead_id, t.supplier_id), coalesce(p_quote_id, t.quote_id),
          coalesce(p_payment_intent, t.payment_ref), p_charge_id,
          p_amount_fils, p_reason_code, p_note, p_requested_by,
          v_in_window, case when v_auto then 'approved' else 'requested' end,
          case
            when v_in_window and not v_auto and v_thr_fils is null
              then 'HELD FOR A HUMAN: inside the refund window, but no ceiling is declared in '
                || 'org_authority(customer_success, refund_within_window), so nothing is auto-approved.'
            when v_in_window and not v_auto
              then 'HELD FOR A HUMAN: inside the refund window, but ' || round(p_amount_fils/100.0, 2)
                || ' AED is above the declared ceiling of ' || v_thr || ' AED.'
            else null end)
  returning id into v_id;

  if v_auto then
    update public.refunds set decided_by = 'policy:auto_window', decided_at = now(),
           decision_note = 'Inside the refund window promised to the customer at reveal '
             || '(transactions.refund_deadline) and at or below the declared ceiling of ' || v_thr || ' AED.'
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
                            'within_auto_window', v_in_window,
                            'auto_approved', v_auto,
                            'ceiling_aed', v_thr);
end $function$;

comment on function public.fn_refund_request(bigint,text,text,uuid,uuid,bigint,uuid,text,text,text,uuid) is
  'Records a refund request. Auto-approves only when the request is inside transactions.refund_deadline '
  'AND at or below org_authority.threshold_aed for (customer_success, refund_within_window). A NULL '
  'threshold auto-approves nothing. Founder decision 4 Aug 2026; ceiling AED 2,000.';;
