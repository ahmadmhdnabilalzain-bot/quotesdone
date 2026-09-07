-- THE KNOWLEDGE PAGE ANSWERS IN UNDER A SECOND (6 Sep 2026).
--
-- Walked in the founder's browser: the OS Knowledge page showed "Could not load knowledge:
-- canceling statement due to statement timeout". fn_ws_knowledge aggregated 2,686,026 kb_chunks
-- rows on every call (count, count by source_kind, distinct categories, group by category, and
-- v_kb_coverage's LEFT JOIN of 86 catalogue categories against the same table): 10.6 s measured,
-- against PostgREST's 8 s wall. The counts a dashboard shows do not need to be recomputed per
-- click. kb_category_stats holds one row per (category, source_kind) with its count, refreshed by
-- fn_kb_category_stats_refresh() under the kernel cron kb_category_stats_30min; v_kb_coverage and
-- fn_ws_knowledge read it. The page shows the same numbers with a freshness stamp
-- (kpis.stats_as_of) instead of a timeout.
--
--   node scripts/apply_sql.mjs scripts/sql/the_knowledge_page_answers_in_under_a_second.sql --apply --ddl
begin;

create table if not exists public.kb_category_stats (
  category    text not null,
  source_kind text not null,
  chunks      bigint not null,
  refreshed_at timestamptz not null default now(),
  primary key (category, source_kind)
);
alter table public.kb_category_stats enable row level security;
revoke all on public.kb_category_stats from public, anon, authenticated;

-- ROUTINE REMOVED 7 September 2026. public.fn_kb_category_stats_refresh was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

revoke all on function public.fn_kb_category_stats_refresh() from public, anon, authenticated;

select public.fn_kb_category_stats_refresh();

create or replace view public.v_kb_coverage as
 select c.slug as category,
        c.name as label,
        c.num,
        coalesce(sum(s.chunks), 0)::bigint as chunks,
        case when coalesce(sum(s.chunks), 0) = 0 then 'gap'
             when coalesce(sum(s.chunks), 0) < 3 then 'thin'
             else 'covered' end as status
   from public.catalog_supplier_categories c
   left join public.kb_category_stats s on regexp_replace(s.category, '^cat:', '') = c.slug
  group by c.slug, c.name, c.num;

CREATE OR REPLACE FUNCTION public.fn_ws_knowledge()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'chunks',(select coalesce(sum(chunks),0) from kb_category_stats),
      'document_chunks',(select coalesce(sum(chunks),0) from kb_category_stats where source_kind='document'),
      'categories',(select count(distinct category) from kb_category_stats),
      'category_specs',(select count(*) from catalog_supplier_categories),
      'stats_as_of',(select max(refreshed_at) from kb_category_stats)
    ),
    'curator', jsonb_build_object(
      'health', (select (kpis->>'health')::numeric from knowledge_kpi_snapshots order by snapshot_date desc limit 1),
      'coverage_pct', k.coverage_pct, 'knowledge_coverage_pct', k.knowledge_coverage_pct, 'playbook_coverage_pct', k.playbook_coverage_pct,
      'accuracy_pct', k.accuracy_pct, 'freshness_pct', k.freshness_pct, 'usage_reach_pct', k.usage_reach_pct,
      'regulations', k.regulations, 'regulations_pending', k.regulations_pending, 'standards', k.standards, 'manufacturers', k.manufacturers, 'brands', k.brands, 'materials', k.materials, 'playbooks', k.playbooks,
      'open_items', (select count(*) from agent_actions where agent='knowledge_curator' and status in ('pending','needs_review')),
      'tasks', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation))
          from agent_actions where agent='knowledge_curator' and status in ('pending','needs_review')),'[]'::jsonb)
    ),
    'reg_library', jsonb_build_object(
      'coverage', (select to_jsonb(rc) from reg_coverage rc),
      'indexed', coalesce((select jsonb_agg(jsonb_build_object('authority',authority,'code',code_name,'domain',domain) order by authority) from reg_catalog where status='indexed'),'[]'::jsonb),
      'missing', coalesce((select jsonb_agg(jsonb_build_object('authority',authority,'code',code_name,'domain',domain,'priority',priority,'status',status) order by priority, authority) from reg_catalog where copyright='free' and status<>'indexed'),'[]'::jsonb),
      'reference_only', coalesce((select jsonb_agg(jsonb_build_object('authority',authority,'code',code_name) order by authority) from reg_catalog where copyright='copyrighted'),'[]'::jsonb)
    ),
    'regulations', coalesce((select jsonb_agg(jsonb_build_object('title',title,'status',authority||coalesce(' · '||status,''),'source_url',source_url) order by coalesce(effective_date, created_at) desc)
        from (select * from regulations order by coalesce(effective_date, created_at) desc limit 20) rg),'[]'::jsonb),
    -- 6 SEP 2026: category counts come from kb_category_stats (refreshed every 30 min), not from a
    -- GROUP BY over 2.7M rows per click.
    'categories', coalesce((select jsonb_agg(jsonb_build_object('key',cat,'count',c) order by c desc) from (
        select coalesce(nullif(regexp_replace(category,'^cat:',''),''),'general') cat, sum(chunks) c from kb_category_stats group by 1 order by 2 desc limit 16) kk),'[]'::jsonb),
    'coverage', coalesce((select jsonb_agg(jsonb_build_object('category',v.category,'label',v.label,'chunks',v.chunks,'status',v.status) order by v.chunks asc, v.num)
        from v_kb_coverage v),'[]'::jsonb),
    'coverage_kpis', jsonb_build_object(
        'gaps',(select count(*) from v_kb_coverage where status='gap'),
        'thin',(select count(*) from v_kb_coverage where status='thin'),
        'covered',(select count(*) from v_kb_coverage where status='covered'),
        'total',(select count(*) from v_kb_coverage)
    ),
    -- WHICH KNOWLEDGE WAS ACTUALLY USED, and by whom. agent_brain writes a row here on every
    -- retrieval; until now nothing read them back, so "the knowledge is being used" was an
    -- assertion rather than something the founder could check.
    'used', coalesce((select jsonb_agg(jsonb_build_object(
        'agent', u.agent, 'query', left(coalesce(u.query,''), 90),
        'category', u.category, 'at', u.created_at) order by u.created_at desc)
      from (select * from kb_usage_log order by created_at desc limit 25) u),'[]'::jsonb),
    'used_kpis', jsonb_build_object(
      'lookups_7d', (select count(*) from kb_usage_log where created_at > now() - interval '7 days'),
      'agents_7d', (select count(distinct agent) from kb_usage_log where created_at > now() - interval '7 days'),
      'categories_7d', (select count(distinct category) from kb_usage_log
                         where created_at > now() - interval '7 days' and category is not null)
    ),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'category',category,'citation',citation)) from (select * from kb_chunks order by created_at desc limit 20) c),'[]'::jsonb)
  )
  from knowledge_kpis k;
