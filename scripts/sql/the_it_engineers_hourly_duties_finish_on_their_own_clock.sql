-- THE IT ENGINEER'S HOURLY DUTIES FINISH ON THEIR OWN CLOCK (it_engineer, 12 Nov 2026).
-- Assigned: it_engineer (fn_it_duties and its schedule are the seat's). Founder ledger 1642, "Proceed with fixes";
-- final audit 12 Nov 2026, health F1 (fix id O1).
--
-- MEASURED (production, read-only, 12 Nov 2026 00:30-01:30Z; timings rehearsed inside rolled-back transactions):
--   * agent_runs it_engineer job=duties: 19-24 completed runs a day from 2 to 10 Nov, the last at 11 Nov 00:45:27Z,
--     none since. Finding duty:heartbeat:itduties "canceling statement due to statement timeout", 62 times to 22:46Z.
--   * The edge tick (resilience_ping -> ticks/it_engineer/duties.ts) calls fn_it_duties over PostgREST, so the call has
--     the API role's 8 s statement timeout. pg_stat_statements: 192 calls, mean 3 273 ms, max 7 916 ms.
--   * WHAT MADE IT SLOW ON 11 NOV: no duty was added. Section 4 (delivery) settles ONE finding per delivery.request
--     handoff older than 2 h with no loop verdict, and each finding upsert/close costs ~75 ms (5 closes: 377 ms, the
--     case-memory and judgement triggers on it_engineer_finding run per row). The 10-11 Nov supplier seed batch put
--     ~650 handoffs into that window: 646 duty:delivery:request findings were open at the 00:45 run (287 new that
--     hour). 646 x 75 ms = ~48 s, plus fn_pack_rows_without_fresh_ml_vector 0.8-2.1 s and the security sweep 0.3 s:
--     the call cannot fit 8 s, and a call that times out rolls back, writes no agent_runs row, so fn_it_duties_due stays
--     true and the readings are taken and thrown away on every 15-minute tick (62 times).
--   * NOW: the delivery query returns 0 items (every one of those handoffs reads done), so the first run that is allowed
--     to finish closes the 646 by the duty's own rule ("the delivery duty no longer finds it") in ~50 s.
--
-- CHANGE
--   1. The edge tick no longer decides. It takes the readings (only the edge can: HTTP to GitHub, Vercel, Stripe, the
--      sites) and stores them with fn_it_duties_readings_store as an agent_runs row (agent it_engineer,
--      job duties_readings, status pending). agent_runs is already the record of this run (the cron log), so no table
--      is added.
--   2. A pg_cron job, it_engineer_duties, runs fn_it_duties_stored_run() every five minutes at :x3 with
--      statement_timeout 120 s: the newest pending readings stored in the last 6 minutes are handed to fn_it_duties,
--      unchanged, and the readings row is marked ok. 120 s, because the backlog run measured above needs ~50 s and the
--      seat duties' 60 s would leave it 10 s; an ordinary hour measured 3.3 s mean. Minute :x3 holds 18 seat-duty jobs
--      and nothing else (read 12 Nov 01:10Z); :x4 now also carries the supplier re-read; :x0 and :x5 the */5 and */10 jobs. The 6-minute window gives one
--      reading at most two attempts, never the 62 of 11 Nov.
--   3. A reading nothing finished is a FAILED run, not a quiet one: the next store (and the job itself) marks a pending
--      readings row older than 6 minutes status error with the reason, which is what the estate's failed-run watch
--      reads (fn_emit_test_failed_*), and fn_it_duties_unfinished() names it so the edge step fails on every tick until
--      a later reading finishes - the heartbeat finding duty:heartbeat:itduties stays open, it does not flicker.
--   4. fn_it_duties_due also counts a stored reading, so readings are taken once an hour whether or not they finished.
-- NOT CHANGED: fn_it_duties itself, fn_it_duty_settle, fn_it_expiry_measured (the edge still sends the expiries).
-- CREATE OR REPLACE keeps fn_it_duties_due's ACL (postgres, service_role: read 12 Nov); the new routines are revoked
-- from public, anon, authenticated and granted to service_role (the edge's role). search_path pinned on all four.
-- Deploy resilience_ping AFTER this file: the new tick calls fn_it_duties_readings_store, which must exist first.
-- An old tick running meanwhile still calls fn_it_duties directly and keeps failing as before; nothing breaks.
-- Prevented by: supabase/functions/resilience_ping/ticks/it_engineer/duties.test.ts (the tick stores, never decides) and
-- the behaviour probe the_it_engineers_hourly_duties_finish_on_their_own_clock_probe.sql (rolled back).
--   node scripts/apply_sql.mjs scripts/sql/the_it_engineers_hourly_duties_finish_on_their_own_clock.sql --apply --ddl

-- ── 1. STORE THE READINGS (the edge tick, hourly) ────────────────────────────────────────────────────────────────
create or replace function public.fn_it_duties_readings_store(p_r jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint; v_failed int;
begin
  if jsonb_typeof(p_r) is distinct from 'object' then
    raise exception 'fn_it_duties_readings_store takes the readings object from _shared/it_duty_readings.ts';
  end if;
  update public.agent_runs
     set status = 'error', finished_at = now(),
         note = 'the hourly duties never finished on these readings (cron it_engineer_duties); see cron.job_run_details'
   where agent = 'it_engineer' and counts->>'job' = 'duties_readings' and status = 'pending'
     and started_at > now() - interval '7 days' and started_at < now() - interval '6 minutes';
  get diagnostics v_failed = row_count;
  insert into public.agent_runs (agent, status, started_at, counts, note)
  values ('it_engineer', 'pending', now(), jsonb_build_object('job', 'duties_readings', 'readings', p_r),
          'readings for fn_it_duties; the cron job it_engineer_duties runs them')
  returning id into v_id;
  return jsonb_build_object('stored', v_id, 'unfinished_marked_failed', v_failed);
end $fn$;

revoke execute on function public.fn_it_duties_readings_store(jsonb) from public, anon, authenticated;
grant execute on function public.fn_it_duties_readings_store(jsonb) to service_role;

-- ── 2. RUN THEM (pg_cron, every five minutes at :x3, 120 s) ──────────────────────────────────────────────────────
create or replace function public.fn_it_duties_stored_run()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_row public.agent_runs; v_out jsonb; v_failed int;
begin
  -- Committed only when this run commits; when it times out the next run (five minutes later) records it.
  update public.agent_runs
     set status = 'error', finished_at = now(),
         note = 'the hourly duties never finished on these readings (cron it_engineer_duties); see cron.job_run_details'
   where agent = 'it_engineer' and counts->>'job' = 'duties_readings' and status = 'pending'
     and started_at > now() - interval '7 days' and started_at < now() - interval '6 minutes';
  get diagnostics v_failed = row_count;
  select * into v_row from public.agent_runs
   where agent = 'it_engineer' and counts->>'job' = 'duties_readings' and status = 'pending'
     and started_at >= now() - interval '6 minutes'
   order by started_at desc limit 1
   for update skip locked;
  if not found then return jsonb_build_object('ran', false, 'unfinished_marked_failed', v_failed); end if;
  v_out := public.fn_it_duties(v_row.counts->'readings');
  -- The readings are not kept once they were decided on: fn_it_duties' own row carries the result.
  update public.agent_runs set status = 'ok', finished_at = now(),
         counts = jsonb_build_object('job', 'duties_readings', 'taken_at', v_row.counts->'readings'->'taken_at',
                                     'duties', (select count(*) from jsonb_object_keys(coalesce(v_out, '{}'::jsonb)))),
         note = null
   where id = v_row.id;
  return jsonb_build_object('ran', true, 'readings_run', v_row.id, 'duties', v_out, 'unfinished_marked_failed', v_failed);
end $fn$;

revoke execute on function public.fn_it_duties_stored_run() from public, anon, authenticated;

-- ── 3. WHAT THE EDGE STEP REPORTS EVERY TICK ─────────────────────────────────────────────────────────────────────
-- The newest stored reading, when no run finished on it within its 6 minutes: the step fails until a later one does.
create or replace function public.fn_it_duties_unfinished()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select case when r.status is distinct from 'ok' and r.started_at < now() - interval '6 minutes'
              then jsonb_build_object('readings_run', r.id, 'taken_at', r.started_at, 'status', r.status) end
    from (select id, status, started_at from public.agent_runs
           where agent = 'it_engineer' and counts->>'job' = 'duties_readings' and started_at > now() - interval '7 days'
           order by started_at desc limit 1) r
$fn$;

revoke execute on function public.fn_it_duties_unfinished() from public, anon, authenticated;
grant execute on function public.fn_it_duties_unfinished() to service_role;

-- ── 4. DUE ONCE AN HOUR, FINISHED OR NOT ─────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_duties_due()
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select not exists (select 1 from public.agent_runs where agent = 'it_engineer'
                        and counts->>'job' in ('duties', 'duties_readings')
                        and started_at > now() - interval '55 minutes')
$fn$;

revoke execute on function public.fn_it_duties_due() from public, anon, authenticated;
grant execute on function public.fn_it_duties_due() to service_role;

comment on function public.fn_it_duties_stored_run() is
  'Every 5 minutes at :x3 (cron it_engineer_duties, 120 s): runs fn_it_duties on the newest readings the edge tick stored in the last 6 minutes (fn_it_duties_readings_store) and marks them ok; marks older unfinished readings error. it_engineer, 12 Nov 2026.';

-- ── 5. THE SCHEDULE AND ITS REGISTRY ROWS ────────────────────────────────────────────────────────────────────────
select cron.schedule('it_engineer_duties', '3-59/5 * * * *', $CRON$set statement_timeout = '120s'; select public.fn_it_duties_stored_run();$CRON$);

insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('it_engineer_duties', 'IT engineer hourly duties', 'Health & monitoring',
   'fn_it_duties_stored_run() every 5 minutes at :03, :08, ...: decides the IT engineer''s hourly duties (live = code, '
   || 'expiries, deliveries, handoffs, pack vectors, payments, security, uptime, demo hygiene) on the readings the '
   || 'resilience_ping tick stored, with 120 s to finish. Moved off the 8 s API call on 12 Nov 2026 (final audit F1).')
on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;

insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'it_engineer_duties', 'it_engineer',
   'fn_it_duties_stored_run() every 5 min at :x3, 120 s: the IT engineer''s hourly duties on the readings resilience_ping stored.',
   'scripts/sql/the_it_engineers_hourly_duties_finish_on_their_own_clock.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;

-- PROBE: read-only; returns its verdict as a row (the file holds DDL, so it must not raise).
with f as (select count(*) n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public' and p.prosecdef
              and p.proname in ('fn_it_duties_readings_store', 'fn_it_duties_stored_run', 'fn_it_duties_unfinished', 'fn_it_duties_due')
              and exists (select 1 from unnest(p.proconfig) cfg where cfg like 'search_path=%')
              and not has_function_privilege('anon', p.oid, 'execute')
              and not has_function_privilege('authenticated', p.oid, 'execute')),
     j as (select count(*) n from cron.job where jobname = 'it_engineer_duties' and active and schedule = '3-59/5 * * * *'
              and command like '%statement_timeout = ''120s''%fn_it_duties_stored_run()%')
select case when (select n from f) = 4 and (select n from j) = 1 then 'PROBE OK'
            else 'PROBE FAILED: routines ' || (select n from f) || ' of 4 closed and pinned, job ' || (select n from j) || ' of 1' end as verdict;
