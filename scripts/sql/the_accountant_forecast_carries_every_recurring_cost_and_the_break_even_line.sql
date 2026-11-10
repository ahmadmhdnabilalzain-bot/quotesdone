-- THE ACCOUNTANT'S 13-WEEK CASH FORECAST CARRIES EVERY RECURRING COST THE BOOKS SHOW, AND THE BREAK-EVEN LINE.
--
-- Assigned: accountant. 10 Nov 2026. Founder ledger 1609. Proposal P13 of docs/reports/2026-11-10-seat-qualification-audit.md.
--
-- == MEASURED, 10 Nov 2026, production read-only ====================================================================
--   * fn_accountant_cash_forecast('mashreq') projects 12 flows from 4 items: Anthropic and OpenAI (the owner-ruled
--     subscription register, AED 799 each), the Mashreq maintenance fee and its VAT (bank statement lines). It leaves out
--     every other vendor the books carry: Supabase, Vercel, GoDaddy (M365), Resend, GlockApps, Google and OpenRouter,
--     all booked in expense_entries with 2+ receipts in 120 days (the audit's "8 of 10 missing", A.4 A2).
--   * It carries no break-even line.
--
-- == WHAT THIS CHANGES ===============================================================================================
--   fn_accountant_cash_forecast: one more item source, 'books_recurring' (rule in the body), and a 'break_even' block read
--   from public.ceo_break_even_month. The live body of 10 Nov 2026, read back, with only those lines changed.
--   Needs the_ceo_plans_on_a_break_even_ledger_to_june_2027.sql applied first (break_even_cost_line, ceo_break_even_month).
-- NOT CHANGED: the opening balance, the bank and register sources, renewals, Stripe payouts, supplier dues.
-- prevented by: scripts/checks/the_accountant_forecast_carries_every_recurring_cost_and_the_break_even_line.test.mjs
-- Pending: scripts/sql/pending/the_accountant_forecast_carries_every_recurring_cost_and_the_break_even_line.txt

CREATE OR REPLACE FUNCTION public.fn_accountant_cash_forecast(p_as_of date DEFAULT NULL::date, p_account text DEFAULT 'mashreq'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
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
      from public.accountant_owner_ruled_subscription where vendor !~* 'zz[_ -]?demo'
    union all
    -- P13 (10 Nov 2026): EVERY RECURRING COST THE BOOKS SHOW. A vendor with 2 or more receipts in 120 days (last one within
    -- 75 days) is a monthly flow on the day of its latest receipt, at what it cost in the last 30 days (else its latest
    -- month). Not when the subscription register already carries it, nor a line the break-even ledger marks off.
    select 'books_recurring', b.v, 'account', -b.amt, 'monthly', b.dom, null from (
      select e.v, extract(day from max(e.charged_on))::int dom,
             coalesce(nullif(sum(e.aed) filter (where e.charged_on > v_as_of - 30), 0),
                      sum(e.aed) filter (where date_trunc('month', e.charged_on) = (select date_trunc('month', max(e2.charged_on)) from public.expense_entries e2
                                                                                     where lower(btrim(e2.vendor)) like e.v || '%'))) amt
        from (select case when lower(x.vendor) like 'vercel%' then 'vercel' when lower(x.vendor) like 'github%' then 'github' else lower(btrim(x.vendor)) end v,
                     x.charged_on, case when x.currency = 'USD' then x.amount * 3.6725 else x.amount end aed
                from public.expense_entries x
               where x.charged_on > v_as_of - 120 and x.charged_on <= v_as_of and coalesce(x.category, '') <> 'licence'
                 and x.vendor !~* 'zz[_ -]?demo') e
       group by e.v
      having count(*) >= 2 and max(e.charged_on) > v_as_of - 75) b
     where not exists (select 1 from public.accountant_owner_ruled_subscription s where lower(s.vendor) = b.v)
       and not exists (select 1 from public.break_even_cost_line c where c.vendor_key = b.v and c.kind = 'excluded')),
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
    -- P13: the break-even line the CEO plans on (public.ceo_break_even_month), beside the cash weeks
    'break_even', (select jsonb_build_object('month', m.month, 'cost_to_cover_aed', m.cost_to_cover_aed, 'monthly_cost_aed', m.monthly_cost_aed,
                     'revenue_net_aed', m.revenue_net_aed, 'gap_aed', m.gap_aed, 'months_left', m.months_left, 'verdict', m.verdict)
                     from public.ceo_break_even_month m order by m.month desc limit 1),
    'next_known_beyond_window', v_next,
    'basis', 'Opening = last Mashreq statement closing balance plus the lines of later statements only. Outflows: recurring statement debits (2+ months in 120 days), the bank fee policy only if no fee line recurs, the subscription register (all from the account, founder ruling 1011), renewals at budget. Inflows: Stripe payouts in transit and supplier charges due. Every vendor the books show 2+ times in 120 days is a monthly flow unless the register carries it (P13). Owner transfers are capital and not projected.');
end $fn$;