$function$;

do $cron$
declare v_job bigint;
begin
  select jobid into v_job from cron.job where jobname = 'kb_category_stats_30min';
  if v_job is null then
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.
  end if;
  perform public.fn_kernel_wrap_and_enable_cron(v_job, 'it_operations_engineer', 'product_eng', 'routine_operational_decision');
  insert into public.cron_registry (jobname, human_name, category, purpose) values
    ('kb_category_stats_30min', 'Knowledge category counts', 'knowledge',
     'Every 30 min: recounts kb_chunks per (category, source_kind) into kb_category_stats so the OS Knowledge page and v_kb_coverage read a table instead of aggregating 2.7M rows per click.')
  on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
  insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine) values
    (v_job, 'kb_category_stats_30min',
     'INSERT/UPDATE/DELETE public.kb_category_stats only (a derived count table). Reads kb_chunks.',
     'Every 30 min in its own transaction. kb_category_stats is a derived table with no scenario rows; a scenario that inserts kb_chunks changes a count, which close() does not assert on.')
  on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;
end $cron$;

do $proof$
declare t0 timestamptz := clock_timestamp(); v_ms int; v_chunks bigint; v_job bigint;
begin
  select (public.fn_ws_knowledge()->'kpis'->>'chunks')::bigint into v_chunks;
  v_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  if v_ms > 4000 then raise exception 'fn_ws_knowledge still takes % ms', v_ms; end if;
  if v_chunks < 1000000 then raise exception 'kb_category_stats reports % chunks; expected millions', v_chunks; end if;
  select j.jobid into v_job from cron.job j where j.jobname = 'kb_category_stats_30min' and j.active and j.command ilike '%fn_kernel_cron_exec%';
  if v_job is null then raise exception 'kb_category_stats_30min is not active and wrapped'; end if;
  raise notice 'proof: fn_ws_knowledge % ms, % chunks from kb_category_stats, cron wrapped', v_ms, v_chunks;
end $proof$;

commit;
