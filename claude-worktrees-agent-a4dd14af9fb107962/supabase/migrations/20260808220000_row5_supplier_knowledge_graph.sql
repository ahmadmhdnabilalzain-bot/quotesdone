-- ROW #5 §23 — the supplier-facing knowledge graph.
--
-- SOURCE: scripts/sql/fn_graph_supplier_market.sql
-- The first hand-written migration since the squash of 8 Aug 2026. Everything before it lives in
-- supabase/migrations_history/; this folder is append-only from here.
--
-- ── THE TIMEOUTS ARE NOT CEREMONY ───────────────────────────────────────────────────────────────
-- Squawk flagged this file for require-lock-timeout and require-statement-timeout on its first run,
-- which is the linter earning its place on the day it was installed. `create or replace function`
-- needs a lock on the function, and without lock_timeout it waits forever behind whatever holds it
-- — on a live database that is an outage that looks like a hung deploy. Five seconds is long enough
-- for a normal deploy and short enough that a blocked one fails instead of queueing behind itself.
set lock_timeout = '5s';
set statement_timeout = '60s';

-- ==============================================================================================
-- ROW #5 §23 — THE KNOWLEDGE GRAPH THE SUPPLIER SURFACE CAN ACTUALLY READ.
--
-- ── WHAT WAS THERE, AND WHY IT WAS A LIST RATHER THAN A GRAPH ───────────────────────────────────
-- graph_nodes held 324 nodes and 86 of them were categories with real names — "Steel &
-- Reinforcement Suppliers", "Waterproofing Suppliers". Not one edge touched any of them. Measured:
--
--     select count(*) from graph_edges where src_kind='category' or dst_kind='category';  -- 0
--
-- Every one of the 301 edges was org chart: operating_system→responsibility, department→employee,
-- employee→employee. So the only graph a supplier could have been shown was QuotesDone's own
-- reporting structure, and the categories — the half that is about their market — were 86
-- disconnected dots. A graph with no edges is a list.
--
-- ── THE ONE CATEGORY EDGE THAT EXISTED COULD NEVER FIRE ─────────────────────────────────────────
-- fn_graph_rebuild already tries to connect them:
--
--     select distinct 'category', c.slug, 'served_by', 'employee', m.agent_slug
--       from category_agent_map m join catalog_supplier_categories c on c.slug=m.catalog_slug
--      where exists (select 1 from org_agents a where a.agent_key=m.agent_slug and a.active)
--
-- category_agent_map has 84 rows and the slug join matches all 84. The agent leg matches ZERO —
-- and zero with `and a.active` removed as well, so it is not a staleness problem. The reason is in
-- the data: agent_slug holds the CATEGORY slug, not an agent key. Both columns read
-- 'steel-and-reinforcement-suppliers'. The edge has been unbuildable since it was written.
--
-- It is left in place and not repaired here, because repairing it would connect a category to an
-- internal AI agent — and that is org structure, which is the thing a supplier must not be shown.
-- What is added instead is the edge a supplier actually needs.
--
-- ── THE EDGE THAT IS WORTH HAVING, FROM 17,107 REAL ROWS ────────────────────────────────────────
-- lead_category links companies to those same 86 slugs, 17,107 times. Two categories served by the
-- same companies are ADJACENT — that is real market structure, and it answers a question a supplier
-- actually asks: "who else does what I do, and what else do they do?" A supplier in waterproofing
-- learning that 340 of their competitors also do flooring is a genuine expansion signal.
--
-- Derived, never invented: every edge carries the number of companies it was computed from, and a
-- pair below the floor is not emitted at all rather than shown as a weak line.
create or replace function public.fn_graph_supplier_market()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare n_edges int := 0; n_props int := 0;
begin
  -- Recomputed wholesale, like fn_graph_rebuild does. Only the edges this function owns are
  -- removed, so it can run independently of the nightly rebuild without eating its work.
  delete from graph_edges where rel = 'adjacent_to' and src_kind = 'category';

  -- b.slug > a.slug emits each unordered pair once. Without it every pair appears twice, which
  -- would double every count a reader aggregates and make the graph look denser than it is.
  insert into graph_edges (src_kind, src_ref, rel, dst_kind, dst_ref, props)
  select 'category', a.slug, 'adjacent_to', 'category', b.slug,
         jsonb_build_object('companies', count(distinct a.lead_id))
  from lead_category a
  join lead_category b on b.lead_id = a.lead_id and b.slug > a.slug
  group by a.slug, b.slug
  -- THE FLOOR IS THE HONESTY. Two companies serving both categories is a coincidence, not an
  -- adjacency, and drawing it would fill the graph with lines that mean nothing.
  having count(distinct a.lead_id) >= 5
  on conflict do nothing;
  get diagnostics n_edges = row_count;

  -- How many companies sit in each category, on the node itself, so a reader never has to guess
  -- whether a big-looking category is big.
  update graph_nodes n
     set props = coalesce(n.props, '{}'::jsonb) || jsonb_build_object('companies', c.n),
         updated_at = now()
  from (select slug, count(distinct lead_id) n from lead_category group by 1) c
  where n.kind = 'category' and n.ref_id = c.slug;
  get diagnostics n_props = row_count;

  return jsonb_build_object('adjacency_edges', n_edges, 'categories_counted', n_props);
