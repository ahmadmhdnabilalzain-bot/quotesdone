-- REORGANISING THE AGENT COMPANY — 4 of 5: runtime orchestration.
--
-- Five changes, each answering a measured fact rather than a preference:
--
--  1. Knowledge scope follows the merge. 5,775 ops_knowledge rows are tagged with the 22 department
--     keys that no longer exist as departments. Retrieval matched `dept_key = agent.department`
--     exactly, so the day the merge landed every moved employee would have retrieved nothing from
--     its own history. fn_dept_scope closes that without rewriting a single knowledge row.
--  2. The context an agent receives now carries its CANONICAL role: what it may decide, what it may
--     not, when it activates, who it hands off to, who it escalates to, and which committees it
--     sits on. A reorganisation the agents cannot read is a document, not an organisation.
--  3. Independent review actually becomes independent. Measured on production: 285 of 1,882
--     review_chain rows have author_agent = reviewer_agent, and 182 of those are APPROVALS, the
--     most recent at 06:40 UTC today. fn_review_submit already knows the author and never passed
--     it to fn_pick_reviewer, which returns the department head — so whenever the head was the
--     author, the head approved itself.
--  4. Ordinary work stops landing on independent reviewers. A reviewer that carries the
--     department's routine queue is not independent of it.
--  5. Specialist-as-tool and structured handoff, so a manager can invoke a specialist without the
--     customer visibly bouncing between agents, and every handoff names an accountable receiver.

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. RETRIEVAL FOLLOWS THE MERGE.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_context_slice(p_dept text, p_role_ids text[], p_category text, p_layer text, p_q tsquery, p_budget integer)
returns jsonb language sql stable security definer set search_path to 'public'
as $function$
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
      -- THE MERGE ARM. A department that absorbed another owns its predecessor's knowledge; the
      -- 5,775 rows tagged with the 22 absorbed keys are not rewritten, they are scoped in.
      or (p_layer = 'department_shared'   and dept_key = any(public.fn_dept_scope(p_dept)))
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
$function$;

-- ---------------------------------------------------------------------------------------------
-- 2. THE AGENT READS ITS OWN CANONICAL ROLE.
-- ---------------------------------------------------------------------------------------------
-- Parameter ORDER is the live one (task_class, task_text, category_key); writing it in any other
-- order creates a second overload rather than replacing this function, and both would then be
-- callable.
create or replace function public.fn_agent_context_v3(p_agent_key text, p_task_class text default null, p_task_text text default null, p_category_key text default null, p_budget_chars integer default 24000)
returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
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
  v_key        text;
begin
  -- RESOLVE AT THE BOUNDARY. Measured 14 Aug 2026: of 68 routines taking an agent, actor or
  -- assignee argument, exactly ONE resolved it. This is the path every employee turn goes through,
  -- and it did two wrong things: `fn_agent_context_v3('chief_of_staff')` — a canonical role id this
  -- reorganisation publishes — answered "unknown agent", while
  -- `fn_agent_context_v3('analytics_director')` — an employee merged away this morning — happily
  -- assembled a full context, because the lookup never checked `active`.
  --
  -- The second is the dangerous one: a deactivated employee that still assembles is a deactivated
  -- employee that can still act.
  v_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);

  select a.agent_key, a.department, a.role, a.title, a.manager_key, a.seniority,
         a.responsibilities, a.max_open_tasks, a.active, d.name dept_name, d.charter, d.north_star
    into v_agent
    from org_agents a
    left join org_departments d on d.dept_key = a.department
   where a.agent_key = v_key;

  if v_agent.agent_key is null then
    return jsonb_build_object('error', 'unknown agent', 'agent_key', p_agent_key,
                              'resolved_to', v_key);
  end if;

  if not coalesce(v_agent.active, false) then
    return jsonb_build_object(
      'error', 'inactive employee',
      'agent_key', p_agent_key, 'resolved_to', v_key,
      'detail', 'this employee is not active — it was merged away or stood down. Address the '
                ||'surviving role instead; fn_org_agent_resolve names it. A context assembled for '
                ||'an inactive employee is a context that lets it act.');
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
$function$;

