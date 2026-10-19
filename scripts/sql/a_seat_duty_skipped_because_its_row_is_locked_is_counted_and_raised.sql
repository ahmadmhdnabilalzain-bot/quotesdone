-- A SEAT DUTY SKIPPED BECAUSE ITS ROW IS LOCKED IS COUNTED, AND RAISED AFTER TWO OF ITS INTERVALS.
-- Seat: it_engineer. 19 Oct 2026.
--
-- MEASURED 19 Oct 2026: five sales_engineer duties (stalled_inquiry_rescue, concierge, disputes, quote_quality_hold,
-- supplier_availability) had no run from 04:45/05:00 UTC to after 06:15, with no failure and no error. CI replays
-- held their public.seat_duty rows, and fn_seat_duty_run's "for update skip locked" answered {ran:false}, which
-- nothing recorded (fixed at the source in PR #1557). A skip is now recorded in its own table (the duty's row
-- is the one that is locked, so it cannot hold the count). fn_seat_duties_tick raises seat_duty_skipped:<duty>
-- once a duty has been skipped for more than two of its own intervals, and closes it when the duty runs again.
-- A healthy day records no skip, so the alarm is quiet (registered in every_alarm_is_quiet_on_a_healthy_day).
-- Redefines fn_seat_duty_run and fn_seat_duties_tick from one_slow_duty_never_wedges_the_seat_duty_tick.sql
-- (the canonical file); only the skip lines are new.

create table if not exists public.seat_duty_skip (
  duty text primary key references public.seat_duty(duty) on delete cascade,
  skips integer not null default 0,
  first_skipped_at timestamptz not null default now(),
  last_skipped_at timestamptz not null default now()
);
alter table public.seat_duty_skip enable row level security;
drop policy if exists seat_duty_skip_service_role_only on public.seat_duty_skip;
create policy seat_duty_skip_service_role_only on public.seat_duty_skip
  as permissive for all to public using (false) with check (false);
revoke all on public.seat_duty_skip from anon, authenticated;

