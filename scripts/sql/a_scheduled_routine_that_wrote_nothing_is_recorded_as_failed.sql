-- A SCHEDULED ROUTINE THAT WROTE NOTHING IS RECORDED AS FAILED (it_engineer, 12 Nov 2026).
-- Assigned: it_engineer (the scheduled work and its watch). Founder ledger 1642; final audit 12 Nov 2026, health F2 / F13
-- (fix O9).
--
-- MEASURED (production, read-only, 12 Nov 2026 01:50Z). The scheduled tasks that replaced the GitHub schedules report
-- SUCCEEDED when they did nothing: the daily task of 11 Nov 22:14Z ran 28 s with no repository checkout. (The runbook's
-- table, docs/runbooks/release-without-ci.md section 3, still names the 27 Oct times; the live ones are below.)
-- What each job last wrote:
--   weekly readings (Mondays 04:30): duty:dependency 2 Nov 04:32Z, duty:platform 2 Nov 04:32Z; the 9 Nov run wrote nothing
--     (findings duty:workflow_heartbeat:dependency / :platform open since 10 Nov 04:45Z, 325 sightings);
--   nightly journey (22:00): it_engineer job=journey 10 Nov 23:39Z; the 11 Nov run wrote nothing;
--   daily parity gate (05:41): security_advisor_baseline last_seen_at 11 Nov 08:49Z (a working session's gate, not the
--     routine); the 36 h parity heartbeat opens at 12 Nov 20:49Z if nothing refreshes it;
--   the multilingual embed backfill writes no row of its own; pack rows overdue a vector: 0 (resilience_ping drains them);
--   the CAD read worker: 0 open cad_read_jobs (2 ever); the Dropbox second scheduler and kb_embed are pg_cron, not
--     routines, and ran (backup_kick pg_cron_second_scheduler 12 Nov 00:41Z, duty:kb_embed 11 Nov 10:30Z).
-- The heartbeats (fn_it_workflow_heartbeats) see a missed weekly run only once 8 days have passed since the last good
-- one, and nothing records the run itself.
--
-- CHANGE: fn_claude_routine_outcomes(), pg_cron claude_routine_outcomes hourly at :47, records each judged job's latest
-- scheduled occurrence ONCE, after its grace, as an agent_runs row (agent it_engineer, job routine:<name>, due_at): status ok
-- when the job's own expected write is newer than the occurrence, status error otherwise (the failed-run path,
-- fn_emit_test_failed_*). A job whose latest occurrence failed is the IT engineer's finding duty:claude_routine:<name> until
-- an occurrence passes. Only jobs with an unconditional write are judged: the embed backfill and the CAD worker write only
-- when there is work, so their silence is not a failure.
-- THE SCHEDULE IS fn_claude_routine_schedule(), THE ONE PLACE, and it mirrors the live scheduled tasks (read 12 Nov 2026
-- 03:40Z with list_triggers): "QuotesDone daily jobs" CRON_TZ=Asia/Dubai 13 2 * * * = 22:13 UTC (project-parity, with the
-- advisor refresh) and "QuotesDone weekly jobs" CRON_TZ=Asia/Dubai 37 7 * * 1 = Mondays 03:37 UTC (it-weekly-readings, and
-- the demo journey, weekly since ledger 1595/1619 of 11 Nov). WHOEVER CHANGES ONE OF THOSE SCHEDULED TASKS UPDATES THAT
-- FUNCTION IN THE SAME CHANGE. Both tasks were repaired on 12 Nov (they now clone the repository first), so nothing before
-- their first repaired run (daily 12 Nov 22:13Z, weekly 16 Nov 03:37Z) is judged: judged_from.
-- Revoked from public, anon, authenticated; search_path pinned. No deploy.
-- Prevented by: the rolled-back probe a_scheduled_routine_that_wrote_nothing_is_recorded_as_failed_probe.sql.
--   node scripts/apply_sql.mjs scripts/sql/a_scheduled_routine_that_wrote_nothing_is_recorded_as_failed.sql --apply --ddl

create or replace function public.fn_claude_routine_schedule()
returns table (name text, scheduled_task text, period interval, anchor timestamptz, grace interval, judged_from timestamptz)
language sql immutable security definer set search_path to 'public', 'pg_temp' as $fn$
  -- Mirrors the live scheduled tasks; change it with them (see the file header).
  values
    ('daily_parity',    'QuotesDone daily jobs (CRON_TZ=Asia/Dubai 13 2 * * *)',  interval '1 day',
     timestamptz '2026-11-12 22:13:00+00', interval '3 hours', timestamptz '2026-11-12 22:13:00+00'),
    ('weekly_readings', 'QuotesDone weekly jobs (CRON_TZ=Asia/Dubai 37 7 * * 1)', interval '7 days',
     timestamptz '2026-11-16 03:37:00+00', interval '6 hours', timestamptz '2026-11-16 03:37:00+00'),
    ('weekly_journey',  'QuotesDone weekly jobs (CRON_TZ=Asia/Dubai 37 7 * * 1)', interval '7 days',
     timestamptz '2026-11-16 03:37:00+00', interval '6 hours', timestamptz '2026-11-16 03:37:00+00')
