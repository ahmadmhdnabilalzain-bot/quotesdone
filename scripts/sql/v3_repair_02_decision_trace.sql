-- V3 REMEDIATION — STAGE 3: DECISION TRACE
-- Result of record V3-COR-0A782DA90B10: TRACE_OR_OBSERVABILITY_FAILURE on 2,284 of 2,284 questions.
-- decision_trace_id was null on all 2,407 execution rows. Decision-trace completeness scored 0%.
--
-- MEASURED BEFORE WRITING THIS FILE (staging, 14 Aug 2026): decision_trace held 1 row against 204
-- agent_actions. The table was not missing and the trigger was not broken; the table was simply
-- never on the path any agent takes.
--
-- Two structural defects fixed here, both of the "guarded by a condition that cannot occur" shape:
--
--   1. The only writer was `after update of decided_at on agent_actions`. os_api INSERTs rows with
--      decided_at ALREADY SET, so for that whole path the trigger cannot fire — not "rarely fires",
--      cannot. Fixed with a matching AFTER INSERT trigger.
--   2. No edge function could write a trace at all. There was no callable writer. Added below, and
--      called from agent_brain.
--
-- The rule this file follows: DO NOT CREATE TRACES NOTHING READS. Every column added here is either
-- read by fn_management_decision_review or is a join key that review needs.

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. THE COLUMNS MANAGEMENT REVIEW NEEDS TO BE POSSIBLE
--    The rich payloads already have homes (knowledge_refs, evidence_refs, alternatives,
--    assumptions, risk, authority_result, decision). What was missing is identity and context:
--    without them you cannot ask "show me every consequential decision this role made".
-- ---------------------------------------------------------------------------------------------
alter table public.decision_trace
  add column if not exists task_id             text,
  add column if not exists agent_key           text,
  add column if not exists role_id             text,          -- canonical role, not the agent key
  add column if not exists department_id       text,
  add column if not exists manager_id          text,
  add column if not exists task_class          text,
  add column if not exists company_objective   text,
  add column if not exists department_objective text,
  add column if not exists relevant_kpi        text,
  add column if not exists knowledge_versions  jsonb  not null default '{}'::jsonb,
  add column if not exists source_freshness    jsonb  not null default '{}'::jsonb,
  add column if not exists tools_requested     text[] not null default '{}',
  add column if not exists tools_executed      text[] not null default '{}',
  add column if not exists tool_result_refs    jsonb  not null default '[]'::jsonb,
  add column if not exists uncertainty         text,
  add column if not exists escalation_decision text,
  add column if not exists proposed_action     text,
  add column if not exists expected_outcome    text,
  add column if not exists review_date         date,
  add column if not exists model               text,
  add column if not exists provider            text,
  add column if not exists input_tokens        integer,
  add column if not exists output_tokens       integer,
  add column if not exists estimated_cost_aed  numeric(12,4),
  add column if not exists final_status        text,
  add column if not exists sealed_at           timestamptz;

create index if not exists ix_decision_trace_agent  on public.decision_trace (agent_key, created_at desc);
create index if not exists ix_decision_trace_role   on public.decision_trace (role_id, created_at desc);
create index if not exists ix_decision_trace_dept   on public.decision_trace (department_id, created_at desc);
create index if not exists ix_decision_trace_status on public.decision_trace (outcome_status, created_at desc);

-- ---------------------------------------------------------------------------------------------
-- 2. THE WRITER — callable from an edge function, which is what did not exist
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_write_decision_trace(p jsonb)
returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare
  v_id       uuid;
  v_agent    text := nullif(p->>'agent_key','');
  v_role     text;
  v_dept     text;
  v_mgr      text;
  v_dobj     text;
  v_corr     uuid := coalesce(nullif(p->>'correlation_id','')::uuid, gen_random_uuid());
