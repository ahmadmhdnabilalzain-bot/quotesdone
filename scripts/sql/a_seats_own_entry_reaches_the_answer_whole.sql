-- A SEAT'S OWN ENTRY REACHES THE ANSWER WHOLE. Seat: ceo (ledger 1003 stage 2), routines owned by it_engineer.
-- 19 Oct 2026. Stacked on a_seats_own_pack_fills_half_of_every_retrieval.sql (#1567): apply AFTER it.
--
-- MEASURED (real-model seat exam of 19 Oct, main d1ef06e; 228 failed items probed with fn_reason_retrieve_ml on the
-- question, both vectors, p_audience internal): in 39 the expected pack entry WAS retrieved but the fact the answer
-- needed sat past the excerpt's 1,200th character, so the seat said "not established" for a number its own entry
-- states. Pack entries are longer than that excerpt: over 1,200 characters are 238 of 427 it_engineer, 160 of 284
-- marketing, 225 of 722 customer_support, 126 of 399 accountant, 106 of 796 ceo and 22 of 242 sales seat rows; the
-- longest is 2,857 (it_engineer), only 5 rows exceed 2,400.
--
-- CHANGE: the excerpt of a SEAT-PACK row (sales_knowledge, accountant_knowledge, it_engineer_knowledge,
-- marketing_knowledge, ceo_knowledge, support_knowledge) is 2,400 characters instead of 1,200, in both routines.
-- kb_chunks, ops_knowledge, agent_knowledge, company_faq and research keep 1,200. Nothing else in either body changes:
-- not the audience rule, not the reservation, not which rows a caller may read. CREATE OR REPLACE with the same
-- signatures keeps the ACL #1567 set (no new EXECUTE to PUBLIC); the revokes are restated anyway.
-- think.ts keeps a seat-pack excerpt to the same 2,400 (it cut every excerpt to 1,200 again on its side).
-- Prevented by: scripts/checks/a_seats_own_entry_reaches_the_answer_whole.test.mjs.

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
begin
  -- 1. RESOLVE, exactly or not at all. The trade through the estate's exact resolver; the kind and the area only
  --    when a row of this trade / of this seat's own table is tagged with exactly that value. No word is read.
  select array_agg('trade:' || c) into v_trade from unnest(public.fn_norm_trades(p_trade)) c;
  v_kind := nullif(lower(btrim(coalesce(p_kind, ''))), '');
  if v_trade is null or (v_kind is not null and not exists (select 1 from public.sales_knowledge x
       where x.tags && v_trade and x.tags @> array['kind:' || v_kind])) then v_kind := null; end if;
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
    (select 'sales_knowledge', s.record_id, s.title, left(s.content, 2400), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed', true
       from public.sales_knowledge s
      where s.embedding_gte is not null and s.runtime_index_eligible
        and (p_seat = 'sales_engineer' or (p_seat = 'customer_support' and s.pack_id like 'verified:trade:%'))
        and (v_trade is null or not exists (select 1 from unnest(s.tags) t where t like 'trade:%')
             or (s.tags && v_trade and (v_kind is null or s.tags @> array['kind:' || v_kind])))
        and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%')))
      order by s.embedding_gte <=> p_embedding limit k)
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
  -- THE SEAT'S OWN ROWS FILL AT LEAST HALF, FOR AN INTERNAL AUDIENCE: its best k own rows (its pack, its agent_knowledge)
  -- are reserved and come first; the rest of the k * 2 is the best of everything else. External: ranked by similarity only.
  select coalesce(jsonb_agg(jsonb_build_object('source', src, 'id', id, 'title', title, 'excerpt', excerpt,
           'citation', citation, 'similarity', round(sim::numeric, 4), 'trust', trust, 'own', mine) order by reserved desc, sim desc), '[]'::jsonb)
    into out
    from (select * from (select h.*, v_internal and h.mine and row_number() over (partition by h.mine order by h.sim desc) <= k reserved from hits h) x
           order by reserved desc, sim desc limit k * 2) t;
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
begin
  -- 1. RESOLVE, exactly or not at all. The trade through the estate's exact resolver; the kind and the area only
  --    when a row of this trade / of this seat's own table is tagged with exactly that value. No word is read.
  select array_agg('trade:' || c) into v_trade from unnest(public.fn_norm_trades(p_trade)) c;
  v_kind := nullif(lower(btrim(coalesce(p_kind, ''))), '');
  if v_trade is null or (v_kind is not null and not exists (select 1 from public.sales_knowledge x
       where x.tags && v_trade and x.tags @> array['kind:' || v_kind])) then v_kind := null; end if;
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
             or (s.tags && v_trade and (v_kind is null or s.tags @> array['kind:' || v_kind])))
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%')))
            order by v.embedding <=> m limit n)
    union (select 'sales_knowledge', s.record_id from public.sales_knowledge s
            where g is not null and s.embedding_gte is not null and s.runtime_index_eligible
              and (p_seat = 'sales_engineer' or (p_seat = 'customer_support' and (s.pack_id like 'verified:trade:%' or exists (select 1 from unnest(s.tags) t where t like 'trade:%'))))
            and (v_trade is null or not exists (select 1 from unnest(s.tags) t where t like 'trade:%')
             or (s.tags && v_trade and (v_kind is null or s.tags @> array['kind:' || v_kind])))
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%')))
            order by s.embedding_gte <=> g limit n)
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
    (select 'sales_knowledge', s.record_id, s.title, left(s.content, 2400), s.pack_id, coalesce(sc.s_ml, sc.s_gte) s_ml, sc.score, 'reviewed', true
       from scored sc join public.sales_knowledge s on sc.src = 'sales_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
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
  ), own_rows as (
    select * from hits where mine order by score desc limit own
  ), chosen as (
    select o.*, true reserved from own_rows o
    union all
    select *, false from (select h.* from hits h where not exists (select 1 from own_rows o where o.src = h.src and o.id = h.id)
                    order by h.score desc limit greatest(k * 2 - (select count(*) from own_rows), 0)) rest
  )
  select coalesce(jsonb_agg(jsonb_build_object('source', src, 'id', id, 'title', title, 'excerpt', excerpt,
           'citation', citation, 'similarity', round(coalesce(s_ml, 0)::numeric, 4), 'score', round(score::numeric, 6),
           'trust', trust, 'own', mine) order by reserved desc, score desc), '[]'::jsonb)
    into out
    from chosen;
  return out;
end $fn$;

revoke execute on function public.fn_reason_retrieve_ml(text, vector, vector, integer, integer, text, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_reason_retrieve_ml(text, vector, vector, integer, integer, text, text, text, text) to service_role;