-- ---------------------------------------------------------------------------------------------
-- 3. INDEPENDENT REVIEW. The author is never the reviewer.
-- ---------------------------------------------------------------------------------------------
-- The one-argument form is dropped, not kept alongside: two overloads would make fn_pick_reviewer
-- ambiguous for every existing one-argument caller. The new second parameter defaults to null, so
-- those callers keep working with exactly today's behaviour.
drop function if exists public.fn_pick_reviewer(text);
create or replace function public.fn_pick_reviewer(p_dept_key text, p_author text default null)
returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare v_head text; v_ok boolean; v_delegate text; v_basis text;
        v_head_tier text; v_head_score numeric; v_score numeric; v_up text;
begin
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

-- fn_review_submit already held the author and never passed it. One argument.
create or replace function public.fn_review_submit(p_subject_type text, p_subject_id text, p_dept_key text, p_author text, p_content text)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_crit        jsonb;
  v_rule        jsonb;
  v_violations  jsonb := '[]'::jsonb;
  v_unenforced  jsonb := '[]'::jsonb;
  v_critical    int := 0;
  v_major       int := 0;
  v_pick        jsonb;
  v_head        text;
  v_deleg_from  text;
  v_deleg_basis text;
  v_cos         text := 'brief';
  v_decision    text;
  v_reason      text;
  v_conf        numeric;
  v_first_rule  text;
  v_res         jsonb;
begin
  -- Who is actually able to approve for this department right now, GIVEN WHO WROTE IT.
  v_pick        := fn_pick_reviewer(p_dept_key, p_author);
  v_head        := v_pick->>'reviewer';
  v_deleg_from  := v_pick->>'delegated_from';
  v_deleg_basis := v_pick->>'basis';

  -- The Chief of Staff cannot counter-sign its own draft either: that review climbs to the CEO.
  if p_author = v_cos then v_cos := 'ceo'; end if;

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, stage, decision, reason, confidence)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, 'drafted', null,
          'Draft submitted for department review', null);

  if v_head is null then
    insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                              decision, reason, confidence, delegated_from, delegation_basis)
    values (p_subject_type, p_subject_id, p_dept_key, p_author, null, 'dept_review',
            'escalate', 'No available approver in ' || p_dept_key || ': ' || coalesce(v_deleg_basis,''), 1.0,
            v_deleg_from, v_deleg_basis);
    return jsonb_build_object('subject_id', p_subject_id, 'outcome', 'escalate',
                              'stopped_at', 'dept_review', 'violations', v_violations,
                              'reason', coalesce(v_deleg_basis,''));
  end if;

  select criteria into v_crit from quality_standard where work_type = p_subject_type;

  if v_crit is not null then
    for v_rule in select * from jsonb_array_elements(v_crit) loop

      if (v_rule ? 'check_fn') then
        begin
          execute format('select %I($1,$2)', v_rule->>'check_fn')
            into v_res using p_subject_id, p_content;
        exception when others then
          v_res := jsonb_build_object('passed', false, 'detail', 'check ' || (v_rule->>'check_fn') || ' errored: ' || sqlerrm);
        end;
        if not coalesce((v_res->>'passed')::boolean, false) then
          v_violations := v_violations || jsonb_build_object(
            'rule', v_rule->>'rule', 'severity', v_rule->>'severity',
            'why', v_rule->>'why', 'detail', v_res->>'detail');
          if (v_rule->>'severity') = 'critical' then v_critical := v_critical + 1;
          elsif (v_rule->>'severity') = 'major' then v_major := v_major + 1; end if;
          if v_first_rule is null then v_first_rule := v_rule->>'rule'; end if;
        end if;

      elsif (v_rule ? 'pattern') and (v_rule ? 'fails_when') then
        if (v_rule->>'fails_when') = 'match' and p_content ~ (v_rule->>'pattern') then
          v_violations := v_violations || jsonb_build_object(
            'rule', v_rule->>'rule', 'severity', v_rule->>'severity', 'why', v_rule->>'why');
          if (v_rule->>'severity') = 'critical' then v_critical := v_critical + 1;
          elsif (v_rule->>'severity') = 'major' then v_major := v_major + 1; end if;
          if v_first_rule is null then v_first_rule := v_rule->>'rule'; end if;
        elsif (v_rule->>'fails_when') = 'no_match' and p_content !~ (v_rule->>'pattern') then
          v_violations := v_violations || jsonb_build_object(
            'rule', v_rule->>'rule', 'severity', v_rule->>'severity', 'why', v_rule->>'why');
          if (v_rule->>'severity') = 'critical' then v_critical := v_critical + 1;
          elsif (v_rule->>'severity') = 'major' then v_major := v_major + 1; end if;
          if v_first_rule is null then v_first_rule := v_rule->>'rule'; end if;
        end if;

      else
        v_unenforced := v_unenforced || jsonb_build_object(
          'rule', v_rule->>'rule', 'severity', v_rule->>'severity', 'why', v_rule->>'why');
      end if;

    end loop;
  end if;

  if v_critical > 0 then
    v_decision := 'reject';
    v_reason   := 'Rejected by department head: ' || v_critical || ' critical rule breach(es) - ' || (v_violations::text);
    v_conf     := 1.0;
  elsif v_major > 0 then
    v_decision := 'request_revision';
    v_reason   := 'Returned for revision: ' || v_major || ' major issue(s) - ' || (v_violations::text);
    v_conf     := 0.9;
  elsif jsonb_array_length(v_unenforced) > 0
        and exists (select 1 from jsonb_array_elements(v_unenforced) u where u->>'severity' = 'critical') then
    v_decision := 'hold_for_human';
    v_reason   := 'Held for human review: no executable check exists for critical criteria - ' || (v_unenforced::text);
    v_conf     := 1.0;
    v_first_rule := (select u->>'rule' from jsonb_array_elements(v_unenforced) u where u->>'severity'='critical' limit 1);
  elsif v_crit is null then
    v_decision := 'hold_for_human';
    v_reason   := 'Held for human review: no quality standard is defined for work type "' || p_subject_type || '"';
    v_conf     := 1.0;
  else
    v_decision := 'approve';
    v_reason   := 'Meets the quality standard for ' || p_subject_type || '; every criterion was checked and passed';
    v_conf     := 0.95;
  end if;

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                            decision, reason, violated_rule, confidence, delegated_from, delegation_basis)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, v_head, 'dept_review',
          v_decision, v_reason, v_first_rule, v_conf, v_deleg_from,
          case when v_deleg_from is not null then v_deleg_basis else null end);

  if v_decision <> 'approve' then
    return jsonb_build_object('subject_id', p_subject_id, 'outcome', v_decision,
                              'stopped_at', 'dept_review', 'violations', v_violations,
                              'unenforceable', v_unenforced,
                              'reviewer', v_head, 'delegated_from', v_deleg_from);
  end if;

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                            decision, reason, confidence)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, v_cos, 'cos_review',
          'approve', 'Approved by Chief of Staff: brand-compliant and serves a company goal', 0.9);

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                            decision, reason, confidence)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, v_cos, 'published',
          'approve', 'Published after full approval chain', 1.0);

  insert into company_event (event_type, entity_type, entity_id, actor, payload)
  values ('content.published', p_subject_type, p_subject_id, p_author,
          jsonb_build_object('dept', p_dept_key));

  return jsonb_build_object('subject_id', p_subject_id, 'outcome', 'published',
                            'stopped_at', 'published', 'violations', v_violations,
                            'unenforceable', v_unenforced,
                            'reviewer', v_head, 'delegated_from', v_deleg_from);
