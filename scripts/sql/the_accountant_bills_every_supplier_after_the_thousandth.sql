-- THE ACCOUNTANT BILLS EVERY SUPPLIER AFTER THE THOUSANDTH, REMINDS BEFORE RENEWAL, AND CHASES WHAT
-- IS NOT PAID — ALWAYS THROUGH THE SALES ENGINEER.
--
-- Assigned: accountant (duty 3 of the eight, founder 14 Sep 2026: "yea add them all"). The supplier
-- hears it from the sales_engineer (fn_sales_engineer_writes_money_notice); customer_support sends it.
--
-- The rule, as the estate already holds it: the first 1,000 registered suppliers are free
-- (pricing_config.supplier_free_count = 1000, leads.founding_rank assigned by trg_assign_founding_rank),
-- and from the 1,001st the subscription is AED 1,000 a year (pricing_config.supplier_reg_fee).
--
-- WHAT WAS MEASURED (14 Sep 2026, production htdblwldjkcgjvmqkbeh):
--   * v_supplier_billing already decides each approved supplier's billing_status (exempt, not_due,
--     active, due, past_due) from founding_rank, the free count and subscription_paid_until.
--   * fn_subscription_billing_run already marks a due supplier and hands 'subscription.due' to the sales
--     engineer. NOTHING SCHEDULED IT: no pg_cron job exists but wa_flush, and resilience_ping does not
--     call it. It now runs inside this seat's duties.
--   * supplier_pay already opens the Stripe checkout for the fee with invoice_creation enabled, so the
--     supplier's annual invoice is Stripe's own; stripe_webhook alone marks it paid (subscription_paid_until).
--   * Nothing counted toward the thousand, nothing reminded a paying supplier before the renewal, nothing
--     chased an unpaid one after the first notice, and a failed subscription payment told nobody.
--
-- WHAT THIS BUILDS: the position toward the free count (reported to the CEO at configured fractions),
-- renewal reminders at configured days before paid_until runs out, dunning at configured days after it
-- falls due, a notice when a subscription payment fails (called by stripe_webhook), and — past the
-- configured escalation day — a finding owned by the sales engineer that goes round the IT loop.
--
--   node scripts/apply_sql.mjs scripts/sql/the_accountant_bills_every_supplier_after_the_thousandth.sql --apply --ddl

-- ── 1. THE SCHEDULE IS CONFIGURATION ─────────────────────────────────────────────────────────────
insert into public.decision_policy (key, value, description) values
  ('supplier_subscription_renewal_reminder_days', '[30, 7]'::jsonb,
   'Days before subscription_paid_until runs out on which the supplier is reminded that the annual subscription renews.'),
  ('supplier_subscription_dunning_days', '[3, 10, 20]'::jsonb,
   'Days after the annual subscription fell due on which an unpaid supplier is reminded again (after the first subscription.due notice).'),
  ('supplier_subscription_escalate_after_days', '30'::jsonb,
   'Days after the subscription fell due at which an unpaid supplier becomes a finding owned by the sales engineer, which goes round the IT loop to the CEO.'),
  ('supplier_subscription_count_report_fractions', '[0.9, 1.0]'::jsonb,
   'Fractions of the free supplier count (pricing_config.supplier_free_count) at which the accountant reports the position to the CEO, once each.')
on conflict (key) do nothing;

create or replace function public.fn_policy_int_array(p_key text)
returns int[] language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(array_agg(e::int order by e::int), '{}')
    from public.decision_policy d, jsonb_array_elements_text(d.value) e where d.key = p_key and jsonb_typeof(d.value) = 'array';
$fn$;
revoke execute on function public.fn_policy_int_array(text) from public, anon, authenticated;

