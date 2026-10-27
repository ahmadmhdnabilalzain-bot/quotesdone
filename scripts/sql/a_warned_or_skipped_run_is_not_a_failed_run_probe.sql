-- PROBE for a_warned_or_skipped_run_is_not_a_failed_run.sql (it_engineer, 27 Oct 2026). A pure probe: it always raises
-- CHK<<...>>, so every row it writes is rolled back. Fixture mode only (qd.duty_fixtures = on), on ZZ DEMO labels, so
-- only 'duty:run_cluster:fixture:' findings can move; the real ones are counted before and after.
--   a. a HEALTHY label - 4 ok, 4 warn, 2 skipped: six of ten not ok, none failed - opens NO finding;
--   b. a FAILING label - 6 error, 2 warn - opens one finding with failed_7d = 6;
--   c. a label whose 6 runs carry no status still opens one (a missing status fails closed);
--   d. no real (non-fixture) run-cluster finding was opened or closed.
-- RED on the live body (the old rule counts warn and skipped, so a. fails); GREEN when run after the file in one
-- rolled-back transaction. Neither run changes production: the raise rolls back the file and the rows together.
do $probe$
declare
  v_r jsonb; f public.it_engineer_finding; v_fail text := ''; i int;
  v_real_before text := (select coalesce(string_agg(issue_key || ':' || coalesce(closed_at::text, 'open'), ',' order by issue_key), '')
                           from public.it_engineer_finding where issue_key like 'duty:run_cluster:%' and issue_key not like 'duty:run_cluster:fixture:%');
begin
  perform set_config('qd.duty_fixtures', 'on', true);
  for i in 1..10 loop
    insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
    values ('zz_demo_run_healthy_probe', now() - make_interval(hours => i), now() - make_interval(hours => i),
            case when i <= 4 then 'ok' when i <= 8 then 'warn' else 'skipped' end,
            '{"fixture": 1, "caller": "fixture"}'::jsonb, 'ZZ DEMO probe run ' || i);
  end loop;
  for i in 1..8 loop
    insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
    values ('zz_demo_run_failing_probe', now() - make_interval(hours => i), now() - make_interval(hours => i),
            case when i <= 6 then 'error' else 'warn' end, '{"fixture": 1, "caller": "fixture"}'::jsonb, 'ZZ DEMO probe run ' || i);
  end loop;
  for i in 1..6 loop
    insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
    values ('zz_demo_run_nostatus_probe', now() - make_interval(hours => i), now() - make_interval(hours => i), null,
            '{"fixture": 1, "caller": "fixture"}'::jsonb, 'ZZ DEMO probe run ' || i);
  end loop;

  v_r := public.fn_it_engineer_run_clusters();

  if exists (select 1 from public.it_engineer_finding where issue_key = 'duty:run_cluster:fixture:zz_demo_run_healthy_probe' and closed_at is null) then
    v_fail := v_fail || ' a(4 ok + 4 warn + 2 skipped opened a finding)';
  end if;
  select * into f from public.it_engineer_finding where issue_key = 'duty:run_cluster:fixture:zz_demo_run_failing_probe';
  if f.issue_key is null or f.closed_at is not null then v_fail := v_fail || ' b(6 error of 8 opened no finding)';
  elsif coalesce((f.evidence->>'failed_7d')::int, -1) <> 6 or (f.evidence->>'runs_7d')::int <> 8 then v_fail := v_fail || ' b(evidence ' || f.evidence::text || ')';
  end if;
  if not exists (select 1 from public.it_engineer_finding where issue_key = 'duty:run_cluster:fixture:zz_demo_run_nostatus_probe' and closed_at is null) then
    v_fail := v_fail || ' c(runs with no status opened no finding)';
  end if;
  if (select coalesce(string_agg(issue_key || ':' || coalesce(closed_at::text, 'open'), ',' order by issue_key), '')
        from public.it_engineer_finding where issue_key like 'duty:run_cluster:%' and issue_key not like 'duty:run_cluster:fixture:%') <> v_real_before then
    v_fail := v_fail || ' d(real findings moved)';
  end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK ' || v_r::text else 'PROBE FAILED:' || v_fail || ' run=' || coalesce(v_r::text, 'null') end;
end $probe$;
