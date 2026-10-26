-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709105024   name: reporting_registry_generator_kpis
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Helper: render a flat jsonb object as "  Key Label: value" lines (skips nulls/objects)
create or replace function public.fn_kv_block(obj jsonb)
returns text language plpgsql immutable set search_path to 'public','pg_temp' as $$
declare k text; v text; out text := ''; begin
  if obj is null then return '  (no data)'; end if;
  for k, v in select key, value from jsonb_each_text(obj) loop
    if v is null or k in ('id','snapshot_date','created_at','captured_at') then continue; end if;
    out := out || '  ' || initcap(replace(k,'_',' ')) || ': ' || v || E'\n';
  end loop;
  if out = '' then out := '  (no data)'; end if;
  return rtrim(out, E'\n');
end $$;

-- Unified catalog of EVERY generated report across the three stores
create or replace view public.report_registry as
select 'narrative'::text as source, report_type, title,
       coalesce(week_start::text, to_char(created_at,'YYYY-MM-DD')) as period,
       created_at, id
from public.board_reports
union all
select 'exec', 'exec_summary', officer||' — '||period, period, created_at, id
from public.exec_reports
union all
select 'finance', coalesce(kind,'financial'),
       'Financial — '||coalesce(kind,'')||' '||coalesce(period_start::text,''),
       coalesce(period_start::text, to_char(created_at,'YYYY-MM-DD')), created_at, id
from public.finance_reports;

-- On-demand generator for report types not covered by the existing period/board/finance functions.
-- SURFACES ONLY: writes an internal report row. Never emails, sends to the board, or publishes.
create or replace function public.fn_report_generate(p_kind text)
returns bigint language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_title text; v_body text; v_kpis jsonb; v_sections jsonb; v_exec text; v_id bigint;
  j_deal jsonb; j_sup jsonb; j_fin jsonb; j_mkt jsonb; j_ops jsonb; j_cust jsonb; j_ai jsonb;
begin
  if p_kind = 'department' then
    select to_jsonb(k.*) into j_deal from public.crm_deal_kpis k limit 1;
    select to_jsonb(k.*) into j_sup  from public.supplier_kpis  k limit 1;
    select to_jsonb(k.*) into j_fin  from public.finance_kpis   k limit 1;
    select to_jsonb(k.*) into j_mkt  from public.marketing_kpis k limit 1;
    select to_jsonb(k.*) into j_ops  from public.ops_kpis       k limit 1;
    v_sections := jsonb_build_array(
      jsonb_build_object('heading','Sales & Pipeline','body', public.fn_kv_block(j_deal)),
      jsonb_build_object('heading','Supply',          'body', public.fn_kv_block(j_sup)),
      jsonb_build_object('heading','Finance',         'body', public.fn_kv_block(j_fin)),
      jsonb_build_object('heading','Marketing',       'body', public.fn_kv_block(j_mkt)),
      jsonb_build_object('heading','Operations',      'body', public.fn_kv_block(j_ops)));
    v_title := 'Department Report — '||to_char(now(),'YYYY-MM-DD');
    v_exec  := 'Cross-department KPI rollup: Sales/Pipeline, Supply, Finance, Marketing, Operations.';
    v_kpis  := jsonb_build_object('sales',j_deal,'supply',j_sup,'finance',j_fin,'marketing',j_mkt,'operations',j_ops);

  elsif p_kind = 'supplier' then
    select to_jsonb(k.*) into j_sup from public.supplier_kpis k limit 1;
    v_sections := jsonb_build_array(jsonb_build_object('heading','Supplier Base','body', public.fn_kv_block(j_sup)));
    v_title := 'Supplier Report — '||to_char(now(),'YYYY-MM-DD');
    v_exec  := 'Supplier base health, coverage and compliance snapshot.';
    v_kpis  := j_sup;

  elsif p_kind = 'customer' then
    select to_jsonb(k.*) into j_cust from public.customer_kpis k limit 1;
    v_sections := jsonb_build_array(jsonb_build_object('heading','Customer Base','body', public.fn_kv_block(j_cust)));
    v_title := 'Customer Report — '||to_char(now(),'YYYY-MM-DD');
    v_exec  := 'Customer base health, activity and retention snapshot.';
    v_kpis  := j_cust;

  elsif p_kind = 'ai' then
    j_ai := jsonb_build_object(
      'active_agents',     (select count(*) from public.category_agents where active),
      'actions_pending',   (select count(*) from public.agent_actions where status in ('pending','needs_review')),
      'actions_done_7d',   (select count(*) from public.agent_actions where status in ('done','auto_done') and created_at > now()-interval '7 days'),
      'actions_rejected_30d',(select count(*) from public.agent_actions where status='rejected' and created_at > now()-interval '30 days'),
      'avg_run_success_pct',(select round(avg(run_success_pct)::numeric,1) from public.ai_agent_quality),
      'total_open_escalations',(select coalesce(sum(open_escalations),0) from public.ai_agent_quality),
      'cron_jobs_active',  (select count(*) from cron.job where active),
      'cron_failures_24h', (select count(*) from cron.job_run_details where status='failed' and start_time > now()-interval '24 hours'));
    v_sections := jsonb_build_array(
      jsonb_build_object('heading','AI Agent Fleet','body', public.fn_kv_block(j_ai)),
      jsonb_build_object('heading','Latest Trainer Snapshot','body',
        public.fn_kv_block((select kpis from public.ai_trainer_snapshots order by created_at desc limit 1))));
    v_title := 'AI Report — '||to_char(now(),'YYYY-MM-DD');
    v_exec  := 'AI agent fleet activity, autonomy queue, training quality and automation health.';
    v_kpis  := j_ai;
  else
    raise exception 'unknown report kind: % (supported: department, supplier, customer, ai)', p_kind;
  end if;

  v_body := public.fn_report_skeleton(v_title, v_exec, v_sections, '[]'::jsonb, null);
  insert into public.board_reports(week_start, title, body, kpis, report_type, created_at)
    values (current_date, v_title, v_body, v_kpis, p_kind, now())
    returning id into v_id;
  return v_id;
