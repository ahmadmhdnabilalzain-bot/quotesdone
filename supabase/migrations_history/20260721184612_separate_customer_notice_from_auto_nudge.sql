-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260721184612   name: separate_customer_notice_from_auto_nudge
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- COLLISION FIX. fn_notify_supplier stamped nudged_24_at, which is also what the automatic hourly
-- reveal-nudge writes. Sharing the column means the system-sent nudge would satisfy the customer's
-- escalation gate: fn_refund_state would report 'notified_waiting' and start the 3-working-day
-- countdown to a refund WITHOUT the customer ever pressing anything, and the tri-party email that
-- puts management on the thread would never be sent. Two different events need two different columns.
alter table public.transactions
  add column if not exists customer_notified_at timestamptz;

comment on column public.transactions.customer_notified_at is
  'When the CUSTOMER pressed "Notify supplier". Distinct from nudged_24_at, which is the automatic system nudge. Only this one starts the working-day clock toward a refund.';

-- carry over anything already stamped by the customer path (only the test, but be exact)
update public.transactions set customer_notified_at = nudged_24_at
 where customer_notified_at is null and nudged_24_at is not null
   and exists (select 1 from notifications n
               where n.type='reveal_no_response_notice' and n.inquiry_id = transactions.inquiry_id);

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

  v_responded := t.supplier_ack_at is not null
    or exists (select 1 from messages m
               where m.inquiry_id = t.inquiry_id and m.supplier_id = t.supplier_id
                 and m.sender = 'supplier' and coalesce(m.blocked,false) = false
                 and m.created_at > t.revealed_at);

  v_notify_at := case when t.revealed_at is null then null
                      else public.fn_add_working_days(t.revealed_at, v_notify_days) end;
  -- the clock to a refund starts at the CUSTOMER's notice, never at the automatic nudge
  v_call_at   := case when t.customer_notified_at is null then null
                      else public.fn_add_working_days(t.customer_notified_at, v_call_days) end;

  v_state := case
    when t.revealed_at is null                              then 'not_revealed'
    when v_responded                                        then 'supplier_responded'
    when t.refund_status in ('approved','refunded')         then 'refunded'
    when t.customer_notified_at is null and now() < v_notify_at then 'waiting'
    when t.customer_notified_at is null                     then 'notify_available'
    when now() < v_call_at                                  then 'notified_waiting'
    else 'call_due' end;

  return jsonb_build_object(
    'transaction_id', t.id,
    'state', v_state,
    'revealed_at', t.revealed_at,
    'supplier_responded', v_responded,
    'notify_available_at', v_notify_at,
    'can_notify', v_state = 'notify_available',
    'notified_at', t.customer_notified_at,
    'auto_nudged_at', t.nudged_24_at,
    'founder_call_due_at', v_call_at,
    'refund_approvable', v_state = 'call_due',
    'refund_status', t.refund_status,
    'working_days_since_notice', case when t.customer_notified_at is null then 0
                                      else public.fn_working_days_between(t.customer_notified_at, now()) end
  );
end $$;

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

  insert into notifications(type, to_email, cc_emails, to_role, lead_id, inquiry_id, channel, subject, body, status)
  values ('reveal_no_response_notice', sup.email,
          array_remove(array[cust_email, v_admin], null),
          'supplier', t.supplier_id, t.inquiry_id, 'email', v_subject, v_body, 'queued');

  update transactions set customer_notified_at = now() where id = p_transaction;

  insert into agent_actions(agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
  values ('customer_success','supplier_unresponsive','needs_review','high',
          'Supplier not responding after a paid reveal: ' || coalesce(sup.company_name,'#'||t.supplier_id),
          'Customer has formally notified them. Call the supplier after the working-day window; a refund may only be approved once that has elapsed.',
          jsonb_build_object('transaction_id', t.id, 'supplier_id', t.supplier_id,
                             'inquiry_id', t.inquiry_id, 'notified_at', now(),
                             'call_due_at', public.fn_add_working_days(now(),
                               coalesce((select value::text::int from decision_policy where key='refund_call_after_working_days'),3))),
          'transactions', t.id::text);

  return jsonb_build_object('ok', true, 'notified_at', now(),
                            'recipients', jsonb_build_array(sup.email, cust_email, v_admin),
                            'state', public.fn_refund_state(p_transaction));
end $$;

-- The 72-hour refund window was clock hours: a Thursday reveal expired mid-weekend, before the
-- supplier had a working day to respond. Working days, consistent with the rest of the flow.
create or replace function public.trg_reveal_window()
returns trigger language plpgsql
set search_path to 'public','pg_temp' as $$
begin
  if NEW.revealed_at is not null and NEW.refund_deadline is null then
    NEW.refund_deadline := public.fn_add_working_days(NEW.revealed_at,
      coalesce((select value::text::int from decision_policy where key='refund_call_after_working_days'), 3));
    if NEW.refund_status is null then NEW.refund_status := 'window_open'; end if;
  end if;
  return NEW;
end $$;

-- Two hourly jobs implemented the same idea with divergent guards. One survives.
select cron.unschedule('reveal_nudges');
