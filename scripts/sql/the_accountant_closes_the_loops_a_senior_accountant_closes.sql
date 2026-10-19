-- THE ACCOUNTANT CLOSES THE LOOPS A SENIOR ACCOUNTANT CLOSES (accountant, founder ledger 1003 stage 2, 19 Oct 2026).
--
-- Assigned: accountant. Stage 1 of ledger 1003 measured the seat against a 20-year senior bar
-- (knowledge/standards/accountant.json in the seat-audit branch): 4 contributions partial, 2 missing. Each becomes a
-- seat_duty with its own last_ok_at that ACTS, in code, no model. Same shape as the CEO's (#1526).
--
-- ══ MEASURED, 19 Oct 2026, htdblwldjkcgjvmqkbeh ═══════════════════════════════════════════════════════════════════
--   ACC-C11 receipts: resend_inbound books (54 expense_entries carry a mailbox id) and the mailbox check records
--           (accountant_mailbox_check, 550 rows, last 04:30 UTC: 14 held over 24h); neither is an accountant.* duty, so
--           a stalled intake never shows as a seat failure.
--   ACC-C12 fn_accountant_recovery_tick runs only as one step inside the accountant runtime's big tick; no duty.
--   ACC-C13 fn_accountant_cash_forecast (91 days, week by week) is computed only inside the CEO weekly report; nothing
--           keeps it, and no duty explains the month's budget lines (budget_lines 36 rows).
--   ACC-C14 nothing measures taxable supplies against the VAT thresholds.
--   ACC-C15 MEASURED, NOT AS THE GAP SAID: fn_accountant_weekly_report already sends the CEO a weekly report (lane 2,
--           run by resilience_ping) with cash and costs, but no collections, exceptions or decisions needed, and no
--           duty owns it.
--   ACC-C16 fn_accountant_year_end_tick runs only inside the big tick; no duty.
--
-- ══ THE AUDITOR (ACC-C16): NOT APPLICABLE, and this file says why rather than building it ═══════════════════════
--   The company is a SOLE ESTABLISHMENT (DET licence 1633275), not an LLC. Federal Decree-Law 32 of 2021 (Commercial
--   Companies) governs companies; its auditor-appointment duty does not reach a sole establishment, which is its
--   natural-person owner trading under a licence. Under Corporate Tax, audited financial statements are required only
--   of a taxable person with revenue over AED 50,000,000 in the period, or a Qualifying Free Zone Person (Ministerial
--   Decision 82 of 2023; replaced from tax periods starting 1 Jan 2025 by Ministerial Decision 84 of 2025 on the same
--   AED 50m test). QuotesDone is a mainland establishment with revenue near zero. So no auditor is appointed and no duty
--   chases one; instead accountant.year_end re-tests the AED 50m condition every day and tells the CEO if it is ever
--   approached (80%), which is the point at which the answer would change.
--
-- ══ WHAT THIS ADDS (one duty per contribution) ════════════════════════════════════════════════════════════════════
--   ACC-C11 accountant.receipt_intake      daily  FAILS (so the seat shows red) when the mailbox check has not run for
--           26h or reports mail not taken in; posts every mailbox-booked expense not yet in the ledger; names
--           accountant as owner of every held expenses-mailbox email that has none.
--   ACC-C12 accountant.charge_recovery     daily  runs the recovery ledger on the UAE court clock and reports the open
--           position (claims, stages, amount) with its own last_ok_at.
--   ACC-C13 accountant.cash_forecast_weekly   weekly keeps the 13-week forecast in accountant_cash_forecast_week; a week
--           whose projected balance goes below zero goes to the CEO as elevated.
--           accountant.budget_variance     daily, acts monthly: for the last closed month, every budget line and every
--           account with spend gets budget, actual, variance and an EXPLANATION (the entries that drove it) in
--           accountant_budget_variance; lines over 10% and AED 100 go to the CEO once.
--   ACC-C14 accountant.vat_threshold       daily  taxable supplies (posted revenue) over the rolling 12 months and the
--           same plus the next 30 days at the last 30 days' rate, against AED 187,500 (voluntary) and AED 375,000
--           (mandatory) into accountant_vat_threshold_check; at 80% of mandatory, voluntary eligibility, or a breach,
--           the CEO is told once with the FTA deadline (30 days).
--   ACC-C15 accountant.finance_week        weekly one CEO report per ISO week: cash, collections, exceptions and the
--           decisions the CEO owes, beside the existing weekly report (which this does not change or send).
--   ACC-C16 accountant.year_end            daily  runs the year-end pack check with its own last_ok_at and re-tests the
--           AED 50m audit condition.
--
-- Everything to the CEO goes through fn_support_report_to_ceo (idempotent by key; the CEO's sweep acknowledges it).
-- Nothing here notifies the founder. NOT CHANGED: fn_accountant_weekly_report*, fn_accountant_recovery_tick,
-- fn_accountant_year_end_tick, fn_accountant_cash_forecast, fn_expense_post_to_gl (called, not redefined).
-- Prevented by: scripts/checks/the_accountant_senior_duties_are_registered_and_act.test.mjs and the aborted-transaction
-- probe the_accountant_closes_the_loops_a_senior_accountant_closes_probe.sql.
--
--   node scripts/apply_sql.mjs scripts/sql/the_accountant_closes_the_loops_a_senior_accountant_closes.sql --apply --ddl

-- ── ACC-C11 ───────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_receipt_intake_duty()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
end $fn$;
revoke execute on function public.fn_accountant_receipt_intake_duty() from public, anon, authenticated;
grant execute on function public.fn_accountant_receipt_intake_duty() to service_role;

-- ── ACC-C12 ───────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_charge_recovery_duty()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  return jsonb_build_object('tick', public.fn_accountant_recovery_tick(),
    'open_claims', (select count(*) from public.v_accountant_recovery_ledger where not demo),
    'open_claim_aed', (select coalesce(sum(claim_aed), 0) from public.v_accountant_recovery_ledger where not demo),
    'by_stage', (select coalesce(jsonb_object_agg(stage, n), '{}'::jsonb) from (select stage, count(*) n from public.v_accountant_recovery_ledger where not demo group by stage) x));
end $fn$;
revoke execute on function public.fn_accountant_charge_recovery_duty() from public, anon, authenticated;
grant execute on function public.fn_accountant_charge_recovery_duty() to service_role;

-- ── ACC-C13 ───────────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.accountant_cash_forecast_week (
  week        date primary key,            -- ISO week's Monday, Dubai
  forecast    jsonb not null,              -- fn_accountant_cash_forecast as of that Monday: 13 weeks
  ceo_report_id bigint,
  recorded_at timestamptz not null default now()
);
alter table public.accountant_cash_forecast_week enable row level security;
drop policy if exists accountant_cash_forecast_week_service_role_only on public.accountant_cash_forecast_week;
create policy accountant_cash_forecast_week_service_role_only on public.accountant_cash_forecast_week as permissive for all to public using (false) with check (false);
revoke all on public.accountant_cash_forecast_week from anon, authenticated;

create or replace function public.fn_accountant_cash_forecast_week()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
end $fn$;
revoke execute on function public.fn_accountant_cash_forecast_week() from public, anon, authenticated;
grant execute on function public.fn_accountant_cash_forecast_week() to service_role;

create table if not exists public.accountant_budget_variance (
  month        date not null,
  account_code text not null,
  budget_aed   numeric(18,2) not null,
  actual_aed   numeric(18,2) not null,
  variance_aed numeric(18,2) not null,      -- actual - budget
  variance_pct numeric,
  explanation  text not null,
  drivers      jsonb not null default '[]'::jsonb,
  recorded_at  timestamptz not null default now(),
  primary key (month, account_code)
);
alter table public.accountant_budget_variance enable row level security;
drop policy if exists accountant_budget_variance_service_role_only on public.accountant_budget_variance;
create policy accountant_budget_variance_service_role_only on public.accountant_budget_variance as permissive for all to public using (false) with check (false);
revoke all on public.accountant_budget_variance from anon, authenticated;

create or replace function public.fn_accountant_budget_variance()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
end $fn$;
revoke execute on function public.fn_accountant_budget_variance() from public, anon, authenticated;
grant execute on function public.fn_accountant_budget_variance() to service_role;

-- ── ACC-C14 ───────────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.accountant_vat_threshold_check (
  checked_on          date primary key,          -- Dubai date
  taxable_12m_aed     numeric(18,2) not null,    -- posted revenue, the 12 months to today
  last_30d_aed        numeric(18,2) not null,
  projected_aed       numeric(18,2) not null,    -- the 12 months ending 30 days from now: last 335 days + last 30 days' rate
  status              text not null check (status in ('below', 'approaching', 'voluntary_eligible', 'mandatory')),
  register_by         date,                      -- FTA: apply within 30 days
  ceo_report_id       bigint,
  recorded_at         timestamptz not null default now()
);
alter table public.accountant_vat_threshold_check enable row level security;
drop policy if exists accountant_vat_threshold_check_service_role_only on public.accountant_vat_threshold_check;
create policy accountant_vat_threshold_check_service_role_only on public.accountant_vat_threshold_check as permissive for all to public using (false) with check (false);
revoke all on public.accountant_vat_threshold_check from anon, authenticated;

create or replace function public.fn_accountant_vat_threshold(p_as_of date default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
end $fn$;
revoke execute on function public.fn_accountant_vat_threshold(date) from public, anon, authenticated;
grant execute on function public.fn_accountant_vat_threshold(date) to service_role;

-- ── ACC-C15 ───────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_finance_week()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
end $fn$;
revoke execute on function public.fn_accountant_finance_week() from public, anon, authenticated;
grant execute on function public.fn_accountant_finance_week() to service_role;

-- ── ACC-C16 ───────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_year_end_duty()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
end $fn$;
revoke execute on function public.fn_accountant_year_end_duty() from public, anon, authenticated;
grant execute on function public.fn_accountant_year_end_duty() to service_role;

-- ── the duties ────────────────────────────────────────────────────────────────────────────────────────────────────
insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('accountant.receipt_intake', 'accountant', interval '1 day', 'fn_accountant_receipt_intake_duty',
   'ACC-C11: fails when the expenses mailbox check stalls or mail was not taken in; posts mailbox-booked expenses to the ledger; gives every held receipt email the accountant as owner.',
   'scripts/sql/the_accountant_closes_the_loops_a_senior_accountant_closes.sql'),
  ('accountant.charge_recovery', 'accountant', interval '1 day', 'fn_accountant_charge_recovery_duty',
   'ACC-C12: runs every supplier non-response charge on the UAE court clock and reports the open position.',
   'scripts/sql/the_accountant_closes_the_loops_a_senior_accountant_closes.sql'),
  ('accountant.cash_forecast_weekly', 'accountant', interval '7 days', 'fn_accountant_cash_forecast_week',
   'ACC-C13: keeps the 13-week cash forecast each week; a week below zero goes to the CEO.',
   'scripts/sql/the_accountant_closes_the_loops_a_senior_accountant_closes.sql'),
  ('accountant.budget_variance', 'accountant', interval '1 day', 'fn_accountant_budget_variance',
   'ACC-C13: every budget line of the last closed month gets its actual, variance and explanation; lines off by 10% go to the CEO.',
   'scripts/sql/the_accountant_closes_the_loops_a_senior_accountant_closes.sql'),
  ('accountant.vat_threshold', 'accountant', interval '1 day', 'fn_accountant_vat_threshold',
   'ACC-C14: taxable supplies over 12 months and 30 days ahead against AED 187,500 and AED 375,000; the CEO is told with the FTA deadline.',
   'scripts/sql/the_accountant_closes_the_loops_a_senior_accountant_closes.sql'),
  ('accountant.finance_week', 'accountant', interval '7 days', 'fn_accountant_finance_week',
   'ACC-C15: one CEO report a week -- cash, collections, exceptions and the decisions waiting on the CEO.',
   'scripts/sql/the_accountant_closes_the_loops_a_senior_accountant_closes.sql'),
  ('accountant.year_end', 'accountant', interval '1 day', 'fn_accountant_year_end_duty',
   'ACC-C16: the year-end pack check with its own last_ok_at, and the AED 50m audit condition re-tested (no auditor is required of a sole establishment below it).',
   'scripts/sql/the_accountant_closes_the_loops_a_senior_accountant_closes.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;
