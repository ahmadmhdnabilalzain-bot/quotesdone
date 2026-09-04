-- THE MODEL BENCHMARK RECORDS ITS COMPARISON, FROM HISTORY, WITH NO NEW PAID CALL.
--
-- Measured 3 Sep 2026: model_outcome held 0 rows. fn_model_benchmark compared models on success
-- rate and cost and RETURNED the table to whoever called it — a cron nobody reads — and wrote
-- only model_registry.quality_score. The comparison existed for the length of one statement. The
-- spec's benchmark store stayed empty and the daily cron was switched off on 16 Aug.
--
-- The benchmark now writes one model_outcome row per (task_class, model) it judges, per day,
-- carrying all three axes the spec names for the same model over the same window:
--   quality  ok = success rate at or above the ACCEPTABLE line (0.85); parse_ok = the share of
--            requests that succeeded on their FIRST attempt from llm_attempt, so a retry cannot
--            mask an unreliable model; the note states both rates and the run count
--   latency  latency_ms = median wall time of the successful calls
--   cost     cost_usd = mean cost per call
-- over the last 90 days of ai_cost_log — the record of every routed call, priced in the database —
-- excluding cache hits and the 'none' route, which is not a model. The 20-run floor stays: a model
-- is never judged on a handful of runs. Today's rows are replaced on re-run, so the store holds one
-- verdict per pair per day. The paid model is held; the whole routine is arithmetic over rows that
-- already exist, and it runs the same whether the hold lifts tomorrow or next year.
--
-- model_benchmark_daily (job 173) is re-enabled as a traced kernel component under the role its
-- component row already carries (ai_director / people_ops).
--
--   node scripts/apply_sql.mjs scripts/sql/model_benchmark_records_outcomes_from_history.sql --apply --ddl

create or replace function public.fn_model_benchmark()
 returns table(task_class text, model_used text, runs bigint, success_rate numeric, avg_cost_usd numeric, verdict text)
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_written int := 0;
  v_models  int := 0;
begin
  create temp table _bench on commit drop as
  with calls as (
    select o.task_class, o.model_used, o.tier, o.ok, o.latency_ms, o.cost_aed
      from public.ai_cost_log o
     where o.occurred_at > now() - interval '90 days'
       and o.task_class is not null
       and o.model_used is not null and o.model_used <> 'none'
       and not coalesce(o.cached, false)
  ), s as (
    select c.task_class, c.model_used,
           max(c.tier) as tier,
           count(*) as runs,
           round(avg(case when c.ok then 1.0 else 0.0 end), 4) as success_rate,
           round((avg(c.cost_aed) / 3.6725)::numeric, 6) as avg_cost_usd,
           percentile_cont(0.5) within group (order by c.latency_ms) filter (where c.ok and c.latency_ms is not null) as p50_latency_ms
      from calls c
     group by c.task_class, c.model_used
    having count(*) >= 20   -- never judge a model on a handful of runs
  ), first_attempt as (
    select a.task_class, a.model_route,
           round(avg(case when a.ok then 1.0 else 0.0 end), 4) as first_ok_rate,
           count(*) as requests
      from public.llm_attempt a
     where a.created_at > now() - interval '90 days' and a.attempt_no = 1 and a.task_class is not null
     group by a.task_class, a.model_route
  )
  select s.task_class, s.model_used, s.tier, s.runs, s.success_rate, s.avg_cost_usd,
         round(s.p50_latency_ms)::int as p50_latency_ms,
         f.first_ok_rate, f.requests as first_requests,
         case
           when s.success_rate >= 0.95 then 'GOOD - safe to keep or promote for this class'
           when s.success_rate >= 0.85 then 'ACCEPTABLE - watch'
           else 'POOR - this class needs a stronger tier'
         end as verdict
    from s
    left join first_attempt f on f.task_class = s.task_class and f.model_route = s.model_used;

  -- one verdict per pair per day: today's rows are replaced, never duplicated
  delete from public.model_outcome m
   where m.fn = 'fn_model_benchmark' and m.occurred_at::date = current_date;

  insert into public.model_outcome (occurred_at, fn, task_class, model_used, tier, ok, parse_ok, latency_ms, cost_usd, note)
  select now(), 'fn_model_benchmark', b.task_class, b.model_used, b.tier,
         b.success_rate >= 0.85,
         coalesce(b.first_ok_rate >= 0.85, b.success_rate >= 0.85),
         b.p50_latency_ms, b.avg_cost_usd,
         format('%s | %s run(s) over 90d: success %s%%, first-attempt success %s (%s request(s)), p50 latency %s ms, mean cost %s USD/call',
                b.verdict, b.runs, round(100 * b.success_rate, 1),
                coalesce(round(100 * b.first_ok_rate, 1)::text || '%', 'n/a'), coalesce(b.first_requests, 0),
                coalesce(b.p50_latency_ms::text, 'n/a'), b.avg_cost_usd)
    from _bench b;
  get diagnostics v_written = row_count;
  select count(distinct b.model_used) into v_models from _bench b;

  -- Feed the score back onto the registry so routing can see it. This is the only writer of
  -- model_registry.quality_score.
  update public.model_registry r set quality_score = q.sr, updated_at = now()
    from (select b.model_used, round(avg(b.success_rate), 4) sr from _bench b group by b.model_used) q
   where r.model_id = q.model_used;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('model_benchmark', now(), now(), 'ok',
          jsonb_build_object('rows', v_written, 'models', v_models),
          'Model benchmark: ' || v_written || ' (task class, model) verdict(s) over ' || v_models
          || ' model(s) written to model_outcome from 90 days of routed calls — quality, latency and '
          || 'cost on the same rows, no new model call.');

  return query
    select b.task_class, b.model_used, b.runs, b.success_rate, b.avg_cost_usd, b.verdict
      from _bench b order by b.task_class, b.success_rate desc;
end $function$;

-- The daily benchmark runs again, traced through the kernel.
select public.fn_kernel_wrap_and_enable_cron(173, 'ai_director', 'people_ops');
update public.phase_c_component c
   set accountable_role_id = 'ai_director', department_id = 'people_ops', activation_state = 'active'
  from public.phase_c_system_execution_wrapper w
 where w.jobid = 173 and c.component_id = w.component_id;

do $$
declare v_bad int;
begin
  select count(*) into v_bad
    from public.phase_c_system_execution_wrapper w
    join public.phase_c_component c on c.component_id = w.component_id
   where w.jobid = 173
     and not exists (select 1 from public.org_role o where o.role_id = c.accountable_role_id);
  if v_bad > 0 then
    raise exception 'model_benchmark_daily: accountable role does not resolve in org_role';
  end if;
end $$;
