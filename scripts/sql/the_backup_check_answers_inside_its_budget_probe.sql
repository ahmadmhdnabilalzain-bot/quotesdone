-- PROBE: THE IT ENGINEER'S DROPBOX CHECK ANSWERS INSIDE ITS BUDGET, REFILE INCLUDED.
--
-- Assigned: it_engineer. 22 Sep 2026. Pure probe: no DDL, nothing survives it.
--
-- WHY: fn_it_backup_check is called by dropbox_backup through PostgREST, which cancels at 8 s. On
-- 20-22 Sep it took 24.6-29.0 s because the refile it hands to the sales engineer (synchronously,
-- inside the same statement) recomputed the whole expected set once per never-queued file. See
-- the_backup_refile_looks_up_its_own_file_instead_of_recomputing_every_expected_file.sql.
--
-- WHAT IT RUNS, each inside a block that always raises so everything is rolled back:
--   1. fn_it_backup_check('[]', 'dropbox_daily_check') exactly as the reconcile calls it, on today's
--      real data (whatever never_queued / upload_failed files exist today are refiled, then undone).
--   2. a 'backup.refile' handoff carrying TEN never-queued files, the shape that killed the check, so
--      the probe stays realistic on a day when production happens to have none. The files are
--      ZZ DEMO: owner zz_demo:probe, bucket zz-demo-probe -- no uploader, no person, no Dropbox.
-- VERDICT: PROBE OK only if (1) answers under 4 s (half of PostgREST's 8 s), (2) answers under 1 s,
-- and the handoff in (2) did not end 'failed' (fn_seat_handoff swallows a handler error onto the row).
--
-- Run the whole file as ONE query through the Management API query endpoint; it is never applied.
-- Measured 22 Sep 2026: before the fixes PROBE FAILED (21,411 ms / 26,730 ms, 7 never_queued pages that
-- never existed); after both, PROBE OK (2,741 ms / 133 ms; 0 never_queued, 0 expected-not-written,
-- 0 written-not-expected; expected table-export items 8,981 -> 8,974, every other kind 1,623 -> 1,623).
-- 3. (added 22 Sep, the_backup_expects_only_the_pages_each_days_export_wrote.sql) for every finished,
--    unpruned export day, the expected table-export files equal the files in that day's folder, and
--    15..21 Sep have 0 never_queued.

create temp table zz_probe_verdict (verdict text, detail text) on commit drop;
do $probe$
declare
  t0 timestamptz; v_check_ms int; v_refile_ms int; v_out jsonb; v_h bigint; v_state text; v_err text;
  v_files jsonb; v_nq bigint; v_ghost bigint; v_dropped bigint;
begin
  -- 1. the check itself, real data
  begin
    t0 := clock_timestamp();
    v_out := public.fn_it_backup_check('[]'::jsonb, 'dropbox_daily_check', null);
    v_check_ms := (extract(epoch from clock_timestamp() - t0) * 1000)::int;
    select status, detail->>'error' into v_state, v_err from public.agent_actions where id = (v_out->>'handoff')::bigint;
    raise exception 'zz_probe_rollback';
  exception when others then
    if sqlerrm <> 'zz_probe_rollback' then
      insert into zz_probe_verdict values ('PROBE FAILED', 'fn_it_backup_check raised ' || sqlstate || ' ' || sqlerrm);
      return;
    end if;
  end;

  -- 2. ten never-queued ZZ DEMO files through the refile handoff
  select jsonb_agg(jsonb_build_object('key', 'exp:obj:zz-demo-probe:' || g, 'reason', 'never_queued',
           'item_key', 'obj:zz-demo-probe:zz-demo/probe/' || g || '.json', 'kind', 'storage', 'bucket', 'zz-demo-probe',
           'path', 'zz-demo/probe/' || g || '.json', 'owner', 'zz_demo:probe', 'demo', true))
    into v_files from generate_series(1, 10) g;
  begin
    t0 := clock_timestamp();
    v_h := public.fn_seat_handoff('it_engineer', 'sales_engineer', 'backup.refile', 'doc_backups',
             'zz_probe:' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS'),
             jsonb_build_object('files', v_files, 'job', 'zz_probe', 'refile_attempts', 0));
    v_refile_ms := (extract(epoch from clock_timestamp() - t0) * 1000)::int;
    select coalesce(v_state, '') || '|' || status, coalesce(v_err, detail->>'error') into v_state, v_err
      from public.agent_actions where id = v_h;
    raise exception 'zz_probe_rollback';
  exception when others then
    if sqlerrm <> 'zz_probe_rollback' then
      insert into zz_probe_verdict values ('PROBE FAILED', 'the refile handoff raised ' || sqlstate || ' ' || sqlerrm);
      return;
    end if;
  end;

  -- 3. the table-export expectation is what each finished day WROTE, no more and no less (22 Sep 2026:
  --    7 pages of a table added to the list later were expected on 15..21 Sep and never existed)
  create temp table zz_probe_exp (path text, item_key text, doc_backup_id bigint) on commit drop;
  insert into zz_probe_exp select s.path, s.item_key, s.doc_backup_id from public.fn_it_backup_expected_status() s
   where s.owner like 'company:table_export:%';
  select count(*) filter (where x.doc_backup_id is null and x.path ~ '^2026-09-(1[5-9]|2[01])/'),
         count(*) filter (where not exists (select 1 from storage.objects o where o.bucket_id = 'backups' and o.name = x.path)
                            and exists (select 1 from public.table_export_run r where r.status = 'done' and r.pruned_at is null
                                          and x.path like to_char(r.stamp, 'YYYY-MM-DD') || '/%')),
         (select count(*) from storage.objects o join public.table_export_run r
                   on r.status = 'done' and r.pruned_at is null and o.name like to_char(r.stamp, 'YYYY-MM-DD') || '/%'
           where o.bucket_id = 'backups' and not exists (select 1 from zz_probe_exp y where y.path = o.name))
    into v_nq, v_ghost, v_dropped from zz_probe_exp x;

  insert into zz_probe_verdict values (
    case when v_check_ms < 4000 and v_refile_ms < 1000 and coalesce(v_state, '') not like '%failed%'
          and v_nq = 0 and v_ghost = 0 and v_dropped = 0
         then 'PROBE OK' else 'PROBE FAILED' end,
    'fn_it_backup_check ' || v_check_ms || ' ms (budget 4000; findings ' || coalesce(v_out->>'findings', '?')
      || ', handoff ' || coalesce(v_out->>'handoff', 'none') || '); 10-file refile ' || v_refile_ms
      || ' ms (budget 1000); handoff states ' || coalesce(v_state, '-') || coalesce('; error ' || v_err, '')
      || '; table exports: never_queued 15-21 Sep ' || v_nq || ', expected but never written ' || v_ghost
      || ', written but not expected ' || v_dropped || ' (all 0 to pass; all rolled back)');
end
$probe$;
select verdict, detail from zz_probe_verdict;