end $function$;

comment on function public.fn_graph_supplier_market() is
  'Row #5 §23. Adds category<->category adjacency edges to the knowledge graph, computed from '
  'lead_category (17,107 rows): two categories are adjacent when at least 5 of the same companies '
  'serve both. Also stamps each category node with its company count. Derived and recomputable; '
  'every edge carries the population it came from.';

-- ==============================================================================================
-- THE SUPPLIER-FACING READER.
--
-- Reads graph_nodes and graph_edges — the check for §23 asks for a knowledge graph REACHABLE from
-- the supplier surface, and a nightly cron rebuilding a graph nobody reads is not that.
--
-- It returns only category structure. No employee, department, goal or responsibility node is ever
-- selected, because those are QuotesDone's internal org chart and a supplier is not an audience for
-- it. That is a filter on kind, in one place, rather than a convention.
create or replace function public.fn_supplier_knowledge_graph(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with mine as (
    select lc.slug, lc.is_primary, lc.score
    from lead_category lc where lc.lead_id = p_lead_id
  ),
  -- Adjacency is stored once per unordered pair, so both directions are recovered here; reading
  -- only src_ref would silently hide half of every supplier's neighbourhood.
  neigh as (
    select case when e.src_ref = m.slug then e.dst_ref else e.src_ref end as slug,
           (e.props->>'companies')::int as companies
    from graph_edges e join mine m on m.slug in (e.src_ref, e.dst_ref)
    where e.rel = 'adjacent_to' and e.src_kind = 'category'
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'basis', 'categories this company is listed in, and the categories its competitors also serve',
    'my_categories', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'slug', m.slug,
        'label', (select n.label from graph_nodes n where n.kind='category' and n.ref_id=m.slug),
        'companies', (select (n.props->>'companies')::int from graph_nodes n where n.kind='category' and n.ref_id=m.slug),
        'primary', m.is_primary) order by m.is_primary desc nulls last, m.slug), '[]'::jsonb)
      from mine m),
    -- Excludes the supplier's own categories: telling them they are adjacent to themselves is noise.
    'adjacent', (
      select coalesce(jsonb_agg(x order by x->'shared_companies' desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'slug', nb.slug,
          'label', (select n.label from graph_nodes n where n.kind='category' and n.ref_id=nb.slug),
          'shared_companies', max(nb.companies),
          'companies', (select (n.props->>'companies')::int from graph_nodes n where n.kind='category' and n.ref_id=nb.slug)
        ) x
        from neigh nb
        where nb.slug not in (select slug from mine)
        group by nb.slug
        order by max(nb.companies) desc
        limit 12) s),
    'population', jsonb_build_object(
      'category_nodes', (select count(*) from graph_nodes where kind='category'),
      'adjacency_edges', (select count(*) from graph_edges where rel='adjacent_to' and src_kind='category'),
      'listed_companies', (select count(distinct lead_id) from lead_category))
  );
$function$;

comment on function public.fn_supplier_knowledge_graph(bigint) is
  'Row #5 §23. The supplier-reachable view of the knowledge graph: the categories this company is '
  'listed in and the adjacent categories its competitors also serve, read from graph_nodes and '
  'graph_edges. Returns category structure ONLY — employee, department and goal nodes are the '
  'internal org chart and are never selected.';
