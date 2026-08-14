-- THE COMPANY BRAIN HAD NO READER
--
-- graph_nodes and graph_edges are rebuilt every night by graph_rebuild_daily and, measured on
-- production, read by nothing: no routine that a browser can reach names either table, and os_api
-- routes no action that would. The nightly job has been drawing a map of the company since it was
-- written and nobody has ever been able to look at it.
--
-- fn_company_map is that reader. It is STABLE and writes nothing.
--
-- WHY IT CAPS. The graph holds 1,136 nodes, 667 of them knowledge domains and 86 supplier pools.
-- Shipping all of them to a canvas would produce a hairball nobody can read, so each class is
-- capped and the FULL count is returned beside the capped list — `shown` and `total` per class, so
-- the screen can say "40 of 667" rather than silently implying it is showing everything. A cap the
-- reader cannot see is the same defect as a scorer whose input vanished.
--
-- Edges are restricted to pairs where BOTH endpoints are in the returned node set, so the canvas
-- never receives an edge pointing at a node it does not have.

create or replace function public.fn_company_map(p_per_class integer default 40)
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_catalog'
as $function$
  with cap as (select greatest(1, least(coalesce(p_per_class, 40), 200)) n),
  ranked as (
    select g.kind, g.ref_id, g.label, g.props,
           row_number() over (partition by g.kind order by g.label, g.ref_id) rn
      from graph_nodes g
  ),
  kept as (select * from ranked, cap where ranked.rn <= cap.n),
  totals as (select kind, count(*) total from graph_nodes group by kind)
  select jsonb_build_object(
    'rebuilt_at', (select max(updated_at) from graph_nodes),
    'node_total', (select count(*) from graph_nodes),
    'edge_total', (select count(*) from graph_edges),
    'per_class_cap', (select n from cap),
    'classes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'kind', t.kind, 'total', t.total,
               'shown', (select count(*) from kept k where k.kind = t.kind))
             order by t.total desc)
        from totals t), '[]'::jsonb),
    'nodes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'kind', k.kind, 'id', k.ref_id, 'label', k.label, 'props', k.props)
             order by k.kind, k.label)
        from kept k), '[]'::jsonb),
    'edges', coalesce((
      select jsonb_agg(distinct jsonb_build_object(
               'src_kind', e.src_kind, 'src', e.src_ref, 'rel', e.rel,
               'dst_kind', e.dst_kind, 'dst', e.dst_ref))
        from graph_edges e
       where exists (select 1 from kept a where a.kind = e.src_kind and a.ref_id = e.src_ref)
         and exists (select 1 from kept b where b.kind = e.dst_kind and b.ref_id = e.dst_ref)),
      '[]'::jsonb)
  );
$function$;

-- A newly CREATEd SECURITY DEFINER function is granted EXECUTE to PUBLIC, so it is revoked here in
-- the same migration. os_api reaches it with the service role.
revoke all on function public.fn_company_map(integer) from public, anon, authenticated;

-- BOTH GATES, SAME CHANGE. os_api classifies every action twice — in its own ACTION_CLASS table and
-- in public.control_mode_action — and an action registered in one but not the other put a phone-code
-- prompt in front of eleven read-only screens on 14 Aug. company_map is read-only in both.
-- requires_control is a GENERATED column derived from classification and is deliberately not set.
insert into public.control_mode_action (action, description, classification, risk)
values ('company_map',
        'Reads graph_nodes/graph_edges for the interactive company map. fn_company_map is STABLE and writes nothing.',
        'read_only', 'low')
on conflict (action) do update
  set classification = excluded.classification, description = excluded.description, risk = excluded.risk;