begin
  if v_agent is null then
    raise exception 'fn_write_decision_trace: agent_key is required. A trace that cannot name who decided is not evidence.';
  end if;

  -- Identity is resolved SERVER-SIDE from the roster. A model cannot label its own trace with
  -- someone else's role, which is the whole point of separating role_id from agent_key.
  select a.department, a.manager_key, d.north_star
    into v_dept, v_mgr, v_dobj
    from org_agents a left join org_departments d on d.dept_key = a.department
   where a.agent_key = v_agent;

  v_role := coalesce(nullif(p->>'role_id',''),
                     (select i.packaged_role_id from org_role_identity i
                       where i.agent_key = v_agent order by i.packaged_role_id limit 1));

  insert into decision_trace (
    correlation_id, entity_type, entity_id, decision_type, proposed_by, decided_by,
    policy_keys, knowledge_refs, evidence_refs, alternatives, assumptions, risk,
    confidence, authority_result, decision, outcome_status,
    task_id, agent_key, role_id, department_id, manager_id, task_class,
    company_objective, department_objective, relevant_kpi,
    knowledge_versions, source_freshness, tools_requested, tools_executed, tool_result_refs,
    uncertainty, escalation_decision, proposed_action, expected_outcome, review_date,
    model, provider, input_tokens, output_tokens, estimated_cost_aed, final_status
  ) values (
    v_corr,
    coalesce(nullif(p->>'entity_type',''),'agent_task'),
    nullif(p->>'entity_id',''),
    coalesce(nullif(p->>'decision_type',''),'agent_decision'),
    v_agent,
    coalesce(nullif(p->>'decided_by',''), v_agent),
    coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p->'policy_keys','[]'::jsonb)) x), '{}'),
    coalesce(p->'knowledge_refs','[]'::jsonb),
    coalesce(p->'evidence_refs','[]'::jsonb),
    coalesce(p->'alternatives','[]'::jsonb),
    coalesce(p->'assumptions','[]'::jsonb),
    coalesce(p->'risk','{}'::jsonb),
    nullif(p->>'confidence','')::numeric,
    coalesce(p->'authority_result','{}'::jsonb),
    coalesce(p->'decision','{}'::jsonb),
    coalesce(nullif(p->>'outcome_status',''),'pending'),
    nullif(p->>'task_id',''), v_agent, v_role, v_dept, v_mgr, nullif(p->>'task_class',''),
    -- The canonical company objective, read from the row that owns it rather than restated here:
    -- company_goals.revenue_annual = "Reach AED 1,000,000 annual revenue", target 1000000 AED.
    coalesce(nullif(p->>'company_objective',''),
             (select g.goal || ' (' || g.target_value::text || ' ' || coalesce(g.unit,'') || ')'
                from company_goals g where g.key = 'revenue_annual' and g.active limit 1)),
    coalesce(nullif(p->>'department_objective',''), v_dobj),
    nullif(p->>'relevant_kpi',''),
    coalesce(p->'knowledge_versions','{}'::jsonb),
    coalesce(p->'source_freshness','{}'::jsonb),
    coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p->'tools_requested','[]'::jsonb)) x), '{}'),
    coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p->'tools_executed','[]'::jsonb)) x), '{}'),
    coalesce(p->'tool_result_refs','[]'::jsonb),
    nullif(p->>'uncertainty',''), nullif(p->>'escalation_decision',''),
    nullif(p->>'proposed_action',''), nullif(p->>'expected_outcome',''),
    nullif(p->>'review_date','')::date,
    nullif(p->>'model',''), nullif(p->>'provider',''),
    nullif(p->>'input_tokens','')::integer, nullif(p->>'output_tokens','')::integer,
    nullif(p->>'estimated_cost_aed','')::numeric, nullif(p->>'final_status','')
  ) returning id into v_id;

  return v_id;
end $$;
revoke all on function public.fn_write_decision_trace(jsonb) from public;
grant execute on function public.fn_write_decision_trace(jsonb) to service_role;

-- ---------------------------------------------------------------------------------------------
-- 3. THE PATH THAT COULD NOT FIRE
--    os_api inserts agent_actions with decided_at already set. `after update of decided_at` is
--    structurally unable to see that. This is the second instance of the same defect shape in this
--    codebase and it is why the trigger looked healthy while the table stayed empty.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_agent_action_trace_ins()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.decided_at is not null then
    perform public.fn_agent_action_trace_row(new);
  end if;
  return new;
end $$;

-- Shared body so the INSERT and UPDATE paths can never drift apart.
create or replace function public.fn_agent_action_trace_row(a public.agent_actions)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_ids text[]; v_id uuid;
begin
  -- knowledge actually retrieved by this agent near the decision, from the recording table
  select coalesce(array_agg(distinct k), '{}') into v_ids
    from agent_context_retrieval r, unnest(r.knowledge_ids) k
   where r.agent_key = a.agent
     and r.created_at between a.decided_at - interval '30 minutes' and a.decided_at + interval '1 minute';

  select public.fn_write_decision_trace(jsonb_build_object(
    'agent_key',       a.agent,
    'entity_type',     coalesce(a.target_table,'agent_action'),
    'entity_id',       coalesce(a.target_id::text, a.id::text),
    'decision_type',   a.kind,
    'decided_by',      coalesce(a.decided_by, a.agent),
    'task_id',         a.id::text,
    'confidence',      a.confidence::text,
    'risk',            jsonb_build_object('tier', a.risk, 'escalated', a.escalated),
    'evidence_refs',   coalesce(a.evidence, '[]'::jsonb),
    'alternatives',    coalesce(a.alternatives, '[]'::jsonb),
    'assumptions',     coalesce(a.assumptions, '[]'::jsonb),
    'knowledge_refs',  to_jsonb(v_ids),
    'proposed_action', a.recommendation,
    'expected_outcome',a.expected_impact,
    'escalation_decision', case when a.escalated then 'escalated' else 'within_authority' end,
    'outcome_status',  case when a.status in ('done','approved') then 'accepted'
                            when a.status in ('rejected','dismissed') then 'rejected'
                            else 'pending' end,
    'final_status',    a.status
  )) into v_id;
  return v_id;
