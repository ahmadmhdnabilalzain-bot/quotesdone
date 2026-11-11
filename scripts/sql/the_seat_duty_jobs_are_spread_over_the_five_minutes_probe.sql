-- PROBE for the_seat_duty_jobs_are_spread_over_the_five_minutes.sql (it_engineer, 11 Nov 2026). Assigned: it_engineer.
-- Run after the file, in the same rolled-back transaction:
--   node scripts/ci/rehearse_sql.mjs scripts/sql/the_seat_duty_jobs_are_spread_over_the_five_minutes.sql \
--        scripts/sql/the_seat_duty_jobs_are_spread_over_the_five_minutes_probe.sql
-- No DDL of its own; it always ends in raise exception CHK<<...>>, so nothing it or the file wrote commits (the cron.job
-- rows the file reschedules roll back with it). The only row it creates is one ZZ DEMO duty, inside this transaction.
-- It proves:
--   1. NONE LOST: the number of seat_duty jobs equals the number before the file (qd.seat_duty_jobs_before, set by the
--      file in this transaction), every own_job duty has exactly one job, and every job still belongs to a duty.
--   2. EVERY FIVE MINUTES: every seat_duty job is on 'N-59/5 * * * *' with N in 0..4 (twelve runs an hour, five minutes
--      apart), is active, and its command is still `set statement_timeout = '60s'; select fn_seat_duty_run(<duty>)`.
--   3. THE BOUND: no minute of the five holds more than ceil(n/5) of the n seat_duty jobs (18 of 89 on 11 Nov).
--   4. THE GENERATOR: a new duty isolated after the move lands on a minute that held the fewest seat_duty jobs, the
--      bound still holds with it, and isolating it again keeps its jobid and its minute. Its job's own call runs it.
do $probe$
declare
  v_fail text := ''; v_before integer; v_n integer; v_bound integer; v_max integer; v_per text;
  v_demo text := 'it_engineer.zz_demo_stagger_probe'; v_min integer; v_least integer; v_jobid bigint; v_jobid2 bigint;
  v_sched text; v_sched2 text;
