-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709105933   name: strategy_intel_risk_kpis
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Market & competitor intelligence store (fed by web research / a connector / the founder)
create table if not exists public.market_intel(
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('competitor','trend','expansion','regulatory','other')),
  title text not null,
  detail text,
  source text,
  impact text default 'medium' check (impact in ('low','medium','high')),
  status text default 'open' check (status in ('open','reviewed','actioned','dismissed')),
  created_at timestamptz not null default now());
alter table public.market_intel enable row level security;

-- Strategic risk register (refreshed from internal signals by fn_strategy_scan)
create table if not exists public.strategy_risks(
  id bigint generated always as identity primary key,
  category text not null,
  title text not null,
  likelihood int not null default 3 check (likelihood between 1 and 5),
  impact int not null default 3 check (impact between 1 and 5),
  score int generated always as (likelihood*impact) stored,
  mitigation text,
  source text default 'internal_scan',
  status text default 'open' check (status in ('open','mitigating','accepted','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(category, title));
alter table public.strategy_risks enable row level security;

-- Upsert helper for the risk register
create or replace function public.fn_strategy_risk(p_cat text, p_title text, p_like int, p_impact int, p_mit text)
returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  insert into public.strategy_risks(category,title,likelihood,impact,mitigation)
  values (p_cat,p_title, greatest(1,least(5,p_like)), greatest(1,least(5,p_impact)), p_mit)
  on conflict (category,title) do update
    set likelihood=excluded.likelihood, impact=excluded.impact, mitigation=excluded.mitigation, updated_at=now();
end $$;
revoke all on function public.fn_strategy_risk(text,text,int,int,text) from anon, authenticated, public;

-- Refresh the strategic risk register from live internal signals. Read/assess only.
create or replace function public.fn_strategy_scan()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare
  v_active int; v_top_share numeric; v_under int; v_cash numeric; v_burn numeric; v_rev numeric; v_intel int; v_risks int;
begin
  select count(distinct supplier_id) into v_active from public.quotes
    where created_at > now()-interval '90 days' and supplier_id is not null;
  select round(100.0*max(c)/nullif(sum(c),0),1) into v_top_share from (
    select supplier_id, count(*) c from public.quotes
    where created_at > now()-interval '90 days' and supplier_id is not null group by supplier_id) s;
  select jsonb_array_length(coalesce(fn_strategy_metrics()->'under_supplied','[]'::jsonb)) into v_under;
  select cash, monthly_burn, revenue_30d into v_cash, v_burn, v_rev from public.finance_kpis;
  select count(*) into v_intel from public.market_intel where kind='competitor' and status<>'dismissed';

  -- Supplier concentration / thin marketplace
  if coalesce(v_active,0) < 5 then
    perform public.fn_strategy_risk('supply','Thin supplier base — marketplace liquidity risk',
      case when coalesce(v_active,0)<=2 then 5 else 4 end, 4,
      'Recruit suppliers across active categories; a marketplace with <5 active suppliers cannot reliably fulfil demand or sustain competitive quoting.');
  end if;
  if coalesce(v_top_share,0) >= 50 then
    perform public.fn_strategy_risk('concentration','Supplier concentration — one supplier dominates quoting',
      4, 4, 'One supplier accounts for '||v_top_share||'% of recent quotes. Diversify to reduce dependency and pricing power imbalance.');
  end if;
  -- Demand not being served
  if coalesce(v_under,0) > 0 then
    perform public.fn_strategy_risk('market','Under-supplied high-demand categories',
      4, 3, v_under||' categories have demand outstripping supplier coverage — targeted supplier acquisition converts lost RFQs into revenue.');
  end if;
  -- Cash / runway
  if coalesce(v_cash,0) <= 0 then
    perform public.fn_strategy_risk('financial','Negative cash position',
      4, 5, 'Cash position is '||coalesce(v_cash,0)||' AED. Prioritise fee collection, control burn, and validate the monetisation model before scaling spend.');
  elsif v_burn is not null and v_burn > 0 and v_cash/v_burn < 6 then
    perform public.fn_strategy_risk('financial','Short cash runway (<6 months)',
      3, 5, 'At current burn the runway is under 6 months. Extend runway via revenue, cost control, or funding before committing to expansion.');
  end if;
  -- Early-stage revenue scale
  if coalesce(v_rev,0) < 5000 then
    perform public.fn_strategy_risk('market','Pre-scale revenue — monetisation unproven',
      3, 4, 'Monthly revenue is still small; validate willingness-to-pay on the reveal fee and supplier registration before heavy growth investment.');
  end if;
  -- No competitor intelligence on file
  if coalesce(v_intel,0) = 0 then
    perform public.fn_strategy_risk('market','No competitor intelligence on file',
      3, 3, 'No competitor records in market_intel. Add a competitor/market-trend source (web research or a connector) so positioning and pricing decisions are evidence-based.');
  end if;

  select count(*) into v_risks from public.strategy_risks where status='open';
  return jsonb_build_object('active_suppliers_90d',v_active,'top_supplier_share_pct',v_top_share,
    'under_supplied',v_under,'cash',v_cash,'competitor_intel',v_intel,'open_risks',v_risks);
end $$;
revoke all on function public.fn_strategy_scan() from anon, authenticated, public;

-- Consolidated strategy KPIs (one row)
create or replace view public.strategy_kpis as
with sup as (select supplier_id, count(*) c from public.quotes
             where created_at > now()-interval '90 days' and supplier_id is not null group by supplier_id),
agg as (select count(*) active, coalesce(round(100.0*max(c)/nullif(sum(c),0),1),0) top_share from sup),
fin as (select cash, monthly_burn, runway_months, revenue_30d, margin_pct from public.finance_kpis),
rk as (select count(*) filter (where status='open') open_risks, max(score) top_score,
       (array_agg(title order by score desc))[1] top_title from public.strategy_risks where status='open')
select
  agg.active as active_suppliers_90d,
  agg.top_share as top_supplier_share_pct,
  jsonb_array_length(coalesce(fn_strategy_metrics()->'under_supplied','[]'::jsonb)) as under_supplied_categories,
  fin.cash, fin.monthly_burn,
  case when fin.cash>0 and fin.monthly_burn>0 then round(fin.cash/fin.monthly_burn,1) else fin.runway_months end as runway_months,
  fin.revenue_30d, fin.margin_pct,
  coalesce(rk.open_risks,0) as open_risks, coalesce(rk.top_score,0) as top_risk_score, rk.top_title as top_risk,
  (select count(*) from public.market_intel where kind='competitor' and status<>'dismissed') as competitor_intel,
  (select count(*) from public.market_intel where kind='trend' and status<>'dismissed') as market_trends,
  (select count(*) from public.market_intel where status='open') as open_intel,
  (select max(created_at) from public.simulations) as last_simulation_at
from agg, fin, rk;

create table if not exists public.strategy_kpi_snapshots(
  id bigint generated always as identity primary key,
  snapshot_date date not null default current_date,
  kpis jsonb not null,
  created_at timestamptz not null default now());
alter table public.strategy_kpi_snapshots enable row level security;
