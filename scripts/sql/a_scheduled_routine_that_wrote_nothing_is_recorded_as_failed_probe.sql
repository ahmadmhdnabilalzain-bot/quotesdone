-- PROBE (rolled back, never applied) for a_scheduled_routine_that_wrote_nothing_is_recorded_as_failed.sql (it_engineer,
-- 12 Nov 2026). A pure probe: it always raises, so the agent_runs rows and findings it makes roll back.
--   node scripts/ci/rehearse_sql.mjs scripts/sql/a_scheduled_routine_that_wrote_nothing_is_recorded_as_failed.sql \
--        scripts/sql/a_scheduled_routine_that_wrote_nothing_is_recorded_as_failed_probe.sql
-- Proves on what production holds: each judged routine gets exactly one row for its latest occurrence, error exactly
-- when its expected write is older than the occurrence (recomputed here from the same markers), a finding for each error,
-- and a second call records nothing more.
do $probe$
declare v1 jsonb; v2 jsonb; x jsonb; v_bad int := 0; v_err int := 0;
begin
  v1 := public.fn_claude_routine_outcomes();
  v2 := public.fn_claude_routine_outcomes();
  if jsonb_array_length(v2->'recorded') <> 0 then raise exception 'PROBE FAILED: a second call recorded again: %', v2; end if;
  for x in select e from jsonb_array_elements(v1->'recorded') e loop
    if not (x->>'ok')::boolean then
      v_err := v_err + 1;
      if not exists (select 1 from public.it_engineer_finding where issue_key = 'duty:claude_routine:' || (x->>'routine') and closed_at is null) then
        v_bad := v_bad + 1;
      end if;
    end if;
    if (select count(*) from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'routine:' || (x->>'routine')
          and counts->>'due_at' = (x->>'due_at')::timestamptz::text) <> 1 then v_bad := v_bad + 1; end if;
  end loop;
  if v_bad > 0 then raise exception 'PROBE FAILED: % routine(s) without exactly one row or without a finding: %', v_bad, v1; end if;
  raise exception 'PROBE OK: % recorded, % failed: %', jsonb_array_length(v1->'recorded'), v_err, v1->'recorded';
end
$probe$;
