select set_config('app.change_reason','Declaring department authority from the COMPANY_OPERATIONS pack v2026.07.31. org_authority had no row for most (department, action_class) pairs, so fn_ops_authority_check fell through to its fail-closed gated default and every employee action reached the founder. Tiers are derived from the executor registry own advisory_safe / reversible / risk_tier flags: low-risk reversible advisory-safe becomes autonomous, high-risk or irreversible stays gated, the rest supervised by an executive.', true);
-- Promote the Company Operations pack's target structure into the live org tables.
--
-- DEPARTMENTS. The pack's own department_crosswalk maps the 15 production departments onto its 24
-- target ones: 20 map directly or by split/share, and FOUR are target_state with no production
-- counterpart (admin_operations, business_development, communications, qa_testing). Production
-- keys are NOT renamed -- org_agents.department, org_tasks and org_authority all reference them,
-- and renaming to reach a tidier count is how you break every foreign key in an estate to make a
-- number look right. The 20 missing target keys are added so all 24 target departments exist.
insert into public.org_departments (dept_key, name, charter, north_star, active, sort)
select d.department_key, d.name,
       coalesce(nullif(btrim(d.charter),''), d.name || ' department, from the COMPANY_OPERATIONS pack v2026.07.31.'),
       coalesce(nullif(btrim(d.north_star),''), 'North star not stated in the pack for this department.'),
       true, 100
  from ops_kb_stage.departments d
 where not exists (select 1 from public.org_departments o where o.dept_key = d.department_key)
on conflict (dept_key) do nothing;

-- ROLES. All 96 target roles are new: not one of their keys collides with the 66 working agents
-- (measured: 0 matches). They land INACTIVE on purpose. The pack describes a target workforce;
-- marking 96 unstaffed roles `active` would tell every per-employee measurement in the company
-- that 162 employees exist, when 18 worked today. The structure is present and honest, and each
-- becomes active when something actually routes to it.
insert into public.org_agents (agent_key, department, role, title, responsibilities, manager_key, active, kind)
select r.agent_key, r.department_key, coalesce(r.authority_tier,'supervised'), r.title,
       r.responsibilities, nullif(r.manager,''), false, 'brain'
  from ops_kb_stage.roles r
 where not exists (select 1 from public.org_agents o where o.agent_key = r.agent_key)
on conflict (agent_key) do nothing;

-- AUTHORITY. The pack states an authority tier per role and per decision rule; org_authority had
-- no row for most (department, action_class) pairs, so fn_ops_authority_check fell through to its
-- fail-closed default of 'gated' -- which is the other half of why everything reached the founder.
insert into public.org_authority (dept_key, action_class, max_tier, note)
select d.department_key, e.action_class,
       case when e.advisory_safe and e.reversible and e.risk_tier = 'low' then 'autonomous'
            when e.risk_tier = 'high' or not e.reversible then 'gated'
            else 'supervised' end,
       'From COMPANY_OPERATIONS pack v2026.07.31: department authority derived from the executor registry''s own advisory_safe / reversible / risk_tier flags.'
  from ops_kb_stage.departments d
  cross join public.org_action_executor e
 where e.active
   and not exists (select 1 from public.org_authority a
                    where a.dept_key = d.department_key and a.action_class = e.action_class)
on conflict do nothing;
