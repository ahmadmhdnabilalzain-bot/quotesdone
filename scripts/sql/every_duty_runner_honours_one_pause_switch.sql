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

-- 3. fn_it_engineer_latency_slo leaves server-marked fixture runs out (finding duty:latency_slo:kyc:error_budget).
--    Body otherwise unchanged from a_slow_function_breaches_its_budget_however_few_runs_it_had.sql. CREATE OR REPLACE keeps the ACL.
create or replace function public.fn_it_engineer_latency_slo()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare x record; j jsonb; v_owner text; v_items jsonb := '[]'::jsonb; v_out jsonb := '[]'::jsonb;
        v_site numeric; v_site_n int;
begin
  for x in
    with r as (
      select substring(r.agent from 4) fn, r.started_at, (r.counts->>'ms')::numeric ms,
             (r.counts->>'budget_ms')::int budget,
             r.status, (coalesce((r.counts->>'http')::int, 0) >= 500 or r.status = 'error') srv_err
        from public.agent_runs r
       where r.agent like 'fn:%' and r.started_at > now() - interval '30 days'
         and r.counts ? 'budget_ms'
         and coalesce(r.counts->>'http', '') <> '204' and coalesce(r.counts->>'method', '') <> 'OPTIONS'
         and coalesce(r.counts->>'region', '') not like 'us-%'
         -- OUR OWN HARNESS IS NOT A USER (29 Sep 2026): a run the SERVER marked fixture (a reserved test identity,
         -- _shared/demo_identity.ts; our launch-path probe) spends no error budget - the key refusal_rate already skips.
         and not (r.counts ? 'fixture'))
    select fn, max(budget) budget,
           count(*) filter (where d1 and status = 'ok') n,
           percentile_cont(0.95) within group (order by ms) filter (where d1 and status = 'ok') p95,
           count(*) filter (where d1) runs_24h,
           count(*) filter (where d1 and (srv_err or ms > budget)) bad_24h,
           count(*) runs_30d,
           count(*) filter (where srv_err or ms > budget) bad_30d,
           count(*) filter (where srv_err) err_30d,
           percentile_cont(0.95) within group (order by ms) p95_30d
      from (select r.*, r.started_at > now() - interval '24 hours' d1 from r) z
     group by fn
  loop
    j := public.fn_it_slo_judge(x.runs_24h::int, x.p95::numeric, x.budget::int, x.bad_24h::int, x.runs_30d::int, x.bad_30d::int);
    v_owner := coalesce((select o.owner from public.function_owner o where o.function_slug = x.fn), 'it_engineer');
    v_out := v_out || jsonb_build_object('fn', x.fn, 'runs', x.n, 'p95_ms', round(x.p95), 'budget_ms', x.budget,
      'runs_30d', x.runs_30d, 'availability_30d', j->'availability',
      'error_rate_30d', case when x.runs_30d > 0 then round(x.err_30d::numeric / x.runs_30d, 4) end,
      'p95_30d_ms', round(x.p95_30d), 'error_budget_spent', j->'budget_spent', 'burn_rate_24h', j->'burn_rate_24h');
    if (j->>'p95_breach')::boolean then
      v_items := v_items || jsonb_build_object('item', x.fn, 'subject', x.fn, 'blast', 'customer_facing', 'affected', x.n,
        'owner_seat', v_owner,
        'title', x.fn || ' answered in ' || round(x.p95) || ' ms at p95 over the last 24 h (' || x.n || ' runs'
                 || case when (j->>'small_sample')::boolean then ', a small sample' else '' end
                 || '); the budget is ' || x.budget || ' ms',
        'evidence', jsonb_build_object('p95_ms', round(x.p95), 'runs', x.n, 'budget_ms', x.budget, 'window', '24 hours'));
    end if;
    if (j->>'budget_breach')::boolean then
      v_items := v_items || jsonb_build_object('item', x.fn || ':error_budget', 'subject', x.fn, 'blast', 'customer_facing',
        'affected', x.bad_24h, 'owner_seat', v_owner,
        'title', x.fn || ' is burning its error budget at ' || (j->>'burn_rate_24h') || 'x over 24 h; 30-day availability '
                 || round((j->>'availability')::numeric * 100, 2) || ' % against a 99.9 % objective',
        'evidence', j || jsonb_build_object('runs_24h', x.runs_24h, 'bad_24h', x.bad_24h, 'runs_30d', x.runs_30d,
                                            'bad_30d', x.bad_30d, 'server_errors_30d', x.err_30d));
    end if;
  end loop;

  select percentile_cont(0.95) within group (order by site_ms), count(site_ms) into v_site, v_site_n
    from public.it_watch_tick where ran_at > now() - interval '24 hours' and site_ms is not null;
  if v_site_n >= 30 and v_site > 2500 then
    v_items := v_items || jsonb_build_object('item', 'site_home', 'subject', 'website', 'blast', 'customer_facing', 'owner_seat', 'it_engineer',
      'title', 'The website home page answered in ' || round(v_site) || ' ms at p95 over the last 24 h; the budget is 2500 ms',
      'evidence', jsonb_build_object('p95_ms', round(v_site), 'samples', v_site_n));
  end if;

  return jsonb_build_object('functions', v_out, 'site_p95_ms', round(v_site), 'site_samples', v_site_n,
                            'settled', public.fn_it_duty_settle('latency_slo', v_items));
end $fn$;
grant execute on function public.fn_it_engineer_latency_slo() to service_role;

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
