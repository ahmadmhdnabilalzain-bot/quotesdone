-- PROBE for one_slow_duty_never_wedges_the_seat_duty_tick.sql (it_engineer, 18 Oct 2026). Run after the file in
-- the same query: an aborted transaction, no DDL of its own, ends in raise exception CHK<<...>>, so nothing commits
-- (the cron.job rows the file schedules roll back with it). Against production as it is (84 duties overdue):
--   1. fn_ceo_improvement_sweep, cold, on today's backlog, returns inside 3.5 s (its own 2 s budget plus one step);
--   2. fn_seat_duties_tick(8) returns inside 5 s and ran at least one duty, whose last_ok_at moved;
--   3. no own_job duty ran inside the tick, and every own_job duty has its own active cron job seat_duty:<duty>;
--   4. STARVATION: a shared duty whose average grows past 1 s (avg_ms forced to 2 900, its routine swapped for a fast harmless one inside this
--      transaction) is moved onto its own job by its next run, and that job's call runs it;
--   5. an unmeasured duty (avg_ms null) gets its own job from the tick.
do $probe$
declare t timestamptz; v jsonb; v_ms int; v_sweep_ms int; v_fail text := ''; v_missing int; v_duty text; v_ran int;
begin
  t := clock_timestamp();
  perform public.fn_ceo_improvement_sweep();
  v_sweep_ms := round(extract(epoch from clock_timestamp() - t) * 1000);
  if v_sweep_ms >= 3500 then v_fail := v_fail || ' sweep took ' || v_sweep_ms || ' ms;'; end if;

  t := clock_timestamp();
  v := public.fn_seat_duties_tick(8);
  v_ms := round(extract(epoch from clock_timestamp() - t) * 1000);
  if v_ms >= 5000 then v_fail := v_fail || ' tick took ' || v_ms || ' ms;'; end if;
  v_ran := jsonb_array_length(coalesce(v->'ran', '[]'));
  if v_ran = 0 then v_fail := v_fail || ' tick ran no duty;'; end if;
  if not exists (select 1 from public.seat_duty where last_ok_at = now()) then v_fail := v_fail || ' no last_ok_at moved;'; end if;
  if exists (select 1 from jsonb_array_elements(v->'ran') r join public.seat_duty s on s.duty = r->>'duty' where s.own_job)
    then v_fail := v_fail || ' an own_job duty ran in the tick;'; end if;

  select count(*) into v_missing from public.seat_duty s
   where s.own_job and not exists (select 1 from cron.job j where j.jobname = 'seat_duty:' || s.duty and j.active);
  if v_missing > 0 or not exists (select 1 from public.seat_duty where own_job) then v_fail := v_fail || ' own_job without its cron job (' || v_missing || ');'; end if;
  -- 4. a shared duty slows down: one run past 1 s on top of a 2.9 s average must isolate it, and its own job runs it.
  select duty into v_duty from public.seat_duty where enabled and not own_job and avg_ms is not null order by duty limit 1;
  update public.seat_duty set avg_ms = 2900, last_started_at = null where duty = v_duty;
  update public.seat_duty set routine = 'fn_seat_duty_health' where duty = v_duty;   -- a real, harmless routine
  v := public.fn_seat_duties_tick(8);                -- skipped here: 2 900 * 1.5 cannot fit
  if exists (select 1 from jsonb_array_elements(v->'ran') r where r->>'duty' = v_duty) then v_fail := v_fail || ' tick ran a 2.9 s duty;'; end if;
  update public.seat_duty set avg_ms = 1500 where duty = v_duty;   -- what one slow run leaves behind
  perform public.fn_seat_duty_run(v_duty);           -- the run that measured it (from its next eligible caller)
  if not (select own_job from public.seat_duty where duty = v_duty)
     or not exists (select 1 from cron.job where jobname = 'seat_duty:' || v_duty and active)
    then v_fail := v_fail || format(' slowed duty %s not isolated;', v_duty); end if;
  update public.seat_duty set last_started_at = null where duty = v_duty;
  -- the job's command is two statements (set statement_timeout; select ...), so run its select as pg_cron would
  if (select command from cron.job where jobname = 'seat_duty:' || v_duty) not like '%fn_seat_duty_run(' || quote_literal(v_duty) || ')%'
    then v_fail := v_fail || ' its job does not call fn_seat_duty_run;'; end if;
  perform public.fn_seat_duty_run(v_duty);
  if (select last_started_at from public.seat_duty where duty = v_duty) is null then v_fail := v_fail || ' its own job did not run it;'; end if;
  -- 5. an unmeasured duty is isolated by the tick
  update public.seat_duty set avg_ms = null where duty = (select duty from public.seat_duty where enabled and not own_job order by duty limit 1 offset 1)
   returning duty into v_duty;
  perform public.fn_seat_duties_tick(8);
  if not coalesce((select own_job from public.seat_duty where duty = v_duty), false) then v_fail := v_fail || format(' unmeasured %s not isolated;', v_duty); end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK tick_ms=' || v_ms || ' ran=' || v_ran
                                       || ' sweep_ms=' || v_sweep_ms || ' own_jobs=' || (select count(*) from public.seat_duty where own_job)
                                     else 'PROBE FAILED:' || v_fail end;
end $probe$;
