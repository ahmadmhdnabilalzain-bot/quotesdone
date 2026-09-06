-- EVERY DOCUMENT ROW CAN BE OPENED (6 Sep 2026, OS walk after PR #524).
--
-- Founder, verbatim: "make sure everything is clickable". Measured in his browser: Documents listed the ten
-- documents in the inventory (file, kind, status, indexed, created) and not one row could be opened — the
-- payload carried no storage location, so the shell had nothing to sign. os_api already has the door
-- (`file` → a 300-second signed URL for a bucket/path); the list simply never handed it the key.
--
-- fn_ws_documents' `documents` entries now carry `bucket` and `path` (the documents table's own columns);
-- the shell opens the file in a new tab through os_api `file`. Nothing else in the payload changes.
--
-- Apply:  node scripts/apply_sql.mjs scripts/sql/every_document_row_can_be_opened.sql --apply
-- Prove:  select count(*) from jsonb_array_elements(fn_ws_documents()->'documents') d where d->>'path' is null -> 0

CREATE OR REPLACE FUNCTION public.fn_ws_documents()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'documents',(select count(*) from documents),
      'inventory_total',(select count(*) from document_inventory),
      'dropbox_files',(select count(*) from dropbox_files where not is_folder),
      'indexed',(select count(*) from documents where indexed is true),
      -- a review a department owns is not pending for the founder (6 Sep 2026)
      'reviews_pending',(select count(*) from doc_reviews where coalesce(status,'')='pending' and owner_role is null),
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
    -- bucket + path: what os_api `file` signs so the shell can open the row (6 Sep 2026)
    'documents', coalesce((select jsonb_agg(jsonb_build_object('id',id,'file_name',file_name,'kind',kind,'ref_table',ref_table,'ref_id',ref_id,'status',status,'indexed',indexed,'created_at',created_at,'bucket',bucket,'path',path)) from (select * from documents order by created_at desc limit 40) d),'[]'::jsonb),
    -- the section is titled "Reviews pending" and carries Approve/Reject: it lists pending, unowned rows only
    'reviews', coalesce((select jsonb_agg(jsonb_build_object('id',id,'file_name',file_name,'ai_category',ai_category,'ai_summary',ai_summary,'ai_confidence',ai_confidence,'status',status,'created_at',created_at)) from (select * from doc_reviews where coalesce(status,'')='pending' and owner_role is null order by created_at desc limit 20) r),'[]'::jsonb),
    'kinds', coalesce((select jsonb_agg(jsonb_build_object('key',k,'count',c) order by c desc) from (select coalesce(nullif(kind,''),'other') k, count(*) c from documents group by 1) kk),'[]'::jsonb)
  );
$function$;