$fn$;

revoke execute on function public.fn_claude_routine_schedule() from public, anon, authenticated;

create or replace function public.fn_claude_routine_outcomes()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare x record; v_items jsonb := '[]'::jsonb; v_out jsonb := '[]'::jsonb; v_ok boolean;
begin
  for x in
    with o as (select r.*, r.anchor + r.period * floor(extract(epoch from (now() - r.grace - r.anchor)) / extract(epoch from r.period)) due
                 from public.fn_claude_routine_schedule() r)
    select o.name, o.scheduled_task, o.due,
           case o.name
             when 'weekly_readings' then
               (select max(started_at) from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duty:dependency') > o.due
               and (select max(started_at) from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duty:platform') > o.due
             when 'weekly_journey' then
               exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'journey' and started_at > o.due)
             when 'daily_parity' then
               (select max(last_seen_at) from public.security_advisor_baseline) > o.due
           end wrote
      from o
     where o.due >= o.judged_from          -- nothing before the repaired task's first run, and nothing before it is due
  loop
    v_ok := coalesce(x.wrote, false);
    if not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'routine:' || x.name
                     and counts->>'due_at' = x.due::text and started_at > now() - interval '8 days') then
      insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
      values ('it_engineer', case when v_ok then 'ok' else 'error' end, now(), now(),
              jsonb_build_object('job', 'routine:' || x.name, 'due_at', x.due::text, 'scheduled_task', x.scheduled_task),
              case when v_ok then null else 'the scheduled task ' || x.scheduled_task || ' due ' || to_char(x.due, 'DD Mon HH24:MI')
                                             || 'Z produced none of the ' || x.name || ' writes' end);
      v_out := v_out || jsonb_build_object('routine', x.name, 'due_at', x.due, 'ok', v_ok);
    end if;
    if not v_ok then
      v_items := v_items || jsonb_build_object('item', x.name, 'owner_seat', 'it_engineer', 'subject', 'claude_routine',
        'title', 'The ' || replace(x.name, '_', ' ') || ' job of ' || x.scheduled_task || ' due ' || to_char(x.due, 'DD Mon HH24:MI') || 'Z produced none of its expected writes',
        'blast', 'agent_facing', 'affected', 1,
        'evidence', jsonb_build_object('due_at', x.due, 'scheduled_task', x.scheduled_task,
          'look_at', 'the scheduled task''s last run: did it clone the repository and run this job'));
    end if;
  end loop;
  return jsonb_build_object('recorded', v_out, 'settle', public.fn_it_duty_settle('claude_routine', v_items));
end $fn$;

revoke execute on function public.fn_claude_routine_outcomes() from public, anon, authenticated;

select cron.schedule('claude_routine_outcomes', '47 * * * *', $CRON$set statement_timeout = '30s'; select public.fn_claude_routine_outcomes();$CRON$);

insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('claude_routine_outcomes', 'Claude routine outcomes', 'Health & monitoring',
   'Hourly at :47: fn_claude_routine_outcomes() records each scheduled task job''s latest occurrence (fn_claude_routine_schedule: '
   || 'daily parity 22:13 UTC, weekly readings and journey Mondays 03:37 UTC) as ok or error by whether its expected write arrived, and keeps the IT engineer''s '
   || 'finding open while the latest failed. it_engineer, 12 Nov 2026 (final audit F2).')
on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;

insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'claude_routine_outcomes', 'it_engineer',
   'Hourly at :47: records each Claude cloud routine occurrence ok/error by its expected write.',
   'scripts/sql/a_scheduled_routine_that_wrote_nothing_is_recorded_as_failed.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;

-- PROBE: read-only; returns its verdict as a row (the file holds DDL, so it must not raise).
with f as (select count(*) n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public' and p.prosecdef and p.proname in ('fn_claude_routine_outcomes', 'fn_claude_routine_schedule')
              and exists (select 1 from unnest(p.proconfig) cfg where cfg like 'search_path=%')
              and not has_function_privilege('anon', p.oid, 'execute')
              and not has_function_privilege('authenticated', p.oid, 'execute')),
     j as (select count(*) n from cron.job where jobname = 'claude_routine_outcomes' and active)
select case when (select n from f) = 2 and (select n from j) = 1 then 'PROBE OK'
            else 'PROBE FAILED: routine ' || (select n from f) || ', job ' || (select n from j) end as verdict;
