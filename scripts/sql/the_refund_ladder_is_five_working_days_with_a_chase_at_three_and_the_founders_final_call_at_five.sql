-- THE REFUND LADDER IS FIVE WORKING DAYS: A CHASE AT THREE, THE FOUNDER'S FINAL CALL AT FIVE.
--
-- Founder decision, 6 Sep 2026, verbatim (recorded below in decision_policy so no employee re-asks):
--   "refund admin fee is 250 AED dont remove it. also the 3% (which the customer paid and got refunded
--    for) is included along with 9% interest annually as per UAE law maximum limit. refund policy is
--    basically 5 working days from the time customer pays, so after 3 days if there is no response from
--    the supplier, our agent should chase and on the 5th day i should be notified to do a final call. if
--    no response we issue the refund and as per the banks usually it takes 7-14 working days. of course
--    this should be updated everywhere and you should never ask me about it again."
--   and: the chase is done by the EXISTING employee who owns supplier follow-up, never a new agent.
--
-- WHAT PRODUCTION DID BEFORE THIS FILE (measured 6 Sep 2026 10:53 UTC):
--   pricing_config.refund_window_working_days = 3; decision_policy refund_notify_after_working_days = 1,
--   refund_call_after_working_days = 3, refund_claim_after_call_working_days = 3. The ladder was
--   reveal + 1 working day (customer may notify) + 3 (founder call) + 3 (claim) and the clock started at
--   the CUSTOMER's notice, so a customer who never pressed "notify" was never chased and the founder
--   was never called. trg_reveal_window opened the window from decision_policy while stripe_confirm
--   opened it from pricing_config: two sources for one date. qd_notify_refund_request emailed the
--   founder's mailbox directly at request time, outside founder_mail_policy. Nothing told the customer
--   how long the bank takes. transactions holds 0 rows, so no live case is mid-ladder.
--
-- WHERE THE AED 250 AND THE 9% LIVE (read, not moved): qd_on_refund_resolved charges the SUPPLIER a
--   supplier_dues row of the refunded 3% fee + gl_settings.clawback_admin_fee_aed (250) with interest
--   accruing at gl_settings.clawback_interest_monthly_pct 0.75%/month = 9% p.a. once overdue;
--   collections_legal computes that interest at decision_policy refund_late_fee_annual_pct (9). The
--   published Refund Policy says no administrative charge is deducted from the customer's refund, and
--   the customer's refund is the fee paid (fn_refund_amount_is_the_fee_paid enforces it). The founder's
--   sentence describes exactly that composition of the supplier's charge; this file keeps it and puts
--   the arithmetic in ONE function, fn_refund_amount_aed.
--
-- WHAT THIS FILE DOES:
--   1. pricing_config: refund_window_working_days 3 -> 5; NEW chase_after_working_days (3),
--      bank_settlement_working_days_min/max (7/14); one check constraint on the ladder.
--   2. decision_policy: the founder's sentence verbatim; refund_call_after_working_days -> 5.
--   3. founder_mail_policy: refund_final_call (allowed - it is his final call), refund_complaint
--      (routed to the Customer Success Director, the existing owner of supplier follow-up).
--   4. fn_refund_amount_aed(paid, paid_at, refund_at): the one computation - customer refund in full,
--      9% p.a. simple interest pro-rated by calendar days, AED 250 admin fee, supplier charge.
--   5. trg_reveal_window, fn_refund_state, fn_notify_supplier restated on the new ladder, all reading
--      pricing_config (one source); fn_notify_supplier no longer stretches the window.
--   6. qd_notify_refund_request: the complaint goes to the owning employee through fn_notify_founder /
--      fn_founder_mail_route, not to his inbox. qd_on_refund_resolved: the customer is told the refund
--      is issued and that banks take 7-14 working days (the admin-fee due it raises is unchanged).
--   7. fn_refund_ladder_sweep(): deterministic, no model. Day 3 without a supplier response: chase email
--      to the supplier (customer cc'd; fn_wa_fanout adds WhatsApp when the supplier opted in) and an
--      org_task for the Customer Success Director (runtime agent 'followup'). Day 5: the refund request
--      is filed through fn_refund_request (the ONE door, still founder-gated) and the founder is
--      notified with the facts (kind refund_final_call). Idempotent by state.
--   8. cron refund_ladder_sweep_hourly, wrapped under customer_success_director / customer_experience.
--
--   6b. trg_reveal_receipt and qd_reveal_nudges (the reveal receipts and the 24h/48h nudges) state the same
--      ladder from pricing_config; qd_on_refund_resolved books the supplier's interest from fn_refund_amount_aed.
--
--   node scripts/apply_sql.mjs scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql --apply --ddl
begin;

-- ---------------------------------------------------------------- 1. pricing_config carries the ladder
alter table public.pricing_config
  add column if not exists chase_after_working_days integer not null default 3,
  add column if not exists bank_settlement_working_days_min integer not null default 7,
  add column if not exists bank_settlement_working_days_max integer not null default 14;

update public.pricing_config
   set refund_window_working_days = 5,
       chase_after_working_days = 3,
       bank_settlement_working_days_min = 7,
       bank_settlement_working_days_max = 14,
       updated_at = now()
 where id = 1;

alter table public.pricing_config drop constraint if exists pricing_config_refund_ladder_ck;
alter table public.pricing_config add constraint pricing_config_refund_ladder_ck
  check (chase_after_working_days > 0
     and chase_after_working_days < refund_window_working_days
     and bank_settlement_working_days_min > 0
     and bank_settlement_working_days_min <= bank_settlement_working_days_max);

-- ---------------------------------------------------------------- 2. the founder's sentence, verbatim
insert into public.decision_policy (key, value, description)
values ('refund_policy_founder_decision_2026_09_06',
        to_jsonb('refund admin fee is 250 AED dont remove it. also the 3% (which the customer paid and got refunded for) is included along with 9% interest annually as per UAE law maximum limit. refund policy is basically 5 working days from the time customer pays, so after 3 days if there is no response from the supplier, our agent should chase and on the 5th day i should be notified to do a final call. if no response we issue the refund and as per the banks usually it takes 7-14 working days. of course this should be updated everywhere and you should never ask me about it again.'::text),
        'The founder''s refund ruling of 6 Sep 2026, verbatim and final. Ladder: pricing_config (window 5, chase 3, banks 7-14). Amounts: fn_refund_amount_aed. Never re-ask.')
on conflict (key) do update set value = excluded.value, description = excluded.description, updated_at = now();

update public.decision_policy
   set value = '5'::jsonb,
       description = 'Working days after the reveal at which the founder''s final call is due. Read from pricing_config.refund_window_working_days since 6 Sep 2026; kept in step here.',
       updated_at = now()
 where key = 'refund_call_after_working_days';

-- ---------------------------------------------------------------- 3. what may reach the founder
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role)
values
  ('refund_final_call', true,
   'day 5 of the refund ladder: the supplier has not responded for 5 working days and the founder makes the final call before the refund is issued (his decision, 6 Sep 2026)',
   'cfo'),
  ('refund_complaint', false,
   'a customer''s non-response complaint is worked by the Customer Success Director, who owns supplier follow-up; only the day-5 final call and the refund approval reach the founder (6 Sep 2026)',
   'customer_success_director')
