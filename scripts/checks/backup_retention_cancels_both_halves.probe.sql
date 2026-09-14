-- BACKUP RETENTION CANCELS BOTH HALVES: a day logged for deletion whose latest full copy then fails is
-- handed to NEITHER picker, and its Dropbox rows return to the status they had.
--
-- Assigned: it_engineer. 15 Sep 2026. Review of #672 (HIGH): the Dropbox picker never re-ran the rules,
-- and a cancelled day's doc_backups rows stayed claimable, so storage could keep a day Dropbox deleted.
--
-- A PURE PROBE: no DDL, and it ends in raise exception, so the whole transaction rolls back and nothing
-- it writes survives. It cannot reach a real file or a real person:
--   * the day is invented (2025-01-02, eight months before the first real export) and every row it
--     writes carries ZZ DEMO / zz_demo;
--   * nothing here calls Storage or Dropbox: the pickers only CLAIM rows, and the claim is rolled back;
--   * it counts real doc_backups rows in a retention state before and after, and asserts both are 0.
-- Run after the_backups_are_kept_ninety_days_and_friday_copies_a_year.sql is applied (or appended to it
-- in one aborted transaction, which is how it was run for #672):
--   node scripts/qsql.mjs scripts/checks/backup_retention_cancels_both_halves.probe.sql   -> CHK<<ok ...>>
do $probe$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_day date := date '2025-01-02';
  v_real_before int; v_real_after int; v_n int; v_log bigint;
begin
  select count(*) into v_real_before from public.doc_backups b
   where b.entity <> 'zz_demo' and b.status in ('prune_pending', 'pruning', 'pruned');

  -- a complete full copy yesterday (so the rules allow deletion), and the invented day to delete
  insert into public.table_export_run (stamp, kind, since, status, attempts, error)
  values (v_today - 1, 'full', null, 'done', 1, 'ZZ DEMO probe')
  on conflict (stamp) do update set kind = 'full', since = null, status = 'done', error = 'ZZ DEMO probe';
  insert into public.table_export_run (stamp, kind, since, status, attempts, error)
  values (v_day, 'incremental', timestamptz '2025-01-01 00:00+04', 'done', 1, 'ZZ DEMO probe');
  insert into public.doc_backups (entity, entity_id, doc_type, bucket, path, file_name, dropbox_path, source, dedupe_key, status)
  select 'zz_demo', 'ZZ DEMO probe', 'Database export', 'backups', '2025-01-02/zz_demo_probe/' || f, f,
         '/QuotesDone Backup/_selftest/ZZ DEMO/2025-01-02/' || f, 'storage', 'EXPORT:2025-01-02/zz_demo_probe/' || f, 'done'
    from unnest(array['page_0000.json', 'page_0001.json']) f;

  insert into public.app_secrets (key, value) values ('backup_prune_mode', 'delete')
  on conflict (key) do update set value = excluded.value;

  assert exists (select 1 from public.fn_backup_prune_plan(v_today) pd where pd.day = v_day and pd.decision = 'delete'),
    'setup: the invented day is not due for deletion';

  insert into public.backup_prune_log (decided_for, mode, day, origin, kind, day_status, reason)
  values (v_today, 'delete', v_day, 'export', 'incremental', 'done', 'ZZ DEMO probe: a daily copy older than 90 days')
  returning id into v_log;

  -- the tick moves the day's rows to the delete queue, keeping the status they had
  perform public.fn_backup_prune_tick();
  select count(*) into v_n from public.doc_backups b
   where b.dedupe_key like 'EXPORT:2025-01-02/%' and b.status = 'prune_pending' and b.status_before_prune = 'done';
  assert v_n = 2, format('the tick queued %s of 2 rows for deletion', v_n);

  -- while the rules still say delete, the Dropbox picker claims them (the claim is never acted on here)
  select count(*) into v_n from public.fn_doc_backups_prune_next(25, 'zz_demo_probe_1') c where c.entity = 'zz_demo';
  assert v_n = 2, format('the Dropbox picker claimed %s of 2 rows before the failure', v_n);

  -- THE LATEST FULL COPY FAILS
  insert into public.table_export_run (stamp, kind, since, status, attempts, error)
  values (v_today, 'full', null, 'failed', 6, 'ZZ DEMO probe')
  on conflict (stamp) do update set kind = 'full', since = null, status = 'failed', attempts = 6, error = 'ZZ DEMO probe';

  select count(*) into v_n from public.fn_doc_backups_prune_next(25, 'zz_demo_probe_2') c where c.dedupe_key like 'EXPORT:2025-01-02/%';
  assert v_n = 0, format('the Dropbox picker handed over %s row(s) of a day the rules now keep', v_n);
  assert (select bl.cancelled_at is not null and bl.storage_error like 'cancelled:%blocked%'
            from public.backup_prune_log bl where bl.id = v_log), 'the day''s log row was not cancelled with the reason';
  select count(*) into v_n from public.doc_backups b
   where b.dedupe_key like 'EXPORT:2025-01-02/%' and b.status = 'done'
     and b.status_before_prune is null and b.claimed_by is null and b.claimed_at is null;
  assert v_n = 2, format('%s of 2 rows are back to done, unclaimed', v_n);
  assert public.fn_backup_prune_storage_next()->>'log_id' is null, 'the storage picker handed over a cancelled day';

  select count(*) into v_real_after from public.doc_backups b
   where b.entity <> 'zz_demo' and b.status in ('prune_pending', 'pruning', 'pruned');
  assert v_real_before = 0 and v_real_after = 0,
    format('a real doc_backups row is in a retention state (before %s, after %s)', v_real_before, v_real_after);

  raise exception 'CHK<<ok: logged delete -> latest full failed -> Dropbox picker returned 0, log cancelled, 2 rows back to done, storage picker idle, real rows untouched>>';
end $probe$;
