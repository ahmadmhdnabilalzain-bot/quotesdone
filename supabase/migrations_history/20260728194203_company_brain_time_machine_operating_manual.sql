-- Layer 6 / #22 COMPANY BRAIN: 49 nodes and 54 edges was a stub. Rebuild from live entities.
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

  -- OS owns department
  insert into graph_edges (src_kind, src_id, rel, dst_kind, dst_id)
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
  select 'employee', k.agent_key, 'accountable_for', 'goal', k.serves_goal
    from employee_kpi k where k.active and k.serves_goal is not null
     and exists (select 1 from company_goals g where g.key=k.serves_goal and g.active)
     and exists (select 1 from org_agents a where a.agent_key=k.agent_key and a.active)
  union all
  select 'category', c.slug, 'served_by', 'employee', m.agent_slug
    from category_agent_map m join catalog_supplier_categories c on c.slug=m.catalog_slug
   where exists (select 1 from org_agents a where a.agent_key=m.agent_slug and a.active)
  on conflict do nothing;
  get diagnostics n_edges = row_count;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('graph_rebuild',now(),now(),'ok',jsonb_build_object('nodes',n_nodes,'edges',n_edges),
    'Company brain rebuilt: '||n_nodes||' nodes, '||n_edges||' edges across systems, departments, employees, categories, goals, workflows and responsibilities.');
  return jsonb_build_object('nodes',n_nodes,'edges',n_edges);
end $fn$;
revoke execute on function public.fn_graph_rebuild() from public, anon, authenticated;

-- Layer 7 / #33 TIME MACHINE: one unified daily snapshot so any past day can be reconstructed.
create table if not exists public.company_snapshot (
  snapshot_on date primary key,
  state       jsonb not null,
  created_at  timestamptz not null default now()
);
alter table public.company_snapshot enable row level security;

create or replace function public.fn_company_snapshot()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare s jsonb;
begin
  s := jsonb_build_object(
    'employees',        (select count(*) from org_agents where active),
    'departments',      (select count(*) from org_departments where active),
    'operating_systems',(select count(*) from operating_system where active),
    'kpis',             (select count(*) from employee_kpi where active),
    'kpis_measurable',  (select count(*) from employee_kpi where active and measure_sql is not null),
    'kpi_gaps_open',    (select count(*) from org_tasks where title like 'KPI missed:%' and status<>'done'),
    'open_tasks',       (select count(*) from org_tasks where status<>'done'),
    'needs_founder',    (select count(*) from org_tasks where status<>'done' and needs_founder),
    'approved_suppliers',(select count(*) from leads where approval_status='approved'),
    'sendable_pool',    (select coalesce(sum(sendable),0) from v_supply_gap),
    'categories_at_target',(select count(*) from v_supply_gap where approved>=10),
    'revenue_30d_aed',  (select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) from transactions where revealed_at>now()-interval '30 days'),
    'ai_cost_30d_aed',  (select round(coalesce(sum(cost_aed),0),2) from ai_cost_log where occurred_at>now()-interval '30 days'),
    'knowledge_items',  (select count(*) from agent_knowledge),
    'knowledge_quarantined',(select count(*) from agent_knowledge where validation_status='quarantined'),
    'outcomes_pending', (select count(*) from outcome_record where verdict='pending'),
    'outcomes_improved',(select count(*) from outcome_record where verdict='improved'),
    'decisions_7d',     (select count(*) from decision_log where created_at>now()-interval '7 days'),
    'agent_runs_7d',    (select count(*) from agent_runs where started_at>now()-interval '7 days'),
    'error_rate_7d',    (select round(100.0*count(*) filter (where status='error')/nullif(count(*),0),2) from agent_runs where started_at>now()-interval '7 days'),
    'os_health',        (select jsonb_object_agg(os_key,health) from os_review where period=to_char(now(),'IYYY-"W"IW')),
    'indices',          (select jsonb_object_agg(index_name,score) from company_index where measured_on=current_date),
    'autonomy_enabled', (select value from app_secrets where key='agent_autonomy_enabled'),
    'invite_enabled',   (select value from app_secrets where key='invite_enabled'));

  insert into company_snapshot (snapshot_on, state) values (current_date, s)
  on conflict (snapshot_on) do update set state=excluded.state, created_at=now();

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('company_snapshot',now(),now(),'ok',jsonb_build_object('keys',(select count(*) from jsonb_object_keys(s))),
    'Company state snapshotted for '||current_date||'. Any past day can now be reconstructed.');
  return s;
end $fn$;
revoke execute on function public.fn_company_snapshot() from public, anon, authenticated;

-- #38 DIGITAL OPERATING MANUAL: the OS documents itself from live schema, always current.
create or replace view public.v_operating_manual as
select 'operating_system' as section, o.os_key as key, o.name as title,
       o.mission as summary,
       jsonb_build_object('purpose',o.charter,'mandate',o.mandate,'owner',o.owner_agent,
         'adapts_by',o.adapts_by,
         'departments',(select jsonb_agg(dept_key) from os_department d where d.os_key=o.os_key),
         'owns',(select jsonb_agg(responsibility) from os_responsibility r where r.os_key=o.os_key),
         'inputs',(select jsonb_agg(kind) from os_interface i where i.os_key=o.os_key and direction='input'),
         'outputs',(select jsonb_agg(kind) from os_interface i where i.os_key=o.os_key and direction='output'),
         'workflows',(select jsonb_agg(workflow_key) from workflow w where w.os_key=o.os_key),
         'objectives',(select jsonb_object_agg(horizon,objective) from
            (select distinct on (horizon) horizon,objective from os_objective ob where ob.os_key=o.os_key order by horizon, id) z)
       ) as detail
from operating_system o where o.active
union all
select 'workflow', w.workflow_key, w.name, w.description,
       jsonb_build_object('os',w.os_key,'trigger',w.trigger_event,
         'steps',(select jsonb_agg(jsonb_build_object('n',step_no,'step',step,'actor',actor_role,'gate',gate) order by step_no)
                    from workflow_step s where s.workflow_key=w.workflow_key))
from workflow w
union all
select 'policy', 'priority_'||rank::text, principle, meaning,
       jsonb_build_object('rank',rank,'overrides_below',overrides_below)
from priority_hierarchy
union all
select 'scheduled_job', jobname, human_name, purpose, jsonb_build_object('category',category)
from cron_registry;

comment on view public.v_operating_manual is
  'The OS documents itself from live schema: every operating system with its purpose, mandate, owner, responsibilities, interfaces, workflows and objectives; every workflow with its steps and gates; every priority rule; every scheduled job. Always current because it is generated, never written.';