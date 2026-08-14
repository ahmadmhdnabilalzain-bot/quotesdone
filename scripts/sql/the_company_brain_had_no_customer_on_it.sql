-- THE COMPANY BRAIN HAD NO CUSTOMER ON IT
--
-- Row #3 §"company-map-entities" wants departments, processes, employees, customers, suppliers and
-- knowledge on one connected canvas. Five of the six were already node kinds; `customer` was not,
-- so the map of a marketplace had no buyer side at all. Measured on production before this change:
-- graph_nodes held 870 nodes of kind category/department/employee/goal/knowledge/operating_system/
-- responsibility/supplier_pool/workflow — 5 of the 6 named classes.
--
-- §22 ("the spec chain can be walked through relationships") wants the whole trade chain as node
-- kinds AND as edges: customer -> rfq -> category -> supplier -> quote -> revenue -> campaign ->
-- knowledge -> employee. Four of the nine classes existed and one of the eight hops.
--
-- WHAT THIS DOES NOT DO: invent a row so a class exists. Production holds 0 inquiries, 0 quotes and
-- 0 transactions, so the rfq/quote/revenue legs below emit NOTHING today and §22 stays MISSING at
-- 6 of 9 classes and 2 of 8 hops. That is the correct verdict for a marketplace that has not yet
-- traded: the map is complete and populates itself on the first real RFQ. Turning it green would
-- require fabricating an inquiry, which the founder has ruled out and which would be a lie about
-- revenue on the founder's own dashboard.
--
-- THE TWO NEW EDGES THAT ARE REAL TODAY:
--   knowledge -> employee, from kb_usage_log (144 rows in 7d, agent + category) — which knowledge
--     an employee actually consulted, not which topics they nominally hold. agent_knowledge.topic
--     was tried first and is the wrong join: measured, 0 of its 1,942 rows carry a topic that equals
--     a kb_chunks category. Two vocabularies, and only kb_usage_log speaks the graph's.
--   customer -> rfq, rfq -> category, supplier -> quote, quote -> revenue, revenue -> campaign,
--     campaign -> knowledge — all present as mechanism, all empty until trade happens.