-- ── 2. THE POSITION TOWARD THE THOUSAND ──────────────────────────────────────────────────────────
create or replace function public.fn_accountant_subscription_position()
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_cfg record; v_ranked int; v_billable int; v_active int; v_due int; v_past int;
begin
  select * into v_cfg from public.fn_supplier_subscription();
  select count(*) into v_ranked from public.leads where founding_rank is not null and not coalesce(is_demo, false);
  select count(*) filter (where b.billing_status not in ('exempt', 'not_due')),
         count(*) filter (where b.billing_status = 'active'),
         count(*) filter (where b.billing_status = 'due'),
         count(*) filter (where b.billing_status = 'past_due')
    into v_billable, v_active, v_due, v_past
    from public.v_supplier_billing b join public.leads l on l.id = b.supplier_id
   where not coalesce(l.is_demo, false);
  return jsonb_build_object(
    'registered_ranked', v_ranked, 'free_limit', v_cfg.free_limit,
    'free_places_left', greatest(v_cfg.free_limit - v_ranked, 0),
    'fraction_of_free_count', round(v_ranked::numeric / nullif(v_cfg.free_limit, 0), 4),
    'billable', v_billable, 'active', v_active, 'due', v_due, 'past_due', v_past,
    'fee', v_cfg.fee, 'currency', v_cfg.currency,
    'basis', 'leads.founding_rank (assigned by trg_assign_founding_rank) counted against pricing_config.supplier_free_count; billing states from v_supplier_billing. ZZ DEMO suppliers are not counted.');
end $fn$;
revoke execute on function public.fn_accountant_subscription_position() from public, anon, authenticated;

