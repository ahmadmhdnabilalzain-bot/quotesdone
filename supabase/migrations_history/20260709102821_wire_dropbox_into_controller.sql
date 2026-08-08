-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709102821   name: wire_dropbox_into_controller
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace view public.document_kpis as
select
  (select count(*) from document_inventory) as total_documents,
  (select coalesce(sum(bytes),0) from document_inventory) as total_bytes,
  (select count(distinct bucket) from document_inventory) as buckets,
  (select count(*) from document_inventory where past_retention) as past_retention,
  (select count(*) from document_inventory where bytes > 30*1024*1024) as oversized,
  (select count(*) from documents) as registered_docs,
  (select count(*) from documents where extracted is not null) as ocr_done,
  (select count(*) from documents where coalesce(status,'') not in ('done','skipped') or coalesce(error,'')<>'') as ocr_backlog,
  round(100.0*(select count(*) from documents where extracted is not null)/nullif((select count(*) from documents),0),1) as ocr_coverage_pct,
  (select count(*) from doc_versions) as version_records,
  (select max(created_at) from storage.objects where bucket_id='backups') as last_backup_at,
  (select (extract(epoch from (now()-max(created_at)))/86400)::int from storage.objects where bucket_id='backups') as days_since_backup,
  (select count(*) from legal_documents) as legal_documents,
  (select count(*) from dropbox_files where not is_folder) as dropbox_files,
  (select count(*) from dropbox_files where is_folder) as dropbox_folders,
  (select coalesce(sum(size),0) from dropbox_files) as dropbox_bytes,
  (select max(synced_at) from dropbox_files) as dropbox_last_sync;
revoke all on public.document_kpis from anon, authenticated;

-- keep Dropbox index fresh (read/index only, never deletes)
select cron.schedule('dropbox_sync_daily','40 2 * * *',
  $$select net.http_post(url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/dropbox_sync',
     headers:='{"Content-Type":"application/json"}'::jsonb,
     body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret')));$$);

create or replace function public.fn_ws_documents()
 returns jsonb language sql stable security definer set search_path to 'public','pg_catalog'
as $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'documents',(select count(*) from documents),
      'inventory_total',(select count(*) from document_inventory),
      'dropbox_files',(select count(*) from dropbox_files where not is_folder),
      'indexed',(select count(*) from documents where indexed is true),
      'reviews_pending',(select count(*) from doc_reviews where coalesce(status,'')='pending'),
      'versions',(select count(*) from doc_versions)
    ),
    'controller', jsonb_build_object(
      'health', (select (kpis->>'doc_health')::numeric from document_kpi_snapshots order by snapshot_date desc limit 1),
      'kpis', (select to_jsonb(k) from document_kpis k),
      'by_bucket', coalesce((select jsonb_agg(jsonb_build_object('bucket',bucket,'docs',c,'bytes',b,'past_retention',pr,'class',cls) order by c desc)
          from (select bucket, count(*) c, sum(bytes) b, count(*) filter (where past_retention) pr, max(retention_class) cls from document_inventory group by bucket) t),'[]'::jsonb),
      'dropbox', jsonb_build_object(
        'connected', (select (max(synced_at) is not null) from dropbox_files),
        'files', (select count(*) from dropbox_files where not is_folder),
        'folders', (select count(*) from dropbox_files where is_folder),
        'bytes', (select coalesce(sum(size),0) from dropbox_files),
        'last_sync', (select max(synced_at) from dropbox_files),
        'top_folders', coalesce((select jsonb_agg(jsonb_build_object('path',path,'items',n) order by n desc)
            from (select split_part(path,'/',2) path, count(*) n from dropbox_files where path like '/%/%' group by 1 order by 2 desc limit 8) t),'[]'::jsonb)
      ),
      'retention', coalesce((select jsonb_agg(jsonb_build_object('bucket',bucket,'class',class,'retention_days',retention_days) order by bucket) from retention_policy),'[]'::jsonb),
      'tasks', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation)) from agent_actions where agent='document_controller' and status in ('pending','needs_review')),'[]'::jsonb)
    ),
    'documents', coalesce((select jsonb_agg(jsonb_build_object('id',id,'file_name',file_name,'kind',kind,'ref_table',ref_table,'ref_id',ref_id,'status',status,'indexed',indexed,'created_at',created_at)) from (select * from documents order by created_at desc limit 40) d),'[]'::jsonb),
    'reviews', coalesce((select jsonb_agg(jsonb_build_object('id',id,'file_name',file_name,'ai_category',ai_category,'ai_summary',ai_summary,'ai_confidence',ai_confidence,'status',status,'created_at',created_at)) from (select * from doc_reviews order by created_at desc limit 20) r),'[]'::jsonb),
    'kinds', coalesce((select jsonb_agg(jsonb_build_object('key',k,'count',c) order by c desc) from (select coalesce(nullif(kind,''),'other') k, count(*) c from documents group by 1) kk),'[]'::jsonb)
  );
$function$;
revoke all on function public.fn_ws_documents() from anon, authenticated, public;
