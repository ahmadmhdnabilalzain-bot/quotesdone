-- REORGANISING THE AGENT COMPANY - 30: the last seven, and two of them are safety gates.
--
-- The final routines from the identity inventory that genuinely compare an org_agents.agent_key.
--
--   fn_agent_tools              decides WHICH TOOLS an employee may hold. It matched
--                               a.agent_key = p_agent_key exactly, so an employee addressed by an
--                               alias, a job title or a packaged role id was granted NO TOOLS AT
--                               ALL - which presents as "the tools are not connected" for that
--                               employee and as a fully-connected registry for everyone else.
--   fn_unsafe_escalation_route  resolves the department an UNSAFE action escalates to. An aliased
--                               actor produced no department, so the escalation had nowhere to go.
--                               A safety route that silently loses its destination is worse than
--                               one that refuses.
--   fn_handoff_respond/close    authorise the receiving side AND write accepted_by, closed_by and
--                               decided_by. Raw matching meant an aliased receiver could not accept
--                               its own handoff, and where it could, the ledger recorded the
--                               spelling rather than the employee.
--   fn_handoff_amend/notify     same shape; notify additionally REFUSES when the agent is unknown,
--                               so an alias made the notification fail closed against a real person.
--   fn_revenue_cascade          p_role is matched against role_id or runtime_agent_key; a job title
--                               matched neither, so the cascade returned nothing for that role.
--
-- One line each for the plpgsql routines, as the first statement after begin. fn_agent_tools is
-- LANGUAGE sql and is wrapped at its single comparison site.

begin;

