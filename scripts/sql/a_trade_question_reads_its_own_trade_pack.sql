-- A TRADE QUESTION READS ITS OWN TRADE PACK. Seat: ceo (company knowledge), routines owned by it_engineer. 19 Oct 2026.
-- Builds on a_seats_own_pack_fills_half_of_every_retrieval.sql (#1567, applied): same signatures, same audience rule.
--
-- MEASURED: the live knowledge-pack eval (main 884817e) put 36 trade market packs and real_estate_services below the
-- EN recall floor of 0.35 for sales_engineer and customer_support (71 of their 74 pack-seat pairs). Read-only checks:
-- every one of those packs is loaded and current (6 rows each, trade tag, runtime_index_eligible, gte vectors,
-- pack_version = the repository's), so nothing was missing. Two causes:
--   1. RANKING. Asked the way think() asks once the trade is known (p_trade), fn_reason_retrieve_ml still ranked a
--      trade's short market entry below generic kb_chunks and its own base pack: 19 of 78 EN questions found it.
--   2. NO ML VECTORS. 0 of the 5,102 trade-pack rows had a multilingual vector, so an Arabic question (which carries
--      no gte vector) could not reach them at all: 0 of 78. Cause: z_ml_vectors_stale fires on "UPDATE OF title,
--      content", which Postgres fires whenever those columns are in the SET list, changed or not. Every verified-pack
--      load is an upsert that sets them, so every load deleted every pack row's vector. The backfill run of 08:06
--      stopped at 08:28 on "queue empty" (3,633 embedded); after the 13:04 pack load, 4,910 sales_knowledge rows had
--      none again. Proved in a rolled-back probe: the same text
--      written back cleared the vector (1 -> 0); with this file it stays (1 -> 1), and a real change still clears it.
--
-- CHANGE:
--   fn_reason_retrieve / fn_reason_retrieve_ml (CREATE OR REPLACE, signatures unchanged, ACL restated below):
--     - when p_trade resolves, every row of that trade's pack is a candidate, and its best k rows are RESERVED ahead
--       of the seat's own rows and the rest. Trade packs are public, so this holds for every audience; #1567's
--       audience guard still removes any internal row first.
--     - MARKET OR PRICING BY MEANING: when the planner's kind (think.ts ENTRY_KINDS, chosen by the model; the market
--       file's three kinds are added there) is one of v_market, the kind filter admits the trade's whole market-and-
--       pricing family and those rows lead the reservation. With no kind, the trade's rows are reserved by
--       similarity alone. No word of the question is read.
--   z_ml_vectors_stale on the 13 tables that feed the ml space: split into an UPDATE trigger that fires only when the
--     embedded text is distinct, and a DELETE trigger. After apply, the existing queue (resilience_ping tick, the
--     nightly ml-embed-backfill workflow) embeds the trade rows; nothing is embedded by hand.
-- PROVED (rolled back, fn_reason_retrieve_ml, the 37 packs' eval questions, both seats, staged = the trade rows' ml
--   vectors computed by the backfill's own recipe, as the queue will write them):
--     live routine, trade named:            EN 19/78  AR  0/78  -> this file, vectors staged:  EN 72/78  AR 76/78
--     this file, trade + planner kind:      EN 78/78  AR 78/78  (EN pack-seat pairs below the floor: 71 -> 0)
--   Regression, 30 packs that pass today (154 questions): no configuration lost a question (EN 154/154 stays).
--   Every configuration is in the PR.
-- Prevented by: scripts/checks/a_trade_question_reads_its_own_trade_pack.test.mjs (mutated once: removing the
--   reservation or the text-changed condition fails it), supabase/functions/_shared/think_trade_retrieval.test.ts.
-- APPLY: the trigger section takes an ACCESS EXCLUSIVE lock per table (lock_timeout 5 s); apply outside a campaign hour.

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
    (select 'sales_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed', true
       from public.sales_knowledge s
      where s.embedding_gte is not null and s.runtime_index_eligible
        and (p_seat = 'sales_engineer' or (p_seat = 'customer_support' and s.pack_id like 'verified:trade:%'))
        and (v_trade is null or not exists (select 1 from unnest(s.tags) t where t like 'trade:%')
             or (s.tags && v_trade and (v_kind is null or s.tags @> array['kind:' || v_kind] or (('kind:' || v_kind) = any(v_market) and s.tags && v_market))))
        and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%')))
      order by (v_trade is not null and s.tags && v_trade) desc, s.embedding_gte <=> p_embedding limit case when v_trade is null then k else 128 end)
    union all
    (select 'accountant_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed', true
       from public.accountant_knowledge s
      where p_seat = 'accountant' and s.embedding_gte is not null and s.runtime_index_eligible
        and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%')))
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'it_engineer_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed', true
       from public.it_engineer_knowledge s
      where p_seat = 'it_engineer' and s.embedding_gte is not null and s.runtime_index_eligible
        and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%')))
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'support_knowledge', s.record_id, s.title, left(s.body, 1200), coalesce(s.source_path, s.pack_id),
            1 - (s.embedding_gte <=> p_embedding), 'reviewed', true
       from public.support_knowledge s
      where p_seat = 'customer_support' and s.embedding_gte is not null and coalesce(s.runtime_index_eligible, true)
        and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%')))
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'ceo_knowledge', s.record_id, s.title, left(s.body, 1200), coalesce(s.source_path, s.pack_fingerprint),
            1 - (s.embedding_gte <=> p_embedding), 'reviewed', true
       from public.ceo_knowledge s
      where p_seat = 'ceo' and s.embedding_gte is not null and s.runtime_index_eligible
        and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%')))
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'marketing_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id,
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
    (select 'sales_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id, coalesce(sc.s_ml, sc.s_gte) s_ml, sc.score, 'reviewed', true
       from scored sc join public.sales_knowledge s on sc.src = 'sales_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit case when v_trade is null then k else 128 end)
    union all
    (select 'accountant_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id, coalesce(sc.s_ml, sc.s_gte) s_ml, sc.score, 'reviewed', true
       from scored sc join public.accountant_knowledge s on sc.src = 'accountant_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
    union all
    (select 'it_engineer_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id, coalesce(sc.s_ml, sc.s_gte) s_ml, sc.score, 'reviewed', true
       from scored sc join public.it_engineer_knowledge s on sc.src = 'it_engineer_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
    union all
    (select 'marketing_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id, coalesce(sc.s_ml, sc.s_gte) s_ml, sc.score, 'reviewed', true
       from scored sc join public.marketing_knowledge s on sc.src = 'marketing_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
    union all
    (select 'ceo_knowledge', s.record_id, s.title, left(s.body, 1200), s.source_path, coalesce(sc.s_ml, sc.s_gte) s_ml, sc.score, 'reviewed', true
       from scored sc join public.ceo_knowledge s on sc.src = 'ceo_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
    union all
    (select 'support_knowledge', s.record_id, s.title, left(s.body, 1200), s.source_path, coalesce(sc.s_ml, sc.s_gte) s_ml, sc.score, 'reviewed', true
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

-- THE ML VECTORS SURVIVE A RELOAD THAT DOES NOT CHANGE THE TEXT. "UPDATE OF col" fires whenever the column is in the
-- SET list, so every verified-pack load (an upsert that sets every column) deleted every pack row's ml vector, changed or
-- not. Each table now clears a vector only when the embedded text actually changed, or when the row is deleted.
-- Replacing a trigger takes an ACCESS EXCLUSIVE lock on its table (kb_chunks and seat_case_memory among them): a
-- rolled-back probe of 19 Oct deadlocked with live traffic once. Fail in 5 s rather than queue the seats behind it.
set local lock_timeout = '5s';
drop trigger if exists z_ml_vectors_stale on public.accountant_knowledge;
create trigger z_ml_vectors_stale after update of title, content on public.accountant_knowledge for each row
  when (old.title is distinct from new.title or old.content is distinct from new.content) execute function public.fn_ml_vectors_stale('accountant_knowledge', 'record_id');
create trigger z_ml_vectors_stale_del after delete on public.accountant_knowledge for each row execute function public.fn_ml_vectors_stale('accountant_knowledge', 'record_id');
drop trigger if exists z_ml_vectors_stale on public.agent_knowledge;
create trigger z_ml_vectors_stale after update of topic, content on public.agent_knowledge for each row
  when (old.topic is distinct from new.topic or old.content is distinct from new.content) execute function public.fn_ml_vectors_stale('agent_knowledge', 'id');
create trigger z_ml_vectors_stale_del after delete on public.agent_knowledge for each row execute function public.fn_ml_vectors_stale('agent_knowledge', 'id');
drop trigger if exists z_ml_vectors_stale on public.ceo_knowledge;
create trigger z_ml_vectors_stale after update of title, body on public.ceo_knowledge for each row
  when (old.title is distinct from new.title or old.body is distinct from new.body) execute function public.fn_ml_vectors_stale('ceo_knowledge', 'record_id');
create trigger z_ml_vectors_stale_del after delete on public.ceo_knowledge for each row execute function public.fn_ml_vectors_stale('ceo_knowledge', 'record_id');
drop trigger if exists z_ml_vectors_stale on public.company_faq;
create trigger z_ml_vectors_stale after update of question, answer on public.company_faq for each row
  when (old.question is distinct from new.question or old.answer is distinct from new.answer) execute function public.fn_ml_vectors_stale('company_faq', 'id');
create trigger z_ml_vectors_stale_del after delete on public.company_faq for each row execute function public.fn_ml_vectors_stale('company_faq', 'id');
drop trigger if exists z_ml_vectors_stale on public.it_engineer_knowledge;
create trigger z_ml_vectors_stale after update of title, content on public.it_engineer_knowledge for each row
  when (old.title is distinct from new.title or old.content is distinct from new.content) execute function public.fn_ml_vectors_stale('it_engineer_knowledge', 'record_id');
create trigger z_ml_vectors_stale_del after delete on public.it_engineer_knowledge for each row execute function public.fn_ml_vectors_stale('it_engineer_knowledge', 'record_id');
drop trigger if exists z_ml_vectors_stale on public.kb_chunks;
create trigger z_ml_vectors_stale after update of title, content on public.kb_chunks for each row
  when (old.title is distinct from new.title or old.content is distinct from new.content) execute function public.fn_ml_vectors_stale('kb_chunks', 'id');
create trigger z_ml_vectors_stale_del after delete on public.kb_chunks for each row execute function public.fn_ml_vectors_stale('kb_chunks', 'id');
drop trigger if exists z_ml_vectors_stale on public.kb_chunks_old;
create trigger z_ml_vectors_stale after update of title, content on public.kb_chunks_old for each row
  when (old.title is distinct from new.title or old.content is distinct from new.content) execute function public.fn_ml_vectors_stale('kb_chunks', 'id');
create trigger z_ml_vectors_stale_del after delete on public.kb_chunks_old for each row execute function public.fn_ml_vectors_stale('kb_chunks', 'id');
drop trigger if exists z_ml_vectors_stale on public.marketing_knowledge;
create trigger z_ml_vectors_stale after update of title, content on public.marketing_knowledge for each row
  when (old.title is distinct from new.title or old.content is distinct from new.content) execute function public.fn_ml_vectors_stale('marketing_knowledge', 'record_id');
create trigger z_ml_vectors_stale_del after delete on public.marketing_knowledge for each row execute function public.fn_ml_vectors_stale('marketing_knowledge', 'record_id');
drop trigger if exists z_ml_vectors_stale on public.ops_knowledge;
create trigger z_ml_vectors_stale after update of title, content on public.ops_knowledge for each row
  when (old.title is distinct from new.title or old.content is distinct from new.content) execute function public.fn_ml_vectors_stale('ops_knowledge', 'record_id');
create trigger z_ml_vectors_stale_del after delete on public.ops_knowledge for each row execute function public.fn_ml_vectors_stale('ops_knowledge', 'record_id');
drop trigger if exists z_ml_vectors_stale on public.reasoning_knowledge_candidate;
create trigger z_ml_vectors_stale after update of question, finding on public.reasoning_knowledge_candidate for each row
  when (old.question is distinct from new.question or old.finding is distinct from new.finding) execute function public.fn_ml_vectors_stale('reasoning_knowledge_candidate', 'id');
create trigger z_ml_vectors_stale_del after delete on public.reasoning_knowledge_candidate for each row execute function public.fn_ml_vectors_stale('reasoning_knowledge_candidate', 'id');
drop trigger if exists z_ml_vectors_stale on public.sales_knowledge;
create trigger z_ml_vectors_stale after update of title, content on public.sales_knowledge for each row
  when (old.title is distinct from new.title or old.content is distinct from new.content) execute function public.fn_ml_vectors_stale('sales_knowledge', 'record_id');
create trigger z_ml_vectors_stale_del after delete on public.sales_knowledge for each row execute function public.fn_ml_vectors_stale('sales_knowledge', 'record_id');
drop trigger if exists z_ml_vectors_stale on public.seat_case_memory;
create trigger z_ml_vectors_stale after update of situation on public.seat_case_memory for each row
  when (old.situation is distinct from new.situation) execute function public.fn_ml_vectors_stale('seat_case_memory', 'id');
create trigger z_ml_vectors_stale_del after delete on public.seat_case_memory for each row execute function public.fn_ml_vectors_stale('seat_case_memory', 'id');
drop trigger if exists z_ml_vectors_stale on public.support_knowledge;
create trigger z_ml_vectors_stale after update of title, body on public.support_knowledge for each row
  when (old.title is distinct from new.title or old.body is distinct from new.body) execute function public.fn_ml_vectors_stale('support_knowledge', 'record_id');
create trigger z_ml_vectors_stale_del after delete on public.support_knowledge for each row execute function public.fn_ml_vectors_stale('support_knowledge', 'record_id');