create or replace function public.fn_seat_duty_run(p_duty text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare d public.seat_duty; v_res jsonb; v_t0 timestamptz := clock_timestamp(); v_ms integer;
begin
  select sd.* into d from public.seat_duty sd
   where sd.duty = p_duty and sd.enabled
     and not exists (select 1 from public.duty_pause dp where dp.duty = sd.duty)
     and (sd.last_started_at is null or now() - sd.last_started_at >= sd.every - interval '2 minutes')
   for update skip locked;
  if not found then
    -- Due, enabled and not paused, yet not found: another transaction holds the row. Count it (19 Oct 2026).
    if exists (select 1 from public.seat_duty sd
                where sd.duty = p_duty and sd.enabled
                  and not exists (select 1 from public.duty_pause dp where dp.duty = sd.duty)
                  and (sd.last_started_at is null or now() - sd.last_started_at >= sd.every - interval '2 minutes')) then
      insert into public.seat_duty_skip as k (duty, skips) values (p_duty, 1)
      on conflict (duty) do update set skips = k.skips + 1, last_skipped_at = now();
      return jsonb_build_object('duty', p_duty, 'ran', false, 'skipped', 'row locked');
    end if;
    return jsonb_build_object('duty', p_duty, 'ran', false);
  end if;
  update public.seat_duty set last_started_at = now() where duty = d.duty;
  delete from public.seat_duty_skip where duty = d.duty;   -- it ran: the skip streak ends
  begin
    if not public.fn_seat_duty_routine_exists(d.routine) then
      raise exception 'routine public.%() does not exist', d.routine;
    end if;
    execute format('select public.%I()', d.routine) into v_res;
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
    update public.seat_duty set last_ok_at = now(), last_result = v_res, last_error = null, failures = 0,
           avg_ms = round(coalesce(avg_ms * 0.7 + v_ms * 0.3, v_ms)) where duty = d.duty;
    if not d.own_job and (select avg_ms from public.seat_duty where duty = d.duty) > 1000 then
      perform public.fn_seat_duty_isolate(d.duty);   -- too slow for the shared tick: its own job from now on
    end if;
    return jsonb_build_object('duty', d.duty, 'ok', true, 'ms', v_ms);
  exception when others then
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
    update public.seat_duty set last_error = left(sqlerrm, 1000), failures = failures + 1,
           avg_ms = round(coalesce(avg_ms * 0.7 + v_ms * 0.3, v_ms)) where duty = d.duty;
    if not d.own_job and (select avg_ms from public.seat_duty where duty = d.duty) > 1000 then
      perform public.fn_seat_duty_isolate(d.duty);
    end if;
    return jsonb_build_object('duty', d.duty, 'ok', false, 'ms', v_ms, 'error', left(sqlerrm, 300));
  end;
end $function$;
revoke execute on function public.fn_seat_duty_run(text) from public, anon, authenticated;

create or replace function public.fn_seat_duties_tick(p_limit integer default 8)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare d public.seat_duty; v_out jsonb := '[]'::jsonb; v_health jsonb; p jsonb; k record;
        v_t0 timestamptz := clock_timestamp(); v_ms integer;
begin
  -- A duty never measured gets its own job before anything else: it may be the 9 s one.
  perform public.fn_seat_duty_isolate(sd.duty) from public.seat_duty sd where sd.enabled and not sd.own_job and sd.avg_ms is null;
  -- Up to greatest(30, least(p_limit, 60)) candidates, the most overdue first; fn_seat_duty_run locks each.
  for d in
    select sd.* from public.seat_duty sd
     where enabled and not own_job and avg_ms is not null
       -- ONE PAUSE SWITCH (29 Sep 2026): a duty public.duty_pause names is not started.
       and not exists (select 1 from public.duty_pause dp where dp.duty = sd.duty)
       -- two minutes of tolerance, the same reasoning as fn_resilience_tick_plan: a tick is never exactly on the beat
       and (last_started_at is null or now() - last_started_at >= every - interval '2 minutes')
     order by last_started_at + every nulls first, duty
     limit greatest(30, least(coalesce(p_limit, 8), 60))
  loop
    -- NEVER START A DUTY THAT WILL NOT FIT (18 Oct 2026): nothing starts after 1.5 s, and a duty starts only if
    -- 1.5x its measured time ends before 4 s. The tick is one statement under an 8 s timeout no handler can catch.
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
    exit when v_ms > 1500;
    continue when v_ms + d.avg_ms * 1.5 > 4000;
    v_out := v_out || public.fn_seat_duty_run(d.duty);
  end loop;

  -- The check, every tick: each problem is a finding; a duty that recovered closes its own.
  v_health := public.fn_seat_duty_health();
  for p in select * from jsonb_array_elements(v_health) loop
    -- a paused duty is overdue on purpose; it is not a finding while the pause stands
    continue when exists (select 1 from public.duty_pause dp where dp.duty = p->>'duty');
    perform public.fn_it_engineer_finding_upsert(
      'seat_duty:' || (p->>'duty'),
      'Seat duty ' || (p->>'duty') || ' is not being done: ' || (p->>'problem'),
      'public.seat_duty / ' || coalesce(p->>'routine', '?'), 'agent_facing', 1, p,
      '{}'::text[], array['why the routine fails or is not reached'], 'it_engineer');
  end loop;
  update public.it_engineer_finding f
     set closed_at = now(), close_note = 'the duty is no longer overdue or failing: it ran on its clock again, or it was disabled or paused (fn_seat_duties_tick)'
   where f.issue_key like 'seat_duty:%' and f.closed_at is null
     and (not exists (select 1 from jsonb_array_elements(v_health) h where 'seat_duty:' || (h->>'duty') = f.issue_key)
          or exists (select 1 from public.duty_pause dp where 'seat_duty:' || dp.duty = f.issue_key));

  -- SKIPPED BECAUSE ITS ROW WAS LOCKED (19 Oct 2026): raised once the streak is longer than two of its intervals.
  for k in select s.duty, s.skips, s.first_skipped_at, sd.every from public.seat_duty_skip s
             join public.seat_duty sd on sd.duty = s.duty
            where now() - s.first_skipped_at > 2 * sd.every loop
    perform public.fn_it_engineer_finding_upsert(
      'seat_duty_skipped:' || k.duty,
      'Seat duty ' || k.duty || ' is skipped: its row was locked by another transaction ' || k.skips || ' times since ' || k.first_skipped_at,
      'public.fn_seat_duty_run (for update skip locked)', 'agent_facing', 1,
      jsonb_build_object('duty', k.duty, 'skips', k.skips, 'first_skipped_at', k.first_skipped_at, 'every', k.every),
      '{}'::text[], array['which transaction holds the seat_duty row (pg_locks), and why it holds it that long'], 'it_engineer');
  end loop;
  update public.it_engineer_finding f
     set closed_at = now(), close_note = 'the duty ran again: no skip streak is open (fn_seat_duties_tick)'
   where f.issue_key like 'seat_duty_skipped:%' and f.closed_at is null
     and not exists (select 1 from public.seat_duty_skip s where 'seat_duty_skipped:' || s.duty = f.issue_key);

  return jsonb_build_object('ran', v_out, 'problems', jsonb_array_length(v_health),
                            'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end $function$;
revoke execute on function public.fn_seat_duties_tick(integer) from public, anon, authenticated;

-- PROBE (verdict row; it writes nothing). The locked-row branch needs a SECOND session holding the row, which one
-- applied file cannot create (a transaction never skips its own lock). This probe asserts the table, its policy and
-- grants, and that an unknown duty is neither run nor counted. The locked branch is proved by the static test in
-- scripts/checks/every_alarm_is_quiet_on_a_healthy_day.test.mjs and is not yet proved on production.
select case
  when to_regclass('public.seat_duty_skip') is null then 'PROBE FAILED: seat_duty_skip missing'
  when not exists (select 1 from pg_policies where tablename = 'seat_duty_skip') then 'PROBE FAILED: seat_duty_skip has no policy'
  when has_table_privilege('anon', 'public.seat_duty_skip', 'select') then 'PROBE FAILED: anon can read seat_duty_skip'
  when (public.fn_seat_duty_run('zz_probe_no_such_duty')->>'ran')::boolean is not false then 'PROBE FAILED: an unknown duty ran'
  when exists (select 1 from public.seat_duty_skip where duty = 'zz_probe_no_such_duty') then 'PROBE FAILED: an unknown duty was counted as skipped'
  else 'PROBE OK'
end as verdict;
