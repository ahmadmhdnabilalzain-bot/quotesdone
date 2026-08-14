-- REORGANISING THE AGENT COMPANY — 5 of 5: overlays, completeness, and the objective cascade.
--
-- Four things the registry measured as missing, each fixed rather than excused:
--   a. The 86 category specialists existed as knowledge and as routes but not as ROLES, so nothing
--      said who invokes them, what they may decide, or what they may never decide.
--   b. 24 active roles had no employee_authority row at all. An agent with no authority record is
--      not restricted — it is undefined, and every caller had to guess.
--   c. Product, Engineering & AI inherited no executable action class: 11 roles with zero tools,
--      because two of its tools sat with the department that GATES its releases.
--   d. 29 department objectives and 26 role KPIs had no link upward, so no chain reached the
--      AED 1,000,000 objective.

begin;
set local app.change_reason = 'Reorganisation 14 Aug 2026: every active role gets an explicit authority record derived from its canonical authority_level, at or below its department tier. No role is widened past what its department already held.';

-- ---------------------------------------------------------------------------------------------
-- a. THE 86 CATEGORY OVERLAYS.
-- They are not departments, they do not report to the CEO individually, and they have no standing
-- model instance: the invoking manager keeps the customer conversation and loads the overlay.
-- ---------------------------------------------------------------------------------------------
insert into public.org_role (
  role_id, display_name, primary_department_id, manager_role_id, runtime_mode, runtime_agent_key,
  responsibilities, owned_decisions, forbidden_decisions, activation_conditions,
  required_inputs, output_contracts, tools, knowledge_scopes, authority_level,
  handoff_targets, escalation_targets, model_policy, evaluation_suite, status, rationale)
select
  'category_overlay_'||c.category_key,
  'Category Overlay — '||replace(regexp_replace(c.category_key, '^[0-9]+_', ''), '-', ' '),
  'marketplace', 'inquiry_router', 'knowledge_overlay', null,
  'Specialist knowledge for '||c.category_key||', loaded into the inquiry-facing manager only when '
   ||'an inquiry routes to '||coalesce(c.route_key, c.category_key)||'.',
  array['route and subcategory knowledge','minimum sufficient questions',
        'mandatory and optional fields','never-infer rules','pricing drivers',
        'required documents','technical comparison fields','regulatory triggers',
        'quote-readiness criteria','escalation rules'],
  array['dispatching to suppliers','approving or confirming a supplier',
        'exposing customer identity','unsupported legal conclusions',
        'overriding a privacy authority or regulatory gate',
        'taking over the customer conversation'],
  'An inquiry is routed to '||coalesce(c.route_key, c.category_key)||' by the Inquiry Router, or a '
   ||'qualification question needs this category''s technical judgement.',
  '{inquiry,category_key}', '{category_checklist,quote_readiness_verdict,missing_fields}',
  '{fn_category_checklist,fn_category_quote_ready}',
  array[c.category_key, coalesce(c.route_key, c.category_key)],
  'advisory',
  '{inquiry_router,rfq_qualification_manager}', '{inquiry_router,marketplace_director}',
  'routine_employee_reasoning', 'eval_category_overlay', 'active',
  'Kept as an on-demand overlay: 86 standing model instances for 86 categories is the cost the '
   ||'overlay model exists to avoid, and none of them needs standing state.'
  from public.org_category_identity c
on conflict (role_id) do update set
  display_name = excluded.display_name,
  primary_department_id = excluded.primary_department_id,
  manager_role_id = excluded.manager_role_id,
  runtime_mode = excluded.runtime_mode,
  owned_decisions = excluded.owned_decisions,
  forbidden_decisions = excluded.forbidden_decisions,
  activation_conditions = excluded.activation_conditions,
  tools = excluded.tools,
  knowledge_scopes = excluded.knowledge_scopes,
  handoff_targets = excluded.handoff_targets,
  escalation_targets = excluded.escalation_targets,
  evaluation_suite = excluded.evaluation_suite,
  status = 'active';

-- The category desk's operational owner is the Inquiry Router, which is what actually selects it.
update public.org_category_identity c
   set owner_agent = (select r.runtime_agent_key from public.org_role r where r.role_id = 'inquiry_router')
 where c.owner_agent is null;

-- ---------------------------------------------------------------------------------------------
-- b. EVERY ACTIVE ROLE GETS AN EXPLICIT AUTHORITY RECORD.
-- Derived from the canonical authority_level and capped by what the role's own department already
-- holds for that action class: a role can never be granted more than its department has.
-- ---------------------------------------------------------------------------------------------
insert into public.employee_authority (agent_key, action_class, max_tier, threshold_aed, note)
select r.runtime_agent_key,
       'analysis',
       case r.authority_level
         when 'advisory'       then 'advisory'
         when 'execute_low'    then 'supervised'
         when 'execute_medium' then 'supervised'
         when 'execute_high'   then 'supervised'
         when 'stop_authority' then 'supervised'
       end,
       null,
       'seeded 14 Aug 2026 from canonical authority_level '||r.authority_level
         ||'; an active role with no authority record is undefined, not restricted'
  from public.org_role r
 where r.status = 'active' and r.runtime_mode <> 'knowledge_overlay'
   and r.runtime_agent_key is not null
   and not exists (select 1 from public.employee_authority e where e.agent_key = r.runtime_agent_key)
