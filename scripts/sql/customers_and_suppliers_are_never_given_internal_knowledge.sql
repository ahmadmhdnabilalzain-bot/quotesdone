-- CUSTOMERS AND SUPPLIERS ARE NEVER GIVEN INTERNAL KNOWLEDGE. Seat: customer_support (what a customer or a supplier
-- is told: widget, WhatsApp, email, and the portal chat it answers with sales_engineer); the routines are it_engineer's.
-- 27 Oct 2026. Founder ruling 1338 (public.founder_instruction): "Withhold from customers." Internal seats keep access.
--
-- MEASURED on production 27 Oct 2026, read-only (and by the probe below, rolled back):
--   ops_knowledge holds 9,143 rows and EVERY ONE is confidentiality = 'internal' (0 public). No support_public_override
--   row names an ops row. Yet four routines hand ops_knowledge text to outside callers without reading that column:
--   * fn_support_corpus_search(p_public => false) — supportReply's corpus on the 'portal' channel (signed-in customers
--     and suppliers; _shared/support_reply.ts). It read EVERY row of v_support_corpus: all 9,143 ops rows, and 98
--     support_knowledge rows tagged audience:internal / kind:company or sourced from founder instructions or memory
--     (of 730 support rows in the view). Probe: an internal routing-policy title returned 25 ops rows and 2 internal
--     support rows ("The answer standard: support always answers ...").
--   * fn_sales_assist — the portal chat's retrieval. Its one production caller is sales_engineer 'assist', whose answer
--     goes to supportReply with audience 'customer'. The ops branch admitted 9,107 rows (embedded and current).
--     Probe: 8 ops records returned for the same question.
--   * fn_reason_retrieve / fn_reason_retrieve_ml — think()'s per-step retrieval for EVERY customer and supplier path
--     (site_assistant, wa_inbound, customer_api, supplier_api, support_reply, ai_reply, given_trade_knowledge). Their
--     ops branch has no audience predicate: 1,402 (gte) / 1,431 (ml) ops rows reach audience customer, supplier,
--     visitor or NULL exactly as they reach 'internal'. Probe: 6 of 6 ops rows to customer, supplier, NULL and visitor.
--   PR #1549 withdraws the 3 live-figure rows; it does not touch the other 9,140.
--
-- THE CHANGE (CREATE OR REPLACE; signatures, settings and ACL unchanged; one overload each, enumerated live; the revoke
-- and grant are restated as they stand):
--   fn_support_corpus_search  p_public = false: an ops row only when confidentiality = 'public'; a support row never
--                             when tagged internal (the outside-audience test fn_reason_retrieve already applies to
--                             support_knowledge). search_path gains pg_temp. p_public = true is unchanged.
--   fn_sales_assist           ops branch: confidentiality = 'public'; support branch: the same internal-tag exclusion.
--   fn_reason_retrieve        ops branch: (v_internal or confidentiality = 'public').
--   fn_reason_retrieve_ml     final ops hits: the same predicate (the candidate stage ranks through HNSW and is unchanged).
--   "Public" is the one column the table already has for it. A row becomes customer-facing when someone sets it to
--   'public'; today none is, so outside callers get no ops_knowledge until a row is approved that way.
--   ALSO CARRIED: the kb_chunks predicate of founder ruling 1338 from #1640 (scripts/sql/knowledge_the_ai_wrote_itself_
--   is_withheld_from_customers.sql), byte for byte, because both files replace fn_reason_retrieve and _ml. This file is a
--   superset of that one: whichever applies LAST must be this file, or the ops predicate is lost.
--
-- INTERNAL ACCESS KEPT, and said plainly: fn_reason_retrieve(_ml) with p_audience 'internal' or 'founder' still reads
-- every eligible ops row (probe: 6 of 6); fn_ops_knowledge_search, fn_ops_knowledge_match, fn_agent_context(_v3),
-- fn_apply_playbook, fn_accountant_assist, fn_it_engineer_assist and fn_marketing_assist are unchanged (none has a
-- customer or supplier caller: measured by their SQL callers and every rpc() in supabase/functions).
--
-- NOT CHANGED:
--   - v_support_corpus itself (PR #1549 replaces it; the filter lives in the one routine that reads it).
--   - fn_reason_retrieve_library / _ml_library read ops rows through knowledge_library and take no audience, but have
--     no caller (SQL or edge) today. They must carry this rule before anything outside reads them.
--   - _shared/tools.ts 'ops_knowledge_search' has no importer; it reaches no one.
--   - No ops_knowledge row is changed. Which rows should be 'public' is a content decision, not this file's.
--
-- PROVED (rolled back): scripts/sql/customers_and_suppliers_are_never_given_internal_knowledge_probe.sql. Alone, on the
--   live routines: LEAK (8 failures listed). After this file, in the same query: PROBE OK, internal still served, and the
--   positive control (the same row flipped to 'public', rolled back) reaches all four outside paths.
-- Prevented by: scripts/checks/customers_and_suppliers_are_never_given_internal_knowledge.test.mjs (offline: fails if the
--   canonical body of any of the four routines loses its predicate; --live: runs the probe both ways).
-- APPLY at merge (release operator), AFTER #1640's file if both are merged:
--   node scripts/apply_sql.mjs scripts/sql/customers_and_suppliers_are_never_given_internal_knowledge.sql --apply --ddl
--   then delete scripts/sql/pending/customers_and_suppliers_are_never_given_internal_knowledge.txt and append the file to
--   the END of scripts/sql/MANIFEST.txt. Then run the probe file once (it must print PROBE OK).

CREATE OR REPLACE FUNCTION public.fn_support_corpus_search(p_query text, p_public boolean, p_limit integer DEFAULT 8)
 RETURNS TABLE(src text, src_id text, title text, content text, citation text, rank real)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  with q as (
    select websearch_to_tsquery('english', coalesce(p_query, '')) as qe,
           websearch_to_tsquery('simple',  coalesce(p_query, '')) as qs,
           websearch_to_tsquery('arabic',  public.fn_ar_norm(coalesce(p_query, ''))) as qa,
           -- The asker's language is the script they typed in, not a flag anyone passed.
           case when coalesce(p_query, '') ~ '[؀-ۿ]' then 'ar' else 'en' end as ask_lang
  ),
  -- BEST-TERMS: the same lexemes the strict query produced, OR'd. Built from the tsquery itself so
  -- it cannot drift from what was actually searched, and so stemming is applied identically.
  qb as (
    select
      nullif(array_to_string(array(
        select lexeme from unnest(to_tsvector('arabic', public.fn_ar_norm(coalesce(p_query,'')))) ), ' | '), '') as ar_or,
      nullif(array_to_string(array(
        select lexeme from unnest(to_tsvector('english', coalesce(p_query,''))) ), ' | '), '') as en_or
  ),
  qb2 as (
    select case when ar_or is null then null else to_tsquery('arabic',  ar_or) end as qab,
           case when en_or is null then null else to_tsquery('english', en_or) end as qeb
      from qb
  ),
  hay as (
    select c.src, c.src_id, c.title, c.content, c.citation, c.is_public, c.lang,
           to_tsvector('english', coalesce(c.title,'') || ' ' || coalesce(c.content,'')) as te,
           to_tsvector('simple',  coalesce(c.title,'') || ' ' || coalesce(c.content,'')) as ts,
           to_tsvector('arabic',  public.fn_ar_norm(coalesce(c.title,'') || ' ' || coalesce(c.content,''))) as ta
      from public.v_support_corpus c
     -- p_public = false is the SIGNED-IN PORTAL: a customer or a supplier, never staff (support_reply.ts, channel
     -- 'portal'). It used to read every row of the view. Founder ruling 1338: only public knowledge reaches them, so an
     -- operations row must be confidentiality 'public' and a support row must not be tagged internal (the same test
     -- fn_reason_retrieve applies to every outside audience).
     where (case when p_public then c.is_public
                 else (c.src <> 'ops' or exists (select 1 from public.ops_knowledge k
                                                  where k.record_id = c.src_id and k.confidentiality = 'public'))
                  and (c.src <> 'supportkb' or not exists (select 1 from public.support_knowledge s
                                                  where s.record_id = c.src_id and (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%'))))
            end)
  ),
  strict as (
    select h.src, h.src_id, h.title, h.content, h.citation,
           (greatest(ts_rank(h.te, q.qe), ts_rank(h.ts, q.qs), ts_rank(h.ta, q.qa))
            + case when h.lang = q.ask_lang then 1.0 else 0.0 end)::real as rank
      from hay h, q
     where h.te @@ q.qe or h.ts @@ q.qs or h.ta @@ q.qa
  ),
  loose as (
    select h.src, h.src_id, h.title, h.content, h.citation,
           -- Halved, then the language bonus added, so a best-terms hit can never outrank a strict
           -- one. A weaker match must look weaker.
           ((greatest(coalesce(ts_rank(h.ta, b.qab), 0), coalesce(ts_rank(h.te, b.qeb), 0)) * 0.5)
            + case when h.lang = q.ask_lang then 1.0 else 0.0 end)::real as rank
      from hay h, q, qb2 b
     where not exists (select 1 from strict)
       and ((b.qab is not null and h.ta @@ b.qab) or (b.qeb is not null and h.te @@ b.qeb))
  )
  select * from (select * from strict union all select * from loose) r
   order by r.rank desc
   limit greatest(1, least(coalesce(p_limit, 8), 25))
$fn$;

revoke execute on function public.fn_support_corpus_search(text, boolean, integer) from public, anon, authenticated;
grant execute on function public.fn_support_corpus_search(text, boolean, integer) to service_role;

CREATE OR REPLACE FUNCTION public.fn_sales_assist(p_text text, p_embedding vector, p_min_similarity numeric DEFAULT 0.86, p_min_rank numeric DEFAULT 0.05, p_k integer DEFAULT 5, p_actor text DEFAULT 'sales_engineer'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
declare
  v_k         int := greatest(1, least(coalesce(p_k, 5), 20));
  -- Per-corpus candidate width. Wider than the answer width so the floors have something to reject
  -- and the decision log records the near-misses that justify the floor.
  v_wide      int := greatest(v_k * 4, 20);
  -- LEXICAL-ONLY ADMISSION BAR. Applied only to rows with no embedding, where there is no vector
  -- to corroborate with. Deliberately 4x p_min_rank's default: it is carrying the whole burden of
  -- proof on its own. Measured basis in the report accompanying this file.
  -- Floored at 0.20 but never BELOW p_min_rank, so a caller that raises the corroboration bar
  -- raises this one too. Without that tie the lexical-only route would be untestable: the probe
  -- that proves a floor bites by raising it above the best hit would leave this route wide open
  -- and conclude the floors do not fire. A gate nobody can prove fires is not a gate.
  c_lex_only  numeric := greatest(0.20, coalesce(p_min_rank, 0));
  -- ponytail: kb_chunks lexical route takes the first 4,000 index matches and ranks those, not the
  -- global best of 2.5m unembedded rows. Ranking every match of a common term would be a table
  -- scan on every portal message. Raise it, or embed the rest, if recall proves short.
  c_kb_scan   int := 4000;
  -- Out of scope by the company's own exclusion, and by slug so it cannot drift.
  c_fnb       text[] := array['cat:catering-companies','cat:bakery-equipment-suppliers',
                              'cat:food-processing-equipment-suppliers','cat:hospitality-supplies-companies',
                              'cat:cold-room-and-refrigeration-suppliers'];
  v_tq        tsquery;
  -- The Arabic arm. company_faq is the only corpus this routine reads that is written in both
  -- languages (22 of its 508 approved rows carry Arabic, measured 18 Sep 2026), and it is the
  -- only corpus here with no precomputed tsvector, so both configurations are built on the fly
  -- for it at no structural cost. fn_ar_norm is the same normaliser fn_support_corpus_search
  -- uses, so an Arabic question reaches an Arabic FAQ by exactly one rule, not two.
  --
  -- AND IT NEEDS THE BEST-TERMS FALLBACK, because the estate has already paid for learning why.
  -- scripts/sql/an_arabic_question_is_not_six_words_that_must_all_appear.sql measured it on
  -- production: the 'arabic' text-search configuration Postgres ships has NO STOPWORD LIST, so
  -- ما / هي / عن / كم / في survive as ordinary content lexemes and websearch_to_tsquery ANDs every
  -- one of them. A nine-word Arabic question then demands one FAQ containing all nine words and
  -- ranks 0.0000 — and because a vector-bearing row here must ALSO corroborate lexically, a good
  -- Arabic embedding hit would be thrown out for want of corroboration that could never arrive.
  -- The Arabic arm would have been a column in a greatest() that contributes nothing.
  --
  -- So the same shape fn_support_corpus_search settled on is used here: the strict query first,
  -- and the SAME lexemes OR'd as a fallback, scored at HALF so a loose match can never outrank a
  -- strict one. Built from the question's own tsvector rather than from a second tokenisation, so
  -- it cannot drift from what was actually searched.
  --
  -- MEASURED on the 508 approved FAQs, 18 Sep 2026, with the recovered Arabic question
  -- "كم تكلفة السقف الجبسي المستعار للمتر المربع في دبي": strict returns 0 rows, the fallback
  -- returns 11. And the floors still hold — the fallback's best row is "ما هو QuotesDone؟" at
  -- ts_rank 0.0169, which halves to 0.0085 and is refused by both the 0.05 corroboration floor and
  -- the 0.20 lexical-only bar. That is the intended shape and worth stating plainly: the fallback's
  -- job is to give an Arabic VECTOR hit something it can corroborate against, not to admit rows on
  -- its own strength. A nearest neighbour is always found; this does not make one citable.
  v_tq_ar     tsquery;
  v_or_ar     text;
  v_tq_ar_or  tsquery;
  -- LEXEME OVERLAP — MEASURED, TRIED, AND REJECTED AS AN ADMISSION RULE. Recorded here because a
  -- rejected relaxation is worth more to the next reader than a silent one.
  --
  -- Over 18 realistic portal questions on 9 Sep 2026, all 5 that fell through did so at
  -- lexical_rank EXACTLY 0.0000 while their best vector hit sat at 0.888–0.916. Not weak evidence
  -- — NO lexical match at all, because websearch_to_tsquery ANDs every term and no single passage
  -- contains all of "dubai & supplier & cover & abu & dhabi". So lowering p_min_rank would have
  -- recovered nothing, and the measurement is what says so rather than a guess.
  --
  -- The obvious relaxation was to corroborate on lexeme OVERLAP instead: admit a row that clears
  -- cosine 0.86 and carries at least 40% of the question's own lexemes literally. It was built,
  -- applied and measured. "does a Dubai supplier cover Abu Dhabi as well" then returned a joinery
  -- FIRE-DOOR CERTIFICATION passage — cosine 0.888, lexemes "dubai" and "suppli" present, subject
  -- entirely wrong. A confidently wrong answer to a procurement question is the exact failure the
  -- floors exist to prevent, so the relaxation was reverted within the hour. The overlap count is
  -- still computed and logged as a DIAGNOSTIC, because it is the cheapest signal for which gaps
  -- are a phrasing problem and which are a genuinely absent subject — it is simply not allowed to
  -- admit anything.
  v_lex       text[];
  v_need      int;
  v_cands     jsonb  := '[]'::jsonb;
  v_cited     text[] := '{}';
  v_answer    jsonb  := '[]'::jsonb;
  v_refusal   text;
  v_norm      text;
  v_gap       public.sales_knowledge_gap%rowtype;
  v_task      bigint;
  v_best_sim  numeric;
  v_best_rank numeric;
  v_best_corp text;
  v_handoff   text;
begin
  if coalesce(btrim(p_text), '') = '' then
    return jsonb_build_object(
    -- THE COMPANY BLOCK. Pinned, never retrieved and never rankable: it is here on every answer,
    -- including the refusals, because a seat with no retrieval hit is exactly the seat most likely
    -- to improvise a fee or a policy. Founder ruling, 9 Sep 2026.
    'company', public.fn_company_context(),
    'ok', false, 'answered', false, 'refusal', 'empty_query');
  end if;

  -- THE QUESTION ARRIVED WITH ITS SCRIPT STRIPPED. See fn_text_lost_its_script for the measured
  -- case. Nothing downstream can answer a question whose letters were replaced by question marks
  -- before it reached us, and filing it as a knowledge gap manufactures a task nobody can work:
  -- org_tasks 578945 sat in the queue for nine days under a title made entirely of them. Refuse
  -- here, say so, and open nothing.
  --
  -- THE REPLY CARRIES BOTH LANGUAGES, AND THAT IS NOT BELT AND BRACES. Every surface in this
  -- estate decides the asker's language from the SCRIPT they typed in — site_assistant tests
  -- /[؀-ۿ]/ against the message, fn_support_corpus_search reads ask_lang the same way. The script
  -- is precisely what was destroyed here: a stripped message is pure ASCII, so every one of those
  -- detectors concludes "English" for the one visitor who most needs the Arabic sentence. The
  -- language is unknowable by construction on this branch, so the choice is not made. 'handoff' is
  -- what the sales_engineer edge function already reads, so putting both paragraphs there is what
  -- makes the Arabic reach a person at all; 'handoff_ar' is kept for a caller that wants the
  -- Arabic alone.
  if public.fn_text_lost_its_script(p_text) then
    return jsonb_build_object(
      'company', public.fn_company_context(),
      'ok', false, 'answered', false, 'refusal', 'text_lost_its_script',
      'handoff', public.fn_text_did_not_survive_reply('en') || E'\n\n'
                 || public.fn_text_did_not_survive_reply('ar'),
      'handoff_en', public.fn_text_did_not_survive_reply('en'),
      'handoff_ar', public.fn_text_did_not_survive_reply('ar'));
  end if;

  v_tq := websearch_to_tsquery('english', p_text);
  -- 21 SEP 2026 — THE ARABIC ARMS EXIST ONLY FOR A QUESTION WRITTEN IN ARABIC. Measured on
  -- production with the customer's English question "the quote excludes scaffolding above 4 m but
  -- my ceilings are 3.2 m, does that exclusion matter": the 'arabic' configuration has no stopword
  -- list, so 'the', 'does', 'that', 'are' became query lexemes, and ts_rank scores PARTIAL matches —
  -- FAQ 624 "Does a Dubai supplier cover Abu Dhabi as well?" ranked 0.7640 under the strict Arabic
  -- query while `@@` was FALSE for it. Five unrelated FAQs cleared the 0.20 lexical-only bar that
  -- way and were dumped on the customer as the answer. An English question now carries null Arabic
  -- arms, and (below) every rank is gated by its own `@@`, so a rank can no longer be earned by a
  -- query the row does not actually match.
  if p_text ~ '[؀-ۿ]' then
    v_tq_ar := websearch_to_tsquery('arabic', public.fn_ar_norm(p_text));
    select nullif(array_to_string(array(
             select lexeme from unnest(to_tsvector('arabic', public.fn_ar_norm(p_text)))), ' | '), '')
      into v_or_ar;
    v_tq_ar_or := case when v_or_ar is null then null else to_tsquery('arabic', v_or_ar) end;
  else
    v_tq_ar := null; v_or_ar := null; v_tq_ar_or := null;
  end if;
  select array_agg(distinct u.lexeme) into v_lex from unnest(to_tsvector('english', p_text)) u;
  v_need := least(coalesce(cardinality(v_lex), 0), greatest(2, ceil(0.4 * coalesce(cardinality(v_lex), 0))::int));

  -- Every corpus produces the same six columns so the union is a fact about provenance, not about
  -- shape. `route` records HOW a row could be admitted, and is what stops a vector-bearing row
  -- being let in on lexical evidence alone.
  create temporary table if not exists _sa_cand (
    corpus text, record_id text, title text, content text, provenance text,
    similarity numeric, lexical_rank numeric, has_vector boolean, lex_hits int default 0
  ) on commit drop;
  -- truncate, not delete: the estate has a guard that refuses an unqualified DELETE, and a
  -- WHERE-less delete on a scratch table is exactly what that guard exists to catch elsewhere.
  truncate table _sa_cand;

  -- sales_knowledge — the seat's own pack. 1,136 rows, 100% embedded.
  if p_embedding is not null then
    insert into _sa_cand
    select 'sales_knowledge', k.record_id, k.title, left(k.content, 4000),
           coalesce(k.record_type, '') || case when k.domain is null then '' else ' · ' || k.domain end
             || case when k.epistemic_status is null then '' else ' · ' || k.epistemic_status end,
           (1 - (k.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(k.search, v_tq), 0)::numeric * (case when k.search @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(k.search) u where u.lexeme = any (v_lex))
      from sales_knowledge k
     where k.embedding_gte is not null
     order by k.embedding_gte <=> p_embedding
     limit v_wide;
  end if;
  insert into _sa_cand
  select 'sales_knowledge', k.record_id, k.title, left(k.content, 4000),
         coalesce(k.record_type, ''), null::numeric, ts_rank(k.search, v_tq)::numeric, false, 0
    from sales_knowledge k
   where k.embedding_gte is null and k.search @@ v_tq
   order by ts_rank(k.search, v_tq) desc
   limit v_wide;

  -- ops_knowledge — 9,139 rows, 100% embedded, tsv + hnsw.
  if p_embedding is not null then
    insert into _sa_cand
    select 'ops_knowledge', o.record_id, o.title, left(o.content, 4000),
           coalesce(o.record_type, '') || case when o.authority_tier is null then '' else ' · authority ' || o.authority_tier end,
           (1 - (o.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(o.tsv, v_tq), 0)::numeric * (case when o.tsv @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(o.tsv) u where u.lexeme = any (v_lex))
      from ops_knowledge o
     where o.embedding_gte is not null
       and coalesce(o.supersession_state, 'current') = 'current'   -- never quote a superseded rule
       -- founder ruling 1338: this routine's one production caller is the portal chat (customers and suppliers), so
       -- an operations row reaches it only when it is confidentiality 'public'. Internal seats read ops_knowledge
       -- through fn_reason_retrieve(_ml) with an internal audience, fn_ops_knowledge_search and fn_agent_context.
       and o.confidentiality = 'public'
     order by o.embedding_gte <=> p_embedding
     limit v_wide;
  end if;

  -- kb_chunks — 2,686,026 rows. Both routes matter here and the lexical one matters most: 93.8% of
  -- this corpus has no vector at all, so a vector-only reader sees 6% of the category and trade
  -- field body.
  if p_embedding is not null then
    insert into _sa_cand
    select 'kb_chunks', c.id::text, c.title, left(c.content, 4000),
           coalesce(c.source_kind, '') || case when c.category is null then '' else ' · ' || c.category end
             || case when c.citation is null then '' else ' · ' || c.citation end,
           (1 - (c.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(c.fts, v_tq), 0)::numeric * (case when c.fts @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(c.fts) u where u.lexeme = any (v_lex))
      from kb_chunks c
     where c.embedding_gte is not null
     order by c.embedding_gte <=> p_embedding
     limit v_wide;
  end if;
  insert into _sa_cand
  select 'kb_chunks', x.id::text, x.title, left(x.content, 4000),
         coalesce(x.source_kind, '') || case when x.category is null then '' else ' · ' || x.category end
           || case when x.citation is null then '' else ' · ' || x.citation end,
         null::numeric, ts_rank(x.fts, v_tq)::numeric, false, 0
    from (select c.id, c.title, c.content, c.source_kind, c.category, c.citation, c.fts
            from kb_chunks c
           where c.embedding_gte is null and c.fts @@ v_tq
           limit c_kb_scan) x
   order by ts_rank(x.fts, v_tq) desc
   limit v_wide;

  -- agent_knowledge — 2,556 rows. The 1,627 'cat:%' rows carry no embedding, which is exactly why
  -- section 1 of this file exists. F&B excluded by slug.
  if p_embedding is not null then
    insert into _sa_cand
    select 'agent_knowledge', a.id::text, a.topic, left(a.content, 4000),
           a.agent_key || case when a.layer is null then '' else ' · ' || a.layer end,
           (1 - (a.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(a.search, v_tq), 0)::numeric * (case when a.search @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(a.search) u where u.lexeme = any (v_lex))
      from agent_knowledge a
     where a.embedding_gte is not null
       and not (a.agent_key = any (c_fnb))
       and coalesce(a.validation_status, '') <> 'quarantined'
     order by a.embedding_gte <=> p_embedding
     limit v_wide;
  end if;
  insert into _sa_cand
  select 'agent_knowledge', a.id::text, a.topic, left(a.content, 4000),
         a.agent_key || case when a.layer is null then '' else ' · ' || a.layer end,
         null::numeric, ts_rank(a.search, v_tq)::numeric, false, 0
    from agent_knowledge a
   where a.embedding_gte is null and a.search @@ v_tq
     and not (a.agent_key = any (c_fnb))
     and coalesce(a.validation_status, '') <> 'quarantined'
   order by ts_rank(a.search, v_tq) desc
   limit v_wide;

  -- support_knowledge — 408 rows, tsvector only. Lexical is not a fallback here, it is the only
  -- instrument the table has.
  insert into _sa_cand
  select 'support_knowledge', s.record_id, s.title, left(s.body, 4000),
         coalesce(s.record_kind, '') || case when s.domain is null then '' else ' · ' || s.domain end,
         null::numeric, ts_rank(s.search, v_tq)::numeric, false, 0
    from support_knowledge s
   where s.search @@ v_tq
     and coalesce(s.runtime_index_eligible, true)
     -- a support row tagged internal is never handed to the portal (fn_reason_retrieve's outside-audience test)
     and not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%'))
   order by ts_rank(s.search, v_tq) desc
   limit v_wide;

  -- category_specs / category_quote_specs — 56 and 141 rows, no index of any kind. Small enough to
  -- vectorise the tsquery on the fly, and they answer the single most common portal question there
  -- is: what does this category actually require.
  insert into _sa_cand
  select 'category_specs', cs.category, cs.label,
         left('Supplier requirements: ' || coalesce(cs.supplier_requirements::text, 'none recorded')
           || E'\nCompliance checklist: ' || coalesce(cs.compliance_checklist::text, 'none recorded')
           || E'\nQuote fields: ' || coalesce(cs.fields::text, 'none recorded'), 4000),
         'category spec · ' || cs.category, null::numeric,
         ts_rank(to_tsvector('english', coalesce(cs.category,'') || ' ' || coalesce(cs.label,'') || ' '
                 || coalesce(cs.supplier_requirements::text,'') || ' ' || coalesce(cs.compliance_checklist::text,'')), v_tq)::numeric,
         false, 0
    from category_specs cs
   where to_tsvector('english', coalesce(cs.category,'') || ' ' || coalesce(cs.label,'') || ' '
         || coalesce(cs.supplier_requirements::text,'') || ' ' || coalesce(cs.compliance_checklist::text,'')) @@ v_tq
   limit v_wide;

  insert into _sa_cand
  select 'category_quote_specs', q.id::text, q.label,
         left('Aspect: ' || coalesce(q.aspect, '—') || E'\nMandatory: ' || coalesce(q.mandatory::text, 'unknown')
           || E'\n' || coalesce(q.note, ''), 4000),
         'quote spec · ' || coalesce(q.spec_group, ''), null::numeric,
         ts_rank(to_tsvector('english', coalesce(q.spec_group,'') || ' ' || coalesce(q.aspect,'') || ' '
                 || coalesce(q.label,'') || ' ' || coalesce(q.note,'')), v_tq)::numeric,
         false, 0
    from category_quote_specs q
   where to_tsvector('english', coalesce(q.spec_group,'') || ' ' || coalesce(q.aspect,'') || ' '
         || coalesce(q.label,'') || ' ' || coalesce(q.note,'')) @@ v_tq
   limit v_wide;

  -- company_faq — 508 approved rows, 466 embedded, 22 carrying Arabic (measured 18 Sep 2026).
  -- THE CORPUS THIS ROUTINE COULD NOT SEE, AND THE ONE THE COMPANY WRITES ITS ANSWERS INTO.
  --
  -- Measured, 18 Sep 2026, against the 13 recorded rows of sales_knowledge_gap: two of them
  -- ("does a Dubai supplier cover Abu Dhabi as well" and "what documents does a supplier need for
  -- verification") are answered by an approved FAQ whose question is almost the asked sentence —
  -- lexical rank 0.9888 and 0.9640. An aborted probe of the deployed routine on the same day
  -- returned answered=false, refusal=no_candidates for the first of them while FAQ 624, titled
  -- "Does a Dubai supplier cover Abu Dhabi as well?", sat approved and published.
  --
  -- The sharper half of that measurement: both FAQs were WRITTEN IN RESPONSE to those two gaps
  -- (created 2026-09-09 21:14, after the questions were refused). So the remediation loop closes
  -- into a table this routine cannot read — a gap answered for the support seat stays open for the
  -- sales seat, and the same question asked by a signed-in customer refuses again. The task text
  -- this routine writes says DONE MEANS "the knowledge exists in a searchable corpus"; company_faq
  -- was not one of them.
  --
  -- WHY THE FAQ IS ADDED HERE RATHER THAN DELEGATED TO fn_support_corpus_search. That routine
  -- already owns FAQ retrieval for the support seat, and delegating was the first instinct. It
  -- reads v_support_corpus, which is company_faq UNION support_knowledge UNION ops_knowledge —
  -- two corpora this routine already reads on its own terms — and it ranks on a different scale
  -- (ts_rank plus a flat +1.0 bonus for the asker's language). Calling it would put two admission
  -- rules behind one answer, double-count two corpora, and leave sales_decision_log unable to say
  -- which rule admitted a row. The subject this routine was missing is not "FAQ retrieval", it is
  -- "the FAQ table", so the table is what it reads — under the one admission rule it already has,
  -- with the same status = 'approved' predicate v_support_corpus applies, so "published" means the
  -- same thing to both readers and there is still exactly one definition of it.
  --
  -- NOT COVERED HERE, said plainly: ops_knowledge holds 173 Arabic-bearing rows whose tsv column
  -- is built with the english configuration, so an Arabic question still cannot reach those
  -- lexically. Rebuilding that column is a change to a different subject and is not in this file.
  -- Both routes read the SAME haystack expression through one subquery, so each row's english and
  -- arabic tsvectors are built once per statement instead of once per clause. `ar_rank` is the
  -- strict Arabic rank, `ar_loose` the best-terms fallback at half weight; the lexical rank a row
  -- carries into admission is the best of the three, so a strict hit in either language always
  -- beats a loose one and English is scored exactly as it was before this change.
  if p_embedding is not null then
    insert into _sa_cand
    select 'company_faq', h.id::text, h.title, left(h.body, 4000), h.provenance,
           (1 - (h.embedding_gte <=> p_embedding))::numeric,
           greatest(case when h.te @@ v_tq then ts_rank(h.te, v_tq) else 0 end,
                    case when v_tq_ar is not null and h.ta @@ v_tq_ar then ts_rank(h.ta, v_tq_ar) else 0 end,
                    case when v_tq_ar_or is not null and h.ta @@ v_tq_ar_or then ts_rank(h.ta, v_tq_ar_or) * 0.5 else 0 end)::numeric,
           true,
           (select count(*) from unnest(h.te) u where u.lexeme = any (v_lex))
      from (select f.id, coalesce(f.question, '') as title, coalesce(f.answer, '') as body,
                   f.embedding_gte,
                   'FAQ' || case when f.section is null then '' else ' · ' || f.section end
                         || ' · ' || coalesce(f.language, 'en') as provenance,
                   to_tsvector('english', coalesce(f.question, '') || ' ' || coalesce(f.answer, '')) as te,
                   to_tsvector('arabic', public.fn_ar_norm(coalesce(f.question, '') || ' ' || coalesce(f.answer, ''))) as ta
              from company_faq f
             where f.embedding_gte is not null
               and f.status = 'approved'
             order by f.embedding_gte <=> p_embedding
             limit v_wide) h;
  end if;
  insert into _sa_cand
  select 'company_faq', h.id::text, h.title, left(h.body, 4000), h.provenance,
         null::numeric, h.lex_rank, false, 0
    -- The outer select reads the alias g. It read f (the inner table's alias) until 21 Sep 2026 —
    -- the dry run passed and the routine failed on its first call with 42P01 "missing FROM-clause
    -- entry for table f", measured by running it inside an aborted transaction.
    from (select g.id, coalesce(g.question, '') as title, coalesce(g.answer, '') as body,
                 'FAQ' || case when g.section is null then '' else ' · ' || g.section end
                       || ' · ' || coalesce(g.language, 'en') as provenance,
                 greatest(case when g.te @@ v_tq then ts_rank(g.te, v_tq) else 0 end,
                          case when v_tq_ar is not null and g.ta @@ v_tq_ar then ts_rank(g.ta, v_tq_ar) else 0 end,
                          case when v_tq_ar_or is not null and g.ta @@ v_tq_ar_or then ts_rank(g.ta, v_tq_ar_or) * 0.5 else 0 end)::numeric as lex_rank
            from (select f.*,
                         to_tsvector('english', coalesce(f.question, '') || ' ' || coalesce(f.answer, '')) as te,
                         to_tsvector('arabic', public.fn_ar_norm(coalesce(f.question, '') || ' ' || coalesce(f.answer, ''))) as ta
                    from company_faq f
                   where f.embedding_gte is null
                     and f.status = 'approved') g
           where (g.te @@ v_tq
               or (v_tq_ar is not null and g.ta @@ v_tq_ar)
               or (v_tq_ar_or is not null and g.ta @@ v_tq_ar_or))
           order by lex_rank desc
           limit v_wide) h;

  -- ADMISSION. A vector-bearing row must clear the cosine floor AND corroborate lexically. A row
  -- with no vector must clear the stricter lexical-only bar. Nothing else is admitted.
  with judged as (
    select c.*,
           (c.has_vector and c.similarity >= p_min_similarity and c.lexical_rank >= p_min_rank) as ok_vector,
           ((not c.has_vector) and c.lexical_rank >= c_lex_only)                                as ok_lexical
      from _sa_cand c
  ), ranked as (
    select j.*, (j.ok_vector or j.ok_lexical) as cited,
           row_number() over (
             order by (case when j.ok_vector or j.ok_lexical then 0 else 1 end),
                      (case when j.has_vector then 0 else 1 end),
                      j.similarity desc nulls last, j.lexical_rank desc) as rn
      from judged j
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'corpus', r.corpus, 'record_id', r.record_id,
      'similarity', round(r.similarity, 4), 'lexical_rank', round(r.lexical_rank, 4),
      'route', case when r.has_vector then 'vector+lexical' else 'lexical_only' end,
      'cleared_floor', coalesce(r.has_vector and r.similarity >= p_min_similarity, false),
      -- Diagnostic only, deliberately NOT an admission criterion. See the header note.
      'lex_hits', r.lex_hits, 'lex_overlap_would_admit', (v_need > 0 and r.lex_hits >= v_need),
      'corroborated', r.lexical_rank >= (case when r.has_vector then p_min_rank else c_lex_only end),
      'cited', r.cited) order by r.rn) filter (where r.rn <= 40), '[]'::jsonb),
    coalesce(array_agg(r.corpus || ':' || r.record_id order by r.rn)
             filter (where r.cited and r.rn <= v_k), '{}'),
    coalesce(jsonb_agg(jsonb_build_object(
      'corpus', r.corpus, 'record_id', r.record_id, 'title', r.title,
      'provenance', r.provenance,
      'similarity', round(r.similarity, 4), 'lexical_rank', round(r.lexical_rank, 4),
      'route', case when r.has_vector then 'vector+lexical' else 'lexical_only' end,
      'content', r.content) order by r.rn) filter (where r.cited and r.rn <= v_k), '[]'::jsonb)
    into v_cands, v_cited, v_answer
    from ranked r;

  select max(similarity), max(lexical_rank) into v_best_sim, v_best_rank from _sa_cand;
  select corpus into v_best_corp from _sa_cand
   order by similarity desc nulls last, lexical_rank desc limit 1;

  if cardinality(v_cited) = 0 then
    v_refusal := case
      when (select count(*) from _sa_cand) = 0 then 'no_candidates'
      when coalesce(v_best_sim, 0) < p_min_similarity and coalesce(v_best_rank, 0) < c_lex_only
        then 'below_similarity_floor_and_lexical_bar'
      when coalesce(v_best_sim, 0) < p_min_similarity then 'below_similarity_floor'
      else 'not_corroborated_lexically' end;

    -- ── THE FALLBACK IS AN ACTION, NOT A SENTENCE ────────────────────────────────────────────
    -- The founder's objection was never to the honesty of "I do not have that". It was to nothing
    -- happening afterwards. Something happens now: the question is kept, counted, and owned.
    v_norm := left(lower(regexp_replace(btrim(p_text), '\s+', ' ', 'g')), 400);

    select * into v_gap from sales_knowledge_gap where question_norm = v_norm;

    if not found then
      insert into org_tasks (title, detail, status, tier, action_class, assigned_agent,
                             priority, requires_evidence, needs_founder)
      values (
        left('Answer an unanswered portal question: ' || btrim(p_text), 160),
        'A customer or supplier asked this in the portal and the Sales Engineer could not source an '
          || 'answer from any corpus it searches (sales_knowledge, ops_knowledge, kb_chunks, '
          || 'agent_knowledge, support_knowledge, company_faq, category_specs, category_quote_specs).' || E'\n\n'
          || 'QUESTION: ' || btrim(p_text) || E'\n'
          || 'REFUSAL: ' || v_refusal || E'\n'
          || 'CLOSEST THE ESTATE GOT: corpus ' || coalesce(v_best_corp, 'none')
          || ', cosine ' || coalesce(round(v_best_sim, 4)::text, 'n/a')
          || ', lexical rank ' || coalesce(round(v_best_rank, 4)::text, 'n/a')
          || ' (floors: cosine ' || p_min_similarity || ', lexical corroboration ' || p_min_rank
          || ', lexical-only ' || c_lex_only || ').' || E'\n\n'
          || 'DONE MEANS: the knowledge exists in a searchable corpus and this question returns it. '
          || 'Then set sales_knowledge_gap.status to knowledge_added.',
        'assigned', 'advisory', 'knowledge_gap', 'sales_engineer', 3, true, false)
      returning id into v_task;

      insert into sales_knowledge_gap
        (question_norm, question, refusal, best_similarity, best_lexical_rank, nearest_corpus, task_id)
      values (v_norm, left(btrim(p_text), 2000), v_refusal,
              round(v_best_sim, 4), round(v_best_rank, 4), v_best_corp, v_task);
    else
      v_task := v_gap.task_id;
      update sales_knowledge_gap
         set asks = asks + 1, last_asked_at = now(), refusal = v_refusal,
             best_similarity = greatest(coalesce(best_similarity, 0), coalesce(round(v_best_sim, 4), 0)),
             best_lexical_rank = greatest(coalesce(best_lexical_rank, 0), coalesce(round(v_best_rank, 4), 0))
       where id = v_gap.id;
      -- Asked repeatedly is the definition of urgent. The task's priority follows the demand.
      update org_tasks set priority = least(9, greatest(priority, 3 + v_gap.asks)), updated_at = now()
       where id = v_task and status not in ('done', 'cancelled');
    end if;

    v_handoff :=
      'I have not got a sourced answer to that yet, and I will not guess at a procurement question. '
      || 'I have recorded it and opened task #' || coalesce(v_task::text, '?')
      || ', owned by the Sales Engineer, with your question kept word for word. '
      || 'It is being looked into and you will get an answer on it.';
  end if;

  insert into sales_decision_log
    (actor, action, query, min_similarity, min_rank, k, candidates, cited, answered, refusal)
  values
    (coalesce(p_actor, 'sales_engineer'), 'assist', left(p_text, 2000), p_min_similarity,
     p_min_rank, v_k, v_cands, v_cited, cardinality(v_cited) > 0, v_refusal);

  return jsonb_build_object(
    -- THE COMPANY BLOCK. Pinned, never retrieved and never rankable: it is here on every answer,
    -- including the refusals, because a seat with no retrieval hit is exactly the seat most likely
    -- to improvise a fee or a policy. Founder ruling, 9 Sep 2026.
    'company', public.fn_company_context(),
    
    'ok', true,
    'answered', cardinality(v_cited) > 0,
    'records', v_answer,
    'cited', v_cited,
    'candidates', v_cands,
    'corpora', jsonb_build_array('sales_knowledge','ops_knowledge','kb_chunks','agent_knowledge',
                                 'support_knowledge','company_faq','category_specs','category_quote_specs'),
    'floor', jsonb_build_object(
      'min_similarity', p_min_similarity, 'min_rank', p_min_rank, 'lexical_only', c_lex_only,
      'lexemes_in_question', coalesce(cardinality(v_lex), 0), 'lexeme_overlap_needed', v_need, 'k', v_k,
      'rule', 'a row with an embedding must clear the cosine floor AND match the all-terms lexical query at ts_rank >= min_rank. A row with no embedding cannot be put to the vector floor at all and must clear the stricter lexical-only bar instead. lexeme_overlap_needed is reported as a diagnostic only: admitting on partial overlap was measured and returned a topically wrong passage, so it does not admit. A nearest neighbour is always found; a lexical match is not.'),
    'refusal', v_refusal,
    'gap_recorded', case when cardinality(v_cited) = 0 then true else false end,
    'task_id', v_task,
    'handoff', v_handoff);
end
$fn$;

revoke execute on function public.fn_sales_assist(text, vector, numeric, numeric, integer, text) from public, anon, authenticated;
grant execute on function public.fn_sales_assist(text, vector, numeric, numeric, integer, text) to service_role;

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
        -- founder ruling 1338: an outside audience is given an operations row only when it is confidentiality 'public'
        and (v_internal or o.confidentiality = 'public')
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
      -- founder ruling 1338: an outside audience is given an operations row only when it is confidentiality 'public'
      where v_internal or o.confidentiality = 'public'
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
