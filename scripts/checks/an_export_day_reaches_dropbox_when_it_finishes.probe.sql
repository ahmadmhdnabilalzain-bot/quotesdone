-- AN EXPORT DAY REACHES DROPBOX WHEN IT FINISHES, AND A QUEUE THAT STOPS MOVING IS A FINDING.
-- Assigned: it_engineer. 15 Sep 2026. Proves scripts/sql/an_export_day_reaches_dropbox_when_it_finishes.sql:
--   1. a zz_demo row queued 5 hours ago raises the duty finding duty:dropbox_queue_zz_demo:stale_pending,
--      a row queued now does not count, and the finding closes itself once the old row is done;
--   2. the live fn_table_export_finish calls fn_backup_kick AFTER fn_enqueue_doc_backups (read from the
--      definition: finishing a real day needs a real manifest and every page in storage, which a probe
--      cannot invent without writing to the backups bucket);
--   3. fn_it_backup_tick runs the queue stage.
--
-- A PURE PROBE: no DDL, ends in raise exception, so the whole transaction rolls back. It cannot reach a
-- real file or a real person: every row it writes is zz_demo / ZZ DEMO, demo mode reads and settles only
-- the duty 'dropbox_queue_zz_demo', nothing here calls Storage, Dropbox or pg_net, and it asserts that the
-- real queue and the real 'dropbox_queue' findings are the same before and after.
-- Run after the migration is applied, or appended to it in one aborted transaction (how it was run for
-- the PR):  node scripts/qsql.mjs scripts/checks/an_export_day_reaches_dropbox_when_it_finishes.probe.sql
do $probe$
declare
  v_real_q_before int; v_real_q_after int; v_real_f_before int; v_real_f_after int;
  r jsonb; v_old bigint; v_def text; v_tick text;
begin
  select count(*) into v_real_q_before from public.doc_backups where entity <> 'zz_demo' and status in ('pending', 'error');
  select count(*) into v_real_f_before from public.it_engineer_finding where issue_key like 'duty:dropbox\_queue:%' and closed_at is null;

  insert into public.doc_backups (entity, entity_id, doc_type, bucket, path, file_name, dropbox_path, source, dedupe_key, status, created_at)
  values ('zz_demo', 'ZZ DEMO probe', 'Database export', 'backups', '2025-01-02/zz_demo_probe/page_0000.json', 'page_0000.json',
          '/QuotesDone Backup/Company/Database Exports/2025-01/2025-01-02/zz_demo_probe/page_0000.json', 'storage',
          'EXPORT:2025-01-02/zz_demo_probe/queue_old.json', 'pending', now() - interval '5 hours')
  returning id into v_old;
  insert into public.doc_backups (entity, entity_id, doc_type, bucket, path, file_name, dropbox_path, source, dedupe_key, status)
  values ('zz_demo', 'ZZ DEMO probe', 'Database export', 'backups', '2025-01-02/zz_demo_probe/page_0001.json', 'page_0001.json',
          '/QuotesDone Backup/Company/Database Exports/2025-01/2025-01-02/zz_demo_probe/page_0001.json', 'storage',
          'EXPORT:2025-01-02/zz_demo_probe/queue_new.json', 'pending');
  -- trg_doc_backups_admit (BEFORE INSERT) files a storage row whose object is not in Storage as
  -- 'waiting_source'; these invented files are not, so put both rows where a real queued file sits.
  update public.doc_backups set status = 'pending', error = null
   where entity = 'zz_demo' and dedupe_key in ('EXPORT:2025-01-02/zz_demo_probe/queue_old.json', 'EXPORT:2025-01-02/zz_demo_probe/queue_new.json');

  r := public.fn_dropbox_queue_stale(3, true);
  assert (r->>'stale')::int = 1, format('expected 1 stale zz_demo row, got %s', r);
  assert exists (select 1 from public.it_engineer_finding
                  where issue_key = 'duty:dropbox_queue_zz_demo:stale_pending' and closed_at is null),
    'a row queued 5 hours ago raised no open finding';

  update public.doc_backups set status = 'done' where id = v_old;
  r := public.fn_dropbox_queue_stale(3, true);
  assert (r->>'stale')::int = 0 and (r->>'closed')::int = 1, format('the finding did not close once the queue moved: %s', r);
  assert not exists (select 1 from public.it_engineer_finding
                      where issue_key = 'duty:dropbox_queue_zz_demo:stale_pending' and closed_at is null),
    'the finding is still open after the old row was done';

  v_def := pg_get_functiondef('public.fn_table_export_finish(date,jsonb,text)'::regprocedure);
  assert position('fn_backup_kick(' in v_def) > position('fn_enqueue_doc_backups()' in v_def)
         and position('fn_enqueue_doc_backups()' in v_def) > 0,
    'fn_table_export_finish does not kick dropbox_backup after it queues the day';
  v_tick := pg_get_functiondef('public.fn_it_backup_tick()'::regprocedure);
  assert position('fn_dropbox_queue_stale()' in v_tick) > 0, 'fn_it_backup_tick does not run the queue stage';

  select count(*) into v_real_q_after from public.doc_backups where entity <> 'zz_demo' and status in ('pending', 'error');
  select count(*) into v_real_f_after from public.it_engineer_finding where issue_key like 'duty:dropbox\_queue:%' and closed_at is null;
  assert v_real_f_before = v_real_f_after, format('a real dropbox_queue finding changed (%s -> %s)', v_real_f_before, v_real_f_after);

  raise exception 'CHK<<ok: stale zz_demo row raised duty:dropbox_queue_zz_demo:stale_pending and it closed once done; the fresh row did not count; finish kicks after it enqueues; the tick runs the queue stage; real open dropbox_queue findings % -> %; real queue % -> % (moves on its own)>>',
    v_real_f_before, v_real_f_after, v_real_q_before, v_real_q_after;
end $probe$;