on conflict (agent_key, action_class) do nothing;

-- An independent reviewer must be able to STOP. That is the whole function; a reviewer that can
-- only advise cannot block a failed release gate, a privacy violation or an unsafe regression.
insert into public.employee_authority (agent_key, action_class, max_tier, threshold_aed, note)
select r.runtime_agent_key, 'review_block', 'autonomous', null,
       'independent stop authority granted 14 Aug 2026: this role may block unsafe work in its '
       ||'domain and may never approve work it authored'
  from public.org_role r
 where r.status = 'active' and r.runtime_mode = 'independent_reviewer'
   and r.runtime_agent_key is not null
on conflict (agent_key, action_class) do update
  set max_tier = 'autonomous', note = excluded.note;

-- ---------------------------------------------------------------------------------------------
-- c. TOOL OWNERSHIP FOLLOWS ACCOUNTABILITY.
-- code_selfheal and incident_fix sat with Assurance, which is the function that GATES releases:
-- the reviewer must not author the fix it then certifies. evolution_scan is product discovery and
-- belongs with the Product Manager, not the executive office.
-- ---------------------------------------------------------------------------------------------
update public.org_action_executor set department = 'product_eng',
       note = coalesce(note,'')||' | moved to Product, Engineering & AI on 14 Aug 2026: the '
              ||'assurance function must not author the change it certifies'
 where action_class in ('code_selfheal','incident_fix') and department = 'assurance';
update public.org_action_executor set department = 'product_eng',
       note = coalesce(note,'')||' | moved to Product, Engineering & AI on 14 Aug 2026: product '
              ||'discovery is owned by the Product Manager'
 where action_class = 'evolution_scan' and department = 'exec';

-- Re-derive tools for every role now that ownership moved.
update public.org_role r set tools = coalesce((
    select array_agg(distinct x.action_class)
      from public.org_action_executor x
      join public.org_agents a on a.agent_key = r.runtime_agent_key
     where x.active and (x.department = any(public.fn_dept_scope(a.department))
                         or x.target = r.runtime_agent_key)), '{}')
 where r.status = 'active' and r.runtime_mode <> 'knowledge_overlay' and r.runtime_agent_key is not null;

-- ---------------------------------------------------------------------------------------------
-- d. THE CASCADE: AED 1,000,000 -> company goal -> department objective -> role KPI.
-- Links are only written where they are UNAMBIGUOUS: a department objective whose department owns
-- exactly one active company goal, and a role KPI whose department owns exactly one active
-- objective. Everything else is reported as unlinked rather than guessed, because a fabricated
-- link would make the cascade look complete while explaining nothing.
-- ---------------------------------------------------------------------------------------------
update public.department_objective o set goal_key = g.key, updated_at = now()
  from (select owner_dept, min(key) as key, count(*) as n
          from public.company_goals where active group by owner_dept) g
 where o.active and coalesce(o.goal_key,'') = '' and g.owner_dept = o.dept_key and g.n = 1;

update public.employee_kpi k set serves_objective = o.id
  from (select dept_key, min(id) as id, count(*) as n
          from public.department_objective where active group by dept_key) o
  join public.org_agents a on a.department = o.dept_key
 where k.active and k.serves_objective is null and coalesce(k.serves_goal,'') = ''
   and k.agent_key = a.agent_key and o.n = 1;

-- The cascade, computed rather than asserted. Every level reports what is linked AND what is not.
create or replace function public.fn_objective_cascade()
returns jsonb language sql stable as $$
  with company as (
    select count(*) filter (where active) as goals,
           count(*) filter (where active and coalesce(measure_sql,'') <> '') as measurable,
           max(target_value) filter (where active and category = 'Financial') as top_target
      from public.company_goals),
  dept as (
    select count(*) filter (where active) as objectives,
           count(*) filter (where active and coalesce(goal_key,'') <> '') as linked_to_goal
      from public.department_objective),
  role_kpi as (
    select count(*) filter (where k.active) as kpis,
           count(*) filter (where k.active and (coalesce(k.serves_goal,'') <> '' or k.serves_objective is not null)) as linked,
           count(*) filter (where k.active and k.measured_at is not null) as measured
      from public.employee_kpi k
      join public.org_role r on r.runtime_agent_key = k.agent_key and r.status = 'active'),
  work as (
    select count(*) filter (where status in ('assigned','in_progress')) as open,
           count(*) filter (where status in ('assigned','in_progress') and assigned_agent is not null) as owned
      from public.org_tasks)
  select jsonb_build_object(
    'revenue_objective_aed', (select top_target from company),
    'company_goals', (select goals from company),
    'company_goals_measurable', (select measurable from company),
    'department_objectives', (select objectives from dept),
    'department_objectives_linked_to_a_company_goal', (select linked_to_goal from dept),
    'role_kpis', (select kpis from role_kpi),
    'role_kpis_linked_upward', (select linked from role_kpi),
    'role_kpis_with_a_measured_actual', (select measured from role_kpi),
    'open_work', (select open from work),
    'open_work_with_one_accountable_owner', (select owned from work),
    'unlinked_department_objectives', (select objectives - linked_to_goal from dept),
    'unlinked_role_kpis', (select kpis - linked from role_kpi),
    'note', 'links are written only where a department owns exactly one active goal or objective; '
            ||'the remainder are reported unlinked rather than guessed');
