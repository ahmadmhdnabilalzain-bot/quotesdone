-- THE LATENCY DUTY TITLES AN ERROR-BUDGET BREACH ON A DAY WITH NO COUNTED RUNS (it_engineer, 27 Oct 2026).
--
-- Measured 26 Oct 2026 21:00Z: seat duty it_engineer.latency_slo had failed 115 times in a row (last ok 22 Oct 00:00Z).
-- Every run raised inside fn_it_duty_settle: "every item needs an item key and a title", on the item
-- customer_api:error_budget. customer_api's 30-day window holds 5,137 counted runs, 321 of them bad (availability
-- 93.75 %, so budget_breach is true), but all 118 of its runs in the last 24 h answered HTTP 204 and are not counted,
-- so runs_24h = 0. fn_it_slo_judge then (correctly) returns burn_rate_24h = null, and the title concatenated that null:
-- 'x is burning its error budget at ' || null || ... is null, so the whole title was null and the settle refused the
-- batch. One item with no traffic today silenced the duty for every function, every hour, for four days.
--
-- The fix: the title says what is true when there is no 24-hour rate (the 30-day budget is spent; no counted runs
-- today) instead of concatenating a null. Nothing else in the routine changes. The judge is untouched.
--
-- Prevented by: scripts/checks/the_latency_and_month_plan_duties_survive_their_failing_inputs.test.mjs (replays the
-- 26 Oct input in a rolled-back transaction: a function with a 30-day breach and no counted runs today).

create or replace function public.fn_it_engineer_latency_slo()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
      -- burn_rate_24h is null on a day with no counted runs (the judge has no rate to give); the breach then comes
      -- from the 30-day window alone, and the title says so rather than concatenating the null (26 Oct 2026).
      v_items := v_items || jsonb_build_object('item', x.fn || ':error_budget', 'subject', x.fn, 'blast', 'customer_facing',
        'affected', x.bad_24h, 'owner_seat', v_owner,
        'title', x.fn || coalesce(' is burning its error budget at ' || (j->>'burn_rate_24h') || 'x over 24 h',
                                  ' has spent its error budget (no counted runs in the last 24 h)')
                 || '; 30-day availability '
                 || coalesce(round((j->>'availability')::numeric * 100, 2)::text, 'unmeasured') || ' % against a 99.9 % objective',
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
revoke execute on function public.fn_it_engineer_latency_slo() from public, anon, authenticated;
