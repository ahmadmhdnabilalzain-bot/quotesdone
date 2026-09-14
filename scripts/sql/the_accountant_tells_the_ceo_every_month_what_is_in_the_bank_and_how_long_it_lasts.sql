-- THE ACCOUNTANT TELLS THE CEO EVERY MONTH WHAT IS IN THE BANK AND HOW LONG IT LASTS.
--
-- Assigned: accountant; the acknowledgement is the ceo's. Founder, 14 Sep 2026: "add all for accountant and
-- IT" — duty 1 of the five further accountant duties: a monthly report to the CEO of cash in the bank
-- (Mashreq), money in and out, the reserve, and the runway in months at the current spend, from booked data
-- only. Missing data is shown as missing, never invented.
--
-- WHAT WAS MEASURED (14 Sep 2026, main at #645):
--   * #645's monthly close (accountant_month_close) already reports a month's P&L, cash in and cash out as
--     booked and the refund reserve to the CEO, and he signs for it (fn_ceo_accountant_reports_sweep). It
--     had NO bank balance: bank_statement_line stores each line's amount and bank_statement_intake stores
--     the statement, and neither kept the balance the statement prints. Without it there is no cash figure
--     and no runway.
--
-- WHAT THIS BUILDS. NOT A SECOND REPORT: the close carries it (the brief: "extend the existing month-close
-- document rather than a new report"). the_accountant_closes_every_month_and_the_ceo_signs_for_it.sql puts
-- fn_accountant_cash_position into the close's figures, its PDF, its CSV and its subject line.
--   bank_statement_intake gains closing_balance_aed and balance_on, recorded by fn_accountant_bank_balance_
--   record (the accountant runtime's bank_statement action takes closing_balance_aed and balance_on).
--   fn_accountant_cash_position(month, expenses)  cash in the bank (the last closing balance recorded on or
--       before the month's end), the month's Mashreq movements, the reserve and the runway. Every figure
--       with no source is null and says why.
--   fn_accountant_bank_balance_tick  the hourly duty: the latest closed month with no Mashreq closing
--       balance recorded is an accountant finding, round the IT loop, until the balance is recorded.
--
-- No VAT and no corporate tax figure is computed here: VAT waits for the AED 375,000 threshold (the VAT watch
-- owns it) and the founder ruled corporate tax out on 14 Sep 2026.
--
--   node scripts/apply_sql.mjs scripts/sql/the_accountant_tells_the_ceo_every_month_what_is_in_the_bank_and_how_long_it_lasts.sql --apply --ddl

alter table public.bank_statement_intake add column if not exists closing_balance_aed numeric(14,2);
alter table public.bank_statement_intake add column if not exists balance_on date;
comment on column public.bank_statement_intake.closing_balance_aed is
  'The closing balance the statement prints, in AED, as of balance_on. Recorded by fn_accountant_bank_balance_record; never derived from the lines.';

-- ── 1. THE BALANCE THE STATEMENT PRINTS ──────────────────────────────────────────────────────────
create or replace function public.fn_accountant_bank_balance_record(p_source_ref text, p_balance_aed numeric, p_on date)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if p_balance_aed is null or p_on is null then
    raise exception 'a closing balance needs its amount and the date the statement prints it for';
  end if;
  update public.bank_statement_intake set closing_balance_aed = round(p_balance_aed, 2), balance_on = p_on
   where source_ref = p_source_ref;
  if not found then raise exception 'no bank statement %: ingest the statement first', p_source_ref; end if;
  return jsonb_build_object('ok', true, 'source_ref', p_source_ref, 'closing_balance_aed', round(p_balance_aed, 2), 'balance_on', p_on);
end $fn$;
revoke execute on function public.fn_accountant_bank_balance_record(text, numeric, date) from public, anon, authenticated;

-- ── 2. CASH, RESERVE AND RUNWAY FOR A MONTH ──────────────────────────────────────────────────────
-- p_month_expenses_aed is the month's booked expenses as the close computed them (cash_out.expenses_aed),
-- passed in because the close calls this before its own row exists. The spend is the average of that and
-- the expenses of up to two earlier closed months. Refunds are not spend.
create or replace function public.fn_accountant_cash_position(p_month date, p_month_expenses_aed numeric)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
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
end $fn$;
revoke execute on function public.fn_accountant_cash_position(date, numeric) from public, anon, authenticated;

-- ── 3. THE DUTY ──────────────────────────────────────────────────────────────────────────────────
-- The latest closed month whose Mashreq closing balance is not recorded is an accountant finding (forward
-- the statement, or hand it to the runtime with its balance) until it is. The close already went to the CEO
-- with the cash shown as missing; the finding is what gets the balance recorded.
create or replace function public.fn_accountant_bank_balance_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
end $fn$;
revoke execute on function public.fn_accountant_bank_balance_tick() from public, anon, authenticated;