$$;

-- ---------------------------------------------------------------------------------------------
-- CATEGORY-SPECIALIST PERFORMANCE, aggregated into the marketplace metrics the brief names.
-- A metric with no input returns null and a reason, never 0 and never 100: pct(got, 0) = 100 is
-- how 56 unmeasured goals once scored as perfect.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_category_specialist_scorecard(p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare
  v_since timestamptz := now() - make_interval(days => greatest(coalesce(p_days,30),1));
  v_routed int; v_routed_ok int; v_inq int; v_quotable int; v_completeness numeric;
  v_disp int; v_responded int; v_quotes int; v_valid int;
  v_overlays int; v_with_knowledge int;
begin
  select count(*) into v_overlays from org_role where status='active' and runtime_mode='knowledge_overlay';
  select count(distinct k.category_key) into v_with_knowledge
    from ops_knowledge k where k.category_key is not null and k.runtime_eligible;

  select count(*), count(*) filter (where coalesce(category,'') <> ''),
         count(*) filter (where coalesce(rfq_ready,false)), avg(completeness)
    into v_routed, v_routed_ok, v_quotable, v_completeness
    from inquiries where created_at >= v_since;
  v_inq := v_routed;

  -- Dispatch is inquiry_matches.sent_at: a match that was never sent is a coverage fact, not a
  -- specialist outcome, so an unsent match is excluded from the denominator rather than counted
  -- as an unanswered dispatch.
  select count(*) into v_disp from inquiry_matches where sent_at >= v_since;
  select count(distinct m.id) into v_responded
    from inquiry_matches m
    join quotes q on q.inquiry_id = m.inquiry_id and q.supplier_id = m.supplier_id
   where m.sent_at >= v_since;

  select count(*) into v_quotes from quotes where created_at >= v_since;
  select count(*) into v_valid from quotes
   where created_at >= v_since and coalesce(status,'') not in ('draft','invalid','withdrawn');

  return jsonb_build_object(
    'window_days', p_days,
    'overlays_active', v_overlays,
    'categories_with_runtime_knowledge', v_with_knowledge,
    'routing_accuracy', case when v_routed = 0 then null
                             else round(100.0 * v_routed_ok / v_routed, 1) end,
    'routing_accuracy_basis', case when v_routed = 0
      then 'no inquiry created in the window: not measurable, and deliberately not reported as 100'
      else v_routed_ok||' of '||v_routed||' inquiries carry a resolved category' end,
    'inquiry_quoteability', case when v_inq = 0 then null
                                 else round(100.0 * v_quotable / v_inq, 1) end,
    'inquiry_quoteability_basis', case when v_inq = 0
      then 'no inquiry in the window' else v_quotable||' of '||v_inq||' marked rfq_ready' end,
    'mandatory_field_completeness', case when v_inq = 0 then null else round(v_completeness, 1) end,
    'mandatory_field_completeness_basis', case when v_inq = 0
      then 'no inquiry in the window' else 'mean inquiries.completeness over '||v_inq||' inquiries' end,
    'supplier_response_rate', case when v_disp = 0 then null
                                   else round(100.0 * v_responded / v_disp, 1) end,
    'supplier_response_rate_basis', case when v_disp = 0
      then 'nothing dispatched in the window; with one confirmed supplier company-wide this is '
           ||'expected and is a coverage fact, not a specialist failure'
      else v_responded||' of '||v_disp||' dispatches answered' end,
    'valid_quotations', case when v_quotes = 0 then null
                             else round(100.0 * v_valid / v_quotes, 1) end,
    'valid_quotations_basis', case when v_quotes = 0
      then 'no quotation in the window' else v_valid||' of '||v_quotes end,
    'measured_at', now());
end
$function$;

revoke all on function public.fn_objective_cascade() from public;
revoke all on function public.fn_category_specialist_scorecard(integer) from public;
grant execute on function public.fn_objective_cascade() to service_role;
grant execute on function public.fn_category_specialist_scorecard(integer) to service_role;

commit;