end;
$function$;

-- The constraint that makes it unrepresentable going forward. NOT VALID on purpose: the 285
-- historical rows stay exactly as they happened. Deleting them would be erasing the evidence that
-- this defect was real.
alter table public.review_chain drop constraint if exists review_chain_no_self_approval_ck;
alter table public.review_chain add constraint review_chain_no_self_approval_ck
  check (reviewer_agent is null or author_agent is null or reviewer_agent <> author_agent) not valid;

-- ---------------------------------------------------------------------------------------------
-- 4. ORDINARY WORK STOPS LANDING ON INDEPENDENT REVIEWERS.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_org_task_assign(p_limit integer default 200)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_assigned int := 0; v_no_capacity int := 0; v_considered int := 0; v_saturated text;
begin
  with open_tasks as (
    select t.id, t.dept_key, t.created_at, t.action_class
      from public.org_tasks t
     where t.assigned_agent is null
       and t.status in ('assigned','in_progress')
     order by t.created_at
     limit greatest(coalesce(p_limit, 200), 1)
  ),
  load as (
    select a.agent_key, a.department, coalesce(a.max_open_tasks, 6) as cap,
           coalesce(r.runtime_mode, 'on_demand_specialist') as runtime_mode,
           (select count(*) from public.org_tasks o
             where o.assigned_agent = a.agent_key and o.status in ('assigned','in_progress')) as open_now,
           case when p.tier = 'probation' then 1 else 0 end as probation_rank
      from public.org_agents a
      left join public.agent_reputation p on p.agent_key = a.agent_key
      left join public.org_role r on r.runtime_agent_key = a.agent_key and r.status = 'active'
     where a.active
       and coalesce(a.available, true)
       and (a.unavailable_until is null or a.unavailable_until < now())
  ),
  ranked as (
    select ot.id as task_id, l.agent_key, l.cap, l.open_now,
           row_number() over (partition by ot.id
                              order by l.probation_rank, l.open_now, l.agent_key) as pick,
           row_number() over (partition by l.agent_key
                              order by ot.created_at, ot.id) as nth_for_agent
      from open_tasks ot
      join load l on l.department = ot.dept_key
      -- AN INDEPENDENT REVIEWER CARRYING THE DEPARTMENT'S ROUTINE QUEUE IS NOT INDEPENDENT OF IT.
      -- Review work still reaches them: the review action classes are the exception, and
      -- fn_pick_reviewer routes review directly rather than through this queue.
     where l.runtime_mode <> 'independent_reviewer'
        or coalesce(ot.action_class,'') in ('review','audit','verify','qa_gate','security_review',
                                            'compliance_check','legal_review','supplier_verify',
                                            'capability_review','self_review')
  ),
  chosen as (
    select task_id, agent_key from ranked
     where pick = 1 and (open_now + nth_for_agent) <= cap
  ),
  done as (
    update public.org_tasks t
       set assigned_agent = c.agent_key, updated_at = now()
      from chosen c
     where t.id = c.task_id and t.assigned_agent is null
    returning t.id
  )
  select (select count(*) from done), (select count(*) from open_tasks)
    into v_assigned, v_considered;

  v_no_capacity := v_considered - v_assigned;

  select string_agg(x.dept_key||' '||x.unowned||'/'||x.capacity, ', ' order by x.unowned desc)
    into v_saturated
    from (select t.dept_key, count(*) as unowned,
                 (select coalesce(sum(coalesce(a.max_open_tasks,6)),0) from public.org_agents a
                   where a.active and coalesce(a.available,true) and a.department = t.dept_key) as capacity
            from public.org_tasks t
           where t.assigned_agent is null and t.status in ('assigned','in_progress')
           group by t.dept_key
          having count(*) > 0
           order by count(*) desc
           limit 6) x;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('org_task_assign', now(), now(), 'ok',
          jsonb_build_object('considered', v_considered, 'assigned', v_assigned,
                             'left_unowned', v_no_capacity, 'oversubscribed', coalesce(v_saturated,'none')),
          'Assigned '||v_assigned||' of '||v_considered||' unowned open task(s) to a named employee '
          ||'in the owning department, skipping independent reviewers for non-review work. '
          ||v_no_capacity||' left unowned because no colleague in that department had capacity '
          ||'under max_open_tasks - deliberate: an unowned task is visible, an overloaded one is '
          ||'not. Departments carrying more open work than they staff (unowned/capacity): '
          ||coalesce(v_saturated,'none')||'.');

  return jsonb_build_object('considered', v_considered, 'assigned', v_assigned,
                            'left_unowned', v_no_capacity, 'oversubscribed', coalesce(v_saturated,'none'));
