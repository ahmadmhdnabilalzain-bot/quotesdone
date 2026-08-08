-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709093208   name: ws_knowledge_add_reg_coverage
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_ws_knowledge()
 returns jsonb language sql stable security definer set search_path to 'public','pg_catalog'
as $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'chunks',(select count(*) from kb_chunks),
      'document_chunks',(select count(*) from kb_chunks where source_kind='document'),
      'categories',(select count(distinct category) from kb_chunks),
      'category_specs',(select count(*) from category_specs)
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
    'categories', coalesce((select jsonb_agg(jsonb_build_object('key',cat,'count',c) order by c desc) from (
        select coalesce(nullif(category,''),'general') cat, count(*) c from kb_chunks group by 1 order by 2 desc limit 16) kk),'[]'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'category',category,'citation',citation)) from (select * from kb_chunks order by created_at desc limit 20) c),'[]'::jsonb)
  )
  from knowledge_kpis k;
$function$;
revoke all on function public.fn_ws_knowledge() from anon, authenticated, public;
