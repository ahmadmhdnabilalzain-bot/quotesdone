-- THE ACCOUNTANT FORECASTS NINETY DAYS OF CASH, WEEK BY WEEK. Seat: accountant.
-- Founder instruction 1013, item 5 (29 Sep 2026).
--
-- What it is: public.fn_accountant_cash_forecast(p_as_of, p_account) projects the Mashreq account 13 weeks
-- (91 days) ahead from the last recorded closing balance, and says in which week the balance would go
-- below zero and by how much, so the founder can top the account up in time.
--
-- FOUNDER RULING (instr 1013): there is no runway target; the founder funds the company. The forecast is
-- INFORMATION and NEVER an alarm. So nothing here notifies anybody, and the monthly close no longer raises
-- its severity because runway fell under six months (that clause is removed from fn_accountant_month_close).
--
-- Where it is read: the weekly CEO review (a BEFORE trigger appends a CASH FORECAST section and
-- figures.cash_forecast_90d) and the monthly close pack (figures.cash_forecast_90d, a table in the PDF, lines
-- in the CSV).
--
-- Known outflows, and where each comes from (measured 29 Sep 2026):
--   1. recurring lines SEEN IN THE BANK STATEMENTS: a debit whose description (digits stripped) appears in
--      at least two different months of the last 120 days, projected monthly on the day it last fell at the
--      amount it last had. On 29 Sep this finds the Mashreq maintenance fee (AED 199) and its VAT (AED 9.95).
--   2. the bank fee from decision_policy accountant_bank_fee_monthly_aed (AED 208.95 = 199 + 9.95 VAT) ONLY
--      when (1) found no fee line, so a thin statement history does not drop the fee.
--   3. recurring subscriptions from the accountant's register accountant_owner_ruled_subscription (built
--      from the books). A row paid_from 'owner_card' is paid by the founder's own card, not by the account,
--      so it is LISTED but not subtracted (today Anthropic and OpenAI, AED 799 each). A register row with a
--      bank_pattern suppresses the same charge in (1) so it is never counted twice.
--   4. renewals in accountant_renewal_budget whose pay_by (else expires_on) falls in the window, at their
--      budget; an unbudgeted one is listed with amount 0 and flagged. The trade licence renewal of
--      24 Jun 2027 (pay by 10 Jun 2027, budget AED 1,200) sits beyond a 29 Sep window, so it is reported
--      under next_known_beyond_window rather than left out of sight.
-- Known inflows: Stripe payouts still on their way (livemode, status pending or in_transit, arriving in the
-- window) and supplier charges owed and due in the window (non-demo suppliers). Owner transfers are capital
-- and are not predictable, so they are not projected.

insert into public.decision_policy (key, value, description)
values ('accountant_bank_fee_monthly_aed', '208.95'::jsonb,
        'Mashreq monthly maintenance fee AED 199 + VAT AED 9.95 (bank statements Aug and Sep 2026). Used by fn_accountant_cash_forecast only when the statements show no recurring fee line.')
on conflict (key) do nothing;

create or replace function public.fn_accountant_cash_forecast(p_as_of date default null, p_account text default 'mashreq')
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_end date; v_bal numeric; v_bal_on date; v_after numeric; v_open numeric;
  v_items jsonb; v_weeks jsonb; v_low jsonb; v_owner jsonb; v_next jsonb; v_fee numeric;
