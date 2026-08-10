-- Same argument as the departments, applied to the 96 target roles: if the target departments do
-- not belong in the live org table, neither do the roles that staff them. They are complete in
-- ops_kb_stage.roles (96 of 96) and reachable through fn_ops_department_context; putting them in
-- org_agents only made org_departments undeletable and the live org untrue.
--
-- Only rows this session created are removed: keys that exist in ops_kb_stage.roles, are inactive,
-- and have never run, reasoned or held authority.
delete from public.org_agents a
 where a.agent_key in (select agent_key from ops_kb_stage.roles)
   and a.active = false
   and not exists (select 1 from public.agent_runs r where r.agent = a.agent_key)
   and not exists (select 1 from public.agent_memory m where m.agent_key = a.agent_key)
   and not exists (select 1 from public.employee_authority e where e.agent_key = a.agent_key);

delete from public.org_authority
 where dept_key in (select department_key from ops_kb_stage.departments)
   and dept_key not in ('analytics','customer_success','evolution','exec','finance','hr',
                        'intelligence','it','knowledge','knowledge_eng','legal','marketing',
                        'procurement','sales','supplier_success');

delete from public.org_departments d
 where d.dept_key in (select department_key from ops_kb_stage.departments)
   and d.dept_key not in ('analytics','customer_success','evolution','exec','finance','hr',
                          'intelligence','it','knowledge','knowledge_eng','legal','marketing',
                          'procurement','sales','supplier_success')
   and not exists (select 1 from public.org_agents a2 where a2.department = d.dept_key);
