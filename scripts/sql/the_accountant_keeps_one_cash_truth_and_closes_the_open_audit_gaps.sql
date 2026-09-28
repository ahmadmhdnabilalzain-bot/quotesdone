-- accountant: the open seat-audit gaps of 28 Sep 2026 (items 1-6, G2-G7).
--
-- Measured before this file (production, 28 Sep 2026):
--   * fn_finance_forecast.cash_now = AED -8,155.10 (GL account 1000) while fn_accountant_cash_position
--     read AED 582.96 (the Mashreq statement closing balance of 31 Aug). Two cash figures.
--   * revenue_run_rate_30d = AED -250 and VAT turnover = AED -250: journal 690 (AED 250 credit to 4400)
--     is VOID and its reversal 821 is POSTED, so "posted lines only" counted the reversal alone.
--   * no Corporate Tax watch; 0 budgets; no 13-week view; no unit-economics routine.
--   * August 2026 closed on 15 Sep (not by day 5); nothing refuses a posting dated in a closed month.
--   * the daily Stripe/bank reconciliation, reveal-invoice filing, refund correctness and the Stripe
--     customer-email setting had no seat_duty row of their own; fn_accountant_duties still said ad spend
--     was "held for the marketing seat" although accountant.ad_spend_reconcile runs daily.
--
-- Decisions:
--   1. ONE CASH TRUTH is the bank statement (fn_accountant_cash_position). The forecast reads it. The GL
--      bank account is reported beside it as a reconciliation difference, never as cash.
--   2. Revenue is measured through ONE view, gl_revenue_lines_measured: posted revenue lines, minus any
--      posted reversal whose original is not posted (the 690/821 shape). Reversals are reported on their
--      own line and never carried forward as run-rate revenue.
--   3. Corporate Tax by legal form: the licence is a sole establishment of a natural person, so the
--      registration trigger is AED 1,000,000 business turnover in a calendar year (Cabinet Decision
--      49/2023). The watch reports to the CEO at 50%, 80% and 100%, once per fraction per year.
--   4. A monthly closing journal to retained earnings is NOT posted: under IFRS for SMEs the income
--      statement closes at the year end (year-end pack). The month's close is the CEO-signed close row
--      plus the period lock below, which refuses a posting dated in a closed month.

-- ── 2. one revenue measure ──────────────────────────────────────────────────────────────────────
create or replace view public.gl_revenue_lines_measured as
select l.id as line_id, l.journal_id, j.entry_date, j.source, l.account_code,
       (l.credit - l.debit) as revenue_aed,
       (j.source = 'reversal' or exists (select 1 from public.gl_journal o where o.reverses = j.id)) as is_reversal
  from public.gl_journal_lines l
  join public.gl_journal j on j.id = l.journal_id and j.status = 'posted'
  join public.gl_accounts a on a.code = l.account_code and a.type = 'revenue'
 where not exists (select 1 from public.gl_journal o where o.reverses = j.id and o.status <> 'posted');
revoke all on public.gl_revenue_lines_measured from public, anon, authenticated;
comment on view public.gl_revenue_lines_measured is
  'Posted revenue lines. A posted reversal of a journal that is itself not posted (void) is excluded, because the original never counted. is_reversal marks a reversal of a posted original, reported on its own line.';

