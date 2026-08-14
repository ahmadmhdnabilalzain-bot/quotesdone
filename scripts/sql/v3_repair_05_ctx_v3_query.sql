-- V3 REMEDIATION — Stage 4. fn_agent_context_v3, patched in place.
-- The ONLY change from the definition read back off staging on 14 Aug 2026 is the task-query
-- builder: websearch_to_tsquery('english', p_task_text) -> public.fn_task_tsquery(p_task_text).
-- Occurrences replaced: 1.
--
-- websearch_to_tsquery ANDs every word of the task sentence. Measured: 'cash reserve budget
-- variance' -> 'cash' & 'reserv' & 'budget' & 'varianc' -> 0 of 8,256 rows. The same words ORed
-- match 49. That is the whole of KNOWLEDGE_NOT_RETRIEVED (1,706 questions), and it is why
-- fn_context_slice had 'or true' bolted onto its filter to keep context from coming back empty.
--
-- Body below is staging's verified definition, not a retype.

CREATE OR REPLACE FUNCTION public.fn_agent_context_v3(p_agent_key text, p_task_class text DEFAULT NULL::text, p_task_text text DEFAULT NULL::text, p_category_key text DEFAULT NULL::text, p_budget_chars integer DEFAULT 24000)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_agent      record;
  v_identity   jsonb;
  v_pkg_dept   text;
  v_role_ids   text[];
  v_out        jsonb;
  v_ids        text[] := '{}';
  v_used       integer := 0;
  v_budget     integer := greatest(coalesce(p_budget_chars, 24000), 2000);
  v_q          tsquery;
  v_scope      text[];
  v_role       record;
