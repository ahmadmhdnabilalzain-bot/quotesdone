-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709083034   name: finance_forecast_and_kpis
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Consolidated finance KPI rollup (single row)
create or replace view public.finance_kpis as
with rr as (
  select
    coalesce(sum(case when ga.type='revenue' then l.credit-l.debit else 0 end),0) as rev30,
    coalesce(sum(case when ga.type='expense' then l.debit-l.credit else 0 end),0) as exp30
  from gl_journal_lines l
  join gl_journal j on j.id=l.journal_id and j.status='posted'
  join gl_accounts ga on ga.code=l.account_code
  where j.entry_date >= current_date-30
),
ar as (
  select
    coalesce(sum(amount_due) filter (where status not in ('paid','waived')),0) as ar_outstanding,
    coalesce(sum(amount_due) filter (where status not in ('paid','waived') and due_date_30 < current_date),0) as ar_overdue,
    coalesce(sum(amount_due) filter (where status='paid'),0) as ar_collected
  from supplier_dues
),
ap as (
  select coalesce(sum(balance_due),0) as ap_outstanding,
         coalesce(sum(balance_due) filter (where days_overdue > 0),0) as ap_overdue
  from ap_open_bills
),
bud as ( select count(*) filter (where type='expense' and pct_of_budget > 110) as budget_overruns from budget_vs_actual_summary )
select
  (select coalesce(sum(balance),0) from gl_account_balances where code in ('1000','1050')) as cash,
  (select coalesce(sum(balance),0) from gl_account_balances where type='revenue') as revenue_total,
  (select coalesce(sum(balance),0) from gl_account_balances where type='expense') as expense_total,
  (select coalesce(sum(balance),0) from gl_account_balances where type='revenue')
    - (select coalesce(sum(balance),0) from gl_account_balances where type='expense') as net_income,
  case when (select coalesce(sum(balance),0) from gl_account_balances where type='revenue')>0
    then round(100.0*((select coalesce(sum(balance),0) from gl_account_balances where type='revenue')-(select coalesce(sum(balance),0) from gl_account_balances where type='expense'))
      /(select coalesce(sum(balance),0) from gl_account_balances where type='revenue'),1) else null end as margin_pct,
  rr.rev30 as revenue_30d, rr.exp30 as expense_30d, (rr.exp30-rr.rev30) as monthly_burn,
  case when (rr.exp30-rr.rev30) > 0 and (select coalesce(sum(balance),0) from gl_account_balances where code in ('1000','1050')) > 0
    then round((select coalesce(sum(balance),0) from gl_account_balances where code in ('1000','1050'))/(rr.exp30-rr.rev30),1) else null end as runway_months,
  ar.ar_outstanding, ar.ar_overdue, ar.ar_collected,
  case when (ar.ar_collected+ar.ar_outstanding) > 0 then round(100.0*ar.ar_collected/(ar.ar_collected+ar.ar_outstanding),1) else null end as collection_rate,
  ap.ap_outstanding, ap.ap_overdue, bud.budget_overruns
from rr, ar, ap, bud;

-- Cash-flow + revenue forecast, 30/60/90 horizons
create or replace function public.fn_finance_forecast()
returns jsonb language sql stable security definer set search_path to 'public','pg_catalog'
as $fn$
  with base as (
    select (select coalesce(sum(balance),0) from gl_account_balances where code in ('1000','1050')) as cash,
           (select coalesce(sum(case when ga.type='revenue' then l.credit-l.debit else 0 end),0)
              from gl_journal_lines l join gl_journal j on j.id=l.journal_id and j.status='posted'
              join gl_accounts ga on ga.code=l.account_code where j.entry_date>=current_date-30) as rev30,
           (select coalesce(sum(case when ga.type='expense' then l.debit-l.credit else 0 end),0)
              from gl_journal_lines l join gl_journal j on j.id=l.journal_id and j.status='posted'
              join gl_accounts ga on ga.code=l.account_code where j.entry_date>=current_date-30) as exp30
  ),
  hz as (
    select h,
      (select coalesce(sum(amount_due),0) from supplier_dues where status not in ('paid','waived') and coalesce(due_date_30,reveal_date+30) <= current_date + h) as ar_in,
      (select coalesce(sum(balance_due),0) from ap_open_bills where coalesce(due_date, bill_date) <= current_date + h) as ap_out
    from (values (30),(60),(90)) v(h)
  )
  select jsonb_build_object(
    'as_of', now(),
    'cash_now', (select cash from base),
    'assumptions', jsonb_build_object('revenue_run_rate_30d',(select rev30 from base),'expense_run_rate_30d',(select exp30 from base)),
    'horizons', (select jsonb_agg(jsonb_build_object(
        'days', h,
        'expected_inflows', round(ar_in + (select rev30 from base)*(h/30.0), 2),
        'expected_outflows', round(ap_out + (select exp30 from base)*(h/30.0), 2),
        'projected_cash', round((select cash from base) + ar_in + (select rev30 from base)*(h/30.0) - ap_out - (select exp30 from base)*(h/30.0), 2),
        'revenue_forecast', round((select rev30 from base)*(h/30.0), 2)
      ) order by h) from hz)
  );
$fn$;

create table if not exists public.finance_kpi_snapshots (
  id bigint generated always as identity primary key,
  snapshot_date date not null default current_date,
  kpis jsonb not null,
  forecast jsonb,
  created_at timestamptz not null default now()
);
create unique index if not exists finance_kpi_snap_day on public.finance_kpi_snapshots(snapshot_date);
revoke all on public.finance_kpis, public.finance_kpi_snapshots from anon, authenticated;
revoke all on function public.fn_finance_forecast() from anon, authenticated, public;
