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
-- Measured 22 Sep 2026: before the fix PROBE FAILED (21,411 ms / 26,730 ms); after, PROBE OK (2,899 ms / 109 ms).

create temp table zz_probe_verdict (verdict text, detail text) on commit drop;
do $probe$
declare
  t0 timestamptz; v_check_ms int; v_refile_ms int; v_out jsonb; v_h bigint; v_state text; v_err text;
  v_files jsonb;
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

  insert into zz_probe_verdict values (
    case when v_check_ms < 4000 and v_refile_ms < 1000 and coalesce(v_state, '') not like '%failed%'
         then 'PROBE OK' else 'PROBE FAILED' end,
    'fn_it_backup_check ' || v_check_ms || ' ms (budget 4000; findings ' || coalesce(v_out->>'findings', '?')
      || ', handoff ' || coalesce(v_out->>'handoff', 'none') || '); 10-file refile ' || v_refile_ms
      || ' ms (budget 1000); handoff states ' || coalesce(v_state, '-') || coalesce('; error ' || v_err, '')
      || ' (all rolled back)');
end
$probe$;
select verdict, detail from zz_probe_verdict;
