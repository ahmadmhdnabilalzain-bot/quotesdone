-- ===== FUNCTIONS =====
CREATE OR REPLACE FUNCTION public._next_docver(p_type text, p_id text)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select coalesce(max(version),0)+1 from public.doc_versions where entity_type=p_type and entity_id=p_id $function$


CREATE OR REPLACE FUNCTION public._rfq_answered(v text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select v is not null
     and btrim(v) <> ''
     and btrim(v) not in ('[]','{}','-','?')
     and lower(btrim(v)) not in ('null','not sure','unknown','tbd','n/a','na');
$function$


CREATE OR REPLACE FUNCTION public._rfq_concept(k text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
    when k is null or btrim(k) = '' then null
    -- location first: "emirate / area" is a place, not a quantity
    when k ~ '(location|emirate|address|site|floor|region|area/|/area)' then 'loc'
    when k ~ '(quantity|qty|size|sizes|dimension|dimensions|area|volume|units|linear|count|sqm|sqft)' then 'qty'
    when k ~ '(scope|supply_install|install)'         then 'scope'
    when k ~ '(timeline|schedule|duration|deadline|when)' then 'time'
    when k ~ '(budget|price|cost)'                    then 'budget'
    when k ~ '(finish|material|fabric|fibre|colou?r)' then 'material'
    when k ~ '(item|product|element|service)'         then 'item'
    else null end;
$function$


CREATE OR REPLACE FUNCTION public.a00_llm_attempt_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  raise exception
    'llm_attempt is append-only (attempted % on attempt_id %). A retry inserts a new row with the next attempt_no; it never rewrites an earlier attempt, because first-attempt success rate must stay computable.',
    tg_op, coalesce(old.attempt_id::text,'?')
    using errcode = 'restrict_violation';
end $function$


CREATE OR REPLACE FUNCTION public.auth_uid_by_email(p_email text)
 RETURNS uuid
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'auth', 'public'
AS $function$
  select id from auth.users where lower(email) = lower(p_email) limit 1;
$function$


CREATE OR REPLACE FUNCTION public.block_disposable_signup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare em text;
begin
  if TG_TABLE_NAME = 'customers' then
    em := NEW.email;
  else
    -- only gate genuine supplier signups; leave scraped leads (claimed false/null) untouched
    if NEW.claimed is distinct from true then return NEW; end if;
    em := coalesce(NEW.claimed_by, NEW.email);
  end if;
  if em is not null and is_disposable_email(em) then
    raise exception 'Please use a permanent email address; temporary inboxes are not allowed.' using errcode = '23514';
  end if;
  return NEW;
end$function$


CREATE OR REPLACE FUNCTION public.dedupe_it_incident()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.agent='it' and NEW.kind='incident' and coalesce(NEW.status,'pending')='pending' then
    if exists (
      select 1 from public.agent_actions a
      where a.agent='it' and a.kind='incident' and a.status='pending'
        and coalesce(a.target_table,'')=coalesce(NEW.target_table,'')
    ) then
      return null; -- duplicate open incident; skip
    end if;
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.enqueue_supplier_invites(p_cap integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_today date := (now() at time zone 'UTC')::date;
  v_planned int; v_used int; v_remaining int; v_count int;
  v_inv_recent int; v_bounced_recent int; v_rate numeric; v_max_rate numeric; v_cap int;
  v_pause boolean := false; v_why text; v_go boolean; v_pool int;
  v_hol_name text; v_hol_action text; v_hol_end date;
  v_cfg jsonb := coalesce((select nullif(value,'')::jsonb from app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_win_start timestamptz; v_win_end timestamptz;
  v_gate text;
begin
  select c.event_name, c.action, c.ends_on into v_hol_name, v_hol_action, v_hol_end
    from public.company_calendar c
   where c.kind = 'public_holiday'
     and v_today between c.starts_on and coalesce(c.ends_on, c.starts_on)
   order by c.starts_on limit 1;
  if v_hol_name is not null then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok',
            jsonb_build_object('queued', 0, 'calendar_paused', true, 'resumes_on', coalesce(v_hol_end, v_today) + 1),
            'Invites held: company_calendar has "' || v_hol_name || '" covering today. Its recorded action: '
            || coalesce(v_hol_action, '(none recorded)'), now(), now());
    return 0;
  end if;

  -- THE UAE WEEKEND IS SATURDAY AND SUNDAY. A cold invitation queued then waits under Monday's pile.
  -- Self-clearing like the holiday hold: nothing is switched off, Monday simply runs.
  if extract(isodow from (now() at time zone 'Asia/Dubai')) in (6, 7) then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok', jsonb_build_object('queued', 0, 'weekend_hold', true),
            'Invites held: it is the UAE weekend in Dubai; the next weekday batch runs as normal.', now(), now());
    return 0;
  end if;

  v_go  := (coalesce((select value from app_secrets where key = 'invite_enabled'), 'false') = 'true')
           and public.fn_supplier_outreach_golive();
  v_cap := coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), 10);
  -- founder ruling 1231: never more than the dated founder cap, whatever invite_daily_cap holds.
  v_cap := least(v_cap, public.fn_invite_founder_cap((now() at time zone 'Asia/Dubai')::date));
  select count(*) into v_pool from leads l where public.fn_supplier_invite_eligible(l);
  v_planned := least(coalesce(p_cap, v_cap), v_cap, v_pool);
  insert into invite_schedule(day, planned, status, note)
  values (v_today, greatest(v_planned, 0),
          case when v_go then 'approved' else 'pending' end,
          'batch of ' || greatest(v_planned, 0) || ' from a pool of ' || v_pool || ' eligible never-invited lead(s), cap ' || v_cap
          || case when v_go then '; sending open'
                  when not public.fn_supplier_outreach_golive() then '; HELD — real invitations wait for the founder''s go (app_secrets.supplier_outreach_golive is false)'
                  else '; HELD — real invitations wait for the founder''s go (app_secrets.invite_enabled)' end)
    on conflict (day) do update
      set planned = excluded.planned, status = excluded.status, note = excluded.note;

  if not v_go then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok',
            jsonb_build_object('queued', 0, 'planned', greatest(v_planned, 0), 'pool', v_pool, 'cap', v_cap, 'held', true),
            'Invites planned and HELD: ' || greatest(v_planned, 0) || ' of a pool of ' || v_pool
            || ' would be queued at cap ' || v_cap || '; '
            || case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive' else 'invite_enabled' end
            || ' is false, so nothing was written to the outbox.', now(), now());
    return 0;
  end if;
  if v_planned <= 0 then return 0; end if;

  -- PLACEMENT GATE (24 Sep 2026, it_engineer). Nothing is queued unless this morning's seed invitation landed
  -- in the Inbox of both seed mailboxes under today's effective sender (fn_invite_placement_gate). Fail closed: a check
  -- that is still running, failed, or never ran all hold the batch.
  v_gate := public.fn_invite_placement_gate((now() at time zone 'Asia/Dubai')::date);
  if v_gate <> 'pass' then
    update invite_schedule set status = 'pending', note = coalesce(note,'') || '; held: inbox placement ' || v_gate where day = v_today;
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok', jsonb_build_object('queued', 0, 'planned', v_planned, 'placement_gate', v_gate, 'held', true),
            'Invites held: the morning inbox placement check answered ' || v_gate || ', so nothing was written to the outbox.', now(), now());
    return 0;
  end if;

  -- THE SENDING WINDOW (22 Sep 2026). Invitations leave between the later of now and the window's start
  -- and the end of the Dubai working day, evenly spaced. Past the window nothing is queued: a cold
  -- invitation at night lands under the morning's pile, and tomorrow's batch runs as normal.
  v_win_start := greatest(now(), ((now() at time zone 'Asia/Dubai')::date
                   + make_interval(hours => coalesce((v_cfg->>'window_start_hour')::int, 9))) at time zone 'Asia/Dubai');
  v_win_end := ((now() at time zone 'Asia/Dubai')::date + make_interval(hours => coalesce((v_cfg->>'window_end_hour')::int, 17)))
               at time zone 'Asia/Dubai';
  if v_win_end < v_win_start + interval '30 minutes' then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok', jsonb_build_object('queued', 0, 'planned', v_planned, 'outside_window', true),
            'Invites held: the Dubai sending window closes at ' || to_char(v_win_end at time zone 'Asia/Dubai', 'HH24:MI')
            || '; the next weekday batch runs as normal.', now(), now());
    return 0;
  end if;

  v_max_rate := coalesce((select nullif(value,'')::numeric from app_secrets where key='invite_max_bounce_rate'), 0.08);
  select count(*) into v_inv_recent from leads where invited_at > now() - interval '3 days';
  select count(*) into v_bounced_recent from leads where invite_status='bounced' and invited_at > now() - interval '3 days';
  v_rate := round(v_bounced_recent::numeric / greatest(v_inv_recent,1), 3);

  if v_inv_recent >= 15 and v_rate > v_max_rate then
    v_pause := true;
    v_why := 'bounce rate '||(v_rate*100)||'% over 3 days ('||v_bounced_recent||'/'||v_inv_recent||') exceeds the '||(v_max_rate*100)||'% limit';
  end if;
  if not v_pause and v_bounced_recent >= greatest(5, ceil(v_inv_recent * v_max_rate)::int) then
    v_pause := true;
    v_why := v_bounced_recent||' hard bounces in 3 days against '||v_inv_recent||' sent. Regardless of rate, that is a list-quality problem';
  end if;

  if v_pause then
    update app_secrets set value='false' where key='invite_enabled';
    update invite_schedule set status = 'pending', note = coalesce(note,'') || '; auto-paused: ' || v_why where day = v_today;
    if not exists (select 1 from founder_alerts where event='invite_paused_bounce' and created_at > now()-interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
        values('crit','invite_paused_bounce','Supplier invites AUTO-PAUSED: '||v_why||'. Clean the list before resuming.','system');
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values('invite_paused_bounce', coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),'management@quotesdone.com'),'admin','email','Supplier invites paused - deliverability risk','Invites were auto-paused: '||v_why||'. Validate the list, then re-enable.','queued');
    end if;
    return 0;
  end if;

  -- test-path rows (fixture addresses) are not invitations and must not spend the day's cap:
  -- measured in the rolled-back rehearsal, two test sends plus one real row cut a batch of 5 to 2.
  -- ONE daily cap for invitations and their nudges (review of #1007, 29 Sep 2026): a nudge queued today spends it too,
  -- as fn_sales_engineer_nudges_invited_suppliers already counts the invitations queued today against the same cap.
  select count(*) into v_used from notifications where type in ('supplier_invite', 'supplier_invite_nudge') and (created_at at time zone 'UTC')::date = v_today
     and not public.fn_is_demo_email(to_email);
  v_remaining := greatest(0, v_planned - v_used);
  if v_remaining <= 0 then return 0; end if;

  with c as (
    select c.*, row_number() over () as rn, count(*) over () as n
      from public.fn_supplier_invite_candidates(v_remaining) c
  ), ins as (
    insert into notifications(type, to_email, to_role, lead_id, subject, body, lang, status, created_at, not_before)
    select 'supplier_invite', c.to_email, 'supplier', c.lead_id, c.subject, c.body, c.lang, 'queued', now(),
           v_win_start + (c.rn - 1) * ((v_win_end - v_win_start) / greatest(c.n, 1))
      from c
    on conflict (lower(btrim(to_email))) where type = 'supplier_invite' do nothing
    returning lead_id
  )
  update leads set invite_status='queued', invited_at=now()
  where invite_status is null and id in (select lead_id from ins);
  get diagnostics v_count = row_count;
  update invite_schedule set sent = sent + v_count where day = v_today;
  insert into agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('supplier_invites', 'ok',
          jsonb_build_object('queued', v_count, 'planned', v_planned, 'pool', v_pool, 'cap', v_cap, 'held', false,
                             'window_ends', v_win_end),
          'Invites: ' || v_count || ' queued of ' || v_planned || ' planned (pool ' || v_pool || ', cap ' || v_cap
          || '), spread until ' || to_char(v_win_end at time zone 'Asia/Dubai', 'HH24:MI') || ' Dubai.', now(), now());
  return v_count;
end;
$function$


CREATE OR REPLACE FUNCTION public.ensure_category_agent()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not exists (select 1 from public.category_agents where slug = NEW.slug) then
    insert into public.category_agents(slug, name, active, created_at)
    values (
      NEW.slug,
      coalesce(NEW.name, initcap(replace(NEW.slug, '-', ' '))),
      true,
      now()
    );
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_acts_on_handoff(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  a public.agent_actions; d jsonb; t text; r public.refunds; tx public.transactions; du public.supplier_dues;
  v_expected bigint; v_ok boolean; v_checks jsonb; v jsonb; v_lines text[] := '{}'; v_match boolean; x record;
begin
  select * into a from public.agent_actions where id = p_id;
  d := a.detail; t := d->>'type';

  if t = 'refund.requested' then
    select * into r from public.refunds where id = (d->>'subject_id')::bigint;
    select * into tx from public.transactions where id = r.transaction_id;
    v_expected := round(coalesce(tx.total_charged, tx.reveal_fee, 0) * 100)::bigint;
    v_checks := jsonb_build_object(
      'transaction_found', tx.id is not null,
      'fee_settled', coalesce(tx.fee_status, '') = 'paid',
      'stripe_reference_matches', coalesce(btrim(tx.payment_ref), '') <> '' and btrim(tx.payment_ref) = btrim(coalesce(r.stripe_payment_intent, '')),
      'amount_is_total_charged', r.amount_fils = v_expected,
      'total_charged_recorded', tx.total_charged is not null,
      'expected_fils', v_expected, 'requested_fils', r.amount_fils);
    v_ok := (v_checks->>'transaction_found')::boolean and (v_checks->>'fee_settled')::boolean
            and (v_checks->>'stripe_reference_matches')::boolean and (v_checks->>'amount_is_total_charged')::boolean;
    perform public.fn_seat_handoff('accountant', 'sales_engineer', 'refund.request_checked', 'refunds', r.id::text,
      jsonb_build_object('refund_id', r.id, 'transaction_id', r.transaction_id, 'customer_id', r.customer_id,
                         'inquiry_id', r.inquiry_id, 'quote_id', r.quote_id, 'money_ok', v_ok,
                         'amount_aed', round(coalesce(r.amount_fils, 0) / 100.0, 2)));
    return v_checks || jsonb_build_object('money_ok', v_ok);

  elsif t = 'billing.question' then
    if d->>'party' = 'supplier' then
      perform public.fn_supplier_dues_accrue_interest(null);
      for x in select * from public.supplier_dues
                where supplier_id = (d->>'supplier_id')::bigint and coalesce(status, '') not in ('cancelled')
                order by id loop
        v_lines := v_lines || ('Charge #' || x.id || ' (reveal of ' || coalesce(x.reveal_date::text, '?') || '): AED '
          || coalesce(x.amount_due, 0) || ' non-response charge (the refund to the customer and, from v14, the processor fee not recovered) + AED ' || coalesce(x.admin_fee, 0) || ' administration + AED '
          || coalesce(x.interest_amount, 0) || ' interest = AED ' || coalesce(x.total_claim, coalesce(x.amount_due, 0) + coalesce(x.admin_fee, 0) + coalesce(x.interest_amount, 0))
          || ', due ' || coalesce(x.due_date::text, '?') || ', ' || case when x.paid_at is not null then 'paid' else coalesce(x.status, 'open') end || '.');
      end loop;
      v := public.fn_supplier_registration_state((d->>'supplier_id')::bigint);
      if v is not null then
        v_lines := v_lines || ('Registration: ' || coalesce(v->>'status', 'unknown') || coalesce(', fee due AED ' || nullif(v->>'fee_due', '0'), '') || '.');
      end if;
    else
      for x in select t2.*, i.summary from public.transactions t2 left join public.inquiries i on i.id = t2.inquiry_id
                where t2.customer_id = (d->>'customer_id')::uuid
                  and ((d->>'transaction_id') is null or t2.id = (d->>'transaction_id')::uuid)
                  and t2.revealed_at is not null
                order by t2.revealed_at desc limit 10 loop
        v_lines := v_lines || ('Reveal on ' || to_char(x.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY')
          || coalesce(' for "' || left(x.summary, 60) || '"', '') || ': you paid AED ' || coalesce(x.total_charged, x.reveal_fee)
          || case when x.total_charged is not null and x.total_charged > coalesce(x.reveal_fee, 0)
                  then ' (reveal fee AED ' || x.reveal_fee || ' + card processing AED ' || (x.total_charged - x.reveal_fee) || ')' else '' end
          || '. Invoice ' || coalesce(x.stripe_invoice_number, 'not yet issued')
          || ' (the invoice and the receipt, as QuotesDone PDFs in English and Arabic, are on the revealed quote in the customer portal)'
          || '. Refund: ' || case when x.refund_status in ('refunded', 'succeeded') then 'AED ' || coalesce(x.refund_amount_aed::text, '?') || ' returned'
                                  when x.refund_status = 'requested' then 'requested and under review'
                                  when x.refund_status = 'rejected' then 'declined'
                                  else 'none requested' end || '.');
      end loop;
    end if;
    perform public.fn_seat_handoff('accountant', 'sales_engineer', 'billing.answer', 'agent_actions', a.id::text,
      jsonb_build_object('party', d->>'party', 'customer_id', d->>'customer_id', 'supplier_id', d->>'supplier_id',
                         'question', d->>'question', 'facts', to_jsonb(v_lines)));
    return jsonb_build_object('facts', to_jsonb(v_lines));

  elsif t = 'charge.disputed' then
    select * into du from public.supplier_dues where id = coalesce((d->>'due_id')::bigint, (d->>'subject_id')::bigint);
    v := public.fn_accountant_nonresponse_charge(du.transaction_id, null);
    v_match := coalesce((v->>'ok')::boolean, false)
               and du.amount_due = (v->>'charge_aed')::numeric
               and du.admin_fee = (v->>'admin_fee_aed')::numeric
               and du.due_date = (v->>'due_date')::date;
    v_lines := array[
      'Charged: AED ' || coalesce(du.amount_due, 0) || ' + AED ' || coalesce(du.admin_fee, 0) || ' administration, due ' || coalesce(du.due_date::text, '?') || '.',
      'Payment record: ' || coalesce('AED ' || (v->>'refunded_aed') || ' refunded to the customer (' || (v->>'refund_source') || ')'
                                     || case when coalesce((v->>'processor_fee_aed')::numeric, 0) > 0 then ' + AED ' || (v->>'processor_fee_aed') || ' processor fee not recovered' else '' end || ' + AED '
                                     || (v->>'admin_fee_aed') || ' administration, due ' || (v->>'due_date') || '.', coalesce(v->>'reason', 'unreadable')),
      'Interest to date: AED ' || coalesce(v->>'interest_aed', '0') || ' at ' || coalesce(round((v->>'interest_apr')::numeric * 100, 2)::text, '?') || '% a year over '
        || coalesce(v->>'interest_days', '0') || ' day(s).'];
    if not v_match then
      insert into public.ceo_task (title, detail)
      values (left('Supplier disputed charge #' || du.id || ' and it does not match the refund record', 200),
              'The accountant recomputed charge #' || du.id || ' from the refund record and the figures differ. ' || array_to_string(v_lines, ' '));
    end if;
    perform public.fn_seat_handoff('accountant', 'sales_engineer', 'charge.dispute_answer', 'supplier_dues', du.id || ':' || a.id,
      jsonb_build_object('supplier_id', du.supplier_id, 'due_id', du.id, 'figures_match', v_match, 'lines', to_jsonb(v_lines), 'reason', d->>'reason'));
    return jsonb_build_object('figures_match', v_match, 'recomputed', v);

  elsif t = 'refund.remediate' then
    return public.fn_accountant_remediates(p_id);

  elsif t = 'incident.fix' then
    return public.fn_accountant_applies_incident_fix(p_id);
  end if;
  raise exception 'accountant has no handler for %', t;
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_ad_spend_figures(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_m date := date_trunc('month', p_month)::date; v_e date; v_from timestamptz; v_to timestamptz;
  v_fx numeric; v_inv numeric; v_n int; v_unconv int; v_rep numeric; v_inq int; v_rev int;
begin
  v_e := (v_m + interval '1 month')::date - 1;
  v_from := v_m::timestamp at time zone 'Asia/Dubai'; v_to := (v_e + 1)::timestamp at time zone 'Asia/Dubai';
  -- The same conversion the monthly close uses (gl_settings usd_to_aed; AED is pegged at 3.6725).
  v_fx := coalesce((select num_value from public.gl_settings where key = 'usd_to_aed'), 3.6725);

  select count(*) filter (where upper(currency) in ('AED', 'USD')),
         round(sum(amount * case upper(currency) when 'USD' then v_fx else 1 end) filter (where upper(currency) in ('AED', 'USD')), 2),
         count(*) filter (where upper(currency) not in ('AED', 'USD'))
    into v_n, v_inv, v_unconv
    from public.expense_entries where read_as = 'meta_ads_invoice' and charged_on between v_m and v_e;
  select reported_spend_aed into v_rep from public.accountant_ad_spend_month where month = v_m;
  select count(*) into v_inq from public.inquiries i left join public.customers c on c.id = i.customer_id
   where i.created_at >= v_from and i.created_at < v_to and not coalesce(c.is_demo, false);
  select count(*) into v_rev from public.transactions t left join public.customers c on c.id = t.customer_id
   where t.fee_status = 'paid' and t.revealed_at >= v_from and t.revealed_at < v_to and not coalesce(c.is_demo, false);

  return jsonb_build_object(
    'month', to_char(v_m, 'YYYY-MM'),
    'invoiced_aed', case when v_n > 0 then v_inv end,
    'meta_invoices', v_n, 'meta_invoices_unconverted', v_unconv,
    'reported_spend_aed', v_rep,
    'difference_aed', case when v_n > 0 and v_rep is not null then v_inv - v_rep end,
    'inquiries', v_inq, 'reveals', v_rev,
    'cost_per_inquiry_aed', case when v_n > 0 and v_inq > 0 then round(v_inv / v_inq, 2) end,
    'cost_per_reveal_aed', case when v_n > 0 and v_rev > 0 then round(v_inv / v_rev, 2) end,
    'missing', to_jsonb(array_remove(array[
      case when v_n = 0 then 'no Meta invoice is booked in expense_entries for the month' end,
      case when v_unconv > 0 then v_unconv || ' Meta invoice(s) in a currency other than AED or USD are not converted' end,
      case when v_rep is null then 'Meta reported no spend for the month (meta_sync wrote none, or nothing was spent)' end,
      case when v_inq = 0 then 'no inquiry in the month, so there is no cost per inquiry' end,
      case when v_rev = 0 then 'no paid reveal in the month, so there is no cost per reveal' end], null)),
    'basis', 'Invoiced = Meta ads invoices booked in expense_entries (read_as meta_ads_invoice: each document REASONED to be a Meta advertising invoice when it was booked), USD at gl_settings usd_to_aed. Reported = ad_spend_policy.month_spent_aed as meta_sync last wrote it for the month. Cost per inquiry and per reveal divide the INVOICED figure by the inquiries created and the reveals paid in the month (Asia/Dubai). ZZ DEMO customers are not counted.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_ad_spend_reconcile()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_accountant_ad_spend_tick() $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_ad_spend_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare p public.ad_spend_policy; v_m date;
begin
  select * into p from public.ad_spend_policy where policy_key = 'default';
  if not found or coalesce(p.month_label, '') !~ '^\d{4}-\d{2}$' then
    return jsonb_build_object('kept', false, 'reason', 'no default ad_spend_policy row with a YYYY-MM month_label');
  end if;
  v_m := to_date(p.month_label || '-01', 'YYYY-MM-DD');
  if coalesce(p.month_spent_aed, 0) <= 0 then
    return jsonb_build_object('kept', false, 'month', p.month_label,
      'reason', 'month_spent_aed is 0: nothing was spent, or meta_sync has not read the account');
  end if;
  insert into public.accountant_ad_spend_month (month, reported_spend_aed, reported_at, updated_at)
  values (v_m, round(p.month_spent_aed, 2), p.updated_at, now())
  on conflict (month) do update set reported_spend_aed = excluded.reported_spend_aed,
                                    reported_at = excluded.reported_at, updated_at = now();
  return jsonb_build_object('kept', true, 'month', p.month_label, 'reported_spend_aed', round(p.month_spent_aed, 2));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_ad_spend_tick(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_tol numeric := (select (value #>> '{}')::numeric from public.decision_policy where key = 'accountant_ad_spend_match_tolerance_aed');
  v_grace int := (select (value #>> '{}')::int from public.decision_policy where key = 'accountant_ad_spend_invoice_grace_days');
  v_snap jsonb; v_last date; v_m date; f jsonb; v_mon text; v_items jsonb := '[]'::jsonb; v_months jsonb := '[]'::jsonb;
begin
  if v_tol is null or v_grace is null then
    raise exception 'decision_policy accountant_ad_spend_match_tolerance_aed and accountant_ad_spend_invoice_grace_days are required';
  end if;
  v_snap := public.fn_accountant_ad_spend_snapshot();
  v_last := (date_trunc('month', v_as_of - v_grace) - interval '1 month')::date;
  for v_m in select generate_series(v_last - interval '2 months', v_last, interval '1 month')::date loop
    f := public.fn_accountant_ad_spend_figures(v_m);
    v_months := v_months || f;
    v_mon := to_char(v_m, 'Mon YYYY');
    if (f->>'reported_spend_aed') is not null and (f->>'invoiced_aed') is null then
      v_items := v_items || jsonb_build_object('item', 'uninvoiced:' || (f->>'month'), 'owner_seat', 'accountant', 'subject', 'expense_entries',
        'title', 'Meta reported AED ' || (f->>'reported_spend_aed') || ' of ad spend in ' || v_mon || ' and no Meta invoice is booked for it',
        'blast', 'agent_facing', 'affected', 1, 'evidence', f);
    elsif (f->>'reported_spend_aed') is not null and abs((f->>'difference_aed')::numeric) > v_tol then
      v_items := v_items || jsonb_build_object('item', 'mismatch:' || (f->>'month'), 'owner_seat', 'accountant', 'subject', 'expense_entries',
        'title', 'Meta invoices booked for ' || v_mon || ' total AED ' || (f->>'invoiced_aed') || ' but Meta reported AED '
                 || (f->>'reported_spend_aed') || ' (difference AED ' || (f->>'difference_aed') || ')',
        'blast', 'agent_facing', 'affected', 1, 'evidence', f);
    elsif (f->>'invoiced_aed') is not null and (f->>'reported_spend_aed') is null then
      -- The Meta token is the founder's to mint (the ad-spend build), so an account nobody read is the CEO's.
      v_items := v_items || jsonb_build_object('item', 'unreported:' || (f->>'month'), 'owner_seat', 'ceo', 'subject', 'ad_spend_policy',
        'title', 'Meta invoices of AED ' || (f->>'invoiced_aed') || ' are booked for ' || v_mon
                 || ' but no reported spend was kept for the month: meta_sync did not read the account',
        'blast', 'agent_facing', 'affected', 1, 'evidence', f);
    end if;
  end loop;
  return jsonb_build_object('snapshot', v_snap, 'months', v_months, 'findings', public.fn_accountant_duty_settle('ad_spend', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_applies_incident_fix(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d jsonb; v_fix text; v_tx uuid; v_old bigint; v_orig bigint; v jsonb; v_j bigint; v_amt numeric; v_res jsonb; v_du public.supplier_dues;
        v_why text;
begin
  select detail into d from public.agent_actions where id = p_id;
  v_fix := d->>'fix'; v_tx := (d->>'transaction_id')::uuid;
  if v_fix in ('refund_difference', 'retry_refund', 'cancel_duplicate') then
    return jsonb_build_object('waiting', 'stripe: the accountant runtime executes ' || v_fix || ' (accountant action execute_refunds)');
  end if;

  perform set_config('app.qd_incident_fix', 'on', true);
  if v_fix = 'book_over_refund_loss' then
    -- test money never reaches the books: a fixture or orphaned transaction's loss is not the company's
    v_why := public.fn_gl_fixture_or_orphan(v_tx, null, null);
    if v_why is not null then
      perform set_config('app.qd_incident_fix', '', true);
      return jsonb_build_object('refused', 'not booked: ' || v_why);
    end if;
    v_amt := round((d->>'amount_aed')::numeric, 2);
    select g.id into v_j from public.gl_journal g where g.source = 'refund_over_loss' and g.source_ref = v_tx || ':' || (d->>'incident_id');
    if v_j is null and v_amt > 0 then
      v_j := public.fn_gl_entry(current_date,
        'Over-refund on reveal ' || left(v_tx::text, 8) || ' booked as company loss (incident #' || (d->>'incident_id') || '); the supplier charge stays at the approved amount',
        'refund_over_loss', v_tx || ':' || (d->>'incident_id'),
        jsonb_build_array(jsonb_build_object('account', '6900', 'debit', v_amt), jsonb_build_object('account', '1050', 'credit', v_amt)), 'accountant');
    end if;
    v_res := jsonb_build_object('journal_id', v_j, 'amount_aed', v_amt);
  elsif v_fix = 'reissue_charge' then
    -- supplier_dues holds ONE row per transaction (supplier_dues_transaction_id_key), so the charge is
    -- reissued IN PLACE: the figures become the routine's, and the old ones are kept in the evidence.
    select * into v_du from public.supplier_dues where transaction_id = v_tx order by id limit 1;
    v_old := v_du.id;
    select (a.evidence->>'notification_id')::bigint into v_orig from public.agent_actions a
     where a.kind = 'handoff' and a.agent = 'customer_support' and a.target_id = 'delivery.request:nonresponse_charge:' || v_old
     order by a.id desc limit 1;
    v := public.fn_accountant_nonresponse_charge(v_tx, null);
    if not coalesce((v->>'ok')::boolean, false) then
      perform set_config('app.qd_incident_fix', '', true);
      return jsonb_build_object('waiting', 'the charge cannot be recomputed: ' || coalesce(v->>'reason', '?'));
    end if;
    update public.supplier_dues
       set amount_due = (v->>'charge_aed')::numeric, admin_fee = (v->>'admin_fee_aed')::numeric,
           interest_amount = (v->>'interest_aed')::numeric, total_claim = (v->>'total_aed')::numeric,
           due_date = (v->>'due_date')::date, due_date_30 = (v->>'due_date')::date + 23,
           status = case when status = 'cancelled' then 'due' else status end
     where id = v_old;
    v := v || jsonb_build_object('due_id', v_old, 'transaction_id', v_tx, 'supplier_id', v_du.supplier_id,
                                 'inquiry_id', (select inquiry_id from public.transactions where id = v_tx),
                                 'quote_id', (select quote_id from public.transactions where id = v_tx));
    if coalesce((d->>'sent')::boolean, false) then
      -- Already in the supplier's hands: a correction that supersedes it, to whoever got the original.
      perform public.fn_seat_handoff('accountant', 'sales_engineer', 'charge.corrected', 'supplier_dues', v_old::text,
        v || jsonb_build_object('original_notification_id', v_orig));
    else
      -- Not sent yet: withdraw it from the outbox and send the right one instead.
      update public.notifications set status = 'cancelled', last_error = 'withdrawn before sending: the charge was reissued with the correct figures'
       where id = v_orig and status in ('queued', 'pending', 'held');
      update public.agent_actions set status = 'failed', detail = detail || jsonb_build_object('superseded_by_incident', d->>'incident_id')
       where kind = 'handoff' and status = 'done'
         and target_id in ('nonresponse.charge_raised:' || v_old, 'delivery.request:nonresponse_charge:' || v_old);
      perform public.fn_seat_handoff('accountant', 'sales_engineer', 'nonresponse.charge_raised', 'supplier_dues', v_old::text, v);
    end if;
    v_res := jsonb_build_object('reissued_due', v_old,
      'was', jsonb_build_object('amount_due', v_du.amount_due, 'admin_fee', v_du.admin_fee, 'due_date', v_du.due_date),
      'now', v, 'correction_sent_to_original_recipients', coalesce((d->>'sent')::boolean, false));
  elsif v_fix = 'raise_charge' then
    v_res := public.fn_accountant_raise_nonresponse_charge(v_tx, true);
  else
    v_res := jsonb_build_object('waiting', 'no handler for fix ' || coalesce(v_fix, '?'));
  end if;
  perform set_config('app.qd_incident_fix', '', true);
  return v_res;
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_assist(p_text text, p_embedding vector DEFAULT NULL::vector, p_min_similarity numeric DEFAULT 0.86, p_min_rank numeric DEFAULT 0.05, p_k integer DEFAULT 5, p_min_overlap numeric DEFAULT 0.60)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_k         int := greatest(1, least(coalesce(p_k, 5), 20));
  v_wide      int := greatest(v_k * 4, 20);
  c_lex_only  numeric := greatest(0.20, coalesce(p_min_rank, 0));
  v_tq        tsquery;
  v_lex       text[];
  v_nlex      int;
  v_need      int;
  v_cands     jsonb  := '[]'::jsonb;
  v_cited     text[] := '{}';
  v_answer    jsonb  := '[]'::jsonb;
  v_refusal   text;
  v_best_sim  numeric;
  v_best_rank numeric;
  v_best_lex  int;
  v_best_corp text;
  v_handoff   text;
begin
  if coalesce(btrim(p_text), '') = '' then
    return jsonb_build_object(
    -- THE COMPANY BLOCK. Pinned, never retrieved and never rankable: it is here on every answer,
    -- including the refusals, because a seat with no retrieval hit is exactly the seat most likely
    -- to improvise a fee or a policy. Founder ruling, 9 Sep 2026.
    'company', public.fn_company_context(),
    'ok', false, 'answered', false, 'refusal', 'empty_query');
  end if;

  v_tq := websearch_to_tsquery('english', p_text);
  select array_agg(distinct u.lexeme) into v_lex from unnest(to_tsvector('english', p_text)) u;
  v_nlex := coalesce(cardinality(v_lex), 0);
  -- The greater of 60% and two lexemes, so a short question cannot be admitted on one common word.
  v_need := case when v_nlex = 0 then 2147483647
                 else greatest(least(2, v_nlex), ceil(coalesce(p_min_overlap, 0.60) * v_nlex)::int) end;

  create temporary table if not exists _aa_cand (
    corpus text, record_id text, title text, content text, provenance text,
    similarity numeric, lexical_rank numeric, has_vector boolean, lex_hits int default 0
  ) on commit drop;
  -- truncate, not delete: the estate refuses an unqualified DELETE and a WHERE-less delete on a
  -- scratch table is exactly what that guard exists to catch elsewhere.
  truncate table _aa_cand;

  -- accountant_knowledge -- the seat's own body.
  if p_embedding is not null then
    insert into _aa_cand
    select 'accountant_knowledge', k.record_id, k.title, left(k.content, 4000),
           coalesce(k.record_type, '') || case when k.domain is null then '' else ' · ' || k.domain end
             || ' · ' || k.epistemic_status,
           (1 - (k.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(k.search, v_tq), 0)::numeric * (case when k.search @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(k.search) u where u.lexeme = any (v_lex))
      from accountant_knowledge k
     where k.embedding_gte is not null and k.runtime_index_eligible
     order by k.embedding_gte <=> p_embedding
     limit v_wide;
  end if;
  insert into _aa_cand
  select 'accountant_knowledge', k.record_id, k.title, left(k.content, 4000),
         coalesce(k.record_type, '') || ' · ' || k.epistemic_status,
         null::numeric, ts_rank(k.search, v_tq)::numeric, false, 0
    from accountant_knowledge k
   where k.embedding_gte is null and k.runtime_index_eligible and k.search @@ v_tq
   order by ts_rank(k.search, v_tq) desc
   limit v_wide;

  -- ops_knowledge -- how this company actually operates. A finance question frequently turns on a
  -- company rule rather than on accounting, and a seat that cannot see those answers half a
  -- question. Superseded rows are excluded: never quote a rule that has been replaced.
  if p_embedding is not null then
    insert into _aa_cand
    select 'ops_knowledge', o.record_id, o.title, left(o.content, 4000),
           coalesce(o.record_type, '') || case when o.authority_tier is null then '' else ' · authority ' || o.authority_tier end,
           (1 - (o.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(o.tsv, v_tq), 0)::numeric * (case when o.tsv @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(o.tsv) u where u.lexeme = any (v_lex))
      from ops_knowledge o
     where o.embedding_gte is not null
       and coalesce(o.supersession_state, 'current') = 'current'
     order by o.embedding_gte <=> p_embedding
     limit v_wide;
  end if;

  -- ADMISSION. The cosine floor is a hard AND for every vector-bearing row; corroboration may come
  -- from either the all-terms rank or literal lexeme overlap, and one of the two is required.
  with judged as (
    select c.*,
           (c.has_vector and c.similarity >= p_min_similarity
             and (c.lexical_rank >= p_min_rank or c.lex_hits >= v_need))     as ok_vector,
           ((not c.has_vector) and c.lexical_rank >= c_lex_only)             as ok_lexical
      from _aa_cand c
  ), ranked as (
    select j.*, (j.ok_vector or j.ok_lexical) as cited,
           row_number() over (
             order by (case when j.ok_vector or j.ok_lexical then 0 else 1 end),
                      (case when j.has_vector then 0 else 1 end),
                      j.similarity desc nulls last, j.lexical_rank desc) as rn
      from judged j
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'corpus', r.corpus, 'record_id', r.record_id,
      'similarity', round(r.similarity, 4), 'lexical_rank', round(r.lexical_rank, 4),
      'route', case when r.has_vector then 'vector+lexical' else 'lexical_only' end,
      'cleared_floor', coalesce(r.has_vector and r.similarity >= p_min_similarity, false),
      'lex_hits', r.lex_hits, 'lex_needed', v_need,
      'corroborated', case when r.has_vector then (r.lexical_rank >= p_min_rank or r.lex_hits >= v_need)
                           else r.lexical_rank >= c_lex_only end,
      'cited', r.cited) order by r.rn) filter (where r.rn <= 40), '[]'::jsonb),
    coalesce(array_agg(r.corpus || ':' || r.record_id order by r.rn)
             filter (where r.cited and r.rn <= v_k), '{}'),
    coalesce(jsonb_agg(jsonb_build_object(
      'corpus', r.corpus, 'record_id', r.record_id, 'title', r.title,
      'provenance', r.provenance,
      'similarity', round(r.similarity, 4), 'lexical_rank', round(r.lexical_rank, 4),
      'route', case when r.has_vector then 'vector+lexical' else 'lexical_only' end,
      'content', r.content) order by r.rn) filter (where r.cited and r.rn <= v_k), '[]'::jsonb)
    into v_cands, v_cited, v_answer
    from ranked r;

  select max(similarity), max(lexical_rank), max(lex_hits)
    into v_best_sim, v_best_rank, v_best_lex from _aa_cand;
  select corpus into v_best_corp from _aa_cand
   order by similarity desc nulls last, lexical_rank desc limit 1;

  if cardinality(v_cited) = 0 then
    v_refusal := case
      when (select count(*) from _aa_cand) = 0 then 'no_candidates'
      when coalesce(v_best_sim, 0) < p_min_similarity and coalesce(v_best_rank, 0) < c_lex_only
        then 'below_similarity_floor_and_lexical_bar'
      when coalesce(v_best_sim, 0) < p_min_similarity then 'below_similarity_floor'
      else 'not_corroborated_lexically' end;
    v_handoff :=
      'I do not have a sourced answer to that, and I will not guess at a financial or tax question. '
      || 'If it needs a rate, a threshold, a deadline or a penalty, that figure is deliberately not '
      || 'held in my knowledge: it is published by the Federal Tax Authority and must be read from '
      || 'its current publication for the period concerned.';
  end if;

  return jsonb_build_object(
    -- THE COMPANY BLOCK. Pinned, never retrieved and never rankable: it is here on every answer,
    -- including the refusals, because a seat with no retrieval hit is exactly the seat most likely
    -- to improvise a fee or a policy. Founder ruling, 9 Sep 2026.
    'company', public.fn_company_context(),
    
    'ok', true,
    'answered', cardinality(v_cited) > 0,
    'records', v_answer,
    'cited', v_cited,
    'candidates', v_cands,
    'corpora', jsonb_build_array('accountant_knowledge', 'ops_knowledge'),
    'floor', jsonb_build_object(
      'min_similarity', p_min_similarity, 'min_rank', p_min_rank, 'lexical_only', c_lex_only,
      'min_overlap', p_min_overlap, 'lexemes_in_question', v_nlex, 'lexeme_overlap_needed', v_need,
      'best_similarity', round(v_best_sim, 4), 'best_lexical_rank', round(v_best_rank, 4),
      'best_lex_hits', v_best_lex, 'nearest_corpus', v_best_corp, 'k', v_k,
      'rule', 'a row with an embedding must clear the cosine floor -- always -- AND corroborate literally by one of two routes: the all-terms lexical query at ts_rank >= min_rank, or at least lexeme_overlap_needed of the question''s own lexemes present verbatim in the row. The overlap route exists because the all-terms route was measured at exactly ts_rank 0.0000 on 9 of 35 realistic questions whose correct record sat at cosine 0.887-0.933: websearch_to_tsquery ANDs every term, so one filler adverb defeats it. A row with no embedding cannot be put to the vector floor at all and must clear the stricter lexical-only bar instead. A nearest neighbour is always found; a literal match is not.'),
    'refusal', v_refusal,
    'handoff', v_handoff);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_bank_balance_record(p_source_ref text, p_balance_aed numeric, p_on date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_balance_aed is null or p_on is null then
    raise exception 'a closing balance needs its amount and the date the statement prints it for';
  end if;
  update public.bank_statement_intake set closing_balance_aed = round(p_balance_aed, 2), balance_on = p_on
   where source_ref = p_source_ref;
  if not found then raise exception 'no bank statement %: ingest the statement first', p_source_ref; end if;
  return jsonb_build_object('ok', true, 'source_ref', p_source_ref, 'closing_balance_aed', round(p_balance_aed, 2), 'balance_on', p_on);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_bank_balance_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_m date; v_items jsonb := '[]'::jsonb;
begin
  select max(month) into v_m from public.accountant_month_close;
  if v_m is not null and not exists (
       select 1 from public.bank_statement_intake where account = 'mashreq' and closing_balance_aed is not null
          and balance_on between v_m and (v_m + interval '1 month')::date - 1) then
    v_items := jsonb_build_array(jsonb_build_object('item', 'bank_balance:' || to_char(v_m, 'YYYY-MM'), 'owner_seat', 'accountant',
      'subject', 'bank_statement_intake',
      'title', 'The Mashreq closing balance for ' || to_char(v_m, 'Mon YYYY')
               || ' is not recorded, so the CEO''s monthly close shows the cash in the bank and the runway as missing',
      'blast', 'agent_facing', 'affected', 1, 'evidence', jsonb_build_object('month', to_char(v_m, 'YYYY-MM'))));
  end if;
  return jsonb_build_object('month', to_char(v_m, 'YYYY-MM'), 'findings', public.fn_accountant_duty_settle('bank_balance', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_bank_line_reasoned(p_line_id bigint, p_kind text, p_by text DEFAULT 'reasoning'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_kind is null or p_kind not in ('bank_charge', 'owner_transfer', 'bank_interest', 'stripe_payout', 'other') then
    raise exception 'fn_accountant_bank_line_reasoned: % is not a bank line kind', p_kind using errcode = '22023';
  end if;
  update public.bank_statement_line set kind = p_kind, kind_by = coalesce(nullif(btrim(p_by), ''), 'reasoning'), kind_at = now()
   where id = p_line_id and kind is null;
  return jsonb_build_object('line_id', p_line_id, 'kind', p_kind, 'recorded', found);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_bank_lines_to_reason(p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_ids bigint[];
begin
  select array_agg(id) into v_ids from (
    select id from public.bank_statement_line where kind is null
     order by kind_tried_at nulls first, id limit greatest(1, least(coalesce(p_limit, 10), 50))) x;
  update public.bank_statement_line set kind_tried_at = now() where id = any(coalesce(v_ids, '{}'));
  return jsonb_build_object(
    'owner', (select owner_name from public.company_registration order by recorded_at desc limit 1),
    'lines', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'value_date', b.value_date, 'amount_aed', b.amount_aed,
                                                           'account', b.account, 'description', public.fn_mask_bank_text(b.description)) order by b.id)
                         from public.bank_statement_line b where b.id = any(coalesce(v_ids, '{}'))), '[]'::jsonb));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_bank_reconcile(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_before int; v_after int; v_grace int; v_due_day int; v_demo_on boolean;
  p public.stripe_payout; l public.bank_statement_line; x record;
  v_items jsonb := '[]'::jsonb; n_matched int := 0; v_settle jsonb;
begin
  select num_value::int into v_before  from public.gl_settings where key = 'bank_match_days_before';
  select num_value::int into v_after   from public.gl_settings where key = 'bank_match_days_after';
  select num_value::int into v_grace   from public.gl_settings where key = 'payout_transit_grace_days';
  select num_value::int into v_due_day from public.gl_settings where key = 'bank_statement_due_day';
  if v_before is null or v_after is null or v_grace is null or v_due_day is null then
    raise exception 'fn_accountant_bank_reconcile: a bank_* or payout_* window is missing from gl_settings';
  end if;
  -- Test-mode payouts are reconciled only while a ZZ DEMO statement exists (a probe or a rehearsal).
  v_demo_on := exists (select 1 from public.bank_statement_intake where account = 'zz_demo');

  -- MATCH: a paid payout to the nearest unmatched bank credit of exactly its amount inside the window,
  -- a line REASONED to be a Stripe payout preferred (bank_statement_line.kind; never a word in its description).
  for p in select * from public.stripe_payout s
            where s.bank_line_id is null and s.status = 'paid' and s.currency = 'aed' and (s.livemode or v_demo_on)
            order by s.arrival_date loop
    select bl.* into l from public.bank_statement_line bl
     where ((p.livemode and bl.account <> 'zz_demo') or (not p.livemode and bl.account = 'zz_demo'))
       and bl.amount_aed = round(p.amount_fils / 100.0, 2)
       and bl.value_date between p.arrival_date - v_before and p.arrival_date + v_after
       and not exists (select 1 from public.stripe_payout q where q.bank_line_id = bl.id)
     order by (bl.kind is not distinct from 'stripe_payout') desc, abs(bl.value_date - p.arrival_date), bl.id
     limit 1;
    if found then
      update public.stripe_payout set bank_line_id = l.id, matched_at = now() where id = p.id;
      n_matched := n_matched + 1;
    end if;
  end loop;

  for p in select * from public.stripe_payout s where (s.livemode or v_demo_on) loop
    -- Stripe says the money did not go.
    if p.status in ('failed', 'canceled') then
      v_items := v_items || jsonb_build_object('item', 'failed:' || p.id, 'owner_seat', 'accountant', 'subject', 'stripe_payout',
        'title', 'Stripe payout ' || p.id || ' of AED ' || round(p.amount_fils / 100.0, 2) || ' ' || p.status
                 || coalesce(' (' || p.failure_code || ')', '') || ': the money did not reach the bank',
        'blast', 'agent_facing', 'affected', 1, 'demo', not p.livemode, 'evidence', to_jsonb(p));
    -- Still travelling well after the date Stripe gave.
    elsif p.status in ('pending', 'in_transit') and p.arrival_date + v_grace < v_as_of then
      v_items := v_items || jsonb_build_object('item', 'transit:' || p.id, 'owner_seat', 'accountant', 'subject', 'stripe_payout',
        'title', 'Stripe payout ' || p.id || ' of AED ' || round(p.amount_fils / 100.0, 2) || ' was due in the bank on '
                 || p.arrival_date || ' and still reads ' || p.status,
        'blast', 'agent_facing', 'affected', 1, 'demo', not p.livemode, 'evidence', to_jsonb(p));
    end if;
    -- The payout does not add up to the balance transactions it carries.
    if p.txn_net_fils is not null and p.txn_net_fils <> p.amount_fils then
      v_items := v_items || jsonb_build_object('item', 'breakdown:' || p.id, 'owner_seat', 'accountant', 'subject', 'stripe_payout',
        'title', 'Stripe payout ' || p.id || ' is AED ' || round(p.amount_fils / 100.0, 2) || ' but its ' || coalesce(p.txn_count, 0)
                 || ' balance transaction(s) net to AED ' || round(p.txn_net_fils / 100.0, 2),
        'blast', 'agent_facing', 'affected', 1, 'demo', not p.livemode, 'evidence', to_jsonb(p));
    end if;
    if p.currency <> 'aed' then
      v_items := v_items || jsonb_build_object('item', 'currency:' || p.id, 'owner_seat', 'accountant', 'subject', 'stripe_payout',
        'title', 'Stripe payout ' || p.id || ' is in ' || upper(p.currency) || ', and the Mashreq account is reconciled in AED',
        'blast', 'agent_facing', 'affected', 1, 'demo', not p.livemode, 'evidence', to_jsonb(p));
    end if;
    -- Paid, unmatched, and a statement already runs past the end of its window: missing from the bank.
    if p.status = 'paid' and p.bank_line_id is null and p.currency = 'aed'
       and exists (select 1 from public.bank_statement_line bl
                    where ((p.livemode and bl.account <> 'zz_demo') or (not p.livemode and bl.account = 'zz_demo'))
                      and bl.value_date >= p.arrival_date + v_after) then
      v_items := v_items || jsonb_build_object('item', 'missing:' || p.id, 'owner_seat', 'accountant', 'subject', 'stripe_payout',
        'title', 'Stripe paid out AED ' || round(p.amount_fils / 100.0, 2) || ' (' || p.id || ') for ' || p.arrival_date
                 || ' and the bank statement shows no credit of that amount between ' || (p.arrival_date - v_before)
                 || ' and ' || (p.arrival_date + v_after),
        'blast', 'agent_facing', 'affected', 1, 'demo', not p.livemode,
        'evidence', to_jsonb(p) || jsonb_build_object('nearest_stripe_credits', (
          select coalesce(jsonb_agg(jsonb_build_object('line', bl.id, 'value_date', bl.value_date, 'amount_aed', bl.amount_aed,
                                                       'description', public.fn_mask_bank_text(bl.description)) order by abs(bl.value_date - p.arrival_date)), '[]'::jsonb)
            from (select * from public.bank_statement_line b2
                   where ((p.livemode and b2.account <> 'zz_demo') or (not p.livemode and b2.account = 'zz_demo'))
                     and b2.amount_aed > 0 and b2.value_date between p.arrival_date - v_before and p.arrival_date + v_after
                   limit 5) bl)));
    end if;
  end loop;

  -- A month with live payouts whose statement has not arrived by the due day of the next month.
  for x in select date_trunc('month', s.arrival_date)::date mo, count(*) n, sum(s.amount_fils) fils
             from public.stripe_payout s where s.livemode and s.status = 'paid'
            group by 1 loop
    if v_as_of > (x.mo + interval '1 month')::date + (v_due_day - 1)
       and not exists (select 1 from public.bank_statement_line bl
                        where bl.account <> 'zz_demo' and bl.value_date >= (x.mo + interval '1 month' - interval '1 day')::date) then
      v_items := v_items || jsonb_build_object('item', 'statement:' || to_char(x.mo, 'YYYY-MM'), 'owner_seat', 'accountant',
        'subject', 'bank_statement',
        'title', 'The Mashreq statement for ' || to_char(x.mo, 'Mon YYYY') || ' has not reached the accountant, so '
                 || x.n || ' Stripe payout(s) totalling AED ' || round(x.fils / 100.0, 2) || ' cannot be confirmed in the bank',
        'blast', 'agent_facing', 'affected', 0,
        'evidence', jsonb_build_object('month', x.mo, 'payouts', x.n, 'amount_aed', round(x.fils / 100.0, 2),
                                       'remedy', 'forward the statement (PDF or CSV export) to expenses@mail.quotesdone.com'));
    end if;
  end loop;

  -- A statement that arrived and could not be read.
  for x in select * from public.bank_statement_intake i where i.state = 'unreadable' and (i.account <> 'zz_demo' or v_demo_on) loop
    v_items := v_items || jsonb_build_object('item', 'unreadable:' || x.source_ref, 'owner_seat', 'accountant', 'subject', 'bank_statement',
      'title', 'A ' || x.account || ' statement' || coalesce(' for ' || to_char(x.statement_month, 'Mon YYYY'), '')
               || ' arrived and no line could be read from it',
      'blast', 'agent_facing', 'affected', 0, 'demo', x.account = 'zz_demo',
      'evidence', jsonb_build_object('source_ref', x.source_ref, 'doc_path', x.doc_path, 'note', x.note,
                                     'remedy', 'forward the CSV export of the same statement, or ingest its lines through the accountant runtime''s bank_statement action'));
  end loop;

  -- Money from Stripe in the bank that no payout explains.
  for x in select bl.* from public.bank_statement_line bl
            where bl.amount_aed > 0 and bl.kind = 'stripe_payout' and bl.value_date + v_after < v_as_of
              and (bl.account <> 'zz_demo' or v_demo_on)
              and not exists (select 1 from public.stripe_payout s where s.bank_line_id = bl.id) loop
    v_items := v_items || jsonb_build_object('item', 'unexplained:' || x.id, 'owner_seat', 'accountant', 'subject', 'bank_statement',
      'title', 'The bank shows a Stripe credit of AED ' || x.amount_aed || ' on ' || x.value_date || ' that no recorded payout explains',
      'blast', 'agent_facing', 'affected', 1, 'demo', x.account = 'zz_demo',
      'evidence', to_jsonb(x) || jsonb_build_object('description', public.fn_mask_bank_text(x.description),
                                                    'reference', public.fn_mask_bank_text(x.reference)));
  end loop;

  v_settle := public.fn_accountant_duty_settle('bank', v_items);
  return jsonb_build_object('as_of', v_as_of, 'matched_now', n_matched, 'findings', v_settle,
    'payouts', (select count(*) from public.stripe_payout where livemode),
    'payouts_matched', (select count(*) from public.stripe_payout where livemode and bank_line_id is not null),
    'statements', (select count(*) from public.bank_statement_intake where account <> 'zz_demo'),
    'basis', 'Stripe payouts (read from GET /v1/payouts) against Mashreq statement lines, amount exact, date within the gl_settings window. Nothing was posted to the ledger.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_bank_statement_ingest(p_account text, p_source_ref text, p_statement_month date, p_lines jsonb, p_doc_path text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare x jsonb; n_new int := 0; n int; v_month date; v_k text; v_seen jsonb := '{}'::jsonb;
begin
  if coalesce(btrim(p_source_ref), '') = '' or coalesce(btrim(p_account), '') = '' then
    raise exception 'fn_accountant_bank_statement_ingest: an account and a source reference are required';
  end if;
  if jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception 'fn_accountant_bank_statement_ingest: lines must be an array (empty for an unreadable statement)';
  end if;
  n := jsonb_array_length(p_lines);
  v_month := coalesce(p_statement_month,
                      (select date_trunc('month', max((e->>'value_date')::date))::date from jsonb_array_elements(p_lines) e));
  insert into public.bank_statement_intake (source_ref, account, statement_month, state, lines, doc_path, note)
  values (p_source_ref, p_account, v_month, case when n > 0 then 'parsed' else 'unreadable' end, n, p_doc_path, p_note)
  on conflict (source_ref) do update
     set state = case when excluded.lines > 0 then 'parsed' else bank_statement_intake.state end,
         lines = greatest(bank_statement_intake.lines, excluded.lines),
         statement_month = coalesce(excluded.statement_month, bank_statement_intake.statement_month),
         doc_path = coalesce(excluded.doc_path, bank_statement_intake.doc_path),
         note = coalesce(excluded.note, bank_statement_intake.note);
  -- TWO IDENTICAL LINES ARE TWO LINES (review of #645): two AED 200 charges on one day are both real.
  -- Each line is keyed on its content AND its occurrence number inside the statement, so a re-forwarded
  -- statement adds nothing while a genuine repeat inside one statement is kept.
  for x in select e from jsonb_array_elements(p_lines) e loop
    if (x->>'value_date') is null or (x->>'amount_aed') is null or coalesce(btrim(x->>'description'), '') = '' then
      raise exception 'fn_accountant_bank_statement_ingest: a line needs value_date, description and amount_aed (%)', left(x::text, 200);
    end if;
    v_k := p_account || '|' || (x->>'value_date') || '|' || ((x->>'amount_aed')::numeric)::text || '|'
           || lower(btrim(x->>'description')) || '|' || coalesce(x->>'reference', '');
    v_seen := v_seen || jsonb_build_object(v_k, coalesce((v_seen->>v_k)::int, 0) + 1);
    insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, reference, line_hash)
    values (p_account, p_source_ref, (x->>'value_date')::date, x->>'description', (x->>'amount_aed')::numeric, x->>'reference',
            md5(v_k || '|#' || (v_seen->>v_k)))
    on conflict (line_hash) do nothing;
    if found then n_new := n_new + 1; end if;
  end loop;
  return jsonb_build_object('source_ref', p_source_ref, 'statement_month', v_month, 'lines', n, 'new_lines', n_new,
                            'state', case when n > 0 then 'parsed' else 'unreadable' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_book_bank_charges()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_hold boolean := coalesce((select num_value from public.gl_settings where key = 'bank_booking_on_hold'), 1) <> 0;
  l record; v_lines jsonb; v_memo text; n_posted int := 0; n_draft int := 0; n_failed int := 0; v_items jsonb := '[]'::jsonb;
begin
  for l in select * from public.bank_statement_line b
            where b.amount_aed < 0 and b.kind = 'bank_charge'
              and not exists (select 1 from public.gl_journal g where g.source = 'bank_charge' and g.source_ref = b.id::text)
            order by b.value_date, b.id loop
    v_lines := jsonb_build_array(jsonb_build_object('account', '6300', 'debit', abs(l.amount_aed)),
                                 jsonb_build_object('account', '1000', 'credit', abs(l.amount_aed)));
    v_memo := case when l.account = 'zz_demo' then 'ZZ DEMO ' else '' end || 'Bank charge (' || l.account || ', ' || l.value_date || '): ' || left(public.fn_mask_bank_text(l.description), 120);
    begin
      if v_hold or l.account = 'zz_demo' then
        perform public.fn_accountant_draft_entry(l.value_date, v_memo, 'bank_charge', l.id::text, v_lines);
        n_draft := n_draft + 1;
      else
        perform public.fn_gl_entry(l.value_date, v_memo, 'bank_charge', l.id::text, v_lines, 'accountant');
        n_posted := n_posted + 1;
      end if;
    exception when others then
      n_failed := n_failed + 1;
      v_items := v_items || jsonb_build_object('item', 'line:' || l.id, 'owner_seat', 'accountant', 'subject', 'bank_statement_line',
        'title', 'The bank charge of AED ' || abs(l.amount_aed) || ' on ' || l.value_date || ' (statement line ' || l.id || ') could not be booked: ' || left(sqlerrm, 200),
        'blast', 'agent_facing', 'affected', 1, 'demo', l.account = 'zz_demo',
        'evidence', jsonb_build_object('line_id', l.id, 'source_ref', l.source_ref, 'error', left(sqlerrm, 600)));
    end;
  end loop;
  return jsonb_build_object('posted', n_posted, 'drafted', n_draft, 'failed', n_failed, 'hold', v_hold,
    'drafts_waiting', (select count(*) from public.gl_journal where source = 'bank_charge' and status = 'draft'),
    'drafts_waiting_aed', (select coalesce(sum(jl.debit), 0) from public.gl_journal g join public.gl_journal_lines jl on jl.journal_id = g.id
                            where g.source = 'bank_charge' and g.status = 'draft'),
    'findings', public.fn_accountant_duty_settle('bank_charges', v_items),
    'basis', case when v_hold then 'gl_settings.bank_booking_on_hold = 1 (the founder''s 9 Sep 2026 instruction): bank charges are prepared as drafts and reported, not posted.'
                  else 'bank_booking_on_hold = 0: bank charges posted to 6300 against 1000.' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_book_bank_credits()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_hold boolean := coalesce((select num_value from public.gl_settings where key = 'bank_booking_on_hold'), 1) <> 0;
  v_after int := coalesce((select num_value::int from public.gl_settings where key = 'bank_match_days_after'), 5);
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  l record; v_lines jsonb; v_memo text; v_src text; v_booked boolean;
  n_posted int := 0; n_draft int := 0; n_raced int := 0; n_failed int := 0; v_items jsonb := '[]'::jsonb;
begin
  -- WHAT A CREDIT IS comes from bank_statement_line.kind, REASONED by the accountant runtime (reasoned_books.ts
  -- bankLineKind) or ruled by the founder (bank_line_owner_ruling). No description is read here.
  for l in select b.*, r.ruling, r.founder_instruction_id
             from public.bank_statement_line b left join public.bank_line_owner_ruling r on r.line_id = b.id
            where b.amount_aed > 0
              and not exists (select 1 from public.stripe_payout p where p.bank_line_id = b.id)
            order by b.value_date, b.id loop
    v_booked := exists (select 1 from public.gl_journal g where g.source in ('owner_capital', 'bank_interest')
                          and g.source_ref = l.id::text and g.status in ('draft', 'posted'));
    if l.ruling = 'loan' then
      v_items := v_items || jsonb_build_object('item', 'loan:' || l.id, 'owner_seat', 'accountant', 'subject', 'bank_statement_line',
        'title', 'A credit of AED ' || l.amount_aed || ' on ' || l.value_date || ' was ruled a loan from the founder, and the chart has no owner-loan account'
                 || case when v_booked then '; the entry already made for it must be reversed' else '' end,
        'blast', 'agent_facing', 'affected', 1, 'demo', l.account = 'zz_demo',
        'evidence', jsonb_build_object('line_id', l.id, 'source_ref', l.source_ref, 'founder_instruction_id', l.founder_instruction_id));
      continue;
    end if;
    continue when v_booked;
    v_src := null;
    if l.ruling = 'capital' or l.kind = 'owner_transfer' then
      v_src := 'owner_capital';
      v_lines := jsonb_build_array(jsonb_build_object('account', '1000', 'debit', l.amount_aed),
                                   jsonb_build_object('account', '3000', 'credit', l.amount_aed));
      v_memo := 'Owner capital contribution (' || l.account || ', ' || l.value_date
                || '), a transfer from the licence holder''s own account: capital unless he says loan (founder_instruction 357): ' || left(public.fn_mask_bank_text(l.description), 120);
    elsif l.kind = 'bank_interest' then
      v_src := 'bank_interest';
      v_lines := jsonb_build_array(jsonb_build_object('account', '1000', 'debit', l.amount_aed),
                                   jsonb_build_object('account', '7000', 'credit', l.amount_aed));
      v_memo := 'Bank interest credited (' || l.account || ', ' || l.value_date || '): ' || left(public.fn_mask_bank_text(l.description), 120);
    elsif l.kind is null and l.value_date + v_after < v_today then
      -- Not yet reasoned (the model hold): not booked on a guess, and said out loud rather than left silent.
      v_items := v_items || jsonb_build_object('item', 'unreasoned:' || l.id, 'owner_seat', 'accountant', 'subject', 'bank_statement_line',
        'title', 'A credit of AED ' || l.amount_aed || ' on ' || l.value_date || ' has not been reasoned yet (the model is held), so it is not booked',
        'blast', 'agent_facing', 'affected', 1, 'demo', l.account = 'zz_demo',
        'evidence', jsonb_build_object('line_id', l.id, 'source_ref', l.source_ref,
                                       'remedy', 'it is reasoned the moment the hold lifts (reasoning_held_question, surface accountant.bank_line)'));
    elsif l.value_date + v_after < v_today then
      v_items := v_items || jsonb_build_object('item', 'unrecognised:' || l.id, 'owner_seat', 'accountant', 'subject', 'bank_statement_line',
        'title', 'A credit of AED ' || l.amount_aed || ' on ' || l.value_date || ' is neither a Stripe payout, a transfer from the licence holder''s own account nor the bank''s interest, so it is not booked',
        'blast', 'agent_facing', 'affected', 1, 'demo', l.account = 'zz_demo',
        'evidence', jsonb_build_object('line_id', l.id, 'source_ref', l.source_ref, 'description', left(public.fn_mask_bank_text(l.description), 200),
                                       'remedy', 'the founder names what it is; an owner transfer is recorded in bank_line_owner_ruling'));
    end if;
    continue when v_src is null;
    if l.account = 'zz_demo' then v_memo := 'ZZ DEMO ' || v_memo; end if;
    begin
      if v_hold or l.account = 'zz_demo' then
        perform public.fn_accountant_draft_entry(l.value_date, v_memo, v_src, l.id::text, v_lines);
        n_draft := n_draft + 1;
      else
        perform public.fn_gl_entry(l.value_date, v_memo, v_src, l.id::text, v_lines, 'accountant');
        n_posted := n_posted + 1;
      end if;
    exception
      when unique_violation then
        n_raced := n_raced + 1;        -- a concurrent run booked this line first: gl_journal_one_live_entry_per_bank_or_fee_line
      when others then
        n_failed := n_failed + 1;
        v_items := v_items || jsonb_build_object('item', 'line:' || l.id, 'owner_seat', 'accountant', 'subject', 'bank_statement_line',
          'title', 'The credit of AED ' || l.amount_aed || ' on ' || l.value_date || ' (statement line ' || l.id || ') could not be booked: ' || left(sqlerrm, 200),
          'blast', 'agent_facing', 'affected', 1, 'demo', l.account = 'zz_demo',
          'evidence', jsonb_build_object('line_id', l.id, 'source_ref', l.source_ref, 'error', left(sqlerrm, 600)));
    end;
  end loop;
  return jsonb_build_object('posted', n_posted, 'drafted', n_draft, 'booked_by_a_concurrent_run', n_raced, 'failed', n_failed, 'hold', v_hold,
    'findings', public.fn_accountant_duty_settle('bank_credits', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_book_stripe_fees(p_livemode boolean, p_bts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare x jsonb; v_amt numeric; v_date date; v_memo text; n_posted int := 0; n_draft int := 0; n_seen int := 0; v_lines jsonb;
        v_items jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_bts) is distinct from 'array' then
    raise exception 'fn_accountant_book_stripe_fees(livemode, balance_transactions[]): an array is required';
  end if;
  for x in select e from jsonb_array_elements(p_bts) e loop
    n_seen := n_seen + 1;
    continue when coalesce(x->>'id', '') !~ '^txn_' or x->>'type' not in ('stripe_fee', 'tax');
    -- A FEE IN ANOTHER CURRENCY IS A FINDING, NOT A SILENT SKIP (review of #645): the ledger is AED and
    -- gl_settings carries no rate for it, so it cannot be booked without a guess, and must not vanish.
    if lower(coalesce(x->>'currency', '')) <> 'aed' then
      v_items := v_items || jsonb_build_object('item', 'currency:' || (x->>'id'), 'owner_seat', 'accountant', 'subject', 'stripe_fees',
        'title', 'Stripe charged a ' || (x->>'type') || ' of ' || round(abs((x->>'amount')::numeric) / 100.0, 2) || ' '
                 || upper(coalesce(x->>'currency', '?')) || ' (' || (x->>'id') || ') and the AED ledger has no rate to book it',
        'blast', 'agent_facing', 'affected', 1, 'demo', not p_livemode, 'evidence', x);
      continue;
    end if;
    continue when exists (select 1 from public.gl_journal g where g.source in ('stripe_fee_bt', 'stripe_fee_bt_test') and g.source_ref = x->>'id');
    v_amt := abs((x->>'amount')::numeric) / 100.0;
    continue when v_amt = 0;
    v_date := (to_timestamp((x->>'created')::bigint) at time zone 'Asia/Dubai')::date;
    v_memo := case x->>'type' when 'tax' then 'VAT Stripe charged on its own fees (not recoverable: QuotesDone is not VAT-registered)'
                               else 'Stripe fee billed separately: ' || coalesce(x->>'description', 'stripe_fee') end || ' [' || (x->>'id') || ']';
    v_lines := jsonb_build_array(jsonb_build_object('account', '6100', 'debit', v_amt),
                                 jsonb_build_object('account', '1050', 'credit', v_amt));
    if p_livemode then
      perform public.fn_gl_entry(v_date, v_memo, 'stripe_fee_bt', x->>'id', v_lines, 'accountant');
      n_posted := n_posted + 1;
    else
      perform public.fn_accountant_draft_entry(v_date, 'TEST MODE, never posted: ' || v_memo, 'stripe_fee_bt_test', x->>'id', v_lines);
      n_draft := n_draft + 1;
    end if;
  end loop;
  return jsonb_build_object('seen', n_seen, 'posted', n_posted, 'drafted', n_draft, 'livemode', p_livemode,
    'findings', public.fn_accountant_duty_settle('stripe_fees_' || case when p_livemode then 'live' else 'test' end, v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_books_duty(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_after int := (select num_value::int from public.gl_settings where key = 'books_stale_after_days');
  v_last date; v_last_at timestamptz; v_mail timestamptz; n_arrived int; n_unbooked int; n_unposted int;
  v_cause text; v_items jsonb := '[]'::jsonb;
begin
  if v_after is null then raise exception 'fn_accountant_books_duty: gl_settings.books_stale_after_days is missing'; end if;
  select max(entry_date), max(posted_at) into v_last, v_last_at from public.gl_journal
   where status = 'posted' and memo !~* 'zz[ _-]?demo';
  select max(created_at) into v_mail from public.inbound_messages where to_email ilike 'expenses@%';
  -- What reached the mailbox since the last posting, and what of it has no entry and no statement behind it.
  select count(*), count(*) filter (where not exists (select 1 from public.expense_entries e where e.source_msg_id = 'resend:' || m.provider_email_id)
                                      and not exists (select 1 from public.bank_statement_intake b where b.source_ref = 'resend:' || m.provider_email_id))
    into n_arrived, n_unbooked
    from public.inbound_messages m
   where m.to_email ilike 'expenses@%' and m.created_at > coalesce(v_last_at, '-infinity') and m.created_at < now() - interval '2 hours';
  select count(*) into n_unposted from public.expense_entries e
   where not exists (select 1 from public.gl_journal g where g.source = 'expense' and g.source_ref = e.id::text)
     and not ((coalesce(e.vendor, '') || ' ' || coalesce(e.note, '')) ~* 'zz[ _-]?demo');

  if v_last is null or v_as_of - v_last > v_after then
    v_cause := case
      when n_unposted > 0 then n_unposted || ' booked expense(s) have no journal: posting is failing'
      when n_unbooked > 0 then n_unbooked || ' message(s) reached the expenses mailbox and were neither booked nor held as a statement'
      else 'nothing has reached the expenses mailbox since ' || coalesce(to_char(v_mail at time zone 'Asia/Dubai', 'DD Mon YYYY'), 'ever')
           || ', so there was nothing to post; the vendor-side gaps are in the expenses duty' end;
    v_items := jsonb_build_array(jsonb_build_object('item', 'books_stale', 'owner_seat', 'accountant', 'subject', 'gl_journal',
      'title', 'The books are ' || coalesce((v_as_of - v_last)::text, 'never') || ' day(s) stale (last posted journal '
               || coalesce(v_last::text, 'none') || '): ' || v_cause,
      'blast', 'internal', 'affected', 1,
      'evidence', jsonb_build_object('last_posted_journal', v_last, 'last_posted_at', v_last_at, 'stale_after_days', v_after,
        'last_expenses_mail', v_mail, 'mail_since_last_posting', n_arrived, 'mail_not_booked', n_unbooked,
        'entries_not_posted', n_unposted,
        'remedy', case when n_unposted + n_unbooked > 0
                       then 'run the accountant expense_sweep for the named message, then fn_gl_sync_business; read the stage finding if it raises'
                       else 'forward the month''s receipts to expenses@mail.quotesdone.com; nothing is broken on this side' end)));
  end if;
  return jsonb_build_object('as_of', v_as_of, 'last_posted_journal', v_last, 'mail_not_booked', n_unbooked,
    'entries_not_posted', n_unposted, 'findings', public.fn_accountant_duty_settle('books', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_budget_variance()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_m date; v_n int; v_big jsonb; v_rep jsonb;
begin
  select month into v_m from public.accountant_month_close order by month desc limit 1;
  if v_m is null then return jsonb_build_object('explained', false, 'reason', 'no month is closed yet'); end if;
  if exists (select 1 from public.accountant_budget_variance where month = v_m) then
    return jsonb_build_object('month', v_m, 'already_explained', true);
  end if;
  with b as (select l.account_code, sum(l.amount) amt from public.budget_lines l join public.budgets g on g.id = l.budget_id and g.status = 'active'
              where l.period_month = v_m group by 1),
       a as (select jl.account_code, sum(jl.debit - jl.credit) amt
               from public.gl_journal j join public.gl_journal_lines jl on jl.journal_id = j.id
               join public.gl_accounts ac on ac.code = jl.account_code and ac.type = 'expense'
              where j.status = 'posted' and j.entry_date >= v_m and j.entry_date < (v_m + interval '1 month')::date group by 1),
       k as (select account_code from b union select account_code from a),
       d as (select k.account_code, jsonb_agg(jsonb_build_object('entry', j.entry_no, 'date', j.entry_date, 'memo', left(j.memo, 120), 'aed', jl.debit - jl.credit)
                                              order by jl.debit - jl.credit desc) filter (where j.id is not null) drv
               from k left join public.gl_journal_lines jl on jl.account_code = k.account_code
               left join public.gl_journal j on j.id = jl.journal_id and j.status = 'posted' and j.entry_date >= v_m and j.entry_date < (v_m + interval '1 month')::date
              group by k.account_code)
  insert into public.accountant_budget_variance (month, account_code, budget_aed, actual_aed, variance_aed, variance_pct, explanation, drivers)
  select v_m, k.account_code, coalesce(b.amt, 0), coalesce(a.amt, 0), coalesce(a.amt, 0) - coalesce(b.amt, 0),
         round(100 * (coalesce(a.amt, 0) - coalesce(b.amt, 0)) / nullif(b.amt, 0), 1),
         case when b.amt is null then 'Spent with no budget line: ' || coalesce((select string_agg(x->>'memo', '; ') from jsonb_array_elements(coalesce(d.drv, '[]')) with ordinality t(x, o) where o <= 3), 'no entries')
              when coalesce(a.amt, 0) = 0 then 'Budgeted, nothing posted in the month: the cost did not fall due or its receipt has not been booked.'
              when abs(coalesce(a.amt, 0) - b.amt) <= greatest(100, abs(b.amt) * 0.10) then 'Within 10% (or AED 100) of budget.'
              else (case when a.amt > b.amt then 'Over' else 'Under' end) || ' budget by AED ' || abs(round(a.amt - b.amt, 2)) || '; largest entries: '
                   || coalesce((select string_agg((x->>'memo') || ' AED ' || (x->>'aed'), '; ') from jsonb_array_elements(coalesce(d.drv, '[]')) with ordinality t(x, o) where o <= 3), 'none') end,
         coalesce((select jsonb_agg(x) from jsonb_array_elements(coalesce(d.drv, '[]')) with ordinality t(x, o) where o <= 5), '[]')
    from k left join b using (account_code) left join a using (account_code) left join d using (account_code);
  get diagnostics v_n = row_count;
  select coalesce(jsonb_agg(to_jsonb(v) - 'recorded_at' - 'drivers' order by abs(v.variance_aed) desc), '[]') into v_big
    from public.accountant_budget_variance v
   where v.month = v_m and abs(v.variance_aed) > greatest(100, abs(v.budget_aed) * 0.10);
  if jsonb_array_length(v_big) > 0 then
    v_rep := public.fn_support_report_to_ceo('accountant.budget_variance:' || to_char(v_m, 'YYYY-MM'), 'routine',
      format('Budget variance %s: %s line(s) off budget by more than 10%%, each explained', to_char(v_m, 'Mon YYYY'), jsonb_array_length(v_big)),
      jsonb_build_object('month', v_m, 'lines', v_big), '[]'::jsonb,
      'Read the explained lines; re-budget any line that is structurally wrong.', null, null, interval '3 days', 'accountant');
  end if;
  return jsonb_build_object('month', v_m, 'lines_explained', v_n, 'lines_over_10pct', jsonb_array_length(v_big), 'reported', v_rep is not null);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_budgets_renewal(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions; v_item text; b jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' is distinct from 'renewal.due' then
    raise exception 'fn_accountant_budgets_renewal: % is not a renewal.due handoff', p_id;
  end if;
  v_item := nullif(btrim(a.detail->>'item'), '');
  if v_item is null then raise exception 'renewal.due handoff % names no item: the payload carries {item: it_expiry.item}', p_id; end if;
  b := public.fn_accountant_renewal_budget_line(v_item);
  update public.accountant_renewal_budget set handoff_id = p_id where item = v_item;
  return jsonb_build_object('waiting', 'it_engineer re-verification of the new expiry of ' || v_item,
    'seat', 'accountant', 'budget', b,
    'reply', case when b->>'budget_aed' is null
                  then 'accountant: ' || v_item || ' is not budgeted. ' || (b->>'basis') || '. It is an open accountant finding until a payment is booked.'
                  else 'accountant: AED ' || (b->>'budget_aed') || ' is set aside for ' || v_item || ', to pay by ' || (b->>'pay_by')
                       || ' (' || (b->>'basis') || ').' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_cash_13_weeks()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_cp jsonb := public.fn_accountant_cash_position(current_date, null);
  v_cash numeric := (v_cp #>> '{cash_in_bank,aed}')::numeric;
  v_spend numeric := (v_cp #>> '{runway,monthly_spend_aed}')::numeric;
  v_fund numeric; w int; v_s date; v_in numeric; v_bud numeric; v_ar numeric; v_out jsonb := '[]'::jsonb;
  v_missing text[] := '{}';
begin
  select num_value into v_fund from public.gl_settings where key = 'founder_committed_funding_aed_per_month';
  if v_cash is null then v_missing := v_missing || text 'no bank closing balance is recorded, so there is no opening cash'; end if;
  if v_fund is null then v_missing := v_missing || text 'no founder funding commitment is recorded (gl_settings founder_committed_funding_aed_per_month); the view counts none'; end if;
  for w in 0..12 loop
    v_s := current_date + w * 7;
    select coalesce(sum(l.amount), 0) * 12 / 52.0 into v_bud from public.budget_lines l join public.budgets b on b.id = l.budget_id
      join public.gl_accounts a on a.code = l.account_code and a.type = 'revenue'
     where b.status = 'active' and l.period_month = date_trunc('month', v_s)::date;
    select coalesce(sum(amount_due), 0) into v_ar from public.supplier_dues
     where public.fn_supplier_due_is_owed(status, paid_at) and coalesce(due_date_30, reveal_date + 30) >= v_s and coalesce(due_date_30, reveal_date + 30) < v_s + 7;
    v_in := v_bud + v_ar + coalesce(v_fund, 0) * 12 / 52.0;
    v_cash := v_cash + v_in - coalesce(v_spend, 0) * 12 / 52.0;
    v_out := v_out || jsonb_build_object('week_from', v_s, 'inflow_budget_revenue_aed', round(v_bud, 2), 'inflow_receivables_aed', round(v_ar, 2),
               'inflow_founder_funding_aed', round(coalesce(v_fund, 0) * 12 / 52.0, 2),
               'outflow_spend_aed', round(coalesce(v_spend, 0) * 12 / 52.0, 2), 'closing_cash_aed', round(v_cash, 2));
  end loop;
  return jsonb_build_object('opening_cash_aed', v_cp #> '{cash_in_bank,aed}', 'weeks', v_out, 'missing', to_jsonb(v_missing),
    'basis', 'Opening = the bank statement balance. Outflow = the average booked monthly spend (fn_accountant_cash_position) x 12/52. Inflow = the active budget''s revenue lines, supplier dues falling due in the week, and the founder''s recorded monthly funding commitment.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_cash_forecast(p_as_of date DEFAULT NULL::date, p_account text DEFAULT 'mashreq'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_end date; v_bal numeric; v_bal_on date; v_bal_ref text; v_after numeric; v_open numeric;
  v_items jsonb; v_weeks jsonb; v_low jsonb; v_next jsonb; v_fee numeric;
begin
  v_end := v_as_of + 91;
  select closing_balance_aed, balance_on, source_ref into v_bal, v_bal_on, v_bal_ref
    from public.bank_statement_intake
   where account = p_account and closing_balance_aed is not null and balance_on <= v_as_of
   order by balance_on desc, received_at desc limit 1;
  -- only lines from OTHER statements: the balance's own statement already includes every one of its lines
  select coalesce(sum(amount_aed), 0) into v_after
    from public.bank_statement_line
   where account = p_account and source_ref is distinct from v_bal_ref and value_date > v_bal_on and value_date <= v_as_of;
  v_open := v_bal + v_after;
  v_fee := (select (value #>> '{}')::numeric from public.decision_policy where key = 'accountant_bank_fee_monthly_aed');

  with bank_rec as (
    select k, (array_agg(amount_aed order by value_date desc))[1] amt,
           extract(day from max(value_date))::int dom, max(description) label
      from (select l.*, btrim(regexp_replace(lower(description), '[0-9]+', '', 'g')) k
              from public.bank_statement_line l
             where account = p_account and amount_aed < 0 and value_date > v_as_of - 120 and value_date <= v_as_of) z
     where not exists (select 1 from public.accountant_owner_ruled_subscription s
                        where s.bank_pattern is not null and z.description ~* s.bank_pattern)
     group by k having count(distinct date_trunc('month', value_date)) >= 2),
  items as (
    select 'bank_statement' src, label, 'account' paid_from, amt amount_aed, 'monthly' cadence, dom, null::date anchor from bank_rec
    union all
    select 'bank_fee_policy', 'Mashreq monthly fee (policy, no fee line in the statements)', 'account', -v_fee, 'monthly',
           extract(day from (date_trunc('month', v_as_of) + interval '1 month - 1 day'))::int, null
     where v_fee is not null and not exists (select 1 from bank_rec where k ~ 'fee|charge')
    union all
    select 'subscription_register', vendor, 'account', -bank_value_aed, cadence, usual_day, expected_from
      from public.accountant_owner_ruled_subscription where vendor !~* 'zz[_ -]?demo'),
  occ as (
    select i.*, make_date(extract(year from m)::int, extract(month from m)::int,
                          least(i.dom, extract(day from (m + interval '1 month - 1 day'))::int)) on_date
      from items i cross join generate_series(date_trunc('month', v_as_of), date_trunc('month', v_end), interval '1 month') m
     where i.cadence = 'monthly'
        or (i.cadence in ('annual', 'yearly') and extract(month from m) = extract(month from i.anchor))),
  flows as (
    select on_date, src, label, paid_from, amount_aed, false unbudgeted from occ
     where on_date > v_as_of and on_date <= v_end and (anchor is null or on_date >= anchor)
    union all
    select coalesce(pay_by, expires_on), 'renewal', item, 'account', -coalesce(budget_aed, 0), budget_aed is null
      from public.accountant_renewal_budget
     where item !~* 'zz[_ -]?demo' and coalesce(pay_by, expires_on) > v_as_of and coalesce(pay_by, expires_on) <= v_end
    union all
    select arrival_date, 'stripe_payout', id, 'account', amount_fils / 100.0, false
      from public.stripe_payout where livemode and status in ('pending', 'in_transit') and arrival_date > v_as_of and arrival_date <= v_end
    union all
    select d.due_date, 'supplier_charge_due', 'supplier due #' || d.id, 'account', coalesce(d.total_claim, d.amount_due), false
      from public.supplier_dues d left join public.leads l on l.id = d.supplier_id
     where public.fn_supplier_due_is_owed(d.status, d.paid_at) and not coalesce(l.is_demo, false)
       and d.due_date > v_as_of and d.due_date <= v_end)
  select coalesce(jsonb_agg(jsonb_build_object('on', on_date, 'source', src, 'item', label, 'paid_from', paid_from,
                                               'amount_aed', round(amount_aed, 2), 'unbudgeted', unbudgeted)
                            order by on_date, src, label), '[]'::jsonb)
    into v_items from flows;

  select jsonb_agg(w order by (w->>'week')::int) into v_weeks from (
    select jsonb_build_object('week', n + 1, 'from', v_as_of + 1 + 7 * n, 'to', v_as_of + 7 * (n + 1),
             'in_aed', in_aed, 'out_aed', out_aed,
             'closing_aed', case when v_open is null then null
                                 else round(v_open + sum(in_aed - out_aed) over (order by n), 2) end) w
      from (select n,
                   coalesce(sum((e->>'amount_aed')::numeric) filter (where (e->>'amount_aed')::numeric > 0), 0) in_aed,
                   coalesce(-sum((e->>'amount_aed')::numeric) filter (where (e->>'amount_aed')::numeric < 0), 0) out_aed
              from generate_series(0, 12) n
              left join jsonb_array_elements(v_items) e
                on true
               and (e->>'on')::date between v_as_of + 1 + 7 * n and v_as_of + 7 * (n + 1)
             group by n) z) s;

  select jsonb_build_object('first_week', (w->>'week')::int, 'week_from', w->>'from', 'closing_aed', (w->>'closing_aed')::numeric,
           'lowest_aed', (select min((x->>'closing_aed')::numeric) from jsonb_array_elements(v_weeks) x),
           'top_up_to_stay_above_zero_aed', -(select min((x->>'closing_aed')::numeric) from jsonb_array_elements(v_weeks) x))
    into v_low
    from jsonb_array_elements(v_weeks) w where (w->>'closing_aed')::numeric < 0 order by (w->>'week')::int limit 1;

  select jsonb_build_object('item', item, 'pay_by', coalesce(pay_by, expires_on), 'budget_aed', budget_aed) into v_next
    from public.accountant_renewal_budget
   where item !~* 'zz[_ -]?demo' and coalesce(pay_by, expires_on) > v_end order by coalesce(pay_by, expires_on) limit 1;

  return jsonb_build_object(
    'as_of', v_as_of, 'to', v_end, 'account', p_account,
    'nature', 'information, never an alarm: there is no runway target and the founder funds the company (instruction 1013)',
    'opening', case when v_bal is null
      then jsonb_build_object('aed', null, 'missing', 'no closing balance recorded for ' || p_account || ' on or before ' || v_as_of)
      else jsonb_build_object('aed', v_open, 'statement_balance_aed', v_bal, 'balance_on', v_bal_on, 'statement', v_bal_ref, 'later_statement_lines_aed', v_after) end,
    'weeks', v_weeks,
    'below_zero', coalesce(v_low, jsonb_build_object('first_week', null, 'note',
                    case when v_open is null then 'not measurable without an opening balance' else 'the balance stays at or above zero for the 13 weeks' end)),
    'flows', v_items,
    'next_known_beyond_window', v_next,
    'basis', 'Opening = last Mashreq statement closing balance plus the lines of later statements only. Outflows: recurring statement debits (2+ months in 120 days), the bank fee policy only if no fee line recurs, the subscription register (all from the account, founder ruling 1011), renewals at budget. Inflows: Stripe payouts in transit and supplier charges due. Owner transfers are capital and not projected.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_cash_forecast_week()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_week date := date_trunc('week', now() at time zone 'Asia/Dubai')::date; f jsonb; v_low numeric; v_rep jsonb;
begin
  f := public.fn_accountant_cash_forecast(v_week);
  insert into public.accountant_cash_forecast_week (week, forecast) values (v_week, f)
  on conflict (week) do update set forecast = excluded.forecast, recorded_at = now();
  select min((w->>'closing_aed')::numeric) into v_low from jsonb_array_elements(coalesce(f->'weeks', '[]'::jsonb)) w;
  v_low := coalesce(v_low, (f#>>'{low_point,balance_aed}')::numeric);
  if v_low < 0 then
    v_rep := public.fn_support_report_to_ceo('accountant.cash_forecast_negative:' || v_week, 'elevated',
      format('13-week cash forecast from %s goes below zero (low point AED %s)', v_week, v_low),
      f, '[]'::jsonb, 'Decide how the gap is funded before the week it opens: owner capital, a cost cut, or a timing change.',
      null, null, interval '2 days', 'accountant');
    update public.accountant_cash_forecast_week set ceo_report_id = (v_rep->>'report_id')::bigint where week = v_week;
  end if;
  return jsonb_build_object('week', v_week, 'low_point_aed', v_low, 'reported', v_rep is not null,
    'weeks', jsonb_array_length(coalesce(f->'weeks', '[]'::jsonb)));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_cash_position(p_month date, p_month_expenses_aed numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_m date := date_trunc('month', p_month)::date; v_e date;
  v_bal numeric; v_bal_on date; v_bal_ref text; v_in numeric; v_out numeric; v_lines int;
  v_res jsonb; v_res_aed numeric; v_spend numeric; v_spend_months int; v_avail numeric; v_run numeric; v_missing text;
begin
  v_e := (v_m + interval '1 month')::date - 1;
  select closing_balance_aed, balance_on, source_ref into v_bal, v_bal_on, v_bal_ref
    from public.bank_statement_intake
   where account = 'mashreq' and closing_balance_aed is not null and balance_on <= v_e
   order by balance_on desc, received_at desc limit 1;
  select coalesce(sum(amount_aed) filter (where amount_aed > 0), 0), coalesce(-sum(amount_aed) filter (where amount_aed < 0), 0), count(*)
    into v_in, v_out, v_lines
    from public.bank_statement_line where account = 'mashreq' and value_date between v_m and v_e;
  v_res := public.fn_accountant_refund_reserve();
  v_res_aed := coalesce((v_res->>'held_for_possible_refunds_aed')::numeric, 0);
  select avg(x), count(x) into v_spend, v_spend_months
    from (select p_month_expenses_aed x where p_month_expenses_aed is not null
          union all
          select (figures#>>'{cash_out,expenses_aed}')::numeric
            from (select figures from public.accountant_month_close where month < v_m order by month desc limit 2) z) s;
  v_missing := case when v_bal is null then 'no Mashreq closing balance is recorded on or before ' || v_e || ', so there is no runway'
                    when coalesce(v_spend, 0) <= 0 then 'no expense is booked in the months measured, so the spend cannot be measured' end;
  if v_missing is null then
    v_avail := v_bal - v_res_aed;
    v_run := round(v_avail / v_spend, 1);
  end if;

  return jsonb_build_object(
    'cash_in_bank', case when v_bal is null
      then jsonb_build_object('aed', null, 'missing', 'no Mashreq statement with a closing balance on or before ' || v_e || ' is recorded (fn_accountant_bank_balance_record)')
      else jsonb_build_object('aed', v_bal, 'as_of', v_bal_on, 'statement', v_bal_ref, 'stale', v_bal_on < v_m) end,
    'bank_movements', case when v_lines = 0
      then jsonb_build_object('in_aed', null, 'out_aed', null, 'missing', 'no Mashreq statement line is dated in the month')
      else jsonb_build_object('in_aed', v_in, 'out_aed', v_out, 'lines', v_lines) end,
    'held_for_possible_refunds_aed', v_res_aed,
    'runway', jsonb_build_object('months', v_run, 'available_aed', v_avail, 'monthly_spend_aed', round(v_spend, 2),
      'spend_months', v_spend_months, 'missing', v_missing,
      'basis', 'Runway = (cash in the bank - money held for possible refunds) / the average monthly expenses booked over this month and up to two earlier closed months (cash_out.expenses_aed). Refunds are not spend.'));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_cash_truth_check()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_f jsonb := public.fn_finance_forecast(); v_cp jsonb := public.fn_accountant_cash_position(current_date, null);
        v_a numeric; v_b numeric; v_gap numeric; v_rep jsonb;
begin
  v_a := (v_f->>'cash_now')::numeric; v_b := (v_cp #>> '{cash_in_bank,aed}')::numeric;
  if v_a is distinct from v_b and abs(coalesce(v_a, 0) - coalesce(v_b, 0)) > 1 then
    raise exception 'the forecast cash (%) and the cash position (%) disagree by more than AED 1', v_a, v_b;
  end if;
  v_gap := (v_f->>'gl_minus_bank_aed')::numeric;
  if abs(coalesce(v_gap, 0)) > 1 then
    v_rep := public.fn_support_report_to_ceo(
      p_idempotency_key => 'accountant_gl_vs_bank:' || to_char(current_date, 'YYYY-MM'),
      p_severity => 'elevated',
      p_subject => 'The books'' bank account differs from the bank statement by AED ' || v_gap,
      p_evidence => jsonb_build_object('gl_cash_aed', v_f->'gl_cash_aed', 'bank_statement_aed', v_b,
                                       'statement_as_of', v_cp #> '{cash_in_bank,as_of}', 'difference_aed', v_gap),
      p_attempted => '[]'::jsonb,
      p_requested => 'None from you. The accountant reconciles GL account 1000 to the statement line by line; every cash figure already reads the statement.',
      p_review_in => interval '30 days', p_source_agent => 'accountant');
  end if;
  return jsonb_build_object('forecast_cash_aed', v_a, 'cash_position_aed', v_b, 'agree', true,
                            'gl_minus_bank_aed', v_gap, 'reported_to_ceo', v_rep is not null);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_charge_audit_candidates(p_limit integer DEFAULT 200)
 RETURNS TABLE(transaction_id uuid, payment_ref text, quote_amount numeric, rate numeric, revealed_at timestamp with time zone, demo boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select t.id, t.payment_ref, t.quote_amount,
         case when c.promo_until is not null and t.revealed_at < c.promo_until then c.promo_reveal_rate else c.standard_reveal_rate end,
         t.revealed_at, coalesce(cu.is_demo, false)
    from public.transactions t
    cross join lateral (select * from public.pricing_config order by id limit 1) c
    left join public.customers cu on cu.id = t.customer_id
    left join public.charge_audit a on a.transaction_id = t.id
   where t.fee_status = 'paid' and t.payment_ref like 'pi\_%' and coalesce(t.quote_amount, 0) > 0
     and (a.transaction_id is null or a.audited_at < now()
          - make_interval(hours => (select num_value::int from public.gl_settings where key = 'charge_audit_every_hours')))
   order by a.audited_at nulls first, t.revealed_at
   limit greatest(p_limit, 1);
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_charge_audit_record(p_results jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  x jsonb; n int := 0; v_items jsonb := '[]'::jsonb; r record; v_sys int; v_rep jsonb; v_sign text;
begin
  if jsonb_typeof(p_results) is distinct from 'array' then
    raise exception 'fn_accountant_charge_audit_record(results[]): an array of audit results is required';
  end if;
  for x in select e from jsonb_array_elements(p_results) e loop
    insert into public.charge_audit (transaction_id, audited_at, livemode, basis, quote_amount, rate, expected_total,
                                     expected_processing, actual_total, actual_fee_fils, diff_aed, shortfall_aed, evidence)
    values ((x->>'transaction_id')::uuid, now(), (x->>'livemode')::boolean, x->>'basis', (x->>'quote_amount')::numeric,
            (x->>'rate')::numeric, (x->>'expected_total')::numeric, (x->>'expected_processing')::numeric,
            (x->>'actual_total')::numeric, (x->>'actual_fee_fils')::bigint,
            round((x->>'actual_total')::numeric - (x->>'expected_total')::numeric, 2),
            (x->>'shortfall_aed')::numeric, coalesce(x->'evidence', '{}'::jsonb))
    on conflict (transaction_id) do update
       set audited_at = now(), livemode = excluded.livemode, basis = excluded.basis, quote_amount = excluded.quote_amount,
           rate = excluded.rate, expected_total = excluded.expected_total, expected_processing = excluded.expected_processing,
           actual_total = excluded.actual_total, actual_fee_fils = excluded.actual_fee_fils, diff_aed = excluded.diff_aed,
           shortfall_aed = excluded.shortfall_aed, evidence = excluded.evidence,
           -- a difference that changed is a new difference: its old resolution no longer covers it
           resolved_at = case when charge_audit.diff_aed = excluded.diff_aed then charge_audit.resolved_at end,
           resolution = case when charge_audit.diff_aed = excluded.diff_aed then charge_audit.resolution end;
    n := n + 1;
  end loop;

  -- Every unresolved LIVE-mode difference is a finding, whether or not it was audited on this run.
  -- 19 Oct 2026: a Stripe test-mode charge moved no money; its audit stays recorded in charge_audit, not raised.
  for r in select a.*, coalesce(cu.is_demo, false) demo from public.charge_audit a
             join public.transactions t on t.id = a.transaction_id left join public.customers cu on cu.id = t.customer_id
            where abs(a.diff_aed) >= 0.01 and a.resolved_at is null and a.livemode loop
    v_items := v_items || jsonb_build_object('item', 'charge:' || r.transaction_id,
      'owner_seat', 'accountant', 'subject', 'stripe_checkout',
      'title', case when r.diff_aed > 0
                    then 'Reveal ' || left(r.transaction_id::text, 8) || ' was charged AED ' || r.actual_total || ', AED ' || r.diff_aed || ' more than the formula''s AED ' || r.expected_total
                    else 'Reveal ' || left(r.transaction_id::text, 8) || ' was charged AED ' || r.actual_total || ', AED ' || abs(r.diff_aed) || ' less than the formula''s AED ' || r.expected_total end,
      'blast', case when r.diff_aed > 0 then 'customer_facing' else 'agent_facing' end, 'affected', 1,
      'demo', r.demo or not r.livemode,
      'evidence', to_jsonb(r) - 'demo' || jsonb_build_object('formula', 'supabase/functions/_shared/reveal_fee.ts revealChargeFor'));
  end loop;

  -- Systematic: the same direction too often inside thirty days is the formula or a rate, not a sale.
  select num_value::int into v_sys from public.gl_settings where key = 'charge_audit_systematic_count';
  foreach v_sign in array array['over', 'under'] loop
    if (select count(*) from public.charge_audit a
         where a.livemode and a.audited_at > now() - interval '30 days'
           and ((v_sign = 'over' and a.diff_aed >= 0.01) or (v_sign = 'under' and a.diff_aed <= -0.01))) >= coalesce(v_sys, 3) then
      v_rep := public.fn_support_report_to_ceo('charge_audit_systematic:' || v_sign || ':' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM'),
        'serious',
        'Reveal charges are systematically ' || v_sign || ' the formula: ' || (select count(*) from public.charge_audit a
          where a.livemode and a.audited_at > now() - interval '30 days'
            and ((v_sign = 'over' and a.diff_aed >= 0.01) or (v_sign = 'under' and a.diff_aed <= -0.01))) || ' sale(s) in 30 days',
        jsonb_build_object('direction', v_sign, 'sales', (select jsonb_agg(jsonb_build_object('transaction_id', a.transaction_id,
            'expected', a.expected_total, 'actual', a.actual_total, 'diff', a.diff_aed, 'basis', a.basis))
          from public.charge_audit a where a.livemode and a.audited_at > now() - interval '30 days'
            and ((v_sign = 'over' and a.diff_aed >= 0.01) or (v_sign = 'under' and a.diff_aed <= -0.01)))),
        '[]'::jsonb,
        'A rate in supabase/functions/_shared/reveal_fee.ts or a Stripe price has moved: every sale is affected, not one. Decide the correction; the accountant refunds any overcharge on your approval and keeps auditing daily.',
        p_review_in => interval '1 day', p_source_agent => 'accountant');
    end if;
  end loop;

  return jsonb_build_object('audited', n, 'findings', public.fn_accountant_duty_settle('charge_audit', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_charge_audit_resolve(p_transaction_id uuid, p_resolution text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if coalesce(btrim(p_resolution), '') = '' then raise exception 'a charge difference is resolved only with what was done about it'; end if;
  update public.charge_audit set resolved_at = now(), resolution = p_resolution
   where transaction_id = p_transaction_id and resolved_at is null and abs(diff_aed) >= 0.01;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no open charge difference on ' || p_transaction_id); end if;
  return jsonb_build_object('ok', true, 'transaction_id', p_transaction_id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_charge_recovery_duty()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  return jsonb_build_object('tick', public.fn_accountant_recovery_tick(),
    'open_claims', (select count(*) from public.v_accountant_recovery_ledger where not demo),
    'open_claim_aed', (select coalesce(sum(claim_aed), 0) from public.v_accountant_recovery_ledger where not demo),
    'by_stage', (select coalesce(jsonb_object_agg(stage, n), '{}'::jsonb) from (select stage, count(*) n from public.v_accountant_recovery_ledger where not demo group by stage) x));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_classify_bank_lines_by_reference()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int;
begin
  update public.bank_statement_line b
     set kind = c.kind, kind_by = 'bank_reference_code#' || c.id, kind_at = now()
    from public.bank_reference_code c
   where b.kind is null and c.kind is not null
     and b.account = c.bank and b.reference is not null
     and starts_with(split_part(b.reference, ' ', 1), c.code_prefix)
     and (c.code_suffix is null or split_part(b.reference, ' ', 2) = c.code_suffix)
     and sign(b.amount_aed) = c.sign;
  get diagnostics n = row_count;
  return n;
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_close_by_day_5()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_local date := (now() at time zone 'Asia/Dubai')::date; v_prev date; v_tick jsonb; v_s jsonb; v_rep jsonb;
begin
  v_prev := (date_trunc('month', v_local) - interval '1 month')::date;
  v_tick := public.fn_accountant_month_close_tick();       -- the close itself runs here too, not only inside the runtime
  v_s := public.fn_accountant_month_close_status(v_prev, v_local);
  if v_s->>'status' = 'waiting_for_statement' and extract(day from v_local) > 5 then
    v_rep := public.fn_support_report_to_ceo(
      p_idempotency_key => 'accountant_close_waiting:' || to_char(v_prev, 'YYYY-MM'), p_severity => 'routine',
      p_subject => 'The ' || to_char(v_prev, 'Mon YYYY') || ' close is waiting for the Mashreq statement',
      p_evidence => jsonb_build_object('month', to_char(v_prev, 'YYYY-MM'), 'statement', v_s->'statement'),
      p_attempted => '[]'::jsonb,
      p_requested => 'None: the founder forwards the statement monthly; the accountant books it and closes the month within two days of its arrival.',
      p_review_in => interval '30 days', p_source_agent => 'accountant');
  elsif (v_s->>'late')::boolean then
    v_rep := public.fn_support_report_to_ceo(
      p_idempotency_key => 'accountant_close_day5:' || to_char(v_prev, 'YYYY-MM'), p_severity => 'elevated',
      p_subject => 'The ' || to_char(v_prev, 'Mon YYYY') || ' close ' || case when v_s->>'status' = 'closed' then 'was late' else 'is not done' end
                   || ' (due by ' || (v_s->>'due_by') || ')',
      p_evidence => jsonb_build_object('month', to_char(v_prev, 'YYYY-MM'), 'status', v_s, 'tick', v_tick),
      p_attempted => '[]'::jsonb, p_requested => 'None: the accountant closes it on this tick; this records the missed target.',
      p_review_in => interval '30 days', p_source_agent => 'accountant');
  end if;
  return jsonb_build_object('month', to_char(v_prev, 'YYYY-MM'), 'status', v_s->>'status', 'due_by', v_s->'due_by',
    'closed_at', v_s->'closed_at', 'closed_by_day_5', v_s->>'status' = 'closed' and not (v_s->>'late')::boolean,
    'late', (v_s->>'late')::boolean, 'tick', v_tick);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_collections_tick(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_basis boolean := coalesce((select (value->>'confirmed')::boolean from public.decision_policy where key = 'supplier_charge_recovery_basis'), false);
  v_offs int[] := public.fn_policy_int_array('supplier_charge_reminder_after_due_days');
  v_fd int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_final_demand_after_due_days');
  v_notice int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_final_demand_notice_days');
  v_esc int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_escalate_ceo_after_due_days');
  v_min_notice int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_legal_minimum_notice_days');
  v_lim_years int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_limitation_years');
  v_lim_warn int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_limitation_warn_days');
  v_min_ver int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_demand_min_agreement_version');
  v_ver int; v_limit_on date; v_route jsonb;
  d record; v jsonb; v_days int; v_i int; v_items jsonb := '[]'::jsonb; v_payload jsonb; v_disputed boolean;
  n_rem int := 0; n_fd int := 0; n_file int := 0; v_accrued int;
begin
  if array_length(v_offs, 1) is null or v_fd is null or v_notice is null or v_esc is null then
    raise exception 'fn_accountant_collections_tick: the supplier_charge_* timeline is missing from decision_policy';
  end if;
  if v_min_notice is null or v_lim_years is null or v_lim_warn is null or v_min_ver is null then
    raise exception 'fn_accountant_collections_tick: the legal minimum, limitation or agreement-version row is missing from decision_policy';
  end if;
  -- CPL 42/2022 Art 144(1): a demand giving fewer than five days is not a notice for payment.
  if v_notice < v_min_notice then
    raise exception 'supplier_charge_final_demand_notice_days is % but CPL Art 144(1) requires at least %; nothing is sent', v_notice, v_min_notice;
  end if;
  v_accrued := public.fn_supplier_dues_accrue_interest(v_as_of);

  for d in select s.*, l.company_name, coalesce(l.is_demo, false) demo, l.accepted_terms_version agreement_version
             from public.supplier_dues s join public.leads l on l.id = s.supplier_id
            where public.fn_supplier_due_is_owed(s.status, s.paid_at)
              and coalesce(s.legal_stage, '') not like 'outcome:%'
            order by s.id loop
    v_days := v_as_of - d.due_date;
    v := public.fn_accountant_nonresponse_charge(d.transaction_id, v_as_of);
    v_payload := coalesce(v, '{}'::jsonb) || jsonb_build_object('agreement_version', coalesce(d.agreement_version, ''), 'due_id', d.id, 'supplier_id', d.supplier_id,
      'transaction_id', d.transaction_id, 'quote_id', d.quote_id, 'days_overdue', greatest(v_days, 0),
      'interest_pct', round(coalesce((v->>'interest_apr')::numeric, 0) * 100, 2), 'due_date', d.due_date,
      'total_aed', coalesce(d.total_claim, d.amount_due));
    -- 14 SEP 2026 (Supplier Agreement v12): every notice carries the clause 21 wording and the WhatsApp basis of
    -- the version THIS supplier accepted, for the templates ({{notice_clause_en}}, {{notice_clause_ar}},
    -- {{whatsapp_basis}}). The number itself is chosen at the outbox by a06 (fn_supplier_notice_route), never here.
    v_route := public.fn_supplier_notice_route(d.supplier_id, null);
    v_payload := v_payload || jsonb_build_object('notice_clause_en', coalesce(v_route->>'clause_en', ''),
      'notice_clause_ar', coalesce(v_route->>'clause_ar', ''), 'whatsapp_basis', coalesce(v_route->'whatsapp'->>'basis', ''));
    v_disputed := exists (select 1 from public.agent_actions a
                           where a.kind = 'handoff' and a.detail->>'type' = 'charge.dispute_answer'
                             and (a.detail->>'due_id')::bigint = d.id and (a.detail->>'figures_match')::boolean is false);

    if v_disputed then
      v_items := v_items || jsonb_build_object('item', 'disputed:' || d.id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', coalesce(d.company_name, 'A supplier') || ' disputed charge #' || d.id || ' and the recomputation did not confirm it; notices are held until the CEO decides',
        'blast', 'agent_facing', 'affected', 1, 'demo', d.demo, 'evidence', v_payload);
    elsif not v_basis then
      if v_days >= v_offs[1] then
        v_items := v_items || jsonb_build_object('item', 'held_basis:' || d.id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
          'title', 'Charge #' || d.id || ' (' || coalesce(d.company_name, 'supplier') || ', AED ' || coalesce(d.total_claim, d.amount_due)
                   || ') is ' || v_days || ' day(s) past due and no reminder can go: the UAE recovery timeline and wording are not yet configured',
          'blast', 'agent_facing', 'affected', 1, 'demo', d.demo,
          'evidence', v_payload || jsonb_build_object('needs', 'decision_policy supplier_charge_recovery_basis confirmed = true, from docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md'));
      end if;
    else
      -- The next reminder, once its day is reached.
      v_i := coalesce(d.reminders, 0) + 1;
      if v_i <= array_length(v_offs, 1) and v_days >= v_offs[v_i] and d.legal_stage is null then
        perform public.fn_seat_handoff('accountant', 'sales_engineer', 'nonresponse.charge_reminder', 'supplier_dues',
          d.id || ':reminder:' || v_i, v_payload || jsonb_build_object('notice', 'charge_reminder', 'reminder_no', v_i));
        update public.supplier_dues set reminders = v_i, last_reminder_at = now() where id = d.id;
        n_rem := n_rem + 1;
      end if;
      -- THE DEMAND NEEDS v11 OR LATER (clause 21 makes WhatsApp and SMS notice, clause 22 makes Arabic govern).
      -- A v11 supplier is not held for v12: v11 covers the notice, which goes to the registered mobile. A
      -- supplier below v11 is held for the CEO until it accepts the current version. Unreadable is older.
      v_ver := (v_route->>'version_no')::int;
      if v_days >= v_fd and d.legal_stage is null and coalesce(v_ver, 0) < v_min_ver then
        v_items := v_items || jsonb_build_object('item', 'demand_held_version:' || d.id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
          'title', 'The final demand on charge #' || d.id || ' (' || coalesce(d.company_name, 'supplier') || ') is held: the supplier accepted '
                   || coalesce(d.agreement_version, 'no version') || ' (' || coalesce(v_route->>'clause_en', 'no clause 21 on record')
                   || '), and a demand needs Supplier Agreement v' || v_min_ver || ' or later (WhatsApp/SMS notice, Arabic governing text)',
          'blast', 'agent_facing', 'affected', 1, 'demo', d.demo,
          'evidence', v_payload || jsonb_build_object('accepted_version', d.agreement_version, 'required_version', 'v' || v_min_ver,
            'remedy', 'the supplier accepts the current version on the next portal sign-in; the demand goes on the next run after that'));
      -- The formal final demand.
      elsif v_days >= v_fd and d.legal_stage is null then
        perform public.fn_seat_handoff('accountant', 'sales_engineer', 'nonresponse.final_demand', 'supplier_dues',
          d.id || ':final_demand', v_payload || jsonb_build_object('notice', 'final_demand',
            'pay_by', (now() at time zone 'Asia/Dubai')::date + v_notice));
        update public.supplier_dues set legal_stage = 'final_demand_sent', legal_escalated_at = now() where id = d.id;
        n_fd := n_fd + 1;
      elsif d.legal_stage = 'final_demand_sent' and now() >= d.legal_escalated_at + make_interval(days => v_notice) then
        update public.supplier_dues set legal_stage = 'filing_pack_due' where id = d.id;
        d.legal_stage := 'filing_pack_due';
        n_file := n_file + 1;
      end if;
    end if;

    if d.legal_stage in ('filing_pack_due', 'filing_pack_sent') then
      v_items := v_items || jsonb_build_object('item', 'filing:' || d.id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', 'The final demand on charge #' || d.id || ' (' || coalesce(d.company_name, 'supplier') || ', AED '
                 || coalesce(d.total_claim, d.amount_due) || ') has expired unpaid: the filing pack is '
                 || case d.legal_stage when 'filing_pack_due' then 'due to the founder' else 'with the founder' end
                 || ', and this stays open until he records the outcome',
        'blast', 'agent_facing', 'affected', 1, 'demo', d.demo,
        'evidence', v_payload || jsonb_build_object('legal_stage', d.legal_stage, 'case_file_path', d.case_file_path,
                                                   'record_outcome', 'select public.fn_accountant_record_filing_outcome(' || d.id || ', ''filed'', ''<reference>'')'));
    end if;
    -- CTL Art 92: five years from the due date. An unfiled charge nearing that date is the CEO's.
    v_limit_on := (d.due_date + make_interval(years => v_lim_years))::date;
    if v_as_of >= v_limit_on - v_lim_warn and coalesce(d.legal_stage, '') not like 'outcome:filed%' then
      v_items := v_items || jsonb_build_object('item', 'limitation:' || d.id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', 'Charge #' || d.id || ' (' || coalesce(d.company_name, 'supplier') || ') is time-barred on ' || v_limit_on
                 || ' (CTL Art 92, five years from the due date) and has not been filed',
        'blast', 'agent_facing', 'affected', 1, 'demo', d.demo, 'evidence', v_payload || jsonb_build_object('limitation_on', v_limit_on));
    end if;
    if v_days >= v_esc then
      v_items := v_items || jsonb_build_object('item', 'overdue:' || d.id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', coalesce(d.company_name, 'A supplier') || ' owes AED ' || coalesce(d.total_claim, d.amount_due) || ' on charge #' || d.id
                 || ', ' || v_days || ' days past due, after ' || coalesce(d.reminders, 0) || ' reminder(s)',
        'blast', 'agent_facing', 'affected', 1, 'demo', d.demo, 'evidence', v_payload);
    end if;
  end loop;

  return jsonb_build_object('as_of', v_as_of, 'basis_confirmed', v_basis, 'interest_updated', v_accrued,
    'reminders', n_rem, 'final_demands', n_fd, 'filing_packs_due', n_file, 'aging', public.fn_accountant_dues_aging(v_as_of),
    'findings', public.fn_accountant_duty_settle('collections', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_cost_booking_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_sync int; v_class int; v_bank jsonb; v_cap jsonb;
begin
  v_sync := public.fn_gl_sync_business();
  -- Structured reference codes first, so the bank-charge and bank-credit rules below book what they classify.
  -- Its own block: a classifier failure never undoes the business sync or stops the bookings below.
  begin
    v_class := public.fn_accountant_classify_bank_lines_by_reference();
    perform public.fn_accountant_duty_settle('bank_reference_classify', '[]'::jsonb);
  exception when others then
    -- never silent (release review): the failure is an accountant finding, and the bookings below still run
    v_class := null;
    perform public.fn_accountant_duty_settle('bank_reference_classify', jsonb_build_array(jsonb_build_object(
      'item', 'run', 'owner_seat', 'accountant', 'subject', 'bank_statement_line',
      'title', 'Classifying bank lines by their reference code failed, so none was classified this run: ' || sqlerrm,
      'blast', 'agent_facing', 'affected', 1)));
  end;
  v_bank := public.fn_accountant_book_bank_charges();
  -- The bank-credit rule runs in its own block (review of b06d251): whatever fails in it can never undo the
  -- business sync or the bank charges above; the failure is an accountant finding instead.
  begin
    v_cap := public.fn_accountant_book_bank_credits();
    perform public.fn_accountant_duty_settle('bank_credits_run', '[]'::jsonb);
  exception when others then
    v_cap := jsonb_build_object('error', sqlerrm);
    perform public.fn_accountant_duty_settle('bank_credits_run', jsonb_build_array(jsonb_build_object(
      'item', 'run', 'owner_seat', 'accountant', 'subject', 'bank_statement_line',
      'title', 'Booking the bank''s credits failed, so nothing was booked from them this run: ' || sqlerrm,
      'blast', 'agent_facing', 'affected', 1)));
  end;
  return jsonb_build_object('gl_sync_business_entries', v_sync, 'classified_by_reference_code', v_class,
                            'bank_charges', v_bank, 'bank_credits', v_cap);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_csv_row(VARIADIC p_cells text[])
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select string_agg('"' || replace(coalesce(c, ''), '"', '""') || '"', ',' order by i)
    from unnest(p_cells) with ordinality u(c, i)
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_dispute_drafted(p_id text, p_ok boolean, p_response jsonb, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.stripe_dispute; v_ev jsonb; v_rep jsonb;
begin
  select * into d from public.stripe_dispute where id = p_id for update;
  if not found then raise exception 'no dispute %', p_id; end if;
  if not p_ok then
    update public.stripe_dispute set submit_error = left('draft not saved: ' || coalesce(p_error, '?'), 600), last_seen_at = now() where id = p_id;
    return jsonb_build_object('ok', false, 'dispute', p_id);
  end if;
  v_ev := public.fn_accountant_dispute_evidence(p_id);
  v_rep := public.fn_support_report_to_ceo('dispute_review:' || p_id, 'serious',
    'Card dispute ' || p_id || ' on AED ' || round(d.amount_fils / 100.0, 2) || ' (' || coalesce(d.reason, 'no reason given')
      || '): evidence saved as a draft, waiting for your approval to submit',
    jsonb_build_object('dispute', p_id, 'amount_aed', round(d.amount_fils / 100.0, 2), 'reason', d.reason,
                       'evidence_due_by', d.evidence_due_by, 'auto_submit_at', d.evidence_due_by - interval '24 hours',
                       'evidence', v_ev->'fields', 'receipt_attached', v_ev ? 'receipt' and v_ev->'receipt' <> 'null'::jsonb,
                       'livemode', d.livemode),
    '[]'::jsonb,
    'Read the evidence and approve its submission: select public.fn_ceo_approve_dispute_submission(''' || p_id || ''', ''<your note>'');'
      || ' Submitting is final — Stripe accepts one submission. If you do not answer, the accountant submits the saved evidence at '
      || to_char((d.evidence_due_by - interval '24 hours') at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' Dubai, 24 hours before Stripe''s deadline.',
    p_review_in => greatest(least(d.evidence_due_by - interval '24 hours' - now(), interval '2 days'), interval '1 hour'),
    p_source_agent => 'accountant');
  update public.stripe_dispute
     set draft_saved_at = now(), submit_error = null, submission = p_response, last_seen_at = now(),
         review_report_id = (v_rep->>'report_id')::bigint
   where id = p_id;
  return jsonb_build_object('ok', true, 'dispute', p_id, 'review_report', v_rep);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_dispute_evidence(p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  d public.stripe_dispute; t public.transactions; c public.customers; v_inq text; v_job text; v_sup text; v_window int;
  v_msgs int; v_sup_msgs int; v_first timestamptz; v_deliv text; v_log text; v_terms text; v_basis text;
  v_policy text; v_policy_v text; v_words text; v_wa text; v_prior int;
begin
  select * into d from public.stripe_dispute where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no dispute ' || p_id); end if;
  select * into t from public.transactions where id = d.transaction_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'dispute ' || p_id || ' names payment ' || coalesce(d.payment_intent, '?') || ', which no transaction records'); end if;
  select * into c from public.customers where id = t.customer_id;
  select summary, coalesce(rfq_no::text, upper(left(id::text, 8))) into v_inq, v_job from public.inquiries where id = t.inquiry_id;
  select company_name into v_sup from public.leads where id = t.supplier_id;
  select refund_window_working_days into v_window from public.pricing_config order by id limit 1;
  select count(*), count(*) filter (where sender = 'supplier') into v_msgs, v_sup_msgs
    from public.messages where inquiry_id = t.inquiry_id and supplier_id = t.supplier_id and created_at >= t.revealed_at;
  select min(first_response_at) into v_first from public.supplier_response_watch where transaction_id = t.id;
  -- every provider-confirmed delivery about this sale, email and WhatsApp alike
  select string_agg(coalesce(n.channel, 'email') || ' ' || n.type || ' to ' || coalesce(n.to_role, '?') || ' sent '
                    || to_char(n.sent_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' (provider id ' || n.provider_message_id || ')',
                    '; ' order by n.sent_at)
    into v_deliv from public.notifications n
   where n.quote_id = t.quote_id and n.status = 'sent' and coalesce(n.provider_message_id, '') <> '';

  -- the fee the customer saw before paying: the Checkout line reads "Reveal fee (3% of AED <quote>)"
  v_basis := 'Fee shown to the customer before payment: AED ' || t.reveal_fee
    || case when coalesce(t.quote_amount, 0) > 0
            then ' = ' || regexp_replace(round(t.reveal_fee / t.quote_amount * 100, 2)::text, '\.?0+$', '') || '% of AED ' || t.quote_amount
                 || ', the supplier''s quoted price' else '' end
    || '. Total charged AED ' || coalesce(t.total_charged, t.reveal_fee) || '.';

  v_terms := case when c.tos_accepted_at is null then 'No terms acceptance is recorded for this customer.'
    else 'The customer accepted the QuotesDone customer terms ' || coalesce(c.tos_version, '(version not recorded)') || ' on '
      || to_char(c.tos_accepted_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' (Dubai)'
      || coalesce(' from IP ' || c.tos_ip, '') || coalesce(', document SHA-256 ' || c.tos_sha256, '')
      || case when coalesce(c.signed_terms_path, '') <> '' then '; the signed acceptance certificate is on record' else '' end
      || ', before paying for this reveal.' end;

  select version, left(btrim(regexp_replace(regexp_replace(replace(replace(body_html, '&amp;', '&'), '&nbsp;', ' '),
                                                           '<[^>]+>', ' ', 'g'), '\s+', ' ', 'g')), 15000)
    into v_policy_v, v_policy from public.legal_documents where slug = 'refund-policy';

  -- the customer's own words: portal messages on this request, and WhatsApp messages from their number
  select string_agg(to_char(m.created_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' portal: ' || left(m.body, 300), E'\n' order by m.created_at)
    into v_words
    from (select * from public.messages where inquiry_id = t.inquiry_id and sender = 'customer' order by created_at desc limit 20) m;
  select string_agg(to_char(w.created_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' WhatsApp: ' || left(w.inbound, 300), E'\n' order by w.created_at)
    into v_wa
    from (select * from public.wa_messages
           where coalesce(inbound, '') <> ''
             and right(regexp_replace(wa_from, '\D', '', 'g'), 9) <> ''
             and right(regexp_replace(wa_from, '\D', '', 'g'), 9) in (right(regexp_replace(coalesce(c.whatsapp_phone, ''), '\D', '', 'g'), 9),
                                                                      right(regexp_replace(coalesce(c.phone, ''), '\D', '', 'g'), 9))
           order by created_at desc limit 20) w;

  select count(*) into v_prior from public.stripe_dispute x join public.transactions y on y.id = x.transaction_id
   where y.customer_id = t.customer_id and x.id <> d.id;

  v_log := 'Reveal paid ' || to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' (Dubai), payment ' || t.payment_ref
        || '. The supplier''s contact details were released in the customer''s QuotesDone portal at that moment. '
        || v_msgs || ' portal message(s) exchanged after the reveal, ' || v_sup_msgs || ' from the supplier'
        || coalesce('; supplier first responded ' || to_char(v_first at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI'), '') || '. '
        || v_terms;

  return jsonb_build_object('ok', true, 'dispute', d.id, 'livemode', d.livemode, 'transaction_id', t.id,
    'fields', jsonb_strip_nulls(jsonb_build_object(
      'customer_name', c.full_name,
      'customer_email_address', c.email,
      'service_date', to_char(t.revealed_at at time zone 'Asia/Dubai', 'YYYY-MM-DD'),
      'product_description', 'A paid reveal on QuotesDone, a UAE procurement marketplace' || coalesce(', job ' || v_job, '')
        || ': the customer paid to release the contact details of ' || coalesce(v_sup, 'a supplier')
        || ', whose quote they chose for their request "' || left(coalesce(v_inq, 'a procurement request'), 200)
        || '". ' || v_basis || ' It is a digital service delivered at the moment of payment.',
      'access_activity_log', v_log,
      'refund_policy_disclosure', 'The customer''s receipt and the terms state that if the supplier does not respond within '
        || coalesce(v_window, 5) || ' working days the customer is refunded everything they paid. Refund status of this payment: '
        || coalesce(t.refund_status, 'none requested') || '.'
        || coalesce(E'\n\nQuotesDone refund policy ' || v_policy_v || ', as published:\n' || v_policy, ''),
      'uncategorized_text', 'Checkout record: payment ' || coalesce(t.payment_ref, '?') || ', Stripe invoice '
        || coalesce(t.stripe_invoice_number, t.stripe_invoice_id, 'not recorded') || ', AED ' || coalesce(t.total_charged, t.reveal_fee)
        || ', paid ' || to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' (Dubai). ' || v_basis
        || E'\nDelivery records: ' || coalesce(v_deliv, 'no provider-confirmed delivery on record') || '.'
        || E'\nTerms: ' || v_terms
        || E'\nThe customer''s own messages: ' || coalesce(nullif(concat_ws(E'\n', v_words, v_wa), ''), 'none on record') || '.',
      -- for the CEO's review only; disputeEvidenceForm never sends a field Stripe does not name
      'ceo_prior_disputes', v_prior,
      'ceo_summary', 'AED ' || round(d.amount_fils / 100.0, 2) || ', reason ' || coalesce(d.reason, '?') || ', due '
        || coalesce(to_char(d.evidence_due_by at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' Dubai', '?')
        || case when v_prior > 0 then '. REPEAT DISPUTER: ' || v_prior || ' earlier dispute(s) by this customer' else '' end
        || case when c.tos_accepted_at is null then '. No terms acceptance on record' else '' end || '.')),
    'receipt', case when coalesce(t.doc_path, '') <> '' then jsonb_build_object('bucket', 'finance-docs', 'path', t.doc_path,
                                                                                'name', coalesce(t.doc_name, 'invoice.pdf')) end,
    'terms_certificate', case when coalesce(c.signed_terms_path, '') <> '' then jsonb_build_object('bucket', 'signed-terms',
                                                                                'path', c.signed_terms_path, 'name', 'signed-terms-certificate.pdf') end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_dispute_record(p_dispute jsonb, p_livemode boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_tx uuid; v_demo boolean; v_status text := p_dispute->>'status'; v_rep jsonb;
begin
  if coalesce(p_dispute->>'id', '') !~ '^(dp|du)_' or (p_dispute->>'amount') is null then
    raise exception 'fn_accountant_dispute_record: % is not a Stripe dispute object', left(p_dispute::text, 200);
  end if;
  select t.id, coalesce(c.is_demo, false) into v_tx, v_demo
    from public.transactions t left join public.customers c on c.id = t.customer_id
   where t.payment_ref = p_dispute->>'payment_intent' limit 1;
  -- A TEST-MODE DISPUTE MAY ONLY EVER TOUCH DEMO DATA (the rule stripe_webhook applies to every test event).
  if not p_livemode and not coalesce(v_demo, false) then
    return jsonb_build_object('ok', true, 'ignored', 'test-mode dispute not on a ZZ DEMO payment');
  end if;
  insert into public.stripe_dispute (id, livemode, charge_id, payment_intent, transaction_id, amount_fils, currency, reason, status,
                                     evidence_due_by, outcome, closed_at)
  values (p_dispute->>'id', p_livemode, p_dispute->>'charge', p_dispute->>'payment_intent', v_tx, (p_dispute->>'amount')::bigint,
          lower(p_dispute->>'currency'), p_dispute->>'reason', v_status,
          to_timestamp(nullif(p_dispute#>>'{evidence_details,due_by}', '')::bigint),
          case when v_status in ('won', 'lost', 'warning_closed') then v_status end,
          case when v_status in ('won', 'lost', 'warning_closed') then now() end)
  on conflict (id) do update
     set status = excluded.status, reason = excluded.reason, last_seen_at = now(),
         transaction_id = coalesce(stripe_dispute.transaction_id, excluded.transaction_id),
         evidence_due_by = coalesce(excluded.evidence_due_by, stripe_dispute.evidence_due_by),
         outcome = coalesce(excluded.outcome, stripe_dispute.outcome),
         closed_at = coalesce(stripe_dispute.closed_at, excluded.closed_at),
         -- Stripe says it has the evidence; keep our record of submitting it
         evidence_submitted_at = coalesce(stripe_dispute.evidence_submitted_at,
           case when (p_dispute#>>'{evidence_details,has_evidence}')::boolean and excluded.status = 'under_review' then now() end);
  if v_status in ('won', 'lost', 'warning_closed') then
    v_rep := public.fn_support_report_to_ceo('dispute_closed:' || (p_dispute->>'id'),
      case when v_status = 'lost' then 'elevated' else 'routine' end,
      'Card dispute ' || (p_dispute->>'id') || ' on AED ' || round((p_dispute->>'amount')::numeric / 100, 2) || ' closed: ' || v_status,
      jsonb_build_object('dispute', p_dispute->>'id', 'status', v_status, 'transaction_id', v_tx, 'reason', p_dispute->>'reason',
                         'livemode', p_livemode),
      '[]'::jsonb, 'Acknowledge. A lost dispute is money Stripe took back; the accountant has recorded the outcome.',
      p_review_in => interval '3 days', p_source_agent => 'accountant');
  end if;
  return jsonb_build_object('ok', true, 'dispute', p_dispute->>'id', 'transaction_id', v_tx, 'status', v_status);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_dispute_submit_trigger(p_id text, p_at timestamp with time zone DEFAULT now())
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
    when d.draft_saved_at is null or d.evidence_submitted_at is not null or d.closed_at is not null then null
    when d.evidence_due_by is not null and p_at >= d.evidence_due_by then null           -- Stripe has closed it
    when d.approved_at is not null then 'ceo_approval'
    when d.evidence_due_by is not null and p_at >= d.evidence_due_by - interval '24 hours' then 'deadline_t24_ceo_silent'
    else null end
  from public.stripe_dispute d where d.id = p_id;
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_dispute_submitted(p_id text, p_ok boolean, p_response jsonb, p_error text DEFAULT NULL::text, p_trigger text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.stripe_dispute;
begin
  select * into d from public.stripe_dispute where id = p_id for update;
  if not found then raise exception 'no dispute %', p_id; end if;
  if p_ok and coalesce(p_trigger, '') not in ('ceo_approval', 'deadline_t24_ceo_silent') then
    raise exception 'a submission to Stripe names what triggered it: ceo_approval or deadline_t24_ceo_silent (got %)', coalesce(p_trigger, 'nothing');
  end if;
  update public.stripe_dispute
     set evidence_submitted_at = case when p_ok then now() else evidence_submitted_at end,
         submit_trigger = case when p_ok then p_trigger else submit_trigger end,
         submission = coalesce(p_response, submission), submit_error = case when p_ok then null else left(p_error, 600) end,
         status = coalesce(case when p_ok then p_response->>'status' end, status), last_seen_at = now()
   where id = p_id;
  if p_ok and d.review_report_id is not null then
    update public.support_ceo_report
       set status = 'completed', completed_at = now(),
           completion_note = 'accountant submitted the evidence to Stripe; trigger: ' || p_trigger
                             || case when p_trigger = 'deadline_t24_ceo_silent' then ' (no CEO answer by T-24h)' else '' end
     where id = d.review_report_id and status <> 'completed';
  end if;
  return jsonb_build_object('ok', true, 'dispute', p_id, 'submitted', p_ok, 'trigger', p_trigger);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_disputes_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d record; v_items jsonb := '[]'::jsonb; v_left interval; n_alert int := 0; v_rep jsonb; v_demo boolean;
begin
  for d in select s.*, coalesce(c.is_demo, false) demo from public.stripe_dispute s
             left join public.transactions t on t.id = s.transaction_id left join public.customers c on c.id = t.customer_id
            where s.closed_at is null loop
    v_demo := d.demo or not d.livemode;
    v_left := d.evidence_due_by - now();
    if d.evidence_submitted_at is null and d.status in ('needs_response', 'warning_needs_response') and d.evidence_due_by is not null then
      if v_left <= interval '24 hours' and d.alerted_24h_at is null then
        v_rep := public.fn_support_report_to_ceo('dispute:' || d.id || ':t24', 'critical',
          'Card dispute ' || d.id || ' (AED ' || round(d.amount_fils / 100.0, 2) || ') is unanswered and Stripe closes it in under 24 hours',
          to_jsonb(d) - 'demo', '[]'::jsonb,
          'Decide now: the accountant submits the evidence it holds, or record why the dispute is accepted. Unanswered, Stripe decides it against us at ' || d.evidence_due_by || '.',
          p_review_in => interval '4 hours', p_source_agent => 'accountant');
        update public.stripe_dispute set alerted_24h_at = now() where id = d.id;
        n_alert := n_alert + 1;
      elsif v_left <= interval '72 hours' and d.alerted_72h_at is null then
        v_rep := public.fn_support_report_to_ceo('dispute:' || d.id || ':t72', 'serious',
          'Card dispute ' || d.id || ' (AED ' || round(d.amount_fils / 100.0, 2) || ') is unanswered with under 72 hours left',
          to_jsonb(d) - 'demo', '[]'::jsonb,
          'The accountant is submitting the evidence; this is the 72-hour warning. Stripe''s deadline is ' || d.evidence_due_by || '.',
          p_review_in => interval '12 hours', p_source_agent => 'accountant');
        update public.stripe_dispute set alerted_72h_at = now() where id = d.id;
        n_alert := n_alert + 1;
      end if;
      if v_left <= interval '72 hours' or d.submit_error is not null or d.transaction_id is null then
        v_items := v_items || jsonb_build_object('item', d.id, 'owner_seat', 'accountant', 'subject', 'stripe_dispute',
          'title', 'Card dispute ' || d.id || ' on AED ' || round(d.amount_fils / 100.0, 2) || ' is not answered'
                   || case when d.transaction_id is null then ': the books have no sale for payment ' || coalesce(d.payment_intent, '?')
                           when d.submit_error is not null then ': Stripe refused the evidence (' || left(d.submit_error, 120) || ')'
                           else '' end || '; Stripe closes it at ' || to_char(d.evidence_due_by at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai',
          'blast', 'customer_facing', 'affected', 0, 'demo', v_demo, 'evidence', to_jsonb(d) - 'demo');
      end if;
    end if;
  end loop;
  return jsonb_build_object('open', (select count(*) from public.stripe_dispute where closed_at is null),
    'ceo_alerts', n_alert, 'findings', public.fn_accountant_duty_settle('disputes', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_disputes_to_draft()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(public.fn_accountant_dispute_evidence(d.id) order by d.evidence_due_by), '[]'::jsonb)
    from public.stripe_dispute d
   where d.status in ('needs_response', 'warning_needs_response') and d.evidence_submitted_at is null
     and d.draft_saved_at is null and d.closed_at is null
     and (d.evidence_due_by is null or d.evidence_due_by > now()) and d.transaction_id is not null;
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_disputes_to_submit()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('dispute', d.id, 'livemode', d.livemode,
                                               'trigger', public.fn_accountant_dispute_submit_trigger(d.id))
                            order by d.evidence_due_by), '[]'::jsonb)
    from public.stripe_dispute d
   where public.fn_accountant_dispute_submit_trigger(d.id) is not null;
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_draft_entry(p_date date, p_memo text, p_source text, p_ref text, p_lines jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare jid bigint; ln jsonb; i int := 0; v_dr numeric; v_cr numeric;
begin
  select sum(round(coalesce((e->>'debit')::numeric, 0), 2)), sum(round(coalesce((e->>'credit')::numeric, 0), 2))
    into v_dr, v_cr from jsonb_array_elements(p_lines) e;
  if coalesce(v_dr, 0) = 0 or v_dr <> v_cr then
    raise exception 'fn_accountant_draft_entry: a draft must balance (debits %, credits %)', v_dr, v_cr;
  end if;
  select id into jid from public.gl_journal where source = p_source and source_ref = p_ref and status in ('draft', 'posted') limit 1;
  if jid is not null then return jid; end if;
  begin
    insert into public.gl_journal (entry_date, memo, source, source_ref, created_by, status)
    values (p_date, p_memo, p_source, p_ref, 'accountant', 'draft') returning id into jid;
  exception when unique_violation then
    -- a concurrent run wrote it between the check and the insert (gl_journal_one_live_entry_per_bank_or_fee_line)
    select id into jid from public.gl_journal where source = p_source and source_ref = p_ref and status in ('draft', 'posted') limit 1;
    return jid;
  end;
  for ln in select e from jsonb_array_elements(p_lines) e loop
    i := i + 1;
    insert into public.gl_journal_lines (journal_id, line_no, account_code, debit, credit, memo)
    values (jid, i, ln->>'account', round(coalesce((ln->>'debit')::numeric, 0), 2), round(coalesce((ln->>'credit')::numeric, 0), 2), ln->>'memo');
  end loop;
  return jid;
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_dues_aging(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with d as (
    select coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date) - due_date days,
           coalesce(total_claim, amount_due + coalesce(admin_fee, 0) + coalesce(interest_amount, 0)) owed, legal_stage
      from public.supplier_dues
     where public.fn_supplier_due_is_owed(status, paid_at))
  select jsonb_build_object(
    'not_yet_due', jsonb_build_object('n', count(*) filter (where days < 0), 'aed', coalesce(sum(owed) filter (where days < 0), 0)),
    'd0_30',  jsonb_build_object('n', count(*) filter (where days between 0 and 30),  'aed', coalesce(sum(owed) filter (where days between 0 and 30), 0)),
    'd31_60', jsonb_build_object('n', count(*) filter (where days between 31 and 60), 'aed', coalesce(sum(owed) filter (where days between 31 and 60), 0)),
    'd61_90', jsonb_build_object('n', count(*) filter (where days between 61 and 90), 'aed', coalesce(sum(owed) filter (where days between 61 and 90), 0)),
    'over_90', jsonb_build_object('n', count(*) filter (where days > 90), 'aed', coalesce(sum(owed) filter (where days > 90), 0)),
    'in_legal_stage', count(*) filter (where legal_stage is not null),
    'total_aed', coalesce(sum(owed), 0))
  from d;
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_duties(p_r jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare o jsonb := '{}'::jsonb; v_err jsonb := '[]'::jsonb; v_mode text; s jsonb; x jsonb; v_step text; v_rec jsonb;
begin
  if jsonb_typeof(p_r) is distinct from 'object' then
    raise exception 'fn_accountant_duties takes the readings object the accountant runtime assembles';
  end if;

  -- What only Stripe can say, recorded first so the duties below read it.
  begin
    for v_mode in select unnest(array['live', 'test']) loop
      s := p_r->'stripe'->v_mode;
      if coalesce(s->>'basis', '') <> 'measured' then
        o := o || jsonb_build_object('stripe_' || v_mode, jsonb_build_object('basis', coalesce(s->>'basis', 'not_read'), 'reason', s->>'reason'));
        continue;
      end if;
      v_rec := jsonb_build_object(
        'payouts', public.fn_accountant_payouts_record(v_mode = 'live', coalesce(s->'payouts', '[]'::jsonb)),
        'stripe_fees', public.fn_accountant_book_stripe_fees(v_mode = 'live', coalesce(s->'fee_bts', '[]'::jsonb)),
        'disputes', (select coalesce(jsonb_agg(public.fn_accountant_dispute_record(e, v_mode = 'live')), '[]'::jsonb)
                       from jsonb_array_elements(coalesce(s->'disputes', '[]'::jsonb)) e));
      o := o || jsonb_build_object('stripe_' || v_mode, v_rec);
    end loop;
  exception when others then v_err := v_err || jsonb_build_object('step', 'stripe', 'error', sqlerrm); end;

  begin o := o || jsonb_build_object('bank', public.fn_accountant_bank_reconcile());
  exception when others then v_err := v_err || jsonb_build_object('step', 'bank', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('collections', public.fn_accountant_collections_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'collections', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('subscriptions', public.fn_accountant_subscription_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'subscriptions', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('expenses', public.fn_accountant_expense_duty());
  exception when others then v_err := v_err || jsonb_build_object('step', 'expenses', 'error', sqlerrm); end;
  begin
    if jsonb_typeof(p_r->'charge_audit') = 'array' then
      o := o || jsonb_build_object('charge_audit', public.fn_accountant_charge_audit_record(p_r->'charge_audit'));
    else
      o := o || jsonb_build_object('charge_audit', jsonb_build_object('basis', 'not_read'));
    end if;
  exception when others then v_err := v_err || jsonb_build_object('step', 'charge_audit', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('disputes', public.fn_accountant_disputes_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'disputes', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('costs', public.fn_accountant_cost_booking_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'costs', 'error', sqlerrm); end;
  -- owner_card (24 Sep 2026): after costs has posted the month's expenses, restate the ruled subscriptions
  -- at their bank value and raise a missed month (claude_and_chatgpt_are_company_expenses_paid_on_the_owners_card.sql).
  begin o := o || jsonb_build_object('owner_card', public.fn_accountant_owner_card_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'owner_card', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('books', public.fn_accountant_books_duty());
  exception when others then v_err := v_err || jsonb_build_object('step', 'books', 'error', sqlerrm); end;
  -- The five further duties (14 Sep 2026). Ad spend, recovery and renewals run BEFORE the close, which
  -- reads their figures; the bank balance and the year-end pack read the close, so they run after it.
  -- F2 AD SPEND IS HELD FOR THE MARKETING SEAT (founder rule 641, 22 Sep 2026: Meta and social are
  -- wired to no agent until that seat exists). The tick booked Meta spend from meta_insights (2 rows)
  -- into accountant_ad_spend_month (0 rows, measured 22 Sep 2026), so unwiring it changes no figure.
  -- fn_accountant_ad_spend_tick and _figures stay defined, and the close still reads the (empty)
  -- figures. The hold is recorded once, in public.company_policy_decision 'meta_and_social_held_for_marketing'.
  -- G4 (28 Sep 2026): the marketing seat exists and seat_duty accountant.ad_spend_reconcile runs daily; the hold stub is gone.
  o := o || jsonb_build_object('ad_spend', jsonb_build_object('run_by_duty', 'accountant.ad_spend_reconcile',
    'last_ok_at', (select last_ok_at from public.seat_duty where duty = 'accountant.ad_spend_reconcile')));
  begin o := o || jsonb_build_object('recovery', public.fn_accountant_recovery_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'recovery', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('renewals', public.fn_accountant_renewals_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'renewals', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('close', public.fn_accountant_month_close_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'close', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('bank_balance', public.fn_accountant_bank_balance_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'bank_balance', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('year_end', public.fn_accountant_year_end_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'year_end', 'error', sqlerrm); end;
  begin
    o := o || jsonb_build_object('ceo_acknowledged', public.fn_ceo_accountant_reports_sweep(),
                                 'completed', public.fn_accountant_reports_complete());
  exception when others then v_err := v_err || jsonb_build_object('step', 'ceo', 'error', sqlerrm); end;

  foreach v_step in array array['stripe', 'bank', 'collections', 'subscriptions', 'expenses', 'charge_audit', 'disputes', 'costs', 'owner_card', 'books',
                                'recovery', 'renewals', 'close', 'bank_balance', 'year_end', 'ceo'] loop
    perform public.fn_accountant_duty_stage(v_step,
      (select string_agg(e->>'error', '; ') from jsonb_array_elements(v_err) e where e->>'step' = v_step));
  end loop;

  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('accountant', case when jsonb_array_length(v_err) = 0 then 'ok' else 'error' end, now(), now(),
          jsonb_build_object('job', 'duties', 'result', o, 'errors', v_err), null);
  return o || jsonb_build_object('ok', jsonb_array_length(v_err) = 0, 'errors', v_err);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_duties_due()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select not exists (select 1 from public.agent_runs where agent = 'accountant' and counts->>'job' = 'duties'
                      and status = 'ok' and started_at > now() - interval '55 minutes')
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_duty_settle(p_duty text, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare x jsonb; v_keys text[] := '{}'; v_key text; n_closed int := 0; v_open text;
        v_waiting jsonb := '[]'::jsonb; v_receipts_wait boolean;
begin
  if coalesce(btrim(p_duty), '') = '' or jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'fn_accountant_duty_settle(duty, items[]): a duty name and an array of failing items are required';
  end if;
  -- Founder instruction 585 (21 Sep 2026): receipts arrive when he forwards them; a missing one is
  -- the accountant's waiting item, not a founder alarm. Read from the decision register, so the rule
  -- is a reviewable row and lifting it is deleting that row.
  v_receipts_wait := p_duty = 'expenses' and exists (select 1 from public.company_policy_decision d
                       where d.decision_key = 'expenses_receipts_are_an_ongoing_routine');
  for x in select e from jsonb_array_elements(p_items) e loop
    if coalesce(btrim(x->>'item'), '') = '' or coalesce(btrim(x->>'title'), '') = '' then
      raise exception 'fn_accountant_duty_settle: every item needs an item key and a title (%)', x;
    end if;
    if coalesce(x->>'owner_seat', '') not in ('accountant', 'sales_engineer', 'customer_support', 'ceo') then
      raise exception 'fn_accountant_duty_settle: item % names owner seat %, which is not a seat the loop can hand to', x->>'item', x->>'owner_seat';
    end if;
    v_key := 'acct:' || p_duty || ':' || (x->>'item');
    if v_receipts_wait and (x->>'item') in ('cadence_gaps', 'never_billed', 'renewal_receipt') then
      v_waiting := v_waiting || jsonb_build_object('item', x->>'item', 'title', x->>'title', 'evidence', x->'evidence');
      if exists (select 1 from public.it_engineer_finding f where f.issue_key = v_key and f.closed_at is null) then
        perform public.fn_it_engineer_finding_close(v_key,
          'Waiting, not an alarm (founder instruction 585, 21 Sep 2026): receipts are an ongoing routine the '
          || 'founder forwards to the expenses mailbox; the accountant tracks this item in its duty result.');
      end if;
      -- 21 Sep 2026: a loop escalated before the ruling holds an incident with no learning record, and
      -- fn_it_loop_reverify parks it for ever. The ruling IS the record; the IT engineer still closes.
      perform public.fn_accountant_receipt_incident_learning(v_key);
      continue;
    end if;
    v_keys := v_keys || v_key;
    perform public.fn_it_engineer_finding_upsert(v_key, x->>'title', 'Accountant duty: ' || p_duty,
      coalesce(x->>'blast', 'agent_facing'), coalesce((x->>'affected')::int, 1),
      coalesce(x->'evidence', '{}'::jsonb) || jsonb_build_object(
        'duty', p_duty, 'owner_seat', x->>'owner_seat', 'subject', coalesce(x->>'subject', 'accountant'),
        'raised_by_seat', 'accountant', 'demo', coalesce((x->>'demo')::boolean, false)),
      '{}'::text[], '{}'::text[], 'accountant.' || p_duty);
  end loop;
  for v_open in select issue_key from public.it_engineer_finding
                 where closed_at is null and issue_key like 'acct:' || p_duty || ':%' and not (issue_key = any (v_keys)) loop
    perform public.fn_it_engineer_finding_close(v_open, 'the accountant''s ' || p_duty || ' duty re-checked and no longer finds it');
    n_closed := n_closed + 1;
  end loop;
  return jsonb_build_object('duty', p_duty, 'failing', coalesce(array_length(v_keys, 1), 0), 'closed', n_closed,
                            'waiting', v_waiting);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_duty_stage(p_step text, p_error text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if coalesce(btrim(p_step), '') = '' then raise exception 'fn_accountant_duty_stage: a stage name is required'; end if;
  if p_error is null then
    if exists (select 1 from public.it_engineer_finding where issue_key = 'acct:stage:' || p_step and closed_at is null) then
      perform public.fn_it_engineer_finding_close('acct:stage:' || p_step, 'the accountant''s ' || p_step || ' duty ran cleanly');
    end if;
    return;
  end if;
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('accountant', 'error', now(), now(), jsonb_build_object('job', 'duties', 'stage', p_step), left(p_error, 600));
  perform public.fn_it_engineer_finding_upsert('acct:stage:' || p_step,
    'The accountant''s ' || p_step || ' duty is failing', 'public.fn_accountant_duties', 'monitor', 1,
    jsonb_build_object('stage', p_step, 'error', left(p_error, 600), 'owner_seat', 'ceo', 'subject', 'accountant', 'duty', 'stage'),
    '{}'::text[], array['why the duty raises: ' || left(p_error, 300)], 'accountant.stage');
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_expense_duty(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_grace int := (select num_value::int from public.gl_settings where key = 'renewal_receipt_grace_days');
  v_items jsonb := '[]'::jsonb; v_list jsonb; v_n int; v_gaps jsonb; n_next int; v_vouched jsonb; v_demo boolean;
begin
  if v_grace is null then raise exception 'fn_accountant_expense_duty: gl_settings.renewal_receipt_grace_days is missing'; end if;

  -- (a) next_due from the latest receipt, for every recurring cost on a known cadence.
  update public.expenses e
     set next_due = (coalesce(r.last_charged, e.expense_date)
                     + case e.cadence when 'annual' then interval '1 year' else interval '1 month' end)::date
    from (select lower(vendor) v, max(charged_on) last_charged from public.expense_entries group by 1) r
   where e.active and e.cadence in ('monthly', 'annual') and r.v = lower(e.vendor)
     and e.next_due is distinct from (coalesce(r.last_charged, e.expense_date)
                     + case e.cadence when 'annual' then interval '1 year' else interval '1 month' end)::date;
  get diagnostics n_next = row_count;

  -- (b) Booked with no document behind it. 14 Sep 2026: an expense the founder vouched for (doc_kind
  -- 'founder_statement', allowed only on source founder_reported with his words in doc_note — expense 122,
  -- the DET licence: "its ok no need for it. just note down the number of 1200 AED") is documented by his
  -- word and is listed, not asked for. ZZ DEMO expenses are their own finding, so a rehearsal never judges,
  -- or is judged by, a real row (scripts/sql/an_expense_the_founder_vouches_for_is_documented_by_his_word.sql).
  select coalesce(jsonb_agg(jsonb_build_object('entry', id, 'vendor', vendor, 'amount', amount, 'currency', currency,
                                               'statement', doc_note) order by id), '[]'::jsonb)
    into v_vouched from public.expense_entries where coalesce(btrim(doc_path), '') = '' and doc_kind = 'founder_statement';
  foreach v_demo in array array[false, true] loop
    select count(*), coalesce(jsonb_agg(jsonb_build_object('entry', id, 'vendor', vendor, 'charged_on', charged_on,
                                                           'amount', amount, 'currency', currency) order by id), '[]'::jsonb)
      into v_n, v_list from public.expense_entries
     where coalesce(btrim(doc_path), '') = '' and doc_kind is distinct from 'founder_statement'
       -- 19 Oct 2026: the daily OpenRouter accrual is measured from usage; no receipt ever exists for it.
       and coalesce(source, '') <> 'accountant:openrouter_daily'
       and ((coalesce(vendor, '') || ' ' || coalesce(note, '')) ~* 'zz[ _-]?demo') = v_demo;
    if v_n > 0 then
      v_items := v_items || jsonb_build_object('item', case when v_demo then 'no_document:zz_demo' else 'no_document' end,
        'owner_seat', 'accountant', 'subject', 'expense_entries', 'demo', v_demo,
        'title', v_n || case when v_demo then ' ZZ DEMO' else '' end || ' booked expense(s) have no receipt or invoice behind them',
        'blast', 'internal', 'affected', v_n, 'evidence', jsonb_build_object('entries', v_list,
          'documented_by_founder_statement', v_vouched,
          'remedy', 'forward each receipt to expenses@mail.quotesdone.com; the sweep attaches it by vendor, amount and date'));
    end if;
  end loop;

  -- (c) A vendor the founder named that has never been billed through the mailbox.
  select count(*), coalesce(jsonb_agg(v order by v), '[]'::jsonb) into v_n, v_list
    from public.decision_policy d, jsonb_array_elements_text(d.value) v
   where d.key = 'accountant_expected_subscription_vendors'
     and not exists (select 1 from public.expense_entries x where lower(x.vendor) = lower(v))
     and not exists (select 1 from public.vendor_billing_ended b where lower(b.vendor) = lower(v));
  if v_n > 0 then
    v_items := v_items || jsonb_build_object('item', 'never_billed', 'owner_seat', 'accountant', 'subject', 'expenses',
      'title', 'No receipt has ever reached the accountant for ' || v_n || ' of the company''s own subscriptions: '
               || (select string_agg(x, ', ') from jsonb_array_elements_text(v_list) x),
      'blast', 'internal', 'affected', v_n, 'evidence', jsonb_build_object('vendors', v_list,
        'remedy', 'forward one receipt per vendor to expenses@mail.quotesdone.com, or record the vendor in vendor_billing_ended if it bills elsewhere'));
  end if;

  -- (d) A renewal that should have been charged and has no receipt.
  select count(*), coalesce(jsonb_agg(jsonb_build_object('vendor', e.vendor, 'renewed_on', e.next_due, 'amount', e.amount,
                                                         'currency', e.currency, 'cadence', e.cadence) order by e.vendor), '[]'::jsonb)
    into v_n, v_list
    from public.expenses e
   where e.active and e.next_due is not null and e.next_due + v_grace < v_as_of
     and not exists (select 1 from public.expense_entries x where lower(x.vendor) = lower(e.vendor) and x.charged_on >= e.next_due - 3)
     and not exists (select 1 from public.vendor_billing_ended b where lower(b.vendor) = lower(e.vendor));
  if v_n > 0 then
    v_items := v_items || jsonb_build_object('item', 'renewal_receipt', 'owner_seat', 'accountant', 'subject', 'expenses',
      'title', v_n || ' subscription renewal(s) fell due more than ' || v_grace || ' days ago with no receipt',
      'blast', 'internal', 'affected', v_n, 'evidence', jsonb_build_object('renewals', v_list,
        'remedy', 'forward the renewal receipt, or mark the subscription inactive in expenses if it was cancelled'));
  end if;

  -- (e) The vendor-side gaps fn_accountant_receipt_cadence_gaps already measures, now owned.
  v_gaps := public.fn_accountant_receipt_cadence_gaps(v_as_of);
  if coalesce((v_gaps->>'suspected_missing')::int, 0) > 0 then
    v_items := v_items || jsonb_build_object('item', 'cadence_gaps', 'owner_seat', 'accountant', 'subject', 'expense_entries',
      'title', (v_gaps->>'suspected_missing') || ' suspected missing receipt(s): a vendor skipped a month, went quiet, or billed once without a recorded reason',
      'blast', 'internal', 'affected', (v_gaps->>'suspected_missing')::int, 'evidence', v_gaps);
  end if;

  return jsonb_build_object('as_of', v_as_of, 'next_due_updated', n_next,
    'documented_by_founder_statement', v_vouched,
    'findings', public.fn_accountant_duty_settle('expenses', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_files_reveal_invoice()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_doc bigint;
begin
  if new.doc_path is null or new.doc_path !~ '^invoices/' then return new; end if;
  if tg_op = 'UPDATE' and old.doc_path is not distinct from new.doc_path then return new; end if;

  -- (bucket, path) is UNIQUE, so a replayed attach files nothing twice and hands off nothing twice.
  insert into public.documents (bucket, path, file_name, kind, ref_table, ref_id, mime, status)
  values ('finance-docs', new.doc_path,
          coalesce(nullif(new.doc_name, ''), 'Invoice ' || coalesce(new.stripe_invoice_number, '') || '.pdf'),
          'invoice', 'inquiries', new.inquiry_id::text, 'application/pdf', 'done')
  on conflict (bucket, path) do nothing
  returning id into v_doc;
  if v_doc is null then return new; end if;

  perform public.fn_emit('invoice.issued', 'transaction', new.id::text, 'accountant',
    jsonb_build_object('document_id', v_doc, 'quote_id', new.quote_id, 'inquiry_id', new.inquiry_id,
                       'customer_id', new.customer_id, 'invoice_id', new.stripe_invoice_id,
                       'invoice_number', new.stripe_invoice_number, 'total_charged', new.total_charged));

  insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
  values ('sales_engineer', 'handoff', 'pending', 'low',
          'Reveal invoice filed - tell the customer it is ready',
          'The Stripe invoice is in the customer''s Documents and on the revealed quote card.',
          jsonb_build_object('from', 'accountant', 'from_name', 'Accountant', 'subject', 'reveal_invoice',
                             'transaction_id', new.id, 'quote_id', new.quote_id, 'inquiry_id', new.inquiry_id,
                             'customer_id', new.customer_id, 'document_id', v_doc,
                             'invoice_number', new.stripe_invoice_number),
          'transactions', new.id::text);
  return new;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_finance_week()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_week date := date_trunc('week', now() at time zone 'Asia/Dubai')::date; v_key text; v jsonb; v_rep jsonb; v_dec int;
begin
  v_key := 'accountant.finance_week:' || to_char(v_week, 'IYYY-"W"IW');
  if exists (select 1 from public.support_ceo_report where idempotency_key = v_key) then
    return jsonb_build_object('week', v_week, 'already_with_the_ceo', true);
  end if;
  v := jsonb_build_object(
    'cash', jsonb_build_object(
       'bank', (select jsonb_build_object('closing_aed', closing_balance_aed, 'on', balance_on) from public.bank_statement_intake
                 where closing_balance_aed is not null order by balance_on desc, received_at desc limit 1),
       'forecast_13w', (select forecast - 'items' from public.accountant_cash_forecast_week order by week desc limit 1)),
    'collections', jsonb_build_object(
       'supplier_charges_open', (select count(*) from public.v_accountant_recovery_ledger where not demo),
       'supplier_charges_aed', (select coalesce(sum(claim_aed), 0) from public.v_accountant_recovery_ledger where not demo),
       'refunds_open', (select count(*) from public.refunds where status in ('requested', 'approved', 'processing'))),
    'exceptions', jsonb_build_object(
       'receipts_held', (select count(*) from public.inbound_messages where to_email ilike 'expenses@%' and needs_review and replied_at is null),
       'expenses_not_in_ledger', (select count(*) from public.expense_entries x where coalesce(x.amount, 0) > 0
                                    and (coalesce(x.vendor, '') || ' ' || coalesce(x.note, '')) !~* 'zz[ _-]?demo'
                                    and not exists (select 1 from public.gl_journal g where g.source = 'expense' and g.source_ref = x.id::text)),
       'unhealthy_duties', (select coalesce(jsonb_agg(h->>'duty'), '[]') from jsonb_array_elements(public.fn_seat_duty_health()) h where h->>'owner_seat' = 'accountant'),
       'vat', (select to_jsonb(t) - 'recorded_at' from public.accountant_vat_threshold_check t order by checked_on desc limit 1)),
    'decisions_needed', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'subject', r.subject, 'since', r.created_at) order by r.id), '[]')
                           from public.support_ceo_report r where r.source_agent = 'accountant' and r.status in ('sent', 'failed', 'blocked')
                            and r.idempotency_key not like 'accountant.finance_week:%'),
    'weekly_report', (select jsonb_build_object('id', id, 'key', report_key, 'status', status) from public.accountant_weekly_report order by id desc limit 1));
  v_dec := jsonb_array_length(v->'decisions_needed');
  v_rep := public.fn_support_report_to_ceo(v_key, case when v_dec > 0 then 'elevated' else 'routine' end,
    format('Finance week %s: cash, collections, exceptions; %s decision(s) waiting on the CEO', to_char(v_week, 'IYYY-"W"IW'), v_dec),
    v, '[]'::jsonb,
    case when v_dec > 0 then 'Decide the waiting items listed under decisions_needed.' else 'Read and acknowledge the week''s finance position.' end,
    null, null, interval '2 days', 'accountant');
  return jsonb_build_object('week', v_week, 'report', v_rep, 'decisions_needed', v_dec);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_flags_touching(p_customer uuid, p_supplier bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('key', f.kind || ':' || f.subject_type || ':' || f.subject_id,
           'kind', f.kind, 'subject_type', f.subject_type, 'subject_id', f.subject_id, 'severity', f.severity,
           'status', f.status, 'party', case when (f.subject_type = 'customer' and f.subject_id = p_customer::text)
                                                or f.detail->'customer_ids' ? coalesce(p_customer::text, '')
                                                or f.detail->>'customer_id' = p_customer::text then 'customer' else 'supplier' end)
           order by f.kind, f.subject_type, f.subject_id), '[]'::jsonb)
    from public.fraud_flags f
   where f.status in ('open', 'escalated')
     and ((p_customer is not null and ((f.subject_type = 'customer' and f.subject_id = p_customer::text)
                                        or f.detail->'customer_ids' ? p_customer::text
                                        or f.detail->>'customer_id' = p_customer::text))
       or (p_supplier is not null and ((f.subject_type in ('lead', 'supplier') and f.subject_id = p_supplier::text)
                                        or f.detail->'lead_ids' @> to_jsonb(p_supplier)
                                        or f.detail->>'supplier_id' = p_supplier::text
                                        or f.detail->>'hired_supplier_id' = p_supplier::text)))
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_founder_close_pack_attach(p_month date, p_bucket text, p_pdf_path text, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if coalesce(btrim(p_pdf_path), '') = '' then
    update public.accountant_founder_close_pack set render_error = coalesce(p_error, 'no PDF path') where month = date_trunc('month', p_month)::date;
    return jsonb_build_object('ok', false, 'month', to_char(p_month, 'YYYY-MM'), 'error', coalesce(p_error, 'no PDF path'));
  end if;
  update public.accountant_founder_close_pack
     set pdf_bucket = p_bucket, pdf_path = p_pdf_path, rendered_at = now(), render_error = null
   where month = date_trunc('month', p_month)::date;
  if not found then raise exception 'no close pack is built for %', to_char(p_month, 'YYYY-MM'); end if;
  return public.fn_accountant_founder_close_pack_send(p_month);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_founder_close_pack_build(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_m date := date_trunc('month', p_month)::date; v_f jsonb;
begin
  if exists (select 1 from public.accountant_founder_close_pack where month = v_m) then
    return jsonb_build_object('ok', true, 'month', to_char(v_m, 'YYYY-MM'), 'already_built', true);
  end if;
  v_f := public.fn_accountant_founder_close_pack_figures(v_m);   -- refuses an open month
  insert into public.accountant_founder_close_pack (month, figures) values (v_m, v_f);
  return jsonb_build_object('ok', true, 'month', to_char(v_m, 'YYYY-MM'), 'built', true,
                            'bank', v_f#>>'{bank,status}', 'unusual_items', v_f->'unusual_items', 'unexplained_items', v_f->'unexplained_items');
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_founder_close_pack_document(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare f jsonb; v_title text; v_pnl jsonb; v_unu jsonb; v_n numeric;
begin
  select figures into f from public.accountant_founder_close_pack where month = date_trunc('month', p_month)::date;
  if f is null then raise exception 'no close pack is built for %', to_char(p_month, 'YYYY-MM'); end if;
  v_title := 'QuotesDone close pack ' || (f->>'month');
  select coalesce(jsonb_agg(jsonb_build_array(e->>'code' || ' ' || (e->>'name'), e->>'actual_aed', coalesce(e->>'budget_aed', '-'),
                            coalesce(e->>'variance_aed', '-') || coalesce(' (' || (e->>'variance_pct') || '%)', '')) order by e->>'code'), '[]'::jsonb)
    into v_pnl from jsonb_array_elements(f#>'{pnl_vs_budget,accounts}') e;
  select coalesce(jsonb_agg(jsonb_build_array(
           u->>'rule' || coalesce(' ' || (u->>'account'), ''), coalesce(u->>'amount_aed', '-'),
           case when (u->>'explained')::boolean
                then coalesce(u->>'explanation', (select string_agg(coalesce(jj->>'journal', '') || ': ' || (jj->>'memo'), '; ') from jsonb_array_elements(u->'journals') jj))
                else 'UNEXPLAINED: ' || coalesce((select string_agg(jj->>'journal', ', ') from jsonb_array_elements(u->'journals') jj where jj->>'memo' is null), 'no journal') || ' has no memo' end)), '[]'::jsonb)
    into v_unu from jsonb_array_elements(f->'unusual') u;
  v_n := jsonb_array_length(v_unu);
  return jsonb_build_object('month', f->>'month', 'title', v_title, 'name', 'QuotesDone_Close_Pack_' || (f->>'month'),
    'blocks', jsonb_build_array(
      jsonb_build_object('t', 'h2', 'text', v_title),
      jsonb_build_object('t', 'p', 'text', 'Period ' || (f->>'from') || ' to ' || (f->>'to') || ', read from the closed and locked month. Nothing is estimated; a figure the books do not hold prints as missing.'),
      jsonb_build_object('t', 'h3', 'text', '1. Bank against the Mashreq statement'),
      jsonb_build_object('t', 'table', 'head', jsonb_build_array('Item', 'AED'), 'widths', jsonb_build_array(0.65, 0.35), 'rows', jsonb_build_array(
        jsonb_build_array('Statement closing balance (' || coalesce(f#>>'{bank,statement_balance_on}', 'missing') || ')', coalesce(f#>>'{bank,statement_closing_aed}', 'missing')),
        jsonb_build_array('Books, account 1000', f#>>'{bank,gl_1000_aed}'),
        jsonb_build_array('Statement lines not yet booked', f#>>'{bank,unbooked_aed}'),
        jsonb_build_array('Booked, not on the statement', f#>>'{bank,book_only_aed}'),
        jsonb_build_array('Unexplained', coalesce(f#>>'{bank,unexplained_aed}', 'missing')),
        jsonb_build_array('Status', f#>>'{bank,status}'))),
      jsonb_build_object('t', 'h3', 'text', '2. VAT position'),
      jsonb_build_object('t', 'p', 'text', 'Not VAT-registered. Rolling 12-month turnover AED ' || coalesce(f#>>'{vat,turnover_aed}', 'missing')
        || coalesce(' of the AED ' || (f#>>'{vat,threshold_aed}') || ' threshold', '') || coalesce(' (' || (f#>>'{vat,band}') || ')', '') || '.'),
      jsonb_build_object('t', 'h3', 'text', '3. Profit and loss against budget'),
      jsonb_build_object('t', 'table', 'head', jsonb_build_array('Account', 'Actual', 'Budget', 'Variance'),
                         'widths', jsonb_build_array(0.43, 0.17, 0.17, 0.23), 'rows', v_pnl || jsonb_build_array(
        jsonb_build_array('Net result', f#>>'{pnl_vs_budget,net_actual_aed}', f#>>'{pnl_vs_budget,net_budget_aed}',
          ((f#>>'{pnl_vs_budget,net_actual_aed}')::numeric - (f#>>'{pnl_vs_budget,net_budget_aed}')::numeric)::text))),
      jsonb_build_object('t', 'h3', 'text', '4. Cash runway'),
      jsonb_build_object('t', 'table', 'head', jsonb_build_array('Item', 'Value'), 'widths', jsonb_build_array(0.65, 0.35), 'rows', jsonb_build_array(
        jsonb_build_array('Available cash (AED)', coalesce(f#>>'{runway,available_aed}', 'missing')),
        jsonb_build_array('Runway at actual spend (months)', coalesce(f#>>'{runway,runway_months_at_actual_spend}', 'missing')),
        jsonb_build_array('Runway at budget (months)', coalesce(f#>>'{runway,runway_months_at_budget}', 'missing')))),
      jsonb_build_object('t', 'h3', 'text', '5. Unusual items (' || v_n || ', ' || (f->>'unexplained_items') || ' unexplained)'),
      case when v_n = 0 then jsonb_build_object('t', 'p', 'text', 'None under the rules: variance past ' || (f#>>'{rules,variance_pct}') || '% and AED '
                                                || (f#>>'{rules,variance_min_aed}') || ', a line of AED ' || (f#>>'{rules,large_line_aed}') || ' or more, a reversal, a prior-period adjustment, an unbooked statement line.')
           else jsonb_build_object('t', 'table', 'head', jsonb_build_array('Item', 'AED', 'Explanation'), 'widths', jsonb_build_array(0.25, 0.15, 0.6), 'rows', v_unu) end,
      jsonb_build_object('t', 'note', 'text', 'Prepared by the QuotesDone accountant from gl_journal, bank_statement_line/intake, budget_lines and the month close. Informational; nothing here needs your approval.')));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_founder_close_pack_figures(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_m date := date_trunc('month', p_month)::date;
  v_end date := (date_trunc('month', p_month) + interval '1 month' - interval '1 day')::date;
  v_close jsonb; v_stmt record; v_gl numeric; v_unbooked numeric; v_bookonly numeric; v_rest numeric;
  v_unb jsonb; v_bo jsonb; v_pnl jsonb; v_unusual jsonb := '[]'::jsonb; v_pct numeric; v_min numeric; v_large numeric;
  r record; v_bank jsonb; v_ppa jsonb;
begin
  select figures into v_close from public.accountant_month_close where month = v_m;
  if v_close is null then
    raise exception 'month % is not closed: a close pack is built only for a closed, locked month', to_char(v_m, 'YYYY-MM');
  end if;
  select coalesce(max(num_value) filter (where key = 'close_pack_variance_pct'), 25),
         coalesce(max(num_value) filter (where key = 'close_pack_variance_min_aed'), 200),
         coalesce(max(num_value) filter (where key = 'close_pack_large_line_aed'), 1000)
    into v_pct, v_min, v_large from public.gl_settings
   where key in ('close_pack_variance_pct', 'close_pack_variance_min_aed', 'close_pack_large_line_aed');

  -- BANK: the books' bank account at month end against the Mashreq statement of that month.
  select * into v_stmt from public.bank_statement_intake
   where account = 'mashreq' and statement_month = v_m and closing_balance_aed is not null
   order by received_at desc limit 1;
  select coalesce(sum(l.debit - l.credit), 0) into v_gl
    from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id and j.status = 'posted'
   where l.account_code = '1000' and j.entry_date <= v_end;
  -- statement lines to month end that no posted journal books
  select coalesce(sum(b.amount_aed), 0),
         coalesce(jsonb_agg(jsonb_build_object('line_id', b.id, 'date', b.value_date, 'amount_aed', b.amount_aed, 'kind', b.kind,
                                               'description', b.description) order by b.value_date, b.id), '[]'::jsonb)
    into v_unbooked, v_unb
    from public.bank_statement_line b
   where b.account = 'mashreq' and b.value_date <= v_end
     and not exists (select 1 from public.gl_journal g
                      where g.status = 'posted' and g.source in ('bank_charge', 'bank_interest', 'owner_capital')
                        and g.source_ref = b.id::text);
  -- GL 1000 postings to month end that came from no statement line
  select coalesce(sum(l.debit - l.credit), 0),
         coalesce(jsonb_agg(jsonb_build_object('journal', j.entry_no, 'date', j.entry_date, 'amount_aed', l.debit - l.credit,
                                               'source', j.source, 'memo', coalesce(nullif(btrim(l.memo), ''), j.memo))
                            order by j.entry_date, j.id), '[]'::jsonb)
    into v_bookonly, v_bo
    from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id and j.status = 'posted'
   where l.account_code = '1000' and j.entry_date <= v_end
     and not (j.source in ('bank_charge', 'bank_interest', 'owner_capital')
              and exists (select 1 from public.bank_statement_line b where b.account = 'mashreq' and b.id::text = j.source_ref));
  v_rest := case when v_stmt.closing_balance_aed is not null
                 then round(v_stmt.closing_balance_aed - (v_gl + v_unbooked - v_bookonly), 2) end;
  v_bank := jsonb_build_object(
    'statement_closing_aed', v_stmt.closing_balance_aed, 'statement_balance_on', v_stmt.balance_on,
    'statement_source', v_stmt.source_ref, 'gl_1000_aed', round(v_gl, 2),
    'difference_aed', case when v_stmt.closing_balance_aed is not null then round(v_stmt.closing_balance_aed - v_gl, 2) end,
    'unbooked_statement_lines', v_unb, 'unbooked_aed', round(v_unbooked, 2),
    'book_only_postings', v_bo, 'book_only_aed', round(v_bookonly, 2),
    'unexplained_aed', v_rest,
    'status', case when v_stmt.closing_balance_aed is null then 'missing: no Mashreq statement with a closing balance for ' || to_char(v_m, 'YYYY-MM')
                   when abs(v_rest) <= 0.01 then 'reconciled' else 'not reconciled' end);

  -- P&L AGAINST BUDGET, per account that has either an actual or a budget line.
  with act as (
    select account_code as code, sum(revenue_aed) as actual from public.gl_revenue_lines_measured
     where entry_date between v_m and v_end group by 1
    union all
    select l.account_code, sum(l.debit - l.credit)
      from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id and j.status = 'posted'
      join public.gl_accounts a on a.code = l.account_code and a.type = 'expense'
     where j.entry_date between v_m and v_end group by 1),
  bud as (
    select l.account_code as code, sum(l.amount) as budget
      from public.budget_lines l join public.budgets b on b.id = l.budget_id and b.status = 'active'
     where l.period_month = v_m group by 1),
  x as (
    select a.code, a.name, a.type, round(coalesce(act.actual, 0), 2) as actual, bud.budget
      from public.gl_accounts a left join act on act.code = a.code left join bud on bud.code = a.code
     where a.type in ('revenue', 'expense') and (act.code is not null or bud.code is not null))
  select jsonb_build_object(
           'accounts', coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name, 'type', type, 'actual_aed', actual,
                         'budget_aed', budget, 'variance_aed', case when budget is not null then round(actual - budget, 2) end,
                         'variance_pct', case when coalesce(budget, 0) <> 0 then round((actual - budget) / abs(budget) * 100, 1) end)
                       order by code), '[]'::jsonb),
           'revenue_actual_aed', coalesce(sum(actual) filter (where type = 'revenue'), 0),
           'revenue_budget_aed', coalesce(sum(budget) filter (where type = 'revenue'), 0),
           'expense_actual_aed', coalesce(sum(actual) filter (where type = 'expense'), 0),
           'expense_budget_aed', coalesce(sum(budget) filter (where type = 'expense'), 0),
           'net_actual_aed', coalesce(sum(actual) filter (where type = 'revenue'), 0) - coalesce(sum(actual) filter (where type = 'expense'), 0),
           'net_budget_aed', coalesce(sum(budget) filter (where type = 'revenue'), 0) - coalesce(sum(budget) filter (where type = 'expense'), 0),
           'budget_lines', count(budget))
    into v_pnl from x;

  -- UNUSUAL ITEMS, by rule. The explanation is the memo on the journals that make the item.
  for r in select e from jsonb_array_elements(v_pnl->'accounts') e
            where abs(coalesce((e->>'actual_aed')::numeric, 0) - coalesce((e->>'budget_aed')::numeric, 0)) >= v_min
              and (coalesce((e->>'budget_aed')::numeric, 0) = 0 or abs((e->>'variance_pct')::numeric) >= v_pct) loop
    v_unusual := v_unusual || jsonb_build_object('rule', 'budget_variance', 'account', r.e->>'code', 'name', r.e->>'name',
      'amount_aed', coalesce((r.e->>'actual_aed')::numeric, 0) - coalesce((r.e->>'budget_aed')::numeric, 0),
      'journals', (select coalesce(jsonb_agg(jsonb_build_object('journal', j.entry_no, 'amount_aed', l.debit - l.credit,
                          'memo', coalesce(nullif(btrim(l.memo), ''), nullif(btrim(j.memo), ''))) order by j.entry_date, l.id), '[]'::jsonb)
                     from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id and j.status = 'posted'
                    where l.account_code = r.e->>'code' and j.entry_date between v_m and v_end));
  end loop;
  for r in select j.entry_no, l.account_code, l.debit, l.credit, coalesce(nullif(btrim(l.memo), ''), nullif(btrim(j.memo), '')) as memo
             from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id and j.status = 'posted'
             join public.gl_accounts a on a.code = l.account_code and a.type in ('revenue', 'expense')
            where j.entry_date between v_m and v_end and greatest(l.debit, l.credit) >= v_large
            order by j.entry_date, l.id loop
    v_unusual := v_unusual || jsonb_build_object('rule', 'large_line', 'account', r.account_code, 'amount_aed', greatest(r.debit, r.credit),
      'journals', jsonb_build_array(jsonb_build_object('journal', r.entry_no, 'amount_aed', r.debit - r.credit, 'memo', r.memo)));
  end loop;
  -- A reversal is the journal fn_gl_reverse writes (source 'reversal', source_ref = the original's id), dated in the
  -- month, in ANY status: fn_gl_reverse voids both sides, so a posted-only rule never fired (re-review of #1063).
  for r in select coalesce(j.entry_no, 'journal ' || j.id) as entry_no, j.memo, j.status,
                  coalesce(o.entry_no, 'journal ' || o.id) as original,
                  (select sum(l.debit) from public.gl_journal_lines l where l.journal_id = j.id) as amount
             from public.gl_journal j
             left join public.gl_journal o on o.id = coalesce(j.reverses, case when j.source_ref ~ '^[0-9]+$' then j.source_ref::bigint end)
            where j.source = 'reversal' and j.entry_date between v_m and v_end order by j.entry_date, j.id loop
    v_unusual := v_unusual || jsonb_build_object('rule', 'reversal', 'reverses', r.original, 'status', r.status, 'amount_aed', r.amount,
      'journals', jsonb_build_array(jsonb_build_object('journal', r.entry_no, 'memo', nullif(btrim(r.memo), ''))));
  end loop;
  -- a late item for a month already closed, booked in this month (fn_gl_post, gl_prior_period_adjustment)
  select coalesce(jsonb_agg(jsonb_build_object('journal', j.entry_no, 'posted_on', a.posted_on, 'original_date', a.original_date,
                            'closed_month', to_char(a.closed_month, 'YYYY-MM'), 'statement_line_id', a.statement_line_id,
                            'source', a.source, 'amount_aed', a.amount_aed, 'memo', nullif(btrim(j.memo), ''))
                            order by a.posted_on, a.journal_id), '[]'::jsonb)
    into v_ppa
    from public.gl_prior_period_adjustment a join public.gl_journal j on j.id = a.journal_id and j.status = 'posted'
   where a.posted_on between v_m and v_end;
  for r in select e from jsonb_array_elements(v_ppa) e loop
    v_unusual := v_unusual || jsonb_build_object('rule', 'prior_period_adjustment', 'amount_aed', (r.e->>'amount_aed')::numeric,
      'journals', jsonb_build_array(jsonb_build_object('journal', r.e->>'journal', 'memo', r.e->>'memo')),
      'explanation', (r.e->>'journal') || ': dated ' || (r.e->>'original_date') || ' in ' || (r.e->>'closed_month') || ', which was already closed'
                     || coalesce(' (statement line ' || (r.e->>'statement_line_id') || ')', '')
                     || '; booked in this month as a prior-period adjustment (IFRS for SMEs Section 10: an immaterial prior-period item is corrected in the current period)');
  end loop;
  for r in select e from jsonb_array_elements(v_unb) e where (e->>'date')::date between v_m and v_end loop
    v_unusual := v_unusual || jsonb_build_object('rule', 'unbooked_statement_line', 'amount_aed', (r.e->>'amount_aed')::numeric,
      'journals', '[]'::jsonb, 'explanation', 'statement line ' || (r.e->>'line_id') || ' (' || coalesce(r.e->>'description', '') || ') has no posted journal');
  end loop;
  -- an item is explained when it names its cause: every journal it lists carries a memo, or it states its own
  select coalesce(jsonb_agg(u || jsonb_build_object('explained',
           coalesce(u ? 'explanation', false)
           or (jsonb_array_length(u->'journals') > 0 and not exists (select 1 from jsonb_array_elements(u->'journals') jj where jj->>'memo' is null)))), '[]'::jsonb)
    into v_unusual from jsonb_array_elements(v_unusual) u;

  return jsonb_build_object(
    'month', to_char(v_m, 'YYYY-MM'), 'from', v_m, 'to', v_end, 'built_from', 'the closed month (period locked)',
    'bank', v_bank,
    'vat', coalesce(v_close->'vat', '{}'::jsonb) || jsonb_build_object('registered', false,
             'note', 'QuotesDone is not VAT-registered; registration is required only past the threshold (fn_vat_threshold_position).'),
    'pnl_vs_budget', v_pnl,
    'runway', public.fn_accountant_runway_figures(v_m) - 'cash_13_weeks',
    'prior_period_adjustments', v_ppa,
    'unusual', v_unusual,
    'unusual_items', jsonb_array_length(v_unusual),
    'unexplained_items', (select count(*) from jsonb_array_elements(v_unusual) u where not (u->>'explained')::boolean),
    'rules', jsonb_build_object('variance_pct', v_pct, 'variance_min_aed', v_min, 'large_line_aed', v_large));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_founder_close_pack_send(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare p public.accountant_founder_close_pack; v_before bigint; v_res jsonb; v_nid bigint; f jsonb;
begin
  select * into p from public.accountant_founder_close_pack where month = date_trunc('month', p_month)::date for update;
  if p.month is null then raise exception 'no close pack is built for %', to_char(p_month, 'YYYY-MM'); end if;
  if p.sent_at is not null then return jsonb_build_object('ok', true, 'already_sent', p.sent_at, 'notification_id', p.notification_id); end if;
  if p.pdf_path is null then return jsonb_build_object('ok', false, 'reason', 'the PDF is not rendered yet'); end if;
  f := p.figures;
  select coalesce(max(id), 0) into v_before from public.notifications;
  v_res := public.fn_notify_founder(
    p_event => 'Close pack ' || (f->>'month') || ': net AED ' || (f#>>'{pnl_vs_budget,net_actual_aed}') || ' against budget AED ' || (f#>>'{pnl_vs_budget,net_budget_aed}'),
    p_detail => 'Your close pack for ' || (f->>'month') || ' is attached (one PDF).' || E'\n'
      || 'Bank against the Mashreq statement: ' || (f#>>'{bank,status}') || '.' || E'\n'
      || 'Runway: ' || coalesce((f#>>'{runway,runway_months_at_actual_spend}') || ' months at actual spend', 'missing') || '.' || E'\n'
      || 'Unusual items: ' || (f->>'unusual_items') || ' (' || (f->>'unexplained_items') || ' unexplained).' || E'\n'
      || 'Nothing here needs your approval.',
    p_level => 'info', p_kind => 'accountant_close_pack',
    p_dedupe_key => 'accountant_close_pack:' || (f->>'month'), p_owner_agent => 'accountant');
  select id into v_nid from public.notifications
   where id > v_before and type = 'founder_alert' and kind = 'accountant_close_pack' and channel = 'email'
   order by id limit 1;
  if v_nid is null then
    update public.accountant_founder_close_pack set send_result = v_res where month = p.month;
    return jsonb_build_object('ok', false, 'reason', 'fn_notify_founder queued no email', 'notify', v_res);
  end if;
  update public.notifications
     set attachments = jsonb_build_array(jsonb_build_object('bucket', p.pdf_bucket, 'path', p.pdf_path,
                                                            'filename', 'QuotesDone_Close_Pack_' || (f->>'month') || '.pdf'))
   where id = v_nid;
  update public.accountant_founder_close_pack set sent_at = now(), notification_id = v_nid, send_result = v_res where month = p.month;
  return jsonb_build_object('ok', true, 'month', f->>'month', 'notification_id', v_nid, 'notify', v_res);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_founder_close_pack_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_local date := (now() at time zone 'Asia/Dubai')::date; v_prev date; v_b jsonb; v_s jsonb; p public.accountant_founder_close_pack; v_rep jsonb;
        v_close jsonb;
begin
  v_prev := (date_trunc('month', v_local) - interval '1 month')::date;
  -- the pack follows the close: a month waiting for its Mashreq statement is waiting, not missed, and a statement
  -- that arrived after the 3rd moves the due date to two days after it (fn_accountant_month_close_status)
  v_close := public.fn_accountant_month_close_status(v_prev, v_local);
  if exists (select 1 from public.accountant_month_close where month = v_prev) then
    v_b := public.fn_accountant_founder_close_pack_build(v_prev);
  end if;
  select * into p from public.accountant_founder_close_pack where month = v_prev;
  if p.month is not null and p.sent_at is null and p.pdf_path is not null then
    v_s := public.fn_accountant_founder_close_pack_send(v_prev);
    select * into p from public.accountant_founder_close_pack where month = v_prev;
  end if;
  if p.sent_at is null and v_close->>'status' <> 'waiting_for_statement'
     and v_local > coalesce((v_close->>'due_by')::date, (v_prev + interval '1 month' + interval '4 days')::date) then
    v_rep := public.fn_support_report_to_ceo(
      p_idempotency_key => 'accountant_close_pack_day5:' || to_char(v_prev, 'YYYY-MM'), p_severity => 'elevated',
      p_subject => 'The founder''s ' || to_char(v_prev, 'Mon YYYY') || ' close pack was not sent by ' || coalesce(v_close->>'due_by', 'day 5'),
      p_evidence => jsonb_build_object('month', to_char(v_prev, 'YYYY-MM'), 'close', v_close,
                                       'built_at', p.built_at, 'rendered_at', p.rendered_at, 'render_error', p.render_error, 'send_result', p.send_result),
      p_attempted => '[]'::jsonb,
      p_requested => 'None from you: the accountant builds, renders and sends it on its next tick; this records the missed day.',
      p_review_in => interval '30 days', p_source_agent => 'accountant');
  end if;
  return jsonb_build_object('month', to_char(v_prev, 'YYYY-MM'), 'close_status', v_close->>'status', 'due_by', v_close->'due_by',
                            'build', v_b, 'send', v_s, 'sent_at', p.sent_at,
                            'late_reported', v_rep is not null);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_fraud_watch_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  r record; v_dup int := 0; v_sig int := 0; v_filed int := 0;
begin
  create temp table if not exists tmp_fraud_new (kind text, subject_type text, subject_id text, severity text, detail jsonb) on commit drop;
  truncate tmp_fraud_new;

  -- ── duplicates: equality of normalised identifiers ──
  insert into tmp_fraud_new
  select 'dup_customer_phone', 'cphone', k, 'medium', jsonb_build_object('customer_ids', ids, 'count', n)
    from (select right(regexp_replace(c.phone, '\D', '', 'g'), 9) k, jsonb_agg(c.id order by c.id) ids, count(*) n
            from public.customers c
           where length(regexp_replace(coalesce(c.phone, ''), '\D', '', 'g')) >= 9
             and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
           group by 1 having count(*) > 1) x;
  insert into tmp_fraud_new
  select 'dup_customer_email', 'cemail', k, 'medium', jsonb_build_object('customer_ids', ids, 'count', n)
    from (select regexp_replace(lower(btrim(c.email)), '[+][^@]*@', '@') k, jsonb_agg(c.id order by c.id) ids, count(*) n
            from public.customers c
           where position('@' in coalesce(c.email, '')) > 1
             and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
           group by 1 having count(*) > 1) x;
  insert into tmp_fraud_new
  select 'duplicate_license', 'licence', k, 'high', jsonb_build_object('lead_ids', ids, 'count', n)
    from (select upper(regexp_replace(l.trade_license_no, '[^A-Za-z0-9]', '', 'g')) k, jsonb_agg(l.id order by l.id) ids, count(*) n
            from public.leads l
           where length(regexp_replace(coalesce(l.trade_license_no, ''), '[^A-Za-z0-9]', '', 'g')) >= 4
             and (l.lifecycle_stage = 'registered' or l.approval_status is not null)
             and (coalesce(l.is_demo, false) or coalesce(l.company_name, '') like 'ZZ DEMO%' or public.fn_is_demo_email(l.email)) = v_fx
           group by 1 having count(*) > 1) x;
  insert into tmp_fraud_new
  select 'dup_trn', 'trn', k, 'high', jsonb_build_object('lead_ids', ids, 'count', n)
    from (select regexp_replace(l.trn, '\D', '', 'g') k, jsonb_agg(l.id order by l.id) ids, count(*) n
            from public.leads l
           where length(regexp_replace(coalesce(l.trn, ''), '\D', '', 'g')) = 15
             and (coalesce(l.is_demo, false) or coalesce(l.company_name, '') like 'ZZ DEMO%' or public.fn_is_demo_email(l.email)) = v_fx
           group by 1 having count(*) > 1) x;
  insert into tmp_fraud_new
  select 'customer_matches_supplier', 'customer', c.id::text, 'high',
         jsonb_build_object('lead_ids', jsonb_agg(distinct l.id), 'on', jsonb_agg(distinct m.what))
    from public.customers c
    join public.leads l on (coalesce(l.is_demo, false) or coalesce(l.company_name, '') like 'ZZ DEMO%' or public.fn_is_demo_email(l.email)) = v_fx
    cross join lateral (select 'phone' as what
                         where length(regexp_replace(coalesce(c.phone, ''), '\D', '', 'g')) >= 9
                           and right(regexp_replace(c.phone, '\D', '', 'g'), 9)
                               in (right(regexp_replace(coalesce(l.phone_e164, ''), '\D', '', 'g'), 9),
                                   right(regexp_replace(coalesce(l.phone, ''), '\D', '', 'g'), 9))
                        union all
                        select 'email' where lower(btrim(coalesce(c.email, ''))) <> ''
                           and lower(btrim(c.email)) in (lower(btrim(coalesce(l.email, ''))), lower(btrim(coalesce(l.claimed_by, ''))))) m
   where (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
   group by c.id;

  -- ── circumvention signals: each a measurable fact about money not reaching the platform ──
  insert into tmp_fraud_new
  select 'hired_without_fee', 'inquiry', i.id::text, 'high',
         jsonb_build_object('inquiry_id', i.id, 'hired_supplier_id', i.hired_supplier_id, 'customer_id', i.customer_id,
                            'completed_at', i.completed_at, 'outcome', i.outcome)
    from public.inquiries i join public.customers c on c.id = i.customer_id
   where i.hired_supplier_id is not null
     and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
     and not exists (select 1 from public.transactions t where t.inquiry_id = i.id and t.supplier_id = i.hired_supplier_id
                        and t.fee_status = 'paid' and t.refund_confirmed_at is null);
  insert into tmp_fraud_new
  select 'refund_after_supplier_contact', 'transaction', t.id::text, 'high',
         jsonb_build_object('transaction_id', t.id, 'supplier_id', t.supplier_id, 'customer_id', t.customer_id,
                            'revealed_at', t.revealed_at, 'supplier_ack_at', t.supplier_ack_at,
                            'refund_requested_at', t.refund_requested_at, 'refund_confirmed_at', t.refund_confirmed_at)
    from public.transactions t join public.customers c on c.id = t.customer_id
   where t.refund_confirmed_at is not null and t.supplier_ack_at is not null
     and t.supplier_ack_at < coalesce(t.refund_requested_at, t.refund_confirmed_at)
     and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx;
  insert into tmp_fraud_new
  select 'silent_after_reveal', 'transaction', t.id::text, 'medium',
         jsonb_build_object('transaction_id', t.id, 'supplier_id', t.supplier_id, 'customer_id', t.customer_id,
                            'revealed_at', t.revealed_at, 'days_silent', extract(day from now() - t.revealed_at)::int)
    from public.transactions t join public.customers c on c.id = t.customer_id
    left join public.inquiries i on i.id = t.inquiry_id
   where t.fee_status = 'paid' and t.revealed_at < now() - interval '60 days' and t.refund_confirmed_at is null
     and i.completed_at is null and i.outcome is null
     and not exists (select 1 from public.inquiries i2 where i2.customer_id = t.customer_id and i2.created_at > t.revealed_at)
     and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx;

  -- ── write each once; a flag a person closed is never re-opened ──
  for r in select * from tmp_fraud_new loop
    insert into public.fraud_flags (kind, subject_type, subject_id, severity, detail, status, created_at, updated_at)
    values (r.kind, r.subject_type, r.subject_id, r.severity, r.detail || jsonb_build_object('raised_by', 'accountant'), 'open', now(), now())
    on conflict (kind, subject_type, subject_id) do nothing;
    if not found then continue; end if;
    if r.kind in ('hired_without_fee', 'refund_after_supplier_contact', 'silent_after_reveal') then
      v_sig := v_sig + 1;
      perform public.fn_seat_duty_reason('accountant', 'accountant.circumvention',
        case when v_fx then 'ZZ DEMO ' else '' end
        || 'A measured signal suggests a customer and a supplier may have completed a job without the platform''s fee. On the facts, is this fee circumvention?',
        jsonb_build_array(
          jsonb_build_object('id', 'circumvention', 'meaning', 'the parties most likely dealt directly to avoid the fee; the CEO should act'),
          jsonb_build_object('id', 'benign', 'meaning', 'the facts have an ordinary explanation (the job fell through, a refund was due, the customer simply stopped)'),
          jsonb_build_object('id', 'insufficient_evidence', 'meaning', 'the facts cannot tell; keep the flag open and watch')),
        jsonb_build_object('signal', r.kind, 'subject_type', r.subject_type, 'subject_id', r.subject_id, 'facts', r.detail),
        jsonb_build_object('kind', r.kind, 'subject_type', r.subject_type, 'subject_id', r.subject_id),
        'circumvention:' || r.kind || ':' || r.subject_id);
      v_filed := v_filed + 1;
    else
      v_dup := v_dup + 1;
    end if;
  end loop;
  return jsonb_build_object('duplicates_flagged', v_dup, 'signals_flagged', v_sig, 'reasoning_filed', v_filed);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_incident_fix_failed(p_id bigint, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions;
begin
  update public.agent_actions
     set status = 'failed', decided_at = now(), detail = detail || jsonb_build_object('error', left(p_reason, 500), 'failed_at', now())
   where id = p_id and kind = 'handoff' and detail->>'type' = 'incident.fix' and status = 'pending'
  returning * into a;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no pending incident fix ' || p_id); end if;
  perform public.fn_seat_handoff_event(p_id, 'failed');
  -- A duplicate Stripe will not cancel is money gone: book it as the company's loss.
  if a.detail->>'fix' = 'cancel_duplicate' then
    perform public.fn_seat_handoff('ceo', 'accountant', 'incident.fix', 'refund_incident', (a.detail->>'incident_id') || ':book_over_refund_loss',
      jsonb_build_object('incident_id', a.detail->>'incident_id', 'transaction_id', a.detail->>'transaction_id',
                         'fix', 'book_over_refund_loss', 'amount_aed', a.detail->>'excess_aed'));
  end if;
  return jsonb_build_object('ok', true, 'advance', public.fn_ceo_incident_advance((a.detail->>'incident_id')::bigint));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_keeps_reported_ad_spend(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions; d jsonb; v_test boolean; v_fx numeric; v_aed numeric; v_recorded boolean := false;
        v_month date; v_pos jsonb; v_inv jsonb; v_bid bigint; v_meta_month numeric;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' is distinct from 'adspend.recorded' then
    raise exception 'fn_accountant_keeps_reported_ad_spend: % is not an adspend.recorded handoff', p_id;
  end if;
  d := a.detail;
  v_test := coalesce((d->>'test')::boolean, false) or coalesce(d->>'source_ref', '') ~* 'zz[ _-]?demo';
  v_fx := coalesce((select num_value from public.gl_settings where key = 'usd_to_aed'), 3.6725);
  v_aed := case d->>'currency' when 'AED' then (d->>'amount')::numeric
                               when 'USD' then round((d->>'amount')::numeric * v_fx, 2) end;
  v_month := date_trunc('month', (d->>'spend_date')::date)::date;

  if not v_test then
    insert into public.ad_spend_reported (source_ref, platform, spend_date, currency, amount, amount_aed, campaign_ref, handoff_id)
    values (d->>'source_ref', d->>'platform', (d->>'spend_date')::date, d->>'currency', (d->>'amount')::numeric, v_aed,
            nullif(d->>'campaign_ref', ''), p_id)
    on conflict (source_ref) do update
      set amount = excluded.amount, amount_aed = excluded.amount_aed, currency = excluded.currency,
          spend_date = excluded.spend_date, campaign_ref = excluded.campaign_ref, handoff_id = excluded.handoff_id,
          revisions = ad_spend_reported.revisions + 1, updated_at = now();
    v_recorded := true;
  end if;

  select jsonb_build_object('platform', d->>'platform', 'month', to_char(v_month, 'YYYY-MM'),
                            'reported_aed', coalesce(sum(amount_aed), 0), 'rows', count(*),
                            'rows_unconverted', count(*) filter (where amount_aed is null))
    into v_pos from public.ad_spend_reported
   where platform = d->>'platform' and spend_date >= v_month and spend_date < (v_month + interval '1 month')::date;
  if d->>'platform' = 'meta' then
    -- the addition: Meta's month total feeds the invoice match's reported side
    if v_recorded then
      select round(sum(amount_aed), 2) into v_meta_month from public.ad_spend_reported
       where platform = 'meta' and amount_aed is not null
         and spend_date >= v_month and spend_date < (v_month + interval '1 month')::date;
      if coalesce(v_meta_month, 0) > 0 then
        insert into public.accountant_ad_spend_month (month, reported_spend_aed, reported_at, updated_at)
        values (v_month, v_meta_month, now(), now())
        on conflict (month) do update set reported_spend_aed = excluded.reported_spend_aed, reported_at = now(), updated_at = now();
        -- the hourly snapshot (fn_accountant_ad_spend_snapshot) reads this; keep it saying the same figure
        update public.ad_spend_policy set month_spent_aed = v_meta_month, month_label = to_char(v_month, 'YYYY-MM'), updated_at = now()
         where policy_key = 'default' and to_char(v_month, 'YYYY-MM') = to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM');
      end if;
    end if;
    begin
      v_inv := public.fn_accountant_ad_spend_figures(v_month);
      v_pos := v_pos || jsonb_build_object('invoiced_aed', v_inv->'invoiced_aed', 'meta_invoices', v_inv->'meta_invoices');
    exception when others then
      v_pos := v_pos || jsonb_build_object('invoiced_aed', null, 'invoiced_error', left(sqlerrm, 200));
    end;
  end if;

  v_bid := public.fn_seat_handoff('accountant', 'marketing', 'adspend.booked', 'ad_spend_reported', (d->>'source_ref') || '@' || (d->>'amount'),
    jsonb_build_object('recorded_handoff', p_id, 'source_ref', d->>'source_ref', 'amount', d->'amount', 'currency', d->>'currency',
                       'amount_aed', v_aed, 'recorded', v_recorded, 'test', v_test, 'demo', v_test, 'month_position', v_pos,
                       'books', case when v_test then 'Test money: not recorded and never booked.'
                                     else 'Recorded on the accountant''s ad-spend record. The ledger entry is made from the platform''s invoice when it reaches the expenses mailbox (fn_gl_sync_business); booking the reported figure as well would count the same spend twice.' end));
  return jsonb_build_object('waiting', 'marketing re-verification of adspend.booked ' || v_bid, 'recorded', v_recorded,
                            'test', v_test, 'amount_aed', v_aed, 'booked_handoff', v_bid, 'month_position', v_pos);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_knowledge_search_vector()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  new.search :=
      setweight(to_tsvector('english'::regconfig, coalesce(new.title,'')), 'A')
   || setweight(to_tsvector('english'::regconfig, coalesce(array_to_string(new.tags,' '),'')), 'B')
   || setweight(to_tsvector('english'::regconfig, coalesce(new.content,'')), 'C');
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_log_issued_document(p_kind text, p_template_version text, p_sha256 text, p_recipient text, p_supplier_id bigint, p_due_id bigint, p_file_path text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint;
begin
  insert into public.accountant_issued_document (document_kind, template_version, content_sha256, recipient, supplier_id, due_id, file_path)
  values (p_kind, p_template_version, lower(p_sha256), p_recipient, p_supplier_id, p_due_id, p_file_path)
  returning id into v_id;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_mailbox_check_record(p_messages jsonb, p_list_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_missing jsonb; v_not int; v_held jsonb; v_held_n int; v_last timestamptz; v_listed int; v_verdict text;
  v_items jsonb := '[]'::jsonb; v_settle jsonb;
begin
  if p_list_error is null and jsonb_typeof(p_messages) is distinct from 'array' then
    raise exception 'fn_accountant_mailbox_check_record: messages must be an array of {id, created_at}';
  end if;
  v_listed := case when p_list_error is null then jsonb_array_length(p_messages) else 0 end;

  select coalesce(jsonb_agg(jsonb_build_object('id', m->>'id', 'received_at', m->>'created_at', 'from', m->>'from')), '[]'::jsonb), count(*)
    into v_missing, v_not
    from jsonb_array_elements(case when p_list_error is null then p_messages else '[]'::jsonb end) m
   where coalesce(m->>'id', '') <> ''
     and not exists (select 1 from public.inbound_messages i where i.provider_email_id = m->>'id')
     and not exists (select 1 from public.expense_entries e where e.source_msg_id = 'resend:' || (m->>'id'))
     and not exists (select 1 from public.inbound_messages i
                      where lower(i.to_email) like 'expenses@%'
                        and position(('Resend inbound id ' || (m->>'id')) in coalesce(i.body, '')) > 0);

  select coalesce(jsonb_agg(jsonb_build_object('inbound_id', i.id, 'received_at', i.created_at, 'subject', left(i.subject, 120)) order by i.id), '[]'::jsonb), count(*)
    into v_held, v_held_n
    from public.inbound_messages i
   -- still waiting = held (needs_review) and not yet closed: fn_receipt_hand_to_bookkeeper's work item tells the
   -- accountant to mark the inbound row replied once the expense is booked, so replied_at is the closing mark.
   where lower(i.to_email) like 'expenses@%' and i.needs_review and i.replied_at is null
     and i.created_at < now() - interval '24 hours';

  select greatest(
           (select max(created_at) from public.inbound_messages where lower(to_email) like 'expenses@%'),
           (select max((m->>'created_at')::timestamptz) from jsonb_array_elements(case when p_list_error is null then p_messages else '[]'::jsonb end) m))
    into v_last;

  v_verdict := case when p_list_error is not null then 'unreadable'
                    when v_not > 0 then 'intake_silent'
                    when v_held_n > 0 then 'held_waiting'
                    when v_last is null or v_last < now() - interval '72 hours' then 'mailbox_quiet'
                    else 'current' end;

  if p_list_error is not null then
    v_items := v_items || jsonb_build_object('item', 'unreadable', 'owner_seat', 'accountant', 'subject', 'resend inbound',
      'title', 'The expenses mailbox could not be listed, so nobody can say whether receipts arrived',
      'evidence', jsonb_build_object('error', left(p_list_error, 300)));
  end if;
  if v_not > 0 then
    v_items := v_items || jsonb_build_object('item', 'intake_silent', 'owner_seat', 'accountant', 'subject', 'inbound_messages',
      'title', v_not || ' message(s) reached the expenses mailbox and no intake recorded them',
      'affected', v_not, 'evidence', jsonb_build_object('messages', v_missing,
        'act', 'run the accountant expense_sweep for each email_id; if it cannot book one, it holds it and says why'));
  end if;
  if v_held_n > 0 then
    v_items := v_items || jsonb_build_object('item', 'held_waiting', 'owner_seat', 'accountant', 'subject', 'inbound_messages',
      'title', v_held_n || ' receipt(s) in the expenses mailbox are held, not booked, for more than 24 hours',
      'affected', v_held_n, 'evidence', jsonb_build_object('held', v_held));
  end if;
  v_settle := public.fn_accountant_duty_settle('mailbox', v_items);

  -- the log keeps 90 days; the latest row is the answer
  delete from public.accountant_mailbox_check where checked_at < now() - interval '90 days';
  insert into public.accountant_mailbox_check (listed, not_taken_in, held_over_24h, last_received_at, verdict, detail)
  values (v_listed, v_not, v_held_n, v_last, v_verdict,
          jsonb_build_object('not_taken_in', v_missing, 'held', v_held, 'list_error', p_list_error));

  return jsonb_build_object('verdict', v_verdict, 'listed', v_listed, 'not_taken_in', v_not, 'held_over_24h', v_held_n,
    'last_received_at', v_last, 'findings', v_settle,
    'says', case v_verdict
      when 'unreadable' then 'the mailbox could not be listed: nothing is known about what arrived'
      when 'intake_silent' then 'receipts reached the mailbox and the intake did not record them'
      when 'held_waiting' then 'every message was taken in, and ' || v_held_n || ' receipt(s) are still held'
      when 'mailbox_quiet' then 'the mailbox is quiet: nothing has arrived since ' || coalesce(to_char(v_last at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' Dubai', 'it was opened')
      else 'every receipt that arrived is recorded' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_money_screen(p_move text, p_ref text, p_customer uuid, p_supplier bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_flags jsonb; v_high jsonb; v_keys text[]; h public.money_move_hold; v_id bigint;
begin
  if p_move is null or p_move not in ('reveal', 'refund') then raise exception 'a money screen names its move (reveal or refund), not %', p_move; end if;
  if coalesce(btrim(p_ref), '') = '' then raise exception 'a money screen names what is moving (the quote or the refund)'; end if;

  -- NOW, not at the next tick: a disposable address or a third refund request is seen before this money moves.
  perform public.fn_accountant_party_flags(p_customer, null) where p_customer is not null;
  perform public.fn_accountant_party_flags(null, p_supplier) where p_supplier is not null;
  v_flags := public.fn_accountant_flags_touching(p_customer, p_supplier);
  select coalesce(jsonb_agg(e.f), '[]'::jsonb), coalesce(array_agg(e.f->>'key' order by e.f->>'key'), '{}')
    into v_high, v_keys from jsonb_array_elements(v_flags) as e(f) where e.f->>'severity' = 'high';

  select * into h from public.money_move_hold where move = p_move and ref = p_ref and status <> 'released' for update;

  if jsonb_array_length(v_high) = 0 then
    if h.status = 'held' then
      update public.money_move_hold set status = 'released', released_at = now(), released_by = 'screen', screened_at = now(),
             release_reason = 'no open high-severity flag touches either party any more', flags = v_flags
       where id = h.id;
      perform public.fn_seat_handoff('accountant', 'customer_support', 'fraud.money_released', 'money_move_hold', h.id::text,
        jsonb_build_object('hold_id', h.id, 'move', p_move, 'ref', p_ref));
      return jsonb_build_object('hold', false, 'released', h.id, 'flags', v_flags);
    end if;
    if jsonb_array_length(v_flags) > 0 then
      insert into public.money_move_hold (move, ref, customer_id, supplier_id, status, flag_keys, flags)
      values (p_move, p_ref, p_customer, p_supplier, 'noted',
              (select array_agg(e.f->>'key' order by e.f->>'key') from jsonb_array_elements(v_flags) as e(f)), v_flags)
      on conflict (move, ref) where status <> 'released'
      do update set flags = excluded.flags, flag_keys = excluded.flag_keys, screened_at = now()
      returning id into v_id;
    end if;
    return jsonb_build_object('hold', false, 'noted', v_id, 'flags', v_flags);
  end if;

  -- A reviewer already let THIS move go with these very flags open: the same flags do not hold it twice.
  if exists (select 1 from public.money_move_hold r where r.move = p_move and r.ref = p_ref and r.status = 'released'
                and r.released_by <> 'screen' and r.flag_keys @> v_keys) then
    return jsonb_build_object('hold', false, 'reviewed', true, 'flags', v_flags);
  end if;

  if h.id is null then
    insert into public.money_move_hold (move, ref, customer_id, supplier_id, status, flag_keys, flags)
    values (p_move, p_ref, p_customer, p_supplier, 'held', v_keys, v_flags)
    on conflict (move, ref) where status <> 'released' do nothing
    returning id into v_id;
    if v_id is null then  -- a concurrent screen of the same move wrote the row first; answer as it did
      select * into h from public.money_move_hold where move = p_move and ref = p_ref and status <> 'released';
      return jsonb_build_object('hold', h.status = 'held', 'hold_id', h.id, 'flags', h.flags);
    end if;
  else
    v_id := h.id;
    update public.money_move_hold set status = 'held', flag_keys = v_keys, flags = v_flags, screened_at = now(),
           opened_at = case when h.status = 'held' then h.opened_at else now() end
     where id = h.id;
  end if;
  if h.id is null or h.status <> 'held' then
    perform public.fn_seat_handoff('accountant', 'customer_support', 'fraud.money_held', 'money_move_hold', v_id::text,
      jsonb_build_object('hold_id', v_id, 'move', p_move, 'ref', p_ref));
  end if;
  return jsonb_build_object('hold', true, 'hold_id', v_id, 'flags', v_flags);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_month_close(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_m date := date_trunc('month', p_month)::date; f jsonb; v_rep jsonb; v_sev text;
begin
  if v_m >= date_trunc('month', now() at time zone 'Asia/Dubai')::date then
    raise exception 'month % has not ended; a month is closed only after it ends', to_char(v_m, 'YYYY-MM');
  end if;
  if exists (select 1 from public.accountant_month_close where month = v_m) then
    return jsonb_build_object('ok', true, 'month', to_char(v_m, 'YYYY-MM'), 'already_closed', true);
  end if;
  f := public.fn_accountant_month_close_figures(v_m);
  v_sev := case when (f#>>'{bank_reconciliation,unmatched}')::int > 0 or (f->>'charge_audit_open_differences')::int > 0
                     or (f#>>'{disputes,open}')::int > 0
                -- 29 Sep 2026, instruction 1013: no runway target, the founder funds the company. Runway and the
                -- cash forecast are information and no longer raise the close's severity.
                then 'elevated' else 'routine' end;
  v_rep := public.fn_support_report_to_ceo('accountant_close:' || to_char(v_m, 'YYYY-MM'), v_sev,
    'Monthly close ' || to_char(v_m, 'Mon YYYY') || ': net result AED ' || (f#>>'{profit_and_loss,net_result_aed}')
      || ', cash in the bank ' || coalesce('AED ' || (f#>>'{cash_position,cash_in_bank,aed}'), 'MISSING')
      || ', runway ' || coalesce((f#>>'{cash_position,runway,months}') || ' months', 'MISSING')
      || ', AED ' || (f#>>'{held_for_possible_refunds,held_for_possible_refunds_aed}') || ' held for possible refunds, '
      || (f#>>'{bank_reconciliation,unmatched}') || ' payout(s) not yet in the bank',
    f, '[]'::jsonb,
    'Acknowledge the close. The PDF and CSV are filed in finance-reports/accountant/close/' || to_char(v_m, 'YYYY-MM') || '.',
    p_review_in => interval '3 days', p_source_agent => 'accountant');
  insert into public.accountant_month_close (month, figures, ceo_report_id)
  values (v_m, f, (v_rep->>'report_id')::bigint);
  return jsonb_build_object('ok', true, 'month', to_char(v_m, 'YYYY-MM'), 'ceo_report', v_rep);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_month_close_attach(p_month date, p_bucket text, p_pdf_path text, p_csv_path text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if coalesce(btrim(p_pdf_path), '') = '' or coalesce(btrim(p_csv_path), '') = '' then
    raise exception 'a close is rendered only with both its PDF and its CSV';
  end if;
  update public.accountant_month_close set pdf_bucket = p_bucket, pdf_path = p_pdf_path, csv_path = p_csv_path, rendered_at = now()
   where month = date_trunc('month', p_month)::date;
  if not found then raise exception 'month % is not closed', to_char(p_month, 'YYYY-MM'); end if;
  update public.support_ceo_report r
     set verified_evidence = r.verified_evidence || jsonb_build_object('pdf', p_bucket || '/' || p_pdf_path, 'csv', p_bucket || '/' || p_csv_path)
    from public.accountant_month_close c
   where c.month = date_trunc('month', p_month)::date and r.id = c.ceo_report_id;
  return jsonb_build_object('ok', true, 'month', to_char(p_month, 'YYYY-MM'));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_month_close_document(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare f jsonb; v_pnl_rows jsonb; v_csv text; x jsonb; v_title text;
begin
  select figures into f from public.accountant_month_close where month = date_trunc('month', p_month)::date;
  if f is null then raise exception 'month % is not closed', to_char(p_month, 'YYYY-MM'); end if;
  v_title := 'QuotesDone monthly close ' || (f->>'month');
  select coalesce(jsonb_agg(jsonb_build_array(e->>'code', e->>'name', e->>'type', to_char((e->>'amount_aed')::numeric, 'FM999,999,990.00'))
                            order by e->>'code'), '[]'::jsonb)
    into v_pnl_rows from jsonb_array_elements(f#>'{profit_and_loss,accounts}') e;
  v_csv := 'section,item,value,note' || E'\n';
  for x in select e from jsonb_array_elements(f#>'{profit_and_loss,accounts}') e loop
    v_csv := v_csv || 'profit_and_loss,' || (x->>'code') || ' ' || replace(x->>'name', ',', ' ') || ',' || (x->>'amount_aed') || ',' || (x->>'type') || E'\n';
  end loop;
  v_csv := v_csv
    || 'profit_and_loss,revenue,' || (f#>>'{profit_and_loss,revenue_aed}') || ',posted journals' || E'\n'
    || 'profit_and_loss,expenses,' || (f#>>'{profit_and_loss,expenses_aed}') || ',posted journals' || E'\n'
    || 'profit_and_loss,net_result,' || (f#>>'{profit_and_loss,net_result_aed}') || ',' || E'\n'
    || 'cash_in,reveals,' || (f#>>'{cash_in,reveals_aed}') || ',' || E'\n'
    || 'cash_in,supplier_charges,' || (f#>>'{cash_in,supplier_charges_aed}') || ',' || E'\n'
    || 'cash_in,subscriptions_paid,' || (f#>>'{cash_in,subscriptions_paid}') || ',count' || E'\n'
    || 'cash_out,refunds,' || (f#>>'{cash_out,refunds_aed}') || ',' || E'\n'
    || 'cash_out,expenses,' || (f#>>'{cash_out,expenses_aed}') || ',AED and USD converted at gl_settings.usd_to_aed' || E'\n'
    || 'held,held_for_possible_refunds,' || (f#>>'{held_for_possible_refunds,held_for_possible_refunds_aed}') || ',not earned while it can be refunded' || E'\n'
    || 'bank,payouts,' || (f#>>'{bank_reconciliation,payouts}') || ',count' || E'\n'
    || 'bank,payouts_aed,' || (f#>>'{bank_reconciliation,payouts_aed}') || ',' || E'\n'
    || 'bank,matched,' || (f#>>'{bank_reconciliation,matched}') || ',count' || E'\n'
    || 'bank,unmatched,' || (f#>>'{bank_reconciliation,unmatched}') || ',count' || E'\n'
    || 'bank,drafts_waiting,' || (f->>'bank_drafts_waiting') || ',bank charges prepared as drafts under the founder''s hold' || E'\n'
    || 'disputes,open,' || (f#>>'{disputes,open}') || ',count' || E'\n'
    || 'collections,open_aed,' || (f#>>'{collections_aging,open_aed}') || ',' || E'\n'
    || 'charge_audit,open_differences,' || (f->>'charge_audit_open_differences') || ',count' || E'\n'
    || 'vat,rolling_12m_turnover,' || (f#>>'{vat,turnover_aed}') || ',' || coalesce(f#>>'{vat,band}', '') || E'\n'
    -- A month closed before 14 Sep 2026 carries none of the lines below; they print MISSING, never a guess.
    || 'cash,in_bank,' || coalesce(f#>>'{cash_position,cash_in_bank,aed}', 'MISSING') || ','
       || replace(coalesce(f#>>'{cash_position,cash_in_bank,as_of}', f#>>'{cash_position,cash_in_bank,missing}', ''), ',', ' ') || E'\n'
    || 'cash,runway_months,' || coalesce(f#>>'{cash_position,runway,months}', 'MISSING') || ','
       || replace(coalesce(f#>>'{cash_position,runway,missing}', ''), ',', ' ') || E'\n'
    || 'ads,meta_invoiced,' || coalesce(f#>>'{ad_spend,invoiced_aed}', 'MISSING') || ',' || E'\n'
    || 'ads,meta_reported,' || coalesce(f#>>'{ad_spend,reported_spend_aed}', 'MISSING') || ',' || E'\n'
    || 'ads,cost_per_inquiry,' || coalesce(f#>>'{ad_spend,cost_per_inquiry_aed}', 'MISSING') || ',' || E'\n'
    || 'ads,cost_per_reveal,' || coalesce(f#>>'{ad_spend,cost_per_reveal_aed}', 'MISSING') || ',' || E'\n'
    || 'recovery,open_claims_aed,' || coalesce(f#>>'{supplier_charge_recovery,open_aed}', 'MISSING') || ',' || E'\n'
    || 'renewals,budgeted_aed,' || coalesce(f#>>'{renewals,budgeted_aed}', 'MISSING') || ','
       || coalesce(f#>>'{renewals,unbudgeted}', '?') || ' unbudgeted' || E'\n'
    -- 29 Sep 2026, instruction 1013 item 5: the 90-day forecast, one line per week. A close before it prints none.
    || coalesce((select string_agg('cash_forecast,week_' || (w->>'week') || '_closing,' || coalesce(w->>'closing_aed', 'MISSING') || ','
                                   || (w->>'from') || ' to ' || (w->>'to') || ' in ' || (w->>'in_aed') || ' out ' || (w->>'out_aed'), E'\n'
                                   order by (w->>'week')::int) || E'\n'
                   from jsonb_array_elements(f#>'{cash_forecast_90d,weeks}') w), '')
    || case when f ? 'cash_forecast_90d' then 'cash_forecast,first_week_below_zero,' || coalesce(f#>>'{cash_forecast_90d,below_zero,first_week}', 'none') || ','
         || coalesce('top-up AED ' || (f#>>'{cash_forecast_90d,below_zero,top_up_to_stay_above_zero_aed}'), 'information only') || E'\n' else '' end;
  return jsonb_build_object('month', f->>'month', 'title', v_title, 'name', 'QuotesDone_Monthly_Close_' || (f->>'month'),
    'csv', v_csv,
    'blocks', jsonb_build_array(
      jsonb_build_object('t', 'h2', 'text', v_title),
      jsonb_build_object('t', 'p', 'text', 'Period ' || (f->>'from') || ' to ' || (f->>'to') || ' (Asia/Dubai). Every figure is read from the books at close; nothing is estimated. QuotesDone is not VAT-registered.'),
      jsonb_build_object('t', 'h3', 'text', 'Profit and loss (posted journals)'),
      jsonb_build_object('t', 'table', 'head', jsonb_build_array('Account', 'Name', 'Type', 'AED'), 'rows', v_pnl_rows,
                         'widths', jsonb_build_array(0.12, 0.5, 0.16, 0.22)),
      jsonb_build_object('t', 'table', 'head', jsonb_build_array('Result', 'AED'), 'widths', jsonb_build_array(0.6, 0.4), 'rows', jsonb_build_array(
        jsonb_build_array('Revenue', f#>>'{profit_and_loss,revenue_aed}'),
        jsonb_build_array('Expenses', f#>>'{profit_and_loss,expenses_aed}'),
        jsonb_build_array('Net result', f#>>'{profit_and_loss,net_result_aed}'),
        jsonb_build_array('Held for possible refunds (not earned while it can be refunded)', f#>>'{held_for_possible_refunds,held_for_possible_refunds_aed}'))),
      jsonb_build_object('t', 'h3', 'text', 'Cash in and out'),
      jsonb_build_object('t', 'table', 'head', jsonb_build_array('Movement', 'Value'), 'widths', jsonb_build_array(0.6, 0.4), 'rows', jsonb_build_array(
        jsonb_build_array('Reveals paid (AED)', f#>>'{cash_in,reveals_aed}'),
        jsonb_build_array('Supplier charges collected (AED)', f#>>'{cash_in,supplier_charges_aed}'),
        jsonb_build_array('Supplier subscriptions paid (count)', f#>>'{cash_in,subscriptions_paid}'),
        jsonb_build_array('Refunds paid out (AED)', f#>>'{cash_out,refunds_aed}'),
        jsonb_build_array('Expenses charged (AED)', f#>>'{cash_out,expenses_aed}'))),
      jsonb_build_object('t', 'h3', 'text', 'Bank reconciliation (Stripe payouts to Mashreq)'),
      jsonb_build_object('t', 'table', 'head', jsonb_build_array('Item', 'Value'), 'widths', jsonb_build_array(0.6, 0.4), 'rows', jsonb_build_array(
        jsonb_build_array('Payouts arriving in the month', f#>>'{bank_reconciliation,payouts}'),
        jsonb_build_array('Payout value (AED)', f#>>'{bank_reconciliation,payouts_aed}'),
        jsonb_build_array('Matched to a statement line', f#>>'{bank_reconciliation,matched}'),
        jsonb_build_array('Paid by Stripe, not yet in the bank', f#>>'{bank_reconciliation,unmatched}'),
        jsonb_build_array('Open reconciliation findings', f#>>'{bank_reconciliation,open_findings}'),
        jsonb_build_array('Bank charges prepared as drafts (founder''s hold)', f->>'bank_drafts_waiting'))),
      jsonb_build_object('t', 'h3', 'text', 'Positions'),
      jsonb_build_object('t', 'table', 'head', jsonb_build_array('Item', 'Value'), 'widths', jsonb_build_array(0.6, 0.4), 'rows', jsonb_build_array(
        jsonb_build_array('Open card disputes', f#>>'{disputes,open}'),
        jsonb_build_array('Supplier charges outstanding (AED)', f#>>'{collections_aging,open_aed}'),
        jsonb_build_array('Open charge-audit differences', f->>'charge_audit_open_differences'),
        jsonb_build_array('Suppliers ranked toward the free thousand', f#>>'{subscriptions,registered_ranked}'),
        jsonb_build_array('Rolling 12-month turnover for VAT (AED)', f#>>'{vat,turnover_aed}'))),
      jsonb_build_object('t', 'h3', 'text', 'Cash in the bank, runway, advertising, recovery and renewals'),
      jsonb_build_object('t', 'table', 'head', jsonb_build_array('Item', 'Value'), 'widths', jsonb_build_array(0.6, 0.4), 'rows', jsonb_build_array(
        jsonb_build_array('Cash in the Mashreq account (AED)', coalesce(f#>>'{cash_position,cash_in_bank,aed}', 'missing: no closing balance recorded')),
        jsonb_build_array('Balance as of', coalesce(f#>>'{cash_position,cash_in_bank,as_of}', '-')),
        jsonb_build_array('Mashreq money in / out in the month (AED)',
          coalesce((f#>>'{cash_position,bank_movements,in_aed}') || ' / ' || (f#>>'{cash_position,bank_movements,out_aed}'), 'missing: no statement line in the month')),
        jsonb_build_array('Runway (months)', coalesce(f#>>'{cash_position,runway,months}', 'missing: ' || coalesce(f#>>'{cash_position,runway,missing}', 'not measured'))),
        jsonb_build_array('Meta invoices booked (AED)', coalesce(f#>>'{ad_spend,invoiced_aed}', 'missing')),
        jsonb_build_array('Ad spend Meta reported (AED)', coalesce(f#>>'{ad_spend,reported_spend_aed}', 'missing')),
        jsonb_build_array('Cost per inquiry / per reveal (AED)',
          coalesce(f#>>'{ad_spend,cost_per_inquiry_aed}', 'missing') || ' / ' || coalesce(f#>>'{ad_spend,cost_per_reveal_aed}', 'missing')),
        jsonb_build_array('Supplier-charge claims open (count / AED)',
          coalesce(f#>>'{supplier_charge_recovery,open_claims}', 'missing') || ' / ' || coalesce(f#>>'{supplier_charge_recovery,open_aed}', 'missing')),
        jsonb_build_array('Renewals budgeted (AED) / lines with no budget',
          coalesce(f#>>'{renewals,budgeted_aed}', 'missing') || ' / ' || coalesce(f#>>'{renewals,unbudgeted}', 'missing')))),
      jsonb_build_object('t', 'h3', 'text', 'Cash forecast, next 13 weeks (information, not an alarm)'),
      jsonb_build_object('t', 'table', 'head', jsonb_build_array('Week', 'Dates', 'In (AED)', 'Out (AED)', 'Closing (AED)'),
                         'widths', jsonb_build_array(0.1, 0.36, 0.18, 0.18, 0.18),
                         'rows', coalesce((select jsonb_agg(jsonb_build_array(w->>'week', (w->>'from') || ' to ' || (w->>'to'), w->>'in_aed', w->>'out_aed',
                                                                               coalesce(w->>'closing_aed', 'missing')) order by (w->>'week')::int)
                                             from jsonb_array_elements(f#>'{cash_forecast_90d,weeks}') w), '[]'::jsonb)),
      jsonb_build_object('t', 'p', 'text', case
        when f#>>'{cash_forecast_90d,below_zero,first_week}' is not null
          then 'The account would go below zero in week ' || (f#>>'{cash_forecast_90d,below_zero,first_week}') || ' (from '
               || (f#>>'{cash_forecast_90d,below_zero,week_from}') || '); a top-up of AED '
               || (f#>>'{cash_forecast_90d,below_zero,top_up_to_stay_above_zero_aed}') || ' keeps it at or above zero.'
        when f ? 'cash_forecast_90d' then coalesce(f#>>'{cash_forecast_90d,below_zero,note}', '')
        else 'This month was closed before the forecast existed.' end),
      jsonb_build_object('t', 'note', 'text', 'Prepared by the QuotesDone accountant from public.gl_journal, stripe_payout, bank_statement_line, transactions, refunds, expense_entries, supplier_dues, stripe_dispute and charge_audit. The CSV beside this document carries the same figures line by line.')));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_month_close_figures(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_m date := date_trunc('month', p_month)::date; v_e date; v_fx numeric;
  v_from timestamptz; v_to timestamptz; v_pnl jsonb; v_rev numeric; v_exp numeric; v_aging jsonb; v_out jsonb;
begin
  v_e := (v_m + interval '1 month' - interval '1 day')::date;
  v_from := v_m::timestamp at time zone 'Asia/Dubai'; v_to := (v_e + 1)::timestamp at time zone 'Asia/Dubai';
  v_fx := coalesce((select num_value from public.gl_settings where key = 'usd_to_aed'), 3.6725);

  select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name, 'type', type, 'amount_aed', amt) order by code), '[]'::jsonb),
         coalesce(sum(amt) filter (where type = 'revenue'), 0), coalesce(sum(amt) filter (where type = 'expense'), 0)
    into v_pnl, v_rev, v_exp
    from (select a.code, a.name, a.type,
                 round(sum(case when a.type = 'revenue' then l.credit - l.debit else l.debit - l.credit end), 2) amt
            from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id join public.gl_accounts a on a.code = l.account_code
           where j.status = 'posted' and j.entry_date between v_m and v_e and a.type in ('revenue', 'expense')
           group by a.code, a.name, a.type) z;

  select jsonb_build_object(
      'current', count(*) filter (where d <= 0), 'd1_30', count(*) filter (where d between 1 and 30),
      'd31_60', count(*) filter (where d between 31 and 60), 'd61_90', count(*) filter (where d between 61 and 90),
      'over_90', count(*) filter (where d > 90), 'open_aed', coalesce(sum(owed), 0))
    into v_aging
    from (select v_e - due_date d, coalesce(total_claim, amount_due + coalesce(admin_fee, 0) + coalesce(interest_amount, 0)) owed
            from public.supplier_dues
           where public.fn_supplier_due_is_owed(status, paid_at)) z;

  v_out := jsonb_build_object(
    'month', to_char(v_m, 'YYYY-MM'), 'from', v_m, 'to', v_e, 'timezone', 'Asia/Dubai',
    'profit_and_loss', jsonb_build_object('accounts', v_pnl, 'revenue_aed', v_rev, 'expenses_aed', v_exp,
                                          'net_result_aed', v_rev - v_exp,
                                          'basis', 'Posted journals dated in the month, revenue and expense accounts. Drafts are not in it.'),
    'cash_in', jsonb_build_object(
      'reveals_aed', (select coalesce(sum(coalesce(total_charged, reveal_fee)), 0) from public.transactions t
                       left join public.customers c on c.id = t.customer_id
                      where t.fee_status = 'paid' and t.revealed_at >= v_from and t.revealed_at < v_to and not coalesce(c.is_demo, false)),
      'supplier_charges_aed', (select coalesce(sum(coalesce(total_claim, amount_due)), 0) from public.supplier_dues
                                where paid_at >= v_from and paid_at < v_to),
      'subscriptions_paid', (select count(*) from public.leads where registration_paid_at >= v_from and registration_paid_at < v_to
                               and not coalesce(is_demo, false))),
    'cash_out', jsonb_build_object(
      'refunds_aed', (select coalesce(sum(amount_fils), 0) / 100.0 from public.refunds where status = 'succeeded'
                       and settled_at >= v_from and settled_at < v_to),
      'expenses_aed', (select coalesce(round(sum(amount * case upper(currency) when 'USD' then v_fx else 1 end)
                                             filter (where upper(currency) in ('AED', 'USD')), 2), 0)
                         from public.expense_entries where charged_on between v_m and v_e),
      'expenses_unconverted', (select count(*) from public.expense_entries where charged_on between v_m and v_e
                                 and upper(currency) not in ('AED', 'USD'))),
    'held_for_possible_refunds', public.fn_accountant_refund_reserve(),
    'bank_reconciliation', jsonb_build_object(
      'payouts', (select count(*) from public.stripe_payout where livemode and arrival_date between v_m and v_e),
      'payouts_aed', (select coalesce(sum(amount_fils), 0) / 100.0 from public.stripe_payout where livemode and arrival_date between v_m and v_e),
      'matched', (select count(*) from public.stripe_payout where livemode and arrival_date between v_m and v_e and bank_line_id is not null),
      'unmatched', (select count(*) from public.stripe_payout where livemode and status = 'paid' and arrival_date between v_m and v_e and bank_line_id is null),
      'statement_lines', (select count(*) from public.bank_statement_line where account <> 'zz_demo' and value_date between v_m and v_e),
      'open_findings', (select count(*) from public.it_engineer_finding where issue_key like 'acct:bank:%' and closed_at is null)),
    'bank_drafts_waiting', (select count(*) from public.gl_journal where source = 'bank_charge' and status = 'draft'),
    'disputes', jsonb_build_object('open', (select count(*) from public.stripe_dispute where livemode and closed_at is null),
                                   'closed_in_month', (select coalesce(jsonb_object_agg(outcome, n), '{}'::jsonb) from (
                                      select outcome, count(*) n from public.stripe_dispute where livemode and closed_at >= v_from and closed_at < v_to
                                       group by outcome) z)),
    'collections_aging', v_aging,
    'charge_audit_open_differences', (select count(*) from public.charge_audit where livemode and abs(diff_aed) >= 0.01 and resolved_at is null),
    'subscriptions', public.fn_accountant_subscription_position(),
    'vat', public.fn_accountant_vat_threshold_check(false),
    'weekly_figures_over_the_month', public.fn_accountant_weekly_report_figures(v_m, v_e),
    'measured_at', now());
  -- 14 Sep 2026, the five further duties ("add all for accountant and IT"): the CEO's monthly report of cash,
  -- runway, ad spend, recovery and renewals rides on the close rather than being a second report.
  return v_out || jsonb_build_object(
    'cash_position', public.fn_accountant_cash_position(v_m, (v_out#>>'{cash_out,expenses_aed}')::numeric),
    'ad_spend', public.fn_accountant_ad_spend_figures(v_m),
    'supplier_charge_recovery', public.fn_accountant_recovery_position(),
    'renewals', public.fn_accountant_renewal_position(),
    -- 29 Sep 2026, instruction 1013 item 5: the 90-day cash forecast from the month's last day. Information only.
    'cash_forecast_90d', public.fn_accountant_cash_forecast(v_e));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_month_close_status(p_month date, p_today date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_m date := date_trunc('month', p_month)::date;
  v_today date := coalesce(p_today, (now() at time zone 'Asia/Dubai')::date);
  v_day int := coalesce((select num_value::int from public.gl_settings where key = 'month_close_day'), 3);
  v_stmt jsonb := public.fn_accountant_statement_booked(v_m);
  v_due_by date; v_closed timestamptz; v_status text;
begin
  -- The close is due by the 5th, or two days after the statement arrived when it arrived later.
  if (v_stmt->>'booked')::boolean then
    v_due_by := greatest((v_m + interval '1 month' + interval '4 days')::date,
                         ((v_stmt->>'received_at')::timestamptz at time zone 'Asia/Dubai')::date + 2);
  end if;
  select closed_at into v_closed from public.accountant_month_close where month = v_m;
  v_status := case when v_closed is not null then 'closed'
                   when v_today < (v_m + interval '1 month')::date + (v_day - 1) then 'not_due'
                   when not (v_stmt->>'booked')::boolean then 'waiting_for_statement'
                   else 'due' end;
  return jsonb_build_object('month', to_char(v_m, 'YYYY-MM'), 'status', v_status, 'due_by', v_due_by,
    'closed_at', v_closed, 'statement', v_stmt,
    'late', case when v_status = 'closed' then v_due_by is not null and (v_closed at time zone 'Asia/Dubai')::date > v_due_by
                 when v_status = 'due' then v_today > v_due_by
                 else false end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_month_close_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_prev date := (date_trunc('month', (now() at time zone 'Asia/Dubai')::date) - interval '1 month')::date; v_s jsonb;
begin
  v_s := public.fn_accountant_month_close_status(v_prev);
  if v_s->>'status' <> 'due' then
    return jsonb_build_object('closed', false, 'month', v_s->>'month', 'status', v_s->>'status',
      'waiting_for', case when v_s->>'status' = 'waiting_for_statement' then v_s#>>'{statement,reason}' end,
      'pending_render', (select count(*) from public.accountant_month_close where rendered_at is null));
  end if;
  return public.fn_accountant_month_close(v_prev) || jsonb_build_object('closed', true, 'status', 'closed');
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_nonresponse_charge(p_transaction_id uuid, p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t public.transactions; c public.pricing_config; v_n int; v_sum bigint;
  v_refunded numeric; v_approved numeric; v_base numeric; v_settled timestamptz; v_src text;
  v_cap numeric; v_apr numeric; v_due_days int; v_due date; v_as_of date; v_days int; v_int numeric;
  v_ver text; v_acc timestamptz; v_fee numeric; v_fee_basis text; v_signed int; v_proc numeric := 0; v_apr_basis text; v_due_id bigint; v_notice timestamptz; v_due_basis text;
  v_out numeric; v_from date; v_acc_int numeric; v_on_pr numeric; v_overpay numeric := 0; v_paid numeric := 0; v_pay record;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such transaction'); end if;

  -- THE REFUND RECORD: every refund Stripe settled against this payment, summed (a top-up the CEO's
  -- playbook issued is part of what the customer got back), dated from the FIRST settlement so a
  -- top-up does not move the due date. The approved amount caps it, so a duplicate or an over-refund
  -- is the company's loss and never a larger charge on the supplier.
  select count(*), sum(x.amount_fils), min(coalesce(x.settled_at, x.updated_at)),
         string_agg(coalesce(x.stripe_refund_id, 'refunds #' || x.id), ', ' order by x.id)
    into v_n, v_sum, v_settled, v_src
    from public.refunds x
   where x.status = 'succeeded' and x.amount_fils is not null
     and (x.transaction_id = p_transaction_id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref));
  select a.amount_aed into v_approved
    from public.refunds x join public.ceo_approval a on a.decision_id = x.refund_decision_id
   where x.transaction_id = p_transaction_id and a.decision = 'approved' order by x.id desc limit 1;
  if v_n > 0 then
    v_refunded := round(v_sum / 100.0, 2);
    v_src      := v_n || ' settled refund(s): ' || v_src;
  elsif t.refund_amount_aed is not null and coalesce(t.refund_status, '') in ('refunded', 'succeeded') then
    v_refunded := round(t.refund_amount_aed, 2);
    v_settled  := coalesce(t.refund_confirmed_at, t.refund_resolved_at);
    v_src      := 'transactions.refund_amount_aed (Stripe ' || coalesce(t.refund_stripe_id, 'reference not recorded') || ')';
  else
    return jsonb_build_object('ok', false, 'reason', 'no settled refund on this transaction, so there is nothing to recover from the supplier');
  end if;
  if v_settled is null then
    return jsonb_build_object('ok', false, 'reason', 'the refund carries no settlement time, so the charge''s due date cannot be set');
  end if;

  v_approved := coalesce(v_approved, t.total_charged, t.reveal_fee, v_refunded);
  v_base     := least(v_refunded, v_approved);

  select * into c from public.pricing_config order by id limit 1;
  v_cap      := (select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'supplier_charge_max_lawful_apr');
  -- 30 SEP 2026: v_apr is set once, by the version branch below (the agreed rate, or 9% where none was agreed).
  v_due_days := coalesce((select (d.value #>> '{}')::int from public.decision_policy d where d.key = 'supplier_charge_due_days'), 7);
  -- 24 SEP 2026 (accountant): CLAUSE 33 SAYS THE CHARGE IS PAYABLE "within seven (7) days of QuotesDone's notice".
  -- This used to count from the refund settling, which could put a supplier in default before it was ever told:
  -- unfair to the supplier and the weak point of any claim (no notice, no default). The due date is now seven
  -- days after the notice was DELIVERED (customer_support's delivery of nonresponse_charge for this due, status done,
  -- evidence delivered). Until it is delivered the due date is seven days from today, so no interest can accrue.
  select d.id into v_due_id from public.supplier_dues d
   where d.transaction_id = p_transaction_id and coalesce(d.status, '') <> 'cancelled' order by d.id limit 1;
  if v_due_id is not null then
    select min(a.decided_at) into v_notice from public.agent_actions a
     where a.kind = 'handoff' and a.agent = 'customer_support' and a.status = 'done'
       and a.target_id in ('delivery.request:nonresponse_charge:' || v_due_id, 'delivery.request:charge_corrected:' || v_due_id)
       and coalesce((a.evidence->>'delivered')::boolean, false);
  end if;
  if v_notice is not null then
    v_due       := (greatest(v_notice, v_settled) at time zone 'Asia/Dubai')::date + v_due_days;
    v_due_basis := 'notice delivered ' || to_char(v_notice at time zone 'Asia/Dubai', 'YYYY-MM-DD') || ' (Dubai) + ' || v_due_days || ' days, clause 33';
  else
    v_due       := greatest((v_settled at time zone 'Asia/Dubai')::date, (now() at time zone 'Asia/Dubai')::date) + v_due_days;
    v_due_basis := 'notice not yet delivered: provisional, today + ' || v_due_days || ' days; it moves to the delivery date + ' || v_due_days || ' when the notice is delivered';
  end if;
  v_as_of    := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_days     := greatest(v_as_of - v_due, 0);
  -- 23 SEP 2026 (ceo): Supplier Agreement v13 clause 33(b) raised the administrative fee (company_facts.json
  -- nonresponse_admin_fee_aed). The fee is the one the supplier had SIGNED when the customer revealed it: v13 or
  -- later accepted at or before the reveal -> decision_policy.supplier_nonresponse_admin_fee_from_v13_aed; anything
  -- else (v12 or earlier, v13 accepted after the reveal, unknown dates) -> pricing_config's AED 250 of clauses v6-v12.
  -- Never retroactive. supplier_charge.ts adminFeeAed() is the same rule for the documents.
  select l.accepted_terms_version, l.accepted_terms_at into v_ver, v_acc from public.leads l where l.id = t.supplier_id;
  -- 24 SEP 2026 (ceo): the version the supplier had SIGNED at the reveal, 0 when either date is unknown. One number, so
  -- every head below reads the same version (supplier_charge.ts termsAt() is the same rule for the documents).
  v_signed := case when v_acc is not null and t.revealed_at is not null and v_acc <= t.revealed_at
                   then coalesce(nullif(regexp_replace(coalesce(v_ver, ''), '\D', '', 'g'), '')::int, 0) else 0 end;
  if v_signed >= 13 then
    v_fee := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'supplier_nonresponse_admin_fee_from_v13_aed'), 500);
    v_fee_basis := 'Supplier Agreement ' || v_ver || ' clause 33(b), accepted ' || v_acc || ' before the reveal';
  else
    -- 19 OCT 2026 (accountant): the AED 250 of clauses v6-v12 is a LITERAL, as the 9% below is. It used to be read from
    -- pricing_config, which made the pricing table state AED 250 as if it were the current fee (marketing's fact
    -- register found it against the FAQ's AED 500), and raising that row to the current figure would have charged a
    -- v12 signer the v13 fee. pricing_config now carries the CURRENT terms (v15: AED 500, 12%); a legacy supplier keeps
    -- the fee it signed, whatever that row says. Never retroactive.
    v_fee := 250;
    v_fee_basis := 'Supplier Agreement ' || coalesce(v_ver, '(no version recorded)') || ' clause 33(b) as signed before this reveal';
  end if;
  -- 24 SEP 2026 (ceo): SUPPLIER AGREEMENT v14 (founder instruction 990: the maximum UAE law safely allows).
  -- For a supplier who had accepted v14 or later before the reveal:
  --   33(b) the processor fee QuotesDone paid on the refunded reveal and could not recover. Stripe keeps its fee on a
  --         refund; transactions.stripe_fee_fils is that fee as Stripe reported it. An ACTUAL loss, charged at cost,
  --         so Civil Transactions Law 25/2025 Art. 340(2) ("the estimate was excessive") does not reach it.
  --   33(d) interest at the AGREED 12% (Commercial Transactions Law 50/2022 Arts. 72, 73, 84: 9% is only the ceiling
  --         where no rate is agreed), decision_policy.supplier_nonresponse_interest_apr_from_v14.
  -- Everyone else keeps the 9% and no processor-fee head (never retroactive). docs/legal/NONRESPONSE_MAX_V14.md.
  if v_signed >= 14 then
    v_proc      := round(coalesce(t.stripe_fee_fils, 0) / 100.0, 2);
    -- 30 SEP 2026 (accountant): the AGREED rate is what v14 writes, 12%. The policy row may lower it, never raise it.
    v_apr       := least(coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'supplier_nonresponse_interest_apr_from_v14'), 0.12), 0.12);
    v_apr_basis := 'the agreed rate of Supplier Agreement ' || v_ver || ' clauses 31 and 33(d)';
  elsif v_signed >= 9 then
    -- 30 SEP 2026 (accountant): Supplier Agreement v9 to v13 clause 31 AGREE nine percent (9%) per annum. Literal.
    v_apr       := 0.09;
    v_apr_basis := 'Supplier Agreement ' || v_ver || ' clause 31 as signed before this reveal: the agreed 9% a year, simple';
  else
    -- 30 SEP 2026 (accountant; founder ruling ledger 1086, Federal Decree-Law 50/2022): NO AGREED RATE (v8 or earlier,
    -- no version, or accepted after the reveal). The rate is the policy rate, HARD-capped at 9% by a literal so no
    -- pricing_config value and no decision_policy row can raise it.
    v_apr       := least(coalesce(c.supplier_nonresponse_interest_apr, 0.09), coalesce(v_cap, 0.09), 0.09);
    v_apr_basis := 'no interest rate agreed in the version signed before this reveal: the policy rate, never above 9% a year (Federal Decree-Law 50/2022)';
  end if;
  -- 30 SEP 2026 (accountant): A PAYMENT REDUCES THE PRINCIPAL FROM ITS OWN DATE. Before this, interest ran on the whole
  -- principal to the as-of date even after a part payment. Now the same day-by-day ledger as supplier_charge.ts
  -- computeCharge(): interest on each period's outstanding principal, from the due date (or the later payment date)
  -- to the next payment or the as-of date; a payment beyond the principal settles accrued interest. Simple: the
  -- accrued interest is never added to the principal. Payments: public.supplier_due_payments.
  v_out := v_base + v_proc + v_fee; v_from := v_due; v_acc_int := 0;
  if v_due_id is not null then
    for v_pay in select p.paid_on, p.amount_aed from public.supplier_due_payments p
                  where p.due_id = v_due_id and p.paid_on <= v_as_of and p.amount_aed > 0 order by p.paid_on, p.id loop
      if greatest(v_due, v_pay.paid_on) > v_from then
        v_acc_int := v_acc_int + v_out * v_apr * (greatest(v_due, v_pay.paid_on) - v_from) / 365.0;
        v_from    := greatest(v_due, v_pay.paid_on);
      end if;
      v_on_pr   := least(v_out, v_pay.amount_aed);
      v_out     := v_out - v_on_pr; v_overpay := v_overpay + v_pay.amount_aed - v_on_pr; v_paid := v_paid + v_pay.amount_aed;
    end loop;
  end if;
  if v_as_of > v_from then v_acc_int := v_acc_int + v_out * v_apr * (v_as_of - v_from) / 365.0; end if;
  v_int      := greatest(0, round(v_acc_int, 2) - v_overpay);

  return jsonb_build_object(
    'ok', true, 'transaction_id', t.id, 'supplier_id', t.supplier_id,
    'refunded_aed', v_base, 'processor_fee_aed', v_proc, 'charge_aed', v_base + v_proc, 'signed_version', v_signed, 'actually_refunded_aed', v_refunded, 'approved_aed', v_approved, 'refund_source', v_src,
    'admin_fee_aed', v_fee, 'admin_fee_basis', v_fee_basis,
    'interest_apr', v_apr, 'interest_apr_basis', v_apr_basis, 'interest_apr_configured', c.supplier_nonresponse_interest_apr, 'interest_apr_lawful_max', v_cap,
    'due_date', v_due, 'due_basis', v_due_basis, 'as_of', v_as_of, 'interest_days', v_days, 'interest_aed', v_int,
    'paid_aed', v_paid, 'unpaid_principal_aed', v_out,
    'total_aed', round(v_out + v_int, 2),
    'basis', 'base = the amount refunded to the customer, read from the refund record and capped at the amount the CEO approved; '
          || '+ from v14, the processor fee QuotesDone could not recover (transactions.stripe_fee_fils); + the administration fee of the agreement version the supplier had signed at the reveal; '
          || '+ simple interest on (base + processor fee + admin fee) at that version''s rate (v14: the agreed 12%; v9 to v13: the agreed 9%; no agreed rate: the policy rate, never above 9% a year; always simple, never compounded), from the due date (' || v_due_days || ' days after the notice was delivered, clause 33) to the as-of date, each payment (supplier_due_payments) reducing the principal from its own date. Nothing is typed.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_openrouter_breakdown(p_day date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- A GROUP WHOSE CALLS ARE ALL UNPRICED HAS AN UNKNOWN COST, NOT A ZERO ONE.
-- Caught by the 9 Sep probe: sales_engineer/document_extraction printed "0.000000 USD" for a single
-- call that used a model and recorded no tokens. Read off a report that is a claim the seat spent
-- nothing on document extraction that day, which is precisely the fabrication the founder's
-- standing rule forbids. Every group therefore reports usd/aed as NULL when it holds no priced
-- call and at least one unpriced one, and every group carries its own unpriced COUNT so an unknown
-- is visible rather than silent. sum() ignoring nulls does the rest: an unpriced call can never
-- inflate or deflate a total, and the money it did cost lands in the unattributed line against
-- OpenRouter's own meter, where it belongs.
with fx as (
  select coalesce(max(num_value), 3.6725) v from public.gl_settings where key = 'usd_to_aed'
),
rows as (
  select * from public.v_openrouter_call_log where dubai_day = p_day
),
tot as (
  select count(*)::int calls,
         count(*) filter (where cost_basis = 'priced')::int   priced,
         count(*) filter (where cost_basis = 'free')::int     free,
         count(*) filter (where cost_basis = 'unpriced')::int unpriced,
         coalesce(sum(cost_usd),0)::numeric                    usd
    from rows
),
by_seat as (
  select jsonb_agg(x order by x->>'seat') j from (
    select jsonb_build_object(
      'seat', seat, 'seat_basis', min(seat_basis),
      'calls', count(*)::int,
      'priced', count(*) filter (where cost_basis='priced')::int,
      'free', count(*) filter (where cost_basis='free')::int,
      'unpriced', count(*) filter (where cost_basis='unpriced')::int,
      'usd', case when count(*) filter (where cost_basis='priced') = 0 and count(*) filter (where cost_basis='unpriced') > 0 then null else round(coalesce(sum(cost_usd),0),6) end,
      'aed', case when count(*) filter (where cost_basis='priced') = 0 and count(*) filter (where cost_basis='unpriced') > 0 then null else round(coalesce(sum(cost_usd),0) * (select v from fx), 2) end) x
    from rows group by seat) s
),
by_purpose as (
  select jsonb_agg(x order by x->>'purpose') j from (
    select jsonb_build_object('purpose', coalesce(purpose,'(unclassified)'),
      'calls', count(*)::int, 'usd', case when count(*) filter (where cost_basis='priced') = 0 and count(*) filter (where cost_basis='unpriced') > 0 then null else round(coalesce(sum(cost_usd),0),6) end,
      'aed', case when count(*) filter (where cost_basis='priced') = 0 and count(*) filter (where cost_basis='unpriced') > 0 then null else round(coalesce(sum(cost_usd),0) * (select v from fx), 2) end,
      'unpriced', count(*) filter (where cost_basis='unpriced')::int) x
    from rows group by coalesce(purpose,'(unclassified)')) s
),
by_model as (
  select jsonb_agg(x order by x->>'model') j from (
    select jsonb_build_object('model', coalesce(model_used,'(none)'),
      'calls', count(*)::int, 'usd', case when count(*) filter (where cost_basis='priced') = 0 and count(*) filter (where cost_basis='unpriced') > 0 then null else round(coalesce(sum(cost_usd),0),6) end,
      'aed', case when count(*) filter (where cost_basis='priced') = 0 and count(*) filter (where cost_basis='unpriced') > 0 then null else round(coalesce(sum(cost_usd),0) * (select v from fx), 2) end,
      'prompt_tokens', coalesce(sum(prompt_tokens),0)::bigint,
      'output_tokens', coalesce(sum(output_tokens),0)::bigint,
      'unpriced', count(*) filter (where cost_basis='unpriced')::int) x
    from rows group by coalesce(model_used,'(none)')) s
),
by_seat_purpose as (
  select jsonb_agg(x order by x->>'seat', x->>'purpose') j from (
    select jsonb_build_object('seat', seat, 'purpose', coalesce(purpose,'(unclassified)'),
      'calls', count(*)::int, 'unpriced', count(*) filter (where cost_basis='unpriced')::int, 'usd', case when count(*) filter (where cost_basis='priced') = 0 and count(*) filter (where cost_basis='unpriced') > 0 then null else round(coalesce(sum(cost_usd),0),6) end,
      'aed', case when count(*) filter (where cost_basis='priced') = 0 and count(*) filter (where cost_basis='unpriced') > 0 then null else round(coalesce(sum(cost_usd),0) * (select v from fx), 2) end) x
    from rows group by seat, coalesce(purpose,'(unclassified)')) s
),
unattributed_fns as (
  select jsonb_agg(x order by x->>'fn') j from (
    select jsonb_build_object('fn', used_by_function, 'calls', count(*)::int,
      'usd', case when count(*) filter (where cost_basis='priced') = 0 and count(*) filter (where cost_basis='unpriced') > 0 then null else round(coalesce(sum(cost_usd),0),6) end) x
    from rows where seat = '(unattributed)' group by used_by_function) s
)
select jsonb_build_object(
  'day', p_day,
  'timezone', 'Asia/Dubai',
  'calls', (select calls from tot),
  'calls_priced', (select priced from tot),
  'calls_free', (select free from tot),
  'calls_unpriced', (select unpriced from tot),
  'attributed_usd', round((select usd from tot), 6),
  'attributed_aed', round((select usd from tot) * (select v from fx), 2),
  'unpriced_note', case when (select unpriced from tot) > 0
      then (select unpriced from tot)::text || ' call(s) used a model and no tokens or provider cost '
           || 'were recorded at the time. Their cost is UNKNOWN -- not recorded at the time -- and is '
           || 'deliberately excluded from attributed_usd rather than counted as zero. They show in '
           || 'the unattributed line against OpenRouter''s own meter.'
      else null end,
  'by_seat', coalesce((select j from by_seat), '[]'::jsonb),
  'by_purpose', coalesce((select j from by_purpose), '[]'::jsonb),
  'by_model', coalesce((select j from by_model), '[]'::jsonb),
  'by_seat_and_purpose', coalesce((select j from by_seat_purpose), '[]'::jsonb),
  'unattributed_functions', coalesce((select j from unattributed_fns), '[]'::jsonb));
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_openrouter_tick(p_reading jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tz     constant text := 'Asia/Dubai';
  v_fx     numeric;
  v_today  date := (now() at time zone v_tz)::date;
  v_meter  bigint;
  v_day    date;
  v_open   public.openrouter_meter%rowtype;
  v_close  public.openrouter_meter%rowtype;
  v_auth   numeric;
  v_basis  text;
  v_note   text;
  v_brk    jsonb;
  v_attr   numeric;
  v_exp    bigint;
  v_done   jsonb := '[]'::jsonb;
  v_n      int := 0;
begin
  select num_value into v_fx from public.gl_settings where key = 'usd_to_aed';
  v_fx := coalesce(v_fx, 3.6725);

  -- ---- the reading -------------------------------------------------------------------------
  -- Stored whether or not it succeeded. A failed reading is the record that turns a day's basis
  -- from measured to unknown; dropping it would let a gap look like a quiet day.
  if p_reading ? 'ok' then
    insert into public.openrouter_meter
      (ok, cumulative_usd, credits_total_usd, usage_daily_usd, usage_monthly_usd,
       limit_remaining_usd, key_label, err)
    values (
      coalesce((p_reading->>'ok')::boolean, false),
      nullif(p_reading->>'cumulative_usd','')::numeric,
      nullif(p_reading->>'credits_total_usd','')::numeric,
      nullif(p_reading->>'usage_daily_usd','')::numeric,
      nullif(p_reading->>'usage_monthly_usd','')::numeric,
      nullif(p_reading->>'limit_remaining_usd','')::numeric,
      nullif(p_reading->>'key_label',''),
      left(nullif(p_reading->>'err',''), 500))
    returning id into v_meter;
  end if;

  -- ---- close every past day that has evidence and no record yet ------------------------------
  -- "Evidence" is a meter reading or a logged call. A day with neither never existed for us and is
  -- not invented. Capped at 60 days so a first run cannot walk the whole history in one tick.
  for v_day in
    select d from (
      select distinct (read_at at time zone v_tz)::date d from public.openrouter_meter
      union
      select distinct (occurred_at at time zone v_tz)::date from public.ai_cost_log
    ) s
    where d < v_today
      and d >= v_today - 60
      and not exists (select 1 from public.openrouter_day o where o.day = d)
    order by d
  loop
    -- The meter either side of the day. open = the last good reading BEFORE the day began;
    -- close = the last good reading taken DURING the day.
    select * into v_open from public.openrouter_meter
      where ok and cumulative_usd is not null
        and read_at < (v_day::timestamp at time zone v_tz)
      order by read_at desc limit 1;
    select * into v_close from public.openrouter_meter
      where ok and cumulative_usd is not null
        and read_at >= (v_day::timestamp at time zone v_tz)
        and read_at <  ((v_day + 1)::timestamp at time zone v_tz)
      order by read_at desc limit 1;

    if v_open.id is null or v_close.id is null then
      v_auth  := null;
      v_basis := 'unknown';
      v_note  := 'UNKNOWN -- not recorded at the time. '
              || case when v_open.id is null and v_close.id is null
                        then 'No OpenRouter meter reading exists either side of this day'
                      when v_open.id is null
                        then 'No OpenRouter meter reading exists from before this day began'
                      else 'No OpenRouter meter reading was taken during this day' end
              || ', so the day''s provider spend cannot be derived and is NOT reported as zero. '
              || 'The meter began on ' || coalesce((select min((read_at at time zone v_tz)::date)::text
                                                     from public.openrouter_meter), 'never')
              || '; GET /api/v1/activity is 403 for a non-management key, so no back-fill is possible.';
    elsif v_close.cumulative_usd < v_open.cumulative_usd then
      v_auth  := null;
      v_basis := 'unknown';
      v_note  := 'UNKNOWN -- OpenRouter''s lifetime usage counter went BACKWARDS across this day ('
              || v_open.cumulative_usd || ' -> ' || v_close.cumulative_usd || '), which a monotonic '
              || 'meter cannot do. The key was probably rotated or the account changed. Reported as '
              || 'unknown rather than as a negative or a zero.';
    else
      v_auth  := v_close.cumulative_usd - v_open.cumulative_usd;
      v_basis := case when v_auth = 0 then 'true zero' else 'measured' end;
      v_note  := 'Meter reading #' || v_open.id || ' (' || v_open.read_at || ', '
              || v_open.cumulative_usd || ' USD lifetime) to #' || v_close.id || ' ('
              || v_close.read_at || ', ' || v_close.cumulative_usd || ' USD lifetime).';
    end if;

    v_brk  := public.fn_accountant_openrouter_breakdown(v_day);
    v_attr := coalesce((v_brk->>'attributed_usd')::numeric, 0);

    -- The expense is booked ONLY on a day whose provider spend was actually measured and is
    -- non-zero. An unknown day and a true-zero day are both recorded above and book nothing:
    -- a general ledger must never carry a figure nobody can walk back to a reading.
    v_exp := null;
    if v_basis = 'measured' and v_auth > 0 then
      insert into public.expense_entries
        (vendor, category, amount, currency, charged_on, note, source)
      values ('OpenRouter', 'Usage', round(v_auth * v_fx, 2), 'AED', v_day,
        'OpenRouter model usage, ' || v_day || ' (Asia/Dubai). ' || round(v_auth,6) || ' USD at '
        || v_fx || ' = ' || round(v_auth * v_fx, 2) || ' AED. Attributed to seats: '
        || round(v_attr, 6) || ' USD. Unattributed: ' || round(v_auth - v_attr, 6) || ' USD. '
        || 'Basis: measured from the OpenRouter meter. ' || v_note
        || ' Full per-seat breakdown in public.openrouter_day for this date.',
        'accountant:openrouter_daily')
      on conflict (charged_on) where source = 'accountant:openrouter_daily'
        do update set amount = excluded.amount, note = excluded.note
      returning id into v_exp;
    end if;

    insert into public.openrouter_day
      (day, authoritative_usd, authoritative_basis, attributed_usd, unattributed_usd,
       calls, calls_priced, calls_free, calls_unpriced, breakdown,
       meter_open_id, meter_close_id, expense_entry_id, note)
    values (v_day, v_auth, v_basis, v_attr,
      case when v_auth is null then null else round(v_auth - v_attr, 6) end,
      coalesce((v_brk->>'calls')::int, 0),
      coalesce((v_brk->>'calls_priced')::int, 0),
      coalesce((v_brk->>'calls_free')::int, 0),
      coalesce((v_brk->>'calls_unpriced')::int, 0),
      v_brk, v_open.id, v_close.id, v_exp, v_note)
    on conflict (day) do nothing;

    v_n := v_n + 1;
    v_done := v_done || jsonb_build_object(
      'day', v_day, 'basis', v_basis,
      'authoritative_usd', v_auth, 'attributed_usd', round(v_attr,6),
      'unattributed_usd', case when v_auth is null then null else round(v_auth - v_attr,6) end,
      'expense_entry_id', v_exp);
  end loop;

  return jsonb_build_object(
    'ok', true, 'agent', 'accountant', 'meter_reading_id', v_meter,
    'today_dubai', v_today, 'days_reconciled', v_n, 'days', v_done);
end;$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_owner_card_tick(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  s record; m date; v_exp date; e record; v_posted numeric(18,2); v_diff numeric(18,2); v_lines jsonb;
  v_booked jsonb := '[]'::jsonb; v_matched jsonb := '[]'::jsonb; v_items jsonb := '[]'::jsonb;
  v_missing jsonb; v_noline jsonb; v_odd jsonb := '[]'::jsonb; v_line bigint; v_pf text;
begin
  for s in select * from public.accountant_owner_ruled_subscription order by vendor loop
    v_missing := '[]'::jsonb; v_noline := '[]'::jsonb;
    for m in select generate_series(date_trunc('month', s.expected_from), date_trunc('month', v_as_of), interval '1 month')::date loop
      v_exp := m + (least(s.usual_day, extract(day from (m + interval '1 month - 1 day'))::int) - 1);
      if v_exp < s.expected_from then continue; end if;
      -- 29 Sep 2026, ruling 1011: who paid is read AS OF the month's charge date, so a month before the switch
      -- keeps the owner's card and a month after it is the company's. Past months are never re-read as company.
      v_pf := public.fn_accountant_subscription_paid_from(s.vendor, v_exp);
      -- The month's charge: the vendor's entry nearest the usual date, within 5 days (a receipt, or his word).
      select x.* into e from public.expense_entries x
       where x.vendor ~* s.vendor_pattern and x.charged_on between v_exp - 5 and v_exp + 5
         and not ((coalesce(x.vendor, '') || ' ' || coalesce(x.note, '')) ~* 'zz[ _-]?demo')
       order by abs(x.charged_on - v_exp), x.id limit 1;
      if not found then
        if v_as_of > v_exp + 5 then
          v_missing := v_missing || jsonb_build_object('month', to_char(m, 'YYYY-MM'), 'expected_on', v_exp);
        end if;
        continue;
      end if;

      -- (a) Restate it at the bank value, once, after its expense journal has posted.
      if not exists (select 1 from public.gl_journal g where g.source = 'owner_card_bank_value' and g.source_ref = e.id::text) then
        select sum(jl.credit) into v_posted from public.gl_journal g join public.gl_journal_lines jl on jl.journal_id = g.id
         where g.source = 'expense' and g.source_ref = e.id::text and g.status = 'posted' and jl.account_code = '1000';
        if v_posted is not null then
          v_diff := s.bank_value_aed - v_posted;
          if v_diff < 0 or v_diff > 0.15 * s.bank_value_aed then
            -- ponytail: a gap over 15% is not FX and card fees; it is reported, never forced to the bank value.
            v_odd := v_odd || jsonb_build_object('vendor', s.vendor, 'entry', e.id, 'posted_aed', v_posted, 'bank_value_aed', s.bank_value_aed);
          elsif v_diff > 0 or v_pf = 'owner_card' then
            v_lines := '[]'::jsonb;
            if v_pf = 'owner_card' then
              v_lines := v_lines || jsonb_build_object('account', '1000', 'debit', v_posted,
                                      'memo', 'Not paid from the company bank: the owner''s card paid it');
            end if;
            if v_diff > 0 then
              v_lines := v_lines || jsonb_build_object('account', '6300', 'debit', v_diff, 'memo', 'FX and card fees above the receipt');
            end if;
            v_lines := v_lines || jsonb_build_object('account', case when v_pf = 'owner_card' then '2500' else '1000' end,
                         'credit', case when v_pf = 'owner_card' then s.bank_value_aed else v_diff end);
            perform public.fn_gl_entry(e.charged_on,
              s.vendor || ' ' || to_char(m, 'Mon YYYY') || ' at the bank value AED ' || s.bank_value_aed
                || ' (booked ' || v_posted || ', FX and card ' || v_diff || ')'
                || case when v_pf = 'owner_card' then ', paid on the owner''s card: due to owner' else '' end,
              'owner_card_bank_value', e.id::text, v_lines, 'accountant');
            v_booked := v_booked || jsonb_build_object('vendor', s.vendor, 'entry', e.id, 'posted_aed', v_posted, 'fx_card_aed', v_diff,
                                                       'bank_value_aed', s.bank_value_aed, 'paid_from', v_pf);
          end if;
        end if;
      end if;

      -- (b) A company_card charge is also on the Mashreq statement, once a statement covering it has arrived.
      if v_pf = 'company_card'
         and exists (select 1 from public.bank_statement_line b where b.account = 'mashreq' and b.value_date >= v_exp + 5) then
        v_line := null;
        select b.id into v_line from public.bank_statement_line b
         where b.account = 'mashreq' and b.value_date between v_exp - 5 and v_exp + 5
           and b.amount_aed between -1.02 * s.bank_value_aed and -0.98 * s.bank_value_aed
           and (s.bank_pattern is null or b.description ~* s.bank_pattern)
         order by abs(b.value_date - v_exp) limit 1;
        if v_line is null then
          v_noline := v_noline || jsonb_build_object('month', to_char(m, 'YYYY-MM'), 'entry', e.id);
        else
          v_matched := v_matched || jsonb_build_object('vendor', s.vendor, 'entry', e.id, 'bank_line', v_line);
        end if;
      end if;
    end loop;

    if jsonb_array_length(v_missing) > 0 then
      v_items := v_items || jsonb_build_object('item', 'missing_charge:' || lower(s.vendor), 'owner_seat', 'accountant',
        'subject', 'expense_entries', 'blast', 'internal', 'affected', jsonb_array_length(v_missing),
        'title', s.vendor || ': ' || jsonb_array_length(v_missing) || ' month(s) with no '
                 || case when s.receipt_emailed then 'receipt' else 'owner confirmation' end
                 || ' 5 days after the usual date (AED ' || s.bank_value_aed || ' a month, ' || replace(s.paid_from, '_', ' ') || ')',
        'evidence', jsonb_build_object('vendor', s.vendor, 'months', v_missing, 'paid_from', s.paid_from,
          'remedy', case when s.receipt_emailed then 'forward the month''s receipt to expenses@mail.quotesdone.com'
                         else 'the founder confirms the month''s charge; it is booked as a founder_statement at the bank value' end));
    end if;
    if jsonb_array_length(v_noline) > 0 then
      v_items := v_items || jsonb_build_object('item', 'bank_line_missing:' || lower(s.vendor), 'owner_seat', 'accountant',
        'subject', 'bank_statement_line', 'blast', 'internal', 'affected', jsonb_array_length(v_noline),
        'title', s.vendor || ' is paid by the company card but ' || jsonb_array_length(v_noline)
                 || ' month(s) have no Mashreq line of AED ' || s.bank_value_aed,
        'evidence', jsonb_build_object('vendor', s.vendor, 'months', v_noline,
          'remedy', 'read the statement for the charge; if the card did not move, set paid_from back to owner_card'));
    end if;
  end loop;

  if jsonb_array_length(v_odd) > 0 then
    v_items := v_items || jsonb_build_object('item', 'bank_value_mismatch', 'owner_seat', 'accountant', 'subject', 'gl_journal',
      'blast', 'internal', 'affected', jsonb_array_length(v_odd),
      'title', jsonb_array_length(v_odd) || ' ruled subscription charge(s) differ from the bank value by more than FX and card fees explain',
      'evidence', jsonb_build_object('entries', v_odd, 'remedy', 'read the receipt; a plan change needs a new bank value from the founder'));
  end if;

  return jsonb_build_object('as_of', v_as_of, 'restated', v_booked, 'bank_lines_matched', v_matched,
    'findings', public.fn_accountant_duty_settle('owner_card', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_party_flags(p_customer uuid DEFAULT NULL::uuid, p_supplier bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_all boolean := p_customer is null and p_supplier is null;
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_new int := 0; v_raised int := 0;
begin
  create temp table if not exists tmp_party_flag (kind text, subject_type text, subject_id text, severity text, detail jsonb) on commit drop;
  truncate tmp_party_flag;

  -- ── suppliers ──
  with s as (
    select l.id, l.company_name, l.licence_legal_name, l as lrow,
           lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email, ''))) as acct,
           lower(regexp_replace(btrim(coalesce(l.domain, '')), '^(https?://)?(www[.])?', '')) as site
      from public.leads l
     where (v_all and (coalesce(l.claimed, false) or l.lifecycle_stage = 'registered' or l.approval_status is not null)
                  and not coalesce(l.banned, false)
                  and (coalesce(l.is_demo, false) or coalesce(l.company_name, '') like 'ZZ DEMO%' or public.fn_is_demo_email(l.email)) = v_fx)
        or l.id = p_supplier
  ), c as (
    select s.*, public.fn_email_domain_class(s.acct) as cls, split_part(s.acct, '@', 2) as edom from s
  )
  insert into tmp_party_flag
  select 'company_name_mismatch', 'lead', c.id::text, 'high',
         jsonb_build_object('company_name', c.company_name, 'licence_legal_name', c.licence_legal_name)
    from c where public.fn_supplier_licence_name_mismatch(c.lrow)
  union all
  select 'disposable_email', 'lead', c.id::text, 'high', jsonb_build_object('account_email_domain', c.edom)
    from c where c.cls = 'disposable'
  union all
  select 'free_email_company', 'lead', c.id::text, 'low', jsonb_build_object('account_email_domain', c.edom, 'company_name', c.company_name)
    from c where c.cls = 'free'
  union all
  -- The website must be the company's OWN domain: a directory, host or marketplace page (email_platform_domain)
  -- says nothing about which domain the company mails from. A subdomain either way is the same company.
  select 'email_domain_mismatch', 'lead', c.id::text, 'medium',
         jsonb_build_object('account_email_domain', c.edom, 'website_domain', c.site, 'company_name', c.company_name)
    from c where c.cls = 'company' and c.site ~ '[.]' and c.edom <> c.site
     and c.edom not like '%.' || c.site and c.site not like '%.' || c.edom
     and not exists (select 1 from public.email_platform_domain e where e.domain in (c.site, c.edom))
  union all
  select 'dispute_pattern', 'lead', x.id::text, case when x.n >= 3 then 'high' else 'medium' end,
         jsonb_build_object('disputes_90d', x.d, 'refunds_paid_90d', x.r, 'window_days', 90)
    from (select c.id,
                 (select count(*) from public.post_reveal_dispute p where p.supplier_id = c.id and p.opened_at > now() - interval '90 days') as d,
                 (select count(*) from public.transactions t where t.supplier_id = c.id and t.refund_confirmed_at > now() - interval '90 days') as r,
                 (select count(*) from public.post_reveal_dispute p where p.supplier_id = c.id and p.opened_at > now() - interval '90 days')
                 + (select count(*) from public.transactions t where t.supplier_id = c.id and t.refund_confirmed_at > now() - interval '90 days') as n
            from c) x
   where x.n >= 2;

  -- ── customers ──
  with k as (
    select cu.* from public.customers cu
     where (v_all and not coalesce(cu.banned, false) and (coalesce(cu.is_demo, false) or public.fn_is_demo_email(cu.email)) = v_fx)
        or cu.id = p_customer
  )
  insert into tmp_party_flag
  select 'disposable_email', 'customer', k.id::text, 'high', jsonb_build_object('email_domain', split_part(lower(k.email), '@', 2))
    from k where public.fn_email_domain_class(k.email) = 'disposable'
  union all
  select 'refund_pattern', 'customer', x.id::text, case when x.n >= 3 then 'high' else 'medium' end,
         jsonb_build_object('refund_requests_90d', x.n, 'window_days', 90)
    from (select k.id, (select count(*) from public.transactions t
                         where t.customer_id = k.id and t.refund_requested_at > now() - interval '90 days') as n from k) x
   where x.n >= 2
  union all
  select 'dispute_pattern', 'customer', x.id::text, case when x.cb > 0 or x.d >= 3 then 'high' else 'medium' end,
         jsonb_build_object('chargebacks_180d', x.cb, 'disputes_raised_90d', x.d)
    from (select k.id,
                 (select count(*) from public.stripe_dispute sd join public.transactions t on t.id = sd.transaction_id
                   where t.customer_id = k.id and sd.first_seen_at > now() - interval '180 days') as cb,
                 (select count(*) from public.post_reveal_dispute p
                   where p.customer_id = k.id and p.raised_by = 'customer' and p.opened_at > now() - interval '90 days') as d
            from k) x
   where x.cb > 0 or x.d >= 2;

  -- ── write: once per (kind, subject); a closed flag stays closed; an OPEN flag whose severity rose is raised ──
  with ins as (
    insert into public.fraud_flags (kind, subject_type, subject_id, severity, detail, status, created_at, updated_at)
    select kind, subject_type, subject_id, severity,
           detail || jsonb_build_object('raised_by', 'accountant', 'owner_seat', 'accountant'), 'open', now(), now()
      from tmp_party_flag
    on conflict (kind, subject_type, subject_id) do nothing
    returning 1)
  select count(*) into v_new from ins;
  with up as (
    update public.fraud_flags f
       set severity = t.severity, detail = f.detail || t.detail || jsonb_build_object('severity_raised_at', now()), updated_at = now()
      from tmp_party_flag t
     where f.kind = t.kind and f.subject_type = t.subject_type and f.subject_id = t.subject_id and f.status = 'open'
       and array_position(array['low', 'medium', 'high'], t.severity) > coalesce(array_position(array['low', 'medium', 'high'], f.severity), 0)
    returning 1)
  select count(*) into v_raised from up;
  return jsonb_build_object('flagged', (select count(*) from tmp_party_flag), 'new', v_new, 'severity_raised', v_raised);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_payouts_record(p_livemode boolean, p_payouts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare x jsonb; n int := 0;
begin
  if jsonb_typeof(p_payouts) is distinct from 'array' then
    raise exception 'fn_accountant_payouts_record(livemode, payouts[]): an array of Stripe payout objects is required';
  end if;
  for x in select e from jsonb_array_elements(p_payouts) e loop
    if coalesce(x->>'id', '') !~ '^po_' or (x->>'amount') is null or (x->>'arrival_date') is null then
      raise exception 'fn_accountant_payouts_record: % is not a Stripe payout object', left(x::text, 200);
    end if;
    insert into public.stripe_payout (id, livemode, amount_fils, currency, status, arrival_date, created_at_stripe,
                                      method, destination, automatic, failure_code, failure_message, txn_count, txn_net_fils)
    values (x->>'id', p_livemode, (x->>'amount')::bigint, lower(x->>'currency'), x->>'status',
            (to_timestamp((x->>'arrival_date')::bigint) at time zone 'Asia/Dubai')::date,
            to_timestamp((x->>'created')::bigint), x->>'method', x->>'destination', (x->>'automatic')::boolean,
            x->>'failure_code', x->>'failure_message', (x->>'txn_count')::int, (x->>'txn_net')::bigint)
    on conflict (id) do update
       set status = excluded.status, arrival_date = excluded.arrival_date,
           failure_code = excluded.failure_code, failure_message = excluded.failure_message,
           txn_count = coalesce(excluded.txn_count, stripe_payout.txn_count),
           txn_net_fils = coalesce(excluded.txn_net_fils, stripe_payout.txn_net_fils),
           last_seen_at = now();
    n := n + 1;
  end loop;
  return jsonb_build_object('recorded', n, 'livemode', p_livemode);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_raise_nonresponse_charge(p_transaction_id uuid, p_notify boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb; t public.transactions; v_due bigint; v_new boolean := false;
begin
  if public.fn_refunds_paused() and coalesce(current_setting('app.qd_incident_fix', true), '') <> 'on' then
    return jsonb_build_object('ok', false, 'held', true,
      'reason', 'refunds and supplier charges are paused by the CEO''s circuit breaker; fn_ceo_refund_loop_sweep raises this charge when it lifts');
  end if;
  v := public.fn_accountant_nonresponse_charge(p_transaction_id, null);
  if not coalesce((v->>'ok')::boolean, false) then return v; end if;
  select * into t from public.transactions where id = p_transaction_id;

  select id into v_due from public.supplier_dues
   where transaction_id = p_transaction_id and coalesce(status, '') <> 'cancelled' order by id limit 1;
  if v_due is null then
    insert into public.supplier_dues (transaction_id, supplier_id, quote_id, quote_amount, commission_pct,
                                      amount_due, admin_fee, interest_amount, total_claim, currency,
                                      reveal_date, due_date, due_date_30, status)
    values (t.id, t.supplier_id, t.quote_id, t.quote_amount, null,
            (v->>'charge_aed')::numeric, (v->>'admin_fee_aed')::numeric, (v->>'interest_aed')::numeric, (v->>'total_aed')::numeric, 'AED',
            (t.revealed_at at time zone 'Asia/Dubai')::date, (v->>'due_date')::date, (v->>'due_date')::date + 23, 'due')
    returning id into v_due;
    update public.leads
       set matching_blocked = true,
           matching_block_reason = 'Unsettled non-response charge (the customer was refunded because the supplier did not respond)',
           rv_nonresponse_refunds = coalesce(rv_nonresponse_refunds, 0) + 1
     where id = t.supplier_id;
    v_new := true;
  end if;

  if p_notify then
    perform public.fn_seat_handoff('accountant', 'sales_engineer', 'nonresponse.charge_raised', 'supplier_dues', v_due::text,
      v || jsonb_build_object('due_id', v_due, 'transaction_id', t.id, 'supplier_id', t.supplier_id,
                              'inquiry_id', t.inquiry_id, 'quote_id', t.quote_id));
  end if;
  return v || jsonb_build_object('due_id', v_due, 'created', v_new);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_reading_context()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'vendors', coalesce((select jsonb_agg(v order by v) from (
        select btrim(vendor) v from public.expense_entries where coalesce(btrim(vendor), '') <> ''
        union select btrim(vendor) from public.expenses where coalesce(btrim(vendor), '') <> ''
        union select btrim(x) from public.decision_policy d, jsonb_array_elements_text(d.value) x
               where d.key = 'accountant_expected_subscription_vendors') s
       where v !~* 'zz[ _-]?demo'), '[]'::jsonb),
    'register', coalesce((select jsonb_agg(jsonb_build_object('vendor', vendor, 'cadence', cadence) order by vendor)
                            from public.expenses where active), '[]'::jsonb),
    'renewals', coalesce((select jsonb_agg(jsonb_build_object('item', item, 'kind', kind, 'expires_on', expires_on) order by item)
                            from public.it_expiry where kind in ('licence', 'domain')), '[]'::jsonb));
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_receipt_bank_match()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_days int; v_pct numeric; v_floor numeric; v_usd numeric;
  e int; n_matched int := 0;
begin
  select num_value::int into v_days  from public.gl_settings where key = 'receipt_match_days';
  select num_value      into v_pct   from public.gl_settings where key = 'receipt_match_tolerance_pct';
  select num_value      into v_floor from public.gl_settings where key = 'receipt_match_tolerance_aed';
  select num_value      into v_usd   from public.gl_settings where key = 'usd_to_aed';
  if v_days is null or v_pct is null or v_floor is null or v_usd is null then
    raise exception 'fn_accountant_receipt_bank_match: a receipt_match_* window or usd_to_aed is missing from gl_settings';
  end if;

  -- Every (unmatched receipt, unmatched debit) pair that fits on account, amount and date, with whether
  -- the debit's text carries the receipt vendor's first 3+ character word (after any ZZ DEMO prefix).
  drop table if exists pg_temp.rbm_cand;
  create temp table rbm_cand on commit drop as
  select x.id as eid, bl.id as lid, r.aed as receipt_aed, -bl.amount_aed as bank_aed,
         bl.value_date - x.charged_on as gap,
         (r.tok is not null and position(r.tok in lower(coalesce(bl.description, '') || ' ' || coalesce(bl.reference, ''))) > 0) as hit
    from public.expense_entries x
    cross join lateral (select round(x.amount * case when upper(x.currency) = 'USD' then v_usd else 1 end, 2) as aed,
                               lower(substring(regexp_replace(coalesce(x.vendor, ''), '^\s*ZZ DEMO\s*', '', 'i')
                                               from '[A-Za-z0-9]{3,}')) as tok) r
    join public.bank_statement_line bl
      on bl.amount_aed < 0
     and (bl.account = 'zz_demo') = (x.vendor ilike 'ZZ DEMO%')
     and abs(-bl.amount_aed - r.aed) <= greatest(v_floor, r.aed * v_pct / 100)
     and bl.value_date between x.charged_on - 1 and x.charged_on + v_days
   where x.amount > 0 and upper(x.currency) in ('AED', 'USD')
     and not exists (select 1 from public.expense_bank_match m where m.expense_entry_id = x.id)
     and not exists (select 1 from public.expense_bank_match m where m.bank_line_id = bl.id);

  -- A receipt whose fitting debits carry no vendor word is never booked: it is listed ambiguous.
  -- Only vendor-word pairs can be booked, and only when the pairing is forced, never by order:
  -- a receipt with exactly one such debit takes it unless another receipt has that same debit as
  -- ITS only one too (contested). Each booking removes both sides and the rest is re-read, so a
  -- later receipt whose only debit an earlier receipt could also use gets it, and the earlier one
  -- is left with its own. Whatever is still open is ambiguous for the accountant.
  drop table if exists pg_temp.rbm_open;
  create temp table rbm_open on commit drop as select * from rbm_cand where hit;
  loop
    with only_one as (
      select eid, min(lid) as lid from rbm_open group by eid having count(*) = 1
    ), forced as (
      select o.eid, o.lid from only_one o
       where (select count(*) from only_one o2 where o2.lid = o.lid) = 1
    ), booked as (
      insert into public.expense_bank_match (expense_entry_id, bank_line_id, receipt_aed, bank_aed, day_gap, vendor_in_text)
      select c.eid, c.lid, c.receipt_aed, c.bank_aed, c.gap, true
        from forced f join rbm_open c on c.eid = f.eid and c.lid = f.lid
      returning expense_entry_id, bank_line_id
    ), gone as (
      delete from rbm_open c using booked b where c.eid = b.expense_entry_id or c.lid = b.bank_line_id
      returning 1
    )
    select count(*) into e from booked;
    exit when e = 0;
    n_matched := n_matched + e;
  end loop;

  return jsonb_build_object(
    'matched_now', n_matched,
    'matched', (select count(*) from public.expense_bank_match),
    -- Receipts with a fitting debit that were NOT booked, for the accountant to decide: never posted.
    'ambiguous', (select coalesce(jsonb_agg(jsonb_build_object('expense_entry', a.eid,
                     'reason', case when not bool_or_hit then 'no_vendor_word'
                                    when open_n > 1 then 'several_debits' else 'contested' end,
                     'lines', a.lines) order by a.eid), '[]'::jsonb)
                    from (select c.eid, bool_or(c.hit) as bool_or_hit,
                                 (select count(*) from rbm_open o where o.eid = c.eid) as open_n,
                                 jsonb_agg(c.lid order by c.lid) as lines
                            from rbm_cand c
                           where not exists (select 1 from public.expense_bank_match m where m.expense_entry_id = c.eid)
                             and not exists (select 1 from public.expense_bank_match m where m.bank_line_id = c.lid)
                           group by c.eid) a),
    'receipts_not_matchable', (select count(*) from public.expense_entries x
                                where not (x.amount > 0 and upper(coalesce(x.currency, '')) in ('AED', 'USD'))),
    -- Receipts inside a statement's coverage (and past the window) with no debit: paid elsewhere, or missing.
    'receipts_unmatched', (select coalesce(jsonb_agg(jsonb_build_object('expense_entry', x.id, 'vendor', x.vendor,
                              'amount', x.amount, 'currency', x.currency, 'charged_on', x.charged_on) order by x.charged_on), '[]'::jsonb)
                             from public.expense_entries x
                            where x.amount > 0 and upper(x.currency) in ('AED', 'USD')
                              and not exists (select 1 from public.expense_bank_match m where m.expense_entry_id = x.id)
                              and not exists (select 1 from rbm_cand c where c.eid = x.id
                                                and not exists (select 1 from public.expense_bank_match m where m.bank_line_id = c.lid))
                              and exists (select 1 from public.bank_statement_line bl
                                           where (bl.account = 'zz_demo') = (x.vendor ilike 'ZZ DEMO%')
                                             and bl.value_date <= x.charged_on - 1)
                              and exists (select 1 from public.bank_statement_line bl
                                           where (bl.account = 'zz_demo') = (x.vendor ilike 'ZZ DEMO%')
                                             and bl.value_date >= x.charged_on + v_days)),
    -- Debits the bank did not book itself, with no receipt: a payment the mailbox never received a document for.
    'bank_debits_unmatched', (select coalesce(jsonb_agg(jsonb_build_object('line', bl.id, 'account', bl.account,
                              'value_date', bl.value_date, 'amount_aed', bl.amount_aed,
                              'description', public.fn_mask_bank_text(bl.description)) order by bl.value_date), '[]'::jsonb)
                             from public.bank_statement_line bl
                            where bl.amount_aed < 0
                              and bl.kind is distinct from 'bank_charge'
                              and not exists (select 1 from public.expense_bank_match m where m.bank_line_id = bl.id)),
    'basis', 'Receipts (expense_entries, from the expenses mailbox) against Mashreq debits: amount within '
             || v_pct || '% (floor AED ' || v_floor || '), USD at ' || v_usd || ', value date ' || '-1..+' || v_days
             || ' days, vendor word in the line preferred. Bank charges book themselves and are not expected to carry a receipt. Nothing was posted to the ledger.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_receipt_cadence_gaps(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tz      text := 'Asia/Dubai';
  v_as_of   date;
  v_gaps    jsonb;
  v_stale   jsonb;
  v_single  jsonb;
  v_ended   jsonb;
  v_n_gap   int;
  v_n_stale int;
  v_n_once  int;
  v_portal   jsonb;
  v_n_portal int;
begin
  v_as_of := coalesce(p_as_of, (now() at time zone v_tz)::date);

  with per_vendor_month as (
    select vendor, date_trunc('month', charged_on)::date mo, count(*) n
      from public.expense_entries
     group by vendor, date_trunc('month', charged_on)::date
  ),
  span as (
    select vendor, min(mo) first_mo, max(mo) last_mo, count(*) months_seen, sum(n) receipts
      from per_vendor_month group by vendor
  ),
  -- TWO distinct months, not three. Requiring three examined neither vendor this was written to
  -- catch: Anthropic had two months booked and Google two. A threshold that excludes the case the
  -- guard exists for is the guard not existing, and it fails in the flattering direction.
  cadenced as (
    select * from span where months_seen >= 2
  ),
  expected as (
    select c.vendor, gs::date mo
      from cadenced c
      cross join lateral generate_series(c.first_mo, c.last_mo, interval '1 month') gs
  ),
  -- A month INSIDE the vendor's own run with no receipt. NEVER suppressed by an explanation: a
  -- vendor that billed May, skipped June and billed July has a real hole whatever happened after.
  gap as (
    select e.vendor, to_char(e.mo, 'YYYY-MM') missing_month
      from expected e
      left join per_vendor_month p on p.vendor = e.vendor and p.mo = e.mo
     where p.vendor is null
  ),
  -- Billed on a cadence, then silent for more than 45 days. 45 rather than 31 so a charge landing a
  -- few days late does not cry wolf. Suppressed only by a recorded explanation.
  stale as (
    select c.vendor, to_char(c.last_mo, 'YYYY-MM') last_month,
           (v_as_of - c.last_mo) days_since_last_month_started, c.receipts
      from cadenced c
      left join public.vendor_billing_ended e on e.vendor = c.vendor
     where v_as_of - c.last_mo > 45 and e.vendor is null
  ),
  -- ONE receipt, silent, and nobody has said why. This is the STRONGEST case, not the weakest: if
  -- that vendor is a monthly subscription then every renewal after it is missing, and no other check
  -- here can see it, because one month is not a cadence. It fed nothing until 9 Sep 2026, which is
  -- how a report claimed completeness while the founder's ChatGPT renewals were unaccounted for.
  single_receipt as (
    select s.vendor, to_char(s.first_mo, 'YYYY-MM') only_month,
           (v_as_of - s.first_mo) days_since
      from span s
      left join public.vendor_billing_ended e on e.vendor = s.vendor
     where s.receipts = 1 and v_as_of - s.first_mo > 45 and e.vendor is null
  ),
  -- STILL BILLING, NEVER EMAILS. The money is missing and the remedy is known: fetch the invoice
  -- from the vendor's own portal. This is a shortfall like any other -- it just carries its answer.
  portal_billing as (
    select s.vendor, to_char(s.last_mo, 'YYYY-MM') last_month, s.receipts,
           (v_as_of - s.last_mo) days_since, e.note
      from span s
      join public.vendor_billing_ended e on e.vendor = s.vendor and e.kind = 'portal_only'
     where v_as_of - s.last_mo > 45
  ),
  explained as (
    select vendor, to_char(ended_after, 'YYYY-MM') ended_after_month, kind, basis
      from public.vendor_billing_ended
  )
  select
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'missing_month', missing_month)
              order by vendor, missing_month), '[]'::jsonb) from gap),
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'last_month', last_month,
              'receipts_seen', receipts, 'days_since', days_since_last_month_started)
              order by vendor), '[]'::jsonb) from stale),
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'only_month', only_month,
              'days_since', days_since) order by vendor), '[]'::jsonb) from single_receipt),
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'kind', kind,
              'since', ended_after_month, 'basis', basis) order by vendor), '[]'::jsonb) from explained),
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'last_billed', last_month,
              'days_since', days_since, 'remedy', note) order by vendor), '[]'::jsonb) from portal_billing)
    into v_gaps, v_stale, v_single, v_ended, v_portal;

  v_n_gap    := jsonb_array_length(v_gaps);
  v_n_stale  := jsonb_array_length(v_stale);
  v_n_once   := jsonb_array_length(v_single);
  v_n_portal := jsonb_array_length(v_portal);

  return jsonb_build_object(
    'as_of', v_as_of,
    'timezone', v_tz,
    'basis', 'Measured from the VENDOR side: what each vendor billed, not what the mailbox received. '
          || 'The intake-side checks (held, refused, unconvertible, unposted) cannot see a receipt '
          || 'that never arrived, which is why a report can read complete while a subscription is '
          || 'missing three months.',
    'months_with_no_receipt_inside_a_run', v_gaps,
    'vendors_gone_quiet', v_stale,
    'vendors_seen_once_unexplained', v_single,
    'vendors_with_a_recorded_reason', v_ended,
    'vendors_billing_outside_email', v_portal,
    'suspected_missing', v_n_gap + v_n_stale + v_n_once + v_n_portal,
    'claim', case when v_n_gap + v_n_stale + v_n_once + v_n_portal = 0
              then 'No vendor is missing a month, unexplained-quiet, or seen once without a reason. '
                || 'That is NOT a claim that the book is complete: a vendor never forwarded even '
                || 'once is invisible to this and to every other check here.'
              else 'These are SUSPECTED gaps, not proven ones -- a subscription can be cancelled, '
                || 'downgraded or paused, and a one-off purchase legitimately bills once. Each '
                || 'carries the evidence that produced it, and any of them can be closed for good by '
                || 'recording the vendor in vendor_billing_ended as ended, annual or one_off. The '
                || 'book should not be called complete while one stands unexplained.' end);
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_receipt_incident_learning(p_issue_key text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int;
begin
  if p_issue_key not in ('acct:expenses:cadence_gaps', 'acct:expenses:never_billed', 'acct:expenses:renewal_receipt')
     or not exists (select 1 from public.company_policy_decision where decision_key = 'expenses_receipts_are_an_ongoing_routine') then
    return 0;
  end if;
  update public.it_incident i
     set cause = coalesce(nullif(btrim(i.cause), ''),
           'Not a fault: a receipt the founder has not forwarded yet. Founder instruction 585 (21 Sep 2026) rules receipts '
           || 'an ongoing routine he forwards to the expenses mailbox whenever he chooses; the accountant reads the mailbox.'),
         fix = coalesce(nullif(btrim(i.fix), ''),
           'Recorded as company_policy_decision expenses_receipts_are_an_ongoing_routine; fn_accountant_duty_settle returns '
           || 'the item as `waiting` in the expenses duty result and raises no finding while that decision stands.'),
         regression_check = coalesce(nullif(btrim(i.regression_check), ''),
           'scripts/sql/a_missing_receipt_the_founder_ruled_a_waiting_item_leaves_no_open_handoff.sql (probe row)'),
         not_automatable_reason = coalesce(nullif(btrim(i.not_automatable_reason), ''),
           'Nothing to automate: the receipt exists only when the founder forwards it.'),
         recorded_by = coalesce(i.recorded_by, 'accountant (founder decision expenses_receipts_are_an_ongoing_routine)'),
         ended_at = coalesce(i.ended_at, now()),
         updated_at = now()
   where i.issue_key = p_issue_key
     and (coalesce(btrim(i.cause), '') = '' or coalesce(btrim(i.fix), '') = '' or coalesce(btrim(i.regression_check), '') = ''
          or (i.playbook_class is null and coalesce(btrim(i.not_automatable_reason), '') = ''));
  get diagnostics n = row_count;
  return n;
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_receipt_intake_duty()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c public.accountant_mailbox_check; e record; n_posted int := 0; n_owned int;
begin
  select * into c from public.accountant_mailbox_check order by checked_at desc limit 1;
  -- a stalled intake is a seat failure: the duty fails, so its last_ok_at stops and the seat shows red
  if c.id is null or c.checked_at < now() - interval '26 hours' then
    raise exception 'the expenses mailbox has not been checked since % (accountant_mailbox_check)', coalesce(c.checked_at::text, 'ever');
  end if;
  if c.not_taken_in > 0 then
    raise exception '% email(s) in the expenses mailbox were never taken in (check #% at %)', c.not_taken_in, c.id, c.checked_at;
  end if;

  -- booked from the mailbox but not in the ledger: post it (AED and USD only; another currency is the routine's own refusal)
  for e in select x.id from public.expense_entries x
            where x.source_msg_id is not null and upper(coalesce(x.currency, 'AED')) in ('AED', 'USD') and coalesce(x.amount, 0) > 0
              and (coalesce(x.vendor, '') || ' ' || coalesce(x.note, '')) !~* 'zz[ _-]?demo'
              and not exists (select 1 from public.gl_journal g where g.source = 'expense' and g.source_ref = x.id::text) loop
    if public.fn_expense_post_to_gl(e.id) is not null then n_posted := n_posted + 1; end if;
  end loop;

  -- a held expenses-mailbox email belongs to the accountant, never to nobody
  update public.inbound_messages m set owner_role = 'accountant'
   where m.owner_role is null and m.needs_review and m.replied_at is null and m.to_email ilike 'expenses@%';
  get diagnostics n_owned = row_count;

  return jsonb_build_object('mailbox_checked_at', c.checked_at, 'verdict', c.verdict, 'listed', c.listed,
    'held_over_24h', c.held_over_24h, 'posted_to_ledger', n_posted, 'held_given_an_owner', n_owned,
    'held_now', (select count(*) from public.inbound_messages where to_email ilike 'expenses@%' and needs_review and replied_at is null));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_record_court_step(p_due_id bigint, p_step text, p_on date, p_reference text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.supplier_dues; r record; v_today date := (now() at time zone 'Asia/Dubai')::date; v_warn text[] := '{}';
begin
  if p_step not in ('filed', 'order_issued', 'order_served', 'grievance_filed', 'recovered', 'withdrawn') then
    raise exception 'a court step is one of filed, order_issued, order_served, grievance_filed, recovered, withdrawn (got %)', p_step;
  end if;
  if p_on is null or p_on > v_today then raise exception 'a court step is recorded on the day it happened, not before it (got %)', p_on; end if;
  select * into d from public.supplier_dues where id = p_due_id for update;
  if not found then raise exception 'no supplier due %', p_due_id; end if;
  if not public.fn_supplier_due_is_owed(d.status, d.paid_at) then
    raise exception 'due % is closed (%); nothing more is recorded against it', p_due_id, coalesce(d.status, 'paid');
  end if;
  select * into r from public.v_accountant_recovery_ledger where due_id = p_due_id;

  if p_step = 'filed' then
    if d.legal_escalated_at is null then
      raise exception 'due % has had no formal demand: CPL 42/2022 Art 144(1) requires the notice for payment before a payment order', p_due_id;
    end if;
    if p_on < r.payment_order_earliest_on then
      v_warn := v_warn || ('filed on ' || p_on || ', before ' || r.payment_order_earliest_on || ' when the demand''s period ran out');
    end if;
    if d.legal_stage in ('filing_pack_due', 'filing_pack_sent') then
      perform public.fn_accountant_record_filing_outcome(p_due_id, 'filed', p_reference);
    end if;
    update public.supplier_dues set payment_order_filed_on = p_on,
           court_reference = coalesce(nullif(btrim(p_reference), ''), court_reference) where id = p_due_id;
  elsif p_step = 'order_issued' then
    if d.payment_order_filed_on is null or p_on < d.payment_order_filed_on then
      raise exception 'due %: record the filing first, on or before the day the order was issued', p_due_id;
    end if;
    update public.supplier_dues set payment_order_issued_on = p_on,
           court_reference = coalesce(nullif(btrim(p_reference), ''), court_reference) where id = p_due_id;
  elsif p_step = 'order_served' then
    if d.payment_order_issued_on is null or p_on < d.payment_order_issued_on then
      raise exception 'due %: record the issued order first, on or before the day it was served', p_due_id;
    end if;
    if p_on > r.serve_order_by then
      v_warn := v_warn || ('served on ' || p_on || ', after ' || r.serve_order_by || ': under CPL Art 146(2) the order is void');
    end if;
    update public.supplier_dues set payment_order_served_on = p_on where id = p_due_id;
  elsif p_step = 'grievance_filed' then
    if d.payment_order_served_on is null or p_on < d.payment_order_served_on then
      raise exception 'due %: record the service first; a grievance runs from service (CPL Art 147(1))', p_due_id;
    end if;
    if p_on > r.grievance_until then
      v_warn := v_warn || ('grievance filed on ' || p_on || ', after the 15 days that ended ' || r.grievance_until);
    end if;
    update public.supplier_dues set grievance_filed_on = p_on where id = p_due_id;
  elsif p_step = 'recovered' then
    update public.supplier_dues set status = 'settled', paid_at = p_on::timestamp at time zone 'Asia/Dubai',
           payment_ref = coalesce(nullif(btrim(p_reference), ''), payment_ref) where id = p_due_id;
  else
    update public.supplier_dues set status = 'waived' where id = p_due_id;
  end if;
  return jsonb_build_object('ok', true, 'due_id', p_due_id, 'step', p_step, 'on', p_on, 'warnings', to_jsonb(v_warn));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_record_filing_outcome(p_due_id bigint, p_outcome text, p_reference text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_outcome not in ('filed', 'paid_after_demand', 'settled', 'withdrawn', 'judgment') then
    raise exception 'a filing outcome is one of filed, paid_after_demand, settled, withdrawn, judgment (got %)', p_outcome;
  end if;
  update public.supplier_dues
     set legal_stage = 'outcome:' || p_outcome || coalesce(' ' || nullif(btrim(p_reference), ''), ''),
         status = case when p_outcome in ('paid_after_demand', 'settled') then 'settled'
                       when p_outcome = 'withdrawn' then 'waived' else status end
   where id = p_due_id and legal_stage in ('filing_pack_due', 'filing_pack_sent');
  if not found then return jsonb_build_object('ok', false, 'reason', 'due ' || p_due_id || ' is not waiting for a filing outcome'); end if;
  return jsonb_build_object('ok', true, 'due_id', p_due_id, 'outcome', p_outcome);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_record_supplier_payment(p_due_id bigint, p_amount numeric, p_paid_on date, p_reference text, p_entered_by text DEFAULT 'accountant'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.supplier_dues; v_id bigint; v jsonb; v_owed numeric; v_today date := (now() at time zone 'Asia/Dubai')::date;
begin
  if coalesce(p_entered_by, '') not in ('accountant', 'service') then
    return jsonb_build_object('ok', false, 'reason', 'entered_by must be accountant or service');
  end if;
  if p_amount is null or p_amount <= 0 then return jsonb_build_object('ok', false, 'reason', 'the amount must be above zero'); end if;
  if p_paid_on is null or p_paid_on > v_today then
    return jsonb_build_object('ok', false, 'reason', 'the payment date is missing or in the future');
  end if;
  if nullif(btrim(p_reference), '') is null then return jsonb_build_object('ok', false, 'reason', 'a bank or Stripe reference is required'); end if;
  select * into d from public.supplier_dues where id = p_due_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such due'); end if;
  if d.paid_at is not null or coalesce(d.status, '') in ('paid', 'settled', 'waived', 'reversed', 'refunded', 'cancelled', 'void') then
    return jsonb_build_object('ok', false, 'reason', 'this due is ' || coalesce(nullif(d.status, ''), 'paid') || ', so nothing is owed on it');
  end if;
  v_owed := least((public.fn_supplier_dues_outstanding(array[d.id], p_paid_on) -> d.id::text ->> 'owed_aed')::numeric,
                  (public.fn_supplier_dues_outstanding(array[d.id], v_today)   -> d.id::text ->> 'owed_aed')::numeric);
  if v_owed is null or round(p_amount, 2) > v_owed then
    perform public.fn_it_engineer_finding_upsert('acct:supplier_overpayment:' || d.id || ':' || btrim(p_reference),
      'An attempt to record AED ' || round(p_amount, 2) || ' against supplier due ' || d.id || ' exceeds the AED ' || coalesce(v_owed, 0) || ' still owed',
      'public.fn_accountant_record_supplier_payment', 'agent_facing', 1,
      jsonb_build_object('due_id', d.id, 'amount_aed', round(p_amount, 2), 'owed_aed', v_owed, 'paid_on', p_paid_on,
                         'reference', btrim(p_reference), 'entered_by', p_entered_by, 'owner_seat', 'accountant', 'raised_by_seat', 'accountant'),
      '{}'::text[], '{}'::text[], 'accountant');
    return jsonb_build_object('ok', false, 'reason', 'the amount is above the AED ' || coalesce(v_owed, 0) || ' still owed on this due; nothing was recorded', 'owed_aed', v_owed);
  end if;
  insert into public.supplier_due_payments (due_id, paid_on, amount_aed, reference, entered_by)
  values (p_due_id, p_paid_on, round(p_amount, 2), btrim(p_reference), p_entered_by)
  on conflict (due_id, reference) do nothing returning id into v_id;
  if v_id is null then
    return jsonb_build_object('ok', false, 'reason', 'this reference is already recorded against this due, so the payment is not counted twice');
  end if;
  v := case when d.transaction_id is not null then public.fn_accountant_nonresponse_charge(d.transaction_id, null) end;
  -- settled only when nothing is outstanding on the same figure the cap reads (principal, interest, fees and any legacy
  -- fine; a due with no transaction reads its stored columns less payments)
  v_owed := (public.fn_supplier_dues_outstanding(array[d.id], v_today) -> d.id::text ->> 'owed_aed')::numeric;
  if v_owed <= 0 then
    update public.supplier_dues set paid_at = now(), status = 'paid', payment_ref = btrim(p_reference) where id = p_due_id;
  end if;
  return jsonb_build_object('ok', true, 'payment_id', v_id, 'due_id', p_due_id, 'settled', v_owed <= 0, 'owed_aed', v_owed,
                            'paid_aed', v->'paid_aed', 'unpaid_principal_aed', v->'unpaid_principal_aed', 'interest_aed', v->'interest_aed', 'total_aed', v->'total_aed');
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_recovery_position()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'open_claims', count(*) filter (where owed),
    'open_aed', coalesce(sum(claim_aed) filter (where owed), 0),
    'in_court', count(*) filter (where stage in ('filed', 'order_issued', 'order_served', 'grievance_filed')),
    'by_stage', coalesce((select jsonb_object_agg(stage, n) from (select stage, count(*) n from public.v_accountant_recovery_ledger
                                                                   where not demo group by stage) s), '{}'::jsonb),
    'recovered_aed', coalesce(sum(claim_aed) filter (where stage in ('paid', 'settled')), 0),
    'basis', 'public.v_accountant_recovery_ledger, ZZ DEMO suppliers excluded. claim_aed is the refund, the AED 250 fee and the 9% simple interest accrued by fn_supplier_dues_accrue_interest.')
  from public.v_accountant_recovery_ledger where not demo;
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_recovery_tick(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_warn int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_serve_warn_days');
  v_decide int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_order_decision_days');
  r record; v_items jsonb := '[]'::jsonb; v_ev jsonb; n int := 0;
begin
  if v_warn is null or v_decide is null then
    raise exception 'decision_policy supplier_charge_serve_warn_days and supplier_charge_order_decision_days are required';
  end if;
  for r in select * from public.v_accountant_recovery_ledger
            where stage in ('filed', 'order_issued', 'order_served', 'grievance_filed') order by due_id loop
    n := n + 1;
    v_ev := jsonb_build_object('due_id', r.due_id, 'supplier', r.supplier, 'claim_aed', r.claim_aed, 'stage', r.stage,
                               'court_reference', r.court_reference, 'legal_pack', r.legal_pack, 'case_file_path', r.case_file_path);
    if r.payment_order_filed_on is not null and r.payment_order_earliest_on is not null and r.payment_order_filed_on < r.payment_order_earliest_on then
      v_items := v_items || jsonb_build_object('item', 'filed_early:' || r.due_id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', 'Charge #' || r.due_id || ' was filed on ' || r.payment_order_filed_on || ', before the demand''s period ran out on '
                 || r.payment_order_earliest_on || ' (CPL 42/2022 Art 144(1)); the court may refuse the order',
        'blast', 'agent_facing', 'affected', 1, 'demo', r.demo, 'evidence', v_ev);
    end if;
    if r.stage = 'filed' and r.payment_order_filed_on is not null and v_as_of > r.payment_order_filed_on + v_decide then
      v_items := v_items || jsonb_build_object('item', 'order_awaited:' || r.due_id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', 'Charge #' || r.due_id || ' was filed on ' || r.payment_order_filed_on
                 || ' and no payment order is recorded; CPL Art 144(4) gives the judge 3 business days',
        'blast', 'agent_facing', 'affected', 1, 'demo', r.demo, 'evidence', v_ev);
    elsif r.stage = 'order_issued' and v_as_of >= r.serve_order_by - v_warn then
      v_items := v_items || jsonb_build_object('item', 'serve:' || r.due_id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', case when v_as_of > r.serve_order_by
                      then 'The payment order on charge #' || r.due_id || ' was not served by ' || r.serve_order_by || ' and is void (CPL Art 146(2)); file again or withdraw'
                      else 'The payment order on charge #' || r.due_id || ' must be served by ' || r.serve_order_by || ' or it is void (CPL Art 146(2))' end,
        'blast', 'agent_facing', 'affected', 1, 'demo', r.demo, 'evidence', v_ev || jsonb_build_object('serve_order_by', r.serve_order_by));
    elsif r.stage = 'order_served' and v_as_of > r.grievance_until then
      v_items := v_items || jsonb_build_object('item', 'enforce:' || r.due_id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', 'No grievance against the payment order on charge #' || r.due_id || ' by ' || r.grievance_until
                 || ' (CPL Art 147(1)): the order is final; apply for execution and record the recovery',
        'blast', 'agent_facing', 'affected', 1, 'demo', r.demo, 'evidence', v_ev || jsonb_build_object('grievance_until', r.grievance_until));
    elsif r.stage = 'grievance_filed' then
      v_items := v_items || jsonb_build_object('item', 'grievance:' || r.due_id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', r.supplier || ' filed a grievance on ' || r.grievance_filed_on || ' against the payment order on charge #' || r.due_id
                 || '; the court decides it, and the outcome is recorded here',
        'blast', 'agent_facing', 'affected', 1, 'demo', r.demo, 'evidence', v_ev);
    end if;
  end loop;
  return jsonb_build_object('in_court', n, 'findings', public.fn_accountant_duty_settle('recovery', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_refund_correctness(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_m date := date_trunc('month', p_month)::date; v_n int; v_ok int; v_bad jsonb;
begin
  with r as (
    select t.id, round(t.total_charged * 100)::bigint as paid_fils, t.payment_ref,
           sum(f.amount_fils) as refunded_fils,
           bool_and(f.refund_decision_id is not null) as approved,
           bool_and(f.stripe_refund_id is not null and (f.stripe_payment_intent = t.payment_ref or f.stripe_charge_id = t.payment_ref)) as same_charge
      from public.refunds f join public.transactions t on t.id = f.transaction_id
     where f.status = 'succeeded' and f.settled_at >= v_m and f.settled_at < v_m + interval '1 month'
     group by t.id, t.total_charged, t.payment_ref)
  select count(*), count(*) filter (where refunded_fils = paid_fils and approved and same_charge),
         coalesce(jsonb_agg(jsonb_build_object('transaction_id', id, 'paid_fils', paid_fils, 'refunded_fils', refunded_fils,
                  'ceo_approved', approved, 'same_charge', same_charge)) filter (where not (refunded_fils = paid_fils and approved and same_charge)), '[]')
    into v_n, v_ok, v_bad from r;
  return jsonb_build_object('month', to_char(v_m, 'YYYY-MM'), 'refunds', v_n, 'correct', v_ok,
    'correct_pct', case when v_n > 0 then round(100.0 * v_ok / v_n, 1) end, 'incorrect', v_bad,
    'basis', 'A succeeded refund is correct when the refunded total equals what the customer paid (total_charged), every refund row carries a CEO approval (refund_decision_id) and a Stripe refund against the same payment (payment_ref).');
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_refund_correctness_check()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_now jsonb := public.fn_accountant_refund_correctness(current_date);
        v_prev jsonb := public.fn_accountant_refund_correctness((current_date - interval '1 month')::date); v jsonb; v_rep int := 0;
begin
  foreach v in array array[v_prev, v_now] loop
    if jsonb_array_length(v->'incorrect') > 0 then
      perform public.fn_support_report_to_ceo(
        p_idempotency_key => 'refund_correctness:' || (v->>'month') || ':' || (v->>'correct'), p_severity => 'serious',
        p_subject => 'Refund correctness ' || (v->>'month') || ': ' || (v->>'correct') || ' of ' || (v->>'refunds') || ' refunds correct',
        p_evidence => v, p_attempted => '[]'::jsonb,
        p_requested => 'Review each listed refund: amount, approval and charge must all match.',
        p_review_in => interval '3 days', p_source_agent => 'accountant');
      v_rep := v_rep + 1;
    end if;
  end loop;
  return jsonb_build_object('previous_month', v_prev, 'this_month', v_now, 'reported', v_rep);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_refund_reserve()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'held_for_possible_refunds_aed', coalesce(sum(held_aed) filter (where not demo), 0),
    'reveals', count(*) filter (where not demo),
    'demo_held_aed', coalesce(sum(held_aed) filter (where demo), 0),
    'lines', coalesce(jsonb_agg(jsonb_build_object('transaction_id', transaction_id, 'held_aed', held_aed, 'reason', reason, 'demo', demo)
                                order by transaction_id), '[]'::jsonb),
    'basis', 'Open refund cases at their amount, and paid unrefunded reveals inside transactions.refund_deadline at total_charged, each transaction once. Revenue booked to 4000 includes this money; it is not earned while it can still be refunded. ZZ DEMO customers are shown apart and not counted.')
  from public.v_accountant_refund_reserve;
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_refund_settled(p_transaction_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t public.transactions; v_reason text; v_charge jsonb; v_verify jsonb;
begin
  select * into t from public.transactions where id = p_transaction_id;
  select coalesce((select r.reason_code from public.refunds r where r.transaction_id = t.id order by r.id desc limit 1),
                  t.refund_reason, 'supplier_unresponsive') into v_reason;
  if v_reason = 'supplier_unresponsive' then
    v_charge := public.fn_accountant_raise_nonresponse_charge(t.id, true);
  end if;
  perform public.fn_seat_handoff('accountant', 'sales_engineer', 'refund.paid', 'transactions', t.id::text,
    jsonb_build_object('transaction_id', t.id, 'customer_id', t.customer_id, 'supplier_id', t.supplier_id,
                       'inquiry_id', t.inquiry_id, 'quote_id', t.quote_id, 'revealed_at', t.revealed_at,
                       'amount_aed', round(t.refund_amount_aed, 2)));
  v_verify := public.fn_ceo_refund_verify(t.id);
  return jsonb_build_object('charge', v_charge, 'verify', v_verify);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_remediates(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d jsonb; v_fils bigint; v_n int;
begin
  select detail into d from public.agent_actions where id = p_id;
  if d->'checks' ? 'amount_equals_total_charged' then
    update public.refunds r
       set amount_fils = round(coalesce(t.total_charged, t.reveal_fee) * 100)::bigint
      from public.transactions t
     where r.id = (d->>'refund_id')::bigint and t.id = r.transaction_id and r.status = 'requested'
    returning r.amount_fils into v_fils;
    get diagnostics v_n = row_count;
    return jsonb_build_object('fixed', v_n = 1, 'amount_fils', v_fils,
      'basis', 'refunds.amount_fils set to the payment''s total_charged; a00_refund_amount_is_the_fee_paid re-checked it against the Stripe reference on write');
  end if;
  return jsonb_build_object('waiting', 'no automatic remedy for ' || coalesce(d->>'checks', '?') || '; the accountant runtime or a person must act');
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_renewal_budget_line(p_item text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  x public.it_expiry; v_before int; v_fx numeric; v_basis text; v_amt numeric;
  v_eid bigint; v_vendor text; v_amount numeric; v_cur text; v_on date;
begin
  select * into x from public.it_expiry where item = p_item;
  if not found then raise exception 'public.it_expiry has no item %', p_item; end if;
  v_before := (select (value #>> '{}')::int from public.decision_policy where key = 'accountant_renewal_pay_days_before');
  if v_before is null then raise exception 'decision_policy accountant_renewal_pay_days_before is missing'; end if;
  v_fx := coalesce((select num_value from public.gl_settings where key = 'usd_to_aed'), 3.6725);
  select id, vendor, amount, upper(currency), charged_on into v_eid, v_vendor, v_amount, v_cur, v_on
    from public.expense_entries
   where renews_item = p_item and upper(currency) in ('AED', 'USD') and amount > 0
   order by charged_on desc, id desc limit 1;
  if v_eid is null then
    v_basis := 'MISSING: no payment booked in expense_entries was reasoned to renew ' || p_item || '; the fee is unknown until its receipt is booked';
  else
    v_amt := round(v_amount * case v_cur when 'USD' then v_fx else 1 end, 2);
    v_basis := 'the last booked payment reasoned to renew it: expense_entries #' || v_eid || ', ' || v_vendor || ', ' || v_cur || ' ' || v_amount || ' on ' || v_on;
  end if;
  insert into public.accountant_renewal_budget (item, kind, expires_on, pay_by, budget_aed, basis, last_expense_id, updated_at)
  values (x.item, x.kind, x.expires_on, x.expires_on - v_before, v_amt, v_basis, v_eid, now())
  on conflict (item) do update set kind = excluded.kind, expires_on = excluded.expires_on, pay_by = excluded.pay_by,
                                   budget_aed = excluded.budget_aed, basis = excluded.basis,
                                   last_expense_id = excluded.last_expense_id, updated_at = now();
  return jsonb_build_object('item', x.item, 'kind', x.kind, 'expires_on', x.expires_on, 'pay_by', x.expires_on - v_before,
                            'budget_aed', v_amt, 'basis', v_basis);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_renewal_position()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'budgeted_aed', coalesce(sum(budget_aed), 0),
    'lines', count(*),
    'unbudgeted', count(*) filter (where budget_aed is null),
    'items', coalesce(jsonb_agg(jsonb_build_object('item', item, 'kind', kind, 'expires_on', expires_on, 'pay_by', pay_by,
                                                   'budget_aed', budget_aed, 'basis', basis) order by expires_on nulls last, item), '[]'::jsonb),
    'basis', 'Each licence and domain in it_expiry expiring within decision_policy accountant_renewal_horizon_days, budgeted at the last payment booked for its vendor. budgeted_aed adds only the lines that have one; unbudgeted counts the rest.')
  from public.accountant_renewal_budget
  where item !~* 'zz[_ -]?demo'
    and (expires_on is null or expires_on <= (now() at time zone 'Asia/Dubai')::date
           + coalesce((select (value #>> '{}')::int from public.decision_policy where key = 'accountant_renewal_horizon_days'), 365));
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_renewals_tick(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_horizon int := (select (value #>> '{}')::int from public.decision_policy where key = 'accountant_renewal_horizon_days');
  v_warn int := (select (value #>> '{}')::int from public.decision_policy where key = 'accountant_renewal_unbudgeted_warn_days');
  x public.it_expiry; b jsonb; n int := 0; v_items jsonb := '[]'::jsonb;
begin
  if v_horizon is null or v_warn is null then
    raise exception 'decision_policy accountant_renewal_horizon_days and accountant_renewal_unbudgeted_warn_days are required';
  end if;
  for x in select * from public.it_expiry
            where kind in ('licence', 'domain') and (expires_on is null or expires_on <= v_as_of + v_horizon) order by item loop
    b := public.fn_accountant_renewal_budget_line(x.item);
    n := n + 1;
    if b->>'budget_aed' is null and x.expires_on is not null and x.expires_on <= v_as_of + v_warn then
      v_items := v_items || jsonb_build_object('item', 'unbudgeted:' || x.item, 'owner_seat', 'accountant', 'subject', 'accountant_renewal_budget',
        'title', x.item || ' must be renewed by ' || x.expires_on || ' and has no budget: ' || (b->>'basis'),
        'blast', 'agent_facing', 'affected', 1, 'demo', x.item ~* 'zz[_ -]?demo', 'evidence', b);
    end if;
  end loop;
  return jsonb_build_object('lines', n, 'position', public.fn_accountant_renewal_position(),
                            'findings', public.fn_accountant_duty_settle('renewals', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_reports_complete()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int;
begin
  update public.support_ceo_report
     set status = 'completed', completed_at = now(),
         completion_note = 'accountant saw the CEO''s receipt: ' || acceptance_receipt
   where source_agent = 'accountant' and status = 'accepted' and acceptance_receipt is not null;
  get diagnostics n = row_count;
  return jsonb_build_object('completed_after_receipt', n);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_reserves_topup(p_transaction_id uuid, p_amount_fils bigint, p_fix_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t public.transactions; c public.refunds; x public.refunds; v_cap bigint; v_live bigint; v_amt bigint; v_marker text;
begin
  v_marker := 'incident.fix #' || p_fix_id;
  select * into t from public.transactions where id = p_transaction_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such transaction'); end if;
  select * into x from public.refunds
   where transaction_id = t.id and topup_of is not null and reason_note like v_marker || ':%' order by id limit 1;
  if found then
    return jsonb_build_object('ok', true, 'refund_id', x.id, 'amount_fils', x.amount_fils, 'status', x.status, 'existing', true);
  end if;
  select * into c from public.refunds
   where transaction_id = t.id and topup_of is null and refund_decision_id is not null
     and status in ('approved', 'processing', 'succeeded')
     and lower(coalesce(requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe')
   order by id desc limit 1;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no approved refund on this payment to top up (a CEO decision still waiting on the second seat is not approved)'); end if;
  v_cap := round(coalesce(t.total_charged, t.reveal_fee, 0) * 100)::bigint;
  select coalesce(sum(r.amount_fils), 0) into v_live
    from public.refunds r
   where r.status not in ('failed', 'rejected', 'cancelled')
     and (r.transaction_id = t.id or (coalesce(btrim(t.payment_ref), '') <> '' and r.stripe_payment_intent = t.payment_ref));
  v_amt := least(coalesce(p_amount_fils, 0), v_cap - v_live);
  if v_amt <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'nothing left to refund: ' || v_live || ' of the ' || v_cap || ' fils paid are already refunded or on their way',
                              'refunded_fils', v_live, 'paid_fils', v_cap);
  end if;
  insert into public.refunds
    (transaction_id, quote_id, inquiry_id, customer_id, supplier_lead_id, stripe_payment_intent, amount_fils, currency,
     reason_code, reason_note, status, requested_by, amount_source, topup_of, refund_decision_id, decided_by, decided_at)
  values
    (t.id, t.quote_id, t.inquiry_id, t.customer_id, t.supplier_id, t.payment_ref, v_amt, 'AED',
     c.reason_code, v_marker || ': the CEO''s mismatch playbook tops refund #' || c.id || ' up towards what the customer paid',
     'requested', 'accountant', 'in_platform_request', c.id, c.refund_decision_id, 'ceo', now())
  returning * into x;
  return jsonb_build_object('ok', true, 'refund_id', x.id, 'amount_fils', v_amt, 'capped', v_amt < coalesce(p_amount_fils, 0), 'case_refund_id', c.id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_reveal_invoice_filing_check()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'; v_gaps jsonb; v_n int; v_rep jsonb;
begin
  select count(*), coalesce(jsonb_agg(jsonb_build_object('transaction_id', t.id, 'invoice', t.stripe_invoice_id is not null,
           'filed', d.id is not null, 'portal_pdf', coalesce(d.status = 'done', false), 'dropbox', x.hit)) filter (where not (t.stripe_invoice_id is not null and d.id is not null and d.status = 'done' and x.hit)), '[]')
    into v_n, v_gaps
    from public.transactions t join public.customers c on c.id = t.customer_id
    left join public.documents d on d.bucket = 'finance-docs' and d.path = t.doc_path
    cross join lateral (select exists (select 1 from public.dropbox_files f where not f.is_folder
                         and t.doc_path is not null and f.name = regexp_replace(t.doc_path, '^.*/', ''))) x(hit)
   where t.fee_status = 'paid' and t.revealed_at < now() - interval '1 hour'
     and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx;
  if jsonb_array_length(v_gaps) > 0 then
    v_rep := public.fn_support_report_to_ceo(
      p_idempotency_key => 'reveal_invoice_filing:' || current_date, p_severity => 'elevated',
      p_subject => jsonb_array_length(v_gaps) || ' paid reveal(s) lack a filed Stripe invoice, portal PDF or Dropbox copy',
      p_evidence => jsonb_build_object('gaps', v_gaps), p_attempted => '[]'::jsonb,
      p_requested => 'None from you: the accountant re-files each one; this records the gap.',
      p_review_in => interval '1 day', p_source_agent => 'accountant');
  end if;
  return jsonb_build_object('paid_reveals', v_n, 'incomplete', jsonb_array_length(v_gaps), 'gaps', v_gaps);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_risk_screen_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_flags jsonb; h record; v_rescreened int := 0; v_released int := 0; v_overdue int := 0; v jsonb;
begin
  v_flags := public.fn_accountant_party_flags(null, null);

  for h in select m.id, m.move, m.ref, m.customer_id, m.supplier_id, m.opened_at, m.flag_keys
             from public.money_move_hold m left join public.customers c on c.id = m.customer_id
            where m.status = 'held'
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
            order by m.id loop
    v := public.fn_accountant_money_screen(h.move, h.ref, h.customer_id, h.supplier_id);
    v_rescreened := v_rescreened + 1;
    if not coalesce((v->>'hold')::boolean, false) then v_released := v_released + 1; continue; end if;
    if h.opened_at < now() - interval '48 hours' then
      v_overdue := v_overdue + 1;
      perform public.fn_it_engineer_finding_upsert('money_hold_unreviewed:' || h.id,
        left('A held ' || h.move || ' has waited ' || extract(day from now() - h.opened_at)::int || ' days for a fraud review', 300),
        'public.money_move_hold / fn_accountant_money_screen', 'agent_facing', 1,
        jsonb_build_object('hold_id', h.id, 'move', h.move, 'ref', h.ref, 'opened_at', h.opened_at, 'flags', to_jsonb(h.flag_keys),
                           'owner_seat', 'accountant',
                           'fix', 'review the flags in the fraud workspace: fn_fraud_resolve dismisses or bans; fn_money_move_hold_release lets this one move go'),
        '{}'::text[], array['whether the flags that hold this money are real'], 'accountant');
    end if;
  end loop;

  update public.it_engineer_finding f set closed_at = now(), close_note = 'the held money was released'
   where f.issue_key like 'money_hold_unreviewed:%' and f.closed_at is null
     and exists (select 1 from public.money_move_hold m where m.id::text = split_part(f.issue_key, ':', 2) and m.status <> 'held');

  return v_flags || jsonb_build_object('holds_rescreened', v_rescreened, 'holds_released', v_released, 'holds_overdue', v_overdue);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_runway_figures(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_m date := date_trunc('month', p_month)::date;
  v_close jsonb; v_exp numeric; v_cp jsonb; v_avail numeric; v_budget numeric; v_budget_lines int; v_run_b numeric;
  v_missing text[] := '{}';
begin
  select figures into v_close from public.accountant_month_close where month = v_m;
  if v_close is null then v_missing := v_missing || ('the month ' || to_char(v_m, 'YYYY-MM') || ' is not closed'); end if;
  v_exp := (v_close #>> '{cash_out,expenses_aed}')::numeric;
  v_cp := public.fn_accountant_cash_position(v_m, v_exp);
  v_avail := (v_cp #>> '{runway,available_aed}')::numeric;
  if (v_cp #>> '{runway,missing}') is not null then v_missing := v_missing || (v_cp #>> '{runway,missing}'); end if;

  select round(sum(l.amount), 2), count(*) into v_budget, v_budget_lines
    from public.budget_lines l join public.budgets b on b.id = l.budget_id
    join public.gl_accounts ga on ga.code = l.account_code and ga.type = 'expense'   -- spend only; revenue lines are not spend
   where b.status = 'active' and l.period_month = v_m;
  if v_budget_lines = 0 then v_missing := v_missing || ('no active budget has a line for ' || to_char(v_m, 'YYYY-MM') || ', so there is no runway against the budget');
  elsif v_budget <= 0 then v_missing := v_missing || 'the budgeted spend for the month is not positive, so the runway against it is undefined';
  elsif v_avail is not null then v_run_b := round(v_avail / v_budget, 1);
  end if;

  return jsonb_build_object(
    'month', to_char(v_m, 'YYYY-MM'),
    'cash_in_bank_aed', v_cp #> '{cash_in_bank,aed}',
    'held_for_possible_refunds_aed', v_cp -> 'held_for_possible_refunds_aed',
    'available_aed', v_avail,
    'monthly_spend_aed', v_cp #> '{runway,monthly_spend_aed}',
    'runway_months_at_actual_spend', v_cp #> '{runway,months}',
    'budgeted_spend_aed', case when v_budget_lines > 0 then v_budget end,
    'runway_months_at_budget', v_run_b,
    'cash_13_weeks', public.fn_accountant_cash_13_weeks(),
    'missing', to_jsonb(v_missing),
    'basis', 'Runway at actual spend is fn_accountant_cash_position''s (available cash / average booked monthly expenses). '
          || 'Runway at budget = the same available cash / the month''s lines of the active budgets. Nothing is estimated.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_runway_report_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_m date; f jsonb; v_warn numeric; v_sev text; v_key text; v_res jsonb; v_low boolean;
begin
  select month into v_m from public.accountant_month_close order by month desc limit 1;
  if v_m is null then return jsonb_build_object('reported', false, 'reason', 'no month is closed yet'); end if;
  v_key := 'accountant.runway:' || to_char(v_m, 'YYYY-MM');
  if exists (select 1 from public.support_ceo_report where idempotency_key = v_key) then
    return jsonb_build_object('reported', false, 'reason', 'the runway for ' || to_char(v_m, 'YYYY-MM') || ' is already with the CEO');
  end if;
  v_warn := (select (value #>> '{}')::numeric from public.decision_policy where key = 'accountant_runway_warn_months');
  if v_warn is null then raise exception 'decision_policy accountant_runway_warn_months is required'; end if;
  f := public.fn_accountant_runway_figures(v_m);
  -- The Mashreq statement for a month arrives at its end or later, after the close. The report is sent ONCE per
  -- month, so it waits for the closing balance until the end of the following month, then goes with the gap named.
  if (f->>'cash_in_bank_aed') is null and (now() at time zone 'Asia/Dubai')::date < (v_m + interval '2 months')::date then
    return jsonb_build_object('reported', false, 'month', to_char(v_m, 'YYYY-MM'),
      'reason', 'waiting for the Mashreq closing balance; sent without it from ' || to_char(v_m + interval '2 months', 'YYYY-MM-DD'));
  end if;
  v_low := coalesce((f->>'runway_months_at_actual_spend')::numeric < v_warn, false)
        or coalesce((f->>'runway_months_at_budget')::numeric < v_warn, false);
  v_sev := case when v_low then 'elevated' else 'routine' end;
  v_res := public.fn_support_report_to_ceo(v_key, v_sev,
    'Runway for ' || to_char(v_m, 'Mon YYYY') || ': '
      || coalesce((f->>'runway_months_at_actual_spend') || ' months at actual spend', 'not measurable at actual spend')
      || ', ' || coalesce((f->>'runway_months_at_budget') || ' months at budget', 'no runway against a budget'),
    f, '[]'::jsonb,
    case when v_low then 'Decide how to extend the runway: it is below ' || v_warn || ' months.'
         else 'Read and acknowledge the month''s cash and runway.' end,
    null, null, interval '3 days', 'accountant');
  return jsonb_build_object('reported', coalesce((v_res->>'ok')::boolean, false), 'month', to_char(v_m, 'YYYY-MM'),
                            'severity', v_sev, 'figures', f, 'report', v_res);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_sanctions_rescreen()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_runs bigint[]; v_oldest timestamptz; v_res jsonb;
begin
  select array_agg(id order by id), min(fetched_at) into v_runs, v_oldest
    from (select distinct on (source) id, fetched_at from public.screening_run where status = 'ok'
           order by source, fetched_at desc, id desc) x;
  if v_runs is null then raise exception 'no sanctions list has ever been fetched successfully (screening_run has no ok row)'; end if;
  if v_oldest < now() - interval '8 days' then
    perform public.fn_it_engineer_finding_upsert('sanctions_list_stale',
      'The sanctions lists the accountant re-screens against are older than 8 days',
      'public.screening_run / sanctions_screen (weekly fetch)', 'agent_facing', 1,
      jsonb_build_object('oldest_list_fetched_at', v_oldest, 'runs', to_jsonb(v_runs), 'owner_seat', 'accountant'),
      '{}'::text[], array['why the weekly sanctions_screen fetch has not produced an ok run'], 'accountant');
  else
    update public.it_engineer_finding set closed_at = now(), close_note = 'a fresh sanctions list was fetched'
     where issue_key = 'sanctions_list_stale' and closed_at is null;
  end if;
  -- the screen builds a temp table that drops at commit; a second call in one transaction must not collide
  drop table if exists tmp_screen_sup;
  v_res := public.fn_supplier_sanctions_screen(v_runs, case when v_fx then 'zz_demo_duty' end);
  return v_res || jsonb_build_object('runs', to_jsonb(v_runs), 'oldest_list', v_oldest);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_self_review()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_seat_self_review((now() at time zone 'Asia/Dubai')::date, 'accountant') $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_spend_report(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tz        text := 'Asia/Dubai';
  v_as_of     date;
  v_fx        numeric;
  v_entries   int;
  v_first     date;
  v_last      date;
  v_aed       numeric(18,2);
  v_vat       numeric(18,2);
  v_unconv    jsonb;
  v_unconv_n  int;
  v_by_cur    jsonb;
  v_by_vendor jsonb;
  v_by_month  jsonb;
  v_vendor_rows jsonb;
  v_month_rows  jsonb;
  v_held      jsonb;
  v_held_n    int;
  v_refused_n int;
  v_unposted  int;
  v_sweep     record;
  v_cov       text;
  v_covj      jsonb;
  v_complete  boolean;
  v_cadence   jsonb;
  v_cad_gap   int;
  v_cad_quiet int;
  v_short     text[] := '{}';
  v_subject   text;
  v_body      text;
  v_blocks    jsonb;
  v_money     text;
  v_rcpt      jsonb;
  v_rcpt_rows jsonb;
  v_receipts  jsonb;
  v_rcpt_n    int;
  v_rcpt_doc  int;
begin
  v_as_of := coalesce(p_as_of, (now() at time zone v_tz)::date);
  select num_value into v_fx from public.gl_settings where key = 'usd_to_aed';
  v_fx := coalesce(v_fx, 3.6725);

  -- ONE conversion expression, repeated verbatim everywhere below rather than varied, so the report
  -- cannot convert two ways in two places. NULL for a currency with no rate: such an entry then
  -- drops out of every sum BY CONSTRUCTION, rather than by a filter somebody could forget to repeat
  -- in the fifth query. It is counted separately and named on the document.
  select count(*), min(charged_on), max(charged_on),
         sum(round(amount * case upper(currency) when 'USD' then v_fx when 'AED' then 1 else null end, 2)),
         sum(round(coalesce(vat_amount,0) * case upper(currency) when 'USD' then v_fx when 'AED' then 1 else null end, 2))
    into v_entries, v_first, v_last, v_aed, v_vat
    from public.expense_entries;
  v_entries := coalesce(v_entries, 0);
  v_aed := coalesce(v_aed, 0);
  v_vat := coalesce(v_vat, 0);

  -- ---- by currency (every currency, converted or not) ----
  select coalesce(jsonb_agg(x order by x->>'currency'), '[]'::jsonb)
    into v_by_cur
    from (select jsonb_build_object(
                   'currency', upper(currency),
                   'entries', count(*),
                   'total', round(sum(amount), 2),
                   'vat_stated', round(sum(coalesce(vat_amount,0)), 2),
                   'convertible', upper(currency) in ('AED','USD'),
                   'aed', case when upper(currency) in ('AED','USD')
                          then round(sum(round(amount * case upper(currency) when 'USD' then v_fx else 1 end, 2)), 2)
                          else null end) as x
            from public.expense_entries group by upper(currency)) s;

  select coalesce(jsonb_agg(x order by x->>'currency'), '[]'::jsonb), count(*)
    into v_unconv, v_unconv_n
    from (select jsonb_build_object('currency', upper(currency), 'entries', count(*),
                                    'total', round(sum(amount), 2)) as x
            from public.expense_entries
           where upper(currency) not in ('AED','USD')
           group by upper(currency)) s;

  -- ---- by vendor ----
  select coalesce(jsonb_agg(x order by (x->>'aed')::numeric desc nulls last), '[]'::jsonb)
    into v_by_vendor
    from (select jsonb_build_object(
                   'vendor', vendor,
                   'entries', count(*),
                   'first', min(charged_on), 'last', max(charged_on),
                   'currencies', (select string_agg(distinct upper(e2.currency), '/' order by upper(e2.currency))
                                    from public.expense_entries e2 where e2.vendor = e.vendor),
                   'aed', round(sum(round(amount * case upper(currency) when 'USD' then v_fx when 'AED' then 1 else null end, 2)), 2)) as x
            from public.expense_entries e group by vendor) s;

  -- ---- by month (calendar month of the charge date, not of the forward) ----
  select coalesce(jsonb_agg(x order by x->>'month'), '[]'::jsonb)
    into v_by_month
    from (select jsonb_build_object(
                   'month', to_char(charged_on, 'YYYY-MM'),
                   'entries', count(*),
                   'aed', round(sum(round(amount * case upper(currency) when 'USD' then v_fx when 'AED' then 1 else null end, 2)), 2)) as x
            from public.expense_entries group by to_char(charged_on, 'YYYY-MM')) s;

  -- ---- what is NOT in the total ----
  -- A held receipt is a receipt the parser refused to guess at. It is NAMED here, with its reason,
  -- because "we could not read this one" is the single most important sentence a spend report can
  -- carry and it must never be reachable only by opening a task queue.
  select coalesce(jsonb_agg(jsonb_build_object(
           'task_id', t.id, 'title', t.title, 'opened', t.created_at::date,
           'assigned', t.assigned_agent,
           'reason', left(regexp_replace(coalesce(t.detail,''), '^\[inbound_message:\d+\]\s*', ''), 400)) order by t.id), '[]'::jsonb),
         count(*)
    into v_held, v_held_n
    from public.org_tasks t
   where t.decided_by = 'fn_receipt_hand_to_bookkeeper'
     and t.status not in ('done', 'cancelled');

  select count(*) into v_refused_n
    from public.inbound_messages
   where to_email ilike 'expenses@%' and body like '[REFUSED%';

  -- An entry that never reached the ledger is money we know about that the accounts do not.
  select count(*) into v_unposted
    from public.expense_entries e
   where not exists (select 1 from public.gl_journal g
                      where g.source = 'expense' and g.source_ref = e.id::text);

  -- ---- COVERAGE. How much was LOOKED AT, not how much was booked. ----
  --
  -- 9 Sep 2026: this block used to quote ONLY the Resend inbound sweep, because that was the only
  -- way an expense had ever reached the book. It is not any more -- 28 of the entries below came
  -- from the founder's own sent-mail record of what he forwarded before Resend's ~1-month inbound
  -- retention aged it out. Quoting one source while totalling two would have made the line that
  -- exists to BOUND the total into one that contradicts it, so both sources are named now.
  -- fn_accountant_spend_report_coverage owns that paragraph and its shortfalls; the arithmetic
  -- below is untouched, and a third source can be added there without reopening this routine.
  v_covj := public.fn_accountant_spend_report_coverage();
  v_cov  := v_covj->>'note';
  select v_short || coalesce(array_agg(s #>> '{}'), '{}')
    into v_short from jsonb_array_elements(coalesce(v_covj->'shortfalls','[]'::jsonb)) s;

  select r.id, r.finished_at, r.counts, r.status into v_sweep
    from public.agent_runs r
   where r.agent = 'accountant' and r.counts->>'action' = 'expense_sweep'
   order by r.id desc limit 1;

  if v_held_n > 0 then v_short := v_short || array[(v_held_n || ' receipt(s) HELD because no amount could be read')]; end if;
  if v_refused_n > 0 then v_short := v_short || array[(v_refused_n || ' message(s) refused because the sender is not on the expense forwarder allowlist')]; end if;
  if v_unconv_n > 0 then v_short := v_short || array[(v_unconv_n || ' currency/currencies with no rate in gl_settings, which are NOT converted and NOT in the AED total')]; end if;
  if v_unposted > 0 then v_short := v_short || array[(v_unposted || ' booked entry/entries that have not reached gl_journal')]; end if;
  -- THE VENDOR-SIDE QUESTION, asked here rather than in a routine nobody calls.
  --
  -- Everything above this line is INTAKE-side: held, refused, unconvertible, unposted. All four ask
  -- "did we handle what arrived", and on 9 Sep 2026 all four were zero while the book was short
  -- three Anthropic receipts. The founder found that, not the report.
  -- fn_accountant_receipt_cadence_gaps was written the same day to ask the other question -- did
  -- every vendor that bills on a cadence produce a receipt for every period -- and was then left
  -- CALLED BY NOTHING, which is the identical defect one layer up: a check nobody runs cannot make
  -- a report more honest than it was before the check existed.
  --
  -- A cadence finding is SUSPECTED, never proven: a subscription can be cancelled, downgraded or
  -- paused. So it is NAMED as a shortfall for somebody to resolve rather than asserted as a missing
  -- amount, no figure is invented for it, and it leaves the list when the vendor bills again, the
  -- receipt is found, or the founder records that the vendor ended.
  begin
    v_cadence   := public.fn_accountant_receipt_cadence_gaps(v_as_of);
    v_cad_gap   := coalesce(jsonb_array_length(v_cadence->'months_with_no_receipt_inside_a_run'), 0);
    v_cad_quiet := coalesce(jsonb_array_length(v_cadence->'vendors_gone_quiet'), 0);

    -- READ THE CHECK'S OWN COUNT, not a hand-picked subset of its findings. The first version of
    -- this block listed two of the check's three lists and left `vendors_seen_once_unexplained`
    -- feeding nothing, so the report returned complete = true while the check returned
    -- suspected_missing = 1. Binding to suspected_missing means a finding added to the check in
    -- future reaches the founder without anyone remembering to wire it.
    if coalesce((v_cadence->>'suspected_missing')::int, 0) > 0 then
      if v_cad_gap > 0 then
        v_short := v_short || array[(
          v_cad_gap || ' month(s) inside a vendor''s own billing run with no receipt at all ('
          || (select string_agg((x->>'vendor') || ' ' || (x->>'missing_month'), ', ')
                from jsonb_array_elements(v_cadence->'months_with_no_receipt_inside_a_run') x)
          || '), so a receipt for each is probably missing rather than genuinely absent')];
      end if;
      if v_cad_quiet > 0 then
        v_short := v_short || array[(
          v_cad_quiet || ' vendor(s) that billed on a monthly cadence and have gone quiet for more than 45 days ('
          || (select string_agg((x->>'vendor') || ', last billed ' || (x->>'last_month'), '; ')
                from jsonb_array_elements(v_cadence->'vendors_gone_quiet') x)
          || '); either the subscription ended and nobody recorded it, or the later receipts never reached the accountant')];
      end if;
      if coalesce(jsonb_array_length(v_cadence->'vendors_seen_once_unexplained'), 0) > 0 then
        v_short := v_short || array[(
          jsonb_array_length(v_cadence->'vendors_seen_once_unexplained')
          || ' vendor(s) with exactly ONE receipt and no recorded reason ('
          || (select string_agg((x->>'vendor') || ', only ' || (x->>'only_month')
                 || ', ' || (x->>'days_since') || ' days ago', '; ')
                from jsonb_array_elements(v_cadence->'vendors_seen_once_unexplained') x)
          || '); if any is a monthly subscription then every renewal after it is missing')];
      end if;
      if coalesce(jsonb_array_length(v_cadence->'vendors_billing_outside_email'), 0) > 0 then
        v_short := v_short || array[(
          jsonb_array_length(v_cadence->'vendors_billing_outside_email')
          || ' vendor(s) STILL BILLING that never email an invoice, so their charges are real and unbooked ('
          || (select string_agg((x->>'vendor') || ', last booked ' || (x->>'last_billed'), '; ')
                from jsonb_array_elements(v_cadence->'vendors_billing_outside_email') x)
          || '); the invoices must be fetched from the vendor''s own billing portal by hand')];
      end if;
    end if;
  exception when others then
    -- The cadence check must never take the report down, and must never fail OPEN: a report may not
    -- claim completeness on the strength of a check that did not run.
    v_short := v_short || array['the vendor-side completeness check could not run (' || sqlerrm
      || '), so this total is NOT claiming to be complete'];
  end;

  v_complete := array_length(v_short, 1) is null;

  v_money := 'AED ' || to_char(v_aed, 'FM999,999,990.00');

  -- ---- the table rows the document prints ----
  select coalesce(jsonb_agg(jsonb_build_array(
           v->>'vendor',
           case when v->>'aed' is null then 'not converted' else 'AED ' || to_char((v->>'aed')::numeric, 'FM999,999,990.00') end,
           v->>'entries', coalesce(v->>'currencies',''),
           coalesce(v->>'first','') || ' to ' || coalesce(v->>'last',''))
         ), '[]'::jsonb)
    into v_vendor_rows
    from jsonb_array_elements(v_by_vendor) v;

  select coalesce(jsonb_agg(jsonb_build_array(
           m->>'month',
           case when m->>'aed' is null then 'not converted' else 'AED ' || to_char((m->>'aed')::numeric, 'FM999,999,990.00') end,
           m->>'entries')
         ), '[]'::jsonb)
    into v_month_rows
    from jsonb_array_elements(v_by_month) m;

  -- ---- THE RECEIPT REGISTER: one line per booked receipt, each carrying its own document ----
  -- The founder, 9 Sep 2026: "can the pdf have clickable links for the actual invoices or receipts
  -- or at least a pdf print of the email". Until now this report totalled the spend and named the
  -- vendors, and the evidence for any single line was not reachable from the document at all.
  --
  -- THE ROUTINE DOES NOT MINT THE LINK, AND CANNOT. receipt-files is a PRIVATE bucket; a URL into
  -- it has to be signed with the service role, and there is no pgjwt in this project (`sign` in
  -- pg_catalog is the arithmetic sign function). So each cell that should be clickable is emitted
  -- as {"text": ..., "link_entry": <expense id>} -- a REQUEST for a link, addressed to the seat that
  -- can sign one. supabase/functions/accountant resolves it immediately before rendering. A cell
  -- that is never resolved still prints its text, so the worst case is a report that reads exactly
  -- as it did yesterday rather than one carrying a link to nothing.
  --
  -- A ROW WITH NO DOCUMENT SAYS SO IN THE ROW. It is not blank and it is not a dead link: it reads
  -- NO DOCUMENT, and the count of such rows is printed under the table.
  select coalesce(jsonb_agg(x order by (x->>'charged_on'), (x->>'id')::bigint), '[]'::jsonb),
         count(*), count(*) filter (where (x->>'document_state') <> 'missing')
    into v_rcpt, v_rcpt_n, v_rcpt_doc
    from (select jsonb_build_object(
                   'id',             v.id,
                   'charged_on',     v.charged_on,
                   'vendor',         v.vendor,
                   'billed',         upper(v.currency) || ' ' || to_char(v.amount, 'FM999,999,990.00'),
                   'aed',            case when upper(v.currency) in ('AED','USD')
                                       then round(v.amount * case upper(v.currency) when 'USD' then v_fx else 1 end, 2)
                                       else null end,
                   'document_state', v.document_state,
                   'doc_bucket',     v.doc_bucket,
                   'doc_path',       v.doc_path,
                   'doc_name',       v.doc_name,
                   'doc_note',       v.doc_note) as x
            from public.v_expense_documents v) s;

  select coalesce(jsonb_agg(jsonb_build_array(
           r->>'id',
           to_char((r->>'charged_on')::date, 'DD Mon YYYY'),
           r->>'vendor',
           r->>'billed',
           case when r->>'aed' is null then 'not converted'
                else to_char((r->>'aed')::numeric, 'FM999,999,990.00') end,
           case r->>'document_state'
             when 'vendor_document' then jsonb_build_object('text', coalesce(nullif(r->>'doc_name',''), 'The vendor invoice'),
                                                            'link_entry', (r->>'id')::bigint)
             when 'email_print'     then jsonb_build_object('text', 'Email print',
                                                            'link_entry', (r->>'id')::bigint)
             when 'unclassified'    then jsonb_build_object('text', coalesce(nullif(r->>'doc_name',''), 'The stored document'),
                                                            'link_entry', (r->>'id')::bigint)
             else to_jsonb('NO DOCUMENT'::text)
           end)
         order by (r->>'charged_on'), (r->>'id')::bigint), '[]'::jsonb)
    into v_rcpt_rows
    from jsonb_array_elements(v_rcpt) r;

  v_receipts := jsonb_build_array(
    jsonb_build_object('t','space','h',10),
    jsonb_build_object('t','h3','text','Every receipt, and the document behind it'),
    jsonb_build_object('t','p','text',
      'One line per booked receipt. The Evidence column opens that receipt''s own stored document: '
      || 'the vendor''s invoice where the source email carried one, otherwise a PDF print of the '
      || 'email itself. A line with no stored document reads NO DOCUMENT rather than carrying a link '
      || 'to nothing. ' || v_rcpt_doc || ' of ' || v_rcpt_n || ' receipt(s) have a document.'),
    jsonb_build_object('t','table',
      'head', jsonb_build_array('Record','Charged','Vendor','As billed','AED','Evidence'),
      'rows', v_rcpt_rows,
      'widths', jsonb_build_array(0.08,0.15,0.22,0.15,0.13,0.27)),
    -- WHY THE RECORD NUMBER IS PRINTED, AND WHY IT IS THE FIRST COLUMN.
    -- A signed URL expires. This document is a financial record the founder keeps for years, and a
    -- PDF whose every link has quietly rotted is worse than one that never had links, because it
    -- still LOOKS like it can be opened. So the link is the convenience and the record number is the
    -- permanent handle: it never expires, it is the primary key of public.expense_entries, and both
    -- public.fn_expense_document(<record>) and the accountant seat's document action take it and
    -- return a fresh link on demand. The paragraph below says that in words, on the document,
    -- because a reader in 2028 will have this PDF and not this file.
    jsonb_build_object('t','note','text',
      'HOW LONG THESE LINKS LIVE. The documents are held in the private receipt-files bucket, so each '
      || 'link above is a signed URL with an expiry stamped into it -- the seat prints the exact '
      || 'expiry date under this table when it renders. AFTER THAT DATE THE RECORD NUMBER IN THE '
      || 'FIRST COLUMN IS STILL THE WAY IN: public.fn_expense_document(<record>) names the bucket and '
      || 'object for that receipt, and the accountant seat''s document action returns a fresh link '
      || 'for it. Nothing about this report stops being useful when the links expire.'));

  v_subject := 'QuotesDone - everything spent since day one, to ' || to_char(v_as_of, 'DD Mon YYYY')
            || ' (' || v_money || ')' || case when v_complete then '' else ' - INCOMPLETE, see the report' end;

  v_body := 'Everything the company has spent since day one, read from the receipts forwarded to '
    || 'expenses@mail.quotesdone.com.' || E'\n\n'
    || 'TOTAL: ' || v_money || ' across ' || v_entries || ' booked receipt(s)'
    || case when v_first is null then '.' else ', ' || to_char(v_first,'DD Mon YYYY') || ' to ' || to_char(v_last,'DD Mon YYYY') || '.' end
    || E'\n'
    || 'Input VAT stated on those receipts: AED ' || to_char(v_vat, 'FM999,999,990.00') || '.' || E'\n\n'
    || case when v_complete
         then 'THIS TOTAL IS COMPLETE as far as the mailbox goes: nothing was held, nothing was refused, every currency converted, and every booked entry reached the ledger.'
         else 'THIS TOTAL IS INCOMPLETE, and here is exactly how: ' || array_to_string(v_short, '; ') || '. Each is named in the attached report.' end
    || E'\n\n' || 'COVERAGE. ' || v_cov || E'\n\n'
    || 'CURRENCY. AED is itself. USD is converted at gl_settings.usd_to_aed = ' || v_fx
    || ', the same rate the ledger uses. A currency with no rate is NOT converted and NOT included - '
    || 'an understated total that says so is worth more than a wrong one that does not.' || E'\n\n'
    || 'No model was used to produce any figure in this report. The receipts were read by '
    || 'supabase/functions/_shared/receipt_parse.ts, the ledger posting is public.fn_expense_post_to_gl, '
    || 'and every number above is arithmetic over public.expense_entries.';

  v_blocks := jsonb_build_array(
    jsonb_build_object('t','h2','text','Everything spent since day one'),
    jsonb_build_object('t','p','text','QuotesDone - Dorata Trading Co. L.L.C.   Prepared by the accountant seat   As at ' || to_char(v_as_of,'DD Mon YYYY') || ' (Asia/Dubai)'),
    jsonb_build_object('t','note','text','Source: the receipts forwarded to expenses@mail.quotesdone.com, read deterministically. No model was used to produce any figure in this document.'),
    jsonb_build_object('t','space','h',6),
    jsonb_build_object('t','total','value', v_money),
    jsonb_build_object('t','kv','pairs', jsonb_build_array(
      jsonb_build_array('Booked receipts', v_entries::text),
      jsonb_build_array('Period covered', case when v_first is null then 'nothing booked' else to_char(v_first,'DD Mon YYYY') || ' - ' || to_char(v_last,'DD Mon YYYY') end),
      jsonb_build_array('Input VAT stated on receipts', 'AED ' || to_char(v_vat,'FM999,999,990.00')),
      jsonb_build_array('Is this total complete?', case when v_complete then 'Yes' else 'NO - see "What is not in this total"' end))),
    jsonb_build_object('t','space','h',8),
    jsonb_build_object('t','h3','text','By vendor'),
    jsonb_build_object('t','table','head', jsonb_build_array('Vendor','Spent (AED)','Receipts','Billed in','First to last'),
                       'rows', v_vendor_rows, 'widths', jsonb_build_array(0.26,0.22,0.12,0.14,0.26)),
    jsonb_build_object('t','space','h',8),
    jsonb_build_object('t','h3','text','By month'),
    jsonb_build_object('t','table','head', jsonb_build_array('Month','Spent (AED)','Receipts'),
                       'rows', v_month_rows, 'widths', jsonb_build_array(0.34,0.4,0.26)),
    jsonb_build_object('t','space','h',8),
    jsonb_build_object('t','h3','text','How currency was handled'),
    jsonb_build_object('t','li','text','AED is itself; no conversion is applied and none is implied.'),
    jsonb_build_object('t','li','text','USD is converted at gl_settings.usd_to_aed = ' || v_fx || ', per entry, rounded to two places - the same rate and the same rounding fn_expense_post_to_gl applies, so this report and the general ledger agree to the fils.'),
    jsonb_build_object('t','li','text', case when v_unconv_n = 0
      then 'Every receipt was billed in AED or USD, so nothing was left out of the total for want of a rate.'
      else 'A currency with no rate in gl_settings is NOT converted and NOT included in the total above. ' || v_unconv_n || ' such currency/currencies appear below, in their own units.' end),
    jsonb_build_object('t','space','h',8),
    jsonb_build_object('t','h3','text','What is not in this total'),
    jsonb_build_object('t','p','bold',true,'text', case when v_complete
      then 'Nothing. Nothing was held, nothing was refused, every currency converted, and every booked entry reached the ledger.'
      else 'This total is INCOMPLETE. ' || array_to_string(v_short, '; ') || '.' end),
    jsonb_build_object('t','space','h',4),
    jsonb_build_object('t','p','bold',true,'text','Receipts HELD because no amount could be read: ' || v_held_n),
    jsonb_build_object('t','note','text','A held receipt is one the deterministic parser refused to guess at. It is not booked, not estimated and not counted as zero - it is money we know we have spent and cannot yet state.'));

  if v_held_n > 0 then
    select v_blocks || coalesce(jsonb_agg(jsonb_build_object('t','li','text',
             'Task #' || (h->>'task_id') || ' (opened ' || (h->>'opened') || ', owner ' || coalesce(h->>'assigned','none') || '): ' || (h->>'title') || ' - ' || (h->>'reason'))), '[]'::jsonb)
      into v_blocks from jsonb_array_elements(v_held) h;
  end if;

  v_blocks := v_blocks || jsonb_build_array(
    jsonb_build_object('t','space','h',4),
    jsonb_build_object('t','p','bold',true,'text','Messages refused because the sender is not a permitted forwarder: ' || v_refused_n),
    jsonb_build_object('t','p','bold',true,'text','Booked entries that have not reached the general ledger: ' || v_unposted),
    jsonb_build_object('t','space','h',8),
    jsonb_build_object('t','h3','text','Coverage of the mailbox'),
    jsonb_build_object('t','p','text', v_cov),
    jsonb_build_object('t','note','text','This line is what bounds the total. Without it the report could say how much was booked but not how much was looked at, and a total nobody can bound is a guess with a decimal point on it.'));

  v_blocks := v_blocks || v_receipts;

  return jsonb_build_object(
    'as_of', v_as_of,
    'subject', v_subject,
    'body', v_body,
    'blocks', v_blocks,
    'doc_name', 'QuotesDone_Spend_Since_Day_One_' || to_char(v_as_of, 'YYYY-MM-DD'),
    'complete', v_complete,
    -- The same lines the table prints, with the storage path on each, so a caller that is not a PDF
    -- (the OS, a check, the seat's own run record) never has to parse the document to find them.
    'receipt_lines', v_rcpt,
    'receipts_with_document', v_rcpt_doc,
    'receipts_without_document', v_rcpt_n - v_rcpt_doc,
    'shortfalls', to_jsonb(v_short),
    'figures', jsonb_build_object(
      'total_aed', v_aed, 'vat_stated_aed', v_vat, 'entries', v_entries,
      'first_charge', v_first, 'last_charge', v_last,
      'usd_to_aed', v_fx,
      'by_currency', v_by_cur, 'by_vendor', v_by_vendor, 'by_month', v_by_month,
      'unconvertible_currencies', v_unconv,
      'held_receipts', v_held, 'held_count', v_held_n,
      'refused_messages', v_refused_n, 'entries_not_in_ledger', v_unposted),
    'coverage', jsonb_build_object('note', v_cov,
      'last_sweep_run_id', v_sweep.id, 'last_sweep_at', v_sweep.finished_at,
      'last_sweep_counts', v_sweep.counts, 'last_sweep_status', v_sweep.status));
end
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_spend_report_coverage()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tz    text := 'Asia/Dubai';
  v_sweep record;
  v_back  record;
  v_cov   text := '';
  v_short text[] := '{}';
  v_mb        record;
  v_mb_seen   int := 0;
  v_mb_blind  int := 0;
  v_undecided int := 0;
  v_names     text;
begin
  select r.id, r.finished_at, r.counts, r.status into v_sweep
    from public.agent_runs r
   where r.agent = 'accountant' and r.counts->>'action' = 'expense_sweep'
   order by r.id desc limit 1;

  select r.id, r.finished_at, r.counts, r.status into v_back
    from public.agent_runs r
   where r.agent = 'accountant' and r.counts->>'action' = 'expense_backfill'
   order by r.id desc limit 1;

  -- ---- SOURCE 1: Resend's inbound history, which is what the live webhook and the sweep see. ----
  if v_sweep.id is null then
    v_cov := 'RESEND INBOUND: never swept. The expenses mailbox has never been read by this seat '
          || 'through Resend, so nothing here bounds how many messages arrived that way.';
    v_short := v_short || array['the Resend inbound mailbox has never been swept'];
  else
    v_cov := 'RESEND INBOUND: the last sweep (agent_runs #' || v_sweep.id || ', '
          || to_char(v_sweep.finished_at at time zone v_tz, 'DD Mon YYYY HH24:MI') || ' Asia/Dubai) read '
          || coalesce(v_sweep.counts->>'history_messages','?') || ' message(s) from Resend''s inbound history, of which '
          || coalesce(v_sweep.counts->>'to_expense_mailbox','?') || ' were addressed to expenses@mail.quotesdone.com. It booked '
          || coalesce(v_sweep.counts->>'booked','?') || ', found ' || coalesce(v_sweep.counts->>'already_booked','?')
          || ' already booked, held ' || coalesce(v_sweep.counts->>'held','?') || ', refused '
          || coalesce(v_sweep.counts->>'refused','?') || ' and failed on ' || coalesce(v_sweep.counts->>'failed','?') || '.'
          || ' Resend''s inbound retention is roughly one month, so that history is a WINDOW on recent '
          || 'mail, never the whole of it. Nothing older than the window was misaddressed or lost by us '
          || '- the provider simply stops keeping it.';
    if coalesce((v_sweep.counts->>'pages_capped')::boolean, false) then
      v_cov := v_cov || ' PAGING WAS CAPPED, so the history itself may be incomplete.';
      v_short := v_short || array['the sweep stopped at its page cap, so older messages may never have been read'];
    end if;
    if coalesce(v_sweep.counts->>'list_error','') <> '' then
      v_cov := v_cov || ' The listing reported an error: ' || (v_sweep.counts->>'list_error') || '.';
      v_short := v_short || array['the mailbox listing errored during the last sweep'];
    end if;
  end if;

  -- ---- SOURCE 2: the founder's own SENT folder, which is what survived the retention window. ----
  if v_back.id is null then
    v_cov := v_cov || E'\n\n' || 'FORWARDED HISTORY: never read. Everything the founder forwarded '
          || 'before Resend''s retention window has NOT been examined, so the total below covers only '
          || 'recent mail and is expected to be short.';
    v_short := v_short || array['the forwarded history older than Resend''s retention window has never been read'];
  else
    v_cov := v_cov || E'\n\n' || 'FORWARDED HISTORY: on '
          || to_char(v_back.finished_at at time zone v_tz, 'DD Mon YYYY HH24:MI') || ' Asia/Dubai (agent_runs #'
          || v_back.id || ') the accountant read the founder''s own record of what he forwarded - a '
          || 'search of his sent mail for ' || coalesce(v_back.counts->>'query','the expenses address')
          || ' returning ' || coalesce(v_back.counts->>'threads_found','?') || ' thread(s) covering '
          || coalesce(v_back.counts->>'period','the whole period') || '. All '
          || coalesce(v_back.counts->>'threads_read','?') || ' were opened and read. '
          || coalesce(v_back.counts->>'amounts_read','?') || ' printed an amount that could be read directly off the receipt; '
          || coalesce(v_back.counts->>'booked','?') || ' were booked here, '
          || coalesce(v_back.counts->>'already_booked','?') || ' were already in the book under their Resend keys, and '
          || coalesce(v_back.counts->>'held','?') || ' were held.';
    if coalesce(v_back.counts->>'date_by_corroboration','0') <> '0' then
      v_cov := v_cov || ' ' || (v_back.counts->>'date_by_corroboration')
            || ' receipt(s) printed an amount but no date, and were dated by matching to the unique '
            || 'source message in the same mailbox rather than by estimate; each says so in its own note.';
    end if;
    if coalesce((v_back.counts->>'more_pages')::boolean, false) then
      v_cov := v_cov || ' THE SEARCH REPORTED MORE RESULTS THAN IT RETURNED, so the forwarded history may be incomplete.';
      v_short := v_short || array['the forwarded-history search did not reach the end of its results'];
    end if;
  end if;

  -- ---- SOURCE 3: the mailboxes vendors bill DIRECTLY, which nobody has to remember to forward. ----
  --
  -- Added 9 Sep 2026. Sources 1 and 2 both describe the same pipe from a different end: mail that
  -- SOMEBODY FORWARDED. Neither can see a vendor that bills an address the accountant does not read,
  -- and neither would ever report that vendor as missing, because a source nobody looks at produces
  -- no evidence of its own absence. Anthropic billed management@doratajewelries.com for four months
  -- and three of its six receipts simply never existed as far as this book was concerned.
  --
  -- So coverage is now stated per MAILBOX, from a register, and a mailbox that is known but unread
  -- makes the report say so out loud instead of quietly totalling what it happens to hold.
  select count(*) filter (where is_swept),
         count(*) filter (where not is_swept)
    into v_mb_seen, v_mb_blind
    from public.expense_billing_mailbox;

  if v_mb_seen + v_mb_blind = 0 then
    v_cov := v_cov || E'\n\n' || 'BILLING MAILBOXES: no mailbox register exists, so nothing states '
          || 'which addresses a vendor bill can even arrive at. The total below is bounded by what '
          || 'was forwarded, which is not the same thing as what was spent.';
    v_short := v_short || array['there is no register of which mailboxes a vendor bills'];
  else
    select string_agg(mailbox || case when is_swept
                       then ' (read' || coalesce(' ' || to_char(last_swept_on, 'DD Mon YYYY'), '') || ')'
                       else ' (NOT READ)' end, '; ' order by is_swept desc, mailbox)
      into v_names from public.expense_billing_mailbox;

    v_cov := v_cov || E'\n\n' || 'BILLING MAILBOXES: a vendor bill only reaches this book if it lands '
          || 'somewhere the accountant reads. ' || v_mb_seen || ' of ' || (v_mb_seen + v_mb_blind)
          || ' known mailbox(es) were read: ' || v_names || '.';

    if v_mb_blind > 0 then
      v_cov := v_cov || ' A mailbox marked NOT READ receives vendor bills that this total CANNOT include.';
      v_short := v_short || array[(v_mb_blind || ' known billing mailbox(es) that the accountant cannot read')];
    end if;

    -- A charge that was SEEN but whose entity is undecided is the honest middle case. It is neither
    -- booked (which would claim it is ours) nor forgotten (which would claim it does not exist).
    select count(*) into v_undecided
      from public.expense_vendor_billing_mailbox where in_ledger_scope is null;

    if v_undecided > 0 then
      select string_agg(vendor, ', ' order by vendor) into v_names
        from public.expense_vendor_billing_mailbox where in_ledger_scope is null;
      v_cov := v_cov || ' ' || v_undecided || ' vendor(s) bill a mailbox that is read but have NOT been '
            || 'attributed to this company rather than to a sibling entity, so their spend is deliberately '
            || 'absent from the total above: ' || v_names || '. Each is recorded in '
            || 'public.expense_vendor_billing_mailbox with the evidence that was actually read.';
      v_short := v_short || array[(v_undecided || ' vendor(s) seen billing a read mailbox whose attribution to this company is undecided, so their spend is NOT in the total')];
    end if;
  end if;

  return jsonb_build_object('note', v_cov, 'shortfalls', to_jsonb(v_short),
    'sweep_run_id', v_sweep.id, 'sweep_at', v_sweep.finished_at, 'sweep_counts', v_sweep.counts,
    'backfill_run_id', v_back.id, 'backfill_at', v_back.finished_at, 'backfill_counts', v_back.counts,
    'mailboxes_read', v_mb_seen, 'mailboxes_unread', v_mb_blind, 'vendors_undecided', v_undecided);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_spend_report_deliver(p_bucket text, p_path text, p_url text DEFAULT NULL::text, p_bytes bigint DEFAULT NULL::bigint, p_as_of text DEFAULT NULL::text, p_subject text DEFAULT NULL::text, p_body text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_owner text;
  v_file  text;
  v_notif bigint;
  v_prior bigint;
  v_body  text;
  v_report jsonb;
  v_kept_err text;
  v_rev int;
begin
  -- THE DOCUMENT IS THE DELIVERABLE. He asked for a report; mailing a covering note and recording
  -- it as delivered would close the loop on something he did not ask for.
  if coalesce(p_path, '') = '' then
    return jsonb_build_object('ok', false, 'reason',
      'not delivered: no PDF path was supplied, and the report IS the document. Render it first and pass the path pdf_native returned.');
  end if;
  if coalesce(p_bucket, '') not in ('finance-reports','finance-docs','agent-docs','reports','compliance-docs') then
    return jsonb_build_object('ok', false, 'reason',
      'not delivered: ' || coalesce(p_bucket,'(null)') || ' is not a bucket notifications.attachments accepts. Refused here with a reason rather than at the trigger with a raise.');
  end if;

  -- How many reports for THIS as-of date have already been put on his mail lane? The first keeps
  -- its plain name because it was delivered under it; every later one is numbered, so two files on
  -- the same date can never be confused for one another.
  select count(*) into v_rev from public.notifications n
   where n.kind = 'accountant_spend_report'
     and n.attachments->0->>'filename' like 'QuotesDone_Spend_Since_Day_One_'
         || regexp_replace(coalesce(nullif(p_as_of,''), to_char((now() at time zone 'Asia/Dubai')::date,'YYYY-MM-DD')), '[^A-Za-z0-9_-]', '_', 'g') || '%';

  v_file := 'QuotesDone_Spend_Since_Day_One_'
         || regexp_replace(coalesce(nullif(p_as_of, ''), to_char((now() at time zone 'Asia/Dubai')::date, 'YYYY-MM-DD')), '[^A-Za-z0-9_-]', '_', 'g')
         || case when v_rev > 0 then '_revision_' || (v_rev + 1) else '' end
         || '.pdf';

  -- Already sent for THIS document? The object path is the identity: a new render is a new report.
  select n.id into v_prior
    from public.notifications n
   where n.kind = 'accountant_spend_report'
     and n.attachments @> jsonb_build_array(jsonb_build_object('bucket', p_bucket, 'path', p_path))
   order by n.id limit 1;
  if v_prior is not null then
    return jsonb_build_object('ok', true, 'already_sent', true, 'notification_id', v_prior,
      'attachment', jsonb_build_object('bucket', p_bucket, 'path', p_path, 'filename', v_file),
      'reason', 'this exact document was already put on the founder''s mail lane; a second row would be a second copy of the same report');
  end if;

  select nullif(btrim(split_part(coalesce(value, ''), ',', 1)), '') into v_owner
    from public.app_secrets where key = 'admin_emails';
  if v_owner is null then
    return jsonb_build_object('ok', false, 'reason', 'not delivered: no recipient is configured in app_secrets.admin_emails');
  end if;

  v_body := coalesce(p_body, '')
    || E'\n\n' || 'The full report is attached as ' || v_file
    || case when coalesce(p_bytes, 0) > 0 then ' (' || round(p_bytes / 1024.0) || ' KB)' else '' end || '.'
    || case when p_url is not null
         then E'\n' || 'If your mail client has stripped it, the same document is here: ' || p_url
              || E'\n' || '(That link is signed and expires seven days from generation; the document itself is retained at ' || p_bucket || '/' || p_path || '.)'
         else E'\n' || 'It is retained at ' || p_bucket || '/' || p_path || '.' end;

  begin
    insert into public.notifications(type, kind, to_email, to_role, channel, subject, body, attachments)
    values ('accountant_spend_report', 'accountant_spend_report', v_owner, 'admin', 'email',
            -- The subject carries the revision too. A founder scanning an inbox reads subjects, not
            -- attachment names, and "which of these two is the current number" must be answerable
            -- without opening either.
            case when v_rev > 0
              then 'REVISION ' || (v_rev + 1) || ' (supersedes the earlier report of the same date) — '
                || coalesce(p_subject, 'QuotesDone - everything spent since day one')
              else coalesce(p_subject, 'QuotesDone - everything spent since day one') end, v_body,
            jsonb_build_array(jsonb_build_object('bucket', p_bucket, 'path', p_path, 'filename', v_file)))
    returning id into v_notif;
  exception when others then
    -- a20_notifications_attachment_policy RAISES on a bad reference rather than dropping the row,
    -- so a malformed attachment lands here by name instead of vanishing.
    return jsonb_build_object('ok', false, 'reason', 'the insert raised: ' || sqlerrm);
  end;

  if v_notif is null then
    -- The a10 gate returned NULL: a REFUSAL, not an error. Name it; never let it read as sent.
    return jsonb_build_object('ok', false, 'reason',
      'the founder-mail gate did not accept the row (kind accountant_spend_report). Nothing was queued and nothing will be sent.');
  end if;

  -- ---- "AND KEEP IT IN HIS RECORD AS WELL" ----------------------------------------------------
  -- The founder asked for the report to be RETAINED, not merely sent. The object in the bucket is
  -- the document; this row is the record OF the document -- what was reported, when, and over which
  -- period -- so a figure he was given in September can be produced again and audited later without
  -- re-reading a mailbox the provider no longer holds. The whole figures payload is stored, not just
  -- the headline, because a total with no breakdown behind it cannot be checked.
  --
  -- Recorded AFTER the notification row exists, so the record can never claim a report was kept
  -- that was never actually queued. A failure to retain is reported alongside the send rather than
  -- swallowed: the mail did go, and he should be told the record did not.
  begin
    v_report := public.fn_accountant_spend_report(nullif(p_as_of,'')::date);
    insert into public.accountant_spend_report
      (as_of, period_start, period_end, entries, total_aed, vat_stated_aed, usd_to_aed,
       complete, shortfalls, figures, coverage, subject, body,
       pdf_bucket, pdf_path, pdf_url, pdf_bytes, notification_id, delivered_at)
    values (
      coalesce(nullif(p_as_of,'')::date, (now() at time zone 'Asia/Dubai')::date),
      nullif(v_report->'figures'->>'first_charge','')::date,
      nullif(v_report->'figures'->>'last_charge','')::date,
      nullif(v_report->'figures'->>'entries','')::int,
      nullif(v_report->'figures'->>'total_aed','')::numeric,
      nullif(v_report->'figures'->>'vat_stated_aed','')::numeric,
      nullif(v_report->'figures'->>'usd_to_aed','')::numeric,
      (v_report->>'complete')::boolean,
      v_report->'shortfalls', coalesce(v_report->'figures','{}'::jsonb), v_report->'coverage',
      coalesce(p_subject, v_report->>'subject'), coalesce(p_body, v_report->>'body'),
      p_bucket, p_path, p_url, p_bytes, v_notif, now())
    on conflict (pdf_bucket, pdf_path) do update
      set notification_id = excluded.notification_id,
          delivered_at    = coalesce(public.accountant_spend_report.delivered_at, excluded.delivered_at);
  exception when others then
    v_kept_err := sqlerrm;
  end;

  return jsonb_build_object('ok', true, 'notification_id', v_notif, 'to', v_owner,
    'retained', v_kept_err is null,
    'retention_error', v_kept_err,
    'attachment', jsonb_build_object('bucket', p_bucket, 'path', p_path, 'filename', v_file),
    'status', 'pending - send_outbox will download the object, base64 it onto the Resend payload and fail the row rather than send a covering note without it');
end
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_statement_booked(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_m date := date_trunc('month', p_month)::date; i record; v_unbooked jsonb;
begin
  select * into i from public.bank_statement_intake
   where account = 'mashreq' and statement_month = v_m and state = 'parsed'
   order by received_at limit 1;
  if i.source_ref is null then
    return jsonb_build_object('month', to_char(v_m, 'YYYY-MM'), 'booked', false,
      'reason', 'no readable Mashreq statement for ' || to_char(v_m, 'YYYY-MM') || ' has been received (the founder forwards it monthly)');
  end if;
  -- A line counts only when a booking routine WOULD book it, under the same sign and kind rules:
  -- fn_accountant_book_bank_charges takes a debit of kind bank_charge; fn_accountant_book_bank_credits takes a
  -- credit that is no Stripe payout and not ruled a loan, as owner capital (ruled capital, or kind owner_transfer)
  -- or bank interest. Anything else (a fee refund left as bank_charge, an unrecognised credit) is that routine's
  -- finding, and never holds the close at waiting_for_statement (re-review of #1063).
  select coalesce(jsonb_agg(jsonb_build_object('line_id', b.id, 'value_date', b.value_date, 'amount_aed', b.amount_aed, 'kind', b.kind,
                                               'books_as', x.src) order by b.value_date, b.id), '[]'::jsonb)
    into v_unbooked
    from public.bank_statement_line b
    left join public.bank_line_owner_ruling r on r.line_id = b.id
    cross join lateral (select case
             when b.amount_aed < 0 and b.kind = 'bank_charge' then 'bank_charge'
             when b.amount_aed > 0 and coalesce(r.ruling, '') <> 'loan'
                  and not exists (select 1 from public.stripe_payout p where p.bank_line_id = b.id) then
               case when r.ruling = 'capital' or b.kind = 'owner_transfer' then 'owner_capital'
                    when b.kind = 'bank_interest' then 'bank_interest' end
           end as src) x
   where b.account = 'mashreq'
     and b.source_ref in (select i2.source_ref from public.bank_statement_intake i2 where i2.account = 'mashreq' and i2.statement_month = v_m)
     and x.src is not null
     -- fn_accountant_book_bank_charges skips a charge line with ANY journal (a voided one included); the credits
     -- routine re-books a credit whose journal was voided. Each is counted exactly as its routine treats it.
     and not exists (select 1 from public.gl_journal g
                      where g.source_ref = b.id::text and g.source = x.src
                        and (x.src = 'bank_charge' or g.status in ('draft', 'posted')));
  return jsonb_build_object('month', to_char(v_m, 'YYYY-MM'), 'booked', jsonb_array_length(v_unbooked) = 0,
    'statement', i.source_ref, 'received_at', i.received_at, 'unbooked_lines', v_unbooked,
    'reason', case when jsonb_array_length(v_unbooked) > 0
                   then jsonb_array_length(v_unbooked) || ' line(s) of the statement are not booked yet' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_statement_reader_defects()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_items jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'item', i.source_ref, 'owner_seat', 'accountant', 'subject', 'bank_statement',
           'title', 'The statement reader could not read a real ' || i.account || ' statement'
                    || coalesce(' for ' || to_char(i.statement_month, 'Mon YYYY'), '')
                    || ': a parser defect to fix, not a question for the founder',
           'blast', 'agent_facing', 'affected', 1, 'demo', false,
           'evidence', jsonb_build_object('source_ref', i.source_ref, 'doc_path', i.doc_path, 'reader_said', i.note,
             'no_founder_email', true,
             'remedy', 'fix supabase/functions/_shared/bank_statement_parse.ts against this document, then run the accountant expense_sweep with email_id so the same source_ref is ingested with lines'))
           order by i.source_ref), '[]'::jsonb)
    into v_items
    from public.bank_statement_intake i
   where i.state = 'unreadable' and i.account <> 'zz_demo';
  return public.fn_it_duty_settle('bank_statement_reader', v_items);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_stripe_email_setting_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb; v_on int; v_stale int;
begin
  select jsonb_agg(to_jsonb(r) - 'id'), count(*) filter (where r.value = 'on'), count(*) filter (where r.read_at < now() - interval '30 days')
    into v, v_on, v_stale
    from (select distinct on (setting) * from public.stripe_setting_reading
           where setting in ('customer_emails.successful_payments', 'customer_emails.refunds') order by setting, read_at desc) r;
  if coalesce(v_on, 0) > 0 or coalesce(v_stale, 0) > 0 or coalesce(jsonb_array_length(v), 0) < 2 then
    perform public.fn_support_report_to_ceo(
      p_idempotency_key => 'stripe_email_setting:' || to_char(current_date, 'YYYY-MM') || ':' || coalesce(v_on, 0),
      p_severity => case when v_on > 0 then 'serious' else 'routine' end,
      p_subject => case when v_on > 0 then 'Stripe is emailing customers directly (a customer-email setting reads ON)'
                        else 'The Stripe customer-email setting needs re-reading (last reading over 30 days old)' end,
      p_evidence => jsonb_build_object('readings', v), p_attempted => '[]'::jsonb,
      p_requested => 'Re-read Settings > Business > Customer emails in the live Stripe dashboard and record it in stripe_setting_reading; both must be OFF (founder_instruction 697).',
      p_review_in => interval '7 days', p_source_agent => 'accountant');
  end if;
  return jsonb_build_object('readings', v, 'on', v_on, 'stale', v_stale);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_stripe_reconcile_duty()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  return jsonb_build_object('bank', public.fn_accountant_bank_reconcile(),
    'payouts_unmatched', (select count(*) from public.stripe_payout where livemode and bank_line_id is null
                            and arrival_date < current_date - coalesce((select num_value::int from public.gl_settings where key = 'payout_transit_grace_days'), 3)));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_subscription_paid_from(p_vendor text, p_on date)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(
    (select paid_from from public.accountant_subscription_paid_from_change
      where vendor = p_vendor and effective_from <= p_on order by effective_from desc limit 1),
    (select paid_from from public.accountant_owner_ruled_subscription where vendor = p_vendor));
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_subscription_payment_failed(p_supplier_id bigint, p_session text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_subscription_position()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_subscription_tick(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_ubo_rescreen()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_runs bigint[]; v_owners int; v_new int := 0; v_missing int; v_stale int; v_screen jsonb; h record;
begin
  select array_agg(id order by id) into v_runs
    from (select distinct on (source) id from public.screening_run where status = 'ok'
           order by source, fetched_at desc, id desc) x;
  if v_runs is null then raise exception 'no sanctions list has ever been fetched successfully (screening_run has no ok row)'; end if;

  -- the suppliers in scope are exactly the ones fn_supplier_sanctions_screen screens (same demo split)
  create temp table if not exists tmp_ubo_scope (lead_id bigint primary key) on commit drop;
  truncate tmp_ubo_scope;
  insert into tmp_ubo_scope
  select l.id from public.leads l
   where (l.lifecycle_stage = 'registered' or l.approval_status = 'approved')
     and l.is_demo = v_fx;   -- the shared marker (founder ruling 1199): fixtures only under qd.duty_fixtures, never otherwise

  select count(*) into v_owners from public.supplier_beneficial_owner o join tmp_ubo_scope s on s.lead_id = o.lead_id;

  for h in
    select o.lead_id, o.full_name, e.id as entry_id, e.run_id, e.name, e.source, coalesce(e.reference, '') as reference, e.entry_type,
           case when x.norm = e.name_norm then 'exact' else 'token_overlap' end as kind,
           case when x.norm = e.name_norm then 1.0
                else round(least(cardinality(x.toks), cardinality(e.tokens))::numeric / greatest(cardinality(x.toks), cardinality(e.tokens), 1), 2) end as score
      from public.supplier_beneficial_owner o
      join tmp_ubo_scope s on s.lead_id = o.lead_id
      cross join lateral (select public.fn_screening_normalise(o.full_name) as norm, public.fn_screening_tokens(o.full_name) as toks) x
      join public.screening_entry e
        on e.run_id = any(v_runs)
       and ((x.norm = e.name_norm and length(x.norm) >= 6)
         or (cardinality(x.toks) >= 2 and cardinality(e.tokens) >= 2 and (x.toks <@ e.tokens or e.tokens <@ x.toks)))
  loop
    insert into public.supplier_screening_hit (run_id, lead_id, field, supplier_value, entry_id, entry_name, entry_source, entry_reference, entry_type, match_kind, score)
    values (h.run_id, h.lead_id, 'beneficial_owner', h.full_name, h.entry_id, h.name, h.source, h.reference, h.entry_type, h.kind, h.score)
    on conflict (lead_id, entry_source, entry_reference, field) do nothing;
    if found then v_new := v_new + 1; end if;
  end loop;

  -- the existing screen files the CEO decision and the sales_engineer hold for every open hit of these runs
  v_screen := public.fn_accountant_sanctions_rescreen();

  select count(*) filter (where not exists (select 1 from public.supplier_beneficial_owner o where o.lead_id = s.lead_id)),
         count(*) filter (where exists (select 1 from public.supplier_beneficial_owner o where o.lead_id = s.lead_id
                                          and coalesce(o.verified_at, o.declared_at) < now() - interval '365 days'))
    into v_missing, v_stale from tmp_ubo_scope s;

  return jsonb_build_object('owners_screened', v_owners, 'owner_hits_new', v_new,
    'suppliers_without_owner_on_record', v_missing, 'suppliers_with_owner_unverified_a_year', v_stale,
    'screen', v_screen - 'sources' - 'runs' - 'oldest_list');
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_ubo_watch_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_none jsonb; v_none_n int; v_changed jsonb := '[]'::jsonb; v_new int := 0; r record; v_items jsonb := '[]'::jsonb;
begin
  create temp table tmp_ubo on commit drop as
    select l.id, l.company_name, nullif(btrim(coalesce(l.signatory_name, '')), '') as owner_name
      from public.leads l
     where (l.lifecycle_stage = 'registered' or l.approval_status = 'approved')
       and not coalesce(l.banned, false)
       and coalesce(l.is_demo, false) = v_fx;

  select coalesce(jsonb_agg(jsonb_build_object('lead_id', id, 'company', company_name) order by id), '[]'::jsonb), count(*)
    into v_none, v_none_n from tmp_ubo where owner_name is null;
  if v_none_n > 0 then
    v_items := v_items || jsonb_build_object('item', 'owner_unknown' || case when v_fx then '_demo' else '' end,
      'owner_seat', 'sales_engineer', 'subject', 'leads.signatory_name', 'demo', v_fx,
      'title', v_none_n || ' registered supplier(s) name no owner, so their owner cannot be sanctions-screened',
      'affected', v_none_n,
      'evidence', jsonb_build_object('suppliers', v_none,
        'act', 'ask each supplier for the name of its owner or authorised signatory as the trade licence shows it and record it in leads.signatory_name',
        'basis', 'there is no UBO register yet: the signatory is the owner of record and the one the sanctions screen reads'));
  end if;

  for r in select t.id, t.owner_name, public.fn_screening_normalise(t.owner_name) as norm, s.owner_norm as seen_norm, s.owner_name as seen_name
             from tmp_ubo t left join public.accountant_ubo_seen s on s.lead_id = t.id
            where t.owner_name is not null loop
    if r.seen_norm is null then
      insert into public.accountant_ubo_seen (lead_id, owner_name, owner_norm) values (r.id, r.owner_name, r.norm);
      v_new := v_new + 1;
    elsif r.seen_norm is distinct from r.norm then
      update public.accountant_ubo_seen
         set previous_owner_name = owner_name, owner_name = r.owner_name, owner_norm = r.norm, changed_at = now()
       where lead_id = r.id;
      v_changed := v_changed || jsonb_build_object('lead_id', r.id, 'from', r.seen_name, 'to', r.owner_name);
    end if;
  end loop;
  drop table if exists tmp_ubo;

  return jsonb_build_object('suppliers_without_owner', v_none_n, 'owners_first_seen', v_new, 'owners_changed', v_changed,
    'rescreened_by', 'accountant.sanctions_rescreen (daily) screens every current owner name',
    'findings', public.fn_accountant_duty_settle('ubo' || case when v_fx then '_demo' else '' end, v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_unit_economics(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_m date := date_trunc('month', p_month)::date; v_e date; v_fx numeric;
  v_reveals int; v_fee numeric; v_gmv numeric; v_charged numeric; v_stripe numeric;
  v_ref_n int; v_ref_aed numeric; v_disp int; v_rfq int; v_llm numeric; v_msg numeric;
  v_sub_n int; v_sub_rev numeric; v_var numeric; v_missing text[] := '{}'; v_llm_unpriced int;
begin
  v_e := (v_m + interval '1 month')::date;
  select num_value into v_fx from public.gl_settings where key = 'usd_to_aed';
  select count(*), coalesce(sum(t.reveal_fee), 0), coalesce(sum(t.quote_amount), 0),
         coalesce(sum(t.total_charged), 0), coalesce(sum(t.stripe_fee_fils), 0) / 100.0
    into v_reveals, v_fee, v_gmv, v_charged, v_stripe
    from public.transactions t join public.customers c on c.id = t.customer_id
   where t.fee_status = 'paid' and t.revealed_at >= v_m and t.revealed_at < v_e
     and not (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email));
  select count(*), coalesce(sum(t.refund_amount_aed), 0) into v_ref_n, v_ref_aed
    from public.transactions t join public.customers c on c.id = t.customer_id
   where t.refund_confirmed_at >= v_m and t.refund_confirmed_at < v_e
     and not (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email));
  select count(*) into v_disp from public.stripe_dispute where livemode and first_seen_at >= v_m and first_seen_at < v_e;
  select count(*) into v_rfq from public.inquiries i join public.customers c on c.id = i.customer_id
   where i.created_at >= v_m and i.created_at < v_e and not (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email));
  select coalesce(sum(cost_aed), 0),
         count(*) filter (where cost_aed is null and not cached and coalesce(model_used, 'none') <> 'none')
    into v_llm, v_llm_unpriced from public.ai_cost_log where occurred_at >= v_m and occurred_at < v_e;
  select coalesce(sum(case when upper(currency) = 'USD' then amount * v_fx else amount end), 0) into v_msg
    from public.expense_entries where charged_on >= v_m and charged_on < v_e and vendor ~* '(twilio|resend|whatsapp|meta.*messag)';
  select count(*) into v_sub_n from public.leads where registration_paid_at >= v_m and registration_paid_at < v_e;
  select coalesce(sum(revenue_aed), 0) into v_sub_rev from public.gl_revenue_lines_measured
   where account_code = '4200' and entry_date >= v_m and entry_date < v_e;
  v_var := v_llm + v_msg;
  if v_reveals = 0 then v_missing := v_missing || text 'no paid reveal in the month, so per-reveal figures are undefined'; end if;
  if v_rfq = 0 then v_missing := v_missing || text 'no request in the month, so cost per request is undefined'; end if;
  if v_llm_unpriced > 0 then v_missing := v_missing || (v_llm_unpriced || ' model call(s) returned no usage: their cost is unknown, so llm_cost_aed is a lower bound'); end if;
  if v_sub_n = 0 then v_missing := v_missing || text 'no paid supplier subscription in the month'; end if;
  return jsonb_build_object(
    'month', to_char(v_m, 'YYYY-MM'),
    'reveals', v_reveals, 'reveal_fee_revenue_aed', round(v_fee, 2), 'gmv_aed', round(v_gmv, 2),
    'take_rate', case when v_gmv > 0 then round(v_fee / v_gmv, 4) end,
    'revenue_per_reveal_aed', case when v_reveals > 0 then round(v_fee / v_reveals, 2) end,
    'stripe_fees_aed', round(v_stripe, 2), 'gross_charged_aed', round(v_charged, 2),
    'payment_cost_ratio', case when v_charged > 0 then round(v_stripe / v_charged, 4) end,
    'refunds', v_ref_n, 'refunded_aed', round(v_ref_aed, 2),
    'refund_rate', case when v_fee > 0 then round(v_ref_aed / v_fee, 4) end,
    'disputes', v_disp, 'dispute_rate', case when v_reveals > 0 then round(v_disp::numeric / v_reveals, 4) end,
    'requests', v_rfq, 'llm_cost_aed', round(v_llm, 2), 'llm_calls_unpriced', v_llm_unpriced, 'messaging_email_cost_aed', round(v_msg, 2),
    'variable_cost_per_request_aed', case when v_rfq > 0 then round(v_var / v_rfq, 2) end,
    'contribution_per_reveal_aed', case when v_reveals > 0 then round((v_fee - v_stripe - v_ref_aed - v_var) / v_reveals, 2) end,
    'subscriptions_paid', v_sub_n, 'subscription_revenue_aed', round(v_sub_rev, 2),
    'revenue_per_subscription_aed', case when v_sub_n > 0 then round(v_sub_rev / v_sub_n, 2) end,
    'missing', to_jsonb(v_missing),
    'basis', 'Paid reveals by revealed_at, refunds by refund_confirmed_at, ZZ DEMO customers excluded. Stripe fees from transactions.stripe_fee_fils. Variable cost = ai_cost_log.cost_aed + messaging/email vendor expenses (USD at gl_settings usd_to_aed). Contribution per reveal = (fee - Stripe fees - refunds - variable cost) / reveals. Numerators and denominators are all returned.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_vat_threshold(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_d date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  c_mand constant numeric := 375000; c_vol constant numeric := 187500;
  v_12 numeric; v_30 numeric; v_335 numeric; v_proj numeric; v_status text; v_by date; v_rep jsonb;
begin
  select coalesce(sum(jl.credit - jl.debit) filter (where j.entry_date > v_d - interval '12 months'), 0),
         coalesce(sum(jl.credit - jl.debit) filter (where j.entry_date > v_d - 30), 0),
         coalesce(sum(jl.credit - jl.debit) filter (where j.entry_date > v_d - 335), 0)
    into v_12, v_30, v_335
    from public.gl_journal j join public.gl_journal_lines jl on jl.journal_id = j.id
    join public.gl_accounts ac on ac.code = jl.account_code and ac.type = 'revenue'
   where j.status = 'posted' and j.entry_date <= v_d and j.entry_date > v_d - interval '12 months';
  v_proj := v_335 + v_30;
  v_status := case when v_12 > c_mand or v_proj > c_mand then 'mandatory'
                   when v_12 > c_vol then 'voluntary_eligible'
                   when v_proj > 0.8 * c_mand or v_12 > 0.8 * c_vol then 'approaching'
                   else 'below' end;
  -- historical test: within 30 days of the end of the month the threshold was passed; forward test: within 30 days
  v_by := case when v_status = 'mandatory' then
                 case when v_12 > c_mand then (date_trunc('month', v_d) + interval '1 month' - interval '1 day')::date + 30 else v_d + 30 end end;
  insert into public.accountant_vat_threshold_check (checked_on, taxable_12m_aed, last_30d_aed, projected_aed, status, register_by)
  values (v_d, v_12, v_30, v_proj, v_status, v_by)
  on conflict (checked_on) do update set taxable_12m_aed = excluded.taxable_12m_aed, last_30d_aed = excluded.last_30d_aed,
    projected_aed = excluded.projected_aed, status = excluded.status, register_by = excluded.register_by, recorded_at = now();
  if v_status <> 'below' then
    v_rep := public.fn_support_report_to_ceo('accountant.vat_threshold:' || v_status || ':' || to_char(v_d, 'YYYY'),
      case when v_status = 'mandatory' then 'elevated' else 'routine' end,
      format('VAT threshold: %s. Taxable supplies AED %s over 12 months, AED %s projected 30 days ahead (voluntary AED 187,500, mandatory AED 375,000)',
             replace(v_status, '_', ' '), v_12, v_proj),
      jsonb_build_object('as_of', v_d, 'taxable_12m_aed', v_12, 'last_30d_aed', v_30, 'projected_aed', v_proj, 'register_by', v_by,
                         'basis', 'posted revenue in gl_journal (gl_accounts.type = revenue); Federal Decree-Law 8 of 2017 Art 13-14'),
      '[]'::jsonb,
      case v_status when 'mandatory' then format('Register QuotesDone for VAT with the FTA by %s.', v_by)
                    when 'voluntary_eligible' then 'Decide whether to register voluntarily now; the accountant keeps measuring toward the mandatory line.'
                    else 'Plan the VAT registration: supplies are at 80% of a threshold.' end,
      null, null, interval '2 days', 'accountant');
    update public.accountant_vat_threshold_check set ceo_report_id = (v_rep->>'report_id')::bigint where checked_on = v_d;
  end if;
  return jsonb_build_object('as_of', v_d, 'taxable_12m_aed', v_12, 'projected_aed', v_proj, 'status', v_status, 'register_by', v_by,
    'reported', v_rep is not null);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_vat_threshold_check(p_notify boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_turn numeric; v_pos jsonb; v_band text; v_key text; v_rpt jsonb;
  v_m3 numeric; v_runrate numeric; v_since date; v_frac numeric; v_dec numeric;
begin
  v_since := (current_date - interval '12 months')::date;

  -- Taxable supplies = what the revenue accounts actually carry, posted only. Draft and reversed
  -- journals are not turnover.
  -- 28 Sep 2026: through gl_revenue_lines_measured, so a posted reversal of a VOID original (journal 821 of 690)
  -- no longer reads as AED -250 of turnover.
  select coalesce(sum(revenue_aed), 0) into v_turn
    from public.gl_revenue_lines_measured
   where entry_date >= v_since;

  v_pos  := public.fn_vat_threshold_position(v_turn);
  v_band := v_pos->>'band';

  -- The forecast limb, reported and never decided: the last 3 months annualised.
  select coalesce(sum(revenue_aed), 0) into v_m3
    from public.gl_revenue_lines_measured
   where entry_date >= (current_date - interval '3 months')::date;
  v_runrate := round(v_m3 * 4, 2);

  v_frac := public.fn_vat_threshold_fraction_reached(v_turn);
  v_pos := v_pos || jsonb_build_object('fraction_reached', v_frac);

  if v_frac is null or not p_notify then
    return v_pos || jsonb_build_object('reported_to_ceo', false,
      'window_from', v_since, 'run_rate_annualised_aed', v_runrate,
      'run_rate_note', 'The preceding-12-months test is decided above. This annualised figure is the forward-looking limb of the UAE rule and is INFORMATION for the CEO and the founder, not a determination — a projection is a judgement about the future, not a measurement.');
  end if;

  -- One report per configured fraction per month. The tick runs every 15 minutes; without this the
  -- CEO would receive the same finding ninety-six times a day and would stop reading it.
  v_key := 'vat_threshold:' || v_frac || ':' || to_char(current_date, 'YYYY-MM');

  -- THE FOUNDER DECIDES REGISTRATION, AND HEARS IT BEFORE THE LINE (14 Sep 2026). Once per fraction,
  -- through customer_support; fn_notify_founder dedupes on the key as well.
  select (value #>> '{}')::numeric into v_dec from public.decision_policy where key = 'vat_threshold_founder_decision_fraction';
  if v_dec is not null and v_frac >= v_dec then
    perform public.fn_seat_handoff('accountant', 'customer_support', 'delivery.request', 'founder', 'vat_decision:' || v_frac,
      jsonb_build_object('recipient_role', 'founder', 'kind', 'finance_alert', 'level', 'high',
        'event', 'VAT registration: your decision is needed (' || round(v_frac * 100) || '% of the threshold)',
        'detail', 'Taxable turnover over the last 12 months is AED ' || (v_pos->>'turnover_aed') || ', which is '
                  || (v_pos->>'pct_of_threshold') || '% of the AED ' || (v_pos->>'threshold_aed') || ' mandatory VAT registration threshold. '
                  || case when v_band = 'crossed' then 'It has been crossed, so registration is required now. '
                          else 'It has not been crossed yet; AED ' || (v_pos->>'headroom_aed') || ' of headroom is left. ' end
                  || 'Please decide whether QuotesDone registers for VAT now or at the threshold, and reply with your decision. '
                  || 'The annualised run rate of the last three months is AED ' || v_runrate || '.',
        'dedupe_key', 'vat_decision:' || v_frac));
  end if;

  v_rpt := public.fn_support_report_to_ceo(
    p_idempotency_key => v_key,
    p_severity        => case when v_band = 'crossed' then 'serious' when v_frac >= coalesce(v_dec, 1) then 'elevated' else 'routine' end,
    p_subject         => case when v_band = 'crossed'
                              then 'VAT registration is now required: rolling 12-month turnover AED '
                                   || (v_pos->>'turnover_aed') || ' has passed AED ' || (v_pos->>'threshold_aed')
                              else 'VAT registration threshold approaching: AED ' || (v_pos->>'turnover_aed')
                                   || ' of AED ' || (v_pos->>'threshold_aed') || ' (' || (v_pos->>'pct_of_threshold') || '%)' end,
    p_evidence        => v_pos || jsonb_build_object(
                           'window_from', v_since, 'window_to', current_date,
                           'run_rate_annualised_aed', v_runrate,
                           'basis', 'Sum of posted journal lines on accounts 4xxx over the preceding 12 months. Draft and reversed journals excluded.'),
    p_attempted       => '[]'::jsonb,
    p_requested       => case when v_band = 'crossed'
      then 'Registration for UAE VAT is required on the preceding-12-months test. Decide who files and by when, and instruct the accountant. Note the accountant holds no filing deadline or penalty figure by design — those come from the FTA, not from this system.'
      else 'No action is required yet. Prepare for registration so that crossing the threshold is a scheduled filing rather than a discovery. The accountant will report again if the band changes.' end,
    p_review_in       => interval '30 days',
    p_source_agent    => 'accountant');

  return v_pos || jsonb_build_object(
    'window_from', v_since, 'run_rate_annualised_aed', v_runrate,
    'reported_to_ceo', coalesce((v_rpt->>'ok')::boolean, false),
    'ceo_report', v_rpt);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_weekly_report(p_week_start date DEFAULT NULL::date, p_revise boolean DEFAULT false, p_revision_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tz      text := 'Asia/Dubai';
  v_company text := 'quotesdone';
  v_start   date;
  v_end     date;
  v_key     text;
  v_row     public.accountant_weekly_report%rowtype;
  v_now     jsonb;
  v_prev    jsonb;
  v_subject text;
  v_body    text;
  v_blocks  jsonb;
  v_rows    jsonb := '[]'::jsonb;
  v_k       text;
  v_ln      jsonb;
  v_pn      jsonb;
  v_val     text;
  v_mov     text;
  v_unknown int := 0;
  v_truezero int := 0;
  v_measured int := 0;
  -- The line order the report prints in. Insertion order of a jsonb object is not preserved, so it
  -- is stated here rather than discovered.
  v_order text[] := array[
    'reveal_fee_revenue','stripe_settlement_events',
    'expenses_filed_to_ledger','receipts_received_at_the_expenses_inbox','cash_out_this_week',
    'recurring_cost_schedule','refunds_requested','outstanding_bills','cash_position',
    'journal_entries_posted','ai_and_model_cost'];
  v_label jsonb := jsonb_build_object(
    'reveal_fee_revenue','Revenue - reveal fees (Stripe in)',
    'stripe_settlement_events','Stripe settlement events seen',
    'expenses_filed_to_ledger','Expenses filed to the ledger',
    'receipts_received_at_the_expenses_inbox','Receipts received at the expenses inbox',
    'cash_out_this_week','Cash out this week',
    'recurring_cost_schedule','Recurring cost schedule',
    'refunds_requested','Refunds requested',
    'outstanding_bills','Outstanding bills (accounts payable)',
    'cash_position','Cash position',
    'journal_entries_posted','Journal entries posted',
    'ai_and_model_cost','AI and model cost');
begin
  -- Default: the week that CLOSED. Never the week in progress -- a partial week reported as a week
  -- is a figure that will be wrong by Sunday and nobody will go back and correct it.
  v_start := coalesce(p_week_start,
                      (date_trunc('week', (now() at time zone v_tz)::date) - interval '7 days')::date);
  v_start := date_trunc('week', v_start::timestamp)::date;   -- normalise to the Monday
  v_end   := v_start + 6;
  v_key   := v_company||':'||to_char(v_start,'IYYY-"W"IW');

  -- UNFILTERED. Never `and status in (...)`.
  select * into v_row from public.accountant_weekly_report where report_key = v_key;

  if found and not p_revise then
    return jsonb_build_object(
      'report_key', v_row.report_key, 'id', v_row.id, 'revision', v_row.revision,
      'status', v_row.status, 'generated', false, 'reason', 'already generated for this ISO week',
      'week_start', v_row.week_start, 'week_end', v_row.week_end,
      'pdf_pending', v_row.pdf_path is null,
      'pdf_blocks', case when v_row.pdf_path is null then v_row.pdf_blocks else null end,
      'subject', v_row.subject,
      'delivered', v_row.delivered_at is not null,
      'delivery_attempts', v_row.delivery_attempts);
  end if;

  v_now  := public.fn_accountant_weekly_report_figures(v_start, v_end);
  v_prev := public.fn_accountant_weekly_report_figures(v_start - 7, v_end - 7);

  -- BUILD THE TABLE. One row per line item: what it is, what it says, on what basis, and how it
  -- moved. A line whose basis is 'unknown' prints the word and never a number.
  foreach v_k in array v_order loop
    v_ln := v_now->'lines'->v_k;
    v_pn := v_prev->'lines'->v_k;
    if v_ln is null then continue; end if;

    if (v_ln->>'basis') = 'unknown' then
      v_val := 'UNKNOWN';
      v_unknown := v_unknown + 1;
    elsif v_ln ? 'aed' then
      v_val := 'AED '||to_char((v_ln->>'aed')::numeric, 'FM999,999,990.00')
               || case when v_ln ? 'n' then ' ('||(v_ln->>'n')||')' else '' end;
    else
      v_val := coalesce(v_ln->>'n', '-');
    end if;
    if (v_ln->>'basis') = 'true zero' then v_truezero := v_truezero + 1;
    elsif (v_ln->>'basis') = 'measured' then v_measured := v_measured + 1; end if;

    -- WEEK-OVER-WEEK. A movement is only stated when BOTH weeks carry a comparable number.
    if v_pn is null or (v_pn->>'basis') = 'unknown' or (v_ln->>'basis') = 'unknown' then
      v_mov := 'not comparable';
    elsif v_ln ? 'aed' and v_pn ? 'aed' then
      v_mov := case when (v_ln->>'aed')::numeric - (v_pn->>'aed')::numeric >= 0 then '+' else '' end
               || to_char((v_ln->>'aed')::numeric - (v_pn->>'aed')::numeric, 'FM999,999,990.00');
    elsif v_ln ? 'n' and v_pn ? 'n' then
      v_mov := case when (v_ln->>'n')::int - (v_pn->>'n')::int >= 0 then '+' else '' end
               || ((v_ln->>'n')::int - (v_pn->>'n')::int)::text;
    else
      v_mov := 'not comparable';
    end if;

    v_rows := v_rows || jsonb_build_array(jsonb_build_array(
      coalesce(v_label->>v_k, v_k), v_val, upper(coalesce(v_ln->>'basis','?')), v_mov));
  end loop;

  v_subject := 'QuotesDone weekly financial report - '||to_char(v_start,'IYYY-"W"IW')
               ||' ('||to_char(v_start,'DD Mon')||' to '||to_char(v_end,'DD Mon YYYY')||')';

  v_body :=
    'WEEKLY FINANCIAL REPORT'||E'\n'||
    to_char(v_start,'Dy DD Mon YYYY')||' to '||to_char(v_end,'Dy DD Mon YYYY')||' (Asia/Dubai) - ISO '||to_char(v_start,'IYYY-"W"IW')||E'\n'||
    'Prepared by the accountant seat. Informational: nothing here asks you for a decision.'||E'\n\n'||
    'HOW TO READ THE BASIS COLUMN'||E'\n'||
    '- MEASURED   the figure was computed over source rows that exist.'||E'\n'||
    '- TRUE ZERO  the source table holds no rows at all, so the figure is zero over a zero denominator.'||E'\n'||
    '- UNKNOWN    no record exists from which the figure could be derived. It is NOT zero.'||E'\n\n';

  foreach v_k in array v_order loop
    v_ln := v_now->'lines'->v_k;
    if v_ln is null then continue; end if;
    v_body := v_body || upper(coalesce(v_label->>v_k, v_k))||E'\n'||
      '  '||case when (v_ln->>'basis') = 'unknown' then 'UNKNOWN'
                 when v_ln ? 'aed' then 'AED '||to_char((v_ln->>'aed')::numeric,'FM999,999,990.00')
                 else coalesce(v_ln->>'n','-') end||
      '   ['||upper(v_ln->>'basis')||']'||E'\n'||
      '  '||coalesce(v_ln->>'note','')||E'\n\n';
  end loop;

  v_body := v_body ||
    'RECONCILIATION OF THE TWO CASHFLOW SOURCES'||E'\n'||
    'The founder named two, and only two: Stripe in, the expenses mailbox out. Against the ledger:'||E'\n'||
    '- Stripe in:  '||coalesce(v_now->'lines'->'stripe_settlement_events'->>'note','')||E'\n'||
    '- Mailbox out: '||coalesce(v_now->'lines'->'cash_out_this_week'->>'note','')||E'\n'||
    '- Ledger:     '||coalesce(v_now->'lines'->'journal_entries_posted'->>'note','')||E'\n\n'||
    'BASIS SUMMARY: '||v_measured||' measured, '||v_truezero||' true zero, '||v_unknown||' unknown, of '||
      (v_measured + v_truezero + v_unknown)||' line item(s).'||E'\n'||
    case when v_unknown > 0
      then 'An unknown is not a gap in this report. It is the report refusing to publish a number it cannot bind to a source row.'
      else 'Every line item on this report binds to a source row.' end;

  -- THE PDF BLOCKS. pdf_native's own block vocabulary; letterhead on, strict glyphs on.
  v_blocks := jsonb_build_array(
    jsonb_build_object('t','h2','text','Weekly financial report'),
    jsonb_build_object('t','p','text', to_char(v_start,'Dy DD Mon YYYY')||' to '||to_char(v_end,'Dy DD Mon YYYY')||
                                       '  (Asia/Dubai)   ISO '||to_char(v_start,'IYYY-"W"IW')||'   Revision '||
                                       coalesce(v_row.revision + 1, 1)::text),
    jsonb_build_object('t','note','text','Prepared by the accountant seat and reported to the CEO. Informational: nothing in this document asks for a decision or an approval.'),
    jsonb_build_object('t','space','h',6),
    jsonb_build_object('t','h3','text','Position'),
    jsonb_build_object('t','table',
      'head', jsonb_build_array('Line item','This week','Basis','vs prior week'),
      'rows', v_rows,
      'widths', jsonb_build_array(0.42, 0.24, 0.16, 0.18)),
    jsonb_build_object('t','space','h',8),
    jsonb_build_object('t','h3','text','What the basis column means'),
    jsonb_build_object('t','li','text','MEASURED - computed over source rows that exist.'),
    jsonb_build_object('t','li','text','TRUE ZERO - the source table holds no rows at all; the figure is zero over a zero denominator.'),
    jsonb_build_object('t','li','text','UNKNOWN - no record exists from which the figure could be derived. It is not zero, and it is not an omission.'),
    jsonb_build_object('t','space','h',8),
    jsonb_build_object('t','h3','text','Every figure, and the rows it binds to'));

  foreach v_k in array v_order loop
    v_ln := v_now->'lines'->v_k;
    if v_ln is null then continue; end if;
    v_blocks := v_blocks || jsonb_build_array(
      jsonb_build_object('t','p','bold',true,'text', coalesce(v_label->>v_k, v_k)||
        ' - '||case when (v_ln->>'basis') = 'unknown' then 'UNKNOWN'
                    when v_ln ? 'aed' then 'AED '||to_char((v_ln->>'aed')::numeric,'FM999,999,990.00')
                    else coalesce(v_ln->>'n','-') end||'  ['||upper(v_ln->>'basis')||']'),
      jsonb_build_object('t','note','text', coalesce(v_ln->>'note','')));
  end loop;

  v_blocks := v_blocks || jsonb_build_array(
    jsonb_build_object('t','space','h',8),
    jsonb_build_object('t','h3','text','Reconciliation of the two cashflow sources'),
    jsonb_build_object('t','p','text','The founder named two, and only two: Stripe in, the expenses mailbox out. Reconciled against the general ledger, this week reads as follows.'),
    jsonb_build_object('t','li','text','Stripe in - '||coalesce(v_now->'lines'->'stripe_settlement_events'->>'note','')),
    jsonb_build_object('t','li','text','Mailbox out - '||coalesce(v_now->'lines'->'cash_out_this_week'->>'note','')),
    jsonb_build_object('t','li','text','Ledger - '||coalesce(v_now->'lines'->'journal_entries_posted'->>'note','')),
    jsonb_build_object('t','space','h',6),
    jsonb_build_object('t','p','bold',true,'text','Basis summary: '||v_measured||' measured, '||v_truezero||
      ' true zero, '||v_unknown||' unknown, of '||(v_measured+v_truezero+v_unknown)||' line items.'),
    jsonb_build_object('t','note','text', case when v_unknown > 0
      then 'An unknown is not a gap in this report. It is the report refusing to publish a number it cannot bind to a source row.'
      else 'Every line item on this report binds to a source row.' end));

  if p_revise and v_row.id is not null then
    update public.accountant_weekly_report
       set revision = revision + 1, revision_note = p_revision_note,
           subject = v_subject, body = v_body,
           figures = jsonb_build_object('this_week', v_now, 'prior_week', v_prev,
                                        'basis_counts', jsonb_build_object('measured', v_measured,
                                          'true_zero', v_truezero, 'unknown', v_unknown)),
           pdf_blocks = v_blocks,
           -- A correction regenerates the document. The old PDF is not the new report.
           pdf_path = null, pdf_url = null, pdf_bytes = null, pdf_generated_at = null, pdf_error = null,
           status = 'generated', generated_at = now(), updated_at = now(),
           -- A CORRECTION MUST BE ABLE TO REACH THE PEOPLE WHO GOT THE ORIGINAL. deliver() skips
           -- the founder lane when founder_submitted_at is set and the CEO lane when
           -- ceo_submitted_at is, so bumping the revision without clearing these left every
           -- correction unreachable behind the copy it replaces: regenerated, re-rendered,
           -- reported ok, delivered to nobody. The CEO idempotency key already carries
           -- ':r'||revision, so a re-opened lane cannot collide with the report it supersedes.
           founder_submitted_at = null, ceo_submitted_at = null,
           notification_id = null, ceo_report_id = null,
           delivered_at = null, delivery_attempts = 0, last_delivery_error = null
     where id = v_row.id
    returning * into v_row;
  else
    insert into public.accountant_weekly_report(
      company_key, iso_year, iso_week, week_start, week_end, local_timezone, report_key,
      revision, revision_note, subject, body, figures, pdf_blocks, status)
    values (
      v_company, extract(isoyear from v_start)::int, extract(week from v_start)::int,
      v_start, v_end, v_tz, v_key, 1, p_revision_note, v_subject, v_body,
      jsonb_build_object('this_week', v_now, 'prior_week', v_prev,
                         'basis_counts', jsonb_build_object('measured', v_measured,
                           'true_zero', v_truezero, 'unknown', v_unknown)),
      v_blocks, 'generated')
    returning * into v_row;
  end if;

  return jsonb_build_object(
    'report_key', v_row.report_key, 'id', v_row.id, 'revision', v_row.revision,
    'status', v_row.status, 'generated', true,
    'week_start', v_row.week_start, 'week_end', v_row.week_end,
    'subject', v_row.subject,
    'basis', jsonb_build_object('measured', v_measured, 'true_zero', v_truezero, 'unknown', v_unknown),
    'pdf_pending', true, 'pdf_blocks', v_blocks);
end;$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_weekly_report_attach_pdf(p_id bigint, p_bucket text DEFAULT NULL::text, p_path text DEFAULT NULL::text, p_url text DEFAULT NULL::text, p_bytes integer DEFAULT NULL::integer, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row public.accountant_weekly_report%rowtype;
begin
  select * into v_row from public.accountant_weekly_report where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such report'); end if;

  if p_path is null or coalesce(p_error,'') <> '' then
    update public.accountant_weekly_report
       set pdf_error = coalesce(nullif(p_error,''), 'pdf_native returned no path'),
           status = case when delivered_at is null then 'pdf_failed' else status end,
           delivery_attempts = delivery_attempts + 1,
           last_delivery_error = 'the PDF could not be rendered: '||coalesce(nullif(p_error,''),'no path returned'),
           updated_at = now()
     where id = p_id returning * into v_row;
    -- RETAINED, NOT LOST. The next tick re-renders from the stored blocks.
    return jsonb_build_object('ok', false, 'report_key', v_row.report_key, 'retained', true,
      'reason', v_row.pdf_error, 'delivery_attempts', v_row.delivery_attempts);
  end if;

  update public.accountant_weekly_report
     set pdf_bucket = p_bucket, pdf_path = p_path, pdf_url = p_url, pdf_bytes = p_bytes,
         pdf_generated_at = now(), pdf_error = null,
         status = case when status = 'pdf_failed' then 'generated' else status end,
         updated_at = now()
   where id = p_id returning * into v_row;

  return public.fn_accountant_weekly_report_deliver(p_id);
end;$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_weekly_report_deliver(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_row     public.accountant_weekly_report%rowtype;
  v_owner   text;
  v_rpt     jsonb;
  v_notif   bigint;
  v_ceo_id  bigint;
  v_errs    text[] := '{}';
  v_link    text;
  v_body    text;
  v_file    text;
  v_attach  jsonb;
begin
  select * into v_row from public.accountant_weekly_report where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such report'); end if;

  -- THE PDF IS THE DELIVERABLE. He asked for the report AS a PDF; mailing the text alone and
  -- marking the week delivered would close the key on something he did not ask for.
  if v_row.pdf_path is null then
    update public.accountant_weekly_report
       set delivery_attempts = delivery_attempts + 1,
           last_delivery_error = 'not delivered: the PDF has not been rendered yet. The report is retained and the next tick retries.',
           updated_at = now()
     where id = p_id returning * into v_row;
    return jsonb_build_object('ok', false, 'report_key', v_row.report_key, 'retained', true,
      'reason', 'pdf not yet rendered', 'delivery_attempts', v_row.delivery_attempts);
  end if;

  -- The attachment the founder actually opens. Built from the row so the name cannot drift from
  -- the week it reports, and stripped to what the attachment guard accepts.
  v_file := 'QuotesDone_Weekly_Financial_Report_'
         || regexp_replace(replace(v_row.report_key, 'quotesdone:', ''), '[^A-Za-z0-9_-]', '_', 'g')
         || case when coalesce(v_row.revision, 1) > 1 then '_revision_'||v_row.revision else '' end
         || '.pdf';
  v_attach := jsonb_build_array(jsonb_build_object(
    'bucket',   coalesce(v_row.pdf_bucket, 'agent-docs'),
    'path',     v_row.pdf_path,
    'filename', v_file));

  -- The link stays, underneath the attachment rather than instead of it.
  v_link := case when v_row.pdf_url is not null
    then E'\n\n'||'The report is attached as '||v_file||'.'||E'\n'
       ||'If your mail client has stripped it, the same document is here: '||v_row.pdf_url||E'\n'
       ||'(That link is signed and expires seven days from generation; the document itself is retained at '||coalesce(v_row.pdf_bucket,'agent-docs')||'/'||v_row.pdf_path||'.)'
    else E'\n\n'||'The report is attached as '||v_file||'. It is retained at '||coalesce(v_row.pdf_bucket,'agent-docs')||'/'||v_row.pdf_path||'.' end;
  v_body := coalesce(v_row.body,'') || v_link;

  -- ---- LANE 1: THE FOUNDER -------------------------------------------------------------------
  if v_row.founder_submitted_at is null then
    select nullif(btrim(split_part(coalesce(value,''), ',', 1)), '') into v_owner
      from public.app_secrets where key = 'admin_emails';
    if v_owner is null then
      v_errs := v_errs || 'no recipient configured in app_secrets.admin_emails';
    else
      begin
        insert into public.notifications(type, kind, to_email, to_role, channel, subject, body, attachments)
        values ('accountant_weekly_report', 'accountant_weekly_report', v_owner, 'admin', 'email',
                v_row.subject, v_body, v_attach)
        returning id into v_notif;
        if v_notif is null then
          -- The gate returned NULL: a refusal, not an error. Name it, do not swallow it.
          v_errs := v_errs || 'the founder-mail gate did not accept the row (kind accountant_weekly_report)';
        end if;
      exception when others then
        -- a20_notifications_attachment_policy RAISES on a bad reference rather than dropping the
        -- row, so a malformed attachment lands here by name instead of vanishing.
        v_errs := v_errs || ('founder submission raised: '||sqlerrm);
      end;
    end if;
  end if;

  -- ---- LANE 2: THE CEO -----------------------------------------------------------------------
  -- ONE ROUTINE OWNS THIS, NOT TWO. This block used to open-code its own INSERT into
  -- support_ceo_report, because fn_support_report_to_ceo hardcoded 'customer_support' as the sender
  -- in three places and the accountant could not use it without filing under Support's name. That
  -- was fixed on 9 Sep 2026 with p_source_agent, so the private copy is now only a second place for
  -- the rules to drift.
  --
  -- WHAT MOVED BACK: the manager lookup (the shared routine reads the SENDER's reporting edge and
  -- refuses rather than picking someone), the requirement that a report states what it wants, and
  -- idempotency by business event. Its duplicate path returns the existing row's id with
  -- duplicate=true, which is exactly what the unique_violation handler here did by hand -- and it no
  -- longer depends on a constraint name a future migration could rename.
  --
  -- IT RETURNS jsonb, NOT AN id, and it REFUSES rather than raising. So a CEO copy that does not go
  -- now lands in last_delivery_error as a sentence instead of leaving ceo_submitted_at silently null.
  if v_row.ceo_submitted_at is null then
    begin
      v_rpt := public.fn_support_report_to_ceo(
        p_idempotency_key => 'accountant_weekly_report:'||v_row.report_key||':r'||v_row.revision,
        p_severity        => 'routine',
        p_subject         => v_row.subject,
        p_evidence        => jsonb_build_object(
                               'report_key', v_row.report_key, 'revision', v_row.revision,
                               'week_start', v_row.week_start, 'week_end', v_row.week_end,
                               'pdf', coalesce(v_row.pdf_bucket,'agent-docs')||'/'||v_row.pdf_path,
                               'pdf_filename', v_file,
                               'pdf_bytes', v_row.pdf_bytes,
                               'basis_counts', v_row.figures->'basis_counts',
                               'figures', v_row.figures->'this_week'->'lines'),
        p_attempted       => '[]'::jsonb,
        p_requested       => 'Note the week''s financial position. NOTHING IS REQUESTED: this is the informational weekly report the founder asked for on 9 Sep 2026, delivered to the CEO because the accountant reports to the CEO. It carries no decision, no approval and no deadline. Refund and Meta-ads approvals reach the CEO through their own lanes, never through this one.',
        p_review_in       => interval '7 days',
        p_source_agent    => 'accountant');

      if coalesce((v_rpt->>'ok')::boolean, false) then
        -- Covers the fresh insert AND the duplicate: a revision already reported IS the delivery,
        -- and the shared routine hands back that report's id either way.
        v_ceo_id := (v_rpt->>'report_id')::bigint;
      else
        v_errs := v_errs || ('CEO submission refused: '||coalesce(v_rpt->>'reason','(no reason given)'));
      end if;
    exception when others then
      v_errs := v_errs || ('CEO submission raised: '||sqlerrm);
    end;
  end if;

  update public.accountant_weekly_report
     set notification_id      = coalesce(v_notif, notification_id),
         founder_submitted_at = case when v_notif is not null then now() else founder_submitted_at end,
         ceo_report_id        = coalesce(v_ceo_id, ceo_report_id),
         ceo_submitted_at     = case when v_ceo_id is not null then now() else ceo_submitted_at end,
         delivery_attempts    = delivery_attempts + 1,
         last_delivery_error  = nullif(array_to_string(v_errs, ' | '), ''),
         updated_at           = now()
   where id = p_id returning * into v_row;

  update public.accountant_weekly_report
     set status = case
           when v_row.founder_submitted_at is not null and v_row.ceo_submitted_at is not null then 'delivered'
           when v_row.founder_submitted_at is not null or  v_row.ceo_submitted_at is not null then 'partial'
           else 'delivery_failed' end,
         delivered_at = case
           when v_row.founder_submitted_at is not null and v_row.ceo_submitted_at is not null
           then coalesce(delivered_at, now()) else delivered_at end
   where id = p_id returning * into v_row;

  return jsonb_build_object(
    'ok', v_row.status in ('delivered','partial'),
    'report_key', v_row.report_key, 'id', v_row.id, 'revision', v_row.revision,
    'status', v_row.status,
    'founder_submitted', v_row.founder_submitted_at is not null,
    'ceo_submitted', v_row.ceo_submitted_at is not null,
    'ceo_report_id', v_row.ceo_report_id,
    'pdf_filename', v_file,
    'delivery_attempts', v_row.delivery_attempts,
    'error', v_row.last_delivery_error);
end;$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_weekly_report_figures(p_start date, p_end date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tz text := 'Asia/Dubai';
  v_from timestamptz := (p_start::timestamp) at time zone v_tz;
  v_to   timestamptz := ((p_end + 1)::timestamp) at time zone v_tz;
  -- revenue
  v_txn_all int; v_txn_n int; v_rev numeric;
  v_stripe_all int; v_stripe_n int; v_stripe_last timestamptz;
  -- expenses
  v_ee_all int; v_ee_n int; v_ee_aed numeric;
  v_rcpt_all int; v_rcpt_n int;
  v_exp_all int; v_exp_active int;
  -- refunds
  v_ref_all int; v_ref_n int; v_ref_aed numeric; v_ref_settled int;
  -- payables
  v_ap_all int; v_ap_open int; v_ap_due numeric;
  -- ledger
  v_gl_all int; v_gl_lines int; v_gl_n int; v_dr numeric; v_cr numeric;
  v_cash numeric;
  -- platform cost
  v_ai_all int; v_ai_n int; v_ai_aed numeric; v_ai_models text; v_ai_unpriced int;
  v_lines jsonb;
begin
  select count(*) into v_txn_all from transactions;
  select count(*), coalesce(sum(coalesce(reveal_fee, app_fee, 0)), 0)
    into v_txn_n, v_rev
    from transactions
   where revealed_at >= v_from and revealed_at < v_to
     and coalesce(fee_status,'') <> 'refunded' and coalesce(refund_status,'') <> 'approved';

  select count(*), max(last_seen_at) into v_stripe_all, v_stripe_last from stripe_events;
  select count(*) into v_stripe_n from stripe_events
   where first_seen_at >= v_from and first_seen_at < v_to;

  select count(*) into v_ee_all from expense_entries;
  select count(*), coalesce(sum(amount), 0) into v_ee_n, v_ee_aed
    from expense_entries where charged_on between p_start and p_end;

  -- The receipts that ARRIVED. This is the counter-evidence to a zero on the line above, and it is
  -- why money-out can be 'unknown' rather than a comfortable 0.
  select count(*) into v_rcpt_all from inbound_messages where coalesce(to_email,'') ilike '%expense%';
  select count(*) into v_rcpt_n from inbound_messages
   where coalesce(to_email,'') ilike '%expense%' and created_at >= v_from and created_at < v_to;

  select count(*), count(*) filter (where active) into v_exp_all, v_exp_active from expenses;

  select count(*) into v_ref_all from refunds;
  select count(*), coalesce(sum(amount_fils), 0) / 100.0, count(*) filter (where settled_at is not null)
    into v_ref_n, v_ref_aed, v_ref_settled
    from refunds where requested_at >= v_from and requested_at < v_to;

  select count(*) into v_ap_all from ap_bills;
  select count(*), coalesce(sum(greatest(total - coalesce(amount_paid,0), 0)), 0)
    into v_ap_open, v_ap_due
    from ap_bills where coalesce(status,'') not in ('paid','void','cancelled');

  select count(*) into v_gl_all from gl_journal;
  select count(*) into v_gl_lines from gl_journal_lines;
  select count(*) into v_gl_n from gl_journal where entry_date between p_start and p_end;
  select coalesce(sum(l.debit),0), coalesce(sum(l.credit),0) into v_dr, v_cr
    from gl_journal_lines l join gl_journal j on j.id = l.journal_id
   where j.entry_date between p_start and p_end;
  select coalesce(sum(balance),0) into v_cash from gl_account_balances where code in ('1000','1050');

  select count(*) into v_ai_all from ai_cost_log;
  select count(*), coalesce(sum(cost_aed),0), coalesce(string_agg(distinct coalesce(model_used,'?'), ', '), ''),
         count(*) filter (where cost_aed is null and not cached and coalesce(model_used, 'none') <> 'none')
    into v_ai_n, v_ai_aed, v_ai_models, v_ai_unpriced
    from ai_cost_log where occurred_at >= v_from and occurred_at < v_to;

  v_lines := jsonb_build_object(

    -- MONEY IN -------------------------------------------------------------------------------
    'reveal_fee_revenue', jsonb_build_object(
      'aed', v_rev, 'n', v_txn_n, 'denom', v_txn_all,
      'basis', case when v_txn_all = 0 then 'true zero' else 'measured' end,
      'note', case when v_txn_all = 0
        then 'public.transactions holds 0 rows in total, so no reveal fee has been recorded for this week or any other. The denominator is zero, not the numerator only.'
        else v_txn_n||' reveal(s) settled in the window, of '||v_txn_all||' transaction row(s) on record; refunded and refund-approved rows excluded.' end),

    'stripe_settlement_events', jsonb_build_object(
      'n', v_stripe_n, 'denom', v_stripe_all,
      'basis', case when v_stripe_all = 0 then 'true zero' else 'measured' end,
      -- ZERO CANNOT TELL A DEAD FEED FROM AN IDLE ONE. Say which this is.
      'note', case when v_stripe_all = 0
        then 'public.stripe_events holds 0 rows and has never recorded one, so 0 events this week is NOT evidence that the Stripe webhook is live and the week was quiet. It is equally consistent with the feed never having delivered. Treat the revenue line above as bounded by that.'
        else v_stripe_n||' event(s) first seen in the window, of '||v_stripe_all||' ever recorded; most recent activity '||coalesce(v_stripe_last::text,'unknown')||'.' end),

    -- MONEY OUT ------------------------------------------------------------------------------
    'expenses_filed_to_ledger', jsonb_build_object(
      'aed', v_ee_aed, 'n', v_ee_n, 'denom', v_ee_all,
      'basis', case when v_ee_all = 0 then 'true zero' else 'measured' end,
      'note', case when v_ee_all = 0
        then 'public.expense_entries holds 0 rows in total. Nothing has ever been filed against the chart of accounts. This is a statement about the bookkeeping, not about the spending.'
        else v_ee_n||' receipt(s) filed with a charge date in the window, of '||v_ee_all||' entr(ies) on record.' end),

    'receipts_received_at_the_expenses_inbox', jsonb_build_object(
      'n', v_rcpt_n, 'denom', v_rcpt_all,
      'basis', case when v_rcpt_all = 0 then 'true zero' else 'measured' end,
      'note', v_rcpt_n||' message(s) reached the expenses inbox inside the window; '||v_rcpt_all||' have reached it in total. Counted from public.inbound_messages, which records arrival, not amount.'),

    -- THE HONEST ONE. If receipts arrived and none was filed, the amount spent is NOT derivable,
    -- and printing 0 would be false in the direction that flatters the company.
    'cash_out_this_week', case
      when v_rcpt_n > v_ee_n then jsonb_build_object(
        'basis', 'unknown',
        'note', v_rcpt_n||' receipt(s) arrived at the expenses inbox inside this window and '||v_ee_n||
                ' were filed to the ledger, so the amount actually spent cannot be derived from any row. '||
                'It is UNKNOWN. It is not zero, and the gap ('||(v_rcpt_n - v_ee_n)||' unfiled receipt(s)) is the reason.')
      when v_ee_all = 0 and v_rcpt_all > 0 then jsonb_build_object(
        'basis', 'unknown',
        'note', 'No receipt has ever been filed to the ledger while '||v_rcpt_all||' have arrived at the expenses inbox. '||
                'Spending for this window is UNKNOWN; a zero here would assert the company spent nothing, which the inbox contradicts.')
      when v_ee_all = 0 and v_rcpt_all = 0 then jsonb_build_object(
        'aed', 0, 'basis', 'true zero',
        'note', 'Both public.expense_entries and the expenses inbox hold 0 rows, so nothing was spent as far as any source row can say, over a denominator of zero.')
      else jsonb_build_object(
        'aed', v_ee_aed, 'n', v_ee_n, 'denom', v_ee_all, 'basis', 'measured',
        'note', 'Every receipt that arrived in the window ('||v_rcpt_n||') has a filed entry; the total is the sum of those entries.') end,

    'recurring_cost_schedule', case
      when v_exp_all = 0 and v_rcpt_all > 0 then jsonb_build_object(
        'basis', 'unknown',
        'note', 'public.expenses holds 0 rows, so no recurring cost is on record -- while the expenses inbox holds '||v_rcpt_all||
                ' vendor receipt(s), which is direct evidence that recurring costs exist. The monthly run rate is UNKNOWN, not zero.')
      when v_exp_all = 0 then jsonb_build_object(
        'n', 0, 'denom', 0, 'basis', 'true zero',
        'note', 'public.expenses holds 0 rows and no receipt has arrived to contradict that.')
      else jsonb_build_object(
        'n', v_exp_active, 'denom', v_exp_all, 'basis', 'measured',
        'note', v_exp_active||' active recurring cost(s) of '||v_exp_all||' on record.') end,

    -- REFUNDS --------------------------------------------------------------------------------
    'refunds_requested', jsonb_build_object(
      'aed', v_ref_aed, 'n', v_ref_n, 'denom', v_ref_all, 'settled', v_ref_settled,
      'basis', case when v_ref_all = 0 then 'true zero' else 'measured' end,
      'note', case when v_ref_all = 0
        then 'public.refunds holds 0 rows in total. No refund has ever been requested, so nothing was decided and nothing was declined -- this is an empty table, not a clean queue.'
        else v_ref_n||' requested in the window ('||v_ref_settled||' settled), of '||v_ref_all||' on record. Every refund decision belongs to the CEO (ceo_standing_grant accountant.refund_decision, max_amount_aed 0).' end),

    -- PAYABLES -------------------------------------------------------------------------------
    'outstanding_bills', jsonb_build_object(
      'aed', v_ap_due, 'n', v_ap_open, 'denom', v_ap_all,
      'basis', case when v_ap_all = 0 then 'true zero' else 'measured' end,
      'note', case when v_ap_all = 0
        then 'public.ap_bills holds 0 rows, so 0 outstanding means NO BILL HAS BEEN ENTERED -- it is not a statement that nothing is owed. The '||v_rcpt_all||' receipt(s) in the expenses inbox are evidence to the contrary.'
        else v_ap_open||' open bill(s) of '||v_ap_all||' on record, '||to_char(v_ap_due,'FM999,999,990.00')||' AED still due.' end),

    -- CASH -----------------------------------------------------------------------------------
    'cash_position', case
      when v_gl_lines = 0 then jsonb_build_object(
        'basis', 'unknown',
        'note', 'The general ledger holds 0 posted lines, and the database carries no bank feed or statement balance. The 1000 Cash & Bank and 1050 Stripe Clearing accounts therefore read 0.00 because NOTHING HAS BEEN POSTED, which is the absence of bookkeeping and not a bank balance. Cash position is UNKNOWN.')
      else jsonb_build_object(
        'aed', v_cash, 'denom', v_gl_lines, 'basis', 'measured',
        'note', 'Sum of the 1000 Cash & Bank and 1050 Stripe Clearing balances across '||v_gl_lines||' posted ledger line(s). It is a book balance, not a confirmed bank statement.') end,

    -- LEDGER ---------------------------------------------------------------------------------
    'journal_entries_posted', jsonb_build_object(
      'n', v_gl_n, 'denom', v_gl_all, 'debits', v_dr, 'credits', v_cr,
      'basis', case when v_gl_all = 0 then 'true zero' else 'measured' end,
      'note', case when v_gl_all = 0
        then 'public.gl_journal holds 0 entries. Debits 0.00 equal credits 0.00, and a trial balance that balances across ZERO entries proves nothing about the books -- it proves there are none. 30 accounts and 6 expense mappings are configured and unused.'
        else v_gl_n||' entr(ies) dated inside the window, of '||v_gl_all||' on record; debits '||to_char(v_dr,'FM999,999,990.00')||' against credits '||to_char(v_cr,'FM999,999,990.00')||
             case when v_dr = v_cr then ' -- balanced.' else ' -- OUT OF BALANCE by '||to_char(abs(v_dr-v_cr),'FM999,999,990.00')||'.' end end),

    -- PLATFORM COST --------------------------------------------------------------------------
    'ai_and_model_cost', jsonb_build_object(
      'aed', v_ai_aed, 'n', v_ai_n, 'denom', v_ai_all, 'models', v_ai_models, 'unpriced', v_ai_unpriced,
      'basis', case when v_ai_all = 0 then 'true zero' else 'measured' end,
      'note', case when v_ai_all = 0
        then 'public.ai_cost_log holds 0 rows.'
        else v_ai_n||' model call(s) inside the window, of '||v_ai_all||' logged in total, costing '||to_char(v_ai_aed,'FM999,999,990.00')||
             ' AED. Models used: '||coalesce(nullif(v_ai_models,''),'none in this window')||
             case when v_ai_unpriced > 0 then ' '||v_ai_unpriced||' call(s) returned no usage, so their cost is unknown and this total is a lower bound.' else '' end||
             case when v_ai_models = 'none' then '. Every logged call resolved to model_used=''none'', so this zero is a real measured zero: the paid route was refused, not that the work was free.' else '.' end end)
  );

  return jsonb_build_object(
    'window', jsonb_build_object('start', p_start, 'end', p_end, 'timezone', v_tz,
                                 'iso', to_char(p_start,'IYYY-"W"IW')),
    'lines', v_lines,
    'measured_at', now());
end;$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_weekly_report_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tz    text := 'Asia/Dubai';
  v_local timestamp;
  v_at    time;
  v_dow   int;
  v_start date;
  v_key   text;
  v_row   public.accountant_weekly_report%rowtype;
begin
  v_local := now() at time zone v_tz;
  v_start := (date_trunc('week', v_local::date) - interval '7 days')::date;   -- the week that closed
  v_key   := 'quotesdone:'||to_char(v_start,'IYYY-"W"IW');

  begin
    select coalesce(nullif(btrim(value),''),'09:00')::time into v_at
      from public.app_secrets where key = 'accountant_weekly_report_local_time';
  exception when others then v_at := time '09:00'; end;
  v_at := coalesce(v_at, time '09:00');

  begin
    select coalesce(nullif(btrim(value),''),'1')::int into v_dow
      from public.app_secrets where key = 'accountant_weekly_report_local_dow';
  exception when others then v_dow := 1; end;
  v_dow := coalesce(v_dow, 1);

  select * into v_row from public.accountant_weekly_report where report_key = v_key;

  -- A REPORT ALREADY IN FLIGHT IS FINISHED WHATEVER DAY IT IS. The schedule decides when a week's
  -- report STARTS, not when a half-delivered one may be retried -- otherwise a Monday failure would
  -- wait a week, which is precisely the "retained but never retried" state this shape exists to
  -- prevent.
  if found then
    if v_row.pdf_path is null then
      return jsonb_build_object('fired', true, 'reason', 'the PDF for this week is still outstanding',
        'report_key', v_key, 'id', v_row.id, 'revision', v_row.revision, 'status', v_row.status,
        'pdf_pending', true, 'pdf_blocks', v_row.pdf_blocks, 'subject', v_row.subject);
    end if;
    if v_row.delivered_at is null then
      return public.fn_accountant_weekly_report_deliver(v_row.id)
             || jsonb_build_object('fired', true, 'reason', 'retrying an undelivered lane');
    end if;
    return jsonb_build_object('fired', false, 'reason', 'already generated and delivered for this ISO week',
      'report_key', v_key, 'id', v_row.id, 'revision', v_row.revision, 'status', v_row.status);
  end if;

  if extract(isodow from v_local)::int < v_dow or (extract(isodow from v_local)::int = v_dow and v_local::time < v_at) then
    return jsonb_build_object('fired', false, 'reason', 'before the configured local day/time',
      'local_now', to_char(v_local,'Dy YYYY-MM-DD HH24:MI'), 'configured_dow', v_dow,
      'configured_at', v_at::text, 'report_key', v_key);
  end if;

  return public.fn_accountant_weekly_report(v_start)
         || jsonb_build_object('fired', true, 'configured_at', v_at::text, 'configured_dow', v_dow);
end;$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_year_end_duty()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_y int := extract(year from now() at time zone 'Asia/Dubai')::int; v_rev numeric; v_rep jsonb;
begin
  -- the Corporate Tax audit condition (MD 82/2023, MD 84/2025): revenue over AED 50m in the period. A sole establishment
  -- is outside the Companies Law auditor duty, so this is the only test that could ever require an audit.
  select coalesce(sum(jl.credit - jl.debit), 0) into v_rev
    from public.gl_journal j join public.gl_journal_lines jl on jl.journal_id = j.id
    join public.gl_accounts ac on ac.code = jl.account_code and ac.type in ('revenue', 'other_income')
   where j.status = 'posted' and extract(year from j.entry_date) = v_y;
  if v_rev > 0.8 * 50000000 then
    v_rep := public.fn_support_report_to_ceo('accountant.audit_threshold:' || v_y, 'elevated',
      format('Revenue for %s is AED %s, over 80%% of the AED 50m Corporate Tax audit threshold', v_y, v_rev),
      jsonb_build_object('year', v_y, 'revenue_aed', v_rev, 'basis', 'Ministerial Decision 84 of 2025 (formerly 82 of 2023)'), '[]'::jsonb,
      'Appoint an auditor for this tax period before its year end.', null, null, interval '3 days', 'accountant');
  end if;
  return jsonb_build_object('year_end', public.fn_accountant_year_end_tick(), 'revenue_ytd_aed', v_rev,
    'auditor', case when v_rev > 50000000 then 'required: revenue over AED 50m'
                    else 'not applicable: sole establishment (outside FDL 32/2021), revenue under the AED 50m CT audit threshold, not a free zone person' end,
    'reported', v_rep is not null);
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_year_end_pack_attach(p_year integer, p_files jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if jsonb_typeof(p_files) is distinct from 'array' or jsonb_array_length(p_files) = 0
     or exists (select 1 from jsonb_array_elements(p_files) f
                 where coalesce(f->>'name', '') = '' or coalesce(f->>'bucket', '') = '' or coalesce(f->>'path', '') = '') then
    raise exception 'a year-end pack is recorded only with every file''s name, bucket and path';
  end if;
  insert into public.accountant_year_end_pack (year, files, rendered_at) values (p_year, p_files, now())
  on conflict (year) do update set files = excluded.files, rendered_at = now();
  return jsonb_build_object('ok', true, 'year', p_year, 'files', jsonb_array_length(p_files), 'enqueued', public.fn_enqueue_doc_backups());
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_year_end_pack_document(p_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_d0 date := make_date(p_year, 1, 1); v_d1 date := make_date(p_year, 12, 31);
  v_t0 timestamptz := make_date(p_year, 1, 1)::timestamp at time zone 'Asia/Dubai';
  v_t1 timestamptz := make_date(p_year + 1, 1, 1)::timestamp at time zone 'Asia/Dubai';
  v_ledger text; v_rec text; v_stmt text; v_inv text; v_ref text; v_dis text; v_close text;
begin
  select coalesce(string_agg(public.fn_accountant_csv_row(j.entry_no, j.entry_date::text, j.status, j.source, j.source_ref, j.memo,
                    l.line_no::text, l.account_code, a.name, l.debit::text, l.credit::text, l.memo),
                    E'\n' order by j.entry_date, j.id, l.line_no), '')
    into v_ledger
    from public.gl_journal j join public.gl_journal_lines l on l.journal_id = j.id left join public.gl_accounts a on a.code = l.account_code
   where j.entry_date between v_d0 and v_d1
     and coalesce(j.source, '') <> 'zz_demo' and coalesce(j.memo, '') !~* 'zz[ _-]?demo';

  select coalesce(string_agg(public.fn_accountant_csv_row(p.id, p.arrival_date::text, (p.amount_fils / 100.0)::text, p.currency, p.status,
                    p.bank_line_id::text, b.value_date::text, b.amount_aed::text, b.description, p.matched_at::text),
                    E'\n' order by p.arrival_date, p.id), '')
    into v_rec
    from public.stripe_payout p left join public.bank_statement_line b on b.id = p.bank_line_id
   where p.livemode and p.arrival_date between v_d0 and v_d1;

  select coalesce(string_agg(public.fn_accountant_csv_row(s.source_ref, s.account, s.statement_month::text, s.state, s.lines::text,
                    s.closing_balance_aed::text, s.balance_on::text, s.doc_path, s.received_at::text),
                    E'\n' order by s.received_at), '')
    into v_stmt
    from public.bank_statement_intake s
   where s.account <> 'zz_demo' and coalesce(s.statement_month, (s.received_at at time zone 'Asia/Dubai')::date) between v_d0 and v_d1;

  select coalesce(string_agg(public.fn_accountant_csv_row(t.id::text, t.revealed_at::text, t.stripe_invoice_number, t.stripe_invoice_id,
                    t.total_charged::text, t.reveal_fee::text, t.fee_status, t.doc_path),
                    E'\n' order by t.revealed_at, t.id), '')
    into v_inv
    from public.transactions t left join public.customers c on c.id = t.customer_id
   where t.revealed_at >= v_t0 and t.revealed_at < v_t1 and t.fee_status in ('paid', 'refunded') and not coalesce(c.is_demo, false);

  select coalesce(string_agg(public.fn_accountant_csv_row(r.id::text, r.requested_at::text, r.status, (r.amount_fils / 100.0)::text,
                    r.currency, r.reason_code, r.decided_by, r.settled_at::text, r.stripe_refund_id, r.doc_path),
                    E'\n' order by r.created_at, r.id), '')
    into v_ref
    from public.refunds r left join public.customers c on c.id = r.customer_id
   where r.created_at >= v_t0 and r.created_at < v_t1 and not coalesce(c.is_demo, false);

  select coalesce(string_agg(public.fn_accountant_csv_row(d.id, d.first_seen_at::text, d.reason, d.status, (d.amount_fils / 100.0)::text,
                    d.currency, d.evidence_due_by::text, d.evidence_submitted_at::text, d.submit_trigger, d.outcome, d.closed_at::text),
                    E'\n' order by d.first_seen_at, d.id), '')
    into v_dis
    from public.stripe_dispute d
   where d.livemode and d.first_seen_at >= v_t0 and d.first_seen_at < v_t1;

  select coalesce(string_agg(public.fn_accountant_csv_row(to_char(c.month, 'YYYY-MM'), c.closed_at::text, c.ceo_report_id::text,
                    c.pdf_bucket, c.pdf_path, c.csv_path, c.figures#>>'{profit_and_loss,net_result_aed}'),
                    E'\n' order by c.month), '')
    into v_close
    from public.accountant_month_close c
   where c.month between v_d0 and v_d1;

  return jsonb_build_object('year', p_year, 'folder', 'accountant/year-end/' || p_year,
    'files', jsonb_build_array(
      jsonb_build_object('name', p_year || ' Ledger.csv', 'csv',
        'entry_no,entry_date,status,source,source_ref,memo,line_no,account_code,account_name,debit_aed,credit_aed,line_memo' || E'\n' || v_ledger),
      jsonb_build_object('name', p_year || ' Bank reconciliation.csv', 'csv',
        'payout,arrival_date,amount,currency,status,bank_line_id,bank_value_date,bank_amount_aed,bank_description,matched_at' || E'\n' || v_rec),
      jsonb_build_object('name', p_year || ' Bank statements.csv', 'csv',
        'source_ref,account,statement_month,state,lines,closing_balance_aed,balance_on,doc_path,received_at' || E'\n' || v_stmt),
      jsonb_build_object('name', p_year || ' Invoices.csv', 'csv',
        'transaction,revealed_at,stripe_invoice_number,stripe_invoice_id,total_charged_aed,reveal_fee_aed,fee_status,doc_path' || E'\n' || v_inv),
      jsonb_build_object('name', p_year || ' Refunds.csv', 'csv',
        'refund,requested_at,status,amount,currency,reason_code,decided_by,settled_at,stripe_refund_id,doc_path' || E'\n' || v_ref),
      jsonb_build_object('name', p_year || ' Disputes.csv', 'csv',
        'dispute,first_seen_at,reason,status,amount,currency,evidence_due_by,evidence_submitted_at,submit_trigger,outcome,closed_at' || E'\n' || v_dis),
      jsonb_build_object('name', p_year || ' Month closes.csv', 'csv',
        'month,closed_at,ceo_report_id,pdf_bucket,pdf_path,csv_path,net_result_aed' || E'\n' || v_close)));
end $function$


CREATE OR REPLACE FUNCTION public.fn_accountant_year_end_pack_due()
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select z.y from (select extract(year from (now() at time zone 'Asia/Dubai'))::int - 1 as y) z
   where z.y >= coalesce((select num_value::int from public.gl_settings where key = 'year_end_pack_first_year'), 2026)
     and extract(doy from (now() at time zone 'Asia/Dubai')) >= coalesce((select num_value::int from public.gl_settings where key = 'year_end_pack_day'), 15)
     and not exists (select 1 from public.accountant_year_end_pack p where p.year = z.y and p.rendered_at is not null)
$function$


CREATE OR REPLACE FUNCTION public.fn_accountant_year_end_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_y int := public.fn_accountant_year_end_pack_due();
  v_day int := coalesce((select num_value::int from public.gl_settings where key = 'year_end_pack_day'), 15);
  v_items jsonb := '[]'::jsonb;
begin
  if v_y is not null and extract(doy from (now() at time zone 'Asia/Dubai')) >= v_day + 2 then
    v_items := jsonb_build_array(jsonb_build_object('item', 'unfiled:' || v_y, 'owner_seat', 'accountant', 'subject', 'accountant_year_end_pack',
      'title', 'The ' || v_y || ' year-end pack (ledger, bank reconciliations, invoices, refunds, disputes) is not filed: the accountant runtime has not written it to the backups bucket',
      'blast', 'agent_facing', 'affected', 1, 'evidence', jsonb_build_object('year', v_y)));
  end if;
  return jsonb_build_object('due_year', v_y, 'findings', public.fn_accountant_duty_settle('year_end', v_items));
end $function$


CREATE OR REPLACE FUNCTION public.fn_action_authority_rank(p_level text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  select case p_level
    when 'execute_high'   then 3
    when 'execute_medium' then 2
    when 'stop_authority' then 2
    when 'execute_low'    then 1
    when 'advisory'       then 0
    else 0 end;
$function$


CREATE OR REPLACE FUNCTION public.fn_action_execution_set_author()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.author is null then
    new.author := coalesce(new.request->>'actor', new.request->>'requested_by', new.request->>'author');
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_action_holder(p_kind text, p_agent text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(
    (select p.authority_role from public.agent_action_kind_policy p
      where p.kind = p_kind and p.authority_role is not null),
    (select d.value->>p_kind from public.decision_policy d
      where d.key = 'action_autonomy'
        and exists (select 1 from public.org_role r
                     where r.role_id = d.value->>p_kind and r.status = 'active')),
    (select od.lead_agent from public.org_agents oa
       join public.org_departments od on od.dept_key = oa.department and od.active
      where oa.agent_key = p_agent limit 1),
    'ceo');
$function$


CREATE OR REPLACE FUNCTION public.fn_action_invoke_collect()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_held int := 0; v_ok int := 0; v_retry int := 0; v_dead int := 0; v_wait int := 0;
        v_status int; v_body text; v_err text; v_good boolean;
begin
  for r in
    select a.id, a.action_class, a.attempts, a.executor,
           (a.response->>'net_request_id')::bigint req,
           coalesce((a.response->>'max_attempts')::int, 1) max_attempts,
           a.started_at
      from public.action_execution a
     where a.status = 'running' and (a.response->>'net_request_id') is not null
  loop
    select status_code, content, error_msg into v_status, v_body, v_err
      from net._http_response where id = r.req;

    if not found then
      if r.started_at < now() - interval '10 minutes' then
        v_status := null; v_err := 'no pg_net response after 10 minutes';
      else
        v_wait := v_wait + 1; continue;
      end if;
    end if;

    -- A 200 IS NOT ENOUGH. quote_compare returned {ok:false,'parse_failed'} at HTTP 200 for weeks.
    v_good := v_status = 200
              and coalesce(v_body,'') <> ''
              and coalesce((nullif(v_body,'')::jsonb ->> 'ok'), 'true') <> 'false';

    -- HELD IS NOT FAILED (3 Sep 2026). An executor that answers 200 {held:true} could not do the
    -- work because the paid model is held open-circuit — the founder's own hold, not a fault. Until
    -- today that answer (or a 502 analytics_llm_unavailable) was retried to max_attempts and then
    -- dead-lettered, twelve times a day, and the resilience watcher paged the founder about his own
    -- hold. The row is PARKED as status='held': no retry, no dead letter, its org_task untouched, and
    -- fn_action_release_held() re-queues every parked row the day a model answers again.
    if v_status = 200 and coalesce(v_body,'') <> '' and pg_input_is_valid(v_body, 'jsonb')
       and coalesce((v_body::jsonb ->> 'held'), 'false') = 'true' then
      update public.action_execution
         set status = 'held', finished_at = null,
             response = coalesce(response,'{}'::jsonb) - 'net_request_id' || jsonb_build_object(
               'invoker','held','at',now(),'http_status',v_status,
               'reason', coalesce(v_body::jsonb ->> 'reason', 'inference_held'))
       where id = r.id;
      v_held := v_held + 1;
      continue;
    end if;

    if v_good then
      update public.action_execution
         set status = 'succeeded', finished_at = now(),
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','succeeded','at',now(),'http_status',v_status,
               'body', left(coalesce(v_body,''), 4000))
       where id = r.id;
      v_ok := v_ok + 1;

      begin
        update public.org_tasks k
           set status = 'done', updated_at = now(), last_run_at = now(),
               -- 5 SEP 2026: a10_org_task_done_needs_a_determination refuses a close with no
               -- deliverable or no decided_by (the org_task lane packet closed the second closing
               -- path). This close carried a summary and no decider, so its next success would
               -- have been refused inside the exception block below and swallowed. The executor's
               -- own response IS the deliverable, and the invoker that ran it is the decider.
               decided_by = coalesce(k.decided_by, 'invoker:' || r.executor),
               result = coalesce(k.result,'{}'::jsonb) || jsonb_build_object(
                 'mode','executed_by_invoker', 'executor', r.executor,
                 'deliverable', left(coalesce(v_body, ''), 4000),
                 'http_status', v_status, 'at', now(),
                 'summary', left(coalesce(v_body,''), 500),
                 -- SIX KEYS, NOT THREE (12 Aug 2026). See the header: action_worker is the largest
                 -- producer in the estate and emits `outcome`, which none of the original three
                 -- matched, so 254 of 556 invocations in 7 days closed their task with a NULL
                 -- deliverable while carrying real work in the body. Appended, never reordered, so
                 -- anything extracting correctly today is untouched.
                 'deliverable', case
                    when pg_input_is_valid(coalesce(v_body,''), 'jsonb') then coalesce(
                      nullif(btrim(coalesce((v_body::jsonb)->>'recommendation','')),''),
                      nullif(btrim(coalesce((v_body::jsonb)->>'deliverable','')),''),
                      nullif(btrim(coalesce((v_body::jsonb)->>'note','')),''),
                      nullif(btrim(coalesce((v_body::jsonb)->>'outcome','')),''),
                      nullif(btrim(coalesce((v_body::jsonb)->>'summary','')),''),
                      nullif(btrim(coalesce((v_body::jsonb)->>'result','')),''))
                    else nullif(btrim(coalesce(v_body,'')),'') end)
         where k.id = (select (a.request->>'org_task_id')::bigint from public.action_execution a where a.id = r.id)
           and k.status in ('assigned','in_progress');
      exception when others then
        update public.action_execution
           set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                 'org_task_close', 'refused', 'reason', left(SQLERRM, 400))
         where id = r.id;
      end;
    elsif coalesce(r.attempts,1) < r.max_attempts then
      update public.action_execution
         set status = 'queued',
             response = coalesce(response,'{}'::jsonb) - 'net_request_id' || jsonb_build_object(
               'invoker','retrying','at',now(),'http_status',v_status,
               'error', left(coalesce(v_err, v_body, 'unknown'), 500))
       where id = r.id;
      v_retry := v_retry + 1;
    else
      update public.action_execution
         set status = 'failed', finished_at = now(),
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','failed','at',now(),'http_status',v_status,
               'error', left(coalesce(v_err, v_body, 'unknown'), 500))
       where id = r.id;
      insert into public.dead_letter(source, source_id, kind, reason, payload, first_failed_at, attempts)
      values ('fn_action_invoke_collect', r.id::text, r.action_class,
              left(coalesce(v_err, v_body, 'http ' || coalesce(v_status::text,'?')), 500),
              jsonb_build_object('executor', r.executor, 'http_status', v_status,
                                 'body', left(coalesce(v_body,''), 2000)),
              now(), coalesce(r.attempts,1));
      v_dead := v_dead + 1;
    end if;
  end loop;

  return jsonb_build_object('succeeded', v_ok, 'retrying', v_retry, 'dead_lettered', v_dead, 'held', v_held,
                            'still_in_flight', v_wait, 'ran_at', now());
end
$function$


CREATE OR REPLACE FUNCTION public.fn_action_invoke_dispatch(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_req bigint; v_sent int := 0; v_refused int := 0; v_skipped int := 0;
        v_url text; v_secret text; v_ref text; v_key text;
        v_awaiting int := 0; v_appr record; v_resolved jsonb; v_entitled text;
        v_amount numeric; v_spend jsonb;   -- D8: amount-aware spend routing
begin
  select value into v_secret from app_secrets where key = 'cred_action_invoker';
  if v_secret is null then
    return jsonb_build_object('error', 'no cred_action_invoker credential', 'ran_at', now());
  end if;
  select value into v_ref from app_secrets where key = 'project_ref';
  if v_ref is null then
    select substring(command from 'https://([a-z]+)[.]supabase[.]co') into v_ref
      from cron.job where command like '%supabase.co/functions/v1/%' limit 1;
  end if;
  if v_ref is null then return jsonb_build_object('error','cannot determine project ref','ran_at',now()); end if;

  for r in
    select a.id, a.action_class, a.request, a.idempotency_key, a.attempts,
           e.target, e.kind, e.active, e.risk_tier, e.advisory_safe, e.reversible,
           e.required_authority, e.compensation_action_class, e.idempotency_strategy, e.params,
           e.notifies_human, e.unattended_ok, e.department, e.second_authority,
           coalesce(e.timeout_seconds, 60) timeout_seconds, coalesce(e.max_attempts, 1) max_attempts
      from public.action_execution a
      join public.org_action_executor e on e.action_class = a.action_class
     where a.status = 'queued' and e.kind = 'edge'
     order by a.created_at
     limit greatest(coalesce(p_limit, 5), 1)
  loop
    -- ---- D9.1: a queuing employee blocked by an open remediation cannot act autonomously ----------
    if coalesce(r.request->>'actor','') <> ''
       and coalesce((public.fn_agent_autonomy_blocked(r.request->>'actor')->>'blocked')::boolean, false) then
      update public.action_execution
         set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','refused','at',now(),
               'reason','the queuing employee ('||(r.request->>'actor')||') is blocked from autonomous action by an open remediation')
       where id = r.id;
      v_refused := v_refused + 1;
      continue;
    end if;

    -- ---- absolute refusals: inactive, founder-reserved (refunds), irreversible-with-no-undo -----
    if not r.active
       or coalesce(r.required_authority,'') = 'founder'
       or (not r.reversible and r.compensation_action_class is null) then
      update public.action_execution
         set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker', 'refused', 'at', now(),
               'reason', case
                 when not r.active then 'executor row is inactive'
                 when coalesce(r.required_authority,'') = 'founder' then 'reserved to the founder'
                 else 'not reversible and declares no compensation_action_class' end)
       where id = r.id;
      v_refused := v_refused + 1;
      continue;
    end if;

    -- ---- D8.2: a request carrying an amount must clear fn_check_spend before anything else ---------
    v_amount := coalesce(nullif(r.request->>'amount_aed',''), nullif(r.request->>'amount',''))::numeric;
    if v_amount is not null then
      v_spend := public.fn_check_spend(coalesce(r.department,'finance'), v_amount, r.request->>'actor');
      if not coalesce((v_spend->>'ok')::boolean, false) then
        update public.action_execution
           set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                 'invoker','refused','at',now(),'reason',v_spend->>'reason','spend',v_spend)
         where id = r.id;
        v_refused := v_refused + 1;
        continue;
      elsif (v_spend->>'route_to') = 'founder' then
        update public.action_execution
           set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                 'invoker','awaiting_founder_approval','at',now(),
                 'reason','spend over AED 10,000 is the founder''s to authorise, not an AI head''s','spend',v_spend)
         where id = r.id;
        begin
          perform public.fn_notify_founder('Spend approval needed: '||r.action_class||' AED '||v_amount,
            coalesce(v_spend->>'reason',''), 'high', p_kind => 'spend_approval_needed');
        exception when others then null; end;
        v_awaiting := v_awaiting + 1;
        continue;
      else
        update public.action_execution set response = coalesce(response,'{}'::jsonb) || jsonb_build_object('spend', v_spend)
         where id = r.id;
      end if;
    end if;

    -- ---- the AI-managerial middle tier. D8.3: a named second_authority always forces this branch ---
    if r.second_authority is not null
       or not (r.risk_tier = 'low' and r.advisory_safe and r.reversible
               and not (coalesce(r.notifies_human,false) and not coalesce(r.unattended_ok,false))) then
      select * into v_appr from public.action_approval where action_execution_id = r.id;

      if found and v_appr.approval_decision = 'approved' and v_appr.consumed_at is null
         and (r.second_authority is null or v_appr.second_approval_decision = 'approved') then
        update public.action_approval set consumed_at = now() where action_execution_id = r.id;
      elsif found and (v_appr.approval_decision = 'rejected'
                       or v_appr.second_approval_decision = 'rejected') then
        update public.action_execution
           set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                 'invoker','refused','at',now(),
                 'approver', coalesce(v_appr.approver_role, v_appr.second_approver_role),
                 'reason','an accountable AI approver rejected this action: '
                          ||coalesce(nullif(v_appr.reason,''),'no reason recorded'))
         where id = r.id;
        v_refused := v_refused + 1;
        continue;
      else
        v_resolved := public.fn_action_resolve_approver(r.department, r.risk_tier);
        v_entitled := v_resolved->>'approver';
        insert into public.action_approval
          (action_execution_id, action_class, department, accountable_approver,
           approval_decision, risk_tier, authority_basis, second_authority, second_approval_decision)
        values (r.id, r.action_class, r.department, coalesce(v_entitled,'(unresolved)'),
                'requested', r.risk_tier, v_resolved->>'basis', r.second_authority,
                case when r.second_authority is not null then 'requested' end)
        on conflict (action_execution_id) do nothing;
        update public.action_execution
           set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                 'invoker', case when r.second_authority is not null then 'awaiting_two_approvals'
                                 else 'awaiting_head_approval' end,
                 'at',now(), 'entitled_approver', v_entitled,
                 'second_authority', r.second_authority, 'risk_tier', r.risk_tier,
                 'basis', v_resolved->>'basis')
         where id = r.id;
        v_awaiting := v_awaiting + 1;
        continue;
      end if;
    end if;

    -- ---- idempotency ------------------------------------------------------------------------------
    v_key := coalesce(nullif(btrim(r.idempotency_key),''),
                      r.action_class || ':' || md5(coalesce(r.request::text,'')));
    if r.idempotency_strategy is distinct from 'none_read_only'
       and exists (select 1 from public.action_execution x
                    where x.id <> r.id and x.status = 'succeeded'
                      and x.idempotency_key = v_key
                      and x.finished_at > now() - interval '24 hours') then
      update public.action_execution
         set status = 'succeeded', finished_at = now(),
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','deduplicated','at',now(),'idempotency_key',v_key,
               'strategy', r.idempotency_strategy)
       where id = r.id;
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v_url := 'https://' || v_ref || '.supabase.co/functions/v1/' || r.target;
    select net.http_post(
             url := v_url,
             headers := '{"Content-Type":"application/json"}'::jsonb,
             body := coalesce(r.params, '{}'::jsonb) || coalesce(r.request, '{}'::jsonb)
                     || jsonb_build_object('__secret', v_secret),
             timeout_milliseconds := r.timeout_seconds * 1000)
      into v_req;

    update public.action_execution
       set status = 'running', attempts = coalesce(attempts,0) + 1,
           executor = r.target, idempotency_key = v_key,
           started_at = coalesce(started_at, now()),
           response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
             'invoker','dispatched','at',now(),'net_request_id',v_req,'url',v_url,
             'timeout_seconds', r.timeout_seconds, 'attempt', coalesce(r.attempts,0)+1,
             'max_attempts', r.max_attempts)
     where id = r.id;
    v_sent := v_sent + 1;
  end loop;

  return jsonb_build_object('dispatched', v_sent, 'refused', v_refused,
                            'deduplicated', v_skipped, 'awaiting_approval', v_awaiting, 'ran_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_action_invoke_rpc(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_ran int := 0; v_refused int := 0; v_skipped int := 0; v_failed int := 0; v_deferred int := 0;
        v_key text; v_res jsonb; v_missing boolean; v_required int; v_takes_jsonb boolean; v_arg jsonb;
begin
  for r in
    select a.id, a.action_class, a.request, a.idempotency_key, a.attempts,
           e.target, e.active, e.risk_tier, e.advisory_safe, e.reversible,
           e.required_authority, e.compensation_action_class, e.idempotency_strategy,
           e.notifies_human, e.unattended_ok, e.params
      from public.action_execution a
      join public.org_action_executor e on e.action_class = a.action_class
     where a.status = 'queued' and e.kind = 'rpc'
       -- a deferred execution is not due yet; see (2) in the header
       and coalesce(nullif(a.request->>'not_before','')::timestamptz, now()) <= now()
     order by a.created_at
     limit greatest(coalesce(p_limit, 5), 1)
  loop
    -- THE SAME REFUSALS AS THE EDGE PATH, in the same order and for the same reasons. A SQL
    -- function is not safer than an HTTP call because it is closer to the data; if anything it is
    -- nearer the money. notifies_human is still checked before the risk tier: a message that
    -- should not have been sent cannot be un-sent by a low risk score.
    if not r.active
       or coalesce(r.required_authority,'') = 'founder'
       or (not r.reversible and r.compensation_action_class is null)
       or (coalesce(r.notifies_human,false) and not coalesce(r.unattended_ok,false))
       or not (r.risk_tier = 'low' and r.advisory_safe and r.reversible) then
      update public.action_execution
         set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','refused','at',now(),'kind','rpc',
               'reason', case
                 when not r.active then 'executor row is inactive'
                 when coalesce(r.required_authority,'') = 'founder' then 'reserved to the founder'
                 when (not r.reversible and r.compensation_action_class is null)
                   then 'not reversible and declares no compensation_action_class'
                 when (coalesce(r.notifies_human,false) and not coalesce(r.unattended_ok,false))
                   then 'notifies_human is true and unattended_ok has not been set for this class'
                 else format('risk gate: tier=%s advisory_safe=%s reversible=%s - the invoker runs low/advisory_safe/reversible only',
                             r.risk_tier, r.advisory_safe, r.reversible) end)
       where id = r.id;
      v_refused := v_refused + 1;
      continue;
    end if;

    -- CAN THIS TARGET ACTUALLY BE CALLED? Asked of pg_proc, not assumed from the table. A missing
    -- function, a function that takes the request as one jsonb, and a function needing arguments we
    -- do not have are three different cases and are reported as three different things.
    select (p.oid is null),
           coalesce(p.pronargs - p.pronargdefaults, -1),
           coalesce(p.pronargs = 1 and p.proargtypes[0] = 'jsonb'::regtype::oid, false)
      into v_missing, v_required, v_takes_jsonb
      from (select 1) _
      left join pg_proc p on p.proname = r.target and p.pronamespace = 'public'::regnamespace;

    if v_missing then
      update public.action_execution
         set status = 'failed', finished_at = now(), attempts = coalesce(attempts,0) + 1,
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','failed','at',now(),'kind','rpc',
               'error', format('executor target public.%s() does not exist', r.target))
       where id = r.id;
      v_failed := v_failed + 1;
      continue;
    end if;

    if v_required > 0 and not v_takes_jsonb then
      update public.action_execution
         set status = 'failed', finished_at = now(), attempts = coalesce(attempts,0) + 1,
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','failed','at',now(),'kind','rpc',
               'error', format('public.%s() requires %s argument(s) with no default, and a workflow step carries none to give it. Take the request as ONE jsonb parameter (the invoker passes params || request || {action_execution_id}), or give the function defaults - do not let the invoker invent them.',
                               r.target, v_required))
       where id = r.id;
      v_failed := v_failed + 1;
      continue;
    end if;

    v_key := coalesce(nullif(btrim(r.idempotency_key),''),
                      r.action_class || ':' || md5(coalesce(r.request::text,'')));
    if r.idempotency_strategy is distinct from 'none_read_only'
       and exists (select 1 from public.action_execution x
                    where x.id <> r.id and x.status = 'succeeded'
                      and x.idempotency_key = v_key
                      and x.finished_at > now() - interval '24 hours') then
      update public.action_execution
         set status = 'succeeded', finished_at = now(),
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','deduplicated','at',now(),'kind','rpc','idempotency_key',v_key)
       where id = r.id;
      v_skipped := v_skipped + 1;
      continue;
    end if;

    -- One form for every return shape. A set-returning function yields its rows; a scalar
    -- function in FROM yields exactly one. Wrapped per row so one failing target cannot roll back
    -- the others in this sweep. A jsonb-taking target gets the same body the edge invoker posts.
    begin
      if v_takes_jsonb then
        v_arg := coalesce(r.params, '{}'::jsonb) || coalesce(r.request, '{}'::jsonb)
                 || jsonb_build_object('action_execution_id', r.id);
        execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from public.%I($1) t', r.target)
          into v_res using v_arg;
      else
        execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from public.%I() t', r.target)
          into v_res;
      end if;

      -- (2) THE TARGET ASKED TO BE CALLED BACK LATER. Left queued and dated; not an attempt.
      if jsonb_typeof(v_res->0) = 'object' and (v_res->0) ? 'defer_until'
         and nullif(v_res->0->>'defer_until','') is not null then
        update public.action_execution
           set executor = r.target, idempotency_key = v_key,
               request = coalesce(request,'{}'::jsonb)
                         || jsonb_build_object('not_before', (v_res->0->>'defer_until')::timestamptz),
               response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                 'invoker','deferred','at',now(),'kind','rpc',
                 'not_before', (v_res->0->>'defer_until')::timestamptz,
                 'defer_reason', left(coalesce(v_res->0->>'reason',''), 500),
                 'deferrals', coalesce((response->>'deferrals')::int, 0) + 1)
         where id = r.id;
        v_deferred := v_deferred + 1;
        continue;
      end if;

      update public.action_execution
         set status = 'succeeded', finished_at = now(), attempts = coalesce(attempts,0) + 1,
             executor = r.target, idempotency_key = v_key,
             started_at = coalesce(started_at, now()),
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','succeeded','at',now(),'kind','rpc','result', v_res)
       where id = r.id;
      v_ran := v_ran + 1;
    exception when others then
      update public.action_execution
         set status = 'failed', finished_at = now(), attempts = coalesce(attempts,0) + 1,
             executor = r.target,
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','failed','at',now(),'kind','rpc',
               'error', replace(coalesce(sqlerrm,'unknown'), '''', ''))
       where id = r.id;
      v_failed := v_failed + 1;
    end;
  end loop;

  return jsonb_build_object('ran', v_ran, 'refused', v_refused, 'deduplicated', v_skipped,
                            'failed', v_failed, 'deferred', v_deferred, 'ran_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_action_policies(p_kind text, p_confidence numeric)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select array_remove(array[
    -- action_autonomy: the standing per-kind rule that decides whether the sweep may clear this
    -- action or the founder must see it. The action's own kind selects the answer.
    (select 'action_autonomy: '||coalesce(p_kind,'(no kind)')||' → '||(d.value->>p_kind)
       from public.decision_policy d
      where d.key = 'action_autonomy' and p_kind is not null and d.value ? p_kind),
    -- confidence_min, against this action's own confidence, so two actions of the same kind read
    -- differently. An action with no confidence says that rather than being left blank.
    (select case when p_confidence is null
              then 'confidence_min '||(d.value#>>'{}')||' — this action records no confidence, so the floor cannot be applied'
              else 'confidence_min '||(d.value#>>'{}')||' — this action '||round(p_confidence, 2)::text
                   ||case when p_confidence < (d.value#>>'{}')::numeric then ', below the floor' else ', at or above the floor' end end
       from public.decision_policy d where d.key = 'confidence_min'),
    -- the chairman doctrine list: an action inside it is not a judgement call.
    (select 'founder_review_gates: '||p_kind||' is on the founder-review list'
       from public.decision_policy d
      where d.key = 'founder_review_gates' and p_kind is not null and d.value ? p_kind)
  ], null);
$function$


CREATE OR REPLACE FUNCTION public.fn_action_release_held()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_n int;
begin
  update public.action_execution
     set status = 'queued',
         response = coalesce(response,'{}'::jsonb) || jsonb_build_object('invoker','released_from_held','at',now())
   where status = 'held';
  get diagnostics v_n = row_count;
  return jsonb_build_object('released', v_n, 'at', now());
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_action_resolve_approver(p_department text, p_risk_tier text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_head text; v_head_auth text; v_need int; v_ceo text;
begin
  select lead_agent into v_head from public.org_departments where dept_key = p_department;
  if v_head is null then
    return jsonb_build_object('approver', null, 'basis',
      'no lead_agent recorded for department ' || coalesce(p_department,'(null)'));
  end if;
  v_head := coalesce(public.fn_org_agent_resolve(v_head), v_head);
  select authority_level into v_head_auth
    from public.org_role where runtime_agent_key = v_head and status='active' limit 1;

  v_need := case coalesce(p_risk_tier,'medium') when 'high' then 3 else 2 end;  -- medium/other -> 2

  if public.fn_action_authority_rank(coalesce(v_head_auth,'advisory')) >= v_need then
    return jsonb_build_object('approver', v_head, 'basis',
      format('department head of %s (authority %s) is entitled to approve a %s-risk action',
             p_department, coalesce(v_head_auth,'unset'), coalesce(p_risk_tier,'medium')));
  end if;

  -- head cannot clear this tier: the CEO (execute_high officer) is the accountable approver.
  select runtime_agent_key into v_ceo from public.org_role
    where role_id='ceo' and status='active' limit 1;
  v_ceo := coalesce(v_ceo, 'ceo');
  return jsonb_build_object('approver', v_ceo, 'basis',
    format('%s head lacks authority for a %s-risk action; escalated to the execute_high officer (CEO)',
           p_department, coalesce(p_risk_tier,'high')));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ad_decision_mark_executed(p_id bigint, p_mode text, p_response jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  d      public.ad_decision%rowtype;
  s      public.ad_campaign_state%rowtype;
  p      public.ad_spend_policy%rowtype;
  v_from numeric;
  v_to   numeric;
begin
  select * into d from public.ad_decision where id = p_id for update;
  if not found then raise exception 'ad_decision % does not exist', p_id; end if;
  if d.executed_at is not null then return; end if;

  -- the channel's allocation BEFORE the move
  select * into s from public.ad_campaign_state where campaign_id = d.campaign_id;

  update public.ad_decision set executed_at = now(), execution_mode = p_mode, api_response = p_response where id = p_id;
  update public.ad_campaign_state set
    status = case d.action when 'activate' then 'ACTIVE' when 'pause' then 'PAUSED' else status end,
    daily_budget_aed = case d.action when 'set_daily_budget' then d.amount_aed else daily_budget_aed end,
    started_at = case when d.action = 'activate' then coalesce(started_at, now()) else started_at end,
    updated_at = now()
  where campaign_id = d.campaign_id;

  -- the reallocation ledger: marketing budget between channels, citing the policy that moved it
  if s.campaign_id is null then return; end if;
  v_from := case d.action
              when 'set_daily_budget' then coalesce((d.evidence->>'from')::numeric, s.daily_budget_aed)
              when 'pause'            then case when s.status = 'ACTIVE' then s.daily_budget_aed else 0 end
              when 'activate'         then 0
              else null end;
  v_to   := case d.action
              when 'set_daily_budget' then d.amount_aed
              when 'pause'            then 0
              when 'activate'         then s.daily_budget_aed
              else null end;
  if v_from is null or v_to is null or v_from = v_to then return; end if;

  select * into p from public.ad_spend_policy where policy_key = 'default';
  insert into public.allocation_change (resource, subject, from_value, to_value, reason, policy)
  values ('marketing_budget_channels', d.campaign_id, v_from, v_to,
          format('%s: %s [ad_decision %s executed %s on %s]',
                 d.rule_key, d.reason, d.id, p_mode, coalesce(s.campaign_name, d.campaign_id)),
          format('ad_spend_policy %s, rule %s: target CPL %s AED, kill at %sx, scale step %s%%, '
                 || 'per-campaign %s..%s AED/day, daily cap %s AED, effective ceiling %s AED/day',
                 coalesce(p.policy_key, 'default'), d.rule_key,
                 coalesce(p.target_cpl_aed::text, 'derived from measured campaign data (no founder target, 6 Sep 2026)'), p.kill_multiplier,
                 p.scale_step_pct, p.min_daily_per_campaign_aed, p.max_daily_per_campaign_aed,
                 case when s.is_demo then p.daily_cap_aed else coalesce((public.fn_ads_autospend_state()->>'cap_aed')::numeric, 0) end,
                 public.fn_ad_spend_daily_ceiling(s.is_demo)));
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_ad_spend_ceiling_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  s        public.ad_campaign_state%rowtype;
  p        public.ad_spend_policy%rowtype;
  st       jsonb;
  v_ceiling numeric;
  v_total  numeric;
  v_new_budget numeric;
  v_new_active boolean;
begin
  select * into s from public.ad_campaign_state where campaign_id = new.campaign_id;
  if not found then
    raise exception 'AD_SPEND_GUARD: decision for unknown campaign %', new.campaign_id using errcode = '23503';
  end if;
  select * into p from public.ad_spend_policy where policy_key = 'default';

  v_new_budget := case when new.action = 'set_daily_budget' then new.amount_aed else s.daily_budget_aed end;
  v_new_active := case new.action when 'activate' then true when 'pause' then false else (s.status = 'ACTIVE') end;

  if new.action = 'set_daily_budget' and new.amount_aed > p.max_daily_per_campaign_aed then
    raise exception 'AD_SPEND_GUARD: % AED/day on campaign % exceeds the per-campaign maximum of % AED',
      new.amount_aed, new.campaign_id, p.max_daily_per_campaign_aed using errcode = 'P0001';
  end if;
  if new.action = 'activate' and s.daily_budget_aed <= 0 then
    raise exception 'AD_SPEND_GUARD: campaign % cannot be activated with no daily budget', new.campaign_id using errcode = 'P0001';
  end if;

  -- A decision that takes money OFF Meta is always allowed: a pause, or a budget at or below the
  -- current one. The guard exists to stop INCREASES beyond the ceiling; refusing a reduction would
  -- make the pacing arm unable to bring an over-ceiling set back down one campaign at a time (the
  -- first rehearsal hit exactly that).
  if new.action = 'pause' or (new.action = 'set_daily_budget' and new.amount_aed <= s.daily_budget_aed) then
    return new;
  end if;

  -- THE FOUNDER'S GO (4 Sep 2026): real money may only be switched on or raised when his go switch
  -- is 'true', his token exists and his daily cap is a number. Demo campaigns are the sandbox.
  if not s.is_demo then
    st := public.fn_ads_autospend_state();
    if not (st->>'live_allowed')::boolean then
      raise exception 'AD_SPEND_GOLIVE: % on real campaign % refused: % (rule %)',
        new.action, new.campaign_id, st->>'reason', new.rule_key using errcode = 'P0001';
    end if;
  end if;

  v_ceiling := public.fn_ad_spend_daily_ceiling(s.is_demo);
  select coalesce(sum(case when c.campaign_id = new.campaign_id then v_new_budget else c.daily_budget_aed end), 0)
    into v_total
  from public.ad_campaign_state c
  where c.is_demo = s.is_demo
    and (c.status = 'ACTIVE' or c.campaign_id = new.campaign_id)
    and (c.campaign_id <> new.campaign_id or v_new_active);

  if v_total > v_ceiling then
    raise exception 'AD_SPEND_CEILING: % would put % AED/day on Meta against an effective ceiling of % AED/day (campaign %, rule %)',
      new.action, v_total, v_ceiling, new.campaign_id, new.rule_key using errcode = 'P0001';
  end if;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_ad_spend_daily_ceiling()
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select public.fn_ad_spend_daily_ceiling(false);
$function$


CREATE OR REPLACE FUNCTION public.fn_ad_spend_daily_ceiling(p_demo boolean)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- NOTE the explicit null branch: greatest()/least() IGNORE nulls in Postgres, so
  -- greatest(0, null - x) is 0, not null, and the first cut of this function paced every
  -- campaign to zero whenever no monthly cap was set.
  with st as (select public.fn_ads_autospend_state() j),
  cap as (
    select case
      when p_demo then p.daily_cap_aed
      when (st.j->>'live_allowed')::boolean then (st.j->>'cap_aed')::numeric
      else 0 end as daily_cap, p.*
    from public.ad_spend_policy p, st
    where p.policy_key = 'default')
  select case
    when cap.monthly_cap_aed is null then cap.daily_cap
    else least(
      cap.daily_cap,
      greatest(0, cap.monthly_cap_aed - case when cap.month_label = to_char(now(), 'YYYY-MM') then cap.month_spent_aed else 0 end)
        / greatest(1, (date_trunc('month', now()) + interval '1 month')::date - current_date))
  end
  from cap;
$function$


CREATE OR REPLACE FUNCTION public.fn_add_working_days(p_from timestamp with time zone, p_days integer)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d date; left_ int := greatest(0, coalesce(p_days,0)); tod time; res timestamptz;
begin
  if p_from is null then return null; end if;
  d   := (p_from at time zone 'Asia/Dubai')::date;
  tod := (p_from at time zone 'Asia/Dubai')::time;
  while left_ > 0 loop
    d := d + 1;
    if public.fn_is_working_day(d) then left_ := left_ - 1; end if;
  end loop;
  -- if we consumed no days and landed on a non-working day, roll forward
  while not public.fn_is_working_day(d) loop d := d + 1; end loop;
  res := ((d::text || ' ' || tod::text)::timestamp) at time zone 'Asia/Dubai';
  return res;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ads_autospend_state()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with s as (
    select
      coalesce((select lower(trim(value)) from public.app_secrets where key = 'meta_autospend_golive'), 'false') = 'true' as golive,
      coalesce((select length(trim(value)) >= 24 from public.app_secrets where key = 'meta_access_token'), false)        as token_present,
      (select case when trim(value) ~ '^[0-9]+(\.[0-9]+)?$' and trim(value)::numeric > 0 then trim(value)::numeric end
         from public.app_secrets where key = 'meta_daily_budget_cap_aed')                                               as cap_aed,
      public.fn_every_category_has_ten_suppliers()                                                                      as ten
  )
  select jsonb_build_object(
    'golive', golive,
    'token_present', token_present,
    'cap_aed', cap_aed,
    'every_category_has_ten', (ten->>'gate')::boolean,
    'live_allowed', (ten->>'gate')::boolean and golive and token_present and cap_aed is not null,
    'reason', case
      when not (ten->>'gate')::boolean then format('organic only (ledger 1004): %s of %s categories have fewer than 10 verified suppliers', ten->>'below_ten', ten->>'categories')
      when not golive then 'meta_autospend_golive is not ''true'''
      when not token_present then 'meta_access_token is absent'
      when cap_aed is null then 'meta_daily_budget_cap_aed is not a positive number'
      else 'live spend allowed under ' || cap_aed || ' AED/day' end)
  from s;
$function$


CREATE OR REPLACE FUNCTION public.fn_ads_manage(p_demo boolean DEFAULT false, p_run_tag text DEFAULT NULL::text)
 RETURNS SETOF ad_decision
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  p          public.ad_spend_policy%rowtype;
  v_ceiling  numeric;
  v_active   numeric;
  c          record;
  v_cpl      numeric;
  v_learning boolean;
  v_new      numeric;
  v_factor   numeric;
  d          public.ad_decision%rowtype;
  v_target   numeric;
  v_target_src text;
begin
  -- 0. THE FOUNDER'S GO. Real campaigns are not managed at all until his switch, token and cap are
  --    in place: nothing is activated, nothing is raised, and nothing he switched on by hand in Ads
  --    Manager is paused by a manager that has not been given the go. The guard refuses the same
  --    things independently; this early return keeps the ledger free of refused attempts.
  if not p_demo and not (public.fn_ads_autospend_state()->>'live_allowed')::boolean then
    return;
  end if;

  select * into p from public.ad_spend_policy where policy_key = 'default';
  v_ceiling := public.fn_ad_spend_daily_ceiling(p_demo);

  -- 6 Sep 2026 (founder): there is NO founder cost-per-lead target ("that target you ingested i never
  -- actually mentioned it"). With ad_spend_policy.target_cpl_aed NULL the target is DERIVED from measured
  -- campaign data: the median cost per lead of the active campaigns that have results in their freshest
  -- row (3 days). Until at least one campaign has measured leads there is no target: spend with no leads
  -- past learning is still killed, and nothing is scaled.
  if p.target_cpl_aed is not null then
    v_target := p.target_cpl_aed; v_target_src := 'ad_spend_policy';
  else
    select percentile_cont(0.5) within group (order by m.cpl) into v_target
    from public.ad_campaign_state s
    join lateral (
      select case when coalesce(i.results, 0) > 0 then i.spend / i.results else null end as cpl
      from public.meta_insights i where i.campaign_id = s.campaign_id
        and i.synced_at > now() - interval '3 days'
      order by (i.time_window = 'last_30d') desc, i.synced_at desc limit 1
    ) m on true
    where s.is_demo = p_demo and s.status = 'ACTIVE' and m.cpl is not null;
    v_target_src := 'median measured CPL of the active set (no founder target)';
  end if;

  -- 1. PACE. If the active set already exceeds the ceiling, shrink it before judging anyone.
  select coalesce(sum(daily_budget_aed), 0) into v_active
  from public.ad_campaign_state where is_demo = p_demo and status = 'ACTIVE'
    and campaign_id not in (select campaign_id from public.ad_decision where executed_at is null);
  if v_active > v_ceiling then
    -- 4 Sep 2026: this is the "Meta optimizer over cap" moment MASTER_PLAN §4.4 names as the
    -- producer of budget.exceeded (budget_cycle's trigger). The pacing below is the remedy; the
    -- event is the record Finance consumes (cfo, brief). Once per scope per day.
    if not exists (select 1 from public.company_event e
                    where e.event_type = 'budget.exceeded' and e.entity_type = 'ad_spend'
                      and e.entity_id = case when p_demo then 'demo' else 'meta' end
                      and e.occurred_at > now() - interval '24 hours') then
      perform public.fn_emit('budget.exceeded', 'ad_spend', case when p_demo then 'demo' else 'meta' end,
        'ads_autopilot',
        jsonb_build_object('requested_aed', v_active, 'available_aed', v_ceiling,
          'purpose', 'daily Meta ad spend across the active campaign set',
          'reason', format('active daily total %s AED exceeds the effective ceiling %s AED; pacing down', v_active, v_ceiling),
          'run_tag', p_run_tag, 'is_demo', p_demo));
    end if;
    v_factor := v_ceiling / v_active;
    for c in
      select s.*, m.cpl from public.ad_campaign_state s
      left join lateral (
        select case when coalesce(i.results, 0) > 0 then i.spend / i.results else null end as cpl
        from public.meta_insights i where i.campaign_id = s.campaign_id
          and i.synced_at > now() - interval '3 days'
        order by (i.time_window = 'last_30d') desc, i.synced_at desc limit 1
      ) m on true
      where s.is_demo = p_demo and s.status = 'ACTIVE'
        and s.campaign_id not in (select campaign_id from public.ad_decision where executed_at is null)
      order by coalesce(m.cpl, 1e12) asc
    loop
      v_new := greatest(p.min_daily_per_campaign_aed, floor(c.daily_budget_aed * v_factor));
      if v_new < c.daily_budget_aed then
        insert into public.ad_decision (campaign_id, action, amount_aed, rule_key, reason, evidence, run_tag)
        values (c.campaign_id, 'set_daily_budget', v_new, 'pace_down',
                format('active daily total %s AED exceeds the effective ceiling %s AED; scaled by %s', v_active, v_ceiling, round(v_factor, 3)),
                jsonb_build_object('active_total', v_active, 'ceiling', v_ceiling, 'factor', v_factor, 'from', c.daily_budget_aed),
                p_run_tag)
        returning * into d;
        return next d;
        v_active := v_active - c.daily_budget_aed + v_new;
      end if;
    end loop;
    -- if the minimums still do not fit, pause the worst cost-per-lead until they do
    for c in
      select s.*, m.cpl from public.ad_campaign_state s
      left join lateral (
        select case when coalesce(i.results, 0) > 0 then i.spend / i.results else null end as cpl
        from public.meta_insights i where i.campaign_id = s.campaign_id
          and i.synced_at > now() - interval '3 days'
        order by (i.time_window = 'last_30d') desc, i.synced_at desc limit 1
      ) m on true
      where s.is_demo = p_demo and s.status = 'ACTIVE'
      order by coalesce(m.cpl, 1e12) desc
    loop
      exit when v_active <= v_ceiling;
      insert into public.ad_decision (campaign_id, action, rule_key, reason, evidence, run_tag)
      values (c.campaign_id, 'pause', 'pace_pause',
              format('even at minimum budgets the active set (%s AED) exceeds the ceiling (%s AED); pausing the worst cost per lead', v_active, v_ceiling),
              jsonb_build_object('active_total', v_active, 'ceiling', v_ceiling, 'cpl', c.cpl), p_run_tag)
      returning * into d;
      return next d;
      v_active := v_active - least(c.daily_budget_aed, greatest(p.min_daily_per_campaign_aed, floor(c.daily_budget_aed * coalesce(v_factor, 1))));
    end loop;
    return;  -- a pacing tick judges nothing else; the next tick sees the paced set
  end if;

  -- 2. JUDGE every active campaign that has no decision waiting.
  --    D3 (4 Sep 2026): the evidence is the FRESHEST row within 3 days, last_30d preferred over the
  --    lifetime window synced beside it. No fresh row = no data = the campaign is held, exactly like
  --    a learner. meta_sync no longer writes a row when Meta errors or returns nothing, so a missing
  --    or stale row can never read as "spend fell to 0" and pause a winner.
  for c in
    select s.*, m.spend, m.results, m.has_results_field
    from public.ad_campaign_state s
    left join lateral (
      select i.spend, i.results, (i.results is not null) as has_results_field
      from public.meta_insights i where i.campaign_id = s.campaign_id
        and i.synced_at > now() - interval '3 days'
      order by (i.time_window = 'last_30d') desc, i.synced_at desc limit 1
    ) m on true
    where s.is_demo = p_demo and s.status = 'ACTIVE'
      and s.campaign_id not in (select campaign_id from public.ad_decision where executed_at is null)
    order by s.campaign_id
  loop
    v_learning := (c.started_at is null)
                  or (c.started_at > now() - make_interval(days => p.learning_phase_days))
                  or (coalesce(c.spend, 0) < p.learning_min_spend_aed);

    -- tracking gate: spent past the threshold and results are not even reported
    if coalesce(c.spend, 0) >= p.learning_min_spend_aed and not coalesce(c.has_results_field, false) then
      insert into public.ad_decision (campaign_id, action, rule_key, reason, evidence, run_tag)
      values (c.campaign_id, 'pause', 'tracking_gate',
              format('%s AED spent and no results field is reported: conversions are not tracked, so nothing can be judged', c.spend),
              jsonb_build_object('spend', c.spend), p_run_tag)
      returning * into d;
      return next d;
      continue;
    end if;

    if v_learning then
      continue;  -- not judged on its first days, nor without fresh data
    end if;

    v_cpl := case when coalesce(c.results, 0) > 0 then c.spend / c.results else null end;

    -- kill: past learning and the cost per lead is above the multiplier, or spend with no leads
    if v_cpl is null or (v_target is not null and v_cpl > p.kill_multiplier * v_target) then
      insert into public.ad_decision (campaign_id, action, rule_key, reason, evidence, run_tag)
      values (c.campaign_id, 'pause', 'kill_3x',
              case when v_cpl is null
                   then format('%s AED spent past the learning phase with no leads at all', c.spend)
                   else format('cost per lead %s AED is above %s x the %s AED target (%s)', round(v_cpl, 2), p.kill_multiplier, round(v_target, 2), v_target_src) end,
              jsonb_build_object('spend', c.spend, 'results', c.results, 'cpl', v_cpl, 'target_cpl', v_target, 'target_source', v_target_src, 'kill_multiplier', p.kill_multiplier), p_run_tag)
      returning * into d;
      return next d;
      continue;
    end if;

    -- scale: at or under target, room on the campaign and under the ceiling
    if v_target is not null and v_cpl <= v_target and c.daily_budget_aed < p.max_daily_per_campaign_aed then
      v_new := least(p.max_daily_per_campaign_aed,
                     floor(c.daily_budget_aed * (1 + p.scale_step_pct / 100.0)),
                     c.daily_budget_aed + greatest(0, v_ceiling - v_active));
      if v_new > c.daily_budget_aed then
        insert into public.ad_decision (campaign_id, action, amount_aed, rule_key, reason, evidence, run_tag)
        values (c.campaign_id, 'set_daily_budget', v_new, 'scale_winner',
                format('cost per lead %s AED is at or under the %s AED target (%s); raising %s to %s AED/day', round(v_cpl, 2), round(v_target, 2), v_target_src, c.daily_budget_aed, v_new),
                jsonb_build_object('spend', c.spend, 'results', c.results, 'cpl', v_cpl, 'target_cpl', v_target, 'target_source', v_target_src, 'from', c.daily_budget_aed, 'ceiling', v_ceiling, 'active_total', v_active), p_run_tag)
        returning * into d;
        return next d;
        v_active := v_active - c.daily_budget_aed + v_new;
      end if;
    end if;
  end loop;

  -- 3. ACTIVATE never-run paused campaigns that fit under the ceiling.
  if p.auto_activate then
    for c in
      select s.* from public.ad_campaign_state s
      where s.is_demo = p_demo and s.status = 'PAUSED' and s.started_at is null and s.daily_budget_aed > 0
        and s.campaign_id not in (select campaign_id from public.ad_decision where executed_at is null)
      order by s.daily_budget_aed asc
    loop
      exit when v_active + c.daily_budget_aed > v_ceiling;
      insert into public.ad_decision (campaign_id, action, rule_key, reason, evidence, run_tag)
      values (c.campaign_id, 'activate', 'activate',
              format('never run, carries %s AED/day and fits under the %s AED/day ceiling (active total %s)', c.daily_budget_aed, v_ceiling, v_active),
              jsonb_build_object('daily_budget', c.daily_budget_aed, 'ceiling', v_ceiling, 'active_total', v_active), p_run_tag)
      returning * into d;
      return next d;
      v_active := v_active + c.daily_budget_aed;
    end loop;
  end if;
  return;
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_agent_action_hand_to_owner(p_action_id bigint, p_owner text, p_basis text)
 RETURNS bigint
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a record; v_owner text; v_dept text; v_task bigint;
begin
  select * into a from public.agent_actions where id = p_action_id;
  if not found then return null; end if;

  v_owner := coalesce(public.fn_org_agent_resolve(p_owner), public.fn_org_agent_resolve(a.agent));
  select o.department into v_dept from public.org_agents o where o.agent_key = v_owner and o.active;
  if v_dept is null or not exists (select 1 from public.org_departments x where x.dept_key = v_dept and x.active) then
    v_dept := 'exec';
    select x.lead_agent into v_owner from public.org_departments x where x.dept_key = 'exec';
  end if;
  if not exists (select 1 from public.org_agents o where o.agent_key = v_owner and o.active and coalesce(o.available, true)) then
    v_owner := null;   -- a05_org_task_fill_ownership picks the least-loaded colleague
  end if;

  insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, decided_by,
                                action_class, assigned_agent, priority, result)
  values (v_dept, left(coalesce(nullif(a.title, ''), a.kind), 200),
          '[agent_action:' || a.id || '] ' || coalesce(nullif(a.recommendation, ''), a.title, a.kind)
            || E'\n\nRaised by ' || coalesce(a.agent, '?') || ' as ' || a.kind || ' at ' || a.created_at
            || '. ' || p_basis
            || ' Determine it from company knowledge or park it with a reason; only a Stripe refund reaches the founder.',
          'assigned', 'advisory', false, 'fn_agent_action_work_sweep',
          'analysis', v_owner, case when lower(coalesce(a.risk, '')) in ('high', 'critical') then 2 else 1 end,
          jsonb_build_object('source', jsonb_build_object('agent_action_id', a.id, 'kind', a.kind,
                             'basis', p_basis, 'handed_at', now())))
  returning id into v_task;
  return v_task;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_agent_action_resolve_addressee()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_key text;
begin
  if new.agent is null or new.agent = '' then
    new.agent := 'brief';
    new.escalated := true;
    new.escalation_reason := coalesce(new.escalation_reason, 'written with no addressee at all');
    return new;
  end if;

  if exists (select 1 from public.org_agents o where o.agent_key = new.agent and o.active) then
    return new;
  end if;

  v_key := public.fn_org_agent_resolve(new.agent);

  if v_key is null then
    new.detail := coalesce(new.detail, '{}'::jsonb)
                  || jsonb_build_object('addressed_as', new.agent, 'addressee_unresolved', true);
    new.escalated := true;
    new.escalation_reason := coalesce(new.escalation_reason,
      'addressee "' || new.agent || '" is not an employee and no org_agent_alias maps it');
    new.agent := 'brief';
    return new;
  end if;

  new.detail := coalesce(new.detail, '{}'::jsonb) || jsonb_build_object('addressed_as', new.agent);
  new.agent := v_key;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_agent_action_work_sweep(p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_q int := 0; v_officer int := 0; v_notify int := 0; r record; v_key text; v_escalated int := 0;
        v_fixture int := 0; v_on_fact int := 0; v_handed int := 0; v_notified int := 0; v_officer_handed int := 0;
        v_task bigint; v_tstatus text; v_tagent text; v_tsummary text; v_reason text; v_decisions jsonb;
begin
  -- 1. a fixture is never real work
  update public.agent_actions a
     set status = 'cancelled', decided_at = now(), decided_by = 'fn_agent_action_work_sweep',
         detail = coalesce(a.detail, '{}'::jsonb) || jsonb_build_object(
           'settled_reason', 'fixture', 'settled_by', 'fn_agent_action_work_sweep', 'settled_at', now())
   where a.status in ('pending', 'needs_review')
     and (a.title ilike '%ZZ DEMO%' or a.title ilike '%example.invalid%'
          or a.recommendation ilike '%ZZ DEMO%' or a.detail::text ilike '%example.invalid%' or a.detail::text ilike '%ZZ DEMO%');
  get diagnostics v_fixture = row_count;

  for r in
    select a.id, a.kind,
           (select count(*) from public.action_execution x
             where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
               and x.status = 'failed') as failures
      from public.agent_actions a
      join public.org_agents o on o.agent_key = a.agent and o.active
      join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'auto'
     where a.status = 'pending'
       -- Nothing live and nothing already settled for this item...
       and not exists (select 1 from public.action_execution x
                        where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
                          and x.status in ('queued','running','succeeded'))
       -- ...and fewer than two attempts have failed. Equality, not LIKE: `_` is a single-character
       -- wildcard in LIKE and 'agent_action:' is full of them, so `like 'agent_action:'||id` would
       -- also match keys this function never wrote.
       and (select count(*) from public.action_execution x
             where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
               and x.status = 'failed') < 2
     order by a.created_at
     limit greatest(coalesce(p_limit, 10), 1)
  loop
    v_key := 'agent_action:' || r.id || case when r.failures >= 1 then '#2' else '' end;
    insert into public.action_execution(id, correlation_id, action_class, executor, idempotency_key,
                                        risk_tier, reversible, request, status, attempts)
    values (gen_random_uuid(), gen_random_uuid(), 'agent_action_work', 'action_worker',
            v_key, 'low', true,
            jsonb_build_object('action_id', r.id, 'kind', r.kind,
                               'source', 'fn_agent_action_work_sweep',
                               'attempt', r.failures + 1),
            'queued', 0)
    on conflict (idempotency_key) do nothing;
    v_q := v_q + 1;
  end loop;

  -- 2. AUTO kinds the worker could not settle go to their owner through the org_task lane
  for r in
    select a.id, a.kind, a.agent, a.detail, a.status, a.escalation_reason,
           nullif(regexp_replace(coalesce(a.detail->>'task_id', ''), '[^0-9]', '', 'g'), '')::bigint as task_id,
           exists (select 1 from public.org_agents o where o.agent_key = a.agent and o.active) as agent_active,
           (select count(*) from public.action_execution x
             where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
               and x.status in ('succeeded', 'failed', 'cancelled')) as finished,
           (select count(*) from public.action_execution x
             where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
               and x.status = 'failed') as failures,
           (select string_agg(left(coalesce(x.response::text, x.status), 300), ' | ')
              from public.action_execution x
             where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')) as verdict
      from public.agent_actions a
      join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'auto'
     where a.status in ('pending', 'needs_review')
       and not exists (select 1 from public.action_execution x
                        where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
                          and x.status in ('queued', 'running'))
     order by a.created_at
  loop
    -- a pending row nobody has attempted is the worker's turn; a needs_review row was held by the action
    -- gate and the worker never takes it, so its review IS the hand-off
    continue when r.status = 'pending' and r.agent_active and r.finished = 0 and r.failures < 2;

    v_task := null; v_tstatus := null;
    if r.task_id is not null then
      select o.id, o.status, coalesce(o.assigned_agent, o.dept_key),
             left(coalesce(o.result->>'summary', o.result->>'deliverable', o.result->'parked'->>'note', ''), 300)
        into v_task, v_tstatus, v_tagent, v_tsummary
        from public.org_tasks o where o.id = r.task_id;
    end if;

    if v_task is not null and v_tstatus in ('done', 'cancelled') then
      v_reason := 'the org_task this reported on (' || v_task || ') is ' || v_tstatus || ' by ' || v_tagent
                  || case when coalesce(v_tsummary, '') = '' then '' else ': ' || v_tsummary end;
      update public.agent_actions
         set status = 'auto_done', decided_at = now(), decided_by = 'fn_agent_action_work_sweep',
             detail = coalesce(detail, '{}'::jsonb) || jsonb_build_object(
               'org_task_id', v_task, 'settled_reason', v_reason,
               'settled_by', 'fn_agent_action_work_sweep', 'settled_at', now())
       where id = r.id;
      v_on_fact := v_on_fact + 1;
    else
      if v_task is null then
        v_task := public.fn_agent_action_hand_to_owner(r.id, r.agent,
                    case when r.status = 'needs_review'
                         then 'The action gate held it for review (' || coalesce(left(r.escalation_reason, 300), 'no reason recorded') || ').'
                         else 'The action_worker could not settle it (' || coalesce(left(r.verdict, 400),
                                case when r.agent_active then 'no attempt recorded' else 'the addressee is no longer an active employee' end) || ').' end);
        v_reason := 'handed to the org_task lane as org_task ' || v_task
                    || case when r.status = 'needs_review' then ': the action gate held it for review and the department is the reviewer'
                            else ': the worker found no company playbook covering it' end
                    || case when r.agent_active then '' else ' and ' || coalesce(r.agent, '?') || ' is no longer an active employee' end;
        v_handed := v_handed + 1;
      else
        v_reason := 'org_task ' || v_task || ' owns this work in the lane (status ' || v_tstatus || ', ' || v_tagent || ')'
                    || case when coalesce(v_tsummary, '') = '' then '' else ': ' || v_tsummary end;
        v_on_fact := v_on_fact + 1;
      end if;
      update public.agent_actions
         set status = 'superseded', decided_at = now(), decided_by = 'fn_agent_action_work_sweep',
             detail = coalesce(detail, '{}'::jsonb) || jsonb_build_object(
               'org_task_id', v_task, 'superseded_by', 'org_task:' || v_task, 'settled_reason', v_reason,
               'settled_by', 'fn_agent_action_work_sweep', 'settled_at', now())
       where id = r.id;
    end if;
  end loop;

  -- OFFICER decisions: route to the accountable AI authority, never the founder. The determination
  -- itself is the authority's own work; this only makes the authority the owner and removes the
  -- founder as the bottleneck.
  for r in
    select a.id, p.authority_role,
           coalesce(ro.runtime_agent_key, p.authority_role) as authority_agent
      from public.agent_actions a
      join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'officer'
      left join public.org_role ro on ro.role_id = p.authority_role and ro.status = 'active'
     where a.status in ('pending','needs_review','held_for_review','proposed','open')
       and (a.detail->>'routed_at') is null
  loop
    update public.agent_actions
       set agent = coalesce(r.authority_agent, agent),
           escalated = true,
           escalation_reason =
             case when coalesce(escalation_reason,'') = '' then '' else escalation_reason || ' | ' end
             || 'routed to accountable AI authority ' || coalesce(r.authority_role,'(unset)')
             || ' — only refunds require the founder',
           detail = coalesce(detail,'{}'::jsonb) || jsonb_build_object(
                      'routed_at', now(),
                      'routed_to', coalesce(r.authority_agent, r.authority_role),
                      'route_basis', 'officer_policy')
     where id = r.id;
    v_officer := v_officer + 1;
  end loop;

  -- NOTIFY alerts: tell the founder (Stage 4), non-blocking, and hand the response to the authority.
  for r in
    select a.id, a.kind, a.title, a.recommendation, a.risk, a.agent, p.authority_role,
           coalesce(ro.runtime_agent_key, p.authority_role) as authority_agent
      from public.agent_actions a
      join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'notify'
      left join public.org_role ro on ro.role_id = p.authority_role and ro.status = 'active'
     where a.status in ('pending','needs_review','held_for_review','proposed','open')
       and (a.detail->>'routed_at') is null
  loop
    perform public.fn_notify_founder(
      coalesce(nullif(r.title,''), r.kind),
      coalesce(nullif(r.recommendation,''), nullif(r.title,''), r.kind)
        || E'\n\nRaised by ' || coalesce(r.agent,'?')
        || '. Handling owner: ' || coalesce(r.authority_role,'(unset)')
        || '. This is a notification — open the OS to review; no approval is required of you.',
      case when lower(coalesce(r.risk,'')) in ('high','critical') then 'high' else 'warn' end,
      -- 6 SEP 2026: the action's own kind is the founder_mail_policy key (backup_alert, security_incident,
      -- legal_flag, ...). finance_alert is allowed; the rest open one org_task for the kind's owner role.
      p_kind => r.kind);
    update public.agent_actions
       set agent = coalesce(r.authority_agent, agent),
           detail = coalesce(detail,'{}'::jsonb) || jsonb_build_object(
                      'routed_at', now(),
                      'routed_to', coalesce(r.authority_agent, r.authority_role),
                      'route_basis', 'notify_policy',
                      'founder_notified_at', now())
     where id = r.id;
    v_notify := v_notify + 1;
  end loop;

  -- 3 and 4. a routed notify/officer row is not settled until the authority role HOLDS it: the response
  -- (notify) or the determination (officer) is an org_task assigned to that role's employee, and the
  -- action row closes — 'notified' for a fact he was told, 'superseded' by the task for a determination.
  for r in
    select a.id, a.kind, a.agent, p.policy, p.authority_role,
           coalesce(a.detail->>'routed_to', ro.runtime_agent_key, p.authority_role) as authority_agent
      from public.agent_actions a
      join public.agent_action_kind_policy p on p.kind = a.kind and p.policy in ('notify', 'officer')
      left join public.org_role ro on ro.role_id = p.authority_role and ro.status = 'active'
     where a.status in ('pending','needs_review','held_for_review','proposed','open')
       and (a.detail->>'routed_at') is not null
     order by a.created_at
  loop
    v_task := public.fn_agent_action_hand_to_owner(r.id, r.authority_agent,
                case when r.policy = 'notify'
                     then 'Policy notify: the founder has been told; the response is ' || coalesce(r.authority_role, 'the accountable role') || '''s to own.'
                     else 'Policy officer: the determination is ' || coalesce(r.authority_role, 'the accountable role') || '''s to make, never the founder''s.' end);
    update public.agent_actions
       set status = case when r.policy = 'notify' then 'notified' else 'superseded' end,
           decided_at = now(), decided_by = 'fn_agent_action_work_sweep',
           detail = coalesce(detail, '{}'::jsonb) || jsonb_build_object(
             'org_task_id', v_task, 'superseded_by', 'org_task:' || v_task,
             'settled_reason', case when r.policy = 'notify'
               then 'notified: the founder was told and the response is owned by ' || coalesce(r.authority_role, '?') || ' as org_task ' || v_task
               else 'handed to accountable authority ' || coalesce(r.authority_role, '?') || ' as org_task ' || v_task end,
             'settled_by', 'fn_agent_action_work_sweep', 'settled_at', now())
     where id = r.id;
    if r.policy = 'notify' then v_notified := v_notified + 1; else v_officer_handed := v_officer_handed + 1; end if;
  end loop;

  -- ESCALATE the unclassified: an emitted kind with no agent_action_kind_policy row is owned by no one,
  -- so the sweep can neither settle nor route it. Tell the founder it needs a classification rather than
  -- leaving it to rot unrouted. (0 such rows today, so this notifies no one now.)
  for r in
    select a.id, a.kind, a.title, a.recommendation, a.risk, a.agent from public.agent_actions a
     where a.status in ('pending','needs_review','held_for_review','proposed','open')
       and (a.detail->>'routed_at') is null
       and not exists (select 1 from public.agent_action_kind_policy p where p.kind = a.kind)
  loop
    perform public.fn_notify_founder(
      'Unclassified work item: ' || coalesce(nullif(r.kind,''),'(no kind)'),
      coalesce(nullif(r.title,''), r.kind) || E'\n\nRaised by ' || coalesce(r.agent,'?')
        || '. This kind has no agent_action_kind_policy row, so no employee owns it and the sweep cannot '
        || 'settle or route it. Classify it (auto/officer/notify).',
      'warn', p_kind => 'agent_action_unclassified');
    update public.agent_actions
       set escalated = true,
           escalation_reason = case when coalesce(escalation_reason,'')='' then '' else escalation_reason||' | ' end
                               || 'no agent_action_kind_policy for kind '||coalesce(r.kind,'(none)'),
           detail = coalesce(detail,'{}'::jsonb) || jsonb_build_object('routed_at', now(), 'route_basis', 'escalated_unclassified')
     where id = r.id;
    v_escalated := v_escalated + 1;
  end loop;

  -- 5. proposed decisions go to their department on the same tick
  begin
    v_decisions := public.fn_decision_record_route(null);
  exception when others then
    v_decisions := jsonb_build_object('error', sqlerrm);
  end;

  return jsonb_build_object('queued', v_q, 'officer_routed', v_officer, 'notify_sent', v_notify, 'escalated', v_escalated,
    'fixtures_cancelled', v_fixture, 'settled_on_task_fact', v_on_fact, 'handed_to_owner', v_handed,
    'notified', v_notified, 'officer_handed', v_officer_handed, 'decision_records', v_decisions,
    'ran_at', now(),
    'eligible_remaining', (select count(*) from public.agent_actions a
                             join public.org_agents o on o.agent_key = a.agent and o.active
                             join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'auto'
                            where a.status = 'pending'
                              and not exists (select 1 from public.action_execution x
                                               where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
                                                 and x.status in ('queued','running','succeeded'))
                              and (select count(*) from public.action_execution x
                                    where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
                                      and x.status = 'failed') < 2),
    -- Named separately so "we have stopped trying" is never counted as "we are working on it".
    'exhausted_two_attempts', (select count(*) from public.agent_actions a
                                 join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'auto'
                                where a.status = 'pending'
                                  and (select count(*) from public.action_execution x
                                        where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
                                          and x.status = 'failed') >= 2),
    -- No kind routes to the founder any more; this is retained as a tripwire and must read 0.
    'never_auto_settled', (select count(*) from public.agent_actions a
                            join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'founder'
                           where a.status = 'pending'),
    'unrouted', (select count(*) from public.agent_actions a
                  where a.status = 'pending'
                    and not exists (select 1 from public.agent_action_kind_policy p where p.kind = a.kind)));
end $function$


CREATE OR REPLACE FUNCTION public.fn_agent_actions_fill_alternatives()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  -- WAS `d record`. A record that is never assigned raises 55000 on the first field reference;
  -- these three are null when the lookup is skipped, and null is answerable.
  v_alts     jsonb;
  v_decision text;
  v_amt      text;
  v_held     boolean;
begin
  -- Nothing to do once every field the caller could supply is already there.
  if NEW.alternatives is not null and NEW.assumptions is not null
     and NEW.expected_impact is not null and NEW.cost is not null then
    return NEW;
  end if;

  if NEW.decision_log_id is not null then
    select l.alternatives, l.decision into v_alts, v_decision
      from public.decision_log l where l.id = NEW.decision_log_id;
  end if;

  if NEW.alternatives is null
     and v_alts is not null
     and v_alts::text not in ('null', '[]', '{}') then
    NEW.alternatives := v_alts;
  end if;

  -- No linked decision, or a decision that recorded nothing: the dispositions this row can take,
  -- with the selected one read from the row's own status and the basis said on the row.
  if NEW.alternatives is null then
    v_held := coalesce(NEW.status, '') in ('needs_review', 'held_for_review', 'pending', 'proposed', 'open');
    NEW.alternatives := jsonb_build_array(
      jsonb_build_object(
        'option', 'act as recommended',
        'selected', not v_held and coalesce(NEW.status, '') not in ('rejected', 'declined', 'dismissed'),
        'basis', 'the recommendation as written: ' || left(coalesce(NEW.recommendation, NEW.title, ''), 160)),
      jsonb_build_object(
        'option', 'hold for human review',
        'selected', v_held,
        'basis', case when NEW.decision_log_id is null
                      then 'no decision_log row is linked; the disposition is read from the action''s own status (' || coalesce(NEW.status, 'unset') || ')'
                      else 'the linked decision recorded no alternatives; the disposition is read from the action''s own status (' || coalesce(NEW.status, 'unset') || ')' end),
      jsonb_build_object(
        'option', 'do nothing and re-measure at the next tick',
        'selected', false,
        'rejected_because', 'the condition this action reports (' || left(coalesce(NEW.title, ''), 120) || ') persists until acted on'));
  end if;

  if NEW.assumptions is null then
    NEW.assumptions := jsonb_build_array(
      'The action context recorded in detail is accurate as supplied by ' || coalesce(NEW.agent, 'the agent') || '.',
      'fn_should_escalate and fn_authorize were evaluated on that context'
        || case when v_decision is not null then ' and returned ' || v_decision || '.' else '.' end);
  end if;

  if NEW.expected_impact is null then
    NEW.expected_impact := case
      when coalesce(NEW.status, '') in ('needs_review', 'held_for_review')
        then 'Held: nothing changes until a human decides. Until then the condition this action reports remains as it is.'
      else 'Proceeds as recommended: ' || left(coalesce(NEW.recommendation, NEW.title, 'the recommended action'), 220) end;
  end if;

  if NEW.cost is null then
    begin
      v_amt := nullif(to_jsonb(NEW.detail) ->> 'amount_aed', '');
      if v_amt is null then v_amt := nullif(to_jsonb(NEW.detail) ->> 'amount', ''); end if;
    exception when others then v_amt := null; end;
    NEW.cost := case when v_amt is not null
      then 'AED ' || v_amt || ' — the amount carried in this action''s own context.'
      else 'No spend is recorded in this action''s context; the cost is the reviewer''s time.' end;
  end if;

  return NEW;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_agent_autonomy_blocked(p_agent_key text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with me as (select coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key) as k)
  select jsonb_build_object(
    'agent_key', (select k from me),
    'asked_as', p_agent_key,
    'blocked', exists (select 1 from agent_remediation
                        where agent_key = (select k from me) and blocks_autonomy and status <> 'passed'),
    'open_remediations', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'failure_class', failure_class, 'competency', competency, 'status', status))
      from agent_remediation where agent_key = (select k from me) and status <> 'passed'), '[]'::jsonb),
    'readiness', coalesce((select jsonb_agg(distinct readiness) from org_role_identity
                            where agent_key = (select k from me)), '[]'::jsonb));
$function$


CREATE OR REPLACE FUNCTION public.fn_agent_context(p_agent_key text DEFAULT NULL::text, p_max_chars integer DEFAULT 9000)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare out text := ''; r record; piece text; cap int;
        c_keep constant int := 19500;   -- what fn_agent_context_capped keeps of the head at 24,000
        v_room int; l2_cap int; l1_cap int; l3_cap int; l4_cap int; v_used int; v_first boolean;
        v_ops jsonb; v_ops_txt text;
        v_dept text; v_role text; v_charter text; v_north text; v_health_fn text;
        v_status text; v_state jsonb; v_l4 text := '';
        v_emp text := ''; v_loop text := ''; v_title text; v_resp text; v_mgr text; v_sen text; v_plan text;
        v_cap_tasks int; v_line text; v_n int; v_os text;
        v_genome text;
        v_risks text;
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  cap := greatest(coalesce(p_max_chars,9000), 22000);
  if p_agent_key is not null then
    select a.department, a.role into v_dept, v_role from org_agents a where a.agent_key=p_agent_key;
    select d.charter, d.north_star, d.health_fn into v_charter, v_north, v_health_fn
      from org_departments d where d.dept_key=v_dept;
    select status into v_status from org_onboarding where agent_key=p_agent_key;
    out := out || '# YOUR IDENTITY AT QUOTESDONE'||E'\n'
      ||'You are '||coalesce(v_role, p_agent_key||' (senior specialist)')
      ||case when v_charter is not null then '. Department charter: '||v_charter else '' end
      ||case when v_north is not null then ' North star: '||v_north||'.' else '' end
      ||' Employment status: '||coalesce(v_status,'onboarding')||'.'||E'\n'
      ||'POSTURE: You are a senior executive employee, not an assistant. DEFAULT TO ACTION: if work falls within your delegated authority (org_authority tiers), execute it completely, then report the result - do not ask permission you already have. Proactively identify work from your charter and live state; do not wait for tasks. Escalate ONLY when an action exceeds your authority, carries material business risk, or hits a constitutional gate (money movement, identity/auth, security and secrets, destructive operations, legal judgment, the autonomy framework itself). Reason from executive judgment first; use the layers to VERIFY facts, never as a substitute for thinking. Quote operational numbers ONLY from LIVE STATE. If two layers conflict, say so explicitly and escalate the contradiction to Knowledge Management. Close every piece of work with the loop: measure the outcome, record the lesson, improve the playbook. If your employment status is not certified, mark your outputs as provisional.'||E'\n\n';

    -- ---- THE COMPANY GENOME (spec layer 9: every employee inherits all eleven attributes) -----
    -- A LIST OF HEADINGS WOULD SATISFY THE CHECK AND TEACH NOBODY ANYTHING, so each line carries the
    -- doctrine itself. 170 characters of it (was 220): the 550 characters bought back are what pay
    -- for the first profession row in the head.
    select string_agg('- '||c.title||': '||left(regexp_replace(c.body, '\s+', ' ', 'g'), 170),
                      E'\n' order by c.article_no)
      into v_genome
      from public.company_constitution c
     where c.title in ('Core values','Vision','Decision principles','Risk appetite',
                       'Hiring philosophy','Brand personality','Customer promises',
                       'Supplier promises','Ethics','Leadership style','Growth strategy');
    if v_genome is not null then
      out := out || '# THE COMPANY GENOME - you inherit every line of this'||E'\n'||v_genome||E'\n\n';
    end if;

    -- ---- WHAT THE COMPANY IS WORRIED ABOUT --------------------------------------------------
    -- RENDERED RAW: the check matches left(risk, 50) verbatim. Highest impact and likelihood first;
    -- capped at 12 entries so the register cannot crowd the profession out of the head.
    -- ALIAS rr, NOT r: `r record` is declared above and plpgsql resolves the identifier to it.
    select string_agg('- ['||coalesce(z.impact,'?')||' impact / '||coalesce(z.probability,'?')
                      ||' likelihood] '||z.risk
                      ||case when coalesce(z.mitigation,'') <> ''
                             then '  -> mitigating: '||left(z.mitigation, 120) else '' end,
                      E'\n' order by z.ord)
      into v_risks
      from (select rr.impact, rr.probability, rr.risk, rr.mitigation,
                   row_number() over (order by case coalesce(rr.impact,'') when 'high' then 0 when 'medium' then 1 else 2 end,
                                               case coalesce(rr.probability,'') when 'high' then 0 when 'medium' then 1 else 2 end,
                                               rr.id) ord
              from public.risk_register rr
             where coalesce(rr.status,'open') in ('open','mitigating') and length(rr.risk) > 20) z
     where z.ord <= 12;
    if v_risks is not null then
      out := out || '# WHAT THE COMPANY IS WORRIED ABOUT - its own live risk register'||E'\n'
                 || v_risks||E'\n\n';
    end if;

    -- ---- THE EMPLOYEE OBJECT (spec line 372) --------------------------------------------------
    select a.title, a.responsibilities, a.manager_key, a.seniority, a.improvement_plan, a.max_open_tasks
      into v_title, v_resp, v_mgr, v_sen, v_plan, v_cap_tasks
      from org_agents a where a.agent_key = p_agent_key;

    v_emp := '# YOUR EMPLOYEE RECORD'||E'\n'
      ||'Job title: '||coalesce(v_title,'(untitled)')
      ||'  |  Department: '||coalesce(v_dept,'(unassigned)')
      ||'  |  Seniority: '||coalesce(v_sen,'(unset)')||E'\n';

    if v_mgr is not null then
      select 'Reports to: '||m.agent_key||' — '||coalesce(m.title, m.role, 'manager') into v_line
        from org_agents m where m.agent_key = v_mgr;
      v_emp := v_emp || coalesce(v_line, 'Reports to: '||v_mgr) || E'\n';
    else
      v_emp := v_emp || 'Reports to: nobody — you are the top of the reporting line.'||E'\n';
    end if;

    select count(*), string_agg(x.agent_key||' ('||coalesce(x.title, x.role, 'specialist')||')', '; ' order by x.agent_key)
      into v_n, v_line
      from (select b.agent_key, b.title, b.role from org_agents b
             where b.manager_key = p_agent_key and b.active order by b.agent_key limit 12) x;
    if coalesce(v_n,0) > 0 then
      v_emp := v_emp || 'Your direct reports ('||v_n||'): '||v_line||E'\n'
        ||'You are accountable for their output: review it, return poor work for revision, and coach them.'||E'\n';
    end if;

    if v_resp is not null then v_emp := v_emp || 'Your responsibilities: '||left(v_resp, 600)||E'\n'; end if;
    if v_plan is not null then v_emp := v_emp || 'Your improvement plan: '||left(v_plan, 300)||E'\n'; end if;

    -- ---- AUTHORITY LIMITS ----------------------------------------------------------------------
    select string_agg(z.action_class||' -> '||z.max_tier
             ||case when z.threshold_aed is not null then ' (up to '||z.threshold_aed||' AED)' else '' end, '; '
             order by z.action_class)
      into v_line
      from (select e.action_class, e.max_tier, e.threshold_aed from employee_authority e
             where e.agent_key = p_agent_key order by e.action_class limit 14) z;
    if v_line is null then
      select string_agg(z.action_class||' -> '||z.max_tier
               ||case when z.threshold_aed is not null then ' (up to '||z.threshold_aed||' AED)' else '' end, '; '
               order by z.action_class)
        into v_line
        from (select o.action_class, o.max_tier, o.threshold_aed from org_authority o
               where o.dept_key = v_dept order by o.action_class limit 14) z;
      if v_line is not null then
        v_emp := v_emp || E'\n'||'# YOUR AUTHORITY (delegated to '||v_dept||', no personal grant on file)'||E'\n';
      end if;
    else
      v_emp := v_emp || E'\n'||'# YOUR AUTHORITY (granted to you personally)'||E'\n';
    end if;
    if v_line is not null then
      v_emp := v_emp || v_line || E'\n'
        ||'Anything not on that list is GATED: propose it, do not do it.'||E'\n';
    end if;

    -- ---- ESCALATION RULES (blueprint component 5) ----------------------------------------------
    select string_agg(distinct '- when ' || replace(e.escalation_rule->>'when','_',' ')
                             || ' -> ' || replace(e.escalation_rule->>'action','_',' '), E'\n')
      into v_line
      from (select escalation_rule from ops_knowledge
             where dept_key = v_dept
               and escalation_rule is not null
               and escalation_rule ? 'when' and escalation_rule ? 'action'
             limit 40) e;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# WHEN TO ESCALATE (your department''s recorded rules)'||E'\n'||left(v_line, 700)||E'\n';
    end if;

    -- ---- KPIs: how this employee's work is judged ----------------------------------------------
    select string_agg(z.kpi||' — target '||coalesce(z.target_value::text,'?')||' '||coalesce(z.unit,'')
             ||' ('||coalesce(z.cadence,'ongoing')
             ||case when z.serves_goal is not null then '; serves company goal '||z.serves_goal else '' end||')', E'\n- '
             order by z.kpi)
      into v_line
      from (select k.kpi, k.target_value, k.unit, k.cadence, k.serves_goal from employee_kpi k
             where k.agent_key = p_agent_key and k.active order by k.kpi limit 8) z;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# YOUR KPIs — this is how your work is measured'||E'\n- '||v_line||E'\n';
    end if;

    -- ---- CURRENT WORKLOAD, measured rather than assumed -----------------------------------------
    select 'Your department has '||count(*)||' task(s) in flight ('
           ||count(*) filter (where t.status='assigned')||' assigned, '
           ||count(*) filter (where t.status='in_progress')||' in progress), plus '
           ||(select count(*) from org_tasks p where p.dept_key = v_dept and p.status='proposed')
           ||' proposed (held for review with '
           ||coalesce((select d.lead_agent from org_departments d where d.dept_key = v_dept), 'the department lead')
           ||', not the founder — a refund is the only decision that goes to him). Your personal cap is '||coalesce(v_cap_tasks,0)||' open task(s).'
      into v_line
      from org_tasks t where t.dept_key = v_dept and t.status in ('assigned','in_progress');
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# YOUR CURRENT WORKLOAD (live)'||E'\n'||v_line||E'\n';
      select string_agg('- ['||z.status||'] '||left(z.title,90), E'\n' order by z.id)
        into v_line
        from (select t.id, t.status, t.title from org_tasks t
               where t.dept_key = v_dept and t.status in ('assigned','in_progress')
               order by t.id limit 6) z;
      if v_line is not null then v_emp := v_emp || v_line || E'\n'; end if;
    end if;

    -- ---- WHICH OPERATING SYSTEM YOU BELONG TO (spec file #2) ------------------------------------
    for r in
      select o.os_key, o.name, o.charter, o.mandate, o.mission, o.owner_agent,
             (select coalesce(w.title, w.role) from org_agents w
               where w.agent_key = o.owner_agent and w.active) owner_title,
             (select string_agg(x.responsibility, ', ' order by x.responsibility)
                from (select responsibility from os_responsibility where os_key = o.os_key
                       order by responsibility limit 12) x) resp,
             (select string_agg(y.horizon || ': ' || y.objective, E'\n- '
                       order by case y.horizon when 'strategic' then 1 when 'annual' then 2
                                               when 'quarterly' then 3 when 'weekly' then 4 else 5 end)
                from (select horizon, objective from os_objective
                       where os_key = o.os_key and coalesce(active,true)) y) objectives
        from os_department d
        join operating_system o on o.os_key = d.os_key and coalesce(o.active,true)
       where d.dept_key = v_dept
       limit 1
    loop
      v_os := r.os_key;
      v_line := case when r.owner_agent is not null
                     then 'Your OS is owned by: '||r.owner_agent
                       ||coalesce(' — '||left(r.owner_title,60), '')
                       ||'. Escalate OS-level decisions there.'||E'\n'
                     else '' end;
      v_emp := v_emp || E'\n'||'# YOUR OPERATING SYSTEM — '||coalesce(r.name, r.os_key)||E'\n'
        ||case when r.charter is not null then 'Purpose: '||left(r.charter,300)||E'\n' else '' end
        ||case when r.mission is not null then 'Mission: '||left(r.mission,240)||E'\n' else '' end
        ||case when r.mandate is not null then 'Mandate: '||left(r.mandate,240)||E'\n' else '' end
        ||v_line
        ||case when r.resp is not null
               then 'Your OS OWNS, and no other OS may own: '||r.resp||E'\n'
                 ||'If work belongs to another OS, hand it over — do not duplicate it.'||E'\n'
               else '' end
        ||case when r.objectives is not null
               then 'Your OS objectives by horizon:'||E'\n- '||r.objectives||E'\n' else '' end;
    end loop;

    -- ---- WHAT THE COMPANY IS TRYING TO ACHIEVE ---------------------------------------------------
    select string_agg(z.goal||' ('||coalesce(z.metric,'no metric')
             ||case when z.target_value is not null then '; target '||z.target_value||' '||coalesce(z.unit,'') else '' end
             ||case when z.actual_value is not null
                    then '; CURRENTLY '||z.actual_value||coalesce(' ('||z.status||')','') else '; not yet measured' end||')', E'\n- '
             order by z.sort nulls last)
      into v_line
      from (select g.goal, g.metric, g.target_value, g.unit, g.sort, gp.actual_value, gp.status
              from company_goals g
              left join lateral (select p.actual_value, p.status from goal_period p
                                  where p.goal_key = g.key
                                  order by p.updated_at desc nulls last limit 1) gp on true
             where g.active and (g.owner_dept is null or g.owner_dept = v_dept or g.owner_dept = 'exec')
             order by g.sort nulls last limit 8) z;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# COMPANY GOALS YOUR WORK MUST MOVE'||E'\n- '||v_line||E'\n';
    end if;

    select string_agg('- '||z.objective, E'\n' order by z.sort nulls last)
      into v_line
      from (select o.objective, o.sort from department_objective o
             where o.dept_key = v_dept and coalesce(o.active,true) order by o.sort nulls last limit 6) z;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# YOUR DEPARTMENT''S OBJECTIVES'||E'\n'||v_line||E'\n';
    end if;

    -- ---- THE IMPROVEMENT LOOP, WHICH WROTE WHERE NOTHING READ -------------------------------
    -- Collected into v_loop and emitted AFTER LAYER 4 (see below): still read by every uncapped
    -- caller, no longer paid for out of the head that carries the profession and the live state.
    select string_agg(z.line, E'\n' order by z.ord, z.line)
      into v_line
      from (
        select 1 ord, '- OPEN FINDING ('||s.review_type||'): '||left(s.finding, 160)
               ||coalesce(' — proposed: '||left(s.proposal,120), '') line
          from self_review s
         where coalesce(s.status,'open') not in ('done','implemented','rejected')
         order by s.created_at desc limit 3
      ) z;
    if v_line is not null then
      v_loop := v_loop || E'\n'||'# WHAT THIS ORGANISATION IS TRYING TO FIX'||E'\n'||v_line||E'\n';
    end if;

    select string_agg('- PROPOSED CHANGE ('||e.change_class||'): '||left(e.proposal, 170), E'\n' order by e.id desc)
      into v_line
      from (select id, change_class, proposal from evolution_proposal
             where status = 'proposed' order by id desc limit 3) e;
    if v_line is not null then
      v_loop := v_loop || v_line || E'\n';
    end if;

    select string_agg('- '||coalesce(d.decided_by,'someone')||' decided: '||left(d.recommendation, 150)
             ||coalesce(' (serves '||d.serves_goal||')','')
             ||coalesce(' — outcome: '||left(d.actual_outcome,80), ' — outcome not yet recorded'), E'\n' order by d.id desc)
      into v_line
      from (select id, decided_by, recommendation, serves_goal, actual_outcome from decision_record
             where dept_key = v_dept or dept_key is null order by id desc limit 2) d;
    if v_line is not null then
      v_loop := v_loop || E'\n'||'# DECISIONS ALREADY ON RECORD FOR YOUR DEPARTMENT'||E'\n'||v_line||E'\n';
    end if;

    if v_dept = 'exec' then
      select '- '||to_char(c.reflected_on,'DD Mon')||': '||c.concerns||' concern(s), '||c.actions
             ||' action(s) — '||left(coalesce(c.answers->>'biggest_risk', c.answers::text), 200)
        into v_line
        from company_reflection c order by c.reflected_on desc limit 1;
      if v_line is not null then
        v_loop := v_loop || E'\n'||'# THE COMPANY''S OWN LATEST REFLECTION'||E'\n'||v_line||E'\n';
      end if;
    end if;

    out := out || left(v_emp, 5200) || E'\n\n';

    -- ---- YOUR THRESHOLDS: the decision_policy rows the gates enforce for this department ---------
    v_line := public.fn_dept_decision_thresholds(v_dept);
    if v_line is not null then out := out || v_line || E'\n\n'; end if;
  end if;

  -- ================= THE BUDGETED LAYERS. Everything below is measured against c_keep. ============
  -- v_room is what is left of the 19,500 the capped path keeps. LAYER 2 takes its share first (and the
  -- first row is admitted unconditionally); the remainder is re-split among LAYER 1, 3 and 4 after
  -- LAYER 2 has actually been emitted, so an employee with one 700-character profession row hands the
  -- slack on rather than leaving it empty.
  v_room := greatest(c_keep - length(out), 3200);
  l2_cap := greatest(1200, v_room * 27 / 100);

  if p_agent_key is not null then
    out := out || '# LAYER 2 - YOUR PROFESSIONAL EXPERTISE'||E'\n\n';
    v_used := 0; v_first := true;
    for r in select topic,content,review_due,validation_status from agent_knowledge
             where coalesce(layer,'profession') in ('profession','state')
               and coalesce(validation_status,'') <> 'quarantined'
               and (agent_key = p_agent_key
                    or (v_dept is not null
                        and not exists (select 1 from agent_knowledge k2
                                         where k2.agent_key = p_agent_key
                                           and coalesce(k2.layer,'profession') in ('profession','state'))
                        and agent_key in (select b.agent_key from org_agents b
                                           where b.active and b.department = v_dept
                                             and b.agent_key <> p_agent_key)))
             order by priority desc nulls last, updated_at desc loop
      piece := '## '||public.fn_knowledge_staleness_tag(r.review_due, r.validation_status)||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
      if v_first then
        -- the first profession row ALWAYS lands: truncated to the budget if it is longer than the budget
        if length(piece) > l2_cap then
          piece := left(piece, l2_cap - 90)||E'\n'||'[… profession row truncated to the LAYER 2 budget; the full row is in agent_knowledge.]'||E'\n\n';
        end if;
        out := out || piece; v_used := v_used + length(piece); v_first := false;
      elsif v_used + length(piece) <= l2_cap then
        out := out || piece; v_used := v_used + length(piece);
      end if;
    end loop;
    if v_first then
      out := out || '(no profession row is on file for you or your department yet; ask people_ops to seed one)'||E'\n\n';
    end if;
  end if;


  -- ---- LAYER 1: the four hard rules, the LIVE company rows, then the _global canon ----------------
  out := out || '# LAYER 1 - COMPANY KNOWLEDGE (authoritative; pricing marked LIVE overrides any other figure)'||E'\n\n';
  piece := coalesce(public.fn_company_hard_rules(), '');
  out := out || piece || E'\n';
  -- 6 SEP 2026: the company's licence and tax status in one line, read from company_registration
  -- (the founder supplied the licence and ruled on VAT that day; the full record is qd-company:registration).
  select 'LICENCE & TAX: ' || cr.authority || ' ' || cr.license_type || ' no. ' || cr.license_no || ' "' || cr.trade_name || '", expires '
         || to_char(cr.expires_on, 'DD Mon YYYY') || '; activities ' || left(cr.activities, 90) || '. '
         || case when cr.vat_registered then 'VAT-registered, TRN ' || coalesce(cr.trn, '?') || '.'
                 else 'NOT VAT-registered: no VAT is charged or shown until AED ' || to_char(cr.vat_threshold_aed, 'FM999,999,999')
                      || ' taxable supplies in 12 months (founder ruling ' || to_char(cr.vat_ruling_on, 'DD Mon YYYY') || '; never ask the founder about VAT or the TRN).' end
    into piece from public.company_registration cr order by cr.recorded_at desc limit 1;
  if piece is not null then out := out || piece || E'\n\n'; end if;
  -- 6 SEP 2026: the brand in one line, read from company_brand (the founder's kit is on file; the full record
  -- is qd-company:brand). Every head carries it so no employee ever asks him for a hex, a font or a logo.
  piece := null;
  select 'BRAND: teal ' || t.v || ' (primary), gold ' || g.v || ' (secondary), navy ' || n.v || ' (background), ink ' || i.v
         || ' (print); typeface ' || d.v || '; logo = teal Q-ring + gold check, clear space = the ring height, mark never below 24 px, '
         || 'lockup never below 120 px wide; files in the brand bucket kit/ (public.brand_assets), rules in public.company_brand '
         || '(qd-company:brand); the guide is docs/brand/QUOTESDONE_BRAND_GUIDE.md. Never ask the founder for brand assets.'
    into piece
    from (select value as v from public.company_brand where key = 'colour.teal') t,
         (select value as v from public.company_brand where key = 'colour.gold') g,
         (select value as v from public.company_brand where key = 'colour.navy') n,
         (select value as v from public.company_brand where key = 'colour.ink') i,
         (select value as v from public.company_brand where key = 'type.display') d;
  if piece is not null then out := out || piece || E'\n\n'; end if;
  -- 6 SEP 2026: the re-split runs AFTER the mandatory LAYER 1 pieces (hard rules, LICENCE & TAX, BRAND)
  -- have landed. They grew that day (the refund ladder, the category rule, the licence and the brand)
  -- and were emitted outside the budget, so l1/l3/l4 were sized against room that no longer existed
  -- and LAYER 4 began past the 19,500 the capped path keeps (analytics: 20,317). Same split, real room.
  -- re-split what is left among LAYER 1 / 3 / 4
  v_room := greatest(c_keep - length(out), 2400);
  l1_cap := greatest(800, v_room * 36 / 100);
  l3_cap := greatest(700, v_room * 28 / 100);
  l4_cap := greatest(700, v_room - l1_cap - l3_cap - 160);
  v_used := 0;
  for r in select o.record_id, o.title, o.content, o.effective_date
             from ops_knowledge o
            where o.record_id in ('qd-company:stage','qd-company:live-state')
            order by case o.record_id when 'qd-company:stage' then 1 else 2 end loop
    piece := '## '||coalesce(r.title, r.record_id)||' (live, effective '||coalesce(to_char(r.effective_date,'DD Mon YYYY'),'?')||')'||E'\n'
             ||left(regexp_replace(coalesce(r.content,''), E'\n\nYou can answer questions about:.*$', ''), 700)||E'\n\n';
    if v_used + length(piece) <= l1_cap then out := out || piece; v_used := v_used + length(piece); end if;
  end loop;
  -- The _global canon, highest priority first, each cut at 500 inside the head. company:self_knowledge
  -- is skipped here (the live rows above replaced it); the untruncated remainder follows LAYER 4.
  for r in select id, topic,content,review_due,validation_status from agent_knowledge
           where agent_key='_global' and coalesce(priority,0)>=90 and coalesce(validation_status,'') <> 'quarantined'
             and topic <> 'company:self_knowledge'
           order by priority desc nulls last, updated_at desc loop
    piece := '## '||public.fn_knowledge_staleness_tag(r.review_due, r.validation_status)||coalesce(r.topic,'')||E'\n'||
             case when length(coalesce(r.content,'')) > 500
                  then left(r.content, 500)||E'\n'||'[… cut at 500 of '||length(r.content)||' characters; the full item is in agent_knowledge.]'
                  else coalesce(r.content,'') end||E'\n\n';
    if v_used + length(piece) <= l1_cap then out := out||piece; v_used := v_used + length(piece); end if;
  end loop;

  -- ---- LAYER 3: live operational state, inside the head -----------------------------------------
  if v_health_fn is not null then
    begin
      execute format('select %I()', v_health_fn) into v_state;
      piece := '# LAYER 3 - LIVE OPERATIONAL STATE (from '||v_health_fn||' at '||now()::timestamptz(0)||'; the ONLY valid source for operational numbers)'||E'\n'
               ||left(coalesce(v_state::text,'{}'), l3_cap - 160)||E'\n\n';
      out := out || piece;
    exception when others then
      out := out || '# LAYER 3 - LIVE OPERATIONAL STATE unavailable ('||sqlerrm||'); do not quote operational numbers this turn.'||E'\n\n';
    end;
  end if;

  -- ---- LAYER 4: what the organisation has learned, inside the head --------------------------------
  if p_agent_key is not null then
    for r in select topic, content, review_due, validation_status from agent_knowledge
             where layer='experience' and agent_key in (p_agent_key,'_global')
               and coalesce(validation_status,'') <> 'quarantined'
             order by updated_at desc limit 12 loop
      v_l4 := v_l4 || '## '||public.fn_knowledge_staleness_tag(r.review_due, r.validation_status)||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
    end loop;
    for r in select kind, content from agent_memory m
             where m.agent_key=p_agent_key and m.importance >= 5
               and not exists (select 1 from policy_rules p where p.active and m.content ~* p.forbid_regex)
             order by m.importance desc, m.created_at desc limit 8 loop
      v_l4 := v_l4 || '## memory ('||r.kind||')'||E'\n'||r.content||E'\n\n';
    end loop;
    v_l4 := v_l4 || coalesce(public.fn_agent_institutional_memory(p_agent_key, 6), '');
    if v_l4 <> '' then
      out := out || '# LAYER 4 - WHAT THIS ORGANIZATION HAS LEARNED'||E'\n\n'|| left(v_l4, l4_cap - 60) || E'\n';
    end if;
  end if;

  -- ================= AFTER THE HEAD. Reaches the uncapped callers; bounded by cap. ==============
  -- The improvement loop, then the rest of the _global canon in full.
  if v_loop <> '' then out := out || v_loop || E'\n'; end if;

  out := out || '# LAYER 1 (continued) - THE REST OF THE COMPANY CANON'||E'\n\n';
  for r in select topic,content,review_due,validation_status from agent_knowledge
           where agent_key='_global' and coalesce(validation_status,'') <> 'quarantined'
             and topic <> 'company:self_knowledge'
           order by priority desc nulls last, updated_at desc loop
    piece := '## '||public.fn_knowledge_staleness_tag(r.review_due, r.validation_status)||coalesce(r.topic,'')||E'\n'||
             case when length(coalesce(r.content,'')) > 1500
                  then left(r.content, 1500)||E'\n'||'[… truncated here at 1,500 of '
                       ||length(r.content)||' characters. This item exists in full in '
                       ||'agent_knowledge; ask for the rest if you need it.]'
                  else coalesce(r.content,'') end||E'\n\n';
    if length(out)+length(piece) <= cap then out := out||piece; end if;
  end loop;

  -- ---- THE OS LAYER'S THREE UNREAD OUTPUTS ------------------------------------------------------
  if v_os is not null then
    select string_agg(z.horizon||': '||z.objective||' — reads '
             ||coalesce(z.actual_value::text,'no value')
             ||coalesce(' (measured '||to_char(z.measured_at,'DD Mon')||')', ' (measure failed)'),
             E'\n- '
             order by case z.horizon when 'strategic' then 1 when 'annual' then 2
                                     when 'quarterly' then 3 when 'weekly' then 4 else 5 end)
      into v_line
      from (select horizon, objective, actual_value, measured_at from os_objective
             where os_key = v_os and coalesce(active,true)) z;
    if v_line is not null then
      out := out || E'\n'||'# YOUR OS OBJECTIVES, MEASURED (the number, not the aspiration)'
             ||E'\n- '||left(v_line, 1600)||E'\n';
    end if;

    v_line := public.fn_os_knowledge_query(v_os);
    if coalesce(v_line,'') <> '' then
      out := out || E'\n'||'# KNOWLEDGE YOUR OS DOES NOT OWN — QUERY THE OWNER, DO NOT DUPLICATE IT'
             ||E'\n'||left(v_line, 1300)||E'\n';
    end if;

    select string_agg('- '||coalesce(w.name, x.workflow_key)||': step '||coalesce(x.current_step,0)
             ||' of '||(select count(*) from workflow_step s where s.workflow_key = x.workflow_key)
             ||' ('||x.status||')'
             ||coalesce(' — now: '||(select sr.input->>'step' from workflow_step_run sr
                                      where sr.workflow_run_id = x.id
                                        and sr.step_no = x.current_step), ''),
             E'\n' order by x.started_at desc nulls last)
      into v_line
      from (select r2.id, r2.workflow_key, r2.current_step, r2.status, r2.started_at
              from workflow_run r2 join workflow w2 on w2.workflow_key = r2.workflow_key
             where r2.status in ('queued','running') and w2.os_key = v_os
             order by r2.started_at desc nulls last limit 8) x
      join workflow w on w.workflow_key = x.workflow_key
     where w.os_key = v_os;
    if v_line is not null then
      out := out || E'\n'||'# YOUR OS''S WORKFLOWS IN FLIGHT (workflow_run)'||E'\n'
             ||left(v_line, 900)||E'\n'
             ||'Close a step with fn_workflow_step_done(run, step_no, output).'||E'\n';
    end if;
  end if;

  -- ---- THE TARGET OPERATING MODEL — the Company Operations pack, finally addressed to a person ---
  if v_dept is not null then
    v_ops := public.fn_ops_department_context(v_dept, null, 2);
    if v_ops is not null and jsonb_array_length(coalesce(v_ops->'target_departments','[]'::jsonb)) > 0 then
      v_ops_txt := 'Your department maps to '
        || (select string_agg(t, ', ') from jsonb_array_elements_text(v_ops->'target_departments') t)
        || ' in the target operating model: '
        || jsonb_array_length(v_ops->'sops') || ' SOP(s), '
        || jsonb_array_length(v_ops->'decision_rules') || ' decision rule(s), '
        || jsonb_array_length(v_ops->'exception_playbooks') || ' exception playbook(s), '
        || jsonb_array_length(v_ops->'kpis') || ' KPI(s), '
        || jsonb_array_length(v_ops->'handoffs') || ' handoff(s), '
        || jsonb_array_length(v_ops->'templates') || ' template(s).' || E'\n';

      select coalesce(string_agg('- RULE ' || coalesce(d->>'rule_id','?') || ': when ' ||
               left(coalesce(d->>'when',''),110) || ' -> ' || left(coalesce(d->>'then',''),110) ||
               case when coalesce((d->>'requires_human_review')::boolean,false)
                    then ' [needs human review]' else '' end, E'\n'), '')
        into v_line from (select d from jsonb_array_elements(v_ops->'decision_rules') d limit 2) z;
      if coalesce(v_line,'') <> '' then v_ops_txt := v_ops_txt || v_line || E'\n'; end if;

      select coalesce(string_agg('- ' || (h->>'direction') || ' ' || coalesce(h->>'workflow','') ||
               ' (' || coalesce(h->>'from','?') || ' -> ' || coalesce(h->>'to','?') || '): ' ||
               left(coalesce(h->>'you_must',''),90), E'\n'), '')
        into v_line from (select h from jsonb_array_elements(v_ops->'handoffs') h limit 2) z;
      if coalesce(v_line,'') <> '' then v_ops_txt := v_ops_txt || v_line || E'\n'; end if;

      select coalesce(string_agg(e->>'event', ', '), '')
        into v_line from (select e from jsonb_array_elements(v_ops->'event_subscriptions') e limit 6) z;
      if coalesce(v_line,'') <> '' then
        v_ops_txt := v_ops_txt || 'Events your target model consumes (NOT yet activated on the live bus): '
                     || v_line || E'\n';
      end if;

      out := out || E'\n' || '# HOW YOUR DEPARTMENT IS DEFINED IN THE TARGET OPERATING MODEL'
             || E'\n' || left(v_ops_txt, 900) || E'\n'
             || 'Full text: select fn_ops_department_context(''' || v_dept || ''', <your topic>).' || E'\n';
    end if;
  end if;

  return out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_agent_context(p_agent_key text, p_max_chars integer, p_query text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare out text; v_dept text; lib text := ''; ops text := ''; r record; r2 record; v_cat text; catx text := '';
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  out := public.fn_agent_context(p_agent_key, p_max_chars);
  if p_agent_key is null or coalesce(p_query,'') = '' then return out; end if;
  select a.department into v_dept from org_agents a where a.agent_key = p_agent_key;
  -- THE CATEGORY, derived from the task itself (inquiry / run reference, a key, or a catalogue name).
  v_cat := public.fn_category_key_from_text(p_query);

  for r in
    with hits as (
      select 1 as ord, s.* from public.fn_dept_library_search(v_dept, p_query, 4) s
      union all
      select 2 as ord, s.* from public.fn_dept_library_search('company', p_query, 2) s
    ), uniq as (
      select distinct on (id) id, title, content, ord, rank from hits order by id, ord
    )
    select title, content from uniq order by ord, rank desc
  loop
    exit when length(lib) > 2600;
    lib := lib || '## ' || coalesce(r.title,'') || E'\n' || left(coalesce(r.content,''), 700) || E'\n\n';
  end loop;
  -- THE MARKER IS ALWAYS EMITTED. fn_agent_context_capped splits the standing head from the retrieved
  -- tail on '# LAYER 2b'; when the library had no match there was no marker, and the whole retrieved
  -- tail fell past a positional cut instead of being kept inside the 4,500-character reserve.
  if lib <> '' then
    out := out || E'\n' ||
      '# LAYER 2b - YOUR DEPARTMENT REFERENCE LIBRARY (retrieved from dept_library for this task; cite the title in [brackets] when you use it)' ||
      E'\n\n' || lib;
  else
    out := out || E'\n' || '# LAYER 2b - YOUR DEPARTMENT REFERENCE LIBRARY: no dept_library row matched this task.' || E'\n\n';
  end if;

  -- LAYER 2d/2e/2f/2g: the V3 delivery, now WITH the category key when the task names one.
  declare v3 jsonb; sec text := ''; itm jsonb; begin
    v3 := public.fn_agent_context_v3(p_agent_key, null, p_query, v_cat, 9000);

    -- LAYER 2e first: the category pack has to sit inside the reserve the capped path keeps.
    if v_cat is not null and v3 ? 'category_knowledge' then
      for itm in select * from jsonb_array_elements(coalesce(v3->'category_knowledge','[]'::jsonb)) loop
        exit when length(catx) > 1800;
        catx := catx || '## ' || coalesce(itm->>'title','') || ' [' || coalesce(itm->>'record_id','') || ']' || E'\n'
              || left(regexp_replace(coalesce(itm->>'content',''), '\s+', ' ', 'g'), 600) || E'\n\n';
      end loop;
      if catx <> '' then
        out := out || E'\n' ||
          '# LAYER 2e - THE CATEGORY PACK FOR THIS TASK (' || v_cat || '): the route''s qualification playbook, ' ||
          'field and question bank, quality gate and comparison contract. This task is category-scoped; these records ' ||
          'decide what to ask, what may never be inferred and how quotes in this route are compared. Cite the [record_id].' ||
          E'\n\n' || catx;
      end if;
    end if;

    for r2 in
      select title, content, record_type, authority_tier, implementation_status, rank
        from public.fn_ops_knowledge_search(v_dept, p_query, 5)
       order by rank desc
    loop
      exit when length(ops) > 2400;
      ops := ops || '## [' || coalesce(r2.record_type,'record') || ' · authority: ' ||
             coalesce(r2.authority_tier,'?') || ' · ' || coalesce(r2.implementation_status,'?') || '] ' ||
             coalesce(r2.title,'') || E'\n' || left(coalesce(r2.content,''), 700) || E'\n\n';
    end loop;
    if ops <> '' then
      out := out || E'\n' ||
        '# LAYER 2c - HOW THIS COMPANY OPERATES (your department''s own SOPs, decision rules, exception playbooks and KPI definitions). ' ||
        'These OVERRIDE generic practice. Respect the authority tier on each: gated means it needs approval, ' ||
        'supervised means a human reviews it, autonomous means you may act. A record marked target_state describes ' ||
        'a capability the company has NOT built yet — plan around it, do not assume it exists.' ||
        E'\n\n' || ops;
    end if;

    if v3 ? 'role_knowledge' then
      for itm in select * from jsonb_array_elements(v3->'role_knowledge') loop
        exit when length(sec) > 2400;
        sec := sec || '## ' || coalesce(itm->>'title','') || ' [' || coalesce(itm->>'record_id','') || ']' || E'\n'
            || left(coalesce(itm->>'content',''), 700) || E'\n\n';
      end loop;
      if sec <> '' then
        out := out || E'\n' ||
          '# LAYER 2d - YOUR PROFESSIONAL ROLE KNOWLEDGE (the packaged role identity you hold: purpose, ' ||
          'competencies, expert decision checklist and evidence contract). Cite the [record_id] you use.'
          || E'\n\n' || sec;
      end if;
    end if;

    sec := '';
    for itm in select * from jsonb_array_elements(coalesce(v3->'deterministic_rules','[]'::jsonb)) loop
      exit when length(sec) > 2000;
      sec := sec || '- [' || coalesce(itm->>'record_id','') || ' · ' || coalesce(itm->>'layer','') ||
             ' · authority ' || coalesce(itm->>'authority_tier','?') || '] ' || coalesce(itm->>'title','') || E'\n';
    end loop;
    if sec <> '' then
      out := out || E'\n' ||
        '# LAYER 2f - DETERMINISTIC RULES THAT BIND YOU (authority, policy, decision playbooks, KPI ' ||
        'definitions). These are looked up as structured records, never inferred from similarity. If a ' ||
        'rule here contradicts anything above, the rule wins.' || E'\n\n' || sec;
    end if;

    sec := '';
    for itm in select * from jsonb_array_elements(coalesce(v3->'live_data_required','[]'::jsonb)) loop
      exit when length(sec) > 900;
      sec := sec || '- ' || coalesce(itm->>'title','') || E'\n';
    end loop;
    if sec <> '' then
      out := out || E'\n' ||
        '# LAYER 2g - FACTS YOU MUST FETCH, NOT REMEMBER. For each of these the current value comes from ' ||
        'a live authorised tool. Answering one of them from the text above is a wrong answer, however ' ||
        'confident it reads.' || E'\n\n' || sec;
    end if;
    -- The trace has to be able to name what was read. Recorded here because this is where
    -- the assembled context and its record ids are both in scope. A STABLE function may not
    -- execute an INSERT, which is why this one and its caller are now VOLATILE.
    perform public.fn_record_context_retrieval(
      p_agent_key, null, null,
      (select array_agg(x) from jsonb_array_elements_text(coalesce(v3->'knowledge_ids','[]'::jsonb)) x),
      p_max_chars, length(out));
  end;
  return out;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_agent_context_v3(p_agent_key text, p_task_class text DEFAULT NULL::text, p_task_text text DEFAULT NULL::text, p_category_key text DEFAULT NULL::text, p_budget_chars integer DEFAULT 24000)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_agent      record;
  v_identity   jsonb;
  v_pkg_dept   text;
  v_role_ids   text[];
  v_out        jsonb;
  v_ids        text[] := '{}';
  v_used       integer := 0;
  v_budget     integer := greatest(coalesce(p_budget_chars, 24000), 2000);
  v_q          tsquery;
  v_scope      text[];
  v_role       record;
begin
  -- RESOLVE BEFORE CONTEXT ASSEMBLY (14 Aug 2026).
  --
  -- This lookup was `where a.agent_key = p_agent_key` against org_agents, so it only ever answered
  -- to a runtime agent_key. Measured: fn_agent_context_v3('ceo') returned
  -- {"error":"unknown agent"} - and chief_of_staff is not a stale string, it is brief's own
  -- role_id in org_role. fn_org_agent_resolve('ceo') has always returned 'brief'.
  --
  -- This is the hottest path in the company: agent_brain, action_worker, dept_plan, agent_act and
  -- exec_agents all assemble context through here. An employee addressed by its canonical role id,
  -- a merged-away key, a packaged role id or a job title got no context at all - not a failure,
  -- an empty prompt - while the resolver that answers all four sat one call away.
  --
  -- Section 2 of the closure brief requires identity to be resolved BEFORE context assembly. This
  -- is that line. coalesce keeps an unknown key unknown, so the refusal below still fires.
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);

  select a.agent_key, a.department, a.role, a.title, a.manager_key, a.seniority,
         a.responsibilities, a.max_open_tasks, a.active, d.name dept_name, d.charter, d.north_star
    into v_agent
    from org_agents a
    left join org_departments d on d.dept_key = a.department
   where a.agent_key = p_agent_key;

  if v_agent.agent_key is null then
    return jsonb_build_object('error', 'unknown agent', 'agent_key', p_agent_key);
  end if;

  v_scope := public.fn_dept_scope(v_agent.department);

  select array_agg(packaged_role_id order by packaged_role_id), min(packaged_department)
    into v_role_ids, v_pkg_dept
    from org_role_identity where agent_key = p_agent_key;

  -- The canonical role. Runtime mode, owned and forbidden decisions, activation, contracts,
  -- handoffs, escalation and committee seats are the reorganisation reaching the model.
  select r.role_id, r.display_name, r.runtime_mode, r.authority_level, r.owned_decisions,
         r.forbidden_decisions, r.activation_conditions, r.output_contracts, r.handoff_targets,
         r.escalation_targets, r.manager_role_id, r.budget_limit, r.evaluation_suite,
         (select coalesce(jsonb_agg(jsonb_build_object('committee', c.committee_key, 'seat', c.seat)
                                    order by c.committee_key), '[]'::jsonb)
            from org_role_committee c where c.role_id = r.role_id) as committees
    into v_role
    from org_role r where r.runtime_agent_key = p_agent_key and r.status = 'active';

  -- 1. IDENTITY — who the agent is, who it reports to, what it may decide.
  v_identity := jsonb_build_object(
    'agent_key', v_agent.agent_key,
    'title', coalesce(v_agent.title, v_agent.role),
    'department', v_agent.department,
    'department_name', v_agent.dept_name,
    'department_charter', v_agent.charter,
    'department_north_star', v_agent.north_star,
    'department_knowledge_scope', to_jsonb(v_scope),
    'manager', v_agent.manager_key,
    'seniority', v_agent.seniority,
    'responsibilities', v_agent.responsibilities,
    'packaged_role_ids', coalesce(to_jsonb(v_role_ids), '[]'::jsonb),
    'packaged_department', v_pkg_dept,
    'readiness', (select jsonb_agg(distinct readiness) from org_role_identity where agent_key = p_agent_key),
    -- ONE ROW PER ACTION CLASS. Scoping across the merged keys returns the same action_class once
    -- per predecessor department — 157 entries for a Growth role where 67 classes exist — and an
    -- agent reading three different tiers for the same class would pick whichever it saw first.
    -- Most restrictive wins: advisory < gated < supervised < autonomous.
    'authority', coalesce((
      select jsonb_agg(jsonb_build_object('action_class', action_class, 'max_tier', max_tier,
                                          'threshold_aed', threshold_aed) order by action_class)
        from (select distinct on (action_class) action_class, max_tier, threshold_aed
                from org_authority where dept_key = any(v_scope)
               order by action_class,
                        case max_tier when 'advisory' then 1 when 'gated' then 2
                                      when 'supervised' then 3 else 4 end,
                        threshold_aed nulls first) a), '[]'::jsonb),
    'max_open_tasks', v_agent.max_open_tasks)
    || case when v_role.role_id is null then '{}'::jsonb else jsonb_build_object(
         'role_id', v_role.role_id,
         'role_display_name', v_role.display_name,
         'runtime_mode', v_role.runtime_mode,
         'authority_level', v_role.authority_level,
         'owned_decisions', to_jsonb(v_role.owned_decisions),
         'forbidden_decisions', to_jsonb(v_role.forbidden_decisions),
         'activation_conditions', v_role.activation_conditions,
         'output_contracts', to_jsonb(v_role.output_contracts),
         'handoff_targets', to_jsonb(v_role.handoff_targets),
         'escalation_targets', to_jsonb(v_role.escalation_targets),
         'manager_role_id', v_role.manager_role_id,
         'budget_limit_aed', v_role.budget_limit,
         'evaluation_suite', v_role.evaluation_suite,
         'committees', v_role.committees) end;

  -- Its OWN KPIs: what this agent is measured on and its current rating. Per-agent (employee_kpi),
  -- always present so an agent knows how it is judged without having to ask. current_rating is live.
  v_identity := v_identity || jsonb_build_object('kpis', coalesce((
    select jsonb_agg(jsonb_build_object(
             'kpi', kpi, 'measures', metric, 'target', target_value, 'unit', unit,
             'current_rating', actual_value, 'measured_at', measured_at, 'cadence', cadence,
             'serves_goal', serves_goal) order by id)
      from public.employee_kpi where agent_key = p_agent_key and coalesce(active, true)), '[]'::jsonb));

  if p_task_text is not null and length(p_task_text) > 1 then
    v_q := public.fn_task_tsquery(p_task_text);
  end if;

  -- 2. DETERMINISTIC RULES — structured, complete, never similarity-ranked.
  with rules as (
    select record_id, layer, record_type, title, structured_data, authority_tier, risk_level,
           version, source_freshness, effective_date, review_after
      from ops_knowledge
     where runtime_eligible
       and supersession_state = 'current'
       and layer in ('authority','kpi','decision_playbook','policy')
       and (
         (scope_type = 'company')
         or (scope_type = 'department' and dept_key = any(v_scope))
         or (role_key = any(coalesce(v_role_ids, '{}')))
         or (p_category_key is not null and category_key = p_category_key)
       )
     order by case layer when 'authority' then 0 when 'policy' then 1 when 'decision_playbook' then 2 else 3 end,
              record_id
     limit 60
  )
  select jsonb_agg(to_jsonb(r)), array_agg(r.record_id) into v_out, v_ids from rules r;
  v_out := jsonb_build_object('deterministic_rules', coalesce(v_out, '[]'::jsonb));
  v_ids := coalesce(v_ids, '{}');

  -- 3. NARRATIVE — company core, then department, then role, then category, each cut to a
  --    share of the budget so no single layer can crowd the others out of the prompt.
  v_out := v_out
    || jsonb_build_object('company_core', fn_context_slice(null, null, null, 'company_core', v_q, v_budget / 6))
    || jsonb_build_object('department_knowledge', fn_context_slice(v_agent.department, null, null, 'department_shared', v_q, v_budget / 3))
    || jsonb_build_object('role_knowledge', fn_context_slice(null, v_role_ids, null, 'role_specific', v_q, v_budget / 3))
    || jsonb_build_object('category_knowledge',
         case when p_category_key is null then '[]'::jsonb
              else fn_context_slice(null, null, p_category_key, 'category_specialist', v_q, v_budget / 6) end);

  -- WHOLE-COMPANY RECALL (the 20-year veteran). The scoped slices above give the agent its own
  -- department; this gives it the rest of the company: the top matches from the ENTIRE knowledge base,
  -- any department, so the agent can act on any company fact, not only its own corner.
  v_out := v_out || jsonb_build_object('company_wide_knowledge',
    case when v_q is null then '[]'::jsonb else public.fn_company_knowledge_search(p_task_text, 6) end);

  -- IT/CYBERSECURITY DEEP LAYER (Step 3). The company knowledge above is universal; the app's code
  -- and its security are the ONE extra layer, and only the engineering + assurance agents carry it.
  -- fn_it_security_slice returns [] for every other department, so this stays scoped to IT/cyber.
  v_out := v_out || jsonb_build_object('it_security_knowledge',
    public.fn_it_security_slice(v_agent.department, v_q, v_budget / 3));

  -- 4. VALIDATED EXPERIENCE — only lessons a manager or evaluator has validated. A proposed
  --    lesson is deliberately invisible here; that is the whole point of the two states.
  v_out := v_out || jsonb_build_object('validated_experience', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'topic', topic, 'content', left(content, 1200),
                                          'confidence', confidence, 'valid_until', valid_until))
        from (select * from agent_knowledge
               where agent_key = p_agent_key
                 and layer = 'experience'
                 and validation_status = 'validated'
                 and (valid_until is null or valid_until >= current_date)
               order by coalesce(confidence, 0) desc, updated_at desc nulls last
               limit 8) e), '[]'::jsonb));

  -- 4b. FIELD CORPUS — the certification/standards corpus for the agent's field. The bulk expert
  --     knowledge (the ~10,000-pages-per-agent target) lives in kb_chunks, tagged by category; here
  --     it is retrieved by the agent's knowledge scope and RANKED against the task, so the prompt
  --     carries the passages that actually bear on the work rather than a category dump. Full-text
  --     ranking (SQL-side, deterministic); the semantic/vector half is added when the query-embed
  --     edge path is wired. Only consulted when a task is supplied, and bounded to a slice of budget.
  if v_q is not null then
    v_out := v_out || jsonb_build_object('field_corpus', coalesce((
        select jsonb_agg(jsonb_build_object('title', title, 'citation', citation,
                                            'category', category, 'content', left(content, 1200))
                         order by rank desc)
          from (select title, citation, category, content, ts_rank(fts, v_q) as rank
                  from kb_chunks
                 where (category = any(v_scope)
                        or (p_category_key is not null and category = p_category_key))
                   and fts @@ v_q
                 order by ts_rank(fts, v_q) desc, effective_date desc nulls last
                 limit 12) k), '[]'::jsonb));
  else
    v_out := v_out || jsonb_build_object('field_corpus', '[]'::jsonb);
  end if;

  -- 5. LIVE DATA BINDINGS — what the agent must fetch rather than remember. The binding is
  --    knowledge; the value is not, and is never cached here.
  v_out := v_out || jsonb_build_object('live_data_required', coalesce((
      select jsonb_agg(jsonb_build_object('record_id', record_id, 'title', title,
                                          'binding', structured_data))
        from ops_knowledge
       where record_type = 'live_data_binding' and runtime_eligible
         and supersession_state = 'current'
         and (scope_type = 'company' or dept_key = any(v_scope))
       limit 12), '[]'::jsonb));

  -- 6. TOOLS the agent is actually allowed to execute.
  v_out := v_out || jsonb_build_object('tools', coalesce((
      select jsonb_agg(jsonb_build_object('action_class', action_class, 'kind', kind,
                                          'risk_tier', risk_tier, 'reversible', reversible,
                                          'required_authority', required_authority,
                                          'notifies_human', notifies_human))
        from org_action_executor
       where active and (department = any(v_scope) or target = p_agent_key)
       limit 30), '[]'::jsonb));

  -- collect every knowledge id the assembly actually used
  select v_ids || coalesce(array_agg(x), '{}') into v_ids
    from (select jsonb_array_elements(coalesce(v_out->'company_core','[]'::jsonb) ||
                                      coalesce(v_out->'department_knowledge','[]'::jsonb) ||
                                      coalesce(v_out->'role_knowledge','[]'::jsonb) ||
                                      coalesce(v_out->'category_knowledge','[]'::jsonb)) ->> 'record_id' x) s;

  return jsonb_build_object(
    'identity', v_identity,
    'task_class', p_task_class,
    'category_key', p_category_key,
    'company_objective', coalesce((
      select jsonb_agg(jsonb_build_object('key', key, 'goal', goal, 'metric', metric,
                                          'target', target_value, 'unit', unit, 'period', period,
                                          'owner_dept', owner_dept, 'horizon', horizon))
        from (select * from company_goals
               where active
               order by (owner_dept is not distinct from v_agent.department) desc,
                        (category = 'Financial') desc, sort
               limit 8) g), '[]'::jsonb),
    'budget_chars', v_budget,
    'knowledge_ids', to_jsonb(v_ids),
    'knowledge_count', coalesce(array_length(v_ids, 1), 0),
    'assembled_at', now()
  ) || v_out;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_agent_handoff_inbox(p_agent_key text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select string_agg(line, E'\n' order by created_at)
  from (
    select a.created_at,
           -- Bound the WHOLE line, not its parts. Capping title and recommendation separately
           -- still left four employees over budget because the prefix varies ("from Document
           -- Controller" is longer than "doc_task"). 215 x 3 lines + 2 newlines = 647, inside the
           -- 678 this inbox was trimmed to after it timed agent_brain out twice.
           left(
           '- #'||a.id||' ('||extract(day from now() - a.created_at)::int||'d old, '
             ||case when a.kind = 'handoff'
                    then 'from '||coalesce(a.detail->>'from_name', a.detail->>'from', 'a colleague')
                    else a.kind end
             ||case when a.kind = any(fn_agent_inbox_closable_kinds()) then '' else ', FOUNDER DECIDES — do not close' end
             ||'): '
             -- The TITLE was never capped, only the recommendation. With handoffs only that was
             -- harmless; the wider kinds carry long generated titles and the block measured 821
             -- characters for `docs` and 769 for `it` — both ABOVE the 678 this inbox was trimmed
             -- to after it timed agent_brain out twice at ~56s. `it`'s prompt is 30,821 tokens and
             -- its one prior success took 53,139 ms, so the margin is real and small. Capped at 80
             -- so three lines cannot exceed roughly the budget that was proved safe.
             ||coalesce(a.title,'(untitled)')
             ||coalesce(' — '||a.recommendation, '')
           , 215) as line
      from agent_actions a
     where coalesce(public.fn_org_agent_resolve(a.agent), a.agent)
         = coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key)
       and a.status in ('pending','needs_review')
     order by a.created_at
     limit 3
  ) z;
$function$


CREATE OR REPLACE FUNCTION public.fn_agent_inbox_closable_kinds()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select array(
    select distinct kind from public.agent_actions
     where kind is not null
       and lower(kind) !~ '(refund|payout|charge|payment|transfer|chargeback)'
    union
    select unnest(array['handoff','improvement_question','knowledge_task','ai_improvement',
      'report_recommendation','ops_recommendation','doc_task','report_task','objective_step',
      'supply_health','autonomy_stall','legal_flag','security_incident','customer_escalation',
      'compliance_update','strategy_rec','marketing_recommendation','incident','prompt_approval',
      'decision.route_category','finance_alert','finance_marketing_budget'])
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_agent_institutional_memory(p_agent_key text, p_limit integer DEFAULT 6)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_dept text; v_cat text; out text := ''; r record;
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  if p_agent_key is null then return ''; end if;

  select department into v_dept from org_agents where agent_key = p_agent_key;
  if p_agent_key like 'cat:%' then v_cat := replace(p_agent_key, 'cat:', ''); end if;

  for r in
    select m.kind, m.headline, m.detail, m.outcome, m.money_aed, m.category_slug, m.confidence
    from institutional_memory m
    where (m.visible_to is null
           or array_length(m.visible_to,1) is null
           or 'all' = any(m.visible_to)
           or v_dept = any(m.visible_to)
           or p_agent_key = any(m.visible_to))
      and (m.category_slug is null or m.category_slug = v_cat)
      and coalesce(m.confidence, 1) >= 0.6
    order by coalesce(m.occurred_at, m.created_at) desc, coalesce(m.confidence,0) desc
    limit greatest(coalesce(p_limit,6), 1)
  loop
    out := out || '## lesson (' || coalesce(r.kind,'note') || ')' || E'\n'
        || coalesce(r.headline,'') || E'\n'
        || left(coalesce(r.detail,''), 600)
        || case when r.outcome is not null then E'\n' || 'What changed as a result: ' || left(r.outcome, 300) else '' end
        || case when coalesce(r.money_aed,0) <> 0 then ' (AED ' || r.money_aed || ' at stake)' else '' end
        || E'\n\n';
  end loop;

  return out;
end; $function$


CREATE OR REPLACE FUNCTION public.fn_agent_may_act(p_grantee_role_id text, p_action_class text, p_amount_aed numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare g record;
begin
  select * into g from public.ceo_standing_grant
   where grantee_role_id = p_grantee_role_id and action_class = p_action_class and active
     and (expires_at is null or expires_at > now())
   order by issued_at desc limit 1;

  if not found then
    -- NOT a founder question. The constitution is explicit that an uncovered action goes to the CEO.
    return jsonb_build_object('may_act', false, 'route', 'ceo_case_decision',
      'reason', format('No current standing grant covers %L for %L. This needs a scoped CEO decision -- not a founder approval, which does not exist.', p_action_class, p_grantee_role_id));
  end if;

  if g.max_amount_aed is not null and p_amount_aed is not null and p_amount_aed > g.max_amount_aed then
    return jsonb_build_object('may_act', false, 'route', 'ceo_case_decision',
      'reason', format('AED %s exceeds the standing limit of AED %s on %L.', p_amount_aed, g.max_amount_aed, g.grant_key));
  end if;

  return jsonb_build_object('may_act', true, 'grant', g.grant_key, 'scope', g.scope_note,
    'limit', g.limit_note);
end $function$


CREATE OR REPLACE FUNCTION public.fn_agent_silence_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n int:=0; f int:=0; g int:=0; nr int:=0; v_email text; v_run bigint;
begin
  insert into agent_runs(agent, started_at) values ('agent_silence_watch', clock_timestamp()) returning id into v_run;

  select to_email into v_email from notifications
   where type='founder_brief' and to_email is not null order by created_at desc limit 1;

  insert into cron_job_seen (jobid, jobname, schedule)
  select j.jobid, j.jobname, j.schedule from cron.job j where j.active
  on conflict (jobid) do update set last_seen = now(), jobname = excluded.jobname, schedule = excluded.schedule;

  -- Record successes BEFORE evaluating, so they survive the 14-day history prune.
  update cron_job_seen s
     set last_success = h.last_ok
    from (select jobid, max(start_time) as last_ok
            from cron.job_run_details where status='succeeded' group by jobid) h
   where h.jobid = s.jobid
     and (s.last_success is null or s.last_success < h.last_ok);

  for r in
    -- ONE AGGREGATE, NOT THREE CORRELATED SUBQUERIES PER JOB. This loop used to ask
    -- cron.job_run_details three separate questions for each of 165 active jobs against an 80 MB
    -- heap with no usable index, and on 11 Aug 2026 it began exceeding the statement timeout and
    -- stopped watching anything at all. A watchdog that dies silently is worse than no watchdog:
    -- fn_agent_silence_watch is the routine that would have reported its own absence.
    with h as (
      select jobid,
             count(*)                                                        as history_rows,
             max(start_time) filter (where status='succeeded')               as last_ok_live,
             count(*) filter (where status='failed'
                              and start_time > now() - interval '24 hours')  as fails_24h
        from cron.job_run_details
       group by jobid)
    select j.jobid, j.jobname,
           case when split_part(j.schedule,' ',5) <> '*' then 336
                when split_part(j.schedule,' ',3) <> '*' then 1440
                when split_part(j.schedule,' ',2) =  '*' then 6
                else 72 end as thresh_h,
           coalesce(h.history_rows, 0) as history_rows,
           greatest(h.last_ok_live, s.last_success) as last_ok,
           coalesce(h.fails_24h, 0) as fails_24h,
           s.first_seen,
           s.last_success as stored_ok
      from cron.job j
      left join h on h.jobid = j.jobid
      left join cron_job_seen s on s.jobid = j.jobid
     where j.active
  loop
    -- 9 SEP 2026 -- PHASE MACHINERY REMOVED, and this one loses a little accuracy, said plainly.
    -- The guard here read the kernel cron wrapper table (its wrapped_at column) as an ACTIVATION
    -- FLOOR: a job put back on today, whose last success predates the 16 Aug stand-down, is not
    -- silent. Without a floor this watch paged the founder about 15 such jobs in one day (3 Sep
    -- 2026). That table is deleted in this sweep and nothing else in the database records when a
    -- cron job was re-enabled, so the floor is rebuilt from the one durable fact this routine
    -- already keeps for itself: cron_job_seen.first_seen, the moment this watch first saw the job.
    -- It is the same floor the never-run branch below already applies.
    --
    -- WHAT THIS NO LONGER COVERS, so nobody is surprised in a year: a job registered long ago,
    -- disabled, then re-enabled today keeps its OLD first_seen, so it can page once as silent
    -- before its next success. Pages are deduped per silence episode (job, last_success), so that
    -- is one alert per such job, not a daily repeat. If it ever becomes noisy the fix is a
    -- re-activation column on cron_job_seen -- not a resurrected phase table.
    if r.first_seen is not null and r.first_seen > now() - (r.thresh_h||' hours')::interval then
      g := g + 1;
      continue;
    end if;
    -- Never-run: only when there is NO history AND we have never recorded a success.
    if r.history_rows = 0 and r.stored_ok is null then
      if r.first_seen is not null and r.first_seen < now() - (r.thresh_h||' hours')::interval then
        if not exists (select 1 from founder_alerts where event='cron_never_ran'
                        and detail like '%"'||r.jobname||'"%'
                        and created_at > now() - interval '24 hours') then
          insert into founder_alerts(level,event,detail,channel)
          values ('high','cron_never_ran', jsonb_build_object(
            'job', r.jobname,
            'first_seen', r.first_seen::text,
            'known_for_hours', round(extract(epoch from (now()-r.first_seen))/3600),
            'expected_within_hours', r.thresh_h)::text, 'email');
          -- 6 SEP 2026: routed to the IT operations engineer as one org_task per job, never emailed
          -- (founder_mail_policy.agent_silence); this watcher's own founder_alerts row above is its ledger.
          perform public.fn_founder_mail_route('agent_silence', 'Scheduled job has never run: '||r.jobname,
              'Job "'||r.jobname||'" is active but has no run history at all. It has been registered since '||
              r.first_seen::text||' and should have run at least every '||r.thresh_h||' hours. It is likely misregistered.', 'high');
          nr := nr + 1;
        end if;
      else
        g := g + 1;
      end if;
      continue;
    end if;

    if r.last_ok is null or r.last_ok < now() - (r.thresh_h||' hours')::interval then
      -- ONCE PER SILENCE EPISODE (3 Sep 2026): the episode is (job, last_success). It is paged the
      -- first time it is seen and never again until the job succeeds again — the 24-hour dedupe
      -- this replaced re-paged every silent job every day.
      if not exists (select 1 from founder_alerts where event='cron_silent'
                      and detail like '%"job": "'||r.jobname||'"%'
                      and detail like '%"last_success": "'||coalesce(r.last_ok::text,'no success on record')||'"%') then
        insert into founder_alerts(level,event,detail,channel)
        values ('high','cron_silent', jsonb_build_object(
          'job',r.jobname,'last_success',coalesce(r.last_ok::text,'no success on record'),
          'silent_hours',round(extract(epoch from (now()-r.last_ok))/3600),
          'expected_within_hours',r.thresh_h)::text,'email');
        perform public.fn_founder_mail_route('agent_silence', 'Scheduled job stopped: '||r.jobname,
            'Job "'||r.jobname||'" last succeeded '||coalesce(r.last_ok::text,'unknown')||
            '. Expected at least every '||r.thresh_h||' hours.', 'high');
        n := n + 1;
      end if;
    end if;

    if r.fails_24h > 0 then
      if not exists (select 1 from founder_alerts where event='cron_failing'
                      and detail like '%"'||r.jobname||'"%'
                      and created_at > now() - interval '24 hours') then
        insert into founder_alerts(level,event,detail,channel)
        values ('high','cron_failing',
          jsonb_build_object('job',r.jobname,'failures_24h',r.fails_24h,
                             'last_success',coalesce(r.last_ok::text,'unknown'))::text,'email');
        perform public.fn_founder_mail_route('agent_silence', 'Scheduled job failing: '||r.jobname,
            'Job "'||r.jobname||'" has failed '||r.fails_24h||' time(s) in the last 24 hours. Last success: '||
            coalesce(r.last_ok::text,'unknown')||'. Check cron.job_run_details for the error text.', 'high');
        f := f + 1;
      end if;
    end if;
  end loop;

  update agent_runs
     set finished_at=clock_timestamp(), status='ok',
         counts=jsonb_build_object('active_jobs',(select count(*) from cron.job where active),
                                   'in_grace',g,'silent',n,'failing',f,'never_ran',nr)
   where id=v_run;

  return jsonb_build_object('ran_at',now(),
    'active_jobs',(select count(*) from cron.job where active),
    'in_grace',g,'silent_alerts',n,'failing_alerts',f,'never_ran_alerts',nr);
exception when others then
  update agent_runs set finished_at=clock_timestamp(), status='error', note=left(sqlerrm,500) where id=v_run;
  raise;
end $function$


CREATE OR REPLACE FUNCTION public.fn_agent_tools(p_agent_key text, p_kind text DEFAULT NULL::text)
 RETURNS TABLE(tool_id text, purpose text, kind text, impl_kind text, impl_target text, input_schema jsonb, timeout_seconds integer, max_attempts integer, backoff text, failure_behaviour text, requires_current_data boolean, required_credential text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with me as (
    select a.agent_key, a.department,
           coalesce((select array_agg(i.packaged_role_id) from org_role_identity i
                      where i.agent_key = a.agent_key), '{}'::text[]) as role_ids
    from org_agents a
   where a.agent_key = coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key)
     and a.active
  )
  select t.tool_id, t.purpose, t.kind, t.impl_kind, t.impl_target,
         t.input_schema, t.timeout_seconds, t.max_attempts, t.backoff,
         t.failure_behaviour, t.requires_current_data, t.required_credential
  from agent_tool t, me
  where t.active
    and t.staging_available
    and (p_kind is null or t.kind = p_kind)
    and (t.authorised_departments = '{}'::text[]
         or '*' = any(t.authorised_departments)
         or me.department = any(t.authorised_departments))
    and (t.authorised_roles = '{}'::text[]
         or '*' = any(t.authorised_roles)
         or me.role_ids && t.authorised_roles)
  order by t.kind, t.tool_id;
$function$


CREATE OR REPLACE FUNCTION public.fn_agents_board()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare out jsonb;
begin
  with runs as (
    select agent, count(*) filter (where started_at > now() - interval '24 hours') as runs24,
           count(*) filter (where started_at > now() - interval '24 hours' and status in ('error','failed')) as fails24,
           max(started_at) as last_run, (array_agg(status order by started_at desc))[1] as last_status
    from agent_runs group by agent
  ), everyone as (
    select a.agent_key, coalesce(nullif(trim(a.department),''),'General') as department, a.role, a.kind, coalesce(a.active,true) as active,
      coalesce(r.runs24,0) as runs24, coalesce(r.fails24,0) as fails24, r.last_run, r.last_status
    from org_agents a left join runs r on r.agent = a.agent_key
  ), base as (select * from everyone where active),
  dc as (select department, count(*) c, sum(runs24) rs from base group by department)
  select jsonb_build_object(
    'total',(select count(*) from base),
    'parked_total',(select count(*) from everyone where not active),
    'runs24',(select coalesce(sum(runs24),0) from base),
    'departments',(select coalesce(jsonb_agg(jsonb_build_object('key',d.department,'label',d.department,'count',d.c,'runs',d.rs,
        'cards',(select jsonb_agg(jsonb_build_object('id',b.agent_key,'agent_key',b.agent_key,'role',b.role,'kind',b.kind,'active',b.active,'runs24',b.runs24,'fails24',b.fails24,'last_status',b.last_status,'last_run',b.last_run) order by b.runs24 desc, b.agent_key) from base b where b.department=d.department))
        order by d.rs desc nulls last, d.department),'[]'::jsonb) from dc d),
    'rows',(select coalesce(jsonb_agg(jsonb_build_object('id',b.agent_key,'agent_key',b.agent_key,'department',b.department,'role',b.role,'kind',b.kind,'active',b.active,'runs24',b.runs24,'fails24',b.fails24,'last_status',b.last_status,'last_run',b.last_run) order by b.runs24 desc, b.agent_key),'[]'::jsonb) from base b),
    -- Parked personas: greyed in the UI, labelled "parked", never "error". No run figures either —
    -- a persona that is not on the roster has no run rate, only a history.
    'parked',(select coalesce(jsonb_agg(jsonb_build_object('id',e.agent_key,'agent_key',e.agent_key,'department',e.department,'role',e.role,'kind',e.kind,'active',false,'runs24',0,'fails24',0,'last_status',null,'last_run',e.last_run) order by e.department, e.agent_key),'[]'::jsonb) from everyone e where not e.active)
  ) into out; return out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ai_confidence_prior(p_agent_key text, p_task_class text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- A CONSTANT IS NOT A MEASUREMENT, AND THIS IS THE GUARD THAT SAYS SO.
  -- The founder's own reading of the two existing emitters: "always emit exactly 1.000, which
  -- carries no information". A model that reports the same number every time would otherwise
  -- downgrade itself to a cheaper tier on the strength of its own unvarying optimism. stddev = 0
  -- over the window means the signal has no content, so it does not route anything. n >= 5 for the
  -- same reason at the other end: one confident answer is an anecdote.
  select case
           when count(*) >= 5 and coalesce(stddev_samp(confidence), 0) > 0
           then jsonb_build_object(
                  'prior', round(percentile_cont(0.5) within group (order by confidence)::numeric, 4),
                  'n', count(*),
                  'spread', round(stddev_samp(confidence)::numeric, 4))
           else null
         end
    from public.ai_cost_log
   where agent_key = coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key)
     and task_class = p_task_class
     and confidence is not null
     and occurred_at > now() - interval '14 days';
$function$


CREATE OR REPLACE FUNCTION public.fn_ai_cost_log_e2e_run_tag()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_tag text;
begin
  v_tag := coalesce(new.e2e_run_tag, public.fn_e2e_run_tag_current());
  if v_tag is not null and not coalesce(public.fn_e2e_run_tag_open(v_tag), false) then v_tag := null; end if;
  new.e2e_run_tag := v_tag;
  return new;
exception when others then
  new.e2e_run_tag := null;   -- the cost record is never lost to a malformed header
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ai_cost_log_releases_rehearsal_reservation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.e2e_run_tag is not null and new.model_used is distinct from 'none' and not coalesce(new.cached, false)
     and greatest(coalesce(new.cost_usd_reported, 0), coalesce(new.cost_aed, 0)) > 0 then
    delete from public.rehearsal_spend_reservation
     where id = (select id from public.rehearsal_spend_reservation
                  where e2e_run_tag = new.e2e_run_tag order by created_at limit 1);
  end if;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ai_quality_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_regs int:=0; v_spikes int:=0; v_detail jsonb; v_open int; v_owner text; v_t0 timestamptz := now();
begin
  -- ONE ROW PER AGENT PER NIGHT. Resolved to the canonical key here rather than left to the BEFORE
  -- INSERT trigger, because the trigger fires per row and therefore turns N raw agents into N rows
  -- that all claim the same identity. The rate is recomputed from the underlying counts, never
  -- averaged from the per-row percentages.
  insert into public.ai_quality_snapshots(agent, override_pct, actions_30d)
  select k.agent,
         round(100.0 * sum(v.rejected_30d)::numeric / nullif(sum(v.actions_30d), 0), 1),
         sum(v.actions_30d)::int
    from public.v_ai_agent_health v
    cross join lateral (select case
             when exists (select 1 from public.org_agents o where o.agent_key = v.agent and o.active)
               then v.agent
             else coalesce(public.fn_org_agent_resolve(v.agent), v.agent)
           end as agent) k
   where v.override_pct is not null
   group by k.agent
  having sum(v.actions_30d) > 0;

  with ranked as (
    select prompt_key, score, created_at,
           row_number() over(partition by prompt_key order by created_at desc) rn
    from public.prompt_eval_runs
  ),
  reg as (
    select c.prompt_key, c.score cur, p.score prev
    from ranked c join ranked p on p.prompt_key=c.prompt_key and p.rn=2
    where c.rn=1 and (c.score < p.score - 5 or c.score < 70)
  ),
  ins as (
    insert into public.security_events(kind,severity,source,subject,detail)
    select 'eval_regression', case when cur<70 then 'high' else 'medium' end, 'ai_quality_watch', prompt_key,
           jsonb_build_object('current',cur,'previous',prev)
    from reg returning 1
  )
  select count(*) into v_regs from ins;

  with cur as (
    -- Same resolution rule as the insert above, so `cur` and `hist` speak one vocabulary. Before
    -- this, 17 of 52 agents carried a raw name here and a canonical one in the snapshot, and the
    -- join below could not match them at all.
    select k.agent,
           round(100.0 * sum(v.rejected_30d)::numeric / nullif(sum(v.actions_30d), 0), 1) as override_pct,
           sum(v.actions_30d)::int as actions_30d
      from public.v_ai_agent_health v
      cross join lateral (select case
               when exists (select 1 from public.org_agents o where o.agent_key = v.agent and o.active)
                 then v.agent
               else coalesce(public.fn_org_agent_resolve(v.agent), v.agent)
             end as agent) k
     where v.override_pct is not null
     group by k.agent
    having sum(v.actions_30d) >= 5
       and k.agent not in ('security','onboarding','email')
  ),
  hist as (
    -- Weighted by actions, not a flat mean of percentages: the historical rows still contain the
    -- pre-fix duplicates, and a flat avg lets an agent with one action in a month move the trailing
    -- average as much as one with a hundred and sixty.
    select agent,
           sum(override_pct * greatest(actions_30d, 1))::numeric / nullif(sum(greatest(actions_30d, 1)), 0) as avg_prev,
           count(*) n
    from public.ai_quality_snapshots where at < now()-interval '12 hours' group by agent
  ),
  spike as (
    select c.agent, c.override_pct, round(h.avg_prev,1) avg_prev
    from cur c join hist h on h.agent=c.agent
    where h.n>=1 and c.override_pct > coalesce(h.avg_prev,0)+20
  ),
  ins2 as (
    insert into public.security_events(kind,severity,source,subject,detail)
    select 'override_spike','medium','ai_quality_watch', agent,
           jsonb_build_object('override_pct',override_pct,'trailing_avg',avg_prev)
    from spike returning 1
  )
  select count(*) into v_spikes from ins2;

  v_detail := jsonb_build_object('eval_regressions',v_regs,'override_spikes',v_spikes);

  -- Added 10 Aug 2026: this routine has detected quality falling since it was written and never
  -- emitted an event, so nothing downstream could react to it.
  if v_regs + v_spikes > 0 then
    perform fn_emit('ai.confidence_dropped',
                    case when se.kind='eval_regression' then 'prompt' else 'agent' end,
                    se.subject, 'ai_quality_watch',
                    se.detail || jsonb_build_object('finding', se.kind, 'severity', se.severity))
       from public.security_events se
      where se.source='ai_quality_watch' and se.kind in ('eval_regression','override_spike')
        and se.created_at >= v_t0;
  end if;

  if v_regs+v_spikes > 0 then
    select count(*) into v_open from public.agent_actions
      where kind='ai_quality_alert' and coalesce(status,'') in ('pending','needs_review')
        and created_at > now()-interval '24 hours';
    if v_open = 0 then
      insert into public.agent_actions(agent,kind,status,risk,title,recommendation,target_table,detail)
      values('ai_trainer','ai_quality_alert','pending','medium',
        'AI quality alert: '||v_regs||' eval regression(s), '||v_spikes||' override spike(s)',
        'Open the AI Observability dashboard and review security_events of kind eval_regression / override_spike. Consider rolling back the regressed prompt version, or investigating why a human-facing agent''s suggestions are being rejected.',
        'security_events', v_detail);
      select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner
        from public.app_secrets where key='admin_emails';
      insert into public.notifications(type,to_email,to_role,channel,subject,body,status)
      values('ai_quality_alert', v_owner,'admin','email','QuotesDone: AI quality alert',
        'The AI quality watch flagged '||v_regs||' eval regression(s) and '||v_spikes||' override spike(s). Open the AI Observability dashboard and check security_events (kind eval_regression / override_spike).','queued');
    end if;
  end if;
  return v_detail;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_ai_route(p_task_class text DEFAULT NULL::text, p_dept_key text DEFAULT NULL::text, p_confidence numeric DEFAULT NULL::numeric, p_fn text DEFAULT NULL::text, p_escalate boolean DEFAULT false, p_require_caps text[] DEFAULT NULL::text[], p_agent_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_class   text;
  v_src     text;
  v_pol     model_policy%rowtype;
  v_reg     model_registry%rowtype;
  v_fb      model_registry%rowtype;
  v_bud     department_budget%rowtype;
  v_pct     numeric := 0;
  v_model   text;
  v_why     text;
  v_min     numeric;
  v_tier    text;
  v_vis     boolean := 'vision' = any(coalesce(p_require_caps, '{}'::text[]));
  v_aud     boolean := 'audio'  = any(coalesce(p_require_caps, '{}'::text[]));
  v_tls     boolean := 'tools'  = any(coalesce(p_require_caps, '{}'::text[]));
  v_sub     model_registry%rowtype;
  v_want    int;
  v_idp     model_policy_by_identity%rowtype;
  v_generic boolean := false;
  v_rt      jsonb;
  v_prior   jsonb;
  v_conf    numeric;
  v_rtier   text;
  v_canon   text;
  v_seat    text;
  v_split   text;
  v_route_base text;
  v_base_pol model_policy%rowtype;
  v_seat_fb text; v_seat_p text;
begin
  if p_task_class is not null and length(btrim(p_task_class)) > 0 then
    v_class := p_task_class; v_src := 'caller-supplied task_class';
  else
    select task_class into v_class from fn_task_class where fn = p_fn and active;
    if v_class is not null then
      v_src := 'classified from calling function "' || p_fn || '"';
    else
      v_class := 'general_drafting';
      v_generic := true;
      v_src := 'UNMAPPED function "' || coalesce(p_fn,'?') || '" - defaulted to general_drafting (medium). Add a fn_task_class row to route this properly.';
    end if;
  end if;

  -- THE PACK'S FOUR-ROLE TAXONOMY REACHES THE PATH IT WAS WRITTEN FOR (14 Aug 2026).
  --
  -- All 93 employees carry org_agents.routing_tier - director 36, operations_specialist 23,
  -- analyst_controller 21, reviewer_auditor 10 - and on the main employee path it was DEAD.
  -- fn_routing_tier_model below only fires when v_generic is true, i.e. when the calling function
  -- is unmapped; agent_brain IS mapped, to agent_reasoning, so every employee from a marketing
  -- copywriter to the CEO got the same blanket large tier.
  --
  -- Meanwhile model_policy carries routine_employee_reasoning at MEDIUM, and its own rationale
  -- says: "Pack: replaces the current blanket large-tier agent_reasoning. agent_reasoning is LIVE
  -- on anthropic/claude-sonnet-5 and agent_brain is ~93% of OpenRouter spend." It had ZERO callers.
  -- A policy written to replace something, that nothing points at, is a build order nobody wired.
  --
  -- This is a ROUTING decision taken from the role, not an override of task_class routing: the
  -- class is chosen by who is asking, then the policy for that class applies normally.
  --
  -- WHO STAYS ON LARGE, AND WHY. Only operations_specialist moves. reviewer_auditor stays large
  -- deliberately - all 24 Reviewer/Auditor rows in the pack name a large model, and a reviewer on
  -- the cheap model is a green check that means nothing. director and analyst_controller stay
  -- because their work is the consequential kind the large tier exists for.
  if v_class = 'agent_reasoning' and p_agent_key is not null then
    v_canon := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
    select a.routing_tier into v_rtier from org_agents a
     where a.agent_key = v_canon and a.active;
    if v_rtier = 'operations_specialist'
       and exists (select 1 from model_policy mp
                    where mp.task_class = 'routine_employee_reasoning' and mp.active) then
      v_class := 'routine_employee_reasoning';
      v_src := v_src || ' | routing_tier "operations_specialist" for "' || v_canon
                     || '" selected the routine employee class instead of the blanket large tier';
    end if;
  end if;

  -- THE SEAT'S OWN ROUTE (29 Sep 2026, sales_engineer; founder_instruction 1056).
  -- think() and every other shared engine bill a step to a class chosen by WHAT the step is
  -- (routine_employee_reasoning, customer_communication, ...). The founder's matrix routes by WHO asks. Matrix v2
  -- (5 Oct 2026): every seat runs openai/gpt-6-luna with google/gemini-3.8-flash as its plan B, and the CEO's
  -- hard work and the comparison report run on Opus with luna behind. The seat is the caller's agent,
  -- resolved as the agent_reasoning block above resolves it (an alias of a seat is that seat).
  --   1. A policy row named '<seat>__<class>' is that seat's own route for <class>: its MODELS are taken, while
  --      the CLASS stays <class> - ai_cost_log, the response cache, the confidence prior and every author proof
  --      key on it, and ai_cost_log.seat already says who asked. The row travels as policy_class, which
  --      fn_ai_route_review_for reads for a review's pair.
  --   2. Otherwise the seat's PLAN B is its own for every class it calls: the fallback of its catch-all row in
  --      model_policy_by_identity replaces the class's, unless the class has no fallback on purpose (only Gemini
  --      hears) or is a review (its pair is chosen against its author's family). Since matrix v2 only on a class
  --      that runs on the seat's own primary: an Opus class keeps luna behind it.
  -- A '<seat>__<class>' row - reached through the seat, or named by fn_task_class for the seat's own function -
  -- never allows fewer tokens than <class>. A seat's own row is never served from the semantic cache: that cache is keyed
  -- by class, not model, so a CEO judgement on Opus could otherwise be answered by another seat's Gemini answer.
  if p_agent_key is not null then
    v_seat := coalesce(v_canon, public.fn_org_agent_resolve(p_agent_key), p_agent_key);
    select mp.task_class into v_split from model_policy mp
     where mp.task_class = v_seat || '__' || v_class and mp.active;
    if v_split is not null then
      v_src := v_src || ' | seat "' || v_seat || '" routes "' || v_class || '" on its own policy row ' || v_split;
    end if;
  end if;

  select * into v_pol from model_policy where task_class = coalesce(v_split, v_class) and active;
  if not found then
    select * into v_pol from model_policy where task_class = 'general_drafting' and active;
    v_src := v_src || ' | no policy for "' || v_class || '", fell back to general_drafting';
    v_generic := true;
  end if;

  v_route_base := case when v_split is not null then v_class
                       when position('__' in v_pol.task_class) > 0 then split_part(v_pol.task_class, '__', 2) end;
  if v_route_base is not null then
    select * into v_base_pol from model_policy where task_class = v_route_base and active;
    if found then
      v_pol.max_tokens    := greatest(coalesce(v_pol.max_tokens, 0), coalesce(v_base_pol.max_tokens, 0));
      v_pol.cache_ttl_min := 0;
    end if;
  end if;

  if v_split is null and not v_generic and v_seat is not null and v_pol.model_fallback is not null
     and cardinality(coalesce(v_pol.reviews_class, '{}')) = 0 then
    select i.fallback_model, i.primary_model into v_seat_fb, v_seat_p from model_policy_by_identity i
     where i.scope = 'current_agent' and i.identity_key = v_seat
       and exists (select 1 from org_role o where o.role_id = v_seat and o.status = 'active');  -- a live seat's row only
    if v_seat_fb is not null and v_seat_fb not in (v_pol.model_primary, v_pol.model_fallback)
       and v_pol.model_primary is not distinct from v_seat_p then  -- matrix v2: only on the seat's own routine model
      v_src := v_src || ' | seat "' || v_seat || '" falls back to its own plan B ' || v_seat_fb
                     || ' instead of ' || v_pol.model_fallback;
      v_pol.model_fallback := v_seat_fb;
    end if;
  end if;

  -- THE ROLE DEFAULT. model_policy_by_identity carries 120 rows — 96 target employees and 24
  -- current production agents — and had NO reader in the database at all. The pack states its own
  -- precedence on every row: note = 'Role default only; task_class routing overrides it.' So it
  -- applies only where the caller would otherwise get the generic general_drafting fallback:
  -- either the named class has no policy, or the calling function is unmapped in fn_task_class.
  --
  -- v_generic exists because the first version of this branch was UNREACHABLE. It hung off
  -- `if not found` on the model_policy lookup, and an unmapped function has already had v_class
  -- rewritten to 'general_drafting' by then — which IS found. Measured: fn_ai_route(...,'ceo')
  -- returned identity_policy null. Same shape as the unreachable block in
  -- fn_kb_route_activation_blocked found earlier today: a branch guarded by a condition that
  -- cannot occur.
  --
  -- 23 of the 24 current_agent keys resolve to a real org_agents row; 'cat:*' covers the
  -- category desks.
  if v_generic and p_agent_key is not null then
    select * into v_idp from model_policy_by_identity
     where scope = 'current_agent'
       and (identity_key = p_agent_key
            or (identity_key = 'cat:*' and p_agent_key like 'cat:%'))
     order by (identity_key = p_agent_key) desc
     limit 1;
    if found and v_idp.primary_model is not null then
      v_pol.model_primary  := v_idp.primary_model;
      v_pol.model_fallback := coalesce(v_idp.fallback_model, v_pol.model_fallback);
      v_pol.max_tokens     := coalesce(v_idp.max_output_tokens, v_pol.max_tokens);
      v_src := v_src || ' | role default for "' || p_agent_key || '" applied from model_policy_by_identity';
    end if;
  end if;

  -- ---- ROUTING TIER, added 11 Aug 2026 ---------------------------------------------------------
  -- The pack's four-role taxonomy carried onto the 93 real employees as org_agents.routing_tier.
  -- Fires LAST and only if the pack had nothing to say about this specific agent, so an explicit
  -- current_agent row always wins. Resolves tier -> registry tier -> cheapest active approved model
  -- AT CALL TIME: no model id is stored anywhere, so this follows the fleet instead of going stale.
  -- Measured direction against the general_drafting default (haiku, 1.00 USD/Mtok in):
  -- operations_specialist 4x cheaper, analyst/director unchanged, reviewer_auditor 2x dearer and
  -- deliberately so - all 24 Reviewer/Auditor rows in the pack name sonnet-5, and a reviewer on the
  -- cheap model is a green check that means nothing.
  if v_generic and p_agent_key is not null and v_idp.identity_key is null then
    v_rt := public.fn_routing_tier_model(p_agent_key);
    -- 18 Oct 2026 (ledger 1240/1241): the routing tier may only pick inside the class's own pair.
    if v_rt is not null and (v_rt->>'model') is not null and (v_rt->>'model') in (v_pol.model_primary, v_pol.model_fallback) then
      v_pol.model_primary := v_rt->>'model';
      v_pol.tier          := v_rt->>'registry_tier';
      v_src := v_src || ' | routing_tier "' || (v_rt->>'routing_tier') || '" for "' || p_agent_key
                     || '" resolved to ' || (v_rt->>'model') || ' (' || (v_rt->>'registry_tier') || ' tier)';
    end if;
  end if;
  -- ----------------------------------------------------------------------------------------------

  if v_pol.tier = 'none' then
    return jsonb_build_object(
      'use_llm', false, 'task_class', v_class, 'tier', 'none',
      'why', 'REFUSED. ' || coalesce(v_pol.deterministic_alternative, 'This is deterministic - use code.')
             || ' [' || v_src || ']',
      'deterministic_alternative', v_pol.deterministic_alternative);
  end if;

  v_tier  := v_pol.tier;
  v_model := v_pol.model_primary;
  v_why   := coalesce(v_pol.rationale, 'policy for ' || v_class) || ' [' || v_src || ']';

  if p_escalate then
    v_model := coalesce(v_pol.model_fallback, v_model);
    v_why   := v_why || ' | ESCALATED one tier after an unsatisfactory cheaper attempt';
  end if;

  select (value #>> '{}')::numeric into v_min from decision_policy where key = 'confidence_min';
  -- THE PRIOR, 11 Aug 2026. Both arms below are original and NEITHER HAS EVER FIRED, because
  -- p_confidence is the confidence of THIS call and no caller can know that before the call.
  -- Measured the day this was written: 7 of 1,746 model calls in seven days carried a confidence at
  -- all. The only confidence that CAN exist beforehand is the agent's own recent record on this
  -- task class, so that is what a caller supplying nothing now routes on.
  --
  -- fn_ai_confidence_prior returns null unless there are at least 5 observations AND they vary.
  -- The variance guard is the important half: the two callers that emitted a confidence before
  -- tonight always emitted exactly 1.0000, and a model reporting the same number every time would
  -- otherwise downgrade itself to a cheaper tier on the strength of its own unvarying optimism.
  v_conf := p_confidence;
  if v_conf is null and p_agent_key is not null then
    v_prior := public.fn_ai_confidence_prior(p_agent_key, v_class);
    if v_prior is not null then v_conf := (v_prior->>'prior')::numeric; end if;
  end if;

  if v_conf is not null then
    -- 1056: 'xlarge' is only the founder's named hard routes (the CEO's judgement, the comparison report, on
    -- Opus); a confidence prior never moves them. 'large' keeps the 11 Aug doctrine.
    if v_conf >= 0.95 and v_tier = 'large' then
      -- 18 Oct 2026 (ledger 1240/1241): the cheapest MEDIUM row of the whole registry was Gemini, which may only hear.
      -- A downgrade now stays inside the class's own pair; with no medium model there, the class keeps its primary.
      v_model := coalesce((select model_id from model_registry
       where active and approved and tier = 'medium' and model_id in (v_pol.model_primary, v_pol.model_fallback) order by in_per_mtok_usd, model_id limit 1), v_model);
      v_why := v_why || ' | confidence ' || v_conf
               || case when v_prior is null then ''
                       else ' (' || p_agent_key || ' own median over ' || (v_prior->>'n')
                            || ' calls on ' || v_class || ', spread ' || (v_prior->>'spread') || ')' end
               || ' >= 0.95, downgraded to medium - no second opinion needed';
    elsif v_min is not null and v_conf < v_min and v_tier = 'small' then
      v_model := coalesce(v_pol.model_fallback, v_model);
      v_why := v_why || ' | confidence ' || v_conf
               || case when v_prior is null then ''
                       else ' (' || p_agent_key || ' own median over ' || (v_prior->>'n') || ' calls)' end
               || ' below floor ' || v_min || ', escalated a tier';
    end if;
  end if;

  -- (Historical, 13 Aug 2026: the halt that used to follow needed a department.) A CALL WITH NO DEPARTMENT: the lookup below needs a
  -- dept_key to find a budget, and 59 of this month's calls arrived without one - inquiry_intake,
  -- drawing_boq, doc_extract, license_extract, supplier_onboard and eleven more, i.e. the demand
  -- path. fn_task_class already maps fn -> task_class for this same function's model choice; it now
  -- carries the owning department too, so an un-attributed call is attributed by what it IS rather
  -- than left outside every ceiling. An explicit p_dept_key from the caller still wins.
  -- CANONICAL BEFORE THE CEILING (14 Aug 2026). department_budget holds the ten canonical rows;
  -- a caller passing a merged-away key ('procurement', 'marketing', 'sales' ...) found NO budget
  -- row and skipped the ceiling entirely. fn_dept_canonical resolves the key the caller used to
  -- the department that actually owns it.
  if public.fn_dept_canonical(coalesce(p_dept_key, (select t.dept_key from fn_task_class t where t.fn = p_fn and t.active))) is not null then
    select * into v_bud from department_budget
     where dept_key = public.fn_dept_canonical(coalesce(p_dept_key, (select t.dept_key from fn_task_class t where t.fn = p_fn and t.active)));
    if found and v_bud.monthly_aed > 0 then
      v_pct := round(100 * coalesce(
        (select sum(cost_aed) from ai_cost_log
          where dept_key = any(public.fn_dept_scope(v_bud.dept_key))
            and occurred_at >= date_trunc('month', now())), 0)
        / v_bud.monthly_aed, 2);
      -- NO HALT AND NO DEGRADE (24 Sep 2026, founder_instruction 987: no caps on LLM spend). v_pct is still
      -- reported as budget_pct so the books can see a department's spend; it no longer refuses or downgrades a call.
    end if;
  end if;

  select * into v_reg from model_registry where model_id = v_model and active;
  if not found then
    select * into v_reg from model_registry
     where active and approved and model_id in (v_pol.model_primary, v_pol.model_fallback)   -- 18 Oct 2026: the class's own pair, never the cheapest of the registry
     order by (model_id = v_pol.model_fallback) desc, in_per_mtok_usd, model_id limit 1;
    v_why := v_why || ' | WARNING: policy model "' || v_model || '" is not in model_registry; substituted ' || coalesce(v_reg.model_id,'(none)');
    v_model := v_reg.model_id;
  end if;

  -- CAPABILITY. Price and tier chose the model above; if it cannot see, hear or call tools the
  -- provider will simply reject the payload. Substitute the nearest capable model, preferring the
  -- intended tier, then the closest tier ABOVE it, and only then below - a capability substitution
  -- must never quietly become a quality downgrade.
  v_want := fn_ai_route_tier_rank(v_tier);
  if (v_vis or v_aud or v_tls)
     and not ( (not v_vis or coalesce(v_reg.supports_vision,false))
           and (not v_aud or coalesce(v_reg.supports_audio, false))
           and (not v_tls or coalesce(v_reg.supports_tools, false)) ) then

    select * into v_sub from model_registry
     where active and approved and model_id not like '%:online'      -- 1056: never a web-grounded variant
       and (not v_vis or supports_vision) and (not v_aud or supports_audio) and (not v_tls or supports_tools)
       and (model_id in (v_pol.model_primary, v_pol.model_fallback) or (v_aud and supports_audio))   -- 18 Oct 2026 (ledger 1241): own pair; only a recording reaches the model that hears
     order by (fn_ai_route_tier_rank(tier) < v_want),                 -- at-or-above the tier first
              abs(fn_ai_route_tier_rank(tier) - v_want),              -- then closest to it
              in_per_mtok_usd, model_id                                -- then cheapest (model_id: 1056 tie-break)
     limit 1;

    if found then
      v_why := v_why || ' | CAPABILITY OVERRIDE: ' || v_model || ' cannot do ('
               || array_to_string(coalesce(p_require_caps,'{}'::text[]), '+') || '); substituted ' || v_sub.model_id
               || ' (' || v_sub.tier || ' tier, intended ' || v_tier || ')';
      v_reg := v_sub; v_model := v_sub.model_id;
    else
      return jsonb_build_object(
        'use_llm', false, 'task_class', v_class, 'tier', v_tier, 'caps', to_jsonb(p_require_caps),
        'why', 'REFUSED. No active approved model in model_registry supports ('
               || array_to_string(coalesce(p_require_caps,'{}'::text[]), '+')
               || '). Add one, or mark the capability on an existing model.');
    end if;
  end if;

  select * into v_fb from model_registry
   where model_id = v_pol.model_fallback and active
     and (not v_vis or supports_vision) and (not v_aud or supports_audio) and (not v_tls or supports_tools);
  if not found and (v_vis or v_aud or v_tls) then
    select * into v_fb from model_registry
     where active and approved and model_id <> v_model and model_id not like '%:online'   -- 1056
       and (not v_vis or supports_vision) and (not v_aud or supports_audio) and (not v_tls or supports_tools)
       and (model_id in (v_pol.model_primary, v_pol.model_fallback) or (v_aud and supports_audio))   -- 18 Oct 2026 (ledger 1241)
     order by (fn_ai_route_tier_rank(tier) < v_want), abs(fn_ai_route_tier_rank(tier) - v_want), in_per_mtok_usd, model_id
     limit 1;
  end if;

  return jsonb_build_object(
    'use_llm', true,
    'task_class', v_class,
    'policy_class', v_pol.task_class,   -- 1056: the policy row the models came from (a seat's own, or the class's)
    'tier', v_tier,
    'model', v_model,
    'fallback', v_fb.model_id,
    'max_tokens', v_pol.max_tokens,
    'cache_ttl_min', coalesce(v_pol.cache_ttl_min, 0),
    'cache', coalesce(v_reg.supports_cache, false),
    'stream', coalesce(v_reg.supports_streaming, true),
    'caps', to_jsonb(coalesce(p_require_caps, '{}'::text[])),
    'in_per_mtok_usd', v_reg.in_per_mtok_usd,
    'out_per_mtok_usd', v_reg.out_per_mtok_usd,
    'cache_read_per_mtok_usd', v_reg.cache_read_per_mtok_usd,
    'budget_pct', v_pct,
    'identity_policy', case when v_idp.identity_key is null then null else jsonb_build_object(
        'identity_key', v_idp.identity_key, 'deterministic_first', v_idp.deterministic_first,
        'reasoning_effort', v_idp.reasoning_effort, 'authority_tier', v_idp.authority_tier) end,
    'routing_tier', v_rt,
    'confidence_prior', v_prior,
    'confidence_used', v_conf,
    'why', v_why);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ai_route_review(p_task_class text, p_counterpart_model text, p_agent_key text DEFAULT NULL::text, p_fn text DEFAULT NULL::text, p_dept_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.fn_ai_route_review_for(p_task_class, p_counterpart_model, p_agent_key, p_fn, p_dept_key, null);
$function$


CREATE OR REPLACE FUNCTION public.fn_ai_route_review_for(p_task_class text, p_counterpart_model text, p_agent_key text DEFAULT NULL::text, p_fn text DEFAULT NULL::text, p_dept_key text DEFAULT NULL::text, p_require_caps text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_names text[]; v_fams text[] := '{}'; v_unknown text[] := '{}'; v_n text; v_f text; v_cp text;
  v_base jsonb; v_rej jsonb := '[]'::jsonb;
  v_pick text; v_pick_fam text; v_fb text; v_tier text;
  v_vis boolean := 'vision' = any (coalesce(p_require_caps, '{}'));
  v_aud boolean := 'audio'  = any (coalesce(p_require_caps, '{}'));
  v_tls boolean := 'tools'  = any (coalesce(p_require_caps, '{}'));
  c record;
begin
  select coalesce(array_agg(distinct btrim(x) order by btrim(x)) filter (where btrim(x) <> ''), '{}') into v_names
    from unnest(string_to_array(coalesce(p_counterpart_model, ''), ',')) x;
  v_cp := array_to_string(v_names, ',');
  foreach v_n in array v_names loop
    continue when v_n = 'deterministic';
    select lower(btrim(r.provider)) into v_f from public.model_registry r where r.model_id = v_n;
    if v_f is null then v_unknown := v_unknown || v_n; else v_fams := array(select distinct unnest(v_fams || v_f)); end if;
  end loop;

  if cardinality(v_names) = 0 or cardinality(v_unknown) > 0 then
    return jsonb_build_object('use_llm', false, 'no_independent_reviewer', true, 'unknown_author', true,
      'task_class', p_task_class, 'author_model', v_cp,
      'why', 'AUTHOR UNKNOWN: ' || coalesce(nullif(array_to_string(v_unknown, ', '), ''), '(none given)')
             || ' is not in model_registry, so its family is unknown and independence cannot be proved. A data defect in '
             || 'what the caller recorded about the author, not a missing reviewer.');
  end if;

  v_base := public.fn_ai_route(p_task_class, p_dept_key, null, p_fn, false, p_require_caps, p_agent_key);
  if not coalesce((v_base->>'use_llm')::boolean, false) then
    return v_base || jsonb_build_object('author_model', v_cp, 'author_family', to_jsonb(v_fams));
  end if;
  if cardinality(v_fams) = 0 then
    return v_base || jsonb_build_object('author_model', 'deterministic', 'author_family', '[]'::jsonb, 'independent', true,
      'reviewer_tier', 'standard', 'why', coalesce(v_base->>'why', '') || ' | INDEPENDENT REVIEW: the author is deterministic code, not a model');
  end if;

  for c in
    -- 1056: the pair of the seat's own row for this review class when the seat has one ('<seat>__<class>'),
    -- otherwise the class's own - never the general_drafting row a missing class falls back to
    with pol as (select model_primary, model_fallback from public.model_policy
                  where task_class = case when right(coalesce(v_base->>'policy_class', ''), length(v_base->>'task_class') + 2)
                                                = '__' || (v_base->>'task_class')
                                          then v_base->>'policy_class' else v_base->>'task_class' end),
    cand as (
      -- 1056: the class's own pair first (primary, then its named fallback), then the pool as depth
      select pol.model_primary model_id, 0 ord from pol
      union all select pol.model_fallback, 1 from pol
      union all select p.model_id, 10 + p.rank from public.review_pool p where p.active
      -- 1068 (30 Sep 2026): the last-resort families are the matrix's live ones. 5 Oct 2026 (matrix v2): the two retired
      -- models leave the list; Gemini first, then luna, Opus last.
      -- 18 Oct 2026 (ledger 1240/1241, matrix v3): Gemini only hears, so it is a last resort only for a review that
      -- must hear; GPT-6 Luna Pro replaces luna (ruling 1218), Sonnet 5.5 and Opus are the Anthropic families.
      union all select 'anthropic/claude-sonnet-5.5', 2000000
      union all select 'openai/gpt-6-luna-pro', 2000001
      union all select 'anthropic/claude-opus-5.5', 2000002
      union all select 'google/gemini-3.8-flash', 2000003 where v_aud)
    select d.model_id, d.ord, lower(btrim(r.provider)) provider, coalesce(r.active and r.approved, false) reg_ok,
           (not v_vis or coalesce(r.supports_vision, false)) and (not v_aud or coalesce(r.supports_audio, false))
             and (not v_tls or coalesce(r.supports_tools, false)) caps_ok,
           h.model_id is not null measured,
           coalesce(h.open_until > now() and h.opened_class is not null, false) tripped
      from (select model_id, min(ord) ord from cand where model_id is not null and model_id <> 'none' group by model_id) d
      left join public.model_registry r on r.model_id = d.model_id
      left join public.llm_route_health h on h.model_id = d.model_id
     order by d.ord, d.model_id
  loop
    if c.provider is null then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'not in model_registry');
    elsif c.provider = any (v_fams) then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'same family as an author (' || c.provider || ')');
    elsif not c.reg_ok then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'inactive or unapproved in model_registry');
    elsif not c.caps_ok then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'lacks a required capability (' || array_to_string(p_require_caps, '+') || ')');
    elsif not c.measured then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'no llm_route_health row: unmeasured is not healthy');
    elsif c.tripped then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'breaker tripped by real failures');
    elsif v_pick is null then
      v_pick := c.model_id; v_pick_fam := c.provider;
      v_tier := case when c.ord >= 2000000 then 'third_family_fallback' else 'standard' end;
    elsif v_fb is null and (c.ord < 2000000 or v_tier = 'third_family_fallback') then
      v_fb := c.model_id;
    end if;
  end loop;

  if v_pick is null then
    return jsonb_build_object('use_llm', false, 'no_independent_reviewer', true,
      'task_class', v_base->>'task_class', 'author_model', v_cp, 'author_family', to_jsonb(v_fams), 'pool_rejected', v_rej,
      'why', 'NO INDEPENDENT REVIEWER: no active, healthy, capable candidate outside the ' || array_to_string(v_fams, '/')
             || ' families, not even a last-resort family. The review is HELD, never run on an author''s family.');
  end if;

  return v_base || jsonb_build_object(
    'model', v_pick, 'fallback', v_fb,
    'in_per_mtok_usd', (select in_per_mtok_usd from public.model_registry where model_id = v_pick),
    'out_per_mtok_usd', (select out_per_mtok_usd from public.model_registry where model_id = v_pick),
    'reviewer_family', v_pick_fam, 'reviewer_tier', v_tier, 'author_model', v_cp, 'author_family', to_jsonb(v_fams),
    'independent', true, 'pool_rejected', v_rej,
    'why', coalesce(v_base->>'why', '') || ' | INDEPENDENT REVIEW: author wrote on ' || v_cp
           || ' (' || array_to_string(v_fams, '/') || '), reviewer routed to ' || v_pick || ' (' || v_pick_fam || ')'
           || coalesce(', fallback ' || v_fb, ', no fallback outside ' || array_to_string(v_fams, '/')));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ai_route_tier_rank(p_tier text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$ select case p_tier when 'small' then 1 when 'medium' then 2 when 'large' then 3 when 'xlarge' then 4 else 0 end $function$


CREATE OR REPLACE FUNCTION public.fn_ai_subject_is_fixture(p_subject jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_uuid  constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_harness constant text := '^qd-([a-z0-9]+)-[^@]*@example[.](invalid|com|net|org)$';
  v_inq  text := nullif(btrim(coalesce(p_subject ->> 'inquiry_id', '')), '');
  v_cust text := nullif(btrim(coalesce(p_subject ->> 'customer_id', '')), '');
  v_sup  text := nullif(btrim(coalesce(p_subject ->> 'supplier_id', '')), '');
  v_emails text[] := array[]::text[];
  v_e text; v_tag text;
begin
  if nullif(btrim(coalesce(p_subject ->> 'email', '')), '') is not null then
    v_emails := v_emails || lower(btrim(p_subject ->> 'email'));
  end if;
  if v_inq ~ v_uuid then
    v_emails := v_emails || array(select lower(btrim(c.email)) from public.inquiries i
                                   join public.customers c on c.id = i.customer_id
                                  where i.id = v_inq::uuid and c.email is not null);
  end if;
  if v_cust ~ v_uuid then
    v_emails := v_emails || array(select lower(btrim(c.email)) from public.customers c where c.id = v_cust::uuid and c.email is not null);
  end if;
  if v_sup ~ '^[0-9]{1,18}$' then
    v_emails := v_emails || array(select lower(btrim(x)) from public.leads l, unnest(array[l.claimed_by, l.email]) x
                                   where l.id = v_sup::bigint and x is not null);
  end if;
  foreach v_e in array v_emails loop
    v_tag := substring(v_e from v_harness);
    if v_tag is not null and exists (select 1 from public.rehearsal_window w where w.run_tag = 'qd_run:' || v_tag) then
      return jsonb_build_object('fixture', true, 'why', 'an identity of harness run ' || v_tag || ' (opened in rehearsal_window)');
    end if;
  end loop;
  return jsonb_build_object('fixture', false);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_alert_severe(p_level text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  -- Deliberately generous and deliberately explicit. Anything a routine plausibly means as
  -- "somebody has to look at this now". info / warn / warning / action are NOT severe and stay out.
  select lower(coalesce(p_level,'')) in ('critical','crit','error','high','fatal','sev1','urgent');
$function$


CREATE OR REPLACE FUNCTION public.fn_ambition_ask_fields(p_held bigint, p_fields jsonb)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ update public.reasoning_held_question set request = jsonb_set(request, '{decision,fields}', p_fields) where id = p_held $function$


CREATE OR REPLACE FUNCTION public.fn_ambition_choice(p_id bigint, p_result jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; v text := p_result->'decision'->>'choice';
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if v is null or not exists (select 1 from jsonb_array_elements(r.request->'decision'->'options') o where o->>'id' = v) then
    raise exception 'CHOICE_NOT_AN_OPTION: % is not an option of % (held question %)', coalesce(v, 'no choice'), r.surface, p_id;
  end if;
  return v;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ambition_fields(p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select coalesce((select jsonb_object_agg(k, coalesce(v->>'value', v #>> '{}')) from jsonb_each(coalesce(p_result->'decision'->'fields', '{}'::jsonb)) f(k, v)), '{}'::jsonb) $function$


CREATE OR REPLACE FUNCTION public.fn_ambition_measure(p_key text, p_from timestamp with time zone, p_to timestamp with time zone)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v numeric; v_den numeric; v_num numeric;
  -- the four highest-fee trades in the plan (61 % of the fee from 12.6 % of requests), as category_specs keys
  c_top4 constant text[] := array['fitout', 'commercial-retail-fitout', 'kitchens', 'carpentry-joinery', 'steel', 'structural-steel-fabrication'];
begin
  case p_key
  when 'fee_aed_cumulative' then
    v := public.fn_ceo_plan_measure('fee_aed', timestamptz '2026-01-01', p_to);
  when 'reveal_conversion_pct', 'top4_category_request_share_pct' then
    with i as (
      select i.id, i.category from public.inquiries i join public.customers c on c.id = i.customer_id
       where i.parent_inquiry_id is null and i.created_at >= p_from and i.created_at < p_to
         and coalesce(i.provenance->>'source', '') not in ('demo_factory', 'e2e')
         and not (coalesce(c.is_demo, false) or coalesce(c.full_name, '') ilike 'ZZ DEMO%'
                  or coalesce(c.email, '') ilike '%@example.invalid' or coalesce(c.phone, '') like '+9715000000%'))
    select case when p_key = 'reveal_conversion_pct' then count(*) filter (where exists (select 1 from public.quotes q where q.inquiry_id = i.id))
                else count(*) end,
           case when p_key = 'reveal_conversion_pct'
                then count(*) filter (where exists (select 1 from public.transactions t where t.inquiry_id = i.id and t.revealed_at is not null
                                                     and t.payment_ref ~ '^(pi|ch|py)_'))
                else count(*) filter (where i.category = any (c_top4)) end
      into v_den, v_num from i;
    -- under 20 in the denominator a percentage is noise: not measurable, never zero
    v := case when v_den >= 20 then round(100.0 * v_num / v_den, 1) end;
  when 'b2b_active_accounts' then
    -- a business buyer (customers.industry set) that posted a real request in the 30 days to p_to
    select count(distinct c.id) into v from public.customers c join public.inquiries i on i.customer_id = c.id
     where nullif(btrim(coalesce(c.industry, '')), '') is not null and i.parent_inquiry_id is null
       and i.created_at >= p_to - interval '30 days' and i.created_at < p_to
       and coalesce(i.provenance->>'source', '') not in ('demo_factory', 'e2e')
       and not (coalesce(c.is_demo, false) or coalesce(c.full_name, '') ilike 'ZZ DEMO%' or coalesce(c.email, '') ilike '%@example.invalid');
  when 'checkout_success_pct' then
    -- a Stripe checkout that completed, over every checkout that completed or expired
    select count(*) filter (where type = 'checkout.session.completed'),
           count(*) filter (where type in ('checkout.session.completed', 'checkout.session.expired'))
      into v_num, v_den from public.stripe_events where first_seen_at >= p_from and first_seen_at < p_to;
    v := case when v_den >= 20 then round(100.0 * v_num / v_den, 1) end;
  when 'reveals_paid_30d' then
    v := public.fn_ceo_plan_measure('reveals_paid', p_to - interval '30 days', p_to);
  when 'fee_aed_30d' then
    v := public.fn_ceo_plan_measure('fee_aed', p_to - interval '30 days', p_to);
  when 'registrations_verified_cumulative' then
    v := public.fn_ceo_plan_measure('registrations_verified', timestamptz '2026-01-01', p_to);
  when 'reveals_paid_cumulative' then
    v := public.fn_ceo_plan_measure('reveals_paid', timestamptz '2026-01-01', p_to);
  when 'quotes_received' then
    -- quotes received on real requests, created in the window
    select count(*) into v from public.quotes q join public.inquiries i on i.id = q.inquiry_id join public.customers c on c.id = i.customer_id
     where q.created_at >= p_from and q.created_at < p_to and i.parent_inquiry_id is null
       and coalesce(i.provenance->>'source', '') not in ('demo_factory', 'e2e')
       and not (coalesce(c.is_demo, false) or coalesce(c.full_name, '') ilike 'ZZ DEMO%'
                or coalesce(c.email, '') ilike '%@example.invalid' or coalesce(c.phone, '') like '+9715000000%');
  when 'costs_aed' then
    -- company costs booked in the expense ledger in the window (Dubai dates), in AED at the fixed USD peg 3.6725.
    -- A currency other than AED or USD has no fixed rate here: the reading is then not measurable, never understated.
    select case when count(*) filter (where currency not in ('AED', 'USD')) > 0 then null
                else coalesce(sum(case currency when 'AED' then amount else amount * 3.6725 end), 0) end
      into v from public.expense_entries
     where charged_on >= (p_from at time zone 'Asia/Dubai')::date
       and charged_on <= ((p_to - interval '1 microsecond') at time zone 'Asia/Dubai')::date;
  when 'uptime_pct' then
    -- the platform's own health checks in the window; under 20 checks is not a rate
    select count(*) filter (where ok), count(*) into v_num, v_den from public.health_checks where created_at >= p_from and created_at < p_to;
    v := case when v_den >= 20 then round(100.0 * v_num / v_den, 2) end;
  when 'duties_on_clock_pct' then
    -- enabled seat duties whose last success is within twice their interval, at p_to
    select count(*) filter (where last_ok_at >= p_to - 2 * every), count(*) into v_num, v_den from public.seat_duty where enabled;
    v := case when v_den > 0 then round(100.0 * v_num / v_den, 1) end;
  when 'it_findings_open' then
    select count(*) into v from public.it_engineer_finding where closed_at is null and started_at < p_to;
  else
    v := public.fn_ceo_plan_measure(p_key, p_from, p_to);   -- raises on an unknown key
  end case;
  return v;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ap_bill_dupe_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_prior bigint;
begin
  if coalesce(new.status,'') in ('void','duplicate_hold') then return new; end if;

  select id into v_prior from ap_bills
  where vendor_id = new.vendor_id
    and coalesce(status,'') not in ('void','duplicate_hold')
    and id is distinct from new.id
    and total = new.total
    and bill_date = new.bill_date
  order by id limit 1;

  if v_prior is not null then
    new.status := 'duplicate_hold';

    insert into brand_signal (signal_type, severity, subject_type, subject_id, rule_key, detail, evidence)
    values ('fake_supplier','critical','ap_bill', coalesce(new.bill_no, new.id::text), 'duplicate_invoice_presented',
            'Same vendor, same amount, same date as an invoice already booked. Held, not posted.',
            jsonb_build_object('vendor_id', new.vendor_id, 'total', new.total,
                               'bill_date', new.bill_date, 'prior_bill_id', v_prior,
                               'presented_bill_no', new.bill_no))
    on conflict do nothing;

    insert into institutional_memory (kind, subject_type, subject_id, headline, detail, outcome,
                                      money_aed, learned_by, confidence, evidence_ref)
    values ('pattern','ap_bill', coalesce(new.bill_no, new.id::text),
            'Duplicate invoice presentation held before payment.',
            format('Vendor %s presented %s for %s on %s, matching bill id %s already on file.',
                   new.vendor_id, coalesce(new.bill_no,'(no ref)'), new.total, new.bill_date, v_prior),
            'held as duplicate_hold; not posted, not paid', new.total, 'finance_bookkeeper', 1.0,
            'trg_ap_bill_dupe_guard; ap_bills id ' || v_prior);

    insert into company_event (event_type, entity_type, entity_id, actor, payload)
    values ('invoice.flagged','ap_bill', coalesce(new.bill_no, new.id::text), 'finance_bookkeeper',
            jsonb_build_object('reason','duplicate_invoice','vendor_id', new.vendor_id,
                               'total', new.total,'prior_bill_id', v_prior));

    raise warning 'invoice held as duplicate of bill id %', v_prior;
  end if;
  return new;
end; $function$


CREATE OR REPLACE FUNCTION public.fn_ap_pay_block_held()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.status in ('paid','partial') and coalesce(old.status,'') = 'duplicate_hold' then
    raise exception 'bill % is held as a duplicate and cannot be paid until a person clears the hold',
      coalesce(new.bill_no, new.id::text);
  end if;
  return new;
end; $function$


CREATE OR REPLACE FUNCTION public.fn_app_secrets_no_paid_ai_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if old.key = 'no_paid_ai' and lower(coalesce(old.value, '')) in ('1','true','yes','on')
     and (tg_op = 'DELETE' or new.key <> 'no_paid_ai' or lower(coalesce(new.value, '')) not in ('1','true','yes','on'))
     and not public.fn_founder_hold_change_allowed() then
    raise exception 'FOUNDER_HOLD: app_secrets.no_paid_ai is on; only the founder turns it off (set local app.change_reason = ''founder:<ledger id>'').'
      using errcode = 'P0001';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $function$


CREATE OR REPLACE FUNCTION public.fn_app_secrets_no_paid_ai_stays_off()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.key = 'no_paid_ai' and lower(coalesce(new.value, '')) in ('1','true','yes','on')
     and not public.fn_founder_hold_change_allowed() then
    raise exception 'RULING_1260: OpenRouter stays on; app_secrets.no_paid_ai is switched on only by the founder (set local app.change_reason = ''founder:<ledger id>'').'
      using errcode = 'P0001';
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_apply_playbook(p_agent_key text, p_query_embedding vector, p_query_text text, p_min_similarity real DEFAULT 0.85, p_k integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_lexemes    text[];
  v_total      int;
  v_row        record;
  -- scalars, not a record compared to null: an unassigned plpgsql record RAISES on `is null`
  v_found      boolean := false;
  v_b_id text; v_b_title text; v_b_content text; v_b_layer text; v_b_type text; v_b_tier text;
  v_b_sim real := -1; v_b_terms int := 0; v_b_sd jsonb;
  v_n_seen     boolean := false;
  v_n_type text; v_n_title text; v_n_sim real; v_n_terms int;
  v_candidates jsonb := '[]'::jsonb;
  v_terms      int;
  v_pass       boolean;
  v_reason     text;
  v_det        text;
  v_key        text;
  v_dept       text;
  v_scope      text[];
  v_role_ids   text[];
begin
  if p_query_embedding is null then
    return jsonb_build_object('matched', false, 'reason', 'no query embedding supplied');
  end if;

  -- The step's own vocabulary, normalised the same way ops_knowledge.tsv is (english stemming).
  select array_agg(distinct lexeme) into v_lexemes
    from unnest(to_tsvector('english', coalesce(p_query_text, '')))
   where length(lexeme) >= 3;
  v_total := coalesce(array_length(v_lexemes, 1), 0);

  -- HYBRID, ACTIONABLE-ONLY RETRIEVAL. fn_ops_knowledge_match's top-20 by cosine is dominated by metric
  -- definitions, failure cases and scenarios (measured: the actionable SOP that DOES corroborate
  -- "Detect from health, drift or a failed gate" — SOP 04 Security Alert Triage — never reached the
  -- top 20). So the candidate set is: in-scope rows of the four actionable kinds, ranked by cosine.
  -- The scope predicate MIRRORS fn_ops_knowledge_match exactly (agent -> department -> fn_dept_scope,
  -- packaged roles via org_role_identity, company/external); change both or neither.
  v_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  select a.department into v_dept from public.org_agents a where a.agent_key = v_key;
  if v_dept is null then
    return jsonb_build_object('matched', false, 'reason', 'agent ' || coalesce(p_agent_key,'?') || ' resolves to no department; no scope');
  end if;
  v_scope := public.fn_dept_scope(v_dept);
  select array_agg(packaged_role_id) into v_role_ids from public.org_role_identity where agent_key = v_key;

  for v_row in
    select k.record_id, k.title, k.content, k.layer, k.record_type, k.authority_tier,
           (1 - (k.embedding_gte <=> p_query_embedding))::real as similarity,
           k.structured_data,
           (select count(*) from unnest(tsvector_to_array(k.tsv)) t where t = any(coalesce(v_lexemes, '{}'))) as terms_matched
      from public.ops_knowledge k
     where k.embedding_gte is not null
       and k.runtime_eligible
       and k.supersession_state = 'current'
       and k.record_type in ('decision_playbook','decision_rule','standard_operating_procedure','exception_playbook')
       and (
             k.scope_type in ('company','external_source')
          or (k.scope_type = 'department' and k.dept_key = any(v_scope))
          or (k.role_key = any(coalesce(v_role_ids, '{}')))
       )
     order by k.embedding_gte <=> p_query_embedding
     limit greatest(coalesce(p_k, 20), 1)
  loop
    v_terms := coalesce(v_row.terms_matched, 0);
    if not v_n_seen then
      v_n_seen := true; v_n_type := v_row.record_type; v_n_title := v_row.title;
      v_n_sim := v_row.similarity; v_n_terms := v_terms;
    end if;
    v_pass := v_row.record_type in ('decision_playbook','decision_rule','standard_operating_procedure','exception_playbook')
              and v_row.similarity >= p_min_similarity
              and v_terms >= 2
              and v_total > 0 and v_terms::numeric / v_total >= 0.30
              and length(coalesce(v_row.content, '')) >= 300;
    v_candidates := v_candidates || jsonb_build_object(
      'record_id', v_row.record_id, 'title', v_row.title, 'layer', v_row.layer,
      'record_type', v_row.record_type, 'similarity', round(v_row.similarity::numeric, 4),
      'terms_matched', v_terms, 'terms_total', v_total, 'corroborated', v_pass);
    if v_pass and (not v_found or v_row.similarity > v_b_sim) then
      v_found := true; v_b_id := v_row.record_id; v_b_title := v_row.title; v_b_content := v_row.content;
      v_b_layer := v_row.layer; v_b_type := v_row.record_type; v_b_tier := v_row.authority_tier;
      v_b_sim := v_row.similarity; v_b_terms := v_terms; v_b_sd := v_row.structured_data;
    end if;
  end loop;

  if not v_found then
    v_reason := case when not v_n_seen then 'no in-scope knowledge for this agent'
                     else 'no corroborated actionable match: nearest is ' || coalesce(v_n_type,'?')
                          || ' "' || coalesce(v_n_title,'') || '" at ' || round(v_n_sim::numeric, 3)
                          || ' (floor ' || p_min_similarity || ', noise median 0.837) sharing '
                          || coalesce(v_n_terms, 0) || ' of ' || v_total || ' step terms'
                end;
    return jsonb_build_object('matched', false, 'reason', v_reason, 'candidates', v_candidates,
                              'terms_total', v_total);
  end if;

  v_det := coalesce(v_b_content, '');
  if v_b_sd is not null and v_b_sd <> '{}'::jsonb then
    v_det := v_det || E'\n\nSTRUCTURED DETERMINATION (from the record''s structured_data):\n'
             || jsonb_pretty(v_b_sd);
  end if;

  return jsonb_build_object(
    'matched',        true,
    'record_id',      v_b_id,
    'title',          v_b_title,
    'layer',          v_b_layer,
    'record_type',    v_b_type,
    'authority_tier', v_b_tier,
    'similarity',     round(v_b_sim::numeric, 4),
    'terms_matched',  v_b_terms,
    'terms_total',    v_total,
    'confidence',     round(v_b_sim::numeric, 3),
    'determination',  v_det,
    'outcome',        'Applied the company ' || v_b_type || ' "' || v_b_title
                      || '" to this step (cosine ' || round(v_b_sim::numeric, 3)
                      || ', corroborated by ' || v_b_terms || ' of ' || v_total || ' step terms).',
    'candidates',     v_candidates,
    'basis',          'deterministic: nearest ACTIONABLE company knowledge by meaning, corroborated by the step''s own terms; no model call'
  );
end
$function$


CREATE OR REPLACE FUNCTION public.fn_ar_days(p_n integer)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE STRICT
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
    when abs(p_n) = 0 then 'اليوم'
    when abs(p_n) = 1 then 'يوم واحد'
    when abs(p_n) = 2 then 'يومان'
    when abs(p_n) <= 10 then abs(p_n)::text || ' أيام'
    else abs(p_n)::text || ' يومًا'
  end
$function$


CREATE OR REPLACE FUNCTION public.fn_ar_norm(p_text text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when p_text is null then null else
    translate(
      -- tashkeel (fathatan..sukun), the combining hamza/madda marks, superscript alef, tatweel,
      -- and the Quranic annotation marks. Written as \u escapes because a combining mark pasted
      -- literally into a file is invisible in every diff that will ever be taken of it.
      regexp_replace(p_text, '[\u064B-\u0655\u0670\u0640\u06D6-\u06ED]', '', 'g'),
      --  أ إ آ ٱ  ى  ة  ؤ  ئ   ٠١٢٣٤٥٦٧٨٩
      'أإآٱىةؤئ٠١٢٣٤٥٦٧٨٩',
      'اااايهوي0123456789'
    )
  end
$function$


CREATE OR REPLACE FUNCTION public.fn_arabic_document_wait(p_quote text, p_texts text[])
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  insert into public.arabic_document_waiter (quote_id, texts) values (p_quote, p_texts)
  on conflict (quote_id) do update set texts = excluded.texts
$function$


CREATE OR REPLACE FUNCTION public.fn_arabic_outbound_flush(p_limit integer DEFAULT 20)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare h record; v_map jsonb; v_rows jsonb; v_row jsonb; v_out jsonb; k text; n integer := 0; v_subject text; v_body text;
begin
  -- Only rows whose every line is ALREADY translated are picked: an incomplete row never starves a ready one.
  for h in select * from public.arabic_outbound_hold o where o.status = 'held'
              and not exists (select 1 from unnest(o.texts) t
                               where not exists (select 1 from public.arabic_translation a where a.source_md5 = md5(t)))
            order by o.id limit greatest(1, least(coalesce(p_limit, 20), 200)) for update skip locked
  loop
    v_map := public.fn_arabic_translations(h.texts);
    v_rows := '[]'::jsonb;
    for v_row in select * from jsonb_array_elements(h.delivery) loop
      v_subject := coalesce(v_row->>'subject', ''); v_body := coalesce(v_row->>'body', '');
      foreach k in array h.texts loop
        v_subject := replace(v_subject, '⟦' || k || '⟧', v_map->>k);
        v_body := replace(v_body, '⟦' || k || '⟧', v_map->>k);
      end loop;
      v_rows := v_rows || jsonb_build_array(v_row || jsonb_build_object('subject', v_subject, 'body', v_body));
    end loop;
    if v_rows::text like '%⟦%' then   -- a placeholder it could not fill: never sent, and never re-picked
      update public.arabic_outbound_hold set status = 'failed', result = jsonb_build_object('error', 'unfilled placeholder') where id = h.id;
      continue;
    end if;
    -- One refused delivery must never roll back the translation store or the park that called this flush.
    begin
      v_out := public.fn_customer_support_takes_delivery(v_rows);
      update public.arabic_outbound_hold set status = 'sent', sent_at = now(), result = v_out where id = h.id;
      n := n + 1;
    exception when others then
      update public.arabic_outbound_hold set status = 'failed', result = jsonb_build_object('error', sqlerrm) where id = h.id;
    end;
  end loop;
  return n;
end $function$


CREATE OR REPLACE FUNCTION public.fn_arabic_outbound_park(p_texts text[], p_rows jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint;
begin
  if coalesce(cardinality(p_texts), 0) = 0 or jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'fn_arabic_outbound_park: texts and a delivery array are required' using errcode = '22023';
  end if;
  insert into public.arabic_outbound_hold (texts, delivery) values (p_texts, p_rows) returning id into v_id;
  perform public.fn_arabic_outbound_flush(10);   -- the Arabic may already be in the cache
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_arabic_translation_store(p_pairs jsonb, p_held_id bigint DEFAULT NULL::bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n integer;
begin
  if jsonb_typeof(p_pairs) is distinct from 'object' then return 0; end if;
  insert into public.arabic_translation (source_md5, source, arabic, held_id)
  select md5(e.key), e.key, btrim(e.value), p_held_id
    from jsonb_each_text(p_pairs) e
   where btrim(e.key) <> '' and (e.value ~ '[؀-ۿ]'
         -- kept as written only when the line has the shape of a code (no lowercase word): the same test as
         -- reasoned_governance.ts keptAsWritten, on our own reply
         or (btrim(e.value) = e.key and not exists (select 1 from regexp_split_to_table(e.key, '[^A-Za-z0-9]+') w
                                                      where w ~ '[a-z]' and w !~ '[0-9]')))
  on conflict (source_md5) do update set arabic = excluded.arabic, held_id = excluded.held_id, created_at = now();
  get diagnostics n = row_count;
  if n > 0 then perform public.fn_arabic_outbound_flush(20); end if;   -- a parked message may now be whole
  return n;
end $function$


CREATE OR REPLACE FUNCTION public.fn_arabic_translations(p_sources text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_object_agg(t.source, t.arabic), '{}'::jsonb)
    from public.arabic_translation t
   where t.source_md5 = any (select md5(s) from unnest(coalesce(p_sources, '{}'::text[])) s)
$function$


CREATE OR REPLACE FUNCTION public.fn_arabic_waiters_ready(p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(w.quote_id), '[]'::jsonb)
    from (select quote_id from public.arabic_document_waiter d
           where d.attempts < 5   -- a render that keeps failing stops costing replays (it is reported by supplier_api)
             and not exists (select 1 from unnest(d.texts) t
                              where not exists (select 1 from public.arabic_translation a where a.source_md5 = md5(t)))
           order by d.attempts, d.last_tried_at nulls first, d.created_at limit greatest(1, least(coalesce(p_limit, 20), 100))) w
$function$


CREATE OR REPLACE FUNCTION public.fn_artifact_review_valid()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_author   text;
  v_reviewer text;
begin
  -- Resolve BOTH sides before comparing. coalesce keeps an unrecognised identity as itself rather
  -- than turning it into null: null = null is null, and a guard that evaluates to null lets the
  -- row through.
  v_author   := coalesce(public.fn_org_agent_resolve(new.author_agent),   new.author_agent);
  v_reviewer := coalesce(public.fn_org_agent_resolve(new.reviewer_agent), new.reviewer_agent);

  if new.verdict = 'pass' then
    -- A PASS WITH NO REVIEWER IS WORSE THAN A SELF-REVIEW, and the previous guard permitted it:
    -- a null reviewer_agent is never equal to author_agent, so the comparison answered "not a
    -- self-review" and the row went in with nobody having looked at the artifact.
    if new.reviewer_agent is null or btrim(new.reviewer_agent) = '' then
      raise exception 'artifact % % cannot be marked pass with no reviewer recorded',
        new.subject_type, new.subject_id
        using errcode = 'check_violation';
    end if;

    if new.author_agent is not null and v_author = v_reviewer then
      raise exception
        'artifact_review refuses a self-review: author "%" and reviewer "%" are the same employee (%). %',
        new.author_agent, new.reviewer_agent, v_author,
        'Route the artifact to the QA path (ai_quality_reviewer) or to fn_pick_reviewer(dept, author).'
        using errcode = 'check_violation';
    end if;
  end if;

  -- Store both sides canonical, so every later count over this table measures employees and not
  -- spelling. Same discipline as trg_review_chain_no_self_review.
  new.author_agent   := case when new.author_agent   is null then null else v_author   end;
  new.reviewer_agent := case when new.reviewer_agent is null then null else v_reviewer end;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_assign_founding_rank()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_limit int; v_rank int;
begin
  -- Rank a supplier once, and only once they are a VERIFIED supplier. Claiming a scraped listing
  -- is not registration; registration without documents is not verification.
  if new.founding_rank is not null then return new; end if;
  if coalesce(new.verified,false) is not true then return new; end if;
  if coalesce(new.banned,false) is true then return new; end if;
  if coalesce(new.approval_status,'') in ('rejected','action_required') then return new; end if;

  v_limit := coalesce((select nullif(value,'')::int from public.app_secrets where key='founding_free_limit'), 1000);

  -- Serialise rank assignment so two concurrent verifications cannot take the same number.
  perform pg_advisory_xact_lock(hashtext('qd_founding_rank'));
  select coalesce(max(founding_rank),0) + 1 into v_rank from public.leads;

  new.founding_rank := v_rank;
  -- Exemption is permanent: it is stamped at verification and never recalculated, so a supplier
  -- who was inside the first 1,000 stays exempt even as the base grows.
  new.subscription_exempt := (v_rank <= v_limit);
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_assign_training(p_agent_key text, p_competency text, p_purpose text DEFAULT 'practice'::text, p_n integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_roles text[]; v_dept text; v_rows jsonb;
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  if p_purpose not in ('practice','retest','drift_check') then
    raise exception 'purpose must be practice, retest or drift_check';
  end if;
  select array_agg(packaged_role_id) into v_roles from org_role_identity where agent_key = p_agent_key;
  select packaged_department into v_dept from org_role_identity where agent_key = p_agent_key limit 1;
  if v_roles is null then
    return jsonb_build_object('assigned', 0, 'reason', 'agent has no role identity');
  end if;

  with pool as (
    select c.case_id, c.case_family, c.competency, c.scope_key
      from agent_training_case c
     -- The parentheses matter: AND binds tighter than OR, so without them the competency
     -- filter applied only to the department branch and every role case slipped past it.
     where ((c.scope_type = 'role' and c.scope_key = any(v_roles))
         or (c.scope_type = 'department' and c.scope_key = v_dept))
       and (p_competency is null or c.competency = p_competency)
  ), unseen as (
    select p.* from pool p
     where not exists (select 1 from agent_training_attempt a
                        where a.agent_key = p_agent_key and a.case_id = p.case_id)
     order by md5(p.case_id || p_agent_key || p_purpose)     -- stable per (agent,purpose), not an ordered list
     limit greatest(coalesce(p_n, 5), 1)
  ), ins as (
    insert into agent_training_attempt (agent_key, case_id, purpose, competency)
    select p_agent_key, case_id, p_purpose, competency from unseen
    on conflict (agent_key, case_id, purpose) do nothing
    returning id, case_id
  )
  select jsonb_agg(jsonb_build_object('attempt_id', i.id, 'case_id', i.case_id,
                                      'payload', c.payload))
    into v_rows
    from ins i join agent_training_case c on c.case_id = i.case_id;

  return jsonb_build_object('assigned', coalesce(jsonb_array_length(v_rows), 0),
                            'purpose', p_purpose, 'cases', coalesce(v_rows, '[]'::jsonb));
end $function$


CREATE OR REPLACE FUNCTION public.fn_authority_rank(p text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  -- How much UNSUPERVISED power the tier confers. advisory advises only; gated needs approval
  -- before acting; supervised acts and is reviewed after; autonomous acts unreviewed.
  select case p when 'advisory' then 0 when 'gated' then 1 when 'supervised' then 2
                when 'autonomous' then 3 else 3 end;   -- unknown tier ranks highest: fail closed
$function$


CREATE OR REPLACE FUNCTION public.fn_autonomy_control_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_key    text := coalesce(new.key, old.key);
  v_old    text := old.value;
  v_new    text := new.value;
  v_reason text := nullif(trim(coalesce(current_setting('app.change_reason', true), '')), '');
  v_dir    text := 'neutral';
  v_widen  boolean := false;
begin
  if v_key not in ('agent_autonomy_enabled','agent_autonomy_from','cos_frozen','ai_kill_switch') then
    return coalesce(new, old);
  end if;

  if tg_op = 'DELETE' then
    -- Deleting cos_frozen or ai_kill_switch removes a brake; deleting the enable flag adds one.
    v_widen := v_key in ('cos_frozen','ai_kill_switch');
  elsif v_key = 'agent_autonomy_enabled' then
    v_widen := v_new = 'true' and coalesce(v_old,'false') <> 'true';
  elsif v_key = 'cos_frozen' then
    v_widen := coalesce(v_new,'false') <> 'true' and v_old = 'true';
  elsif v_key = 'ai_kill_switch' then
    v_widen := coalesce(v_new,'false') = 'false' and coalesce(v_old,'false') <> 'false';
  elsif v_key = 'agent_autonomy_from' then
    v_widen := tg_op = 'INSERT' or v_new is distinct from v_old;   -- any move of the date is a widen
  end if;
  v_dir := case when v_widen then 'widen' else 'tighten' end;

  if v_widen and (v_reason is null or length(v_reason) < 12) then
    raise exception
      'app_secrets.%: widening autonomy needs a stated reason. Run '
      '`set local app.change_reason = ''why, in a sentence'';` in the same transaction. '
      'A PostgREST update from an edge function cannot set that, which is the point — this key '
      'was reachable by all 190 service-role functions. Tightening (freeze, kill switch, disable) '
      'never needs a reason and is never refused.', v_key
      using errcode = 'check_violation';
  end if;

  insert into public.autonomy_control_audit (object, op, direction, old_value, new_value, reason)
  values ('app_secrets:' || v_key, tg_op, v_dir, v_old, v_new, v_reason);

  return coalesce(new, old);
end $function$


CREATE OR REPLACE FUNCTION public.fn_autonomy_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_blockers text[] := '{}';
  v_p0       record;
  v_enabled  text;
  v_from     text;
  v_frozen   text;
  v_kill     text;
begin
  for v_p0 in
    select id, item from public.spec_backlog where priority = 0 and status = 'open' order by id
  loop
    v_blockers := array_append(v_blockers, 'spec_backlog#' || v_p0.id || ' open: ' || left(v_p0.item, 90));
  end loop;

  select value into v_enabled from public.app_secrets where key = 'agent_autonomy_enabled';
  select value into v_from    from public.app_secrets where key = 'agent_autonomy_from';
  select value into v_frozen  from public.app_secrets where key = 'cos_frozen';
  select value into v_kill    from public.app_secrets where key = 'ai_kill_switch';

  if coalesce(v_enabled, 'false') <> 'true' then
    v_blockers := array_append(v_blockers, 'agent_autonomy_enabled is not true');
  end if;
  if v_frozen = 'true' then
    v_blockers := array_append(v_blockers, 'cos_frozen is true');
  end if;
  if v_kill is not null and v_kill <> 'false' then
    v_blockers := array_append(v_blockers, 'ai_kill_switch is set');
  end if;
  begin
    if v_from is not null and v_from::date > current_date then
      v_blockers := array_append(v_blockers, 'agent_autonomy_from is in the future: ' || v_from);
    end if;
  exception when others then
    v_blockers := array_append(v_blockers, 'agent_autonomy_from is unparseable: ' || coalesce(v_from, 'null'));
  end;

  return jsonb_build_object(
    'allowed',    cardinality(v_blockers) = 0,
    'blockers',   to_jsonb(v_blockers),
    'checked_at', now());
exception when others then
  return jsonb_build_object(
    'allowed', false,
    'blockers', to_jsonb(array['autonomy status could not be determined: ' || sqlerrm]),
    'checked_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_backup_coverage()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_not_done int; v_ids jsonb; v_abandoned int; v_unqueued int; v_unq_err text; v_last_ok timestamptz;
  v_conv jsonb; v_conv_fn text := 'public.fn_conversation_retention' || '_breaches(interval)';
  v_refile int; v_fail text[] := '{}';
begin
  select count(*), coalesce(jsonb_agg(id order by id) filter (where rn <= 20), '[]'::jsonb) into v_not_done, v_ids
    from (select d.id, row_number() over (order by d.id) rn from public.doc_backups d
           where d.status <> 'done' and d.entity <> 'zz_demo'
             -- 19 Oct 2026: retention moves only a verified copy into these; a stuck prune is a backup_prune finding.
             and d.status not in ('prune_pending', 'pruning', 'pruned')
             and not (d.status = 'abandoned' and coalesce(d.error, '') like 'abandoned:%')
             and coalesce(d.requeued_at, d.created_at) < now() - interval '48 hours') x;
  select count(*) into v_abandoned from public.doc_backups where status = 'abandoned' and coalesce(error, '') like 'abandoned:%';
  if v_not_done > 0 then v_fail := array_append(v_fail, 'not_done_after_48h'); end if;

  begin
    v_unqueued := public.fn_enqueue_doc_backups();
    raise exception using errcode = 'QDRBK', message = 'roll back the coverage measurement';
  exception
    when sqlstate 'QDRBK' then null;
    when read_only_sql_transaction then v_unq_err := 'not measurable in a read-only transaction';
    when others then v_unq_err := left(sqlerrm, 200);
  end;
  select max(started_at) into v_last_ok from public.agent_runs where agent = 'dropbox_backup' and status = 'ok';
  if (v_unqueued > 0 and coalesce(v_last_ok, '-infinity') < now() - interval '48 hours')
     or (v_unq_err is not null and v_unq_err <> 'not measurable in a read-only transaction') then
    v_fail := array_append(v_fail, 'sources_without_a_row');
  end if;

  if to_regprocedure(v_conv_fn) is not null then
    begin
      execute 'select ' || replace(v_conv_fn, '(interval)', '($1)') into v_conv using interval '48 hours';
    exception when others then v_conv := jsonb_build_object('error', left(sqlerrm, 200));
    end;
    if coalesce((v_conv->>'total')::int, 0) > 0 or v_conv ? 'error' then v_fail := array_append(v_fail, 'conversation_retention'); end if;
  end if;

  select count(*) into v_refile from public.agent_actions
   where kind = 'handoff' and agent = 'sales_engineer' and detail->>'type' in ('backup.refile', 'backup.remediate')
     and (status = 'failed' or (status = 'pending' and created_at < now() - interval '48 hours'));
  if v_refile > 0 then v_fail := array_append(v_fail, 'refile_not_verified_in_48h'); end if;

  return jsonb_build_object(
    'ok', cardinality(v_fail) = 0, 'failing', to_jsonb(v_fail),
    'not_done_after_48h', v_not_done, 'not_done_ids', v_ids, 'abandoned_documented', v_abandoned,
    'sources_without_a_row', v_unqueued, 'sources_error', v_unq_err, 'last_ok_backup', v_last_ok,
    'conversation_retention', coalesce(v_conv, jsonb_build_object('checked', false, 'reason', 'function not installed')),
    'refiles_open_past_48h', v_refile, 'measured_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_backup_enqueue_outcome(p_stage text, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_stage is null or p_stage not in ('new_documents', 'backfill') then
    raise exception 'fn_backup_enqueue_outcome: stage is new_documents or backfill (got %)', p_stage;
  end if;
  -- One duty per stage, so a clean backfill never closes a failing new-document enqueue or the reverse.
  return public.fn_it_duty_settle('backup_enqueue_' || p_stage,
    case when p_error is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object(
      'item', 'failing', 'owner_seat', 'it_engineer', 'subject', 'dropbox_backup', 'blast', 'agent_facing', 'affected', 1,
      'title', case p_stage
                 when 'new_documents' then 'New documents are not being queued for Dropbox: fn_enqueue_doc_backups failed'
                 else 'The Dropbox backfill (storage sweep, pre-7-Sep exports) failed; new documents are still queued' end,
      'evidence', jsonb_build_object('error', left(p_error, 500), 'at', now(),
                    'routine', case p_stage when 'new_documents' then 'fn_enqueue_doc_backups' else 'fn_enqueue_doc_backups_backfill' end,
                    'caller', 'dropbox_backup')))
    end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_backup_enqueue_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_n integer; v_oldest timestamptz; v_sample jsonb; v_items jsonb := '[]'::jsonb;
begin
  with reg as (
    select l.* from public.leads l
     where not coalesce(l.is_demo, false)
       and (l.approved_at is not null or l.registration_submitted_at is not null
         or l.signed_terms_path is not null or l.company_profile_doc_path is not null
         or l.license_doc_path is not null or coalesce(l.claimed, false))
  ),
  files(bucket, path, owner) as (
    select v.bucket, v.path, 'supplier:' || l.id
      from reg l cross join lateral (values
        ('supplier-docs', l.license_doc_path), ('supplier-docs', l.egr_doc_path),
        ('supplier-docs', l.insurance_doc_path), ('supplier-docs', l.vat_doc_path), ('supplier-docs', l.iso_doc_path),
        ('supplier-docs', l.manufacturer_auth_doc_path), ('supplier-docs', l.company_profile_doc_path),
        ('signed-terms', l.signed_terms_path)) v(bucket, path)
    union all
    select 'supplier-docs', cat, 'supplier:' || l.id from reg l cross join lateral unnest(coalesce(l.catalog_doc_paths, '{}')) cat
    union all
    select 'signed-terms', c.signed_terms_path, 'customer:' || c.id from public.customers c where not coalesce(c.is_demo, false)
    union all
    select 'drawing-files', i.drawing_file_path, 'inquiry:' || i.id
      from public.inquiries i join public.customers c on c.id = i.customer_id where not coalesce(c.is_demo, false)
    union all
    select 'finance-docs', t.doc_path, 'transaction:' || t.id from public.transactions t
  ),
  missing as (
    select f.owner, f.bucket || '/' || f.path as item, o.created_at as since
      from files f join storage.objects o on o.bucket_id = f.bucket and o.name = f.path
     where length(coalesce(f.path, '')) > 0 and f.path !~* 'zz[_ -]?demo'
       and o.created_at < now() - interval '1 hour'
       and not exists (select 1 from public.doc_backups d where d.bucket = f.bucket and d.path = f.path)
    union all
    -- dated from when the lead became a registrant where leads records it (review, 15 Sep 2026: a lead
    -- created weeks ago and approved a minute ago is not yet late); claimed and the document paths carry no
    -- date of their own, so those fall back to created_at
    select 'supplier:' || l.id, 'Company Details.pdf',
           greatest(l.created_at, coalesce(l.approved_at, l.registration_submitted_at, l.created_at)) from reg l
     where greatest(l.created_at, coalesce(l.approved_at, l.registration_submitted_at, l.created_at)) < now() - interval '1 hour'
       and not exists (select 1 from public.doc_backups d where d.dedupe_key = 'S:' || l.id || ':details')
    union all
    select 'customer:' || c.id, 'Customer Details.pdf', c.created_at from public.customers c
     where not coalesce(c.is_demo, false) and c.created_at < now() - interval '1 hour'
       and not exists (select 1 from public.doc_backups d where d.dedupe_key = 'C:' || c.id || ':details')
    union all
    select 'inquiry:' || i.id, 'Inquiry Summary.pdf', i.created_at
      from public.inquiries i join public.customers c on c.id = i.customer_id
     where not coalesce(c.is_demo, false) and i.created_at < now() - interval '1 hour'
       and not exists (select 1 from public.doc_backups d where d.dedupe_key = 'I:' || i.id || ':summary')
  )
  select count(*), min(since),
         coalesce(jsonb_agg(jsonb_build_object('owner', owner, 'item', item, 'since', since) order by since)
                    filter (where rn <= 10), '[]'::jsonb)
    into v_n, v_oldest, v_sample
    from (select m.*, row_number() over (order by m.since) rn from missing m) z;

  if v_n > 0 then
    v_items := jsonb_build_array(jsonb_build_object(
      'item', 'unqueued_documents', 'owner_seat', 'it_engineer', 'subject', 'dropbox_backup', 'blast', 'agent_facing',
      'affected', v_n,
      'title', left(format('%s customer/supplier document(s) over an hour old have no Dropbox backup row (oldest %s)',
                           v_n, to_char(v_oldest at time zone 'UTC', 'YYYY-MM-DD HH24:MI "UTC"')), 300),
      'evidence', jsonb_build_object('count', v_n, 'oldest', v_oldest, 'first', v_sample,
        'why', 'fn_enqueue_doc_backups is not filing new documents: see duty:backup_enqueue_new_documents:failing and dropbox_backup agent_runs signal enqueue_failed')));
  end if;
  return public.fn_it_duty_settle('backup_enqueue_watch', v_items) || jsonb_build_object('unqueued', v_n, 'oldest', v_oldest);
end $function$


CREATE OR REPLACE FUNCTION public.fn_backup_kick(p_reason text, p_mode text DEFAULT 'process_only'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_ref text; v_secret text; v_req bigint;
begin
  if p_mode not in ('process_only', 'enqueue') then
    raise exception 'fn_backup_kick: mode must be process_only or enqueue, got %', p_mode;
  end if;
  -- the lock makes check-then-act atomic: two kicks in the same instant cannot both pass
  if not pg_try_advisory_xact_lock(hashtext('fn_backup_kick'))
     or exists (select 1 from public.agent_runs where agent = 'backup_kick' and status = 'ok'
                and started_at > now() - interval '60 seconds') then
    -- 7 Oct 2026: the scheduler's call is recorded, so its heartbeat sees that it ran (dropbox_kick, handoff
    -- 130872). Only the two second schedulers (GitHub until 26 Oct 2026, pg_cron from then): the per-document
    -- trigger kicks debounce in bursts and nothing reads them.
    if p_reason in ('github_actions', 'pg_cron_second_scheduler') then
      insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
      values ('backup_kick', 'skipped', jsonb_build_object('reason', p_reason, 'mode', p_mode, 'debounced', true),
              left('dropbox_backup not kicked (' || p_mode || '): debounced, a kick in the last 60 seconds is still draining: ' || p_reason, 500),
              now(), now());
    end if;
    return jsonb_build_object('kicked', false, 'reason', 'debounced: a kick in the last 60 seconds is still draining');
  end if;
  select value into v_ref from public.app_secrets where key = 'project_ref';
  select value into v_secret from public.app_secrets where key = 'cred_fn_backup_kick';
  if coalesce(v_ref, '') = '' or coalesce(v_secret, '') = '' then
    insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
    values ('backup_kick', 'error', jsonb_build_object('reason', p_reason, 'mode', p_mode),
            'Could not kick dropbox_backup: app_secrets project_ref or cred_fn_backup_kick is missing. The daily pass still runs.', now(), now());
    return jsonb_build_object('kicked', false, 'reason', 'missing project_ref or cred_fn_backup_kick');
  end if;
  select net.http_post(
           url := 'https://' || v_ref || '.supabase.co/functions/v1/dropbox_backup',
           headers := '{"Content-Type":"application/json"}'::jsonb,
           body := jsonb_build_object('__secret', v_secret, 'mode', p_mode, 'reason', left(coalesce(p_reason, ''), 120), 'chain', 0),
           timeout_milliseconds := 150000) into v_req;
  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('backup_kick', 'ok', jsonb_build_object('reason', p_reason, 'mode', p_mode, 'request_id', v_req),
          left('dropbox_backup kicked (' || p_mode || '): ' || coalesce(p_reason, ''), 500), now(), now());
  return jsonb_build_object('kicked', true, 'request_id', v_req, 'mode', p_mode);
end $function$


CREATE OR REPLACE FUNCTION public.fn_backup_prune_cancel(p_log_id bigint, p_why text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_reverted integer;
begin
  with cl as (
    update public.backup_prune_log bl
       set cancelled_at = now(),
           storage_error = left('cancelled: the day is no longer due for deletion (' || coalesce(p_why, 'no reason given') || ')', 1000)
     where bl.id = p_log_id and bl.mode = 'delete' and bl.cancelled_at is null
    returning bl.day)
  update public.doc_backups b
     set status = coalesce(b.status_before_prune, 'pending'), status_before_prune = null,
         claimed_at = null, claimed_by = null, error = null
    from cl
   where left(b.dedupe_key, 18) = 'EXPORT:' || to_char(cl.day, 'YYYY-MM-DD') || '/'
     and b.status in ('prune_pending', 'pruning');
  get diagnostics v_reverted = row_count;
  return v_reverted;
end $function$


CREATE OR REPLACE FUNCTION public.fn_backup_prune_days()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(t.x order by t.x->>'day'), '[]'::jsonb) from (
    select jsonb_build_object('day', r.stamp, 'origin', 'export', 'kind', r.kind, 'status', r.status)
      from public.table_export_run r where r.pruned_at is null
    union all
    select jsonb_build_object('day', lg.dy, 'origin', 'legacy', 'kind', 'full',
                              'status', case when lg.has_manifest then 'done' else 'incomplete' end)
      from (select split_part(o.name, '/', 1)::date as dy,
                   bool_or(o.name = split_part(o.name, '/', 1) || '/_manifest.json') as has_manifest
              from storage.objects o
             where o.bucket_id = 'backups' and o.name ~ '^\d{4}-\d{2}-\d{2}/' and split_part(o.name, '/', 1) <= '2026-09-07'
             group by 1) lg
     where not exists (select 1 from public.table_export_run r where r.stamp = lg.dy)
  ) t(x);
$function$


CREATE OR REPLACE FUNCTION public.fn_backup_prune_decide(p_days jsonb, p_today date)
 RETURNS TABLE(day date, origin text, kind text, day_status text, decision text, reason text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with d as (
    select (e->>'day')::date as dy, coalesce(e->>'origin', 'export') as og,
           coalesce(e->>'kind', 'full') as kd, coalesce(e->>'status', '') as st
      from jsonb_array_elements(coalesce(p_days, '[]'::jsonb)) e),
  g as (
    select max(d.dy) filter (where d.kd = 'full' and d.st = 'done') as newest_full,
           max(d.dy) filter (where d.kd = 'full') as latest_full_attempt
      from d),
  -- the month's copy: its first complete full copy, or a full-less month's last complete copy
  mf as (
    select date_trunc('month', d.dy)::date as mo,
           min(d.dy) filter (where d.kd = 'full' and d.st = 'done') as first_full,
           max(d.dy) filter (where d.st = 'done') as last_done
      from d group by 1),
  k as (
    select d.dy, d.og, d.kd, d.st,
           (d.st = 'done' and (d.dy = mf.first_full or (mf.first_full is null and d.dy = mf.last_done))) as month_copy,
           (date_trunc('month', d.dy)::date > (date_trunc('month', p_today) - interval '12 months')::date) as within_12_months,
           case when g.newest_full is null then 'blocked: no complete full copy exists, so nothing is deleted'
                when g.latest_full_attempt > g.newest_full
                  then 'blocked: the latest full copy (' || g.latest_full_attempt || ') did not complete, so nothing is deleted'
           end as blocked,
           d.dy = g.newest_full as is_newest_full,
           d.dy > g.newest_full as after_newest_full,
           d.st = 'running' as running,
           (p_today - d.dy) <= 30 as within_30
      from d cross join g left join mf on mf.mo = date_trunc('month', d.dy)::date),
  kp as (
    select k.*, (k.is_newest_full or k.after_newest_full or k.running or k.within_30
                 or (k.month_copy and k.within_12_months)) as policy_keep from k),
  anchor as (
    select kp.dy as inc_day,
           (select max(f.dy) from d f where f.kd = 'full' and f.st = 'done' and f.dy <= kp.dy) as full_day
      from kp where kp.kd = 'incremental' and kp.policy_keep),
  c as (
    select kp.*, exists (select 1 from anchor a where kp.dy between a.full_day and a.inc_day) as in_kept_chain from kp)
  select c.dy, c.og, c.kd, c.st,
         case when c.blocked is not null or c.policy_keep or c.in_kept_chain then 'keep' else 'delete' end,
         case when c.blocked is not null then c.blocked
              when c.is_newest_full then 'the newest complete full copy'
              when c.after_newest_full then 'part of the newest restore chain (the newest full copy and every day after it)'
              when c.running then 'still being written'
              when c.within_30 then 'within 30 days'
              when c.month_copy and c.within_12_months and c.kd = 'full' then 'the first complete full copy of its month, within 12 months'
              when c.month_copy and c.within_12_months then 'the last complete copy of a month with no full copy, within 12 months'
              when c.in_kept_chain then 'needed by a kept kb_chunks restore chain (its full copy, or a day between)'
              when c.month_copy then 'a monthly copy older than 12 months'
              when c.st <> 'done' then 'an incomplete export (' || coalesce(nullif(c.st, ''), 'unknown') || ') older than 30 days'
              else 'a daily copy older than 30 days'
         end
    from c order by c.dy;
$function$


CREATE OR REPLACE FUNCTION public.fn_backup_prune_dropbox_allowed(p_bucket text, p_path text, p_dedupe_key text, p_doc_type text, p_dropbox_path text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(p_doc_type = 'Database export'
                  and p_dedupe_key = 'EXPORT:' || p_path
                  and public.fn_backup_prune_path_allowed(p_bucket, p_path)
                  and p_dropbox_path = '/QuotesDone Backup/Company/Database Exports/' || left(p_path, 7) || '/' || p_path,
                  false);
$function$


CREATE OR REPLACE FUNCTION public.fn_backup_prune_mode()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((select 'delete' from public.app_secrets s where s.key = 'backup_prune_mode' and s.value = 'delete'), 'dry_run');
$function$


CREATE OR REPLACE FUNCTION public.fn_backup_prune_path_allowed(p_bucket text, p_path text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- A table name starts with a letter, and no path segment may start with '_' except the exact
  -- _manifest.json. Final review of #672 (HIGH): '[a-z0-9_]+' let v1's inventory of the backups bucket
  -- itself, <day>/_storage_backups.json, through (the bucket name has no hyphen), so a document inventory
  -- would have been deleted. The same rule is in supabase/functions/_shared/backup_prune_allow.ts.
  select coalesce(p_bucket = 'backups'
         and (p_path ~ '^\d{4}-\d{2}-\d{2}/_manifest\.json$' or p_path !~ '/_')
         and (p_path ~ '^\d{4}-\d{2}-\d{2}/_manifest\.json$'                      -- the day's manifest
           or p_path ~ '^\d{4}-\d{2}-\d{2}/[a-z][a-z0-9_]*/page_\d{4}\.json$'     -- backup v1 (paged) and v2
           or p_path ~ '^\d{4}-\d{2}-\d{2}/[a-z][a-z0-9_]*\.json$'),              -- backup v1 (one file per table)
         false);
$function$


CREATE OR REPLACE FUNCTION public.fn_backup_prune_plan(p_today date DEFAULT NULL::date)
 RETURNS TABLE(day date, origin text, kind text, day_status text, decision text, reason text, objects bigint, bytes bigint, dropbox_files bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select p.day, p.origin, p.kind, p.day_status, p.decision, p.reason, s.n, s.b,
         (select count(*) from public.doc_backups b
           where left(b.dedupe_key, 18) = 'EXPORT:' || to_char(p.day, 'YYYY-MM-DD') || '/' and b.status <> 'pruned'
             and public.fn_backup_prune_dropbox_allowed(b.bucket, b.path, b.dedupe_key, b.doc_type, b.dropbox_path))
    from public.fn_backup_prune_decide(public.fn_backup_prune_days(),
                                       coalesce(p_today, (now() at time zone 'Asia/Dubai')::date)) p
    cross join lateral (select count(*) as n, coalesce(sum((o.metadata->>'size')::bigint), 0)::bigint as b
                          from storage.objects o
                         where o.bucket_id = 'backups'
                           and o.name collate "C" >= to_char(p.day, 'YYYY-MM-DD') || '/' and o.name collate "C" < to_char(p.day, 'YYYY-MM-DD') || '0'
                           and o.name like to_char(p.day, 'YYYY-MM-DD') || '/%'
                           and public.fn_backup_prune_path_allowed(o.bucket_id, o.name)) s;
$function$


CREATE OR REPLACE FUNCTION public.fn_backup_prune_recheck()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_days jsonb := public.fn_backup_prune_days(); v_n integer := 0; x record;
begin
  v_days := v_days || coalesce((
    select jsonb_agg(jsonb_build_object('day', bl.day, 'origin', bl.origin, 'kind', bl.kind, 'status', bl.day_status))
      from public.backup_prune_log bl
     where bl.mode = 'delete' and bl.cancelled_at is null and bl.dropbox_done_at is null
       and not exists (select 1 from jsonb_array_elements(v_days) e where (e->>'day')::date = bl.day)), '[]'::jsonb);
  for x in select bl.id, pd.decision, pd.reason
             from public.backup_prune_log bl
             left join public.fn_backup_prune_decide(v_days, (now() at time zone 'Asia/Dubai')::date) pd on pd.day = bl.day
            where bl.mode = 'delete' and bl.cancelled_at is null
              and (bl.storage_deleted_at is null or bl.dropbox_done_at is null)
              and pd.decision is distinct from 'delete' loop
    perform public.fn_backup_prune_cancel(x.id, coalesce(x.reason, 'the day is no longer listed'));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$


CREATE OR REPLACE FUNCTION public.fn_backup_prune_storage_done(p_log_id bigint, p_removed integer, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_log public.backup_prune_log; v_left bigint;
begin
  select * into v_log from public.backup_prune_log l where l.id = p_log_id and l.mode = 'delete';
  if not found then raise exception 'fn_backup_prune_storage_done: no delete-mode log row %', p_log_id; end if;
  update public.backup_prune_log l set objects_removed = l.objects_removed + greatest(coalesce(p_removed, 0), 0) where l.id = p_log_id;
  if p_error is not null then
    update public.backup_prune_log l set storage_attempts = l.storage_attempts + 1, storage_error = left(p_error, 1000) where l.id = p_log_id;
    return jsonb_build_object('ok', false, 'day', v_log.day, 'error', left(p_error, 300));
  end if;
  select count(*) into v_left from storage.objects o
   where o.bucket_id = 'backups' and o.name like to_char(v_log.day, 'YYYY-MM-DD') || '/%'
     and public.fn_backup_prune_path_allowed(o.bucket_id, o.name);   -- the inventories that stay are not "left"
  if v_left = 0 then
    update public.backup_prune_log l set storage_deleted_at = now(), storage_error = null where l.id = p_log_id;
    update public.table_export_run r set pruned_at = now() where r.stamp = v_log.day;
  end if;
  return jsonb_build_object('ok', true, 'day', v_log.day, 'left', v_left);
end $function$


CREATE OR REPLACE FUNCTION public.fn_backup_prune_storage_next()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_log public.backup_prune_log; v_cancelled integer; v_names text[];
begin
  if public.fn_backup_prune_mode() <> 'delete' then return jsonb_build_object('log_id', null, 'reason', 'dry run'); end if;
  v_cancelled := public.fn_backup_prune_recheck();
  select * into v_log from public.backup_prune_log l
   where l.mode = 'delete' and l.storage_deleted_at is null and l.cancelled_at is null and l.storage_attempts < 3
   order by l.day limit 1 for update skip locked;
  if not found then return jsonb_build_object('log_id', null, 'cancelled', v_cancelled); end if;
  select coalesce(array_agg(o.name order by o.name), '{}') into v_names
    from (select o2.name from storage.objects o2
           where o2.bucket_id = 'backups'
             and o2.name collate "C" >= to_char(v_log.day, 'YYYY-MM-DD') || '/' and o2.name collate "C" < to_char(v_log.day, 'YYYY-MM-DD') || '0'
             and o2.name like to_char(v_log.day, 'YYYY-MM-DD') || '/%'
             and public.fn_backup_prune_path_allowed(o2.bucket_id, o2.name)
             -- 15 Sep 2026 (the guard): only a file whose Dropbox copy was uploaded AND verified. A file
             -- without one stays, and fn_backup_prune_storage_done counts it as left, so the day is never
             -- marked deleted and its Dropbox half never starts.
             and exists (select 1 from public.doc_backups d
                          where d.bucket = o2.bucket_id and d.path = o2.name
                            and d.status = 'done' and d.verified_at is not null)
           order by o2.name limit 1000) o;
  return jsonb_build_object('log_id', v_log.id, 'day', v_log.day, 'names', to_jsonb(v_names));
end $function$


CREATE OR REPLACE FUNCTION public.fn_backup_prune_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_mode text := public.fn_backup_prune_mode();
  v_export public.table_export_run;
  v_pass jsonb := null; v_logged int := 0; v_items jsonb := '[]'::jsonb; v_settle jsonb; x record;
begin
  -- A PASS: once per Dubai day, after that day's export finished.
  select * into v_export from public.table_export_run r where r.stamp = v_today;
  if found and (v_export.status = 'done' or (v_export.status = 'failed' and v_export.attempts >= 6))
     and not exists (select 1 from public.agent_runs ar
                      where ar.agent = 'it_engineer' and ar.counts->>'job' = 'backup_prune'
                        and (ar.started_at at time zone 'Asia/Dubai')::date = v_today) then
    insert into public.backup_prune_log (decided_for, mode, day, origin, kind, day_status, reason, objects, bytes, dropbox_files)
    select v_today, v_mode, p.day, p.origin, p.kind, p.day_status, p.reason, p.objects, p.bytes, p.dropbox_files
      from public.fn_backup_prune_plan(v_today) p
     where p.decision = 'delete'
       and not exists (select 1 from public.backup_prune_log l
                        where l.day = p.day and l.mode = 'delete' and l.storage_deleted_at is null and l.cancelled_at is null)
    on conflict do nothing;
    get diagnostics v_logged = row_count;
    v_pass := jsonb_build_object('days', v_logged);
    insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
    values ('it_engineer', 'ok', jsonb_build_object('job', 'backup_prune', 'mode', v_mode, 'days', v_logged),
            left(case when v_mode = 'delete' then 'Backup retention: ' || v_logged || ' export day(s) logged for deletion.'
                      else 'Backup retention DRY RUN: ' || v_logged || ' export day(s) would be deleted; nothing was touched.' end, 500),
            now(), now());
  end if;

  if v_mode = 'delete' then
    perform public.fn_backup_prune_recheck();
    -- the day's Dropbox copies leave the upload queue and join the delete queue; the status they had is kept.
    -- 15 Sep 2026 (the guard): only AFTER the day's storage deletion finished -- which itself happens only
    -- under verified copies -- and only a copy that was uploaded and verified. Before, every row of the day
    -- moved at once, uploaded or not, so a never-uploaded file was "deleted" from Dropbox (a missing path
    -- is success), marked pruned, and never uploaded while storage still held the only copy.
    update public.doc_backups b set status = 'prune_pending', status_before_prune = b.status, claimed_at = null, claimed_by = null
      from public.backup_prune_log l
     where l.mode = 'delete' and l.cancelled_at is null and l.dropbox_done_at is null
       and l.storage_deleted_at is not null
       and left(b.dedupe_key, 18) = 'EXPORT:' || to_char(l.day, 'YYYY-MM-DD') || '/'
       and b.status = 'done' and b.verified_at is not null
       and public.fn_backup_prune_dropbox_allowed(b.bucket, b.path, b.dedupe_key, b.doc_type, b.dropbox_path);
    update public.doc_backups b set status = 'pruned', error = null
     where b.status = 'prune_pending' and b.dropbox_path is null;
    update public.backup_prune_log l set dropbox_done_at = now()
     where l.mode = 'delete' and l.cancelled_at is null and l.dropbox_done_at is null
       and not exists (select 1 from public.doc_backups b
                        where left(b.dedupe_key, 18) = 'EXPORT:' || to_char(l.day, 'YYYY-MM-DD') || '/' and b.status <> 'pruned');
  end if;

  -- A prune failure is an it_engineer finding; the same settle closes it once the deletion completes.
  for x in select l.* from public.backup_prune_log l
            where l.mode = 'delete' and l.storage_deleted_at is null and l.cancelled_at is null
              and (l.storage_attempts >= 3 or l.decided_at < now() - interval '2 days') loop
    v_items := v_items || jsonb_build_object('item', 'storage:' || x.day, 'owner_seat', 'it_engineer', 'subject', 'backups',
      'title', 'Backup retention could not remove the ' || x.day || ' export from the backups bucket',
      'blast', 'agent_facing', 'affected', 1,
      'evidence', jsonb_build_object('backup_prune_log_id', x.id, 'attempts', x.storage_attempts, 'error', x.storage_error,
                                     'objects_removed', x.objects_removed, 'logged_at', x.decided_at));
  end loop;
  for x in select split_part(substr(b.dedupe_key, 8), '/', 1) as dy, count(*) as n, max(b.error) as err
             from public.doc_backups b
            where b.status in ('prune_pending', 'pruning') and b.prune_attempts >= 5
            group by 1 loop
    v_items := v_items || jsonb_build_object('item', 'dropbox:' || x.dy, 'owner_seat', 'it_engineer', 'subject', 'dropbox',
      'title', 'Backup retention could not remove ' || x.n || ' Dropbox copy(ies) of the ' || x.dy || ' export',
      'blast', 'agent_facing', 'affected', x.n, 'evidence', jsonb_build_object('last_error', x.err));
  end loop;
  v_settle := public.fn_it_duty_settle('backup_prune', v_items);

  return jsonb_build_object('mode', v_mode, 'pass', v_pass,
    'storage_pending', case when v_mode = 'delete' then (select count(*) from public.backup_prune_log l
                          where l.mode = 'delete' and l.storage_deleted_at is null and l.cancelled_at is null) else 0 end,
    'dropbox_pending', case when v_mode = 'delete' then (select count(*) from public.doc_backups b
                          where b.status = 'prune_pending' and b.prune_attempts < 5) else 0 end,
    'findings', v_settle->'failing');
end $function$


CREATE OR REPLACE FUNCTION public.fn_backup_sandbox_enqueue(p_tag text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_n integer;
begin
  if coalesce(p_tag, '') !~ '^[A-Za-z0-9-]{6,40}$' then
    raise exception 'fn_backup_sandbox_enqueue: the tag is 6-40 letters, digits or hyphens (got %)', p_tag;
  end if;
  perform set_config('qd.backup_sandbox', p_tag, true);
  v_n := public.fn_enqueue_doc_backups();
  perform set_config('qd.backup_sandbox', '', true);
  return jsonb_build_object('tag', p_tag, 'enqueued', v_n,
    'sandbox_rows', (select count(*) from public.doc_backups d where d.entity = 'zz_demo' and d.dedupe_key like 'SBX:' || p_tag || ':%'));
end $function$


CREATE OR REPLACE FUNCTION public.fn_backup_source_registry()
 RETURNS TABLE(source text, kind text, bucket text, backed_up boolean, enqueue_rule text, reason text)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  values
    -- ── (a) backed up by an owner rule: each names the fn_enqueue_doc_backups section that files it ──
    ('leads.license_doc_path',               'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.egr_doc_path',                   'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.insurance_doc_path',             'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.vat_doc_path',                   'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.iso_doc_path',                   'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.manufacturer_auth_doc_path',     'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.company_profile_doc_path',       'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.catalog_doc_paths',              'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS (catalogue)', null),
    ('leads.signed_terms_path',              'column', 'signed-terms',  true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('customers.signed_terms_path',          'column', 'signed-terms',  true,  'fn_enqueue_doc_backups: CUSTOMERS', null),
    ('inquiries.drawing_file_path',          'column', 'drawing-files', true,  'fn_enqueue_doc_backups: INQUIRIES', null),
    ('transactions.doc_path',                'column', 'finance-docs',  true,  'fn_enqueue_doc_backups: REVENUE INVOICES', null),
    ('conversation_archive.pdf_path',        'column', 'backups',       true,  'fn_enqueue_doc_backups: CORRESPONDENCE', null),
    ('backups/<YYYY-MM-DD>/<table>/page_NNNN.json', 'export', 'backups', true, 'fn_enqueue_doc_backups: TABLE EXPORTS (written daily by supabase/functions/backup; the tables are fn_table_export_list()); kept 90 days, Friday full copies 12 months (fn_backup_prune_tick)', null),
    -- The accountant's four (open gaps until 14 Sep 2026, closed by
    -- the_accountant_files_the_year_end_pack_in_dropbox_and_the_backups_bucket.sql). A path stored as
    -- '<bucket>/<path>' names its bucket itself, so the bucket column is null for those two.
    ('accountant_month_close.pdf_path',      'column', 'finance-reports', true, 'fn_enqueue_doc_backups: ACCOUNTING', null),
    ('accountant_month_close.csv_path',      'column', 'finance-reports', true, 'fn_enqueue_doc_backups: ACCOUNTING', null),
    ('accountant_issued_document.file_path', 'column', null,              true, 'fn_enqueue_doc_backups: ACCOUNTING', null),
    ('bank_statement_intake.doc_path',       'column', null,              true, 'fn_enqueue_doc_backups: ACCOUNTING', null),

    -- ── (a) the buckets: every file an owner rule did not file is filed by the STORAGE SWEEP ──
    ('supplier-docs',    'bucket', 'supplier-docs',    true, 'fn_enqueue_doc_backups: SUPPLIERS; STORAGE SWEEP for every other file (inbound/, legal/, catalog/ ...)', null),
    ('signed-terms',     'bucket', 'signed-terms',     true, 'fn_enqueue_doc_backups: SUPPLIERS, CUSTOMERS; STORAGE SWEEP for every other signed record', null),
    ('drawing-files',    'bucket', 'drawing-files',    true, 'fn_enqueue_doc_backups: INQUIRIES; STORAGE SWEEP for every other file, the anonymised redacted/ copies included', null),
    ('finance-docs',     'bucket', 'finance-docs',     true, 'fn_enqueue_doc_backups: REVENUE INVOICES; STORAGE SWEEP for every other file', null),
    ('backups',          'bucket', 'backups',          true, 'fn_enqueue_doc_backups: CORRESPONDENCE, ACCOUNTING (the year-end pack in backups/accountant/year-end/), TABLE EXPORTS; dropbox_backup renders generated documents into backups/generated/; STORAGE SWEEP for everything outside the dated export folders, conversations/ and generated/ (archives/, engineering/, imports/ ...)', null),
    ('quote-files',      'bucket', 'quote-files',      true, 'fn_enqueue_doc_backups: STORAGE SWEEP (suppliers'' quotation files and the regenerated quotations)', null),
    ('compliance-docs',  'bucket', 'compliance-docs',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP (compliance sources as downloaded, the UAE library)', null),
    ('receipt-files',    'bucket', 'receipt-files',    true, 'fn_enqueue_doc_backups: ACCOUNTING (bank statements); STORAGE SWEEP for the expense receipts (the inbound mailbox keeps about a month)', null),
    ('agent-docs',       'bucket', 'agent-docs',       true, 'fn_enqueue_doc_backups: STORAGE SWEEP (quotations and invoices as sent, weekly reports, incident PDFs)', null),
    ('finance-reports',  'bucket', 'finance-reports',  true, 'fn_enqueue_doc_backups: ACCOUNTING (month close); STORAGE SWEEP for every other report and legal notice', null),
    ('reports',          'bucket', 'reports',          true, 'fn_enqueue_doc_backups: STORAGE SWEEP (board and executive report PDFs; their rows are not in the daily table export)', null),
    ('social-media',     'bucket', 'social-media',     true, 'fn_enqueue_doc_backups: STORAGE SWEEP (generated post cards and avatars; not in the repository)', null),
    ('brand',            'bucket', 'brand',            true, 'fn_enqueue_doc_backups: STORAGE SWEEP (brand kit, signature and stamp images; not in the repository)', null),
    ('company-seal',     'bucket', 'company-seal',     true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the company stamp and signature, private since 6 Oct 2026; read by pdf_native with the service role)', null),
    ('evidence',         'bucket', 'evidence',         true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the laptop''s sandbox and campaign evidence moved off the Desktop on 26 Oct 2026: screenshots, recordings, files over 5 MB and real third parties'' documents kept out of git; private, service role only; indexed by sha256 in docs/reports/EVIDENCE_INDEX.md)', null),
    ('kb-import-assets', 'bucket', 'kb-import-assets', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (knowledge import runs; only part of it is in the repository)', null),
    ('site',             'bucket', 'site',             true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the static website pages as first published)', null),
    ('marketing-media',  'bucket', 'marketing-media',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the media of the posts the founder and Claude ingest to the marketing seat; private, not in the repository)', null),

    -- ── (a) columns whose files are filed by the STORAGE SWEEP of the bucket they sit in ──
    -- measured 15 Sep 2026 where rows exist; "no writer today" where no code writes the column yet
    ('quotes.original_file_path',            'column', 'quote-files',      true, 'fn_enqueue_doc_backups: STORAGE SWEEP (written by supplier_api)', null),
    ('accountant_founder_close_pack.pdf_path', 'column', 'finance-reports', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the accountant function renders the founder close pack into finance-reports)', null),
    ('quote_spec_hold.pdf_path',             'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (bucket in quote_spec_hold.pdf_bucket; the regenerated quotations sit in quote-files)', null),
    ('quote_reviews.original_file_path',     'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('quote_committed_items.sub_quote_path', 'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('quote_items.datasheet_path',           'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('rfq_archives.archive_path',            'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (bucket in rfq_archives.bucket; backups/archives/ is swept)', null),
    ('compliance_sources.doc_path',          'column', 'compliance-docs',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP (16 of 16 paths in compliance-docs)', null),
    ('support_artifact.storage_path',        'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('support_document_intake.storage_path', 'column', 'supplier-docs',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the path is the one written into leads.*_doc_path)', null),
    ('wa_document_intake.storage_path',      'column', 'supplier-docs',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the path is the one written into leads.*_doc_path)', null),
    ('messages.attachment_path',             'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (bucket chosen by the portal, recorded in public.documents)', null),
    ('customer_calls.recording_path',        'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('refunds.doc_path',                     'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('supplier_dues.demand_letter_path',     'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today; the legal notices on file sit in supplier-docs/legal/ and finance-reports/legal/)', null),
    ('supplier_dues.case_file_path',         'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('supplier_dues.evidence_terms_path',    'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('expense_entries.doc_path',             'column', 'receipt-files',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (52 of 52 paths in receipt-files; the inbound mailbox keeps about a month)', null),
    ('doc_reviews.file_path',                'column', 'supplier-docs',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (7 of 7 paths in supplier-docs/inbound/, none filed by an owner rule)', null),
    ('supplier_catalog.source_document_path','column', 'supplier-docs',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (written by supplier_catalog_ingest into supplier-docs/catalog/)', null),
    ('drawing_redaction_runs.source_path',   'column', 'drawing-files',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the customer''s original drawing; also INQUIRIES)', null),
    ('accountant_weekly_report.pdf_path',    'column', 'agent-docs',       true, 'fn_enqueue_doc_backups: STORAGE SWEEP (agent-docs/accountant/weekly/)', null),
    ('accountant_spend_report.pdf_path',     'column', 'finance-reports',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP (finance-reports/accountant/spend/)', null),
    ('finance_reports.html_path',            'column', 'finance-reports',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP', null),
    ('finance_reports.xlsx_path',            'column', 'finance-reports',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP', null),
    ('finance_reports.pdf_path',             'column', 'finance-reports',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP', null),
    ('board_reports.pdf_path',               'column', 'reports',          true, 'fn_enqueue_doc_backups: STORAGE SWEEP (20 of 20 paths in reports)', null),
    ('exec_reports.pdf_path',                'column', 'reports',          true, 'fn_enqueue_doc_backups: STORAGE SWEEP (2 of 2 paths in reports)', null),
    ('it_incident.pdf_path',                 'column', 'agent-docs',       true, 'fn_enqueue_doc_backups: STORAGE SWEEP (rendered into agent-docs/it_engineer/incidents/)', null),
    ('ceo_daily_digest.pdf_path',            'column', 'agent-docs',       true, 'fn_enqueue_doc_backups: STORAGE SWEEP (rendered into agent-docs/ceo/daily_brief/)', null),
    ('ceo_weekly_report.pdf_path',           'column', 'agent-docs',       true, 'fn_enqueue_doc_backups: STORAGE SWEEP (rendered into agent-docs by resilience_ping renderPdfAndAttach)', null),
    ('marketing_post.media_paths',           'column', 'marketing-media',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP (marketing-media/posts/<ingest_key>/, written by marketing_channels ingest)', null),
    ('marketing_post.video_path',            'column', 'marketing-media', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (marketing-media/posts/<ingest_key>/, the calendar''s video, written by marketing_channels ingest)', null),
    ('marketing_post.cover_path',            'column', 'marketing-media', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (marketing-media/posts/<ingest_key>/, the cover image, written by marketing_channels ingest)', null),
    ('marketing_post_variant.cover_path',    'column', 'marketing-media', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (marketing-media, a platform''s own cover image)', null),
    ('marketing_campaign.calendar_pdf_path', 'column', 'agent-docs',     true, 'fn_enqueue_doc_backups: STORAGE SWEEP (agent-docs/marketing/calendar/<campaign_key>/, the monthly calendar PDF the founder approves)', null),
    ('marketing_campaign.calendar_xlsx_path', 'column', 'agent-docs',     true, 'fn_enqueue_doc_backups: STORAGE SWEEP (agent-docs/marketing/calendar/<campaign_key>/, the same calendar as a spreadsheet)', null),
    ('ceo_weekly_review.pdf_path',           'column', 'agent-docs',     true, 'fn_enqueue_doc_backups: STORAGE SWEEP (agent-docs/ceo/weekly_review/, the CEO''s one-page weekly review PDF)', null),

    -- ── (b) EXEMPT (not a file or not ours) ──
    ('doc_backups.dropbox_path',             'column', null, false, null, 'EXEMPT (not a file or not ours): the Dropbox destination of a backup, not a source'),
    ('pdpl_erase_files.storage_path',        'column', null, false, null, 'EXEMPT (not a file or not ours): the PDPL erasure ledger names files being REMOVED under a data subject''s request; fn_backup_sweep_objects never offers a file it names, so an erased file is never copied again'),
    ('pdpl_erase_files.dropbox_path',        'column', null, false, null, 'EXEMPT (not a file or not ours): the PDPL erasure ledger names Dropbox copies being REMOVED; never a source'),
    -- The knowledge source paths are LABELS: none of the sampled paths exists as a storage object or in
    -- the repository (review, 15 Sep 2026). The knowledge is the table rows, which the daily table export
    -- (fn_table_export_list) carries to Dropbox.
    ('support_knowledge.source_path',        'column', null, false, null, 'EXEMPT (not a file or not ours): a label naming where a knowledge entry came from, not a stored file; the entries themselves are table rows in the daily table export'),
    ('ops_knowledge.source_path',            'column', null, false, null, 'EXEMPT (not a file or not ours): a label naming where a knowledge entry came from, not a stored file; the entries themselves are table rows in the daily table export'),
    ('ceo_knowledge.source_path',            'column', null, false, null, 'EXEMPT (not a file or not ours): a label naming where a knowledge entry came from, not a stored file; the entries themselves are table rows in the daily table export'),
    ('cad_read_jobs.source_path',            'column', null, false, null, 'EXEMPT (not a file or not ours): a work-queue pointer to the customer''s original drawing in drawing-files, which is backed up through inquiries.drawing_file_path; the job holds no second copy'),
    ('marketing_first_touch.landing_path',  'column', null, false, null, 'EXEMPT (not a file or not ours): the site page (a URL path such as /en/suppliers) a supplier first landed on from a post, not a stored file; the row is in the daily table export'),
    ('marketing_asset_feature.asset_path',  'column', null, false, null, 'EXEMPT (not a file or not ours): a pointer to a post video already in marketing-media (backed up through marketing_post.video_path and media_paths); the feature row measures it and holds no second copy'),
    ('conversation_retention_pdf.pdf_path',  'column', null, false, null, 'EXEMPT (not a file or not ours): a pointer, kept after the text is removed, to the conversation PDF already in backups/conversations/ (backed up through conversation_archive.pdf_path); it holds no second copy'),
    ('action_class_demand.on_revenue_path', 'column', null, false, null, 'EXEMPT (not a file or not ours): a boolean saying whether an action_class is on the revenue path; it names no file, and the row is in the daily table export'),
    ('ml-models',                            'bucket', null, false, null, 'EXEMPT (not a file or not ours): a copy of a public embedding model downloaded from Hugging Face for the multilingual embedder; it can be fetched again and holds no record'),
    ('supplier_campaign_daily_list.pdf_path', 'column', null, false, null, 'EXEMPT (not a file or not ours): the 18:00 supplier-list PDF is drawn from its own row (rows, pdf_blocks), which is in the daily table export; it can be rendered again'),
    ('demo-assets',                          'bucket', null, false, null, 'EXEMPT (not a file or not ours): a rehearsal fixture (one sample recording), never a record'),

    -- ── (c) EXEMPT (derived): no registry source. The one derived thing left out is a folder, not a
    -- source: signed-terms/registers/ (the customer register compliance_archive uploads to Dropbox
    -- itself), excluded in fn_backup_sweep_objects. The anonymised drawings are derived, but 2 of the 3
    -- redacted files have no original left (review, 15 Sep 2026), so they are kept like any other file. ──
    ('inquiries.drawing_redacted_paths',     'column', 'drawing-files', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (drawing-files/redacted/; derived, but not every original survives)', null),
    ('drawing_redaction_runs.output_paths',  'column', 'drawing-files', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (drawing-files/redacted/; derived, but not every original survives)', null)
$function$


CREATE OR REPLACE FUNCTION public.fn_backup_sweep_objects()
 RETURNS TABLE(bucket text, path text, bytes bigint, created_at timestamp with time zone, entity text, entity_id text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- The cheap filters first, once: without the fence the planner evaluated the owner lookups below for
  -- every object of every swept bucket, 8,369 export pages included (47.8 s measured; 125 ms with it).
  with o as materialized (
    select o.bucket_id, o.name, o.metadata, o.created_at
      from storage.objects o
     where o.bucket_id in (select r.bucket from public.fn_backup_source_registry() r
                            where r.kind = 'bucket' and r.backed_up and r.enqueue_rule like '%STORAGE SWEEP%')
       and right(o.name, 1) <> '/' and o.name !~ '(^|/)\.emptyFolderPlaceholder$'
       and o.name !~* 'zz[ _-]?demo'
       and not (o.bucket_id = 'backups' and o.name ~ '^(\d{4}-\d{2}-\d{2}|conversations)/')
       and not (o.bucket_id = 'signed-terms' and o.name like 'registers/%')
       and not exists (select 1 from public.pdpl_erase_files e where e.bucket = o.bucket_id and e.storage_path = o.name))
  select o.bucket_id, o.name, coalesce((o.metadata->>'size')::bigint, 0), o.created_at, x.entity, x.id
    from o
    cross join lateral (select
        (regexp_match(o.name, '^generated/\d+_(customer_details|inquiry_summary|comparison|supplier_details)_([0-9a-f_]{36}|\d{1,18})\.pdf$', 'i')) as gen,
        split_part(o.name, '/', 2) as seg2, split_part(o.name, '/', 3) as seg3) p
    -- OFFSET 0 keeps this a subquery computed once per row; flattened, it was copied into every reference.
    cross join lateral (select coalesce(
        (select case d.ref_table when 'customers' then 'customer' when 'inquiries' then 'inquiry'
                                 when 'quotes' then 'quote' when 'leads' then 'supplier' end || ':' || d.ref_id
           from public.documents d
          where d.bucket = o.bucket_id and d.path = o.name
            and d.ref_table in ('customers', 'inquiries', 'quotes', 'leads') and coalesce(d.ref_id, '') <> '' limit 1),
        (select 'customer:' || c.customer_id from public.quote_pdf_cache c
          where c.bucket = o.bucket_id and c.path = o.name and c.customer_id is not null limit 1),
        (select 'customer:' || t.customer_id from public.reveal_invoices ri join public.transactions t on t.id = ri.transaction_id
          where ri.bucket = o.bucket_id and ri.path = o.name and t.customer_id is not null limit 1),
        (select 'quote:' || q.id from public.quotes q where o.bucket_id = 'quote-files' and q.original_file_path = o.name limit 1),
        case when o.bucket_id = 'backups' and p.gen is not null then
               case lower(p.gen[1]) when 'customer_details' then 'customer' when 'supplier_details' then 'supplier' else 'inquiry' end
               || ':' || replace(lower(p.gen[2]), '_', '-') end,
        case when o.bucket_id = 'supplier-docs' and p.seg2 ~ '^\d{1,18}$' then 'supplier:' || p.seg2 end,
        case when o.bucket_id = 'drawing-files' and p.seg2 ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then 'inquiry:' || lower(p.seg2) end,
        case when o.bucket_id = 'quote-files' and p.seg3 ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then 'inquiry:' || lower(p.seg3) end,
        'company:storage/' || o.bucket_id) as owner
      offset 0) y
    cross join lateral (select split_part(y.owner, ':', 1) as entity, substr(y.owner, strpos(y.owner, ':') + 1) as id) x
    -- the owner row behind it: is it demo (null when the row is gone), and which customer email, for PDPL.
    -- Each cast is inside CASE behind the shape test that makes it safe.
    left join lateral (select
        case x.entity
          when 'supplier' then (select coalesce(l.is_demo, false) from public.leads l
                                 where l.id = case when x.id ~ '^\d{1,18}$' then x.id::bigint end)
          when 'customer' then (select coalesce(c.is_demo, false) from public.customers c
                                 where c.id = case when x.id ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then x.id::uuid end)
          when 'inquiry'  then (select coalesce(c.is_demo, false) from public.inquiries i left join public.customers c on c.id = i.customer_id
                                 where i.id = case when x.id ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then x.id::uuid end)
          when 'quote'    then (select coalesce(l.is_demo, false) or coalesce(c.is_demo, false)
                                  from public.quotes q left join public.leads l on l.id = q.supplier_id
                                  left join public.inquiries i on i.id = q.inquiry_id left join public.customers c on c.id = i.customer_id
                                 where q.id = case when x.id ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then x.id::uuid end)
        end as demo,
        case x.entity
          when 'customer' then (select c.email from public.customers c
                                 where c.id = case when x.id ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then x.id::uuid end)
          when 'inquiry'  then (select c.email from public.inquiries i join public.customers c on c.id = i.customer_id
                                 where i.id = case when x.id ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then x.id::uuid end)
          when 'quote'    then (select c.email from public.quotes q join public.inquiries i on i.id = q.inquiry_id
                                  join public.customers c on c.id = i.customer_id
                                 where q.id = case when x.id ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then x.id::uuid end)
        end as email
      offset 0) w on true
   where not coalesce(w.demo, false)
     and not (x.entity <> 'company' and w.demo is null
              and exists (select 1 from public.doc_backups z where z.entity = 'zz_demo' and z.entity_id = x.id))
     and not (w.email is not null and (w.email ~* '@removed\.invalid$'
              or exists (select 1 from public.pdpl_requests r
                          where r.kind = 'delete' and coalesce(r.status, '') not in ('rejected', 'withdrawn', 'cancelled')
                            and lower(r.email) = lower(w.email))));
$function$


CREATE OR REPLACE FUNCTION public.fn_backup_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_last timestamptz; v_status text; v_stale boolean; v_open int; v_subject_rows int;
  v_cov jsonb; v_cov_ok boolean; v_cov_open int := 0; v_date text := to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD');
  v_hb timestamptz; v_hb_silent boolean;
  -- when this watcher started expecting a daily check (the apply of this file)
  c_hb_since constant timestamptz := '2026-09-14 15:00:00+00';
  c_agents constant text[] := array['dropbox_backup','fn:dropbox_backup'];
begin
  select count(*) into v_subject_rows from agent_runs where agent = any(c_agents);
  if v_subject_rows = 0 then
    return jsonb_build_object(
      'ok', false,
      'reason', 'subject_not_found',
      'watched', c_agents,
      'detail', 'No run of any watched backup agent has ever been recorded, so this watcher cannot '
             || 'tell a stopped backup from a renamed one. It alerts nobody rather than reporting '
             || 'catastrophe from an empty lookup. Check the agent name before the backup.');
  end if;

  select started_at, status into v_last, v_status
    from agent_runs where agent = any(c_agents) order by started_at desc limit 1;

  -- HEARTBEAT: silence of the check is an alarm, never a clean bill.
  select max(started_at) into v_hb from agent_runs
   where agent = 'it_engineer' and counts->>'job' = 'dropbox_daily_check' and status in ('ok','warn');
  v_hb_silent := coalesce(v_hb, c_hb_since) < now() - interval '26 hours';
  if v_hb_silent then
    perform public.fn_support_report_to_ceo(
      'it_backup_heartbeat:' || v_date, 'serious',
      'The IT engineer''s daily Dropbox check has not run for '
        || round(extract(epoch from (now() - coalesce(v_hb, c_hb_since))) / 3600)::text || ' hours',
      jsonb_build_object('last_daily_check', v_hb, 'expected_since', c_hb_since, 'watched', 'agent_runs it_engineer job dropbox_daily_check'),
      '[]'::jsonb,
      'Find out why the daily check is not running (resilience_ping -> fn_it_backup_tick -> dropbox_backup mode reconcile). Until it runs, nothing confirms that the backup is complete.',
      p_review_in => interval '1 day', p_source_agent => 'it_engineer');
  end if;

  v_cov := public.fn_backup_coverage();
  v_cov_ok := coalesce((v_cov->>'ok')::boolean, false);
  if not v_cov_ok then
    select count(*) into v_cov_open from agent_actions
     where kind = 'backup_coverage' and agent = 'it_engineer' and coalesce(status,'') in ('pending','needs_review')
       and created_at > now() - interval '20 hours';
    if v_cov_open = 0 then
      insert into agent_actions(agent, kind, status, risk, title, recommendation, target_table, detail)
      values('it_engineer','backup_coverage','pending','medium',
        'Dropbox backup coverage failing: ' || (v_cov->>'failing'),
        'Something that should be in Dropbox has not reached it within 48 hours: '
        || (v_cov->>'not_done_after_48h') || ' queued row(s) not done, '
        || coalesce(v_cov->>'sources_without_a_row','unknown') || ' source(s) with no row, '
        || (v_cov->>'refiles_open_past_48h') || ' refile(s) not verified. Rows: ' || (v_cov->>'not_done_ids') || '.',
        'doc_backups', v_cov);
      -- 19 Oct 2026: one condition is one report. While an earlier escalation is still accepted the CEO holds it;
      -- a new day's key is raised only after that one is completed (12 sat accepted, one per day, before this).
      if not exists (select 1 from public.support_ceo_report
                      where idempotency_key like 'dropbox_backup_escalation:%' and status = 'accepted') then
      perform public.fn_support_report_to_ceo(
        'dropbox_backup_escalation:' || v_date, 'serious',
        'Dropbox backup coverage has been failing for over 48 hours (' || (v_cov->>'failing') || ')',
        v_cov,
        coalesce((select jsonb_agg(jsonb_build_object('handoff_id', id, 'status', status, 'type', detail->>'type'))
                    from agent_actions where kind = 'handoff' and detail->>'type' in ('backup.refile','backup.remediate') and status <> 'done'), '[]'::jsonb),
        'Decide whether the missing documents need the founder''s Dropbox checked by hand or the filing corrected. The IT engineer has raised it and handed each missing file to the sales engineer to refile; this is past 48 hours, which is why it reaches you.',
        p_review_in => interval '1 day', p_source_agent => 'it_engineer');
      end if;
    end if;
  end if;

  v_stale := (v_last < now() - interval '26 hours') or (coalesce(v_status,'') = 'error');
  if not v_stale then
    return jsonb_build_object('ok', v_cov_ok and not v_hb_silent, 'last', v_last, 'status', v_status, 'watched', c_agents,
                              'coverage', v_cov, 'coverage_alerted', not v_cov_ok and v_cov_open = 0,
                              'heartbeat', jsonb_build_object('last_daily_check', v_hb, 'silent', v_hb_silent));
  end if;

  select count(*) into v_open from agent_actions
   where kind = 'backup_alert' and coalesce(status,'') in ('pending','needs_review')
     and created_at > now() - interval '20 hours';

  if v_open = 0 then
    insert into agent_actions(agent, kind, status, risk, title, recommendation, target_table, detail)
    values('it_engineer','backup_alert','pending','high',
      'Document backup to Dropbox has failed or is overdue',
      'The Dropbox document mirror has not completed successfully in the last 26 hours (last: '
      || coalesce(v_last::text,'never') || ', status: ' || coalesce(v_status,'unknown')
      || '). Check the dropbox_backup function and its logs. This concerns stored DOCUMENTS only — '
      || 'the managed Postgres backups are outside this database and are not covered by this check.',
      'agent_runs', jsonb_build_object('last_backup', v_last, 'last_status', v_status, 'watched', c_agents));

    insert into security_events(kind, severity, source, subject, detail)
    values('backup_overdue','high','backup','dropbox document mirror',
      jsonb_build_object('last_backup', v_last, 'last_status', v_status, 'watched', c_agents));

    if v_last < now() - interval '48 hours' then
      perform public.fn_notify_founder(
        'Document backup failing after retry: no successful Dropbox mirror for '
        || round(extract(epoch from (now() - v_last)) / 3600)::text || ' hours',
        'The Dropbox document mirror has now been failing for '
        || round(extract(epoch from (now() - v_last)) / 3600)::text || ' hours (last run: '
        || v_last::text || ', status: ' || coalesce(v_status,'unknown')
        || '). This covers stored DOCUMENTS — supplier files, quotes, drawings. The managed Postgres '
        || 'backups are a separate system outside this database and this alert says nothing about '
        || 'them either way. Verify the dropbox_backup function.',
        'critical', p_kind => 'backup_failed_after_retry', p_dedupe_key => 'backup_failed_after_retry');
    end if;
  end if;

  return jsonb_build_object('alerted', true, 'last', v_last, 'status', v_status,
                            'existing_open', v_open, 'watched', c_agents, 'coverage', v_cov,
                            'heartbeat', jsonb_build_object('last_daily_check', v_hb, 'silent', v_hb_silent));
end
$function$


CREATE OR REPLACE FUNCTION public.fn_ban_overdue_dues()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_days int; v_n int := 0; v_admin text;
begin
  v_days  := coalesce((select num_value from public.gl_settings where key='clawback_ban_days'), 90)::int;
  v_admin := coalesce((select split_part(value,',',1) from public.app_secrets where key='admin_emails'),'management@quotesdone.com');

  for r in
    select d.id, d.supplier_id, d.amount_due, d.admin_fee, d.interest_amount, d.due_date,
           l.company_name, coalesce(l.claimed_by,l.email) as email,
           l.accepted_terms_at, l.accepted_terms_version, l.signed_terms_path, l.banned
    from public.supplier_dues d
    join public.leads l on l.id = d.supplier_id
    where public.fn_supplier_due_is_owed(d.status, d.paid_at)
      and coalesce(d.amount_due,0) > 0
      and d.due_date is not null
      and current_date >= (d.due_date::date + v_days)
      and d.legal_escalated_at is null
  loop
    update public.supplier_dues
       set status = 'legal', legal_stage = 'pending_case', legal_escalated_at = now()
     where id = r.id;

    update public.leads
       set banned = true,
           banned_reason = 'Unpaid refund clawback of AED ' ||
                           round(coalesce(r.amount_due,0)+coalesce(r.admin_fee,0)+coalesce(r.interest_amount,0),2) ||
                           ' more than ' || v_days || ' days past due (due ' || r.due_date::date || ').',
           matching_blocked = true,
           matching_block_reason = 'Banned: unpaid refund clawback escalated to legal'
     where id = r.supplier_id;

    insert into public.founder_alerts(level, event, detail, channel)
    values ('crit', 'supplier_banned_legal',
      coalesce(r.company_name,'Supplier #'||r.supplier_id) || ' has been banned and due #' || r.id ||
      ' escalated to legal: AED ' || round(coalesce(r.amount_due,0)+coalesce(r.admin_fee,0)+coalesce(r.interest_amount,0),2) ||
      ' unpaid for over ' || v_days || ' days. ' ||
      case when r.accepted_terms_at is null
           then '*** NO SIGNED TERMS ON RECORD - the supplier agreement cannot be produced as evidence, so a filing may not be supportable. Verify before instructing the legal agent. ***'
           else 'Terms accepted ' || r.accepted_terms_at::date || ' (version ' || coalesce(r.accepted_terms_version,'?') || ') - available as supporting evidence.'
      end, 'system');

    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_board_review(p_subject text, p_subject_ref text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare adv record; ch jsonb; v_rec text; v_conf numeric; v_supply int; v_rev numeric;
  n_pro int:=0; n_cond int:=0; n_against int:=0; v_out jsonb := '[]'::jsonb; v_held boolean;
begin
  ch := fn_challenge(p_subject,'board','board');
  v_held := (ch->>'stance') = 'held';
  select count(*) into v_supply from leads where approval_status='approved';
  select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) into v_rev from transactions where revealed_at>now()-interval '30 days';

  for adv in select * from board_advisor where active order by advisor_key loop
    if v_held then
      v_rec:='abstain'; v_conf:=0.5;
    elsif adv.advisor_key='risk' and (ch->>'stance')='recommend_against' then
      v_rec:='do_not_proceed'; v_conf:=0.85;
    elsif adv.advisor_key='economist' and v_rev=0 then
      v_rec:='proceed_with_conditions'; v_conf:=0.7;
    elsif adv.advisor_key in ('customer','supplier') and v_supply=0 then
      v_rec:='abstain'; v_conf:=0.5;
    elsif (ch->>'stance')='recommend_against' then
      v_rec:='do_not_proceed'; v_conf:=0.75;
    elsif (ch->>'stance')='concern' then
      v_rec:='proceed_with_conditions'; v_conf:=0.65;
    else
      v_rec:='proceed'; v_conf:=0.6;
    end if;

    insert into board_opinion (subject,subject_ref,advisor_key,recommendation,rationale,confidence)
    values (p_subject,p_subject_ref,adv.advisor_key,v_rec,
      adv.name||' ('||adv.lens||') asks: '||adv.asks||' — '||
      case when v_held then 'The challenge of this proposal is held for reasoning (question #'||(ch->>'held_id')||'); an opinion before it is reasoned would be a guess.'
        when v_rec='do_not_proceed' then 'On the evidence available this fails that test.'
        when v_rec='proceed_with_conditions' then 'Proceed only with a named metric, a captured baseline and a reversal path.'
        when v_rec='abstain' then 'There is no data on this side of the marketplace yet; an opinion would be invention.'
        else 'Nothing in this lens argues against it.' end, v_conf);

    if v_rec='proceed' then n_pro:=n_pro+1;
    elsif v_rec='proceed_with_conditions' then n_cond:=n_cond+1;
    elsif v_rec='do_not_proceed' then n_against:=n_against+1; end if;

    v_out := v_out || jsonb_build_array(jsonb_build_object('advisor',adv.name,'lens',adv.lens,'recommendation',v_rec,'confidence',v_conf));
  end loop;

  return jsonb_build_object('subject',p_subject,'proceed',n_pro,'with_conditions',n_cond,
    'against',n_against,'abstained',(select count(*) from board_advisor where active)-n_pro-n_cond-n_against,
    'board_verdict', case when v_held then 'HELD — the challenge is not yet reasoned'
                          when n_against>0 then 'DO NOT PROCEED' when n_cond>0 then 'PROCEED WITH CONDITIONS' else 'PROCEED' end,
    'challenge_stance', ch->>'stance', 'challenge_held_id', ch->'held_id', 'opinions', v_out);
end $function$


CREATE OR REPLACE FUNCTION public.fn_budget_available(p_dept text)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select greatest(
    coalesce(b.monthly_aed, 0)
    - coalesce((select sum(l.cost_aed) from ai_cost_log l
                 where l.dept_key = any(public.fn_dept_scope(b.dept_key))
                   and l.occurred_at >= date_trunc('month', now())), 0),
    0)
  from department_budget b
  where b.dept_key = public.fn_dept_canonical(p_dept);
$function$


CREATE OR REPLACE FUNCTION public.fn_business_entity_list(p_entity text, p_filter text DEFAULT NULL::text, p_limit integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb; e text := lower(btrim(coalesce(p_entity,''))); f text := btrim(coalesce(p_filter,'')); n int := least(greatest(coalesce(p_limit,25),1),200);
begin
  if e in ('customer','buyer') then
    select jsonb_agg(to_jsonb(c)) into v from (select id,email,phone,created_at from public.customers order by created_at desc limit n) c;
  elsif e in ('supplier','lead','vendor') then
    select jsonb_agg(to_jsonb(l)) into v from (
      select id,company_name,contact_name,email,phone,approval_status,created_at from public.leads
       where f='' or company_name ilike '%'||f||'%' or approval_status=f
       order by (approval_status='approved') desc, created_at desc limit n) l;
  elsif e in ('inquiry','rfq','request') then
    select jsonb_agg(to_jsonb(i)) into v from (
      select id,customer_id,category,status,created_at from public.inquiries
       where f='' or status=f or category ilike '%'||f||'%' order by created_at desc limit n) i;
  elsif e in ('quote','quotation','offer') then
    select jsonb_agg(to_jsonb(q)) into v from (select id,inquiry_id,supplier_id,quote_amount,status,created_at from public.quotes order by created_at desc limit n) q;
  elsif e in ('transaction','payment','order','reveal') then
    select jsonb_agg(to_jsonb(t)) into v from (select id,inquiry_id,supplier_id,customer_id,quote_amount from public.transactions limit n) t;
  else
    return jsonb_build_object('ok',false,'error','unknown entity "'||e||'". Use: customer, supplier, inquiry, quote or transaction.');
  end if;
  return jsonb_build_object('ok',true,'entity',e,'filter',nullif(f,''),'items',coalesce(v,'[]'::jsonb),'count',jsonb_array_length(coalesce(v,'[]'::jsonb)));
end $function$


CREATE OR REPLACE FUNCTION public.fn_business_entity_lookup(p_entity text, p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb; e text := lower(btrim(coalesce(p_entity,''))); k text := btrim(coalesce(p_key,''));
begin
  if k = '' then return jsonb_build_object('ok',false,'error','a key is required (id, email, company name or phone)'); end if;
  if e in ('customer','buyer') then
    select to_jsonb(c) into v from public.customers c where c.id::text=k or lower(c.email)=lower(k) or c.phone=k limit 1;
  elsif e in ('supplier','lead','vendor') then
    select to_jsonb(l) into v from public.leads l where l.id::text=k or lower(l.email)=lower(k) or l.company_name ilike k or l.phone=k limit 1;
  elsif e in ('inquiry','rfq','request') then
    select to_jsonb(i) into v from public.inquiries i where i.id::text=k limit 1;
  elsif e in ('quote','quotation','offer') then
    select to_jsonb(q) into v from public.quotes q where q.id::text=k limit 1;
  elsif e in ('transaction','payment','order','reveal') then
    select to_jsonb(t) into v from public.transactions t where t.id::text=k limit 1;
  else
    return jsonb_build_object('ok',false,'error','unknown entity "'||e||'". Use: customer, supplier, inquiry, quote or transaction.');
  end if;
  if v is null then return jsonb_build_object('ok',true,'entity',e,'key',k,'found',false); end if;
  return jsonb_build_object('ok',true,'entity',e,'found',true,'profile',v);
end $function$


CREATE OR REPLACE FUNCTION public.fn_business_entity_summary()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'as_of', now(),
    'customers',            (select count(*) from public.customers),
    'customers_with_inquiry',(select count(distinct customer_id) from public.inquiries where customer_id is not null),
    'suppliers_total',      (select count(*) from public.leads),
    'suppliers_approved',   (select count(*) from public.leads where approval_status='approved'),
    'suppliers_prospective',(select count(*) from public.leads where coalesce(approval_status,'') <> 'approved'),
    'sendable_supplier_pool',(select coalesce(sum(sendable),0)::int from public.v_supply_gap),
    'inquiries',            (select count(*) from public.inquiries),
    'quotes',               (select count(*) from public.quotes),
    'transactions',         (select count(*) from public.transactions),
    'categories_total',     (select count(*) from public.catalog_supplier_categories),
    'categories_at_target', (select count(*) from public.v_supply_gap where approved >= 10));
$function$