on conflict (kind) do update
  set allowed_to_email = excluded.allowed_to_email, reason = excluded.reason,
      owner_role = excluded.owner_role, updated_at = now();

-- ---------------------------------------------------------------- 4. the one computation
CREATE OR REPLACE FUNCTION public.fn_refund_amount_aed(p_paid_aed numeric, p_paid_at timestamp with time zone, p_refund_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_paid numeric; v_admin numeric; v_pct numeric; v_days integer; v_interest numeric;
  v_min integer; v_max integer;
begin
  -- The customer's refund is the fee actually paid, in full: the published Refund Policy promises no
  -- administrative deduction and fn_refund_amount_is_the_fee_paid enforces it on the refunds row.
  v_paid  := round(coalesce(p_paid_aed, 0), 2);
  -- The AED 250 administrative fee and the 9% p.a. (UAE statutory maximum) are what the SUPPLIER whose
  -- silence caused the refund owes on top of the fee: founder decision 6 Sep 2026, verbatim in
  -- decision_policy.refund_policy_founder_decision_2026_09_06.
  v_admin := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_admin_fee_aed'), 250);
  v_pct   := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_late_fee_annual_pct'), 9);
  select bank_settlement_working_days_min, bank_settlement_working_days_max
    into v_min, v_max from public.pricing_config order by id limit 1;
  -- simple interest, pro-rated by CALENDAR days (Dubai dates) between the two instants
  v_days := greatest(0, (coalesce(p_refund_at, now()) at time zone 'Asia/Dubai')::date
                      - (coalesce(p_paid_at, coalesce(p_refund_at, now())) at time zone 'Asia/Dubai')::date);
  v_interest := round(v_paid * v_pct / 100.0 * v_days / 365.0, 2);
  return jsonb_build_object(
    'paid_aed', v_paid,
    'customer_refund_aed', v_paid,
    'admin_fee_aed', v_admin,
    'interest_pct_pa', v_pct,
    'interest_days', v_days,
    'interest_aed', v_interest,
    'supplier_charge_aed', round(v_paid + v_admin + v_interest, 2),
    'bank_settlement_working_days', coalesce(v_min, 7)::text || '-' || coalesce(v_max, 14)::text,
    'basis', 'customer: the reveal fee paid, refunded in full, no deduction; supplier: that fee + AED '
             || v_admin::text || ' administrative fee + ' || v_pct::text
             || '% p.a. simple interest for ' || v_days::text || ' calendar day(s)');
end $function$;

revoke execute on function public.fn_refund_amount_aed(numeric, timestamp with time zone, timestamp with time zone) from public, anon;
grant execute on function public.fn_refund_amount_aed(numeric, timestamp with time zone, timestamp with time zone) to authenticated, service_role;

-- ---------------------------------------------------------------- 5. the ladder reads one source
CREATE OR REPLACE FUNCTION public.trg_reveal_window()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- The refund window opens refund_window_working_days after the customer paid (pricing_config, the
  -- same source stripe_confirm and stripe_webhook read), so every path agrees on the date.
  if NEW.revealed_at is not null and NEW.refund_deadline is null then
    NEW.refund_deadline := public.fn_add_working_days(NEW.revealed_at,
      coalesce((select refund_window_working_days from public.pricing_config order by id limit 1), 5));
    if NEW.refund_status is null then NEW.refund_status := 'window_open'; end if;
  end if;
  return NEW;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_refund_state(p_transaction uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t record; v_window int; v_chase int; v_notify_days int; v_min int; v_max int;
        v_responded boolean; v_chase_at timestamptz; v_final_at timestamptz; v_notify_at timestamptz;
        v_chased_at timestamptz; v_final_sent_at timestamptz; v_state text;
begin
  select * into t from transactions where id = p_transaction;
  if not found then return jsonb_build_object('error','transaction_not_found'); end if;

  -- THE LADDER (founder, 6 Sep 2026): the clock starts when the customer PAYS (revealed_at), never at
  -- a nudge or a notice. Day 3 without a supplier response: the owning employee chases. Day 5: the
  -- founder is notified for the final call and the refund becomes approvable. All from pricing_config.
  select refund_window_working_days, chase_after_working_days,
         bank_settlement_working_days_min, bank_settlement_working_days_max
    into v_window, v_chase, v_min, v_max from pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3);
  v_notify_days := coalesce((select value::text::int from decision_policy where key='refund_notify_after_working_days'),1);

  v_responded := t.supplier_ack_at is not null
    or exists (select 1 from messages m
               where m.inquiry_id = t.inquiry_id and m.supplier_id = t.supplier_id
                 and m.sender = 'supplier' and coalesce(m.blocked,false) = false
                 and m.created_at > t.revealed_at);

  v_chase_at  := case when t.revealed_at is null then null else public.fn_add_working_days(t.revealed_at, v_chase) end;
  v_final_at  := case when t.revealed_at is null then null
                      else coalesce(t.refund_deadline, public.fn_add_working_days(t.revealed_at, v_window)) end;
  v_notify_at := case when t.revealed_at is null then null else public.fn_add_working_days(t.revealed_at, v_notify_days) end;

  select min(n.created_at) into v_chased_at from notifications n
   where n.type = 'supplier_no_response_chase' and n.channel = 'email'
     and n.inquiry_id = t.inquiry_id and n.lead_id = t.supplier_id
     and t.revealed_at is not null and n.created_at > t.revealed_at;
  select min(f.created_at) into v_final_sent_at from founder_alerts f
   where f.dedupe_key = 'refund_final_call:' || t.id::text;

  v_state := case
    when t.revealed_at is null                                                          then 'not_revealed'
    when v_responded                                                                    then 'supplier_responded'
    when coalesce(t.refund_status,'') in ('approved','refunded','processing','succeeded') then 'refunded'
    when coalesce(t.refund_status,'') = 'rejected'                                      then 'refund_rejected'
    when now() < v_chase_at                                                             then 'waiting'
    when now() < v_final_at then case when v_chased_at is null then 'chase_due' else 'chased' end
    else case when v_final_sent_at is null then 'final_call_due' else 'final_call_sent' end end;

  return jsonb_build_object(
    'transaction_id', t.id,
    'state', v_state,
    'revealed_at', t.revealed_at,
    'supplier_responded', v_responded,
    'refund_window_working_days', v_window,
    'chase_after_working_days', v_chase,
    'chase_due_at', v_chase_at,
    'chased_at', v_chased_at,
    'founder_call_due_at', v_final_at,
    'final_call_sent_at', v_final_sent_at,
    'refund_deadline', t.refund_deadline,
    'notify_available_at', v_notify_at,
    'can_notify', (t.revealed_at is not null and not v_responded and t.customer_notified_at is null
                   and now() >= v_notify_at and v_state not in ('refunded','refund_rejected')),
    'notified_at', t.customer_notified_at,
    'auto_nudged_at', t.nudged_24_at,
    'refund_approvable', v_state in ('final_call_due','final_call_sent'),
    'refund_status', t.refund_status,
    'working_days_since_reveal', case when t.revealed_at is null then 0
                                      else public.fn_working_days_between(t.revealed_at, now()) end,
    'working_days_since_notice', case when t.customer_notified_at is null then 0
                                      else public.fn_working_days_between(t.customer_notified_at, now()) end,
    'bank_settlement_working_days', coalesce(v_min,7)::text || '-' || coalesce(v_max,14)::text
  );
end $function$;

CREATE OR REPLACE FUNCTION public.fn_notify_supplier(p_transaction uuid, p_actor text DEFAULT 'customer'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t record; st jsonb; sup record; cust_email text; v_subject text; v_body text;
        v_window int; v_final_at timestamptz; v_fee numeric;
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
  v_window   := coalesce((st->>'refund_window_working_days')::int, 5);
  v_final_at := (st->>'founder_call_due_at')::timestamptz;
  v_fee      := round(coalesce(t.reveal_fee, 0), 2);

  -- The customer's own formal notice. It does NOT move the ladder: the window is fixed at
  -- pricing_config.refund_window_working_days from payment (founder, 6 Sep 2026).
  v_subject := 'Awaiting your response — QuotesDone reveal #' || left(t.id::text, 8);
  v_body :=
    'Hello,' || chr(10) || chr(10) ||
    'A customer paid to reveal your contact details on QuotesDone on ' ||
      to_char(t.revealed_at at time zone 'Asia/Dubai','DD Mon YYYY') ||
      ' and has not yet heard from you. The customer is copied on this email so you can simply reply to all and pick it up here.' || chr(10) || chr(10) ||
    'Under the Supplier Agreement you must respond within ' || v_window::text || ' working days of the reveal, that is by ' ||
      to_char(v_final_at at time zone 'Asia/Dubai','DD Mon YYYY') || '. If we have not seen a response by then, the case goes to our founder for a final call and the customer''s reveal fee is refunded. ' ||
    'Under the supplier terms that refund is then recovered from your account: the reveal fee (AED ' || v_fee::text ||
      '), an administrative fee of AED 250 and interest at 9% per annum until it is settled, and matching is paused until it is paid.' || chr(10) || chr(10) ||
    'If you have already been in touch with this customer, reply here and we will close this off.' || chr(10) || chr(10) ||
    'QuotesDone';

  insert into notifications(type, kind, to_email, cc_emails, to_role, lead_id, inquiry_id, channel, subject, body, status)
  values ('reveal_no_response_notice', 'refund_ladder_notice', sup.email,
          array_remove(array[cust_email], null),
          'supplier', t.supplier_id, t.inquiry_id, 'email', v_subject, v_body, 'queued');

  update transactions
     set customer_notified_at = now(),
         refund_deadline = coalesce(refund_deadline, v_final_at)
   where id = p_transaction;

  insert into agent_actions(agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
  values ('customer_success','supplier_unresponsive','needs_review','high',
          'Supplier not responding after a paid reveal: ' || coalesce(sup.company_name,'#'||t.supplier_id),
          'Customer has formally notified them. The ladder sweep chases at day ' || (st->>'chase_after_working_days') ||
            ' and files the refund for the founder''s final call at day ' || v_window::text || '; a refund may only be approved once that has elapsed.',
          jsonb_build_object('transaction_id', t.id, 'supplier_id', t.supplier_id,
                             'inquiry_id', t.inquiry_id, 'notified_at', now(),
                             'chase_due_at', st->'chase_due_at',
                             'founder_call_due_at', v_final_at),
          'transactions', t.id::text);

  return jsonb_build_object('ok', true, 'notified_at', now(),
                            'recipients', jsonb_build_array(sup.email, cust_email),
                            'founder_call_due_at', v_final_at,
                            'state', public.fn_refund_state(p_transaction));
end $function$;

-- ---------------------------------------------------------------- 6. the complaint goes to its owner; the customer hears from the bank
CREATE OR REPLACE FUNCTION public.qd_notify_refund_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_company text; v_window int; v_chase int;
begin
  select company_name into v_company from leads where id = NEW.supplier_id;
  select refund_window_working_days, chase_after_working_days into v_window, v_chase
    from pricing_config order by id limit 1;
  -- 6 Sep 2026: the complaint is the Customer Success Director's to work (founder_mail_policy
  -- refund_complaint, allowed_to_email = false). The founder hears about a refund exactly twice: the
  -- day-5 final call (refund_final_call) and the approval itself.
  perform public.fn_notify_founder(
    p_event => 'Refund requested — supplier not responding: ' || coalesce(v_company, '(id ' || NEW.supplier_id::text || ')'),
    p_detail => 'A customer has asked for the reveal fee back because a revealed supplier is not responding.' || chr(10) ||
    'Supplier: ' || coalesce(v_company, '(id ' || NEW.supplier_id::text || ')') || chr(10) ||
    'Inquiry: ' || coalesce(NEW.inquiry_id::text, '') || ' · Transaction: ' || NEW.id::text ||
      ' · Reveal fee: AED ' || coalesce(NEW.reveal_fee::text, '0') || ' · paid ' ||
      coalesce(to_char(NEW.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY'), '?') || chr(10) || chr(10) ||
    'Ladder: the supplier has ' || coalesce(v_window, 5)::text || ' working days from payment. The sweep chases at day ' ||
      coalesce(v_chase, 3)::text || ' and files the refund for the founder''s final call at day ' || coalesce(v_window, 5)::text ||
      '. Reach the supplier now; if they respond, record it (supplier_ack_at or a portal message) so the case closes. ' ||
      'Read fn_refund_state(''' || NEW.id::text || ''') for where it stands.',
    p_level => 'high', p_kind => 'refund_complaint', p_dedupe_key => 'refund_complaint:' || NEW.id::text, p_owner_agent => null);
  -- K20 cutover. A refund complaint raised against a revealed supplier is the declared start of W17. Placed at the final return so the owner notification is sent whether or not the kernel accepts the request.
  -- 4 Sep 2026: W17's case object is the refunds row, which by design does not exist at the
  -- request stage (the claim window has not opened), and the kernel re-raises a missing parent.
  -- The kernel is asked only once the case object exists; the request stage travels on the bus.
  if exists (select 1 from public.refunds r where r.transaction_id = NEW.id) then
    perform public.fn_kernel_source_emit('dbtrigger:public.transactions:trg_notify_refund', jsonb_build_object(
      'source_ref',  NEW.id::text,
      'raw_payload', jsonb_build_object('transaction_id', NEW.id::text, 'inquiry_id', NEW.inquiry_id::text, 'supplier_id', NEW.supplier_id::text, 'reveal_fee', NEW.reveal_fee)));
  end if;
  return NEW;
end $function$;

CREATE OR REPLACE FUNCTION public.qd_on_refund_resolved()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_fee numeric; v_admin numeric; v_cust record; v_min int; v_max int; v_window int; v_amount numeric; v_amounts jsonb;
begin
  if NEW.refund_status in ('refunded','approved') and (OLD.refund_status is distinct from NEW.refund_status) then
    v_fee   := coalesce(NEW.reveal_fee, NEW.app_fee, 0);
    v_admin := coalesce((select num_value from public.gl_settings where key='clawback_admin_fee_aed'), 250);
    -- 6 Sep 2026: the one arithmetic. The supplier's charge at issue = the refunded fee + the AED 250
    -- administrative fee (unchanged, from gl_settings as before) + 9% p.a. simple interest pro-rated
    -- by calendar days from the customer's payment to this issue (founder ruling, verbatim in
    -- decision_policy.refund_policy_founder_decision_2026_09_06). collections_legal keeps accruing on
    -- the overdue balance from the due date exactly as before.
    v_amounts := public.fn_refund_amount_aed(v_fee, NEW.revealed_at, now());
  -- Kernel cutover. Resolution of a refund already inside a W17 run. Routing it as new work would open a second W17 for the same transaction.
  perform public.fn_kernel_source_emit('dbtrigger:public.transactions:trg_refund_resolved', jsonb_build_object(
    'source_ref',  NEW.id::text,
    'workflow_run_id', public.fn_kernel_run_for('refund_dispute_case:' || NEW.id::text),
    'raw_payload', jsonb_build_object('transaction_id', NEW.id::text, 'refund_status', NEW.refund_status, 'reveal_fee', v_fee)));


    if not exists (select 1 from public.supplier_dues where transaction_id=NEW.id and coalesce(status,'')<>'cancelled') then
      insert into public.supplier_dues(
        transaction_id, supplier_id, quote_id, quote_amount, commission_pct,
        amount_due, admin_fee, interest_amount, currency,
        reveal_date, due_date, due_date_30, status, created_at)
      values(
        NEW.id, NEW.supplier_id, NEW.quote_id, NEW.quote_amount, 3,
        v_fee,          -- the 3% reveal fee QuotesDone already refunded to the customer
        v_admin,        -- flat administration fee, charged immediately per the supplier terms
        coalesce((v_amounts->>'interest_aed')::numeric, 0),  -- 9% p.a. from the customer's payment to this issue (fn_refund_amount_aed)
        'AED',
        NEW.revealed_at, (now()+interval '7 days'), (now()+interval '30 days'), 'due', now());
    end if;

    update public.leads
      set matching_blocked = true,
          matching_block_reason = 'Unsettled non-response charge (customer refunded due to no response)',
          rv_nonresponse_refunds = coalesce(rv_nonresponse_refunds,0)+1
    where id = NEW.supplier_id;

    if NEW.refund_resolved_at is null then NEW.refund_resolved_at := now(); end if;

    -- 6 Sep 2026: once the money has actually moved ('refunded' is written by refunds_api after
    -- Stripe returned it), the customer is told, and told what the bank takes.
    if NEW.refund_status = 'refunded' then
      select email, full_name into v_cust from public.customers where id = NEW.customer_id;
      select bank_settlement_working_days_min, bank_settlement_working_days_max, refund_window_working_days
        into v_min, v_max, v_window from public.pricing_config order by id limit 1;
      v_amount := round(coalesce(NEW.refund_amount_aed, v_fee), 2);
      if v_cust.email is not null and not exists (
           select 1 from public.notifications n where n.type = 'refund_issued' and n.inquiry_id = NEW.inquiry_id
              and n.to_email = v_cust.email and n.lead_id = NEW.supplier_id) then
        insert into public.notifications(type, kind, to_email, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status)
        values ('refund_issued', 'refund_issued', v_cust.email, 'customer', NEW.supplier_id, NEW.inquiry_id, NEW.quote_id, 'email',
          'Your QuotesDone reveal fee refund of AED ' || v_amount::text || ' has been issued',
          'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || ',' || chr(10) || chr(10) ||
          'We have issued a refund of AED ' || v_amount::text || ' — the full reveal fee you paid on ' ||
            coalesce(to_char(NEW.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY'), 'the reveal date') ||
            ' — to your original payment method, because the supplier did not respond within ' ||
            coalesce(v_window, 5)::text || ' working days. No administrative charge is deducted from your refund.' || chr(10) || chr(10) ||
          'Banks and card issuers usually take ' || coalesce(v_min, 7)::text || '–' || coalesce(v_max, 14)::text ||
            ' working days to show it on your statement. If it has not appeared after ' || coalesce(v_max, 14)::text ||
            ' working days, reply to this email and we will trace it with the payment processor.' || chr(10) || chr(10) ||
          'You are welcome to post the request again; we will introduce you to another supplier.' || chr(10) || chr(10) ||
          'QuotesDone', 'queued');
      end if;
    end if;
  end if;
  return NEW;
end;
$function$;

-- ---------------------------------------------------------------- 6b. the reveal receipt and the nudges state the same ladder
CREATE OR REPLACE FUNCTION public.trg_reveal_receipt()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  cemail  text;
  semail  text;
  comp    text;
  inq     record;
  v_window int; v_chase int;
begin
  if NEW.revealed_at is not null and (TG_OP = 'INSERT' or OLD.revealed_at is null) then
    -- K20 cutover. The reveal payment is the declared start of W16. Placed INSIDE the branch that
    -- tests revealed_at, so it fires once when the reveal actually happens and not on every update.
    perform public.fn_kernel_source_emit('dbtrigger:public.transactions:trg_reveal_receipt_a', jsonb_build_object(
      'source_ref', NEW.id::text,
      'raw_payload', jsonb_build_object(
        'provider_event_id', coalesce(nullif(NEW.payment_ref, ''), NEW.id::text),
        'transaction_id', NEW.id::text, 'inquiry_id', NEW.inquiry_id::text,
        'supplier_id', NEW.supplier_id::text, 'reveal_fee', NEW.reveal_fee)));

    select email into cemail from public.customers where id = NEW.customer_id;
    select company_name, email into comp, semail from public.leads where id = NEW.supplier_id;
    select summary, category into inq from public.inquiries where id = NEW.inquiry_id;
    -- 6 Sep 2026: both receipts state the ladder from pricing_config (window 5, chase 3), one source.
    select refund_window_working_days, chase_after_working_days into v_window, v_chase
      from public.pricing_config order by id limit 1;
    v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3);

    -- 1. customer email
    if cemail is not null then
      insert into public.notifications (type, to_email, to_role, inquiry_id, quote_id, subject, body, status)
      values ('reveal_receipt', cemail, 'customer', NEW.inquiry_id, NEW.quote_id,
              'Reveal confirmed — ' || coalesce(comp, 'supplier'),
              'You have unlocked ' || coalesce(comp, 'the supplier') || '''s contact details'
                || coalesce(' for: ' || left(inq.summary, 80), '')
                || '. You can now message them directly in the app. We track this reveal from the moment you paid: if the supplier has not responded within '
                || v_chase::text || ' working days we chase them for you and copy you; if there is still no response by working day '
                || v_window::text || ' the case goes to our founder for a final call, and if the supplier does not respond to it your reveal fee is refunded in full. '
                || 'Banks usually take 7-14 working days to show a refund. You can also open the request and Report an issue at any time.',
              'queued');
    end if;

    -- 2. supplier email (moved here from stripe_webhook)
    if semail is not null and semail like '%@%' then
      insert into public.notifications (type, to_email, to_role, lead_id, inquiry_id, quote_id, subject, body, status)
      values ('quote_accepted', semail, 'supplier', NEW.supplier_id, NEW.inquiry_id, NEW.quote_id,
              'A customer revealed your quote on QuotesDone',
              'A customer paid to reveal your contact for: ' || coalesce(inq.summary, '')
                || '. Please respond promptly — under the Supplier Agreement you must respond within ' || v_window::text
                || ' working days of the reveal. If you have not responded after ' || v_chase::text
                || ' working days we chase you with the customer copied; if there is still no response on working day ' || v_window::text
                || ' our founder makes a final call, the customer is refunded, and the reveal fee plus an AED 250 administrative fee and 9% p.a. interest is recovered from your account.',
              'queued');
    end if;

    -- 3 and 4: the WhatsApp to each opted-in party is queued by trg_wa_fanout from the two email rows above.
  end if;
  return NEW;
end
$function$;

CREATE OR REPLACE FUNCTION public.qd_reveal_nudges()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare base text := 'https://' || public.qd_project_ref() || '.supabase.co/functions/v1/supplier_ack';
        v_window int; v_chase int;
begin
  -- 6 Sep 2026: the nudges quote the ladder from pricing_config (window 5, chase 3), one source.
  select refund_window_working_days, chase_after_working_days into v_window, v_chase
    from public.pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3);

  with due as (
    select t.id, t.inquiry_id, t.supplier_id, t.ack_token, l.email, coalesce(l.locale,'en') as locale
    from transactions t join leads l on l.id=t.supplier_id
    where t.revealed_at is not null and t.revealed_at < now()-interval '24 hours'
      and t.nudged_24_at is null and coalesce(t.fee_status,'')='paid' and t.refund_status is null and t.supplier_ack_at is null
      and not exists (select 1 from messages m where m.inquiry_id=t.inquiry_id and m.supplier_id=t.supplier_id and m.sender='supplier' and coalesce(m.blocked,false)=false and m.created_at>t.revealed_at)
      and l.email ~ '@'
  ), ins as (
    insert into notifications(type,to_email,to_role,inquiry_id,subject,body)
    select 'supplier_nudge', d.email, 'supplier', d.inquiry_id,
      case when d.locale='ar' then 'عميل دافع بانتظارك — يُرجى الرد'
           else 'A paying customer is waiting for you — please respond' end,
      (case when d.locale='ar'
        then 'دفع أحد العملاء لكشف بيانات تواصلك على QuotesDone وهو بانتظار ردك. يُرجى التواصل معه في أقرب وقت. وفقاً لاتفاقية المورّد، يجب عليك الرد خلال ' || v_window::text || ' أيام عمل من الكشف؛ وإذا لم ترد خلال ' || v_chase::text || ' أيام عمل نتابعك مع نسخة للعميل، وإذا لم ترد بحلول يوم العمل ' || v_window::text || ' يجري مؤسسنا اتصالاً أخيراً ثم يُسترد المبلغ للعميل وتُحصَّل من حسابك رسوم الكشف (٣٪ من قيمة العرض) مع رسم إداري قدره ٢٥٠ درهماً وفائدة ٩٪ سنوياً.'
        else 'A customer has paid to reveal your contact on QuotesDone and is waiting to hear from you. Please contact them as soon as possible. Under the Supplier Agreement you must respond within ' || v_window::text || ' working days of the reveal; if you have not responded after ' || v_chase::text || ' working days we chase you with the customer copied, and if there is still no response on working day ' || v_window::text || ' our founder makes a final call, the customer is refunded, and the reveal fee (3% of the quoted value) plus an AED 250 administrative fee and 9% p.a. interest is recovered from your account.' end)
      || E'\n\n' ||
      (case when d.locale='ar' then 'هل تواصلت مع العميل بالفعل؟ أكّد هنا لإيقاف هذه التذكيرات: '
            else 'Already contacted this customer? Confirm here to stop these reminders: ' end)
      || base || '?tx=' || d.id || '&token=' || d.ack_token
    from due d returning 1
  )
  update transactions set nudged_24_at=now() where id in (select id from due);

  with due as (
    select t.id, t.inquiry_id, t.supplier_id, t.ack_token, l.email, coalesce(l.locale,'en') as locale
    from transactions t join leads l on l.id=t.supplier_id
    where t.revealed_at is not null and t.revealed_at < now()-interval '48 hours'
      and t.nudged_48_at is null and coalesce(t.fee_status,'')='paid' and t.refund_status is null and t.supplier_ack_at is null
      and not exists (select 1 from messages m where m.inquiry_id=t.inquiry_id and m.supplier_id=t.supplier_id and m.sender='supplier' and coalesce(m.blocked,false)=false and m.created_at>t.revealed_at)
      and l.email ~ '@'
  ), ins as (
    insert into notifications(type,to_email,to_role,inquiry_id,subject,body)
    select 'supplier_nudge', d.email, 'supplier', d.inquiry_id,
      case when d.locale='ar' then 'تذكير أخير: عميل لا يزال بانتظارك — يُرجى الرد اليوم'
           else 'Final reminder: a customer is still waiting — please respond today' end,
      (case when d.locale='ar'
        then 'هذا تذكير أخير بأن عميلاً دافعاً بانتظار ردك على QuotesDone. إذا لم ترد بحلول يوم العمل ' || v_window::text || ' من الكشف وتم استرداد المبلغ للعميل، تُحصَّل من حسابك رسوم الكشف (٣٪ من قيمة العرض) مع رسم إداري قدره ٢٥٠ درهماً وفائدة ٩٪ سنوياً، وقد يؤدي تكرار عدم الرد إلى إزالتك من المنصّة.'
        else 'This is a final reminder that a paying customer is waiting for your response on QuotesDone. If you have not responded by working day ' || v_window::text || ' after the reveal and the customer is refunded, the reveal fee (3% of the quoted value) plus an AED 250 administrative fee and 9% p.a. interest is recovered from your account, and repeated non-response may lead to removal from the Platform.' end)
      || E'\n\n' ||
      (case when d.locale='ar' then 'هل تواصلت مع العميل بالفعل؟ أكّد هنا لإيقاف هذه التذكيرات: '
            else 'Already contacted this customer? Confirm here to stop these reminders: ' end)
      || base || '?tx=' || d.id || '&token=' || d.ack_token
    from due d returning 1
  )
  update transactions set nudged_48_at=now() where id in (select id from due);
end $function$;

-- the two retired ladder keys keep their rows (fn_dept_decision_thresholds lists them) but say what they are now
update public.decision_policy
   set description = 'RETIRED 6 Sep 2026: the ladder no longer has a claim window after the call. Kept for fn_dept_decision_thresholds readers; the live ladder is pricing_config (refund_window_working_days 5, chase_after_working_days 3).',
       updated_at = now()
 where key = 'refund_claim_after_call_working_days';
update public.decision_policy
   set description = 'Flat administrative fee, AED, charged to the SUPPLIER whose non-response caused a refund, on top of the refunded reveal fee and 9% p.a. interest. Founder ruling 6 Sep 2026 ("refund admin fee is 250 AED dont remove it"); written into Supplier Agreement clause 33 the same day. Applied by qd_on_refund_resolved from gl_settings.clawback_admin_fee_aed; stated by fn_refund_amount_aed. Never deducted from the customer.',
       updated_at = now()
 where key = 'refund_admin_fee_aed';

-- ---------------------------------------------------------------- 7. the deterministic ladder sweep
CREATE OR REPLACE FUNCTION public.fn_refund_ladder_sweep()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t record; st jsonb; sup record; cust record;
  v_window int; v_chase int; v_agent text; v_dept text;
  v_subject text; v_body text; v_amounts jsonb; v_req jsonb; v_refund_id bigint; v_task bigint;
  v_chase_at timestamptz; v_final_at timestamptz; v_fee numeric;
  n_seen int := 0; n_chased int := 0; n_final int := 0; v_ids jsonb := '[]'::jsonb;
begin
  select refund_window_working_days, chase_after_working_days into v_window, v_chase
    from pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3);

  -- THE OWNER of the chase is the existing employee who owns supplier follow-up: the Customer Success
  -- Director (org_role customer_success_director, runtime agent 'followup'; workflow_step refund #3/#4
  -- already names this role). Never a new agent (founder, 6 Sep 2026).
  select r.runtime_agent_key, r.primary_department_id into v_agent, v_dept
    from org_role r where r.role_id = 'customer_success_director' and r.status = 'active';
  v_agent := coalesce(v_agent, 'followup'); v_dept := coalesce(v_dept, 'customer_experience');

  for t in
    select x.* from transactions x
     where x.revealed_at is not null and coalesce(x.reveal_fee, 0) > 0
       and coalesce(x.refund_status, '') not in ('approved','refunded','processing','succeeded','rejected','cancelled','failed')
       and x.revealed_at > now() - interval '120 days'
     order by x.revealed_at
  loop
    n_seen := n_seen + 1;
    st := public.fn_refund_state(t.id);
    continue when st ? 'error' or coalesce((st->>'supplier_responded')::boolean, false);
    continue when st->>'state' not in ('chase_due', 'final_call_due');

    select company_name, coalesce(claimed_by, email) as email into sup from leads where id = t.supplier_id;
    select email, full_name into cust from customers where id = t.customer_id;
    v_chase_at := (st->>'chase_due_at')::timestamptz;
    v_final_at := (st->>'founder_call_due_at')::timestamptz;
    v_fee      := round(coalesce(t.reveal_fee, 0), 2);

    -- DAY 3: the chase. One email to the supplier, customer cc'd (fn_wa_fanout adds the WhatsApp copy
    -- when the supplier opted in), and one task on the owning employee. fn_refund_state reads the
    -- email back as chased_at, so a second tick cannot chase twice.
    if st->>'state' = 'chase_due' then
      v_subject := 'Action needed: a customer is waiting for your response — QuotesDone reveal #' || left(t.id::text, 8);
      v_body :=
        'Hello ' || coalesce(sup.company_name, '') || ',' || chr(10) || chr(10) ||
        'A customer paid to reveal your contact details on QuotesDone on ' ||
          to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY') ||
          ' and has not heard from you. ' || v_chase::text || ' working days have passed. The customer is copied on this email so you can reply to all and pick it up here.' || chr(10) || chr(10) ||
        'Under the Supplier Agreement you must respond within ' || v_window::text || ' working days of the reveal, that is by ' ||
          to_char(v_final_at at time zone 'Asia/Dubai', 'DD Mon YYYY') ||
          '. If we have not seen a response by then, the case goes to our founder for a final call and the customer''s reveal fee is refunded. ' ||
        'Under the supplier terms that refund is then recovered from your account: the reveal fee (AED ' || v_fee::text ||
          '), an administrative fee of AED 250 and interest at 9% per annum until it is settled, and matching is paused until it is paid.' || chr(10) || chr(10) ||
        'If you have already been in touch with this customer, reply here and we will close this off.' || chr(10) || chr(10) ||
        'QuotesDone — Customer Success';
      insert into notifications(type, kind, to_email, cc_emails, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status)
      values ('supplier_no_response_chase', 'refund_ladder_chase', sup.email,
              array_remove(array[cust.email], null), 'supplier', t.supplier_id, t.inquiry_id, t.quote_id,
              'email', v_subject, v_body, 'queued');
      insert into org_tasks(dept_key, title, detail, status, tier, needs_founder, decided_by,
                            action_class, assigned_agent, priority, result)
      values (v_dept,
              left('Chase ' || coalesce(sup.company_name, 'supplier #' || t.supplier_id::text) || ': no response ' ||
                   v_chase::text || ' working days after a paid reveal', 200),
              'Reveal #' || t.id::text || ' (inquiry ' || coalesce(t.inquiry_id::text, '?') || '). The customer paid AED ' || v_fee::text ||
                ' on ' || to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY') ||
                ' and the supplier has not responded. The chase email has been queued to ' || coalesce(sup.email, '(no email)') ||
                ' with the customer copied. Reach the supplier by every channel on file today. If they respond, record it ' ||
                '(supplier_ack_at or a portal message) so the case closes. If not, on ' ||
                to_char(v_final_at at time zone 'Asia/Dubai', 'DD Mon YYYY') ||
                ' the sweep files the refund and the founder makes the final call.',
              'assigned', 'advisory', false, 'fn_refund_ladder_sweep', 'routine_operational_decision', v_agent, 2,
              jsonb_build_object('refund_ladder', jsonb_build_object(
                'transaction_id', t.id, 'inquiry_id', t.inquiry_id, 'supplier_id', t.supplier_id,
                'step', 'chase', 'chase_due_at', v_chase_at, 'founder_call_due_at', v_final_at)))
      returning id into v_task;
      n_chased := n_chased + 1;
      v_ids := v_ids || jsonb_build_object('transaction_id', t.id, 'step', 'chase', 'task_id', v_task);
    end if;

    -- DAY 5: the founder's final call. The refund is FILED through the one existing door
    -- (fn_refund_request -> refunds 'requested', founder-gated by fn_refund_decide and the z00/z05
    -- guards) and he is notified with the facts. founder_alerts.dedupe_key is the idempotency record.
    if st->>'state' = 'final_call_due' then
      v_amounts := public.fn_refund_amount_aed(t.reveal_fee, t.revealed_at, now());
      if not exists (select 1 from refunds r where r.transaction_id = t.id) then
        v_req := public.fn_refund_request(
          round(t.reveal_fee * 100)::bigint, 'supplier_unresponsive', 'refund_ladder_sweep',
          t.inquiry_id, t.customer_id, t.supplier_id, t.quote_id, t.payment_ref, null,
          'Day ' || v_window::text || ' of the refund ladder: the supplier responded neither to the customer nor to the day-' ||
            v_chase::text || ' chase. Filed by the deterministic ladder sweep for the founder''s final call.',
          t.id);
      end if;
      select r.id into v_refund_id from refunds r where r.transaction_id = t.id order by r.id desc limit 1;

      perform public.fn_notify_founder(
        p_event => 'Refund final call: ' || coalesce(sup.company_name, 'supplier #' || t.supplier_id::text) ||
          ' silent for ' || v_window::text || ' working days on reveal #' || left(t.id::text, 8) || ' (AED ' || v_fee::text || ')',
        p_detail => 'Day ' || v_window::text || ' of the refund ladder. The supplier has not responded to the customer, to the day-' || v_chase::text ||
          ' chase' || case when (st->>'chased_at') is not null then ' sent ' || to_char((st->>'chased_at')::timestamptz at time zone 'Asia/Dubai', 'DD Mon YYYY') else ' (chase not recorded)' end ||
          case when t.customer_notified_at is not null then ', or to the customer''s formal notice of ' || to_char(t.customer_notified_at at time zone 'Asia/Dubai', 'DD Mon YYYY') else '' end || '.' || chr(10) || chr(10) ||
        'SUPPLIER: ' || coalesce(sup.company_name, '#' || t.supplier_id::text) || ' · ' || coalesce(sup.email, '(no email)') || ' · ' ||
          coalesce((select coalesce(nullif(btrim(l.whatsapp), ''), l.phone_e164, l.phone) from leads l where l.id = t.supplier_id), '(no phone)') || chr(10) ||
        'CUSTOMER: ' || coalesce(cust.full_name, '') || ' · ' || coalesce(cust.email, '') || chr(10) ||
        'REVEAL: transaction ' || t.id::text || ' · inquiry ' || coalesce(t.inquiry_id::text, '?') || ' · quotation AED ' || coalesce(t.quote_amount::text, '?') ||
          ' · reveal fee AED ' || v_fee::text || ' paid ' || to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || chr(10) ||
        'REFUND REQUEST: #' || coalesce(v_refund_id::text, '?') || ' is in your queue (status requested).' || chr(10) ||
        'AMOUNTS (fn_refund_amount_aed): customer refund AED ' || (v_amounts->>'customer_refund_aed') || ' in full; supplier charge AED ' ||
          (v_amounts->>'supplier_charge_aed') || ' = fee ' || (v_amounts->>'paid_aed') || ' + admin fee AED ' || (v_amounts->>'admin_fee_aed') ||
          ' + ' || (v_amounts->>'interest_pct_pa') || '% p.a. interest (AED ' || (v_amounts->>'interest_aed') || ' for ' || (v_amounts->>'interest_days') || ' day(s) so far).' || chr(10) || chr(10) ||
        'YOUR CALL: phone the supplier. If there is still no response, approve refund #' || coalesce(v_refund_id::text, '?') ||
          ' in the OS; the customer is then refunded in full and told that banks take ' || (v_amounts->>'bank_settlement_working_days') ||
          ' working days, and the supplier''s charge is raised. If the supplier responds, reject it with a note and the case closes.',
        p_level => 'high', p_kind => 'refund_final_call', p_dedupe_key => 'refund_final_call:' || t.id::text, p_owner_agent => null);
      n_final := n_final + 1;
      v_ids := v_ids || jsonb_build_object('transaction_id', t.id, 'step', 'final_call', 'refund_id', v_refund_id);
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'seen', n_seen, 'chased', n_chased, 'final_calls', n_final,
                            'window_working_days', v_window, 'chase_after_working_days', v_chase,
                            'owner_agent', v_agent, 'cases', v_ids, 'ran_at', now());
