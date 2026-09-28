-- A SLOW FUNCTION BREACHES ITS BUDGET HOWEVER FEW RUNS IT HAD; EVERY PORTAL FUNCTION CARRIES AN ERROR BUDGET.
-- Seat: it_engineer. 28 Sep 2026. Supersedes fn_it_engineer_latency_slo() in
-- the_it_engineer_holds_the_portals_to_their_latency_budget.sql (the duty row there is unchanged).
--
-- WHAT WAS MEASURED (production, 28 Sep 2026, seat_duty.last_result of it_engineer.latency_slo at 12:31 UTC):
--   kyc p95 10,923 ms over 11 runs against a 2,500 ms budget, and the duty reported settled.failing = 0.
--   ROOT CAUSE: the breach required `x.n >= 30` runs in 24 h. Pre-launch no portal function reaches 30 real
--   (non-204, non-US) runs a day - kyc 11, messages_api 7, supplier_portal 16, supplier_api 27 - so the duty
--   could never fire for ANY function. The floor protected against a noisy p95 on traffic that does not exist.
--   30-day shape of the rows it reads (agent_runs 'fn:%' carrying counts.budget_ms, every run logged):
--   2xx/204 'ok', 4xx 'warn' (supplier_portal 94 x 401), no 5xx yet.
--
-- WHAT THIS CHANGES:
--   1. The p95 breach needs 5 runs, not 30 (MIN_RUNS). With 5-29 runs the finding says the sample is small.
--   2. Per-function SLIs over 30 days, same rows: availability = good runs / runs, a good run being not a
--      server error (http >= 500 or status 'error') AND inside budget_ms; error rate = server errors / runs;
--      p95. SLO 99.9 % availability, so the 30-day error budget is 0.1 % of runs. Burn rate = bad share over
--      the last 24 h / 0.001. Burn >= 2 over 24 h (>= 5 runs), or the 30-day budget spent, is a finding
--      duty:latency_slo:<fn>:error_budget for the owning seat, through fn_it_duty_settle like the p95 one.
--   The judgement is fn_it_slo_judge(), pure and immutable, so the probe below tests it with kyc's real numbers.
--
-- WHAT THIS DOES NOT DO: it does not make kyc faster. Not applied, not deployed (see pending note).
--   node scripts/apply_sql.mjs scripts/sql/a_slow_function_breaches_its_budget_however_few_runs_it_had.sql --apply --ddl

create or replace function public.fn_it_slo_judge(p_runs_24h int, p_p95_ms numeric, p_budget_ms int,
                                                  p_bad_24h int, p_runs_30d int, p_bad_30d int)
returns jsonb
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  -- MIN_RUNS 5, SLO 99.9 % (error budget 0.001), burn-rate alarm 2x. One place for every threshold.
  select jsonb_build_object(
    'p95_breach',   coalesce(p_runs_24h, 0) >= 5 and p_p95_ms > p_budget_ms,
    'small_sample', coalesce(p_runs_24h, 0) between 5 and 29,
    'availability', case when p_runs_30d > 0 then round(1 - p_bad_30d::numeric / p_runs_30d, 4) end,
    'budget_spent', case when p_runs_30d > 0 then round((p_bad_30d::numeric / p_runs_30d) / 0.001, 2) end,
    'burn_rate_24h', case when p_runs_24h > 0 then round((p_bad_24h::numeric / p_runs_24h) / 0.001, 2) end,
    'budget_breach', (case when coalesce(p_runs_24h, 0) >= 5 then p_bad_24h::numeric / p_runs_24h / 0.001 >= 2 else false end)
                     or (case when coalesce(p_runs_30d, 0) >= 5 then p_bad_30d::numeric / p_runs_30d > 0.001 else false end));
$fn$;
revoke execute on function public.fn_it_slo_judge(int, numeric, int, int, int, int) from public, anon, authenticated;
grant execute on function public.fn_it_slo_judge(int, numeric, int, int, int, int) to service_role;

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
         and coalesce(r.counts->>'region', '') not like 'us-%')
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
    j := public.fn_it_slo_judge(x.runs_24h::int, x.p95, x.budget, x.bad_24h::int, x.runs_30d::int, x.bad_30d::int);
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
revoke execute on function public.fn_it_engineer_latency_slo() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_latency_slo() to service_role;

-- PROBE: kyc's real reading of 28 Sep (11 runs, p95 10,923 ms, budget 2,500) must breach; the old 30-run floor
-- did not. Pure function, no rows written.
select case
  when not (public.fn_it_slo_judge(11, 10923, 2500, 2, 84, 10)->>'p95_breach')::boolean
    then 'PROBE FAILED: kyc at 10,923 ms p95 over 11 runs is not flagged'
  when not (public.fn_it_slo_judge(11, 10923, 2500, 2, 84, 10)->>'budget_breach')::boolean
    then 'PROBE FAILED: 2 of 11 runs over budget does not burn the error budget'
  when (public.fn_it_slo_judge(11, 900, 2500, 0, 84, 0)->>'p95_breach')::boolean
    or (public.fn_it_slo_judge(11, 900, 2500, 0, 84, 0)->>'budget_breach')::boolean
    then 'PROBE FAILED: a healthy function is flagged'
  when (public.fn_it_slo_judge(3, 10923, 2500, 3, 3, 3)->>'p95_breach')::boolean
    then 'PROBE FAILED: 3 runs is below the floor and still breached'
  when not (public.fn_it_slo_judge(20, 900, 2500, 0, 500, 1)->>'budget_breach')::boolean
    then 'PROBE FAILED: 1 bad run in 500 (99.8 %) does not breach the 99.9 % objective'
  else 'PROBE OK' end as verdict;
