-- THE SEAT-DUTY JOBS ARE SPREAD OVER THE FIVE MINUTES, SO NO MINUTE TAKES THEM ALL (it_engineer, 11 Nov 2026).
-- Assigned: it_engineer - the seat-duty scheduler fn_seat_duty_isolate (one_slow_duty_never_wedges_the_seat_duty_tick.sql)
-- and the database's latency are its.
--
-- MEASURED 11 Nov 2026 (production, read-only, 09:43Z by the database clock):
--   * cron.job holds 105 jobs. 89 are seat_duty:<duty>, and every one of the 89 is on the same schedule, every five
--     minutes from minute 0, so all 89 start together at :x0 and :x5. Each opens its own connection
--     (cron.use_background_workers = off; max_connections 120; cron.max_running_jobs 32). In the hour to 09:43Z they ran
--     1 068 times (89 x 12), 127 ms each on average: nearly all are no-ops (the duty is not due), all at one instant.
--   * Edge calls 05:30-08:40Z, first 10 s after a five-minute mark: p50 1.1 s, p90 3.4 s, 18.5% over 3 s. The rest of
--     the five minutes: p50 0.63 s, p90 1.4 s, 3.8% over 3 s. Supplier registration took ~3-4.5 s on every server call
--     at exactly 06:10 and 08:10. The founder's "not laggy" bar (ruling 1620) fails on it.
--   * ONE routine makes these jobs: fn_seat_duty_isolate(text) (the only public routine that calls cron.schedule for a
--     seat duty; one overload). Its callers: fn_seat_duty_run, when a duty's moving average passes 1 s, and
--     fn_seat_duties_tick, for a duty never measured. It wrote the same minute for every duty.
--
-- CHANGE
--   1. fn_seat_duty_isolate gives each duty's job ONE minute of the five, schedule 'N-59/5 * * * *' with N in 0..4:
--      still every five minutes, twelve times an hour. N is the minute that holds the fewest seat_duty jobs; on a tie,
--      the fewest five-minute jobs of any owner (today site_uptime_5min at :x2, unfinished_signup_purge and
--      cs_held_question_route at :x0); then the lowest N. A duty whose job already has a minute keeps it, so calling it
--      again moves nothing. The duty row is only written when own_job was false, so re-isolating a duty never waits
--      on (or holds) the row lock fn_seat_duty_run takes with skip locked.
--      BOUND: with n active seat_duty jobs, no minute of the five holds more than ceil(n/5) of them - 18 of 89 today
--      (20%), where it was 89 of 89.
--   2. The jobs still on the shared minute are moved one at a time, in duty order, through the same function, so they
--      fill the five minutes evenly. cron.schedule with a name that exists UPDATES that row (pg_cron 1.6.4): the jobid,
--      the command and the count stay. This file refuses to finish if the number of seat_duty jobs changed.
--
-- NOT CHANGED: fn_seat_duty_run and its due test (now() - last_started_at >= every - 2 minutes). A job moved to a later
-- minute runs its duty when due; on the move a duty can run up to one five-minute step later, once. The shared tick
-- (resilience_ping -> fn_seat_duties_tick), and the 16 jobs that are not seat duties, are not touched.
-- REJECTED: one dispatcher job that runs every due duty. A duty has its own job BECAUSE it is slow (over 1 s, up to its
-- own 60 s statement_timeout); in one dispatcher a statement timeout rolls back every duty with it, which is the wedge
-- of 15-18 Oct this design was built to end. Spreading keeps each duty's own transaction and its own timeout.
--
-- CREATE OR REPLACE keeps the live ACL (postgres and service_role only, read 11 Nov); the revoke and grant are restated
-- as the duty-file check requires. search_path pinned.
-- Prevented by: scripts/checks/seat_duties_run_on_their_clock.test.mjs (static: the generator names no fixed minute;
-- production: no minute of the five holds more than ceil(n/5) seat_duty jobs, replaying this file while it is pending)
-- and the probe the_seat_duty_jobs_are_spread_over_the_five_minutes_probe.sql.
-- Apply at merge, away from a :x0/:x5 mark:
--   node scripts/apply_sql.mjs scripts/sql/the_seat_duty_jobs_are_spread_over_the_five_minutes.sql --apply --ddl

