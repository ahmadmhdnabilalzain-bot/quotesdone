-- V3 REMEDIATION — fix found by running the check rather than by reading it.
--
-- v_decision_trace_incomplete and fn_management_decision_review both called
-- jsonb_array_length(evidence_refs) unguarded. decision_trace.evidence_refs defaults to '[]' but
-- pre-remediation writers stored a jsonb OBJECT there, and jsonb_array_length raises
-- "22023: cannot get array length of a non-array" on those rows. The effect is worse than a wrong
-- number: the completeness monitor ERRORS OUT, so the gate that is supposed to report incomplete
-- traces reports nothing at all — and an erroring check reads like a passing one to anything that
-- only looks at row count.
--
-- Guarded with jsonb_typeof. A non-array evidence_refs now counts as ZERO evidence, which is the
-- honest reading: it is not a list of evidence references.

begin;

create or replace view public.v_decision_trace_incomplete as
  select id, created_at, agent_key, role_id, department_id, decision_type,
         role_id is null as missing_role,
         (jsonb_typeof(evidence_refs) is distinct from 'array'
          or coalesce(jsonb_array_length(evidence_refs),0) = 0) as missing_evidence,
         escalation_decision is null as missing_authority,
         final_status is null       as missing_output_status
  from decision_trace
  where role_id is null
     or jsonb_typeof(evidence_refs) is distinct from 'array'
     or coalesce(jsonb_array_length(evidence_refs),0) = 0
     or escalation_decision is null
     or final_status is null;
comment on view public.v_decision_trace_incomplete is
  'V3 remediation acceptance gate: zero traces missing role, evidence, authority or output status. evidence_refs that is not a JSON array counts as no evidence.';

create or replace function public.fn_management_decision_review(
  p_department text default null, p_days integer default 7, p_limit integer default 100)
returns table (
  trace_id uuid, decided_at timestamptz, agent_key text, role_id text, department_id text,
  manager_id text, decision_type text, proposed_action text, confidence numeric,
  escalation_decision text, tools_requested text[], tools_executed text[],
  knowledge_count integer, evidence_count integer, review_date date,
  outcome_status text, final_status text, sealed boolean, gap text)
language sql stable security definer set search_path = public as $$
  with t as (
    select *,
           case when jsonb_typeof(knowledge_refs)='array' then jsonb_array_length(knowledge_refs) else 0 end as kn,
           case when jsonb_typeof(evidence_refs) ='array' then jsonb_array_length(evidence_refs)  else 0 end as ev
      from decision_trace
     where (p_department is null or department_id = p_department)
       and created_at > now() - make_interval(days => greatest(p_days,1))
  )
  select t.id, t.created_at, t.agent_key, t.role_id, t.department_id, t.manager_id,
         t.decision_type, t.proposed_action, t.confidence, t.escalation_decision,
         t.tools_requested, t.tools_executed, t.kn, t.ev,
         t.review_date, t.outcome_status, t.final_status, t.sealed_at is not null,
         nullif(concat_ws('; ',
           case when t.role_id is null            then 'no canonical role' end,
           case when t.ev = 0                     then 'no evidence' end,
           case when t.confidence is null         then 'no confidence' end,
           case when t.escalation_decision is null then 'no authority decision' end,
           case when t.review_date is null        then 'no review date' end,
           case when t.final_status is null       then 'no output status' end), '')
  from t order by t.created_at desc limit greatest(p_limit,1);
$$;

commit;
