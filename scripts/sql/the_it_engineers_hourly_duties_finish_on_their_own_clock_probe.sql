-- PROBE (rolled back, never applied) for the_it_engineers_hourly_duties_finish_on_their_own_clock.sql (it_engineer, 12 Nov 2026).
--   node scripts/ci/rehearse_sql.mjs scripts/sql/the_it_engineers_hourly_duties_finish_on_their_own_clock.sql \
--        scripts/sql/the_it_engineers_hourly_duties_finish_on_their_own_clock_probe.sql
-- Drives the new routines inside the replay's transaction: a stale pending reading is recorded failed, the edge step is
-- told so, a fresh reading is run by the cron routine and marked ok, the duties row is written, and the hour is then not
-- due. fn_it_duties itself (unchanged by the file) is replaced INSIDE this transaction by a stand-in that writes its
-- duties row: the real one closes ~646 stale findings on its first run (~50 s, measured), past the management API's
-- gateway (a rehearsal was cut at 35 s on 12 Nov). Its own cost is what the cron job's 120 s is for.
set local statement_timeout = '60s';
create or replace function public.fn_it_duties(p_r jsonb) returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp' as $stand_in$
begin
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), now(), jsonb_build_object('job', 'duties', 'result', '{"probe_stand_in": {}}'::jsonb), null);
  return jsonb_build_object('probe_stand_in', jsonb_build_object('readings', p_r));
end $stand_in$;
do $p$
declare v_old bigint; v_new jsonb; v_unf jsonb; v_run jsonb; v_status text; v_old_status text; v_duties int; v_due boolean;
        v_again jsonb;
begin
  insert into public.agent_runs (agent, status, started_at, counts, note)
  values ('it_engineer', 'pending', now() - interval '20 minutes', jsonb_build_object('job', 'duties_readings', 'readings', '{}'::jsonb), 'ZZ DEMO probe')
  returning id into v_old;
  v_unf := public.fn_it_duties_unfinished();
  -- Production may already hold a newer real reading (the edge stores one an hour); then that one is the newest and
  -- this assertion is about it, so it is made only when the probe's row is the newest.
  if not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duties_readings'
                   and id <> v_old and started_at > now() - interval '20 minutes')
     and (v_unf is null or (v_unf->>'readings_run')::bigint <> v_old) then
    raise exception 'PROBE FAILED: a reading left pending for 20 minutes is not reported unfinished (%)', v_unf;
  end if;
  v_new := public.fn_it_duties_readings_store('{"taken_at": "probe"}'::jsonb);
  select status into v_old_status from public.agent_runs where id = v_old;
  if v_old_status <> 'error' or (v_new->>'unfinished_marked_failed')::int < 1 then
    raise exception 'PROBE FAILED: storing new readings did not record the unfinished one as failed (%, %)', v_old_status, v_new;
  end if;
  if public.fn_it_duties_due() then raise exception 'PROBE FAILED: due again straight after readings were stored'; end if;
  v_run := public.fn_it_duties_stored_run();
  select status into v_status from public.agent_runs where id = (v_new->>'stored')::bigint;
  select count(*) into v_duties from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duties' and started_at = now();
  if not coalesce((v_run->>'ran')::boolean, false) or v_status <> 'ok' or v_duties <> 1 then
    raise exception 'PROBE FAILED: the cron routine did not run the stored readings (ran %, status %, duties rows %)', v_run->>'ran', v_status, v_duties;
  end if;
  if public.fn_it_duties_unfinished() is not null then raise exception 'PROBE FAILED: still reported unfinished after a good run'; end if;
  v_again := public.fn_it_duties_stored_run();
  if coalesce((v_again->>'ran')::boolean, true) then raise exception 'PROBE FAILED: the same readings ran twice'; end if;
  raise exception 'PROBE OK: stale reading % recorded failed; reading % ran (% duties) and is ok; not run twice',
    v_old, v_new->>'stored', jsonb_array_length(coalesce((select jsonb_agg(k) from jsonb_object_keys(v_run->'duties') k), '[]'));
end $p$;
