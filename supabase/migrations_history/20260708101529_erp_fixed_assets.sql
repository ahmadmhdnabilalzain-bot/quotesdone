-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708101529   name: erp_fixed_assets
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============================================================
-- ERP: Fixed Assets (straight-line depreciation, posts to GL)
-- ============================================================

-- gain/loss on disposal accounts
insert into public.gl_accounts (code,name,type,subtype,normal_balance,parent_code,is_active) values
 ('4300','Gain on Asset Disposal','revenue','other','C',null,true),
 ('6500','Loss on Asset Disposal','expense','other','D',null,true)
on conflict (code) do nothing;

create table if not exists public.fa_assets (
  id bigint generated always as identity primary key,
  asset_no text unique,
  name text not null,
  category text,
  acquire_date date not null default current_date,
  in_service_date date not null default current_date,
  cost numeric(18,2) not null check (cost >= 0),
  salvage_value numeric(18,2) not null default 0,
  useful_life_months int not null check (useful_life_months > 0),
  method text not null default 'straight_line' check (method in ('straight_line')),
  asset_account text not null default '1600' references public.gl_accounts(code),
  accum_account text not null default '1650' references public.gl_accounts(code),
  expense_account text not null default '6400' references public.gl_accounts(code),
  accumulated_depreciation numeric(18,2) not null default 0,
  status text not null default 'active' check (status in ('active','fully_depreciated','disposed')),
  disposed_date date,
  created_by text,
  created_at timestamptz not null default now()
);

create table if not exists public.fa_depreciation (
  id bigint generated always as identity primary key,
  asset_id bigint not null references public.fa_assets(id) on delete cascade,
  period date not null,                     -- month being depreciated (use month-end)
  amount numeric(18,2) not null,
  gl_journal_id bigint references public.gl_journal(id),
  created_at timestamptz not null default now(),
  unique (asset_id, period)
);

-- ---- Acquire an asset ----------------------------------------------------
create or replace function public.fn_fa_acquire(
  p_name text, p_category text, p_acquire_date date, p_cost numeric,
  p_salvage numeric, p_life_months int, p_in_service date default null,
  p_fund_account text default '1000', p_post_gl boolean default true, p_by text default null)
returns bigint language plpgsql security definer set search_path=public,pg_catalog as $$
declare a bigint; j bigint;
begin
  insert into public.fa_assets(name,category,acquire_date,in_service_date,cost,salvage_value,
        useful_life_months,created_by)
    values (p_name,p_category,coalesce(p_acquire_date,current_date),
            coalesce(p_in_service,p_acquire_date,current_date),
            round(p_cost,2),round(coalesce(p_salvage,0),2),p_life_months,p_by)
    returning id into a;
  update public.fa_assets set asset_no='FA-'||lpad(a::text,6,'0') where id=a;
  if p_post_gl then                                  -- Dr Fixed Asset  Cr funding account
    j := public.fn_gl_entry(coalesce(p_acquire_date,current_date),
           'Asset acquisition '||p_name, 'fa_acquire', a::text,
           jsonb_build_array(jsonb_build_object('account','1600','debit',round(p_cost,2)),
                             jsonb_build_object('account',p_fund_account,'credit',round(p_cost,2))), p_by);
  end if;
  return a;
end $$;

-- ---- Depreciate one asset for one period (idempotent per period) ----------
create or replace function public.fn_fa_depreciate(p_asset bigint, p_period date)
returns bigint language plpgsql security definer set search_path=public,pg_catalog as $$
declare a record; depreciable numeric(18,2); remaining numeric(18,2);
        monthly numeric(18,2); amt numeric(18,2); j bigint;