create or replace function public.fn_graph_rebuild()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
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
  -- THE SUPPLY BOOK. One node per category pool rather than 20,470 dots, built from v_supply_gap so
  -- the map and the supply reports read from the same numbers. The label carries the state, so the
  -- node says something.
  union all select 'supplier_pool', g.slug,
         g.name || ' — ' || g.sendable || ' sendable, ' || g.invited || ' invited, ' || g.approved || ' approved'
    from v_supply_gap g
  -- THE KNOWLEDGE BASE. One node per KB category with its depth.
  union all select 'knowledge', k.category, k.category || ' — ' || k.n || ' chunk(s)'
    from (select category, count(*) n from kb_chunks where category is not null group by category) k
  -- ...and one per KNOWLEDGE DOMAIN the employees actually hold. These are a second, coarser
  -- vocabulary than the kb_chunks slugs ('UAE Regulations & Authorities' beside 'cat:signage'),
  -- and they are the only one that joins to an employee: measured, 0 of agent_knowledge's 1,942
  -- rows carry a topic equal to a kb_chunks category. Without these the knowledge->employee hop
  -- cannot be drawn at all.
  union all select 'knowledge', t.topic, t.topic || ' — held by ' || t.n || ' employee(s)'
    from (select topic, count(distinct agent_key) n from agent_knowledge
           where agent_key <> '_global' and topic is not null group by topic) t
  -- THE BUYER SIDE. One node per real customer. This is the class the map was missing: a
  -- marketplace brain that drew its supply pools, its departments and its knowledge, and no buyer.
  union all select 'customer', c.id::text,
         coalesce(nullif(btrim(c.full_name), ''), c.email, c.id::text)
    from customers c
  -- THE TRADE CHAIN. Empty today (0 inquiries, 0 quotes, 0 transactions) and deliberately left
  -- empty rather than seeded: each of these becomes a node the moment the business does the thing.
  union all select 'rfq', i.id::text,
         coalesce('RFQ #' || i.rfq_no::text, 'RFQ ' || left(i.id::text, 8))
         || ' — ' || coalesce(i.category, 'uncategorised') || ', ' || coalesce(i.status, 'new')
    from inquiries i
  union all select 'quote', q.id::text,
         'Quote ' || left(q.id::text, 8) || ' — AED ' || coalesce(q.customer_price, q.quote_amount, 0)::text
    from quotes q
  union all select 'revenue', t.id::text,
         'Reveal ' || left(t.id::text, 8) || ' — AED ' || coalesce(t.reveal_fee, t.app_fee, 0)::text
    from transactions t
  -- MARKETING. One node per piece of content the marketing employees actually produced.
  union all select 'campaign', d.id::text,
         coalesce(nullif(btrim(d.title), ''), 'draft ' || d.id::text)
         || ' — ' || coalesce(d.channel, 'unrouted') || ', ' || coalesce(d.status, 'draft')
    from content_drafts d
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
  -- Both hang off the category node that already exists, which is what makes the map walkable:
  -- department -> category -> supplier pool, and department -> category -> knowledge.
  union all
  select 'category', g.slug, 'supplied_by', 'supplier_pool', g.slug from v_supply_gap g
  union all
  select 'category', regexp_replace(k.category,'^cat:',''), 'documented_by', 'knowledge', k.category
    from (select distinct category from kb_chunks where category is not null) k
   where exists (select 1 from catalog_supplier_categories c
                  where c.slug = regexp_replace(k.category,'^cat:',''))
  -- ---- THE TRADE CHAIN, hop by hop ----------------------------------------------------------
  -- customer -> rfq: who asked for what.
  union all
  select distinct 'customer', i.customer_id::text, 'raised', 'rfq', i.id::text
    from inquiries i where i.customer_id is not null
     and exists (select 1 from customers c where c.id = i.customer_id)
  -- rfq -> category: what trade the ask belongs to.
  union all
  select distinct 'rfq', i.id::text, 'in_category', 'category', i.category
    from inquiries i where i.category is not null
     and exists (select 1 from catalog_supplier_categories c where c.slug = i.category)
  -- supplier_pool -> quote: which pool the price came out of. The quote hangs off the pool for the
  -- category of its own inquiry, which is the pool the RFQ was actually sent to.
  union all
  select distinct 'supplier_pool', i.category, 'priced_by', 'quote', q.id::text
    from quotes q join inquiries i on i.id = q.inquiry_id
   where i.category is not null
     and exists (select 1 from v_supply_gap g where g.slug = i.category)
  -- quote -> revenue: the reveal that turned a price into money.
  union all
  select distinct 'quote', t.quote_id::text, 'realised_as', 'revenue', t.id::text
    from transactions t where t.quote_id is not null
  -- revenue -> campaign: the marketing that fed the category the money came from.
  union all
  select distinct 'revenue', t.id::text, 'attributed_to', 'campaign', d.id::text
    from transactions t
    join inquiries i on i.id = t.inquiry_id
    join content_drafts d on d.category = i.category
  -- campaign -> knowledge: the corpus the content was written out of.
  union all
  select distinct 'campaign', d.id::text, 'draws_on', 'knowledge', d.category
    from content_drafts d where d.category is not null
     and exists (select 1 from kb_chunks k where k.category = d.category)
  -- knowledge -> employee: which domain each employee holds. kb_usage_log was tried first and is
  -- the wrong join despite being the usage table: measured, its `category` is the RETRIEVAL CONTEXT
  -- ('agent_context' on 144 of 144 rows), not a KB category, so 0 of its rows join to a knowledge
  -- node. agent_knowledge is the honest source and its topics are emitted as nodes above.
  union all
  select distinct 'knowledge', k.topic, 'held_by', 'employee', k.agent_key
    from agent_knowledge k
   where k.agent_key <> '_global' and k.topic is not null
     and exists (select 1 from org_agents a where a.agent_key = k.agent_key and a.active)
  on conflict do nothing;
  get diagnostics n_edges = row_count;

  -- THE NIGHTLY REBUILD USED TO EAT THE SUPPLIER-MARKET EDGES. fn_graph_supplier_market is careful
  -- in one direction only — it deletes just the `adjacent_to` edges it owns, with a comment saying
  -- it can therefore run independently of the nightly rebuild. The nightly rebuild was not careful
  -- back: `delete from graph_edges` above removes all 242 of its category adjacency edges, which
  -- then stayed missing until that function next ran on its own schedule. Calling it here closes
  -- the loop, so a rebuild always leaves a COMPLETE graph rather than one that is correct only
  -- between 04:05 and whenever the market function happens to run.
  perform public.fn_graph_supplier_market();

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('graph_rebuild',now(),now(),'ok',jsonb_build_object('nodes',n_nodes,'edges',n_edges),
    'Company brain rebuilt: '||n_nodes||' nodes, '||n_edges||' edges.');
  return jsonb_build_object('nodes',n_nodes,'edges',n_edges);
end $function$;
