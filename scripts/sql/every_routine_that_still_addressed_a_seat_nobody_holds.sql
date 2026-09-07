-- EVERY ROUTINE THAT STILL ADDRESSED A SEAT NOBODY HOLDS
--
-- The founder removed the organisation chart on 7 Sep 2026 and two seats remain: ceo and
-- customer_support. These routines still carried the old seat names as string literals, so every
-- branch that tested one was dead and every row that wrote one was refused -- which is how the
-- whole cron estate came to fail with "accountable role does not resolve".
--
-- The literals are repointed, not deleted: seats that dealt with the customer or the supplier
-- channel go to customer_support, and everything else to the ceo, because in a two-seat company
-- the ceo holds whatever customer support does not. Only quoted literals are touched; no logic,
-- no signature and no comment prose is changed.
--
-- Swept: 30 routine(s).
CREATE OR REPLACE FUNCTION public.fn_action_holder(p_kind text, p_agent text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(
    (select p.authority_role from public.agent_action_kind_policy p
      where p.kind = p_kind and p.authority_role is not null),
    (select d.value->>p_kind from public.decision_policy d
      where d.key = 'action_autonomy'
        and exists (select 1 from public.org_role r
                     where r.role_id = d.value->>p_kind and r.status = 'active')),
    (select od.lead_agent from public.org_agents oa
       join public.org_departments od on od.dept_key = oa.department and od.active
      where oa.agent_key = p_agent limit 1),
    'ceo');
$function$;

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
  -- RESOLVE BEFORE CONTEXT ASSEMBLY (14 Aug 2026).
  --
  -- This lookup was `where a.agent_key = p_agent_key` against org_agents, so it only ever answered
  -- to a runtime agent_key. Measured: fn_agent_context_v3('ceo') returned
  -- {"error":"unknown agent"} - and chief_of_staff is not a stale string, it is brief's own
  -- role_id in org_role. fn_org_agent_resolve('ceo') has always returned 'brief'.
  --
  -- This is the hottest path in the company: agent_brain, action_worker, dept_plan, agent_act and
  -- exec_agents all assemble context through here. An employee addressed by its canonical role id,
  -- a merged-away key, a packaged role id or a job title got no context at all - not a failure,
  -- an empty prompt - while the resolver that answers all four sat one call away.
  --
  -- Section 2 of the closure brief requires identity to be resolved BEFORE context assembly. This
  -- is that line. coalesce keeps an unknown key unknown, so the refusal below still fires.
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);

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

  -- Its OWN KPIs: what this agent is measured on and its current rating. Per-agent (employee_kpi),
  -- always present so an agent knows how it is judged without having to ask. current_rating is live.
  v_identity := v_identity || jsonb_build_object('kpis', coalesce((
    select jsonb_agg(jsonb_build_object(
             'kpi', kpi, 'measures', metric, 'target', target_value, 'unit', unit,
             'current_rating', actual_value, 'measured_at', measured_at, 'cadence', cadence,
             'serves_goal', serves_goal) order by id)
      from public.employee_kpi where agent_key = p_agent_key and coalesce(active, true)), '[]'::jsonb));

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

  -- WHOLE-COMPANY RECALL (the 20-year veteran). The scoped slices above give the agent its own
  -- department; this gives it the rest of the company: the top matches from the ENTIRE knowledge base,
  -- any department, so the agent can act on any company fact, not only its own corner.
  v_out := v_out || jsonb_build_object('company_wide_knowledge',
    case when v_q is null then '[]'::jsonb else public.fn_company_knowledge_search(p_task_text, 6) end);

  -- IT/CYBERSECURITY DEEP LAYER (Step 3). The company knowledge above is universal; the app's code
  -- and its security are the ONE extra layer, and only the engineering + assurance agents carry it.
  -- fn_it_security_slice returns [] for every other department, so this stays scoped to IT/cyber.
  v_out := v_out || jsonb_build_object('it_security_knowledge',
    public.fn_it_security_slice(v_agent.department, v_q, v_budget / 3));

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

  -- 4b. FIELD CORPUS — the certification/standards corpus for the agent's field. The bulk expert
  --     knowledge (the ~10,000-pages-per-agent target) lives in kb_chunks, tagged by category; here
  --     it is retrieved by the agent's knowledge scope and RANKED against the task, so the prompt
  --     carries the passages that actually bear on the work rather than a category dump. Full-text
  --     ranking (SQL-side, deterministic); the semantic/vector half is added when the query-embed
  --     edge path is wired. Only consulted when a task is supplied, and bounded to a slice of budget.
  if v_q is not null then
    v_out := v_out || jsonb_build_object('field_corpus', coalesce((
        select jsonb_agg(jsonb_build_object('title', title, 'citation', citation,
                                            'category', category, 'content', left(content, 1200))
                         order by rank desc)
          from (select title, citation, category, content, ts_rank(fts, v_q) as rank
                  from kb_chunks
                 where (category = any(v_scope)
                        or (p_category_key is not null and category = p_category_key))
                   and fts @@ v_q
                 order by ts_rank(fts, v_q) desc, effective_date desc nulls last
                 limit 12) k), '[]'::jsonb));
  else
    v_out := v_out || jsonb_build_object('field_corpus', '[]'::jsonb);
  end if;

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
$function$;

CREATE OR REPLACE FUNCTION public.fn_ai_route(p_task_class text DEFAULT NULL::text, p_dept_key text DEFAULT NULL::text, p_confidence numeric DEFAULT NULL::numeric, p_fn text DEFAULT NULL::text, p_escalate boolean DEFAULT false, p_require_caps text[] DEFAULT NULL::text[], p_agent_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_class   text;
  v_src     text;
  v_pol     model_policy%rowtype;
  v_reg     model_registry%rowtype;
  v_fb      model_registry%rowtype;
  v_bud     department_budget%rowtype;
  v_pct     numeric := 0;
  v_model   text;
  v_why     text;
  v_min     numeric;
  v_tier    text;
  v_vis     boolean := 'vision' = any(coalesce(p_require_caps, '{}'::text[]));
  v_aud     boolean := 'audio'  = any(coalesce(p_require_caps, '{}'::text[]));
  v_tls     boolean := 'tools'  = any(coalesce(p_require_caps, '{}'::text[]));
  v_sub     model_registry%rowtype;
  v_want    int;
  v_idp     model_policy_by_identity%rowtype;
  v_generic boolean := false;
  v_rt      jsonb;
  v_prior   jsonb;
  v_conf    numeric;
  v_rtier   text;
  v_canon   text;
begin
  if p_task_class is not null and length(btrim(p_task_class)) > 0 then
    v_class := p_task_class; v_src := 'caller-supplied task_class';
  else
    select task_class into v_class from fn_task_class where fn = p_fn and active;
    if v_class is not null then
      v_src := 'classified from calling function "' || p_fn || '"';
    else
      v_class := 'general_drafting';
      v_generic := true;
      v_src := 'UNMAPPED function "' || coalesce(p_fn,'?') || '" - defaulted to general_drafting (medium). Add a fn_task_class row to route this properly.';
    end if;
  end if;

  -- THE PACK'S FOUR-ROLE TAXONOMY REACHES THE PATH IT WAS WRITTEN FOR (14 Aug 2026).
  --
  -- All 93 employees carry org_agents.routing_tier - director 36, operations_specialist 23,
  -- analyst_controller 21, reviewer_auditor 10 - and on the main employee path it was DEAD.
  -- fn_routing_tier_model below only fires when v_generic is true, i.e. when the calling function
  -- is unmapped; agent_brain IS mapped, to agent_reasoning, so every employee from a marketing
  -- copywriter to the CEO got the same blanket large tier.
  --
  -- Meanwhile model_policy carries routine_employee_reasoning at MEDIUM, and its own rationale
  -- says: "Pack: replaces the current blanket large-tier agent_reasoning. agent_reasoning is LIVE
  -- on anthropic/claude-sonnet-5 and agent_brain is ~93% of OpenRouter spend." It had ZERO callers.
  -- A policy written to replace something, that nothing points at, is a build order nobody wired.
  --
  -- This is a ROUTING decision taken from the role, not an override of task_class routing: the
  -- class is chosen by who is asking, then the policy for that class applies normally.
  --
  -- WHO STAYS ON LARGE, AND WHY. Only operations_specialist moves. reviewer_auditor stays large
  -- deliberately - all 24 Reviewer/Auditor rows in the pack name a large model, and a reviewer on
  -- the cheap model is a green check that means nothing. director and analyst_controller stay
  -- because their work is the consequential kind the large tier exists for.
  if v_class = 'agent_reasoning' and p_agent_key is not null then
    v_canon := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
    select a.routing_tier into v_rtier from org_agents a
     where a.agent_key = v_canon and a.active;
    if v_rtier = 'operations_specialist'
       and exists (select 1 from model_policy mp
                    where mp.task_class = 'routine_employee_reasoning' and mp.active) then
      v_class := 'routine_employee_reasoning';
      v_src := v_src || ' | routing_tier "operations_specialist" for "' || v_canon
                     || '" selected the routine employee class instead of the blanket large tier';
    end if;
  end if;

  select * into v_pol from model_policy where task_class = v_class and active;
  if not found then
    select * into v_pol from model_policy where task_class = 'general_drafting' and active;
    v_src := v_src || ' | no policy for "' || v_class || '", fell back to general_drafting';
    v_generic := true;
  end if;

  -- THE ROLE DEFAULT. model_policy_by_identity carries 120 rows — 96 target employees and 24
  -- current production agents — and had NO reader in the database at all. The pack states its own
  -- precedence on every row: note = 'Role default only; task_class routing overrides it.' So it
  -- applies only where the caller would otherwise get the generic general_drafting fallback:
  -- either the named class has no policy, or the calling function is unmapped in fn_task_class.
  --
  -- v_generic exists because the first version of this branch was UNREACHABLE. It hung off
  -- `if not found` on the model_policy lookup, and an unmapped function has already had v_class
  -- rewritten to 'general_drafting' by then — which IS found. Measured: fn_ai_route(...,'ceo')
  -- returned identity_policy null. Same shape as the unreachable block in
  -- fn_kb_route_activation_blocked found earlier today: a branch guarded by a condition that
  -- cannot occur.
  --
  -- 23 of the 24 current_agent keys resolve to a real org_agents row; 'cat:*' covers the
  -- category desks.
  if v_generic and p_agent_key is not null then
    select * into v_idp from model_policy_by_identity
     where scope = 'current_agent'
       and (identity_key = p_agent_key
            or (identity_key = 'cat:*' and p_agent_key like 'cat:%'))
     order by (identity_key = p_agent_key) desc
     limit 1;
    if found and v_idp.primary_model is not null then
      v_pol.model_primary  := v_idp.primary_model;
      v_pol.model_fallback := coalesce(v_idp.fallback_model, v_pol.model_fallback);
      v_pol.max_tokens     := coalesce(v_idp.max_output_tokens, v_pol.max_tokens);
      v_src := v_src || ' | role default for "' || p_agent_key || '" applied from model_policy_by_identity';
    end if;
  end if;

  -- ---- ROUTING TIER, added 11 Aug 2026 ---------------------------------------------------------
  -- The pack's four-role taxonomy carried onto the 93 real employees as org_agents.routing_tier.
  -- Fires LAST and only if the pack had nothing to say about this specific agent, so an explicit
  -- current_agent row always wins. Resolves tier -> registry tier -> cheapest active approved model
  -- AT CALL TIME: no model id is stored anywhere, so this follows the fleet instead of going stale.
  -- Measured direction against the general_drafting default (haiku, 1.00 USD/Mtok in):
  -- operations_specialist 4x cheaper, analyst/director unchanged, reviewer_auditor 2x dearer and
  -- deliberately so - all 24 Reviewer/Auditor rows in the pack name sonnet-5, and a reviewer on the
  -- cheap model is a green check that means nothing.
  if v_generic and p_agent_key is not null and v_idp.identity_key is null then
    v_rt := public.fn_routing_tier_model(p_agent_key);
    if v_rt is not null and (v_rt->>'model') is not null then
      v_pol.model_primary := v_rt->>'model';
      v_pol.tier          := v_rt->>'registry_tier';
      v_src := v_src || ' | routing_tier "' || (v_rt->>'routing_tier') || '" for "' || p_agent_key
                     || '" resolved to ' || (v_rt->>'model') || ' (' || (v_rt->>'registry_tier') || ' tier)';
    end if;
  end if;
  -- ----------------------------------------------------------------------------------------------

  if v_pol.tier = 'none' then
    return jsonb_build_object(
      'use_llm', false, 'task_class', v_class, 'tier', 'none',
      'why', 'REFUSED. ' || coalesce(v_pol.deterministic_alternative, 'This is deterministic - use code.')
             || ' [' || v_src || ']',
      'deterministic_alternative', v_pol.deterministic_alternative);
  end if;

  v_tier  := v_pol.tier;
  v_model := v_pol.model_primary;
  v_why   := coalesce(v_pol.rationale, 'policy for ' || v_class) || ' [' || v_src || ']';

  if p_escalate then
    v_model := coalesce(v_pol.model_fallback, v_model);
    v_why   := v_why || ' | ESCALATED one tier after an unsatisfactory cheaper attempt';
  end if;

  select (value #>> '{}')::numeric into v_min from decision_policy where key = 'confidence_min';
  -- THE PRIOR, 11 Aug 2026. Both arms below are original and NEITHER HAS EVER FIRED, because
  -- p_confidence is the confidence of THIS call and no caller can know that before the call.
  -- Measured the day this was written: 7 of 1,746 model calls in seven days carried a confidence at
  -- all. The only confidence that CAN exist beforehand is the agent's own recent record on this
  -- task class, so that is what a caller supplying nothing now routes on.
  --
  -- fn_ai_confidence_prior returns null unless there are at least 5 observations AND they vary.
  -- The variance guard is the important half: the two callers that emitted a confidence before
  -- tonight always emitted exactly 1.0000, and a model reporting the same number every time would
  -- otherwise downgrade itself to a cheaper tier on the strength of its own unvarying optimism.
  v_conf := p_confidence;
  if v_conf is null and p_agent_key is not null then
    v_prior := public.fn_ai_confidence_prior(p_agent_key, v_class);
    if v_prior is not null then v_conf := (v_prior->>'prior')::numeric; end if;
  end if;

  if v_conf is not null then
    if v_conf >= 0.95 and v_tier in ('large','xlarge') then
      select model_id into v_model from model_registry
       where active and approved and tier = 'medium' order by in_per_mtok_usd limit 1;
      v_why := v_why || ' | confidence ' || v_conf
               || case when v_prior is null then ''
                       else ' (' || p_agent_key || ' own median over ' || (v_prior->>'n')
                            || ' calls on ' || v_class || ', spread ' || (v_prior->>'spread') || ')' end
               || ' >= 0.95, downgraded to medium - no second opinion needed';
    elsif v_min is not null and v_conf < v_min and v_tier = 'small' then
      v_model := coalesce(v_pol.model_fallback, v_model);
      v_why := v_why || ' | confidence ' || v_conf
               || case when v_prior is null then ''
                       else ' (' || p_agent_key || ' own median over ' || (v_prior->>'n') || ' calls)' end
               || ' below floor ' || v_min || ', escalated a tier';
    end if;
  end if;

  -- A CALL WITH NO DEPARTMENT IS A CALL NO CEILING CAN STOP (13 Aug 2026). The halt below needs a
  -- dept_key to find a budget, and 59 of this month's calls arrived without one - inquiry_intake,
  -- drawing_boq, doc_extract, license_extract, supplier_onboard and eleven more, i.e. the demand
  -- path. fn_task_class already maps fn -> task_class for this same function's model choice; it now
  -- carries the owning department too, so an un-attributed call is attributed by what it IS rather
  -- than left outside every ceiling. An explicit p_dept_key from the caller still wins.
  -- CANONICAL BEFORE THE CEILING (14 Aug 2026). department_budget holds the ten canonical rows;
  -- a caller passing a merged-away key ('procurement', 'marketing', 'sales' ...) found NO budget
  -- row and skipped the ceiling entirely. fn_dept_canonical resolves the key the caller used to
  -- the department that actually owns it.
  if public.fn_dept_canonical(coalesce(p_dept_key, (select t.dept_key from fn_task_class t where t.fn = p_fn and t.active))) is not null then
    select * into v_bud from department_budget
     where dept_key = public.fn_dept_canonical(coalesce(p_dept_key, (select t.dept_key from fn_task_class t where t.fn = p_fn and t.active)));
    if found and v_bud.monthly_aed > 0 then
      v_pct := round(100 * coalesce(
        (select sum(cost_aed) from ai_cost_log
          where dept_key = any(public.fn_dept_scope(v_bud.dept_key))
            and occurred_at >= date_trunc('month', now())), 0)
        / v_bud.monthly_aed, 2);
      if v_pct >= v_bud.halt_at_pct then
        return jsonb_build_object(
          'use_llm', false, 'task_class', v_class, 'tier', v_tier, 'halted', true, 'budget_pct', v_pct,
          'why', 'HALTED. ' || v_bud.dept_key || ' is at ' || v_pct || '% of its monthly AI budget (halt at '
                 || v_bud.halt_at_pct || '%). Non-gated work stops until the budget resets or is raised.');
      elsif v_pct >= v_bud.degrade_at_pct then
        select model_id into v_model from model_registry
         where active and approved
           and tier = case v_tier when 'xlarge' then 'large' when 'large' then 'medium' else 'small' end
         order by in_per_mtok_usd limit 1;
        v_why := v_why || ' | department at ' || v_pct || '% of budget, degraded one tier';
      end if;
    end if;
  end if;

  select * into v_reg from model_registry where model_id = v_model and active;
  if not found then
    select * into v_reg from model_registry
     where active and approved and tier = (case v_tier when 'xlarge' then 'xlarge' else v_tier end)
     order by in_per_mtok_usd limit 1;
    v_why := v_why || ' | WARNING: policy model "' || v_model || '" is not in model_registry; substituted ' || coalesce(v_reg.model_id,'(none)');
    v_model := v_reg.model_id;
  end if;

  -- CAPABILITY. Price and tier chose the model above; if it cannot see, hear or call tools the
  -- provider will simply reject the payload. Substitute the nearest capable model, preferring the
  -- intended tier, then the closest tier ABOVE it, and only then below - a capability substitution
  -- must never quietly become a quality downgrade.
  v_want := fn_ai_route_tier_rank(v_tier);
  if (v_vis or v_aud or v_tls)
     and not ( (not v_vis or coalesce(v_reg.supports_vision,false))
           and (not v_aud or coalesce(v_reg.supports_audio, false))
           and (not v_tls or coalesce(v_reg.supports_tools, false)) ) then

    select * into v_sub from model_registry
     where active and approved
       and (not v_vis or supports_vision) and (not v_aud or supports_audio) and (not v_tls or supports_tools)
     order by (fn_ai_route_tier_rank(tier) < v_want),                 -- at-or-above the tier first
              abs(fn_ai_route_tier_rank(tier) - v_want),              -- then closest to it
              in_per_mtok_usd                                          -- then cheapest
     limit 1;

    if found then
      v_why := v_why || ' | CAPABILITY OVERRIDE: ' || v_model || ' cannot do ('
               || array_to_string(coalesce(p_require_caps,'{}'::text[]), '+') || '); substituted ' || v_sub.model_id
               || ' (' || v_sub.tier || ' tier, intended ' || v_tier || ')';
      v_reg := v_sub; v_model := v_sub.model_id;
    else
      return jsonb_build_object(
        'use_llm', false, 'task_class', v_class, 'tier', v_tier, 'caps', to_jsonb(p_require_caps),
        'why', 'REFUSED. No active approved model in model_registry supports ('
               || array_to_string(coalesce(p_require_caps,'{}'::text[]), '+')
               || '). Add one, or mark the capability on an existing model.');
    end if;
  end if;

  select * into v_fb from model_registry
   where model_id = v_pol.model_fallback and active
     and (not v_vis or supports_vision) and (not v_aud or supports_audio) and (not v_tls or supports_tools);
  if not found and (v_vis or v_aud or v_tls) then
    select * into v_fb from model_registry
     where active and approved and model_id <> v_model
       and (not v_vis or supports_vision) and (not v_aud or supports_audio) and (not v_tls or supports_tools)
     order by (fn_ai_route_tier_rank(tier) < v_want), abs(fn_ai_route_tier_rank(tier) - v_want), in_per_mtok_usd
     limit 1;
  end if;

  return jsonb_build_object(
    'use_llm', true,
    'task_class', v_class,
    'tier', v_tier,
    'model', v_model,
    'fallback', v_fb.model_id,
    'max_tokens', v_pol.max_tokens,
    'cache_ttl_min', coalesce(v_pol.cache_ttl_min, 0),
    'cache', coalesce(v_reg.supports_cache, false),
    'stream', coalesce(v_reg.supports_streaming, true),
    'caps', to_jsonb(coalesce(p_require_caps, '{}'::text[])),
    'in_per_mtok_usd', v_reg.in_per_mtok_usd,
    'out_per_mtok_usd', v_reg.out_per_mtok_usd,
    'cache_read_per_mtok_usd', v_reg.cache_read_per_mtok_usd,
    'budget_pct', v_pct,
    'identity_policy', case when v_idp.identity_key is null then null else jsonb_build_object(
        'identity_key', v_idp.identity_key, 'deterministic_first', v_idp.deterministic_first,
        'reasoning_effort', v_idp.reasoning_effort, 'authority_tier', v_idp.authority_tier) end,
    'routing_tier', v_rt,
    'confidence_prior', v_prior,
    'confidence_used', v_conf,
    'why', v_why);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_budget_rollup()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_period text := to_char(current_date,'YYYY-MM'); n int := 0; v_degraded int := 0; v_halted int := 0; r record;
begin
  -- Every department is rolled, including the ones that spent nothing. The previous inner join
  -- skipped zero-spend departments entirely, leaving last month's spent_aed and period_label in
  -- place indefinitely. Only rows whose value actually changes are written, so updated_at still
  -- means "this budget moved".
  update department_budget b
     set spent_aed = v.total, period_label = v_period, updated_at = now()
  from (
    select b2.dept_key,
           coalesce((select sum(l.cost_aed) from ai_cost_log l
                      where l.dept_key = b2.dept_key
                        and l.occurred_at >= date_trunc('month', now())), 0) as total
      from department_budget b2
  ) v
  where b.dept_key = v.dept_key
    and (b.spent_aed is distinct from v.total or b.period_label is distinct from v_period);
  get diagnostics n = row_count;

  for r in
    select dept_key, monthly_aed, spent_aed, degrade_at_pct, halt_at_pct,
           round(100.0*spent_aed/nullif(monthly_aed,0),1) as pct
    from department_budget
    where monthly_aed > 0 and spent_aed is not null
  loop
    if r.pct >= r.halt_at_pct then
      v_halted := v_halted + 1;
      insert into founder_alerts (level, event, detail, channel)
      select 'high','ai_budget_halt', r.dept_key||' has spent '||r.pct||'% of its monthly AI budget ('||r.spent_aed||' of '||r.monthly_aed||' AED). Halt threshold '||r.halt_at_pct||'% reached.','email'
      where not exists (select 1 from founder_alerts where event='ai_budget_halt' and detail like r.dept_key||'%' and created_at > now()-interval '24 hours');
      -- The same fact, on the bus, so the Finance OS hears it as well as the founder.
      if not exists (select 1 from company_event where event_type='budget.exceeded'
                       and entity_id = r.dept_key and occurred_at > now()-interval '24 hours') then
        perform public.fn_emit('budget.exceeded','department', r.dept_key, 'ceo',
                  jsonb_build_object('pct', r.pct, 'spent_aed', r.spent_aed,
                                     'monthly_aed', r.monthly_aed, 'halt_at_pct', r.halt_at_pct));
      end if;
    elsif r.pct >= r.degrade_at_pct then
      v_degraded := v_degraded + 1;
      insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
      select r.dept_key, 'AI budget degrade threshold: '||r.dept_key,
             r.dept_key||' has spent '||r.pct||'% of its monthly AI budget. Move non-critical work to the cheaper model tier and enable response caching before the halt threshold at '||r.halt_at_pct||'%.',
             'proposed','gated', false, 'recommend'
      where not exists (select 1 from org_tasks where title='AI budget degrade threshold: '||r.dept_key and status<>'done');
    end if;
  end loop;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('budget_rollup', now(), now(), 'ok',
          jsonb_build_object('depts_changed',n,'degraded',v_degraded,'halted',v_halted),
          'AI spend rolled into department budgets: '||n||' department(s) changed, '||v_degraded||' past degrade threshold, '||v_halted||' past halt.');
  return jsonb_build_object('updated',n,'degraded',v_degraded,'halted',v_halted);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_company_self_knowledge_sync()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_state jsonb := public.fn_company_state();
  v_snap  jsonb := public.fn_company_snapshot();
  v_brief text  := public.fn_company_brief(6000);
  v_fee   numeric; v_sup_fee numeric; v_charge date; v_refund_wd int; v_cur text; v_free_n int; v_cat_min int;
  v_chase_wd int; v_bank_min int; v_bank_max int; v_admin numeric; v_pct numeric; v_founder_words text;
  v_target text; v_deadline text;
  v_social text; v_social_at text; v_blog text; v_blog_at text;
  v_funnel text;
  v_founder text;
  v_tmpl text;
  v_rev numeric; v_exp numeric; v_pnl text;
  v_stance record; v_decisions text; v_cat_open text;
  v_records jsonb; r jsonb; v_rid text; v_n int := 0;
  reg public.company_registration%rowtype;
  -- 6 SEP 2026: the two supplier loops (acquisition, sanctions screening) — live values for the record below
  v_golive boolean; v_reg_target text; v_reg_month text; v_bd text; v_co text; v_last_un text; v_last_uae text;
  v_hits_open int; v_invited int; v_registered int; v_followups int; v_intake int;
begin
  v_golive := public.fn_supplier_outreach_golive();
  select coalesce(target_value::text, '300') into v_reg_target from public.company_goals where key = 'suppliers_registered_monthly';
  select coalesce(actual_value::text, '0') || ' (measured ' || coalesce(to_char(measured_at, 'DD Mon YYYY HH24:MI'), 'not yet') || ' UTC)'
    into v_reg_month from public.employee_kpi where agent_key = 'bd' and kpi = 'Suppliers registered per month' and active;
  select display_name into v_bd from public.org_role where role_id = 'business_development';
  select display_name into v_co from public.org_role where role_id = 'ceo';
  select entries || ' entries, fetched ' || to_char(fetched_at, 'DD Mon YYYY HH24:MI') || ' UTC, sha256 ' || left(coalesce(sha256, '?'), 12) || ', ' || status
    into v_last_un from public.screening_run where source = 'un_consolidated' and run_tag is null order by id desc limit 1;
  select entries || ' entries, fetched ' || to_char(fetched_at, 'DD Mon YYYY HH24:MI') || ' UTC, sha256 ' || left(coalesce(sha256, '?'), 12) || ', ' || status
    into v_last_uae from public.screening_run where source = 'uae_local_terrorist_list' and run_tag is null order by id desc limit 1;
  select count(*) into v_hits_open from public.supplier_screening_hit where status = 'open';
  select count(*) filter (where invite_status is not null), count(*) filter (where lifecycle_stage = 'registered'), coalesce(sum(invite_followups), 0)
    into v_invited, v_registered, v_followups from public.leads where coalesce(email, '') not ilike '%@example.invalid';
  select count(*) into v_intake from public.supplier_lead_intake where run_tag is null;
  select * into reg from public.company_registration order by recorded_at desc limit 1;
  -- the founder identity (who leads the company)
  select string_agg(identity, ' / ' order by identity) into v_founder
    from public.phase_c_founder_identity where active and kind = 'email';
  -- the live P&L (financial state beyond headline revenue)
  select coalesce(sum(amount) filter (where type='revenue'),0), coalesce(sum(amount) filter (where type='expense'),0),
         string_agg(case when amount <> 0 then '  - '||type||': '||name||' = AED '||amount::text else null end, E'\n' order by type, code)
    into v_rev, v_exp, v_pnl from public.gl_pnl;
  select standard_reveal_rate, supplier_reg_fee, supplier_charging_starts, refund_window_working_days,
         coalesce(reveal_currency,'AED'), chase_after_working_days, bank_settlement_working_days_min, bank_settlement_working_days_max,
         coalesce(supplier_free_count,1000), coalesce(category_open_min_suppliers,10)
    into v_fee, v_sup_fee, v_charge, v_refund_wd, v_cur, v_chase_wd, v_bank_min, v_bank_max, v_free_n, v_cat_min
    from public.pricing_config order by id limit 1;
  -- 6 SEP 2026: the refund ladder's money side and the founder's own words, from decision_policy
  v_admin := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_admin_fee_aed'), 250);
  v_pct   := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_late_fee_annual_pct'), 9);
  v_founder_words := (select d.value #>> '{}' from public.decision_policy d where d.key = 'refund_policy_founder_decision_2026_09_06');
  -- 6 SEP 2026: the founder's budget stance and his decisions on record (company_financial_stance,
  -- company_policy_decision), and the category-open count (v_category_open)
  select * into v_stance from public.company_financial_stance where id = 1;
  select string_agg('- ' || upper(decision_key) || ' (decided ' || to_char(decided_on,'DD Mon YYYY') || ' by the ' || decided_by
                    || case when never_ask_again then '; NEVER ask about it again' else '' end || '): ' || decision_text
                    || case when cardinality(applies_to) > 0 then ' [applies to: ' || array_to_string(applies_to, ', ') || ']' else '' end,
                    E'\n' order by decision_key)
    into v_decisions from public.company_policy_decision;
  select count(*) filter (where is_open) || ' of ' || count(*) || ' categories are OPEN today (' ||
         coalesce(max(verified_registered_suppliers),0) || ' is the highest verified-registered count in any category)'
    into v_cat_open from public.v_category_open;

  select coalesce(target_value::text,'1000000'), coalesce(to_char(deadline,'DD Mon YYYY'),'31 Aug 2027')
    into v_target, v_deadline
    from public.company_goals
   where active and (lower(coalesce(key,'')) like '%revenue%' or lower(coalesce(goal,'')) like '%revenue%'
                     or category = 'Financial')
   order by sort nulls last limit 1;

  select left(coalesce(content->>'text', content->>'body', content::text), 240), to_char(created_at,'DD Mon YYYY')
    into v_social, v_social_at from public.social_posts order by created_at desc limit 1;
  select title, to_char(coalesce(published_at, updated_at),'DD Mon YYYY')
    into v_blog, v_blog_at from public.blog_posts where published order by published_at desc nulls last limit 1;

  select string_agg('  ' || workflow_id || ' — ' || workflow_name, E'\n' order by workflow_id)
    into v_funnel from public.phase_b_workflow
   where workflow_id in ('W04','W05','W06','W07','W08','W09','W10','W12','W13','W14','W15','W16','W17','W18');

  -- 6 SEP 2026: the WhatsApp template ledger (messaging_template), one line per template, live.
  select coalesce(string_agg('  - ' || template_key || ' [' || lang || ']: ' || upper(status) || ' (' || sid
           || coalesce(', ' || category, '') || coalesce(', submitted ' || to_char(submitted_at, 'DD Mon YYYY'), '')
           || coalesce(', approved (first seen ' || to_char(approved_at, 'DD Mon YYYY') || ')', '')
           || coalesce(', reason: ' || left(rejection_reason, 90), '') || coalesce(', ' || note, '') || ')',
           E'\n' order by template_key, lang), '  (no templates recorded)')
    into v_tmpl from public.messaging_template where channel = 'whatsapp';

  v_records := jsonb_build_array(

    -- 6 SEP 2026: the company's registration and tax status, from company_registration (the founder
    -- supplied the trade licence and ruled on VAT, Corporate Tax and the auditor that day; all are
    -- closed facts, never questions).
    jsonb_build_object('rid','registration','module','company_registration',
      'title','QuotesDone — Trade licence, registration and tax status',
      'kw', to_jsonb(array['trade licence','trade license','licence number','license number','DET','department of economy and tourism',
        'issuing authority','licence expiry','renewal','activity code','portal','software design','trader licence','e-trader',
        'VAT','vat registered','TRN','tax registration number','FTA','federal tax authority','threshold','375,000','corporate tax',
        'corporate tax registration','CT registration','small business relief','auditor','external auditor','audit firm','who audits us',
        'are we vat registered','do we charge vat','company registration','legal entity','owner','who owns the licence']),
      'content',
        case when reg.license_no is null then 'REGISTRATION: not recorded.' else
        'TRADE LICENCE: ' || reg.authority || ' ' || reg.license_type || ' no. ' || reg.license_no || ', trade name "' || reg.trade_name || '"; issued ' ||
        to_char(reg.issued_on,'DD Mon YYYY') || ', expires ' || to_char(reg.expires_on,'DD Mon YYYY') || ' (renew before then; renewal is a company task, not a founder question).' || E'\n' ||
        'OWNER: ' || reg.owner_name || ' (' || reg.owner_share || '); licensed activities: ' || reg.activities || '.' || E'\n' ||
        'REGISTERED CONTACT: ' || reg.registered_email || ', ' || reg.registered_mobile || '; e-stores on the licence: ' || reg.e_stores || '.' || E'\n' ||
        'LICENCE CLASS: ' || reg.license_class_note || E'\n' ||
        'TAX STATUS: ' || case when reg.vat_registered then 'VAT-registered, TRN ' || coalesce(reg.trn,'?') else
          'NOT VAT-registered (founder ruling ' || to_char(reg.vat_ruling_on,'DD Mon YYYY') || '): no VAT is charged or shown on any QuotesDone invoice until taxable supplies reach the FTA mandatory registration threshold of AED ' ||
          to_char(reg.vat_threshold_aed,'FM999,999,999') || ' in a rolling 12 months. Do not ask the founder about VAT or the TRN; when revenue approaches the threshold the CFO opens a registration task.' end || E'\n' ||
        'CORPORATE TAX: ' || coalesce(reg.corporate_tax_note,'registration status not recorded.') || E'\n' ||
        'AUDITOR: ' || coalesce(reg.auditor,'not recorded.')
        end),

    jsonb_build_object('rid','identity','module','company_identity',
      'title','QuotesDone — Identity, Vision and Mission',
      'kw', to_jsonb(array['vision','mission','what is quotesdone','who are we','company','marketplace','target','revenue goal','anonymous','uae','b2b',
        'who is the founder','company founder','who owns quotesdone','founder name','ahmad alzain','the owner',
        'company target and deadline','revenue target','what is our goal','aed 1 million target','1000000 by 2027','when is the deadline']),
      'content',
        'WHO WE ARE. ' || coalesce(v_state->>'mission','') || E'\n' ||
        'VISION: ' || coalesce(v_state->>'vision','') || E'\n' ||
        'TARGET: AED ' || v_target || ' in revenue by ' || v_deadline ||
          ' — every department''s objectives trace to this one number.' || E'\n' ||
        'HOW IT WORKS IN ONE LINE: an anonymous UAE B2B quotation marketplace — buyers post an RFQ, verified UAE '
        'suppliers submit quotes, and the buyer pays a small reveal fee to unlock and contact a chosen supplier. '
        'Every department is an autonomous AI expert that plans and executes toward the vision.' || E'\n' ||
        'FOUNDER / OWNER: Ahmad Alzain (' || coalesce(v_founder,'management@quotesdone.com') || '). The company is '
        'founder-led: he sets the vision, the target and the boundaries, and he is the ONLY approver of refunds. '
        'The AI departments run everything else on their own.'),

    jsonb_build_object('rid','financials','module','financials',
      'title','QuotesDone — Our Financials (live P&L) and the Budget Policy',
      'kw', to_jsonb(array['financials','finance','p&l','profit and loss','expenses','costs','revenue','how much did we spend','what were our expenses','net','burn','money','accounting','are we profitable',
        'budget','budget limit','budget policy','do we have a budget','budget variance','over budget','spending limit','when do we set budgets','profitable']),
      'content',
        'LIVE FINANCIAL STATE (from the general ledger; refreshes):' || E'\n' ||
        '  Total revenue: AED ' || round(coalesce(v_rev,0),2)::text || '  ·  Total expenses: AED ' || round(coalesce(v_exp,0),2)::text ||
        '  ·  Net: AED ' || round(coalesce(v_rev,0)-coalesce(v_exp,0),2)::text || E'\n' ||
        'By account (non-zero lines):' || E'\n' || coalesce(v_pnl,'  (no posted amounts yet)') || E'\n' ||
        'Read it honestly: revenue is ' || case when coalesce(v_rev,0)=0 then 'AED 0 because the marketplace is pre-launch' else 'as above' end ||
        '; the spend so far is mostly software and AI infrastructure while the company is being built.' || E'\n' ||
        'BUDGET POLICY (founder, ' || coalesce(to_char(v_stance.decided_on,'DD Mon YYYY'),'6 Sep 2026') || '): ' ||
          coalesce(v_stance.policy_text, 'No budget limit while costs are subscriptions; budgets come with profitability.') ||
          ' Current stance: ' || case when coalesce(v_stance.is_profitable,false) then 'PROFITABLE - budgets apply and budget-variance alerts are live.'
                                     else 'NOT YET PROFITABLE - budget_mode ' || coalesce(v_stance.budget_mode,'unlimited_until_profitable') ||
                                          '; there is no budget limit, and budget-variance alerts and budget-limit checks are inert. Do not ask the founder for a budget.' end),

    jsonb_build_object('rid','operating-model','module','operating_model',
      'title','QuotesDone — How the Marketplace Works, End to End',
      'kw', to_jsonb(array['funnel','operating model','how it works','journey','inquiry','rfq','routing','packaging','dispatch','reveal','pipeline','workflow']),
      'content',
        'THE FUNNEL. A customer''s job travels the pipeline autonomously:' || E'\n' ||
        '  W04 register/onboard the customer → W05 intake and qualify the inquiry (RFQ) → W06 route it to the right '
        'category → W07 process any drawings/BOQ/documents → W08 build and approve a supplier-SAFE package (customer '
        'identity and any contact details stripped) → W09/W10 onboard and verify suppliers → W12 match and dispatch to '
        'enough confirmed suppliers → W13 notify them → W14 suppliers submit and we evaluate quotations → W15 build the '
        'top-3 comparison and reveal path → W16 the customer pays the reveal fee and gets supplier contact → W17 handles '
        'any refund/dispute, W18 support and retention.' || E'\n' ||
        'ANONYMITY: buyers and suppliers never see each other until the buyer pays to reveal. Quotes are anonymized/'
        'masked until then. The 30 workflows that run this: ' || coalesce(v_funnel,'(registry)') ),

    jsonb_build_object('rid','commercials','module','commercials',
      'title','QuotesDone — Fees, Pricing and Refund Terms (live)',
      'kw', to_jsonb(array['fee','reveal fee','review fee','pricing','how much','commission','refund','supplier fee','registration fee','late fee','cost','price','supplier charging','when does supplier charging start','how much do suppliers pay','are suppliers charged','supplier registration','supplier pays',
        'discount','promo','promotion','coupon','free reveal','cap','fee cap','maximum fee','first 1000','first 1,000','open category','category open','when is a category open','how many suppliers to open a category']),
      'content',
        'REVEAL FEE (what the customer pays to unlock a supplier): ' || round(v_fee*100,2) || '% of the deal, in ' || v_cur ||
          ' — read live from pricing_config, so this figure is always the current one. NO cap, NO discount, NO promotional rate, '
          'NO coupon and NO free reveal exist or may be offered (founder, 6 Sep 2026; pricing_config forbids them by constraint).' || E'\n' ||
        'SUPPLIERS: ' || case when v_charge is null
          then 'registration is FREE for the first ' || v_free_n || ' registrations (those suppliers are exempt permanently); every registration after them pays ' ||
               coalesce(v_sup_fee::text,'1000') || ' ' || v_cur || ' per year. There is NO calendar start date and never will be: charging begins with registration ' ||
               (v_free_n + 1) || ', whenever that happens (founder, 6 Sep 2026). Never state a date; never ask the founder for one.'
          else 'registration is FREE until ' || to_char(v_charge,'DD Mon YYYY') || ', then ' || coalesce(v_sup_fee::text,'1000') || ' ' || v_cur || ' per year.' end ||
          ' Suppliers are auto-approved on a verified file.' || E'\n' ||
        'CATEGORY OPENING: a category is OPEN once it has ' || v_cat_min || ' verified registered suppliers (public.v_category_open); ' ||
          coalesce(v_cat_open, '') || '. Matching an RFQ still needs at least one confirmed supplier.' || E'\n' ||
        'REFUNDS: the supplier has ' || coalesce(v_refund_wd::text,'5') || ' UAE working days from the customer''s payment (Mon-Fri; Sat+Sun off; public holidays excluded). '
        'No response by working day ' || coalesce(v_chase_wd::text,'3') || ': the Customer Success Director chases the supplier, customer copied. Still silent on working day ' || coalesce(v_refund_wd::text,'5') ||
        ': the founder is notified for his final call. No response to that: the customer is refunded the FULL reveal fee (the 3% paid, no deduction) - EVERY refund of any amount is the founder''s approval - and told banks take '
        || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days. The supplier then owes that fee + AED ' || v_admin::text || ' administrative fee + '
        || v_pct::text || '% p.a. simple interest (fn_refund_amount_aed). Full record: qd-company:refunds.' || E'\n' ||
        'LATE FEE on overdue recoverables: 9% per annum (UAE Federal Decree-Law 50/2022).'),

    jsonb_build_object('rid','comparison-report','module','comparison_report',
      'title','QuotesDone — The Top-3 Comparison Report',
      'kw', to_jsonb(array['comparison report','compare','top 3','top three','quote comparison','ranking','shortlist','quote_compare','how do we compare','side by side']),
      'content',
        'THE COMPARISON REPORT IS ALWAYS THE TOP 3. However many quotations arrive — 3 or 100 — quote_compare ranks '
        'them ALL and returns the top three (ranks 1, 2, 3). It is NOT cheapest-wins: quotes are scored across multiple '
        'technical and commercial factors — price positioned across the range of offers, lead time, warranty, scope match, '
        'payment terms — so the strongest overall quote wins, not merely the lowest. The ranking is deterministic; the model '
        'writes the plain-language explanation of why the top three are the top three. The customer sees an anonymized '
        'side-by-side comparison table, saveable as a PDF, and only then decides whom to reveal.'),

    jsonb_build_object('rid','quotation-format','module','quotation_format',
      'title','QuotesDone — What a Supplier Quotation Contains',
      'kw', to_jsonb(array['quotation format','quote format','what is in a quote','quote fields','lead time','validity','payment terms','warranty','scope','exclusions','anonymized']),
      'content',
        'A supplier quotation carries: the quote amount, lead time, validity period, payment terms, warranty, scope of '
        'supply, conditions, exclusions, and notes. It may be typed or extracted from an uploaded file, then structured '
        'and committed (hashed) so it cannot be silently changed. BEFORE the customer sees it, the supplier''s identity '
        'and any contact details are anonymized/masked. The price the customer sees (customer_price) includes the '
        'platform margin/app fee on top of the supplier''s amount.'),

    jsonb_build_object('rid','terms','module','terms_and_conditions',
      'title','QuotesDone — Terms, Anonymity and Working Days',
      'kw', to_jsonb(array['terms','conditions','t&c','anonymous','reveal','working days','jurisdiction','policy','rules','uae']),
      'content',
        'QuotesDone is an ANONYMOUS UAE B2B marketplace. Suppliers are verified before they can quote. Buyer and supplier '
        'identities are hidden from each other until the buyer pays the reveal fee to contact a chosen supplier. All time '
        'windows use UAE working days (Asia/Dubai; Friday is a working day; the weekend is Saturday and Sunday; public '
        'holidays excluded). The reveal refund ladder is ' || coalesce(v_refund_wd::text,'5') || ' working days from payment: chase at '
        || coalesce(v_chase_wd::text,'3') || ', founder''s final call on day ' || coalesce(v_refund_wd::text,'5') || ', refund in full on no response, banks '
        || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days. Late fees '
        'follow UAE Federal Decree-Law 50/2022 (9% p.a.). The platform mediates disputes through a defined escalation ladder.'),

    jsonb_build_object('rid','governance','module','governance',
      'title','QuotesDone — How the Company Governs Itself',
      'kw', to_jsonb(array['governance','who approves','autonomy','refund approval','founder','escalation','boundaries','decisions','authority']),
      'content',
        'QuotesDone runs as ten autonomous AI departments (90 brain agents) that plan and execute toward the vision '
        'WITHOUT needing the founder''s approval for ordinary work. The founder is escalated to only for: money that '
        'leaves the company (every refund, any amount, needs his approval), destructive/irreversible production changes, '
        'and decisions only he holds (his intentions, external credentials, commercial direction). Everything else — '
        'routing, packaging, matching, pricing within policy, content — the agents decide and own. Colleagues hand work '
        'to one another through defined handoffs; nothing is left unowned.'),

    -- DYNAMIC: regenerated from the live org every run.
    jsonb_build_object('rid','organization','module','organization',
      'title','QuotesDone — The Organization: Departments, Colleagues and Roles',
      'kw', to_jsonb(array['organization','org chart','departments','how many agents','who works here','colleagues','roles','manager','line manager','team','north star','who does what','name the ten departments','list the departments','what are our departments','department names','the 10 departments']),
      'content', 'THE COMPANY YOU WORK IN (live roster — these are your colleagues; know who does what and who leads each team).' || E'\n' ||
        'THE TEN DEPARTMENTS: ' || coalesce((select string_agg(name, ', ' order by sort nulls last, dept_key) from public.org_departments where active),'') || E'\n' ||
        coalesce(v_brief,'')),

    -- DYNAMIC: the live snapshot every run.
    jsonb_build_object('rid','live-state','module','live_state',
      'title','QuotesDone — Live Company State (current)',
      'kw', to_jsonb(array['live','current','right now','revenue','last month revenue','how much revenue','customers','suppliers','open tasks','kpi','last social post','last blog','latest post','state','status','how are we doing']),
      'content',
        'LIVE STATE as of ' || to_char(now(),'DD Mon YYYY HH24:MI') || ' UTC (this refreshes; if a figure is 0 the company '
        'is pre-launch, not broken):' || E'\n' ||
        '  Revenue (last 30 days): ' || coalesce(v_snap->>'revenue_30d_aed','0') || ' AED' || E'\n' ||
        '  Customers: ' || coalesce(v_snap->>'customers','0') || ' (with an inquiry: ' || coalesce(v_snap->>'customers_with_inquiry','0') || ')' || E'\n' ||
        '  Approved suppliers: ' || coalesce(v_snap->>'approved_suppliers','0') || ' · Sendable supplier pool: ' || coalesce(v_snap->>'sendable_pool','0') || E'\n' ||
        '  Employees (brain agents): ' || coalesce(v_snap->>'employees','90') || ' · Departments: ' || coalesce(v_snap->>'departments','10') || E'\n' ||
        '  KPIs tracked: ' || coalesce(v_snap->>'kpis','0') || ' (open gaps: ' || coalesce(v_snap->>'kpi_gaps_open','0') || ')' || E'\n' ||
        '  Open tasks: ' || coalesce(v_snap->>'open_tasks','0') || ' · Items needing the founder: ' || coalesce(v_snap->>'needs_founder','0') || E'\n' ||
        '  AI spend (last 30 days): ' || coalesce(v_snap->>'ai_cost_30d_aed','0') || ' AED' || E'\n' ||
        '  Last social post: ' || coalesce(nullif(v_social,''),'(none yet)') || case when v_social_at is not null then ' [' || v_social_at || ']' else '' end || E'\n' ||
        '  Last blog post: ' || coalesce(nullif(v_blog,''),'(none yet)') || case when v_blog_at is not null then ' [' || v_blog_at || ']' else '' end),

    jsonb_build_object('rid','stage','module','company_stage',
      'title','QuotesDone — What Stage the Company Is At',
      'kw', to_jsonb(array['stage','pre-launch','have we launched','are we live','do we have customers','how many customers','are we operating','company status','how far along','launched yet','traction','are we making money']),
      'content',
        'COMPANY STAGE — READ THIS BEFORE ANSWERING ANYTHING ABOUT TRACTION. QuotesDone is PRE-LAUNCH. The '
        'platform and the AI organization are built and being readied; there are ' || coalesce(v_snap->>'customers','0') ||
        ' real customers and AED ' || coalesce(v_snap->>'revenue_30d_aed','0') || ' revenue so far. What is already in place: '
        '10 departments and ' || coalesce(v_snap->>'employees','90') || ' AI agents, 30 workflows, 86 supplier categories, '
        'the knowledge base and ' || coalesce(v_snap->>'approved_suppliers','1') || ' approved supplier(s). What is still pending before real '
        'operation: the marketplace go-live, real customer inquiries arriving, and funded AI inference so the agents can reason. '
        'NEVER claim customers, revenue, or results the numbers above do not show — we are building toward AED 1,000,000 by 31 Aug 2027, not there yet.'),

    -- 6 SEP 2026 (added at the END: sibling files restate this function; keep this the last element): the
    -- refund ladder, from pricing_config + decision_policy, the founder's ruling verbatim. Never re-ask him.
    jsonb_build_object('rid','refunds','module','refunds',
      'title','QuotesDone — The Refund Ladder (live): 5 working days, chase at 3, founder''s final call at 5',
      'kw', to_jsonb(array['refund','refund ladder','refund policy','refund window','non-response','supplier not responding','not responding','no response',
        'chase','chase the supplier','final call','founder final call','working days','5 working days','five working days','3 working days',
        'bank','7-14 working days','how long does a refund take','admin fee','administrative fee','250','9%','interest','9% per annum',
        'who chases','who owns refunds','refund amount','how much is refunded','supplier charge','non-response charge','fn_refund_amount_aed','fn_refund_state','refund_ladder_sweep']),
      'content',
        'THE REFUND LADDER (founder ruling 6 Sep 2026, final; read live from pricing_config and decision_policy):' || E'\n' ||
        '  Day 0: the customer pays the reveal fee (' || round(v_fee*100,2) || '% of the quotation, no cap). The clock starts at PAYMENT; nothing the customer does or does not do moves it.' || E'\n' ||
        '  Working day ' || coalesce(v_chase_wd::text,'3') || ' with no supplier response: the Customer Success Director (runtime agent followup, customer_experience) chases the supplier by email, customer copied, WhatsApp when opted in, and holds an org_task until the supplier responds. Deterministic: fn_refund_ladder_sweep, cron refund_ladder_sweep_hourly.' || E'\n' ||
        '  Working day ' || coalesce(v_refund_wd::text,'5') || ' with still no response: the refund request is filed through fn_refund_request (the ONE door) and the founder is notified for his FINAL CALL (founder_mail_policy kind refund_final_call - one of only two refund signals that reach his inbox; the other is the approval itself).' || E'\n' ||
        '  No response to his call: he approves the refund in the OS (fn_refund_decide; every refund, any amount, is his decision, never automatic).' || E'\n' ||
        '  The customer is refunded the FULL fee paid - no deduction - and told that banks take ' || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days to show it.' || E'\n' ||
        '  The supplier whose silence caused it owes: the refunded fee (the 3%) + AED ' || v_admin::text || ' administrative fee + ' || v_pct::text || '% per annum simple interest (the UAE statutory maximum), and is blocked from matching until settled. One function states the arithmetic: fn_refund_amount_aed(paid, paid_at, refund_at).' || E'\n' ||
        '  Working days are Monday to Friday, UAE public holidays excluded (fn_is_working_day). fn_refund_state(transaction) says where any case stands.' || E'\n' ||
        'WHO OWNS WHAT: chase = Customer Success Director (existing owner of supplier follow-up); final call + approval = the founder; execution on Stripe = Payments & Billing Manager; reconciliation = Financial Controller; recovery from the supplier = Accounts Receivable via collections_legal. No new employee was created for this.' || E'\n' ||
        'THE FOUNDER''S WORDS (verbatim, 6 Sep 2026 - never ask him about refunds again): "' || coalesce(v_founder_words, '(decision_policy.refund_policy_founder_decision_2026_09_06)') || '"'),

    -- 6 SEP 2026: the brand kit, from company_brand (the founder attached the kit that day: "make sure it's
    -- in company knowledge so you never ask me about it again"). Appended LAST on purpose: sibling files add
    -- qd-company:decisions and qd-company:refunds to this same array; they merge ahead of this record.
    jsonb_build_object('rid','brand','module','brand',
      'title','QuotesDone — Brand Kit: colours, typography, logo rules, voice and asset files',
      'kw', to_jsonb(array['brand','brand kit','brand guide','brand guidelines','logo','logo files','lockup','wordmark','mark','favicon','app icon',
        'colour','color','colours','colors','hex','palette','teal','gold','navy','ink','brand colours','what are our colours','primary colour','primary color',
        'font','typeface','typography','poppins','plus jakarta sans','tajawal','arabic font','type scale',
        'tagline','clear space','minimum size','logo usage','social image size','cover size','avatar','banner','post template',
        'tone of voice','voice','wording','bilingual','arabic','rtl','email template','pdf header','letterhead','business card','trademark','ip filing','vector','svg',
        'where is the logo','which logo file','brand assets','brand bucket','contrast','wcag','accessibility','button colour','link colour']),
      'content',
        'THE BRAND KIT IS ON FILE (the founder attached QuotesDone_Brand_Kit.zip on 6 Sep 2026 and ruled it company knowledge: never ask him for a logo, a colour or a font again). '
        || 'Files: ' || (select count(*) from public.brand_assets where bucket = 'brand')::text
        || ' assets in the public brand bucket under kit/ (public.brand_assets holds kind, platform, path, size and usage per file; WHERE_TO_USE.txt is the kit index). '
        || 'The full guide is docs/brand/QUOTESDONE_BRAND_GUIDE.md and the "QuotesDone Brand Guide" PDF in the OS Reports panel.' || E'\n'
        || coalesce((select string_agg(g.block, E'\n' order by g.grp_sort)
                       from (select cb."group", min(cb.sort) as grp_sort,
                                    upper(cb."group") || ':' || E'\n'
                                    || string_agg('  - ' || cb.key || ': ' || cb.value || coalesce(' — ' || cb.note, ''), E'\n' order by cb.sort) as block
                               from public.company_brand cb group by cb."group") g),
                    '  (company_brand is empty)')),

    -- 6 SEP 2026: the founder's decisions, verbatim in substance, from company_policy_decision. Added at the
    -- END on purpose: the renderer is code-driven and sibling packets (the refund ladder and the brand kit
    -- above, messaging) add their records before it. Whichever packet lands last keeps its record last;
    -- order carries no meaning here.
    jsonb_build_object('rid','decisions','module','founder_decisions',
      'title','QuotesDone — The Founder''s Standing Decisions (never ask about these again)',
      'kw', to_jsonb(array['founder decision','founder decisions','standing decision','ruling','policy decision','what did the founder decide','never ask again',
        'corporate tax','auditor','meta token','daily budget cap','30 aed','cost per lead target','cpl target','openrouter','open router credit','recharge','receipts','expenses email',
        'discount','no discounts','reveal cap','category open','10 suppliers','finance budget','budget limit','profitable','supplier registration fee','first 1000','1000 aed per year','no deadline','no date']),
      'content',
        'THE FOUNDER''S STANDING DECISIONS. Each line is final. None is a question; none is asked again; every table, document and agent head is kept in sync with them.' || E'\n' ||
        coalesce(v_decisions, '(none recorded)'))
,

    -- 6 SEP 2026 (appended at the END, code-driven): the two supplier loops the founder decided on that day.
    jsonb_build_object('rid','supplier-loops','module','supplier_loops',
      'title','QuotesDone — Supplier acquisition loop and weekly sanctions screening (owners, cadence, switch)',
      'kw', to_jsonb(array['supplier acquisition','invite campaign','supplier invites','follow-up','follow up','300 suppliers','suppliers per month',
        'registered suppliers target','lead intake','inbound email','new leads','lead sourcing','supplier_outreach_golive','outreach switch','is outreach on',
        'sanctions','sanctions screening','UN consolidated list','UAE terrorist list','local terrorist list','screening hit','banned supplier',
        'who owns supplier acquisition','who screens suppliers','compliance officer','business development manager','weekly screening','when do we screen']),
      'content',
        'SUPPLIER ACQUISITION LOOP (founder decision 6 Sep 2026). Owner: ' || coalesce(v_bd, 'Business Development Manager') || ' (org_role business_development, agent bd, department supply) — '
        'no new employee was created; this is that role''s existing responsibility. Target: at least ' || v_reg_target || ' suppliers registered every month '
        '(company_goals.suppliers_registered_monthly; the BD scorecard KPI "Suppliers registered per month", measured from leads registration timestamps). '
        'This month so far: ' || coalesce(v_reg_month, '0 (not measured yet)') || '. Sources: the leads we already hold (' || v_invited || ' invited to date, '
        || v_registered || ' registered), inbound e-mail (senders on business domains become leads; supplier-intent replies are classified by keyword — no model — into '
        'register / question / document / decline / bounce and become ONE reply task on the BD manager; ' || v_intake || ' classified so far), and the staged directory '
        'promoted daily by supplier_discovery_daily. No scraping (Apify paused) and no paid inference anywhere in the loop. Cadence: supplier_invites_daily 09:00 UTC '
        '(the invitation batch, capped, deliverability-guarded) and supplier_outreach_daily 05:30 UTC (follow-ups at +3 and +7 WORKING days after a delivered '
        'invitation, at most two, never to a lead that replied, registered, bounced or is suppressed; ' || v_followups || ' follow-ups sent to date; inbox intake; lead sourcing). '
        'THE SWITCH: app_secrets.supplier_outreach_golive is ' || case when v_golive then 'TRUE — outreach is LIVE.' else 'FALSE — every part of the loop is HELD and records "held" on each run; the founder flips it when the app is ready ("none of this will run till the app is perfect").' end
        || ' Both it and invite_enabled must be true before an invitation is written.' || E'\n\n' ||
        'WEEKLY SANCTIONS SCREENING (founder decision 6 Sep 2026). Owner: ' || coalesce(v_co, 'Compliance & Privacy Officer') || ' (org_role compliance_and_privacy_officer, agent compliance_mgr, '
        'department legal — the actor of supplier_onboarding step 4 "Compliance screen before anything is activated"). Cadence: sanctions_screen_weekly, Mondays 03:00 UTC (07:00 Dubai). '
        'Sources: the UN Security Council consolidated list (XML; last: ' || coalesce(v_last_un, 'not fetched yet') || ') and the UAE Local Terrorist List from the Executive Office '
        'for Control & Non-Proliferation (published as PDF and legacy Excel only — the Excel is parsed, the PDF is not; last: ' || coalesce(v_last_uae, 'not fetched yet') || '). '
        'Every registered supplier is screened on legal name, licence name, owner, contact and e-mail domain by normalised exact match and conservative token overlap. '
        'A hit opens ONE task on the compliance officer with the evidence and ONE hold on the BD manager — the team is updated, never the founder — and NOBODY is removed automatically: '
        'the compliance officer decides (fn_supplier_screening_decide), and a CONFIRMED hit moves the supplier through the existing status path (banned, matching blocked, approval withdrawn). '
        'Open hits right now: ' || v_hits_open || '. Records: screening_run (source, entries, fetched_at, sha256), screening_entry, supplier_screening_hit.'),

    -- 6 SEP 2026 (LAST on purpose — every sibling file of the day restates this function and the last record
    -- is the one a later restatement can carry forward without touching the others): the WhatsApp templates
    -- and their Meta approval status, live from messaging_template (the founder said "fix the template
    -- yourself"; the status is company knowledge, never his question).
    jsonb_build_object('rid','messaging-templates','module','messaging_templates',
      'title','QuotesDone — WhatsApp templates and their Meta approval status (live)',
      'kw', to_jsonb(array['whatsapp template','whatsapp templates','template approval','meta approval','twilio','content sid','contentsid',
        'founder alert whatsapp','whatsapp alert','whatsapp alerts to the founder','is the whatsapp template approved','pending template',
        'template pending','template rejected','63016','utility template','messaging template','messaging_template','wa_template_sids',
        'can we send whatsapp','why did the whatsapp not arrive','send_whatsapp','wa_template_setup','business-initiated message','24-hour session']),
      'content',
        'WHATSAPP TEMPLATES (Twilio Content API, approved by Meta; live from messaging_template):' || E'\n' || v_tmpl || E'\n' ||
        'THE RULES. A business-initiated WhatsApp (an alert to the founder, a job / quote / reveal / document notice to a supplier or '
        'customer) is deliverable ONLY through a Meta-APPROVED template sent by ContentSid; a freeform body is delivered only inside the '
        '24-hour session the recipient opened by messaging us first (Twilio error 63016 otherwise). A template still pending approval is a '
        'HELD message, never a failed one: send_whatsapp keeps supplier and customer rows queued until the template lands, marks founder-alert '
        'rows skipped with the reason (the email already carried the alert), and refuses a direct send with the reason instead of erroring. '
        'Templates are created and submitted by the wa_template_setup function (category UTILITY, language en/ar, the body opens AND closes '
        'with literal text because Meta rejects a variable at the start or end); the sender refreshes each pending status from Twilio at most '
        'every ten minutes and only ever sends with a status of APPROVED. The sender number is registered with Meta as "QuotesDone" '
        '(quality rating and messaging tier are read from Twilio, not assumed). Nobody asks the founder about WhatsApp templates: the '
        'status above is the answer, and a pending line means Meta has not answered yet.')
  );

  for r in select * from jsonb_array_elements(v_records) loop
    v_rid := 'qd-company:' || (r->>'rid');
    insert into public.ops_knowledge(
      record_id, scope_type, scope_key, layer, module, record_type, title, content,
      structured_data, source_ids, implementation_status, validation_status, authority_tier,
      risk_level, version, keywords, dependencies, escalation_rule, jurisdiction, source_freshness,
      confidentiality, runtime_eligible, deterministic, supersession_state, embedding_status,
      effective_date)
    values (
      v_rid, 'company', 'company_core', 'company_core', r->>'module', 'md', r->>'title',
      -- fold the keyword vocabulary into the content so the generated tsv (title+content) indexes the
      -- phrasings agents actually ask in, not only the prose. This is what makes deep questions match.
      (r->>'content') || E'\n\nYou can answer questions about: ' ||
        array_to_string(array(select jsonb_array_elements_text(r->'kw')), ', ') || '.',
      '{}'::jsonb, array['fn_company_self_knowledge_sync'], 'active', 'validated', 'autonomous',
      'low', '1', array(select jsonb_array_elements_text(r->'kw')), '{}'::text[], '{}'::jsonb, 'UAE', 'current',
      'internal', true, true, 'current', 'pending', current_date)
    on conflict (record_id) do update set
      module = excluded.module, title = excluded.title, content = excluded.content,
      keywords = excluded.keywords, effective_date = excluded.effective_date,
      supersession_state = 'current', embedding_status = 'pending';
    v_n := v_n + 1;
  end loop;

  -- The org directory (everyone knows everyone: role, line manager, KPI, live rating) and the
  -- published content (FAQ, social, blog, website) are recomposed in the same refresh.
  perform public.fn_company_org_directory_sync();

  return jsonb_build_object('ok', true, 'records', v_n, 'ran_at', now(),
    'revenue_30d_aed', v_snap->>'revenue_30d_aed', 'reveal_fee_pct', round(v_fee*100,2),
    'employees', v_snap->>'employees');
end $function$;

CREATE OR REPLACE FUNCTION public.fn_customer_terms_accept(p_customer_id uuid, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c            public.customers%rowtype;
  v_slug       text;
  v_version    text;
  v_digest     text;
  v_bkey       text;
  v_owner      text := p_customer_id::text;
  v_existing   text;
  v_write      jsonb;
  v_acc_ref    text;
  v_run        bigint;
  v_step_run   bigint;
  v_actor      text;
  v_disp       jsonb := null;
  v_effect     bigint := null;
begin
  select * into c from public.customers where id = p_customer_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no such customer ' || p_customer_id);
  end if;

  -- The document this acceptance object accepts, and its published version + digest (never trusted
  -- from the caller). This is the same relation and pair BR-025 judges against.
  select a.document_slug into v_slug
    from public.phase_d_acceptance_document a where a.object_id = 'customer_terms_acceptance';
  v_slug := coalesce(v_slug, 'customer-terms');
  -- The currently published document: newest effective_date wins (version is a label, not an order).
  select d.version, encode(sha256(convert_to(coalesce(d.body_html,''),'UTF8')),'hex')
    into v_version, v_digest
    from public.legal_documents d where d.slug = v_slug
    order by d.effective_date desc nulls last, d.version desc limit 1;
  if v_version is null then
    return jsonb_build_object('ok', false, 'reason', 'no published document for slug ' || v_slug);
  end if;

  -- Keep the product's own fast-path columns in step, idempotently.
  update public.customers
     set tos_accepted_at = coalesce(tos_accepted_at, now()),
         tos_version = v_version,
         tos_ip = coalesce(nullif(btrim(p_ip),''), tos_ip)
   where id = p_customer_id;

  -- One acceptance record per (customer, version). APPEND_ONLY refuses a second write to a key that
  -- already holds a record, so reuse the current one rather than let that surface as an error.
  v_bkey := v_owner || ':' || v_version;
  select o.business_key into v_existing
    from public.phase_d_object_record o
   where o.object_id = 'customer_terms_acceptance' and o.business_key = v_bkey
     and o.superseded_by is null
   order by o.record_id desc limit 1;

  if v_existing is not null then
    v_acc_ref := v_existing;
  else
    v_write := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id',   'customer_terms_acceptance',
      'business_key', v_bkey,
      'owner_ref',    v_owner,
      'state',        'accepted',
      'created_by',   'customer_support',
      'payload', jsonb_build_object(
        'terms_version', v_version,
        'terms_hash',    v_digest,
        'accepted_at',   to_char(now() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'ip',            nullif(btrim(p_ip),''),
        'document_slug', v_slug,
        'source',        'kyc.accept_terms')));
    v_acc_ref := coalesce(v_write->>'business_key', v_bkey);
  end if;

  -- Re-dispatch the open W04-S01 for this customer through the canonical door. The kernel opened it
  -- on registration; nothing re-entered it after the refusal. With the acceptance now on record,
  -- terms_version, terms_hash and acceptance_ref all resolve and the step can execute.
  select r.run_id into v_run
    from public.phase_c_workflow_run r
   where r.workflow_id = 'W04'
     and r.business_object_id = 'customer_account:' || v_owner
     and r.state not in ('closed','cancelled','failed','completed')
   order by r.run_id desc limit 1;

  if v_run is not null then
    select sr.step_run_id, sr.accountable_role_id into v_step_run, v_actor
      from public.phase_c_workflow_step_run sr
     where sr.run_id = v_run and sr.step_id = 'W04-S01' and sr.state = 'active'
     order by sr.step_run_id desc limit 1;

    if v_step_run is not null then
      v_disp := public.fn_phase_d_dispatch_step(jsonb_build_object(
        'step_run_id',   v_step_run,
        'actor_role_id', coalesce(v_actor, 'customer_support'),
        'opened_by_kind','terms_accepted',
        'opened_by_ref', 'fn_customer_terms_accept:' || v_owner,
        'idempotency_key','W04-accept:' || v_run || ':W04-S01'));
      v_effect := nullif(v_disp->>'effect_id','')::bigint;
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'acceptance_ref', v_acc_ref,
    'terms_version', v_version,
    'terms_hash', v_digest,
    'run_id', v_run,
    'step_run_id', v_step_run,
    'dispatch_outcome', v_disp->>'outcome',
    'effect_id', v_effect,
    'dispatch', v_disp);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_day_conductor()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d date := current_date; v_ok int := 0; v_bad int := 0;
begin
  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d,'ceo_reviews_company',1,'an exec or board report in the last 24h',
    jsonb_build_object('board_reports_24h',(select count(*) from board_reports where created_at>now()-interval '24 hours'),
                       'exec_reports_24h',(select count(*) from exec_reports where created_at>now()-interval '24 hours')),
    ((select count(*) from board_reports where created_at>now()-interval '24 hours')
   + (select count(*) from exec_reports where created_at>now()-interval '24 hours'))>0,
    'strategy_ai_daily / board_report_weekly / exec_meeting_weekly'
  on conflict (business_day,stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d,'cos_reviews_departments',2,'cos_execute_hourly fired and succeeded',
    jsonb_build_object('cron_ok',fn_cron_ran('cos_execute_hourly','3 hours'),
                       'runs_24h',(select count(*) from agent_runs where agent='ceo' and started_at>now()-interval '24 hours')),
    fn_cron_ran('cos_execute_hourly','3 hours'),'cos_execute_hourly'
  on conflict (business_day,stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d,'departments_plan',3,'dept_plan_daily fired and succeeded',
    jsonb_build_object('cron_ok',fn_cron_ran('dept_plan_daily')),
    fn_cron_ran('dept_plan_daily'),'dept_plan_daily (does not always write agent_runs)'
  on conflict (business_day,stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d,'tasks_execute',4,'agent runs happened',
    jsonb_build_object('runs_24h',(select count(*) from agent_runs where started_at>now()-interval '24 hours'),
                       'errors_24h',(select count(*) from agent_runs where started_at>now()-interval '24 hours' and status='error')),
    (select count(*) from agent_runs where started_at>now()-interval '24 hours')>0,'all scheduled workers'
  on conflict (business_day,stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d,'results_measured',5,'outcomes gradeable and KPIs measurable',
    jsonb_build_object('outcomes_pending',(select count(*) from outcome_record where verdict='pending'),
                       'kpis_measurable',(select count(*) from employee_kpi where active and measure_sql is not null)),
    (select count(*) from employee_kpi where active and measure_sql is not null)>0,'outcome_evaluate_daily / kpi_review_weekly'
  on conflict (business_day,stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d,'lessons_learned',6,'dept_learn_daily fired and succeeded',
    jsonb_build_object('cron_ok',fn_cron_ran('dept_learn_daily'),
                       'memory_rows',(select count(*) from institutional_memory)),
    fn_cron_ran('dept_learn_daily'),'dept_learn_daily (does not always write agent_runs)'
  on conflict (business_day,stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d,'knowledge_updated',7,'knowledge touched in the last 24h',
    jsonb_build_object('touched_24h',(select count(*) from agent_knowledge where updated_at>now()-interval '24 hours')),
    (select count(*) from agent_knowledge where updated_at>now()-interval '24 hours')>0,'kb_deepen / knowledge_curator_daily'
  on conflict (business_day,stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d,'tomorrow_planned',8,'open work exists',
    jsonb_build_object('open_tasks',(select count(*) from org_tasks where status<>'done')),
    (select count(*) from org_tasks where status<>'done')>0,'dept_plan_daily / kpi_review_weekly'
  on conflict (business_day,stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  select count(*) filter (where ok), count(*) filter (where not ok) into v_ok, v_bad
    from day_cadence where business_day=d;

  if v_bad>0 then
    insert into founder_alerts (level,event,detail,channel)
    select 'high','daily_cadence_broken',
      'The daily operating loop did not complete. Failed stages: '||
      (select string_agg(stage,', ' order by stage_order) from day_cadence where business_day=d and not ok),'email'
    where not exists (select 1 from founder_alerts where event='daily_cadence_broken' and created_at>now()-interval '20 hours');
  end if;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('day_conductor',now(),now(),case when v_bad>0 then 'error' else 'ok' end,
    jsonb_build_object('stages_ok',v_ok,'stages_failed',v_bad),
    'Daily operating rhythm: '||v_ok||' of '||(v_ok+v_bad)||' stages verified.');

  return jsonb_build_object('day',d,'ok',v_ok,'failed',v_bad);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_dispute_open(p_stripe_dispute_id text, p_stripe_charge_id text, p_payment_ref text, p_amount_aed numeric, p_reason text, p_evidence_due_by timestamp with time zone)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id bigint; v_txn bigint;
begin
  select id into v_txn from transactions where payment_ref = p_payment_ref limit 1;

  insert into payment_dispute (stripe_dispute_id, stripe_charge_id, payment_ref, transaction_id,
                               amount_aed, reason, evidence_due_by)
  values (p_stripe_dispute_id, p_stripe_charge_id, p_payment_ref, v_txn,
          p_amount_aed, p_reason, p_evidence_due_by)
  on conflict (stripe_dispute_id) do update set
    status = 'needs_response', evidence_due_by = excluded.evidence_due_by
  returning id into v_id;

  insert into founder_alerts (level, event, detail, channel)
  values ('crit','payment_dispute',
          format('Card dispute opened: AED %s, reason "%s", evidence due %s. Stripe dispute %s. An unanswered dispute is lost automatically and counts toward the account dispute rate.',
                 coalesce(p_amount_aed,0), coalesce(p_reason,'unknown'),
                 coalesce(p_evidence_due_by::text,'unknown'), p_stripe_dispute_id),
          'system');

  insert into company_event (event_type, entity_type, entity_id, actor, payload)
  values ('invoice.flagged','dispute', p_stripe_dispute_id, 'ceo',
          jsonb_build_object('amount_aed', p_amount_aed, 'reason', p_reason,
                             'evidence_due_by', p_evidence_due_by, 'transaction_id', v_txn));

  insert into institutional_memory (kind, subject_type, subject_id, headline, detail, outcome,
                                    money_aed, learned_by, confidence, evidence_ref)
  values ('pattern','dispute', p_stripe_dispute_id,
          'Card dispute opened on a reveal fee.',
          format('Reason "%s" on AED %s. Disputes on a facilitation fee usually mean the buyer did not understand what they paid for, or the supplier never responded after reveal.', coalesce(p_reason,'unknown'), coalesce(p_amount_aed,0)),
          'open', p_amount_aed, 'ceo', 1.0, 'payment_dispute id '||v_id);

  return v_id;
end; $function$;

CREATE OR REPLACE FUNCTION public.fn_doc_expiry_scan()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  rec record; v_go boolean; v_status text; v_n_actions int := 0; v_n_requests int := 0; v_n_held int := 0;
  v_blocks json; v_site text; v_reply text;
begin
  -- A RENEWAL REMINDER IS NOT AN INVITATION. v_go used to read app_secrets.invite_enabled, the
  -- cold-outreach campaign switch, so a supplier already on the books could not be told their own
  -- trade licence was about to lapse until a marketing campaign was running. Two unrelated things
  -- were sharing one switch: asking a stranger to join, and telling a member their document
  -- expires. The second is service mail to someone who gave us the document in the first place,
  -- it goes to an address already on their record, and withholding it is worse for them than
  -- sending it -- matching is suspended automatically on the day the licence lapses either way.
  --
  -- Founder ruling 7 Sep 2026: every gate that is not OpenRouter comes off. This one comes off by
  -- being deleted rather than defaulted, so nothing can quietly close it again.
  v_go := true;
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from app_secrets where key = 'public_site_url';
  select coalesce(nullif(btrim(value), ''), 'docs@mail.quotesdone.com') into v_reply from app_secrets where key = 'email_reply_supplier_docs';

  for rec in
    select l.id, l.company_name, l.email, d.doc, d.exp, (d.exp < current_date) as expired
      from leads l
      cross join lateral (values
        ('trade licence', l.license_expiry),
        ('insurance', l.insurance_expiry),
        ('registration', l.registration_expires_at::date),
        ('ISO certification', l.iso_expiry),
        ('manufacturer authorisation', l.manufacturer_auth_expiry)) d(doc, exp)
     where coalesce(l.approval_status, '') = 'approved' and coalesce(l.banned, false) = false
       and d.exp is not null and d.exp <= current_date + 30
     order by d.exp, l.id
  loop
    -- 1. the renewal request to the supplier, into the outbox.
    if rec.email is not null and rec.email <> ''
       and not exists (select 1 from notifications n
                        where n.type = 'doc_renewal_request' and n.lead_id = rec.id
                          and n.subject like '%' || rec.doc || '%' and n.created_at > now() - interval '20 days') then
      v_status := case when v_go or rec.email ~* '@example[.]invalid$' then 'queued' else 'held' end;
      insert into notifications (type, to_email, to_role, lead_id, channel, status, subject, body, last_error)
      values ('doc_renewal_request', rec.email, 'supplier', rec.id, 'email', v_status,
              case when rec.expired then 'Action needed: your ' || rec.doc || ' on QuotesDone has expired'
                   else 'Your ' || rec.doc || ' on QuotesDone expires on ' || to_char(rec.exp, 'DD Mon YYYY') end,
              'Dear ' || coalesce(nullif(btrim(rec.company_name), ''), 'supplier') || ',' || E'\n\n'
              || case when rec.expired
                      then 'The ' || rec.doc || ' on your QuotesDone supplier profile expired on ' || to_char(rec.exp, 'DD Mon YYYY')
                           || '. Until a valid document is on file your company is not matched to new requests for quotation.'
                      else 'The ' || rec.doc || ' on your QuotesDone supplier profile expires on ' || to_char(rec.exp, 'DD Mon YYYY')
                           || '. To keep receiving requests for quotation without interruption, please upload the renewed document before that date.' end
              || E'\n\n' || 'Upload it in your supplier portal: ' || v_site || '/en/portal' || E'\n'
              || 'or reply to this email with the document attached (' || v_reply || ').' || E'\n\n'
              || 'QuotesDone Supplier Verification',
              case when v_status = 'held' then 'HELD by fn_doc_expiry_scan: supplier outbound waits for the founder''s go (app_secrets.invite_enabled).' end);
      v_n_requests := v_n_requests + 1;
      if v_status = 'held' then v_n_held := v_n_held + 1; end if;
    end if;

    -- 3. the record of it, once per document per 20 days.
    if not exists (select 1 from agent_actions a
                    where a.kind in ('licence_expiring', 'licence_expired') and a.target_table = 'leads'
                      and a.target_id = rec.id::text and a.title like '%' || rec.doc || '%'
                      and a.created_at > now() - interval '20 days') then
      insert into agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id,
                                 confidence, evidence, decided_by, decided_at, expected_impact, cost)
      values ('customer_support',
              case when rec.expired then 'licence_expired' else 'licence_expiring' end,
              'auto_done', case when rec.expired then 'medium' else 'low' end,
              coalesce(nullif(btrim(rec.company_name), ''), 'Supplier #' || rec.id) || ' — ' || rec.doc
              || case when rec.expired then ' EXPIRED on ' else ' expires on ' end || to_char(rec.exp, 'DD Mon YYYY'),
              case when rec.expired
                   then 'Renewal request written to the supplier outbox; matching suspended by fn_reconcile_licence_blocks until the date on file is renewed.'
                   else 'Renewal request written to the supplier outbox ' || (rec.exp - current_date) || ' day(s) ahead; matching is suspended automatically on the day it lapses.' end,
              jsonb_build_object('document', rec.doc, 'expires_on', rec.exp, 'days_left', rec.exp - current_date,
                                 'renewal_request', case when rec.email is null or rec.email = '' then 'no email on file'
                                                         when v_go or rec.email ~* '@example[.]invalid$' then 'queued' else 'held' end,
                                 'supplier_outbound_go', v_go),
              'leads', rec.id::text, 1.0,
              jsonb_build_object('basis', 'leads.' || case rec.doc when 'trade licence' then 'license_expiry' when 'insurance' then 'insurance_expiry'
                                                                    when 'registration' then 'registration_expires_at' when 'ISO certification' then 'iso_expiry'
                                                                    else 'manufacturer_auth_expiry' end || ' read by fn_doc_expiry_scan on ' || current_date),
              'doc_expiry_scan', now(),
              'An approved supplier with a lapsed document is not matched; a renewed one keeps its supply available.',
              'No spend: one outbox email; the supplier bears the renewal fee.');
      v_n_actions := v_n_actions + 1;
    end if;
  end loop;

  -- 2. the suspension and the restoration, from the dates on file.
  v_blocks := public.fn_reconcile_licence_blocks(0);

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('doc_expiry_scan', now(), now(), 'ok',
          jsonb_build_object('actions', v_n_actions, 'renewal_requests', v_n_requests, 'held', v_n_held,
                             'suspended', (v_blocks->>'suspended')::int, 'restored', (v_blocks->>'restored')::int,
                             'supplier_outbound_go', v_go),
          'Document expiry scan: ' || v_n_actions || ' action(s) recorded, ' || v_n_requests
          || ' renewal request(s) written to the outbox (' || v_n_held || ' held pending the founder''s go), '
          || (v_blocks->>'suspended') || ' supplier(s) suspended for a lapsed licence, '
          || (v_blocks->>'restored') || ' restored.');

  return jsonb_build_object('actions', v_n_actions, 'renewal_requests', v_n_requests, 'held', v_n_held,
                            'suspended', (v_blocks->>'suspended')::int, 'restored', (v_blocks->>'restored')::int,
                            'supplier_outbound_go', v_go, 'scanned_at', now());
end $function$;

CREATE OR REPLACE FUNCTION public.fn_event_consolidate()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r record; v_outcome text; v_note text; v_backbone text; v_lesson bigint; v_sev text;
  n_closed int := 0; n_lessons int := 0; n_rollups int := 0; n_priorities int := 0;
  v_open_chains bigint := 0;
  -- Bounded like the dispatcher's batch, for the same reason: an unbounded first run on a backlog
  -- is how a burst happens.  The work is finite and the cron is hourly.
  c_max_close    constant int := 200;
  c_max_priority constant int := 25;
begin
  -- ── LINK 7 · the result comes back to the event that caused the work ────────────────────────
  -- A delivery whose task has closed but whose result column is still NULL is precisely the gap:
  -- the OS did the work and the event never heard.  org_tasks.result is the OS's own words; the
  -- status is the fallback when it closed without writing one.
  for r in
    select d.id as delivery_id, d.event_id, d.task_id, d.os_key,
           t.status, t.result, t.title, t.updated_at, e.correlation_id, e.event_type
      from event_delivery d
      join org_tasks t     on t.id = d.task_id
      join company_event e on e.id = d.event_id
     where d.closed_at is null and t.status in ('done','closed')
     order by d.id
     limit c_max_close
  loop
    update event_delivery
       -- ->> not nullif(...,''): org_tasks.result is jsonb and event_delivery.result is text.
       set result    = left(coalesce(nullif(r.result->>'summary',''),
                                     r.status || ': ' || coalesce(r.title,'')), 1000),
           closed_at = coalesce(r.updated_at, now())
     where id = r.delivery_id;
    n_closed := n_closed + 1;

    -- ── LINK 10 · Knowledge captures the lesson from an EVENT outcome ─────────────────────────
    -- Joined through event_delivery.task_id, which is what makes the lesson traceable to a
    -- dispatched event rather than to a task that arrived some other way.
    if not exists (select 1 from institutional_memory m
                    where m.subject_type = 'org_task' and m.subject_id = r.task_id::text) then
      v_lesson := public.fn_task_lesson(r.task_id, 'event_closed',
                    jsonb_build_object('event_type', r.event_type,
                                       'correlation_id', r.correlation_id::text,
                                       'os_key', r.os_key));
      if v_lesson is not null then n_lessons := n_lessons + 1; end if;
    end if;
  end loop;

  -- ── LINK 8 · the Chief of Staff consolidates ACROSS OSes ───────────────────────────────────
  -- One row per business episode, not per event: correlation_id is the episode.  os_count is the
  -- number of distinct Operating Systems the episode touched, which is the difference between a
  -- consolidation and a receipt.
  --
  -- LINK 4 IS READ HERE.  Each OS records an event_assessment — severity, impact, proposed action
  -- — before it raises a task, and until now nothing ever looked at one.  The episode's assessed
  -- severity travels with the consolidation into priority_note and into the priority.updated
  -- payload, so what the OSes said about impact reaches the person re-prioritising on it.
  for r in
    select e.correlation_id,
           min(e.id)                                        as root_event_id,
           (array_agg(e.event_type order by e.id))[1]       as root_type,
           count(distinct d.os_key)                         as os_count,
           count(d.task_id)                                 as tasks_total,
           count(*) filter (where d.closed_at is not null)   as tasks_closed,
           (select count(*) from event_assessment a
              join company_event ae on ae.id = a.event_id
             where ae.correlation_id = e.correlation_id)     as assessed,
           (select max(case a.severity when 'high' then 3 when 'medium' then 2 else 1 end)
              from event_assessment a
              join company_event ae on ae.id = a.event_id
             where ae.correlation_id = e.correlation_id)     as sev_rank
      from company_event e
      join event_delivery d on d.event_id = e.id
     where e.correlation_id is not null
     group by e.correlation_id
  loop
    -- Defence 2: never consolidate a chain a re-prioritisation started.
    if r.root_type = 'priority.updated' then continue; end if;

    v_outcome := case when r.tasks_total = 0                  then 'no_work'
                      when r.tasks_closed = 0                 then 'open'
                      when r.tasks_closed < r.tasks_total     then 'partial'
                      else 'closed' end;
    v_sev := case r.sev_rank when 3 then 'high' when 2 then 'medium' when 1 then 'low'
                             else 'unassessed' end;
    v_note := format('%s across %s OS: %s of %s task(s) closed. Impact: %s assessment(s), highest severity %s.',
                     r.root_type, r.os_count, r.tasks_closed, r.tasks_total,
                     coalesce(r.assessed,0), v_sev);

    insert into event_rollup (correlation_id, root_event_id, event_type, os_count,
                              tasks_total, tasks_closed, outcome, priority_note, consolidated_at)
    values (r.correlation_id, r.root_event_id, r.root_type, r.os_count,
            r.tasks_total, r.tasks_closed, v_outcome, v_note, now())
    on conflict (correlation_id) do update
      set os_count = excluded.os_count, tasks_total = excluded.tasks_total,
          tasks_closed = excluded.tasks_closed, outcome = excluded.outcome,
          priority_note = excluded.priority_note, consolidated_at = excluded.consolidated_at;
    n_rollups := n_rollups + 1;

    -- ── LINK 9 · the CEO re-prioritises off the consolidated outcome ──────────────────────────
    -- The episode must have crossed an OS boundary — a single-OS chain is that OS's own business
    -- and does not move company priorities — and at least one OS must have RETURNED something,
    -- because a priority cannot be revised against an outcome that does not exist yet.
    --   Deliberately not 'closed' only. Measured on production: all 22 cross-OS episodes sit at
    --   0/4 or 1/4 tasks closed, and one task that never closes would hold the whole episode — and
    --   the company's priorities — hostage forever. Link 9 says "off event OUTCOMES", not "off all
    --   of them". One re-prioritisation per episode either way: the dedupe is on correlation_id.
    if v_outcome in ('closed','partial') and r.os_count > 1 and n_priorities < c_max_priority
       and not exists (select 1 from company_event ce
                        where ce.event_type = 'priority.updated'
                          and ce.correlation_id = r.correlation_id) then
      -- xos-14. This event is CAUSED by the root of the chain and belongs to the same chain. The
      -- settings are read by company_event's column defaults, which is why fn_emit does not name
      -- either column.  Defence 1 lives here: same correlation_id => the `not exists` above is
      -- permanently true for this episode from the next run onward.
      perform set_config('app.correlation_id',      r.correlation_id::text, true);
      perform set_config('app.causation_event_id',  r.root_event_id::text,  true);
      perform public.fn_emit('priority.updated', 'event_chain', r.correlation_id::text, 'ceo',
                jsonb_build_object('root_event_id', r.root_event_id, 'root_type', r.root_type,
                                   'os_count', r.os_count, 'tasks_closed', r.tasks_closed,
                                   'assessments', coalesce(r.assessed,0), 'max_severity', v_sev,
                                   'note', v_note));
      perform set_config('app.correlation_id',     '', true);
      perform set_config('app.causation_event_id', '', true);
      n_priorities := n_priorities + 1;
    end if;
  end loop;

  -- The Knowledge OS's declared output. One per run rather than one per lesson: the bus carries
  -- the fact that institutional memory moved, not 58 copies of it.
  if n_lessons > 0 then
    perform public.fn_emit('knowledge.updated', 'institutional_memory', 'event_lessons',
              'ceo', jsonb_build_object('lessons_added', n_lessons));
  end if;

  -- ── xos-15 · somebody looks at the bus ─────────────────────────────────────────────────────
  -- v_event_backbone is the one surface that says which subscribed event types are live, which
  -- have never fired and which are undelivered.  It had zero readers, which made it a diagram.
  -- chains_open is the consolidation backlog the view now carries: episodes that reached an OS
  -- and have not finished.  Reported here so the number lands in agent_runs rather than only in
  -- the view definition.
  select coalesce(string_agg(event_type || ' ' || state, ', ' order by event_type),
                  'every subscribed event type is LIVE')
    into v_backbone
    from v_event_backbone where state <> 'LIVE';

  select coalesce(sum(chains_open), 0) into v_open_chains from v_event_backbone;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('event_consolidate', now(), now(), 'ok',
          jsonb_build_object('deliveries_closed', n_closed, 'lessons', n_lessons,
                             'rollups', n_rollups, 'priorities_emitted', n_priorities,
                             'chains_open', v_open_chains),
          'Cross-OS contract closed: ' || n_closed || ' delivery result(s) returned, ' || n_lessons
          || ' lesson(s) captured, ' || n_rollups || ' chain(s) consolidated, ' || n_priorities
          || ' re-prioritisation(s) emitted, ' || v_open_chains || ' episode(s) still open. '
          || 'Bus backbone: ' || v_backbone);

  return jsonb_build_object('deliveries_closed', n_closed, 'lessons', n_lessons,
                            'rollups', n_rollups, 'priorities_emitted', n_priorities,
                            'chains_open', v_open_chains, 'bus_backbone', v_backbone);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_exec_meeting()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare m jsonb; findings jsonb := '[]'::jsonb; actions int := 0; recs jsonb;
  -- the six agenda sections, rebuilt per contribution, plus their company-scoped counterparts
  v_wins text; v_probs text; v_risks text; v_opps text; v_reqs text; v_kpis jsonb;
  v_ask text; v_target jsonb;
  v_dept text; v_opp_all int; v_co jsonb; p record; v_challenger text; v_ch int := 0;
  v_period text := to_char(now(),'IYYY-"W"IW');
  v_rev numeric; v_spend numeric; v_sup int; v_open int; v_avail numeric;
  v_red int; v_amber int; v_green int; r record; v_drivers text;
  v_report_id bigint; v_raised int := 0;
  -- SURVIVAL LINE: cash, burn and runway, read once from fn_ws_finance (already computed).
  v_fin jsonb; v_cash numeric; v_burn numeric; v_runway numeric; v_fin_health text; v_fin_raised int := 0;
begin
  -- EVERY ACTIVE OPERATING SYSTEM MUST HAVE THIS WEEK'S REVIEW BEFORE THE MEETING READS IT.
  -- "A row exists for the period" let a review taken before an OS was created stand in for it, and
  -- let a retired OS keep its seat. fn_os_review upserts on (os_key, period), so re-running it for a
  -- missing OS is safe.
  if exists (select 1 from operating_system o where o.active
              and not exists (select 1 from os_review rv where rv.os_key = o.os_key and rv.period = v_period)) then
    perform fn_os_review();
  end if;

  -- Counted over the ACTIVE operating systems, the same population the agenda iterates below. An
  -- active OS the review could not produce a row for is amber: unreviewed is not green.
  -- (alias rv, not r: r is the loop RECORD below, and plpgsql would read r.health as its field)
  select count(*) filter (where rv.health='red'),
         count(*) filter (where coalesce(rv.health,'amber')='amber'),
         count(*) filter (where rv.health='green')
    into v_red, v_amber, v_green
    from operating_system o
    left join os_review rv on rv.os_key = o.os_key and rv.period = v_period
   where o.active;

  select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) into v_rev from transactions where revealed_at > now()-interval '7 days';
  select coalesce(sum(cost_aed),0) into v_spend from ai_cost_log where occurred_at > now()-interval '7 days';
  select count(*) into v_sup from leads where approval_status='approved';
  select count(*) into v_open from org_tasks where status<>'done';
  select round(100.0*count(*) filter (where ok)/nullif(count(*),0),1) into v_avail
    from health_checks where check_kind='http' and created_at > now()-interval '7 days';

  select count(*) into v_opp_all from opportunity where coalesce(status,'open')='open';

  m := jsonb_build_object('week',v_period,'os_green',v_green,'os_amber',v_amber,'os_red',v_red,
       'revenue_7d_aed',v_rev,'ai_spend_7d_aed',round(coalesce(v_spend,0),2),
       'approved_suppliers',v_sup,'supplier_target',860,
       'open_tasks',v_open,'platform_availability_pct',v_avail);

  -- THE SURVIVAL LINE. One read of fn_ws_finance; carry it in the metrics so the meeting's KPI blob
  -- and every report built from it carries cash/burn/runway. runway_months is only a real number
  -- when the company is burning AND has cash, so burn and cash are tested first.
  v_fin := public.fn_ws_finance();
  v_cash := coalesce((v_fin->'cash'->>'total')::numeric, 0);
  v_burn := coalesce((v_fin->'run_rate'->>'monthly_burn')::numeric, 0);
  v_runway := nullif(v_fin->'run_rate'->>'runway_months','')::numeric;
  v_fin_health := case when v_burn <= 0 then 'green'
                       when v_cash <= 0 then 'red'
                       when v_runway < 3 then 'red'
                       when v_runway < 6 then 'amber'
                       else 'green' end;
  m := m || jsonb_build_object('cash_aed', v_cash, 'monthly_burn_aed', v_burn, 'runway_months', v_runway);

  -- AGENDA ITEM PER ACTIVE OPERATING SYSTEM, named with its owner AND with the live per-OS figures
  -- out of v_os_health that put it there. Both joins are LEFT: an OS the review could not produce a
  -- row for still reaches the agenda (amber, with a finding saying so), and an OS the view cannot
  -- resolve reaches it without drivers.
  for r in
    select o.num, o.name,
           coalesce(r2.health, 'amber') health,
           coalesce(r2.owner_agent, o.owner_agent) owner_agent,
           coalesce(r2.findings, jsonb_build_array(jsonb_build_object(
             'issue', 'no review this week',
             'detail', 'fn_os_review produced no row for this operating system in '||v_period||'.'))) findings,
           h.open_risks, h.kpi_gaps, h.backlog_per_head, h.stale_tasks,
           h.review_pass_pct, h.budget_pct, h.needs_founder_pct,
           r2.metrics->>'capacity_pct' capacity_pct
    from operating_system o
    left join os_review r2 on r2.os_key = o.os_key and r2.period = v_period
    left join v_os_health h on h.os_key = o.os_key
    where o.active
    order by
      case coalesce(r2.health, 'amber') when 'red' then 1 when 'amber' then 2 else 3 end, o.num
  loop
    v_drivers := 'open_risks '||coalesce(r.open_risks::text,'?')
      ||', kpi_gaps '||coalesce(r.kpi_gaps::text,'?')
      ||', capacity_pct '||coalesce(r.capacity_pct,'?')
      ||', backlog_per_head '||coalesce(r.backlog_per_head::text,'?')
      ||', stale_tasks '||coalesce(r.stale_tasks::text,'?')
      ||', review_pass_pct '||coalesce(r.review_pass_pct::text,'?')
      ||', budget_pct '||coalesce(r.budget_pct::text,'?')
      ||', needs_founder_pct '||coalesce(r.needs_founder_pct::text,'?');
    v_dept := (select department from org_agents where agent_key = r.owner_agent);

    v_wins := (select count(*) from org_tasks
                where status='done' and updated_at > now()-interval '7 days' and dept_key = v_dept)
      ||' task(s) closed in the last 7 days'
      || coalesce(': '||(select string_agg(w.title, '; ') from (
             select title from org_tasks where status='done'
              and updated_at > now()-interval '7 days' and dept_key = v_dept
              order by updated_at desc limit 3) w), '')||'.';

    v_probs := case when jsonb_typeof(r.findings)='array' and jsonb_array_length(r.findings) > 0
      then (select string_agg(coalesce(e->>'issue', e::text)||coalesce(' — '||(e->>'detail'), ''), '; ')
              from jsonb_array_elements(r.findings) e)
      else 'No unresolved finding recorded for this operating system in '||v_period||'.' end;

    v_kpis := jsonb_build_object('health', r.health,
      'open_risks', r.open_risks, 'kpi_gaps', r.kpi_gaps, 'capacity_pct', r.capacity_pct,
      'backlog_per_head', r.backlog_per_head, 'stale_tasks', r.stale_tasks,
      'review_pass_pct', r.review_pass_pct, 'budget_pct', r.budget_pct,
      'needs_founder_pct', r.needs_founder_pct);

    v_risks := (select count(*) from risk_register
                 where coalesce(status,'open') <> 'closed' and dept_key = v_dept)
      ||' open risk(s) on the register'
      || coalesce(': '||(select string_agg(k.risk, '; ') from (
             select risk from risk_register where coalesce(status,'open') <> 'closed'
              and dept_key = v_dept order by updated_at desc nulls last limit 3) k), '')||'.';

    v_opps := (select count(*) from opportunity op join org_agents oa on oa.agent_key = op.detected_by
                where coalesce(op.status,'open')='open' and oa.department = v_dept)
      ||' open opportunit(ies) attributed to this operating system'
      || coalesce(': '||(select string_agg(x.title, '; ') from (
             select op.title from opportunity op join org_agents oa on oa.agent_key = op.detected_by
              where coalesce(op.status,'open')='open' and oa.department = v_dept
              order by op.value_score desc nulls last limit 3) x), '')
      ||'; '||v_opp_all||' open company-wide.';

    -- HELD WITH THE ROLE, NOT THE FOUNDER. needs_founder on an org_task is a review hold owned by the
    -- department lead; the only decision that reaches the founder is a refund, and
    -- fn_founder_refund_approvals_open() is the one count for that. A cancelled task is not held.
    v_reqs := (select count(*) from org_tasks
                where needs_founder and status not in ('done','cancelled') and dept_key = v_dept)
      ||' item(s) held with '||coalesce((select d.lead_agent from org_departments d where d.dept_key = v_dept), v_dept, 'the department lead')
      || coalesce(': '||(select string_agg(q.title, '; ') from (
             select title from org_tasks where needs_founder and status not in ('done','cancelled')
              and dept_key = v_dept order by created_at desc limit 3) q), '')
      ||'; '||public.fn_founder_refund_approvals_open()||' refund decision(s) with the founder.';

    -- THE QUANTIFIED ASK. The three drivers the owner can move this week, with where they stand
    -- and where they must be, in the same sentence and again as numbers. A green OS is asked to
    -- hold its figures, not to improve on zero.
    v_ask := case when r.health = 'green'
      then 'Hold: '||coalesce(r.kpi_gaps,0)||' KPI gap(s), '||coalesce(r.stale_tasks,0)
           ||' stale task(s), '||coalesce(r.open_risks,0)||' open risk(s) — keep all three at 0 through '
           ||to_char(current_date + 7, 'YYYY-MM-DD')||'.'
      else 'Close '||coalesce(r.kpi_gaps,0)||' KPI gap(s) → 0, clear '||coalesce(r.stale_tasks,0)
           ||' stale task(s) → 0 and retire '||coalesce(r.open_risks,0)||' open risk(s) → 0 by '
           ||to_char(current_date + 7, 'YYYY-MM-DD')
           ||coalesce('; budget at '||r.budget_pct||'% of month, stay under 70%', '')||'.' end;
    v_target := jsonb_build_object(
      'kpi_gaps', 0, 'stale_tasks', 0, 'open_risks', 0, 'budget_pct_max', 70,
      'current', jsonb_build_object('kpi_gaps', coalesce(r.kpi_gaps,0), 'stale_tasks', coalesce(r.stale_tasks,0),
                                    'open_risks', coalesce(r.open_risks,0), 'budget_pct', r.budget_pct),
      'by', to_char(current_date + 7, 'YYYY-MM-DD'));

    findings := findings || jsonb_build_array(jsonb_build_object(
      'item', r.num||'. '||r.name, 'owner', coalesce(r.owner_agent,'unassigned'),
      'health', r.health, 'finding', r.findings::text, 'drivers', v_drivers,
      'wins', v_wins, 'problems', v_probs, 'kpis', v_kpis,
      'risks', v_risks, 'opportunities', v_opps, 'requests', v_reqs,
      'ask', v_ask, 'target', v_target));
  end loop;

  -- COMPANY-LEVEL ITEMS the CEO owns directly. Each carries the same quantified ask.
  if coalesce(v_rev,0)=0 then
    findings := findings || jsonb_build_array(jsonb_build_object('item','Revenue','owner','ceo','health','amber',
      'finding','No revenue recognised in the last 7 days.',
      'ask','Revenue AED 0 in 7 days: book at least 1 revealed quote (3% reveal fee) by '||to_char(current_date + 7, 'YYYY-MM-DD')||'.',
      'target',jsonb_build_object('reveals_7d',1,'revenue_7d_aed_min',1,'current',jsonb_build_object('revenue_7d_aed',v_rev),'by',to_char(current_date + 7, 'YYYY-MM-DD'))));
  end if;
  if v_sup < 860 then
    findings := findings || jsonb_build_array(jsonb_build_object('item','Supplier coverage','owner','procurement','health',
      case when v_sup=0 then 'red' else 'amber' end,
      'finding', v_sup||' approved suppliers against a target of 860 (10 in each of 86 categories).',
      'ask','Approve '||(860 - v_sup)||' more suppliers to reach 860 (now '||v_sup||'); at least 10 this week.',
      'target',jsonb_build_object('approved_suppliers',860,'approved_this_week_min',10,'current',jsonb_build_object('approved_suppliers',v_sup))));
  end if;
  if coalesce(v_avail,100) < 99.5 then
    findings := findings || jsonb_build_array(jsonb_build_object('item','Platform availability','owner','cto','health','amber',
      'finding','Availability '||coalesce(v_avail,0)||'% against 99.5%.',
      'ask','Raise 7-day availability from '||coalesce(v_avail,0)||'% to 99.5%.',
      'target',jsonb_build_object('availability_pct',99.5,'current',jsonb_build_object('availability_pct',v_avail))));
  end if;
  -- SURVIVAL LINE ON THE AGENDA. The CFO owns it. It joins the agenda only when it is not green,
  -- like the three items above, and it always exists as a board report below.
  if v_fin_health <> 'green' then
    findings := findings || jsonb_build_array(jsonb_build_object('item','Runway & cash','owner','ceo','health',v_fin_health,
      'finding','Cash AED '||round(v_cash)||', monthly burn AED '||round(v_burn)||', runway '
        ||coalesce(v_runway::text,'—')||' months against a break-even target.',
      'ask','Cash AED '||round(v_cash)||' and burn AED '||round(v_burn)||'/month: cut burn or add cash until runway is at least 6 months (now '
        ||coalesce(v_runway::text,'—')||').',
      'target',jsonb_build_object('runway_months_min',6,'current',jsonb_build_object('cash_aed',v_cash,'monthly_burn_aed',v_burn,'runway_months',v_runway))));
    v_fin_raised := 1;
  end if;

  -- The company-level items above are contributions too, so they carry the same six sections,
  -- scoped to the company rather than to one department.
  v_co := jsonb_build_object(
    'wins', (select count(*) from org_tasks where status='done' and updated_at > now()-interval '7 days')
            ||' task(s) closed company-wide in the last 7 days.',
    'problems', v_red||' operating system(s) red and '||v_amber||' amber in '||v_period||'.',
    'kpis', m,
    'risks', (select count(*) from risk_register where coalesce(status,'open') <> 'closed')
             ||' open risk(s) on the company register.',
    'opportunities', v_opp_all||' open opportunit(ies) company-wide.',
    'requests', (select count(*) from org_tasks where needs_founder and status not in ('done','cancelled'))
                ||' item(s) held with department leads company-wide; '
                ||public.fn_founder_refund_approvals_open()||' refund decision(s) with the founder.');
  select coalesce(jsonb_agg(case when f ? 'wins' then f else f || v_co end order by ord), '[]'::jsonb)
    into findings from jsonb_array_elements(findings) with ordinality as t(f, ord);

  insert into org_tasks (dept_key,title,detail,status,tier,needs_founder,action_class)
  select coalesce((select department from org_agents where agent_key=f->>'owner'),'exec'),
    'Exec meeting '||v_period||': '||(f->>'item'),
    'Health: '||(f->>'health')||'. Owner: '||(f->>'owner')||'. '||(f->>'finding')
    ||coalesce(' Drivers: '||(f->>'drivers')||'.','')
    ||coalesce(' Ask: '||(f->>'ask'),'')
    ||' Raised at the weekly executive meeting. Close it, or bring evidence the standard is wrong.',
    'proposed','advisory',false,'exec_review'
  from jsonb_array_elements(findings) f
  where coalesce(f->>'health','') <> 'green'
    and not exists (select 1 from org_tasks t where t.title='Exec meeting '||v_period||': '||(f->>'item') and t.status<>'done');
  get diagnostics actions = row_count;

  select coalesce(jsonb_agg(jsonb_build_object(
           'rank', x.rn, 'owner', x.owner, 'priority', x.health,
           'title', x.item, 'why', x.finding, 'ask', x.ask, 'target', x.target) order by x.rn), '[]'::jsonb)
    into recs from (
      select row_number() over (order by case f->>'health' when 'red' then 1 else 2 end, ord) rn,
             f->>'item' item, f->>'owner' owner, f->>'health' health,
             case when f ? 'drivers' then f->>'problems' else f->>'finding' end finding,
             f->>'ask' ask, f->'target' target
        from jsonb_array_elements(findings) with ordinality as t(f, ord)
       where coalesce(f->>'health','') <> 'green') x;
  if jsonb_array_length(recs) = 0 then
    recs := jsonb_build_array(jsonb_build_object('rank', 1, 'owner', 'ceo', 'priority', 'hold',
      'title', 'Hold current priorities',
      'why', 'All operating systems green and company metrics within tolerance.',
      'ask', 'Hold: keep '||v_green||' of '||v_green||' active operating systems green through '||to_char(current_date + 7, 'YYYY-MM-DD')||'.',
      'target', jsonb_build_object('os_green', v_green, 'os_red', 0, 'os_amber', 0, 'by', to_char(current_date + 7, 'YYYY-MM-DD'))));
  end if;

  insert into exec_reports (officer,period,summary,findings,recommendations,metrics,status)
  values ('ceo',v_period,
    'Weekly executive meeting across all operating systems. '||v_green||' green, '||v_amber||' amber, '||v_red
    ||' red. '||jsonb_array_length(findings)||' agenda contribution(s), '||actions||' action(s) assigned.',
    findings, recs, m, 'open')
  on conflict do nothing;

  -- THE FINANCE BOARD REPORT. One report_type='finance' board_reports row per week, carrying the
  -- survival figures, so the board has a standing finance record independent of whether the agenda
  -- surfaced runway this week. Its own block: a failure here must not fail the meeting.
  begin
    if not exists (select 1 from board_reports
                    where report_type='finance' and week_start = date_trunc('week',current_date)::date) then
      insert into board_reports(week_start, title, body, kpis, report_type)
      values (date_trunc('week',current_date)::date,
        'Finance — runway, cash & burn ('||v_period||')',
        'Cash AED '||round(v_cash)||' · monthly burn AED '||round(v_burn)||' · runway '
          ||coalesce(v_runway::text,'—')||' months · ARR est AED '
          ||round(coalesce((v_fin->'run_rate'->>'arr_estimate')::numeric,0))
          ||' · net income (all-time) AED '||round(coalesce((v_fin->'pnl'->>'net_income')::numeric,0))
          ||'. Health: '||v_fin_health||'.',
        jsonb_build_object('cash_aed',v_cash,'monthly_burn_aed',v_burn,'runway_months',v_runway,
          'arr_estimate',(v_fin->'run_rate'->>'arr_estimate'),'net_income',(v_fin->'pnl'->>'net_income'),
          'health',v_fin_health,'period',v_period),
        'finance');
    end if;
  exception when others then
    v_fin_raised := v_fin_raised;   -- board report is best-effort; the meeting proceeds
  end;

  -- THE DEBATE.
  begin
    for p in select (e->>'rank')::int prank, e->>'title' ptitle, e->>'owner' powner
               from jsonb_array_elements(recs) e
              where (e->>'rank')::int <= 3 order by (e->>'rank')::int
    loop
      v_challenger := coalesce((select e2->>'owner' from jsonb_array_elements(recs) e2
                                 where coalesce(e2->>'owner','') <> coalesce(p.powner,'')
                                 order by (e2->>'rank')::int limit 1), 'ceo');
      perform fn_challenge('Exec meeting '||v_period||' priority '||p.prank||': '||p.ptitle,
                           coalesce(p.powner,'ceo'), v_challenger);
      v_ch := v_ch + 1;
    end loop;
  exception when others then
    v_ch := -1;
  end;

  -- THE PRIORITIES REACH THE DECISION QUEUE.
  begin
    select id into v_report_id from exec_reports
     where officer='ceo' and period=v_period order by created_at desc limit 1;

    if v_report_id is not null then
      for p in select (e->>'rank')::int prank, e->>'title' ptitle, e->>'owner' powner,
                      e->>'why' pwhy, e->>'priority' phealth
                 from jsonb_array_elements(recs) e order by (e->>'rank')::int
      loop
        if not exists (select 1 from agent_actions a
                        where a.target_table='exec_reports'
                          and a.target_id = v_report_id::text
                          and coalesce(a.title,'') = 'Exec priority '||p.prank||': '||p.ptitle) then
          insert into agent_actions (agent, kind, status, risk, title, recommendation, detail,
                                     target_table, target_id)
          values (coalesce(p.powner,'ceo'), 'report_recommendation', 'pending',
                  case when p.phealth='red' then 'high' else 'medium' end,
                  'Exec priority '||p.prank||': '||p.ptitle,
                  coalesce(p.pwhy,'Ranked priority '||p.prank||' from the '||v_period||' executive meeting.'),
                  jsonb_build_object('source','fn_exec_meeting','period',v_period,'rank',p.prank,
                                     'owner',p.powner,'health',p.phealth,'report_id',v_report_id),
                  'exec_reports', v_report_id::text)
          on conflict (agent, kind, target_id) where status = 'pending' do nothing;
          v_raised := v_raised + 1;
        end if;
      end loop;
    end if;
  exception when others then
    v_raised := -1;
  end;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('exec_meeting',now(),now(),'ok',
    jsonb_build_object('os_green',v_green,'os_amber',v_amber,'os_red',v_red,'findings',jsonb_array_length(findings),'actions',actions,
      'priorities',jsonb_array_length(recs),'challenges',v_ch,'raised_for_approval',v_raised,
      'runway_months',v_runway,'finance_health',v_fin_health),
    'Executive meeting '||v_period||': '||v_green||' green / '||v_amber||' amber / '||v_red||' red across all active operating systems, '||actions||' actions assigned, '
    ||jsonb_array_length(recs)||' ranked priorities, '
    ||case when v_ch < 0 then 'the challenge round failed' else v_ch||' challenge(s) put to a second officer' end
    ||', '||case when v_raised < 0 then 'raising priorities for approval failed' else v_raised||' priority(ies) raised as decisions held with their owners' end
    ||'. Finance '||v_fin_health||' (runway '||coalesce(v_runway::text,'—')||'mo).');

  return jsonb_build_object('week',v_period,'green',v_green,'amber',v_amber,'red',v_red,
                            'findings',jsonb_array_length(findings),'actions',actions,
                            'priorities',jsonb_array_length(recs),'challenges',v_ch,
                            'raised_for_approval',v_raised,
                            'finance_health',v_fin_health,'runway_months',v_runway,'metrics',m);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_founder_command_clarify(p_command_id bigint, p_answer text, p_actor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  cmd public.founder_command%rowtype;
  msg public.founder_command_message%rowtype;
  c record; v_combined text; v_qn text; v_owner text; v_child text;
  v_tasks bigint[] := '{}'; v_owners text[] := '{}'; v_task bigint;
  v_due timestamptz; v_wf text; v_start_event text; v_plan bigint; v_clar bigint;
  v_kernel jsonb; v_items int := 0; v_manager text; v_dept text;
  v_founder text;
begin
  v_founder := public.fn_phase_c_require_founder(p_actor);   -- raises 28000 for anyone else

  if coalesce(btrim(p_answer),'') = '' then
    return jsonb_build_object('ok', false, 'error','answer_required',
      'message','Say what you want and I will route it. An empty reply cannot resolve a clarification.');
  end if;
  select * into cmd from public.founder_command where command_id = p_command_id;
  if not found then return jsonb_build_object('ok', false, 'error','not_found'); end if;
  if cmd.state <> 'clarification_required' then
    return jsonb_build_object('ok', false, 'error','not_awaiting_clarification',
      'state', cmd.state,
      'message','This command is not waiting for a clarification.');
  end if;
  select * into msg from public.founder_command_message where message_id = cmd.message_id;

  -- The original instruction is never edited. The reply is APPENDED, on its own row, with its own
  -- timestamp, and the exact words the founder used.
  update public.founder_command_clarification
     set answer_text = p_answer, answered_at = now()
   where clarification_id = (select max(cl.clarification_id) from public.founder_command_clarification cl
                             where cl.command_id = p_command_id)
  returning clarification_id into v_clar;

  update public.founder_command set state = 'interpreting' where command_id = p_command_id;

  -- Re-interpret the instruction AND its clarification together, through the same deterministic
  -- classifier the first attempt used. No model is consulted; nothing is guessed.
  v_combined := coalesce(msg.raw_text,'') || E'\n' || p_answer;
  select * into c from public.fn_founder_command_classify(v_combined);

  insert into public.founder_command_interpretation
    (command_id, version, intent_id, confidence, matched_rule_id, workflow_ids,
     specificity_signals, reason)
  values (p_command_id,
          1 + coalesce((select max(i.version) from public.founder_command_interpretation i
                         where i.command_id = p_command_id), 0),
          c.intent_id, c.confidence, c.matched_rule_id, c.workflow_ids, c.specificity,
          'after clarification: ' || c.reason);

  -- Still not routable. Ask once more; still create nothing.
  if c.outcome not in ('ROUTE_AND_CREATE_TASKS','FOUNDER_INITIATED_POLICY_CHANGE',
                       'FOUNDER_INITIATED_PHASE_A_CHANGE','REFUND_APPROVAL') then
    v_qn := coalesce(nullif(c.reason,''), 'I still cannot route this safely.')
            || ' What exactly do you want changed, by how much, and by when?';
    insert into public.founder_command_clarification (command_id, question)
    values (p_command_id, v_qn);
    update public.founder_command set state = 'clarification_required' where command_id = p_command_id;
    return jsonb_build_object('ok', true, 'command_id', p_command_id,
      'status','clarification_required', 'tasks_created', 0, 'task_ids','[]'::jsonb,
      'owner','ceo', 'clarification', v_qn,
      'answer_recorded', true, 'clarification_id', v_clar, 'actor', v_founder);
  end if;

  -- Routable now. One command id, the plan and the tasks, in this transaction.
  update public.founder_command
     set intent_id = c.intent_id, outcome = c.outcome, priority = c.priority,
         primary_role_id = coalesce(nullif(c.primary_role_id,''), 'ceo'),
         state = 'accepted'
   where command_id = p_command_id;
  update public.founder_command set state = 'routed' where command_id = p_command_id;

  v_due := now() + case c.priority when 'P0' then interval '4 hours' when 'P1' then interval '2 days'
                                   when 'P2' then interval '5 days' else interval '10 days' end;
  v_wf := btrim(split_part(c.workflow_ids, ';', 1));

  insert into public.founder_command_workflow_link (command_id, workflow_id)
  select p_command_id, btrim(x) from unnest(string_to_array(c.workflow_ids, ';')) x
   where btrim(x) <> '' on conflict do nothing;

  select role_id into v_owner from public.fn_phase_c_resolve_actor(
    coalesce(nullif(c.primary_role_id,''), 'ceo'));
  -- ---- THE PLAN (not operational tasks) --------------------------------------------------
  -- K2 moved this for fn_founder_command_submit and left the clarify path behind, so answering a
  -- clarification still created four phase_c_task rows and no workflow run at all. Measured on
  -- command 270 through the real authenticated path on 17 Aug: tasks 4, runs 0, outbox 0.
  -- Plan items record who the command plan names. They are not work anybody is accountable for.
  if v_owner is not null then
    select r.manager_role_id, r.primary_department_id into v_manager, v_dept
      from public.org_role r where r.role_id = v_owner;
    insert into public.founder_command_plan_item
      (command_id, item_kind, role_id, department_id, summary, priority, workflow_id)
    values (p_command_id, 'primary', v_owner, coalesce(v_dept,''),
            left(v_combined, 1500), c.priority, nullif(v_wf,''))
    on conflict (command_id, item_kind, role_id) do nothing;
    v_items := v_items + 1; v_owners := v_owners || v_owner;
  end if;

  for v_child in select btrim(x) from unnest(string_to_array(c.child_role_ids, ';')) x where btrim(x) <> '' loop
    select role_id into v_owner from public.fn_phase_c_resolve_actor(v_child);
    continue when v_owner is null;
    select r.manager_role_id, r.primary_department_id into v_manager, v_dept
      from public.org_role r where r.role_id = v_owner;
    insert into public.founder_command_plan_item
      (command_id, item_kind, role_id, department_id, summary, priority, workflow_id)
    values (p_command_id, 'contribution', v_owner, coalesce(v_dept,''),
            'Contribution required by the command plan for ' || v_child || ': ' || left(v_combined, 1500),
            c.priority, nullif(v_wf,''))
    on conflict (command_id, item_kind, role_id) do nothing;
    v_items := v_items + 1; v_owners := v_owners || v_owner;
  end loop;

  -- ---- THE WORK --------------------------------------------------------------------------------
  -- One call, one run, one operational task, one factual event — the same kernel entry point the
  -- submit path uses, so the two can no longer drift apart.
  if coalesce(v_wf,'') <> '' and exists (select 1 from public.phase_b_workflow where workflow_id = v_wf) then
    v_kernel := public.fn_kernel_workflow_start(jsonb_build_object(
      'workflow_id', v_wf,
      'business_object_id', 'founder_command:' || p_command_id,
      'source_kind','founder_command',
      'source_ref','founder_command:' || p_command_id,
      'command_id', p_command_id,
      'correlation_id','cmd:' || p_command_id,
      'causation_id','command:' || p_command_id,
      'requested_by', v_founder,
      'priority', c.priority,
      'trigger_ctx', jsonb_build_object(
        'intent', c.intent_id, 'outcome', c.outcome, 'confidence', c.confidence,
        'matched_rule_id', c.matched_rule_id, 'after_clarification', true,
        'clarification_id', v_clar, 'plan_items', v_items)));
    v_task := (v_kernel->>'task_id')::bigint;
    v_start_event := v_kernel->>'event_id';
    if v_task is null then
      raise exception 'command %: the kernel returned no operational task for workflow %',
        p_command_id, v_wf using errcode = '23502';
    end if;
    insert into public.founder_command_task_link (command_id, task_id)
    values (p_command_id, v_task) on conflict do nothing;
    v_tasks := array[v_task];
    update public.phase_c_task set due_at = coalesce(due_at, v_due) where task_id = v_task;
  end if;

  insert into public.founder_command_plan (command_id, summary, child_task_count, departments)
  values (p_command_id,
          format('%s: %s after clarification. Command owner chief_of_staff; %s plan item(s), %s operational task against %s.',
                 c.intent_id, c.outcome, v_items, cardinality(v_tasks),
                 coalesce(nullif(c.workflow_ids,''),'no workflow')),
          v_items,
          coalesce((select string_agg(distinct t.department_id, '; ') from public.phase_c_task t
                     where t.command_id = p_command_id and t.department_id <> ''), ''))
  returning plan_id into v_plan;

  update public.founder_command set state = 'tasks_created', due_at = v_due
   where command_id = p_command_id;

  return jsonb_build_object('ok', true, 'command_id', p_command_id, 'status','tasks_created',
    'intent', c.intent_id, 'outcome', c.outcome, 'owner','ceo',
    'primary_owner', coalesce(v_owners[1],'founder'), 'task_ids', to_jsonb(v_tasks),
    'tasks_created', cardinality(v_tasks), 'workflow_id', v_wf,
    'event_emitted', v_start_event, 'plan_id', v_plan, 'clarification_id', v_clar,
    'answer_recorded', true, 'trace_id', cmd.trace_id, 'actor', v_founder,
    'interpretation','after clarification: ' || c.reason);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_founder_command_classify(p_text text)
 RETURNS TABLE(intent_id text, outcome text, workflow_ids text, primary_role_id text, child_role_ids text, priority text, confidence numeric, matched_rule_id text, specificity text, reason text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.phase_c_command_rule%rowtype; v_txt text := coalesce(p_text, '');
begin
  specificity := public.fn_phase_c_command_specificity(v_txt);
  for r in select * from public.phase_c_command_rule order by rule_order loop
    if v_txt ~* r.pattern and (r.antipattern = '' or not (v_txt ~* r.antipattern)) then
      if r.requires_specificity and specificity = '' then
        intent_id := 'AMBIGUOUS'; outcome := 'CLARIFICATION_REQUIRED';
        workflow_ids := ''; primary_role_id := 'ceo'; child_role_ids := '';
        priority := 'P2'; confidence := 0.35; matched_rule_id := r.rule_id;
        reason := format('matched %s but the instruction names no quantity, deadline, identifier or deliverable', r.rule_id);
        return next; return;
      end if;
      intent_id := r.intent_id; outcome := r.outcome; workflow_ids := r.workflow_ids;
      primary_role_id := r.primary_role_id; child_role_ids := r.child_role_ids;
      priority := r.priority; confidence := 0.95; matched_rule_id := r.rule_id;
      reason := format('deterministic registry rule %s (%s)', r.rule_id, r.notes);
      return next; return;
    end if;
  end loop;
  intent_id := 'AMBIGUOUS'; outcome := 'CLARIFICATION_REQUIRED'; workflow_ids := '';
  primary_role_id := 'ceo'; child_role_ids := ''; priority := 'P2';
  confidence := 0.0; matched_rule_id := '';
  reason := 'no registered command intent matches this instruction';
  return next;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_founder_command_rollup(p_command_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c public.founder_command%rowtype;
  n_total bigint; n_open bigint; n_blocked bigint; n_started bigint; n_failed bigint; n_done bigint;
  v_want text; v_summary text;
begin
  select * into c from public.founder_command where command_id = p_command_id for update;
  if not found then return null; end if;
  -- a terminal command is not re-opened by a late task movement
  if c.state in ('completed','cancelled','refused','superseded','failed') then return null; end if;

  select count(*),
         count(*) filter (where closed_at is null),
         count(*) filter (where state = 'blocked'),
         count(*) filter (where state in ('in_progress','accepted','review_required','revision_required')),
         count(*) filter (where state = 'failed'),
         count(*) filter (where state = 'completed')
    into n_total, n_open, n_blocked, n_started, n_failed, n_done
  from public.phase_c_task where command_id = p_command_id;

  if n_total = 0 then return null; end if;

  v_want := case
    when n_open = 0 and n_failed > 0 then 'failed'
    when n_open = 0                  then 'completed'
    when n_blocked > 0               then 'partially_blocked'
    when n_started > 0               then 'in_progress'
    else c.state
  end;
  if v_want = c.state then return null; end if;

  -- The frozen command state model still decides. A move it does not allow is not forced; the
  -- command stays where it is and the task movement is unaffected.
  if not exists (select 1 from public.phase_c_command_transition
                 where from_state = c.state and to_state = v_want) then
    return null;
  end if;

  update public.founder_command set
    state = v_want,
    closed_at = case when v_want in ('completed','failed') then now() else closed_at end
  where command_id = p_command_id;

  if v_want in ('completed','failed') then
    v_summary := format(
      '%s of %s task(s) completed, %s failed. Owners: %s.',
      n_done, n_total, n_failed,
      coalesce((select string_agg(distinct accountable_role_id, ', ' order by accountable_role_id)
                from public.phase_c_task where command_id = p_command_id), 'none'));
    insert into public.founder_command_completion (command_id, summary, evidence)
    values (p_command_id, v_summary, jsonb_build_object(
      'tasks_total', n_total, 'tasks_completed', n_done, 'tasks_failed', n_failed,
      'task_ids', coalesce((select jsonb_agg(task_id order by task_id)
                            from public.phase_c_task where command_id = p_command_id), '[]'::jsonb),
      'traces', coalesce((select jsonb_agg(trace_id) from public.phase_c_task
                          where command_id = p_command_id and trace_id is not null), '[]'::jsonb)))
    on conflict (command_id) do update set summary = excluded.summary,
      evidence = excluded.evidence, closed_at = now();

    perform public.fn_phase_c_trace_write('TRACE-FOUNDER-COMMAND', jsonb_build_object(
      'subject_kind','command', 'subject_ref', p_command_id::text, 'command_id', p_command_id,
      'actor_role_id','ceo', 'system_actor_id','system.task_engine',
      'state_before', c.state, 'state_after', v_want, 'status','sealed',
      'evidence_refs', jsonb_build_array(jsonb_build_object('completion_summary', v_summary))));
  end if;

  return v_want;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_founder_command_submit(p_founder_identity text, p_text text, p_idempotency_key text, p_ctx jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_start_event text; v_wf_selected text;
  c record; v_msg bigint; v_cmd bigint; v_existing bigint; v_trace bigint; v_task bigint;
  v_tasks bigint[] := '{}'; v_owners text[] := '{}'; v_overlays text[] := '{}';
  v_wf text; v_child text; v_owner text; v_kind text; v_manager text; v_dept text;
  v_action text; v_due timestamptz; v_intent public.phase_c_command_intent%rowtype;
  v_plan_id bigint; v_qn text; v_ov jsonb;
  v_kernel jsonb; v_items int := 0; v_status text;
begin
  if coalesce(p_founder_identity, '') = '' then
    raise exception 'founder identity is required' using errcode = '28000';
  end if;
  if not exists (select 1 from public.phase_c_founder_identity
                 where identity = lower(btrim(p_founder_identity)) and active) then
    return jsonb_build_object('ok', false, 'error', 'not_the_founder',
      'message', 'The Command Center accepts commands from the registered founder identity only.');
  end if;

  select m.message_id into v_msg from public.founder_command_message m
   where m.client_idempotency_key = p_idempotency_key;
  if v_msg is not null then
    select fc.command_id into v_existing from public.founder_command fc where fc.message_id = v_msg;
    return public.fn_founder_command_duplicate_result(v_existing, p_idempotency_key);
  end if;

  insert into public.founder_command_message
    (session_id, founder_identity, raw_text, raw_text_hash, client_idempotency_key, channel)
  values ((p_ctx->>'session_id')::bigint, lower(btrim(p_founder_identity)), p_text,
          encode(sha256(convert_to(coalesce(p_text,''), 'UTF8')), 'hex'), p_idempotency_key,
          coalesce(p_ctx->>'channel', 'command_center'))
  returning message_id into v_msg;

  select * into c from public.fn_founder_command_classify(p_text);

  insert into public.founder_command
    (message_id, intent_id, outcome, state, priority, primary_role_id,
     founder_initiated_only, refund_semantics)
  values (v_msg, c.intent_id, c.outcome, 'received', c.priority,
          coalesce(nullif(c.primary_role_id,''), 'ceo'),
          c.outcome in ('FOUNDER_INITIATED_POLICY_CHANGE','FOUNDER_INITIATED_PHASE_A_CHANGE'),
          c.outcome = 'REFUND_APPROVAL')
  returning command_id into v_cmd;
  if v_cmd is null then
    raise exception 'fn_founder_command_submit wrote no command row' using errcode = '23502';
  end if;

  insert into public.founder_command_interpretation
    (command_id, version, intent_id, confidence, matched_rule_id, workflow_ids, specificity_signals, reason)
  values (v_cmd, 1, c.intent_id, c.confidence, c.matched_rule_id, c.workflow_ids, c.specificity, c.reason);

  update public.founder_command set state = 'interpreting' where command_id = v_cmd;

  v_trace := public.fn_phase_c_trace_write('TRACE-FOUNDER-COMMAND', jsonb_build_object(
    'subject_kind','command', 'subject_ref', v_cmd::text, 'command_id', v_cmd,
    'actor_role_id','founder', 'system_actor_id','system.command_router',
    'input_hash', encode(sha256(convert_to(coalesce(p_text,''), 'UTF8')), 'hex'),
    'state_before','received', 'state_after','interpreting', 'status','open'));
  update public.founder_command set trace_id = v_trace where command_id = v_cmd;

  if c.outcome = 'REFUSE_UNSCOPED_UNSAFE_COMMAND' then
    update public.founder_command set state = 'refused', closed_at = now() where command_id = v_cmd;
    return jsonb_build_object('ok', true, 'command_id', v_cmd, 'status','refused',
      'intent', c.intent_id, 'interpretation', c.reason, 'workflow_ids','[]'::jsonb,
      'task_ids','[]'::jsonb, 'owner','ceo', 'tasks_created', 0,
      'blocker', 'Unscoped destructive or financial instruction. Name the individual cases and the evidence, and it will route.',
      'trace_id', v_trace);
  end if;

  -- A RETIRED RITUAL GETS A PLAIN REPLY, NOT A CLARIFICATION LOOP (5 Sep 2026). "I approve PCCR-008 ..."
  -- names a Phase C change request; phase freezes, PCCR/PACR/PBCR amendments and acceptance-standard
  -- signatures were abolished on 2 Sep 2026. Six such messages bounced back as "no registered intent"
  -- and sat at clarification_required. Rule CR-005 now classifies them; the reply is the rule's note
  -- (recorded on the interpretation row) and the command closes as refused: unsupported, with reason.
  if c.outcome = 'RETIRED_RITUAL_REPLY' then
    update public.founder_command set state = 'refused', closed_at = now() where command_id = v_cmd;
    return jsonb_build_object('ok', true, 'command_id', v_cmd, 'status','refused',
      'intent', c.intent_id, 'interpretation', c.reason, 'workflow_ids','[]'::jsonb,
      'task_ids','[]'::jsonb, 'owner','ceo', 'tasks_created', 0,
      'reply', (select r.notes from public.phase_c_command_rule r where r.rule_id = c.matched_rule_id),
      'blocker', 'Nothing to approve: the ritual this names was retired on 2 September 2026.',
      'trace_id', v_trace);
  end if;

  -- A STATUS ASK GETS THE BRIEF, NOT A CLARIFICATION (6 Sep 2026). "status" typed into the Console —
  -- whose placeholder says "Ask for a status…" — matched CR-020 (command_or_task_status, which needs an
  -- identifier) and bounced back as "I can route this, but not safely yet" (command 81887). Rule CR-004
  -- classifies a bare "status" / "brief" / "how are we doing" as CMD-BRIEF: the reply is the overnight
  -- brief sentence fn_ws_exec_home writes (the same text the Console's "speak the overnight brief"
  -- button reads), the command closes as accepted, and no task is minted.
  if c.outcome = 'BRIEF_REPLY' then
    update public.founder_command set state = 'accepted', closed_at = now() where command_id = v_cmd;
    return jsonb_build_object('ok', true, 'command_id', v_cmd, 'status','accepted',
      'intent', c.intent_id, 'interpretation', c.reason, 'control_command', true,
      'workflow_ids','[]'::jsonb, 'task_ids','[]'::jsonb, 'owner','ceo', 'tasks_created', 0,
      'reply', coalesce(public.fn_ws_exec_home()->>'brief_text', 'The company brief is not available right now.'),
      'trace_id', v_trace);
  end if;

  if c.intent_id = 'AMBIGUOUS' then
    v_qn := case when c.matched_rule_id <> ''
      then 'I can route this, but not safely yet. What exactly do you want changed, by how much, and by when?'
      else 'I have no registered intent for that. What outcome do you want, in which area, and by when?' end;
    insert into public.founder_command_clarification (command_id, question) values (v_cmd, v_qn);
    update public.founder_command set state = 'clarification_required' where command_id = v_cmd;
    return jsonb_build_object('ok', true, 'command_id', v_cmd, 'status','clarification_required',
      'intent','AMBIGUOUS', 'interpretation', c.reason, 'workflow_ids','[]'::jsonb,
      'task_ids','[]'::jsonb, 'owner','ceo', 'tasks_created', 0,
      'clarification', v_qn, 'trace_id', v_trace);
  end if;

  if c.intent_id in ('CMD-STATUS','CMD-CANCEL','CMD-REPRIORITIZE','CMD-EXPLAIN') then
    update public.founder_command set state = 'accepted' where command_id = v_cmd;
    return jsonb_build_object('ok', true, 'command_id', v_cmd, 'status','accepted',
      'intent', c.intent_id, 'interpretation', c.reason, 'control_command', true,
      'workflow_ids','[]'::jsonb, 'task_ids','[]'::jsonb, 'owner','ceo',
      'tasks_created', 0, 'trace_id', v_trace,
      'next', 'call fn_founder_command_control(command_id, op, target_ref, value)');
  end if;

  update public.founder_command set state = 'accepted' where command_id = v_cmd;
  select * into v_intent from public.phase_c_command_intent where intent_id = c.intent_id;

  v_due := now() + case c.priority when 'P0' then interval '4 hours'
                                   when 'P1' then interval '2 days'
                                   else interval '5 days' end;

  for v_wf in select btrim(x) from unnest(string_to_array(c.workflow_ids, ';')) x where btrim(x) <> '' loop
    if exists (select 1 from public.phase_b_workflow where workflow_id = v_wf) then
      insert into public.founder_command_workflow_link (command_id, workflow_id)
      values (v_cmd, v_wf) on conflict do nothing;
    end if;
  end loop;
  update public.founder_command set state = 'routed' where command_id = v_cmd;

  v_wf_selected := btrim(split_part(c.workflow_ids, ';', 1));

  -- ---- THE PLAN (was: four phase_c_task rows) ------------------------------------------------
  -- The primary interpretation.
  v_owner := coalesce(nullif(c.primary_role_id, ''), v_intent.default_accountable_role_id, 'ceo');
  if v_owner <> 'founder' then
    select role_id into v_owner from public.fn_phase_c_resolve_actor(v_owner);
    if v_owner is null then
      raise exception 'command %: primary owner does not resolve to an active canonical role', v_cmd
        using errcode = '23514';
    end if;
    select r.manager_role_id, r.primary_department_id into v_manager, v_dept
      from public.org_role r where r.role_id = v_owner;
    insert into public.founder_command_plan_item
      (command_id, item_kind, role_id, department_id, summary, priority, workflow_id)
    values (v_cmd, 'primary', v_owner, coalesce(v_dept,''),
            left(coalesce(p_text,''), 2000), c.priority, nullif(v_wf_selected,''))
    on conflict (command_id, item_kind, role_id) do nothing;
    v_items := v_items + 1;
    v_owners := v_owners || v_owner;
  end if;

  -- The contributions.
  for v_child in select btrim(x) from unnest(string_to_array(c.child_role_ids, ';')) x where btrim(x) <> '' loop
    select kind, role_id into v_kind, v_owner from public.fn_phase_c_resolve_actor(v_child);
    if v_kind = 'overlay' then
      v_ov := public.fn_phase_c_overlay_invoke(v_child, jsonb_build_object(
        'command_id', v_cmd, 'evidence_refs', jsonb_build_array('CMD-' || v_cmd)));
      insert into public.founder_command_overlay_invocation
        (command_id, overlay_id, live_role_id, returns_to_role_id, result, trace_id)
      values (v_cmd, coalesce(v_ov->>'overlay_id', v_child), v_owner,
              coalesce(v_ov->>'return_owner', coalesce(v_owners[1], 'ceo')),
              v_ov, (v_ov->>'trace_id')::bigint)
      on conflict (command_id, overlay_id) do nothing;
      v_overlays := v_overlays || coalesce(v_ov->>'overlay_id', v_child);
      continue;
    end if;
    continue when v_kind is distinct from 'canonical' or v_owner is null;
    select r.manager_role_id, r.primary_department_id into v_manager, v_dept
      from public.org_role r where r.role_id = v_owner;
    insert into public.founder_command_plan_item
      (command_id, item_kind, role_id, department_id, summary, priority, workflow_id)
    values (v_cmd, 'contribution', v_owner, coalesce(v_dept,''),
            'Contribution required by the command plan for ' || v_child || ': '
              || left(coalesce(p_text,''), 1500),
            c.priority, nullif(v_wf_selected,''))
    on conflict (command_id, item_kind, role_id) do nothing;
    v_items := v_items + 1;
    v_owners := v_owners || v_owner;
  end loop;

  -- ---- THE WORK (was: an event that a consumer turned into a fifth task) ---------------------
  -- One call, one run, one operational task, one factual event. The task carries command_id, so
  -- the founder's thread can see the work his instruction actually produced.
  if v_wf_selected <> '' and exists (select 1 from public.phase_b_workflow where workflow_id = v_wf_selected) then
    v_kernel := public.fn_kernel_workflow_start(jsonb_build_object(
      'workflow_id', v_wf_selected,
      'business_object_id', 'founder_command:' || v_cmd,
      'source_kind','founder_command',
      'source_ref','founder_command:' || v_cmd,
      'command_id', v_cmd,
      'correlation_id','cmd:' || v_cmd,
      'causation_id','command:' || v_cmd,
      'requested_by', lower(btrim(p_founder_identity)),
      'priority', c.priority,
      'trigger_ctx', jsonb_build_object(
        'intent', c.intent_id, 'outcome', c.outcome, 'confidence', c.confidence,
        'matched_rule_id', c.matched_rule_id,
        'raw_text_hash', encode(sha256(convert_to(coalesce(p_text,''), 'UTF8')), 'hex'),
        'plan_items', v_items)));
    v_task := (v_kernel->>'task_id')::bigint;
    v_start_event := v_kernel->>'event_id';
    if v_task is null then
      raise exception 'command %: the kernel returned no operational task for workflow %',
        v_cmd, v_wf_selected using errcode = '23502';
    end if;
    insert into public.founder_command_task_link (command_id, task_id)
    values (v_cmd, v_task) on conflict do nothing;
    v_tasks := array[v_task];
    -- The command's due date is the founder's, and it is applied to the task the kernel made.
    update public.phase_c_task set due_at = coalesce(due_at, v_due) where task_id = v_task;
  end if;

  insert into public.founder_command_plan (command_id, summary, child_task_count, departments)
  values (v_cmd,
          format('%s: %s. Command owner ceo; %s plan item(s) and %s operational task(s) against %s%s.',
                 c.intent_id, c.outcome, v_items, cardinality(v_tasks),
                 coalesce(nullif(c.workflow_ids,''), 'no workflow'),
                 case when cardinality(v_overlays) > 0
                      then format('; %s category overlay invocation(s): %s',
                                  cardinality(v_overlays), array_to_string(v_overlays, ', '))
                      else '' end),
          greatest(v_items - 1, 0),
          coalesce((select string_agg(distinct i.department_id, '; ')
                    from public.founder_command_plan_item i
                   where i.command_id = v_cmd and i.department_id <> ''), ''))
  on conflict (command_id) do update set summary = excluded.summary,
    child_task_count = excluded.child_task_count, departments = excluded.departments
  returning plan_id into v_plan_id;

  if c.outcome = 'REFUND_APPROVAL' then
    insert into public.founder_approval_request
      (command_id, action_class, subject_ref, prepared_by_role_id, amount_note, evidence, state)
    values (v_cmd, 'refund_decision',
            coalesce((regexp_match(p_text, '(TX-[A-Za-z0-9_-]+)'))[1], 'UNIDENTIFIED_TRANSACTION'),
            'ceo',
            'amount, reason, customer/supplier impact and fraud checks required before decision',
            jsonb_build_object('raw_command', left(coalesce(p_text,''), 500)), 'pending');
  end if;

  -- A command that produced no operational task did not create tasks, and does not claim to.
  if cardinality(v_tasks) > 0 then
    update public.founder_command set state = 'tasks_created', due_at = v_due where command_id = v_cmd;
    v_status := 'tasks_created';
  else
    update public.founder_command set due_at = v_due where command_id = v_cmd;
    v_status := 'routed';
  end if;

  return jsonb_build_object(
    'ok', true, 'command_id', v_cmd, 'status', v_status, 'intent', c.intent_id,
    'outcome', c.outcome, 'interpretation', c.reason,
    'workflow_ids', coalesce((select jsonb_agg(workflow_id order by workflow_id)
                              from public.founder_command_workflow_link where command_id = v_cmd), '[]'::jsonb),
    'task_ids', to_jsonb(v_tasks),
    'owner', 'ceo', 'primary_owner', coalesce(v_owners[1], 'founder'),
    'child_owners', to_jsonb(v_owners[2:]),
    'category_overlays_invoked', to_jsonb(v_overlays),
    'tasks_created', cardinality(v_tasks),
    'plan_items', v_items,
    'workflow_run_id', (v_kernel->>'run_id')::bigint,
    'step_run_id', (v_kernel->>'step_run_id')::bigint,
    'handoff_run_id', (v_kernel->>'handoff_run_id')::bigint,
    'event_id', v_start_event, 'outbox_id', (v_kernel->>'outbox_id')::bigint,
    'correlation_id', 'cmd:' || v_cmd,
    'blocker', case when cardinality(v_tasks) = 0
                    then 'The interpretation selected no registered workflow, so no operational task was '
                      || 'created. The plan is recorded; name the area and it will route.'
                    else null end,
    'priority', c.priority, 'due_at', v_due,
    'founder_approval_required', (c.outcome = 'REFUND_APPROVAL'),
    'founder_initiated_only', (c.outcome in ('FOUNDER_INITIATED_POLICY_CHANGE','FOUNDER_INITIATED_PHASE_A_CHANGE')),
    'plan_id', v_plan_id, 'trace_id', v_trace);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_index_slowdown_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int := 0; r record; v_moved text; v_ins int; v_moved_json jsonb;
begin
  for r in
    select z.index_name, z.measured_on, z.score, z.prev, z.dims, z.prev_dims
      from (select c.index_name, c.measured_on, c.score, c.dimensions dims,
                   lag(c.score)      over (partition by c.index_name order by c.measured_on) prev,
                   lag(c.dimensions) over (partition by c.index_name order by c.measured_on) prev_dims
              from public.company_index c
             where c.measured_on > current_date - 30) z
     where z.prev is not null and z.score < z.prev - 1 and z.measured_on > current_date - 7
       and not exists (select 1 from public.founder_alerts a
                        where a.created_at::date >= z.measured_on
                          and position(z.index_name in coalesce(a.event,'')||' '||coalesce(a.detail::text,'')) > 0)
       and not exists (select 1 from public.evolution_proposal p
                        where p.created_at::date >= z.measured_on
                          and position(z.index_name in coalesce(p.subject,'')||' '||coalesce(p.observation,'')) > 0)
       and not exists (select 1 from public.agent_actions g
                        where g.created_at::date >= z.measured_on
                          and position(z.index_name in coalesce(g.title,'')||' '||coalesce(g.detail::text,'')) > 0)
  loop
    -- WHERE THE DROP CAME FROM, out of the index's own stored dimensions. Only dimensions that
    -- actually fell, biggest mover first, with both values so the size is visible.
    select string_agg(d.k||' '||d.was||' to '||d.now_v, ', ' order by (d.was - d.now_v) desc),
           jsonb_object_agg(d.k, jsonb_build_object('was', d.was, 'now', d.now_v, 'fell_by', round(d.was - d.now_v, 2)))
      into v_moved, v_moved_json
      from (select k, (r.prev_dims->>k)::numeric was, (r.dims->>k)::numeric now_v
              from jsonb_object_keys(r.dims) k
             where jsonb_typeof(r.dims->k) = 'number'
               and jsonb_typeof(coalesce(r.prev_dims->k,'null'::jsonb)) = 'number'
               and (r.prev_dims->>k)::numeric > (r.dims->>k)::numeric) d;

    insert into public.evolution_proposal (trigger_kind, subject, observation, evidence, proposal, change_class)
    values ('metric_off_target', r.index_name,
      format('%s fell from %s to %s on %s, a drop of %s points. Dimensions that moved down: %s.',
             r.index_name, r.prev, r.score, r.measured_on, round(r.prev - r.score, 2),
             coalesce(v_moved, 'none that the index breaks out — the drop is in the weighting, not in a named dimension')),
      jsonb_build_object('index', r.index_name, 'from', r.prev, 'to', r.score,
                         'fell_by', round(r.prev - r.score, 2), 'measured_on', r.measured_on,
                         'dimensions_down', v_moved),
      format('Find the cause of the %s fall before it compounds. The dimensions above are where it came from; the drop is arithmetic, the reason is not, and only one of those two is in the data.', r.index_name),
      'process')
    -- The partial unique index gets the final say. Its predicate is repeated verbatim so the
    -- arbiter resolves to evolution_proposal_dedupe_idx and nothing else.
    on conflict (trigger_kind, subject, change_class) where status = 'proposed' do nothing;

    -- THE RECORD OF THE INVESTIGATION. Not deduped: every fall is its own finding, and this is the
    -- row the scorer and the founder both read when they ask "was this looked at".
    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id,
                                      confidence, evidence, decided_by, decided_at, expected_impact, cost)
    values ('ceo', 'index_slowdown', 'auto_done', 'low',
      format('%s fell %s points (%s to %s) on %s', r.index_name, round(r.prev - r.score, 2), r.prev, r.score, r.measured_on),
      case when v_moved is null
           then 'No named dimension fell: the drop is in the weighting. Compare the dimension set of the two measurements.'
           else 'Investigated from the index''s own dimensions: ' || v_moved || '. The measure behind the biggest mover is where the cause is.' end,
      jsonb_build_object('index', r.index_name, 'from', r.prev, 'to', r.score, 'fell_by', round(r.prev - r.score, 2),
                         'measured_on', r.measured_on, 'dimensions_down', coalesce(v_moved_json, '{}'::jsonb)),
      'company_index', r.index_name, 1.0,
      jsonb_build_object('basis', 'company_index rows for ' || r.index_name || ' on ' || r.measured_on || ' and the measurement before it'),
      'index_slowdown_watch', now(),
      'A fall that is attributed to its dimension on the day it happens is a fall someone can act on; one found a week later is a trend.',
      'No spend: arithmetic over stored dimensions.');
    get diagnostics v_ins = row_count;
    n := n + v_ins;
  end loop;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('index_slowdown_watch', now(), now(), 'ok', jsonb_build_object('investigated', n),
    case when n = 0 then 'No index lost more than a point in the last 7 days without something already picking it up.'
         else n||' index fall(s) over a point investigated, with the dimensions that moved.' end);

  return jsonb_build_object('investigated', n);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_kernel_source_cutover_state()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
with
-- The population is recomputed from the catalogue every time, never read off this table: a check
-- whose denominator is a column the same migration writes goes green by emptying itself.
pop as (
  select * from public.v_kernel_trigger_source_derived
   where connection_state in ('CONNECTED_ACTIVE','CONNECTED_INACTIVE','INTENTIONALLY_RETIRED')
      or (coalesce(is_active_now,false) and coalesce(creates_work_now,false)
          and coalesce(disposition,'') <> 'FOUNDER_COMMAND_SURFACE')
      -- ...or it is already classified. The register may GROW when a new source appears and may
      -- never silently SHED a row because a flag on it moved.
      or source_key in (select source_component_id from public.phase_c_source_cutover)
),
c as (select * from public.phase_c_source_cutover),
act as (select * from c where current_activation = 'ACTIVE'),
protected(t) as (values
  ('phase_c_workflow_run'),('phase_c_workflow_step_run'),('phase_c_task'),('phase_c_handoff_run'),
  ('kernel_trigger_inbox'),('kernel_signal_inbox'),('phase_c_event_outbox'),('phase_c_refund_decision')),
-- A source and the routine it actually fires. Only database triggers and cron jobs can be resolved
-- to a routine from the catalogue; an Edge Function has no prosrc to read, and saying so is better
-- than pretending the scan covered it.
source_routine as (
  select s.source_component_id as source_key, p.oid, p.proname
    from public.phase_c_source_cutover s
    join pg_trigger tg on tg.tgname = split_part(s.source_component_id, ':', 3)
    join pg_class cl on cl.oid = tg.tgrelid and cl.relname = split_part(split_part(s.source_component_id, ':', 2), '.', 2)
    join pg_proc p on p.oid = tg.tgfoid
   where s.source_type = 'database_trigger' and not tg.tgisinternal
),
writes_business_work as (
  select sr.source_key, string_agg(distinct pr.t, ', ') tables
    from source_routine sr
    join pg_proc p on p.oid = sr.oid
    join protected pr on regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
         ~ ('(insert\s+into|update|delete\s+from)\s+(public\.)?' || pr.t || '\M')
   group by sr.source_key
)
select 'sources_in_the_population_with_no_classification'::text,
       '0 of ' || (select count(*)::text from pop),
       (select count(*)::text from pop p
         where not exists (select 1 from c where c.source_component_id = p.source_key))
         || ' of ' || (select count(*)::text from pop),
       (select count(*) = 0 from pop p
         where not exists (select 1 from c where c.source_component_id = p.source_key))
union all
select 'classified_sources_that_are_not_in_the_k10_inventory',
       '0 of ' || (select count(*)::text from c),
       (select count(*)::text from c
         where not exists (select 1 from public.kernel_trigger_source k
                            where k.source_key = c.source_component_id))
         || ' of ' || (select count(*)::text from c),
       (select count(*) = 0 from c
         where not exists (select 1 from public.kernel_trigger_source k
                            where k.source_key = c.source_component_id))
union all
select 'class_split',
       'reported, never counted as one backlog',
       (select string_agg(source_class || ' ' || n::text, '; ' order by source_class)
          from (select source_class, count(*) n from c group by 1) d),
       true
union all
select 'active_new_work_sources_not_pointed_at_the_trigger_adapter',
       '0 of ' || (select count(*)::text from act where source_class = 'A NEW_WORK_REQUEST'),
       (select count(*)::text from act
         where source_class = 'A NEW_WORK_REQUEST' and target_kernel_adapter <> 'fn_kernel_trigger_submit')
         || ' of ' || (select count(*)::text from act where source_class = 'A NEW_WORK_REQUEST'),
       (select count(*) = 0 from act
         where source_class = 'A NEW_WORK_REQUEST' and target_kernel_adapter <> 'fn_kernel_trigger_submit')
union all
select 'active_existing_run_signals_not_pointed_at_the_signal_adapter',
       '0 of ' || (select count(*)::text from act where source_class = 'B EXISTING_WORKFLOW_SIGNAL'),
       (select count(*)::text from act
         where source_class = 'B EXISTING_WORKFLOW_SIGNAL' and target_kernel_adapter <> 'fn_kernel_signal_submit')
         || ' of ' || (select count(*)::text from act where source_class = 'B EXISTING_WORKFLOW_SIGNAL'),
       (select count(*) = 0 from act
         where source_class = 'B EXISTING_WORKFLOW_SIGNAL' and target_kernel_adapter <> 'fn_kernel_signal_submit')
union all
-- K22c. THE class-C rule, measured as it is written: a monitor may not create business work, and
-- business work is the eight tables §7 protects. Scanned from the deployed body, and enforced
-- independently by K18 — so this line cannot be made green by relabelling a source.
select 'active_read_only_monitors_that_write_business_work',
       '0 of ' || (select count(*)::text from act where source_class = 'C READ_ONLY_MONITOR'),
       (select count(*)::text from act a join writes_business_work w on w.source_key = a.source_component_id
         where a.source_class = 'C READ_ONLY_MONITOR')
         || ' of ' || (select count(*)::text from act where source_class = 'C READ_ONLY_MONITOR')
         || coalesce(' [' || (select string_agg(a.source_component_id || ' -> ' || w.tables, '; ')
              from act a join writes_business_work w on w.source_key = a.source_component_id
             where a.source_class = 'C READ_ONLY_MONITOR') || ']', ''),
       (select count(*) = 0 from act a join writes_business_work w on w.source_key = a.source_component_id
         where a.source_class = 'C READ_ONLY_MONITOR')
union all
-- The old proxy, kept as a REPORTED line so a monitor that starts touching sibling tables is still
-- visible. It is not a pass/fail: writing a sibling row is what a normalising trigger is for.
select 'read_only_monitors_that_write_a_sibling_table',
       'reported, not a defect — a normalising trigger writes a sibling row by design',
       (select count(*)::text from act a join pop p on p.source_key = a.source_component_id
         where a.source_class = 'C READ_ONLY_MONITOR' and coalesce(p.creates_work_now,false))
         || ' of ' || (select count(*)::text from act where source_class = 'C READ_ONLY_MONITOR'),
       true
union all
select 'retired_sources_that_are_still_live_and_writing_business_work',
       '0 of ' || (select count(*)::text from c where source_class = 'D RETIRE_OR_HISTORICAL'),
       (select count(*)::text from c join writes_business_work w on w.source_key = c.source_component_id
         where c.source_class = 'D RETIRE_OR_HISTORICAL')
         || ' of ' || (select count(*)::text from c where source_class = 'D RETIRE_OR_HISTORICAL'),
       (select count(*) = 0 from c join writes_business_work w on w.source_key = c.source_component_id
         where c.source_class = 'D RETIRE_OR_HISTORICAL')
union all
select 'class_A_sources_whose_trigger_type_is_not_registered',
       '0 of ' || (select count(*)::text from c where source_class = 'A NEW_WORK_REQUEST'),
       (select count(*)::text from c where source_class = 'A NEW_WORK_REQUEST'
          and not exists (select 1 from public.kernel_trigger_type t
                           where t.trigger_type = c.target_step_or_signal))
         || ' of ' || (select count(*)::text from c where source_class = 'A NEW_WORK_REQUEST'),
       (select count(*) = 0 from c where source_class = 'A NEW_WORK_REQUEST'
          and not exists (select 1 from public.kernel_trigger_type t
                           where t.trigger_type = c.target_step_or_signal))
union all
select 'class_B_sources_whose_signal_type_is_not_registered',
       '0 of ' || (select count(*)::text from c where source_class = 'B EXISTING_WORKFLOW_SIGNAL'),
       (select count(*)::text from c where source_class = 'B EXISTING_WORKFLOW_SIGNAL'
          and not exists (select 1 from public.kernel_signal_type s
                           where s.signal_type = c.target_step_or_signal))
         || ' of ' || (select count(*)::text from c where source_class = 'B EXISTING_WORKFLOW_SIGNAL'),
       (select count(*) = 0 from c where source_class = 'B EXISTING_WORKFLOW_SIGNAL'
          and not exists (select 1 from public.kernel_signal_type s
                           where s.signal_type = c.target_step_or_signal))
union all
select 'sources_switched_off_today',
       'reported; an adapter existing is not a reason to activate one',
       (select count(*)::text from c where current_activation = 'DISABLED')
         || ' of ' || (select count(*)::text from c) || ' carry an adapter and stay disabled',
       true
union all
select 'active_sources_now_calling_a_kernel_adapter',
       'reported; it rises as each cutover increment lands',
       (select count(*)::text from source_routine sr
         join pg_proc p on p.oid = sr.oid
        where regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
              ~ '\yfn_kernel_source_emit\s*\(')
         || ' of ' || (select count(*)::text from act
                        where source_class in ('A NEW_WORK_REQUEST','B EXISTING_WORKFLOW_SIGNAL'))
         || ' active class-A/B sources reach the kernel (database triggers only — an Edge Function '
         || 'has no prosrc to scan, and saying so beats pretending the scan covered it)',
       true
union all
select 'routine_autonomous_work_routed_through_the_founder_or_chief_of_staff',
       '0 of ' || (select count(*)::text from act where source_class in
                    ('A NEW_WORK_REQUEST','B EXISTING_WORKFLOW_SIGNAL')),
       (select count(*)::text from act
         where source_class in ('A NEW_WORK_REQUEST','B EXISTING_WORKFLOW_SIGNAL')
           and accountable_role in ('founder','ceo'))
         || ' of ' || (select count(*)::text from act where source_class in
                        ('A NEW_WORK_REQUEST','B EXISTING_WORKFLOW_SIGNAL')),
       (select count(*) = 0 from act
         where source_class in ('A NEW_WORK_REQUEST','B EXISTING_WORKFLOW_SIGNAL')
           and accountable_role in ('founder','ceo'));
$function$;

CREATE OR REPLACE FUNCTION public.fn_kernel_trigger_state()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'cron', 'pg_temp'
AS $function$
with d as (select * from public.v_kernel_trigger_source_derived),
tot as (select count(*)::text n from d),
auto as (   -- a live source that starts or changes business work: what an adapter is FOR.
            -- The founder's own command channel is excluded by name: it is not autonomous, a
            -- person drives it, and giving it an autonomous adapter is the one thing the frozen
            -- operating model forbids. Excluded here and counted on the deferred_handler_split
            -- line, so it is never simply missing.
  select * from d
   where coalesce(is_active_now,false) and coalesce(creates_work_now,false)
     and coalesce(disposition,'') not in (
           -- Q03. Three dispositions, each a MEASUREMENT recorded on the row with the reading it
           -- was taken from, not a name added to get a number down. FOUNDER_COMMAND_SURFACE was
           -- already here; the other two are the F1 and F2 corrections of
           -- docs/phase-d/PHASE_D_AUTONOMOUS_SOURCE_BYPASS_TABLE.md. Every one of them is still
           -- counted, by name, on the disposition_split line below, so nothing leaves this board
           -- by being excluded here.
           'FOUNDER_COMMAND_SURFACE',
           'RECOMPUTATION_ONLY_NO_BUSINESS_WORK',
           'HUMAN_DRIVEN_SURFACE_NOT_AN_AUTONOMOUS_SOURCE')
),
act as (select count(*)::text n from auto),
-- UNACCOUNTED FOR: it starts work, it is live, it has no working adapter, and nobody has written
-- down why. A recorded DEFERRED_HANDLER is an answer; silence is the gap.
gap as (
  select * from auto a
   where a.disposition is null
     and (a.adapter_trigger_type is null
          or not exists (select 1 from public.kernel_trigger_type t
                          where t.trigger_type = a.adapter_trigger_type
                            and t.activation_state = 'active'))
)
select 'active_autonomous_source_with_no_adapter'::text,
       '0 of ' || (select n from act) || ' active autonomous sources (' || (select n from tot) || ' inventoried)',
       (select count(*)::text from gap)
         || ' of ' || (select n from act) || ' active autonomous sources unaccounted for ('
         || (select n from tot) || ' inventoried); '
         || (select count(*)::text from auto where disposition = 'NO_WORKFLOW_IN_REGISTRY')
         || ' carry a recorded DEFERRED_HANDLER, '
         || (select count(*)::text from d where coalesce(is_active_now,false)
               and coalesce(creates_work_now,false) and disposition = 'FOUNDER_COMMAND_SURFACE')
         || ' are founder command surfaces held out of this population by name',
       (select count(*) from gap) = 0
union all
select 'active_adapter_bypassing_fn_kernel_workflow_start'::text,
       '0 of ' || (select count(*)::text from public.kernel_trigger_type where activation_state = 'active')
         || ' active trigger types',
       -- The adapter is fn_kernel_trigger_submit. It bypasses the kernel creator if its own body
       -- (comments stripped) does not call fn_kernel_workflow_start, or if any OTHER routine reads
       -- kernel_trigger_inbox and creates work without going through it.
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
               ~ '\ykernel_trigger_inbox\y'
           and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
               ~ '(insert\s+into\s+(public\.)?phase_c_(task|workflow_run)\y)'
           and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
               !~ '\yfn_kernel_workflow_start\s*\(')::text
         || ' routines read kernel_trigger_inbox and create work without fn_kernel_workflow_start; '
         || 'fn_kernel_trigger_submit calls it: '
         || (select (regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
                     ~ '\yfn_kernel_workflow_start\s*\(')::text
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'fn_kernel_trigger_submit'),
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
               ~ '\ykernel_trigger_inbox\y'
           and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
               ~ '(insert\s+into\s+(public\.)?phase_c_(task|workflow_run)\y)'
           and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
               !~ '\yfn_kernel_workflow_start\s*\(') = 0
       and coalesce((select regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
                            ~ '\yfn_kernel_workflow_start\s*\('
                       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                      where n.nspname = 'public' and p.proname = 'fn_kernel_trigger_submit'), false)
union all
select 'normal_autonomous_trigger_routing_through_founder'::text,
       '0 of ' || (select count(*)::text from public.kernel_trigger_type where workflow_id is not null)
         || ' mapped trigger types',
       (select count(*) from public.kernel_trigger_type t
          join public.phase_b_workflow w on w.workflow_id = t.workflow_id
          left join public.phase_b_workflow_step s
                 on s.workflow_id = t.workflow_id and s.step_no = 1
         where 'founder' in (w.accountable_role_id, coalesce(s.accountable_role_id,'')))::text
         || ' of ' || (select count(*)::text from public.kernel_trigger_type where workflow_id is not null)
         || ' mapped trigger types (workflow owner or entry-step owner)',
       (select count(*) from public.kernel_trigger_type t
          join public.phase_b_workflow w on w.workflow_id = t.workflow_id
          left join public.phase_b_workflow_step s
                 on s.workflow_id = t.workflow_id and s.step_no = 1
         where 'founder' in (w.accountable_role_id, coalesce(s.accountable_role_id,''))) = 0
union all
select 'normal_autonomous_trigger_routing_through_chief_of_staff'::text,
       '0 of ' || (select count(*)::text from public.kernel_trigger_type where workflow_id is not null)
         || ' mapped trigger types',
       (select count(*) from public.kernel_trigger_type t
          join public.phase_b_workflow w on w.workflow_id = t.workflow_id
          left join public.phase_b_workflow_step s
                 on s.workflow_id = t.workflow_id and s.step_no = 1
         where 'ceo' in (w.accountable_role_id, coalesce(s.accountable_role_id,'')))::text
         || ' of ' || (select count(*)::text from public.kernel_trigger_type where workflow_id is not null)
         || ' mapped trigger types; W01 is the founder-command path and is refused by '
         || 'a00_kernel_trigger_type_routing_guard, not merely absent',
       (select count(*) from public.kernel_trigger_type t
          join public.phase_b_workflow w on w.workflow_id = t.workflow_id
          left join public.phase_b_workflow_step s
                 on s.workflow_id = t.workflow_id and s.step_no = 1
         where 'ceo' in (w.accountable_role_id, coalesce(s.accountable_role_id,''))) = 0
union all
select 'duplicate_trigger_delivery_creating_duplicate_workflow'::text,
       '0 of ' || (select count(*)::text from public.kernel_trigger_inbox
                    where status in ('accepted','duplicate')) || ' resolved inbox rows',
       -- Two ways a duplicate could show: the same idempotency key twice (the UNIQUE constraint
       -- makes it impossible and it is still counted, because a constraint that is never tested is
       -- an assumption), or one (workflow, business object) carrying more than one run.
       (select count(*) from (
          select 1 from public.kernel_trigger_inbox
           group by idempotency_key having count(*) > 1) x)::text
         || ' repeated idempotency keys + '
         || (select count(*) from (
               select workflow_id, business_object_id from public.kernel_trigger_inbox
                where status in ('accepted','duplicate') and run_id is not null
                group by workflow_id, business_object_id having count(distinct run_id) > 1) y)::text
         || ' (workflow, object) pairs with more than one run, of '
         || (select count(*)::text from public.kernel_trigger_inbox
              where status in ('accepted','duplicate')) || ' resolved inbox rows',
       (select count(*) from (
          select 1 from public.kernel_trigger_inbox
           group by idempotency_key having count(*) > 1) x)
       + (select count(*) from (
            select workflow_id, business_object_id from public.kernel_trigger_inbox
             where status in ('accepted','duplicate') and run_id is not null
             group by workflow_id, business_object_id having count(distinct run_id) > 1) y) = 0
union all
select 'trigger_source_using_the_domain_event_outbox_as_its_request_queue'::text,
       '0 of ' || (select n from tot) || ' inventoried sources',
       (select count(*) from d where outbox_used_as_request_queue)::text
         || ' of ' || (select n from tot) || ' inventoried sources. The predicate is live: it '
         || 'matches '
         || (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public'
                and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g') ~ '\yphase_c_event_outbox\y'
                and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g') ~ '\yfn_(kernel|phase_c)_(workflow_start|event_ingress)\s*\(')
         || ' routines in the database (the legacy ingress pair), and no ACTIVE source reaches them',
       (select count(*) from d where outbox_used_as_request_queue) = 0
-- ---- reported alongside the six, because a green mapping check must not read as a green wiring
-- ---- check. This is the increment's own open gap and it is stated as a number, not as prose.
union all
select 'active_autonomous_source_not_yet_routing_through_the_inbox'::text,
       '0 of ' || (select n from act) || ' active autonomous sources — NOT MET BY K10',
       (select count(*) from auto where not coalesce(routes_through_inbox,false))::text
         || ' of ' || (select n from act) || ' active autonomous sources still start or change '
         || 'business work without entering the kernel. K10 builds the door and registers the '
         || 'routes; moving each source onto it is the wiring increment.',
       (select count(*) from auto where not coalesce(routes_through_inbox,false)) = 0
union all
select 'inventory_row_whose_accountable_role_does_not_resolve'::text,
       '0 of ' || (select n from tot) || ' inventoried sources',
       (select count(*) from d where accountable_kind is distinct from 'canonical')::text
         || ' of ' || (select n from tot) || ' inventoried sources',
       (select count(*) from d where accountable_kind is distinct from 'canonical') = 0
union all
select 'disposition_split'::text,
       'reported, never counted as one backlog of owed handlers',
       (select count(*)::text from public.kernel_trigger_source
         where disposition = 'NO_WORKFLOW_IN_REGISTRY')
         || ' owe a handler (no Phase B workflow starts from that signal); '
         || (select count(*)::text from public.kernel_trigger_source
              where disposition = 'NOT_A_BUSINESS_TRIGGER')
         || ' are not business triggers at all (guards, audits, probes, held jobs); '
         || (select count(*)::text from public.kernel_trigger_source
              where disposition = 'FOUNDER_COMMAND_SURFACE')
         || ' are founder command surfaces that must never get an autonomous adapter; '
         || (select count(*)::text from public.kernel_trigger_source
              where disposition is null and adapter_trigger_type is not null)
         || ' carry an adapter; '
         || (select count(*)::text from public.kernel_trigger_source
              where disposition = 'RECOMPUTATION_ONLY_NO_BUSINESS_WORK')
         || ' recompute a derived value and create no business work; '
         || (select count(*)::text from public.kernel_trigger_source
              where disposition = 'HUMAN_DRIVEN_SURFACE_NOT_AN_AUTONOMOUS_SOURCE')
         || ' are human-driven browser surfaces that write no table themselves; '
         || (select count(*)::text from public.kernel_trigger_source
              where disposition = 'READ_ONLY_DERIVED_INTERNAL')
         || ' are read-only or derived-internal',
       true
-- ---- Q03. THE INVENTORY'S OWN COMPLETENESS, PUBLISHED AS A NUMBER.
-- Every correction on this board rests on the same sentence: 'the write happens in the edge
-- function, which is inventoried separately'. That sentence is only worth anything if the
-- inventory is complete, and it is not. Measured 25 Aug 2026: 143 deployed edge functions write
-- at least one table, 25 hold an inventory row, and 52 of the uninventoried ones write a WORK
-- table. Counting them here rather than in a document is the difference between a disclosed gap
-- and a footnote nobody reads. It is ok=false on purpose: this is owed work, not an exemption.
union all
select 'edge_functions_writing_a_work_table_and_absent_from_the_inventory'::text,
       '0 — every edge function that writes a work table carries an inventory row',
       (select count(*)::text from (
          select distinct w.edge_function
            from public.phase_c_edge_function_writes w
           where not w.unbounded
             and w.table_name in ('agent_actions','org_tasks','phase_c_task','notifications',
                                  'os_incidents','board_reports','evolution_proposal','leads',
                                  'inquiries','inquiry_intake','quotes','transactions','customers')
             and not exists (select 1 from public.kernel_trigger_source s
                              where s.source_key = 'edge:' || w.edge_function)) x)
         || ' of ' || (select count(distinct w.edge_function)::text
                         from public.phase_c_edge_function_writes w) 
         || ' edge functions with a measured write are absent from public.kernel_trigger_source '
         || 'while writing a work table. The sources this board reports on are what the inventory '
         || 'can see, not what the estate contains.',
       not exists (
          select 1 from public.phase_c_edge_function_writes w
           where not w.unbounded
             and w.table_name in ('agent_actions','org_tasks','phase_c_task','notifications',
                                  'os_incidents','board_reports','evolution_proposal','leads',
                                  'inquiries','inquiry_intake','quotes','transactions','customers')
             and not exists (select 1 from public.kernel_trigger_source s
                              where s.source_key = 'edge:' || w.edge_function));
$function$;

CREATE OR REPLACE FUNCTION public.fn_kernel_trigger_type_routing_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_wf_owner   text;
  v_step_owner text;
  v_step_id    text;
begin
  if new.workflow_id is null then
    return new;                     -- a DEFERRED_HANDLER routes to nothing and owns nothing
  end if;

  select w.accountable_role_id into v_wf_owner
    from public.phase_b_workflow w where w.workflow_id = new.workflow_id;

  select s.step_id, s.accountable_role_id into v_step_id, v_step_owner
    from public.phase_b_workflow_step s
   where s.workflow_id = new.workflow_id and s.step_no = 1;

  -- SELECT INTO that matched nothing leaves NULLs, so the absence is tested rather than assumed.
  if v_step_id is null then
    raise exception
      'kernel_trigger_type %: workflow % declares no step_no = 1, so this trigger type has no entry '
      'step to own the work it would create.', new.trigger_type, new.workflow_id
      using errcode = '23502';
  end if;

  if v_wf_owner in ('founder','ceo') or v_step_owner in ('founder','ceo') then
    raise exception
      'kernel_trigger_type %: workflow % is owned by "%" and its entry step % is owned by "%". '
      'Normal autonomous work bypasses both the founder and the Chief of Staff — that is a frozen '
      'boundary, not a preference. Register this route only if it is a founder command, and founder '
      'commands do not come through the trigger inbox.',
      new.trigger_type, new.workflow_id, v_wf_owner, v_step_id, v_step_owner
      using errcode = '23514';
  end if;

  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.fn_overlay_for_category(p_category_key text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  select jsonb_build_object(
    'category_key', c.category_key,
    'route_key', c.route_key,
    'overlay_role_id', 'category_overlay_'||c.category_key,
    'owner_agent', c.owner_agent,
    'invoked_by_role', 'customer_support',
    'readiness', c.readiness,
    'exists', (select count(*) > 0 from public.org_role r
                where r.role_id = 'category_overlay_'||c.category_key and r.status='active'))
    from public.org_category_identity c where c.category_key = p_category_key;
$function$;

CREATE OR REPLACE FUNCTION public.fn_phase_c_reporting_map_drift()
 RETURNS TABLE(subject text, role_id text, approved text, live text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- FIRST, THE SUBJECT ITSELF. Every other branch below reads phase_c_reporting_authority, so an
  -- empty table would make all of them return nothing and the check would report perfect agreement
  -- with an authority that is no longer there. Absent input must not score as satisfied: the row
  -- count is asserted against the founder-approved shape before anything is compared to it.
  select 'authority_not_recorded', 'phase_c_reporting_authority',
         '75 standing roles', count(*)::text
    from public.phase_c_reporting_authority having count(*) <> 75
  union all
  select 'overlay_authority_not_recorded', 'phase_c_overlay_binding',
         '86 category overlays', count(*)::text
    from public.phase_c_overlay_binding having count(*) <> 86
  union all
  -- a standing role the map names that the organisation cannot resolve
  select 'unresolved_role', a.canonical_role_id, a.live_role_id, '(no active org_role)'
    from public.phase_c_reporting_authority a
   where not exists (select 1 from public.org_role r
                      where r.role_id = a.live_role_id and r.status = 'active')
  union all
  select 'primary_manager', a.canonical_role_id, a.manager_role_id, coalesce(r.manager_role_id,'founder')
    from public.phase_c_reporting_authority a
    join public.org_role r on r.role_id = a.live_role_id
   where coalesce(r.manager_role_id,'founder') is distinct from a.manager_role_id
  union all
  select 'primary_department', a.canonical_role_id, a.department_id, r.primary_department_id
    from public.phase_c_reporting_authority a
    join public.org_role r on r.role_id = a.live_role_id
   where r.primary_department_id is distinct from a.department_id
  union all
  select 'role_class', a.canonical_role_id, a.role_class||'/'||a.runtime_mode, r.runtime_mode
    from public.phase_c_reporting_authority a
    join public.org_role r on r.role_id = a.live_role_id
    join (select live_role_id, count(*) canonical_count
            from public.phase_c_reporting_authority group by 1) f
      on f.live_role_id = a.live_role_id
   where r.runtime_mode is distinct from a.runtime_mode
     -- COMPARED ONLY WHERE THE COMPARISON MEANS SOMETHING. Thirteen live roles absorbed 34 canonical
     -- ones; comparing an absorbed specialist's approved class against the absorbing director's
     -- runtime_mode reported 18 mismatches, every one of them a false positive.
     and f.canonical_count = 1

  union all
  -- and the absorbed ones stay VISIBLE under their own subject rather than vanishing
  select 'role_class_not_comparable', a.canonical_role_id, a.role_class||'/'||a.runtime_mode,
         format('absorbed into %s, which carries %s canonical roles', a.live_role_id, f.canonical_count)
    from public.phase_c_reporting_authority a
    join public.org_role r on r.role_id = a.live_role_id
    join (select live_role_id, count(*) canonical_count
            from public.phase_c_reporting_authority group by 1) f
      on f.live_role_id = a.live_role_id
   where r.runtime_mode is distinct from a.runtime_mode
     and f.canonical_count > 1
  union all
  -- the department head the map names must be the head the department records
  select 'department_head', a.canonical_role_id, a.department_head_role_id, coalesce(d.lead_agent,'(none)')
    from public.phase_c_reporting_authority a
    join public.org_departments d on d.dept_key = a.department_id
    left join public.org_role h on h.role_id = a.department_head_role_id
   where d.lead_agent is distinct from h.runtime_agent_key
  union all
  -- the path to the founder, WALKED in the live graph rather than assumed, and compared with the
  -- approved path. This is also the cycle check: a chain that loops never reaches the founder, so
  -- the walk returns null and the row is reported.
  select 'reporting_path', a.canonical_role_id, a.reporting_path, coalesce(w.walked,'(never reaches the founder)')
    from public.phase_c_reporting_authority a
    left join lateral (
      with recursive up(cur, depth, path) as (
        select a.live_role_id, 0, a.live_role_id
        union all
        select coalesce(r.manager_role_id,'founder'), u.depth+1,
               u.path||' > '||coalesce(r.manager_role_id,'founder')
          from up u join public.org_role r on r.role_id = u.cur and r.status='active'
         where u.depth < 20 and u.cur <> 'founder')
      select path as walked from up where cur = 'founder' order by depth limit 1
    ) w on true
   where w.walked is distinct from a.reporting_path
  union all
  -- one live role standing in for two canonical roles
  select 'duplicate_active_identity', x.live_role_id, 'one canonical role', x.n::text
    from (select live_role_id, count(*) n from public.phase_c_reporting_authority
           group by 1 having count(*) > 1) x
   where not exists (select 1 from public.phase_c_approved_consolidation c
                      where c.live_role_id = x.live_role_id and c.canonical_count = x.n)
  union all
  select 'self_management', a.canonical_role_id, a.manager_role_id, r.manager_role_id
    from public.phase_c_reporting_authority a
    join public.org_role r on r.role_id = a.live_role_id
   where r.manager_role_id = r.role_id
  union all
  -- An identity that cannot act, or one that acts as an employee nobody models.
  --
  -- runtime_enabled=false is treated separately from the rest, and deliberately so. Phase A
  -- deferred product_ux_designer's tools, knowledge, KPI and authority to a later phase with the
  -- founder's approval, and switching the role OFF is the correct consequence of that deferral —
  -- a role left enabled with no tools is the worse state, not the better one. So a disabled role
  -- is reported unless fn_phase_a_deferred_items() is currently carrying it. That exemption is not
  -- a hole: it is checked against the live deferral list on every call, so the moment the deferral
  -- is closed — or the moment any OTHER role is switched off — this fires. A missing agent key, an
  -- agent absent from org_agents, or an inactive agent are never exempt.
  select 'identity_cannot_act', a.canonical_role_id, 'an active runtime identity',
         coalesce(r.runtime_agent_key,'(none)')
           || case when r.runtime_enabled then '' else ' runtime_enabled=false' end
           || case when g.agent_key is null then ' not in org_agents'
                   when g.active is not true then ' agent inactive' else '' end
    from public.phase_c_reporting_authority a
    join public.org_role r on r.role_id = a.live_role_id
    left join public.org_agents g on g.agent_key = r.runtime_agent_key
   where r.runtime_agent_key is null
      or g.agent_key is null
      or g.active is not true
      or (r.runtime_enabled is not true
          and not exists (select 1 from public.fn_phase_a_deferred_items() d
                           where d.role_id = r.role_id))
  union all
  -- OVERLAYS: the governance facts the founder's instruction lists, one row per failing overlay
  select 'overlay_unbound', o.overlay_id, 'a live category overlay', coalesce(o.live_role_id,'(none)')
    from public.phase_c_overlay_binding o
   where not exists (select 1 from public.org_role r
                      where r.role_id = o.live_role_id and r.status='active'
                        and r.runtime_mode='knowledge_overlay')
  union all
  select 'overlay_department', o.overlay_id, 'marketplace', r.primary_department_id
    from public.phase_c_overlay_binding o join public.org_role r on r.role_id = o.live_role_id
   where r.primary_department_id is distinct from 'marketplace'
  union all
  select 'overlay_accountable_manager', o.overlay_id, 'marketplace_director reachable',
         array_to_string(r.escalation_targets,'+')
    from public.phase_c_overlay_binding o join public.org_role r on r.role_id = o.live_role_id
   where not ('marketplace_director' = any(r.escalation_targets))
  union all
  select 'overlay_invocation_role', o.overlay_id, 'customer_support', coalesce(o.invocation_role_id,'(none)')
    from public.phase_c_overlay_binding o
   where o.invocation_role_id is distinct from 'customer_support'
  union all
  select 'overlay_result_returns_to', o.overlay_id, 'ceo',
         coalesce(o.result_returns_to_role_id,'(none)')
    from public.phase_c_overlay_binding o
   where o.result_returns_to_role_id is distinct from 'ceo'
  union all
  select 'overlay_returns_unreachable', o.overlay_id, 'rfq_qualification_manager in handoff_targets',
         array_to_string(r.handoff_targets,'+')
    from public.phase_c_overlay_binding o join public.org_role r on r.role_id = o.live_role_id
   where not ('ceo' = any(r.handoff_targets))
  union all
  select 'overlay_broad_domain_escalation', o.overlay_id,
         coalesce(o.broad_domain_escalation_role_id,'(unrecorded)'), array_to_string(r.escalation_targets,'+')
    from public.phase_c_overlay_binding o join public.org_role r on r.role_id = o.live_role_id
   where o.broad_domain_escalation_role_id is null
      or not (o.broad_domain_escalation_role_id = any(r.escalation_targets))
  union all
  -- the three governance owners the map names must exist and be able to act
  select 'overlay_governance_owner', g.responsibility, g.owner_role_id, 'missing or not active'
    from public.phase_c_governance_owner g
   where not exists (select 1 from public.org_role r
                      where r.role_id = g.owner_role_id and r.status='active')
  union all
  -- an overlay that could decide something the map forbids it
  select 'overlay_authority', o.overlay_id, 'advisory, holding no runtime employee',
         r.authority_level||coalesce(' as '||r.runtime_agent_key,'')
    from public.phase_c_overlay_binding o join public.org_role r on r.role_id = o.live_role_id
   where r.authority_level <> 'advisory' or r.runtime_agent_key is not null
  union all
  select 'overlay_states_no_money_limit', o.overlay_id, 'cannot move money or decide a refund',
         'no such forbidden_decision'
    from public.phase_c_overlay_binding o join public.org_role r on r.role_id = o.live_role_id
   where not exists (select 1 from unnest(r.forbidden_decisions) f where f ilike '%money%')
  union all
  -- THE CHAIN OF COMMAND. Normal autonomous work may not route through the founder or the Chief of
  -- Staff. The two founder-facing workflows are the declared exception — W01 founder mandate to
  -- company objectives, W02 company target miss and corrective management — and they are named
  -- rather than pattern-matched, so a new workflow cannot quietly join them.
  select 'autonomous_work_routes_through_chief_of_staff', s.step_id,
         'an accountable department role', s.accountable_role_id
    from public.phase_c_step_binding s
   where s.accountable_role_id in ('ceo','founder')
     and s.workflow_id not in ('W01','W02')
  union all
  -- the founder's single routine approval
  select 'non_refund_founder_approval', c.action_class, 'refund_decision is the only one',
         'founder_approval_required'
    from public.phase_c_action_class c
   where c.founder_approval_required and c.action_class <> 'refund_decision';
$function$;

CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_file_revision(p_package_ref text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  -- scripts/staging/fixtures/metadata/supplier_drawing_clean.pdf, 736 bytes. Its CLEAN verdict in
  -- public.phase_d_metadata_scan was produced by scripts/phase_d/run_metadata_scan_probe.mjs
  -- reading these exact bytes; nothing here fabricates a scan.
  v_clean constant text := 'd1311fb75b6d5c012a5dbf4513f098896b371dd65802526e9689951f6b2025a2';
  v_dirty constant text := '617d50b1a1654b3b612d1981a55e84d8746f5f7821781a99b6b10da7948844a7';
  v_ref text;
begin
  if coalesce(btrim(p_package_ref),'') = '' then return null; end if;
  v_ref := 'fxrev:' || btrim(p_package_ref);
  insert into public.phase_d_file_revision
    (revision_ref, package_ref, file_name, media_type, source_sha256, safe_sha256,
     redaction_state, redaction_method, elements_removed, reviewer_role_id, reviewer_verdict,
     reviewed_at, authored_by_role_id)
  values (v_ref, btrim(p_package_ref), 'supplier_drawing_clean.pdf', 'application/pdf',
          v_dirty, v_clean, 'APPROVED', 'title_block_mask_and_info_dictionary_cleared',
          '["pdf:/Info//Author","pdf:/Info//Subject","pdf:/Info//Keywords","pdf:/Info//Creator","title_block"]'::jsonb,
          'ceo', 'approved', now(),
          'marketplace_content_privacy_reviewer')
  on conflict (revision_ref) do nothing;
  return v_ref;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_scenario(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  st       public.phase_d_fixture_stage%rowtype;
  v_label  text := nullif(btrim(coalesce(p_input->>'label','')),'');
  v_ctx    text := lower(coalesce(nullif(btrim(p_input->>'execution_context'),''),''));
  v_upto   int  := coalesce(nullif(p_input->>'up_to_stage','')::int, 9999);
  v_actor  text := coalesce(nullif(btrim(p_input->>'created_by'),''), 'phase_d_fixture_factory');
  v_refs   jsonb := '{}'::jsonb;
  v_man    jsonb := '[]'::jsonb;
  v_w      jsonb;
  v_pay    jsonb;
  v_key    text;
  v_owner  text;
  v_state  text;
  v_name   text;
  v_missing text[];
  v_ref_n  bigint;
  v_err    text;
  v_ok     int := 0; v_blocked int := 0; v_owned int := 0;
  v_for_wf text := nullif(btrim(coalesce(p_input->>'for_workflow','')),'');
  v_notif_before bigint; v_notif_after bigint;
  v_notif_id_before bigint;              -- G11: the high-water mark, so new rows are identifiable
  v_notif_id_start  bigint;              -- G13: the same, for the whole scenario rather than one stage
  v_inbox_before bigint; v_inbox_after bigint;
  v_notif_start  bigint; v_inbox_start  bigint;
  v_net_start    bigint;
  v_fixture_run  bigint;                     -- F01: the audited fixture run this build belongs to
  v_terms_ver    text;   v_terms_hash text;  -- F08: a REAL published document, not an invented one
  v_sup_ver      text;   v_sup_hash   text;
  v_art_sha      text;                       -- F08: the digest BR-036 resolves
  v_cat          jsonb;                      -- F08: a committed catalogue value
  v_scenario_id  bigint;
  v_state_col    text;    -- F15: the column the write map points at the state
  v_actual       text;    -- F15: what the product left in it
begin
  if v_label is null then
    raise exception 'fn_phase_d_fixture_scenario: label is required; it is what makes the ids deterministic and the residue findable (pd_fixture_label_missing)'
      using errcode = '22023';
  end if;
  if v_ctx <> 'test' then
    raise exception 'fn_phase_d_fixture_scenario: execution_context is %; this factory runs only in test (pd_fixture_not_test_context)',
      coalesce(nullif(v_ctx,''),'(unset)') using errcode = '23514';
  end if;
  -- F01. THIS READ A GUC ANY CALLER COULD SET. `set local app.phase_d_test_context = 'on'` was
  -- accepted from service_role, so the "protected test context" was a string the caller supplied
  -- about itself -- the same shape as a guard authenticating an email. The context is now an hmac
  -- over the current txid, keyed by a secret no role can SELECT, minted only by
  -- fn_phase_d_test_context_open against an approved audited operation.
  v_fixture_run := public.fn_phase_d_fixture_context();
  if v_fixture_run is null then
    raise exception 'fn_phase_d_fixture_scenario: no verified Phase D fixture context in this transaction (pd_fixture_no_test_context)'
      using errcode = '23514',
            hint = 'select public.fn_phase_d_test_context_open(''{"operation_key":"pdop_scenario_factory","label":"..."}''); and abort the transaction when finished.';
  end if;
  if current_user in ('anon','authenticated') then
    raise exception 'fn_phase_d_fixture_scenario: % may not build fixtures (pd_fixture_untrusted_caller)',
      current_user using errcode = '42501';
  end if;

  -- F08. BR-025 REQUIRES THE EXACT DISPLAYED VERSION AND ITS DIGEST, and this factory was writing
  -- 'zz-terms-v1' with sha256('zz-terms-v1') -- a hash OF THE VERSION STRING, not of any terms.
  -- The rule resolves the pair against public.legal_documents where the displayed body hashes to
  -- exactly that digest, so the acceptance the factory created could never be an acceptance of
  -- anything, and BR-025 refused every terms step for the right reason. The pair is now READ from
  -- the published document, so the fixture accepts terms that actually exist.
  select d.version, encode(sha256(convert_to(coalesce(d.body_html,''),'UTF8')),'hex')
    into v_terms_ver, v_terms_hash
    from public.legal_documents d where d.slug = 'customer-terms' order by d.version desc limit 1;
  select d.version, encode(sha256(convert_to(coalesce(d.body_html,''),'UTF8')),'hex')
    into v_sup_ver, v_sup_hash
    from public.legal_documents d where d.slug = 'supplier-agreement' order by d.version desc limit 1;
  -- The artifact digest is the digest of the committed artifact fixture's own text, so BR-036
  -- resolves it against a record this scenario writes rather than against a string.
  select encode(sha256(convert_to(c.value #>> '{}','UTF8')),'hex') into v_art_sha
    from public.phase_d_fixture_catalogue c
   where c.scope = 'CONTEXT_KEY' and c.field_key = 'artifact_ref';

  select coalesce(max(id),0) into v_net_start from net.http_request_queue;
  select count(*) into v_notif_start from public.notifications;
  select coalesce(max(id),0) into v_notif_id_start from public.notifications;  -- G13
  select count(*) into v_inbox_start from public.kernel_trigger_inbox;

  for st in select * from public.phase_d_fixture_stage where stage_no <= v_upto order by stage_no
  loop
    -- A SCENARIO MUST NOT PRE-CREATE THE OBJECT THE WORKFLOW UNDER TEST PRODUCES. W09 writes
    -- supplier_capability, W14 writes quotation, W16 writes payment_transaction; building those
    -- first made the workflow collide with its own output on a unique constraint, and a harness
    -- that seeds the row the step is supposed to create is answering its own question. The set is
    -- read from phase_d_step_effect for that workflow, never listed by hand.
    -- D22. THE EXCLUSION SKIPS LEAVES ONLY, SO A CASCADE IS IMPOSSIBLE BY CONSTRUCTION.
    --
    -- Measured with the old rule: for_workflow on W09 skipped 3 stages and the requires_stages
    -- cascade then blocked 13 MORE, because supplier_account is a parent of half the lineage. The
    -- D9 closure recorded the same shape as closure falling 14 -> 3, which is why the exclusion was
    -- left available and unused. Removing a parent to avoid a collision costs more than it saves.
    --
    -- A stage no other stage requires cannot cascade. supplier_assignment and provider_event are
    -- both leaves, and they are exactly the two collisions left: W12 writes supplier_assignment and
    -- GATE-015 correctly refused the fixture's as a duplicate dispatch. The skip is still recorded
    -- in the manifest as SKIPPED_PRODUCED_BY_THE_WORKFLOW_UNDER_TEST, never silently.
    if v_for_wf is not null
       and not exists (select 1 from public.phase_d_fixture_stage t
                        where st.stage_key = any(t.requires_stages))
       and exists (
         select 1 from public.phase_d_step_effect x
          where x.workflow_id = v_for_wf and x.effect_object_id = st.object_id) then
      v_man := v_man || jsonb_build_array(jsonb_build_object(
        'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
        'status', 'SKIPPED_PRODUCED_BY_THE_WORKFLOW_UNDER_TEST', 'detail', v_for_wf));
      v_owned := v_owned + 1;
      continue;
    end if;

    select array_agg(r) into v_missing
      from unnest(st.requires_stages) r
     where not exists (select 1 from jsonb_array_elements(v_man) m
                        where m->>'stage_key' = r and m->>'status' = 'CREATED');
    if v_missing is not null then
      v_man := v_man || jsonb_build_array(jsonb_build_object(
        'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
        'status', 'SKIPPED_PARENT_NOT_CREATED', 'detail', array_to_string(v_missing, ', ')));
      v_blocked := v_blocked + 1;
      continue;
    end if;

    if st.reference_relation is not null then
      execute format('select count(*) from %s', st.reference_relation) into v_ref_n;
      if v_ref_n = 0 then
        v_man := v_man || jsonb_build_array(jsonb_build_object(
          'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
          'status', 'BLOCKED_NO_REFERENCE_DATA', 'detail',
          format('%s holds 0 rows and this factory does not create business reference data',
                 st.reference_relation)));
        v_blocked := v_blocked + 1;
        continue;
      end if;
    end if;

    v_name  := format('ZZ DEMO — %s %s', v_label, st.stage_key);
    v_key   := md5(format('%s:%s', v_label, st.stage_key))::uuid::text;
    v_owner := v_key;
    -- F10. THE STATE IS THE STAGE'S OWN DECLARATION. This line used to read v_state := 'open' and
    -- every branch below then assigned a literal over it, so public.phase_d_fixture_stage.working_state
    -- -- the column whose sibling working_state_evidence explains, per stage, WHY that state -- was
    -- read by nothing at all. Five stages carried a state their object's contract does not declare
    -- and refused on every build since they were written; correcting the table changed nothing,
    -- because the table was not the source. It is now.
    v_state := coalesce(nullif(btrim(st.working_state),''), 'open');
    v_pay   := jsonb_build_object('fixture_label', v_label, 'stage', st.stage_key,
                                  'phase_d_test_context', true);

    -- D22. company_objective HAS NEVER ONCE CREATED ITS OBJECT.
    --
    -- D16 added this stage to fix W01-S03 dying on department_objective_goal_key_fkey, and it has
    -- refused on every build since with
    --     null value in column "goal" of relation "company_goals" violates not-null
    -- because the chain below has no branch for it, so the payload carried only the three
    -- bookkeeping keys every stage gets. The write map declares goal and metric; both are NOT NULL
    -- with no default.
    --
    -- Nothing failed loudly. stages_created read 23 of 25 and the missing one was recorded as
    -- REFUSED inside the manifest, where no caller was looking. A stage added to fix a foreign key
    -- and never observed creating anything is the "finished capability with no entry point" shape,
    -- and the only reason it surfaced is that a control started counting stages_not_created.
    if st.stage_key = 'company_objective' then
      v_pay := v_pay || jsonb_build_object(
        'goal', 1, 'metric', format('zz_demo_%s', v_label), 'active', true, 'direction', 'at_least');

    elsif st.stage_key = 'customer_account' then
      -- NO EMAIL AND NO PHONE. trg_inquiry_received_a queues a customer email for any inquiry whose
      -- customer has an address, and trg_new_quote_sms / trg_reveal_receipt_a do the same on a
      -- phone. The fixture identity carries neither, and the per-stage assertion below is what
      -- proves it rather than this comment.
      v_pay := v_pay || jsonb_build_object('full_name', v_name, 'locale', 'en');

    elsif st.stage_key = 'customer_terms_acceptance' then
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || jsonb_build_object(
        'terms_version', v_terms_ver,
        'terms_hash',    v_terms_hash,
        'accepted_by',   v_refs->>'customer_id');

    elsif st.stage_key = 'inquiry' then
      -- The FACTS fn_rfq_score reads, never a readiness flag. rfq_ready is derived by
      -- trg_rfq_complete and the verdict stays the product's own.
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || public.fn_phase_d_fixture_inquiry_payload(v_label);

    elsif st.stage_key = 'inquiry_answer' then
      v_owner := v_refs->>'inquiry_id';
      -- G11. THE GROUP IS A CHILD OF THIS SCENARIO'S OWN INQUIRY, so this stage creates it.
      -- public.inquiry_workstream_group holds 0 rows on production and this stage reported
      -- BLOCKED_NO_REFERENCE_DATA on every build since D9c. A group carries an inquiry_id foreign
      -- key and a defaulted rfq_mode and nothing else -- it is structure belonging to one inquiry,
      -- not a supplier or a field definition the estate shares. It is created for the inquiry this
      -- scenario created and rolled back with it.
      insert into public.inquiry_workstream_group (inquiry_id)
      values ((v_refs->>'inquiry_id')::uuid)
      on conflict do nothing;
      v_pay := v_pay || jsonb_build_object(
        'answer_scope','inquiry_shared', 'source_kind','customer', 'precedence','customer_confirmed',
        'value', to_jsonb('PHASE_D_FIXTURE_DO_NOT_PUBLISH — fixture answer'::text),
        'field_id', (select fd.field_id from public.field_definition fd order by fd.field_id limit 1),
        'group_id', (select g.id from public.inquiry_workstream_group g
                      where g.inquiry_id = (v_refs->>'inquiry_id')::uuid
                      order by g.id desc limit 1));

    elsif st.stage_key = 'notification' then
      -- G11. The recipient is the committed catalogue's reserved .invalid address and the channel
      -- is none. status is NOT set here: fn_phase_d_object_write's outbound-door loop overwrites it
      -- with the declared suppression in verified fixture context and does not let a caller opt out,
      -- which is exactly the D19 property -- a generated payload must not be able to re-arm a door.
      v_owner := 'phase_d_fixture';
      v_pay := v_pay || jsonb_build_object(
        'type', 'phase_d_fixture',
        'channel', 'none',
        'to_email', public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'recipient'),
        'subject', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — Phase D fixture notification record',
        'body', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a Phase D fixture notification. It is written at the suppression the outbound door declares, no sender selects it, and it is created inside a transaction that is aborted.');

    elsif st.stage_key = 'inquiry_version' then
      v_owner := v_refs->>'inquiry_id';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id', 'version', 1);

    elsif st.stage_key = 'inquiry_route_set' then
      v_owner := v_refs->>'inquiry_id';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'route_state','confirmed', 'routes', '["general"]'::jsonb,
                                           'evidence','ZZ DEMO — fixture route evidence');

    elsif st.stage_key = 'inquiry_document' then
      v_owner := v_refs->>'inquiry_id';
      v_pay := v_pay || jsonb_build_object('kind','boq', 'mime','application/pdf',
                                           'bucket','zz-phase-d-fixtures',
                                           'path', format('zz/%s/%s.pdf', v_label, st.stage_key),
                                           'file_name', format('zz-%s.pdf', v_label));

    elsif st.stage_key = 'document_extraction' then
      v_owner := v_refs->>'document_id';
      v_pay := v_pay || jsonb_build_object('document_id', v_refs->>'document_id',
                                           'method','deterministic', 'paid_model_used', false);

    elsif st.stage_key = 'supplier_safe_package' then
      v_owner := v_refs->>'inquiry_id';
      -- O11. THE PACKAGE NAMES A FILE, BECAUSE AN EMPTY FILE SET IS NOT AN APPROVED ONE.
      -- Before this line the stage built an inquiry, an approver and a prose 'contents' string and
      -- no files at all. Once BR-012 and GATE-013 gained the file-set leg PD-PRIV-002 needs, that
      -- made every W08, W12 and W13 drive refuse -- 41 of the 1,799 step-contract cases, all
      -- 'positive', all pd_rule_refused or pd_gate_refused. The fixture was incomplete under the
      -- new contract, and the fix is to complete it rather than to soften the rule back to the one
      -- that passed a package with an unredacted drawing.
      --
      -- The revision it registers points at the COMMITTED clean fixture bytes, whose CLEAN metadata
      -- verdict is a real recorded scan of those bytes. A fixture that fabricated its own scan
      -- verdict would be answering the question the scan exists to ask.
      perform public.fn_phase_d_fixture_file_revision(v_key);
      v_pay := v_pay || jsonb_build_object(
        'inquiry_id', v_refs->>'inquiry_id',
        'safe_package_ref', v_key,
        'safe_package_approved_by', 'ceo',
        'file_revisions', jsonb_build_array('fxrev:' || v_key),
        'contents','ZZ DEMO — scope and quantities only; no customer identity');

    elsif st.stage_key = 'supplier_account' then
      v_pay := v_pay || jsonb_build_object('company_name', v_name, 'verified', true);

    elsif st.stage_key = 'supplier_terms_acceptance' then
      v_owner := v_refs->>'supplier_id';
      v_pay := v_pay || jsonb_build_object('terms_version', v_sup_ver,
        'terms_hash',  v_sup_hash,
        'supplier_id', v_refs->>'supplier_id');

    elsif st.stage_key = 'supplier_capability' then
      v_owner := v_refs->>'supplier_id';
      v_pay := v_pay || jsonb_build_object('trades', '["general"]'::jsonb);

    elsif st.stage_key = 'supplier_verification_case' then
      v_owner := v_refs->>'supplier_id';
      v_pay := v_pay || jsonb_build_object('supplier_id', v_refs->>'supplier_id',
                                           'evidence','ZZ DEMO — fixture verification evidence',
                                           'verified_by','customer_support');

    elsif st.stage_key = 'supplier_assignment' then
      v_owner := v_refs->>'supplier_id';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'similarity', 0.9,
                                           'match_reason','ZZ DEMO — fixture assignment');

    elsif st.stage_key = 'quotation' then
      v_owner := v_refs->>'supplier_id';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id', 'quote_amount', 1000);

    elsif st.stage_key = 'quotation_revision' then
      v_owner := v_refs->>'supplier_id';
      v_pay := v_pay || jsonb_build_object('quote_id', v_refs->>'quote_id',
                                           'quote_revision_ref', v_key, 'platform_edited', false);

    elsif st.stage_key = 'quotation_comparison' then
      v_owner := v_refs->>'customer_id';
      -- O13. THE COMPARISON STATES ITS PUBLICATION. quote_comparisons.publication_state defaults to
      -- DRAFT on purpose -- a row written by a path that does not know about publication must be
      -- invisible to a customer rather than visible -- and this factory was such a path, so BR-019
      -- and GATE-018 refused every W14 and W15 drive on a comparison nobody had published. The
      -- workflows those steps model are reading a comparison that IS published, so the fixture says
      -- so. published_at is stamped by a20_quote_comparison_publication_stamp rather than supplied,
      -- because a caller should not be trusted to date a state change it is making right now.
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'analysis', jsonb_build_object('note','ZZ DEMO — fixture comparison'),
                                           'quote_count', 1,
                                           'publication_state', 'PUBLISHED',
                                           'signature', encode(sha256(convert_to(v_key,'UTF8')),'hex'));

    elsif st.stage_key = 'customer_selection' then
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || jsonb_build_object('comparison_id', v_refs->>'comparison_id',
                                           'selected_quote_id', v_refs->>'quote_id');

    elsif st.stage_key = 'payment_transaction' then
      -- THE REVEAL TIME IS SET HERE, WHERE THE ROW IS CREATED. Stage 190 inserts the transaction and
      -- stage 220 upserts the same id, so the refund window is stamped from THIS statement:
      -- trg_reveal_window fills refund_deadline only while it is null, and a later correction to
      -- revealed_at does not move a deadline that already exists. Setting it at stage 220 alone
      -- therefore changed nothing, measured -- the deadline stayed at now() + 3 working days and
      -- stage 230 stayed refused.
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'quote_id', v_refs->>'quote_id',
                                           'quote_amount', 1000, 'reveal_fee', 100,
                                           'revealed_at', now() - interval '30 days',
                                           'payment_ref', format('zz-pay-%s', v_label));

    elsif st.stage_key = 'provider_event' then
      v_owner := v_refs->>'transaction_id';
      v_key := format('evt_zz_%s', v_label);
      v_pay := v_pay || jsonb_build_object('event_type','checkout.session.completed');

    elsif st.stage_key = 'reconciliation_case' then
      v_owner := v_refs->>'transaction_id';
      v_pay := v_pay || jsonb_build_object('transaction_id', v_refs->>'transaction_id',
                                           'monetary_state','reconciled');

    elsif st.stage_key = 'reveal_transaction' then
      v_key := v_refs->>'transaction_id';
      v_owner := v_refs->>'customer_id';
      -- REVEALED THIRTY DAYS AGO, NOT THIS MINUTE. 26 Aug 2026: the founder's rule that a refund
      -- may only be claimed after the reveal window -- "only the option of refund is clickable after
      -- the period of 3 working days" -- is now enforced on public.refunds itself, and this chain
      -- paid and demanded its money back in the same transaction. Measured: stage 230
      -- refund_dispute_case REFUSED, "the refund window on transaction ... opens at 2026-08-31 and
      -- it is now 2026-08-26 (refund_window_not_yet_open)". A refund case follows a reveal that has
      -- already matured, so the fixture now describes one; the window it must clear is read from the
      -- same decision_policy the product reads, never assumed to be three days here.
      v_pay := v_pay || jsonb_build_object('reveal_fee', 100,
                                           'payment_ref', format('zz-pay-%s', v_label),
                                           'revealed_at', now() - interval '30 days',
                                           'supplier_id', (v_refs->>'supplier_id')::bigint);

    elsif st.stage_key = 'refund_dispute_case' then
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || jsonb_build_object('transaction_id', v_refs->>'transaction_id',
                                           'amount_fils', 10000, 'reason_code','other',
                                           'reason_note','ZZ DEMO — fixture refund case; no refund is executed',
                                           'requested_by', v_refs->>'customer_id');

    elsif st.stage_key = 'artifact_revision' then
      -- F08. BR-036 resolves artifact_sha256 against an artifact_review row or a business object
      -- record CARRYING that digest. public.artifact_review holds 0 rows, so the record is the
      -- only honest route: this stage writes one whose payload carries the digest of the committed
      -- artifact fixture's own text. The digest is computed, never typed.
      -- F48. v_art_sha WAS DECLARED AND NEVER ASSIGNED, SO THIS PAYLOAD CARRIED A NULL.
      --
      -- F08 added the variable with the comment "the digest BR-036 resolves" and the stage below
      -- writes it into the artifact record's payload. Nothing ever assigned it. Measured: BR-036
      -- refuses W08, W20, W22 and W24 with "review names artifact <id> at digest 5be99093ba73,
      -- which resolves to 0 artifact_review row(s) and 0 business object record(s) carrying exactly
      -- that digest" -- and the reason no record carries it is that this line wrote null.
      --
      -- The digest is the committed one F39 computed over the committed artifact body, read here
      -- rather than recomputed, so the value in the record is the same value the context resolver
      -- hands the rule and anyone can recompute both from the catalogue.
      v_art_sha := public.fn_phase_d_stage_content(st.object_id, 'CONTEXT_KEY', 'artifact_sha256');
      if v_art_sha is null then
        raise exception 'fn_phase_d_fixture_scenario: no committed artifact_sha256 fixture, so the artifact record would carry no digest and BR-036 could never pass or fail for a real reason (pd_fixture_artifact_digest_missing)'
          using errcode = '23502';
      end if;

      v_pay := v_pay || jsonb_build_object(
        'artifact_ref', public.fn_phase_d_stage_content(st.object_id, 'CONTEXT_KEY', 'artifact_ref'),
        'artifact_sha256', v_art_sha,
        'revision', 1);

    elsif st.stage_key = 'system_incident' then
      v_pay := v_pay || jsonb_build_object(
        'title',    public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'title'),
        'severity', 'low');

    elsif st.stage_key = 'marketing_content' then
      v_pay := v_pay || jsonb_build_object(
        'title', public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'title'),
        'body',  public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'body'),
        'channel','none', 'published', false);

    elsif st.stage_key = 'knowledge_capability_request' then
      v_pay := v_pay || jsonb_build_object(
        'requested_capability','REASONING',
        'note', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a knowledge/capability request record; no provider is called by Phase D');

    elsif st.stage_key = 'workforce_performance_case' then
      v_pay := v_pay || jsonb_build_object(
        'subject_role','phase_d_fixture_role',
        'note', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a workforce performance case about no real person and no real agent');

    elsif st.stage_key = 'notification_intent' then
      v_pay := v_pay || jsonb_build_object(
        'recipient',     public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'recipient'),
        'consent_basis', public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'consent_basis'),
        'provider_mode','mock', 'suppressed', true);

    elsif st.stage_key = 'department_mandate' then
      v_pay := v_pay || jsonb_build_object(
        'objective', public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'objective'),
        'goal_key',  v_refs->>'goal_key',
        'dept_key',  (select dept_key from public.org_departments where active order by dept_key limit 1));
      v_owner := (select dept_key from public.org_departments where active order by dept_key limit 1);

    elsif st.stage_key = 'review_record' then
      v_pay := v_pay || jsonb_build_object('verdict','approved',
                                           'subject_type','phase_d_fixture', 'subject_id', v_label,
                                           'author_agent','customer_support',
                                           'reviewer_role_id','customer_support',
                                           'stage', st.stage_key, 'notes','ZZ DEMO — fixture review');

    -- G10. THE FOUR EXISTING RELATIONS WHOSE COLUMNS A HANDLER MUST NOT INVENT.
    elsif st.stage_key = 'initiative' then
      -- public.org_tasks.dept_key is a foreign key into public.org_departments and title is NOT
      -- NULL. The department is read from the estate and the title from the committed catalogue.
      v_owner := (select dept_key from public.org_departments where active order by dept_key limit 1);
      v_pay := v_pay || jsonb_build_object(
        'title',  public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'title'),
        'detail', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a Phase D fixture initiative. It assigns no real work to any department and is created inside a transaction that is aborted.',
        'dept_key', (select dept_key from public.org_departments where active order by dept_key limit 1));

    elsif st.stage_key = 'legal_risk_review' then
      v_pay := v_pay || jsonb_build_object(
        'title',      public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'title'),
        'summary',    'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a Phase D fixture legal risk review. No document was reviewed, no legal opinion is expressed, and it is created inside a transaction that is aborted.',
        'doc_kind',   'phase_d_fixture',
        'risk_level', 'low');

    elsif st.stage_key = 'partnership_opportunity' then
      v_pay := v_pay || jsonb_build_object(
        'kind',   public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'kind'),
        'title',  public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'title'),
        'detail', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a Phase D fixture partnership opportunity. No partner is named, no approach is made, and it is created inside a transaction that is aborted.');

    elsif st.stage_key = 'invoice_receipt' then
      -- transaction_id is NOT NULL and a foreign key, so this stage depends on payment_transaction
      -- and takes the transaction the scenario created rather than choosing one.
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || jsonb_build_object(
        'transaction_id', v_refs->>'transaction_id',
        'bucket', 'zz-phase-d-fixtures',
        'path',   format('zz/%s/invoice-%s.pdf', v_label, st.stage_key));

    else
      -- G10. EVERY STAGE THE CHAIN ABOVE DOES NOT NAME, WHICH IS SIXTEEN PHASE D STORE OBJECTS AND
      -- ANY ADDED LATER. The object store writes from the payload every stage already carries, so
      -- the only thing these need is the one fact the store checks and a bookkeeping payload cannot
      -- supply: WHO OWNS THE RECORD. That is derived from the object's own declared ownership_scope
      -- rather than repeated sixteen times, so a CUSTOMER-scoped case is owned by the scenario's
      -- customer and a SUPPLIER-scoped one by its supplier. D9h found the opposite of this once --
      -- a customer-scoped object owned by something that was not a customer -- and a derivation
      -- cannot drift back into it one object at a time.
      v_owner := case (select ob.ownership_scope from public.phase_d_business_object_binding ob
                        where ob.object_id = st.object_id)
                   when 'CUSTOMER' then coalesce(nullif(v_refs->>'customer_id',''), v_key)
                   when 'SUPPLIER' then coalesce(nullif(v_refs->>'supplier_id',''), v_key)
                   else v_key end;
      v_pay := v_pay || jsonb_build_object('note', format(
        'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a Phase D fixture %s, created through fn_phase_d_object_write inside a transaction that is aborted. It states nothing about the business and is never published.',
        st.object_id));
    end if;

    select count(*) into v_notif_before from public.notifications;
    select coalesce(max(id),0) into v_notif_id_before from public.notifications;  -- G11
    select count(*) into v_inbox_before from public.kernel_trigger_inbox;

    begin
      v_w := public.fn_phase_d_object_write(jsonb_build_object(
        'object_id', st.object_id, 'business_key', v_key, 'owner_ref', v_owner,
        'created_by', v_actor, 'state', v_state, 'payload', v_pay));

      select count(*) into v_notif_after from public.notifications;
      if v_notif_after <> v_notif_before then
        -- G11. A STAGE MAY WRITE INTO ITS OWN OBJECT'S CANONICAL RELATION, AND ONLY SUPPRESSED.
        -- The assertion exists because a canonical write to some OTHER object queued a message as a
        -- side effect, and that property is what the Phase D hold rests on. It could not tell that
        -- apart from the one stage whose DECLARED object is the notification. Narrowed by
        -- derivation, never by naming a stage: the relation must be this object's own canonical
        -- relation, and every row written must carry the suppression the outbound door declares for
        -- it. A stage writing here for any other object still aborts the build, and so does this one
        -- if the row it wrote is deliverable.
        if not exists (select 1 from public.phase_d_object_write_map wm2
                        where wm2.object_id = st.object_id
                          and wm2.target_relation = 'public.notifications')
           -- and every row this stage wrote must carry the state the stage declares, which is the
           -- value the outbound door forces and no sender selects. A row at any other status is a
           -- deliverable message and aborts the build exactly as before.
           or exists (select 1 from public.notifications n
                       where n.id > v_notif_id_before
                         and n.status is distinct from st.working_state)
        then
          raise exception 'fn_phase_d_fixture_scenario: stage % wrote % row(s) into public.notifications. A fixture may not queue an outbound message. (pd_fixture_external_effect_produced)',
            st.stage_key, v_notif_after - v_notif_before using errcode = '23514';
        end if;
      end if;

      -- F15. THE PRODUCT'S OWN TRIGGERS GET THE LAST WORD ON AN INSERT, SO SETTLE THE STATE.
      -- public.trg_inquiry_enrich is a BEFORE INSERT trigger that sets the status a NEW inquiry
      -- has, so the inquiry stage asked for quote_ready and the row came out open, and GATE-011
      -- and BR-013 refused it -- correctly, because it was not quote-ready. A real inquiry is
      -- created open and BECOMES quote-ready, so the factory now does that: create, read back the
      -- column the write map points at the state, and if the product moved it, write again through
      -- the same canonical service. Skipped entirely when the readback already agrees.
      select c.k into v_state_col
        from public.phase_d_object_write_map wm,
             lateral (select k from jsonb_object_keys(wm.column_map) k where wm.column_map->>k = 'state') c
       where wm.object_id = st.object_id limit 1;
      if v_state_col is not null then
        begin
          execute format('select %I::text from %s where %I::text = $1',
                         v_state_col,
                         (select wm.target_relation from public.phase_d_object_write_map wm
                           where wm.object_id = st.object_id),
                         (select wm.key_column from public.phase_d_object_write_map wm
                           where wm.object_id = st.object_id))
            into v_actual using coalesce(split_part(v_w->>'result_reference','=',2), v_key);
          if v_actual is distinct from v_state then
            -- H08. ADDRESS THE ROW THE FIRST WRITE RETURNED. v_key is the stage's own uuid and names
            -- nothing on a generated-key relation; the returned identity is the row.
            v_w := public.fn_phase_d_object_write(jsonb_build_object(
              'object_id', st.object_id,
              'business_key', coalesce(split_part(v_w->>'result_reference','=',2), v_key),
              'owner_ref', v_owner,
              'created_by', v_actor, 'state', v_state, 'payload', v_pay));
            v_man := v_man || jsonb_build_array(jsonb_build_object(
              'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
              'status','SETTLED',
              'detail', format('%s.%s was %s after the create and the stage declares %s; a second write through the same canonical service settled it',
                               v_state_col, st.object_id, coalesce(v_actual,'(null)'), v_state)));
          end if;
        exception when others then
          v_man := v_man || jsonb_build_array(jsonb_build_object(
            'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
            'status','SETTLE_REFUSED',
            'refused_with', coalesce((regexp_match(SQLERRM,'\((pd_[a-z0-9_]+)\)'))[1],'(none)'),
            'reason', left(SQLERRM, 300)));
        end;
        v_state_col := null; v_actual := null;
      end if;

      -- F02. THE EVIDENCE MANIFEST THE FOUNDER ASKED FOR. Written from what the canonical write
      -- RETURNED, in the same statement block, so a manifest entry cannot exist for an object the
      -- service did not create -- and so an object the service created cannot be missing from it.
      v_scenario_id := public.fn_phase_d_scenario_record_write(jsonb_build_object(
        'fixture_id',        format('PDS-%s', st.stage_key),
        'fixture_version',   1,
        'source_checksum',   encode(sha256(convert_to(v_pay::text,'UTF8')),'hex'),
        'object_id',         st.object_id,
        'business_key',      coalesce(split_part(v_w->>'result_reference','=',2), v_key),
        'owner_ref',         v_owner,
        'ownership_scope',   coalesce((select ob.ownership_scope
                                         from public.phase_d_business_object_binding ob
                                        where ob.object_id = st.object_id), 'COMPANY'),
        'state',             v_w->>'state',
        'canonical_relation',v_w->>'canonical_relation',
        'canonical_service', 'fn_phase_d_object_write',
        'result_reference',  v_w->>'result_reference',
        'contributes_ref',   st.contributes_ref,
        'contributes_kind',  st.contributes_kind,
        'canonical_ref',     v_w->'canonical_ref',
        'contributed_value', case when st.stage_key = 'inquiry_route_set' then 'confirmed'
                                  -- F41. A PAYLOAD_VALUE STAGE CONTRIBUTES A VALUE, NOT ITS ROW ID.
                                  -- artifact_revision declares it contributes artifact_sha256, and
                                  -- this expression handed over split_part(result_reference,'=',2)
                                  -- -- the primary key of the row it had just written. BR-036 read
                                  -- 44208 and refused it as "not a SHA-256 digest", correctly.
                                  -- The digest is in the record's own payload, written by F08 over
                                  -- the committed artifact body, so it is read from there.
                                  -- F42. AN OBJECT_KEY STAGE CONTRIBUTES THE KEY THE PHASE D
                                  -- OBJECT STORE USES, WHICH IS NOT THE RELATION'S ROW ID.
                                  -- F45. OBJECT_KEY AND RESULT_KEY WERE THE SAME QUESTION ASKED TWICE.
                                  -- Which identity an object is known by is a property of the
                                  -- object, recorded once in phase_d_object_reference_strategy and
                                  -- derived from the frozen map -- not something a stage decides.
                                  -- Both arms are now the canonical reference the writer returned.
                                  when st.contributes_kind in ('OBJECT_KEY','RESULT_KEY')
                                    then v_w->'canonical_ref'->>'canonical_identity'
                                  when st.contributes_kind = 'PAYLOAD_VALUE' then
                                    (select o.payload #>> array[st.contributes_ref]
                                       from public.phase_d_object_record o
                                      where o.object_id = st.object_id
                                        and o.business_key = split_part(v_w->>'result_reference', '=', 2)
                                      limit 1)
                                  else split_part(v_w->>'result_reference', '=', 2) end,
        'expected_effect',   coalesce(st.note,'(none recorded on the stage)')));

      if st.contributes_ref is not null then
        v_refs := v_refs || jsonb_build_object(st.contributes_ref,
          case when st.stage_key = 'inquiry_route_set' then 'confirmed'
               when st.contributes_kind in ('OBJECT_KEY','RESULT_KEY')
                 then v_w->'canonical_ref'->>'canonical_identity'
               when st.contributes_kind = 'PAYLOAD_VALUE' then
                 (select o.payload #>> array[st.contributes_ref]
                    from public.phase_d_object_record o
                   where o.object_id = st.object_id
                     and o.business_key = split_part(v_w->>'result_reference', '=', 2)
                   limit 1)
               else split_part(v_w->>'result_reference', '=', 2) end);
      end if;

      select count(*) into v_inbox_after from public.kernel_trigger_inbox;
      v_man := v_man || jsonb_build_array(jsonb_build_object(
        'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
        'status','CREATED', 'relation', v_w->>'canonical_relation',
        'result_reference', v_w->>'result_reference', 'state', v_w->>'state',
        'policy_family', v_w->>'policy_family',
        'notifications_written', v_notif_after - v_notif_before,
        'kernel_trigger_rows_written', v_inbox_after - v_inbox_before,
        'contributes', st.contributes_ref));
      v_ok := v_ok + 1;

    exception when others then
      v_err := SQLERRM;
      if position('pd_fixture_external_effect_produced' in v_err) > 0 then raise; end if;
      -- D17. An outbound HTTP request is not a stage that failed; it is the whole scenario losing
      -- its zero-external-effect property. It aborts the build exactly as a notification does.
      if position('pd_object_outbound_request_produced' in v_err) > 0 then raise; end if;
      v_man := v_man || jsonb_build_array(jsonb_build_object(
        'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
        'status','REFUSED',
        'refused_with', coalesce((regexp_match(v_err,'\((pd_[a-z0-9_]+)\)'))[1],'(none)'),
        'reason', left(v_err, 300)));
      v_blocked := v_blocked + 1;
    end;
  end loop;

  -- G12. THE THREE OBJECTS ONLY THE KERNEL MAY CREATE, asked for through the kernel's own doors.
  -- fn_phase_d_object_write refuses workflow_run, workflow_step_run and handoff_record by name --
  -- "a Phase D handler that wrote it would be a second creator for one object" -- so no stage of
  -- the chain above can create them and the round-trip proof reported all three as
  -- NOT_CREATED_BY_ANY_STAGE, counted as neither pass nor fail. This does not write them either: it
  -- calls fn_kernel_workflow_start and fn_kernel_step_complete and records what the kernel made.
  begin
    v_w := public.fn_phase_d_kernel_object_fixture(jsonb_build_object('label', v_label));
    v_man := v_man || jsonb_build_array(jsonb_build_object(
      'stage_no', 998, 'stage_key','kernel_objects', 'object_id','workflow_run/workflow_step_run/handoff_record',
      'status', case when coalesce((v_w->>'objects_recorded')::int,0) > 0 then 'CREATED' else 'REFUSED' end,
      'relation','public.phase_c_workflow_run + _step_run + _handoff_run',
      'result_reference', format('run_id=%s step_run_id=%s handoff_run_id=%s',
        coalesce(v_w->>'run_id','(none)'), coalesce(v_w->>'step_run_id','(none)'),
        coalesce(v_w->>'handoff_run_id','(none)')),
      'state','open', 'contributes', null, 'detail', v_w->>'note'));
    if coalesce((v_w->>'objects_recorded')::int,0) > 0 then v_ok := v_ok + 1;
    else v_blocked := v_blocked + 1; end if;
  exception when others then
    v_man := v_man || jsonb_build_array(jsonb_build_object(
      'stage_no', 998, 'stage_key','kernel_objects', 'object_id','workflow_run/workflow_step_run/handoff_record',
      'status','REFUSED',
      'refused_with', coalesce((regexp_match(SQLERRM,'\((pd_[a-z0-9_]+)\)'))[1],'(none)'),
      'reason', left(SQLERRM, 300)));
    v_blocked := v_blocked + 1;
  end;

  -- F12. THE FOUNDER AUTHORITY FIXTURE, LAST, BECAUSE NOTHING DEPENDS ON IT. Six rules resolve
  -- founder_authority_ref against public.founder_command; a Phase D run has no founder command
  -- behind it, so all six refuse on every founder-gated step. This creates one, marked, at state
  -- received, founder_initiated_only false and refund_semantics false, inside the same aborted
  -- transaction -- and it authenticates nobody: see the header of F12.
  begin
    v_w := public.fn_phase_d_founder_authority_fixture(jsonb_build_object('label', v_label));
    v_refs := v_refs || jsonb_build_object('founder_authority_ref', v_w->>'founder_authority_ref');
    v_man := v_man || jsonb_build_array(jsonb_build_object(
      'stage_no', 999, 'stage_key','founder_authority', 'object_id','founder_command_fixture',
      'status','CREATED', 'relation','public.founder_command',
      'result_reference', v_w->>'founder_authority_ref', 'state','received',
      'contributes','founder_authority_ref'));
    v_ok := v_ok + 1;
  exception when others then
    v_man := v_man || jsonb_build_array(jsonb_build_object(
      'stage_no', 999, 'stage_key','founder_authority', 'object_id','founder_command_fixture',
      'status','REFUSED',
      'refused_with', coalesce((regexp_match(SQLERRM,'\((pd_[a-z0-9_]+)\)'))[1],'(none)'),
      'reason', left(SQLERRM, 300)));
    v_blocked := v_blocked + 1;
  end;

  select count(*) into v_notif_after from public.notifications;
  select count(*) into v_inbox_after from public.kernel_trigger_inbox;

  select coalesce(max(id),0) into v_notif_id_before from public.notifications;  -- reused as a bound

  return jsonb_build_object(
    'ok', v_blocked = 0, 'label', v_label, 'fixture_run_id', v_fixture_run,
    'evidence_manifest', (select coalesce(jsonb_agg(to_jsonb(x) order by x.scenario_record_id),'[]'::jsonb)
                            from public.phase_d_scenario_record x
                           where x.fixture_run_id = v_fixture_run),
    'stages_created', v_ok, 'stages_not_created', v_blocked,
    'stages_left_to_the_workflow_under_test', v_owned, 'for_workflow', v_for_wf,
    'stages_declared', (select count(*) from public.phase_d_fixture_stage where stage_no <= v_upto),
    'parent_refs', v_refs,
    -- THE RULE CONTEXT IS WHAT THIS SCENARIO ACTUALLY PERSISTED, not a set of plausible strings.
    -- Every value below is either a key returned by a write above or the exact value that write
    -- recorded on the row. A rule reading one of these is reading the scenario, and a rule whose
    -- key is absent still gets the driver's generated fixture and still refuses.
    -- F08. `rule_context` used to be returned here as a set of plausible strings for a caller to
    -- hand the rules. E32 removed the caller's ability to hand the kernel anything, so nothing has
    -- read it since; and two of its values were false -- terms_hash was the digest of the VERSION
    -- STRING, and safe_package_approved_by and assignment_result were literals with no record
    -- behind them. It is replaced by evidence_manifest above, which is what this scenario actually
    -- persisted, and by the committed catalogue for the values that are content rather than record.
    'parent_ref_keys', (select coalesce(jsonb_agg(k order by k),'[]'::jsonb)
                          from jsonb_object_keys(v_refs) k),
    'manifest', v_man,
    'notifications_written_by_this_scenario', v_notif_after - v_notif_start,
    -- G13. THE ONE THAT MUST BE ZERO. A row a sender would select is a queued outbound message; a
    -- row at the suppression the outbound door forces is a record. The suppression is read from the
    -- stage that declares it rather than written here, so there is no second copy of the word.
    'deliverable_notifications_written_by_this_scenario',
      (select count(*) from public.notifications n
        where n.id > coalesce(v_notif_id_start, 0)
          and n.status is distinct from (
            select st2.working_state from public.phase_d_fixture_stage st2
             where st2.object_id in (select wm3.object_id from public.phase_d_object_write_map wm3
                                      where wm3.target_relation = 'public.notifications')
             limit 1)),
    'kernel_trigger_rows_written_by_this_scenario', v_inbox_after - v_inbox_start,
    -- D17. MEASURED, NOT ASSERTED. Before D17 this object said 'external_effects', 0 while every
    -- build enqueued two POSTs to production edge functions, because the only thing counted was
    -- public.notifications. Both doors are now counted and the writer refuses on either.
    'outbound_http_requests_written_by_this_scenario',
      (select r.n from public.fn_phase_d_outbound_requests_by_this_transaction(v_net_start) r),
    'external_effects', 0, 'paid_calls', 0,
    'note', 'every row here was written through fn_phase_d_object_write; abort the transaction to leave nothing behind');
end $function$;

CREATE OR REPLACE FUNCTION public.fn_phase_d_rule_can_refuse()
 RETURNS TABLE(rule_id text, refusing_context text, states text, can_refuse boolean, note text)
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_full jsonb; v_held jsonb; v_overlay text;
  r record; e public.phase_d_rule_enforcement%rowtype; s1 text; s2 text; s3 text;
begin
  select ob.overlay_id into v_overlay from public.phase_c_overlay_binding ob order by 1 limit 1;

  -- (2) everything named, including the authority that permits it
  v_full := jsonb_build_object(
    'accountable_role_id','ceo','actor_role_id','ceo',
    'reviewer_role_id','inquiry_quality_analyst','step_id','W05-S01','workflow_id','W05',
    'run_id', 1, 'founder_gate','NONE','execution_context','production',
    'evidence_refs', jsonb_build_array('e1'), 'assumptions', jsonb_build_array('a real assumption'),
    'formula','numerator/denominator','denominator', 2, 'numerator', 1,
    'inquiry_owner','ceo','evidence_authority','A NEW_WORK_REQUEST',
    'commercial_policy_change','raise reveal fee','founder_authority_ref','founder_command:1',
    'policy_exception','waive fee','exception_authority_ref','founder_command:1',
    'sla_policy_id', (select sp.sla_policy_id from public.phase_b_sla_policy sp order by 1 limit 1),
    'handoff_id', (select hc.handoff_id from public.phase_d_handoff_contract hc order by 1 limit 1),
    'packet', '{}'::jsonb);

  -- (3) the same subjects with the AUTHORITY WITHHELD, and an actor that resolves to an overlay.
  -- This is the context the first two could not express, and it is where six of the seven refuse.
  v_held := (v_full - 'founder_authority_ref' - 'exception_authority_ref')
            || jsonb_build_object('actor_role_id', coalesce(v_overlay,'ceo'));

  for r in select br.rule_id from public.phase_b_business_rule br order by br.rule_id loop
    select rc.state into s1 from public.fn_phase_d_rule_check(r.rule_id, '{}'::jsonb) rc limit 1;
    select rc.state into s2 from public.fn_phase_d_rule_check(r.rule_id, v_full)      rc limit 1;
    select rc.state into s3 from public.fn_phase_d_rule_check(r.rule_id, v_held)      rc limit 1;
    select * into e from public.phase_d_rule_enforcement en where en.rule_id = r.rule_id;

    rule_id := r.rule_id;
    states  := format('empty=%s full=%s authority_withheld=%s', s1, s2, s3);
    can_refuse := 'ENFORCED_FAIL' in (s1, s2, s3);
    refusing_context := case
      when s1 = 'ENFORCED_FAIL' then 'empty'
      when s3 = 'ENFORCED_FAIL' then 'authority_withheld'
      when s2 = 'ENFORCED_FAIL' then 'full'
      else '(none)' end;
    -- E20. DERIVED FROM THE ENFORCEMENT ROW, NEVER FROM A RULE ID. The prior body matched
    -- 'BR-028' and 'BR-053'/'BR-054' as literals, so the excuse would have printed unchanged if any
    -- of them had started or stopped refusing. Every branch below reads a column.
    note := case
      when can_refuse then 'a context producing ENFORCED_FAIL exists'
      when s1 = 'DELEGATED_TO_KERNEL_GUARD' then 'delegated: the kernel guard decides, this predicate cannot invoke it'
      when e.rule_id is null then 'this rule has no row in phase_d_rule_enforcement, so nothing here can explain it'
      when e.enforcement_kind = 'EXECUTOR_ENFORCED'
        then format('enforced at %s, which is not this predicate; the predicate is not where this rule refuses',
                    coalesce(e.enforcement_point,'(unstated)'))
      when s1 = s2 and s2 = s3 and coalesce(cardinality(e.required_context),0) = 0
        then format('constant under every context tried, and it must be: this rule declares no required_context, so its verdict comes from %s — estate state, not the call. It will vary when that does.',
                    coalesce(e.enforcement_point,'(unstated)'))
      else 'NO CONTEXT PRODUCED A REFUSAL — this rule cannot fail' end;
    return next;
  end loop;
end
$function$;

CREATE OR REPLACE FUNCTION public.fn_phase_d_rule_check(p_rule_id text, p_context jsonb)
 RETURNS TABLE(state text, ok boolean, rule_type text, enforced boolean, reason text, refusal_code text, evidence_absent boolean)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_txt3 text; v_rev_ok boolean; v_rev_code text; v_rev_why text;   -- O07
  r public.phase_b_business_rule%rowtype;
  e public.phase_d_rule_enforcement%rowtype;
  v_missing text[]; v_n bigint; v_txt text; v_ok boolean; v_reason text;
  -- E30. A second count and a second string. A reference that must RESOLVE is two questions --
  -- is it shaped like the thing it claims to be, and does it name something that exists -- and
  -- more than once the answer lives in two relations.
  v_n2 bigint; v_txt2 text;
begin
  -- E19. FALSE UNLESS A BRANCH SAYS OTHERWISE. An OUT parameter left unset is NULL, and a null
  -- read as "not evidence-absent" by one caller and as "unknown" by another is how one column
  -- ends up meaning two things.
  evidence_absent := false;
  select * into r from public.phase_b_business_rule where rule_id = p_rule_id;
  if not found then
    state := 'NOT_IMPLEMENTED'; ok := false; rule_type := 'unknown'; enforced := false;
    reason := format('unknown business rule %s — fail closed', p_rule_id);
    refusal_code := 'unknown_rule'; return next; return;
  end if;
  rule_type := r.rule_type;

  select * into e from public.phase_d_rule_enforcement where rule_id = p_rule_id;
  if not found then
    state := 'NOT_IMPLEMENTED'; ok := false; enforced := false;
    reason := format('rule %s has no row in phase_d_rule_enforcement — fail closed rather than assume it is satisfied', p_rule_id);
    refusal_code := 'rule_unregistered'; return next; return;
  end if;
  refusal_code := e.refusal_code;
  enforced := (e.status = 'ENFORCED');

  -- ============================ the predicates ============================================
  -- Each reads the relation D2 bound for the object it governs. A rule whose evidence is absent
  -- REFUSES; it never passes for want of data.

  if p_rule_id in ('BR-001','BR-005') then
    v_ok := public.fn_phase_c_actor_may_own(p_context->>'accountable_role_id');
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('%s: owner %s %s', p_rule_id, coalesce(p_context->>'accountable_role_id','(none)'),
                     case when v_ok then 'resolves to one active canonical role'
                          else 'does not resolve to an active canonical role' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-004' then
    v_ok := coalesce((select kind from public.fn_phase_c_resolve_actor(p_context->>'actor_role_id')),'') = 'canonical';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-004: actor %s %s', coalesce(p_context->>'actor_role_id','(none)'),
                     case when v_ok then 'is canonical' else 'is not canonical; aliases are input compatibility only' end);
    return next; return;
  end if;

  if p_rule_id in ('BR-002','BR-030','BR-031','BR-037','BR-038') then
    v_ok := public.fn_kernel_reviewer_independent(p_context->>'accountable_role_id', p_context->>'reviewer_role_id');
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('%s: %s and %s %s', p_rule_id, coalesce(p_context->>'accountable_role_id','(none)'),
                     coalesce(p_context->>'reviewer_role_id','(none)'),
                     case when v_ok then 'are different effective identities'
                          else 'resolve to the same effective identity' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-048' then
    v_ok := not exists (select 1 from public.phase_c_overlay_binding ob
                         where ob.live_role_id = (select role_id from public.fn_phase_c_resolve_actor(p_context->>'actor_role_id')));
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then 'BR-048: the acting identity is not a category overlay'
                   else format('BR-048: %s is a category overlay and may not dispatch, approve suppliers, reveal identity or change policy',
                               p_context->>'actor_role_id') end;
    return next; return;
  end if;

  if p_rule_id in ('BR-053','BR-054') then
    v_ok := not coalesce((public.fn_kernel_paid_provider_gate('openai/gpt-4o-mini')->>'allowed')::boolean, true);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('%s: the paid-provider gate %s', p_rule_id,
                     case when v_ok then 'refuses a paid route' else 'ALLOWED a paid route' end);
    return next; return;
  end if;

  -- E28. BR-003 CHECKED THAT A KEY WAS PRESENT, NEVER THAT IT MEANT ANYTHING.
  -- It fell through to the generic CONTEXT_REQUIRED branch, whose whole test is "is the key present
  -- and non-empty". Measured 2026-08-20: BR-003 returned ENFORCED_PASS for
  -- founder_authority_ref = 'ZZ DEMO — founder_authority_ref for W16-S01', and for the single word
  -- 'banana'. A rule whose name is "founder-reserved decisions require founder authority" was
  -- satisfied by any non-empty string, which means the harness driving the workflow deliverable was
  -- forging founder authority and being told it had it. The founder's standing rule, written into
  -- this estate's own injected-defect catalogue, is that a fixture may never forge one.
  --
  -- The reference must now RESOLVE. 'founder_command:<id>' has to name a row in
  -- public.founder_command; nothing else is accepted, and the refusal says which of the two
  -- failures it is so a caller can tell "you named nothing" from "you named something that is not
  -- a founder decision". Fixing it here rather than in the harness closes it for every caller.
  if p_rule_id = 'BR-003' then
    v_txt := btrim(coalesce(p_context->>'founder_authority_ref',''));
    if v_txt = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-003 requires [founder_authority_ref] and the call names none of it.';
      return next; return;
    end if;
    v_ok := exists (select 1 from public.founder_command fc
                     where 'founder_command:' || fc.command_id::text = v_txt);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok
                   then format('BR-003: %s resolves to a founder command on record', v_txt)
                   else format('BR-003: %s does not resolve to any row in public.founder_command. A founder-reserved decision needs the founder''s actual decision, not a string in its shape.', v_txt) end;
    return next; return;
  end if;

  if p_rule_id = 'BR-043' then
    -- E30. BR-043 REFUSED NOTHING, FOR TWO INDEPENDENT REASONS, AND BOTH HAD TO GO.
    -- (1) Applicability keyed on 'policy_exception', which is NOT in its required_context, so the
    --     rule was NOT_APPLICABLE on every call the estate actually makes -- including calls that
    --     named an exception authority.
    -- (2) The authority test was "is the string non-empty", so 'banana' authorised an exception.
    -- Bound, applicable and ACTUALLY REFUSES are three different questions. A brief and two
    -- audits named this rule as a blocker; it had only ever answered the first.
    v_txt  := btrim(coalesce(p_context->>'policy_exception',''));
    v_txt2 := btrim(coalesce(p_context->>'exception_authority_ref',''));
    if v_txt = '' and v_txt2 = '' then
      state := 'NOT_APPLICABLE'; ok := true;
      reason := 'BR-043: the call proposes no policy exception and names no exception authority, so there is no exception to authorise';
      return next; return;
    end if;
    if v_txt2 = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := format('BR-043: exception %s is proposed with no exception_authority_ref', v_txt);
      return next; return;
    end if;
    -- Does the exception reach founder-reserved subject matter? public.founder_reserved_decision
    -- carries the eleven decision keys and their match terms. That table is the boundary list;
    -- it is not a literal typed into this predicate, so the predicate follows it when it moves.
    select count(*) into v_n from public.founder_reserved_decision d
     where v_txt <> ''
       and (position(lower(replace(d.decision_key,'_',' ')) in lower(replace(v_txt,'_',' '))) > 0
            or exists (select 1 from unnest(d.match_any) t
                        where btrim(t) <> '' and position(lower(btrim(t)) in lower(v_txt)) > 0));
    -- The founder's own authority, resolved exactly as E28 resolved BR-003.
    v_n2 := case when exists (select 1 from public.founder_command fc
                               where 'founder_command:' || fc.command_id::text = v_txt2)
                 then 1 else 0 end;
    if v_n > 0 then
      -- "cannot bypass ... founder boundaries": a delegated authority is not enough here.
      v_ok := (v_n2 = 1);
      reason := format('BR-043: exception %s touches %s founder-reserved decision(s) and names authority %s, which %s',
                       v_txt, v_n, v_txt2,
                       case when v_ok then 'resolves to a founder command on record'
                            else 'does not resolve to any row in public.founder_command -- a delegated authority cannot clear a founder boundary' end);
    else
      v_ok := (v_n2 = 1)
              or exists (select 1 from public.employee_authority ea
                          where 'employee_authority:' || ea.agent_key || ':' || ea.action_class = v_txt2);
      reason := format('BR-043: exception %s names authority %s, which %s',
                       coalesce(nullif(v_txt,''),'(unnamed)'), v_txt2,
                       case when v_ok then 'resolves to a founder command or a granted employee authority'
                            else 'resolves to no row in public.founder_command or public.employee_authority' end);
    end if;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    return next; return;
  end if;

  if p_rule_id in ('BR-021','BR-022','BR-023','BR-024') then
    -- E31. THE SAME DEFECT E30 FOUND IN BR-043, IN THE FOUR RULES E29 HAD JUST FIXED.
    -- E29 made the AUTHORITY resolve, and that half holds. But applicability still keyed on
    -- 'commercial_policy_change', which is NOT in these rules' required_context -- all four
    -- declare only [founder_authority_ref]. So a call that named a founder authority and no
    -- commercial_policy_change was NOT_APPLICABLE, and the authority E29 taught the rule to
    -- resolve was never looked at. Measured after E30: feeding every rule 'banana' for each key
    -- it declares, BR-021..BR-024 were four of the five remaining passes, and all four passed as
    -- NOT_APPLICABLE rather than on the merits.
    --
    -- Bound, applicable and ACTUALLY REFUSES are three questions. E28 and E29 answered the third
    -- for these rules and left the second. A rule is now applicable when EITHER key is named: if
    -- a call in a founder-gated workflow asserts a founder authority, that assertion is judged.
    if coalesce(btrim(p_context->>'commercial_policy_change'),'') = ''
       and coalesce(btrim(p_context->>'founder_authority_ref'),'') = '' then
      state := 'NOT_APPLICABLE'; ok := true;
      reason := format('%s: the call proposes no change to a founder-reserved commercial term and asserts no founder authority', p_rule_id);
      return next; return;
    end if;
    -- E29. THE SAME DEFECT E28 FOUND IN BR-003, IN FOUR MORE RULES.
    -- This tested only that founder_authority_ref was non-empty, so BR-021 through BR-024 --
    -- the rules guarding founder-reserved COMMERCIAL terms -- returned ENFORCED_PASS for the
    -- literal string 'banana'. Measured 2026-08-20: 17 of the 30 rules that declare a
    -- required_context pass on that string. These four are the ones where the consequence is a
    -- forged founder decision on pricing, and they get the same resolution E28 gave BR-003.
    v_txt := btrim(coalesce(p_context->>'founder_authority_ref',''));
    if v_txt = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := format('%s: change %s names no founder authority', p_rule_id,
                       coalesce(nullif(btrim(p_context->>'commercial_policy_change'),''),'(unnamed)'));
      return next; return;
    end if;
    v_ok := exists (select 1 from public.founder_command fc
                     where 'founder_command:' || fc.command_id::text = v_txt);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('%s: change %s %s', p_rule_id,
                     coalesce(nullif(btrim(p_context->>'commercial_policy_change'),''),'(unnamed)'),
                     case when v_ok then format('carries founder authority %s, which resolves to a founder command on record', v_txt)
                          else format('names %s, which does not resolve to any row in public.founder_command', v_txt) end);
    return next; return;
  end if;

  -- ---------------- BR-020: reveal only after reconciliation -------------------------------
  if p_rule_id = 'BR-020' then
    if p_context->>'transaction_id' is null then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-020: no transaction_id in context. A reveal decision with no transaction to reconcile is refused.';
      return next; return;
    end if;
    -- Aliased for the same reason as the lookup inside fn_phase_d_reveal_permitted: this
    -- function's OUT parameter is also called `reason`, so an unqualified reference is ambiguous
    -- between the plpgsql variable and the callee's returned column.
    select rp.permitted, rp.reason into v_ok, v_reason
      from public.fn_phase_d_reveal_permitted(p_context->>'transaction_id') rp;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := v_reason;
    return next; return;
  end if;

  -- ---------------- the object-backed rules D2 unblocked -----------------------------------
  if p_rule_id = 'BR-011' then           -- no customer identity in a supplier-facing payload
    v_txt := coalesce(p_context->>'supplier_payload','');
    if v_txt = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-011: no supplier_payload named. A payload nobody showed cannot be certified free of customer identity.';
      return next; return;
    end if;
    select count(*) into v_n from public.customers c
     where (coalesce(c.email,'') <> '' and position(lower(c.email) in lower(v_txt)) > 0)
        or (coalesce(c.phone,'') <> '' and position(c.phone   in v_txt) > 0)
        or (coalesce(c.full_name,'') <> '' and length(c.full_name) > 3
            and position(lower(c.full_name) in lower(v_txt)) > 0);
    -- The test is simply whether any customer identity appears in the payload. An earlier draft
    -- also ORed in a reveal_state check, which collapsed to the same expression under operator
    -- precedence and read as if it were doing something it was not.
    -- E30. I DID NOT CHANGE WHAT THIS RULE MEANS, BECAUSE ITS 'banana' PASS IS A TRUE PASS: the
    -- string 'banana' carries no customer identity, and BR-011 is a content test, not a reference
    -- test. What was wrong is that its only evidence source is a table held at zero. The row-match
    -- arm answers 0 for every payload ever shown to it, and 0 is also what it would answer if it
    -- were broken. So the SHAPE is tested too: a supplier-facing payload carrying an email address
    -- or a dialable UAE mobile is a customer identity leak whether or not that person is a row in
    -- this estate yet.
    -- O04/O07. THE TWO REGEX CLASSES WERE A LIST INSIDE THIS PREDICATE, AND THE LIST WAS SHORT.
    -- Measured on the live body, 24 Aug 2026: the payload
    --   '/Author (Omar Bin Faisal) /Title (Villa 42 plot 345-8871) /Creator (AL NAHDA CONSULTANTS)'
    -- returned ok = TRUE. The row arm searches public.customers, which holds 0 rows, and the shape
    -- arm tested an email and a UAE mobile and nothing else -- so the exact injection PD-PRIV-005
    -- names, a customer's NAME in a PDF /Info dictionary, passed the one rule that names it.
    --
    -- The classes now come from public.phase_d_personal_identifier_class, so extending the list is
    -- a row and not a redeploy, and the scanner in scripts/phase_d/metadata_scan.mjs reads the same
    -- table -- the rule and the scanner cannot disagree about what a personal identifier is.
    select count(*) into v_n2
      from public.phase_d_personal_identifier_class pic
     where pic.detection = 'REGEX' and not pic.supplier_facing_allowed
       and v_txt ~* pic.pattern;

    -- AND A FILE REVISION, WHERE ONE IS NAMED. A payload is text; the file that goes with it
    -- carries metadata this predicate cannot see. Where the caller names the revision, its recorded
    -- scan is part of the same answer, and a revision that is named and not dispatchable refuses
    -- here rather than at the point the file is already on its way.
    v_txt3 := btrim(coalesce(p_context->>'file_revision_ref',''));
    if v_txt3 <> '' then
      select fr.dispatchable, fr.refusal_code, fr.reason into v_rev_ok, v_rev_code, v_rev_why
        from public.fn_phase_d_file_revision_dispatchable(v_txt3) fr;
    else
      v_rev_ok := true; v_rev_code := null; v_rev_why := 'no file revision named in this context';
    end if;

    v_ok := (v_n = 0 and v_n2 = 0 and v_rev_ok);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    if not v_rev_ok then refusal_code := v_rev_code; end if;
    reason := format('BR-011: %s customer identity match(es) over %s customer row(s) searched for email, phone and full name; %s of %s registered machine-decidable identifier class(es) matched the payload itself; file revision %s. %s of the registered classes are HUMAN_REVIEW and are never scored automatically as absent.',
                     v_n, (select count(*) from public.customers), v_n2,
                     (select count(*) from public.phase_d_personal_identifier_class
                       where detection = 'REGEX' and not supplier_facing_allowed),
                     coalesce(nullif(v_txt3,''),'(none named)') || ': ' || coalesce(v_rev_why,''),
                     (select count(*) from public.phase_d_personal_identifier_class
                       where detection = 'HUMAN_REVIEW'));
    return next; return;
  end if;

  if p_rule_id = 'BR-012' then           -- an approved immutable supplier-safe package exists
    -- E30. This asked only whether two strings were non-empty, so 'banana' approved by 'banana'
    -- was an approved immutable supplier-safe package. supplier_safe_package is a REGISTERED
    -- business object of the IMMUTABLE_REVISION family: the ref must name one of those records in
    -- the approved state, and the approver must be someone who may own work here.
    v_txt  := btrim(coalesce(p_context->>'safe_package_ref',''));
    v_txt2 := btrim(coalesce(p_context->>'safe_package_approved_by',''));
    if v_txt = '' or v_txt2 = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-012: no approved supplier-safe package named, or no approver named. No assignment or notification may be created without one.';
      return next; return;
    end if;
    select count(*) into v_n from public.phase_d_object_record o
     where o.object_id = 'supplier_safe_package' and o.state = 'approved' and o.superseded_by is null
       and (o.business_key = v_txt or 'supplier_safe_package:' || o.business_key = v_txt);
    -- O04/O07. THE FILE SET WAS NEVER OPENED. This counted an approved package record and resolved
    -- the approver string, and stopped. Measured before the change: a package whose drawing carried
    -- an unapproved redaction and one whose drawing was clean returned the IDENTICAL ENFORCED_PASS.
    -- An identical answer to the injection and its control is the defect PD-PRIV-002 names, whatever
    -- the answer happens to be.
    --
    -- The leg below is the whole of the change: every LIVE revision registered against this package
    -- must be redaction-approved AND metadata-clean AT THE APPROVED DIGEST. The package answer is
    -- the WORST revision answer -- one leaking file in a set is a leak, so this is never an average
    -- and never a majority.
    select pr.dispatchable, pr.refusal_code, pr.reason into v_rev_ok, v_rev_code, v_rev_why
      from public.fn_phase_d_package_revisions_dispatchable(v_txt) pr;

    v_ok := (v_n >= 1) and public.fn_phase_c_actor_may_own(v_txt2) and v_rev_ok;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    if not v_rev_ok then refusal_code := v_rev_code; end if;
    reason := format('BR-012: package %s resolves to %s approved supplier_safe_package record(s) in public.phase_d_object_record, approver %s %s, and its file set: %s',
                     v_txt, v_n, v_txt2,
                     case when public.fn_phase_c_actor_may_own(v_txt2)
                          then 'resolves to an active canonical role'
                          else 'does not resolve to an active canonical role' end,
                     coalesce(v_rev_why,'(no verdict)'));
    return next; return;
  end if;

  if p_rule_id = 'BR-013' then           -- the inquiry is quote-ready
    if p_context->>'inquiry_id' is null then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-013: no inquiry_id named; readiness cannot be measured against nothing.';
      return next; return;
    end if;
    select count(*) into v_n from public.inquiries i
     where i.id::text = p_context->>'inquiry_id'
       and coalesce(i.status,'') in ('quote_ready','dispatched','quoted','completed');
    v_ok := (v_n = 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-013: inquiry %s %s', p_context->>'inquiry_id',
                     case when v_ok then 'is in a quote-ready state'
                          else 'is not quote-ready; mandatory qualification, route or document blockers remain' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-014' then           -- only a CONFIRMED route authorises dispatch
    v_ok := lower(coalesce(btrim(p_context->>'route_state'),'')) = 'confirmed';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-014: route state %s. Proposed, ambiguous, rejected and excluded routes cannot authorise dispatch.',
                     coalesce(nullif(btrim(p_context->>'route_state'),''),'(unstated)'));
    return next; return;
  end if;

  if p_rule_id = 'BR-015' then           -- only an approved, eligible supplier is dispatched to
    if p_context->>'supplier_id' is null then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-015: no supplier_id named.'; return next; return;
    end if;
    select count(*) into v_n from public.leads l
     where l.id::text = p_context->>'supplier_id'
       and coalesce(l.approval_status,'') = 'approved' and coalesce(l.verified,false);
    v_ok := (v_n = 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-015: supplier %s %s. public.leads already enforces approved implies verified as a CHECK constraint.',
                     p_context->>'supplier_id',
                     case when v_ok then 'is approved and verified' else 'is not an approved, verified supplier' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-016' then           -- one assignment per supplier per inquiry version
    if p_context->>'inquiry_id' is null or p_context->>'supplier_id' is null then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-016: inquiry_id and supplier_id are both required to decide duplicate assignment.';
      return next; return;
    end if;
    select count(*) into v_n from public.inquiry_matches m
     where m.inquiry_id::text = p_context->>'inquiry_id'
       and m.supplier_id::text = p_context->>'supplier_id';
    v_ok := (v_n <= 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-016: %s existing assignment(s) for that supplier and inquiry. NOTE: public.inquiry_matches carries no version column and no unique constraint, so this is enforced here and NOT structurally — recorded as the D2 REPAIR on supplier_assignment.', v_n);
    return next; return;
  end if;

  if p_rule_id = 'BR-017' then           -- a refused assignment is not a contact
    v_ok := lower(coalesce(btrim(p_context->>'assignment_result'),'')) in ('delivered','accepted','sent');
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-017: assignment result %s. Refused and failed assignments are not counted as contacted and create no success notification.',
                     coalesce(nullif(btrim(p_context->>'assignment_result'),''),'(unstated)'));
    return next; return;
  end if;

  if p_rule_id = 'BR-018' then           -- the supplier's own revision is never platform-edited
    -- O06/O07. THIS COMPARED NOTHING. The whole predicate was
    --   quote_revision_ref is non-empty AND platform_edited = 'false'
    -- which reads the CALLER'S OWN CLAIM ABOUT ITSELF: a normalisation that genuinely overwrote the
    -- supplier's figure and reported platform_edited = false passed. It is now a comparison of two
    -- records -- the live quotation_revision payload against the digest every live normalisation
    -- says it was derived from -- so an original that moved after it was normalised is visible
    -- whatever the caller says about itself.
    v_txt := btrim(coalesce(p_context->>'quote_revision_ref',''));
    select qi.intact, qi.refusal_code, qi.reason into v_rev_ok, v_rev_code, v_rev_why
      from public.fn_phase_d_quote_original_intact(v_txt) qi;
    v_ok := v_rev_ok;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    if not v_ok then refusal_code := v_rev_code; end if;
    reason := 'BR-018: ' || coalesce(v_rev_why, 'no verdict returned by fn_phase_d_quote_original_intact');
    return next; return;
  end if;

  if p_rule_id = 'BR-019' then           -- a customer sees only their own published comparison
    if p_context->>'comparison_id' is null or p_context->>'caller_customer_id' is null then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-019: comparison_id and caller_customer_id are both required.'; return next; return;
    end if;
    -- O06/O07. THIS TESTED OWNERSHIP AND CALLED IT PUBLICATION. The rule is "a customer sees only
    -- their own PUBLISHED comparison" and the predicate was count(*) ... where id = ? and
    -- customer_id = ?. A customer's own unpublished comparison passed, so the injection
    -- PD-QUOTE-004 names changed nothing a control could separate. Ownership is still tested --
    -- fn_phase_d_comparison_visible tests it FIRST and refuses an unrelated customer on a published
    -- comparison too, which is the arm proving the publication leg did not replace the ownership leg.
    select cv.visible, cv.refusal_code, cv.reason into v_rev_ok, v_rev_code, v_rev_why
      from public.fn_phase_d_comparison_visible(
             p_context->>'comparison_id', p_context->>'caller_customer_id',
             coalesce(nullif(btrim(p_context->>'caller_kind'),''), 'customer')) cv;
    v_ok := v_rev_ok;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    if not v_ok then refusal_code := v_rev_code; end if;
    reason := 'BR-019: ' || coalesce(v_rev_why, 'no verdict returned by fn_phase_d_comparison_visible');
    return next; return;
  end if;

  if p_rule_id = 'BR-025' then           -- acceptance names the exact version and hash
    -- E30. "the exact displayed version AND hash" was tested as "two non-empty strings", so
    -- 'banana' was an exact hash of version 'banana'. public.legal_documents holds the displayed
    -- documents and their versions. The hash must be a real SHA-256 digest, and it must be the
    -- digest OF THAT DOCUMENT AT THAT VERSION -- a hash that matches nothing is not a reference
    -- to anything specific, which is the whole of what this rule asks for.
    v_txt  := btrim(coalesce(p_context->>'terms_version',''));
    v_txt2 := lower(btrim(coalesce(p_context->>'terms_hash','')));
    if v_txt = '' or v_txt2 = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-025: acceptance must reference the exact displayed version AND hash; one without the other is not an acceptance of anything specific.';
      return next; return;
    end if;
    if v_txt2 !~ '^[0-9a-f]{64}$' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := format('BR-025: terms_hash %s is not a SHA-256 digest (64 hexadecimal characters), so it was never computed over the displayed terms.',
                       left(v_txt2, 24));
      return next; return;
    end if;
    select count(*) into v_n from public.legal_documents d
     where d.version = v_txt
       and encode(sha256(convert_to(coalesce(d.body_html,''), 'UTF8')), 'hex') = v_txt2;
    v_ok := (v_n >= 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-025: acceptance names version %s at digest %s, which matches %s row(s) in public.legal_documents whose displayed body hashes to exactly that digest',
                     v_txt, left(v_txt2, 12), v_n);
    return next; return;
  end if;

  if p_rule_id = 'BR-026' then           -- no certificate before an acceptance record
    -- E30. The reason string read "acceptance record %s exists" while the predicate had only
    -- checked that a string was non-empty -- evidence stating the premise it never tested.
    -- customer_terms_acceptance and supplier_terms_acceptance are registered APPEND_ONLY business
    -- objects; the ref must name one of those records.
    v_txt := btrim(coalesce(p_context->>'acceptance_ref',''));
    if v_txt = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-026: no acceptance record named. A certificate generated before acceptance would assert a fact that has not happened.';
      return next; return;
    end if;
    select count(*) into v_n from public.phase_d_object_record o
     where o.object_id in ('customer_terms_acceptance','supplier_terms_acceptance')
       and (o.business_key = v_txt or o.object_id || ':' || o.business_key = v_txt);
    v_ok := (v_n >= 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-026: acceptance_ref %s resolves to %s terms-acceptance record(s) in public.phase_d_object_record. A certificate may not precede one.',
                     v_txt, v_n);
    return next; return;
  end if;

  if p_rule_id = 'BR-029' then           -- conflicting evidence is preserved, not overwritten
    -- E30. Two arms, both weak. conflict_preserved='true' was the CALLER asserting its own
    -- compliance, which is not evidence of it; and evidence_authority was tested for
    -- non-emptiness, so 'banana' was an authority ranking. This rule is about RANK -- lower
    -- authority may not overwrite higher -- and this estate has a ranking:
    -- public.mep_evidence_weight, with its weight keys, evidence sources and source authorities.
    -- An authority that is not in the ranking cannot be ordered against another, so it cannot be
    -- preserved against one either.
    v_txt := btrim(coalesce(p_context->>'evidence_authority',''));
    if v_txt = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-029: no evidence authority named. Lower-authority evidence may not silently overwrite higher, and an unranked authority cannot be ordered against any other.';
      return next; return;
    end if;
    select count(*) into v_n from public.mep_evidence_weight w
     where w.weight_key = v_txt or w.evidence_source = v_txt or w.source_authority = v_txt;
    v_ok := (v_n >= 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-029: evidence authority %s matches %s row(s) in the public.mep_evidence_weight ranking (weight_key, evidence_source or source_authority)%s',
                     v_txt, v_n,
                     case when v_ok then ', so conflicting evidence can be retained in rank order'
                          else ' -- it is not a ranked authority in this estate' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-032' then           -- provider events are unique and replay-safe
    if coalesce(btrim(p_context->>'provider_event_id'),'') = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-032: no provider_event_id named; duplicate delivery cannot be decided without one.';
      return next; return;
    end if;
    -- E30. THE TEST WAS "appears AT MOST once", so an event id appearing ZERO times satisfied a
    -- rule about the safety of REAL provider events -- one never delivered, or the literal
    -- 'banana'. Zero cannot tell an unknown event from a safe one. It must resolve to EXACTLY ONE
    -- recorded delivery, in the provider event log or in the registered provider_event object.
    v_txt := btrim(coalesce(p_context->>'provider_event_id',''));
    select count(*) into v_n  from public.stripe_events se where se.event_id = v_txt;
    select count(*) into v_n2 from public.phase_d_object_record o
     where o.object_id = 'provider_event'
       and (o.business_key = v_txt or 'provider_event:' || o.business_key = v_txt);
    v_ok := (v_n + v_n2) = 1;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-032: provider event %s resolves to %s row(s) in public.stripe_events and %s registered provider_event record(s). Exactly one is replay-safe: zero is an event nobody received, more than one is a duplicate.',
                     v_txt, v_n, v_n2);
    return next; return;
  end if;

  if p_rule_id = 'BR-033' then           -- unknown money is quarantined, never success
    -- E30. A DENY-LIST OF THREE WORDS LEFT EVERY OTHER STRING AS A GOOD MONETARY STATE. The
    -- acceptance audit watched the harness hand this rule 'checkout_created' and get ok=true;
    -- 'banana' did just as well. An unrecognised monetary state IS an unknown one, which is
    -- precisely what this rule exists to quarantine. The permitted set is read from the state
    -- contracts of the TRANSACTION_RECORD family -- the money-carrying objects -- and not typed
    -- in here, so it follows the registry instead of drifting from it.
    -- G04. THE RULE ABOUT MONEY WAS ASKING THE REGISTER THAT DOES NOT MODEL MONEY.
    --
    -- E30 corrected a deny-list of three words by reading the allowed_states of the
    -- TRANSACTION_RECORD family, which was right about the method and wrong about the register.
    -- Two vocabularies describe a transaction in this estate:
    --
    --   public.phase_d_object_state_contract  open, pending, settled, refunded, failed, reconciled
    --       the generic OBJECT-RECORD lifecycle, derived from policy_family and applied identically
    --       to dispatch_batch, payment_transaction, reveal_transaction and supplier_assignment.
    --   public.phase_d_payment_state          checkout_created, payment_initiated, provider_success,
    --       payment_confirmed, payment_reconciled, reveal_authorized -- a SIX-RUNG LADDER, each rung
    --       carrying authorizes_reveal and a stated reason, and it is what public.transactions
    --       .fee_status actually holds and what BR-020 reads.
    --
    -- MEASURED: the intersection of those two sets is EMPTY. Not "different in places" -- no value
    -- appears in both. So BR-033 refused every real monetary state this estate can produce,
    -- including payment_reconciled, the founder-approved bar in BR-020, and would have PASSED
    -- 'settled' or 'refunded' for a payment that never reconciled. Two rules about one transaction,
    -- unable to agree about any transaction, because one of them was reading the wrong register.
    --
    -- THE FROZEN TEXT DECIDES WHICH REGISTER IS RIGHT: "Unknown, conflicting or unreconciled
    -- monetary states are blocked/quarantined and cannot be treated as success." Recognised, and
    -- reconciled. The ladder is the register of recognised monetary states and authorizes_reveal is
    -- the ladder's own mark for the reconciled rungs, so both halves of the frozen sentence are
    -- read from the register that states them.
    --
    -- THIS IS STRICTLY TIGHTER THAN WHAT IT REPLACES, and that is the test of it. Before: five
    -- words passed that say nothing about reconciliation. After: an unrecognised state is refused
    -- as unrecognised, a recognised state below reconciliation is refused as unreconciled, and the
    -- three quarantine words are refused by name as they always were. Only payment_reconciled and
    -- reveal_authorized pass, which is the relationship the founder's section 5 asked BR-020 and
    -- BR-033 to evaluate between them.
    --
    -- public.phase_d_object_state_contract IS NOT AMENDED. The founder's section 5 forbids putting
    -- reveal_authorized into the TRANSACTION_RECORD family to make this rule green, and nothing
    -- here does: the family keeps the generic lifecycle it describes, and this rule stops asking
    -- it a question it was never the register for.
    v_txt := lower(coalesce(btrim(p_context->>'monetary_state'),''));
    select count(*) into v_n
      from public.phase_d_payment_state ps
     where lower(ps.state_key) = v_txt and ps.authorizes_reveal;
    v_ok := v_txt <> '' and v_txt not in ('unknown','conflicting','unreconciled') and v_n >= 1;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-033: monetary state %s matches %s reconciled rung(s) of the payment ladder public.phase_d_payment_state (%s of its %s rungs are reconciled: %s). Unknown, conflicting, unreconciled and unrecognised states are blocked and quarantined, never treated as success.',
                     coalesce(nullif(v_txt,''),'(unstated)'), v_n,
                     (select count(*) from public.phase_d_payment_state where authorizes_reveal),
                     (select count(*) from public.phase_d_payment_state),
                     (select string_agg(ps2.state_key, ', ' order by ps2.rung)
                        from public.phase_d_payment_state ps2 where ps2.authorizes_reveal));
    return next; return;
  end if;

  if p_rule_id = 'BR-034' then           -- consent and suppression are respected
    if coalesce(btrim(p_context->>'notify_email'),'') = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-034: no notify_email named; consent cannot be decided for an unnamed recipient.';
      return next; return;
    end if;
    -- E30. 'banana' is not in the suppression list, so 'banana' was a consenting recipient. A
    -- string that cannot be an email address cannot have been checked for consent: it has to be
    -- an address before the suppression lookup means anything at all.
    v_txt := btrim(coalesce(p_context->>'notify_email',''));
    if v_txt !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+[.][A-Z]{2,}$' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := format('BR-034: %s is not an email address, so no consent or suppression decision about it exists to respect.', v_txt);
      return next; return;
    end if;
    select count(*) into v_n from public.email_suppressions s
     where lower(s.email) = lower(v_txt);
    v_ok := (v_n = 0);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-034: %s is %s in public.email_suppressions (%s matching row(s) over %s suppression(s) on record)',
                     v_txt,
                     case when v_ok then 'not suppressed' else 'SUPPRESSED and must not be contacted' end,
                     v_n, (select count(*) from public.email_suppressions));
    return next; return;
  end if;

  if p_rule_id = 'BR-035' then           -- only the approved revision publishes
    -- E30. Feeding the same junk string to both keys satisfied this rule, because equality of two
    -- unresolved strings is not evidence that either names an approved revision. The approved ref
    -- must resolve to an IMMUTABLE_REVISION business object record in the approved state -- the
    -- estate's own registry of revisions -- and the revision being published must be that one.
    v_txt  := btrim(coalesce(p_context->>'approved_revision_ref',''));
    v_txt2 := btrim(coalesce(p_context->>'publishing_revision_ref',''));
    if v_txt = '' or v_txt2 = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-035: the revision being published is not the independently approved revision, or neither was named.';
      return next; return;
    end if;
    if v_txt <> v_txt2 then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := format('BR-035: the publishing revision %s is not the approved revision %s', v_txt2, v_txt);
      return next; return;
    end if;
    select count(*) into v_n from public.phase_d_object_record o
      join public.phase_d_object_state_contract c on c.object_id = o.object_id
     where c.policy_family = 'IMMUTABLE_REVISION' and o.state = 'approved'
       and (o.business_key = v_txt or o.object_id || ':' || o.business_key = v_txt);
    v_ok := (v_n >= 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-035: the publishing revision is the approved one (%s), and that reference resolves to %s approved IMMUTABLE_REVISION record(s) in public.phase_d_object_record',
                     v_txt, v_n);
    return next; return;
  end if;

  if p_rule_id = 'BR-036' then           -- review inspects the artifact, not the brief
    -- E30. The acceptance audit caught this one from the other end: it read back
    -- "review names artifact ZZ DEMO - artifact_ref at digest ZZ DEMO - artifact_sha256" and got
    -- ok=true. A SHA-256 is 64 hexadecimal characters; a value that is not one was never computed
    -- over any artifact. And the digest must be OF something -- an artifact_review row, or a
    -- business object record carrying it. In an estate whose vision model once listed eight
    -- identifiers verbatim from a solid black rectangle, the digest is the only part of an
    -- artifact review that cannot be imagined.
    v_txt  := btrim(coalesce(p_context->>'artifact_ref',''));
    v_txt2 := lower(btrim(coalesce(p_context->>'artifact_sha256','')));
    if v_txt = '' or v_txt2 = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-036: the review names no artifact and digest. A verifier that reads the brief instead of the artifact has already produced a false pass in this estate.';
      return next; return;
    end if;
    if v_txt2 !~ '^[0-9a-f]{64}$' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := format('BR-036: artifact_sha256 %s is not a SHA-256 digest (64 hexadecimal characters), so it was not computed over any artifact.',
                       left(v_txt2, 24));
      return next; return;
    end if;
    select count(*) into v_n  from public.artifact_review ar where lower(ar.artifact_sha256) = v_txt2;
    select count(*) into v_n2 from public.phase_d_object_record o
     where lower(o.payload->>'artifact_sha256') = v_txt2;
    v_ok := (v_n + v_n2) >= 1;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-036: review names artifact %s at digest %s, which resolves to %s artifact_review row(s) and %s business object record(s) carrying exactly that digest',
                     v_txt, left(v_txt2, 12), v_n, v_n2);
    return next; return;
  end if;

  if p_rule_id = 'BR-039' then           -- a release needs an executable rollback
    -- E30. The rule says DEFINED AND EXECUTABLE; the predicate tested only that a string had been
    -- typed, so 'banana' was an executable rollback path. Executable means the estate can name the
    -- thing that would run: a registered action class carrying a compensating action, or a routine
    -- that exists in this database.
    v_txt := btrim(coalesce(p_context->>'rollback_ref',''));
    if v_txt = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-039: no rollback or recovery path named. A consequential release without one is not approvable.';
      return next; return;
    end if;
    select count(*) into v_n from public.org_action_executor x
     where x.action_class = v_txt and coalesce(btrim(x.compensation_action_class),'') <> '';
    select count(*) into v_n2 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = regexp_replace(v_txt, '^public[.]', '');
    v_ok := (v_n + v_n2) >= 1;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-039: rollback path %s resolves to %s registered action class(es) carrying a compensating action and %s routine(s) in this database%s',
                     v_txt, v_n, v_n2,
                     case when v_ok then '' else ' -- nothing that could be executed to undo the release' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-041' then           -- activity is not outcome
    -- E30. "when a business outcome is DEFINED" was tested as "a string was typed that differs
    -- from the activity metric", so 'banana' was a business outcome. public.metric_definition IS
    -- this estate's register of defined metrics. A metric that is not in it has not been defined,
    -- and success declared on it is exactly the vanity claim this rule forbids.
    v_txt  := btrim(coalesce(p_context->>'outcome_metric',''));
    v_txt2 := coalesce(p_context->>'activity_metric','');
    if v_txt = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-041: no business outcome metric named.';
      return next; return;
    end if;
    if v_txt = v_txt2 then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := format('BR-041: the declared outcome metric %s IS the activity metric under another name', v_txt);
      return next; return;
    end if;
    select count(*) into v_n from public.metric_definition m where m.metric_key = v_txt;
    v_ok := (v_n = 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-041: success is declared on outcome metric %s, distinct from the activity metric, and that key resolves to %s row(s) in public.metric_definition (of %s defined metrics)',
                     v_txt, v_n, (select count(*) from public.metric_definition));
    return next; return;
  end if;

  if p_rule_id = 'BR-049' then           -- inquiry accountability does not drift
    v_ok := coalesce(btrim(p_context->>'inquiry_owner'),'') = 'ceo'
            or coalesce(btrim(p_context->>'accountability_transfer_approved'),'') = 'true';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-049: inquiry owner is %s. Specialist and document handoffs do not move overall inquiry accountability away from rfq_qualification_manager without an approved workflow that says so.',
                     coalesce(nullif(btrim(p_context->>'inquiry_owner'),''),'(unstated)'));
    return next; return;
  end if;

  -- ---------------- D47. FIVE RULES THAT NOW DECIDE FOR THEMSELVES --------------------------
  -- BR-027, BR-040 and BR-042 were SCHEMA_ENFORCED fall-throughs returning ENFORCED_PASS with the
  -- reason "is enforced ... later in this same call". True, and useless: the schema they deferred
  -- to checked presence and emptiness only, so none of the three could refuse anything. D46 gave
  -- the validator declared types and domains; these three read the same facts directly.

  if p_rule_id = 'BR-027' then           -- a finding names the evidence it rests on
    v_ok := jsonb_typeof(p_context->'evidence_refs') = 'array'
            and jsonb_array_length(coalesce(p_context->'evidence_refs','[]'::jsonb)) > 0;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-027: %s evidence reference(s) named',
                                         jsonb_array_length(p_context->'evidence_refs'))
                   else 'BR-027: no evidence_refs array. A finding that names no evidence is an assertion.' end;
    return next; return;
  end if;

  if p_rule_id = 'BR-040' then           -- a ratio states its formula and its denominator
    -- THE DENOMINATOR IS TYPED HERE, not merely present. jsonb_typeof('"0"') is 'string', so a
    -- denominator of "0" as text satisfied every presence check in this estate and still divided
    -- something by nothing. least(100, NULL) = 100 is the same defect in another costume.
    v_ok := coalesce(btrim(p_context->>'formula'),'') <> ''
            and jsonb_typeof(p_context->'denominator') = 'number'
            and (p_context->>'denominator')::numeric > 0;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-040: formula %L over a numeric denominator of %s',
                                         p_context->>'formula', p_context->>'denominator')
                   else format('BR-040: formula %L, denominator %s of type %s. A ratio needs a stated formula and a numeric denominator greater than zero.',
                               coalesce(p_context->>'formula','(none)'),
                               coalesce(p_context->>'denominator','(none)'),
                               coalesce(jsonb_typeof(p_context->'denominator'),'absent')) end;
    return next; return;
  end if;

  if p_rule_id = 'BR-042' then           -- an analysis states its assumptions
    -- AND THEY MAY NOT BE THE ONES THE EXECUTOR WRITES FOR ITSELF. fn_phase_d_handler_execute
    -- writes ANALYSIS_HANDLER's assumptions unconditionally as the fixed one-element literal
    -- 'only the inputs named in this call were used; no external source was consulted'. A rule
    -- satisfied by a constant its own caller supplies is a rule that cannot fail, so that exact
    -- value is refused by name.
    v_ok := jsonb_typeof(p_context->'assumptions') = 'array'
            and jsonb_array_length(coalesce(p_context->'assumptions','[]'::jsonb)) > 0
            and p_context->'assumptions' <> jsonb_build_array(
                  'only the inputs named in this call were used; no external source was consulted');
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-042: %s assumption(s) stated',
                                         jsonb_array_length(p_context->'assumptions'))
                   when p_context->'assumptions' = jsonb_build_array(
                          'only the inputs named in this call were used; no external source was consulted')
                     then 'BR-042: the only assumption stated is the executor''s own boilerplate. A constant the caller writes for itself is not a stated assumption.'
                   else 'BR-042: no assumptions array. An analysis that states no assumptions has hidden them.' end;
    return next; return;
  end if;

  -- D51. BR-008 HAD ITS PREDICATE REMOVED AGAIN, AND THE REGISTRY WAS RIGHT THE FIRST TIME.
  -- D47 gave it one because fn_phase_d_handoff_packet_valid is STABLE and therefore callable.
  -- Callable is not the same as answerable HERE. The packet is what the SENDING STEP PRODUCES;
  -- at the moment fn_phase_d_rule_check runs — the step has just opened and nobody has done it —
  -- the packet does not exist yet. So the predicate refused 29 of 30 first steps, then 15 of 30
  -- once the applicability rule was added, and every one of those refusals was the rule being
  -- asked a question the lifecycle had not reached.
  --
  -- Its enforcement_kind was KERNEL_ENFORCED for exactly that reason: the kernel checks the packet
  -- when the handoff is accepted, which is when there is one to check. It falls through to the
  -- delegated branch below, where it is honestly labelled rather than given a pass or a refusal it
  -- has not earned. BR-044 keeps its predicate: an SLA due time IS computable when the step opens.
  if p_rule_id = 'BR-044' then           -- an SLA has a computable due time
    if coalesce(btrim(p_context->>'sla_policy_id'),'') = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-044: no sla_policy_id named, so no due time can be computed.';
      return next; return;
    end if;
    -- D51. THE DELEGATE DEFAULTS, SO "is not null" COULD NEVER FAIL. fn_kernel_sla_due ends in
    -- coalesce(<the policy lookup>, 24), so an sla_policy_id that exists nowhere silently gets a
    -- 24-hour deadline and a non-null answer. Measured: fn_kernel_sla_due('zz-demo-no-such-policy')
    -- returns a timestamp 24 hours out. The predicate therefore asks the question the default hides:
    -- is this policy REGISTERED, and does it then compute a due time. The 24-hour fallback lives in
    -- a frozen kernel routine and is not changed here; it is named so it can be seen.
    v_ok := exists (select 1 from public.phase_b_sla_policy sp
                     where sp.sla_policy_id = p_context->>'sla_policy_id')
            and public.fn_kernel_sla_due(p_context->>'sla_policy_id', now()) is not null;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-044: policy %s resolves to a due time',
                                         p_context->>'sla_policy_id')
                   else format('BR-044: policy %L computes no due time', p_context->>'sla_policy_id') end;
    return next; return;
  end if;
  -- ---------------- structurally enforced elsewhere ----------------------------------------
  if e.enforcement_kind in ('SCHEMA_ENFORCED','EXECUTOR_ENFORCED') then
    state := 'ENFORCED_PASS'; ok := true;
    reason := format('%s is enforced at %s later in this same call, which refuses with %s',
                     p_rule_id, e.enforcement_point, e.refusal_code);
    return next; return;
  end if;
  if e.enforcement_kind in ('KERNEL_ENFORCED','TRIGGER_ENFORCED') then
    -- D47. THIS USED TO SAY ENFORCED_PASS, AND THE PLAN ASKED FOR THE DELEGATE TO BE INVOKED
    -- INSTEAD. Measured, that is possible for two of these and impossible for the other eleven:
    --
    --   BR-006 BR-007 BR-009 BR-045  public.fn_kernel_step_complete(jsonb)  VOLATILE SECDEF, writes
    --   BR-046                       public.fn_kernel_cancel(jsonb)         VOLATILE SECDEF, writes
    --   BR-010                       public.fn_phase_c_trace_append_only()  returns trigger
    --   BR-047                       public.fn_org_authority_guard()        returns trigger
    --   BR-050 BR-051 BR-052         public.fn_kernel_write_guard()         returns trigger
    --
    -- A routine returning trigger cannot be called at all, and a volatile writer cannot be called
    -- from this STABLE predicate without performing the very act it is being asked about. BR-008
    -- and BR-044 CAN be called, and now are, above.
    --
    -- So these get a state of their own rather than a pass they did not earn. Nothing about the
    -- runtime changes: fn_phase_d_handler_execute refuses on ENFORCED_FAIL and NOT_IMPLEMENTED, and
    -- DELEGATED_TO_KERNEL_GUARD is neither. What changes is the count that may be claimed. A rule
    -- enforced by a guard this call never reaches is not a rule this predicate enforces.
    state := 'DELEGATED_TO_KERNEL_GUARD'; ok := true;
    reason := format('%s is enforced at %s, which raises %s. That routine %s, so this predicate cannot invoke it: the guard decides and this call does not.',
                     p_rule_id, e.enforcement_point, e.refusal_code,
                     case when e.enforcement_kind = 'TRIGGER_ENFORCED'
                          then 'returns trigger' else 'is a volatile writer' end);
    return next; return;
  end if;
  if e.enforcement_kind = 'CONTEXT_REQUIRED' then
    select array_agg(k order by k) into v_missing
      from unnest(e.required_context) k
     where not (p_context ? k) or coalesce(btrim(p_context->>k),'') = '';
    v_ok := (v_missing is null);
    -- E19. THE REFUSAL STANDS; ONLY ITS NAME CHANGES. This branch fires when the call names none of
    -- the evidence the rule reads, which is not the same event as the rule reading that evidence and
    -- finding it violates policy. Both refuse. The state stays ENFORCED_FAIL so that every existing
    -- reader -- fn_phase_d_handler_execute, fn_phase_d_rule_can_refuse, fn_phase_d_rule_state --
    -- behaves exactly as before; evidence_absent is the new fact, and it is what lets
    -- fn_phase_d_dispatch_step record REFUSED_EVIDENCE_ABSENT instead of REFUSED. A reader could
    -- previously take an absence of evidence for a business violation, and the 2026-08-20
    -- acceptance audit did exactly that and said so in finding 3.
    evidence_absent := not v_ok;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('%s: the call names %s', p_rule_id, array_to_string(e.required_context,', '))
                   else format('%s requires [%s] and the call names none of it.', p_rule_id, array_to_string(v_missing,', ')) end;
    return next; return;
  end if;

  -- ---------------- NO PREDICATE. This is the answer that used to be `true`. ----------------
  state := 'NOT_IMPLEMENTED'; ok := false; enforced := false;
  reason := format('%s has no predicate in fn_phase_d_rule_check. NOT_IMPLEMENTED is not a pass.', p_rule_id);
  refusal_code := coalesce(e.refusal_code, 'rule_not_implemented');
  return next;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_phase_d_run_injected_defects()
 RETURNS TABLE(defect_id text, category text, status text, observed text, blocker text)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_s4_step text; v_s4_bare text; v_s4_reason text; v_s3_step text; v_s3_flip text;
  v_p2_state text; v_p2_code text; v_p2_fstate text; v_p2_fpassed boolean;
  v_p2_fcode text; v_p2_fabsent boolean; v_p2_other text;
  -- N04 locals. Named for the case that uses them so a later reader can delete them with it.
  v_c4_ob0 bigint; v_c4_row bigint; v_c4_n0 bigint; v_c4_n1 bigint; v_c4_n2 bigint; v_c4_emit jsonb;
  v_t5_board text; v_c1_verdict text; v_c1_observed text;
  v_ok boolean; v_msg text; v_n int; v_a jsonb; v_b jsonb; v_key text; v_pay jsonb;
  v_f3_txn uuid;   -- PD-FIN-003 fixture: the payment the injected refund reverses
  v_sup text; v_id bigint;
  -- M08. The locals the eight re-measured branches need. Every one is scratch for a single branch
  -- except v_m3_trace and v_m3_task, which carry a REAL sealed verdict and a REAL task from the
  -- branch that produced them to the branch that has to attempt to tamper with it.
  v_m3_fx jsonb; v_m3_drive jsonb; v_m3_a jsonb;
  v_m3_refkey text; v_m3_boid text; v_m3_key text; v_m3_ctl text; v_m3_state text; v_m3_def text;
  v_m3_srid bigint; v_m3_run bigint; v_m3_task bigint; v_m3_trace bigint; v_m3_sup bigint;
  v_m3_n int; v_m3_s0 int; v_m3_s1 int; v_m3_p1 int; v_m3_p2 int; v_m3_p3 int;
  v_m3_ok2 boolean; v_m3_orph bigint;
begin
  if public.fn_phase_d_fixture_context() is null then
    -- F01. THIS READ A GUC ANY CALLER COULD SET. app.phase_d_test_context = 'on' was a string the
    -- caller supplied about itself; the context is now an hmac over txid_current(), keyed by a
    -- secret no role can SELECT, minted only against an approved audited operation. Leaving the old
    -- door open here would have left the whole control reachable through the value F01 removed.
    raise exception 'no verified Phase D fixture context in this transaction (pd_fixture_no_test_context)'
      using errcode = '23514',
            hint = 'select public.fn_phase_d_test_context_open(''{"operation_key":"pdop_deliverable_build","label":"..."}''); and abort the transaction when finished.';
  end if;

  -- ============ helper shape: each probe INJECTS, then reports what the machine did ============

  -- ---- IDEMPOTENCY ----------------------------------------------------------------------------
  -- PD-IDEM-001 duplicate registration: one identity, two canonical writes, no second row.
  v_key := 'zz-idem-001-' || md5('reg');
  v_a := public.fn_phase_d_object_write(jsonb_build_object(
    'object_id','customer_account','business_key', md5(v_key)::uuid::text,'owner_ref', md5(v_key)::uuid::text,
    'created_by','defect_probe','state','active','payload', jsonb_build_object('full_name','ZZ DEMO — idem001')));
  begin
    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','customer_account','business_key', md5(v_key)::uuid::text,'owner_ref', md5(v_key)::uuid::text,
      'created_by','defect_probe','state','active','payload', jsonb_build_object('full_name','ZZ DEMO — idem001')));
    v_ok := (v_a->>'result_reference') = (v_b->>'result_reference');
    v_msg := format('both writes resolved to %s', v_b->>'result_reference');
  exception when others then
    v_ok := true; v_msg := 'second write refused: ' || left(SQLERRM,70);
  end;
  defect_id:='PD-IDEM-001'; category:='IDEMPOTENCY';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-IDEM-003 duplicate supplier assignment: the unique index is the machine's answer.
  select count(*) into v_n from pg_index i join pg_class ic on ic.oid=i.indexrelid
   where i.indrelid='public.inquiry_matches'::regclass and i.indisunique
     and ic.relname='inquiry_matches_inquiry_id_supplier_id_key';
  defect_id:='PD-IDEM-003'; category:='IDEMPOTENCY';
  status := case when v_n=1 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('UNIQUE (inquiry_id, supplier_id) present=%s; GATE-015 refuses a duplicate dispatch before it', v_n);
  blocker := null; return next;

  -- PD-IDEM-004 duplicate notification request -> one effect. The effect ledger's unique key.
  select count(*) into v_n from pg_constraint
   where conrelid='public.phase_d_effect_ledger'::regclass and contype='u';
  defect_id:='PD-IDEM-004'; category:='IDEMPOTENCY';
  status := case when v_n>0 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('phase_d_effect_ledger carries %s unique constraint(s) on (step_run_id, effect_type)', v_n);
  blocker := null; return next;

  -- PD-IDEM-005 duplicate payment webhook -> one monetary transition.
  v_key := 'zz-idem-005-' || md5('pay');
  begin
    perform public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W16-S02','idempotency_key',v_key,'mock_case','success',
      'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
    v_b := public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W16-S02','idempotency_key',v_key,'mock_case','success',
      'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
    select count(*) into v_n from public.phase_d_external_attempt where idempotency_key=v_key and delivered;
    v_ok := coalesce((v_b->>'replay')::boolean,false) and v_n=1;
    v_msg := format('replay=%s deliveries=%s', v_b->>'replay', v_n);
  exception when others then v_ok:=false; v_msg:='raised: '||left(SQLERRM,70); end;
  defect_id:='PD-IDEM-005'; category:='IDEMPOTENCY';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-IDEM-002 duplicate workflow step completion -> the FIRST result is returned again.
  -- THE OLD BLOCKER SAID THIS NEEDED A COMMITTED STEP RUN. Re-measured 24 Aug 2026 and false.
  -- fn_kernel_step_complete section 1 reads public.phase_c_step_completion by idempotency_key
  -- BEFORE any work and returns v_prior || jsonb_build_object('replay', true). Nothing on that
  -- path waits for a commit, so two calls in ONE transaction exercise the real branch.
  begin
    perform set_config('app.phase_d_hold_step','W04-S03', true);
    v_m3_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','zz-pd-idem-002','execution_context','test','for_workflow','W04'));
    select st.contributes_ref into v_m3_refkey from public.phase_d_fixture_stage st
     where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id='W04')
     limit 1;
    v_m3_boid := case when v_m3_refkey is not null and coalesce(v_m3_fx->'parent_refs'->>v_m3_refkey,'') <> ''
      then (select primary_object from public.phase_b_workflow where workflow_id='W04')
           || ':' || (v_m3_fx->'parent_refs'->>v_m3_refkey) else null end;
    v_m3_drive := public.fn_phase_d_drive_workflow(jsonb_build_object(
      'workflow_id','W04','label','zz-pd-idem-002','execution_context','production',
      'hold_at_step_id','W04-S03')
      || case when v_m3_boid is null then '{}'::jsonb
              else jsonb_build_object('business_object_id', v_m3_boid) end);
    v_m3_srid := nullif(v_m3_drive->>'held_step_run_id','')::bigint;
    v_m3_run  := nullif(v_m3_drive->>'run_id','')::bigint;
    perform set_config('app.phase_d_hold_step','', true);
    if v_m3_srid is null then
      v_ok := false;
      v_msg := 'no step run was held open at W04-S03; the drive stopped at '
            || coalesce(v_m3_drive->'stopped'->>'refused_with','(no reason given)');
    else
      v_m3_key := 'zz-pd-idem-002:' || v_m3_srid;
      v_a := public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_m3_srid,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = v_m3_srid),
        'outcome','pass', 'idempotency_key', v_m3_key,
        'inputs', jsonb_build_object('mode','first completion'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - validated customer profile'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','first completion')),
        'acceptance_criteria','the step completes once',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1));
      v_b := public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_m3_srid,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = v_m3_srid),
        'outcome','pass', 'idempotency_key', v_m3_key,
        'inputs', jsonb_build_object('mode','duplicate completion'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - validated customer profile'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','duplicate completion')),
        'acceptance_criteria','a duplicate returns the first result',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1));
      begin
        perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_m3_srid,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = v_m3_srid),
        'outcome','pass', 'idempotency_key', v_m3_key || ':a-different-key',
        'inputs', jsonb_build_object('mode','control'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - validated customer profile'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','control')),
        'acceptance_criteria','a different key on a step run already completed',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1));
        v_m3_ctl := 'ACCEPTED';
      exception when others then
        v_m3_ctl := case when position('k3_step_state_invalid' in SQLERRM) > 0
                         then 'k3_step_state_invalid/' || SQLSTATE
                         else SQLSTATE || ':' || left(SQLERRM, 60) end;
      end;
      select count(*) into v_m3_n from public.phase_c_step_completion where step_run_id = v_m3_srid;
      select state into v_m3_state from public.phase_c_workflow_step_run where step_run_id = v_m3_srid;
      v_ok := not coalesce((v_a->>'replay')::boolean, true)
          and coalesce((v_b->>'replay')::boolean, false)
          and v_m3_ctl = 'k3_step_state_invalid/23514'
          and v_m3_n = 1 and v_m3_state = 'completed';
      v_msg := format(
        'W04 driven through the kernel doors and held open at W04-S03 (step run %s). INJECTION: '
     || 'fn_kernel_step_complete called TWICE with the same idempotency_key %L. First call '
     || 'replay=%s; second call replay=%s and it returned the FIRST stored result rather than '
     || 'recomputing one. CONTROL, differing in exactly one respect - same step run, same actor, '
     || 'same output, a DIFFERENT idempotency_key: %s, because public.phase_b_step_transition '
     || 'declares no completed -> completed edge, so a second real completion is refused rather '
     || 'than replayed. public.phase_c_step_completion rows for this step run: %s. Step run state: '
     || '%s. No second completion and no second effect; the transaction is aborted.',
        v_m3_srid, v_m3_key, coalesce(v_a->>'replay','(null)'), coalesce(v_b->>'replay','(null)'),
        v_m3_ctl, v_m3_n, v_m3_state);
    end if;
  exception when others then
    perform set_config('app.phase_d_hold_step','', true);
    v_ok := false;
    v_msg := 'the W04 drive raised before the injection could be made: ' || left(SQLERRM, 220);
  end;
  defect_id:='PD-IDEM-002'; category:='IDEMPOTENCY';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- ---- CONCURRENCY ----------------------------------------------------------------------------
  -- PD-CONC-002 two suppliers submit the same revision number -> revision uniqueness.
  select count(*) into v_n from public.phase_d_business_object_binding
   where object_id='quotation_revision' and policy_family='IMMUTABLE_REVISION';
  defect_id:='PD-CONC-002'; category:='CONCURRENCY';
  status := case when v_n=1 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := 'quotation_revision is IMMUTABLE_REVISION: a second write supersedes as a new revision and never overwrites';
  blocker := null; return next;

  -- PD-CONC-003 two admins publish the same quotation set -> idempotent result.
  v_key := 'zz-conc-003-' || md5('pub');
  begin
    perform public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W15-S04','idempotency_key',v_key,'mock_case','success',
      'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
    v_b := public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W15-S04','idempotency_key',v_key,'mock_case','success',
      'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
    v_ok := coalesce((v_b->>'replay')::boolean,false);
    v_msg := format('second publish returned the first result id %s and delivered nothing new', v_b->>'provider_result_id');
  exception when others then v_ok:=false; v_msg:='raised: '||left(SQLERRM,70); end;
  defect_id:='PD-CONC-003'; category:='CONCURRENCY';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-CONC-004 cancellation races with delivery -> a cancelled subject cannot deliver.
  v_key := 'zz-conc-004-' || md5('cancel');
  begin
    perform public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W13-S01','idempotency_key',v_key,'mock_case','cancellation',
      'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
    begin
      perform public.fn_phase_d_external_deliver(jsonb_build_object(
        'step_id','W13-S01','idempotency_key',v_key,'mock_case','success',
        'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
      v_ok := false; v_msg := 'a cancelled subject was delivered';
    exception when others then
      v_ok := position('pd_external_cancelled' in SQLERRM)>0;
      v_msg := 'delivery after cancellation refused: pd_external_cancelled';
    end;
  exception when others then v_ok:=false; v_msg:='raised: '||left(SQLERRM,70); end;
  defect_id:='PD-CONC-004'; category:='CONCURRENCY';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-CONC-005 refund decision races with execution -> one immutable decision.
  defect_id:='PD-CONC-005'; category:='CONCURRENCY';
  select count(*) into v_n from pg_trigger t join pg_proc p on p.oid=t.tgfoid
   where t.tgrelid='public.refunds'::regclass and p.proname='fn_refund_founder_decision_only';
  status := case when v_n=1 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := 'z00_refund_founder_decision_only is a row trigger on public.refunds: every approval path, '
           || 'racing or not, must present an active founder identity or the row is refused';
  blocker := null; return next;

  -- PD-CONC-001 two workers claim the same task.
  -- The race is driven by scripts/phase_d/run_concurrency_probes.mjs, which issues two overlapping
  -- statements on two distinct backends against a temporary committed canary and then removes it.
  -- This branch reads what that harness recorded and refuses to invent a verdict when it has not run.
  select r.verdict, r.observed into v_c1_verdict, v_c1_observed
    from public.phase_d_concurrency_probe_result r
   where r.probe_id = 'C1-skip-locked-single-claimant'
   order by r.ran_at desc limit 1;
  defect_id:='PD-CONC-001'; category:='CONCURRENCY';
  if v_c1_verdict is null then
    status := 'NOT_RUN'; observed := null;
    blocker := 'the two-session harness has not run. node scripts/phase_d/run_concurrency_probes.mjs '
            || 'records C1-skip-locked-single-claimant; until it does there is no result to read, and '
            || 'a verdict invented here would be the fabrication this register exists to prevent.';
  else
    status := v_c1_verdict; observed := v_c1_observed; blocker := null;
  end if;
  return next;

  -- ---- FINANCE --------------------------------------------------------------------------------
  -- PD-FIN-003 refund without founder decision -> refused.
  --
  -- 26 AUG 2026: THE FIXTURE WAS WRONG, NOT THE GUARD. This injection named no transaction, and
  -- a00_refund_amount_is_the_fee_paid -- added the same day, on the founder's instruction that a
  -- refund figure "should be exactly equal to the amount of the 3% the customer paid" -- refuses a
  -- refund that names no payment with 23514 (refund_names_no_payment), BEFORE
  -- z00_refund_founder_decision_only is reached. The case therefore recorded "refused for another
  -- reason before the guard" and the builder counted it FAILED TO REFUSE, while the defect was in
  -- fact refused twice over. Accepting 23514 here would have been the trap: it would record the
  -- amount refusal as proof that the founder-identity arm fires, and that arm would never be tested
  -- again. So the injection now carries a real payment behind it -- a revealed transaction whose
  -- reveal_fee it returns exactly, past its refund window -- and the arm this case is ABOUT is the
  -- arm that refuses it. Both rows live in this subtransaction and go with it.
  begin
    insert into public.transactions (id, revealed_at, reveal_fee, fee_status, paid_by, payment_ref)
    values (gen_random_uuid(), now() - interval '60 days', 10.00, 'paid', 'customer', 'pd-fin-003')
    returning id into v_f3_txn;
    insert into public.refunds (transaction_id, customer_id, amount_fils, reason_code, status,
                                requested_by, requested_at, decided_by, decided_at)
    select v_f3_txn, null, round(t.reveal_fee * 100)::bigint, 'other', 'approved',
           'zz-pd-fin-003@example.invalid', now(), 'ceo', now()
      from public.transactions t where t.id = v_f3_txn;
    v_ok := false; v_msg := 'an approved refund by a non-founder was ACCEPTED';
  exception when sqlstate '42501' then
    v_ok := true; v_msg := 'refused 42501: approved by a role that is not an active founder identity';
  when others then
    v_ok := false; v_msg := 'refused for another reason before the guard: ' || left(SQLERRM,60);
  end;
  defect_id:='PD-FIN-003'; category:='FINANCE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-FIN-005 unknown monetary state silently accepted -> visible exception.
  begin
    update public.phase_d_fixture_stage set working_state = 'zz_not_a_rung'
     where object_id = 'payment_transaction';
    v_ok := false; v_msg := 'an undeclared payment state was ACCEPTED';
  exception when others then
    v_ok := position('pd_stage_payment_state_undeclared' in SQLERRM)>0;
    v_msg := 'refused: the state is not a rung of public.phase_d_payment_state';
  end;
  defect_id:='PD-FIN-005'; category:='FINANCE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-FIN-002 reveal before confirmed reconciliation -> refused.
  select count(*) into v_n from public.phase_d_payment_state where authorizes_reveal;
  defect_id:='PD-FIN-002'; category:='FINANCE';
  status := case when v_n=2 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('%s of 6 payment rungs authorise a reveal (payment_reconciled, reveal_authorized); '
                     'BR-020 names rung 5 as the founder-approved bar and no rung below it authorises', v_n);
  blocker := null; return next;

  -- ---- Ten injections that DO have a live refusal, each with a control -------------------------
  -- Recorded blockers for all ten said the subject needed section 8, a committed run or a path that
  -- is not built. Measured 24 Aug 2026: the refusal exists, it is nameable, and a control differing
  -- in exactly one respect behaves differently. Each branch injects, then reports what the machine
  -- did — and states its own boundary where it has one.
  declare
    v_ovl   text;   -- a real category overlay, read from the register rather than typed here
    v_state text;   -- the injected call's state
    v_ctl   text;   -- the control call's state
    v_code  text;   -- the refusal code the machine named
    v_p1    boolean; v_p2 boolean;
    v_qbad  uuid;    v_qgood uuid;
    v_task  bigint;
  begin
    select b.live_role_id into v_ovl from public.phase_c_overlay_binding b order by b.overlay_id limit 1;

    -- PD-FIN-001 executor also reconciles -> separation of duties.
    select rc.state, rc.refusal_code into v_state, v_code from public.fn_phase_d_rule_check('BR-031',
      jsonb_build_object('accountable_role_id','ceo','reviewer_role_id','ceo')) rc;
    select rc.state into v_ctl from public.fn_phase_d_rule_check('BR-031',
      jsonb_build_object('accountable_role_id','ceo','reviewer_role_id','ceo')) rc;
    v_ok := v_state = 'ENFORCED_FAIL' and v_ctl = 'ENFORCED_PASS';
    defect_id:='PD-FIN-001'; category:='FINANCE';
    status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('BR-031 at its registered point fn_kernel_reviewer_independent: one identity as executor and reconciler -> %s/%s; two identities -> %s. CHECK phase_c_refund_decision_ck carries it too but kernel_write_authority names no writer for that table.',
                       v_state, v_code, v_ctl);
    blocker := null; return next;
  -- PD-AUTH-005. THE RECORDED BLOCKER WAS WRONG ABOUT A ROUTINE THAT WAS ALWAYS HERE.
  -- It said closing this needs fn_phase_c_task_create, a KERNEL_INTERNAL_PRIMITIVE, and that a
  -- probe calling it is the bypass fn_kernel_retired_path_state exists to catch. public.
  -- fn_kernel_open_step IS "a kernel entry point that accepts an owner and routes to the primitive"
  -- -- the exact thing the blocker said had to be built. It takes owner_role_id FROM THE CALLER.
  declare
    v_a5_ovl text; v_a5_alias text; v_a5_fx jsonb; v_a5_dr jsonb; v_a5_run bigint;
    v_a5_step text; v_a5_owner text; v_a5_msg text := ''; v_a5_ok boolean := false;
    v_a5_t1 bigint; v_a5_t2 bigint; v_a5_r1 bigint; v_a5_r2 bigint; v_a5_c1 bigint; v_a5_c2 bigint;
    v_a5_A text; v_a5_B text; v_a5_C text; v_a5_G text;
  begin
    -- WRITES INSIDE A BLOCK THAT ALWAYS RAISES. fn_phase_d_injected_defect_report has callers other
    -- than the deliverable builder, and not all of them abort. A plpgsql exception block is a
    -- subtransaction: raising at the end of it discards every row this branch wrote, in every
    -- caller, without depending on anyone else's discipline. The findings come back in the message.
    begin
      select b.live_role_id into v_a5_ovl from public.phase_c_overlay_binding b order by b.overlay_id limit 1;
      select a.alias into v_a5_alias from public.org_role_alias a where a.role_id = v_a5_ovl limit 1;
      v_a5_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
        'label','pd-auth-005','execution_context','test','for_workflow','W04'));
      v_a5_dr := public.fn_phase_d_drive_workflow(jsonb_build_object(
        'workflow_id','W04','scenario', v_a5_fx, 'mode','happy','hold_at_first_open_step', true));
      v_a5_run := (v_a5_dr->>'run_id')::bigint;
      select s.step_id, s.accountable_role_id into v_a5_step, v_a5_owner
        from public.phase_b_workflow_step s
       where s.workflow_id='W04'
         and not exists (select 1 from public.phase_c_workflow_step_run r
                          where r.run_id=v_a5_run and r.step_id=s.step_id)
       order by s.step_no limit 1;

      select count(*) into v_a5_t1 from public.phase_c_task;
      select count(*) into v_a5_r1 from public.phase_c_workflow_step_run;
      select count(*) into v_a5_c1 from public.phase_c_trace;

      begin
        perform public.fn_kernel_open_step(jsonb_build_object('run_id',v_a5_run,'step_id',v_a5_step,
          'owner_role_id', v_a5_ovl, 'opened_because','PD-AUTH-005 overlay as accountable owner'));
        v_a5_A := 'ACCEPTED';
      exception when others then v_a5_A := 'REFUSED ' || SQLSTATE; end;
      begin
        perform public.fn_kernel_open_step(jsonb_build_object('run_id',v_a5_run,'step_id',v_a5_step,
          'owner_role_id', v_a5_alias, 'opened_because','PD-AUTH-005 overlay behind its alias'));
        v_a5_B := 'ACCEPTED';
      exception when others then v_a5_B := 'REFUSED ' || SQLSTATE; end;

      select count(*) into v_a5_t2 from public.phase_c_task;
      select count(*) into v_a5_r2 from public.phase_c_workflow_step_run;
      select count(*) into v_a5_c2 from public.phase_c_trace;

      begin
        perform public.fn_kernel_open_step(jsonb_build_object('run_id',v_a5_run,'step_id',v_a5_step,
          'owner_role_id', v_a5_owner, 'opened_because','PD-AUTH-005 control: the standing role'));
        v_a5_C := 'ACCEPTED';
      exception when others then v_a5_C := 'REFUSED ' || SQLSTATE; end;

      -- THE TABLE BOUNDARY IS ASSERTED SOMEWHERE ELSE, AND THIS IS WHY.
      -- a02_phase_c_step_run_owner_admissible can only be reached with an overlay through
      -- fn_kernel_write_guard's audited maintenance door, and a literal
      -- `update public.phase_c_workflow_step_run` inside THIS routine is precisely what
      -- fn_kernel_write_guard_state's routines_that_write_a_protected_table_with_no_authority
      -- exists to surface -- it took that board from 1 of 37 to 3 of 39. Registering this routine
      -- to quieten it would GRANT it authority over the table, which is the opposite of the point.
      -- The forced firing lives in scripts/checks/protected_table_guards_actually_fire.test.mjs,
      -- which is a check rather than a routine and so is not a writer any board can count.
      -- What this branch asserts is the LIVE path: fn_kernel_open_step refuses the overlay before
      -- a row exists, and the stable identity comes from the predicate both guards raise from.
      v_a5_G := coalesce((select refusal_code
                            from public.fn_phase_d_owner_admissibility(v_a5_ovl)), 'ADMISSIBLE');

      raise exception '%', 'PDA5' || chr(31) || v_a5_A || '|' || v_a5_B || '|' || v_a5_C || '|' || v_a5_G || '|' || (select refusal_code from public.fn_phase_d_owner_admissibility(v_a5_ovl)) || '|' || (select refusal_code from public.fn_phase_d_owner_admissibility(v_a5_alias)) || '|' || case when v_a5_t1 = v_a5_t2 and v_a5_r1 = v_a5_r2 and v_a5_c1 = v_a5_c2 then 'unchanged' else 'MOVED tasks '||(v_a5_t2-v_a5_t1)||' step runs '||(v_a5_r2-v_a5_r1)||' traces '||(v_a5_c2-v_a5_c1) end;
    exception when others then
      if position('PDA5' in SQLERRM) = 1 then v_a5_msg := split_part(SQLERRM, chr(31), 2);
      else v_a5_msg := 'BRANCH_ERROR ' || left(SQLERRM, 120); end if;
    end;

    v_a5_ok := split_part(v_a5_msg,'|',1) like 'REFUSED%'
           and split_part(v_a5_msg,'|',2) like 'REFUSED%'
           and split_part(v_a5_msg,'|',3) = 'ACCEPTED'
           and split_part(v_a5_msg,'|',4) = 'pd_overlay_cannot_own_task'
           and split_part(v_a5_msg,'|',5) = 'pd_overlay_cannot_own_task'
           and split_part(v_a5_msg,'|',6) = 'pd_overlay_cannot_own_task'
           -- and the standing role must still be ADMISSIBLE, or the predicate refuses everything
           and (select admissible from public.fn_phase_d_owner_admissibility(
                  (select accountable_role_id from public.phase_b_workflow_step
                    where step_id = 'W04-S02')))
           and split_part(split_part(v_a5_msg,'|',7),' ',1) like '%'
           and split_part(v_a5_msg,'|',7) = 'unchanged';
    defect_id:='PD-AUTH-005'; category:='AUTH';
    status := case when v_a5_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('overlay owner->%s alias->%s standing role->%s; owner-admissibility predicate %s; tasks, step runs and traces across both refusals: %s',
                       split_part(v_a5_msg,'|',1), split_part(v_a5_msg,'|',2),
                       split_part(v_a5_msg,'|',3), split_part(v_a5_msg,'|',4),
                       split_part(v_a5_msg,'|',7));
    blocker := null; return next;
  end;

  -- (the withdrawn note below is kept as the record of why this case was NOT_RUN until O01)
  -- PD-AUTH-005 — the earlier withdrawal, and this is why rather than a silent revert.
  -- The branch that closed it called public.fn_phase_c_task_create. public.kernel_write_authority
  -- says that routine may write public.phase_c_task; public.kernel_retired_path says it is a
  -- KERNEL_INTERNAL_PRIMITIVE, reachable only from fn_kernel_*. Both are true together — it is the
  -- authorised writer, called by the kernel — so a PROBE calling it is exactly the bypass
  -- fn_kernel_retired_path_state counts, and it took that board from 0 of 9 to 1 of 9.
  -- Making the board's exclusion list longer to admit this estate's own probe would be editing a
  -- kernel board to suit the code it audits. The refusal was real and was observed; the route to it
  -- was not one a probe may take.

    -- PD-DISP-005 category overlay attempts a dispatch.
    select rc.state, rc.refusal_code into v_state, v_code
      from public.fn_phase_d_rule_check('BR-048', jsonb_build_object('actor_role_id', v_ovl)) rc;
    select rc.state into v_ctl
      from public.fn_phase_d_rule_check('BR-048', jsonb_build_object('actor_role_id','customer_support')) rc;
    v_ok := v_state = 'ENFORCED_FAIL' and v_ctl = 'ENFORCED_PASS';
    defect_id:='PD-DISP-005'; category:='DISPATCH';
    status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('BR-048 (category overlays cannot dispatch): actor %s -> %s/%s; the overlay''s own invocation_role_id inquiry_router -> %s. The identity is resolved through fn_phase_c_resolve_actor and matched against phase_c_overlay_binding, not taken from the call.',
                       v_ovl, v_state, v_code, v_ctl);
    blocker := null; return next;
  -- PD-LEGAL-005. THE CANONICAL REVIEW SERVICE ALREADY REFUSES A SELF-REVIEW, AND THE TASK
  -- BOUNDARY REFUSES THE COLLISION BEFORE A TASK EXISTS. Both are driven here on a REAL
  -- review-required privacy artifact -- W08-S06, "Approve immutable supplier-safe package",
  -- frozen owner marketplace_content_privacy_reviewer, frozen reviewer
  -- compliance_and_privacy_officer -- and the alias arm uses privacy_officer, a registered
  -- legacy_role_id of the reviewer.
  declare
    v_l5_fx jsonb; v_l5_dr jsonb; v_l5_run bigint; v_l5_task bigint; v_l5_msg text := '';
    v_l5_ok boolean := false; v_l5_A text; v_l5_B text; v_l5_C text; v_l5_T text; v_l5_S text;
    v_l5_t1 bigint; v_l5_t2 bigint;
  begin
    -- WRITES INSIDE A BLOCK THAT ALWAYS RAISES. fn_phase_d_injected_defect_report has callers other
    -- than the deliverable builder, and not all of them abort. A plpgsql exception block is a
    -- subtransaction: raising at the end of it discards every row this branch wrote, in every
    -- caller, without depending on anyone else's discipline. The findings come back in the message.
    begin
      v_l5_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
        'label','pd-legal-005','execution_context','test','for_workflow','W08'));
      v_l5_dr := public.fn_phase_d_drive_workflow(jsonb_build_object(
        'workflow_id','W08','scenario', v_l5_fx, 'mode','happy','hold_at_first_open_step', true));
      v_l5_run := (v_l5_dr->>'run_id')::bigint;

      select count(*) into v_l5_t1 from public.phase_c_task;
      -- the task boundary: the declared reviewer presented as the step's own owner
      begin
        perform public.fn_kernel_open_step(jsonb_build_object('run_id',v_l5_run,'step_id','W08-S06',
          'owner_role_id','ceo',
          'opened_because','PD-LEGAL-005 creator is the declared reviewer'));
        v_l5_T := 'ACCEPTED';
      exception when others then
        v_l5_T := case when position('pd_creator_reviewer_collision' in SQLERRM) > 0
                       then 'pd_creator_reviewer_collision' else 'other:' || SQLSTATE end;
      end;
      -- the same collision reached through a legacy alias of the reviewer
      begin
        perform public.fn_kernel_open_step(jsonb_build_object('run_id',v_l5_run,'step_id','W08-S06',
          'owner_role_id','privacy_officer',
          'opened_because','PD-LEGAL-005 alias of the declared reviewer'));
        v_l5_S := 'ACCEPTED';
      exception when others then
        v_l5_S := case when position('pd_creator_reviewer_collision' in SQLERRM) > 0
                       then 'pd_creator_reviewer_collision' else 'other:' || SQLSTATE end;
      end;
      select count(*) into v_l5_t2 from public.phase_c_task;

      -- the canonical owner, so a task exists for the review service to be asked about
      perform public.fn_kernel_open_step(jsonb_build_object('run_id',v_l5_run,'step_id','W08-S06',
        'owner_role_id','marketplace_content_privacy_reviewer',
        'opened_because','PD-LEGAL-005 control: the frozen canonical owner'));
      select t.task_id into v_l5_task from public.phase_c_task t
       where t.run_id = v_l5_run and t.step_id = 'W08-S06' order by t.task_id desc limit 1;

      -- A: the reviewer resolves to the creator
      v_l5_A := coalesce((public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_l5_task, 'reviewer_role_id','marketplace_content_privacy_reviewer',
        'decision','approved','reason','PD-LEGAL-005 arm A')))->>'error', 'ACCEPTED');
      -- B: a legacy alias of the creator
      v_l5_B := coalesce((public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_l5_task, 'reviewer_role_id','moderation_specialist',
        'decision','approved','reason','PD-LEGAL-005 arm B')))->>'error', 'ACCEPTED');
      -- C: the genuinely independent authorised reviewer the frozen registry declares
      v_l5_C := coalesce((public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_l5_task, 'reviewer_role_id','ceo',
        'decision','approved','reason','PD-LEGAL-005 arm C')))->>'error', 'ACCEPTED');

      raise exception '%', 'PDL5' || chr(31) || v_l5_A || '|' || v_l5_B || '|' || v_l5_C || '|' || v_l5_T || '|' || v_l5_S || '|' || case when v_l5_t1 = v_l5_t2 then 'unchanged' else 'MOVED '||(v_l5_t2-v_l5_t1) end;
    exception when others then
      if position('PDL5' in SQLERRM) = 1 then v_l5_msg := split_part(SQLERRM, chr(31), 2);
      else v_l5_msg := 'BRANCH_ERROR ' || left(SQLERRM, 120); end if;
    end;

    -- BOTH refusal codes are accepted, and this is why rather than left as a loose predicate.
    -- fn_kernel_review_decide checks the DECLARED reviewer (frozen Phase B) before it checks
    -- independence, so a creator offering itself is refused as not_the_declared_reviewer -- the
    -- stronger of the two answers, because the registry names who reviews and the creator is not
    -- that role. reviewer_not_independent is what fires where no reviewer is declared. Either is a
    -- refusal of the same act; a case that demanded exactly one of them would be asserting the
    -- ORDER of two guards rather than the behaviour of the control.
    v_l5_ok := split_part(v_l5_msg,'|',1) in ('reviewer_not_independent','not_the_declared_reviewer')
           and split_part(v_l5_msg,'|',2) in ('reviewer_not_independent','not_the_declared_reviewer')
           and split_part(v_l5_msg,'|',3) = 'ACCEPTED'
           and split_part(v_l5_msg,'|',4) = 'pd_creator_reviewer_collision'
           and split_part(v_l5_msg,'|',5) = 'pd_creator_reviewer_collision'
           and split_part(v_l5_msg,'|',6) = 'unchanged'
           -- AND THE INDEPENDENCE DECISION ITSELF, ACROSS BOTH IDENTITY VOCABULARIES, so the case
           -- does not rest on a refusal that fired for the declared-reviewer reason.
           and not public.fn_kernel_reviewer_independent(
                     'marketplace_content_privacy_reviewer','marketplace_content_privacy_reviewer')
           and not public.fn_kernel_reviewer_independent(
                     'marketplace_content_privacy_reviewer','moderation_specialist')
           and not public.fn_kernel_reviewer_independent(
                     'ceo','privacy_officer')
           and public.fn_kernel_reviewer_independent(
                     'marketplace_content_privacy_reviewer','ceo');
    defect_id:='PD-LEGAL-005'; category:='LEGAL';
    status := case when v_l5_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('W08-S06 review service: creator->%s alias-of-creator->%s independent->%s; task boundary %s / alias %s; tasks across both refusals: %s; fn_kernel_reviewer_independent self=f alias=f cross-vocab=f independent=t',
                       split_part(v_l5_msg,'|',1), split_part(v_l5_msg,'|',2), split_part(v_l5_msg,'|',3),
                       split_part(v_l5_msg,'|',4), split_part(v_l5_msg,'|',5), split_part(v_l5_msg,'|',6));
    blocker := null; return next;
  end;

  -- (the withdrawn note below is kept as the record of why this case was NOT_RUN until O01)
  -- PD-LEGAL-005 — the earlier withdrawal, and this is why rather than a silent revert.
  -- The branch that closed it called public.fn_phase_c_task_create. public.kernel_write_authority
  -- says that routine may write public.phase_c_task; public.kernel_retired_path says it is a
  -- KERNEL_INTERNAL_PRIMITIVE, reachable only from fn_kernel_*. Both are true together — it is the
  -- authorised writer, called by the kernel — so a PROBE calling it is exactly the bypass
  -- fn_kernel_retired_path_state counts, and it took that board from 0 of 9 to 1 of 9.
  -- Making the board's exclusion list longer to admit this estate's own probe would be editing a
  -- kernel board to suit the code it audits. The refusal was real and was observed; the route to it
  -- was not one a probe may take.

    -- PD-DISP-003 an unapproved supplier-safe package reaches dispatch.
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_safe_package','business_key','zz-disp-003-approved','owner_ref','zz-disp-003',
      'created_by','defect_probe','state','approved','payload', jsonb_build_object('n',1)));
    select rc.state, rc.refusal_code into v_state, v_code from public.fn_phase_d_rule_check('BR-012',
      jsonb_build_object('safe_package_ref','zz-disp-003-unapproved',
                         'safe_package_approved_by','marketplace_content_privacy_reviewer')) rc;
    select rc.state into v_ctl from public.fn_phase_d_rule_check('BR-012',
      jsonb_build_object('safe_package_ref','zz-disp-003-approved',
                         'safe_package_approved_by','marketplace_content_privacy_reviewer')) rc;
    select g.passed into v_p1 from public.fn_phase_d_gate_evaluate('GATE-013', jsonb_build_object(
      'safe_package_ref','zz-disp-003-approved','safe_package_approved_by','marketplace_content_privacy_reviewer',
      'actor_role_id','marketplace_content_privacy_reviewer')) g;
    select g.passed into v_p2 from public.fn_phase_d_gate_evaluate('GATE-013', jsonb_build_object(
      'safe_package_ref','zz-disp-003-approved','safe_package_approved_by','ceo',
      'actor_role_id','marketplace_content_privacy_reviewer')) g;
    v_ok := v_state = 'ENFORCED_FAIL' and v_ctl = 'ENFORCED_PASS' and v_p1 is false and v_p2 is true;
    defect_id:='PD-DISP-003'; category:='DISPATCH';
    status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('BR-012: a package ref that resolves to no approved supplier_safe_package record -> %s/%s; the approved record written through fn_phase_d_object_write -> %s. GATE-013 on the same approved package: approver=author -> passed %s, independent approver -> passed %s.',
                       v_state, v_code, v_ctl, v_p1, v_p2);
    blocker := null; return next;

    -- PD-LEGAL-001 a certificate issued before terms acceptance.
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','customer_terms_acceptance','business_key','zz-legal-001-accepted','owner_ref','zz-legal-001',
      'created_by','defect_probe','state','accepted','payload', jsonb_build_object('n',1)));
    select rc.state, rc.refusal_code into v_state, v_code from public.fn_phase_d_rule_check('BR-026',
      jsonb_build_object('acceptance_ref','zz-legal-001-no-such-acceptance')) rc;
    select rc.state into v_ctl from public.fn_phase_d_rule_check('BR-026',
      jsonb_build_object('acceptance_ref','zz-legal-001-accepted')) rc;
    v_ok := v_state = 'ENFORCED_FAIL' and v_ctl = 'ENFORCED_PASS';
    defect_id:='PD-LEGAL-001'; category:='LEGAL';
    status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('BR-026: a certificate whose acceptance_ref resolves to no customer_terms_acceptance or supplier_terms_acceptance record -> %s/%s; the same call naming a real acceptance record -> %s. The ref is resolved, not merely required to be non-empty.',
                       v_state, v_code, v_ctl);
    blocker := null; return next;

    -- PD-PRIV-001 a supplier-facing payload carrying a customer identity.
    select rc.state, rc.refusal_code into v_state, v_code from public.fn_phase_d_rule_check('BR-011',
      jsonb_build_object('supplier_payload','RFQ 12 t rebar. Contact zz.customer@example.invalid 0501234567')) rc;
    select rc.state into v_ctl from public.fn_phase_d_rule_check('BR-011',
      jsonb_build_object('supplier_payload','RFQ 12 t rebar grade B500B, delivery Dubai, no identity')) rc;
    v_ok := v_state = 'ENFORCED_FAIL' and v_ctl = 'ENFORCED_PASS';
    defect_id:='PD-PRIV-001'; category:='PRIVACY';
    status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('BR-011: a supplier-safe payload carrying an email address and a UAE mobile -> %s/%s; the same payload with the identity removed -> %s. BOUNDED: the row-match arm searches public.customers, which holds few rows; the refusal here came from the shape arm.',
                       v_state, v_code, v_ctl);
    blocker := null; return next;

    -- PD-QUOTE-002 a quote missing a mandatory commercial field is published.
    insert into public.quotes (id, quote_amount, status, source)
      values (gen_random_uuid(), 1000, '', 'zz-defect-probe') returning id into v_qbad;
    insert into public.quotes (id, quote_amount, status, source)
      values (gen_random_uuid(), 1000, 'submitted', 'zz-defect-probe') returning id into v_qgood;
    select g.passed, g.refusal_code into v_p1, v_code
      from public.fn_phase_d_gate_evaluate('GATE-017', jsonb_build_object('quote_id', v_qbad::text)) g;
    select g.passed into v_p2
      from public.fn_phase_d_gate_evaluate('GATE-017', jsonb_build_object('quote_id', v_qgood::text)) g;
    begin
      insert into public.quotes (id, quote_amount, status, source)
        values (gen_random_uuid(), null, 'submitted', 'zz-defect-probe');
      v_ctl := 'a quote with no amount was ACCEPTED';
    exception when others then v_ctl := 'no amount refused by quotes.quote_amount NOT NULL'; end;
    v_ok := v_p1 is false and v_p2 is true and v_ctl like 'no amount refused%';
    defect_id:='PD-QUOTE-002'; category:='QUOTE';
    status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('GATE-017 against a real row of public.quotes: a quote with a blank status -> passed %s/%s; the same row complete -> passed %s; and %s.',
                       v_p1, v_code, v_p2, v_ctl);
    blocker := null; return next;

    -- PD-QUOTE-003 a technical claim with no evidence reaches the evaluation path.
    select rc.state, rc.refusal_code into v_state, v_code from public.fn_phase_d_rule_check('BR-027',
      jsonb_build_object('claim','grade B500B certified')) rc;
    select rc.state into v_ctl from public.fn_phase_d_rule_check('BR-027',
      jsonb_build_object('claim','grade B500B certified','evidence_refs', jsonb_build_array('doc:1#p3'))) rc;
    v_ok := v_state = 'ENFORCED_FAIL' and v_ctl = 'ENFORCED_PASS';
    defect_id:='PD-QUOTE-003'; category:='QUOTE';
    status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('BR-027 (evidence provenance, workflow_scope names W14): a technical claim with no evidence_refs -> %s/%s; the same claim naming one -> %s. BOUNDED: the predicate tests that the array is present and non-empty, not that each ref resolves.',
                       v_state, v_code, v_ctl);
    blocker := null; return next;

    -- PD-LEGAL-003 a non-refund subject enters the founder approval path.
    begin
      insert into public.founder_approval_request (command_id, action_class, subject_ref,
        prepared_by_role_id, amount_note, evidence, state)
      values (null,'policy_change','zz-legal-003','ceo','','{}'::jsonb,'pending');
      v_state := 'ACCEPTED';
    exception when others then v_state := 'REFUSED'; v_code := left(SQLERRM, 95); end;
    begin
      insert into public.founder_approval_request (command_id, action_class, subject_ref,
        prepared_by_role_id, amount_note, evidence, state)
      values (null,'refund_decision','zz-legal-003c','ceo','','{}'::jsonb,'pending');
      v_ctl := 'ACCEPTED';
    exception when others then v_ctl := 'REFUSED: ' || left(SQLERRM, 60); end;
    v_ok := v_state = 'REFUSED' and v_ctl = 'ACCEPTED';
    defect_id:='PD-LEGAL-003'; category:='LEGAL';
    status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('public.founder_approval_request is the founder approval path, not phase_c_refund_decision. action_class policy_change -> %s (%s); action_class refund_decision -> %s. z10_founder_approval_refund_only plus CHECK founder_approval_request_refund_only_ck.',
                       v_state, v_code, v_ctl);
    blocker := null; return next;
  end;


  -- PD-FIN-004. THE APPEND-ONLY CONTROL WAS ALWAYS REAL; WHAT WAS MISSING WAS A PRODUCER.
  -- public.kernel_write_authority held ZERO rows for phase_c_refund_decision, so no routine could
  -- ever create the row the immutability trigger exists to protect, and the table stayed at 0.
  -- O02 registered public.fn_kernel_refund_decision_record -- the canonical founder decision
  -- service, which resolves the founder through fn_phase_c_require_founder and writes decided_by
  -- from the VERIFIED identity, never from the call. Nothing here forges a founder: the subject is
  -- bound through the estate's own server door, in a subtransaction that always rolls back, on the
  -- founder's own written instruction for this session.
  declare
    v_f4_sub uuid; v_f4_req bigint; v_f4_d1 bigint; v_f4_res jsonb; v_f4_msg text := '';
    v_f4_ok boolean := false; v_f4_before jsonb; v_f4_row public.phase_c_refund_decision%rowtype;
    v_f4_N text; v_f4_U text; v_f4_D text; v_f4_S text; v_f4_E text; v_f4_R text; v_f4_W text;
  begin
    -- WRITES INSIDE A BLOCK THAT ALWAYS RAISES. fn_phase_d_injected_defect_report has callers other
    -- than the deliverable builder, and not all of them abort. A plpgsql exception block is a
    -- subtransaction: raising at the end of it discards every row this branch wrote, in every
    -- caller, without depending on anyone else's discipline. The findings come back in the message.
    begin
      begin
        perform public.fn_kernel_refund_decision_record(jsonb_build_object(
          'op','record','request_id',1,'decision','approved','reason','no founder on this call'));
        v_f4_N := 'ACCEPTED';
      exception when others then v_f4_N := 'REFUSED ' || SQLSTATE; end;

      select f.auth_user_id into v_f4_sub from public.phase_c_founder_identity f
       where f.active and f.kind='email' and f.auth_user_id is not null order by f.identity limit 1;
      -- PCCR-006, 25 AUG 2026. THE BIND IS NOW A QUESTION, NOT A STEP.
      -- fn_phase_c_founder_subject_bind refuses any connection that is not the PostgREST one that
      -- verified a bearer token. Unwrapped, this PERFORM aborted the subtransaction, the outer
      -- handler stored BRANCH_ERROR, v_f4_ok came out false, and PD-FIN-004 was reported
      -- NOT_REFUSED -- "a founder refund decision can be updated or deleted". That is the most
      -- alarming sentence this routine can emit, about a control it never reached and which had
      -- not moved. A blocked probe must not report on the guard it failed to ask.
      begin
        perform public.fn_phase_c_founder_subject_bind(v_f4_sub);
      exception when others then
        raise exception '%', 'PDF4' || chr(31) || 'BIND_REFUSED ' || SQLSTATE;
      end;
      insert into public.founder_approval_request(action_class, subject_ref, prepared_by_role_id)
      values ('refund_decision','pd-fin-004','ceo') returning request_id into v_f4_req;
      v_f4_res := public.fn_kernel_refund_decision_record(jsonb_build_object(
        'op','record','request_id',v_f4_req,'decision','approved','reason','PD-FIN-004'));
      v_f4_d1 := (v_f4_res->>'decision_id')::bigint;
      select * into v_f4_row from public.phase_c_refund_decision where decision_id = v_f4_d1;
      v_f4_before := to_jsonb(v_f4_row);

      -- THE EDIT AND THE DELETE ARE ASKED OF THE SERVICE, NOT WRITTEN BY HAND, and this is why.
      -- The raw UPDATE and DELETE reach a00_phase_c_refund_decision_immutable only through
      -- fn_kernel_write_guard's maintenance door, and a literal
      -- `update public.phase_c_refund_decision` inside this routine is exactly what
      -- fn_kernel_write_guard_state counts as an unauthorised writer. Those two arms are driven in
      -- scripts/checks/protected_table_guards_actually_fire.test.mjs, which asserts the frozen
      -- trigger's own 23514 refusals and that the original row did not move.
      -- Here the same two acts are asked of the canonical service, which is the door a caller
      -- actually has, and it refuses both with pd_refund_decision_append_only rather than teaching
      -- its callers that a raw edit is worth attempting.
      begin
        perform public.fn_kernel_refund_decision_record(jsonb_build_object(
          'op','record','decision_id',v_f4_d1,'edit',true,'request_id',v_f4_req,
          'decision','rejected','reason','PD-FIN-004 edit attempt'));
        v_f4_U := 'ACCEPTED';
      exception when others then
        v_f4_U := case when position('pd_refund_decision_append_only' in SQLERRM) > 0
                       then 'REFUSED pd_refund_decision_append_only' else 'other:' || SQLSTATE end;
      end;
      begin
        perform public.fn_kernel_refund_decision_record(jsonb_build_object(
          'op','record','decision_id',v_f4_d1,'delete',true,'request_id',v_f4_req,
          'decision','rejected','reason','PD-FIN-004 delete attempt'));
        v_f4_D := 'ACCEPTED';
      exception when others then
        v_f4_D := case when position('pd_refund_decision_append_only' in SQLERRM) > 0
                       then 'REFUSED pd_refund_decision_append_only' else 'other:' || SQLSTATE end;
      end;
      select * into v_f4_row from public.phase_c_refund_decision where decision_id = v_f4_d1;
      v_f4_R := case when to_jsonb(v_f4_row) = v_f4_before then 'UNCHANGED' else 'CHANGED' end;

      begin
        v_f4_res := public.fn_kernel_refund_decision_record(jsonb_build_object(
          'op','record','request_id',v_f4_req,'decision','rejected','reason','superseding',
          'supersedes_decision_id', v_f4_d1, 'supersession_reason','PD-FIN-004 supersession'));
        v_f4_S := 'ACCEPTED';
      exception when others then v_f4_S := 'REFUSED ' || SQLSTATE; end;
      begin
        perform public.fn_kernel_refund_decision_record(jsonb_build_object('op','execute','decision_id',v_f4_d1));
        v_f4_E := 'ACCEPTED';
      exception when others then
        v_f4_E := case when position('pd_refund_execution_without_founder_decision' in SQLERRM) > 0
                       then 'pd_refund_execution_without_founder_decision' else 'other:'||SQLSTATE end;
      end;
      begin
        insert into public.refunds(amount_fils, currency, status, requested_by, reason_code)
        values (1000,'AED','succeeded','customer_support','goodwill');
        v_f4_W := 'ACCEPTED';
      exception when others then
        v_f4_W := case when position('pd_refund_execution_without_founder_decision' in SQLERRM) > 0
                       then 'pd_refund_execution_without_founder_decision' else 'other:'||SQLSTATE end;
      end;

      raise exception '%', 'PDF4' || chr(31) || v_f4_N || '|' || v_f4_U || '|' || v_f4_D || '|' || v_f4_R || '|' || v_f4_S || '|' || v_f4_E || '|' || v_f4_W;
    exception when others then
      if position('PDF4' in SQLERRM) = 1 then v_f4_msg := split_part(SQLERRM, chr(31), 2);
      else v_f4_msg := 'BRANCH_ERROR ' || left(SQLERRM, 120); end if;
    end;

    v_f4_ok := split_part(v_f4_msg,'|',1) like 'REFUSED%'
           and split_part(v_f4_msg,'|',2) like 'REFUSED%'
           and split_part(v_f4_msg,'|',3) like 'REFUSED%'
           and split_part(v_f4_msg,'|',4) = 'UNCHANGED'
           and split_part(v_f4_msg,'|',5) = 'ACCEPTED'
           and split_part(v_f4_msg,'|',6) = 'pd_refund_execution_without_founder_decision'
           and split_part(v_f4_msg,'|',7) = 'pd_refund_execution_without_founder_decision';
    defect_id:='PD-FIN-004'; category:='FINANCE';
    if v_f4_msg like 'BIND_REFUSED%' then
      -- NOT_RUN WITH A NAMED BLOCKER, which is a state this estate already models and already
      -- checks: phase_d_documents_do_not_contradict_each_other asserts that every NOT_RUN names a
      -- specific blocker and that none is a placeholder. It is not a pass and it is not a failure;
      -- it is the honest third answer, and it keeps the control visible instead of green.
      status := 'NOT_RUN';
      observed := format('the probe could not create the founder decision this control protects: '
                      || 'fn_phase_c_founder_subject_bind answered %s. The no-founder arm was still '
                      || 'measured before the bind and came out %s.',
                         v_f4_msg, coalesce(nullif(v_f4_N,''), '(not reached)'));
      blocker := 'PCCR-006 closed the server bind door: fn_phase_c_founder_subject_bind refuses any '
              || 'connection that is not the PostgREST one which verified a founder bearer token '
              || '(pccr_founder_bind_untrusted_connection). Recording a founder refund decision -- '
              || 'the row a00_phase_c_refund_decision_immutable exists to protect -- therefore needs '
              || 'a founder JWT through PostgREST, which only the founder can produce. The append-only '
              || 'trigger itself is unchanged and its raw UPDATE/DELETE arms are still driven in '
              || 'scripts/checks/protected_table_guards_actually_fire.test.mjs.';
    else
      -- ONE `return next` FOR THIS CONTROL, AND IT IS BELOW THE if. The first cut of this splice
      -- put `return next; end if;` in the arm above and left the original emit underneath, so
      -- PD-FIN-004 came back TWICE -- once NOT_RUN and once NOT_REFUSED -- and the builder said
      -- "FINANCE produced 6 row(s); 5 are expected". `return next` does not leave a SETOF function.
      status := case when v_f4_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
      observed := format('no-founder->%s; UPDATE->%s DELETE->%s original %s; supersede->%s; execute superseded->%s; refund without decision->%s',
                         split_part(v_f4_msg,'|',1), split_part(v_f4_msg,'|',2), split_part(v_f4_msg,'|',3),
                         split_part(v_f4_msg,'|',4), split_part(v_f4_msg,'|',5), split_part(v_f4_msg,'|',6),
                         split_part(v_f4_msg,'|',7));
      blocker := null;
    end if;
    return next;
  end;

  -- ---- REVIEW ---------------------------------------------------------------------------------
  -- PD-REV-001 creator alias equals reviewer alias -> self-review refusal.
  v_ok := not public.fn_kernel_reviewer_independent('ceo','ceo');
  defect_id:='PD-REV-001'; category:='REVIEW';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := 'fn_kernel_reviewer_independent(x, x) is false: one identity cannot review its own output';
  blocker := null; return next;

  -- PD-REV-003 reviewer outside authority -> refused.
  v_ok := not public.fn_kernel_reviewer_independent('ceo', null);
  defect_id:='PD-REV-003'; category:='REVIEW';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := 'a null reviewer is not independent; BR-002 refuses the step rather than proceeding unreviewed';
  blocker := null; return next;

  -- PD-REV-002/004/005. THE OLD BLOCKERS SAID THESE NEEDED A COMMITTED RUN AND A COMMIT-TIME SEAL.
  -- Re-measured 24 Aug 2026 and false on both counts: fn_kernel_step_complete section 3g raises
  -- k3_reviewer_verdict_missing in the same statement, and fn_phase_c_trace_write stamps sealed_at
  -- in the same INSERT that sets status='sealed'. Neither waits for a commit.

  -- PD-REV-002 a required review step completed with no verdict -> refused.
  begin
    perform set_config('app.phase_d_hold_step','W04-S04', true);
    v_m3_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','zz-pd-rev-002','execution_context','test','for_workflow','W04'));
    select st.contributes_ref into v_m3_refkey from public.phase_d_fixture_stage st
     where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id='W04')
     limit 1;
    v_m3_boid := case when v_m3_refkey is not null and coalesce(v_m3_fx->'parent_refs'->>v_m3_refkey,'') <> ''
      then (select primary_object from public.phase_b_workflow where workflow_id='W04')
           || ':' || (v_m3_fx->'parent_refs'->>v_m3_refkey) else null end;
    v_m3_drive := public.fn_phase_d_drive_workflow(jsonb_build_object(
      'workflow_id','W04','label','zz-pd-rev-002','execution_context','production',
      'hold_at_step_id','W04-S04')
      || case when v_m3_boid is null then '{}'::jsonb
              else jsonb_build_object('business_object_id', v_m3_boid) end);
    v_m3_srid := nullif(v_m3_drive->>'held_step_run_id','')::bigint;
    v_m3_run  := nullif(v_m3_drive->>'run_id','')::bigint;
    perform set_config('app.phase_d_hold_step','', true);
    if v_m3_srid is null then
      v_ok := false;
      v_msg := 'no step run was held open at W04-S04; the drive stopped at '
            || coalesce(v_m3_drive->'stopped'->>'refused_with','(no reason given)');
    else
      select t.task_id into v_m3_task from public.phase_c_task t
       where t.run_id = v_m3_run and t.step_id = 'W04-S04' order by t.task_id limit 1;
      begin
        perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_m3_srid,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = v_m3_srid),
        'outcome','pass', 'idempotency_key', 'zz-pd-rev-002-inj:' || v_m3_srid,
        'inputs', jsonb_build_object('mode','no verdict recorded'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - acceptance record linked to the exact document version and identity'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','no verdict recorded')),
        'acceptance_criteria','a required review step may not pass unreviewed',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1));
        v_m3_ctl := 'COMPLETED_UNREVIEWED';
      exception when others then
        v_m3_ctl := case when position('k3_reviewer_verdict_missing' in SQLERRM) > 0
                         then 'k3_reviewer_verdict_missing/' || SQLSTATE
                         else SQLSTATE || ':' || left(SQLERRM, 60) end;
      end;
      perform public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_m3_task, 'reviewer_role_id','ceo',
        'decision','approved',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the declared independent reviewer approves'));
      begin
        perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_m3_srid,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = v_m3_srid),
        'outcome','pass', 'idempotency_key', 'zz-pd-rev-002-ctl:' || v_m3_srid,
        'inputs', jsonb_build_object('mode','approved verdict on record'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - acceptance record linked to the exact document version and identity'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','approved verdict on record')),
        'acceptance_criteria','the same step with a sealed approving verdict completes',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1));
        v_m3_state := 'COMPLETED';
      exception when others then
        v_m3_state := SQLSTATE || ':' || left(SQLERRM, 90);
      end;
      v_ok := v_m3_ctl = 'k3_reviewer_verdict_missing/23514' and v_m3_state = 'COMPLETED';
      v_msg := format(
        'W04 held open at W04-S04 (step run %s, task %s), one of the 28 of 257 frozen steps that '
     || 'declare an independent_reviewer_role_id - here compliance_and_privacy_officer. INJECTION: '
     || 'fn_kernel_step_complete outcome=pass with no verdict on the task at all -> %s. CONTROL, '
     || 'differing in exactly one respect - fn_kernel_review_decide first records an APPROVED '
     || 'verdict from that same declared reviewer - and the identical call then %s. Section 3g is '
     || 'the predicate: it looks for a TRACE-ROLE-ACTION trace on the task whose evidence_refs '
     || 'carry review_decision=approved from a reviewer that resolves to the declared one and is '
     || 'independent of the step owner. The refused arm left no partial completion; the whole '
     || 'transaction is aborted.',
        v_m3_srid, v_m3_task, v_m3_ctl, v_m3_state);
    end if;
  exception when others then
    perform set_config('app.phase_d_hold_step','', true);
    v_ok := false;
    v_msg := 'the W04 drive raised before the injection could be made: ' || left(SQLERRM, 220);
  end;
  defect_id:='PD-REV-002'; category:='REVIEW';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-REV-004 a REJECTED output pushed forward -> refused, and no successor is opened.
  begin
    perform set_config('app.phase_d_hold_step','W04-S04', true);
    v_m3_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','zz-pd-rev-004','execution_context','test','for_workflow','W04'));
    select st.contributes_ref into v_m3_refkey from public.phase_d_fixture_stage st
     where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id='W04')
     limit 1;
    v_m3_boid := case when v_m3_refkey is not null and coalesce(v_m3_fx->'parent_refs'->>v_m3_refkey,'') <> ''
      then (select primary_object from public.phase_b_workflow where workflow_id='W04')
           || ':' || (v_m3_fx->'parent_refs'->>v_m3_refkey) else null end;
    v_m3_drive := public.fn_phase_d_drive_workflow(jsonb_build_object(
      'workflow_id','W04','label','zz-pd-rev-004','execution_context','production',
      'hold_at_step_id','W04-S04')
      || case when v_m3_boid is null then '{}'::jsonb
              else jsonb_build_object('business_object_id', v_m3_boid) end);
    v_m3_srid := nullif(v_m3_drive->>'held_step_run_id','')::bigint;
    v_m3_run  := nullif(v_m3_drive->>'run_id','')::bigint;
    perform set_config('app.phase_d_hold_step','', true);
    if v_m3_srid is null then
      v_ok := false; v_m3_trace := null;
      v_msg := 'no step run was held open at W04-S04; the drive stopped at '
            || coalesce(v_m3_drive->'stopped'->>'refused_with','(no reason given)');
    else
      select t.task_id into v_m3_task from public.phase_c_task t
       where t.run_id = v_m3_run and t.step_id = 'W04-S04' order by t.task_id limit 1;
      select count(*) into v_m3_s0 from public.phase_c_workflow_step_run
       where run_id = v_m3_run and step_id = 'W04-S05';
      perform public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_m3_task, 'reviewer_role_id','ceo',
        'decision','rejected',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the declared reviewer rejects this output'));
      begin
        perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_m3_srid,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = v_m3_srid),
        'outcome','pass', 'idempotency_key', 'zz-pd-rev-004-inj:' || v_m3_srid,
        'inputs', jsonb_build_object('mode','rejected output pushed forward'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - acceptance record linked to the exact document version and identity'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','rejected output pushed forward')),
        'acceptance_criteria','a rejected output must not progress',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1));
        v_m3_ctl := 'PROGRESSED';
      exception when others then
        v_m3_ctl := case when position('k3_reviewer_verdict_missing' in SQLERRM) > 0
                         then 'k3_reviewer_verdict_missing/' || SQLSTATE
                         else SQLSTATE || ':' || left(SQLERRM, 60) end;
      end;
      select count(*) into v_m3_n from public.phase_c_workflow_step_run
       where run_id = v_m3_run and step_id = 'W04-S05';
      v_m3_a := public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_m3_task, 'reviewer_role_id','ceo',
        'decision','approved',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the same reviewer approves the same output'));
      v_m3_trace := nullif(v_m3_a->>'trace_id','')::bigint;   -- the subject PD-REV-005 tampers with
      begin
        perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_m3_srid,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = v_m3_srid),
        'outcome','pass', 'idempotency_key', 'zz-pd-rev-004-ctl:' || v_m3_srid,
        'inputs', jsonb_build_object('mode','approved output progresses'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - acceptance record linked to the exact document version and identity'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','approved output progresses')),
        'acceptance_criteria','an approved output progresses to its successor',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1));
        v_m3_state := 'PROGRESSED';
      exception when others then
        v_m3_state := SQLSTATE || ':' || left(SQLERRM, 90);
      end;
      select count(*) into v_m3_s1 from public.phase_c_workflow_step_run
       where run_id = v_m3_run and step_id = 'W04-S05';
      v_ok := v_m3_ctl = 'k3_reviewer_verdict_missing/23514'
          and v_m3_s0 = 0 and v_m3_n = 0
          and v_m3_state = 'PROGRESSED' and v_m3_s1 = 1;
      v_msg := format(
        'W04 held open at W04-S04 (step run %s, task %s). Its successor W04-S05 has the same owner, '
     || 'so the kernel opens it directly and no handoff has to be accepted first - which is what '
     || 'makes "was a successor opened" a readable number here. INJECTION: fn_kernel_review_decide '
     || 'records a REJECTED verdict from the declared reviewer, then fn_kernel_step_complete is '
     || 'called with outcome=pass -> %s, and public.phase_c_workflow_step_run rows for W04-S05 went '
     || '%s -> %s: no successor step run was opened. CONTROL, differing in exactly one respect - '
     || 'the same reviewer records APPROVED on the same task - and the identical call %s, W04-S05 '
     || 'step runs going to %s. MEASURED GAP, STATED AND NOT FIXED HERE: section 3g runs only when '
     || 'outcome=''pass'' AND the step declares an independent_reviewer_role_id. 28 of the 257 '
     || 'frozen steps declare one, so on the other 229 a recorded rejected verdict stops nothing: '
     || 'fn_kernel_review_decide writes the sealed trace and stamps phase_c_task.reviewer_role_id, '
     || 'and no predicate in the kernel reads review_decision=rejected. That is a measurement, not '
     || 'a repair.',
        v_m3_srid, v_m3_task, v_m3_ctl, v_m3_s0, v_m3_n, v_m3_state, v_m3_s1);
    end if;
  exception when others then
    perform set_config('app.phase_d_hold_step','', true);
    v_ok := false; v_m3_trace := null;
    v_msg := 'the W04 drive raised before the injection could be made: ' || left(SQLERRM, 220);
  end;
  defect_id:='PD-REV-004'; category:='REVIEW';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-REV-005 a verdict edited after sealing -> append-only refusal.
  -- The subject is the REAL sealed verdict fn_kernel_review_decide wrote for PD-REV-004. A trace
  -- this branch minted for itself would be an identity it had generated, which proves nothing.
  if v_m3_trace is null then
    v_ok := false; v_m3_ctl := 'NO_SUBJECT';
    v_msg := 'PD-REV-004 produced no sealed verdict trace, so there was no verdict to attempt to '
          || 'edit and nothing was injected. With no subject there is nothing to discriminate; this '
          || 'is not a pass.';
  else
    select (sealed_at is not null) into v_m3_ok2 from public.phase_c_trace where trace_id = v_m3_trace;
    begin
      update public.phase_c_trace
         set evidence_refs = evidence_refs || '[{"review_decision":"approved","tampered":true}]'::jsonb
       where trace_id = v_m3_trace;
      v_m3_ctl := 'ACCEPTED';
    exception when others then
      v_m3_ctl := case when position('append-only' in SQLERRM) > 0
                       then 'z10_phase_c_trace_append_only/' || SQLSTATE
                       else SQLSTATE || ':' || left(SQLERRM, 60) end;
    end;
    begin
      v_m3_sup := public.fn_phase_c_trace_write('TRACE-ROLE-ACTION', jsonb_build_object(
        'subject_kind','task', 'subject_ref', v_m3_task::text, 'task_id', v_m3_task,
        'actor_role_id','defect_probe', 'status','sealed',
        'evidence_refs', jsonb_build_array(jsonb_build_object(
          'note','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the superseding row the trigger names'))));
      update public.phase_c_trace set superseded_by = v_m3_sup where trace_id = v_m3_trace;
      v_m3_state := 'ACCEPTED';
    exception when others then
      v_m3_state := SQLSTATE || ':' || left(SQLERRM, 90);
    end;
    select count(*) into v_m3_n from public.phase_c_trace
     where trace_id = v_m3_trace and evidence_refs @> '[{"tampered":true}]'::jsonb;
    v_ok := v_m3_ctl = 'z10_phase_c_trace_append_only/23514'
        and v_m3_state = 'ACCEPTED' and v_m3_n = 0 and coalesce(v_m3_ok2, false);
    v_msg := format(
      'The subject is trace %s, the sealed TRACE-ROLE-ACTION verdict fn_kernel_review_decide wrote '
   || 'for PD-REV-004. sealed_at is already not null on it: %s - fn_phase_c_trace_write stamps '
   || 'sealed_at in the same INSERT that sets status=''sealed'', so the seal does not wait for a '
   || 'commit and the old blocker was wrong about that. INJECTION: an UPDATE of its evidence_refs '
   || 'adding a second approving decision -> %s. CONTROL, differing in exactly one respect - the '
   || 'same UPDATE on the same sealed row changing ONLY superseded_by from null, pointing at a '
   || 'superseding sealed trace written through the same door -> %s. Rows on phase_c_trace carrying '
   || 'the tampered evidence afterwards: %s.',
      v_m3_trace, coalesce(v_m3_ok2::text,'(unknown)'), v_m3_ctl, v_m3_state, v_m3_n);
  end if;
  defect_id:='PD-REV-005'; category:='REVIEW';
  status := case when v_ok then 'REFUSED_AS_REQUIRED'
                 when v_m3_ctl = 'NO_SUBJECT' then 'NOT_DISCRIMINATED'
                 else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- ---- OUTBOX (the D29 adapter is the machine under test) --------------------------------------
  -- PD-OUTBOX-001 consumer returns null -> delivery failure, attempt recorded.
  v_key := 'zz-out-001-' || md5('null');
  v_b := public.fn_phase_d_external_deliver(jsonb_build_object(
    'step_id','W13-S02','idempotency_key',v_key,'mock_case','null_result',
    'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
  select count(*) into v_n from public.phase_d_external_attempt where idempotency_key=v_key;
  defect_id:='PD-OUTBOX-001'; category:='OUTBOX';
  status := case when coalesce((v_b->>'delivered')::boolean,true)=false and v_n=1
                 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('null result: delivered=%s, reconciliation=%s, attempts recorded=%s',
                     v_b->>'delivered', v_b->>'reconciliation_state', v_n);
  blocker := null; return next;

  -- PD-OUTBOX-002 retryable failure then success -> first failure preserved.
  v_key := 'zz-out-002-' || md5('retry');
  perform public.fn_phase_d_external_deliver(jsonb_build_object(
    'step_id','W13-S03','idempotency_key',v_key,'mock_case','retryable_failure',
    'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
  v_b := public.fn_phase_d_external_deliver(jsonb_build_object(
    'step_id','W13-S03','idempotency_key',v_key,'mock_case','success',
    'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
  select count(*) into v_n from public.phase_d_external_attempt
   where idempotency_key=v_key and provider_outcome='retryable_failure';
  defect_id:='PD-OUTBOX-002'; category:='OUTBOX';
  status := case when coalesce((v_b->>'delivered')::boolean,false) and v_n=1
                 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('attempt 1 retryable preserved (%s row), attempt 2 delivered=%s', v_n, v_b->>'delivered');
  blocker := null; return next;

  -- PD-OUTBOX-003 terminal failure -> dead_letter, no business success.
  v_key := 'zz-out-003-' || md5('term');
  v_b := public.fn_phase_d_external_deliver(jsonb_build_object(
    'step_id','W13-S04','idempotency_key',v_key,'mock_case','terminal_failure',
    'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
  defect_id:='PD-OUTBOX-003'; category:='OUTBOX';
  status := case when coalesce((v_b->>'dead_lettered')::boolean,false)
                  and coalesce((v_b->>'delivered')::boolean,true)=false
                 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('terminal: retry_class=%s dead_lettered=%s delivered=%s',
                     v_b->>'retry_class', v_b->>'dead_lettered', v_b->>'delivered');
  blocker := null; return next;

  -- PD-OUTBOX-005 cancelled subject pending delivery -> non-deliverable.
  v_key := 'zz-out-005-' || md5('cx');
  perform public.fn_phase_d_external_deliver(jsonb_build_object(
    'step_id','W13-S05','idempotency_key',v_key,'mock_case','cancellation',
    'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
  begin
    perform public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W13-S05','idempotency_key',v_key,'mock_case','success',
      'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
    v_ok := false; v_msg := 'a cancelled subject was delivered';
  exception when others then
    v_ok := position('pd_external_cancelled' in SQLERRM)>0; v_msg := 'refused: pd_external_cancelled';
  end;
  defect_id:='PD-OUTBOX-005'; category:='OUTBOX';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-OUTBOX-004 consumer re-emits the same event -> self-loop.
  -- THE OLD BLOCKER SAID NO CONSUMER RUNS UNDER THE HOLD. Re-measured 24 Aug 2026: the canonical
  -- consumer public.fn_kernel_event_consume(outbox_id) runs inside the CALLER'S transaction and
  -- projects only -- fn_kernel_step_complete is the single authoritative progression path, so a
  -- consumer that created work would be a second creator racing the first. The live cron
  -- phase_c_outbox_deliver_1min, which does deliver externally, never sees a row in a transaction
  -- that is aborted. So the consumption CAN be driven here, and the self-loop is measured rather
  -- than inferred from two registry columns being equal.
  --
  -- THE INJECTION IS A SECOND CONSUMPTION OF THE SAME ROW. If consuming re-emits, the second call
  -- adds outbox rows; if the projection holds, both calls add none. Consuming twice also answers
  -- the idempotency half: a replayed delivery must not produce a second effect.
  begin
    select coalesce(max(outbox_id),0) into v_c4_ob0 from public.phase_c_event_outbox;
    v_c4_emit := public.fn_kernel_outbox_emit(jsonb_build_object(
      'event_id', 'EV-W01-STARTED', 'workflow_id','W01',
      'producer','system.workflow_engine',
      'accountable_role_id','ceo',
      'correlation_id', gen_random_uuid(), 'causation_id', gen_random_uuid(),
      'source_id','pd-outbox-004-probe',
      'dedupe_value','zz-pd-outbox-004-' || gen_random_uuid()::text,
      'payload', jsonb_build_object('fact','PHASE_D_FIXTURE_DO_NOT_PUBLISH outbox-004 probe')));
    select o.outbox_id into v_c4_row from public.phase_c_event_outbox o
     where o.outbox_id > v_c4_ob0 order by o.outbox_id limit 1;
    if v_c4_row is null then
      status := 'NOT_DISCRIMINATED';
      observed := 'fn_kernel_outbox_emit wrote no row, so there was nothing to consume twice';
    else
      select count(*) into v_c4_n0 from public.phase_c_event_outbox;
      perform 1 from public.fn_kernel_event_consume(v_c4_row);
      select count(*) into v_c4_n1 from public.phase_c_event_outbox;
      perform 1 from public.fn_kernel_event_consume(v_c4_row);
      select count(*) into v_c4_n2 from public.phase_c_event_outbox;
      v_ok := (v_c4_n1 - v_c4_n0) = 0 and (v_c4_n2 - v_c4_n1) = 0;
      status := case when v_ok then 'IDEMPOTENT_NO_DUPLICATE' else 'NOT_REFUSED' end;
      observed := format('outbox row %s consumed twice by the canonical consumer inside this '
                      || 'transaction: first consumption added %s outbox row(s), second added %s. '
                      || 'A consumer that re-emitted would have added one each time.',
                      v_c4_row, v_c4_n1 - v_c4_n0, v_c4_n2 - v_c4_n1);
    end if;
  exception when others then
    status := 'NOT_DISCRIMINATED';
    observed := 'the consume probe raised ' || SQLSTATE || ': ' || left(SQLERRM, 200);
  end;
  defect_id:='PD-OUTBOX-004'; category:='OUTBOX'; blocker := null;
  return next;

  -- ---- NOTIFY ---------------------------------------------------------------------------------
  -- PD-NOTIFY-001 external send attempted in Phase D -> provider-disabled refusal.
  begin
    perform public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W13-S06','idempotency_key','zz-notify-001','mock_case','success','provider_mode','live',
      'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
    v_ok := false; v_msg := 'a LIVE provider mode was accepted';
  exception when others then
    v_ok := position('pd_external_live_mode_refused' in SQLERRM)>0;
    v_msg := 'refused: pd_external_live_mode_refused — this adapter has no live mode';
  end;
  defect_id:='PD-NOTIFY-001'; category:='NOTIFY';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-NOTIFY-002 opted-out recipient queued -> suppressed.
  v_key := 'zz-notify-002-' || md5('supp');
  v_b := public.fn_phase_d_external_deliver(jsonb_build_object(
    'step_id','W13-S07','idempotency_key',v_key,'mock_case','suppression',
    'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
  defect_id:='PD-NOTIFY-002'; category:='NOTIFY';
  status := case when (v_b->>'reconciliation_state')='SUPPRESSED'
                  and coalesce((v_b->>'delivered')::boolean,true)=false
                 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('suppressed: delivered=%s reconciliation=%s', v_b->>'delivered', v_b->>'reconciliation_state');
  blocker := null; return next;

  -- PD-NOTIFY-003 duplicate message from retry -> one send ledger row.
  v_key := 'zz-notify-003-' || md5('dup');
  perform public.fn_phase_d_external_deliver(jsonb_build_object(
    'step_id','W13-S01','idempotency_key',v_key,'mock_case','success',
    'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
  perform public.fn_phase_d_external_deliver(jsonb_build_object(
    'step_id','W13-S01','idempotency_key',v_key,'mock_case','success',
    'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
  select count(*) into v_n from public.phase_d_external_attempt where idempotency_key=v_key and delivered;
  defect_id:='PD-NOTIFY-003'; category:='NOTIFY';
  status := case when v_n=1 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('two identical sends produced %s delivered row(s)', v_n);
  blocker := null; return next;

  -- PD-NOTIFY-004 success claimed on a null provider result -> failure.
  v_key := 'zz-notify-004-' || md5('nullclaim');
  v_b := public.fn_phase_d_external_deliver(jsonb_build_object(
    'step_id','W13-S02','idempotency_key',v_key,'mock_case','null_result',
    'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
  defect_id:='PD-NOTIFY-004'; category:='NOTIFY';
  status := case when coalesce((v_b->>'ok')::boolean,true)=false
                  and coalesce((v_b->>'delivered')::boolean,true)=false
                 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := 'a null provider result returns ok=false and delivered=false — it is never a success';
  blocker := null; return next;

  -- PD-NOTIFY-005 supplier receives raw customer identity -> approval/send refused.
  -- THE BLOCKER WAS WRONG AND THE DOOR WAS OPEN. It said this needs a rendered body and a PII
  -- detector in the edge functions. Measured 24 Aug 2026: fn_phase_d_external_deliver('W13-S02',
  -- ...) with an approved payload whose body read "contact Ahmad at zz.cust@example.invalid /
  -- 0501234567" returned ok=true, delivered=true and recorded attempt 25981. BR-011 refuses that
  -- exact string -- on SHAPE as well as on a row match, so it does not need public.customers to
  -- hold rows -- and the send path had simply never asked it. M05 makes the send path ask
  -- fn_phase_d_rule_applies and then fn_phase_d_rule_check, and this is the injection against it.
  begin
    v_pay := public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W13-S02','idempotency_key','zz-notify005-dirty','mock_case','success',
      'approved_payload_ref','zz-approved-notify005',
      'approved_payload', jsonb_build_object('body',
        'contact Ahmad at zz-notify005@example.invalid / 0501234567 for the site visit')));
    v_ok := false;
    v_msg := 'the send path delivered a payload carrying a customer identity: ' || coalesce(v_pay->>'delivered','?');
  exception when others then
    v_ok := position('br011_identity_before_reveal' in SQLERRM) > 0;
    v_msg := 'a supplier-facing body carrying an e-mail and a dialable number was refused at the '
          || 'send path: br011_identity_before_reveal. ';
  end;
  -- CONTROL. The SAME call, the same step, the same idempotency shape; the one thing that differs
  -- is that the body carries no identity.
  begin
    v_pay := public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W13-S02','idempotency_key','zz-notify005-clean','mock_case','success',
      'approved_payload_ref','zz-approved-notify005',
      'approved_payload', jsonb_build_object('body','the supplier-safe brief carries no identity')));
    v_ok := coalesce(v_ok,false) and coalesce((v_pay->>'delivered')::boolean,false);
    v_msg := v_msg || 'CONTROL, identity removed and nothing else: delivered=' || coalesce(v_pay->>'delivered','?') || '.';
  exception when others then
    v_ok := false; v_msg := v_msg || 'CONTROL was refused too: ' || left(SQLERRM,80);
  end;
  defect_id:='PD-NOTIFY-005'; category:='NOTIFY';
  status := case when coalesce(v_ok,false) then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null;
  return next;

  -- ---- PROVIDER -------------------------------------------------------------------------------
  -- PD-PROV-005 provider reports success with no request ID -> failure.
  begin
    insert into public.phase_d_external_attempt
      (step_id, idempotency_key, attempt_no, provider_mode, approved_payload_ref, approved_payload_sha256,
       provider_request_id, provider_result_id, provider_outcome, retry_class, delivered)
    values ('W13-S01','zz-prov-005',1,'mock','zz','zz','req_zz', null, 'success','NOT_APPLICABLE', true);
    v_ok := false; v_msg := 'a DELIVERED attempt with no result id was accepted';
  exception when others then
    v_ok := true; v_msg := 'refused by phase_d_external_attempt_delivered_has_result: delivered requires a result id';
  end;
  defect_id:='PD-PROV-005'; category:='PROVIDER';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-PROV-001 OpenRouter request in zero-cost mode -> network denied.
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in ('fn_phase_d_external_deliver','fn_phase_d_run_external_cases',
                                              'fn_phase_d_object_write','fn_phase_d_drive_workflow')
     -- READING the queue is the D17 GUARD; POSTING to it is a request. The first draft matched
     -- net.http_ and counted fn_phase_d_object_write, which references net.http_request_queue
     -- precisely in order to REFUSE one. The control refused the file rather than scoring it.
     -- MATCH A CALL, NOT A MENTION. Two drafts of this probe were wrong and both are worth keeping
     -- in the record. The first matched net.http_ and counted fn_phase_d_object_write, which names
     -- net.http_request_queue in order to REFUSE a request. The second narrowed to net.http_post and
     -- STILL counted it, because the D17 refusal's own hint text reads "A trigger on this relation
     -- calls net.http_post" — a keyword scanner matching a sentence ABOUT the thing it forbids.
     -- Quoted literals are stripped before judging, exactly as qd_guard does for the same reason:
     -- check the skeleton, not the payload.
     and regexp_replace(p.prosrc, '''(''''|[^''])*''', '''''', 'g') ~* 'openrouter|net[.]http_(post|get)[[:space:]]*[(]';
  defect_id:='PD-PROV-001'; category:='PROVIDER';
  status := case when v_n=0 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('%s Phase D routine(s) make an openrouter or net.http_post/get call; the D17 guard additionally '
                     'refuses any Phase D write that leaves a request in net.http_request_queue', v_n);
  blocker := null; return next;

  -- PD-PROV-004 direct provider client bypass -> repo/network scan.
  defect_id:='PD-PROV-004'; category:='PROVIDER'; status:='NOT_RUN'; observed:=null;
  blocker := 'a repository scan for a direct provider client lives in the CI credential test over '
          || 'supabase/functions, not in the database. Executing it as an INJECTION means adding a bypass '
          || 'to an edge function and observing CI refuse it, which needs the section 8 deploy path.';
  return next;

  -- PD-PROV-002/003 gate read failure and malformed route state.
  begin
    perform public.fn_phase_d_gate_evaluate('GATE-010', jsonb_build_object('route_state',''));
    select count(*) into v_n from public.fn_phase_d_gate_evaluate('GATE-010', jsonb_build_object('route_state','')) where ok;
    v_ok := (v_n = 0);
    v_msg := 'an empty route_state does not pass GATE-010; the gate denies rather than falling back';
  exception when others then v_ok := true; v_msg := 'gate raised on malformed evidence: ' || left(SQLERRM,60); end;
  defect_id:='PD-PROV-003'; category:='PROVIDER';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-PROV-002 a gate READ failure must not look like a gate refusal.
  -- THE OLD BLOCKER SAID THE DISTINCTION "IS NOT REPRESENTABLE". It was not representable because
  -- it had not been built: fn_phase_d_gate_evaluate carried zero exception handlers, so a read
  -- error propagated and aborted the caller instead of becoming a verdict. N06 built it. A defect
  -- catalogue entry saying a control cannot be tested because the control does not exist is a
  -- product gap wearing an exemption, and this one was.
  --
  -- THREE ARMS ON ONE GATE, so the refusal is about the fault and not about the gate refusing
  -- everything: the gate reads and passes; the gate's read is made to fail; and a DIFFERENT gate
  -- evaluated with the fault still armed still answers normally, which is what proves the fault is
  -- scoped rather than global.
  begin
    perform set_config('app.phase_d_gate_read_fault', '', true);
    select g.state, g.refusal_code into v_p2_state, v_p2_code
      from public.fn_phase_d_gate_evaluate('GATE-001', jsonb_build_object('step_id','W01-S01')) g;

    perform set_config('app.phase_d_gate_read_fault', 'GATE-001', true);
    select g.state, g.passed, g.refusal_code, g.evidence_absent
      into v_p2_fstate, v_p2_fpassed, v_p2_fcode, v_p2_fabsent
      from public.fn_phase_d_gate_evaluate('GATE-001', jsonb_build_object('step_id','W01-S01')) g;

    select g.state into v_p2_other
      from public.fn_phase_d_gate_evaluate('GATE-002',
             jsonb_build_object('actor_role_id','ceo')) g;
    perform set_config('app.phase_d_gate_read_fault', '', true);

    v_ok := v_p2_state = 'PASSED'
        and v_p2_fstate = 'BLOCKED' and v_p2_fpassed is not true
        and v_p2_fcode = 'gate_read_failed' and v_p2_fabsent is true
        and v_p2_other = 'PASSED';
    v_msg := format('read-and-passed: %s/%s | read FAILED: %s passed=%s code=%s evidence_absent=%s '
                 || '| a different gate with the fault still armed: %s. A gate that could not read '
                 || 'now fails closed under its own refusal code instead of answering like one that '
                 || 'read and refused.',
                 v_p2_state, coalesce(v_p2_code,'-'),
                 v_p2_fstate, coalesce(v_p2_fpassed::text,'-'), coalesce(v_p2_fcode,'-'),
                 coalesce(v_p2_fabsent::text,'-'), coalesce(v_p2_other,'-'));
  exception when others then
    perform set_config('app.phase_d_gate_read_fault', '', true);
    v_ok := false;
    v_msg := 'the gate read-fault probe raised instead of returning a verdict: '
          || SQLSTATE || ' ' || left(SQLERRM, 160)
          || ' — a read error that still propagates is the defect itself.';
  end;
  defect_id:='PD-PROV-002'; category:='PROVIDER';
  status := case when v_ok then 'FAIL_CLOSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- ---- STATE ----------------------------------------------------------------------------------
  -- PD-STATE-001 step completed from an invalid state.
  begin
    perform public.fn_phase_d_effect_produce(jsonb_build_object(
      'step_run_id', -1, 'idempotency_key','zz-state-001','actor_role_id','defect_probe',
      'payload', jsonb_build_object('x',1)));
    v_ok := false; v_msg := 'a nonexistent step run was accepted';
  exception when others then
    v_ok := position('pd_step_state_invalid' in SQLERRM)>0;
    v_msg := 'refused: pd_step_state_invalid — no such step run';
  end;
  defect_id:='PD-STATE-001'; category:='STATE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-STATE-005 failure outcome interpreted as a step id -> no invented step.
  select count(*) into v_n from public.fn_phase_d_step_cases('NOT-A-STEP') where passed;
  defect_id:='PD-STATE-005'; category:='STATE';
  status := case when v_n=0 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := 'fn_phase_d_step_cases on an unknown step returns passed=false with step_unknown; no step is invented';
  blocker := null; return next;

  -- PD-STATE-002/003. THE OLD BLOCKERS SAID BOTH NEEDED A COMMITTED RUN. Re-measured 24 Aug 2026
  -- and false: k3_closure_blocked is raised by fn_kernel_step_complete in the same statement, and
  -- closed_at is written in the same statement too, so both are readable before any commit.

  -- PD-STATE-002 a workflow closed with a mandatory blocker open -> a stable refusal code.
  -- ONE drive carries both arms. The injection runs inside its own subtransaction, so the refusal
  -- unwinds every row it staged and the control then starts from the state the drive left.
  begin
    perform set_config('app.phase_d_hold_step','W04-S06', true);
    v_m3_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','zz-pd-state-002','execution_context','test','for_workflow','W04'));
    select st.contributes_ref into v_m3_refkey from public.phase_d_fixture_stage st
     where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id='W04')
     limit 1;
    v_m3_boid := case when v_m3_refkey is not null and coalesce(v_m3_fx->'parent_refs'->>v_m3_refkey,'') <> ''
      then (select primary_object from public.phase_b_workflow where workflow_id='W04')
           || ':' || (v_m3_fx->'parent_refs'->>v_m3_refkey) else null end;
    v_m3_drive := public.fn_phase_d_drive_workflow(jsonb_build_object(
      'workflow_id','W04','label','zz-pd-state-002','execution_context','production',
      'hold_at_step_id','W04-S06')
      || case when v_m3_boid is null then '{}'::jsonb
              else jsonb_build_object('business_object_id', v_m3_boid) end);
    v_m3_srid := nullif(v_m3_drive->>'held_step_run_id','')::bigint;
    v_m3_run  := nullif(v_m3_drive->>'run_id','')::bigint;
    perform set_config('app.phase_d_hold_step','', true);
    if v_m3_srid is null then
      v_ok := false; v_m3_task := null;
      v_msg := 'no step run was held open at W04-S06; the drive stopped at '
            || coalesce(v_m3_drive->'stopped'->>'refused_with','(no reason given)');
    else
      perform set_config('app.phase_d_hold_step','W04-S07', true);
      select count(*) into v_m3_s0 from public.phase_c_workflow_step_run where run_id = v_m3_run;
      begin
        v_m3_a := public.fn_kernel_open_step(jsonb_build_object(
          'run_id', v_m3_run, 'step_id','W04-S07', 'owner_role_id','customer_support',
          'opened_because','PHASE_D_FIXTURE_DO_NOT_PUBLISH - closure attempted with W04-S06 open'));
        select t.task_id into v_m3_task from public.phase_c_task t
         where t.run_id = v_m3_run and t.step_id = 'W04-S07' order by t.task_id limit 1;
        perform public.fn_kernel_review_decide(jsonb_build_object(
          'task_id', v_m3_task, 'reviewer_role_id','customer_support','decision','approved',
          'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the closure step''s declared reviewer approves'));
        perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', (v_m3_a->>'step_run_id')::bigint,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = (v_m3_a->>'step_run_id')::bigint),
        'outcome','pass', 'idempotency_key', 'zz-pd-state-002-inj:' || v_m3_run,
        'inputs', jsonb_build_object('mode','closure with a mandatory step still open'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - closed onboarding record'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','closure with a mandatory step still open')),
        'acceptance_criteria','a run may not close over an unexecuted mandatory step',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1));
        v_m3_ctl := 'CLOSED';
      exception when others then
        v_m3_ctl := case when position('k3_closure_blocked' in SQLERRM) > 0
                         then 'k3_closure_blocked/' || SQLSTATE
                              || case when position('mandatory_steps_never_executed' in SQLERRM) > 0
                                      then ' listing mandatory_steps_never_executed'
                                      else ' WITHOUT naming mandatory_steps_never_executed' end
                         else SQLSTATE || ':' || left(SQLERRM, 60) end;
      end;
      select count(*) into v_m3_s1 from public.phase_c_workflow_step_run where run_id = v_m3_run;
      select count(*) into v_m3_p1 from public.phase_c_workflow_run
       where run_id = v_m3_run and closed_at is not null;
      -- CONTROL: the one thing that differs is that the mandatory step is executed first.
      perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_m3_srid,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = v_m3_srid),
        'outcome','pass', 'idempotency_key', 'zz-pd-state-002-ctl6:' || v_m3_run,
        'inputs', jsonb_build_object('mode','the last mandatory step is executed'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - onboarding completion and inquiry-start handoff'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','the last mandatory step is executed')),
        'acceptance_criteria','every earlier mandatory step reaches a terminal state',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1));
      select sr.step_run_id into v_m3_sup from public.phase_c_workflow_step_run sr
       where sr.run_id = v_m3_run and sr.step_id = 'W04-S07' order by sr.step_run_id limit 1;
      select t.task_id into v_m3_task from public.phase_c_task t
       where t.run_id = v_m3_run and t.step_id = 'W04-S07' order by t.task_id limit 1;
      perform public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_m3_task, 'reviewer_role_id','customer_support','decision','approved',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the closure step''s declared reviewer approves'));
      begin
        perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_m3_sup,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = v_m3_sup),
        'outcome','pass', 'idempotency_key', 'zz-pd-state-002-ctl7:' || v_m3_run,
        'inputs', jsonb_build_object('mode','closure with every mandatory step executed'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - closed onboarding record'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','closure with every mandatory step executed')),
        'acceptance_criteria','the run closes',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1));
        v_m3_state := 'CLOSED';
      exception when others then
        v_m3_state := SQLSTATE || ':' || left(SQLERRM, 90);
      end;
      select count(*) into v_m3_p2 from public.phase_c_workflow_run
       where run_id = v_m3_run and closed_at is not null;
      select state into v_m3_def from public.phase_c_workflow_run where run_id = v_m3_run;
      v_ok := v_m3_ctl like 'k3_closure_blocked/23514 listing mandatory_steps%'
          and v_m3_p1 = 0 and v_m3_s0 = v_m3_s1
          and v_m3_state = 'CLOSED' and v_m3_p2 = 1 and v_m3_def = 'completed';
      v_msg := format(
        'W04 driven to W04-S06 and held there, so W04-S01..S05 are completed and W04-S06 - a '
     || 'mandatory step of this workflow - has never reached a terminal state. INJECTION: the '
     || 'closure step W04-S07 is opened through the kernel''s own fn_kernel_open_step, its declared '
     || 'reviewer approves, and fn_kernel_step_complete is called with outcome=pass -> %s. The run''s '
     || 'closed_at rows: %s; step runs on the run went %s -> %s, so the refusal left nothing behind. '
     || 'CONTROL, differing in exactly one respect - W04-S06 is completed through '
     || 'fn_kernel_step_complete first, so no mandatory step is open - and the closure step then %s, '
     || 'the run reaching state %L with closed_at set on %s row. The closure step run in the control '
     || 'was opened by the kernel''s own progression rather than by fn_kernel_open_step; that is a '
     || 'consequence of the injected condition, not a second variable, because progression cannot '
     || 'reach a closure step whose predecessor is still open.',
        v_m3_ctl, v_m3_p1, v_m3_s0, v_m3_s1, v_m3_state, v_m3_def, v_m3_p2);
    end if;
  exception when others then
    perform set_config('app.phase_d_hold_step','', true);
    v_ok := false;
    v_msg := 'the W04 drive raised before the injection could be made: ' || left(SQLERRM, 220);
  end;
  defect_id:='PD-STATE-002'; category:='STATE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-STATE-003 a nonterminal step treated as closure -> a stable refusal code.
  -- THIS ONE IS NOT CLOSED, AND SAYING SO IS THE POINT. The refusal exists - fn_kernel_step_successor
  -- returns kind=closure_flag_disagrees and fn_kernel_step_complete turns that into
  -- k3_no_valid_successor (23514) - but the condition it answers cannot be created. Terminality is
  -- stated twice in public.phase_b_workflow_step (next_step_if_pass = 'WORKFLOW_COMPLETE' and
  -- is_closure_step) and the two agree on all 257 rows. Making them disagree means UPDATE-ing
  -- phase_b_workflow_step, which z90_phase_b_freeze refuses without a Phase B change request, and
  -- setting app.phase_b_change_reason to get past the founder's freeze inside a defect probe is not
  -- something this file will do. A zero-population arm is NOT_DISCRIMINATED, never a pass.
  select count(*) into v_m3_n from public.phase_b_workflow_step
   where (next_step_if_pass = 'WORKFLOW_COMPLETE') is distinct from is_closure_step;
  select count(*) into v_m3_p1 from public.phase_b_workflow_step;
  select count(*) into v_m3_p2 from public.phase_b_workflow_step where is_closure_step;
  v_m3_ctl   := (select kind from public.fn_kernel_step_successor('W04-S06'));
  v_m3_state := (select kind from public.fn_kernel_step_successor('W04-S07'));
  -- PD-STATE-003 a nonterminal step presented to the kernel as a closure step.
  -- THE POPULATION IS EMPTY — 0 of 257 frozen steps state their terminality inconsistently — and
  -- the old row stopped there, at NOT_DISCRIMINATED. But "why is it empty" is the measurable part:
  -- creating an inconsistent step is refused by z90_phase_b_freeze, which compares a DIGEST rather
  -- than a count, so flipping one boolean is refused even though no row count moves.
  --
  -- THE CONTROL IS THE OTHER REFUSAL. PD-STATE-004 above is refused by a10_phase_b_owner_guard with
  -- a different message. Two different guards answering two different injections is what shows the
  -- registry is judging the change rather than refusing every statement identically.
  begin
    select count(*) into v_n from public.phase_b_workflow_step
     where (next_step_if_pass = 'WORKFLOW_COMPLETE') <> is_closure_step;
    select step_id into v_s3_step from public.phase_b_workflow_step
     where workflow_id='W04' order by step_no limit 1;
    begin
      update public.phase_b_workflow_step set is_closure_step = not is_closure_step
       where step_id = v_s3_step;
      v_s3_flip := 'ACCEPTED — an inconsistent step was written';
    exception when others then v_s3_flip := left(SQLERRM, 130);
    end;
    v_ok := v_n = 0 and v_s3_flip not like 'ACCEPTED%';
    v_msg := format('%s of 257 frozen steps state their terminality inconsistently, and creating one '
                 || 'was refused: [%s]. The population is empty because the registry refuses to make '
                 || 'it non-empty, which is the fact this case is about; the refusal differs from the '
                 || 'one PD-STATE-004 receives, so the registry is judging the change rather than '
                 || 'refusing every statement alike.', v_n, v_s3_flip);
  exception when others then
    v_ok := false; v_msg := 'the probe raised outside its own handlers: ' || left(SQLERRM, 160);
  end;
  defect_id:='PD-STATE-003'; category:='STATE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;
  -- PD-STATE-004 a successor step with no accountable owner.
  -- THE OLD BLOCKER SAID THE SUBJECT IS A FROZEN PHASE B PROPERTY AND SO CANNOT BE INJECTED. The
  -- frozen registry REFUSING the injection is itself a discriminating result — it is what makes the
  -- state unreachable — and refusing to execute it left that refusal unmeasured.
  --
  -- TWO ARMS, and the second is the one that matters. Blanking the owner is refused by
  -- a10_phase_b_owner_guard; blanking it again with app.phase_b_change_reason SET is refused by the
  -- SAME guard, so an unowned successor cannot be created even by a caller holding change-request
  -- authority. That is stronger than "it is frozen": freezing can be amended, and this cannot.
  begin
    select step_id into v_s4_step from public.phase_b_workflow_step
     where workflow_id='W04' order by step_no limit 1;
    begin
      update public.phase_b_workflow_step set accountable_role_id = '' where step_id = v_s4_step;
      v_s4_bare := 'ACCEPTED — an unowned successor was written';
    exception when others then v_s4_bare := left(SQLERRM, 120);
    end;
    begin
      perform set_config('app.phase_b_change_reason',
        'PBCR-probe: a probe is not a change request; this exists to show the guard does not care', true);
      update public.phase_b_workflow_step set accountable_role_id = '' where step_id = v_s4_step;
      v_s4_reason := 'ACCEPTED with a change reason set';
    exception when others then v_s4_reason := left(SQLERRM, 120);
    end;
    perform set_config('app.phase_b_change_reason', '', true);
    v_ok := v_s4_bare not like 'ACCEPTED%' and v_s4_reason not like 'ACCEPTED%';
    v_msg := format('blanking the accountable owner of %s was refused [%s]; and refused again with '
                 || 'app.phase_b_change_reason set [%s]. A successor with no accountable owner cannot '
                 || 'be created in this estate even by a caller holding change-request authority, so '
                 || 'the state the defect names is unreachable by construction rather than by policy.',
                    v_s4_step, v_s4_bare, v_s4_reason);
  exception when others then
    v_ok := false; v_msg := 'the probe raised outside its own handlers: ' || left(SQLERRM, 160);
  end;
  defect_id:='PD-STATE-004'; category:='STATE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- ---- TRACE ----------------------------------------------------------------------------------
  -- PD-TRACE-001 / PD-TRACE-002.
  -- THE OLD BLOCKER TREATED THE REFUSAL AS THE OBSTACLE. It is the control. Phase D's whole
  -- contract for a kernel-owned object is that it refuses to write it, and fn_phase_d_object_write
  -- says so by name. Calling it and reading the refusal is a discriminating result: a Phase D path
  -- that DID stage an untraced step run is exactly the defect, and this proves it cannot.
  -- The positive half is that the same routine accepts a Phase D-owned object in the same shape,
  -- so the refusal is about the subject and not about the routine refusing everything.
  begin
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','workflow_step_run',
      'business_key','zz-pd-trace-001',
      'owner_ref','system.workflow_engine', 'created_by','system.workflow_engine',
      'target_state','active',
      'payload', jsonb_build_object('note','PHASE_D_FIXTURE_DO_NOT_PUBLISH — untraced step run')));
    v_ok := false;
    v_msg := 'a Phase D handler WROTE a kernel-owned step run';
  exception when others then
    v_ok := position('pd_object_kernel_owned' in SQLERRM) > 0;
    v_msg := case when v_ok
      then 'fn_phase_d_object_write refused the kernel-owned relation by name (pd_object_kernel_owned): '
        || 'a Phase D handler that wrote it would be a second creator for one object. An active step '
        || 'run with no trace therefore cannot be staged through any Phase D door.'
      else 'refused, but not as a kernel-owned object: ' || left(SQLERRM, 160) end;
  end;
  defect_id:='PD-TRACE-001'; category:='TRACE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  defect_id:='PD-TRACE-002'; category:='TRACE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := 'the closing half has the same single door and the same refusal: ' || v_msg;
  blocker := null; return next;
  -- PD-TRACE-003 a sealed trace with no sealed_at -> refused.
  -- THE OLD BLOCKER SAID sealed_at IS A KERNEL COLUMN AND SO OUT OF REACH. Re-measured 24 Aug 2026:
  -- the refusal is a CHECK constraint, phase_c_trace_sealed_ck ((status='sealed') = (sealed_at is
  -- not null)), which fires on the statement, not at commit and not through any kernel routine.
  begin
    v_m3_trace := public.fn_phase_c_trace_write('TRACE-ROLE-ACTION', jsonb_build_object(
      'subject_kind','task', 'subject_ref','zz-pd-trace-003',
      'actor_role_id','defect_probe', 'status','open',
      'evidence_refs', jsonb_build_array(jsonb_build_object(
        'note','PHASE_D_FIXTURE_DO_NOT_PUBLISH - an OPEN trace, written through the kernel door'))));
    -- ALIASED: status, observed, category, defect_id and blocker are OUT columns of this
    -- function, so an unqualified status in a query against phase_c_trace is ambiguous (42702).
    select (tr.sealed_at is null and tr.status = 'open') into v_m3_ok2
      from public.phase_c_trace tr where tr.trace_id = v_m3_trace;
    begin
      update public.phase_c_trace set status = 'sealed' where trace_id = v_m3_trace;
      v_m3_ctl := 'ACCEPTED';
    exception when others then
      v_m3_ctl := case when position('phase_c_trace_sealed_ck' in SQLERRM) > 0
                       then 'phase_c_trace_sealed_ck/' || SQLSTATE
                       else SQLSTATE || ':' || left(SQLERRM, 60) end;
    end;
    begin
      update public.phase_c_trace set status = 'sealed', sealed_at = now()
       where trace_id = v_m3_trace;
      v_m3_state := 'ACCEPTED';
    exception when others then
      v_m3_state := SQLSTATE || ':' || left(SQLERRM, 90);
    end;
    select count(*) into v_m3_n from public.phase_c_trace tr
     where tr.trace_id = v_m3_trace and tr.status = 'sealed' and tr.sealed_at is null;
    v_ok := coalesce(v_m3_ok2,false) and v_m3_ctl = 'phase_c_trace_sealed_ck/23514'
        and v_m3_state = 'ACCEPTED' and v_m3_n = 0;
    v_msg := format(
      'An OPEN trace %s was written through fn_phase_c_trace_write (status=open, sealed_at null: %s). '
   || 'INJECTION: update it to status=''sealed'' and leave sealed_at null -> %s. CONTROL, differing '
   || 'in exactly one respect - the SAME update with sealed_at = now() -> %s. Rows on '
   || 'public.phase_c_trace that are sealed with a null sealed_at after both attempts: %s. The '
   || 'refusal is the table''s own CHECK, so it is the same answer for every writer of that column, '
   || 'kernel or not; the whole transaction is aborted.',
      v_m3_trace, coalesce(v_m3_ok2::text,'(unknown)'), v_m3_ctl, v_m3_state, v_m3_n);
  exception when others then
    v_ok := false;
    v_msg := 'the open trace could not be written, so nothing was injected: ' || left(SQLERRM, 200);
  end;
  defect_id:='PD-TRACE-003'; category:='TRACE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;
  -- PD-TRACE-004 a failed idempotent insert leaves an orphan trace -> zero orphan.
  -- THE OLD BLOCKER SAID THE ORPHAN HAD TO COMMIT TO BE SEEN. Re-measured 24 Aug 2026 and false in
  -- two independent ways, both below: the ORDERING that makes the orphan impossible is readable
  -- from the routine itself, and the detector that would catch one is DEFERRABLE, which means
  -- SET CONSTRAINTS ALL IMMEDIATE fires it inside this transaction instead of at a commit.

  -- (a) ORDERING, measured off the live routine rather than asserted about it.
  select pg_get_functiondef('public.fn_kernel_step_complete(jsonb)'::regprocedure) into v_m3_def;
  v_m3_p1 := position('4. CLAIM THE IDEMPOTENCY KEY' in v_m3_def);
  v_m3_p2 := position('idempotency key % is claimed and carries no result' in v_m3_def);
  v_m3_p3 := least(nullif(position('fn_phase_c_trace_advance' in v_m3_def),0),
                   nullif(position('fn_phase_c_trace_write'   in v_m3_def),0));
  v_m3_ok2 := v_m3_p1 > 0 and v_m3_p2 > 0 and v_m3_p3 > 0
          and v_m3_p1 < v_m3_p2 and v_m3_p2 < v_m3_p3;

  -- (b) THE DETECTOR IS FORCEABLE. z90_system_execution_pair_guard on public.phase_c_trace is a
  --     CONSTRAINT TRIGGER, DEFERRABLE INITIALLY DEFERRED.
  begin
    v_m3_trace := public.fn_phase_c_trace_write('TRACE-SYSTEM-EXECUTION', jsonb_build_object(
      'subject_kind','system_execution', 'subject_ref','zz.pd.trace004.probe',
      'component_id','zz.pd.trace004.probe', 'actor_role_id','defect_probe', 'status','open'));
    set constraints all immediate;
    v_m3_state := 'SILENT';
    set constraints all deferred;
  exception when others then
    v_m3_state := SQLSTATE || ':' || left(SQLERRM, 90);
  end;
  begin
    v_m3_sup := public.fn_phase_c_trace_write('TRACE-SYSTEM-EXECUTION', jsonb_build_object(
      'subject_kind','system_execution', 'subject_ref','zz.pd.trace004.probe',
      'component_id','zz.pd.trace004.probe', 'actor_role_id','defect_probe', 'status','sealed'));
    set constraints all immediate;
    v_m3_ctl := 'SILENT';
    set constraints all deferred;
  exception when others then
    v_m3_ctl := case when position('with no row in phase_c_system_execution' in SQLERRM) > 0
                     then 'z90_system_execution_pair_guard/' || SQLSTATE
                     else SQLSTATE || ':' || left(SQLERRM, 60) end;
  end;

  -- (c) THE TASK SIDE CANNOT EVEN BE STAGED, and that is a stronger answer than the one expected.
  if v_m3_task is null then
    v_m3_key := 'no task from the PD-STATE-002 drive was available to point at a deleted trace';
  else
    begin
      v_m3_orph := public.fn_phase_c_trace_write('TRACE-ROLE-ACTION', jsonb_build_object(
        'subject_kind','task', 'subject_ref','zz-pd-trace-004-orphan',
        'actor_role_id','defect_probe', 'status','open'));
      delete from public.phase_c_trace where trace_id = v_m3_orph;
      update public.phase_c_task set trace_id = v_m3_orph where task_id = v_m3_task;
      set constraints all immediate;
      v_m3_key := 'the orphan was STAGED AND NOT DETECTED';
      set constraints all deferred;
    exception when others then
      v_m3_key := case when SQLSTATE = '42501'
        then 'refused 42501 before the orphan could be staged at all - a direct UPDATE of '
             || 'public.phase_c_task is refused because no routine with write authority for that '
             || 'table is on the call stack, so z95_phase_c_task_trace_committed never has to fire'
        else SQLSTATE || ': ' || left(SQLERRM, 110) end;
    end;
  end if;

  select count(*) into v_m3_n from public.phase_c_task t
   where t.trace_id is null
      or not exists (select 1 from public.phase_c_trace x where x.trace_id = t.trace_id);
  v_ok := v_m3_ok2 and v_m3_state = 'SILENT'
      and v_m3_ctl = 'z90_system_execution_pair_guard/23514' and v_m3_n = 0;
  defect_id:='PD-TRACE-004'; category:='TRACE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format(
      '(a) ORDERING, measured off pg_get_functiondef of the live fn_kernel_step_complete rather '
   || 'than asserted: the idempotency claim (section 4) is at character %s, the lost-race branch '
   || 'that returns the other caller''s result is at %s, and the FIRST trace write of any kind is '
   || 'at %s - claim before lost-race return before any trace, ordered correctly: %s. A caller that '
   || 'loses the race therefore returns before a trace exists to be orphaned. '
   || '(b) THE DETECTOR IS FORCEABLE IN-TRANSACTION. z90_system_execution_pair_guard on '
   || 'public.phase_c_trace is DEFERRABLE INITIALLY DEFERRED, so SET CONSTRAINTS ALL IMMEDIATE '
   || 'fires it here. CONTROL: a correctly paired TRACE-SYSTEM-EXECUTION trace left OPEN - an '
   || 'execution in flight, which is allowed to have no phase_c_system_execution row - forced -> '
   || '%s. INJECTION, differing in exactly one respect, the same trace written SEALED with no '
   || 'execution row -> %s. (c) THE TASK-SIDE ORPHAN CANNOT BE STAGED: pointing a real task at a '
   || 'trace deleted in this transaction was %s. Tasks in the whole estate with a null or '
   || 'unresolvable trace_id after all of it: %s.',
      v_m3_p1, v_m3_p2, v_m3_p3, v_m3_ok2, v_m3_state, v_m3_ctl, v_m3_key, v_m3_n);
  blocker := null; return next;
  -- PD-TRACE-005. THE ABSENCE OF A PHASE D PATH IS THE CONTROL, not the blocker: a Phase D route
  -- that could put a state-changing component on a read-only trace policy is precisely the defect.
  -- Both halves are executed -- the Phase D door refuses the write, and the kernel's own board
  -- reports the standing population -- so the row rests on two measurements rather than on prose.
  begin
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','trace_policy',
      'business_key','TRACE-MONITORING',
      'owner_ref','system.workflow_engine', 'created_by','system.workflow_engine',
      'target_state','exempt',
      'payload', jsonb_build_object('note','PHASE_D_FIXTURE_DO_NOT_PUBLISH — exemption request')));
    v_ok := false;
    v_msg := 'a Phase D handler granted itself a trace exemption';
  exception when others then
    -- The specific code, not any error: a probe that accepts every failure would score a typo as a
    -- pass. trace_policy is not a bound Phase D object, so the door fails closed rather than storing
    -- a record under a policy nobody declared -- which is the refusal this case needs.
    v_ok := position('pd_object_unbound' in SQLERRM) > 0;
    v_msg := 'the Phase D write door refused the trace policy (' ||
             coalesce((regexp_match(SQLERRM,'\((pd_[a-z0-9_]+)\)'))[1], SQLSTATE) || ')';
  end;
  select coalesce(string_agg(b.check_name || ' ' || b.actual, '; '), '(no rows)')
    into v_t5_board
    from public.fn_kernel_system_trace_state() b
   where b.check_name in ('state_changing_components_on_a_read_only_policy',
                          'read_only_components_without_a_recorded_exemption');
  defect_id:='PD-TRACE-005'; category:='TRACE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg || '; and the kernel board reports ' || v_t5_board;
  blocker := null; return next;

  -- ---- The categories that need section 8 -------------------------------------------------------
  -- Each names the specific missing capability. None is mapped onto a nearby guard.
  for v_key, v_msg in
    select * from (values
      ('PD-AUTH-001','AUTH: needs an unauthenticated HTTP request against a deployed customer endpoint and the response status. No Phase D path issues an HTTP request.'),
      ('PD-AUTH-002','AUTH: needs supplier A''s bearer token against supplier B''s document URL. Requires the section 8 API + storage path.'),
      ('PD-AUTH-003','AUTH: needs a non-admin identity attempting an admin mutation over HTTP; the RLS/route decision is made in the edge function, not in SQL.'),
      ('PD-AUTH-004','AUTH: needs an inactive canonical role to attempt a step through the API; in SQL the driver supplies the role directly and never authenticates it.'),
      ('PD-FILE-001','FILES: needs a real upload whose magic bytes disagree with its extension. The attachment classifier lives in supabase/functions/_shared/attachment.ts and is exercised by its own deno test, not by any SQL path.'),
      ('PD-FILE-002','FILES: needs an oversized upload against the storage endpoint and a 413.'),
      ('PD-FILE-003','FILES: needs executable content posted as a document and the quarantine result.'),
      ('PD-FILE-004','FILES: needs an EXPIRED signed URL to be reused and the 403 observed; signed URLs are minted by storage, not by the database.'),
      ('PD-FILE-005','FILES: needs an insert into storage.objects under a path the caller does not own, judged by a storage RLS policy.'),
      ('PD-PRIV-003','PRIVACY: needs a signed URL whose path belongs to another supplier; storage authorization is the subject.'),
      ('PD-PRIV-004','PRIVACY: needs a supplier bearer token calling the raw inquiry endpoint and the response body.')
    ) as t(a,b)
  loop
    defect_id := v_key; category := split_part(v_msg, ':', 1); status := 'NOT_RUN';
    observed := null; blocker := 'SECTION 8 NOT BUILT — ' || v_msg;
    return next;
  end loop;


  -- ---- THE FOUR THAT NEEDED A FIXTURE, NOT A COMMITTED ROW -------------------------------------
  -- public.inquiries, public.quotes and public.phase_d_object_record hold ZERO rows OUTSIDE a
  -- fixture. Inside one they do not. fn_phase_d_fixture_scenario builds the customer, the inquiry,
  -- the supplier account and the terms acceptance IN THIS TRANSACTION, and every refusal below is
  -- an immediate BEFORE-trigger, CHECK or writer refusal -- none is deferred to commit. The four
  -- blockers these branches replace each said the injection needed a COMMITTED row. It did not; it
  -- needed a fixture, and this function already runs inside a verified fixture context.
  -- MEASURED, NOT ASSUMED: the deliverable driver opens the context and builds NO scenario, so the
  -- scenario is built here rather than presumed to be standing.
  v_pay := public.fn_phase_d_fixture_scenario(jsonb_build_object(
             'label','zz-defect-four','execution_context','test'));
  v_sup := v_pay->'parent_refs'->>'inquiry_id';

  -- PD-DISP-001 an inquiry that is not quote-ready, presented to the dispatch path.
  -- TWO IMPLEMENTATIONS AND THEY DO NOT READ THE SAME COLUMN. fn_phase_d_gate_evaluate('GATE-011')
  -- and fn_phase_d_rule_check('BR-013') read public.inquiries.status; trigger gate_incomplete_match
  -- BEFORE INSERT ON public.inquiry_matches reads i.rfq_ready and returns null. Both are measured.
  -- rfq_ready is DERIVED -- trg_rfq_complete recomputes it from fn_rfq_score on every write -- so
  -- setting that column false is not an injection at all. The injection is an RFQ that is genuinely
  -- incomplete; the scorer then makes both columns unready, which is why one arm can move both.
  v_a := (select to_jsonb(i) from public.inquiries i where i.id::text = v_sup);
  -- RESOLVE, THEN CREATE. uq_leads_email_lower is a unique index on lower(email), so a second call
  -- to this function inside one transaction would collide on it. Every demo supplier below is
  -- looked up first and written only when it is not already standing.
  if not exists (select 1 from public.leads l where lower(l.email) = 'zz-disp001@example.invalid') then
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_account','business_key','zz-disp001-sup','owner_ref','zz-disp001-sup',
      'created_by','defect_probe','state','approved',
      'payload', jsonb_build_object('company_name','ZZ DEMO - disp001 supplier',
        'email','zz-disp001@example.invalid','verified', true)));
  end if;
  select l.id::text into v_key from public.leads l where lower(l.email)='zz-disp001@example.invalid';
  update public.inquiries set spec=null, summary=null, raw_input=null, boq=null, budget=null,
         trades=null, scope_type=null, status='new',
         routing = coalesce(routing,'{}'::jsonb) || jsonb_build_object('dispatched_at', now(),
           'dispatched_by','phase_d_test_context','phase_d_outbound_suppressed', true)
   where id::text = v_sup;
  select count(*) into v_n from public.inquiry_matches;
  select (g.passed is not true) and g.refusal_code = 'gate011_inquiry_not_ready'
    into v_ok from public.fn_phase_d_gate_evaluate('GATE-011', jsonb_build_object('inquiry_id', v_sup)) g;
  select coalesce(v_ok,false) and (r.ok is not true) into v_ok
    from public.fn_phase_d_rule_check('BR-013', jsonb_build_object('inquiry_id', v_sup)) r;
  begin
    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_assignment','business_key','zz-disp001-inject','owner_ref', v_key,
      'created_by','defect_probe',
      'payload', jsonb_build_object('inquiry_id', v_sup,'similarity',0.5,
        'match_reason','ZZ DEMO - disp001 injection')));
    v_ok := false; v_msg := 'the dispatch write was NOT refused: ' || (v_b->>'result_reference') || ' ';
  exception when others then
    -- THE VERDICT IS READ OUT OF THE RAISED MESSAGE, NOT OFF THE GUC. This exception block is a
    -- subtransaction, so the set_config the refusing trigger issued was rolled back with it and the
    -- key still holds PASS from the fixture's own earlier assignment. Reading it here measured the
    -- wrong subject and said PASS for a write that had just been refused.
    v_ok := coalesce(v_ok,false) and position('pd_object_write_produced_nothing' in SQLERRM) > 0
            and position('BLOCKED_NOT_RFQ_READY' in SQLERRM) > 0;
    v_msg := format('status=%s rfq_ready=%s: gate011_inquiry_not_ready + BR-013 BLOCKED, trigger %s, pd_object_write_produced_nothing, im %s->%s. ',
      (select coalesce(i2.status,'(null)') from public.inquiries i2 where i2.id::text=v_sup),
      (select coalesce(i2.rfq_ready::text,'(null)') from public.inquiries i2 where i2.id::text=v_sup),
      split_part(coalesce(nullif(split_part(SQLERRM, 'Gate verdict: ', 2),''),'(no verdict)'), ' ', 1),
      v_n, (select count(*) from public.inquiry_matches));
  end;
  -- CONTROL. The SAME inquiry with its qualification content restored and the SAME supplier, so
  -- readiness is the only thing that differs between the two arms.
  update public.inquiries set spec = v_a->'spec', summary = v_a->>'summary',
         raw_input = v_a->>'raw_input', boq = v_a->'boq', budget = v_a->>'budget',
         scope_type = v_a->>'scope_type', status = v_a->>'status',
         trades = (select coalesce(array_agg(x),'{}')::text[]
                     from jsonb_array_elements_text(coalesce(v_a->'trades','[]'::jsonb)) x),
         routing = coalesce(routing,'{}'::jsonb) || jsonb_build_object('dispatched_at', now(),
           'dispatched_by','phase_d_test_context','phase_d_outbound_suppressed', true)
   where id::text = v_sup;
  select count(*) into v_n from public.inquiry_matches;
  begin
    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_assignment','business_key','zz-disp001-control','owner_ref', v_key,
      'created_by','defect_probe',
      'payload', jsonb_build_object('inquiry_id', v_sup,'similarity',0.5,
        'match_reason','ZZ DEMO - disp001 control')));
    v_ok := coalesce(v_ok,false) and (v_b->>'result_reference') is not null;
    v_msg := v_msg || format('CONTROL restored (%s/%s), same supplier: written, im %s->%s.',
      (select coalesce(i2.status,'(null)') from public.inquiries i2 where i2.id::text=v_sup),
      (select coalesce(i2.rfq_ready::text,'(null)') from public.inquiries i2 where i2.id::text=v_sup),
      v_n, (select count(*) from public.inquiry_matches));
  exception when others then
    v_ok := false; v_msg := v_msg || 'CONTROL was refused too: ' || left(SQLERRM,80);
  end;
  defect_id:='PD-DISP-001'; category:='DISPATCH';
  status := case when coalesce(v_ok,false) then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-DISP-002 a supplier that is pending, rejected or expired, presented to the assignment path.
  -- All four suppliers below are verified=true, so approval_status is the ONLY thing that differs
  -- between each injection and the control -- leads_approved_implies_verified would otherwise make
  -- the control differ in two columns at once.
  -- pending / rejected / expired are written into approval_status, which is the column both
  -- BR-015 and GATE-014 read and which carries no CHECK on its values. leads.registration_expires_at
  -- exists but no rule, no gate and no trigger on inquiry_matches reads it, so expiry has no other
  -- representation any of these three implementations would see.
  v_msg := ''; v_ok := true;
  for v_key in select unnest(array['pending','rejected','expired']) loop
    if not exists (select 1 from public.leads l
                    where lower(l.email) = 'zz-disp002-'||v_key||'@example.invalid') then
      perform public.fn_phase_d_object_write(jsonb_build_object(
        'object_id','supplier_account','business_key','zz-disp002-'||v_key,
        'owner_ref','zz-disp002-'||v_key,'created_by','defect_probe','state', v_key,
        'payload', jsonb_build_object('company_name','ZZ DEMO - disp002 '||v_key,
          'email','zz-disp002-'||v_key||'@example.invalid','verified', true)));
    end if;
    select jsonb_build_object('supplier_id', l.id::text) into v_a from public.leads l
     where lower(l.email) = 'zz-disp002-'||v_key||'@example.invalid';
    select coalesce(v_ok,false) and (r.ok is not true) into v_ok
      from public.fn_phase_d_rule_check('BR-015', v_a) r;
    select coalesce(v_ok,false) and (g.passed is not true)
       and g.refusal_code = 'gate014_supplier_unverified'
      into v_ok from public.fn_phase_d_gate_evaluate('GATE-014', v_a) g;
    -- AND WHAT THE WRITE PATH ITSELF DOES WITH THE SAME SUPPLIER. Undone in its own subtransaction
    -- so the measurement leaves nothing behind whichever way it comes out.
    begin
      v_b := public.fn_phase_d_object_write(jsonb_build_object(
        'object_id','supplier_assignment','business_key','zz-disp002-a-'||v_key,
        'owner_ref', v_a->>'supplier_id','created_by','defect_probe',
        'payload', jsonb_build_object('inquiry_id', v_sup,'similarity',0.5,
          'match_reason','ZZ DEMO - disp002 '||v_key)));
      v_msg := v_msg || v_key || '=W ';
      raise exception 'ZZ_UNDO';
    exception when others then
      if SQLERRM <> 'ZZ_UNDO' then v_msg := v_msg || v_key || '=refused '; end if;
    end;
  end loop;
  if not exists (select 1 from public.leads l
                  where lower(l.email) = 'zz-disp002-approved@example.invalid') then
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_account','business_key','zz-disp002-approved',
      'owner_ref','zz-disp002-approved','created_by','defect_probe','state','approved',
      'payload', jsonb_build_object('company_name','ZZ DEMO - disp002 approved',
        'email','zz-disp002-approved@example.invalid','verified', true)));
  end if;
  select jsonb_build_object('supplier_id', l.id::text) into v_a from public.leads l
   where lower(l.email) = 'zz-disp002-approved@example.invalid';
  select coalesce(v_ok,false) and coalesce(r.ok,false) into v_ok
    from public.fn_phase_d_rule_check('BR-015', v_a) r;
  select count(*) into v_n from public.inquiry_matches;
  begin
    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_assignment','business_key','zz-disp002-control',
      'owner_ref', v_a->>'supplier_id','created_by','defect_probe',
      'payload', jsonb_build_object('inquiry_id', v_sup,'similarity',0.5,
        'match_reason','ZZ DEMO - disp002 control')));
    v_msg := v_msg || format('| CTRL approved: written, im %s->%s',
      v_n, (select count(*) from public.inquiry_matches));
    raise exception 'ZZ_UNDO';
  exception when others then
    if SQLERRM <> 'ZZ_UNDO' then
      v_ok := false; v_msg := v_msg || '| CONTROL refused: ' || left(SQLERRM,60);
    end if;
  end;
  defect_id:='PD-DISP-002'; category:='DISPATCH';
  status := case when coalesce(v_ok,false) then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('BR-015+GATE-014(gate014_supplier_unverified) refuse all 3 alike, none distinguished; the inquiry_matches BEFORE-INSERT guard never reads approval_status and WROTE all 3: %s', v_msg);
  blocker := null; return next;

  -- PD-DISP-004 a refused assignment counted as a notification.
  -- The refusal is a BEFORE-trigger return-null on public.inquiry_matches; the notification is
  -- written by the AFTER INSERT trigger notify_matched_supplier, which a BEFORE null never reaches.
  -- Both counts are taken around both arms and both are stated.
  if not exists (select 1 from public.leads l where lower(l.email) = 'zz-disp004@example.invalid') then
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_account','business_key','zz-disp004-sup','owner_ref','zz-disp004-sup',
      'created_by','defect_probe','state','approved',
      'payload', jsonb_build_object('company_name','ZZ DEMO - disp004 supplier',
        'email','zz-disp004@example.invalid','verified', true)));
  end if;
  select l.id::text into v_key from public.leads l where lower(l.email)='zz-disp004@example.invalid';
  update public.leads set matching_blocked = true,
         matching_block_reason = 'ZZ DEMO - PD-DISP-004 injection' where id::text = v_key;
  select count(*) into v_n from public.inquiry_matches;
  select count(*) into v_id from public.notifications;
  begin
    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_assignment','business_key','zz-disp004-inject','owner_ref', v_key,
      'created_by','defect_probe',
      'payload', jsonb_build_object('inquiry_id', v_sup,'similarity',0.5,
        'match_reason','ZZ DEMO - disp004 injection')));
    v_ok := false; v_msg := 'the refused assignment was written: ' || (v_b->>'result_reference') || ' ';
  exception when others then
    -- Same reason as PD-DISP-001: the GUC the trigger published was rolled back with this
    -- subtransaction, so the verdict is taken from the message the writer raised.
    v_ok := position('pd_object_write_produced_nothing' in SQLERRM) > 0
            and position('BLOCKED_INELIGIBLE_SUPPLIER' in SQLERRM) > 0
            and v_n = (select count(*) from public.inquiry_matches)
            and v_id = (select count(*) from public.notifications);
    -- Q08. THE VERDICT WAS ALWAYS A DELTA; THE EVIDENCE WAS AN ABSOLUTE COUNT.
    -- v_ok above compares counts BEFORE and AFTER, which is right. This string printed the two
    -- absolute values -- 'notifications 676->676' -- and public.notifications grows on its own:
    -- the 15-minute health cron writes to it. So the deliverable this string lands in could not
    -- reproduce byte-for-byte more than a few minutes after it was built, and Gate 2 requires
    -- exactly that. Measured 25 Aug 2026: the only diff between two runs seven hours apart was
    -- 676->676 becoming 678->678. The delta is the fact the control is about and it is stable.
    v_msg := format('refused %s: im %s, notifications %s. ',
      split_part(coalesce(nullif(split_part(SQLERRM, 'Gate verdict: ', 2),''),'(no verdict)'), ' ', 1),
      to_char((select count(*) from public.inquiry_matches) - v_n, 'SFM999999'),
      to_char((select count(*) from public.notifications) - v_id, 'SFM999999'));
  end;
  -- CONTROL. The SAME supplier and the SAME inquiry; matching_blocked is the one thing that moves.
  update public.leads set matching_blocked = false, matching_block_reason = null
   where id::text = v_key;
  select count(*) into v_n from public.inquiry_matches;
  select count(*) into v_id from public.notifications;
  begin
    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_assignment','business_key','zz-disp004-control','owner_ref', v_key,
      'created_by','defect_probe',
      'payload', jsonb_build_object('inquiry_id', v_sup,'similarity',0.5,
        'match_reason','ZZ DEMO - disp004 control')));
    v_msg := v_msg || format('CONTROL same supplier+inquiry, unblocked: im %s, notifications %s.',
      to_char((select count(*) from public.inquiry_matches) - v_n, 'SFM999999'),
      to_char((select count(*) from public.notifications) - v_id, 'SFM999999'));
    v_ok := coalesce(v_ok,false)
            and (select count(*) from public.inquiry_matches) = v_n + 1
            and (select count(*) from public.notifications) = v_id + 1;
  exception when others then
    v_ok := false; v_msg := v_msg || 'CONTROL was refused too: ' || left(SQLERRM,80);
  end;
  defect_id:='PD-DISP-004'; category:='DISPATCH';
  status := case when coalesce(v_ok,false) then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-LEGAL-002 an accepted terms version, rewritten. Two layers and both are immediate.
  select r.record_id, r.business_key, r.owner_ref into v_id, v_key, v_msg
    from public.phase_d_object_record r
   where r.object_id = 'customer_terms_acceptance' and r.superseded_by is null
   order by r.record_id desc limit 1;
  begin
    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','customer_terms_acceptance','business_key', v_key,'owner_ref', v_msg,
      'created_by','defect_probe','state','accepted',
      'payload', jsonb_build_object('stage','customer_terms_acceptance',
        'terms_version','v9-rewritten','accepted_by', v_msg)));
    v_ok := false; v_msg := 'the writer accepted a second version: ' || (v_b->>'result_reference') || ' ';
  exception when others then
    v_ok := position('pd_object_append_only' in SQLERRM) > 0;
    v_msg := 'writer pd_object_append_only; ';
  end;
  select count(*) into v_n from public.phase_d_object_record;
  begin
    update public.phase_d_object_record
       set payload = jsonb_set(payload, '{terms_version}', '"v9-rewritten"')
     where record_id = v_id;
    v_ok := false; v_msg := v_msg || 'the guard permitted a payload rewrite; ';
  exception when others then
    v_ok := coalesce(v_ok,false) and position('pd_object_overwrite_refused' in SQLERRM) > 0;
    v_msg := v_msg || 'guard pd_object_overwrite_refused; ';
  end;
  -- CONTROL. The SAME UPDATE on the SAME row, differing in exactly one respect: the column it moves
  -- is one the APPEND_ONLY family does not freeze. Read from the guard body -- identity, owner,
  -- payload, created_by and created_at are frozen, and for APPEND_ONLY the state too; the
  -- supersession columns are not, and that is the one change an append-only record still permits.
  begin
    update public.phase_d_object_record set superseded_at = now() where record_id = v_id;
    v_msg := v_msg || 'CONTROL same row, superseded_at (not frozen): ACCEPTED';
  exception when others then
    v_ok := false; v_msg := v_msg || 'CONTROL refused too: ' || left(SQLERRM,60);
  end;
  defect_id:='PD-LEGAL-002'; category:='LEGAL';
  status := case when coalesce(v_ok,false) then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg || format('; records %s->%s, terms_version still %s', v_n,
    (select count(*) from public.phase_d_object_record),
    (select r2.payload->>'terms_version' from public.phase_d_object_record r2 where r2.record_id = v_id));
  blocker := null; return next;

  -- ---- THE FIVE THAT NEEDED A CONTRACT, AND NOW HAVE ONE ---------------------------------------
  -- Each of these was NOT_RUN because the control it names did not exist in this estate. O03-O07
  -- built them. Every branch below drives an injection AND its control, and the control is the half
  -- that makes the refusal mean something: a predicate that refuses both arms is indistinguishable
  -- from a dead path.

  -- PD-LEGAL-004. Four ways a source fails and one way it does not, over committed reference rows
  -- in public.phase_d_legal_source that this branch does not create -- a probe that writes its own
  -- stale source and then asks whether a stale source is refused has answered its own question.
  declare v_g4 text[]; v_g4_ok boolean;
  begin
    select array[
      coalesce((select refusal_code from public.fn_phase_d_legal_source_current('zz-demo-fta-corporate-tax-expired')),'USABLE'),
      coalesce((select refusal_code from public.fn_phase_d_legal_source_current('zz-demo-undated-circular')),'USABLE'),
      coalesce((select refusal_code from public.fn_phase_d_legal_source_current('zz-demo-blog-vat-opinion')),'USABLE'),
      coalesce((select refusal_code from public.fn_phase_d_legal_source_current('zz-demo-fta-corporate-tax-2024')),'USABLE'),
      coalesce((select refusal_code from public.fn_phase_d_legal_source_current('zz-demo-fta-corporate-tax-current')),'USABLE'),
      coalesce((select refusal_code from public.fn_phase_d_gate_evaluate('GATE-027', jsonb_build_object(
        'reconciliation_ref','zz','control_exception_ref','zz','tax_source_ref','zz-demo-fta-corporate-tax-expired'))),'PASSED')
    ] into v_g4;
    v_g4_ok := v_g4[1]='pd_legal_source_stale' and v_g4[2]='pd_legal_source_missing'
           and v_g4[3]='pd_legal_source_not_authoritative' and v_g4[4]='pd_legal_source_superseded'
           and v_g4[5]='USABLE' and v_g4[6]='pd_legal_source_stale';
    -- and the HARD boundary: an assertion citing the stale source is refused outright
    begin
      insert into public.phase_d_legal_assertion
        (subject, jurisdiction, position_summary, source_id, asserted_by_role_id)
      values ('pd-legal-004','AE','probe','zz-demo-fta-corporate-tax-expired','ceo');
      v_g4 := v_g4 || 'ASSERTION_ACCEPTED';
    exception when others then
      v_g4 := v_g4 || case when position('pd_legal_source_stale' in SQLERRM) > 0
                           then 'pd_legal_source_stale' else 'other:'||SQLSTATE end;
    end;
    v_g4_ok := v_g4_ok and v_g4[7] = 'pd_legal_source_stale';
    defect_id:='PD-LEGAL-004'; category:='LEGAL';
    status := case when v_g4_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('freshness predicate stale/undated/non-authoritative/superseded/current -> %s; GATE-027 on the stale source -> %s; assertion citing it -> %s',
                       array_to_string(v_g4[1:5],','), v_g4[6], v_g4[7]);
    blocker := null; return next;
  end;

  -- PD-PRIV-002. A revision whose redaction is unapproved, one rejected, one superseded, and the
  -- approved clean one, all through BR-012 and GATE-013 -- the two predicates that returned the
  -- IDENTICAL ENFORCED_PASS to the injection and the control before O07.
  declare v_p2 text[]; v_p2_ok boolean;
  begin
    select array[
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-drawing-unredacted')),'DISPATCHABLE'),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-drawing-rejected')),'DISPATCHABLE'),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-drawing-superseded')),'DISPATCHABLE'),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-drawing-safe')),'DISPATCHABLE'),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-drawing-safe', repeat('f',64))),'DISPATCHABLE'),
      (select state from public.fn_phase_d_gate_evaluate('GATE-013', jsonb_build_object(
        'safe_package_ref','zz-demo-pkg-priv-002','safe_package_approved_by','ceo',
        'actor_role_id','marketplace_content_privacy_reviewer'))),
      (select state from public.fn_phase_d_gate_evaluate('GATE-013', jsonb_build_object(
        'safe_package_ref','zz-demo-pkg-priv-002-clean','safe_package_approved_by','ceo',
        'actor_role_id','marketplace_content_privacy_reviewer')))
    ] into v_p2;
    v_p2_ok := v_p2[1]='pd_revision_redaction_unapproved' and v_p2[2]='pd_revision_redaction_rejected'
           and v_p2[3]='pd_revision_superseded' and v_p2[4]='DISPATCHABLE'
           and v_p2[5]='pd_revision_digest_mismatch' and v_p2[6]='BLOCKED' and v_p2[7]='PASSED';
    defect_id:='PD-PRIV-002'; category:='PRIVACY';
    status := case when v_p2_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('revision pending/rejected/superseded/approved/wrong-digest -> %s; GATE-013 on the unapproved package -> %s, on the approved one -> %s',
                       array_to_string(v_p2[1:5],','), v_p2[6], v_p2[7]);
    blocker := null; return next;
  end;

  -- PD-PRIV-005. The hidden-metadata verdict recorded by scripts/phase_d/run_metadata_scan_probe.mjs
  -- over the committed fixture bytes, and the two fail-closed arms. The scan is a MEASUREMENT taken
  -- outside the database because Postgres never receives file bytes; this branch reads what it
  -- recorded and refuses to score a revision whose scan is absent.
  declare v_p5 text[]; v_p5_ok boolean; v_p5_n bigint;
  begin
    select count(*) into v_p5_n from public.phase_d_metadata_scan;
    select array[
      coalesce((select outcome from public.phase_d_metadata_scan
                 where revision_ref='zz-demo-rev-photo-unredacted' order by scan_id desc limit 1),'NO_SCAN'),
      coalesce((select outcome from public.phase_d_metadata_scan
                 where revision_ref='zz-demo-rev-photo-safe' order by scan_id desc limit 1),'NO_SCAN'),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-photo-unredacted')),'DISPATCHABLE'),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-photo-safe')),'DISPATCHABLE'),
      (select state from public.fn_phase_d_rule_check('BR-011', jsonb_build_object(
        'supplier_payload','scope only','file_revision_ref','zz-demo-rev-photo-unredacted'))),
      (select state from public.fn_phase_d_rule_check('BR-011', jsonb_build_object(
        'supplier_payload','scope only','file_revision_ref','zz-demo-rev-photo-safe'))),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-drawing-unredacted')),'DISPATCHABLE')
    ] into v_p5;
    v_p5_ok := v_p5[1]='IDENTIFIERS_FOUND' and v_p5[2]='CLEAN'
           and v_p5[3]='pd_hidden_metadata_identifier_found' and v_p5[4]='DISPATCHABLE'
           and v_p5[5]='ENFORCED_FAIL' and v_p5[6]='ENFORCED_PASS' and v_p5_n >= 4;
    defect_id:='PD-PRIV-005'; category:='PRIVACY';
    status := case when v_p5_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    -- v_p5_n is asserted (>= 4 recorded scans, or the verdicts below are about nothing) and NOT
    -- printed: it is an estate total that grows whenever another artefact is scanned, and a
    -- deliverable row that moves for a reason the case is not about does not reproduce.
    observed := format('dirty bytes -> %s, cleared bytes -> %s; dispatch %s / %s; BR-011 %s / %s',
                       v_p5[1], v_p5[2], v_p5[3], v_p5[4], v_p5[5], v_p5[6]);
    blocker := null; return next;
  end;

  -- PD-QUOTE-001. Supplier B naming supplier A's key, through the canonical write service, and
  -- supplier A rewriting their own key in the same shape. The object is SUPPLIER-scoped and goes
  -- through the same routine and the same owner_ref handling as a quotation; nothing here writes
  -- public.quotes, so no marketplace trigger fires.
  declare v_q1_a text; v_q1_b text; v_q1_msg text := ''; v_q1_ok boolean := false;
         v_q1_I text; v_q1_C text; v_q1_n bigint;
  begin
    begin
      select id::text into v_q1_a from public.leads order by id limit 1;
      select id::text into v_q1_b from public.leads order by id offset 1 limit 1;
      perform public.fn_phase_d_object_write(jsonb_build_object(
        'object_id','supplier_correction_case','business_key','pd-quote-001','owner_ref',v_q1_a,
        'created_by','pd_quote_001','state','open','payload',jsonb_build_object('n',1)));
      begin
        perform public.fn_phase_d_object_write(jsonb_build_object(
          'object_id','supplier_correction_case','business_key','pd-quote-001','owner_ref',v_q1_b,
          'created_by','pd_quote_001','state','in_progress','payload',jsonb_build_object('n',2)));
        v_q1_I := 'ACCEPTED';
      exception when others then
        v_q1_I := case when position('pd_object_cross_owner_write' in SQLERRM) > 0
                       then 'pd_object_cross_owner_write' else 'other:'||SQLSTATE end;
      end;
      begin
        perform public.fn_phase_d_object_write(jsonb_build_object(
          'object_id','supplier_correction_case','business_key','pd-quote-001','owner_ref',v_q1_a,
          'created_by','pd_quote_001','state','in_progress','payload',jsonb_build_object('n',3)));
        v_q1_C := 'ACCEPTED';
      exception when others then v_q1_C := 'REFUSED '||SQLSTATE; end;
      select count(*) into v_q1_n from public.phase_d_object_record
       where object_id='supplier_correction_case' and business_key='pd-quote-001'
         and owner_ref = v_q1_b;
      raise exception '%', 'PDQ1' || chr(31) || v_q1_I || '|' || v_q1_C || '|' || v_q1_n;
    exception when others then
      if position('PDQ1' in SQLERRM) = 1 then v_q1_msg := split_part(SQLERRM, chr(31), 2);
      else v_q1_msg := 'BRANCH_ERROR '||left(SQLERRM,110); end if;
    end;
    v_q1_ok := split_part(v_q1_msg,'|',1)='pd_object_cross_owner_write'
           and split_part(v_q1_msg,'|',2)='ACCEPTED'
           and split_part(v_q1_msg,'|',3)='0';
    defect_id:='PD-QUOTE-001'; category:='QUOTE';
    status := case when v_q1_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('supplier B writing supplier A''''s key -> %s; supplier A rewriting their own -> %s; rows left owned by B: %s',
                       split_part(v_q1_msg,'|',1), split_part(v_q1_msg,'|',2), split_part(v_q1_msg,'|',3));
    blocker := null; return next;
  end;

  -- PD-QUOTE-004. One customer, two comparisons differing in EXACTLY ONE respect -- the publication
  -- state -- read as the owner, as an unrelated customer, and as admin.
  declare v_q4_msg text := ''; v_q4_ok boolean := false; v_q4_cust uuid; v_q4_d bigint; v_q4_p bigint;
         v_q4_a1 text; v_q4_a2 text; v_q4_a3 text; v_q4_a4 text; v_q4_n bigint;
  begin
    begin
      v_q4_cust := '00000000-0000-4000-8000-0000000c0004'::uuid;
      insert into public.quote_comparisons(inquiry_id, customer_id, lang, quote_count, signature, analysis, publication_state)
      values (gen_random_uuid(), v_q4_cust, 'en', 2, 'PD-QUOTE-004-draft', '{}'::jsonb, 'DRAFT')
      returning id into v_q4_d;
      insert into public.quote_comparisons(inquiry_id, customer_id, lang, quote_count, signature, analysis, publication_state, published_at)
      values (gen_random_uuid(), v_q4_cust, 'en', 2, 'PD-QUOTE-004-published', '{}'::jsonb, 'PUBLISHED', now())
      returning id into v_q4_p;
      select coalesce(refusal_code,'VISIBLE') into v_q4_a1 from public.fn_phase_d_comparison_visible(v_q4_d::text, v_q4_cust::text, 'customer');
      select coalesce(refusal_code,'VISIBLE') into v_q4_a2 from public.fn_phase_d_comparison_visible(v_q4_p::text, v_q4_cust::text, 'customer');
      select coalesce(refusal_code,'VISIBLE') into v_q4_a3 from public.fn_phase_d_comparison_visible(v_q4_p::text, gen_random_uuid()::text, 'customer');
      select coalesce(refusal_code,'VISIBLE') into v_q4_a4 from public.fn_phase_d_comparison_visible(v_q4_d::text, v_q4_cust::text, 'admin');
      select count(*) into v_q4_n from public.fn_phase_d_rule_check('BR-019', jsonb_build_object(
        'comparison_id', v_q4_d::text, 'caller_customer_id', v_q4_cust::text)) rc where rc.ok;
      raise exception '%', 'PDQ4' || chr(31) || v_q4_a1 || '|' || v_q4_a2 || '|' || v_q4_a3 || '|' || v_q4_a4 || '|' || v_q4_n;
    exception when others then
      if position('PDQ4' in SQLERRM) = 1 then v_q4_msg := split_part(SQLERRM, chr(31), 2);
      else v_q4_msg := 'BRANCH_ERROR '||left(SQLERRM,110); end if;
    end;
    v_q4_ok := split_part(v_q4_msg,'|',1)='pd_comparison_unpublished'
           and split_part(v_q4_msg,'|',2)='VISIBLE'
           and split_part(v_q4_msg,'|',3)='pd_comparison_not_the_owner'
           and split_part(v_q4_msg,'|',4)='VISIBLE'
           and split_part(v_q4_msg,'|',5)='0';
    defect_id:='PD-QUOTE-004'; category:='QUOTE';
    status := case when v_q4_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('owner reading their own unpublished -> %s, published -> %s; unrelated customer on the published one -> %s; admin on the draft -> %s; BR-019 passes on the draft: %s',
                       split_part(v_q4_msg,'|',1), split_part(v_q4_msg,'|',2), split_part(v_q4_msg,'|',3),
                       split_part(v_q4_msg,'|',4), split_part(v_q4_msg,'|',5));
    blocker := null; return next;
  end;

  -- PD-QUOTE-005. A supplier revision, a normalisation beside it, a replay, and an attempt to
  -- overwrite the original -- all through the object store, none of it touching public.quotes.
  declare v_q5_msg text := ''; v_q5_ok boolean := false; v_q5_rec bigint; v_q5_sha text;
         v_q5_N text; v_q5_R text; v_q5_O text; v_q5_I text; v_q5_B text; v_q5_n1 bigint; v_q5_n2 bigint;
  begin
    begin
      perform public.fn_phase_d_object_write(jsonb_build_object(
        'object_id','quotation_revision','business_key','pd-quote-005','owner_ref','ZZ DEMO SUPPLIER',
        'created_by','pd_quote_005','state','submitted',
        'payload', jsonb_build_object('lead_time','30 days','payment_terms','50/50','scope','as tendered')));
      select o.record_id, encode(extensions.digest(convert_to(o.payload::text,'UTF8'),'sha256'),'hex')
        into v_q5_rec, v_q5_sha
        from public.phase_d_object_record o
       where o.object_id='quotation_revision' and o.business_key='pd-quote-005' and o.superseded_by is null
       order by o.record_id desc limit 1;

      -- the derived projection, referencing the original and restating none of it
      insert into public.phase_d_quote_normalisation
        (source_quote_ref, source_revision_ref, source_payload_sha256, schema_version, normalised,
         transformation, actor_role_id)
      values ('pd-quote-005','pd-quote-005', v_q5_sha, 'v1',
              jsonb_build_object('normalised_lead_time_days', 30),
              jsonb_build_object('source_fields', jsonb_build_array('lead_time'),
                                 'rule','"30 days" -> 30'), 'ceo');
      v_q5_N := 'ACCEPTED';
      select count(*) into v_q5_n1 from public.phase_d_quote_normalisation where source_revision_ref='pd-quote-005';

      -- replay: identical source, identical schema version -> no second row
      begin
        insert into public.phase_d_quote_normalisation
          (source_quote_ref, source_revision_ref, source_payload_sha256, schema_version, normalised,
           transformation, actor_role_id)
        values ('pd-quote-005','pd-quote-005', v_q5_sha, 'v1',
                jsonb_build_object('normalised_lead_time_days', 30),
                jsonb_build_object('source_fields', jsonb_build_array('lead_time')), 'ceo');
        v_q5_R := 'DUPLICATED';
      exception when unique_violation then v_q5_R := 'IDEMPOTENT_NO_DUPLICATE';
                when others then v_q5_R := 'other:'||SQLSTATE; end;
      select count(*) into v_q5_n2 from public.phase_d_quote_normalisation where source_revision_ref='pd-quote-005';

      -- a projection that restates a supplier-authored field is not a projection
      begin
        insert into public.phase_d_quote_normalisation
          (source_quote_ref, source_revision_ref, source_payload_sha256, schema_version, normalised,
           transformation, actor_role_id)
        values ('pd-quote-005','pd-quote-005', v_q5_sha, 'v2',
                jsonb_build_object('lead_time','7 days'),
                jsonb_build_object('source_fields', jsonb_build_array('lead_time')), 'ceo');
        v_q5_B := 'ACCEPTED';
      exception when others then
        v_q5_B := case when position('pd_normalisation_restates_original' in SQLERRM) > 0
                       then 'pd_normalisation_restates_original' else 'other:'||SQLSTATE end;
      end;

      -- the direct overwrite of the original
      perform set_config('kernel.maintenance_reason','PD-QUOTE-005: attempt the original overwrite', true);
      begin
        update public.phase_d_object_record set payload = jsonb_build_object('lead_time','7 days')
         where record_id = v_q5_rec;
        v_q5_O := 'ACCEPTED';
      exception when others then
        v_q5_O := case when position('pd_object_overwrite_refused' in SQLERRM) > 0
                       then 'pd_object_overwrite_refused' else 'other:'||SQLSTATE end;
      end;
      perform set_config('kernel.maintenance_reason','', true);

      select case when qi.intact then 'INTACT' else coalesce(qi.refusal_code,'NOT_INTACT') end into v_q5_I
        from public.fn_phase_d_quote_original_intact('pd-quote-005') qi;
      raise exception '%', 'PDQ5' || chr(31) || v_q5_N || '|' || v_q5_R || '|' || v_q5_B || '|' || v_q5_O || '|' || v_q5_I || '|' || v_q5_n1||'/'||v_q5_n2;
    exception when others then
      if position('PDQ5' in SQLERRM) = 1 then v_q5_msg := split_part(SQLERRM, chr(31), 2);
      else v_q5_msg := 'BRANCH_ERROR '||left(SQLERRM,110); end if;
    end;
    v_q5_ok := split_part(v_q5_msg,'|',1)='ACCEPTED'
           and split_part(v_q5_msg,'|',2)='IDEMPOTENT_NO_DUPLICATE'
           and split_part(v_q5_msg,'|',3)='pd_normalisation_restates_original'
           and split_part(v_q5_msg,'|',4)='pd_object_overwrite_refused'
           and split_part(v_q5_msg,'|',5)='INTACT'
           and split_part(split_part(v_q5_msg,'|',6),'/',1)=split_part(split_part(v_q5_msg,'|',6),'/',2);
    defect_id:='PD-QUOTE-005'; category:='QUOTE';
    status := case when v_q5_ok then 'IDEMPOTENT_NO_DUPLICATE' else 'NOT_REFUSED' end;
    observed := format('normalisation -> %s; replay -> %s (rows %s); restating an original field -> %s; direct overwrite -> %s; original %s',
                       split_part(v_q5_msg,'|',1), split_part(v_q5_msg,'|',2), split_part(v_q5_msg,'|',6),
                       split_part(v_q5_msg,'|',3), split_part(v_q5_msg,'|',4), split_part(v_q5_msg,'|',5));
    blocker := null; return next;
  end;

  -- ---- Remaining rows whose subject exists but whose injection needs a committed run ------------
  for v_key, v_msg in
    select * from (values
      ('PD-ZZ-LIST-TAIL','TAIL: not a defect and never emitted. Removing a row from this list must not strip the comma from its neighbour, so the list ends on a row nobody removes and the loop filters it out by name.')
    ) as t(a,b) where t.a <> 'PD-ZZ-LIST-TAIL'
  loop
    defect_id := v_key; category := split_part(v_msg, ':', 1); status := 'NOT_RUN';
    observed := null; blocker := v_msg;
    return next;
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_phase_d_step_context(p_step_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  sr public.phase_c_workflow_step_run%rowtype;
  v_val_txt text;  -- G02: the acceptance value read back before it becomes jsonb
  v_key_obj text;  -- G08: the object a context key names, from phase_d_context_key_object
  v_link    text;  -- G08: the column on this run's relation that reaches that object
  v_link_v  text;  -- G08: what that column holds
  v_scn_ref jsonb; -- G08: the canonical reference the scenario recorded for that object
  r  public.phase_c_workflow_run%rowtype;
  s  public.phase_b_workflow_step%rowtype;
  b  public.phase_d_handler_binding%rowtype;
  ec public.phase_d_step_effect%rowtype;
  v_keys   text[];
  v_k      text;
  v_val    jsonb;
  v_src    text;
  v_ctx    jsonb := '{}'::jsonb;
  v_prov   jsonb := '{}'::jsonb;
  v_unres  text[] := '{}';
  v_obj    text;
  v_boid   text;
  v_run_key text;
  v_rel    text;
  v_keycol text;
  v_owncol text;
  v_row_id text;
  v_row_own text;
  v_found  boolean := false;
  v_key_prefixed boolean := false;   -- E25
  v_sql    text;
  v_from   text;
  v_to     text;
  v_route  text;
  v_cmd    bigint;
  v_auth   jsonb;   -- K01
  v_src_ref   text;
  v_src_kind  text;
  v_src_class text;
  v_src_actor text;
  v_src_act   text;
  v_email     text;
  v_fx_val    jsonb;   -- F11
  v_fx_src    text;    -- F11
begin
  select * into sr from public.phase_c_workflow_step_run where step_run_id = p_step_run_id;
  if not found then
    raise exception 'fn_phase_d_step_context: no step run %', p_step_run_id using errcode = '23503';
  end if;
  select * into r  from public.phase_c_workflow_run    where run_id  = sr.run_id;
  select * into s  from public.phase_b_workflow_step   where step_id = sr.step_id;
  select * into b  from public.phase_d_handler_binding where step_id = sr.step_id;
  select * into ec from public.phase_d_step_effect     where step_id = sr.step_id;

  select coalesce(array_agg(distinct k), '{}') into v_keys from (
    select unnest(re.required_context) k from public.phase_d_rule_enforcement re
     where re.rule_id = any (coalesce(b.rule_ids,'{}'))
    union
    select unnest(gc.evidence_keys) k from public.phase_d_gate_contract gc
     where gc.gate_id = any (coalesce(b.gate_ids,'{}'))
    -- K03. THE PARENT OF THE RECORD THIS STEP WRITES. The list was the union of what the step's
    -- rules and gates ask for, and nothing else, so a key no rule happens to name was never
    -- resolved even where the estate could answer it. W16-S01 wrote a reveal payment that belonged
    -- to no quote for exactly that reason. The object's own frozen binding names its parent and the
    -- write map names the payload key that carries it; both are read here. A step that writes no
    -- business object adds nothing, and a key a rule already asks for is unchanged -- this is a
    -- distinct union.
    union
    select wm.column_map->>bb.parent_identity k
      from public.phase_d_business_object_binding bb
      join public.phase_d_object_write_map wm on wm.object_id = bb.object_id
     where bb.object_id = ec.effect_object_id
       and coalesce(btrim(bb.parent_identity),'') <> ''
       and wm.column_map ? bb.parent_identity
       and wm.column_map->>bb.parent_identity not in ('business_key','owner_ref','state')
    ) q(k);

  -- ---- the frozen state model ------------------------------------------------------------------
  v_from  := r.state;
  -- E12. THE RESOLVER NULLED A FACT THE GATE EXISTS TO JUDGE.
  --
  -- to_state is the step's own frozen declaration: phase_b_workflow_step.success_workflow_state.
  -- Until now this line also re-ran GATE-006's test on it, and blanked the value when the test
  -- failed. That is a different act from resolving, and it had two consequences.
  --
  -- First, it made the answer depend on WHEN the resolver was called rather than on what the
  -- registry says. fn_phase_d_dispatch_step runs inside fn_kernel_open_step, and a step opened out
  -- of a handoff is dispatched while its run is still in waiting_handoff -- the state it is
  -- leaving. The old guard therefore asked whether the run could go waiting_handoff ->
  -- waiting_handoff, which the frozen model rightly says it cannot, and nulled the key. Called a
  -- moment later, against the same step run, the same function resolved it. Measured 2026-08-20:
  -- W01-S04/S05/S06 record to_state in phase_d_dispatch.unresolved_keys, and a direct call for the
  -- same step runs resolves it to waiting_handoff.
  --
  -- Second, and worse, it turned a judgeable fact into an absent one. GATE-006 already tests the
  -- transition against public.phase_b_workflow_transition, and already holds the reasoned branch
  -- for the case where a step declares the state it is already in (55 of 257 steps do). With the
  -- key blanked, the gate could not reach either branch and reported "requires [to_state] and the
  -- call names none of it" -- an evidence-absence message standing in for a judgement the
  -- instrument was built to make.
  --
  -- The resolution is therefore the declaration, and the judgement stays with the gate. This is a
  -- REMOVAL: nothing new is asserted, and a transition the frozen model does not declare is still
  -- refused -- by GATE-006, which is the check that owns it.
  v_to    := nullif(btrim(coalesce(s.success_workflow_state,'')),'');
  -- D42. route_state IS NOT "the first declared transition, alphabetically". That is what this
  -- resolver did, and GATE-010 duly reported "route state approved; only a confirmed route carries
  -- dispatch authority" for an inquiry that had never been routed. Picking a plausible value out of
  -- the declared set is the placeholder defect wearing a schema. A route state exists when a route
  -- has been confirmed; until then the key is unresolved and GATE-010 refuses, which is the gate
  -- doing its job.
  v_route := null;

  -- ---- the arrival that caused this run, and how the register classifies it ---------------------
  select ti.source_system, 'trigger' into v_src_ref, v_src_kind
    from public.kernel_trigger_inbox ti where ti.run_id = sr.run_id order by ti.inbox_id desc limit 1;
  if v_src_ref is null and coalesce(btrim(coalesce(r.business_object_id,'')),'') <> '' then
    -- D39(2). The first step of a run dispatches INSIDE fn_kernel_workflow_start, before the inbox
    -- row is stamped with run_id. business_object_id is on both sides already, derived from the same
    -- object rule, so it is what links them at the only moment that matters.
    select ti.source_system, 'trigger' into v_src_ref, v_src_kind
      from public.kernel_trigger_inbox ti
     where ti.business_object_id = r.business_object_id
     order by ti.inbox_id desc limit 1;
  end if;
  if v_src_ref is null then
    select si.source_type, 'signal' into v_src_ref, v_src_kind
      from public.kernel_signal_inbox si
     where si.workflow_run_id = sr.run_id order by si.signal_id desc limit 1;
  end if;
  if v_src_ref is null then
    select tk.source_ref, tk.source_kind into v_src_ref, v_src_kind
      from public.phase_c_task tk where tk.run_id = sr.run_id order by tk.task_id limit 1;
  end if;
  -- D40. THE INBOX ROW IS NOT READABLE BY run_id OR business_object_id AT FIRST-STEP DISPATCH TIME.
  -- fn_kernel_trigger_submit inserts the inbox row, then calls fn_kernel_workflow_start passing
  -- source_ref = 'trigger_inbox:<inbox_id>', and stamps run_id and business_object_id onto that row
  -- only AFTER the call returns. The dispatch happens inside it, so both earlier matches were looking
  -- for columns the row does not carry yet. The inbox id IS in the source_ref the kernel already
  -- passes, and fn_kernel_workflow_start writes it onto the task before it opens the step — the one
  -- identifier available at the only moment that matters.
  if v_src_ref like 'trigger_inbox:%' then
    select ti.source_system, 'trigger' into v_src_ref, v_src_kind
      from public.kernel_trigger_inbox ti
     where ti.inbox_id = nullif(substr(v_src_ref, 15), '')::bigint;
  end if;
  if coalesce(btrim(coalesce(v_src_ref,'')),'') <> '' then
    select c.source_class, c.system_actor, c.current_activation
      into v_src_class, v_src_actor, v_src_act
      from public.phase_c_source_cutover c
     where c.source_component_id = v_src_ref limit 1;
  end if;

  -- ---- the run's own business object -----------------------------------------------------------
  v_obj := coalesce(nullif(btrim(coalesce(ec.effect_object_id,'')),''),
                    (select bo.object_id from public.phase_d_business_object_binding bo
                      where bo.governing_workflow_id = r.workflow_id limit 1));
  v_boid := nullif(btrim(coalesce(r.business_object_id,'')),'');
  -- THE RUN'S OWN PARTY, KEPT SEPARATELY. v_boid below is consumed by the STEP's object: where the
  -- step writes something other than what the run is about, the prefix does not match, the lookup
  -- fails and v_found is false. That is correct for the step's own subject and wrong for anything
  -- that belongs to the run as a whole. Measured 23 Aug 2026 on W09-S03: the run's
  -- business_object_id is 'supplier_account:37085' and the step's business object is
  -- supplier_capability on public.supplier_capabilities with row_found false, so the terms branch
  -- below had no anchor and fell through to the catalogue.
  v_run_key := case when v_boid like '%:%' then substr(v_boid, position(':' in v_boid) + 1) else null end;
  -- D39(1). The kernel writes the object rule out in full: 'inquiry:<uuid>'. Strip ONLY that
  -- object's own prefix; a blind split on ':' would corrupt an identifier that contains one.
  -- E25. WHETHER THE PREFIX MATCHED IS ITSELF A FACT, and the caller needs it. A run whose
  -- business_object_id is 'inquiry:<uuid>' names the object this step writes; one that reads
  -- 'outbox:195' or a probe label does not, and using the raw string as a business key would invent
  -- an identity for a record. Only a stripped key is a key.
  v_key_prefixed := (v_obj is not null and v_boid is not null and v_boid like (v_obj || ':%'));
  if v_key_prefixed then
    v_boid := substr(v_boid, length(v_obj) + 2);
  end if;
  if v_obj is not null and coalesce(v_boid,'') <> '' then
    select wm.target_relation, wm.key_column, wm.owner_column
      into v_rel, v_keycol, v_owncol
      from public.phase_d_object_write_map wm where wm.object_id = v_obj limit 1;
    if v_rel is not null and coalesce(btrim(v_keycol),'') <> ''
       and to_regclass(v_rel) is not null then
      begin
        v_sql := format('select %I::text, %s from %s where %I::text = $1 limit 1',
                        v_keycol,
                        case when coalesce(btrim(v_owncol),'') = '' then 'null::text'
                             else quote_ident(v_owncol) || '::text' end,
                        to_regclass(v_rel)::text, v_keycol);
        execute v_sql into v_row_id, v_row_own using v_boid;
        v_found := v_row_id is not null;
      exception when others then
        v_found := false;
      end;
    end if;
  end if;

  foreach v_k in array v_keys loop
    v_val := null; v_src := null;

    if v_k = 'from_state' then
      v_val := to_jsonb(v_from); v_src := 'phase_c_workflow_run.state';
    elsif v_k = 'to_state' then
      if v_to is not null then
        v_val := to_jsonb(v_to);
        v_src := 'phase_b_workflow_step.success_workflow_state, confirmed against phase_b_workflow_transition';
      end if;
    elsif v_k = 'route_state' then
      -- Resolved only from a route that actually exists. See the note above v_route.
      if v_route is not null then
        v_val := to_jsonb(v_route); v_src := 'the confirmed route for this inquiry';
      end if;

    elsif v_k in ('inquiry_id','supplier_id','quote_id','transaction_id','document_id',
                  'comparison_id','refund_id') then
      -- G08. THIS ANSWERED ALL SEVEN WITH THE RUN'S OWN ROW ID. See the file header: BR-015 was told
      -- a quote was a supplier, BR-020 that a comparison was a transaction, BR-013 that a document
      -- was an inquiry. Each key names an object, that object is recorded, and the answer must come
      -- from the object it names or not at all.
      select cko.object_id into v_key_obj
        from public.phase_d_context_key_object cko
       where cko.context_key = v_k and cko.key_role = 'IDENTIFIES';

      if v_found and v_key_obj is not null and v_key_obj = v_obj then
        -- The key names the object this run is about. The row id is the answer.
        v_val := to_jsonb(v_row_id);
        v_src := format('%s.%s, looked up by the run''s business_object_id', v_rel, v_keycol);

      elsif v_found and v_key_obj is not null then
        -- The key names a DIFFERENT object. Reach it from this run's own row, through a declared
        -- foreign key to that object's canonical relation where one exists, and otherwise through a
        -- column named exactly like the key. Both are read from the catalog; neither is listed here.
        select a.attname into v_link
          from pg_constraint con
          join lateral unnest(con.conkey) k(attnum) on true
          join pg_attribute a on a.attrelid = con.conrelid and a.attnum = k.attnum
         where con.contype = 'f'
           and con.conrelid = to_regclass(v_rel)
           and con.confrelid = (select to_regclass(bb.canonical_relation)
                                  from public.phase_d_business_object_binding bb
                                 where bb.object_id = v_key_obj)
         order by a.attname limit 1;
        if v_link is null then
          select a.attname into v_link from pg_attribute a
           where a.attrelid = to_regclass(v_rel) and a.attnum > 0 and not a.attisdropped
             and a.attname = v_k;
        end if;
        if v_link is not null then
          begin
            execute format('select %I::text from %s where %I::text = $1',
                           v_link, to_regclass(v_rel)::text, v_keycol)
              into v_link_v using v_row_id;
          exception when others then v_link_v := null; end;
          if coalesce(btrim(v_link_v),'') <> '' then
            v_val := to_jsonb(v_link_v);
            v_src := format('%s.%s of the run''s own row, which reaches %s', v_rel, v_link, v_key_obj);
          end if;
          v_link := null; v_link_v := null;
        end if;
      end if;
    elsif v_k = 'caller_customer_id' then
      -- G18. THE OWNER IS THE ANSWER ONLY WHEN THE OWNER IS A CUSTOMER.
      -- On a W14 run the business object is a quotation and its owner column is
      -- public.quotes.supplier_id, so this branch handed BR-019 a supplier and BR-019 refused,
      -- correctly, about the wrong party. Whether the owner column reaches the customer relation is
      -- read from the catalog, not assumed from the column's name.
      if v_found and v_row_own is not null and v_owncol is not null
         and exists (select 1
                       from pg_constraint con
                       join lateral unnest(con.conkey) k(attnum) on true
                       join pg_attribute a on a.attrelid = con.conrelid and a.attnum = k.attnum
                      where con.contype = 'f'
                        and con.conrelid = to_regclass(v_rel)
                        and a.attname = v_owncol
                        and con.confrelid = (select to_regclass(bb.canonical_relation)
                                               from public.phase_d_business_object_binding bb
                                              where bb.object_id = 'customer_account')) then
        v_val := to_jsonb(v_row_own);
        v_src := format('%s.%s of the run''s own object, which is a declared foreign key into the customer relation', v_rel, v_owncol);
      end if;

    elsif v_k = 'inquiry_owner' then
      -- D41. inquiry_owner IS A ROLE, NOT A CUSTOMER. BR-049 is the only consumer of this key —
      -- no gate declares it — and its predicate compares it to the literal role
      -- 'ceo'. Resolving it from inquiries.customer_id handed a rule about
      -- ACCOUNTABILITY a customer UUID, so it refused every inquiry the moment the owner started
      -- resolving at all. The frozen rule text is unambiguous: "Specialist and document handoffs do
      -- not transfer overall inquiry accountability away from RFQ Qualification Manager unless an
      -- explicit approved workflow says so."
      --
      -- The subject is therefore the role accountable for the INQUIRY, which is
      -- phase_c_workflow_run.accountable_role_id of the run that owns it. For a W05 run that is this
      -- run; for W06 and W07, which are the specialist workflows the rule is about, it is the W05
      -- run for the same inquiry, and where no such run exists the key stays unresolved rather than
      -- being answered with this run''s own role.
      --
      -- This is what makes the rule able to FAIL: it fails exactly when a run''s accountable role
      -- has drifted from the frozen registry''s, which is the drift BR-049 exists to catch.
      if r.workflow_id = 'W05' then
        v_val := to_jsonb(r.accountable_role_id);
        v_src := 'phase_c_workflow_run.accountable_role_id of this inquiry''s own run';
      elsif v_found then
        select to_jsonb(r2.accountable_role_id) into v_val
          from public.phase_c_workflow_run r2
         where r2.workflow_id = 'W05'
           and r2.business_object_id = ('inquiry:' || v_row_id)
         order by r2.run_id desc limit 1;
        v_src := 'phase_c_workflow_run.accountable_role_id of the W05 run that owns this inquiry';
        -- G09. AN INQUIRY NO RUN HAS CLAIMED HAS NOT DRIFTED FROM ANYTHING.
        -- Measured: W06-S01 and W07-S01 refused with "inquiry owner is (unstated)" because the
        -- inquiry exists and no W05 run does. The branch above still comes first, so an inquiry a
        -- run HAS claimed is answered by that run's actual role and BR-049 still refuses when it
        -- has drifted. Only the unclaimed case changes, and there the frozen registry's own
        -- accountable role for the workflow that owns the inquiry object is the answer -- read from
        -- public.phase_b_workflow, never named here.
      end if;
      -- G14. THE FALLBACK WAS INSIDE THE BRANCH THAT NEEDS THE RUN'S OWN ROW, AND W06 HAS NONE.
      -- W06's primary object is inquiry_route_set, whose fixture stage contributes a STATE rather
      -- than a key, so the run's business object never resolves and the branch above never ran.
      -- W06-S01 kept refusing with "inquiry owner is (unstated)" after G09 had supposedly answered
      -- it. The fallback belongs wherever nothing else has answered, which is here.
      if v_val is null then
        select to_jsonb(w2.accountable_role_id) into v_val
          from public.phase_b_workflow w2
         where w2.primary_object = 'inquiry' order by w2.workflow_id limit 1;
        v_src := 'phase_b_workflow.accountable_role_id of the workflow whose primary object is '
              || 'the inquiry -- no workflow run has claimed this inquiry, so accountability is '
              || 'where the frozen registry puts it and has not moved';
      end if;
    elsif v_k = 'monetary_state' then
      if v_found and v_rel like '%transactions' then
        select to_jsonb(t.fee_status) into v_val from public.transactions t
          where t.id::text = v_row_id limit 1;
        v_src := 'public.transactions.fee_status of the run''s own transaction';
      end if;

    elsif v_k = 'evidence_authority' then
      -- F13. THIS RESOLVED, AND RESOLVED TO SOMETHING THE RULE CANNOT RANK.
      --
      -- BR-029 is about RANK: lower-authority evidence may not silently overwrite higher, and the
      -- estate's ranking is public.mep_evidence_weight (alias, customer_text, document_extraction,
      -- scope_rule, structured_answer). This branch answered with the arrival CLASSIFICATION --
      -- "A NEW_WORK_REQUEST (system.task_engine) via dbtrigger:public.inquiries:trg_inquiry_received_a,
      -- activation ACTIVE" -- which is a true fact about how the run started and is not an evidence
      -- authority at all. Measured on every drive: 0 rows matched, so BR-029 refused for the whole
      -- estate, and it refused with a reason that read as though the authority were unranked rather
      -- than as though the resolver had answered a different question.
      --
      -- The correction is a REMOVAL plus a test: the classification is offered only if it actually
      -- appears in the ranking. When it does not, the key is UNRESOLVED, which is the honest state
      -- -- and which is what lets the Phase D fixture door supply a ranked authority, and what
      -- keeps BR-029 refusing in production where no such authority is named.
      if v_src_class is not null
         and exists (select 1 from public.mep_evidence_weight w
                      where w.weight_key = v_src_class or w.evidence_source = v_src_class
                         or w.source_authority = v_src_class) then
        v_val := to_jsonb(v_src_class);
        v_src := 'phase_c_source_cutover classification of the arrival that caused this run, confirmed present in the public.mep_evidence_weight ranking';
      elsif exists (select 1 from public.phase_d_object_record o
                     where o.object_id = 'document_extraction'
                       and o.payload->>'document_id' = coalesce(v_row_id,'')) then
        -- The run's own object carries a document extraction, and document_extraction IS a ranked
        -- evidence source. This is a read of what the run rests on, not a choice.
        v_val := to_jsonb('document_extraction'::text);
        v_src := 'public.mep_evidence_weight: the run''s own object carries a document extraction, which is a ranked evidence source';
      end if;

    elsif v_k = 'notify_email' then
      if v_found and v_row_own is not null then
        v_email := null;
        if v_owncol = 'customer_id' then
          select c.email into v_email from public.customers c where c.id::text = v_row_own limit 1;
        elsif v_owncol in ('supplier_id','lead_id') then
          select l.email into v_email from public.leads l where l.id::text = v_row_own limit 1;
        end if;
        if coalesce(btrim(coalesce(v_email,'')),'') <> '' then
          v_val := to_jsonb(v_email);
          v_src := format('the email of %s.%s, the owner of the run''s own object', v_rel, v_owncol);
        end if;
      end if;

    elsif v_k = 'evidence_refs' then
      -- E22. A CONDITION THE FIRST STEP OF A RUN COULD NEVER MEET.
      --
      -- This resolved evidence_refs from public.phase_d_effect_ledger for the run and nothing else.
      -- The FIRST step of a run has no predecessor, so it has no prior effect, so the key was
      -- unresolvable for it by construction — not sometimes, ever. BR-027 is bound to 59 steps and
      -- applies to 7 of the estate's first steps; six of those seven (the seventh is held by the
      -- capability boundary) were refused by a rule they had no way to satisfy. Measured 2026-08-20.
      --
      -- The fix is not to hand the key a placeholder. It is to notice that a first step DOES have
      -- evidence, and that the resolver was reading the wrong subject for it: what a first step
      -- rests on is THE ARRIVAL THAT OPENED THE RUN. That is a row — phase_c_workflow_run carries
      -- start_event, command_id and opened_at, and phase_c_source_cutover classifies the source
      -- component — so naming it is a read, not an invention.
      --
      -- THE ARRIVAL COUNTS ONLY FOR A STEP WITH NO PREDECESSOR, and that restriction is what keeps
      -- BR-027 able to fail. A later step must still show what the run has PRODUCED; if its
      -- predecessors produced nothing, it still gets nothing and BR-027 still refuses. Handing every
      -- call an automatic arrival reference would have turned a rule that refuses into a rule that
      -- cannot, which is the defect this file is fixing, in the other direction.
      select case when count(*) = 0 then null
                  else jsonb_agg(jsonb_build_object(
                         'effect_id', el.effect_id, 'step_id', el.step_id,
                         'effect_type', el.effect_type,
                         'result_reference', el.result_reference) order by el.effect_id) end
        into v_val
        from public.phase_d_effect_ledger el where el.run_id = sr.run_id;
      v_src := 'phase_d_effect_ledger for this run';

      if v_val is null
         and not exists (select 1 from public.phase_c_workflow_step_run pr
                          where pr.run_id = sr.run_id and pr.step_run_id < sr.step_run_id) then
        v_val := jsonb_build_array(jsonb_build_object(
          'kind',          'arrival',
          'run_id',        sr.run_id,
          'workflow_id',   r.workflow_id,
          'start_event',   nullif(btrim(coalesce(r.start_event,'')),''),
          'command_id',    r.command_id,
          'source_ref',    nullif(btrim(coalesce(v_src_ref,'')),''),
          'source_class',  v_src_class,
          'system_actor',  v_src_actor,
          'opened_at',     r.opened_at));
        v_src := 'the arrival that opened this run (phase_c_workflow_run.start_event/command_id '
              || 'plus its phase_c_source_cutover classification) — this step has no predecessor, '
              || 'so the arrival is the evidence it rests on';
      end if;

    elsif v_k = 'handoff_id' then
      -- D50. The handoff this step opens is a row of the frozen registry, not something a caller has
      -- to remember to pass. BR-008 was refusing for want of an identifier sitting in a table.
      select to_jsonb(hc.handoff_id) into v_val
        from public.phase_d_handoff_contract hc where hc.from_step_id = sr.step_id
       order by hc.handoff_id limit 1;
      v_src := 'phase_d_handoff_contract.handoff_id for the handoff this step opens';

    elsif v_k = 'sla_policy_id' then
      -- Likewise: the SLA policy of that handoff is recorded against it in the frozen registry.
      select to_jsonb(nullif(btrim(coalesce(h.sla_policy_id,'')),'')) into v_val
        from public.phase_b_handoff h where h.from_step_id = sr.step_id
       order by h.handoff_id limit 1;
      v_src := 'phase_b_handoff.sla_policy_id of the handoff this step opens';

    elsif v_k in ('packet','requested_action','source_version') then
      select case v_k
               when 'packet' then case when hc.packet_keys is null or cardinality(hc.packet_keys) = 0
                                       then null else to_jsonb(hc.packet_keys) end
               when 'requested_action' then to_jsonb(nullif(btrim(coalesce(hc.acceptance_criteria,'')),''))
               else to_jsonb(nullif(btrim(coalesce(hc.source_object_version_key,'')),'')) end
        into v_val
        from public.phase_d_handoff_contract hc where hc.from_step_id = sr.step_id limit 1;
      v_src := 'phase_d_handoff_contract for this step';

    elsif v_k = 'founder_authority_ref' then
      -- K01. GATE-005's frozen evidence is "Decision is within delegated authority OR founder
      -- approval exists", and this resolved only the second half, so a step whose run no founder
      -- instructed could never answer it. One resolver now answers both, from the founder's own
      -- frozen boundary register where no command instructed the run, and it reports the reference
      -- only when that reference is valid -- exists, current, and covering this workflow.
      v_auth := public.fn_phase_d_founder_authority(sr.run_id, sr.step_id);
      if coalesce((v_auth->>'valid')::boolean, false) then
        v_val := to_jsonb(v_auth->>'ref');
        v_src := v_auth->>'source';
      end if;

    elsif v_k = 'run_id' then
      -- E11. This function loads sr and r in its first ten lines and then declared run_id
      -- unresolved, which refused GATE-008 on every step in the estate for want of a number the
      -- same function was already holding.
      v_val := to_jsonb(sr.run_id);
      v_src := 'phase_c_workflow_step_run.run_id of this step run';

    elsif v_k = 'actor_role_id' then
      -- The role ACCOUNTABLE for this step run, read from the kernel's own row. Not the caller's
      -- claim about who they are: this function is given a step_run_id and nothing else, and a
      -- context resolver that took an identity from its caller would be answering the question it
      -- was asked to check.
      v_val := to_jsonb(nullif(btrim(coalesce(sr.accountable_role_id,'')),''));
      v_src := 'phase_c_workflow_step_run.accountable_role_id';

    elsif v_k = 'reviewer_role_id' then
      -- The INDEPENDENT reviewer the frozen binding declares, and only that. 45 of the 47 review
      -- steps name none, and for those this stays unresolved so GATE-004 and GATE-021 refuse —
      -- which is the gate working. Choosing a reviewer here would be fn_pick_reviewer returning the
      -- department head 182 times, one layer up.
      -- G02. THE REVIEWER WHO ACTUALLY REVIEWED, BEFORE THE ONE THE REGISTRY DECLARES.
      --
      -- This read only phase_d_handler_binding.independent_reviewer_role_id, which 229 of the 257
      -- steps leave blank, so every gate asking who reviewed something was answered "nobody" even
      -- after fn_kernel_review_decide had sealed a verdict and STAMPED THE REVIEWER on the task.
      -- fn_phase_d_recorded_review already reads that stamp and nothing consulted it here.
      --
      -- Order matters and this order is deliberate: the reviewer who actually reviewed outranks the
      -- reviewer a registry column names, because the gate's question is about the review that
      -- happened. Where no review has been recorded the declared reviewer still answers, and where
      -- neither exists the key stays unresolved and the gate refuses -- which is the gate working,
      -- and is what the previous comment here was protecting. Nothing chooses a reviewer: this
      -- resolver reports one or reports none, exactly as fn_pick_reviewer should have.
      v_val := to_jsonb(nullif(btrim(coalesce(
                 (public.fn_phase_d_recorded_review(p_step_run_id))->>'reviewer_role_id','')),''));
      if v_val is not null then
        v_src := 'phase_c_task.reviewer_role_id, stamped by fn_kernel_review_decide on the review '
              || 'actually recorded for this step run';
      else
        v_val := to_jsonb(nullif(btrim(coalesce(b.independent_reviewer_role_id,'')),''));
        v_src := 'phase_d_handler_binding.independent_reviewer_role_id, declared not chosen';
      end if;
      -- H03. A STEP THAT IS NOT A REVIEW IS ASKED ABOUT THE REVIEW THE RUN RECORDED. GATE-021 and
      -- GATE-026 apply from the first review step to the last step; at a publish step the reviewer
      -- is whoever reviewed earlier in this run. Read from the same task stamp, on an earlier step
      -- run of the same run, only where this step reviews nothing itself.
      if (v_val is null or v_val = 'null'::jsonb)
         and b.handler_class is distinct from 'REVIEW_HANDLER'
         and coalesce(btrim((select s3.independent_reviewer_role_id
                              from public.phase_b_workflow_step s3 where s3.step_id = sr.step_id)),'') = '' then
        select to_jsonb(nullif(btrim(coalesce(t2.reviewer_role_id,'')),'')) into v_val
          from public.phase_c_task t2
          join public.phase_c_workflow_step_run sr2
            on sr2.run_id = t2.run_id and sr2.step_id = t2.step_id
         where t2.run_id = sr.run_id
           and sr2.step_run_id < p_step_run_id
           and coalesce(btrim(t2.reviewer_role_id),'') <> ''
         order by sr2.step_run_id desc, t2.task_id desc
         limit 1;
        if v_val is not null then
          v_src := 'phase_c_task.reviewer_role_id of the most recent review fn_kernel_review_decide '
                || 'recorded on an earlier step run of this same run -- this step reviews nothing '
                || 'itself, and the gate asks about the review that happened';
        end if;
      end if;

    elsif v_k = 'step_id' then
      -- MENTIONED IN THIS FUNCTION AND NOT BRANCHED, which is why the first measurement of this
      -- defect missed it. sr.step_id appears in the return object at the bottom, so a grep for
      -- 'step_id' finds it and a reader concludes the key resolves. It did not. A mention is not a
      -- branch — the same lens that cost the 19 Aug audit its central premise, applied here to the
      -- very file that was measuring it.
      v_val := to_jsonb(sr.step_id);
      v_src := 'phase_c_workflow_step_run.step_id';

    elsif v_k = 'step_run_id' then
      v_val := to_jsonb(p_step_run_id);
      v_src := 'the step_run_id this function was called with';

    elsif v_k = 'acceptance_ref' then
      -- M01 (6 Sep 2026). THE ACCEPTANCE THIS RUN'S PARTY OWNS, BY ITS OWN BUSINESS KEY.
      -- BR-026 asks whether a certificate is preceded by a real acceptance RECORD, and its predicate
      -- checks acceptance_ref against public.phase_d_object_record.business_key. When a customer
      -- accepts the published terms through the product (kyc.accept_terms -> fn_customer_terms_accept)
      -- an APPEND_ONLY customer_terms_acceptance record is written owned by that customer. Read that
      -- record's business_key here, exactly as terms_version/terms_hash below read the pair it carries
      -- and for the same reason (G02, J05, L03): a key that names a record is answered from the
      -- record, never from a constant. A run whose party owns no acceptance resolves nothing here and
      -- falls through to the effect-ledger and scenario doors after the loop, where BR-026 still
      -- matches 0 rows and still refuses -- so the rule keeps its ability to fail.
      if coalesce(v_row_id, v_run_key) is not null then
        select o.business_key into v_val_txt
          from public.phase_d_object_record o
         where o.superseded_by is null
           and o.object_id in ('customer_terms_acceptance','supplier_terms_acceptance')
           and o.owner_ref in (v_row_id, v_run_key)
         order by (o.owner_ref = v_row_id) desc, o.record_id desc limit 1;
        if coalesce(btrim(v_val_txt),'') <> '' then
          v_val := to_jsonb(v_val_txt);
          v_src := 'the terms-acceptance record this run''s own business object owns, in '
                || 'public.phase_d_object_record.business_key -- the record BR-026 checks against';
        end if;
        v_val_txt := null;
      end if;

    elsif v_k in ('terms_version','terms_hash') then
      -- G02. A KEY THAT NAMES A RECORD WAS ANSWERED FROM A CONSTANT, AND THE CONSTANT WON.
      --
      -- BR-025 asks whether an acceptance references the exact displayed version AND hash, and it
      -- resolves the pair against public.legal_documents. Measured on W04 and W09: it refused with
      --
      --   "acceptance names version phase-d-fixture-terms-v1 at digest 5d31c13d1f0f, which matches
      --    0 row(s) in public.legal_documents whose displayed body hashes to exactly that digest"
      --
      -- Those two values are the COMMITTED CATALOGUE FIXTURES PDF-3104 and PDF-3105. Nothing was
      -- wrong with them; they are a real pair over a real fixture body. What was wrong is that they
      -- were the answer at all. The scenario factory reads the version and digest of the ACTUALLY
      -- PUBLISHED documents -- public.legal_documents customer-terms v3 and supplier-agreement v5 --
      -- and writes them onto the acceptance record it creates. Both keys then fell through every
      -- branch of this resolver to the fixture door, which answered from the catalogue, and the
      -- catalogue value shadowed the record the scenario had just written. That is D9g's "a
      -- generated fixture beat the real reference", one layer up, and F47's "a key that names an
      -- object is answered from that object's reference" stated for a third time.
      --
      -- THE ACCEPTANCE RECORD IS FOUND BY WHAT IT CARRIES, NOT BY WHAT IT IS CALLED. The record
      -- sought is the live object record owned by this run's own business object that carries both
      -- terms keys -- no object name, no naming convention, no workflow list. A run whose object
      -- row was not found, or that owns no acceptance, resolves nothing here and falls through to
      -- the catalogue exactly as before, where BR-025 still matches 0 rows and still refuses. The
      -- rule keeps its ability to fail, and it now also has a way to pass for a true reason.
      -- J05. AND THE ACCEPTANCE BELONGS TO THE RUN'S PARTY, NOT TO THE STEP'S SUBJECT. The block
      -- above anchored on v_row_id, which is the row the STEP is about. Measured on W09-S03, S05
      -- and S06: the run is about supplier_account 37085 and the step is about a
      -- supplier_capability that does not exist yet, so v_found was false, this branch never ran,
      -- and BR-025 was answered from catalogue fixtures PDF-3104/PDF-3105 --
      -- "acceptance names version phase-d-fixture-terms-v1 at digest 5d31c13d1f0f, which matches 0
      -- row(s) in public.legal_documents". The acceptance the scenario actually wrote names
      -- supplier-agreement v5, owned by 37085, and it was one join away the whole time.
      --
      -- A terms acceptance is a fact about the PARTY the run concerns; no step in a workflow makes
      -- it a fact about that step's own subject. So the step's subject is tried first, and the
      -- run's own party second. A run whose party owns no acceptance still resolves nothing and
      -- BR-025 still matches 0 rows and still refuses: the rule keeps its ability to fail.
      if coalesce(v_row_id, v_run_key) is not null then
        select o.payload ->> v_k into v_val_txt
          from public.phase_d_object_record o
         where o.superseded_by is null
           and o.payload ? 'terms_version' and o.payload ? 'terms_hash'
           and o.owner_ref in (v_row_id, v_run_key)
         order by (o.owner_ref = v_row_id) desc, o.record_id desc limit 1;
        if coalesce(btrim(v_val_txt),'') <> '' then
          v_val := to_jsonb(v_val_txt);
          v_src := 'the terms-acceptance record this run''s own business object owns, in '
                || 'public.phase_d_object_record -- the pair the acceptance actually names';
        end if;
        v_val_txt := null;
      end if;
      -- L03. AND AT THE STEP THAT RECORDS THE ACCEPTANCE THERE IS NOTHING TO FIND YET.
      -- W09-S06 is the only step in the estate whose declared effect object is a terms acceptance.
      -- Asked to withhold the object the workflow under test produces -- which is what a harness
      -- that does not answer its own question must do -- no acceptance record exists at S06, both
      -- keys fell to the catalogue door, and BR-025 refused with "matches 0 row(s) in
      -- public.legal_documents" for fixture PDF-3104/PDF-3105: a version string and a digest over
      -- a fixture terms body that is not a published document and never can be one.
      -- An acceptance step accepts THE CURRENTLY DISPLAYED DOCUMENT. Which document that is, for
      -- which acceptance object, is registered once in public.phase_d_acceptance_document and read
      -- from public.legal_documents here -- the same relation BR-025 judges against, so the rule
      -- keeps its ability to fail: a step that produces no registered acceptance resolves nothing
      -- here and falls through to the catalogue exactly as before.
      if coalesce(btrim(coalesce(v_val #>> '{}','')),'') = '' then
        select case when v_k = 'terms_version' then d.version
                    else encode(sha256(convert_to(coalesce(d.body_html,''),'UTF8')),'hex') end
          into v_val_txt
          from public.phase_d_step_effect x
          join public.phase_d_acceptance_document a on a.object_id = x.effect_object_id
          join public.legal_documents d on d.slug = a.document_slug
         where x.step_id = sr.step_id
         order by d.version desc limit 1;
        if coalesce(btrim(v_val_txt),'') <> '' then
          v_val := to_jsonb(v_val_txt);
          v_src := 'public.legal_documents — the currently published document this step''s own '
                || 'acceptance object accepts, per public.phase_d_acceptance_document';
        end if;
        v_val_txt := null;
      end if;

    elsif v_k = 'source_ref' then
      -- The arrival that caused this run, already computed into v_src_ref from kernel_trigger_inbox
      -- at the top of this function. Unresolved when no arrival is recorded, which is a fact about
      -- the run rather than a gap in this resolver.
      v_val := to_jsonb(nullif(btrim(coalesce(v_src_ref,'')),''));
      v_src := 'kernel_trigger_inbox.source_system for this run';

    else
      -- 40 of the 71 declared context keys still land here, and that is correct: artifact_sha256,
      -- terms_hash, legal_review_ref, denominator, formula, outcome_metric and the rest are facts a
      -- CALLER produces at runtime, not facts this estate holds. They stay unresolved and their
      -- rules and gates refuse, which is the contract working.
      -- exception_authority_ref is here on purpose too: BR-043 applies only when the call names a
      -- policy exception, and inventing an authority reference would be the placeholder defect the
      -- D42 comment above already refused once for route_state.
      v_val := null; v_src := null;
    end if;


    -- G08. THE SCENARIO-REFERENCE DOOR, in front of the catalogue and behind every real source.
    --
    -- public.quote_comparisons carries no transaction column and public.documents relates to its
    -- inquiry through a polymorphic (ref_table, ref_id) pair, so no derivation from the schema can
    -- reach W15's transaction_id or W07's inquiry_id from the run's own row. The scenario created
    -- both objects and recorded the canonical reference of each. This answers from THAT -- a row the
    -- scenario actually wrote through fn_phase_d_object_write -- rather than from the committed
    -- constant the fixture door below would otherwise supply.
    --
    -- It returns nothing unless fn_phase_d_fixture_context() verifies an hmac over the current txid
    -- keyed by a secret no role can SELECT. In production this block resolves nothing at all.
    -- K07. THE OBJECT THIS RUN ALREADY CREATED, before any fixture is consulted.
    --
    -- A key that names an object was answered from the run's own row, from a declared foreign key
    -- on it, or -- fixture context only -- from the canonical reference the SCENARIO recorded.
    -- Nothing answered "the object THIS RUN produced at an earlier step", so W17-S07 asked for the
    -- refund_id of a refund_dispute_case that W17-S01 had created six steps earlier and was told
    -- there was none. public.phase_d_effect_ledger holds it: run_id, effect_object_id and the
    -- canonical result_reference fn_phase_d_object_write returned. This is not a fixture and it runs
    -- in production; it is asked after every source that reads the run's own row, and before the
    -- scenario record, because a fact this run produced outranks one a scenario planted.
    if (v_val is null or v_val = 'null'::jsonb
        or (jsonb_typeof(v_val) = 'string' and btrim(coalesce(v_val #>> '{}','')) = '')) then
      select cko.object_id into v_key_obj
        from public.phase_d_context_key_object cko
       where cko.context_key = v_k and cko.key_role = 'IDENTIFIES';
      if v_key_obj is not null then
        select nullif(btrim(substring(el.result_reference from position('=' in el.result_reference) + 1)),'')
          into v_link_v
          from public.phase_d_effect_ledger el
          join public.phase_d_business_object_binding bb on bb.object_id = el.effect_object_id
         where el.run_id = sr.run_id
           and el.effect_object_id = v_key_obj
           -- AN EFFECT NAMED FOR AN OBJECT IS NOT ALWAYS A REFERENCE TO ONE. phase_d_effect_ledger
           -- records effect_object_id from the step's DECLARED object, so a REVIEW_VERDICT step of
           -- W15 carries effect_object_id quotation_comparison and result_reference
           -- public.review_chain:id=15748 -- the identity of the review, not of the comparison.
           -- Taking it made GATE-018 judge a review row as a comparison and refuse W15-S05 for
           -- 'comparison 15748 does NOT belong to the calling customer', which was true and was
           -- about the wrong row. Only a reference into the object's OWN canonical relation is an
           -- identity of that object.
           and el.effect_relation = bb.canonical_relation
           and coalesce(btrim(el.result_reference),'') <> ''
           and position('=' in el.result_reference) > 0
         order by el.effect_id desc limit 1;
        if v_link_v is not null then
          v_ctx  := v_ctx  || jsonb_build_object(v_k, to_jsonb(v_link_v));
          v_prov := v_prov || jsonb_build_object(v_k,
            format('the canonical reference of the %s this run itself created, read from '
                || 'public.phase_d_effect_ledger.result_reference', v_key_obj));
          v_link_v := null; v_key_obj := null;
          continue;
        end if;
      end if;
      v_key_obj := null;
    end if;

    if (v_val is null or v_val = 'null'::jsonb
        or (jsonb_typeof(v_val) = 'string' and btrim(coalesce(v_val #>> '{}','')) = ''))
       and public.fn_phase_d_fixture_context() is not null then
      select cko.object_id into v_key_obj
        from public.phase_d_context_key_object cko
       where cko.context_key = v_k and cko.key_role = 'IDENTIFIES';
      if v_key_obj is not null then
        select sc.canonical_ref into v_scn_ref
          from public.phase_d_scenario_record sc
         where sc.fixture_run_id = public.fn_phase_d_fixture_context()
           and sc.object_id = v_key_obj
         order by sc.scenario_record_id desc limit 1;
        if v_scn_ref is not null
           and coalesce(btrim(v_scn_ref->>'canonical_identity'),'') <> '' then
          v_ctx  := v_ctx  || jsonb_build_object(v_k, to_jsonb(v_scn_ref->>'canonical_identity'));
          v_prov := v_prov || jsonb_build_object(v_k,
            format('the canonical reference the scenario recorded for %s in '
                || 'public.phase_d_scenario_record -- a row this scenario created through '
                || 'fn_phase_d_object_write, not a committed constant', v_key_obj));
          v_scn_ref := null; v_key_obj := null;
          continue;
        end if;
        v_scn_ref := null;
      end if;
      v_key_obj := null;
    end if;

    -- F11. THE FIXTURE DOOR, AND ONLY AFTER EVERY REAL SOURCE HAS BEEN TRIED.
    --
    -- The founder's section B: "A deterministic handler must not invent business content. The
    -- scenario catalogue supplies explicit test values... The handler receives the fixture as
    -- input. The handler must not generate the fixture itself."
    --
    -- This is where the fixture becomes an input. It runs in the RESOLVER, which is called by
    -- fn_phase_d_dispatch_step before fn_phase_d_handler_execute is entered, so the handler is
    -- handed a value and never reaches for one. And it runs LAST: a key a real row can answer is
    -- answered by that row, and the fixture never shadows a fact.
    --
    -- fn_phase_d_fixture_input returns NO ROW unless fn_phase_d_fixture_context() verifies an hmac
    -- over the current txid keyed by a secret no role can read. In production there is no such
    -- context, so this block resolves nothing, the key stays unresolved, and its rule or gate
    -- refuses exactly as it did before this file existed.
    if v_val is null or v_val = 'null'::jsonb
       or (jsonb_typeof(v_val) = 'string' and btrim(coalesce(v_val #>> '{}','')) = '') then
      select fi.value, fi.provenance || format(' [fixture %s v%s %s]', fi.fixture_id,
                                               fi.fixture_version, left(fi.checksum, 12))
        into v_fx_val, v_fx_src
        from public.fn_phase_d_fixture_input(p_step_run_id, 'CONTEXT_KEY', v_k) fi;
      if v_fx_val is not null then
        v_ctx := v_ctx || jsonb_build_object(v_k, v_fx_val);
        v_prov := v_prov || jsonb_build_object(v_k, v_fx_src);
        v_fx_val := null; v_fx_src := null;
        continue;
      end if;
    end if;
    if v_val is null or v_val = 'null'::jsonb
       or (jsonb_typeof(v_val) = 'string' and btrim(coalesce(v_val #>> '{}','')) = '') then
      v_unres := v_unres || v_k;
    else
      v_ctx  := v_ctx  || jsonb_build_object(v_k, v_val);
      v_prov := v_prov || jsonb_build_object(v_k, v_src);
    end if;
  end loop;

  return jsonb_build_object(
    'step_run_id', p_step_run_id, 'step_id', sr.step_id,
    'declared_keys', to_jsonb(v_keys),
    'context', v_ctx, 'provenance', v_prov, 'unresolved', to_jsonb(v_unres),
    'arrival', jsonb_build_object('source_ref', v_src_ref, 'source_kind', v_src_kind,
                                  'source_class', v_src_class, 'activation', v_src_act),
    'business_object', jsonb_build_object(
      'object_id', v_obj, 'object_key', v_boid, 'relation', v_rel, 'key_column', v_keycol,
      'owner_column', v_owncol, 'row_found', v_found,
      -- E25. The two facts fn_phase_d_effect_produce demands of its caller, reported here because
      -- this is the routine that already resolved them and the dispatch had no way to know them.
      'key_is_prefixed', v_key_prefixed,
      'row_owner_ref', v_row_own,
      'ownership_scope', (select ob.ownership_scope
                            from public.phase_d_business_object_binding ob
                           where ob.object_id = v_obj)));
end
$function$;

CREATE OR REPLACE FUNCTION public.fn_pick_reviewer(p_dept_key text, p_author text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_head text; v_ok boolean; v_delegate text; v_basis text;
        v_head_tier text; v_head_score numeric; v_score numeric; v_up text;
begin
  -- THE AUTHOR ARRIVES UNDER WHATEVER NAME THE CALLER HAD (14 Aug 2026).
  -- Every comparison below is a raw string test - p_author = v_head, and three
  -- "a.agent_key is distinct from p_author" filters. All ten department heads carry aliases, so
  -- an author passed as 'finance_ai', 'marketplace_director' or 'CEO AI' was not equal to 'ceo',
  -- 'procurement' or 'ceo', the guard did not fire, and this function returned the author as its
  -- own reviewer. Measured on production before this line: 10 of 10 departments.
  -- Resolving once here fixes every comparison at the same time, because they all read p_author.
  p_author := coalesce(public.fn_org_agent_resolve(p_author), p_author);

  select lead_agent into v_head from org_departments where dept_key = p_dept_key;

  if v_head is null then
    return jsonb_build_object('reviewer', null, 'available', false,
      'basis', 'no lead_agent recorded for department ' || p_dept_key);
  end if;

  -- THE AUTHOR IS THE HEAD. Measured 14 Aug 2026: 285 of 1,882 review_chain rows had
  -- author_agent = reviewer_agent and 182 of those were approvals, because this function was only
  -- ever told the department and answered with its head. When the head wrote the work, review
  -- climbs: first to an independent reviewer inside the same department, then to the head's own
  -- manager. It never returns the author.
  if p_author is not null and p_author = v_head then
    select a.agent_key into v_delegate
      from org_agents a
      join org_role r on r.runtime_agent_key = a.agent_key and r.status = 'active'
     where a.department = p_dept_key and a.agent_key <> p_author
       and r.runtime_mode = 'independent_reviewer'
       and a.active and a.available and (a.unavailable_until is null or a.unavailable_until < current_date)
     order by a.agent_key limit 1;

    if v_delegate is not null then
      return jsonb_build_object('reviewer', v_delegate, 'available', true, 'delegated_from', v_head,
        'basis', 'the department head authored this work; review routed to the department''s '
                 || 'independent reviewer, which never approves its own output');
    end if;

    select m.agent_key into v_up
      from org_agents o join org_agents m on m.agent_key = o.manager_key and m.active
     where o.agent_key = v_head
       and m.available and (m.unavailable_until is null or m.unavailable_until < current_date);

    if v_up is not null and v_up <> p_author then
      return jsonb_build_object('reviewer', v_up, 'available', true, 'delegated_from', v_head,
        'basis', 'the department head authored this work and the department has no independent '
                 || 'reviewer available; review escalated one level up the reporting chain');
    end if;

    return jsonb_build_object('reviewer', null, 'available', false, 'delegated_from', v_head,
      'basis', 'the department head authored this work and no independent reviewer or manager is '
               || 'available - escalate rather than approve it');
  end if;

  select (a.active and a.available and (a.unavailable_until is null or a.unavailable_until < current_date))
    into v_ok from org_agents a where a.agent_key = v_head;

  select p.tier, p.score into v_head_tier, v_head_score
    from agent_reputation p where p.agent_key = v_head;

  if coalesce(v_ok, false) then
    if coalesce(v_head_tier, '') = 'probation' then
      select a.agent_key, p.score into v_delegate, v_score
        from org_agents a
        join agent_reputation p on p.agent_key = a.agent_key
       where a.department = p_dept_key and a.agent_key <> v_head
         and a.agent_key is distinct from p_author
         and a.active and a.available and (a.unavailable_until is null or a.unavailable_until < current_date)
         and p.tier <> 'probation' and p.score > coalesce(v_head_score, 0)
       order by p.score desc, a.agent_key
       limit 1;

      if v_delegate is not null then
        return jsonb_build_object('reviewer', v_delegate, 'available', true, 'delegated_from', v_head,
          'basis', 'department head ' || v_head || ' is on the probation reputation tier ('
                   || coalesce(v_head_score::text, '?') || '); review routed to the highest-scoring '
                   || 'available employee in ' || p_dept_key || ' (' || coalesce(v_score::text, '?') || ')');
      end if;
    end if;

    return jsonb_build_object('reviewer', v_head, 'available', true, 'delegated_from', null,
      'basis', 'department head (reputation ' || coalesce(v_head_score::text, 'unscored')
               || ', tier ' || coalesce(v_head_tier, 'unscored') || ')');
  end if;

  select d.delegate_to, d.basis into v_delegate, v_basis
  from delegation_rule d
  join org_agents a on a.agent_key = d.delegate_to
  where d.active and d.dept_key = p_dept_key and d.when_agent = v_head
    and a.agent_key is distinct from p_author
    and a.active and a.available and (a.unavailable_until is null or a.unavailable_until < current_date)
  order by d.rank limit 1;

  if v_delegate is null then
    select a.agent_key,
           'highest-scoring available employee in ' || p_dept_key
             || ' (reputation ' || coalesce(p.score::text, 'unscored') || ')'
      into v_delegate, v_basis
    from org_agents a
    left join agent_reputation p on p.agent_key = a.agent_key
    where a.department = p_dept_key and a.agent_key <> v_head
      and a.agent_key is distinct from p_author
      and a.active and a.available and (a.unavailable_until is null or a.unavailable_until < current_date)
      and coalesce(p.tier, 'standard') <> 'probation'
    order by p.score desc nulls last, fn_seniority_rank(a.seniority), a.agent_key
    limit 1;
  end if;

  if v_delegate is null then
    return jsonb_build_object('reviewer', null, 'available', false, 'delegated_from', v_head,
      'basis', 'department head unavailable and no delegate available - escalate');
  end if;

  return jsonb_build_object('reviewer', v_delegate, 'available', true,
    'delegated_from', v_head, 'basis', coalesce(v_basis, 'delegation'));
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_refund_ladder_sweep()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t record; st jsonb; sup record; cust record;
  v_window int; v_chase int; v_agent text; v_dept text;
  v_subject text; v_body text; v_amounts jsonb; v_req jsonb; v_refund_id bigint; v_task bigint;
  v_chase_at timestamptz; v_final_at timestamptz; v_fee numeric;
  n_seen int := 0; n_chased int := 0; n_final int := 0; v_ids jsonb := '[]'::jsonb;
begin
  select refund_window_working_days, chase_after_working_days into v_window, v_chase
    from pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3);

  -- THE OWNER of the chase is the existing employee who owns supplier follow-up: the Customer Success
  -- Director (org_role customer_success_director, runtime agent 'followup'; workflow_step refund #3/#4
  -- already names this role). Never a new agent (founder, 6 Sep 2026).
  select r.runtime_agent_key, r.primary_department_id into v_agent, v_dept
    from org_role r where r.role_id = 'customer_support' and r.status = 'active';
  v_agent := coalesce(v_agent, 'followup'); v_dept := coalesce(v_dept, 'customer_experience');

  for t in
    select x.* from transactions x
     where x.revealed_at is not null and coalesce(x.reveal_fee, 0) > 0
       and coalesce(x.refund_status, '') not in ('approved','refunded','processing','succeeded','rejected','cancelled','failed')
       and x.revealed_at > now() - interval '120 days'
     order by x.revealed_at
  loop
    n_seen := n_seen + 1;
    st := public.fn_refund_state(t.id);
    continue when st ? 'error' or coalesce((st->>'supplier_responded')::boolean, false);
    continue when st->>'state' not in ('chase_due', 'final_call_due');

    select company_name, coalesce(claimed_by, email) as email into sup from leads where id = t.supplier_id;
    select email, full_name into cust from customers where id = t.customer_id;
    v_chase_at := (st->>'chase_due_at')::timestamptz;
    v_final_at := (st->>'founder_call_due_at')::timestamptz;
    v_fee      := round(coalesce(t.reveal_fee, 0), 2);

    -- DAY 3: the chase. One email to the supplier, customer cc'd (fn_wa_fanout adds the WhatsApp copy
    -- when the supplier opted in), and one task on the owning employee. fn_refund_state reads the
    -- email back as chased_at, so a second tick cannot chase twice.
    if st->>'state' = 'chase_due' then
      v_subject := 'Action needed: a customer is waiting for your response — QuotesDone reveal #' || left(t.id::text, 8);
      v_body :=
        'Hello ' || coalesce(sup.company_name, '') || ',' || chr(10) || chr(10) ||
        'A customer paid to reveal your contact details on QuotesDone on ' ||
          to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY') ||
          ' and has not heard from you. ' || v_chase::text || ' working days have passed. The customer is copied on this email so you can reply to all and pick it up here.' || chr(10) || chr(10) ||
        'Under the Supplier Agreement you must respond within ' || v_window::text || ' working days of the reveal, that is by ' ||
          to_char(v_final_at at time zone 'Asia/Dubai', 'DD Mon YYYY') ||
          '. If we have not seen a response by then, the case goes to our founder for a final call and the customer''s reveal fee is refunded. ' ||
        'Under the supplier terms that refund is then recovered from your account: the reveal fee (AED ' || v_fee::text ||
          '), an administrative fee of AED 250 and interest at 9% per annum until it is settled, and matching is paused until it is paid.' || chr(10) || chr(10) ||
        'If you have already been in touch with this customer, reply here and we will close this off.' || chr(10) || chr(10) ||
        'QuotesDone — Customer Success';
      insert into notifications(type, kind, to_email, cc_emails, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status)
      values ('supplier_no_response_chase', 'refund_ladder_chase', sup.email,
              array_remove(array[cust.email], null), 'supplier', t.supplier_id, t.inquiry_id, t.quote_id,
              'email', v_subject, v_body, 'queued');
      insert into org_tasks(dept_key, title, detail, status, tier, needs_founder, decided_by,
                            action_class, assigned_agent, priority, result)
      values (v_dept,
              left('Chase ' || coalesce(sup.company_name, 'supplier #' || t.supplier_id::text) || ': no response ' ||
                   v_chase::text || ' working days after a paid reveal', 200),
              'Reveal #' || t.id::text || ' (inquiry ' || coalesce(t.inquiry_id::text, '?') || '). The customer paid AED ' || v_fee::text ||
                ' on ' || to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY') ||
                ' and the supplier has not responded. The chase email has been queued to ' || coalesce(sup.email, '(no email)') ||
                ' with the customer copied. Reach the supplier by every channel on file today. If they respond, record it ' ||
                '(supplier_ack_at or a portal message) so the case closes. If not, on ' ||
                to_char(v_final_at at time zone 'Asia/Dubai', 'DD Mon YYYY') ||
                ' the sweep files the refund and the founder makes the final call.',
              'assigned', 'advisory', false, 'fn_refund_ladder_sweep', 'routine_operational_decision', v_agent, 2,
              jsonb_build_object('refund_ladder', jsonb_build_object(
                'transaction_id', t.id, 'inquiry_id', t.inquiry_id, 'supplier_id', t.supplier_id,
                'step', 'chase', 'chase_due_at', v_chase_at, 'founder_call_due_at', v_final_at)))
      returning id into v_task;
      n_chased := n_chased + 1;
      v_ids := v_ids || jsonb_build_object('transaction_id', t.id, 'step', 'chase', 'task_id', v_task);
    end if;

    -- DAY 5: the founder's final call. The refund is FILED through the one existing door
    -- (fn_refund_request -> refunds 'requested', founder-gated by fn_refund_decide and the z00/z05
    -- guards) and he is notified with the facts. founder_alerts.dedupe_key is the idempotency record.
    if st->>'state' = 'final_call_due' then
      v_amounts := public.fn_refund_amount_aed(t.reveal_fee, t.revealed_at, now());
      if not exists (select 1 from refunds r where r.transaction_id = t.id) then
        v_req := public.fn_refund_request(
          round(t.reveal_fee * 100)::bigint, 'supplier_unresponsive', 'refund_ladder_sweep',
          t.inquiry_id, t.customer_id, t.supplier_id, t.quote_id, t.payment_ref, null,
          'Day ' || v_window::text || ' of the refund ladder: the supplier responded neither to the customer nor to the day-' ||
            v_chase::text || ' chase. Filed by the deterministic ladder sweep for the founder''s final call.',
          t.id);
      end if;
      select r.id into v_refund_id from refunds r where r.transaction_id = t.id order by r.id desc limit 1;

      perform public.fn_notify_founder(
        p_event => 'Refund final call: ' || coalesce(sup.company_name, 'supplier #' || t.supplier_id::text) ||
          ' silent for ' || v_window::text || ' working days on reveal #' || left(t.id::text, 8) || ' (AED ' || v_fee::text || ')',
        p_detail => 'Day ' || v_window::text || ' of the refund ladder. The supplier has not responded to the customer, to the day-' || v_chase::text ||
          ' chase' || case when (st->>'chased_at') is not null then ' sent ' || to_char((st->>'chased_at')::timestamptz at time zone 'Asia/Dubai', 'DD Mon YYYY') else ' (chase not recorded)' end ||
          case when t.customer_notified_at is not null then ', or to the customer''s formal notice of ' || to_char(t.customer_notified_at at time zone 'Asia/Dubai', 'DD Mon YYYY') else '' end || '.' || chr(10) || chr(10) ||
        'SUPPLIER: ' || coalesce(sup.company_name, '#' || t.supplier_id::text) || ' · ' || coalesce(sup.email, '(no email)') || ' · ' ||
          coalesce((select coalesce(nullif(btrim(l.whatsapp), ''), l.phone_e164, l.phone) from leads l where l.id = t.supplier_id), '(no phone)') || chr(10) ||
        'CUSTOMER: ' || coalesce(cust.full_name, '') || ' · ' || coalesce(cust.email, '') || chr(10) ||
        'REVEAL: transaction ' || t.id::text || ' · inquiry ' || coalesce(t.inquiry_id::text, '?') || ' · quotation AED ' || coalesce(t.quote_amount::text, '?') ||
          ' · reveal fee AED ' || v_fee::text || ' paid ' || to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || chr(10) ||
        'REFUND REQUEST: #' || coalesce(v_refund_id::text, '?') || ' is in your queue (status requested).' || chr(10) ||
        'AMOUNTS (fn_refund_amount_aed): customer refund AED ' || (v_amounts->>'customer_refund_aed') || ' in full; supplier charge AED ' ||
          (v_amounts->>'supplier_charge_aed') || ' = fee ' || (v_amounts->>'paid_aed') || ' + admin fee AED ' || (v_amounts->>'admin_fee_aed') ||
          ' + ' || (v_amounts->>'interest_pct_pa') || '% p.a. interest (AED ' || (v_amounts->>'interest_aed') || ' for ' || (v_amounts->>'interest_days') || ' day(s) so far).' || chr(10) || chr(10) ||
        'YOUR CALL: phone the supplier. If there is still no response, approve refund #' || coalesce(v_refund_id::text, '?') ||
          ' in the OS; the customer is then refunded in full and told that banks take ' || (v_amounts->>'bank_settlement_working_days') ||
          ' working days, and the supplier''s charge is raised. If the supplier responds, reject it with a note and the case closes.',
        p_level => 'high', p_kind => 'refund_final_call', p_dedupe_key => 'refund_final_call:' || t.id::text, p_owner_agent => null);
      n_final := n_final + 1;
      v_ids := v_ids || jsonb_build_object('transaction_id', t.id, 'step', 'final_call', 'refund_id', v_refund_id);
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'seen', n_seen, 'chased', n_chased, 'final_calls', n_final,
                            'window_working_days', v_window, 'chase_after_working_days', v_chase,
                            'owner_agent', v_agent, 'cases', v_ids, 'ran_at', now());
end $function$;

CREATE OR REPLACE FUNCTION public.fn_runner_silence_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_run bigint; n_alert int := 0; n_watched int := 0; v_email text;
begin
  insert into agent_runs(agent, started_at) values ('runner_silence_watch', clock_timestamp()) returning id into v_run;

  select to_email into v_email from notifications
   where type='founder_brief' and to_email is not null order by created_at desc limit 1;

  -- RE-DERIVE, NEVER SEED. One pass over 30 days of runs gives every runner its own observed
  -- cadence. A runner seen fewer than 5 times has no cadence worth calling regular and is recorded
  -- as on-demand rather than alerted on — which is what stops this becoming the noise generator the
  -- 18 July snapshot would have been if anything had ever read it.
  with runs as (
    select agent, started_at, counts,
           started_at - lag(started_at) over (partition by agent order by started_at) gap
      from agent_runs where started_at > now() - interval '30 days'),
  agg as (
    select agent,
           count(*) as n,
           -- A CADENCE IS NOT A BURST. Measured on the first run: doc_extract, match, quote_compare,
           -- inquiry_intake and stripe_webhook all showed a "median gap" of 0.00-0.08 hours, because
           -- they are EVENT-DRIVEN and fire in clusters when work arrives. Treating a cluster as a
           -- schedule makes every quiet day an alert. A real cadence shows up on separate DAYS, so
           -- that is what is counted.
           count(distinct started_at::date) as active_days,
           -- A RUNNER LOGGED ONLY ON EXCEPTIONS HAS NO CADENCE EITHER. cos_execute writes an
           -- agent_runs row under its own name ONLY when it has a throttled signal to report (a
           -- refused task start); its ordinary hourly work is logged under 'ceo'. So its
           -- rows stop the moment it stops having a PROBLEM, and the first version of this watch
           -- read that as the runner going silent -- alerting daily on a loop that was working.
           count(*) filter (where coalesce(counts ? 'signal', false)) as signal_rows,
           max(started_at) as last_seen,
           percentile_cont(0.5) within group (order by extract(epoch from gap)/3600.0) as median_gap_h
      from runs group by agent)
  insert into agent_expectations (agent, kind, max_silence_hours, on_demand, median_gap_hours,
                                  runs_observed, last_seen, note, updated_at)
  select a.agent,
         case when exists (select 1 from org_agents o where o.agent_key = a.agent) then 'employee' else 'code' end,
         -- Three times its own median, floored at 6 hours and capped at two weeks. Derived from the
         -- runner rather than from its schedule, because the schedule is what fn_agent_silence_watch
         -- already checks and is exactly what stayed green while the work stopped.
         case when a.n >= 5 and a.active_days >= 5 and a.median_gap_h >= 0.5 and a.n > a.signal_rows
              then least(336, greatest(6, ceil(a.median_gap_h * 3)))
              else 999999 end,
         not (a.n >= 5 and a.active_days >= 5 and a.median_gap_h >= 0.5 and a.n > a.signal_rows),
         round(a.median_gap_h::numeric, 2),
         a.n,
         a.last_seen,
         case when a.n >= 5 and a.active_days >= 5 and a.median_gap_h >= 0.5 and a.n > a.signal_rows
              then 'cadence learned from '||a.n||' run(s) across '||a.active_days||' day(s) in 30d, median gap '||round(a.median_gap_h::numeric,2)||'h'
              else 'no steady cadence ('||a.n||' run(s) across '||a.active_days||' day(s), median gap '
                   ||coalesce(round(a.median_gap_h::numeric,2)::text,'n/a')||'h) — event-driven or on-demand, not watched' end,
         now()
    from agg a
  on conflict (agent) do update set
    kind = excluded.kind, max_silence_hours = excluded.max_silence_hours,
    on_demand = excluded.on_demand, median_gap_hours = excluded.median_gap_hours,
    runs_observed = excluded.runs_observed, last_seen = excluded.last_seen,
    note = excluded.note, updated_at = now();

  select count(*) into n_watched from agent_expectations where not on_demand;

  -- EVERY row, not just the watched ones. Scoping this to `not on_demand` left a stale silent=true
  -- on any runner that moved INTO on_demand — measured on the first run: five event-driven runners
  -- kept a silent flag they could no longer clear.
  update agent_expectations e
     set silent = (not e.on_demand
                   and e.last_seen is not null
                   and e.last_seen < now() - (e.max_silence_hours || ' hours')::interval);

  -- ONCE PER SILENCE EPISODE, ONE EMAIL PER RUN (3 Sep 2026). This loop paged the founder once per
  -- silent employee per DAY — 21 "Employee has stopped working" emails in the 24 hours measured on
  -- 3 Sep, 59 all-time — for runners whose schedules were switched off by his own 16 Aug stand-down
  -- and re-enabled on 2-3 Sep. A silence is one fact, not a daily one: an episode is (runner,
  -- last_seen); it is paged the first time it is seen and never again until the runner has run
  -- (a new last_seen is a new episode). And the employees newly silent in one pass go into ONE
  -- email, never one email each. Nothing is hidden: every silent runner is still in
  -- agent_expectations.silent and in the company snapshot.
  declare v_new text := ''; v_new_n int := 0;
  begin
  for r in select agent, kind, last_seen, max_silence_hours, median_gap_hours
             from agent_expectations where silent and not on_demand order by agent
  loop
    if not exists (select 1 from founder_alerts
                    where event='runner_silent'
                      and detail like '%"runner": "'||r.agent||'"%'
                      and detail like '%"last_run": "'||coalesce(r.last_seen::text,'')||'"%') then
      insert into founder_alerts(level, event, detail, channel)
      values (case when r.kind='employee' then 'high' else 'warn' end, 'runner_silent',
        jsonb_build_object('runner', r.agent, 'kind', r.kind,
          'last_run', r.last_seen::text,
          'silent_hours', round(extract(epoch from (now()-r.last_seen))/3600),
          'own_median_gap_hours', r.median_gap_hours,
          'expected_within_hours', r.max_silence_hours)::text, 'email');
      if r.kind = 'employee' then
        v_new_n := v_new_n + 1;
        v_new := v_new || '- ' || r.agent || ': last did anything at ' || coalesce(r.last_seen::text,'unknown')
              || ' (own cadence one run every ' || coalesce(r.median_gap_hours::text,'?') || ' hours)' || E'\n';
      end if;
      n_alert := n_alert + 1;
    end if;
  end loop;
  if v_new_n > 0 then
    -- 6 SEP 2026: routed to the COO as one org_task per condition, never emailed
    -- (founder_mail_policy.runner_silence); this watcher's own founder_alerts rows are its ledger.
    perform public.fn_founder_mail_route('runner_silence',
      v_new_n || ' employee(s) have stopped working',
      'These runners went past their own observed cadence for the first time since they last ran:' || E'\n' || v_new ||
      E'\n' || 'Each is reported once per silence; it will be reported again only after it runs and stops again. ' ||
      'A scheduled job may still be succeeding — this watch looks at what the runner DID, not at whether its schedule fired.',
      'high');
  end if;
  end;

  update agent_runs set finished_at=clock_timestamp(), status='ok',
      counts=jsonb_build_object('runners', (select count(*) from agent_expectations),
                                'watched', n_watched, 'silent', (select count(*) from agent_expectations where silent),
                                'alerts', n_alert,
                                'employees', (select count(*) from agent_expectations where kind='employee'))
   where id=v_run;

  return jsonb_build_object('runners',(select count(*) from agent_expectations),
                            'watched',n_watched,'alerts',n_alert);
exception when others then
  update agent_runs set finished_at=clock_timestamp(), status='error', note=left(sqlerrm,500) where id=v_run;
  raise;
end $function$;

