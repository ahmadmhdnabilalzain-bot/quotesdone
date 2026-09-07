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

-- ROUTINE REMOVED 7 September 2026. public.fn_budget_rollup was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


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

-- ROUTINE REMOVED 7 September 2026. public.fn_day_conductor was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ROUTINE REMOVED 7 September 2026. public.fn_dispute_open was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ROUTINE REMOVED 7 September 2026. public.fn_doc_expiry_scan was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


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

-- ROUTINE REMOVED 7 September 2026. public.fn_exec_meeting was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


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

-- ROUTINE REMOVED 7 September 2026. public.fn_index_slowdown_watch was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ROUTINE REMOVED 7 September 2026. public.fn_kernel_source_cutover_state was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ROUTINE REMOVED 7 September 2026. public.fn_kernel_trigger_state was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


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

-- ROUTINE REMOVED 7 September 2026. public.fn_overlay_for_category was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ROUTINE REMOVED 7 September 2026. public.fn_phase_c_reporting_map_drift was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


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

-- ROUTINE REMOVED 7 September 2026. public.fn_phase_d_run_injected_defects was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


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