-- ── 1. the forecast reads the one cash truth ────────────────────────────────────────────────────
create or replace function public.fn_finance_forecast()
returns jsonb language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_cp jsonb := public.fn_accountant_cash_position(current_date, null);
  v_cash numeric := (v_cp #>> '{cash_in_bank,aed}')::numeric;
  v_gl numeric; v_rev numeric; v_rvs numeric; v_exp numeric; v_out jsonb := '[]'::jsonb; h int; v_ar numeric; v_ap numeric;
begin
  select coalesce(sum(balance), 0) into v_gl from public.gl_account_balances where code in ('1000', '1050');
  select coalesce(sum(revenue_aed) filter (where not is_reversal), 0), coalesce(sum(revenue_aed) filter (where is_reversal), 0)
    into v_rev, v_rvs from public.gl_revenue_lines_measured where entry_date >= current_date - 30;
  select coalesce(sum(l.debit - l.credit), 0) into v_exp
    from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id and j.status = 'posted'
    join public.gl_accounts a on a.code = l.account_code and a.type = 'expense'
   where j.entry_date >= current_date - 30;
  foreach h in array array[30, 60, 90] loop
    select coalesce(sum(amount_due), 0) into v_ar from public.supplier_dues
     where public.fn_supplier_due_is_owed(status, paid_at) and coalesce(due_date_30, reveal_date + 30) <= current_date + h;
    select coalesce(sum(balance_due), 0) into v_ap from public.ap_open_bills where coalesce(due_date, bill_date) <= current_date + h;
    v_out := v_out || jsonb_build_object('days', h,
      'expected_inflows', round(v_ar + v_rev * h / 30.0, 2),
      'expected_outflows', round(v_ap + v_exp * h / 30.0, 2),
      'projected_cash', case when v_cash is not null then round(v_cash + v_ar + v_rev * h / 30.0 - v_ap - v_exp * h / 30.0, 2) end,
      'revenue_forecast', round(v_rev * h / 30.0, 2));
  end loop;
  return jsonb_build_object(
    'as_of', now(),
    'cash_now', v_cash,
    'cash_source', jsonb_build_object('basis', 'fn_accountant_cash_position: the latest Mashreq statement closing balance',
                                      'as_of', v_cp #> '{cash_in_bank,as_of}', 'stale', v_cp #> '{cash_in_bank,stale}',
                                      'missing', v_cp #> '{cash_in_bank,missing}'),
    'gl_cash_aed', v_gl,
    'gl_minus_bank_aed', case when v_cash is not null then round(v_gl - v_cash, 2) end,
    'assumptions', jsonb_build_object('revenue_run_rate_30d', v_rev, 'reversals_30d_not_carried_forward', v_rvs,
                                      'expense_run_rate_30d', v_exp),
    'horizons', v_out);
end $fn$;
revoke execute on function public.fn_finance_forecast() from public, anon, authenticated;

create or replace function public.fn_accountant_cash_truth_check()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
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
end $fn$;
revoke execute on function public.fn_accountant_cash_truth_check() from public, anon, authenticated;

-- ── 3. Corporate Tax by legal form ──────────────────────────────────────────────────────────────
insert into public.gl_settings (key, num_value) values ('ct_natural_person_registration_threshold_aed', 1000000)
on conflict (key) do nothing;

create or replace function public.fn_accountant_ct_threshold_check(p_notify boolean default true)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_from date := date_trunc('year', v_today)::date;
  v_thr numeric; v_turn numeric; v_frac numeric; v_hit numeric; v_rep jsonb;
begin
  select num_value into v_thr from public.gl_settings where key = 'ct_natural_person_registration_threshold_aed';
  if v_thr is null then raise exception 'gl_settings.ct_natural_person_registration_threshold_aed is missing'; end if;
  select coalesce(sum(revenue_aed), 0) into v_turn from public.gl_revenue_lines_measured where entry_date between v_from and v_today;
  v_frac := round(v_turn / v_thr, 4);
  select max(f) into v_hit from unnest(array[0.5, 0.8, 1.0]) f where v_frac >= f;
  if v_hit is not null and p_notify then
    v_rep := public.fn_support_report_to_ceo(
      p_idempotency_key => 'ct_threshold:' || extract(year from v_today) || ':' || v_hit,
      p_severity => case when v_hit >= 1 then 'serious' when v_hit >= 0.8 then 'elevated' else 'routine' end,
      p_subject => 'Corporate Tax: business turnover ' || extract(year from v_today) || ' is AED ' || round(v_turn, 2)
                   || ', ' || round(v_frac * 100, 1) || '% of the AED ' || v_thr || ' natural-person registration trigger',
      p_evidence => jsonb_build_object('turnover_aed', round(v_turn, 2), 'threshold_aed', v_thr, 'fraction', v_frac,
                                       'window_from', v_from, 'window_to', v_today,
                                       'basis', 'gl_revenue_lines_measured over the calendar year (Asia/Dubai). The licence (DET 1633275) is a sole establishment owned by a natural person: registration is due once business turnover exceeds AED 1,000,000 in a calendar year (Cabinet Decision 49/2023). A juridical person would register regardless.'),
      p_attempted => '[]'::jsonb,
      p_requested => case when v_hit >= 1
        then 'Registration for Corporate Tax is now required. Instruct the accountant to prepare the EmaraTax application; late registration costs AED 10,000.'
        else 'No registration is due yet. Plan it so the filing is scheduled before the threshold, not discovered after it.' end,
      p_review_in => interval '30 days', p_source_agent => 'accountant');
  end if;
  return jsonb_build_object('year', extract(year from v_today), 'turnover_aed', round(v_turn, 2), 'threshold_aed', v_thr,
                            'fraction', v_frac, 'fraction_reported', v_hit, 'reported_to_ceo', v_rep is not null);
end $fn$;
revoke execute on function public.fn_accountant_ct_threshold_check(boolean) from public, anon, authenticated;

-- ── 4. unit economics ───────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_unit_economics(p_month date)
returns jsonb language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_m date := date_trunc('month', p_month)::date; v_e date; v_fx numeric;
  v_reveals int; v_fee numeric; v_gmv numeric; v_charged numeric; v_stripe numeric;
  v_ref_n int; v_ref_aed numeric; v_disp int; v_rfq int; v_llm numeric; v_msg numeric;
  v_sub_n int; v_sub_rev numeric; v_var numeric; v_missing text[] := '{}';
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
  select coalesce(sum(cost_aed), 0) into v_llm from public.ai_cost_log where occurred_at >= v_m and occurred_at < v_e;
  select coalesce(sum(case when upper(currency) = 'USD' then amount * v_fx else amount end), 0) into v_msg
    from public.expense_entries where charged_on >= v_m and charged_on < v_e and vendor ~* '(twilio|resend|whatsapp|meta.*messag)';
  select count(*) into v_sub_n from public.leads where registration_paid_at >= v_m and registration_paid_at < v_e;
  select coalesce(sum(revenue_aed), 0) into v_sub_rev from public.gl_revenue_lines_measured
   where account_code = '4200' and entry_date >= v_m and entry_date < v_e;
  v_var := v_llm + v_msg;
  if v_reveals = 0 then v_missing := v_missing || text 'no paid reveal in the month, so per-reveal figures are undefined'; end if;
  if v_rfq = 0 then v_missing := v_missing || text 'no request in the month, so cost per request is undefined'; end if;
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
    'requests', v_rfq, 'llm_cost_aed', round(v_llm, 2), 'messaging_email_cost_aed', round(v_msg, 2),
    'variable_cost_per_request_aed', case when v_rfq > 0 then round(v_var / v_rfq, 2) end,
    'contribution_per_reveal_aed', case when v_reveals > 0 then round((v_fee - v_stripe - v_ref_aed - v_var) / v_reveals, 2) end,
    'subscriptions_paid', v_sub_n, 'subscription_revenue_aed', round(v_sub_rev, 2),
    'revenue_per_subscription_aed', case when v_sub_n > 0 then round(v_sub_rev / v_sub_n, 2) end,
    'missing', to_jsonb(v_missing),
    'basis', 'Paid reveals by revealed_at, refunds by refund_confirmed_at, ZZ DEMO customers excluded. Stripe fees from transactions.stripe_fee_fils. Variable cost = ai_cost_log.cost_aed + messaging/email vendor expenses (USD at gl_settings usd_to_aed). Contribution per reveal = (fee - Stripe fees - refunds - variable cost) / reveals. Numerators and denominators are all returned.');
end $fn$;
revoke execute on function public.fn_accountant_unit_economics(date) from public, anon, authenticated;

-- ── 5. a budget from the plan, and a 13-week cash view ──────────────────────────────────────────
-- Conservative path (company-plan-scenarios: ~AED 50,000 reveal fees to Aug 2027, customers from Jan 2027):
-- AED 6,250 a month on 4000 from Jan to Aug 2027. Costs: each expense account's average booked spend over
-- Jun-Aug 2026 (a month with no booking counts as 0). Cash planning uses the conservative path (the plan's rule).
-- ponytail: a straight-line revenue path; re-seed from the drivers once reveals are measured.
insert into public.budgets (name, fiscal_year, status, created_by)
select 'Conservative plan Sep 2026 - Aug 2027', 2027, 'active', 'accountant'
 where not exists (select 1 from public.budgets where name = 'Conservative plan Sep 2026 - Aug 2027');
insert into public.budget_lines (budget_id, account_code, period_month, amount)
select b.id, x.code, m::date, x.amount
  from public.budgets b
  cross join generate_series(date '2026-09-01', date '2027-08-01', interval '1 month') m
  cross join lateral (
    select a.code, round(coalesce((select sum(l.debit - l.credit) from public.gl_journal_lines l
             join public.gl_journal j on j.id = l.journal_id and j.status = 'posted'
            where l.account_code = a.code and j.entry_date >= date '2026-06-01' and j.entry_date < date '2026-09-01'), 0) / 3, 2) as amount
      from public.gl_accounts a where a.type = 'expense' and a.code in ('6000', '6300')
    union all
    select '4000', case when m >= date '2027-01-01' then 6250 else 0 end) x
 where b.name = 'Conservative plan Sep 2026 - Aug 2027'
   and not exists (select 1 from public.budget_lines bl where bl.budget_id = b.id);

create or replace function public.fn_accountant_cash_13_weeks()
returns jsonb language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
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
end $fn$;
revoke execute on function public.fn_accountant_cash_13_weeks() from public, anon, authenticated;

-- ── 6. the period lock ──────────────────────────────────────────────────────────────────────────
create or replace function public.fn_gl_period_lock()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if new.status = 'posted'
     and (tg_op = 'INSERT' or old.status is distinct from 'posted' or old.entry_date is distinct from new.entry_date)
     and exists (select 1 from public.accountant_month_close where month = date_trunc('month', new.entry_date)::date)
     and coalesce(current_setting('app.period_reopen_reason', true), '') = '' then
    raise exception 'period % is closed: post this entry in the open period, or set app.period_reopen_reason in the same transaction',
      to_char(new.entry_date, 'YYYY-MM');
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_gl_period_lock() from public, anon, authenticated;
drop trigger if exists a05_gl_period_lock on public.gl_journal;
create trigger a05_gl_period_lock before insert or update on public.gl_journal
  for each row execute function public.fn_gl_period_lock();

-- ── G2-G7: the checks become duties with their own last_ok_at ───────────────────────────────────
create or replace function public.fn_accountant_stripe_reconcile_duty()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  return jsonb_build_object('bank', public.fn_accountant_bank_reconcile(),
    'payouts_unmatched', (select count(*) from public.stripe_payout where livemode and bank_line_id is null
                            and arrival_date < current_date - coalesce((select num_value::int from public.gl_settings where key = 'payout_transit_grace_days'), 3)));
end $fn$;
revoke execute on function public.fn_accountant_stripe_reconcile_duty() from public, anon, authenticated;

create or replace function public.fn_accountant_close_by_day_5()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_local date := (now() at time zone 'Asia/Dubai')::date; v_prev date; v_tick jsonb; v_row record; v_on_time boolean; v_rep jsonb;
begin
  v_prev := (date_trunc('month', v_local) - interval '1 month')::date;
  v_tick := public.fn_accountant_month_close_tick();       -- the close itself runs here too, not only inside the runtime
  select * into v_row from public.accountant_month_close where month = v_prev;
  v_on_time := v_row.month is not null and (v_row.closed_at at time zone 'Asia/Dubai')::date <= v_prev + interval '1 month' + interval '4 days';
  if not coalesce(v_on_time, false) and extract(day from v_local) > 5 then
    v_rep := public.fn_support_report_to_ceo(
      p_idempotency_key => 'accountant_close_day5:' || to_char(v_prev, 'YYYY-MM'), p_severity => 'elevated',
      p_subject => 'The ' || to_char(v_prev, 'Mon YYYY') || ' close ' || case when v_row.month is null then 'is not done' else 'was late' end || ' (target: day 5)',
      p_evidence => jsonb_build_object('month', to_char(v_prev, 'YYYY-MM'), 'closed_at', v_row.closed_at, 'tick', v_tick),
      p_attempted => '[]'::jsonb, p_requested => 'None: the accountant closes it on this tick; this records the missed target.',
      p_review_in => interval '30 days', p_source_agent => 'accountant');
  end if;
  return jsonb_build_object('month', to_char(v_prev, 'YYYY-MM'), 'closed_at', v_row.closed_at, 'closed_by_day_5', v_on_time, 'tick', v_tick);
end $fn$;
revoke execute on function public.fn_accountant_close_by_day_5() from public, anon, authenticated;

create or replace function public.fn_accountant_reveal_invoice_filing_check()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
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
end $fn$;
revoke execute on function public.fn_accountant_reveal_invoice_filing_check() from public, anon, authenticated;

create or replace function public.fn_accountant_refund_correctness(p_month date)
returns jsonb language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
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
end $fn$;
revoke execute on function public.fn_accountant_refund_correctness(date) from public, anon, authenticated;

create or replace function public.fn_accountant_refund_correctness_check()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
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
end $fn$;
revoke execute on function public.fn_accountant_refund_correctness_check() from public, anon, authenticated;

-- G7. Stripe exposes no API for the dashboard's customer-email setting, so it is re-read by a person and
-- recorded here. The duty refuses to let the reading go stale (older than 30 days) or read ON.
create table if not exists public.stripe_setting_reading (
  id bigint generated always as identity primary key,
  setting text not null,
  value text not null check (value in ('on', 'off')),
  read_at timestamptz not null,
  read_by text not null,
  evidence text not null
);
alter table public.stripe_setting_reading enable row level security;
drop policy if exists stripe_setting_reading_service_role_only on public.stripe_setting_reading;
create policy stripe_setting_reading_service_role_only on public.stripe_setting_reading
  as permissive for all to public using (false) with check (false);
revoke all on public.stripe_setting_reading from anon, authenticated;
insert into public.stripe_setting_reading (setting, value, read_at, read_by, evidence)
select s, 'off', timestamptz '2026-09-22 05:40:00+00', 'claude (founder_instruction 697)',
       'Live Stripe dashboard, Settings > Business > Customer emails: Successful payments and Refunds both OFF.'
  from unnest(array['customer_emails.successful_payments', 'customer_emails.refunds']) s
 where not exists (select 1 from public.stripe_setting_reading r where r.setting = s);

create or replace function public.fn_accountant_stripe_email_setting_watch()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
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
end $fn$;
revoke execute on function public.fn_accountant_stripe_email_setting_watch() from public, anon, authenticated;

insert into public.seat_duty (duty, what, every, enabled, routine, owner_file, owner_seat) values
 ('accountant.cash_truth', 'the forecast and the cash position read the same bank balance (within AED 1); the books'' bank account against the statement goes to the CEO', '1 day', true, 'fn_accountant_cash_truth_check', 'scripts/sql/the_accountant_keeps_one_cash_truth_and_closes_the_open_audit_gaps.sql', 'accountant'),
 ('accountant.ct_threshold', 'calendar-year business turnover against the AED 1M natural-person Corporate Tax trigger; the CEO hears at 50%, 80% and 100%', '1 day', true, 'fn_accountant_ct_threshold_check', 'scripts/sql/the_accountant_keeps_one_cash_truth_and_closes_the_open_audit_gaps.sql', 'accountant'),
 ('accountant.stripe_reconcile', 'Stripe payouts matched to the bank daily, with a last_ok_at of its own', '1 day', true, 'fn_accountant_stripe_reconcile_duty', 'scripts/sql/the_accountant_keeps_one_cash_truth_and_closes_the_open_audit_gaps.sql', 'accountant'),
 ('accountant.close_by_day_five', 'the previous month closed and locked by day 5; the close runs here and a miss goes to the CEO', '1 day', true, 'fn_accountant_close_by_day_5', 'scripts/sql/the_accountant_keeps_one_cash_truth_and_closes_the_open_audit_gaps.sql', 'accountant'),
 ('accountant.reveal_invoice_filing', 'every paid reveal has its Stripe invoice filed, the portal PDF and a Dropbox copy', '1 day', true, 'fn_accountant_reveal_invoice_filing_check', 'scripts/sql/the_accountant_keeps_one_cash_truth_and_closes_the_open_audit_gaps.sql', 'accountant'),
 ('accountant.refund_correctness', 'refund correctness per month: amount = what was paid, CEO approval, same charge', '1 day', true, 'fn_accountant_refund_correctness_check', 'scripts/sql/the_accountant_keeps_one_cash_truth_and_closes_the_open_audit_gaps.sql', 'accountant'),
 ('accountant.stripe_email_setting', 'the Stripe customer-email setting stays OFF and its reading is never older than 30 days', '1 day', true, 'fn_accountant_stripe_email_setting_watch', 'scripts/sql/the_accountant_keeps_one_cash_truth_and_closes_the_open_audit_gaps.sql', 'accountant')
on conflict (duty) do nothing;

-- ── edited copies of existing routines (CREATE OR REPLACE keeps their ACL) ──

create or replace function public.fn_accountant_vat_threshold_check(p_notify boolean default true)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
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
end $fn$;

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
end $fn$;

create or replace function public.fn_accountant_month_close(p_month date)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_m date := date_trunc('month', p_month)::date; f jsonb; v_rep jsonb; v_sev text;
begin
  if v_m >= date_trunc('month', now() at time zone 'Asia/Dubai')::date then
    raise exception 'month % has not ended; a month is closed only after it ends', to_char(v_m, 'YYYY-MM');
  end if;
  if exists (select 1 from public.accountant_month_close where month = v_m) then
    return jsonb_build_object('ok', true, 'month', to_char(v_m, 'YYYY-MM'), 'already_closed', true);
  end if;
  f := public.fn_accountant_month_close_figures(v_m) || jsonb_build_object('unit_economics', public.fn_accountant_unit_economics(v_m));
  v_sev := case when (f#>>'{bank_reconciliation,unmatched}')::int > 0 or (f->>'charge_audit_open_differences')::int > 0
                     or (f#>>'{disputes,open}')::int > 0
                     or (f#>>'{cash_position,runway,months}') is null or (f#>>'{cash_position,runway,months}')::numeric < 6
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
end $fn$;

create or replace function public.fn_ceo_pricing_monitor()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_week date := public.fn_ceo_review_week(); v_ev jsonb; v_quoted int; v_held bigint;
begin
  with q as (
    select i.id, (select count(*) from public.quotes x where x.inquiry_id = i.id) as quotes
      from public.inquiries i where i.created_at > now() - interval '90 days'
  )
  select jsonb_build_object(
    'pricing_config', (select to_jsonb(p) - 'id' - 'updated_at' from public.pricing_config p order by id limit 1),
    'requests_90d', (select count(*) from q),
    'quoted_requests_90d', (select count(*) from q where quotes > 0),
    'reveals_90d', (select count(*) from public.transactions where revealed_at > now() - interval '90 days'),
    'refunds_90d', (select count(*) from public.transactions where refund_requested_at > now() - interval '90 days'),
    'avg_quote_aed', (select round(avg(quote_amount), 2) from public.quotes where created_at > now() - interval '90 days' and quote_amount > 0),
    'avg_reveal_fee_aed', (select round(avg(reveal_fee), 2) from public.transactions where revealed_at > now() - interval '90 days'),
    'nonresponse_refunds', (select coalesce(sum(rv_nonresponse_refunds), 0) from public.leads),
    'supplier_fee_paying', (select count(*) from public.leads where registration_paid_at is not null),
    'competitors_on_file', (select count(*) from public.competitor),
    'unit_economics_last_month', public.fn_accountant_unit_economics((date_trunc('month', now() at time zone 'Asia/Dubai') - interval '1 month')::date))
  into v_ev;
  v_quoted := (v_ev->>'quoted_requests_90d')::int;
  insert into public.ceo_review (kind, period, facts, decision) values ('pricing_monitor', v_week, v_ev,
    case when v_quoted < 20 then 'insufficient_evidence' end)
  on conflict (kind, period) do update set facts = excluded.facts,
    decision = case when ceo_review.decided_at is null then excluded.decision else ceo_review.decision end;

  -- UNDER 20 QUOTED REQUESTS THE EVIDENCE CANNOT SUPPORT A PRICE CALL: recorded, not reasoned, not proposed.
  if v_quoted >= 20 and (select held_id from public.ceo_review where kind = 'pricing_monitor' and period = v_week) is null then
    v_held := public.fn_seat_duty_reason('ceo', 'ceo.pricing_monitor',
      'The weekly pricing review. From 90 days of evidence, decide whether our pricing (the supplier annual fee, the caps, '
        || 'the promotion window and the non-response charge) should stay as it is or whether an evidence-based change should '
        || 'be proposed to the founder. The 3 per cent reveal fee paid by the buyer is the founder''s fixed rule and is not in scope.',
      ('[{"id":"keep","meaning":"the evidence supports the current pricing"},'
      || '{"id":"propose_change","meaning":"the evidence supports proposing a specific change to the founder"}]')::jsonb,
      v_ev, jsonb_build_object('kind', 'pricing_monitor', 'period', v_week), 'ceo_pricing:' || v_week);
    update public.reasoning_held_question
       set request = jsonb_set(request, '{decision,fields}', jsonb_build_array(
             jsonb_build_object('key', 'proposal', 'question', 'the exact change proposed, if any, with the figure'),
             jsonb_build_object('key', 'evidence', 'question', 'the measured evidence it rests on')))
     where id = v_held;
    -- ONE CALL PER REPORT (24 Sep 2026, it_engineer): normal stakes, so think() runs no second-family verify on it.
    update public.reasoning_held_question set request = request || '{"stakes":"normal"}'::jsonb where id = v_held;
    update public.ceo_review set held_id = v_held where kind = 'pricing_monitor' and period = v_week;
  end if;
  return jsonb_build_object('week', v_week, 'quoted_requests_90d', v_quoted, 'reasoning_filed', v_held is not null);
end $fn$;

create or replace function public.fn_accountant_duties(p_r jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
end $fn$;
