-- A REFUND REQUEST IS ROUTED TO THE CEO, NOT MERELY REFUSED WITHOUT ONE.
--
-- Founder, 8 September 2026: "refunds belong to the CEO from now on" — and, when told the guards had
-- moved: "that was the old rule for refund. now its router to CEO."
--
-- He is pointing at the gap, and he is right. The earlier change moved the GUARD: refunds may no
-- longer reach approved without a standing decision in ceo_approval by an active ceo_identity. But
-- the ROUTE was untouched. fn_refund_request still wrote, in the row it created:
--
--     'HELD FOR THE FOUNDER. Every refund waits for his decision, whatever the amount ... founder
--      instruction, 17 Aug 2026'
--
-- and returned awaiting: 'founder'. So a customer asking for a refund produced a row addressed to a
-- person who is no longer in the loop, and nothing appeared in front of the seat that now decides.
-- A guard without a route is a refusal with no path to a yes: every refund would have sat at
-- 'requested' for ever, and the failure would have looked like nobody getting round to it rather than
-- like a missing wire.
--
-- WHAT THIS ADDS: the request opens a ceo_task. That is the CEO's own work queue, built today, whose
-- constraints already refuse a task marked done without evidence or blocked without a reason. So a
-- refund decision cannot be closed silently or left blocked without saying why.
--
-- WHAT IS CARRIED OVER UNCHANGED, because it was right: whether the request arrived inside the window
-- promised at reveal (transactions.refund_deadline, computed by fn_add_working_days at reveal) is
-- RECORDED AND NEVER ACTED ON. It is exactly the fact the decider wants in front of them, and exactly
-- the fact that must not decide for them. The hole that guards against is a refund approving itself
-- as 'policy:auto_window', which is what happened before 17 August.
--
--   node scripts/apply_sql.mjs scripts/sql/a_refund_request_is_routed_to_the_ceo_not_merely_refused.sql --apply --ddl

begin;

create or replace function public.fn_refund_request(
  p_amount_fils bigint, p_reason_code text, p_requested_by text,
  p_inquiry_id uuid default null, p_customer_id uuid default null,
  p_supplier_lead_id bigint default null, p_quote_id uuid default null,
  p_payment_intent text default null, p_charge_id text default null,
  p_note text default null, p_transaction_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_id bigint; v_task bigint; v_in_window boolean := false; t public.transactions;
begin
  if p_amount_fils is null or p_amount_fils <= 0 then
    return jsonb_build_object('ok', false, 'error', 'amount_required');
  end if;

  select * into t from public.transactions
   where (p_transaction_id is not null and id = p_transaction_id)
      or (p_transaction_id is null and p_quote_id is not null and quote_id = p_quote_id)
      or (p_transaction_id is null and p_quote_id is null and p_payment_intent is not null and payment_ref = p_payment_intent)
   order by revealed_at desc nulls last limit 1;

  -- Recorded, never acted on. Whether the request arrived inside the window promised at reveal is
  -- exactly the kind of thing the decider wants in front of them, and exactly the kind of thing that
  -- must not decide for them.
  if t.id is not null and t.refund_deadline is not null and t.refund_deadline >= now() then
    v_in_window := true;
  end if;

  insert into public.refunds (transaction_id, inquiry_id, customer_id, supplier_lead_id, quote_id,
                              stripe_payment_intent, stripe_charge_id,
                              amount_fils, reason_code, reason_note, requested_by,
                              within_auto_window, status, reconciliation_note)
  values (t.id, coalesce(p_inquiry_id, t.inquiry_id), coalesce(p_customer_id, t.customer_id),
          coalesce(p_supplier_lead_id, t.supplier_id), coalesce(p_quote_id, t.quote_id),
          coalesce(p_payment_intent, t.payment_ref), p_charge_id,
          p_amount_fils, p_reason_code, p_note, p_requested_by,
          v_in_window, 'requested',
          'ROUTED TO THE CEO. Every refund waits for the CEO seat''s decision, whatever the amount '
       || 'and whether or not it is inside the promised window — founder ruling, 8 Sep 2026, '
       || 'replacing his 17 Aug rule that every refund needed him personally. This one is '
       || round(p_amount_fils / 100.0, 2) || ' AED and is '
       || case when v_in_window then 'inside' else 'outside' end || ' the window promised at reveal.')
  returning id into v_id;

  if t.id is not null then
    update public.transactions
       set refund_status = 'requested',
           refund_reason = coalesce(refund_reason, p_reason_code),
           refund_requested_at = coalesce(refund_requested_at, now()),
           refund_note = coalesce(p_note, refund_note)
     where id = t.id;
  end if;

  -- THE ROUTE. Without this the request is recorded and nothing is asked of anyone.
  insert into public.ceo_task (title, detail)
  values (
    'Decide refund ' || v_id || ' — AED ' || round(p_amount_fils / 100.0, 2),
    'Refund ' || v_id || ' requested by ' || coalesce(nullif(btrim(p_requested_by), ''), '(unknown)')
      || ' for ' || round(p_amount_fils / 100.0, 2) || ' AED, reason ' || coalesce(p_reason_code, '(none)')
      || '. Transaction ' || coalesce(t.id::text, '(none matched)')
      || '. The request arrived ' || case when v_in_window then 'INSIDE' else 'OUTSIDE' end
      || ' the refund window promised at reveal — a fact, not a decision.'
      || coalesce(chr(10) || 'Customer note: ' || nullif(btrim(p_note), ''), '')
      || chr(10) || chr(10)
      || 'To approve: write a row in public.ceo_approval (subject_kind = ''refund'') and set '
      || 'refunds.refund_decision_id to it. The guards on public.refunds will refuse the money moving '
      || 'any other way.')
  returning task_id into v_task;

  return jsonb_build_object('ok', true, 'refund_id', v_id, 'transaction_id', t.id,
                            'status', 'requested',
                            'within_auto_window', v_in_window,
                            'auto_approved', false,
                            'ceo_task_id', v_task,
                            'awaiting', 'ceo');
end
$function$;

commit;
