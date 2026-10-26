create or replace function public.fn_graph_rebuild()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare n_nodes int := 0; n_edges int := 0;
begin
  delete from graph_edges; delete from graph_nodes;

  insert into graph_nodes (kind, ref_id, label)
  select 'operating_system', os_key, name from operating_system where active
  union all select 'department', dept_key, name from org_departments where active
  union all select 'employee', agent_key, coalesce(title, agent_key) from org_agents where active
  union all select 'category', slug, name from catalog_supplier_categories
  union all select 'goal', key, goal from company_goals where active
  union all select 'workflow', workflow_key, name from workflow
  union all select 'responsibility', responsibility, responsibility from os_responsibility
  on conflict do nothing;
  get diagnostics n_nodes = row_count;

  insert into graph_edges (src_kind, src_ref, rel, dst_kind, dst_ref)
  select 'operating_system', os_key, 'contains', 'department', dept_key from os_department
  union all
  select 'department', a.department, 'employs', 'employee', a.agent_key from org_agents a where a.active
  union all
  select 'employee', manager_key, 'manages', 'employee', agent_key from org_agents where active and manager_key is not null
  union all
  select 'operating_system', os_key, 'owns', 'responsibility', responsibility from os_responsibility
  union all
  select 'operating_system', os_key, 'runs', 'workflow', workflow_key from workflow where os_key is not null
  union all
  select distinct 'employee', k.agent_key, 'accountable_for', 'goal', k.serves_goal
    from employee_kpi k where k.active and k.serves_goal is not null
     and exists (select 1 from company_goals g where g.key=k.serves_goal and g.active)
     and exists (select 1 from org_agents a where a.agent_key=k.agent_key and a.active)
  union all
  select distinct 'category', c.slug, 'served_by', 'employee', m.agent_slug
    from category_agent_map m join catalog_supplier_categories c on c.slug=m.catalog_slug
   where exists (select 1 from org_agents a where a.agent_key=m.agent_slug and a.active)
  on conflict do nothing;
  get diagnostics n_edges = row_count;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('graph_rebuild',now(),now(),'ok',jsonb_build_object('nodes',n_nodes,'edges',n_edges),
    'Company brain rebuilt: '||n_nodes||' nodes, '||n_edges||' edges.');
  return jsonb_build_object('nodes',n_nodes,'edges',n_edges);
end $fn$;
revoke execute on function public.fn_graph_rebuild() from public, anon, authenticated;