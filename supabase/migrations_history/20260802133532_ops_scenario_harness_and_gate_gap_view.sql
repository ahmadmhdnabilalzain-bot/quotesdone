-- PHASE 4 TEST HARNESS.
-- Honest scoping first: the 282 scenarios describe BEHAVIOUR ("a supplier submits a quote after the
-- deadline; the system should ..."). Executing them properly needs a runner that can drive the real
-- flows, which does not exist and is not in this session's scope. What CAN be executed
-- deterministically today is whether each scenario is even RUNNABLE - whether the department it
-- names exists, has knowledge, has resolved live data, has an authority position and has stated
-- pass criteria. A scenario that fails this cannot pass a behavioural run either, so it is a real
-- filter rather than a box-tick, and it is labelled 'structural' everywhere so nobody mistakes it
-- for behavioural proof.
create or replace function public.fn_ops_run_scenarios()
returns table (scenario_id text, kind text, scope_key text, verdict text, failures text[])
language sql volatile as $$
with checked as (
  select s.record_id, s.kind, s.scope_key,
    array_remove(array[
      case when not exists (select 1 from ops_kb_stage.departments d where d.department_key = s.scope_key)
            and s.kind = 'department' then 'department not in the corpus department index' end,
      case when s.kind = 'workflow'
            and not exists (select 1 from ops_kb_stage.workflows w where w.workflow_key = s.scope_key)
           then 'workflow_key does not resolve to an imported workflow' end,
      case when coalesce(btrim(s.expected_behaviour), '') = '' then 'no expected behaviour stated' end,
      case when jsonb_array_length(coalesce(s.pass_criteria, '[]'::jsonb)) = 0 then 'no pass criteria' end,
      case when s.kind = 'department'
            and not exists (select 1 from ops_kb_stage.records r
                            where r.scope_type='department' and r.scope_key = s.scope_key
                              and r.module = 'professional_knowledge')
           then 'department has no professional knowledge to reason from' end,
      case when s.kind = 'department'
            and not exists (select 1 from ops_kb_stage.live_bindings b
                            where b.department_key = s.scope_key and b.mapping_status='mapped')
           then 'department has no resolved live-data binding' end,
      case when s.kind = 'department'
            and not exists (select 1 from ops_kb_stage.decision_rules dr where dr.department_key = s.scope_key)
           then 'department has no decision rules' end
    ], null) as failures
  from ops_kb_stage.scenarios s
)
select c.record_id, c.kind, c.scope_key,
       case when cardinality(c.failures) = 0 then 'RUNNABLE' else 'BLOCKED' end,
       c.failures
from checked c;
$$;

comment on function public.fn_ops_run_scenarios() is
  'STRUCTURAL scenario check, not behavioural. Answers "could this scenario be run at all" - department exists, has knowledge, has resolved live data, has rules, states pass criteria. A BLOCKED scenario cannot pass a behavioural run either. Behavioural execution needs a flow runner that does not exist yet.';

-- Persist the outcome so the counts are queryable rather than transient.
update ops_kb_stage.scenarios s
set last_result = r.verdict,
    last_run = now(),
    raw = s.raw || jsonb_build_object('structural_failures', to_jsonb(r.failures))
from public.fn_ops_run_scenarios() r
where r.scenario_id = s.record_id;

-- GOVERNANCE GAP VIEW. 8 of the 10 corpus hard gates have no org_authority row at ALL. They are
-- safe inside fn_ops_authority_check because it fails closed, but any other code path that reads
-- org_authority directly finds nothing and has to invent a default. Stating the gap is the point;
-- filling it would be an authority change, which is itself hard-gated and is the founder's call.
create or replace view public.v_ops_hard_gate_coverage as
select g.raw->>'action_class'   as action_class,
       g.title                  as gate_title,
       g.raw->>'default_tier'   as corpus_default_tier,
       g.raw->>'approval_role'  as approval_role,
       (select count(*) from public.org_authority a where a.action_class = g.raw->>'action_class') as org_authority_rows,
       (select string_agg(a.dept_key || '=' || a.max_tier, ', ' order by a.dept_key)
          from public.org_authority a where a.action_class = g.raw->>'action_class') as existing_authority,
       case when (select count(*) from public.org_authority a where a.action_class = g.raw->>'action_class') = 0
            then 'NO AUTHORITY ROW - relies on fail-closed default'
            else 'covered' end as status
from ops_kb_stage.hard_gates g;

comment on view public.v_ops_hard_gate_coverage is
  'Which of the 10 corpus hard gates are actually represented in public.org_authority. Eight are not. They are gated today only because fn_ops_authority_check defaults to gated when no row exists; filling them in is an authority change and therefore the founder''s decision, not the importer''s.';
