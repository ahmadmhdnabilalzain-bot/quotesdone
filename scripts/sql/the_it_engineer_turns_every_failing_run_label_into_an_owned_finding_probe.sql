-- PROBE for the_it_engineer_turns_every_failing_run_label_into_an_owned_finding.sql (it_engineer, 27 Oct 2026). A pure
-- probe: it always raises CHK<<...>>, so every row it writes is rolled back. Fixture mode only, on a ZZ DEMO label.
--   a. six failing fixture runs of a label nobody owns open ONE finding that says no seat owns it;
--   b. ten ok runs later the label is no longer a cluster and its finding is closed with the reading;
--   c. no real (non-fixture) run-cluster finding was opened or closed by the fixture run.
do $probe$
declare
  v_r1 jsonb; v_r2 jsonb; f public.it_engineer_finding; v_fail text := ''; i int;
  v_real_open_before int := (select count(*) from public.it_engineer_finding where closed_at is null and issue_key like 'duty:run_cluster:%' and issue_key not like 'duty:run_cluster:fixture:%');
begin
  perform set_config('qd.duty_fixtures', 'on', true);
  for i in 1..6 loop
    insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
    values ('zz_demo_run_probe', now() - make_interval(hours => i), now() - make_interval(hours => i), 'error',
            '{"fixture": 1, "caller": "fixture"}'::jsonb, 'ZZ DEMO probe failure ' || i);
  end loop;
  v_r1 := public.fn_it_engineer_run_clusters();
  select * into f from public.it_engineer_finding where issue_key = 'duty:run_cluster:fixture:zz_demo_run_probe';
  if f.issue_key is null then v_fail := v_fail || ' a(no finding)';
  else
    if f.closed_at is not null then v_fail := v_fail || ' a(closed)'; end if;
    if not coalesce((f.evidence->>'unowned')::boolean, false) or f.title not like '%no seat owns this run label%' then v_fail := v_fail || ' a(unowned not named)'; end if;
    if f.affected <> 6 or (f.evidence->>'runs_7d')::int <> 6 or not coalesce((f.evidence->>'demo')::boolean, false) then v_fail := v_fail || ' a(evidence)'; end if;
  end if;

  for i in 1..10 loop
    insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
    values ('zz_demo_run_probe', now() - make_interval(mins => i), now() - make_interval(mins => i), 'ok',
            '{"fixture": 1, "caller": "fixture"}'::jsonb, null);
  end loop;
  v_r2 := public.fn_it_engineer_run_clusters();
  select * into f from public.it_engineer_finding where issue_key = 'duty:run_cluster:fixture:zz_demo_run_probe';
  if f.closed_at is null or f.close_note not like 'cleared: zz_demo_run_probe now has 6 non-ok of 16 runs%' then v_fail := v_fail || ' b(' || coalesce(f.close_note, 'open') || ')'; end if;

  if (select count(*) from public.it_engineer_finding where closed_at is null and issue_key like 'duty:run_cluster:%' and issue_key not like 'duty:run_cluster:fixture:%') <> v_real_open_before then
    v_fail := v_fail || ' c(real findings moved)';
  end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK run1=' || v_r1::text || ' run2=' || v_r2::text
                                    else 'PROBE FAILED:' || v_fail || ' run1=' || coalesce(v_r1::text, 'null') end;
end $probe$;
