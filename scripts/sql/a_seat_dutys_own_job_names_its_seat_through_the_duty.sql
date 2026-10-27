-- A SEAT DUTY'S OWN JOB NAMES ITS SEAT THROUGH THE DUTY (it_engineer, 27 Oct 2026).
-- Assigned: it_engineer - the ownership register public.writer_seat and its resolver are its
-- (every_run_label_and_cron_job_names_its_seat.sql). Founder rule, 7 Sep 2026: "no job/task should exist if it
-- doesnt belong to an agent".
--
-- MEASURED 27 Oct 2026 (26 Oct 23:0x UTC by the database clock), production: fn_writers_without_a_seat(7) returned 43
-- cron jobs, so scripts/checks/every_run_label_and_cron_job_names_its_seat.test.mjs is red:
--   * 42 named seat_duty:<duty> (seat_duty:accountant.fraud_watch, seat_duty:it_engineer.latency_closure, ...). They are
--     made at run time by fn_seat_duty_isolate, called from fn_seat_duty_run when a duty's moving avg_ms passes 1 s
--     (one_slow_duty_never_wedges_the_seat_duty_tick.sql, 18 Oct, commit 634a8952). Every one of the 42 matches a
--     public.seat_duty row by 'seat_duty:' || duty, and every such row's owner_seat is an active org_role (the
--     unmatched / inactive count was 0). The job DOES name its seat - through its duty - but the resolver only
--     looked a cron job up in writer_seat, and nothing writes a writer_seat row for a job made at run time.
--   * cs_held_question_route (*/5: fn_cs_held_question_route(); fn_ceo_support_handover_duty()), scheduled by
--     a_customer_support_question_reaches_a_person_in_fifteen_minutes.sql (#1479, 19 Oct), whose header names
--     customer_support as the seat (the router and the acknowledgement). It never registered in writer_seat.
--
-- CHANGE
--   1. fn_writers_without_a_seat: a cron job named 'seat_duty:' || d.duty is owned when that seat_duty row exists and
--      its owner_seat is an ACTIVE org_role - the same "active seat" bar writer_seat rows are held to. A job left
--      behind by a deleted duty, or by a seat that is no longer active, is still reported. Nothing else changes.
--   2. writer_seat: cs_held_question_route -> customer_support.
-- CREATE OR REPLACE keeps the live ACL (revoked from public, anon, authenticated in every_run_label_and_cron_job_names_its_seat.sql);
-- search_path stays pinned. Body otherwise the canonical file's.
-- prevented by: scripts/checks/every_run_label_and_cron_job_names_its_seat.test.mjs (red on production before this
-- file; replays it while pending).

create or replace function public.fn_writers_without_a_seat(p_days integer default 7)
returns table (kind text, name text, runs bigint)
language sql stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select 'agent_runs_label', l.agent, count(*)
    from public.agent_runs l
   where l.started_at > now() - make_interval(days => greatest(coalesce(p_days, 7), 1))
     and not exists (select 1 from public.function_owner f where f.function_slug = regexp_replace(l.agent, '^fn:', ''))
     and not exists (select 1 from public.seat_duty d where l.agent in (d.duty, d.routine))
     and not exists (select 1 from public.writer_seat o join public.org_role r on r.role_id = o.owner_seat and r.status = 'active'
                      where o.kind = 'agent_runs_label' and o.name = l.agent)
   group by l.agent
  union all
  select 'cron_job', j.jobname, null::bigint
    from cron.job j
   where not exists (select 1 from public.writer_seat o join public.org_role r on r.role_id = o.owner_seat and r.status = 'active'
                      where o.kind = 'cron_job' and o.name = j.jobname)
     -- a duty's own job (fn_seat_duty_isolate): owned by the duty's seat while that seat is active
     and not exists (select 1 from public.seat_duty d join public.org_role r on r.role_id = d.owner_seat and r.status = 'active'
                      where j.jobname = 'seat_duty:' || d.duty)
$fn$;

insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'cs_held_question_route', 'customer_support',
   'Every 5 min: fn_cs_held_question_route() routes customer_support held questions to a person within 15 minutes, then fn_ceo_support_handover_duty() answers the handovers it filed for the CEO seat.',
   'scripts/sql/a_customer_support_question_reaches_a_person_in_fifteen_minutes.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;

select case
  when exists (select 1 from public.fn_writers_without_a_seat(7))
    then 'PROBE FAILED: writers without a seat remain: '
         || (select string_agg(kind || ':' || name, ', ') from public.fn_writers_without_a_seat(7))
  else 'PROBE OK' end as verdict;
