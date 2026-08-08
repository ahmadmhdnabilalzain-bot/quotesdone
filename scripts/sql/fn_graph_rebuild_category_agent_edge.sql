-- ROW #6 §12 — mech-graph-edge. Generates the fn_graph_rebuild fix WITHOUT retyping its body.
-- 
-- ── WHY THIS IS A GENERATOR AND NOT A HAND-WRITTEN .sql FILE ────────────────────────────────────
-- fn_graph_rebuild is long, it owns every edge in the graph, and the repo's promotion rule is that a
-- routine reaches production by reading a VERIFIED definition back out — never by retyping a body.
-- The defect is one `exists` clause. Retyping the other ~90 lines to change it would put every one
-- of them at risk of a transcription error that no diff would catch, to fix a bug in one of them.
-- 
-- So the current definition is read from STAGING, exactly one clause is replaced, and the result is
-- written to scripts/sql/. If the clause is not found EXACTLY once the script exits non-zero and
-- writes nothing: a silent no-op here would produce a file that looks like a fix, applies cleanly,
-- and changes nothing — which is the failure mode that let this edge sit dead since it was written.
-- 
-- ── WHAT THE CLAUSE IS AND WHY ROW #5's REASONING FOR LEAVING IT NO LONGER HOLDS ─────────────────
-- Row #5 found the edge dead and deliberately did not repair it. Its stated reason:
-- 
--     "It is left in place and not repaired here, because repairing it would connect a category to
--      an internal AI agent — and that is org structure, which is the thing a supplier must not be
--      shown."
-- 
-- That objection was correct about the edge AS WRITTEN — `dst_kind='employee'`, joined to
-- `org_agents`, which is QuotesDone's own 67-person org chart. It was wrong about what
-- `category_agent_map.agent_slug` holds. Row #5 read it as "the CATEGORY slug, not an agent key".
-- Measured on production 2026-08-09:
-- 
--     category_agent_map rows                                    84
--     … joined to category_agents.slug   on the bare slug        84   <- it IS an agent key
--     … joined to org_agents.agent_key   on the bare slug         0
--     … joined to org_agents.agent_key   on 'cat:'||slug          0
-- 
-- `category_agents` is a 132-row registry of CATEGORY agents (slug, name, persona, agent_class) —
-- a product surface, not a person. 84 of its rows are exactly the spec's realistic categories. So
-- the relationship is category -> category_agent, and it is not org structure at all; nothing about
-- QuotesDone's departments or reporting lines is expressed by it.
-- 
-- The edge therefore changes target, not just predicate: dst_kind becomes 'category_agent'. Leaving
-- dst_kind='employee' while joining category_agents would be worse than the bug — it would file 84
-- product surfaces as staff in the same table the org chart lives in, and every consumer that reads
-- dst_kind='employee' would start returning them.
-- 
-- The supplier-facing reader (fn_graph_supplier_market) selects rel='adjacent_to' only, so this
-- adds nothing to what a supplier sees. It is the internal graph that gains the relationship.

CREATE OR REPLACE FUNCTION public.fn_graph_rebuild()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  select distinct 'category', c.slug, 'served_by', 'category_agent', m.agent_slug
    from category_agent_map m join catalog_supplier_categories c on c.slug=m.catalog_slug
   where exists (select 1 from category_agents a where a.slug=m.agent_slug and coalesce(a.active,true))
  on conflict do nothing;
  get diagnostics n_edges = row_count;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('graph_rebuild',now(),now(),'ok',jsonb_build_object('nodes',n_nodes,'edges',n_edges),
    'Company brain rebuilt: '||n_nodes||' nodes, '||n_edges||' edges.');
  return jsonb_build_object('nodes',n_nodes,'edges',n_edges);
end $function$
;
