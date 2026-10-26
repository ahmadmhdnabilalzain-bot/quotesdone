-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727010542   name: capability_tests_latest_run_and_flakiness_v2
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

drop view if exists public.v_critical_capability_tests;

create view public.v_critical_capability_tests as
with latest as (
  select distinct on (agent) agent, status, started_at
  from agent_runs order by agent, started_at desc
)
select c.capability_key, c.capability, c.owner_dept, c.test_kind, c.test_ref, c.why_critical,
       case
         when c.test_kind = 'none' or c.test_ref is null then 'UNTESTED'
         when c.test_kind = 'rpc_selftest' then 'SELFTEST_ON_BUILD'
         when c.test_kind = 'scenario' then coalesce(
              (select case when s.last_result = 'pass' then 'PASSING'
                           when s.last_result = 'not_run' then 'NEVER_RUN'
                           else 'FAILING' end
                 from scenario_library s where s.scenario_key = c.test_ref), 'NEVER_RUN')
         when c.test_kind = 'suite' then coalesce(
              (select case when l.status = 'ok' then 'PASSING' else 'FAILING' end
                 from latest l where l.agent = c.test_ref), 'NEVER_RUN')
         else 'UNKNOWN'
       end as state,
       case when c.test_kind = 'suite' and coalesce((select t.pass_pct from v_test_matrix t where t.suite = c.test_ref), 100) < 100
            then true else false end as flaky_in_window,
       (select t.pass_pct from v_test_matrix t where t.suite = c.test_ref) as pass_pct_14d,
       (select l.started_at from latest l where l.agent = c.test_ref) as last_run
from critical_capability c;
