-- THE MOST OVERDUE SEAT DUTY RUNS FIRST, AND THE TICK USES ITS TIME. Seat: it_engineer, 29 Sep 2026.
--
-- MEASURED 29 Sep 2026 (00:0x UTC): sales_engineer.disputes, a 30-minute duty, went 91 minutes without a
-- run and every_alarm_is_quiet_on_a_healthy_day went red on it. fn_seat_duties_tick ran at most 8 due
-- duties per 15-minute tick (resilience_ping passes p_limit 8), ordered by last_started_at: a backlog
-- larger than 8 left short-interval duties waiting behind long-interval ones that were merely older.
--
-- THE CHANGE (body otherwise identical to a_duty_routine_whose_arguments_all_have_defaults_is_found.sql):
--   * order by how overdue each duty is - its due instant, last_started_at + every - earliest first;
--   * p_limit is now a floor, not the cap: the tick keeps starting due duties, up to 30, while less than
--     4 seconds have passed. resilience_ping calls it through PostgREST under the authenticator's 8 s
--     statement_timeout (the_knowledge_exam_is_scored_in_slices_that_fit_the_duty_tick.sql), so the budget
--     leaves room for the duty in flight and the health pass. A duty is never started past the budget.
create or replace function public.fn_seat_duties_tick(p_limit integer default 8)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare d public.seat_duty; v_res jsonb; v_out jsonb := '[]'::jsonb; v_health jsonb; p jsonb;
        v_t0 timestamptz := clock_timestamp(); v_n int := 0;
begin
  for d in
    select * from public.seat_duty
     where enabled
       -- two minutes of tolerance, the same reasoning as fn_resilience_tick_plan: a tick is never exactly on the beat
       and (last_started_at is null or now() - last_started_at >= every - interval '2 minutes')
     order by last_started_at + every nulls first, duty   -- the most overdue first
     limit greatest(30, least(coalesce(p_limit, 8), 60))
     for update skip locked
  loop
    -- the time budget: past 4 s no further duty starts (8 s PostgREST statement_timeout), except the
    -- first p_limit, which always run as before
    exit when v_n >= greatest(1, coalesce(p_limit, 8)) and clock_timestamp() - v_t0 > interval '4 seconds';
    v_n := v_n + 1;
    update public.seat_duty set last_started_at = now() where duty = d.duty;
    begin
      if not public.fn_seat_duty_routine_exists(d.routine) then
        raise exception 'routine public.%() does not exist', d.routine;
      end if;
      execute format('select public.%I()', d.routine) into v_res;
      update public.seat_duty set last_ok_at = now(), last_result = v_res, last_error = null, failures = 0 where duty = d.duty;
      v_out := v_out || jsonb_build_object('duty', d.duty, 'ok', true);
    exception when others then
      update public.seat_duty set last_error = left(sqlerrm, 1000), failures = failures + 1 where duty = d.duty;
      v_out := v_out || jsonb_build_object('duty', d.duty, 'ok', false, 'error', left(sqlerrm, 300));
    end;
  end loop;

  -- The check, every tick: each problem is a finding; a duty that recovered closes its own.
  v_health := public.fn_seat_duty_health();
  for p in select * from jsonb_array_elements(v_health) loop
    perform public.fn_it_engineer_finding_upsert(
      'seat_duty:' || (p->>'duty'),
      'Seat duty ' || (p->>'duty') || ' is not being done: ' || (p->>'problem'),
      'public.seat_duty / ' || coalesce(p->>'routine', '?'), 'agent_facing', 1, p,
      '{}'::text[], array['why the routine fails or is not reached'], 'it_engineer');
  end loop;
  update public.it_engineer_finding f
     set closed_at = now(), close_note = 'the duty is no longer overdue or failing: it ran on its clock again, or it was disabled (fn_seat_duties_tick)'
   where f.issue_key like 'seat_duty:%' and f.closed_at is null
     and not exists (select 1 from jsonb_array_elements(v_health) h where 'seat_duty:' || (h->>'duty') = f.issue_key);
  return jsonb_build_object('ran', v_out, 'problems', jsonb_array_length(v_health));
end $fn$;
revoke execute on function public.fn_seat_duties_tick(integer) from public, anon, authenticated;
grant execute on function public.fn_seat_duties_tick(integer) to service_role;
