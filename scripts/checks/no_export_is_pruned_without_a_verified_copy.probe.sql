-- PROBE (it_engineer, 15 Sep 2026): retention never deletes an export from storage that has no verified
-- Dropbox copy, and never deletes a Dropbox copy before storage is done. Also: the legacy-export enqueue
-- files a legacy page once, in the retention-recognised shape, and keeps at most 200 waiting.
--
-- A PURE PROBE: one transaction that ends in raise exception, so every fixture -- the delete-mode switch,
-- the storage objects, the doc_backups rows, the retention log row -- is rolled back. Nothing is deleted
-- (no storage API call is made; the routines only choose names), nothing reaches Dropbox, and nothing
-- reaches a person. The fixture day is 2000-01-03, a legacy day no real export has. Success is CHK<<ok.
--
--   node scripts/apply_sql.mjs scripts/checks/no_export_is_pruned_without_a_verified_copy.probe.sql --apply
do $probe$
declare
  v_day constant date := date '2000-01-03';
  p_ok  constant text := '2000-01-03/qdprobe_verified/page_0000.json';   -- done and verified: may go
  p_unv constant text := '2000-01-03/qdprobe_unverified/page_0000.json'; -- done, never verified: stays
  p_non constant text := '2000-01-03/qdprobe_unqueued/page_0000.json';   -- no backup row at all: stays
  p_new constant text := '2000-01-04/qdprobe_legacy/page_0000.json';     -- an unqueued legacy page for the enqueue
  v_log bigint; v_next jsonb; v_names text[]; v_done jsonb; v_claimed int; v_moved int; v_q int;
begin
  insert into public.app_secrets (key, value) values ('backup_prune_mode', 'delete')
    on conflict (key) do update set value = 'delete';
  insert into storage.objects (bucket_id, name, metadata) values
    ('backups', p_ok, '{"size": 1}'), ('backups', p_unv, '{"size": 1}'), ('backups', p_non, '{"size": 1}'),
    ('backups', p_new, '{"size": 1}');
  insert into public.doc_backups (entity, entity_id, doc_type, bucket, path, file_name, dropbox_path, source, dedupe_key,
                                  status, backed_up_at, verified_at)
  values ('company', 'table_export:2000-01-03', 'Database export', 'backups', p_ok, 'page_0000.json',
          '/QuotesDone Backup/Company/Database Exports/2000-01/' || p_ok, 'storage', 'EXPORT:' || p_ok, 'done', now(), now()),
         ('company', 'table_export:2000-01-03', 'Database export', 'backups', p_unv, 'page_0000.json',
          '/QuotesDone Backup/Company/Database Exports/2000-01/' || p_unv, 'storage', 'EXPORT:' || p_unv, 'done', now(), null);
  insert into public.backup_prune_log (decided_for, mode, day, origin, kind, day_status, reason)
  values (current_date, 'delete', v_day, 'legacy', 'full', 'incomplete', 'probe') returning id into v_log;

  -- 1. Dropbox first is refused: before storage is done, the tick queues nothing and nothing is claimable.
  perform public.fn_backup_prune_tick();
  select count(*) into v_moved from public.doc_backups where dedupe_key like 'EXPORT:2000-01-03/%' and status = 'prune_pending';
  select count(*) into v_claimed from public.fn_doc_backups_prune_next(25, 'probe:no_export_is_pruned');
  if v_moved <> 0 or v_claimed <> 0 then
    raise exception 'CHK<<fail: before storage finished, % Dropbox copy(ies) were queued and % claimed for deletion>>', v_moved, v_claimed;
  end if;

  -- 2. Storage hands over ONLY the verified page.
  v_next := public.fn_backup_prune_storage_next();
  if (v_next->>'log_id')::bigint is distinct from v_log then
    raise exception 'CHK<<fail: the probe day was not picked (%)>>', v_next;
  end if;
  select array_agg(x order by x) into v_names from jsonb_array_elements_text(v_next->'names') x;
  if v_names is distinct from array[p_ok] then
    raise exception 'CHK<<fail: storage would delete % (only % has a verified copy)>>', v_names, p_ok;
  end if;

  -- 3. With the unbacked pages still there, the day is NOT marked deleted, so Dropbox never starts.
  v_done := public.fn_backup_prune_storage_done(v_log, 1, null);
  if (select storage_deleted_at from public.backup_prune_log where id = v_log) is not null then
    raise exception 'CHK<<fail: the day was marked deleted with unbacked pages left (%)>>', v_done;
  end if;

  -- 4. The legacy enqueue files the unqueued legacy page once, in the shape retention recognises.
  -- 15 Sep 2026: LEGACY EXPORTS is fn_enqueue_doc_backups_backfill. 1000 leaves room above the 200 real
  -- legacy rows that may already wait (the fixture day sorts first, so it is inside the bound).
  perform public.fn_enqueue_doc_backups_backfill(1000);
  perform public.fn_enqueue_doc_backups_backfill(1000);
  select count(*) into v_q from public.doc_backups
   where bucket = 'backups' and path = p_new and dedupe_key = 'EXPORT:' || p_new and doc_type = 'Database export'
     and public.fn_backup_prune_dropbox_allowed(bucket, path, dedupe_key, doc_type, dropbox_path);
  if v_q <> 1 then raise exception 'CHK<<fail: the legacy page was queued % time(s) in the retention shape, expected 1>>', v_q; end if;
  if (select count(*) from public.doc_backups where dedupe_key like 'EXPORT:%' and entity_id like 'table_export:%'
        and status in ('pending', 'processing', 'error', 'waiting_source')
        and split_part(path, '/', 1) <= '2026-09-07') > 200 then
    raise exception 'CHK<<fail: more than 200 legacy export rows are waiting>>';
  end if;

  raise exception 'CHK<<ok: Dropbox-first refused (0 queued, 0 claimed); storage handed over only the verified page; day left open with % unbacked; legacy page queued once>>',
    (v_done->>'left');
end $probe$;
