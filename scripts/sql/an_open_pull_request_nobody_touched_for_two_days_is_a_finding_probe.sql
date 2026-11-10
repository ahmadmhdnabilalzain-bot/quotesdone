-- PROBE for an_open_pull_request_nobody_touched_for_two_days_is_a_finding.sql (it_engineer, 10 Nov 2026).
-- NEVER APPLIED: it ends in raise exception, so the whole request rolls back - the ZZ DEMO findings and the duty run
-- rows included. Send it through scripts/lib/safe_replay.mjs (scripts/ci/rehearse_sql.mjs <file> <this file>) after the main
-- file while that file is pending. The verdict is in the exception text: 'PROBE OK :: ...' or 'PROBE FAILED :: ...'.
-- Pull requests 900001-900003 do not exist on GitHub, and nothing here sends to a person: findings and agent_runs only.
--
-- Asserts: one finding per stale pull request, each naming number, title, age and the SQL flag (true, false, unknown);
-- a reading GitHub could not give settles nothing and records no run; a pull request that left the reading closes its
-- finding by itself; the founder's list names only those open more than 7 days, once, by number, with the SQL count; no
-- finding outside this duty is touched.
do $probe$
declare
  v_rows jsonb; r1 jsonb; r2 jsonb; r3 jsonb; v_other_before text; v_other_after text; v_runs_before int; v_runs_mid int;
  v_open_after_1 int; v_open_after_3 int; v_line text; v_sql_true boolean; v_sql_false boolean; v_sql_null boolean; v_title text;
begin
  select md5(coalesce(string_agg(issue_key || coalesce(closed_at::text, ''), ',' order by issue_key), '')) into v_other_before
    from public.it_engineer_finding where issue_key not like 'duty:open\_pull\_requests:%';
  select count(*) into v_runs_before from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duty:open_pull_requests';

  v_rows := jsonb_build_array(
    jsonb_build_object('number', 900001, 'title', 'ZZ DEMO it_engineer: SQL waiting', 'url', 'https://example.invalid/900001', 'author', 'zz-demo',
      'draft', false, 'created_at', (now() - interval '10 days')::text, 'updated_at', (now() - interval '9 days')::text,
      'age_hours', 240, 'idle_hours', 216, 'touches_sql', true, 'sql_files', jsonb_build_array('scripts/sql/zz_demo.sql')),
    jsonb_build_object('number', 900002, 'title', 'ZZ DEMO no SQL, three days old', 'url', 'https://example.invalid/900002', 'author', 'zz-demo',
      'draft', true, 'created_at', (now() - interval '3 days')::text, 'updated_at', (now() - interval '3 days')::text,
      'age_hours', 72, 'idle_hours', 72, 'touches_sql', false, 'sql_files', '[]'::jsonb),
    jsonb_build_object('number', 900003, 'title', 'ZZ DEMO files unreadable', 'url', 'https://example.invalid/900003', 'author', 'zz-demo',
      'draft', false, 'created_at', (now() - interval '8 days')::text, 'updated_at', (now() - interval '4 days')::text,
      'age_hours', 192, 'idle_hours', 96, 'touches_sql', null, 'sql_files', '[]'::jsonb));

  r1 := public.fn_it_open_pull_requests_record(jsonb_build_object('basis', 'measured', 'taken_at', now(), 'open_count', 3, 'stale', v_rows));
  select count(*) into v_open_after_1 from public.it_engineer_finding where issue_key like 'duty:open\_pull\_requests:pr:9000%' and closed_at is null;
  select title, (evidence->>'touches_sql')::boolean is true into v_title, v_sql_true from public.it_engineer_finding where issue_key = 'duty:open_pull_requests:pr:900001';
  select (evidence->>'touches_sql') = 'false' into v_sql_false from public.it_engineer_finding where issue_key = 'duty:open_pull_requests:pr:900002';
  select (evidence->'touches_sql') = 'null'::jsonb into v_sql_null from public.it_engineer_finding where issue_key = 'duty:open_pull_requests:pr:900003';

  -- the founder's list: 900001 (10 days) and 900003 (8 days) are past 7 days; 900002 (3 days) is not
  select x->>'line' into v_line from jsonb_array_elements(public.fn_it_session_fix_list()) x where x->>'line' like '%pull request(s)%' limit 1;

  -- GitHub could not be read: nothing settles, nothing closes, no run is recorded
  r2 := public.fn_it_open_pull_requests_record(jsonb_build_object('basis', 'unavailable', 'reason', 'GitHub answered 502'));
  select count(*) into v_runs_mid from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duty:open_pull_requests';

  -- 900001 and 900003 are merged or closed (gone from the reading); 900002 stays
  r3 := public.fn_it_open_pull_requests_record(jsonb_build_object('basis', 'measured', 'taken_at', now(), 'open_count', 1,
          'stale', jsonb_build_array(v_rows->1)));
  select count(*) into v_open_after_3 from public.it_engineer_finding where issue_key like 'duty:open\_pull\_requests:pr:9000%' and closed_at is null;

  select md5(coalesce(string_agg(issue_key || coalesce(closed_at::text, ''), ',' order by issue_key), '')) into v_other_after
    from public.it_engineer_finding where issue_key not like 'duty:open\_pull\_requests:%';

  if (r1->>'stale')::int = 3 and v_open_after_1 = 3
     and v_title like 'Pull request #900001 "ZZ DEMO%' and v_title like '%SQL is waiting to be applied%' and v_title like '%9 days%' and v_title like '%open 10 days%'
     and v_sql_true and v_sql_false and v_sql_null
     and v_line like '2 pull request(s) have been open for more than 7 days without a merge: #900001, #900003 (1 carry SQL that was never applied)'
     and r2->>'recorded' = 'false' and v_runs_mid = v_runs_before + 1
     and (r3->>'closed')::int = 2 and v_open_after_3 = 1
     and exists (select 1 from public.it_engineer_finding where issue_key = 'duty:open_pull_requests:pr:900002' and closed_at is null)
     and not exists (select 1 from public.fn_it_session_fix_list() x where x->>'line' like '%#900002%')
     and v_other_before = v_other_after
  then
    raise exception 'PROBE OK :: one finding per stale pull request with its number, title, age and SQL flag; an unreadable reading settled nothing; a pull request that left the reading closed its finding; the founder list named only those open over 7 days, by number';
  end if;
  raise exception 'PROBE FAILED :: %', jsonb_build_object('r1', r1, 'r2', r2, 'r3', r3, 'open_after_1', v_open_after_1, 'open_after_3', v_open_after_3,
    'title', v_title, 'sql', jsonb_build_array(v_sql_true, v_sql_false, v_sql_null), 'line', v_line, 'runs', jsonb_build_array(v_runs_before, v_runs_mid),
    'others_unchanged', v_other_before = v_other_after)::text;
end $probe$;
