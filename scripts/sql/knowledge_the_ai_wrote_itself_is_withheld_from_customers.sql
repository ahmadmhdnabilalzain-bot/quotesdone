-- KNOWLEDGE THE AI WROTE ITSELF IS WITHHELD FROM CUSTOMERS. Seat: customer_support (what a customer or supplier is told);
-- the routines are owned by it_engineer. 27 Oct 2026. Founder ruling 1338 (public.founder_instruction).
--
-- THE RULING. Asked, 27 Oct 2026 ~13:50Z: "1,317 knowledge rows that the AI wrote itself (including 'Typical Cost Ranges
-- (AED)' per trade) are currently shown to customers in chat. No one ever opened a source page to check them. Your 7 Oct
-- rule says a fact not read on a page actually opened is never stated to a customer. Should these rows be withheld from
-- customers?" His answer: "Withhold from customers." Internal seats may still use them; a row becomes customer-facing
-- only once it is checked against a source page.
--
-- MEASURED on production 27 Oct 2026, read-only: kb_chunks 54,360 rows; source_kind 'generated' 1,317 (model-written
-- trade knowledge) and 'memory' 53 (agent working notes), every one of them with a gte vector and an ml vector, so both
-- routines can rank them. No row has a null source_kind. The live bodies of both routines equal this file's base,
-- scripts/sql/a_trade_question_reads_its_own_trade_pack.sql (the last MANIFEST entry defining them), apart from the
-- dollar-quote tag.
--   fn_reason_retrieve: the kb_chunks branch had no audience predicate; a customer, supplier or visitor got the same
--   kb_chunks rows as an internal seat. fn_reason_retrieve_ml: the same in its final kb_chunks hits.
--   think() (support_reply, ai_reply, site_assistant, customer_api, supplier_api, wa_inbound and every reasoned_* reader)
--   retrieves through these two with p_audience, so this is every think()-based customer and supplier path.
--
-- CHANGE (CREATE OR REPLACE, signatures, search_path, settings and ACL unchanged; the revoke and grant are restated as in
-- the base file; each routine has ONE overload, enumerated live 27 Oct 2026):
--   fn_reason_retrieve     kb_chunks branch: (v_internal or source_kind not in ('generated', 'memory')), NULL withheld.
--   fn_reason_retrieve_ml  final kb_chunks hits: the same predicate. The candidate stage is unchanged (it ranks through
--                          the HNSW indexes and knowledge_vector_ml carries no source_kind), so an external audience
--                          simply gets no such row back.
--   Every other line is the base file's, byte for byte.
-- The edge copy of the same list is supabase/functions/_shared/customer_facing_knowledge.ts (portal_turn customerSafe
-- for fn_sales_assist, inquiry_intake for kb_query); scripts/checks/knowledge_the_ai_wrote_itself_is_withheld_from_
-- customers.test.mjs keeps the two equal.
--
-- NOT CHANGED, and said plainly:
--   - fn_knowledge_library_source_sql still marks every kb_chunks row verified = true (generated and memory included).
--     The library is not read by any customer path today (fn_reason_retrieve no longer hands off to it; 2 kb_chunks rows
--     are in it) and its 'verified' column gates no audience. Phase 2 of the library must carry this rule before it
--     serves a customer: fn_reason_retrieve_library / _ml_library take no p_audience at all.
--   - fn_sales_assist and kb_query still return generated rows to their callers; the two customer-facing callers filter
--     them at the edge (above). Internal callers keep them, as the ruling allows.
--   - No row is changed or deleted. A generated row that is later checked against a source page should get the
--     source_kind of what it was read from; until then it stays internal.
--
-- PROVED (rolled back): knowledge_the_ai_wrote_itself_is_withheld_from_customers_probe.sql, run in ONE query after this
--   file, on production: an internal caller gets a generated row back from both routines; a customer, supplier, visitor
--   or NULL audience does not; a read-source row ('standard') still reaches a customer. Against the live routines alone
--   the same probe reports the customer receiving the generated row.
-- Prevented by: scripts/checks/knowledge_the_ai_wrote_itself_is_withheld_from_customers.test.mjs (fails if either
--   routine's kb_chunks branch loses the audience predicate, or the SQL and edge lists differ).
-- APPLY at merge (release operator): node scripts/apply_sql.mjs scripts/sql/knowledge_the_ai_wrote_itself_is_withheld_
--   from_customers.sql --apply --ddl; then delete its pending note and append it to the END of MANIFEST.txt. No trigger,
--   no table lock beyond the routine replace.

select '[1]'::vector <-> '[1]'::vector as loads_pgvector;

CREATE OR REPLACE FUNCTION public.fn_reason_retrieve(p_seat text, p_embedding vector, p_k integer DEFAULT 6, p_trade text DEFAULT NULL::text, p_kind text DEFAULT NULL::text, p_area text DEFAULT NULL::text, p_audience text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
 SET "hnsw.iterative_scan" TO 'relaxed_order'
 SET "hnsw.ef_search" TO '100'
AS $fn$
declare
  k   integer := greatest(1, least(coalesce(p_k, 6), 12));
  out jsonb := '[]'::jsonb;
  v_trade text[];  -- 'trade:<code>' of the resolved trade; NULL = no trade resolved
  v_kind  text;    -- the trade's resolved topic: a kind one of its entries carries; NULL = any kind
  v_area  text;    -- the seat's resolved area: an area one of its own rows carries; NULL = every area
  -- ONLY AN AUDIENCE NAMED internal OR founder reads the company's own facts and gets the own-row reservation.
  -- customer, supplier, visitor, a NULL or any other value: external (fails closed, as settledFacts() in think.ts).
  v_internal constant boolean := lower(btrim(coalesce(p_audience, ''))) in ('internal', 'founder');
  -- MARKET OR PRICING, BY MEANING: the kind tags a trade's market and pricing entries carry. The planner names a kind
  -- (think.ts ENTRY_KINDS, chosen by the model from the question's meaning); no word of the question is read here.
  v_market constant text[] := array['kind:uae_market_products', 'kind:uae_market_brands', 'kind:uae_market_sizes',
    'kind:price_driver', 'kind:price_drivers', 'kind:pricing_basis', 'kind:pricing_rule', 'kind:pricing_structure',
    'kind:pricing_reference', 'kind:pricing_benchmark', 'kind:market_practice', 'kind:market_reference'];
  v_lead_market boolean;   -- the trade resolved and the planner says the question is about its market or pricing
begin
  -- 1. RESOLVE, exactly or not at all. The trade through the estate's exact resolver; the kind and the area only
  --    when a row of this trade / of this seat's own table is tagged with exactly that value. No word is read.
  select array_agg('trade:' || c) into v_trade from unnest(public.fn_norm_trades(p_trade)) c;
  v_kind := nullif(lower(btrim(coalesce(p_kind, ''))), '');
  if v_trade is null or (v_kind is not null and not exists (select 1 from public.sales_knowledge x
       where x.tags && v_trade and x.tags @> array['kind:' || v_kind])) then v_kind := null; end if;
  v_lead_market := coalesce(v_trade is not null and ('kind:' || v_kind) = any(v_market), false);   -- never NULL: a NULL would sort FIRST under DESC
  v_area := nullif(lower(btrim(coalesce(p_area, ''))), '');
  if v_area is not null and not exists (
       select 1 from public.sales_knowledge x        where p_seat = 'sales_engineer'   and x.tags @> array['area:' || v_area]
       union all select 1 from public.accountant_knowledge x  where p_seat = 'accountant'       and x.tags @> array['area:' || v_area]
       union all select 1 from public.it_engineer_knowledge x where p_seat = 'it_engineer'      and x.tags @> array['area:' || v_area]
       union all select 1 from public.support_knowledge x     where p_seat = 'customer_support' and x.tags @> array['area:' || v_area]
       union all select 1 from public.ceo_knowledge x         where p_seat = 'ceo'              and x.tags @> array['area:' || v_area]
       union all select 1 from public.marketing_knowledge x   where p_seat = 'marketing'        and x.tags @> array['area:' || v_area]) then
    v_area := null;
  end if;
  -- 2. FILTER BEFORE RANKING (the TRADE and AREA predicates below). 3. Nothing resolved: exactly the ranking before.
  if p_embedding is null then return out; end if;

  with hits as (
    (select 'kb_chunks' src, c.id::text id, c.title, left(c.content, 1200) excerpt, c.citation,
            1 - (c.embedding_gte <=> p_embedding) sim, 'reviewed' trust, false mine
       from public.kb_chunks c where c.embedding_gte is not null
        -- founder ruling 1338 (27 Oct 2026): a row a model or an agent wrote is never told to an outside audience
        and (v_internal or coalesce(c.source_kind not in ('generated', 'memory'), false))
      order by c.embedding_gte <=> p_embedding limit k)
    union all
    (select 'ops_knowledge', o.record_id, o.title, left(o.content, 1200), o.source_path,
            1 - (o.embedding_gte <=> p_embedding), 'reviewed', false
       from public.ops_knowledge o
      where o.embedding_gte is not null and o.runtime_eligible and o.supersession_state = 'current'
        and o.scope_type in ('company', 'external_source', 'category') and o.dept_key is null
      order by o.embedding_gte <=> p_embedding limit k)
    union all
    (select 'agent_knowledge', a.id::text, a.topic, left(a.content, 1200), a.source_ref,
            1 - (a.embedding_gte <=> p_embedding), 'reviewed', a.agent_key = p_seat
       from public.agent_knowledge a
      where a.embedding_gte is not null and (a.agent_key = '_global' or (v_internal and a.agent_key = p_seat))
      order by a.embedding_gte <=> p_embedding limit k)
    union all
    (select 'company_faq', f.id::text, f.question, left(f.answer, 1200), 'FAQ ' || f.id,
            1 - (f.embedding_gte <=> p_embedding), 'reviewed', false
       from public.company_faq f where f.embedding_gte is not null and f.status = 'approved'
      order by f.embedding_gte <=> p_embedding limit k)
    union all
    (select 'sales_knowledge', s.record_id, s.title, left(s.content, 2400), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed', true
       from public.sales_knowledge s
      where s.embedding_gte is not null and s.runtime_index_eligible
        and (p_seat = 'sales_engineer' or (p_seat = 'customer_support' and s.pack_id like 'verified:trade:%'))
        and (v_trade is null or not exists (select 1 from unnest(s.tags) t where t like 'trade:%')
             or (s.tags && v_trade and (v_kind is null or s.tags @> array['kind:' || v_kind] or (('kind:' || v_kind) = any(v_market) and s.tags && v_market))))
        and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%')))
      order by (v_trade is not null and s.tags && v_trade) desc, s.embedding_gte <=> p_embedding limit case when v_trade is null then k else 128 end)
    union all
    (select 'accountant_knowledge', s.record_id, s.title, left(s.content, 2400), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed', true
       from public.accountant_knowledge s
      where p_seat = 'accountant' and s.embedding_gte is not null and s.runtime_index_eligible
        and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%')))
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'it_engineer_knowledge', s.record_id, s.title, left(s.content, 2400), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed', true
       from public.it_engineer_knowledge s
      where p_seat = 'it_engineer' and s.embedding_gte is not null and s.runtime_index_eligible
        and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%')))
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'support_knowledge', s.record_id, s.title, left(s.body, 2400), coalesce(s.source_path, s.pack_id),
            1 - (s.embedding_gte <=> p_embedding), 'reviewed', true
       from public.support_knowledge s
      where p_seat = 'customer_support' and s.embedding_gte is not null and coalesce(s.runtime_index_eligible, true)
        and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%')))
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'ceo_knowledge', s.record_id, s.title, left(s.body, 2400), coalesce(s.source_path, s.pack_fingerprint),
            1 - (s.embedding_gte <=> p_embedding), 'reviewed', true
       from public.ceo_knowledge s
      where p_seat = 'ceo' and s.embedding_gte is not null and s.runtime_index_eligible
        and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%')))
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'marketing_knowledge', s.record_id, s.title, left(s.content, 2400), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed', true
       from public.marketing_knowledge s
      where p_seat = 'marketing' and s.embedding_gte is not null and s.runtime_index_eligible
        and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%')))
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'research', r.id::text, left(r.question, 200), r.finding, r.sources->0->>'url',
            1 - (r.embedding_gte <=> p_embedding), case when r.status = 'approved' then 'reviewed' else 'pending_review' end, false
       from public.reasoning_knowledge_candidate r
      where r.embedding_gte is not null and r.status <> 'rejected' and (v_internal or r.status = 'approved')
      order by r.embedding_gte <=> p_embedding limit k)
  )
  -- THE TRADE'S OWN PACK FIRST, THEN THE SEAT'S OWN ROWS (internal only), THEN THE REST. When the trade resolves, its
  -- best k pack rows (base and market) are reserved, by similarity; when the planner says the question is about the
  -- market or pricing, its market and pricing rows lead them. Trade packs are public, so this holds for every audience; #1567's
  -- audience guard has already removed any internal row.
  select coalesce(jsonb_agg(jsonb_build_object('source', src, 'id', id, 'title', title, 'excerpt', excerpt,
           'citation', citation, 'similarity', round(sim::numeric, 4), 'trust', trust, 'own', mine) order by reserved desc, tr nulls last, sim desc), '[]'::jsonb)
    into out
    from (select * from (
            select h.*, t.tr,
                   case when t.tr <= k then 2
                        when v_internal and h.mine and t.tr is null
                         and row_number() over (partition by h.mine and t.tr is null order by h.sim desc) <= k then 1
                        else 0 end reserved
              from hits h
              left join (select h2.id, row_number() over (order by (v_lead_market and s.tags && v_market) desc, h2.sim desc) tr
                           from hits h2 join public.sales_knowledge s on h2.src = 'sales_knowledge' and s.record_id = h2.id
                          where v_trade is not null and s.tags && v_trade) t on h.src = 'sales_knowledge' and t.id = h.id) x
           order by reserved desc, tr nulls last, sim desc limit k * 2) y;
  return out;
end $fn$;

revoke execute on function public.fn_reason_retrieve(text, vector, integer, text, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_reason_retrieve(text, vector, integer, text, text, text, text) to service_role;

CREATE OR REPLACE FUNCTION public.fn_reason_retrieve_ml(p_seat text, p_embedding vector, p_embedding_gte vector DEFAULT NULL::vector, p_k integer DEFAULT 6, p_own integer DEFAULT 3, p_trade text DEFAULT NULL::text, p_kind text DEFAULT NULL::text, p_area text DEFAULT NULL::text, p_audience text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
 SET "hnsw.iterative_scan" TO 'relaxed_order'
 SET "hnsw.ef_search" TO '100'
AS $fn$
declare
  k    integer := greatest(1, least(coalesce(p_k, 6), 12));
  own  integer := case when lower(btrim(coalesce(p_audience, ''))) in ('internal', 'founder') then least(greatest(coalesce(p_own, 3), k), 2 * k) else 0 end;  -- internal: own rows fill at least half of the k * 2 returned; external: no reservation
  n    constant integer := 20;
  g    vector(384) := p_embedding_gte;
  m    vector(384) := p_embedding;
  out  jsonb := '[]'::jsonb;
  v_trade text[];  -- 'trade:<code>' of the resolved trade; NULL = no trade resolved
  v_kind  text;    -- the trade's resolved topic: a kind one of its entries carries; NULL = any kind
  v_area  text;    -- the seat's resolved area: an area one of its own rows carries; NULL = every area
  -- ONLY AN AUDIENCE NAMED internal OR founder reads the company's own facts and gets the own-row reservation.
  -- customer, supplier, visitor, a NULL or any other value: external (fails closed, as settledFacts() in think.ts).
  v_internal constant boolean := lower(btrim(coalesce(p_audience, ''))) in ('internal', 'founder');
  -- MARKET OR PRICING, BY MEANING: the kind tags a trade's market and pricing entries carry. The planner names a kind
  -- (think.ts ENTRY_KINDS, chosen by the model from the question's meaning); no word of the question is read here.
  v_market constant text[] := array['kind:uae_market_products', 'kind:uae_market_brands', 'kind:uae_market_sizes',
    'kind:price_driver', 'kind:price_drivers', 'kind:pricing_basis', 'kind:pricing_rule', 'kind:pricing_structure',
    'kind:pricing_reference', 'kind:pricing_benchmark', 'kind:market_practice', 'kind:market_reference'];
  v_lead_market boolean;   -- the trade resolved and the planner says the question is about its market or pricing
begin
  -- 1. RESOLVE, exactly or not at all. The trade through the estate's exact resolver; the kind and the area only
  --    when a row of this trade / of this seat's own table is tagged with exactly that value. No word is read.
  select array_agg('trade:' || c) into v_trade from unnest(public.fn_norm_trades(p_trade)) c;
  v_kind := nullif(lower(btrim(coalesce(p_kind, ''))), '');
  if v_trade is null or (v_kind is not null and not exists (select 1 from public.sales_knowledge x
       where x.tags && v_trade and x.tags @> array['kind:' || v_kind])) then v_kind := null; end if;
  v_lead_market := coalesce(v_trade is not null and ('kind:' || v_kind) = any(v_market), false);   -- never NULL: a NULL would sort FIRST under DESC
  v_area := nullif(lower(btrim(coalesce(p_area, ''))), '');
  if v_area is not null and not exists (
       select 1 from public.sales_knowledge x        where p_seat = 'sales_engineer'   and x.tags @> array['area:' || v_area]
       union all select 1 from public.accountant_knowledge x  where p_seat = 'accountant'       and x.tags @> array['area:' || v_area]
       union all select 1 from public.it_engineer_knowledge x where p_seat = 'it_engineer'      and x.tags @> array['area:' || v_area]
       union all select 1 from public.support_knowledge x     where p_seat = 'customer_support' and x.tags @> array['area:' || v_area]
       union all select 1 from public.ceo_knowledge x         where p_seat = 'ceo'              and x.tags @> array['area:' || v_area]
       union all select 1 from public.marketing_knowledge x   where p_seat = 'marketing'        and x.tags @> array['area:' || v_area]) then
    v_area := null;
  end if;
  -- 2. FILTER BEFORE RANKING (the TRADE and AREA predicates below). 3. Nothing resolved: exactly the ranking before.
  if m is null then return out; end if;
  with cand as (
    -- kb_chunks: both spaces through their HNSW indexes
    (select 'kb_chunks' src, v.row_id from public.knowledge_vector_ml v where v.src = 'kb_chunks' order by v.embedding <=> m limit n)
    union (select 'kb_chunks', c.id::text from public.kb_chunks c where g is not null and c.embedding_gte is not null order by c.embedding_gte <=> g limit n)
    union (select 'ops_knowledge', o.record_id from public.knowledge_vector_ml v join public.ops_knowledge o on v.src = 'ops_knowledge' and o.record_id = v.row_id
            where o.runtime_eligible and o.supersession_state = 'current' and o.scope_type in ('company', 'external_source', 'category') and o.dept_key is null
            order by v.embedding <=> m limit n)
    union (select 'ops_knowledge', o.record_id from public.ops_knowledge o
            where g is not null and o.embedding_gte is not null and o.runtime_eligible and o.supersession_state = 'current'
              and o.scope_type in ('company', 'external_source', 'category') and o.dept_key is null order by o.embedding_gte <=> g limit n)
    union (select 'agent_knowledge', a.id::text from public.knowledge_vector_ml v join public.agent_knowledge a on v.src = 'agent_knowledge' and a.id::text = v.row_id
            where (a.agent_key = '_global' or (v_internal and a.agent_key = p_seat)) order by v.embedding <=> m limit n)
    union (select 'agent_knowledge', a.id::text from public.agent_knowledge a
            where g is not null and a.embedding_gte is not null and (a.agent_key = '_global' or (v_internal and a.agent_key = p_seat)) order by a.embedding_gte <=> g limit n)
    union (select 'company_faq', f.id::text from public.knowledge_vector_ml v join public.company_faq f on v.src = 'company_faq' and f.id::text = v.row_id
            where f.status = 'approved' order by v.embedding <=> m limit n)
    union (select 'company_faq', f.id::text from public.company_faq f
            where g is not null and f.embedding_gte is not null and f.status = 'approved' order by f.embedding_gte <=> g limit n)
    union (select 'reasoning_knowledge_candidate', r.id::text from public.knowledge_vector_ml v
             join public.reasoning_knowledge_candidate r on v.src = 'reasoning_knowledge_candidate' and r.id::text = v.row_id
            where r.status <> 'rejected' and (v_internal or r.status = 'approved') order by v.embedding <=> m limit n)
    union (select 'reasoning_knowledge_candidate', r.id::text from public.reasoning_knowledge_candidate r
            where g is not null and r.embedding_gte is not null and r.status <> 'rejected' and (v_internal or r.status = 'approved') order by r.embedding_gte <=> g limit n)
    -- sales_knowledge: the sales engineer reads all of it; customer_support reads the TRADE packs (what a trade
    -- needs), never the sales seat's own playbook
    union (select 'sales_knowledge', s.record_id from public.knowledge_vector_ml v join public.sales_knowledge s on v.src = 'sales_knowledge' and s.record_id = v.row_id
            where s.runtime_index_eligible and (p_seat = 'sales_engineer' or (p_seat = 'customer_support' and (s.pack_id like 'verified:trade:%' or exists (select 1 from unnest(s.tags) t where t like 'trade:%'))))
            and (v_trade is null or not exists (select 1 from unnest(s.tags) t where t like 'trade:%')
             or (s.tags && v_trade and (v_kind is null or s.tags @> array['kind:' || v_kind] or (('kind:' || v_kind) = any(v_market) and s.tags && v_market))))
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%')))
            order by v.embedding <=> m limit n)
    union (select 'sales_knowledge', s.record_id from public.sales_knowledge s
            where g is not null and s.embedding_gte is not null and s.runtime_index_eligible
              and (p_seat = 'sales_engineer' or (p_seat = 'customer_support' and (s.pack_id like 'verified:trade:%' or exists (select 1 from unnest(s.tags) t where t like 'trade:%'))))
            and (v_trade is null or not exists (select 1 from unnest(s.tags) t where t like 'trade:%')
             or (s.tags && v_trade and (v_kind is null or s.tags @> array['kind:' || v_kind] or (('kind:' || v_kind) = any(v_market) and s.tags && v_market))))
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%')))
            order by s.embedding_gte <=> g limit n)
    -- every row of the resolved trade's own pack is a candidate, whatever its rank in either space
    union (select 'sales_knowledge', s.record_id from public.sales_knowledge s
            where v_trade is not null and s.runtime_index_eligible and s.tags && v_trade
              and (p_seat = 'sales_engineer' or (p_seat = 'customer_support' and (s.pack_id like 'verified:trade:%' or exists (select 1 from unnest(s.tags) t where t like 'trade:%'))))
              and (v_kind is null or s.tags @> array['kind:' || v_kind] or (('kind:' || v_kind) = any(v_market) and s.tags && v_market))
              and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%'))))
    union (select 'accountant_knowledge', s.record_id from public.knowledge_vector_ml v join public.accountant_knowledge s on v.src = 'accountant_knowledge' and s.record_id = v.row_id
            where p_seat = 'accountant' and s.runtime_index_eligible
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%'))) order by v.embedding <=> m limit n)
    union (select 'accountant_knowledge', s.record_id from public.accountant_knowledge s
            where p_seat = 'accountant' and g is not null and s.embedding_gte is not null and s.runtime_index_eligible
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%'))) order by s.embedding_gte <=> g limit n)
    union (select 'it_engineer_knowledge', s.record_id from public.knowledge_vector_ml v join public.it_engineer_knowledge s on v.src = 'it_engineer_knowledge' and s.record_id = v.row_id
            where p_seat = 'it_engineer' and s.runtime_index_eligible
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%'))) order by v.embedding <=> m limit n)
    union (select 'it_engineer_knowledge', s.record_id from public.it_engineer_knowledge s
            where p_seat = 'it_engineer' and g is not null and s.embedding_gte is not null and s.runtime_index_eligible
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%'))) order by s.embedding_gte <=> g limit n)
    union (select 'marketing_knowledge', s.record_id from public.knowledge_vector_ml v join public.marketing_knowledge s on v.src = 'marketing_knowledge' and s.record_id = v.row_id
            where p_seat = 'marketing' and s.runtime_index_eligible
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%'))) order by v.embedding <=> m limit n)
    union (select 'marketing_knowledge', s.record_id from public.marketing_knowledge s
            where p_seat = 'marketing' and g is not null and s.embedding_gte is not null and s.runtime_index_eligible
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%'))) order by s.embedding_gte <=> g limit n)
    union (select 'ceo_knowledge', v.row_id from public.knowledge_vector_ml v join public.ceo_knowledge s on v.src = 'ceo_knowledge' and s.record_id = v.row_id
            where p_seat = 'ceo' and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%'))) order by v.embedding <=> m limit n)
    union (select 'ceo_knowledge', s.record_id from public.ceo_knowledge s
            where p_seat = 'ceo' and g is not null and s.embedding_gte is not null
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%'))) order by s.embedding_gte <=> g limit n)
    union (select 'support_knowledge', v.row_id from public.knowledge_vector_ml v join public.support_knowledge s on v.src = 'support_knowledge' and s.record_id = v.row_id
            where p_seat = 'customer_support' and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%'))) order by v.embedding <=> m limit n)
    union (select 'support_knowledge', s.record_id from public.support_knowledge s
            where p_seat = 'customer_support' and g is not null and s.embedding_gte is not null
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%'))) order by s.embedding_gte <=> g limit n)
  ), sims as (
    -- both similarities for every candidate; a CASE evaluates only its own branch, so a text key is never cast
    select c.src, c.row_id,
           (select 1 - (v.embedding <=> m) from public.knowledge_vector_ml v where v.src = c.src and v.row_id = c.row_id) s_ml,
           case when g is null then null else case c.src
             when 'kb_chunks' then (select 1 - (x.embedding_gte <=> g) from public.kb_chunks x where x.id = c.row_id::bigint)
             when 'ops_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.ops_knowledge x where x.record_id = c.row_id)
             when 'agent_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.agent_knowledge x where x.id = c.row_id::bigint)
             when 'company_faq' then (select 1 - (x.embedding_gte <=> g) from public.company_faq x where x.id = c.row_id::bigint)
             when 'reasoning_knowledge_candidate' then (select 1 - (x.embedding_gte <=> g) from public.reasoning_knowledge_candidate x where x.id = c.row_id::bigint)
             when 'sales_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.sales_knowledge x where x.record_id = c.row_id)
             when 'accountant_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.accountant_knowledge x where x.record_id = c.row_id)
             when 'it_engineer_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.it_engineer_knowledge x where x.record_id = c.row_id)
             when 'marketing_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.marketing_knowledge x where x.record_id = c.row_id)
             when 'ceo_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.ceo_knowledge x where x.record_id = c.row_id)
             when 'support_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.support_knowledge x where x.record_id = c.row_id)
           end end s_gte
      from cand c
  ), ranked as (
    select s.*,
           case when s_ml is not null then row_number() over (order by s_ml desc nulls last) end r_ml,
           case when s_gte is not null then row_number() over (order by s_gte desc nulls last) end r_gte
      from sims s
  ), gaps as (
    -- decisiveness: best minus 21st (or the last, when there are fewer candidates)
    select coalesce(max(s_ml) - coalesce(max(s_ml) filter (where r_ml = n + 1), min(s_ml)), 0) d_ml,
           coalesce(max(s_gte) - coalesce(max(s_gte) filter (where r_gte = n + 1), min(s_gte)), 0) d_gte
      from ranked
  ), scored as (
    select r.*,
           case when r.r_ml is null and r.r_gte is not null then 1.0 / (60 + r.r_gte) else
           coalesce(case when gp.d_ml + gp.d_gte > 0 then gp.d_ml / (gp.d_ml + gp.d_gte) else 1 end / (60 + r.r_ml), 0)
         + coalesce(case when gp.d_ml + gp.d_gte > 0 then gp.d_gte / (gp.d_ml + gp.d_gte) else 0 end / (60 + r.r_gte), 0) end score
      from ranked r cross join gaps gp
  ), hits as (
    -- a bigint key is cast only inside its own source's rows (scored is materialised; the filter runs first)
    (select 'kb_chunks' src, c.id::text id, c.title, left(c.content, 1200) excerpt, c.citation, coalesce(sc.s_ml, sc.s_gte) s_ml, sc.score, 'reviewed' trust, false mine
       from (select *, row_id::bigint key from scored where src = 'kb_chunks') sc join public.kb_chunks c on c.id = sc.key
      -- founder ruling 1338 (27 Oct 2026): a row a model or an agent wrote is never told to an outside audience
      where v_internal or coalesce(c.source_kind not in ('generated', 'memory'), false)
      order by sc.score desc limit k)
    union all
    (select 'ops_knowledge', o.record_id, o.title, left(o.content, 1200), o.source_path, coalesce(sc.s_ml, sc.s_gte) s_ml, sc.score, 'reviewed', false
       from scored sc join public.ops_knowledge o on sc.src = 'ops_knowledge' and o.record_id = sc.row_id
      order by sc.score desc limit k)
    union all
    (select 'agent_knowledge', a.id::text, a.topic, left(a.content, 1200), a.source_ref, coalesce(sc.s_ml, sc.s_gte) s_ml, sc.score, 'reviewed', a.agent_key = p_seat
       from (select *, row_id::bigint key from scored where src = 'agent_knowledge') sc join public.agent_knowledge a on a.id = sc.key
      order by sc.score desc limit k)
    union all
    (select 'company_faq', f.id::text, f.question, left(f.answer, 1200), 'FAQ ' || f.id, coalesce(sc.s_ml, sc.s_gte) s_ml, sc.score, 'reviewed', false
       from (select *, row_id::bigint key from scored where src = 'company_faq') sc join public.company_faq f on f.id = sc.key
      order by sc.score desc limit k)
    union all
    (select 'research', r.id::text, left(r.question, 200), r.finding, r.sources->0->>'url', coalesce(sc.s_ml, sc.s_gte) s_ml, sc.score,
            case when r.status = 'approved' then 'reviewed' else 'pending_review' end, false
       from (select *, row_id::bigint key from scored where src = 'reasoning_knowledge_candidate') sc join public.reasoning_knowledge_candidate r on r.id = sc.key
      where r.status <> 'rejected' and (v_internal or r.status = 'approved')
      order by sc.score desc limit k)
    union all
    (select 'sales_knowledge', s.record_id, s.title, left(s.content, 2400), s.pack_id, coalesce(sc.s_ml, sc.s_gte) s_ml, sc.score, 'reviewed', true
       from scored sc join public.sales_knowledge s on sc.src = 'sales_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit case when v_trade is null then k else 128 end)
    union all
    (select 'accountant_knowledge', s.record_id, s.title, left(s.content, 2400), s.pack_id, coalesce(sc.s_ml, sc.s_gte) s_ml, sc.score, 'reviewed', true
       from scored sc join public.accountant_knowledge s on sc.src = 'accountant_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
    union all
    (select 'it_engineer_knowledge', s.record_id, s.title, left(s.content, 2400), s.pack_id, coalesce(sc.s_ml, sc.s_gte) s_ml, sc.score, 'reviewed', true
       from scored sc join public.it_engineer_knowledge s on sc.src = 'it_engineer_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
    union all
    (select 'marketing_knowledge', s.record_id, s.title, left(s.content, 2400), s.pack_id, coalesce(sc.s_ml, sc.s_gte) s_ml, sc.score, 'reviewed', true
       from scored sc join public.marketing_knowledge s on sc.src = 'marketing_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
    union all
    (select 'ceo_knowledge', s.record_id, s.title, left(s.body, 2400), s.source_path, coalesce(sc.s_ml, sc.s_gte) s_ml, sc.score, 'reviewed', true
       from scored sc join public.ceo_knowledge s on sc.src = 'ceo_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
    union all
    (select 'support_knowledge', s.record_id, s.title, left(s.body, 2400), s.source_path, coalesce(sc.s_ml, sc.s_gte) s_ml, sc.score, 'reviewed', true
       from scored sc join public.support_knowledge s on sc.src = 'support_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
  ), trade_rows as (
    -- THE TRADE'S OWN PACK FIRST, THEN THE SEAT'S OWN ROWS (internal only), THEN THE REST. When the trade resolves, its
    -- best k pack rows (base and market) are reserved, by similarity; when the planner says the question is about the
    -- market or pricing, its market and pricing rows lead them. Trade packs are public, so this holds for every audience; #1567's
    -- audience guard has already removed any internal row.
    select h.*, row_number() over (order by (v_lead_market and s.tags && v_market) desc, h.score desc) tr
      from hits h join public.sales_knowledge s on h.src = 'sales_knowledge' and s.record_id = h.id
     where v_trade is not null and s.tags && v_trade
     order by tr limit k
  ), own_rows as (
    select h.*, null::bigint tr from hits h
     where h.mine and not exists (select 1 from trade_rows t where t.src = h.src and t.id = h.id)
     order by h.score desc limit least(own, k * 2 - (select count(*) from trade_rows))
  ), chosen as (
    select t.*, 2 reserved from trade_rows t
    union all
    select o.*, 1 from own_rows o
    union all
    select *, 0 from (select h.*, null::bigint tr from hits h
                       where not exists (select 1 from trade_rows t where t.src = h.src and t.id = h.id)
                         and not exists (select 1 from own_rows o where o.src = h.src and o.id = h.id)
                       order by h.score desc limit greatest(k * 2 - (select count(*) from trade_rows) - (select count(*) from own_rows), 0)) rest
  )
  select coalesce(jsonb_agg(jsonb_build_object('source', src, 'id', id, 'title', title, 'excerpt', excerpt,
           'citation', citation, 'similarity', round(coalesce(s_ml, 0)::numeric, 4), 'score', round(score::numeric, 6),
           'trust', trust, 'own', mine) order by reserved desc, tr nulls last, score desc), '[]'::jsonb)
    into out
    from chosen;
  return out;
end $fn$;

revoke execute on function public.fn_reason_retrieve_ml(text, vector, vector, integer, integer, text, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_reason_retrieve_ml(text, vector, vector, integer, integer, text, text, text, text) to service_role;