end $function$;

revoke execute on function public.fn_refund_ladder_sweep() from public, anon, authenticated;
grant execute on function public.fn_refund_ladder_sweep() to service_role;

-- ---------------------------------------------------------------- 8. the cron, owned by the same role
do $cron$
declare v_job bigint; v jsonb;
begin
  select jobid into v_job from cron.job where jobname = 'refund_ladder_sweep_hourly';
  if v_job is null then
    v_job := cron.schedule('refund_ladder_sweep_hourly', '35 * * * *', 'select public.fn_refund_ladder_sweep();');
  end if;
  v := public.fn_kernel_wrap_and_enable_cron(v_job, 'customer_success_director', 'customer_experience', 'routine_operational_decision');
  if coalesce((v->>'ok')::boolean, false) is not true then raise exception 'refund_ladder_sweep_hourly wrap failed: %', v; end if;
  insert into public.cron_registry (jobname, human_name, category, purpose) values
    ('refund_ladder_sweep_hourly', 'Refund ladder sweep', 'Operations',
     'Hourly: fn_refund_ladder_sweep() walks every paid reveal without a supplier response. At pricing_config.chase_after_working_days (3) it queues the chase email to the supplier (customer cc''d) and a task for the Customer Success Director; at refund_window_working_days (5) it files the refund through fn_refund_request (still founder-gated) and notifies the founder for his final call (refund_final_call). Deterministic, no model. Founder decision 6 Sep 2026.')
  on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
  insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine) values
    (v_job, 'refund_ladder_sweep_hourly',
     'INSERT public.notifications (supplier_no_response_chase, to the supplier), public.org_tasks (chase task), public.refunds via fn_refund_request (status requested), public.founder_alerts + founder notifications via fn_notify_founder (refund_final_call); UPDATE public.transactions.refund_status -> requested. Reads transactions, leads, customers, messages, pricing_config.',
     'Hourly in its own transaction. Acts only on transactions with revealed_at set, reveal_fee > 0 and no supplier response, past day 3 / day 5 of the working-day ladder; a scenario reveal younger than 3 working days is never touched, and ZZ DEMO fixtures address @example.invalid parties which fn_notifications_founder_mail_policy and the demo guard treat as never-real. close() removes the run''s transactions, and the sweep''s rows hang off inquiry_id / lead_id / transaction_id of those rows.')
  on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;
  raise notice 'refund_ladder_sweep_hourly jobid % : %', v_job, v->>'action';
