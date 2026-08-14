-- Stage 5/6 — make the decision trace real.
--
-- decision_trace has carried the right columns since it was built: policy keys, knowledge
-- refs, evidence refs, alternatives, assumptions, risk, confidence, authority result. It held
-- FOUR rows, all written on 6 Aug by fn_decide — a 20,000-character engine with no caller in
-- any function, edge function or script. Meanwhile 576 agent actions were decided in the last
-- seven days and none of them left a trace. The capability was finished and had no entry point.
--
-- Two changes give it one:
--   1. the context path records what it retrieved, so there is something to cite;
--   2. every agent action that gets decided writes a trace naming those knowledge ids.

-- What a context assembly actually returned. Written by the one path every agent calls.
create table if not exists agent_context_retrieval (
  id             bigserial primary key,
  agent_key      text not null,
  task_class     text,
  category_key   text,
  knowledge_ids  text[] not null default '{}',
  knowledge_count integer not null default 0,
  budget_chars   integer,
  chars_returned integer,
  created_at     timestamptz not null default now()
);
create index if not exists agent_context_retrieval_agent on agent_context_retrieval (agent_key, created_at desc);
alter table agent_context_retrieval enable row level security;

-- Keep it from growing without bound: a retrieval is only useful while an action might still
-- cite it. Anything older than seven days is history the trace already captured.
create or replace function fn_context_retrieval_prune() returns integer
language sql security definer set search_path = public as $$
  with d as (delete from agent_context_retrieval where created_at < now() - interval '7 days' returning 1)
  select count(*)::int from d;
$$;
revoke all on function fn_context_retrieval_prune() from public;

-- The recorder. Separate from fn_agent_context_v3 because that one is STABLE and must remain
-- so — it is called inside SELECTs.
create or replace function fn_record_context_retrieval(
  p_agent_key text, p_task_class text, p_category text,
  p_ids text[], p_budget integer, p_chars integer
) returns bigint
language sql volatile security definer set search_path = public as $$
  insert into agent_context_retrieval
    (agent_key, task_class, category_key, knowledge_ids, knowledge_count, budget_chars, chars_returned)
  values (p_agent_key, p_task_class, p_category, coalesce(p_ids,'{}'),
          coalesce(array_length(p_ids,1),0), p_budget, p_chars)
  returning id;
$$;
revoke all on function fn_record_context_retrieval(text, text, text, text[], integer, integer) from public;
grant execute on function fn_record_context_retrieval(text, text, text, text[], integer, integer) to service_role;

-- Every decided agent action leaves a trace. The knowledge ids come from that agent's most
-- recent context assembly; the window is stated rather than implied, and a trace written with
-- no retrieval in the window says so instead of pretending it read something.
create or replace function fn_agent_action_trace() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_ret   agent_context_retrieval;
  v_ident record;
  v_auth  jsonb;
begin
  select * into v_ret from agent_context_retrieval
   where agent_key = new.agent and created_at >= new.created_at - interval '30 minutes'
   order by created_at desc limit 1;

  select a.department, i.packaged_role_id, i.packaged_department, i.readiness
    into v_ident
    from org_agents a
    left join org_role_identity i on i.agent_key = a.agent_key
   where a.agent_key = new.agent
   limit 1;

  select coalesce(jsonb_agg(jsonb_build_object('action_class', action_class, 'max_tier', max_tier,
                                               'threshold_aed', threshold_aed)), '[]'::jsonb)
    into v_auth
    from org_authority where dept_key = v_ident.department;

  insert into decision_trace (
    correlation_id, entity_type, entity_id, decision_type, proposed_by, decided_by,
    policy_keys, knowledge_refs, evidence_refs, alternatives, assumptions, risk,
    confidence, authority_result, decision, outcome_status)
  values (
    gen_random_uuid(), 'agent_action', new.id::text, coalesce(new.kind, 'agent_action'),
    new.agent, coalesce(new.decided_by, new.agent),
    array_remove(array[new.kind, new.risk], null),
    case when v_ret.id is null
         then jsonb_build_object('retrieval', 'none within 30 minutes of the action',
                                 'agent_key', new.agent)
         else jsonb_build_object('retrieval_id', v_ret.id, 'assembled_at', v_ret.created_at,
                                 'knowledge_count', v_ret.knowledge_count,
                                 'knowledge_ids', to_jsonb(v_ret.knowledge_ids),
                                 'task_class', v_ret.task_class) end,
    coalesce(new.evidence, '{}'::jsonb),
    coalesce(new.alternatives, '[]'::jsonb),
    coalesce(new.assumptions, '[]'::jsonb),
    jsonb_build_object('risk', new.risk, 'cost', new.cost, 'expected_impact', new.expected_impact),
    new.confidence,
    jsonb_build_object('department', v_ident.department, 'role_id', v_ident.packaged_role_id,
                       'packaged_department', v_ident.packaged_department,
                       'readiness', v_ident.readiness, 'escalated', new.escalated,
                       'escalation_reason', new.escalation_reason, 'department_authority', v_auth),
    jsonb_build_object('status', new.status, 'title', new.title,
                       'recommendation', new.recommendation, 'target_table', new.target_table,
                       'target_id', new.target_id),
    case when new.status in ('approved','applied','executed') then 'accepted'
         when new.status in ('rejected','refused') then 'rejected'
         else 'pending' end);
  return null;
end $$;

revoke all on function fn_agent_action_trace() from public;

drop trigger if exists z90_agent_action_decision_trace on agent_actions;
create trigger z90_agent_action_decision_trace
  after update of decided_at on agent_actions
  for each row
  when (old.decided_at is null and new.decided_at is not null)
  execute function fn_agent_action_trace();
