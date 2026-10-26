-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709090644   name: knowledge_usage_and_kpis
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- usage tracking (agents can adopt fn_kb_search to record what knowledge they query)
create table if not exists public.kb_usage_log (
  id bigint generated always as identity primary key,
  query text, category text, agent text,
  created_at timestamptz not null default now()
);
create index if not exists kb_usage_log_created on public.kb_usage_log(created_at);
revoke all on public.kb_usage_log from anon, authenticated;

create or replace function public.fn_kb_search(p_query text, p_category text default null, p_agent text default null, p_limit int default 8)
returns table(source_kind text, category text, title text, snippet text, citation text, effective_date date, rank real)
language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  insert into kb_usage_log(query, category, agent) values (left(coalesce(p_query,''),300), p_category, p_agent);
  return query select * from kb_query(p_query, p_category, p_limit);
end $$;
revoke all on function public.fn_kb_search(text,text,text,int) from anon, authenticated, public;

-- consolidated knowledge KPIs: coverage / accuracy / freshness / usage
create or replace view public.knowledge_kpis as
with cats as (
  select slug from category_agents
  where active and slug not in ('chief_of_staff','supplier_success','customer_success','finance_ai','marketing_ai','knowledge_curator')
),
base as (
  select
    (select count(*) from cats) as categories_total,
    (select count(*) from cats c where exists(select 1 from category_specs s where s.category=c.slug)) as cat_with_spec,
    (select count(*) from cats c where exists(select 1 from qualification_playbooks p where p.category=c.slug)) as cat_with_playbook,
    (select count(*) from cats c where exists(select 1 from agent_knowledge k where k.agent_key=c.slug)) as cat_with_knowledge,
    (select count(*) from regulations) as regulations,
    (select count(*) from regulations where status='active' and approved_at is not null) as regulations_published,
    (select count(*) from regulations where approved_at is null) as regulations_pending,
    (select count(*) from mdm_standards) as standards,
    (select count(*) from mdm_manufacturers) as manufacturers,
    (select count(*) from mdm_brands) as brands,
    (select count(*) from materials) as materials,
    (select count(*) from qualification_playbooks) as playbooks,
    (select count(*) from category_specs) as category_specs,
    (select count(*) from kb_chunks) as chunks,
    (select count(*) from kb_revisions) as revisions,
    (select count(*) from kb_revisions where coalesce(ai_validation->>'result','pass') in ('fail','flag','warn') or status='rejected') as flagged_revisions,
    (select count(*) from compliance_sources where active) as compliance_active,
    (select count(*) from compliance_sources where active and last_checked_at>=now()-interval '45 days') as compliance_fresh,
    (select count(*) from category_specs where updated_at>=now()-interval '180 days') as specs_fresh,
    (select count(*) from regulations where updated_at>=now()-interval '365 days') as regs_fresh,
    (select count(*) from kb_usage_log where created_at>=now()-interval '30 days') as queries_30d,
    (select count(distinct category) from kb_usage_log where created_at>=now()-interval '30 days') as topics_queried_30d
)
select b.*,
  round(100.0*(cat_with_spec + cat_with_playbook + cat_with_knowledge)/nullif(3*categories_total,0),1) as coverage_pct,
  round(100.0*(revisions - flagged_revisions)/nullif(revisions,0),1) as accuracy_pct,
  round(100.0*(
     coalesce(compliance_fresh::numeric/nullif(compliance_active,0),1)
   + coalesce(specs_fresh::numeric/nullif(category_specs,0),1)
   + coalesce(regs_fresh::numeric/nullif(regulations,0),1))/3,1) as freshness_pct,
  round(100.0*cat_with_knowledge/nullif(categories_total,0),1) as usage_reach_pct
from base b;
revoke all on public.knowledge_kpis from anon, authenticated;

create table if not exists public.knowledge_kpi_snapshots (
  id bigint generated always as identity primary key,
  snapshot_date date not null default current_date,
  kpis jsonb not null,
  created_at timestamptz not null default now()
);
create unique index if not exists knowledge_kpi_snap_day on public.knowledge_kpi_snapshots(snapshot_date);
revoke all on public.knowledge_kpi_snapshots from anon, authenticated;