end $cron$;

-- the routine components behind the cron (literal declarations; the cron:* row is declared once the jobid is known)
insert into public.phase_c_component(
    component_id, component_type, source_path_or_db_object, entry_method, current_callers, external_entry,
    schedule_or_trigger, mutates_state, current_actor, canonical_system_actor, accountable_role_id,
    department_id, workflow_id, step_id, authority_class, trace_policy_id, idempotency_strategy, retry_policy,
    activation_state, classification, gap, repair_or_keep_action, evidence, measured_at)
values
  ('dbfn:fn_refund_ladder_sweep()', 'database_function', 'public.fn_refund_ladder_sweep',
   'called by cron refund_ladder_sweep_hourly through fn_kernel_cron_exec', 'cron:refund_ladder_sweep_hourly', 'no',
   '', true, 'service_role', 'system.scheduler', 'customer_success_director',
   'customer_experience', 'W17', '', 'routine_operational_decision', 'TRACE-ROLE-ACTION',
   'transaction_id:fn_refund_state.state (chase_due -> chased, final_call_due -> final_call_sent)', 'next_scheduled_tick',
   'active', 'WIRE_TO_CANONICAL', '', 'keep: the refund ladder''s chase and final call, founder decision 6 Sep 2026',
   'the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql 2026-09-06: new; deterministic day-3 chase and day-5 founder final call', now()::date),
  ('dbfn:fn_refund_amount_aed(p_paid_aed numeric, p_paid_at timestamp with time zone, p_refund_at timestamp with time zone)', 'database_function', 'public.fn_refund_amount_aed',
   'called by fn_refund_ladder_sweep and any surface that states a refund amount', 'dbfn:fn_refund_ladder_sweep()', 'no',
   '', false, 'service_role', 'system.scheduler', 'cfo',
   'finance', 'W17', '', 'routine_operational_decision', 'TRACE-ROLE-ACTION',
   'pure function of its arguments', 'none',
   'active', 'WIRE_TO_CANONICAL', '', 'keep: the one refund arithmetic (fee in full to the customer; fee + AED 250 + 9% p.a. from the supplier)',
   'the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql 2026-09-06: new', now()::date)