begin
  select a.agent_key, a.department, a.role, a.title, a.manager_key, a.seniority,
         a.responsibilities, a.max_open_tasks, a.active, d.name dept_name, d.charter, d.north_star
    into v_agent
    from org_agents a
    left join org_departments d on d.dept_key = a.department
   where a.agent_key = p_agent_key;

  if v_agent.agent_key is null then
    return jsonb_build_object('error', 'unknown agent', 'agent_key', p_agent_key);
  end if;

  v_scope := public.fn_dept_scope(v_agent.department);

  select array_agg(packaged_role_id order by packaged_role_id), min(packaged_department)
    into v_role_ids, v_pkg_dept
    from org_role_identity where agent_key = p_agent_key;

  -- The canonical role. Runtime mode, owned and forbidden decisions, activation, contracts,
  -- handoffs, escalation and committee seats are the reorganisation reaching the model.
  select r.role_id, r.display_name, r.runtime_mode, r.authority_level, r.owned_decisions,
         r.forbidden_decisions, r.activation_conditions, r.output_contracts, r.handoff_targets,
         r.escalation_targets, r.manager_role_id, r.budget_limit, r.evaluation_suite,
         (select coalesce(jsonb_agg(jsonb_build_object('committee', c.committee_key, 'seat', c.seat)
                                    order by c.committee_key), '[]'::jsonb)
            from org_role_committee c where c.role_id = r.role_id) as committees
    into v_role
    from org_role r where r.runtime_agent_key = p_agent_key and r.status = 'active';

  -- 1. IDENTITY — who the agent is, who it reports to, what it may decide.
  v_identity := jsonb_build_object(
    'agent_key', v_agent.agent_key,
    'title', coalesce(v_agent.title, v_agent.role),
    'department', v_agent.department,
    'department_name', v_agent.dept_name,
    'department_charter', v_agent.charter,
    'department_north_star', v_agent.north_star,
    'department_knowledge_scope', to_jsonb(v_scope),
    'manager', v_agent.manager_key,
    'seniority', v_agent.seniority,
    'responsibilities', v_agent.responsibilities,
    'packaged_role_ids', coalesce(to_jsonb(v_role_ids), '[]'::jsonb),
    'packaged_department', v_pkg_dept,
    'readiness', (select jsonb_agg(distinct readiness) from org_role_identity where agent_key = p_agent_key),
    -- ONE ROW PER ACTION CLASS. Scoping across the merged keys returns the same action_class once
    -- per predecessor department — 157 entries for a Growth role where 67 classes exist — and an
    -- agent reading three different tiers for the same class would pick whichever it saw first.
    -- Most restrictive wins: advisory < gated < supervised < autonomous.
    'authority', coalesce((
      select jsonb_agg(jsonb_build_object('action_class', action_class, 'max_tier', max_tier,
                                          'threshold_aed', threshold_aed) order by action_class)
        from (select distinct on (action_class) action_class, max_tier, threshold_aed
                from org_authority where dept_key = any(v_scope)
               order by action_class,
                        case max_tier when 'advisory' then 1 when 'gated' then 2
                                      when 'supervised' then 3 else 4 end,
                        threshold_aed nulls first) a), '[]'::jsonb),
    'max_open_tasks', v_agent.max_open_tasks)
    || case when v_role.role_id is null then '{}'::jsonb else jsonb_build_object(
         'role_id', v_role.role_id,
         'role_display_name', v_role.display_name,
         'runtime_mode', v_role.runtime_mode,
         'authority_level', v_role.authority_level,
         'owned_decisions', to_jsonb(v_role.owned_decisions),
         'forbidden_decisions', to_jsonb(v_role.forbidden_decisions),
         'activation_conditions', v_role.activation_conditions,
         'output_contracts', to_jsonb(v_role.output_contracts),
         'handoff_targets', to_jsonb(v_role.handoff_targets),
         'escalation_targets', to_jsonb(v_role.escalation_targets),
         'manager_role_id', v_role.manager_role_id,
         'budget_limit_aed', v_role.budget_limit,
         'evaluation_suite', v_role.evaluation_suite,
         'committees', v_role.committees) end;

  if p_task_text is not null and length(p_task_text) > 1 then
    v_q := public.fn_task_tsquery(p_task_text);
  end if;

  -- 2. DETERMINISTIC RULES — structured, complete, never similarity-ranked.
  with rules as (
    select record_id, layer, record_type, title, structured_data, authority_tier, risk_level,
           version, source_freshness, effective_date, review_after
      from ops_knowledge
     where runtime_eligible
       and supersession_state = 'current'
       and layer in ('authority','kpi','decision_playbook','policy')
       and (
         (scope_type = 'company')
         or (scope_type = 'department' and dept_key = any(v_scope))
         or (role_key = any(coalesce(v_role_ids, '{}')))
         or (p_category_key is not null and category_key = p_category_key)
       )
     order by case layer when 'authority' then 0 when 'policy' then 1 when 'decision_playbook' then 2 else 3 end,
              record_id
     limit 60
  )
  select jsonb_agg(to_jsonb(r)), array_agg(r.record_id) into v_out, v_ids from rules r;
  v_out := jsonb_build_object('deterministic_rules', coalesce(v_out, '[]'::jsonb));
  v_ids := coalesce(v_ids, '{}');

  -- 3. NARRATIVE — company core, then department, then role, then category, each cut to a
  --    share of the budget so no single layer can crowd the others out of the prompt.
  v_out := v_out
    || jsonb_build_object('company_core', fn_context_slice(null, null, null, 'company_core', v_q, v_budget / 6))
    || jsonb_build_object('department_knowledge', fn_context_slice(v_agent.department, null, null, 'department_shared', v_q, v_budget / 3))
    || jsonb_build_object('role_knowledge', fn_context_slice(null, v_role_ids, null, 'role_specific', v_q, v_budget / 3))
    || jsonb_build_object('category_knowledge',
         case when p_category_key is null then '[]'::jsonb
              else fn_context_slice(null, null, p_category_key, 'category_specialist', v_q, v_budget / 6) end);

  -- 4. VALIDATED EXPERIENCE — only lessons a manager or evaluator has validated. A proposed
  --    lesson is deliberately invisible here; that is the whole point of the two states.
  v_out := v_out || jsonb_build_object('validated_experience', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'topic', topic, 'content', left(content, 1200),
                                          'confidence', confidence, 'valid_until', valid_until))
        from (select * from agent_knowledge
               where agent_key = p_agent_key
                 and layer = 'experience'
                 and validation_status = 'validated'
                 and (valid_until is null or valid_until >= current_date)
               order by coalesce(confidence, 0) desc, updated_at desc nulls last
               limit 8) e), '[]'::jsonb));

  -- 5. LIVE DATA BINDINGS — what the agent must fetch rather than remember. The binding is
  --    knowledge; the value is not, and is never cached here.
  v_out := v_out || jsonb_build_object('live_data_required', coalesce((
      select jsonb_agg(jsonb_build_object('record_id', record_id, 'title', title,
                                          'binding', structured_data))
        from ops_knowledge
       where record_type = 'live_data_binding' and runtime_eligible
         and supersession_state = 'current'
         and (scope_type = 'company' or dept_key = any(v_scope))
       limit 12), '[]'::jsonb));

  -- 6. TOOLS the agent is actually allowed to execute.
  v_out := v_out || jsonb_build_object('tools', coalesce((
      select jsonb_agg(jsonb_build_object('action_class', action_class, 'kind', kind,
                                          'risk_tier', risk_tier, 'reversible', reversible,
                                          'required_authority', required_authority,
                                          'notifies_human', notifies_human))
        from org_action_executor
       where active and (department = any(v_scope) or target = p_agent_key)
       limit 30), '[]'::jsonb));

  -- collect every knowledge id the assembly actually used
  select v_ids || coalesce(array_agg(x), '{}') into v_ids
    from (select jsonb_array_elements(coalesce(v_out->'company_core','[]'::jsonb) ||
                                      coalesce(v_out->'department_knowledge','[]'::jsonb) ||
                                      coalesce(v_out->'role_knowledge','[]'::jsonb) ||
                                      coalesce(v_out->'category_knowledge','[]'::jsonb)) ->> 'record_id' x) s;

  return jsonb_build_object(
    'identity', v_identity,
    'task_class', p_task_class,
    'category_key', p_category_key,
    'company_objective', coalesce((
      select jsonb_agg(jsonb_build_object('key', key, 'goal', goal, 'metric', metric,
                                          'target', target_value, 'unit', unit, 'period', period,
                                          'owner_dept', owner_dept, 'horizon', horizon))
        from (select * from company_goals
               where active
               order by (owner_dept is not distinct from v_agent.department) desc,
                        (category = 'Financial') desc, sort
               limit 8) g), '[]'::jsonb),
    'budget_chars', v_budget,
    'knowledge_ids', to_jsonb(v_ids),
    'knowledge_count', coalesce(array_length(v_ids, 1), 0),
    'assembled_at', now()
  ) || v_out;
end
$function$
;