begin
  v_before := nullif(current_setting('qd.seat_duty_jobs_before', true), '')::integer;
  if v_before is null then
    raise exception 'CHK<<PROBE FAILED: the file did not run first in this transaction (qd.seat_duty_jobs_before unset)>>';
  end if;

  -- 1. none lost
  select count(*) into v_n from cron.job where left(jobname, 10) = 'seat_duty:';
  if v_n <> v_before then v_fail := v_fail || format(' %s seat_duty jobs before, %s after;', v_before, v_n); end if;
  if exists (select 1 from public.seat_duty s where s.own_job
              and (select count(*) from cron.job j where j.jobname = 'seat_duty:' || s.duty) <> 1)
    then v_fail := v_fail || ' an own_job duty has no job or more than one;'; end if;
  if exists (select 1 from cron.job j where left(j.jobname, 10) = 'seat_duty:'
              and not exists (select 1 from public.seat_duty s where 'seat_duty:' || s.duty = j.jobname and s.own_job))
    then v_fail := v_fail || ' a seat_duty job has no own_job duty;'; end if;

  -- 2. every five minutes, the same command
  if exists (select 1 from cron.job j where left(j.jobname, 10) = 'seat_duty:'
              and (j.schedule !~ '^[0-4]-59/5 \* \* \* \*$' or not j.active))
    then v_fail := v_fail || ' not every five minutes: ' || (select string_agg(jobname || ' ' || schedule, ', ')
           from cron.job where left(jobname, 10) = 'seat_duty:' and (schedule !~ '^[0-4]-59/5 \* \* \* \*$' or not active)) || ';'; end if;
  if exists (select 1 from cron.job j where left(j.jobname, 10) = 'seat_duty:'
              and j.command <> format($c$set statement_timeout = '60s'; select public.fn_seat_duty_run(%L);$c$, substr(j.jobname, 11)))
    then v_fail := v_fail || ' a seat_duty job command changed;'; end if;

  -- 3. the bound
  v_bound := ceil(v_n / 5.0);
  select max(c), string_agg(':x' || n || '=' || c, ' ' order by n) into v_max, v_per
    from (select m.n, (select count(*) from cron.job j where left(j.jobname, 10) = 'seat_duty:' and j.active
                        and substring(j.schedule from '^([0-4])-59/5 ')::integer = m.n) c
            from generate_series(0, 4) m(n)) x;
  if v_max > v_bound then v_fail := v_fail || format(' a minute holds %s of %s, over ceil(n/5) = %s;', v_max, v_n, v_bound); end if;

  -- 4. the generator, on a ZZ DEMO duty that exists only in this transaction
  select min(c) into v_least
    from (select (select count(*) from cron.job j where left(j.jobname, 10) = 'seat_duty:' and j.active
                   and substring(j.schedule from '^([0-4])-59/5 ')::integer = m.n) c
            from generate_series(0, 4) m(n)) x;
  -- Unqualified on purpose: seat_duties_run_on_their_clock.test.mjs reads a schema-qualified insert into the duty
  -- register as a file that REGISTERS a duty and replays it alone. This is a rolled-back fixture, not a registration.
  set local search_path to 'public', 'pg_temp';
  insert into seat_duty (duty, owner_seat, every, routine, what, owner_file, avg_ms)
  values (v_demo, 'it_engineer', '1 day', 'fn_seat_duty_health', 'ZZ DEMO stagger probe - rolled back',
          'scripts/sql/the_seat_duty_jobs_are_spread_over_the_five_minutes_probe.sql', 10);
  v_jobid := public.fn_seat_duty_isolate(v_demo);
  select schedule, substring(schedule from '^([0-4])-59/5 ')::integer into v_sched, v_min from cron.job where jobid = v_jobid;
  if v_min is null then v_fail := v_fail || ' the new duty''s job is not on one minute of the five: ' || coalesce(v_sched, 'none') || ';';
  elsif (select count(*) from cron.job j where left(j.jobname, 10) = 'seat_duty:' and j.active and j.jobid <> v_jobid
          and substring(j.schedule from '^([0-4])-59/5 ')::integer = v_min) <> v_least
    then v_fail := v_fail || format(' the new duty went to :x%s, not a minute holding the fewest (%s);', v_min, v_least); end if;
  if (select max(c) from (select count(*) c from cron.job where left(jobname, 10) = 'seat_duty:' and active
                           group by substring(schedule from '^([0-4])-59/5 ')) x) > ceil((v_n + 1) / 5.0)
    then v_fail := v_fail || ' the bound broke with one more duty;'; end if;
  v_jobid2 := public.fn_seat_duty_isolate(v_demo);
  select schedule into v_sched2 from cron.job where jobid = v_jobid2;
  if v_jobid2 <> v_jobid or v_sched2 <> v_sched then
    v_fail := v_fail || format(' isolating again moved the job (%s %s -> %s %s);', v_jobid, v_sched, v_jobid2, v_sched2); end if;
  if not (select own_job from public.seat_duty where duty = v_demo) then v_fail := v_fail || ' the new duty is not own_job;'; end if;
  -- the job's own call runs the duty (its routine is the harmless health read)
  perform public.fn_seat_duty_run(v_demo);
  if (select last_started_at from public.seat_duty where duty = v_demo) is null then v_fail := v_fail || ' its job''s call did not run it;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = ''
    then format('PROBE OK seat_duty_jobs=%s (before %s) bound=ceil(n/5)=%s max=%s per_minute=[%s] new_duty=:x%s',
                v_n, v_before, v_bound, v_max, v_per, v_min)
    else 'PROBE FAILED:' || v_fail end;
end $probe$;
