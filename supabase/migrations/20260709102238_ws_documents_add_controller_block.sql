-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709102238   name: ws_documents_add_controller_block
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_ws_documents()
 returns jsonb language sql stable security definer set search_path to 'public','pg_catalog'
as $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'documents',(select count(*) from documents),
      'inventory_total',(select count(*) from document_inventory),
      'indexed',(select count(*) from documents where indexed is true),
      'reviews_pending',(select count(*) from doc_reviews where coalesce(status,'')='pending'),
      'versions',(select count(*) from doc_versions)
    ),
    'controller', jsonb_build_object(
      'health', (select (kpis->>'doc_health')::numeric from document_kpi_snapshots order by snapshot_date desc limit 1),
      'kpis', (select to_jsonb(k) from document_kpis k),
      'by_bucket', coalesce((select jsonb_agg(jsonb_build_object('bucket',bucket,'docs',c,'bytes',b,'past_retention',pr,'class',cls) order by c desc)
          from (select bucket, count(*) c, sum(bytes) b, count(*) filter (where past_retention) pr, max(retention_class) cls from document_inventory group by bucket) t),'[]'::jsonb),
      'retention', coalesce((select jsonb_agg(jsonb_build_object('bucket',bucket,'class',class,'retention_days',retention_days) order by bucket) from retention_policy),'[]'::jsonb),
      'tasks', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation)) from agent_actions where agent='document_controller' and status in ('pending','needs_review')),'[]'::jsonb)
    ),
    'documents', coalesce((select jsonb_agg(jsonb_build_object('id',id,'file_name',file_name,'kind',kind,'ref_table',ref_table,'ref_id',ref_id,'status',status,'indexed',indexed,'created_at',created_at)) from (select * from documents order by created_at desc limit 40) d),'[]'::jsonb),
    'reviews', coalesce((select jsonb_agg(jsonb_build_object('id',id,'file_name',file_name,'ai_category',ai_category,'ai_summary',ai_summary,'ai_confidence',ai_confidence,'status',status,'created_at',created_at)) from (select * from doc_reviews order by created_at desc limit 20) r),'[]'::jsonb),
    'kinds', coalesce((select jsonb_agg(jsonb_build_object('key',k,'count',c) order by c desc) from (select coalesce(nullif(kind,''),'other') k, count(*) c from documents group by 1) kk),'[]'::jsonb)
  );
$function$;
revoke all on function public.fn_ws_documents() from anon, authenticated, public;