begin
  select * into a from public.fa_assets where id=p_asset;
  if a.id is null then raise exception 'asset % not found', p_asset; end if;
  if a.status <> 'active' then return null; end if;
  if p_period < a.in_service_date then return null; end if;               -- not yet in service
  if exists (select 1 from public.fa_depreciation where asset_id=p_asset and period=p_period) then
    return null;                                                          -- already booked
  end if;
  depreciable := a.cost - a.salvage_value;
  remaining := depreciable - a.accumulated_depreciation;
  if remaining <= 0 then
    update public.fa_assets set status='fully_depreciated' where id=p_asset; return null;
  end if;
  monthly := round(depreciable / a.useful_life_months, 2);
  amt := least(monthly, remaining);                                       -- final period soaks rounding
  j := public.fn_gl_entry(p_period, 'Depreciation '||a.asset_no||' '||to_char(p_period,'YYYY-MM'),
         'fa_deprec', p_asset::text,
         jsonb_build_array(jsonb_build_object('account',a.expense_account,'debit',amt),
                           jsonb_build_object('account',a.accum_account,'credit',amt)), null);
  insert into public.fa_depreciation(asset_id,period,amount,gl_journal_id) values (p_asset,p_period,amt,j);
  update public.fa_assets
     set accumulated_depreciation = accumulated_depreciation + amt,
         status = case when accumulated_depreciation + amt >= depreciable then 'fully_depreciated' else 'active' end
   where id=p_asset;
  return j;
end $$;

-- ---- Run depreciation for all active assets for a period ------------------
create or replace function public.fn_fa_run_depreciation(p_period date default null)
returns int language plpgsql security definer set search_path=public,pg_catalog as $$
declare per date := coalesce(p_period, (date_trunc('month',current_date)+interval '1 month -1 day')::date);
        r record; n int := 0; j bigint;
begin
  for r in select id from public.fa_assets where status='active' and in_service_date <= per loop
    j := public.fn_fa_depreciate(r.id, per);
    if j is not null then n := n + 1; end if;
  end loop;
  return n;
end $$;

-- ---- Dispose an asset (with gain/loss) -----------------------------------
create or replace function public.fn_fa_dispose(
  p_asset bigint, p_date date, p_proceeds numeric default 0,
  p_proceeds_account text default '1000', p_by text default null)
returns bigint language plpgsql security definer set search_path=public,pg_catalog as $$
declare a record; nbv numeric(18,2); proceeds numeric(18,2); gainloss numeric(18,2);
        gl_lines jsonb; j bigint;
begin
  select * into a from public.fa_assets where id=p_asset;
  if a.id is null then raise exception 'asset % not found', p_asset; end if;
  if a.status='disposed' then raise exception 'asset % already disposed', p_asset; end if;
  proceeds := round(coalesce(p_proceeds,0),2);
  nbv := a.cost - a.accumulated_depreciation;
  gainloss := proceeds - nbv;                          -- +gain / -loss
  gl_lines := jsonb_build_array(
      jsonb_build_object('account',a.accum_account,'debit',a.accumulated_depreciation),  -- clear accum
      jsonb_build_object('account',a.asset_account,'credit',a.cost));                     -- remove cost
  if proceeds > 0 then
    gl_lines := gl_lines || jsonb_build_object('account',p_proceeds_account,'debit',proceeds);
  end if;
  if gainloss > 0 then
    gl_lines := gl_lines || jsonb_build_object('account','4300','credit',gainloss);       -- gain
  elsif gainloss < 0 then
    gl_lines := gl_lines || jsonb_build_object('account','6500','debit',-gainloss);       -- loss
  end if;
  j := public.fn_gl_entry(coalesce(p_date,current_date), 'Disposal '||a.asset_no,
         'fa_dispose', p_asset::text, gl_lines, p_by);
  update public.fa_assets set status='disposed', disposed_date=coalesce(p_date,current_date) where id=p_asset;
  return j;
end $$;

-- ---- Asset register view -------------------------------------------------
create or replace view public.fa_register as
select id, asset_no, name, category, acquire_date, in_service_date, cost,
       salvage_value, useful_life_months, accumulated_depreciation,
       (cost - accumulated_depreciation) as net_book_value, status, disposed_date
from public.fa_assets
order by asset_no;