end $$;

drop trigger if exists z90_agent_action_decision_trace_ins on public.agent_actions;
create trigger z90_agent_action_decision_trace_ins
  after insert on public.agent_actions
  for each row when (new.decided_at is not null)
  execute function public.fn_agent_action_trace_ins();

-- ---------------------------------------------------------------------------------------------
-- 4. IMMUTABILITY — a runtime agent must not be able to rewrite completed evidence
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_decision_trace_immutable()
returns trigger language plpgsql set search_path = public as $$
begin
  if old.sealed_at is not null then
    -- Only the outcome may be graded after sealing. Everything the decision was BASED on is frozen.
    if (new.decision        is distinct from old.decision)
    or (new.evidence_refs   is distinct from old.evidence_refs)
    or (new.knowledge_refs  is distinct from old.knowledge_refs)
    or (new.tool_result_refs is distinct from old.tool_result_refs)
    or (new.confidence      is distinct from old.confidence)
    or (new.authority_result is distinct from old.authority_result)
    or (new.agent_key       is distinct from old.agent_key)
    or (new.role_id         is distinct from old.role_id)
    or (new.proposed_action is distinct from old.proposed_action) then
      raise exception 'decision_trace % is sealed. Evidence, confidence, authority and identity cannot be edited after the fact; grade the outcome instead.', old.id;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists a00_decision_trace_immutable on public.decision_trace;
create trigger a00_decision_trace_immutable
  before update on public.decision_trace
  for each row execute function public.fn_decision_trace_immutable();

-- Seal a trace once its decision is final. Called by the runtime after the answer is committed.
create or replace function public.fn_seal_decision_trace(p_id uuid)
returns boolean language sql volatile security definer set search_path = public as $$
  update decision_trace set sealed_at = now() where id = p_id and sealed_at is null returning true;
$$;
revoke all on function public.fn_seal_decision_trace(uuid) from public;
grant execute on function public.fn_seal_decision_trace(uuid) to service_role;

-- ---------------------------------------------------------------------------------------------
-- 5. THE READER — so these traces are not write-only
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_management_decision_review(
  p_department text default null, p_days integer default 7, p_limit integer default 100)
returns table (
  trace_id uuid, decided_at timestamptz, agent_key text, role_id text, department_id text,
  manager_id text, decision_type text, proposed_action text, confidence numeric,
  escalation_decision text, tools_requested text[], tools_executed text[],
  knowledge_count integer, evidence_count integer, review_date date,
  outcome_status text, final_status text, sealed boolean,
  gap text)
language sql stable security definer set search_path = public as $$
  select t.id, t.created_at, t.agent_key, t.role_id, t.department_id, t.manager_id,
         t.decision_type, t.proposed_action, t.confidence, t.escalation_decision,
         t.tools_requested, t.tools_executed,
         coalesce(jsonb_array_length(t.knowledge_refs),0), coalesce(jsonb_array_length(t.evidence_refs),0),
         t.review_date, t.outcome_status, t.final_status, t.sealed_at is not null,
         -- name what is missing rather than presenting an incomplete trace as complete
         nullif(concat_ws('; ',
           case when t.role_id is null                                 then 'no canonical role' end,
           case when coalesce(jsonb_array_length(t.evidence_refs),0)=0 then 'no evidence' end,
           case when t.confidence is null                              then 'no confidence' end,
           case when t.escalation_decision is null                     then 'no authority decision' end,
           case when t.review_date is null                             then 'no review date' end,
           case when t.final_status is null                            then 'no output status' end), '')
  from decision_trace t
  where (p_department is null or t.department_id = p_department)
    and t.created_at > now() - make_interval(days => greatest(p_days,1))
  order by t.created_at desc
  limit greatest(p_limit,1);
$$;
revoke all on function public.fn_management_decision_review(text,integer,integer) from public;
grant execute on function public.fn_management_decision_review(text,integer,integer) to service_role;

-- Completeness monitor. Target: zero rows.
create or replace view public.v_decision_trace_incomplete as
  select id, created_at, agent_key, role_id, department_id, decision_type,
         role_id is null                                  as missing_role,
         coalesce(jsonb_array_length(evidence_refs),0)=0  as missing_evidence,
         escalation_decision is null                      as missing_authority,
         final_status is null                             as missing_output_status
  from decision_trace
  where role_id is null
     or coalesce(jsonb_array_length(evidence_refs),0)=0
     or escalation_decision is null
     or final_status is null;
comment on view public.v_decision_trace_incomplete is
  'V3 remediation acceptance gate: zero traces missing role, evidence, authority or output status.';

commit;
