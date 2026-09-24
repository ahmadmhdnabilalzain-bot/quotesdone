-- THE ACCOUNTANT SENDS THE CEO THE RUNWAY, AT ACTUAL SPEND AND AGAINST THE BUDGET, EVERY MONTH.
--
-- Assigned: accountant; acknowledging it is the ceo's (fn_ceo_accountant_reports_sweep). Founder_instruction
-- 327 (14 Sep 2026): "monthly CEO report with runway". Ledger 983 (24 Sep 2026): Accountant gap 2 in GAPS.md.
--
-- WHAT WAS MEASURED (24 Sep 2026, production, read-only):
--   * fn_accountant_cash_position(month, expenses) computes the runway at ACTUAL spend, and the month close
--     prints it in its PDF. That is the only place it appears: no report of its own reaches the CEO, and
--     nothing compares it with a budget.
--   * public.budgets and public.budget_lines hold 0 rows. There is no budget yet.
--   * accountant_month_close holds one closed month (2026-08).
--
-- WHAT THIS BUILDS
--   fn_accountant_runway_figures(month)  cash, reserve, available cash, runway at actual spend (from
--       fn_accountant_cash_position: ONE formula, not a second one), the month's budgeted spend (the active
--       budgets' lines for that month) and the runway at the budgeted spend. Every missing input is null and
--       named in 'missing' -- "no budget is set" is said, never a zero.
--   fn_accountant_runway_report_tick()  the duty: for the latest closed month with no runway report yet, one
--       support_ceo_report from the accountant (idempotency key accountant.runway:YYYY-MM), severity elevated
--       when either runway is under decision_policy accountant_runway_warn_months, routine otherwise.
--   seat_duty accountant.runway_report, daily (the report itself is monthly; the key makes the rest no-ops).
--
-- NOT DONE HERE: setting a budget. The budget is a commercial figure; this reports "no budget is set" until
-- one exists. No VAT and no corporate tax figure (instr 344; the VAT watch owns VAT).
--
-- prevented by: scripts/checks/accountant_duties_are_wired.test.mjs

insert into public.decision_policy (key, value, description) values
  ('accountant_runway_warn_months', '6'::jsonb,
   'The monthly runway report to the CEO is severity elevated when the runway, at actual or at budgeted spend, is below this many months.')
on conflict (key) do nothing;

create or replace function public.fn_accountant_runway_figures(p_month date)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
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
    'missing', to_jsonb(v_missing),
    'basis', 'Runway at actual spend is fn_accountant_cash_position''s (available cash / average booked monthly expenses). '
          || 'Runway at budget = the same available cash / the month''s lines of the active budgets. Nothing is estimated.');
end $fn$;
revoke execute on function public.fn_accountant_runway_figures(date) from public, anon, authenticated;
grant execute on function public.fn_accountant_runway_figures(date) to service_role;

create or replace function public.fn_accountant_runway_report_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
end $fn$;
revoke execute on function public.fn_accountant_runway_report_tick() from public, anon, authenticated;
grant execute on function public.fn_accountant_runway_report_tick() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('accountant.runway_report', 'accountant', interval '1 day', 'fn_accountant_runway_report_tick',
   'once per closed month: cash, reserve and runway at actual spend and against the budget, reported to the CEO',
   'scripts/sql/the_accountant_sends_the_ceo_the_runway_against_the_budget_every_month.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- PROBE (verdict row; the figures function writes nothing): with no budget the runway against it is null and
-- the absence is SAID, never a zero.
select case
  when (select count(*) from public.budget_lines) = 0
       and (public.fn_accountant_runway_figures(date '2026-08-01') ->> 'runway_months_at_budget') is not null
    then 'PROBE FAILED: a runway against the budget was produced with no budget'
  when (select count(*) from public.budget_lines) = 0
       and not exists (select 1 from jsonb_array_elements_text(public.fn_accountant_runway_figures(date '2026-08-01') -> 'missing') m
                        where m like 'no active budget%')
    then 'PROBE FAILED: the missing budget is not named'
  else 'PROBE OK' end as verdict;