on conflict (component_id) do update set
    current_callers = excluded.current_callers, activation_state = 'active', classification = 'WIRE_TO_CANONICAL',
    accountable_role_id = excluded.accountable_role_id, department_id = excluded.department_id,
    trace_policy_id = excluded.trace_policy_id, evidence = excluded.evidence, gap = '';

-- ---------------------------------------------------------------- the ledger follows the manifest
insert into public.kernel_routine_ownership(schema_name, routine_name, identity_args, ownership_class, classified_by_rule, evidence, source_kind, source_file, justification, recorded_at)
values
  ('public', 'fn_refund_amount_aed', 'p_paid_aed numeric, p_paid_at timestamp with time zone, p_refund_at timestamp with time zone', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'defined by scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql', null, now()),
  ('public', 'fn_refund_ladder_sweep', '', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'defined by scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql', null, now()),
  ('public', 'fn_refund_state', 'p_transaction uuid', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'restated by scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql', null, now()),
  ('public', 'fn_notify_supplier', 'p_transaction uuid, p_actor text', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'restated by scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql', null, now()),
  ('public', 'trg_reveal_window', '', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'restated by scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql', null, now()),
  ('public', 'qd_notify_refund_request', '', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'restated by scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql', null, now()),
  ('public', 'qd_on_refund_resolved', '', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'restated by scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql', null, now()),
  ('public', 'trg_reveal_receipt', '', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'restated by scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql', null, now()),
  ('public', 'qd_reveal_nudges', '', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'restated by scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql', null, now())
