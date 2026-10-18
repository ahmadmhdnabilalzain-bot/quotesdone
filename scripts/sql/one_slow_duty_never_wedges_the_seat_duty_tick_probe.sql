-- PROBE for one_slow_duty_never_wedges_the_seat_duty_tick.sql (it_engineer, 18 Oct 2026). Run after the file in
-- the same query: an aborted transaction, no DDL of its own, ends in raise exception CHK<<...>>, so nothing commits
-- (the cron.job rows the file schedules roll back with it). Against production as it is (84 duties overdue):
--   1. fn_ceo_improvement_sweep, cold, on today's backlog, returns inside 3.5 s (its own 2 s budget plus one step);
--   2. fn_seat_duties_tick(8) returns inside 5 s and ran at least one duty, whose last_ok_at moved;
--   3. no own_job duty ran inside the tick, and every own_job duty has its own active cron job seat_duty:<duty>;
--   4. the seat_duty:unmeasured lane is scheduled.
do $probe$
declare t timestamptz; v jsonb; v_ms int; v_sweep_ms int; v_fail text := ''; v_missing int;
begin
  t := clock_timestamp();
  perform public.fn_ceo_improvement_sweep();
  v_sweep_ms := round(extract(epoch from clock_timestamp() - t) * 1000);
  if v_sweep_ms >= 3500 then v_fail := v_fail || ' sweep took ' || v_sweep_ms || ' ms;'; end if;

  t := clock_timestamp();
  v := public.fn_seat_duties_tick(8);
  v_ms := round(extract(epoch from clock_timestamp() - t) * 1000);
  if v_ms >= 5000 then v_fail := v_fail || ' tick took ' || v_ms || ' ms;'; end if;
  if jsonb_array_length(coalesce(v->'ran', '[]')) = 0 then v_fail := v_fail || ' tick ran no duty;'; end if;
  if not exists (select 1 from public.seat_duty where last_ok_at = now()) then v_fail := v_fail || ' no last_ok_at moved;'; end if;
  if exists (select 1 from jsonb_array_elements(v->'ran') r join public.seat_duty s on s.duty = r->>'duty' where s.own_job)
    then v_fail := v_fail || ' an own_job duty ran in the tick;'; end if;

  select count(*) into v_missing from public.seat_duty s
   where s.own_job and not exists (select 1 from cron.job j where j.jobname = 'seat_duty:' || s.duty and j.active);
  if v_missing > 0 or not exists (select 1 from public.seat_duty where own_job) then v_fail := v_fail || ' own_job without its cron job (' || v_missing || ');'; end if;
  if not exists (select 1 from cron.job where jobname = 'seat_duty:unmeasured' and active) then v_fail := v_fail || ' no unmeasured lane;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK tick_ms=' || v_ms || ' ran=' || jsonb_array_length(v->'ran')
                                       || ' sweep_ms=' || v_sweep_ms || ' own_jobs=' || (select count(*) from public.seat_duty where own_job)
                                     else 'PROBE FAILED:' || v_fail end;
end $probe$;
