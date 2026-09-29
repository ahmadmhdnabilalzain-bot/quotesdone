-- PROBE for the_it_engineer_watches_each_providers_weekly_cost_and_names_the_cause.sql (founder instruction 1013 item 8).
-- A pure probe: it always raises CHK<<...>>, so every row it writes (model calls, Twilio days, findings) rolls back.
-- Seat: it_engineer. What it proves:
--   1. the jump rule: the floor and the multiple both have to be crossed;
--   2. an OpenRouter rise opens a finding owned by the seat whose calls rose, naming seat / task / model;
--   3. a Twilio rise opens a finding owned by customer_support, naming the costliest day;
--   4. every provider gets a row, journal-read ones with a 30-day period;
--   5. the next week, with the rise gone, the OpenRouter finding closes itself;
--   6. nothing was capped: the tick changes no gate, hold or limit (it writes only its own week row and findings).
do $probe$
declare
  r1 jsonb; r2 jsonb; v_bad text := ''; v_week date := (now() at time zone 'Asia/Dubai')::date;
  v_open_before int; f record;
begin
  select count(*) into v_open_before from public.it_engineer_finding where issue_key like 'duty:cost_watch:%' and closed_at is null;

  if public.fn_it_cost_jumped(10, 0) then v_bad := v_bad || ' floor_ignored'; end if;
  if not public.fn_it_cost_jumped(100, 40) then v_bad := v_bad || ' real_jump_missed'; end if;
  if public.fn_it_cost_jumped(100, 70) then v_bad := v_bad || ' under_floor_rise_flagged'; end if;
  if public.fn_it_cost_jumped(200, 140) then v_bad := v_bad || ' under_multiple_rise_flagged'; end if;

  insert into public.ai_cost_log (occurred_at, fn, seat, agent_key, task_class, model_used, cost_aed, ok)
  select now() - interval '1 hour', 'zz_demo_1013_probe', 'sales_engineer', 'sales_engineer', 'zz_demo_quote_read', 'zz/demo-model', 40, true
    from generate_series(1, 5);
  delete from public.it_spend_daily where source = 'twilio' and day > v_week - 14;
  insert into public.it_spend_daily (day, source, amount_minor, currency)
  select v_week - g, 'twilio', case when g < 7 then 2000 else 100 end, 'USD' from generate_series(0, 13) g;

  r1 := public.fn_it_cost_watch_tick();

  select * into f from public.it_engineer_finding where issue_key = 'duty:cost_watch:openrouter' and closed_at is null;
  if f.issue_key is null then v_bad := v_bad || ' no_openrouter_finding';
  else
    if f.evidence->>'owner_seat' <> 'sales_engineer' then v_bad := v_bad || ' openrouter_owner=' || coalesce(f.evidence->>'owner_seat', 'null'); end if;
    if f.title !~ 'zz_demo_quote_read' then v_bad := v_bad || ' openrouter_cause_unnamed'; end if;
  end if;
  select * into f from public.it_engineer_finding where issue_key = 'duty:cost_watch:twilio' and closed_at is null;
  if f.issue_key is null then v_bad := v_bad || ' no_twilio_finding';
  elsif f.evidence->>'owner_seat' <> 'customer_support' or f.title !~ 'costliest day' then v_bad := v_bad || ' twilio_owner_or_cause'; end if;
  if (select count(*) from public.it_cost_watch_week where week_ending = v_week) <> 5 then v_bad := v_bad || ' not_five_rows'; end if;
  if exists (select 1 from public.it_cost_watch_week where week_ending = v_week and provider in ('supabase', 'vercel', 'resend') and period_days <> 30) then
    v_bad := v_bad || ' journal_period'; end if;

  delete from public.ai_cost_log where fn = 'zz_demo_1013_probe';
  r2 := public.fn_it_cost_watch_tick();
  if exists (select 1 from public.it_engineer_finding where issue_key = 'duty:cost_watch:openrouter' and closed_at is null) then
    v_bad := v_bad || ' openrouter_did_not_close'; end if;

  if v_open_before <> 0 then v_bad := v_bad || ' real_findings_open_before=' || v_open_before; end if;
  if v_bad = '' then raise exception 'CHK<<PROBE OK: first=% | second_settled=%>>', r1::text, (r2->'settled')::text;
  else raise exception 'CHK<<PROBE FAILED:% | %>>', v_bad, r1::text; end if;
end $probe$;