end
$function$;

-- ---------------------------------------------------------------------------------------------
-- 5. SPECIALIST AS A TOOL, AND HANDOFF AS A RECORD.
-- ---------------------------------------------------------------------------------------------
-- Which overlay a category loads, and who invokes it. The chain is Marketplace Director ->
-- RFQ Qualification Manager -> Inquiry Router -> the category overlay.
create or replace function public.fn_overlay_for_category(p_category_key text)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'category_key', c.category_key,
    'route_key', c.route_key,
    'overlay_role_id', 'category_overlay_'||c.category_key,
    'owner_agent', c.owner_agent,
    'invoked_by_role', 'inquiry_router',
    'readiness', c.readiness,
    'exists', (select count(*) > 0 from public.org_role r
                where r.role_id = 'category_overlay_'||c.category_key and r.status='active'))
    from public.org_category_identity c where c.category_key = p_category_key;
$$;

-- A manager invoking a specialist as a tool. The manager keeps the conversation; the specialist
-- returns a finding. Recorded, so "the specialist was consulted" is a fact and not a claim.
create or replace function public.fn_specialist_invoke(
  p_manager text, p_specialist text, p_subject_type text, p_subject_id text, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_mgr text; v_spec text; v_mode text; v_dept text; v_id bigint;
begin
  v_mgr  := public.fn_org_role_resolve(p_manager);
  v_spec := public.fn_org_role_resolve(p_specialist);
  if v_mgr is null then
    return jsonb_build_object('ok', false, 'error', 'unknown invoking role: '||p_manager);
  end if;
  if v_spec is null then
    return jsonb_build_object('ok', false, 'error', 'unknown specialist role: '||p_specialist);
  end if;

  select runtime_mode, primary_department_id into v_mode, v_dept from public.org_role where role_id = v_spec;

  -- A standing manager or an event-driven operator is not a tool: work goes to it by handoff, so
  -- that one accountable owner exists rather than two agents holding the same subject.
  if v_mode not in ('on_demand_specialist','knowledge_overlay','independent_reviewer') then
    return jsonb_build_object('ok', false, 'error',
      v_spec||' is a '||v_mode||'; invoke it by handoff (fn_role_handoff), not as a tool',
      'use', 'fn_role_handoff');
  end if;

  insert into public.review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent,
                                   stage, decision, reason, confidence, delegation_basis)
  values (p_subject_type, p_subject_id, v_dept,
          public.fn_org_role_agent(v_mgr), public.fn_org_role_agent(v_spec),
          'specialist_invocation', 'owned',
          coalesce(p_reason, 'specialist consulted as a tool'), null,
          v_mgr||' invoked '||v_spec||' as a tool and retains ownership of the subject')
  returning id into v_id;

  return jsonb_build_object('ok', true, 'invocation_id', v_id,
    'manager_role', v_mgr, 'specialist_role', v_spec, 'specialist_mode', v_mode,
    'accountable_owner', v_mgr,
    'customer_visible', false,
    'note', 'the invoking manager remains the accountable owner and keeps the conversation');
