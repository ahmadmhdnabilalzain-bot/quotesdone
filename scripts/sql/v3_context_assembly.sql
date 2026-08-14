-- The V3 assembler is a distinct name: fn_agent_context already exists in two text-returning
-- overloads that every edge function calls. A third overload of the same name would have been
-- resolvable by argument count today and ambiguous the first time a default changed.
-- Stage 5 — one authoritative context-assembly path.
--
-- Before this, an agent's prompt was built from agent_knowledge rows filtered by agent_key
-- and nothing else: no department inheritance, no role identity, no task class, no category,
-- no freshness, no budget, and no record of what was retrieved. fn_agent_context is the one
-- path that assembles a task-time context and names every record it used, so the decision
-- trace can carry the knowledge ids instead of a prose summary.
--
-- Deterministic rules (authority, KPI definitions, decision playbooks, policy) are returned
-- as structured rows from SQL, never from a similarity search. Narrative is ranked lexically
-- against the task text and cut to the caller's character budget.

-- One narrative slice: deterministic filters first (layer, scope, runtime eligibility,
-- supersession), lexical ranking second, and a hard character budget last. Returns the
-- record ids alongside the text so the caller can record what it actually read.
create or replace function fn_context_slice(
  p_dept      text,
  p_role_ids  text[],
  p_category  text,
  p_layer     text,
  p_q         tsquery,
  p_budget    integer
) returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with candidate as (
    select record_id, title, content, version, source_freshness, effective_date, review_after,
           layer, record_type,
           case when p_q is null then 0 else ts_rank(tsv, p_q) end as rank
      from ops_knowledge
     where runtime_eligible
       and supersession_state = 'current'
       and layer = p_layer
       and (
         (p_layer = 'company_core'        and scope_type = 'company')
      or (p_layer = 'department_shared'   and dept_key = p_dept)
      or (p_layer = 'role_specific'       and role_key = any(coalesce(p_role_ids, '{}')))
      or (p_layer = 'category_specialist' and category_key = p_category)
       )
       and (p_q is null or tsv @@ p_q or true)
  ), ranked as (
    select *, sum(least(length(content), 1800)) over (order by rank desc, record_id
                                                      rows between unbounded preceding and current row) as running
      from candidate
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'record_id', record_id, 'title', title, 'layer', layer, 'record_type', record_type,
           'version', version, 'source_freshness', source_freshness,
           'review_after', review_after,
           'content', left(content, 1800)) order by rank desc, record_id), '[]'::jsonb)
    from ranked
   where running <= greatest(p_budget, 1800);
$$;

revoke all on function fn_context_slice(text, text[], text, text, tsquery, integer) from public;

create or replace function fn_agent_context_v3(
  p_agent_key    text,
  p_task_class   text default null,
  p_task_text    text default null,
  p_category_key text default null,
  p_budget_chars integer default 24000
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
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

  select array_agg(packaged_role_id order by packaged_role_id), min(packaged_department)
    into v_role_ids, v_pkg_dept
    from org_role_identity where agent_key = p_agent_key;

  -- 1. IDENTITY — who the agent is, who it reports to, what it may decide.
  v_identity := jsonb_build_object(
    'agent_key', v_agent.agent_key,
    'title', coalesce(v_agent.title, v_agent.role),
    'department', v_agent.department,
    'department_name', v_agent.dept_name,
    'department_charter', v_agent.charter,
    'department_north_star', v_agent.north_star,
    'manager', v_agent.manager_key,
    'seniority', v_agent.seniority,
    'responsibilities', v_agent.responsibilities,
    'packaged_role_ids', coalesce(to_jsonb(v_role_ids), '[]'::jsonb),
    'packaged_department', v_pkg_dept,
    'readiness', (select jsonb_agg(distinct readiness) from org_role_identity where agent_key = p_agent_key),
    'authority', coalesce((
      select jsonb_agg(jsonb_build_object('action_class', action_class, 'max_tier', max_tier,
                                          'threshold_aed', threshold_aed))
        from org_authority where dept_key = v_agent.department), '[]'::jsonb),
    'max_open_tasks', v_agent.max_open_tasks);

  if p_task_text is not null and length(p_task_text) > 1 then
    v_q := websearch_to_tsquery('english', p_task_text);
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
         or (scope_type = 'department' and dept_key = v_agent.department)
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
                 -- 'validated' only. A proposed lesson and an author-verified note are not the
                 -- same thing as a lesson someone other than its author has confirmed.
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
         and (scope_type = 'company' or dept_key = v_agent.department)
       limit 12), '[]'::jsonb));

  -- 6. TOOLS the agent is actually allowed to execute.
  v_out := v_out || jsonb_build_object('tools', coalesce((
      select jsonb_agg(jsonb_build_object('action_class', action_class, 'kind', kind,
                                          'risk_tier', risk_tier, 'reversible', reversible,
                                          'required_authority', required_authority,
                                          'notifies_human', notifies_human))
        from org_action_executor
       where active and (department = v_agent.department or target = p_agent_key)
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
    -- The current company objective is a live fact, not a knowledge file: it is read from
    -- company_goals every time a context is assembled.
    --
    -- The first version of this filtered `horizon = 'company'`. company_goals holds 'year_1'
    -- and 'quarter' and has never held 'company', so every context said the objective was []
    -- — a filter on a value no path writes. The agent's own department's goals come first,
    -- then the financial ones, which is where the AED 1,000,000 revenue target lives.
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
end $$;

revoke all on function fn_agent_context_v3(text, text, text, text, integer) from public;
grant execute on function fn_agent_context_v3(text, text, text, text, integer) to service_role;
