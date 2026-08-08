-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727004445   name: fix_bi_metric_sql_and_evolution_scan
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

update public.metric_definition
set measure_sql = 'select count(*) from v_marketplace_liquidity where coalesce(inquiries,0) > 0 and coalesce(suppliers_verified,0) > 0'
where metric_key = 'categories_live';

update public.metric_definition
set measure_sql = 'select count(*) from agent_runs where status = ''error'' and started_at > now() - interval ''24 hours'''
where metric_key = 'failed_runs_24h';

create or replace function public.fn_evolution_scan() returns integer
language plpgsql security definer set search_path = public as $fn$
begin
  insert into evolution_proposal (trigger_kind, subject, observation, evidence, proposal, change_class)
  select 'repeated_failure', r.agent,
         format('%s failed %s times in the last 7 days.', r.agent, r.fails),
         jsonb_build_object('failures_7d', r.fails),
         format('Root-cause %s rather than retry it. If the failure is external, add a documented fallback to continuity_plan; if it is a parsing or contract failure, fix the contract and add a regression test.', r.agent),
         'code'
  from (select agent, count(*) fails from agent_runs
        where status = 'error' and started_at > now() - interval '7 days'
        group by agent having count(*) >= 3) r
  on conflict do nothing;

  insert into evolution_proposal (trigger_kind, subject, observation, evidence, proposal, change_class)
  select 'metric_off_target', s.metric_key,
         format('%s is %s against a target of %s.', s.label, coalesce(s.value::text,'unmeasured'), s.target),
         jsonb_build_object('value', s.value, 'target', s.target, 'owner', s.owner_dept),
         format('%s owns this. Either the target is wrong and should be restated, or the operating approach behind it is wrong and should change. Do not carry it as-is for another period.', coalesce(s.owner_dept,'exec')),
         'process'
  from v_bi_scorecard s where s.state = 'OFF_TARGET'
  on conflict do nothing;

  insert into evolution_proposal (trigger_kind, subject, observation, evidence, proposal, change_class)
  select 'cost_anomaly', c.fn,
         format('%s made %s model calls in 30 days that the cost governor flagged as avoidable.', c.fn, c.n),
         jsonb_build_object('avoidable_calls', c.n, 'cost_aed', c.cost),
         format('Replace the flagged path in %s with a rule, a lookup or SQL, or drop it to the small tier.', c.fn),
         'model_routing'
  from (select fn, count(*) n, round(sum(cost_aed),2) cost from ai_cost_log
        where could_be_cheaper and occurred_at > now() - interval '30 days'
        group by fn having count(*) >= 5) c
  on conflict do nothing;

  return (select count(*) from evolution_proposal where status='proposed');
end; $fn$;

revoke execute on function public.fn_evolution_scan() from anon, authenticated, public;
