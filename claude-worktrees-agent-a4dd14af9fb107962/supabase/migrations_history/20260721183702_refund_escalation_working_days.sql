-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260721183702   name: refund_escalation_working_days
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Refund escalation, founder's model:
--   reveal paid -> 1 WORKING DAY -> customer may press "Notify supplier"
--   -> one email to customer + supplier + management on the same thread
--   -> 3 WORKING DAYS -> founder calls the supplier personally
--   -> only then may the founder approve the refund
-- Fees (3% reveal recovery, 9% monthly late fee, admin fee) apply ONLY on that path. There is no
-- ongoing commission.

insert into public.decision_policy (key, value, description) values
 ('refund_notify_after_working_days', '1'::jsonb,  'Working days after the reveal is paid before the customer may press "Notify supplier". Working days, so a Friday-evening reveal does not expose the button mid-weekend.'),
 ('refund_call_after_working_days',   '3'::jsonb,  'Working days after the tri-party notice before the founder calls the supplier and a refund may be approved.'),
 ('refund_reveal_fee_pct',            '3'::jsonb,  'Percent of quote value recovered from an unresponsive supplier - equals the reveal fee the customer paid.'),
 ('refund_late_fee_monthly_pct',      '9'::jsonb,  'Monthly late fee on an unpaid supplier due.'),
 ('refund_admin_fee_aed',             '0'::jsonb,  'Flat admin fee added to a refund claim. Left at 0 deliberately - set this to the real figure rather than have code invent one.')
on conflict (key) do nothing;

-- One email, three recipients, one thread. Without this the "tri-party" notice becomes three
-- separate emails nobody can reply-all to, which defeats the point of putting everyone together.
alter table public.notifications add column if not exists cc_emails text[] not null default '{}';
comment on column public.notifications.cc_emails is
  'Additional recipients on the SAME email. send_outbox must pass these as cc so all parties share one thread.';

-- Read-only state for the customer portal: what stage is this reveal at, and what may be done now.
create or replace function public.fn_refund_state(p_transaction uuid)
returns jsonb language plpgsql stable
set search_path to 'public','pg_temp' as $$
declare t record; v_notify_days int; v_call_days int;
        v_responded boolean; v_notify_at timestamptz; v_call_at timestamptz; v_state text;
begin
  select * into t from transactions where id = p_transaction;
  if not found then return jsonb_build_object('error','transaction_not_found'); end if;

  v_notify_days := coalesce((select value::text::int from decision_policy where key='refund_notify_after_working_days'),1);
  v_call_days   := coalesce((select value::text::int from decision_policy where key='refund_call_after_working_days'),3);

  -- "Responded" means the supplier acknowledged OR actually messaged the customer after the reveal.
  -- An ack alone is not contact, but it is a response, and both stop the clock.
  v_responded := t.supplier_ack_at is not null
    or exists (select 1 from messages m
               where m.inquiry_id = t.inquiry_id and m.supplier_id = t.supplier_id
                 and m.sender = 'supplier' and coalesce(m.blocked,false) = false
                 and m.created_at > t.revealed_at);

  v_notify_at := case when t.revealed_at is null then null
                      else public.fn_add_working_days(t.revealed_at, v_notify_days) end;
  v_call_at   := case when t.nudged_24_at is null then null
                      else public.fn_add_working_days(t.nudged_24_at, v_call_days) end;

  v_state := case
    when t.revealed_at is null                      then 'not_revealed'
    when v_responded                                then 'supplier_responded'
    when t.refund_status in ('approved','refunded') then 'refunded'
    when t.nudged_24_at is null and now() < v_notify_at then 'waiting'
    when t.nudged_24_at is null                     then 'notify_available'
    when now() < v_call_at                          then 'notified_waiting'
    else 'call_due' end;

  return jsonb_build_object(
    'transaction_id', t.id,
    'state', v_state,
    'revealed_at', t.revealed_at,
    'supplier_responded', v_responded,
    'notify_available_at', v_notify_at,
    'can_notify', v_state = 'notify_available',
    'notified_at', t.nudged_24_at,
    'founder_call_due_at', v_call_at,
    -- refund approval is the founder's alone, and only after the call window has elapsed
    'refund_approvable', v_state = 'call_due',
    'refund_status', t.refund_status,
    'working_days_since_notice', case when t.nudged_24_at is null then 0
                                      else public.fn_working_days_between(t.nudged_24_at, now()) end
  );
end $$;

-- The customer presses the button. Guarded so it cannot fire early, twice, or after a response.
create or replace function public.fn_notify_supplier(p_transaction uuid, p_actor text default 'customer')
returns jsonb language plpgsql
security definer
set search_path to 'public','pg_temp' as $$
declare t record; st jsonb; sup record; cust_email text; v_admin text; v_subject text; v_body text;
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

  v_subject := 'Awaiting your response — QuotesDone reveal #' || left(t.id::text, 8);
  v_body :=
    'Hello,' || chr(10) || chr(10) ||
    'A customer paid to reveal your contact details on QuotesDone on ' ||
      to_char(t.revealed_at at time zone 'Asia/Dubai','DD Mon YYYY') ||
      ' and has not yet heard from you.' || chr(10) || chr(10) ||
    'Everyone is copied on this email so you can simply reply to all and pick it up here.' || chr(10) || chr(10) ||
    'If we have not heard from you within ' ||
      coalesce((select value::text from decision_policy where key='refund_call_after_working_days'),'3') ||
      ' working days, we will call you. If we still cannot reach you and the customer is refunded, the reveal fee is recovered from your account under the supplier terms.' || chr(10) || chr(10) ||
    'If you have already been in touch with this customer, reply here and we will close this off.' || chr(10) || chr(10) ||
    'QuotesDone';

  -- Supplier is the addressee; customer and management are cc'd so all three share one thread.
  insert into notifications(type, to_email, cc_emails, to_role, lead_id, inquiry_id, channel, subject, body, status)
  values ('reveal_no_response_notice', sup.email,
          array_remove(array[cust_email, v_admin], null),
          'supplier', t.supplier_id, t.inquiry_id, 'email', v_subject, v_body, 'queued');

  update transactions set nudged_24_at = now() where id = p_transaction;

  insert into agent_actions(agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
  values ('customer_success','supplier_unresponsive','needs_review','high',
          'Supplier not responding after a paid reveal: ' || coalesce(sup.company_name,'#'||t.supplier_id),
          'Customer has formally notified them. Call the supplier after the working-day window; a refund may only be approved once that has elapsed.',
          jsonb_build_object('transaction_id', t.id, 'supplier_id', t.supplier_id,
                             'inquiry_id', t.inquiry_id, 'notified_at', now(),
                             'call_due_at', public.fn_add_working_days(now(),
                               coalesce((select value::text::int from decision_policy where key='refund_call_after_working_days'),3))),
          'transactions', t.id::text)
  on conflict do nothing;

  return jsonb_build_object('ok', true, 'notified_at', now(),
                            'recipients', jsonb_build_array(sup.email, cust_email, v_admin),
                            'state', public.fn_refund_state(p_transaction));
end $$;

comment on function public.fn_notify_supplier is
  'Customer-initiated notice after one working day of silence on a paid reveal. Sends ONE email with the supplier as addressee and the customer + management cc''d, so all three are on one thread. Idempotent via nudged_24_at.';