begin
  v_end := v_as_of + 91;
  select closing_balance_aed, balance_on into v_bal, v_bal_on
    from public.bank_statement_intake
   where account = p_account and closing_balance_aed is not null and balance_on <= v_as_of
   order by balance_on desc, received_at desc limit 1;
  select coalesce(sum(amount_aed), 0) into v_after
    from public.bank_statement_line where account = p_account and value_date > v_bal_on and value_date <= v_as_of;
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
    select 'subscription_register', vendor, paid_from, -bank_value_aed, cadence, usual_day, expected_from
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
                on e->>'paid_from' <> 'owner_card'
               and (e->>'on')::date between v_as_of + 1 + 7 * n and v_as_of + 7 * (n + 1)
             group by n) z) s;

  select jsonb_build_object('first_week', (w->>'week')::int, 'week_from', w->>'from', 'closing_aed', (w->>'closing_aed')::numeric,
           'lowest_aed', (select min((x->>'closing_aed')::numeric) from jsonb_array_elements(v_weeks) x),
           'top_up_to_stay_above_zero_aed', -(select min((x->>'closing_aed')::numeric) from jsonb_array_elements(v_weeks) x))
    into v_low
    from jsonb_array_elements(v_weeks) w where (w->>'closing_aed')::numeric < 0 order by (w->>'week')::int limit 1;

  select coalesce(jsonb_agg(e), '[]'::jsonb) into v_owner from jsonb_array_elements(v_items) e where e->>'paid_from' = 'owner_card';
  select jsonb_build_object('item', item, 'pay_by', coalesce(pay_by, expires_on), 'budget_aed', budget_aed) into v_next
    from public.accountant_renewal_budget
   where item !~* 'zz[_ -]?demo' and coalesce(pay_by, expires_on) > v_end order by coalesce(pay_by, expires_on) limit 1;

  return jsonb_build_object(
    'as_of', v_as_of, 'to', v_end, 'account', p_account,
    'nature', 'information, never an alarm: there is no runway target and the founder funds the company (instruction 1013)',
    'opening', case when v_bal is null
      then jsonb_build_object('aed', null, 'missing', 'no closing balance recorded for ' || p_account || ' on or before ' || v_as_of)
      else jsonb_build_object('aed', v_open, 'statement_balance_aed', v_bal, 'balance_on', v_bal_on, 'lines_since_aed', v_after) end,
    'weeks', v_weeks,
    'below_zero', coalesce(v_low, jsonb_build_object('first_week', null, 'note',
                    case when v_open is null then 'not measurable without an opening balance' else 'the balance stays at or above zero for the 13 weeks' end)),
    'flows', v_items,
    'paid_by_the_founders_card_not_the_account', v_owner,
    'next_known_beyond_window', v_next,
    'basis', 'Opening = last Mashreq closing balance plus statement lines after it. Outflows: recurring statement debits (2+ months in 120 days), the bank fee policy only if no fee line recurs, the subscription register (owner-card rows listed, not subtracted), renewals at budget. Inflows: Stripe payouts in transit and supplier charges due. Owner transfers are capital and not projected.');
end $fn$;

revoke execute on function public.fn_accountant_cash_forecast(date, text) from public, anon, authenticated;

-- ------------------------------------------------------------------ the weekly CEO review carries it
create or replace function public.fn_ceo_weekly_report_carries_the_cash_forecast()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare f jsonb; v_txt text;
begin
  if new.body is null or position('CASH FORECAST (90 DAYS)' in new.body) > 0 then return new; end if;
  f := public.fn_accountant_cash_forecast(new.week_end);
  v_txt := 'CASH FORECAST (90 DAYS) - information, not an alarm' || E'\n'
    || '  Opening AED ' || coalesce(f#>>'{opening,aed}', 'missing (' || coalesce(f#>>'{opening,missing}', '') || ')') || E'\n'
    || coalesce((select string_agg(format('  Week %s (%s to %s): in %s, out %s, closing %s', w->>'week', w->>'from', w->>'to',
                                          w->>'in_aed', w->>'out_aed', coalesce(w->>'closing_aed', '?')), E'\n' order by (w->>'week')::int)
                   from jsonb_array_elements(f->'weeks') w), '') || E'\n'
    || case when f#>>'{below_zero,first_week}' is not null
            then format('  The account would go below zero in week %s (from %s). A top-up of AED %s keeps it at or above zero.',
                        f#>>'{below_zero,first_week}', f#>>'{below_zero,week_from}', f#>>'{below_zero,top_up_to_stay_above_zero_aed}')
            else '  ' || coalesce(f#>>'{below_zero,note}', '') end;
  new.body := new.body || E'\n\n' || v_txt;
  new.figures := coalesce(new.figures, '{}'::jsonb) || jsonb_build_object('cash_forecast_90d', f);
  return new;
end $fn$;

revoke execute on function public.fn_ceo_weekly_report_carries_the_cash_forecast() from public, anon, authenticated;

drop trigger if exists ceo_weekly_report_carries_the_cash_forecast on public.ceo_weekly_report;
create trigger ceo_weekly_report_carries_the_cash_forecast
  before insert or update of body on public.ceo_weekly_report
  for each row execute function public.fn_ceo_weekly_report_carries_the_cash_forecast();

-- ------------------------------------------------------------------ the monthly close pack carries it
-- The three routines below are the live bodies (supabase/schema/full_schema.sql, 29 Sep 2026) with only
-- the marked changes.

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
end $function$;

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
end $function$;

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
end $function$;
