-- A DUTY ROUTINE WHOSE ARGUMENTS ALL HAVE DEFAULTS IS FOUND (24 Sep 2026; seat: it_engineer).
-- fn_seat_duties_tick and fn_seat_duty_health (every_seat_duty_has_an_owner_a_clock_and_a_check.sql, #901) tested a
-- duty's routine with to_regprocedure on public.<name>() with no arguments, which matches only a zero-argument
-- signature. The CEO's ceo.target_verdict (#913) names fn_ceo_target_daily_verdict(p_at timestamptz default now()):
-- callable with no arguments, but read as missing, so the duty would fail every tick and be reported as not being
-- done. The two bodies are copied from their canonical file with that one test replaced.
--   node scripts/apply_sql.mjs scripts/sql/a_duty_routine_whose_arguments_all_have_defaults_is_found.sql --apply --ddl --seat it_engineer

create or replace function public.fn_seat_duty_routine_exists(p_routine text)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  -- A duty runs as: select public.<routine>(). Any public routine of that name whose arguments ALL have defaults.
  select exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = p_routine
                   and p.pronargs = p.pronargdefaults)
$fn$;
revoke execute on function public.fn_seat_duty_routine_exists(text) from public, anon, authenticated;
grant execute on function public.fn_seat_duty_routine_exists(text) to service_role;

create or replace function public.fn_seat_duties_tick(p_limit integer default 8)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare d public.seat_duty; v_res jsonb; v_out jsonb := '[]'::jsonb; v_health jsonb; p jsonb;
begin
  for d in
    select * from public.seat_duty
     where enabled
       -- two minutes of tolerance, the same reasoning as fn_resilience_tick_plan: a tick is never exactly on the beat
       and (last_started_at is null or now() - last_started_at >= every - interval '2 minutes')
     order by last_started_at nulls first, duty
     limit greatest(1, least(coalesce(p_limit, 8), 30))
     for update skip locked
  loop
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

create or replace function public.fn_seat_duty_health()
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('duty', d.duty, 'owner_seat', d.owner_seat, 'routine', d.routine,
           'problem', x.problem, 'last_ok_at', d.last_ok_at, 'failures', d.failures, 'last_error', d.last_error)
           order by d.duty), '[]'::jsonb)
    from public.seat_duty d
    cross join lateral (select case
        when not public.fn_seat_duty_routine_exists(d.routine) then 'its routine public.' || d.routine || '() does not exist'
        when not exists (select 1 from public.org_role r where r.role_id = d.owner_seat and r.status = 'active')
          then 'its owner ' || d.owner_seat || ' is not an active seat'
        when d.failures >= 3 then 'failed ' || d.failures || ' times running: ' || coalesce(left(d.last_error, 200), '?')
        -- overdue: no success within twice the interval plus one 15-minute tick (a new row gets the same grace)
        when coalesce(d.last_ok_at, d.created_at) < now() - (2 * d.every) - interval '15 minutes'
          then 'no successful run since ' || coalesce(to_char(d.last_ok_at, 'YYYY-MM-DD HH24:MI'), 'it was registered')
      end as problem) x
   where d.enabled and x.problem is not null;
$fn$;
revoke execute on function public.fn_seat_duty_health() from public, anon, authenticated;
grant execute on function public.fn_seat_duty_health() to service_role;