-- ── 3. A SUBSCRIPTION PAYMENT THAT DID NOT COMPLETE ──────────────────────────────────────────────
-- Called by stripe_webhook on checkout.session.expired / async_payment_failed with metadata.kind
-- 'supplier_registration'. The supplier is told nothing was charged and how to pay; the dunning
-- schedule keeps running regardless.
create or replace function public.fn_accountant_subscription_payment_failed(p_supplier_id bigint, p_session text, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint;
begin
  if p_supplier_id is null or coalesce(btrim(p_session), '') = '' then
    raise exception 'fn_accountant_subscription_payment_failed: a supplier and a checkout session are required';
  end if;
  if not exists (select 1 from public.leads where id = p_supplier_id) then
    return jsonb_build_object('ok', false, 'reason', 'no supplier ' || p_supplier_id);
  end if;
  v_id := public.fn_seat_handoff('accountant', 'sales_engineer', 'subscription.payment_failed', 'leads',
    p_supplier_id || ':payment_failed:' || p_session,
    jsonb_build_object('notice', 'subscription_payment_failed', 'supplier_id', p_supplier_id,
                       'session', p_session, 'reason', p_reason));
  return jsonb_build_object('ok', true, 'handoff_id', v_id);
end $fn$;
revoke execute on function public.fn_accountant_subscription_payment_failed(bigint, text, text) from public, anon, authenticated;

-- ── 4. THE DUTY ──────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_subscription_tick(p_as_of date default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_cfg record; v_pos jsonb; v_frac numeric; v_rep jsonb; v_run json;
  v_renew int[] := public.fn_policy_int_array('supplier_subscription_renewal_reminder_days');
  v_dun int[] := public.fn_policy_int_array('supplier_subscription_dunning_days');
  v_esc int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_subscription_escalate_after_days');
  b record; v_off int; v_i int; v_due_on date; v_days int; v_items jsonb := '[]'::jsonb;
  n_renew int := 0; n_dun int := 0; n_rep int := 0;
begin
  if array_length(v_renew, 1) is null or array_length(v_dun, 1) is null or v_esc is null then
    raise exception 'fn_accountant_subscription_tick: the supplier_subscription_* schedule is missing from decision_policy';
  end if;
  select * into v_cfg from public.fn_supplier_subscription();

  -- (a) The position toward the free count, reported to the CEO once per configured fraction.
  v_pos := public.fn_accountant_subscription_position();
  for v_frac in select e::numeric from public.decision_policy d, jsonb_array_elements_text(d.value) e
                 where d.key = 'supplier_subscription_count_report_fractions' order by 1 loop
    if (v_pos->>'fraction_of_free_count')::numeric >= v_frac then
      v_rep := public.fn_support_report_to_ceo('subscription_position:' || v_frac,
        case when v_frac >= 1 then 'elevated' else 'routine' end,
        (v_pos->>'registered_ranked') || ' of the ' || (v_pos->>'free_limit') || ' free supplier places are taken ('
          || round(v_frac * 100) || '% reached)',
        v_pos, '[]'::jsonb,
        case when v_frac >= 1 then 'The free places are gone: every supplier from here is billed ' || v_cfg.currency || ' ' || v_cfg.fee
                                   || ' a year through Stripe. Acknowledge; the accountant bills and chases through the sales engineer.'
             else 'No action. The accountant will report again when the free places are gone.' end,
        p_review_in => interval '3 days', p_source_agent => 'accountant');
      if coalesce((v_rep->>'ok')::boolean, false) and not coalesce((v_rep->>'duplicate')::boolean, false) then n_rep := n_rep + 1; end if;
    end if;
  end loop;

  -- (b) First notice when a subscription falls due (the existing routine; it hands subscription.due).
  v_run := public.fn_subscription_billing_run(false);

  for b in select vb.*, coalesce(l.is_demo, false) is_demo from public.v_supplier_billing vb
             join public.leads l on l.id = vb.supplier_id loop
    -- (c) Renewal reminders for a paying supplier, at each configured day before paid_until runs out.
    if b.billing_status = 'active' and b.subscription_paid_until is not null then
      foreach v_off in array v_renew loop
        if v_as_of >= b.subscription_paid_until - v_off and v_as_of <= b.subscription_paid_until then
          perform public.fn_seat_handoff('accountant', 'sales_engineer', 'subscription.renewal_reminder', 'leads',
            b.supplier_id || ':renew:' || b.subscription_paid_until || ':' || v_off,
            jsonb_build_object('notice', 'subscription_renewal', 'supplier_id', b.supplier_id,
                               'paid_until', b.subscription_paid_until, 'renews_on', b.subscription_paid_until + 1,
                               'fee', b.annual_fee_aed, 'currency', v_cfg.currency, 'days_before', v_off));
          n_renew := n_renew + 1;
          exit;
        end if;
      end loop;
    end if;

    -- (d) Dunning for an unpaid one: the highest configured day already reached, once.
    if b.billing_status in ('due', 'past_due') then
      v_due_on := coalesce(b.subscription_paid_until + 1, b.billing_starts_on, b.registered_on);
      v_days := v_as_of - v_due_on;
      v_i := null;
      for v_off in select generate_subscripts(v_dun, 1) loop
        if v_days >= v_dun[v_off] then v_i := v_off; end if;
      end loop;
      if v_i is not null then
        perform public.fn_seat_handoff('accountant', 'sales_engineer', 'subscription.dunning', 'leads',
          b.supplier_id || ':dunning:' || v_due_on || ':' || v_i,
          jsonb_build_object('notice', 'subscription_dunning', 'supplier_id', b.supplier_id, 'dunning_no', v_i,
                             'due_on', v_due_on, 'days_overdue', v_days, 'fee', b.amount_due_aed, 'currency', v_cfg.currency));
        n_dun := n_dun + 1;
      end if;
      -- (e) Past the escalation day: the sales engineer owns it, and the IT loop takes it to the CEO.
      if v_days >= v_esc then
        v_items := v_items || jsonb_build_object('item', 'unpaid:' || b.supplier_id, 'owner_seat', 'sales_engineer',
          'subject', 'supplier_subscription',
          'title', coalesce(b.company_name, 'Supplier ' || b.supplier_id) || ' has not paid the ' || v_cfg.currency || ' '
                   || b.amount_due_aed || ' subscription due on ' || v_due_on || ' (' || v_days || ' days, '
                   || coalesce(array_length(v_dun, 1), 0) || ' reminders sent)',
          'blast', 'agent_facing', 'affected', 1, 'demo', b.is_demo,
          'evidence', jsonb_build_object('supplier_id', b.supplier_id, 'due_on', v_due_on, 'days_overdue', v_days,
                                         'billing_status', b.billing_status, 'amount_due_aed', b.amount_due_aed));
      end if;
    end if;
  end loop;

  return jsonb_build_object('as_of', v_as_of, 'position', v_pos, 'ceo_reports', n_rep, 'first_notices', v_run,
    'renewal_reminders', n_renew, 'dunning', n_dun, 'findings', public.fn_accountant_duty_settle('subscriptions', v_items));
end $fn$;
revoke execute on function public.fn_accountant_subscription_tick(date) from public, anon, authenticated;