create or replace function public.fn_seat_duty_isolate(p_duty text)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare v_job text := 'seat_duty:' || p_duty; v_min integer;
begin
  if not exists (select 1 from public.seat_duty where duty = p_duty) then raise exception 'no seat duty %', p_duty; end if;
  update public.seat_duty set own_job = true where duty = p_duty and not own_job;
  -- A job that already has its minute keeps it.
  select substring(j.schedule from '^([0-4])-59/5 \* \* \* \*$')::integer into v_min
    from cron.job j where j.jobname = v_job;
  if v_min is null then
    -- The minute of the five holding the fewest seat_duty jobs, then the fewest five-minute jobs of any owner.
    -- A five-minute job's minute: the plain every-five-minutes shape is minute 0; 'N-59/5 * * * *' is minute N.
    select m.n into v_min
      from generate_series(0, 4) as m(n)
      left join lateral (
        select count(*) filter (where left(j.jobname, 10) = 'seat_duty:') as seat, count(*) as every_five
          from cron.job j
         where j.active and j.jobname <> v_job
           and case when j.schedule = '*/5 * * * *' then 0
                    else substring(j.schedule from '^([0-4])-59/5 \* \* \* \*$')::integer end = m.n) c on true
     order by c.seat, c.every_five, m.n
     limit 1;
  end if;
  return cron.schedule(v_job, v_min || '-59/5 * * * *',
    format($c$set statement_timeout = '60s'; select public.fn_seat_duty_run(%L);$c$, p_duty));
end $function$;
revoke execute on function public.fn_seat_duty_isolate(text) from public, anon, authenticated;
grant execute on function public.fn_seat_duty_isolate(text) to service_role;

-- Move every seat_duty job still on the shared minute, one at a time, in duty order. The count before is kept for the
-- rest of this transaction (set_config local), so the probe that runs after this file can compare it too.
do $spread$
declare v_before integer; v_after integer; v_duty text;
begin
  select count(*) into v_before from cron.job where left(jobname, 10) = 'seat_duty:';
  perform set_config('qd.seat_duty_jobs_before', v_before::text, true);
  for v_duty in
    select s.duty from public.seat_duty s join cron.job j on j.jobname = 'seat_duty:' || s.duty
     where s.own_job and j.schedule = '*/5 * * * *'
     order by s.duty
  loop
    perform public.fn_seat_duty_isolate(v_duty);
  end loop;
  select count(*) into v_after from cron.job where left(jobname, 10) = 'seat_duty:';
  if v_after <> v_before then
    raise exception 'seat_duty jobs: % before, % after - a job was added or dropped; nothing is applied', v_before, v_after;
  end if;
end $spread$;

-- Verdict row (this file defines a routine, so it never raises to report): the bound, every five minutes, none lost.
with j as (
  select jobname, schedule, substring(schedule from '^([0-4])-59/5 \* \* \* \*$')::integer as minute
    from cron.job where left(jobname, 10) = 'seat_duty:' and active),
per as (select m.n, count(j.jobname) as jobs from generate_series(0, 4) m(n) left join j on j.minute = m.n group by m.n)
select case
  when exists (select 1 from j where minute is null)
    then 'PROBE FAILED: seat_duty jobs not on one minute of the five: '
         || (select string_agg(jobname || ' ' || schedule, ', ') from j where minute is null)
  when (select max(jobs) from per) > ceil((select count(*) from j) / 5.0)
    then 'PROBE FAILED: a minute holds ' || (select max(jobs) from per) || ' of ' || (select count(*) from j)
         || ' seat_duty jobs, over ceil(n/5)'
  when exists (select 1 from public.seat_duty s where s.own_job
                and not exists (select 1 from cron.job c where c.jobname = 'seat_duty:' || s.duty))
    then 'PROBE FAILED: an own_job duty has no job'
  else 'PROBE OK seat_duty jobs per minute of five: '
       || (select string_agg(':x' || n || '=' || jobs, ' ' order by n) from per)
end as verdict;
