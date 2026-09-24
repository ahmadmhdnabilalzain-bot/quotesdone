-- THE IT ENGINEER HOLDS THE PORTALS TO THEIR LATENCY BUDGET, EVERY HOUR, PER FUNCTION AND FOR THE SITE.
-- Seat: it_engineer. 24 Sep 2026, seat audit (GAPS.md IT gap 4; ledger 983). Needs
-- every_seat_duty_has_an_owner_a_clock_and_a_check.sql (seat_duty) and fn_it_duty_settle.
--
-- WHAT WAS MEASURED (production, 24 Sep 2026): the 2.5 s budget on portal data (the founder's number) was checked
--   only by the nightly journey, once a night, and it has failed there on 21-23 Sep (duty:journey:... overview data
--   under 2.5 s, seen 5 times). v_edge_function_health computes a p95, but from SAMPLED rows: observe() logs one healthy
--   run a minute per isolate and every run over 4 s, so its p95 over-states the slow tail and nobody judged it.
--
-- WHAT THIS ADDS: seat_duty it_engineer.latency_slo (1 hour). observe() now logs EVERY run of the seven portal data
--   functions with counts.budget_ms (supabase/functions/_shared/observe.ts LATENCY_BUDGET_MS), so the p95 here is
--   a true p95. Per function over the last 24 hours, healthy runs only (status 'ok', not the 204 warm-up pings,
--   not OPTIONS), at least 30 of them: p95 over budget_ms is a finding duty:latency_slo:<fn> for the seat that owns
--   the function (public.function_owner). Runs served from a us-* edge region are left out: measured 21 Sep, the
--   GitHub-runner smoke is served there at ~3.3 s p50 against ~1 s from ap-south-1, and customers are in the UAE.
--   The site: p95 of it_watch_tick.site_ms (the home page, every 15 min) over 24 h against the same 2.5 s.
--   A reading that recovers closes its finding (fn_it_duty_settle).
--
-- WHAT THIS DOES NOT DO: it does not make a slow function faster; the owning seat's handoff carries the numbers.
--
--   node scripts/apply_sql.mjs scripts/sql/the_it_engineer_holds_the_portals_to_their_latency_budget.sql --apply --ddl
--   then deploy every function that imports _shared/observe.ts (the seven portal functions at least).

create or replace function public.fn_it_engineer_latency_slo()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare x record; v_items jsonb := '[]'::jsonb; v_out jsonb := '[]'::jsonb; v_site numeric; v_site_n int;
begin
  for x in
    select substring(r.agent from 4) fn, max((r.counts->>'budget_ms')::int) budget, count(*) n,
           percentile_cont(0.95) within group (order by (r.counts->>'ms')::numeric) p95
      from public.agent_runs r
     where r.agent like 'fn:%' and r.started_at > now() - interval '24 hours'
       and r.counts ? 'budget_ms' and r.status = 'ok'
       and coalesce(r.counts->>'http', '') <> '204' and coalesce(r.counts->>'method', '') <> 'OPTIONS'
       and coalesce(r.counts->>'region', '') not like 'us-%'
     group by 1
  loop
    v_out := v_out || jsonb_build_object('fn', x.fn, 'runs', x.n, 'p95_ms', round(x.p95), 'budget_ms', x.budget);
    if x.n >= 30 and x.p95 > x.budget then
      v_items := v_items || jsonb_build_object('item', x.fn, 'subject', x.fn, 'blast', 'customer_facing', 'affected', x.n,
        'owner_seat', coalesce((select o.owner from public.function_owner o where o.function_slug = x.fn), 'it_engineer'),
        'title', x.fn || ' answered in ' || round(x.p95) || ' ms at p95 over the last 24 h (' || x.n || ' runs); the budget is ' || x.budget || ' ms',
        'evidence', jsonb_build_object('p95_ms', round(x.p95), 'runs', x.n, 'budget_ms', x.budget, 'window', '24 hours'));
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
revoke execute on function public.fn_it_engineer_latency_slo() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_latency_slo() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('it_engineer.latency_slo', 'it_engineer', interval '1 hour', 'fn_it_engineer_latency_slo',
   'p95 per portal data function and for the home page over 24 h against the 2.5 s budget; over budget is a finding for the owning seat.',
   'scripts/sql/the_it_engineer_holds_the_portals_to_their_latency_budget.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

select case when to_regprocedure('public.fn_it_engineer_latency_slo()') is not null
             and exists (select 1 from public.seat_duty where duty = 'it_engineer.latency_slo')
            then 'PROBE OK' else 'PROBE FAILED: the latency duty is not registered' end as verdict;
