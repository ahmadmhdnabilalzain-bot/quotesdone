-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260721194634   name: refund_window_covers_escalation_ladder
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- The refund was unreachable by construction.
--
-- refund_deadline is set at reveal to add_working_days(now, pricing_config.refund_window_working_days)
-- = reveal + 3 working days. The escalation ladder reaches call_due at reveal + 1 working day (notify)
-- + 3 working days (founder call) = 4 or more. customer_api.request_refund rejects anything past
-- refund_deadline, so the window ALWAYS closed before the customer became entitled.
--
-- Fix: once the customer formally notifies, they are pursuing the claim through our own process, so
-- the window is extended to cover the call window plus a claim period after it. GREATEST guarantees
-- this can only ever lengthen a window, never shorten one already granted.
--
-- Unchanged: a customer who never notifies keeps the original reveal + 3 working day window, which is
-- what the reveal fee note and the supplier terms promise.

insert into decision_policy (key, value)
values ('refund_claim_after_call_working_days', '3'::jsonb)
on conflict (key) do nothing;

CREATE OR REPLACE FUNCTION public.fn_notify_supplier(p_transaction uuid, p_actor text DEFAULT 'customer'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t record; st jsonb; sup record; cust_email text; v_admin text; v_subject text; v_body text;
        v_call_days int; v_claim_days int; v_new_deadline timestamptz;
begin
  st := public.fn_refund_state(p_transaction);
  if st ? 'error' then return st; end if;
  if (st->>'can_notify') <> 'true' then
    return jsonb_build_object('ok', false, 'error', 'not_available', 'state', st->>'state',
                              'notify_available_at', st->>'notify_available_at');
  end if;

  select * into t from transactions where id = p_transaction;
  select company_name, coalesce(claimed_by, email) as email into sup from leads where id = t.supplier_id;
  select email into cust_email from customers where id = t.customer_id;
  v_admin := coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),
                      'management@quotesdone.com');

  v_call_days  := coalesce((select value::text::int from decision_policy where key='refund_call_after_working_days'), 3);
  v_claim_days := coalesce((select value::text::int from decision_policy where key='refund_claim_after_call_working_days'), 3);

  v_subject := 'Awaiting your response — QuotesDone reveal #' || left(t.id::text, 8);
  v_body :=
    'Hello,' || chr(10) || chr(10) ||
    'A customer paid to reveal your contact details on QuotesDone on ' ||
      to_char(t.revealed_at at time zone 'Asia/Dubai','DD Mon YYYY') ||
      ' and has not yet heard from you.' || chr(10) || chr(10) ||
    'Everyone is copied on this email so you can simply reply to all and pick it up here.' || chr(10) || chr(10) ||
    'If we have not heard from you within ' || v_call_days::text ||
      ' working days, we will call you. If we still cannot reach you and the customer is refunded, the reveal fee is recovered from your account under the supplier terms.' || chr(10) || chr(10) ||
    'If you have already been in touch with this customer, reply here and we will close this off.' || chr(10) || chr(10) ||
    'QuotesDone';

  insert into notifications(type, to_email, cc_emails, to_role, lead_id, inquiry_id, channel, subject, body, status)
  values ('reveal_no_response_notice', sup.email,
          array_remove(array[cust_email, v_admin], null),
          'supplier', t.supplier_id, t.inquiry_id, 'email', v_subject, v_body, 'queued');

  -- Deadline must outlive the ladder the customer is being asked to follow.
  v_new_deadline := public.fn_add_working_days(
                      public.fn_add_working_days(now(), v_call_days), v_claim_days);

  update transactions
     set customer_notified_at = now(),
         refund_deadline = greatest(coalesce(refund_deadline, now()), v_new_deadline)
   where id = p_transaction;

  insert into agent_actions(agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
  values ('customer_success','supplier_unresponsive','needs_review','high',
          'Supplier not responding after a paid reveal: ' || coalesce(sup.company_name,'#'||t.supplier_id),
          'Customer has formally notified them. Call the supplier after the working-day window; a refund may only be approved once that has elapsed.',
          jsonb_build_object('transaction_id', t.id, 'supplier_id', t.supplier_id,
                             'inquiry_id', t.inquiry_id, 'notified_at', now(),
                             'call_due_at', public.fn_add_working_days(now(), v_call_days),
                             'refund_claim_until', v_new_deadline),
          'transactions', t.id::text);

  return jsonb_build_object('ok', true, 'notified_at', now(),
                            'recipients', jsonb_build_array(sup.email, cust_email, v_admin),
                            'refund_claim_until', v_new_deadline,
                            'state', public.fn_refund_state(p_transaction));
end $function$;
