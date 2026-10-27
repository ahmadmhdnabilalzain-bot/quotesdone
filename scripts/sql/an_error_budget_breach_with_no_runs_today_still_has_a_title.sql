-- AN ERROR-BUDGET BREACH WITH NO RUNS TODAY STILL HAS A TITLE (it_engineer, 27 Oct 2026).
--
-- MEASURED (production htdblwldjkcgjvmqkbeh, read-only, 27 Oct 2026 UTC): the duty it_engineer.latency_slo
-- (fn_it_engineer_latency_slo) had failed 116 runs in a row since 2026-10-22T00:00:51Z with
--   fn_it_duty_settle: every item needs an item key and a title ({"item": "customer_portal:error_budget", "title": null,
--   ... "runs_24h": 0, "runs_30d": 3358, "bad_30d": 23, "budget_breach": true, "burn_rate_24h": null ...})
-- fn_it_slo_judge breaches the error budget on EITHER window: 24 h (>= 5 runs, burn >= 2x) or 30 days (>= 5 runs,
-- bad share > 0.1 %). With 0 runs in the last 24 h it correctly returns burn_rate_24h = null (nothing to divide), and
-- the title concatenated that null, so the whole title became null and fn_it_duty_settle refused the item. One
-- function with a 30-day breach and a quiet day stopped the duty for EVERY function: no latency finding was settled
-- for five days, and the alarm seat_duty:it_engineer.latency_slo fired at every instant.
--
-- WHAT THIS CHANGES: only the error-budget title. With runs in the last 24 h it reads exactly as before; with none it
-- says so and states the 30-day budget spent. Every value in the title is coalesced, so no future null can blank it.
-- The rest of the body is byte for byte the canonical one (every_duty_runner_honours_one_pause_switch.sql, MANIFEST
-- line 1909), whose prosrc equalled production's (md5 a18e9ad5493c23051cdebfda71e9f65c) before this edit.
-- CREATE OR REPLACE keeps the ACL (postgres, service_role only, read 27 Oct 2026); the grant is repeated as the source does.
--
-- Prevented by: scripts/checks/an_error_budget_breach_with_no_runs_today_still_has_a_title.test.mjs (static: every
-- title in the body survives a null; production, rolled back: a 30-day breach with no 24-h runs settles a titled item).
--   node scripts/apply_sql.mjs scripts/sql/an_error_budget_breach_with_no_runs_today_still_has_a_title.sql --apply --ddl --seat it_engineer

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
        -- the 30-day window can breach on a day with no runs: burn_rate_24h is then null, and so would the title be
        'title', x.fn || case when j->>'burn_rate_24h' is not null
                              then ' is burning its error budget at ' || (j->>'burn_rate_24h') || 'x over 24 h'
                              else ' had no runs in the last 24 h and has spent ' || coalesce(j->>'budget_spent', '?')
                                   || 'x its 30-day error budget' end
                 || '; 30-day availability '
                 || coalesce(round((j->>'availability')::numeric * 100, 2)::text, '?') || ' % against a 99.9 % objective',
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
