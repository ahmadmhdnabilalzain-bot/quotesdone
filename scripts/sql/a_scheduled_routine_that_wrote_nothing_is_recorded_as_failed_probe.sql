-- PROBE (rolled back, never applied) for a_scheduled_routine_that_wrote_nothing_is_recorded_as_failed.sql (it_engineer,
-- 12 Nov 2026). A pure probe: it always raises, so the agent_runs rows, findings and the replaced schedule roll back.
--   node scripts/ci/rehearse_sql.mjs scripts/sql/a_scheduled_routine_that_wrote_nothing_is_recorded_as_failed.sql \
--        scripts/sql/a_scheduled_routine_that_wrote_nothing_is_recorded_as_failed_probe.sql
-- Proves: (1) with the live schedule, nothing before a repaired task's first run is judged; (2) with the schedule moved one
-- period back inside this transaction, each job gets exactly one row for its latest occurrence, error exactly when its
-- expected write is older than the occurrence (recomputed here from the same markers), a finding for each error, and a
-- second call records nothing more.
do $probe$
declare v0 jsonb; v1 jsonb; v2 jsonb; x jsonb; v_bad int := 0; v_err int := 0; v_due timestamptz; v_expect boolean;
begin
  v0 := public.fn_claude_routine_outcomes();
  if exists (select 1 from jsonb_array_elements(v0->'recorded') e, public.fn_claude_routine_schedule() r
              where r.name = e->>'routine' and (e->>'due_at')::timestamptz < r.judged_from) then
    raise exception 'PROBE FAILED: (1) an occurrence before the repaired task''s first run was judged: %', v0;
  end if;
  create or replace function public.fn_claude_routine_schedule()
  returns table (name text, scheduled_task text, period interval, anchor timestamptz, grace interval, judged_from timestamptz)
  language sql immutable security definer set search_path to 'public', 'pg_temp' as $s$
    values ('daily_parity', 'probe', interval '1 day', timestamptz '2026-11-02 22:13:00+00', interval '3 hours', timestamptz '2026-11-01 00:00:00+00'),
           ('weekly_readings', 'probe', interval '7 days', timestamptz '2026-11-02 03:37:00+00', interval '6 hours', timestamptz '2026-11-01 00:00:00+00'),
           ('weekly_journey', 'probe', interval '7 days', timestamptz '2026-11-02 03:37:00+00', interval '6 hours', timestamptz '2026-11-01 00:00:00+00')
  $s$;
  v1 := public.fn_claude_routine_outcomes();
  v2 := public.fn_claude_routine_outcomes();
  if jsonb_array_length(v1->'recorded') <> 3 then raise exception 'PROBE FAILED: (2) expected 3 occurrences: %', v1; end if;
  if jsonb_array_length(v2->'recorded') <> 0 then raise exception 'PROBE FAILED: (2) a second call recorded again: %', v2; end if;
  for x in select e from jsonb_array_elements(v1->'recorded') e loop
    v_due := (x->>'due_at')::timestamptz;
    v_expect := case x->>'routine'
      when 'weekly_readings' then (select max(started_at) from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duty:dependency') > v_due
                              and (select max(started_at) from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duty:platform') > v_due
      when 'weekly_journey' then exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'journey' and started_at > v_due)
      when 'daily_parity' then (select max(last_seen_at) from public.security_advisor_baseline) > v_due end;
    if coalesce(v_expect, false) <> (x->>'ok')::boolean then v_bad := v_bad + 1; end if;
    if not (x->>'ok')::boolean then
      v_err := v_err + 1;
      if not exists (select 1 from public.it_engineer_finding where issue_key = 'duty:claude_routine:' || (x->>'routine') and closed_at is null) then v_bad := v_bad + 1; end if;
    end if;
    if (select count(*) from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'routine:' || (x->>'routine')
          and counts->>'due_at' = v_due::text) <> 1 then v_bad := v_bad + 1; end if;
  end loop;
  if v_bad > 0 then raise exception 'PROBE FAILED: (2) % disagreement(s): %', v_bad, v1; end if;
  raise exception 'PROBE OK: live schedule judged % before the repaired runs; moved back: % recorded, % failed: %',
    jsonb_array_length(v0->'recorded'), jsonb_array_length(v1->'recorded'), v_err, v1->'recorded';
end
$probe$;