-- fn_handoff_amend(p_id bigint, p_agent_key text, p_patch jsonb)
CREATE OR REPLACE FUNCTION public.fn_handoff_amend(p_id bigint, p_agent_key text, p_patch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c          handoff_contract%rowtype;
  v_evidence jsonb;
  v_accept   text[];
  v_deadline timestamptz;
  v_owner    text;
  v_gaps     text[] := '{}';
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  select * into c from handoff_contract where id = p_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no handoff contract with that id');
  end if;
  if c.status = 'closed' then
    return jsonb_build_object('ok', false, 'reason', 'a closed handoff cannot be amended');
  end if;
  if not exists (select 1 from org_agents
                  where agent_key = p_agent_key and active and department = c.from_dept) then
    return jsonb_build_object('ok', false, 'reason', 'only an active employee of the originating department may amend',
                              'from_dept', c.from_dept);
  end if;

  v_evidence := case when jsonb_typeof(p_patch->'evidence') = 'array' then p_patch->'evidence' else c.evidence end;
  v_accept   := case when jsonb_typeof(p_patch->'acceptance_criteria') = 'array'
                     then public.fn_handoff_criteria(p_patch->'acceptance_criteria') else c.acceptance_criteria end;
  v_owner    := coalesce(nullif(btrim(p_patch->>'accountable_owner'), ''), p_agent_key);
  begin v_deadline := coalesce((p_patch->>'deadline')::timestamptz, c.deadline);
  exception when others then v_deadline := c.deadline; end;

  update handoff_contract
     set evidence = v_evidence,
         acceptance_criteria = v_accept,
         deadline = v_deadline,
         accountable_owner = v_owner,          -- guard refuses a blank, a stranger or an ex-employee
         status = case when c.status in ('rejected','returned') then 'open' else c.status end,
         return_status = case when c.status in ('rejected','returned') then null else c.return_status end,
         return_reason = case when c.status in ('rejected','returned') then null else c.return_reason end
   where id = p_id;

  -- Back into the receiver's inbox if the rejection had taken it out.
  update agent_actions
     set status = 'needs_review', decided_at = null, decided_by = null,
         detail = coalesce(detail, '{}'::jsonb) || jsonb_build_object('amended_at', now(), 'amended_by', p_agent_key)
   where id = c.action_id and c.status in ('rejected','returned');

  if jsonb_array_length(v_evidence) = 0 then v_gaps := v_gaps || 'evidence'::text; end if;
  if cardinality(v_accept) = 0 then v_gaps := v_gaps || 'acceptance_criteria'::text; end if;

  return jsonb_build_object('ok', true, 'id', p_id,
    'status', case when c.status in ('rejected','returned') then 'open' else c.status end,
    'accountable_owner', v_owner, 'owner_changed', v_owner is distinct from c.accountable_owner,
    'complete', array_length(v_gaps, 1) is null, 'missing_for_acceptance', to_jsonb(v_gaps));
end $function$
;

-- fn_handoff_close(p_id bigint, p_agent_key text, p_closure_evidence jsonb)
CREATE OR REPLACE FUNCTION public.fn_handoff_close(p_id bigint, p_agent_key text, p_closure_evidence jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c         handoff_contract%rowtype;
  v_ev      jsonb := case when jsonb_typeof(p_closure_evidence) = 'array' then p_closure_evidence else '[]'::jsonb end;
  v_missing text[];
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  select * into c from handoff_contract where id = p_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no handoff contract with that id');
  end if;
  if c.status <> 'accepted' then
    return jsonb_build_object('ok', false, 'reason', 'only an accepted handoff can be closed', 'status', c.status);
  end if;
  if not exists (select 1 from org_agents
                  where agent_key = p_agent_key and active and department = c.to_dept) then
    return jsonb_build_object('ok', false, 'reason', 'only an active employee of the receiving department may close it',
                              'to_dept', c.to_dept);
  end if;

  select coalesce(array_agg(x), '{}'::text[]) into v_missing
    from unnest(c.closure_criteria) x
   where not exists (
     select 1 from jsonb_array_elements(v_ev) e
      where btrim(coalesce(e->>'criterion', '')) = btrim(x)
        and coalesce(btrim(e->>'evidence'), '') <> '');
  if array_length(v_missing, 1) is not null then
    return jsonb_build_object('ok', false, 'reason', 'closure criteria without recorded proof',
      'unproven', to_jsonb(v_missing), 'declared', to_jsonb(c.closure_criteria));
  end if;

  update handoff_contract
     set status = 'closed', return_status = 'closed', closure_evidence = v_ev,
         closed_by = p_agent_key, closed_at = now()
   where id = p_id;

  update agent_actions
     set status = 'done', decided_at = now(), decided_by = p_agent_key,
         detail = coalesce(detail, '{}'::jsonb)
                  || jsonb_build_object('outcome', 'closed', 'closure_evidence', v_ev, 'closed_at', now())
   where id = c.action_id;

  perform public.fn_handoff_notify(c.accountable_owner,
    'Handoff #'||p_id||' ("'||c.purpose||'") was CLOSED by '||p_agent_key||' ('||c.to_dept||'). '
    ||'Proof recorded for '||cardinality(c.closure_criteria)||' closure criteria: '||v_ev::text,
    'handoff_contract:'||p_id);

  return jsonb_build_object('ok', true, 'id', p_id, 'status', 'closed', 'closed_by', p_agent_key,
    'criteria_proven', cardinality(c.closure_criteria), 'closure_evidence', v_ev);
end $function$
;

-- fn_handoff_notify(p_agent_key text, p_content text, p_source text)
CREATE OR REPLACE FUNCTION public.fn_handoff_notify(p_agent_key text, p_content text, p_source text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  if coalesce(btrim(p_agent_key), '') = ''
     or not exists (select 1 from org_agents where agent_key = p_agent_key) then
    return false;
  end if;
  insert into agent_memory (agent_key, kind, content, source, importance)
  values (p_agent_key, 'learned', left(p_content, 2000), p_source, 4);
  return true;
end $function$
;

-- fn_handoff_respond(p_id bigint, p_agent_key text, p_decision text, p_reason text)
CREATE OR REPLACE FUNCTION public.fn_handoff_respond(p_id bigint, p_agent_key text, p_decision text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c        handoff_contract%rowtype;
  v_dec    text := lower(btrim(coalesce(p_decision, '')));
  v_reason text := btrim(coalesce(p_reason, ''));
  v_gaps   text[] := '{}';
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  if v_dec not in ('accept','reject','return') then
    return jsonb_build_object('ok', false, 'reason', 'decision must be accept, reject or return');
  end if;
  select * into c from handoff_contract where id = p_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no handoff contract with that id');
  end if;
  if not exists (select 1 from org_agents
                  where agent_key = p_agent_key and active and department = c.to_dept) then
    return jsonb_build_object('ok', false, 'reason', 'only an active employee of the receiving department may answer',
                              'to_dept', c.to_dept);
  end if;

  if jsonb_array_length(c.evidence) = 0 then v_gaps := v_gaps || 'evidence'::text; end if;
  if cardinality(c.acceptance_criteria) = 0 then v_gaps := v_gaps || 'acceptance_criteria'::text; end if;

  if v_dec = 'accept' then
    if c.status <> 'open' then
      return jsonb_build_object('ok', false, 'reason', 'only an open handoff can be accepted', 'status', c.status);
    end if;
    -- REJECTABLE ON ARRIVAL: an incomplete handoff cannot be silently taken on.
    if array_length(v_gaps, 1) is not null then
      return jsonb_build_object('ok', false, 'reason', 'handoff is incomplete and cannot be accepted',
        'missing', to_jsonb(v_gaps), 'next', 'reject it with a reason, or ask the sender to amend it');
    end if;
    update handoff_contract
       set status = 'accepted', return_status = 'accepted',
           accepted_by = p_agent_key, accepted_at = now(), return_reason = nullif(v_reason, '')
     where id = p_id;
    perform public.fn_handoff_notify(c.accountable_owner,
      'Handoff #'||p_id||' ("'||c.purpose||'") was ACCEPTED by '||p_agent_key||' ('||c.to_dept||'). '
      ||'Due '||to_char(c.deadline, 'YYYY-MM-DD HH24:MI')||'. Closure criteria: '
      ||array_to_string(c.closure_criteria, ' | '),
      'handoff_contract:'||p_id);
    return jsonb_build_object('ok', true, 'id', p_id, 'status', 'accepted',
      'accepted_by', p_agent_key, 'deadline', c.deadline,
      'acceptance_criteria', to_jsonb(c.acceptance_criteria),
      'closure_criteria', to_jsonb(c.closure_criteria));
  end if;

  if v_reason = '' then
    return jsonb_build_object('ok', false, 'reason', 'a '||v_dec||' must state why');
  end if;

  if v_dec = 'reject' then
    if c.status <> 'open' then
      return jsonb_build_object('ok', false, 'reason', 'only an open handoff can be rejected', 'status', c.status);
    end if;
    update handoff_contract
       set status = 'rejected',
           return_status = case when array_length(v_gaps, 1) is not null
                                then 'rejected_incomplete' else 'rejected' end,
           return_reason = v_reason
     where id = p_id;
    -- The transport row leaves the receiver's inbox; the sender is told, in their own memory.
    update agent_actions
       set status = 'done', decided_at = now(), decided_by = p_agent_key,
           detail = coalesce(detail, '{}'::jsonb)
                    || jsonb_build_object('outcome', 'rejected', 'reason', left(v_reason, 1000),
                                          'missing', to_jsonb(v_gaps), 'rejected_at', now())
     where id = c.action_id;
    perform public.fn_handoff_notify(c.accountable_owner,
      'Handoff #'||p_id||' ("'||c.purpose||'") was REJECTED by '||p_agent_key||' ('||c.to_dept||'): '
      ||v_reason||case when array_length(v_gaps, 1) is not null
                       then '. Missing: '||array_to_string(v_gaps, ', ')||'. Amend and resubmit with fn_handoff_amend.'
                       else '' end,
      'handoff_contract:'||p_id);
    return jsonb_build_object('ok', true, 'id', p_id, 'status', 'rejected',
      'return_status', case when array_length(v_gaps, 1) is not null then 'rejected_incomplete' else 'rejected' end,
      'missing', to_jsonb(v_gaps), 'sender_notified', c.accountable_owner);
  end if;

  -- return: the receiver took it on, then found it cannot be finished as handed over.
  if c.status <> 'accepted' then
    return jsonb_build_object('ok', false, 'reason', 'only an accepted handoff can be returned for correction',
                              'status', c.status);
  end if;
  update handoff_contract
     set status = 'returned', return_status = 'returned_for_correction',
         return_reason = v_reason, returns_count = returns_count + 1
   where id = p_id;
  perform public.fn_handoff_notify(c.accountable_owner,
    'Handoff #'||p_id||' ("'||c.purpose||'") was RETURNED FOR CORRECTION by '||p_agent_key||': '||v_reason
    ||' Correct it with fn_handoff_amend; it goes back to '||c.to_dept||' as open.',
    'handoff_contract:'||p_id);
  return jsonb_build_object('ok', true, 'id', p_id, 'status', 'returned',
    'return_status', 'returned_for_correction', 'returns_count', c.returns_count + 1,
    'sender_notified', c.accountable_owner);
end $function$
;

-- fn_revenue_cascade(p_dept text, p_role text)
CREATE OR REPLACE FUNCTION public.fn_revenue_cascade(p_dept text, p_role text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_dept text;
  v_name text;
  v_north text;
  v_objectives jsonb;
  v_kpis jsonb;
  v_os jsonb;
  v_agents text[];
begin
  p_role := coalesce(public.fn_org_agent_resolve(p_role), p_role);
  if coalesce(p_dept,'') = '' then
    return jsonb_build_object('error','department_required');
  end if;

  select d.dept_key, d.name, d.north_star into v_dept, v_name, v_north
    from public.org_departments d where d.dept_key = lower(btrim(p_dept)) and d.active;

  if v_dept is null then
    select d.dept_key, d.name, d.north_star into v_dept, v_name, v_north
      from public.org_department_alias a
      join public.org_departments d on d.dept_key = a.dept_key and d.active
     where a.packaged_department = lower(btrim(p_dept)) and not a.is_second_home;
  end if;

  if v_dept is null then
    return jsonb_build_object(
      'error','unknown_department',
      'asked_for', p_dept,
      'known_canonical', (select jsonb_agg(dept_key order by dept_key)
                            from public.org_departments where active),
      'known_packaged',  (select jsonb_agg(distinct packaged_department)
                            from public.org_department_alias));
  end if;

  -- Department objectives. Every one reports whether it reconciles upward and whether it carries a
  -- number, separately — a linked objective with no target is a different problem from an unlinked
  -- one, and collapsing them is how 66 sentences passed for a cascade.
  select coalesce(jsonb_agg(x order by x->>'objective'), '[]'::jsonb) into v_objectives from (
    select jsonb_build_object(
      'objective',            o.objective,
      'horizon',              o.horizon,
      'reconciles_to_goal',   o.goal_key,
      'company_goal',         cg.goal,
      -- coalesced, not bare: `null = 'revenue_annual'` is NULL, and an objective that does not
      -- reach the revenue target must read as false, not as an unanswered question.
      'is_the_revenue_target', coalesce(o.goal_key = 'revenue_annual', false),
      'target_value',         o.target_value,
      'unit',                 o.unit,
      'measured',             o.actual_value is not null,
      'actual_value',         o.actual_value,
      'measured_at',          o.measured_at,
      'not_measured_reason', case
          when o.actual_value is not null then null
          when coalesce(o.measure_sql,'') = '' then 'no measure_sql recorded for this objective'
          else 'measure_sql present but has not produced a value; run fn_cascade_refresh()' end,
      'attainment_pct', case
          when o.actual_value is null or o.target_value is null or o.target_value = 0 then null
          else round(100.0 * o.actual_value / o.target_value, 1) end
    ) x
    from public.department_objective o
    left join public.company_goals cg on cg.key = o.goal_key and cg.active
   where o.dept_key = v_dept and o.active) s;

  select array_agg(distinct r.runtime_agent_key) into v_agents
    from public.org_role r
   where r.primary_department_id = v_dept and r.status = 'active'
     and r.runtime_agent_key is not null
     and (p_role is null or r.role_id = p_role or r.runtime_agent_key = p_role);

  -- The KPI -> department objective link is resolved on (this department, the goal the KPI names),
  -- not on employee_kpi.serves_objective — that column is a foreign key to os_objective, a
  -- different table. Where the department holds more than one objective against the same goal, all
  -- of them are listed and none is picked.
  select coalesce(jsonb_agg(x order by x->>'agent_key', x->>'kpi'), '[]'::jsonb) into v_kpis from (
    select jsonb_build_object(
      'agent_key',   k.agent_key,
      'kpi',         k.kpi,
      'metric',      k.metric,
      'class',       coalesce(k.kpi_class, public.fn_metric_class(k.kpi, k.metric, k.unit)),
      'class_source', case when k.kpi_class is not null then 'declared' else 'inferred' end,
      'target_value', k.target_value,
      'unit',        k.unit,
      'measured',    k.actual_value is not null,
      'actual_value', k.actual_value,
      'measured_at', k.measured_at,
      'not_measured_reason', case
          when k.actual_value is not null then null
          when k.no_measure_reason is not null then k.no_measure_reason
          when coalesce(k.measure_sql,'') = '' then 'no measure_sql recorded for this KPI'
          else 'measure_sql present but has not produced a value' end,
      'serves_company_goal',           k.serves_goal,
      'serves_department_objectives',  m.objectives,
      'connects_to_revenue_target',    coalesce(k.serves_goal = 'revenue_annual', false),
      'attainment_pct', case
          when k.actual_value is null or k.target_value is null or k.target_value = 0 then null
          else round(100.0 * k.actual_value / k.target_value, 1) end
    ) x
    from public.employee_kpi k
    left join lateral (
      select jsonb_agg(o.objective order by o.objective) as objectives
        from public.department_objective o
       where o.dept_key = v_dept and o.active and o.goal_key = k.serves_goal) m on true
   where k.active and k.agent_key = any(v_agents)) s;

  -- THE SECOND OBJECTIVE TABLE. os_objective is measured (a sweep populates actual_value) and
  -- carries no goal_key at all, so nothing in it reconciles to a company goal. Hiding it would
  -- make the cascade look complete while a department's most current numbers sat outside it.
  select coalesce(jsonb_agg(jsonb_build_object(
      'objective',    oo.objective,
      'measure',      oo.measure,
      'measured',     oo.actual_value is not null,
      'actual_value', oo.actual_value,
      'measured_at',  oo.measured_at,
      'reconciles_to_a_company_goal', false) order by oo.id), '[]'::jsonb)
    into v_os
    from public.os_objective oo
    join public.os_department od on od.os_key = oo.os_key
   where od.dept_key = v_dept and oo.active;

  return jsonb_build_object(
    'department',            v_dept,
    'department_name',       v_name,
    'asked_for',             p_dept,
    'role_filter',           p_role,
    'north_star',            v_north,
    'company_objective',     public.fn_revenue_trajectory(),
    'department_objectives', v_objectives,
    'operating_system_objectives', v_os,
    'operating_system_objectives_note',
      'A second objective table, measured but carrying no company goal_key. Listed so its numbers '
      ||'are visible; none of them reconciles upward, and that is a gap, not a link.',
    'role_kpis',             v_kpis,
    -- Counts, not a composite. There is deliberately no single number here: an average over items
    -- of which half are unmeasured is the exact instrument that reported 97.7% on a zero-revenue
    -- day, and management cannot act on it.
    'counts', jsonb_build_object(
      'department_objectives',                    jsonb_array_length(v_objectives),
      'department_objectives_linked_to_a_goal',
        (select count(*) from jsonb_array_elements(v_objectives) e
          where e->>'reconciles_to_goal' is not null),
      'department_objectives_on_the_revenue_target',
        (select count(*) from jsonb_array_elements(v_objectives) e
          where (e->>'is_the_revenue_target')::boolean),
      'department_objectives_measured',
        (select count(*) from jsonb_array_elements(v_objectives) e
          where (e->>'measured')::boolean),
      'role_kpis',                                jsonb_array_length(v_kpis),
      'role_kpis_measured',
        (select count(*) from jsonb_array_elements(v_kpis) e where (e->>'measured')::boolean),
      'role_kpis_connected_to_the_revenue_target',
        (select count(*) from jsonb_array_elements(v_kpis) e
          where (e->>'connects_to_revenue_target')::boolean),
      'role_kpis_that_are_activity_only',
        (select count(*) from jsonb_array_elements(v_kpis) e where e->>'class' = 'activity'),
      'role_kpis_unclassified',
        (select count(*) from jsonb_array_elements(v_kpis) e where e->>'class' = 'unclassified')),
    'before_you_reallocate',
      'Name the binding constraint first: select public.fn_binding_constraint(). Moving effort to a '
      ||'stage that is not binding changes this department''s activity and not the company''s revenue.');
end $function$
;

-- fn_unsafe_escalation_route(p_class_key text, p_actor text)
CREATE OR REPLACE FUNCTION public.fn_unsafe_escalation_route(p_class_key text, p_actor text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare c record; v_dept text; v_auth jsonb; v_esc jsonb; v_auto text;
begin
  p_actor := coalesce(public.fn_org_agent_resolve(p_actor), p_actor);
  select * into c from public.unsafe_class where class_key = p_class_key;
  if c.class_key is null then
    return jsonb_build_object('error', 'unknown unsafe class: ' || coalesce(p_class_key,'(null)'));
  end if;

  select a.department into v_dept from public.org_agents a where a.agent_key = p_actor and a.active;
  v_dept := coalesce(v_dept, 'exec');

  -- No action_class means no department delegation exists for this class: it is founder-level by
  -- construction, and saying so is more honest than resolving a tier for a class nobody mapped.
  if c.authority_action_class is not null then
    v_auth := public.fn_ops_authority_check(v_dept, c.authority_action_class, null,
                                            case when c.severity = 'critical' then 'critical' else null end);
  end if;

  -- SECOND, INDEPENDENT SIGNAL. fn_autonomy_class holds the hard rails written as a per-kind
  -- disposition rather than a per-department tier: anything matching money, deletion or supplier
  -- approval returns 'founder' regardless of what any department was delegated. It is consulted,
  -- not replaced — where the two disagree the more restrictive one wins, which is why 'founder'
  -- forces approval even if the department tier came back permissive.
  v_auto := public.fn_autonomy_class(c.authority_action_class, null, null);

  v_esc := public.fn_should_escalate(jsonb_build_object(
             'actor', p_actor,
             'kind', 'unsafe_block',
             'category', c.class_key,
             'text', c.title || '. ' || c.mechanism));

  return jsonb_build_object(
    'class_key', c.class_key,
    'requires_human_authority', c.requires_human_authority,
    'department', v_dept,
    'action_class', c.authority_action_class,
    'effective_tier', coalesce(v_auth->>'effective_tier', 'gated'),
    'requires_approval', coalesce((v_auth->>'requires_approval')::boolean, true) or v_auto = 'founder',
    'autonomy_class', v_auto,
    'founder_only', v_auto = 'founder',
    'authority_reason', coalesce(v_auth->>'reason', 'no action_class mapped for this class: treated as gated')
                        || case when v_auto = 'founder'
                                then '; fn_autonomy_class returns founder for this action class, which overrides any department tier'
                                else '' end,
    'route_to', v_esc->>'route_to',
    'route_basis', v_esc->>'route_basis',
    'hard_gate', v_auth->'hard_gate');
end $function$
;

commit;
