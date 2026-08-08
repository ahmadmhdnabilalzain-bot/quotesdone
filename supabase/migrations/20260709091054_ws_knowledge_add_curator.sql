-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709091054   name: ws_knowledge_add_curator
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_ws_knowledge()
 returns jsonb language sql stable security definer set search_path to 'public','pg_catalog'
as $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'chunks',(select count(*) from kb_chunks),
      'categories',(select count(distinct category) from kb_chunks),
      'legal_docs',(select count(*) from legal_documents),
      'category_specs',(select count(*) from category_specs),
      'revisions_pending',(select count(*) from kb_revisions where coalesce(status,'')='pending')
    ),
    'curator', jsonb_build_object(
      'health', (select (kpis->>'health')::numeric from knowledge_kpi_snapshots order by snapshot_date desc limit 1),
      'coverage_pct', k.coverage_pct, 'knowledge_coverage_pct', k.knowledge_coverage_pct, 'playbook_coverage_pct', k.playbook_coverage_pct,
      'accuracy_pct', k.accuracy_pct, 'freshness_pct', k.freshness_pct, 'usage_reach_pct', k.usage_reach_pct, 'queries_30d', k.queries_30d,
      'regulations', k.regulations, 'regulations_pending', k.regulations_pending,
      'standards', k.standards, 'manufacturers', k.manufacturers, 'brands', k.brands, 'materials', k.materials, 'playbooks', k.playbooks,
      'open_items', (select count(*) from agent_actions where agent='knowledge_curator' and status in ('pending','needs_review')),
      'tasks', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation))
          from agent_actions where agent='knowledge_curator' and status in ('pending','needs_review')),'[]'::jsonb)
    ),
    'categories', coalesce((select jsonb_agg(jsonb_build_object('key',cat,'count',c) order by c desc) from (
        select coalesce(nullif(category,''),'general') cat, count(*) c from kb_chunks group by 1 order by 2 desc limit 16) kk),'[]'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'category',category,'citation',citation,'effective_date',effective_date,'created_at',created_at)) from (select * from kb_chunks order by created_at desc limit 20) c),'[]'::jsonb),
    'legal', coalesce((select jsonb_agg(jsonb_build_object('slug',slug,'title',title,'category',category,'version',version,'effective_date',effective_date,'updated_at',updated_at)) from (select * from legal_documents order by updated_at desc limit 20) l),'[]'::jsonb),
    'revisions', coalesce((select jsonb_agg(jsonb_build_object('id',id,'entry_kind',entry_kind,'version',version,'status',status,'author',author,'created_at',created_at)) from (select * from kb_revisions order by created_at desc limit 12) rv),'[]'::jsonb)
  )
  from knowledge_kpis k;
$function$;
revoke all on function public.fn_ws_knowledge() from anon, authenticated, public;
