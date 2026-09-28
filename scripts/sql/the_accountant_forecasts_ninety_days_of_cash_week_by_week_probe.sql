-- PROBE: THE ACCOUNTANT FORECASTS NINETY DAYS OF CASH, WEEK BY WEEK. Seat: accountant. Instruction 1013 item 5.
--
-- Pure probe: no DDL. Run AFTER the_accountant_forecasts_ninety_days_of_cash_week_by_week.sql, as ONE query
-- through node scripts/qsql.mjs. Every write is inside a block that always raises, so nothing survives. The
-- seeded rows live on the ZZ DEMO bank account 'zz_demo' (which fn_accountant_month_close_figures already
-- excludes) and are named ZZ DEMO; nothing here notifies anybody.
--
-- PROBE OK only if:
--   1. on 'zz_demo' with an opening balance of AED 1,000 and a ZZ DEMO debit of AED 600 in each of the two
--      months before, the forecast has 13 weeks, projects that debit, adds the policy bank fee (no fee line
--      on that account), goes below zero in some week and names a positive top-up;
--   2. the real 'mashreq' forecast has 13 weeks and LISTS the owner-card subscriptions without subtracting
--      them (the week outflows never include an owner_card flow);
--   3. a ceo_weekly_report row inserted with a body gains the CASH FORECAST section and figures.cash_forecast_90d;
--   4. fn_accountant_month_close_figures for Aug 2026 carries cash_forecast_90d with 13 weeks.
do $probe$
declare v_as date := (now() at time zone 'Asia/Dubai')::date; f jsonb; m jsonb; b text; g jsonb; v_fail text := '';
begin
  insert into public.bank_statement_intake (source_ref, account, statement_month, state, lines, closing_balance_aed, balance_on)
  values ('zz-demo-forecast-probe', 'zz_demo', date_trunc('month', v_as)::date, 'parsed', 2, 1000, v_as - 1);
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash)
  values ('zz_demo', 'zz-demo-forecast-probe', v_as - 35, 'ZZ DEMO HOSTING 001', -600, 'zz-demo-forecast-probe-1'),
         ('zz_demo', 'zz-demo-forecast-probe', v_as - 5,  'ZZ DEMO HOSTING 002', -600, 'zz-demo-forecast-probe-2');

  f := public.fn_accountant_cash_forecast(v_as, 'zz_demo');
  if jsonb_array_length(f->'weeks') <> 13 then v_fail := v_fail || ' demo weeks<>13;'; end if;
  if (f#>>'{opening,aed}')::numeric <> 1000 then v_fail := v_fail || ' demo opening ' || coalesce(f#>>'{opening,aed}', 'null') || ';'; end if;
  if not exists (select 1 from jsonb_array_elements(f->'flows') e where e->>'item' ilike 'ZZ DEMO HOSTING%' and (e->>'amount_aed')::numeric = -600)
    then v_fail := v_fail || ' hosting not projected;'; end if;
  if not exists (select 1 from jsonb_array_elements(f->'flows') e where e->>'source' = 'bank_fee_policy')
    then v_fail := v_fail || ' policy fee missing;'; end if;
  if f#>>'{below_zero,first_week}' is null or (f#>>'{below_zero,top_up_to_stay_above_zero_aed}')::numeric <= 0
    then v_fail := v_fail || ' below-zero week not found;'; end if;

  m := public.fn_accountant_cash_forecast(v_as);
  if jsonb_array_length(m->'weeks') <> 13 then v_fail := v_fail || ' mashreq weeks<>13;'; end if;
  if jsonb_array_length(m->'paid_by_the_founders_card_not_the_account') = 0 then v_fail := v_fail || ' owner-card subscriptions not listed;'; end if;
  if (select coalesce(sum((w->>'out_aed')::numeric), 0) from jsonb_array_elements(m->'weeks') w)
     <> (select coalesce(-sum((e->>'amount_aed')::numeric), 0) from jsonb_array_elements(m->'flows') e
          where e->>'paid_from' <> 'owner_card' and (e->>'amount_aed')::numeric < 0)
    then v_fail := v_fail || ' week outflows include owner-card flows;'; end if;

  insert into public.ceo_weekly_report (iso_year, iso_week, week_start, week_end, report_key, subject, body)
  values (2099, 1, date '2099-01-05', date '2099-01-11', 'zz-demo:forecast-probe', 'ZZ DEMO', 'ZZ DEMO body')
  returning body, figures into b, g;
  if position('CASH FORECAST (90 DAYS)' in b) = 0 or not (g ? 'cash_forecast_90d') then v_fail := v_fail || ' weekly review lacks the section;'; end if;

  if jsonb_array_length(public.fn_accountant_month_close_figures(date '2026-08-01')#>'{cash_forecast_90d,weeks}') <> 13
    then v_fail := v_fail || ' close figures lack the forecast;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK: demo first week below zero ' || (f#>>'{below_zero,first_week}')
      || ', top-up AED ' || (f#>>'{below_zero,top_up_to_stay_above_zero_aed}') || '; mashreq opening ' || coalesce(m#>>'{opening,aed}', 'missing')
      || ', below zero week ' || coalesce(m#>>'{below_zero,first_week}', 'none') || ', lowest ' || coalesce(m#>>'{below_zero,lowest_aed}', '-')
      else 'PROBE FAILED:' || v_fail end;
end $probe$;
