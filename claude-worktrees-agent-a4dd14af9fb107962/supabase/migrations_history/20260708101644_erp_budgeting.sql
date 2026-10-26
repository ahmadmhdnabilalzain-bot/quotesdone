-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708101644   name: erp_budgeting
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============================================================
-- ERP: Budgeting (budget vs actual from GL)
-- ============================================================

create table if not exists public.budgets (
  id bigint generated always as identity primary key,
  name text not null,
  fiscal_year int not null,
  status text not null default 'active' check (status in ('draft','active','closed')),
  created_by text,
  created_at timestamptz not null default now(),
  unique (name, fiscal_year)
);

create table if not exists public.budget_lines (
  id bigint generated always as identity primary key,
  budget_id bigint not null references public.budgets(id) on delete cascade,
  account_code text not null references public.gl_accounts(code),
  period_month date not null,                    -- month-start (e.g. 2026-01-01)
  amount numeric(18,2) not null default 0,
  unique (budget_id, account_code, period_month)
);
create index if not exists idx_budget_lines_budget on public.budget_lines(budget_id);

-- ---- Create a budget -----------------------------------------------------
create or replace function public.fn_budget_create(p_name text, p_year int, p_by text default null)
returns bigint language plpgsql security definer set search_path=public,pg_catalog as $$
declare b bigint;
begin
  insert into public.budgets(name,fiscal_year,created_by) values (p_name,p_year,p_by) returning id into b;
  return b;
end $$;

-- ---- Set one month's budget for an account (upsert) ----------------------
create or replace function public.fn_budget_set(
  p_budget bigint, p_account text, p_month date, p_amount numeric)
returns void language plpgsql security definer set search_path=public,pg_catalog as $$
begin
  insert into public.budget_lines(budget_id,account_code,period_month,amount)
    values (p_budget, p_account, date_trunc('month',p_month)::date, round(p_amount,2))
  on conflict (budget_id,account_code,period_month)
    do update set amount = excluded.amount;
end $$;

-- ---- Spread an annual amount evenly across 12 months ---------------------
create or replace function public.fn_budget_set_annual(
  p_budget bigint, p_account text, p_amount numeric)
returns void language plpgsql security definer set search_path=public,pg_catalog as $$
declare yr int; base numeric(18,2); rem numeric(18,2); mth date; i int; amt numeric(18,2);
begin
  select fiscal_year into yr from public.budgets where id=p_budget;
  if yr is null then raise exception 'budget % not found', p_budget; end if;
  base := round(round(p_amount,2)/12, 2);
  rem  := round(p_amount,2) - base*12;                 -- rounding remainder to last month
  for i in 0..11 loop
    mth := make_date(yr,1,1) + (i||' months')::interval;
    amt := base + case when i=11 then rem else 0 end;
    perform public.fn_budget_set(p_budget, p_account, mth, amt);
  end loop;
end $$;

-- ---- Budget vs actual (monthly grain) ------------------------------------
create or replace view public.budget_vs_actual as
with actual as (
  select l.account_code, date_trunc('month', j.entry_date)::date as period_month,
         sum(l.debit) as dr, sum(l.credit) as cr
  from public.gl_journal_lines l
  join public.gl_journal j on j.id = l.journal_id and j.status='posted'
  group by 1,2
)
select b.id as budget_id, b.name as budget_name, b.fiscal_year,
       bl.account_code, ga.name as account_name, ga.type,
       bl.period_month,
       bl.amount as budget_amount,
       coalesce(case when ga.normal_balance='D' then a.dr-a.cr else a.cr-a.dr end,0) as actual_amount,
       bl.amount - coalesce(case when ga.normal_balance='D' then a.dr-a.cr else a.cr-a.dr end,0) as variance
from public.budget_lines bl
join public.budgets b on b.id=bl.budget_id
join public.gl_accounts ga on ga.code=bl.account_code
left join actual a on a.account_code=bl.account_code and a.period_month=bl.period_month;

-- ---- Budget vs actual (full-year rollup per account) ---------------------
create or replace view public.budget_vs_actual_summary as
select budget_id, budget_name, fiscal_year, account_code, account_name, type,
       sum(budget_amount) as budget_ytd,
       sum(actual_amount) as actual_ytd,
       sum(variance)      as variance_ytd,
       case when sum(budget_amount) <> 0
            then round(100.0*sum(actual_amount)/sum(budget_amount),1) else null end as pct_of_budget
from public.budget_vs_actual
group by budget_id, budget_name, fiscal_year, account_code, account_name, type
order by account_code;