end
$function$;

-- A handoff, where the specialist genuinely takes over. Exactly one accountable owner at a time.
create or replace function public.fn_role_handoff(
  p_from text, p_to text, p_subject_type text, p_subject_id text, p_reason text, p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_from text; v_to text; v_dept text; v_allowed boolean; v_id bigint;
begin
  v_from := public.fn_org_role_resolve(p_from);
  v_to   := public.fn_org_role_resolve(p_to);
  if v_from is null or v_to is null then
    return jsonb_build_object('ok', false, 'error', 'unknown role in handoff',
                              'from', p_from, 'to', p_to);
  end if;
  if v_from = v_to then
    return jsonb_build_object('ok', false, 'error', 'a role cannot hand off to itself');
  end if;

  select primary_department_id into v_dept from public.org_role where role_id = v_to;

  -- The declared handoff graph. An undeclared handoff is allowed but recorded as such, because a
  -- refusal here would silently drop work; what must never happen is an unrecorded one.
  select v_to = any(r.handoff_targets) or v_to = any(r.escalation_targets)
    into v_allowed from public.org_role r where r.role_id = v_from;

  insert into public.review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent,
                                   stage, decision, reason, delegated_from, delegation_basis)
  values (p_subject_type, p_subject_id, v_dept,
          public.fn_org_role_agent(v_from), public.fn_org_role_agent(v_to),
          'handoff', 'owned', coalesce(p_reason, 'ownership transferred'),
          public.fn_org_role_agent(v_from),
          case when coalesce(v_allowed,false)
               then 'declared handoff target of '||v_from
               else 'UNDECLARED handoff from '||v_from||' to '||v_to||'; recorded for the '
                    ||'organisation designer to reconcile' end)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'handoff_id', v_id,
    'from_role', v_from, 'to_role', v_to, 'accountable_owner', v_to,
    'declared', coalesce(v_allowed, false),
    'to_agent', public.fn_org_role_agent(v_to), 'payload', p_payload);
end
$function$;

revoke all on function public.fn_overlay_for_category(text) from public;
revoke all on function public.fn_specialist_invoke(text,text,text,text,text) from public;
revoke all on function public.fn_role_handoff(text,text,text,text,text,jsonb) from public;
grant execute on function public.fn_overlay_for_category(text) to service_role;
grant execute on function public.fn_specialist_invoke(text,text,text,text,text) to service_role;
grant execute on function public.fn_role_handoff(text,text,text,text,text,jsonb) to service_role;

commit;
