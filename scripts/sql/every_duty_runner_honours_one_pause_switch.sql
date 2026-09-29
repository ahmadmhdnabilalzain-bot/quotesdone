-- EVERY DUTY RUNNER HONOURS ONE PAUSE SWITCH; OUR OWN LAUNCH-PATH PROBE MAY PROVE ITSELF TO supplier_portal.
-- Seat: it_engineer. 29 Sep 2026.
--
-- 1. public.duty_pause. MEASURED: the Twilio API key rotation (resilience_ping step rotate_by_api) had no pause
--    but a code deploy; its only gate is fn_it_provider_rotation_claim reading its own history. seat_duty.enabled
--    stops a SQL duty, but only one with a seat_duty row, and no edge-function step (resilience_ping plan steps,
--    its later-duty steps, marketing's 11 duties) has one. One row here pauses one duty wherever it runs; the
--    names are listed in supabase/functions/_shared/duty_pause.ts. Every runner reads it once a tick:
--      fn_seat_duties_tick (below), resilience_ping (plan + later duties), marketing runDuties.
--    Prevented by: scripts/checks/every_duty_runner_honours_the_pause.test.mjs.
--
-- 2. fn.resilience_ping's credential gains 'supplier_portal' in its scope. MEASURED (edge logs, incident 508):
--    the hourly unauthenticated POST /supplier_portal (401) is resilience_ping's launch-path probe - user-agent
--    SupabaseEdgeRuntime ref=htdblwldjkcgjvmqkbeh, body `{"action":"dashboard"}` (22 bytes),
--    ?forceFunctionRegion=ap-southeast-1, every hour since 21 Sep. The probe now presents this credential in
--    x-qd-probe; supplier_portal marks the refusal fixture only when fn_internal_auth accepts it for
--    supplier_portal (_shared/probe_caller.ts), so refusal_rate stops counting it. The call is still refused.
--
-- Apply at merge:  node scripts/apply_sql.mjs scripts/sql/every_duty_runner_honours_one_pause_switch.sql --apply --ddl

create table if not exists public.duty_pause (
  duty      text primary key,
  reason    text not null check (length(btrim(reason)) > 0),
  paused_by text not null check (length(btrim(paused_by)) > 0),
  paused_at timestamptz not null default now()
);
comment on table public.duty_pause is
  'One row = one duty paused wherever it runs (seat_duty name, resilience_ping.<step>, marketing.<duty>). Delete the row to resume. See supabase/functions/_shared/duty_pause.ts.';
alter table public.duty_pause enable row level security;
drop policy if exists duty_pause_service_role_only on public.duty_pause;
create policy duty_pause_service_role_only on public.duty_pause
  as permissive for all to public using (false) with check (false);
revoke all on public.duty_pause from anon, authenticated;

create or replace function public.fn_seat_duties_tick(p_limit integer default 8)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare d public.seat_duty; v_res jsonb; v_out jsonb := '[]'::jsonb; v_health jsonb; p jsonb;
        v_t0 timestamptz := clock_timestamp(); v_n int := 0;
begin
  for d in
    select * from public.seat_duty
     where enabled
       -- ONE PAUSE SWITCH (29 Sep 2026): a duty public.duty_pause names is not started.
       and not exists (select 1 from public.duty_pause dp where dp.duty = seat_duty.duty)
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
  return jsonb_build_object('ran', v_out, 'problems', jsonb_array_length(v_health));
end $function$;

update public.internal_credential
   set scope = array_append(scope, 'supplier_portal')
 where context = 'fn.resilience_ping' and not ('supplier_portal' = any(scope));

-- PROBE (verdict row; cleans up after itself). A paused seat_duty row is not started by the tick; resumed, it is.
-- Uses a duty name that no seat_duty row carries, so no real duty is touched: the tick's filter is what is read.
with ins as (insert into public.duty_pause (duty, reason, paused_by) values ('zz_probe.duty_pause', 'probe', 'it_engineer') returning duty),
chk as (select (select count(*) from ins) n,
               (select 'supplier_portal' = any(scope) from public.internal_credential where context = 'fn.resilience_ping') scoped)
select case
  when (select n from chk) <> 1 then 'PROBE FAILED: duty_pause refused a row'
  when not coalesce((select scoped from chk), false) then 'PROBE FAILED: fn.resilience_ping is not scoped to supplier_portal'
  when pg_get_functiondef('public.fn_seat_duties_tick(integer)'::regprocedure) !~ 'duty_pause' then 'PROBE FAILED: the tick does not read duty_pause'
  else 'PROBE OK' end as verdict;
delete from public.duty_pause where duty = 'zz_probe.duty_pause';
select case when exists (select 1 from public.duty_pause where duty = 'zz_probe.duty_pause')
            then 'PROBE FAILED: probe row left behind' else 'PROBE OK' end as verdict;