on conflict (schema_name, routine_name, identity_args) do update set
  ownership_class = excluded.ownership_class, classified_by_rule = excluded.classified_by_rule,
  evidence = excluded.evidence, source_kind = excluded.source_kind, source_file = excluded.source_file,
  recorded_at = now();

-- ---------------------------------------------------------------- proof, in the same transaction
do $proof$
declare v jsonb; c record;
begin
  select * into c from public.pricing_config where id = 1;
  if c.refund_window_working_days <> 5 or c.chase_after_working_days <> 3
     or c.bank_settlement_working_days_min <> 7 or c.bank_settlement_working_days_max <> 14 then
    raise exception 'pricing_config does not carry the ladder: %', to_jsonb(c);
  end if;
  -- fixed inputs: AED 300 paid 1 Jan 2026, refunded 31 Jan 2026 = 30 calendar days
  v := public.fn_refund_amount_aed(300, '2026-01-01 09:00+04'::timestamptz, '2026-01-31 09:00+04'::timestamptz);
  if (v->>'customer_refund_aed')::numeric <> 300 or (v->>'admin_fee_aed')::numeric <> 250
     or (v->>'interest_days')::int <> 30 or (v->>'interest_aed')::numeric <> 2.22
     or (v->>'supplier_charge_aed')::numeric <> 552.22 or (v->>'bank_settlement_working_days') <> '7-14' then
    raise exception 'fn_refund_amount_aed(300, 1 Jan, 31 Jan) is wrong: %', v;
  end if;
  if not exists (select 1 from public.founder_mail_policy where kind = 'refund_final_call' and allowed_to_email)
     or exists (select 1 from public.founder_mail_policy where kind = 'refund_complaint' and allowed_to_email) then
    raise exception 'founder_mail_policy rows are not as declared';
  end if;
  if not exists (select 1 from cron.job where jobname = 'refund_ladder_sweep_hourly' and active and command ilike '%fn_kernel_cron_exec%') then
    raise exception 'refund_ladder_sweep_hourly is not wrapped and active';
  end if;
  raise notice 'proof ok: %', v;
end $proof$;

commit;