end $$;

revoke all on function public.fn_kv_block(jsonb) from anon, authenticated, public;
revoke all on function public.fn_report_generate(text) from anon, authenticated, public;

-- Reporting coverage & freshness (one row)
create or replace view public.report_kpis as
with reg as (select * from public.report_registry),
lt as (
  select
    max(created_at) filter (where report_type='weekly')     as weekly_at,
    max(created_at) filter (where report_type='monthly')    as monthly_at,
    max(created_at) filter (where report_type='quarterly')  as quarterly_at,
    max(created_at) filter (where report_type='department') as department_at,
    max(created_at) filter (where report_type='supplier')   as supplier_at,
    max(created_at) filter (where report_type='customer')   as customer_at,
    max(created_at) filter (where report_type='ai')         as ai_at,
    max(created_at) filter (where source='exec')            as exec_at,
    max(created_at) filter (where source='finance')         as finance_at
  from reg
),
daily as (select max(created_at) as daily_at from public.agent_actions where kind='exec_briefing')
select
  (select count(*) from reg)                                          as total_reports,
  (select count(*) from reg where created_at > now()-interval '30 days') as reports_30d,
  (select count(distinct report_type) from reg)                       as report_types,
  d.daily_at, lt.weekly_at, lt.monthly_at, lt.quarterly_at,
  lt.department_at, lt.supplier_at, lt.customer_at, lt.ai_at, lt.exec_at, lt.finance_at,
  (d.daily_at        > now()-interval '36 hours') as daily_fresh,
  (lt.weekly_at      > now()-interval '8 days')   as weekly_fresh,
  (lt.monthly_at     > date_trunc('month', now())) as monthly_fresh,
  (lt.quarterly_at   > now()-interval '95 days')  as quarterly_fresh,
  (lt.department_at  > now()-interval '2 days')   as department_fresh,
  (lt.supplier_at    > now()-interval '2 days')   as supplier_fresh,
  (lt.customer_at    > now()-interval '2 days')   as customer_fresh,
  (lt.ai_at          > now()-interval '2 days')   as ai_fresh,
  (
    (case when coalesce(d.daily_at        > now()-interval '36 hours',false) then 0 else 1 end)+
    (case when coalesce(lt.weekly_at      > now()-interval '8 days',false)   then 0 else 1 end)+
    (case when coalesce(lt.monthly_at     > date_trunc('month', now()),false) then 0 else 1 end)+
    (case when coalesce(lt.quarterly_at   > now()-interval '95 days',false)  then 0 else 1 end)+
    (case when coalesce(lt.department_at  > now()-interval '2 days',false)   then 0 else 1 end)+
    (case when coalesce(lt.supplier_at    > now()-interval '2 days',false)   then 0 else 1 end)+
    (case when coalesce(lt.customer_at    > now()-interval '2 days',false)   then 0 else 1 end)+
    (case when coalesce(lt.ai_at          > now()-interval '2 days',false)   then 0 else 1 end)
  ) as stale_count
from lt, daily d;

create table if not exists public.report_kpi_snapshots(
  id bigint generated always as identity primary key,
  snapshot_date date not null default current_date,
  kpis jsonb not null,
  created_at timestamptz not null default now());
alter table public.report_kpi_snapshots enable row level security;
