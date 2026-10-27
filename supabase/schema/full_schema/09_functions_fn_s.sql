CREATE OR REPLACE FUNCTION public.fn_sales_assist(p_text text, p_embedding vector, p_min_similarity numeric DEFAULT 0.86, p_min_rank numeric DEFAULT 0.05, p_k integer DEFAULT 5, p_actor text DEFAULT 'sales_engineer'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  -- TEST TRAFFIC FILES NOTHING (27 Oct 2026): a request carrying a sandbox run tag, or a ZZ DEMO question, records no
  -- gap, bumps no ask counter and opens or raises no task. Both tests are the estate's own (see the file header).
  v_test      boolean := public.fn_e2e_run_tag_current() is not null or public.fn_seat_work_is_demo(p_text, null);
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

    if v_test then
      -- Our own test asked it. The question stays in sales_decision_log (stamped with its run, removed by teardown);
      -- no gap, no counter and no task, because no person asked and nobody confirmed the work.
      v_handoff := 'I have not got a sourced answer to that yet, and I will not guess at a procurement question.';
    else
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
    'gap_recorded', cardinality(v_cited) = 0 and not v_test,
    'test_traffic', v_test,
    'task_id', v_task,
    'handoff', v_handoff);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_acts_on_handoff(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  a public.agent_actions; d jsonb; t text;
  v_cust record; v_sup record; v_inq text; v_window int; v_chase int; v_min int; v_max int;
  v_tx public.transactions; v_amt text; v_req bigint; v_lines text; v_orig public.notifications;
  v_revealed text; v_rid text;
begin
  select * into a from public.agent_actions where id = p_id;
  d := a.detail; t := d->>'type';
  select refund_window_working_days, chase_after_working_days, bank_settlement_working_days_min, bank_settlement_working_days_max
    into v_window, v_chase, v_min, v_max from public.pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3); v_min := coalesce(v_min, 7); v_max := coalesce(v_max, 14);

  select null::uuid as id, null::text as email, null::text as full_name into v_cust;
  select null::bigint as id, null::text as company_name, null::text as email into v_sup;
  if (d->>'customer_id') is not null then
    select id, email, full_name into v_cust from public.customers where id = (d->>'customer_id')::uuid;
  end if;
  if (d->>'supplier_id') is not null then
    select id, company_name, coalesce(claimed_by, email) as email into v_sup from public.leads where id = (d->>'supplier_id')::bigint;
  end if;
  if (d->>'inquiry_id') is not null then
    select summary into v_inq from public.inquiries where id = (d->>'inquiry_id')::uuid;
  end if;
  v_revealed := coalesce(to_char((d->>'revealed_at')::timestamptz at time zone 'Asia/Dubai', 'DD Mon YYYY'), 'the reveal date');
  v_rid := left(coalesce(d->>'transaction_id', d->>'subject_id', ''), 8);

  if t = 'reveal.paid' then
    -- The words trg_reveal_receipt used to write itself, unchanged, now composed by the seat whose
    -- voice the portal is and carried by the seat that owns the pipe.
    if v_cust.email is not null then
      v_req := public.fn_sales_engineer_writes('reveal_receipt', 'customer', v_cust.email, null, v_cust.id,
        (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
        'Reveal confirmed — ' || coalesce(v_sup.company_name, 'supplier'),
        'You have unlocked ' || coalesce(v_sup.company_name, 'the supplier') || '''s contact details'
          || coalesce(' for: ' || left(v_inq, 80), '')
          || '. You can now message them directly in the app. We track this reveal from the moment you paid: if the supplier has not responded within '
          || v_chase::text || ' working days we chase them for you and copy you; if there is still no response by working day '
          || v_window::text || ' the case is decided by our chief executive, and if the supplier never responded everything you paid is refunded in full. '
          || 'Banks usually take ' || v_min || '-' || v_max || ' working days to show a refund. You can also open the request and Report an issue at any time.',
        'اكتمل الكشف — ' || coalesce(v_sup.company_name, 'المورّد'),
        'أصبحت بيانات التواصل مع ' || coalesce(v_sup.company_name, 'المورّد') || ' متاحة لكم الآن، ويمكنكم مراسلته مباشرة من التطبيق. '
          || 'نتابع هذا الكشف منذ لحظة الدفع: إن لم يردّ المورّد خلال ' || v_chase::text || ' أيام عمل فسنتواصل معه نيابةً عنكم مع نسخة إليكم، '
          || 'وإن لم يردّ حتى يوم العمل ' || v_window::text || ' فسيبتّ رئيسنا التنفيذي في الحالة، وإن لم يردّ المورّد إطلاقًا فسنردّ إليكم كامل المبلغ المدفوع.',
        '{}', 'reveal_receipt:' || (d->>'subject_id'), null, jsonb_build_object('transaction_id', d->>'subject_id'));
    end if;
    if coalesce(v_sup.email, '') like '%@%' then
      perform public.fn_sales_engineer_writes('quote_accepted', 'supplier', v_sup.email, v_sup.id, null,
        (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
        'A customer revealed your quote on QuotesDone',
        'A customer paid to reveal your contact for: ' || coalesce(v_inq, '')
          || '. Please respond promptly — under the Supplier Agreement you must respond within ' || v_window::text
          || ' working days of the reveal. If you have not responded after ' || v_chase::text
          || ' working days we chase you with the customer copied; if there is still no response on working day ' || v_window::text
          || ' our chief executive decides the case, the customer is refunded, and the amount refunded, with the administrative fee, interest and other amounts set out in clause 33 of the Supplier Agreement you accepted, is recovered from your account.',
        'كشف أحد العملاء عن عرضكم على QuotesDone',
        'سدّد أحد العملاء رسوم الكشف عن بيانات التواصل معكم بشأن: ' || coalesce(v_inq, '') || '. نرجو المبادرة بالرد، إذ تُلزم اتفاقية المورّد بالرد خلال '
          || v_window::text || ' أيام عمل من تاريخ الكشف، وإلا فسيُردّ إلى العميل كامل ما دفعه، ويُسترد من حسابكم المبلغ المردود مع الرسم الإداري والفائدة وسائر المبالغ المبيّنة في البند 33 من اتفاقية المورّد التي قبلتموها.',
        '{}', 'quote_accepted:' || (d->>'subject_id'), null, jsonb_build_object('transaction_id', d->>'subject_id'));
    end if;
    return jsonb_build_object('customer_reachable', v_cust.email is not null,
                              'supplier_reachable', coalesce(v_sup.email, '') like '%@%',
                              'delivery_request', v_req);

  elsif t = 'payment.failed' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('reveal_payment_incomplete', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'Your reveal payment did not complete',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'Your payment to unlock the supplier''s contact details did not go through, and nothing was charged to your card.' || E'\n\n'
        || 'You can try again at any time: open the request in your QuotesDone portal and choose Reveal on the quote you picked. If the card was declined, your bank can tell you why, and a different card also works.',
      'لم يكتمل دفع رسوم الكشف',
      'تعذّر إتمام دفع رسوم الكشف عن بيانات المورّد، ولم يُخصم أي مبلغ من بطاقتكم. يمكنكم إعادة المحاولة في أي وقت من بوابتكم على QuotesDone.',
      '{}', 'payment_failed:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'payment.received' then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes(coalesce(d->>'msg_type', 'dues_paid'), 'supplier', v_sup.email, v_sup.id, null, null, null,
      case when d->>'kind' = 'supplier_registration' then 'Registration confirmed - thank you' else 'Payment received - thank you' end,
      case when d->>'kind' = 'supplier_registration'
           then 'We have received your registration payment of AED ' || (d->>'amount_aed') || '. Your QuotesDone supplier account is registered for the next 12 months.'
           else 'We have received your payment of AED ' || (d->>'amount_aed') || ' settling ' || coalesce(d->>'items', '1') || ' outstanding charge(s). Your account is now up to date.' end,
      'استلمنا دفعتكم', 'استلمنا دفعتكم البالغة ' || (d->>'amount_aed') || ' درهم، ونشكركم على ذلك.',
      '{}', 'payment_received:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'refund.request_checked' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_amt := case when (d->>'money_ok')::boolean then ' — AED ' || (d->>'amount_aed') else '' end;
    v_req := public.fn_sales_engineer_writes('refund_request_received', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'We have your refund request',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'We have received your refund request for the reveal on ' || coalesce('"' || left(v_inq, 80) || '"', 'your request') || '.' || E'\n\n'
        || 'What happens next: we check whether the supplier ever replied to you, our chief executive decides on that record, and if the refund is due you get back everything you paid'
        || v_amt || ', the reveal fee and the card processing part together, to the card you paid with. Banks usually take ' || v_min || '–' || v_max || ' working days to show it.' || E'\n\n'
        || 'If you have an email thread with the supplier, keep it: it is the proof we rely on.',
      'استلمنا طلب الاسترداد',
      'استلمنا طلبكم استرداد رسوم الكشف. نتحقق أولًا من ردّ المورّد، ثم يبتّ رئيسنا التنفيذي في الطلب، فإن ثبت استحقاق الاسترداد فسيُعاد إليكم كامل المبلغ المدفوع إلى البطاقة نفسها خلال '
        || v_min || '–' || v_max || ' يوم عمل بحسب البنك.',
      '{}', 'refund_request_received:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req, 'money_ok', d->'money_ok');

  elsif t = 'refund.paid' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('refund_issued', 'customer', v_cust.email, (d->>'supplier_id')::bigint, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'Your QuotesDone refund of AED ' || (d->>'amount_aed') || ' has been issued',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'We have issued a refund of AED ' || (d->>'amount_aed') || ' — everything you paid on ' || v_revealed
        || ', the reveal fee and the card processing part together — to your original payment method, because the supplier did not respond within '
        || v_window::text || ' working days. Nothing is deducted.' || E'\n\n'
        || 'Banks and card issuers usually take ' || v_min || '–' || v_max || ' working days to show it on your statement. If it has not appeared after '
        || v_max || ' working days, reply to this email and we will trace it with the payment processor.' || E'\n\n'
        || 'You are welcome to post the request again; we will introduce you to another supplier.',
      'أصدرنا استردادًا بقيمة ' || (d->>'amount_aed') || ' درهم',
      'أصدرنا لكم استردادًا بقيمة ' || (d->>'amount_aed') || ' درهم، أي كامل المبلغ المدفوع، إلى وسيلة الدفع الأصلية، إذ لم يردّ المورّد خلال '
        || v_window::text || ' أيام عمل. وقد يستغرق ظهوره في كشف حسابكم ' || v_min || '–' || v_max || ' يوم عمل.',
      '{}', 'refund_issued:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req, 'amount_aed', d->'amount_aed');

  elsif t = 'refund.declined' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('refund_declined', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'About your refund request',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'We looked at your refund request for the reveal on ' || coalesce('"' || left(v_inq, 80) || '"', 'your request') || ' and it was not approved.' || E'\n\n'
        || 'The reason: ' || coalesce(nullif(btrim(d->>'note'), ''), 'the record shows the supplier did respond.') || E'\n\n'
        || 'If you think we have missed something, reply to this email with what you have — an email thread with the supplier, dates, anything — and we will look again.',
      'بشأن طلب الاسترداد',
      'راجعنا طلب الاسترداد وتعذّرت الموافقة عليه. السبب: ' || coalesce(nullif(btrim(d->>'note'), ''), 'يُظهر السجل أن المورّد قد ردّ.')
        || ' وإن كان لديكم ما يثبت خلاف ذلك، فيسعدنا أن تردّوا على هذه الرسالة لنعيد النظر في الطلب.',
      '{}', 'refund_declined:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'refund.in_progress' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('refund_in_progress', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'Your refund is being processed',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'Your refund of AED ' || coalesce(d->>'amount_aed', '') || ' has been approved and is being processed with the payment provider. It has not reached your card yet; we will write again the moment it has.',
      'استردادكم قيد المعالجة',
      'وافقنا على استردادكم، وهو الآن قيد المعالجة لدى مزوّد الدفع ولم يصل إلى بطاقتكم بعد. وسنُعلمكم فور وصوله.',
      '{}', 'refund_in_progress:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t in ('nonresponse.charge_raised', 'charge.corrected') then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_lines := '  Amount refunded to the customer: AED ' || (d->>'refunded_aed') || E'\n'
            || case when coalesce((d->>'processor_fee_aed')::numeric, 0) > 0
                    then '  Payment processor fee we could not recover (clause 33(b)): AED ' || (d->>'processor_fee_aed') || E'\n' else '' end
            || '  Administration fee: AED ' || (d->>'admin_fee_aed') || E'\n'
            || '  Interest: ' || round((d->>'interest_apr')::numeric * 100, 2) || '% a year, simple, on AED '
            || round(coalesce((d->>'charge_aed')::numeric, (d->>'refunded_aed')::numeric) + (d->>'admin_fee_aed')::numeric, 2) || ' from ' || (d->>'due_date') || ' until paid' || E'\n'
            || '  Due by: ' || (d->>'due_date')
            || case when coalesce((d->>'signed_version')::int, 0) >= 14
                    then E'\n  If it is not paid by then, the official fees of recovering it (court, payment-order, execution and notary fees) are added at cost (clause 33).' else '' end;
    if t = 'nonresponse.charge_raised' then
      v_req := public.fn_sales_engineer_writes('nonresponse_charge', 'supplier', v_sup.email, v_sup.id, null,
        (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
        'Charge under the Supplier Agreement — reveal #' || left(coalesce(d->>'transaction_id', ''), 8),
        'Hello ' || coalesce(v_sup.company_name, '') || E',\n\n'
          || 'A customer paid to reveal your contact details and did not hear from you within ' || v_window::text
          || ' working days, despite the reminders we sent. Under the Supplier Agreement the customer has been refunded in full, and that refund is recovered from your account:' || E'\n\n'
          || v_lines || E'\n\n'
          || 'Matching is paused until this is settled. You can pay it from the Billing section of your supplier portal. If you believe it is wrong, use "Dispute this charge" there or reply to this email and we will check the figures against the payment record.',
        'رسوم بموجب اتفاقية المورّد',
        'سدّد أحد العملاء رسوم الكشف عن بيانات التواصل معكم ولم يتلقَّ ردًّا خلال ' || v_window::text || ' أيام عمل رغم التذكيرات، فرُدّ إليه كامل ما دفعه بموجب اتفاقية المورّد، ويُسترد من حسابكم ما يلي: المبلغ المسترد '
          || (d->>'refunded_aed') || ' درهم، '
          || case when coalesce((d->>'processor_fee_aed')::numeric, 0) > 0 then 'ورسوم مزوّد خدمة الدفع التي لم نتمكن من استردادها ' || (d->>'processor_fee_aed') || ' درهم، ' else '' end
          || 'ورسوم إدارية ' || (d->>'admin_fee_aed') || ' درهم، وفائدة بسيطة ' || round((d->>'interest_apr')::numeric * 100, 2)
          || '% سنويًا من ' || (d->>'due_date') || ' حتى السداد.'
          || case when coalesce((d->>'signed_version')::int, 0) >= 14 then ' وإن لم يُسدَّد المبلغ في موعده، تُضاف بالتكلفة الرسوم الرسمية لتحصيله (رسوم المحكمة وأمر الأداء والتنفيذ والتوثيق) (البند 33).' else '' end
          || ' ويمكنكم السداد أو الاعتراض من قسم الفواتير في بوابتكم.',
        '{}', 'nonresponse_charge:' || (d->>'subject_id'));
    else
      -- THE CORRECTION MUST REACH WHOEVER GOT THE ORIGINAL: its To and every Cc, not today's address book.
      select * into v_orig from public.notifications where id = (d->>'original_notification_id')::bigint;
      v_req := public.fn_sales_engineer_writes('nonresponse_charge_correction', 'supplier',
        coalesce(v_orig.to_email, v_sup.email), v_sup.id, null, (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
        'Correction: ' || coalesce(v_orig.subject, 'your charge under the Supplier Agreement'),
        'This replaces our message of ' || coalesce(to_char(v_orig.created_at at time zone 'Asia/Dubai', 'DD Mon YYYY'), 'earlier')
          || ' about this charge, which carried the wrong figures. Please disregard it. The correct figures are:' || E'\n\n' || v_lines,
        'تصحيح: رسوم بموجب اتفاقية المورّد',
        'هذه الرسالة تحلّ محلّ رسالتنا السابقة التي تضمنت أرقامًا غير صحيحة. الأرقام الصحيحة: المبلغ المسترد ' || (d->>'refunded_aed')
          || ' درهم، ' || case when coalesce((d->>'processor_fee_aed')::numeric, 0) > 0 then 'ورسوم مزوّد خدمة الدفع ' || (d->>'processor_fee_aed') || ' درهم، ' else '' end || 'ورسوم إدارية ' || (d->>'admin_fee_aed') || ' درهم، مستحقة في ' || (d->>'due_date') || '.',
        coalesce(v_orig.cc_emails, '{}'), 'charge_corrected:' || (d->>'subject_id'));
    end if;
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'subscription.due' then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('subscription_due', 'supplier', v_sup.email, v_sup.id, null, null, null,
      'Your QuotesDone annual subscription is due',
      'Dear ' || coalesce(v_sup.company_name, 'there') || E',\n\nYour QuotesDone annual supplier subscription of '
        || coalesce(d->>'currency', 'AED') || ' ' || (d->>'fee') || E' is now due.\n\nYou keep paying no commission on the jobs you win — this is the annual subscription only. You can settle it securely on the supplier portal: https://quotesdone.com/suppliers\n\nIf it is not settled, your profile is paused from receiving new customer requests until it is.\n\nThank you for being part of QuotesDone.',
      'اشتراككم السنوي في QuotesDone مستحق',
      'حان موعد سداد اشتراككم السنوي كمورّد بقيمة ' || (d->>'fee') || ' درهم، ويمكنكم السداد بأمان من بوابة المورّد.',
      '{}', 'subscription_due:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'billing.answer' then
    v_lines := (select string_agg('  ' || x, E'\n') from jsonb_array_elements_text(d->'facts') x);
    if d->>'party' = 'supplier' then
      if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
      v_req := public.fn_sales_engineer_writes('billing_answer', 'supplier', v_sup.email, v_sup.id, null, null, null,
        'Your question about a charge', E'Here is what our records show:\n\n' || coalesce(v_lines, '  Nothing is recorded against your account.'),
        null, null, '{}', 'billing_answer:' || (d->>'subject_id'));
    else
      if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
      v_req := public.fn_sales_engineer_writes('billing_answer', 'customer', v_cust.email, null, v_cust.id, null, null,
        'Your question about a charge', E'Here is what our records show:\n\n' || coalesce(v_lines, '  No payment is recorded on your account.'),
        null, null, '{}', 'billing_answer:' || (d->>'subject_id'));
    end if;
    return jsonb_build_object('delivery_request', v_req, 'facts', d->'facts');

  elsif t = 'charge.dispute_answer' then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_lines := (select string_agg('  ' || x, E'\n') from jsonb_array_elements_text(d->'lines') x);
    v_req := public.fn_sales_engineer_writes('charge_dispute_answer', 'supplier', v_sup.email, v_sup.id, null, null, null,
      'Your query about charge #' || coalesce(d->>'due_id', ''),
      case when (d->>'figures_match')::boolean
           then E'We checked the charge against the payment record and the figures stand:\n\n'
           else E'We checked the charge against the payment record and the figures do not match it. It is on hold while our chief executive reviews it; you do not need to pay it until we write again.\n\n' end
        || coalesce(v_lines, ''),
      null, null, '{}', 'charge_dispute_answer:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req, 'figures_match', d->'figures_match');

  elsif t = 'refund.remediate' then
    return public.fn_sales_engineer_remediates(p_id);

  elsif t = 'delivery.result' then
    return public.fn_sales_engineer_attaches_delivery_result(p_id);

  elsif t in ('backup.refile', 'backup.remediate') then
    return public.fn_sales_engineer_refiles_backup(p_id);
  end if;
  raise exception 'sales_engineer has no handler for %', t;
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_answers_delivery_remediate(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  a public.agent_actions; req public.agent_actions; n public.notifications;
  v_role text; v_failed_email text; v_failed_ch text; v_cust uuid; v_lead bigint; v_subject text; v_body text;
  v_ch text; v_phone text; v_email text; v_rs bigint; v_type text;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff' and detail->>'type' = 'delivery.remediate';
  if not found then raise exception 'fn_sales_engineer_answers_delivery_remediate: % is not a delivery.remediate handoff', p_id; end if;
  select * into req from public.agent_actions where id = (a.detail->>'request_id')::bigint;
  if req.id is null then
    return jsonb_build_object('waiting', 'ceo re-verification', 'resend_request_id', null,
      'reply', 'sales_engineer: request ' || coalesce(a.detail->>'request_id', '?') || ' no longer exists, so there is nothing to resend.');
  end if;
  select * into n from public.notifications
   where id = coalesce((req.detail->>'retry_notification_id')::bigint, (req.evidence->>'notification_id')::bigint);
  v_role := coalesce(req.detail->>'recipient_role', n.to_role);
  v_failed_email := coalesce(n.to_email, req.detail->'prepared'->>'to_email', req.detail->>'to_email');
  if req.detail::text ilike '%ZZ DEMO%' or coalesce(v_failed_email, '') ilike '%@example.invalid' then
    return jsonb_build_object('waiting', 'ceo re-verification', 'resend_request_id', null,
      'reply', 'sales_engineer: a ZZ DEMO fixture; nothing is resent to a fixture address.');
  end if;
  v_failed_ch := coalesce(n.channel, req.detail->'prepared'->>'channel', 'email');
  v_cust := (req.detail->>'customer_id')::uuid;
  v_lead := coalesce((req.detail->>'supplier_id')::bigint, n.lead_id);
  v_type := coalesce(n.type, req.detail->>'msg_type');
  v_subject := coalesce(n.subject, req.detail->'prepared'->>'subject', req.detail->>'subject_en');
  v_body := coalesce(n.body, req.detail->'prepared'->>'body', req.detail->>'body_en');
  if coalesce(btrim(v_body), '') = '' then
    return jsonb_build_object('waiting', 'ceo re-verification', 'resend_request_id', null,
      'reply', 'sales_engineer: the words of the ' || coalesce(v_type, 'notice') || ' are gone, so it cannot be resent.');
  end if;

  if v_failed_ch <> 'whatsapp' then
    v_phone := public.fn_whatsapp_destination(v_role, v_cust, v_lead, v_failed_email);
    if v_phone is not null then v_ch := 'whatsapp'; end if;
  end if;
  if v_ch is null and v_failed_ch <> 'sms' then
    v_phone := public.fn_verified_mobile(v_role, v_cust, v_lead, v_failed_email);
    if v_phone is not null then v_ch := 'sms'; end if;
  end if;
  if v_ch is null then
    v_email := case v_role when 'customer' then (select c.email from public.customers c where c.id = v_cust)
                           when 'supplier' then (select coalesce(l.claimed_by, l.email) from public.leads l where l.id = v_lead) end;
    if coalesce(v_email, '') ~ '@' and v_email !~* '@example\.invalid$'
       and lower(btrim(v_email)) is distinct from lower(btrim(coalesce(v_failed_email, ''))) then
      v_ch := 'email';
    end if;
  end if;
  if v_ch is null then
    return jsonb_build_object('waiting', 'ceo re-verification', 'resend_request_id', null,
      'reply', 'sales_engineer: no other channel is on file for this ' || coalesce(v_role, 'recipient')
               || ' (the ' || v_failed_ch || ' send failed; no confirmed WhatsApp, verified mobile or other email).');
  end if;

  -- retry_of makes fn_originator_checks_delivery escalate rather than retry again if this one fails too.
  v_rs := public.fn_seat_handoff('sales_engineer', 'customer_support', 'delivery.request', 'notifications', 'remediate:' || a.id,
    jsonb_build_object('retry_of', req.id, 'remediate_handoff_id', a.id, 'msg_type', v_type, 'recipient_role', v_role,
      'to_email', coalesce(v_email, v_failed_email), 'supplier_id', v_lead, 'customer_id', v_cust,
      'inquiry_id', coalesce(n.inquiry_id::text, req.detail->>'inquiry_id'), 'quote_id', coalesce(n.quote_id::text, req.detail->>'quote_id'),
      'prepared', jsonb_build_object('type', v_type, 'kind', n.kind, 'to_role', v_role, 'lead_id', v_lead,
        'inquiry_id', coalesce(n.inquiry_id::text, req.detail->>'inquiry_id'), 'quote_id', coalesce(n.quote_id::text, req.detail->>'quote_id'),
        'subject', v_subject, 'body', v_body, 'lang', coalesce(n.lang, req.detail->>'locale', 'en'), 'channel', v_ch,
        'to_email', case when v_ch = 'email' then v_email else v_failed_email end,
        'to_phone', case when v_ch in ('whatsapp', 'sms') then v_phone end)));
  return jsonb_build_object('waiting', 'ceo re-verification', 'resend_request_id', v_rs, 'channel', v_ch,
    'reply', 'sales_engineer resent the ' || coalesce(v_type, 'notice') || ' to the ' || coalesce(v_role, 'recipient')
             || ' by ' || v_ch || ' (request ' || v_rs || ').');
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_answers_reveal_invoice(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  a public.agent_actions;
  c record;
  v_ar boolean;
  v_nid bigint;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' is distinct from 'invoice.issued' then
    raise exception 'fn_sales_engineer_answers_reveal_invoice: % is not an invoice.issued handoff', p_id;
  end if;
  select id, email into c from public.customers where id = (a.detail->>'customer_id')::uuid;
  if c.email is null or c.email !~ '@' then
    return jsonb_build_object('told', false, 'reason', 'no email address on file for the customer');
  end if;
  v_ar := public.fn_customer_notice_locale((a.detail->>'inquiry_id')::uuid, c.id) = 'ar';
  insert into public.notifications (type, to_email, to_role, inquiry_id, quote_id, subject, body, lang)
  values ('invoice_ready', c.email, 'customer',
          (a.detail->>'inquiry_id')::uuid, (a.detail->>'quote_id')::uuid,
          case when v_ar then 'فاتورتكم جاهزة' else 'Your invoice is ready' end,
          case when v_ar
            then 'أصبحت فاتورة رسوم الكشف التي سددتموها متاحة في حسابكم على QuotesDone، ويمكنكم فتحها في أي وقت من زر «الفاتورة» على العرض الذي كشفتموه، أو من «المستندات» ضمن «الفواتير».'
            else 'The invoice for the reveal fee you paid is now in your QuotesDone account. Open it any time from the "Invoice (PDF)" button on the quote you revealed, or under Invoices in Documents.'
          end,
          case when v_ar then 'ar' else 'en' end)
  returning id into v_nid;
  return jsonb_build_object('told', true, 'notification_id', v_nid, 'language', case when v_ar then 'ar' else 'en' end);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_attaches_delivery_result(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d jsonb; v_tx uuid; v_ev bigint; v_ref bigint; v_delivered boolean; v_rev jsonb; v_rem bigint;
begin
  select detail into d from public.agent_actions where id = p_id;
  v_tx := (d->>'transaction_id')::uuid;
  if v_tx is null then return jsonb_build_object('attached', false, 'reason', 'this delivery was not about a refund'); end if;
  v_delivered := case when d->>'result' = 'proof_of_response' then true
                      else coalesce((d->'evidence'->>'delivered')::boolean, false) end;
  insert into public.refund_ladder_evidence (transaction_id, refund_id, step, result, delivered, evidence, request_handoff_id, result_handoff_id)
  values (v_tx, (d->>'refund_id')::bigint,
          case when d->>'step' in ('chase', 'final_call', 'customer_notice', 'customer_proof') then d->>'step' else 'unknown' end,
          d->>'result', v_delivered, coalesce(d->'evidence', '{}'::jsonb), (d->>'request_id')::bigint, p_id)
  returning id into v_ev;

  if d->>'result' = 'proof_of_response' then
    insert into public.supplier_response_watch (transaction_id, lead_id, first_response_at, response_channel, response_ref)
    select v_tx, t.supplier_id, coalesce((d->'evidence'->'reply'->>'at')::timestamptz, now()),
           d->'evidence'->'reply'->>'channel', d->'evidence'->'reply'->>'ref'
      from public.transactions t where t.id = v_tx
    on conflict (transaction_id) do update
      set first_response_at = coalesce(public.supplier_response_watch.first_response_at, excluded.first_response_at),
          response_channel  = coalesce(public.supplier_response_watch.response_channel, excluded.response_channel),
          response_ref      = coalesce(public.supplier_response_watch.response_ref, excluded.response_ref);
  end if;

  v_rem := (d->>'remediation_id')::bigint;
  if v_rem is not null then
    perform public.fn_seat_handoff_complete(v_rem, jsonb_build_object('ladder_evidence_id', v_ev, 'result', d->>'result', 'delivered', v_delivered));
  elsif d->>'step' = 'final_call' then
    select id into v_ref from public.refunds where transaction_id = v_tx and status = 'requested' order by id desc limit 1;
    if v_ref is not null then v_rev := public.fn_ceo_refund_review(v_ref, 'final_call_result'); end if;
  end if;
  return jsonb_build_object('attached', true, 'ladder_evidence_id', v_ev, 'result', d->>'result', 'delivered', v_delivered, 'ceo_review', v_rev);
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_availability_tick(p_include_fixtures boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_expired int; r record; v jsonb; v_swept int := 0; v_flagged int := 0; v_new int := 0; v_cleared int := 0;
begin
  -- A busy date that has come: the supplier is available again, with nothing for him to do.
  with x as (
    update public.supplier_availability
       set state = 'available', busy_until = null, set_at = now(), set_by = 'sales_engineer (busy date reached)'
     where state = 'busy' and busy_until <= (now() at time zone 'Asia/Dubai')::date
    returning 1)
  select count(*)::int into v_expired from x;

  -- ponytail: one call per open inquiry (3 rows today); a set-based pass if open inquiries reach thousands.
  for r in
    select i.id from public.inquiries i
      join public.customers c on c.id = i.customer_id
     where i.status in ('sent', 'quoted')
       and (p_include_fixtures or not public.fn_seat_clock_customer_is_fixture(c))
    union
    select f.inquiry_id from public.stalled_inquiry_rescue f
     where f.cleared_at is null and (p_include_fixtures or not f.fixture)
  loop
    v := public.fn_stalled_inquiry_flag(r.id, 'sales_engineer.supplier_availability');
    v_swept := v_swept + 1;
    if coalesce((v->>'flagged')::boolean, false) then
      v_flagged := v_flagged + 1;
      if coalesce((v->>'new')::boolean, false) then v_new := v_new + 1; end if;
    end if;
    if coalesce((v->>'cleared')::boolean, false) then v_cleared := v_cleared + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'busy_expired', v_expired, 'inquiries_swept', v_swept,
                            'unreachable', v_flagged, 'newly_flagged', v_new, 'cleared', v_cleared);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_comparison_kpi(p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
with rep as (
  select c.inquiry_id, min(c.created_at) as reported_at
    from public.qd_compare_cache c
   where not (c.analysis ? '__failed')
     -- fixture run (qd.duty_fixtures = 'on'): ONLY demo requests; every real run: ONLY real ones
     and exists (select 1 from public.inquiries di where di.id::text = c.inquiry_id and public.fn_inquiry_is_demo(di.id))
         = (coalesce(current_setting('qd.duty_fixtures', true), '') = 'on')
     and c.created_at >= now() - make_interval(days => greatest(1, p_days))
   group by c.inquiry_id
),
q as (
  select r.inquiry_id,
         count(*) filter (where coalesce(qt.price_ex_vat, qt.quote_amount) is not null
                            and nullif(btrim(qt.lead_time), '') is not null
                            and nullif(btrim(qt.validity), '') is not null
                            and nullif(btrim(qt.warranty), '') is not null
                            and nullif(btrim(qt.payment_terms), '') is not null) as complete_n,
         count(*) filter (where nullif(btrim(qt.exclusions), '') is not null) as excl_n
    from rep r
    left join public.quotes qt on qt.inquiry_id::text = r.inquiry_id
   group by r.inquiry_id
),
t as (
  select r.inquiry_id, extract(epoch from (r.reported_at - i.created_at)) / 3600.0 as hours,
         q.complete_n, q.excl_n
    from rep r
    join q on q.inquiry_id = r.inquiry_id
    left join public.inquiries i on i.id::text = r.inquiry_id
)
select jsonb_build_object(
  'window_days', greatest(1, p_days),
  'reports', count(*),
  'hours_median', round((percentile_cont(0.5) within group (order by hours))::numeric, 1),
  'hours_p90', round((percentile_cont(0.9) within group (order by hours))::numeric, 1),
  'share_3plus_complete', case when count(*) > 0 then round(count(*) filter (where complete_n >= 3)::numeric / count(*), 3) end,
  'reports_with_exclusions', count(*) filter (where excl_n > 0),
  'quotes_with_exclusions', coalesce(sum(excl_n), 0))
from t;
$function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_comparison_report()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_lines jsonb; v_hash text; v_best uuid; v_rec text; v_n int; v_c int; v_old public.sales_engineer_comparison_report;
  n_new int := 0; n_refreshed int := 0; n_delivered int := 0; v_cust record; v_h bigint; v_first timestamptz;
begin
  for r in select i.id, i.created_at, i.customer_id, public.fn_inquiry_is_demo(i.id) demo
             from public.inquiries i
            where coalesce(i.status, 'open') not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
              and public.fn_inquiry_is_demo(i.id) = (coalesce(current_setting('qd.duty_fixtures', true), '') = 'on')
              and exists (select 1 from public.quotes q where q.inquiry_id = i.id and q.stale_at is null
                             and coalesce(q.status, 'submitted') not in ('withdrawn', 'rejected', 'expired', 'draft')) loop
    with q as (
      select q.id, coalesce(q.price_ex_vat, q.quote_amount) ex_vat, coalesce(q.vat_amount, 0) vat, q.created_at,
             array_remove(array[case when coalesce(q.price_ex_vat, q.quote_amount) is null then 'price' end,
                   case when nullif(btrim(q.lead_time), '') is null then 'lead_time' end,
                   case when nullif(btrim(q.validity), '') is null then 'validity' end,
                   case when nullif(btrim(q.warranty), '') is null then 'warranty' end,
                   case when nullif(btrim(q.payment_terms), '') is null then 'payment_terms' end], null) missing,
             q.lead_time, q.validity, q.warranty, q.payment_terms, nullif(btrim(q.exclusions), '') exclusions
        from public.quotes q
       where q.inquiry_id = r.id and q.stale_at is null and coalesce(q.status, 'submitted') not in ('withdrawn', 'rejected', 'expired', 'draft'))
    select jsonb_agg(jsonb_build_object('quote_id', id, 'price_ex_vat', ex_vat, 'vat', vat, 'total', ex_vat + vat,
             'lead_time', lead_time, 'validity', validity, 'warranty', warranty, 'payment_terms', payment_terms,
             'exclusions', exclusions, 'missing', to_jsonb(missing), 'complete', cardinality(missing) = 0) order by ex_vat + vat nulls last, id),
           md5(string_agg(id::text || ':' || coalesce(ex_vat, 0) || ':' || cardinality(missing), ',' order by id)),
           count(*), count(*) filter (where cardinality(missing) = 0),
           (array_agg(id order by ex_vat + vat, id) filter (where cardinality(missing) = 0))[1],
           min(created_at)
      into v_lines, v_hash, v_n, v_c, v_best, v_first
      from q;
    -- a report is due with 3+ complete quotes, or once the first quote has waited 48 hours
    continue when v_c < 3 and v_first > now() - interval '48 hours';
    select * into v_old from public.sales_engineer_comparison_report where inquiry_id = r.id;
    continue when found and v_old.quotes_hash = v_hash;
    v_rec := case when v_best is null then format('No quote is complete yet (%s received); the missing terms are being asked for before a recommendation.', v_n)
                  else format('Recommended: the lowest complete total of %s complete quote(s) out of %s, levelled ex-VAT plus VAT on the same five terms.', v_c, v_n) end;
    insert into public.sales_engineer_comparison_report (inquiry_id, quotes_hash, quotes_n, complete_n, lines, recommended_quote_id, recommendation, hours_to_report)
    values (r.id, v_hash, v_n, v_c, v_lines, v_best, v_rec,
            round((extract(epoch from now() - (select created_at from public.inquiries where id = r.id)) / 3600)::numeric, 1))
    on conflict (inquiry_id) do update set quotes_hash = excluded.quotes_hash, quotes_n = excluded.quotes_n, complete_n = excluded.complete_n,
      lines = excluded.lines, recommended_quote_id = excluded.recommended_quote_id, recommendation = excluded.recommendation, refreshed_at = now();
    if v_old.inquiry_id is null then n_new := n_new + 1; else n_refreshed := n_refreshed + 1; end if;

    -- delivered to the customer once, when there are two quotes to compare
    if v_n >= 2 and coalesce(v_old.delivered_at, null) is null then
      select id, email into v_cust from public.customers where id = r.customer_id;
      if v_cust.email like '%@%' and public.fn_is_demo_email(v_cust.email) = r.demo then
        v_h := public.fn_sales_engineer_writes('comparison_ready', 'customer', v_cust.email, null, v_cust.id, r.id, null,
          'Your quotations are compared',
          format('%s quotations for your request are levelled side by side on the same terms (price before VAT, VAT, lead time, validity, warranty, payment terms). %s Open your request in your QuotesDone account to read the comparison.', v_n, v_rec),
          'تمت مقارنة عروض الأسعار',
          format('تمت مقارنة %s من عروض الأسعار لطلبكم على الشروط نفسها (السعر قبل الضريبة، الضريبة، مدة التوريد، الصلاحية، الضمان، شروط الدفع). يمكنكم الاطلاع على المقارنة من طلبكم في حسابكم على QuotesDone.', v_n),
          '{}', 'comparison_ready:' || r.id, null, jsonb_build_object('report', 'sales_engineer_comparison_report'));
        update public.sales_engineer_comparison_report set delivered_at = now(), delivery_handoff_id = v_h where inquiry_id = r.id;
        n_delivered := n_delivered + 1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('reports_new', n_new, 'reports_refreshed', n_refreshed, 'delivered', n_delivered,
    'kpi_7d', public.fn_sales_engineer_comparison_kpi(7));
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_decides_vision_trades(p_action_id bigint, p_confirm text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions; v_supplier bigint; v_path text; cap public.supplier_capabilities; docs jsonb; d jsonb;
        i int; v_held jsonb; v_keep jsonb; v_codes text[] := '{}';
begin
  select * into a from public.agent_actions where id = p_action_id and kind = 'vision_trades_confirm' for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no_such_item'); end if;
  if a.status <> 'pending' then return jsonb_build_object('ok', false, 'error', 'already_decided', 'status', a.status); end if;
  v_supplier := (a.detail ->> 'supplier_id')::bigint; v_path := a.detail ->> 'path';
  select * into cap from public.supplier_capabilities where supplier_id = v_supplier for update;
  if found then
    docs := coalesce(cap.source_docs -> 'docs', '[]'::jsonb);
    for i in 0 .. jsonb_array_length(docs) - 1 loop
      d := docs -> i;
      continue when d ->> 'path' is distinct from v_path;
      v_held := coalesce(d -> 'vision_held', '[]'::jsonb);
      -- only a code that was held, and confirmed, is kept; it is marked as the sales engineer's confirmation
      select coalesce(jsonb_agg(h || jsonb_build_object('via', 'sales_engineer_confirmed')), '[]'::jsonb), coalesce(array_agg(distinct h ->> 'code'), '{}')
        into v_keep, v_codes
        from jsonb_array_elements(v_held) h where h ->> 'code' = any(coalesce(p_confirm, '{}'));
      docs := jsonb_set(docs, array[i::text], (d - 'vision_held') || jsonb_build_object('trades', coalesce(d -> 'trades', '[]'::jsonb) || v_keep));
    end loop;
    update public.supplier_capabilities
       set source_docs = jsonb_set(cap.source_docs, '{docs}', docs),
           proposed_trades = (select coalesce(array_agg(distinct c order by c), '{}') from unnest(coalesce(cap.proposed_trades, '{}') || v_codes) c)
     where supplier_id = v_supplier;
  end if;
  update public.agent_actions set status = case when cardinality(v_codes) > 0 then 'done' else 'dismissed' end,
         decided_at = now(), decided_by = 'sales_engineer',
         detail = detail || jsonb_build_object('confirmed', to_jsonb(v_codes))
   where id = a.id;
  return jsonb_build_object('ok', true, 'supplier_id', v_supplier, 'path', v_path, 'confirmed', to_jsonb(v_codes),
                            'status', case when cardinality(v_codes) > 0 then 'done' else 'dismissed' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_disputes_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'; d record; v_q bigint;
  v_review int := 0; v_overdue int := 0;
begin
  for d in select p.*, (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) as demo
             from public.post_reveal_dispute p left join public.customers c on c.id = p.customer_id
            where p.stage = 'evidence'
              and ((p.customer_evidence is not null and p.supplier_evidence is not null) or now() > p.evidence_due)
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
            order by p.id for update of p skip locked loop
    v_q := public.fn_seat_duty_reason('sales_engineer', 'sales_engineer.dispute_fault',
      case when d.demo then 'ZZ DEMO ' else '' end
      || 'A customer and a supplier disagree about a job after the supplier''s details were revealed. On the statements and evidence of both parties, which finding does the evidence support?',
      jsonb_build_array(
        jsonb_build_object('id', 'customer_upheld', 'meaning', 'the customer''s complaint is supported: the supplier fell short of what was agreed'),
        jsonb_build_object('id', 'supplier_upheld', 'meaning', 'the supplier''s position is supported: the supplier did what was agreed'),
        jsonb_build_object('id', 'shared', 'meaning', 'both parties contributed to the problem'),
        jsonb_build_object('id', 'no_fault', 'meaning', 'the evidence shows no fault by either party, or is too thin to find one')),
      jsonb_build_object('raised_by', d.raised_by, 'opened_at', d.opened_at, 'evidence_due', d.evidence_due,
                         'customer', d.customer_evidence, 'supplier', d.supplier_evidence),
      jsonb_build_object('dispute_id', d.id), 'dispute_fault:' || d.id);
    update public.post_reveal_dispute set stage = 'review', fault_question_id = v_q where id = d.id;
    v_review := v_review + 1;
  end loop;

  for d in select p.id, p.decision_due, p.finding from public.post_reveal_dispute p
             left join public.customers c on c.id = p.customer_id
            where p.stage = 'ceo_decision' and now() > p.decision_due
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx loop
    perform public.fn_it_engineer_finding_upsert('dispute_decision_overdue:' || d.id,
      'Post-reveal dispute QD-D-' || lpad(d.id::text, 5, '0') || ' is past its decision date',
      'public.post_reveal_dispute / fn_ceo_decides_post_reveal_dispute', 'agent_facing', 1,
      jsonb_build_object('dispute_id', d.id, 'decision_due', d.decision_due, 'owner_seat', 'ceo'),
      '{}'::text[], array['the CEO''s decision: select public.fn_ceo_decides_post_reveal_dispute(<id>, <outcome>, <note>)'],
      'sales_engineer');
    v_overdue := v_overdue + 1;
  end loop;
  return jsonb_build_object('to_review', v_review, 'decision_overdue', v_overdue);
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_duty_supply_gap()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_sales_engineer_supply_gap(10) $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_framework_proposal()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_id bigint; v_task bigint; n_drafted int := 0;
begin
  for r in select i.customer_id, t trade, count(*) n,
                  (select round(avg(q.quote_amount), 2) from public.quotes q join public.inquiries j on j.id = q.inquiry_id
                    where j.customer_id = i.customer_id and t = any(j.trades) and j.created_at > now() - interval '180 days') avg_quote
             from public.inquiries i, unnest(i.trades) t
            where i.created_at > now() - interval '180 days' and i.customer_id is not null
              and public.fn_inquiry_is_demo(i.id) = (coalesce(current_setting('qd.duty_fixtures', true), '') = 'on')
            group by i.customer_id, t having count(*) >= 3 loop
    continue when exists (select 1 from public.sales_engineer_framework_proposal where customer_id = r.customer_id and trade = r.trade);
    insert into public.sales_engineer_framework_proposal (customer_id, trade, requests_180d, quoted_total_aed, draft)
    values (r.customer_id, r.trade, r.n, r.avg_quote,
            format('Framework proposal (draft): %s requests for %s in 180 days, average quotation AED %s. Proposed: a 12-month framework for %s with pre-agreed rates from the best-performing suppliers, a fixed response time, and one levelled quotation per call-off. Rates and any fee change need the CEO''s approval before this is offered.',
                   r.n, r.trade, coalesce(r.avg_quote::text, 'not measured'), r.trade))
    returning id into v_id;
    v_task := public.fn_ceo_task_open(format('Approve framework proposal #%s (%s, %s requests)', v_id, r.trade, r.n),
      format('The sales engineer drafted framework proposal #%s for a repeat customer: %s requests for %s in 180 days. Approve or decline its rates; nothing is offered until you do.', v_id, r.n, r.trade));
    update public.sales_engineer_framework_proposal set ceo_task_id = v_task where id = v_id;
    n_drafted := n_drafted + 1;
  end loop;
  return jsonb_build_object('drafted', n_drafted,
    'by_status', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from public.sales_engineer_framework_proposal group by status) x));
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_knowledge_gap_tick()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_knowledge_gap_sweep(26, false) $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_ladder_step(p_transaction_id uuid, p_step text, p_refund_id bigint DEFAULT NULL::bigint, p_remediation_id bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t public.transactions; sup record; cust record; st jsonb; v_window int; v_chase int;
  v_final timestamptz; v_watch timestamptz; v_amt numeric; v_key text; v_days int; v_when text; v_extra jsonb;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found then raise exception 'no transaction %', p_transaction_id; end if;
  select id, company_name, coalesce(claimed_by, email) as email into sup from public.leads where id = t.supplier_id;
  select id, email, full_name into cust from public.customers where id = t.customer_id;
  select refund_window_working_days, chase_after_working_days into v_window, v_chase from public.pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3);
  st := public.fn_refund_state(t.id);
  v_final := (st->>'founder_call_due_at')::timestamptz;
  v_amt := round(coalesce(t.total_charged, t.reveal_fee, 0), 2);
  v_key := p_step || ':' || t.id || coalesce(':r' || p_remediation_id, '');
  v_days := coalesce((select (d.value #>> '{}')::int from public.decision_policy d where d.key = 'refund_final_call_watch_working_days'), 1);
  v_when := to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY');
  v_extra := jsonb_build_object('step', p_step, 'transaction_id', t.id, 'refund_id', p_refund_id, 'remediation_id', p_remediation_id);

  if p_step = 'chase' then
    v_watch := case when p_remediation_id is not null then public.fn_add_working_days(now(), 1)
                    else coalesce(v_final, public.fn_add_working_days(now(), greatest(v_window - v_chase, 1))) end;
    return public.fn_sales_engineer_writes('supplier_no_response_chase', 'supplier', sup.email, t.supplier_id, null, t.inquiry_id, t.quote_id,
      'Action needed: a customer is waiting for your response — QuotesDone reveal #' || left(t.id::text, 8),
      'Hello ' || coalesce(sup.company_name, '') || E',\n\n'
        || 'A customer paid to reveal your contact details on QuotesDone on ' || v_when || ' and has not heard from you. ' || v_chase
        || ' working days have passed. The customer is copied on this email so you can reply to all and pick it up here.' || E'\n\n'
        || 'Under the Supplier Agreement you must respond within ' || v_window || ' working days of the reveal, that is by '
        || coalesce(to_char(v_final at time zone 'Asia/Dubai', 'DD Mon YYYY'), 'the deadline')
        || '. If there is no response by then, our chief executive decides the case and the customer is refunded everything they paid (AED ' || v_amt
        || '). Under the Supplier Agreement you accepted, that amount is then recovered from your account with the administrative fee, interest and other amounts set out in its clause 33, and matching is paused until it is paid.' || E'\n\n'
        || 'If you have already been in touch with this customer, reply here and we will close this off.',
      'إجراء مطلوب: عميل بانتظار ردّكم — QuotesDone',
      'سدّد أحد العملاء رسوم الكشف عن بيانات التواصل معكم بتاريخ ' || v_when || ' ولم يتلقَّ منكم ردًّا بعد مرور ' || v_chase || ' أيام عمل، والعميل مُدرَج في نسخة هذه الرسالة. '
        || 'وتُلزم اتفاقية المورّد بالرد خلال ' || v_window || ' أيام عمل من تاريخ الكشف، وإلا فسيُردّ إلى العميل كامل ما دفعه (' || v_amt
        || ' درهم)، ويُسترد من حسابكم المبلغ المردود مع الرسم الإداري والفائدة وسائر المبالغ المبيّنة في البند 33 من اتفاقية المورّد التي قبلتموها، ويُعلَّق إسناد الطلبات إليكم حتى السداد. وإن كنتم قد تواصلتم مع العميل، فيُرجى الرد على هذه الرسالة.',
      array_remove(array[cust.email], null), v_key, v_watch, v_extra);

  elsif p_step = 'final_call' then
    v_watch := public.fn_add_working_days(now(), v_days);
    return public.fn_sales_engineer_writes('refund_final_notice', 'supplier', sup.email, t.supplier_id, null, t.inquiry_id, t.quote_id,
      'Final call: a customer is still waiting — QuotesDone reveal #' || left(t.id::text, 8),
      'Hello ' || coalesce(sup.company_name, '') || E',\n\n'
        || 'This is our final call about the customer who paid to reveal your contact details on ' || v_when
        || '. The ' || v_window || ' working days the Supplier Agreement allows have passed with no response from you, to the customer or to our reminder.' || E'\n\n'
        || 'If we do not hear from you by ' || to_char(v_watch at time zone 'Asia/Dubai', 'DD Mon YYYY')
        || ', the customer is refunded everything they paid (AED ' || v_amt || ') and that amount is recovered from your account with the administrative fee, interest and other amounts set out in clause 33 of the Supplier Agreement you accepted. '
        || 'Reply to this email, message the customer in your portal, or answer us on WhatsApp — any of them stops this.',
      'نداء أخير: عميل لا يزال بانتظار ردّكم — QuotesDone',
      'هذا نداؤنا الأخير بشأن العميل الذي كشف عن بيانات التواصل معكم بتاريخ ' || v_when || '، وقد انقضت أيام العمل المحددة دون ردّ منكم. '
        || 'فإن لم يصلنا ردّكم حتى ' || to_char(v_watch at time zone 'Asia/Dubai', 'DD Mon YYYY') || ' فسيُردّ إلى العميل كامل ما دفعه (' || v_amt
        || ' درهم)، ويُسترد من حسابكم المبلغ المردود مع الرسم الإداري والفائدة وسائر المبالغ المبيّنة في البند 33 من اتفاقية المورّد التي قبلتموها. ويكفي أي ردّ منكم عبر البريد الإلكتروني أو البوابة أو واتساب لإيقاف ذلك.',
      array_remove(array[cust.email], null), v_key, v_watch, v_extra);

  elsif p_step = 'customer_proof' then
    return public.fn_sales_engineer_writes('refund_proof_request', 'customer', cust.email, null, t.customer_id, t.inquiry_id, t.quote_id,
      'Anything you sent the supplier helps your refund case',
      'Hello ' || coalesce(nullif(btrim(cust.full_name), ''), 'there') || E',\n\n'
        || 'If you tried to reach the supplier yourself, forwarding that email to supplier@mail.quotesdone.com (or replying to it with that address in copy) puts it on your case and can help us close it faster. '
        || 'It is optional: it is never a condition of the refund, and you do not need to do anything for your case to be decided.',
      'مراسلاتكم مع المورّد تدعم حالة الاسترداد',
      'إن سبق أن تواصلتم مع المورّد بأنفسكم، فإن إعادة توجيه تلك الرسالة إلى supplier@mail.quotesdone.com (أو الرد عليها مع إضافة هذا العنوان في النسخة) تضمّها إلى حالتكم، وقد تساعدنا على إنهائها أسرع. هذا اختياري وليس شرطًا للاسترداد، ولا يلزمكم أي إجراء ليُبتّ في حالتكم.',
      '{}', v_key, null, v_extra);
  end if;
  raise exception 'no such ladder step %', p_step;
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_licence_expiry_watch()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_it_engineer_licence_expiry_watch() $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_negotiation_round()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; l jsonb; v_sup record; v_h bigint; n_clarify int := 0; n_bafo int := 0; n_answered int;
begin
  -- a round is answered when the supplier's quote has changed since it was asked (the levelled line moved)
  update public.sales_engineer_negotiation_round n set answered_at = now()
    from public.quotes q
   where n.answered_at is null and q.id = n.quote_id
     and (q.stale_at is not null or greatest(q.created_at, coalesce(q.committed_at, q.created_at)) > n.asked_at);
  get diagnostics n_answered = row_count;

  for r in select c.*, i.status, public.fn_inquiry_is_demo(c.inquiry_id) demo
             from public.sales_engineer_comparison_report c join public.inquiries i on i.id = c.inquiry_id
            where coalesce(i.status, 'open') not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
              and public.fn_inquiry_is_demo(c.inquiry_id) = (coalesce(current_setting('qd.duty_fixtures', true), '') = 'on') loop
    for l in select * from jsonb_array_elements(r.lines) loop
      select q.id, q.supplier_id, lw.company_name, lower(nullif(btrim(coalesce(lw.claimed_by, lw.email)), '')) email
        into v_sup from public.quotes q join public.leads lw on lw.id = q.supplier_id where q.id = (l->>'quote_id')::uuid;
      -- demo never reaches a real person, and a real request never writes to a fixture
      continue when v_sup.email is null or public.fn_is_demo_email(v_sup.email) <> r.demo;
      if not (l->>'complete')::boolean then
        continue when exists (select 1 from public.sales_engineer_negotiation_round where quote_id = v_sup.id and round = 'clarify');
        v_h := public.fn_sales_engineer_writes('negotiation_clarify', 'supplier', v_sup.email, v_sup.supplier_id, null, r.inquiry_id, v_sup.id,
          'Please complete your quotation',
          format(E'Dear %s,\n\nYour quotation does not yet state: %s. Please add these in your supplier portal so the customer has your complete terms.',
                 coalesce(nullif(btrim(case when v_sup.company_name ~ '[؀-ۿ]' then '' else v_sup.company_name end), ''), 'supplier'),
                 (select string_agg(replace(x, '_', ' '), ', ') from jsonb_array_elements_text(l->'missing') x)),
          null, null, '{}', 'negotiation_clarify:' || v_sup.id, now() + interval '2 days', jsonb_build_object('round', 'clarify'));
        insert into public.sales_engineer_negotiation_round (inquiry_id, quote_id, round, asked_for, handoff_id)
        values (r.inquiry_id, v_sup.id, 'clarify', l->'missing', v_h);
        n_clarify := n_clarify + 1;
      elsif r.complete_n >= 2 then   -- every complete quote alike: the invitation never depends on a quote's position
        continue when exists (select 1 from public.sales_engineer_negotiation_round where quote_id = v_sup.id and round = 'best_and_final');
        v_h := public.fn_sales_engineer_writes('negotiation_best_and_final', 'supplier', v_sup.email, v_sup.supplier_id, null, r.inquiry_id, v_sup.id,
          'Invitation to submit your best and final offer',
          format(E'Dear %s,\n\nYour quotation for this request is complete. You are invited, once, to submit your best and final offer in your supplier portal within 48 hours: price, lead time or payment terms. If you keep your quotation as it is, nothing more is needed.',
                 coalesce(nullif(btrim(case when v_sup.company_name ~ '[؀-ۿ]' then '' else v_sup.company_name end), ''), 'supplier')),
          null, null, '{}', 'negotiation_bafo:' || v_sup.id, now() + interval '2 days', jsonb_build_object('round', 'best_and_final'));
        insert into public.sales_engineer_negotiation_round (inquiry_id, quote_id, round, asked_for, handoff_id)
        values (r.inquiry_id, v_sup.id, 'best_and_final', jsonb_build_array('price', 'lead_time', 'payment_terms'), v_h);
        n_bafo := n_bafo + 1;
      end if;
    end loop;
  end loop;
  return jsonb_build_object('clarify_sent', n_clarify, 'best_and_final_sent', n_bafo, 'answered', n_answered,
    'open_rounds', (select count(*) from public.sales_engineer_negotiation_round where answered_at is null));
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_nudges_invited_suppliers(p_now timestamp with time zone DEFAULT now(), p_cap integer DEFAULT NULL::integer, p_include_fixtures boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_dxb timestamp := p_now at time zone 'Asia/Dubai';
  v_cfg jsonb := coalesce((select nullif(value, '')::jsonb from public.app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_hol text; v_cap int; v_used int; v_left int; v_queued int := 0; v_due int := 0; r record; v_link text;
  v_res jsonb; v_not_before timestamptz;
  v_gate text; v_inv_recent int; v_bounced_recent int; v_max_rate numeric;
begin
  select c.event_name into v_hol from public.company_calendar c
   where c.kind = 'public_holiday' and v_dxb::date between c.starts_on and coalesce(c.ends_on, c.starts_on) limit 1;
  if v_hol is not null then return jsonb_build_object('held', 'holiday: ' || v_hol, 'queued', 0); end if;
  if extract(isodow from v_dxb) in (6, 7) then return jsonb_build_object('held', 'UAE weekend', 'queued', 0); end if;
  -- THE SENDING WINDOW (review of #1007, 29 Sep 2026). The duty that calls this runs at 00:01 UTC (04:01 Dubai),
  -- before the window opens, so a start-hour HOLD would block every nudge. Instead a nudge queued before the
  -- window leaves no earlier than window_start_hour (default 9) Dubai the same day: not_before, exactly as
  -- enqueue_supplier_invites spreads its batch from the window's start. After window_end_hour it is held.
  v_not_before := greatest(p_now, (v_dxb::date + make_interval(hours => coalesce((v_cfg->>'window_start_hour')::int, 9)))
                                  at time zone 'Asia/Dubai');
  if extract(hour from v_dxb) >= coalesce((v_cfg->>'window_end_hour')::int, 17) then
    return jsonb_build_object('held', 'after the Dubai sending window', 'queued', 0); end if;
  -- THE GO SWITCH governs every mode, the probe's fixture mode included (30 Sep 2026).
  if not (coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
          and public.fn_supplier_outreach_golive()) then
    return jsonb_build_object('held', 'the supplier campaign is not open (invite_enabled / supplier_outreach_golive)', 'queued', 0,
                              'due', (select count(*) from public.fn_supplier_invite_nudges_due(p_now, p_include_fixtures)));
  end if;
  -- THE BATCH'S BRAKES, for real mail (a fixture address never leaves: send_outbox suppresses @example.invalid).
  if not p_include_fixtures then
    v_gate := public.fn_invite_placement_gate(v_dxb::date, p_now);
    if v_gate like 'fail:%' then
      return jsonb_build_object('held', 'inbox placement ' || v_gate, 'queued', 0); end if;
    -- enqueue_supplier_invites' 3-day bounce brake, read only (the batch owns the auto-pause)
    select count(*), count(*) filter (where invite_status = 'bounced') into v_inv_recent, v_bounced_recent
      from public.leads where invited_at > p_now - interval '3 days';
    v_max_rate := coalesce((select nullif(value, '')::numeric from public.app_secrets where key = 'invite_max_bounce_rate'), 0.08);
    if (v_inv_recent >= 15 and v_bounced_recent::numeric / greatest(v_inv_recent, 1) > v_max_rate)
       or v_bounced_recent >= greatest(5, ceil(v_inv_recent * v_max_rate)::int) then
      return jsonb_build_object('held', 'bounce brake: ' || v_bounced_recent || ' of ' || v_inv_recent || ' in 3 days', 'queued', 0); end if;
  end if;

  -- ONE daily cap for the domain: invitations and nudges queued this day, same class (real or fixture). The day is
  -- the UTC date, exactly as enqueue_supplier_invites counts it (review of #1007): on a Dubai-date basis the two
  -- would disagree between 00:00 and 04:00 Dubai and could each spend a full cap.
  v_cap := coalesce((select nullif(value, '')::int from public.app_secrets where key = 'invite_daily_cap'), 10);
  v_cap := least(v_cap, coalesce(p_cap, v_cap));
  select count(*) into v_used from public.notifications n
   where n.type in ('supplier_invite', 'supplier_invite_nudge')
     and (n.created_at at time zone 'UTC')::date = (p_now at time zone 'UTC')::date
     and public.fn_is_demo_email(n.to_email) = p_include_fixtures;
  v_left := greatest(0, v_cap - v_used);

  for r in select d.*, l.company_name, l.claim_token from public.fn_supplier_invite_nudges_due(p_now, p_include_fixtures) d
             join public.leads l on l.id = d.lead_id loop
    v_due := v_due + 1;
    continue when v_queued >= v_left;
    -- ALWAYS ENGLISH (review, 29 Sep 2026; founder rule: suppliers are always English): one copy, and the link is
    -- the invitation's own: fn_supplier_invite_link (#1051) - /en/portal with the claim token and the invitation ref.
    -- A lead with no claim token (the function then answers null) gets the plain English portal.
    v_link := coalesce(public.fn_supplier_invite_link(
                         (select nullif(btrim(value), '') from public.app_secrets where key = 'public_site_url'), r.claim_token, r.lead_id),
                       coalesce((select nullif(btrim(value), '') from public.app_secrets where key = 'public_site_url'), 'https://quotesdone.com')
                       || '/en/portal');
    v_res := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'supplier_invite_nudge', 'requested_by', 'sales_engineer', 'channel', 'email',
      'to_email', r.to_email, 'to_role', 'supplier', 'lead_id', r.lead_id, 'lang', 'en', 'dedupe_key', r.dedupe_key,
      'subject', case when r.step = 3 then 'A last reminder: ' else '' end || 'your invitation to join QuotesDone as a supplier',
      -- #1070's greeting guard: an Arabic-script company name is not written into an English letter
      'body', coalesce('Dear ' || nullif(btrim(case when r.company_name ~ '[\u0600-\u06FF]' then '' else r.company_name end), '') || ',',
                       'Dear Sir or Madam,') || E'\n\n'
          || 'A reminder of our invitation to register your company as a supplier on QuotesDone. It is free and takes a few minutes.'
          || E'\n\n' || v_link
          || case when r.step = 3 then E'\n\nThis is the last reminder we will send about it.' else '' end
          || E'\n\nIf you would rather not receive these e-mails, reply to this one and we will remove your address.')));
    -- support's handler queues the row without a not_before (it takes only the words and the address), so the
    -- requester sets the window start on the row it was just given back (by id, whatever the outbox's status:
    -- a fixture address is 'suppressed' on insert, a real one 'queued')
    update public.notifications set not_before = v_not_before
     where id = (v_res->0->>'notification_id')::bigint and type = 'supplier_invite_nudge';
    v_queued := v_queued + 1;
  end loop;
  return jsonb_build_object('held', null, 'due', v_due, 'queued', v_queued, 'cap', v_cap, 'used_before', v_used);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_onboarding_conversion()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_week date := date_trunc('week', now() at time zone 'Asia/Dubai')::date;
  v_order text[] := array['invited', 'clicked', 'registering', 'approved', 'matched', 'quoting'];
  v_stages jsonb; v_reached jsonb := '{}'::jsonb; v_conv jsonb := '{}'::jsonb; i int; v_n int; v_next int;
  v_worst text; v_worst_pct numeric; v_imp bigint; v_sent int; v_clicked int;
begin
  select coalesce(jsonb_object_agg(stage, n), '{}'::jsonb) into v_stages from (select stage, count(*) n from public.supplier_onboarding group by stage) x;
  -- reached stage k = now at stage k or any later stage (action_required counts as registering; closed is left out)
  for i in 1 .. array_length(v_order, 1) loop
    select count(*) into v_n from public.supplier_onboarding o
     where array_position(v_order, case when o.stage = 'action_required' then 'registering' else o.stage end) >= i;
    v_reached := v_reached || jsonb_build_object(v_order[i], v_n);
  end loop;
  for i in 1 .. array_length(v_order, 1) - 1 loop
    v_n := (v_reached->>v_order[i])::int; v_next := (v_reached->>v_order[i + 1])::int;
    v_conv := v_conv || jsonb_build_object(v_order[i] || '>' || v_order[i + 1], case when v_n > 0 then round(100.0 * v_next / v_n, 1) end);
    if v_n >= 20 and 100.0 * v_next / v_n < 20 and (v_worst_pct is null or 100.0 * v_next / v_n < v_worst_pct) then
      v_worst := v_order[i]; v_worst_pct := round(100.0 * v_next / v_n, 1);
    end if;
  end loop;
  select count(*) filter (where n.type = 'supplier_invite' and n.created_at > now() - interval '7 days' and not public.fn_is_demo_email(n.to_email))
    into v_sent from public.notifications n where n.type = 'supplier_invite' and n.created_at > now() - interval '7 days';
  select count(*) into v_clicked from public.leads where invite_clicked_at > now() - interval '7 days' and not coalesce(is_demo, false);

  if v_worst is not null then
    v_imp := public.fn_ceo_improvement_open('funnel_stage_drop', 'supplier_onboarding:' || v_worst || ':' || v_week,
      case when v_worst in ('invited', 'clicked') then 'marketing' else 'sales_engineer' end,
      format('Supplier onboarding: only %s%% of the %s suppliers who reached "%s" moved on this week. Find why they stop at this stage and change what they receive there.',
             v_worst_pct, v_reached->>v_worst, v_worst),
      jsonb_build_object('week', v_week, 'stage', v_worst, 'conversion_pct', v_conv, 'reached', v_reached, 'invites_sent_7d', v_sent));
  end if;
  insert into public.sales_engineer_onboarding_week (week, stages, reached, conversion_pct, invites_sent_7d, invites_clicked_7d, bottleneck, improvement_id)
  values (v_week, v_stages, v_reached, v_conv, v_sent, v_clicked, v_worst, v_imp)
  on conflict (week) do update set stages = excluded.stages, reached = excluded.reached, conversion_pct = excluded.conversion_pct,
    invites_sent_7d = excluded.invites_sent_7d, invites_clicked_7d = excluded.invites_clicked_7d, bottleneck = excluded.bottleneck,
    improvement_id = coalesce(excluded.improvement_id, sales_engineer_onboarding_week.improvement_id), recorded_at = now();
  return jsonb_build_object('week', v_week, 'reached', v_reached, 'conversion_pct', v_conv, 'bottleneck', v_worst,
    'improvement_id', v_imp, 'invites_sent_7d', v_sent, 'invites_clicked_7d', v_clicked);
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_quote_quality_tick(p_include_fixtures boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_hours numeric := public.fn_seat_clock_policy('quote_quality_hold_hours', 24);
  h record; q public.quotes; v_flags jsonb; m jsonb; v jsonb; v_to text; v_why text; v_key text; v_md5 text; v_notice jsonb;
  v_sent int := 0; v_corrected int := 0; v_waited int := 0; v_left_to_spec int := 0; v_told int := 0;
  v_not_sent jsonb := '[]'::jsonb; v_not_the_accepted int := 0;
begin
  for h in
    select x.*, i.category, i.emirate, i.lang as inq_lang, i.status as inq_status, public.fn_job_no(x.inquiry_id) as job_no,
           c.email as cemail, c.full_name as cname, l.company_name, lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email))) as semail
      from public.quote_quality_hold x
      join public.inquiries i on i.id = x.inquiry_id
      left join public.customers c on c.id = i.customer_id
      left join public.leads l on l.id = x.supplier_id
     where x.released_at is null and x.superseded_at is null and (p_include_fixtures or not x.fixture)
     order by x.held_at
  loop
    select * into q from public.quotes where id = h.quote_id;
    -- ONLY THE VERSION THE DOOR ACCEPTED (review of #1108, 29 Sep 2026). The gate runs only when acceptLive sets
    -- 'submitted', so accepted_md5 is content that passed the exact-specs gate, the review's rules 1-7 and the accept rule.
    -- Content that has changed since was written by a submission the door has not (yet) accepted: nothing is sent and
    -- nothing is released - a wait never publishes it. supplier_api supersedes the hold when it rejects a submission.
    if public.fn_quote_quality_content_md5(q) is distinct from h.accepted_md5 then
      v_not_the_accepted := v_not_the_accepted + 1;
      continue;
    end if;
    v_flags := public.fn_quote_quality_flags(q);

    -- (a) the fixes, once per distinct set, while the quote is still flagged
    if jsonb_array_length(v_flags) > 0 then
      if v_flags is distinct from h.flags then
        update public.quote_quality_hold set flags = v_flags, fixes_en = public.fn_quote_quality_fixes_en(v_flags), updated_at = now()
         where quote_id = h.quote_id;
      end if;
      v_md5 := md5(public.fn_quote_quality_fixes_en(v_flags));
      if v_md5 is distinct from h.fixes_sent_md5 and now() < h.release_due then
        m := public.fn_quote_quality_compose('supplier', 'en', jsonb_build_object('name', h.company_name, 'category', h.category,
               'emirate', h.emirate, 'job_no', h.job_no, 'fixes', public.fn_quote_quality_fixes_en(v_flags),
               'due', to_char(h.release_due at time zone 'Asia/Dubai', 'DD Mon YYYY, HH24:MI')));
        v_key := 'quote_quality_fixes:' || h.quote_id || ':' || left(v_md5, 12);
        v_why := public.fn_seat_clock_refusal(h.fixture, h.semail, 'quote_quality_fixes');
        if v_why is null and public.fn_seat_clock_asked(v_key) then v_why := 'already sent'; end if;
        if v_why is null then
          v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
            'type', 'quote_quality_fixes', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', h.semail,
            'to_role', 'supplier', 'lead_id', h.supplier_id, 'inquiry_id', h.inquiry_id, 'quote_id', h.quote_id,
            'lang', 'en', 'subject', m->>'subject', 'body', m->>'body', 'dedupe_key', v_key)));
          update public.quote_quality_hold set fixes_sent_md5 = v_md5, fixes_sent_at = now(), fixes_delivery = v->0, updated_at = now()
           where quote_id = h.quote_id;
          v_sent := v_sent + 1;
        else
          update public.quote_quality_hold set fixes_delivery = jsonb_build_object('sent', false, 'reason', v_why), updated_at = now()
           where quote_id = h.quote_id;
          v_not_sent := v_not_sent || jsonb_build_array(jsonb_build_object('quote_id', h.quote_id, 'reason', v_why));
        end if;
      end if;
    end if;

    -- (b) corrected, or waited its hours: released (the hold is marked first, so the gate lets it through)
    if jsonb_array_length(v_flags) = 0 or now() >= h.release_due then
      update public.quote_quality_hold
         set flags = v_flags, released_at = now(),
             release_reason = case when jsonb_array_length(v_flags) = 0 then 'corrected' else 'waited_24h' end,
             corrected_at = case when jsonb_array_length(v_flags) = 0 then now() end, updated_at = now()
       where quote_id = h.quote_id;
      if jsonb_array_length(v_flags) = 0 then v_corrected := v_corrected + 1; else v_waited := v_waited + 1; end if;
      -- a quote the exact-specs desk holds (quote_spec_hold) is that desk's to release
      if coalesce(q.status, '') = 'draft' and not exists (select 1 from public.quote_spec_hold s
                                                          where s.quote_id = h.quote_id and s.state in ('open', 'awaiting_approval')) then
        update public.quotes set status = 'submitted' where id = h.quote_id and status = 'draft';
        update public.inquiries set status = 'quoted' where id = h.inquiry_id and status in ('sent', 'quoted');
        m := public.fn_quote_quality_compose('customer', h.inq_lang, jsonb_build_object('name', h.cname, 'category', h.category,
               'emirate', h.emirate, 'hours', v_hours, 'waited', jsonb_array_length(v_flags) > 0));
        v_key := 'quote_quality_release:' || h.quote_id;
        v_to := lower(btrim(coalesce(h.cemail, '')));
        v_why := public.fn_seat_clock_refusal(h.fixture, v_to, 'new_quote');
        if v_why is null and public.fn_seat_clock_asked(v_key) then v_why := 'already told'; end if;
        if v_why is null then
          v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
            'type', 'new_quote', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', v_to, 'to_role', 'customer',
            'inquiry_id', h.inquiry_id, 'quote_id', h.quote_id, 'lang', m->>'lang', 'subject', m->>'subject', 'body', m->>'body',
            'dedupe_key', v_key)));
          v_notice := jsonb_build_object('sent', coalesce(v->0->>'status', '') <> 'failed', 'lang', m->>'lang', 'delivery', v->0);
          if (v_notice->>'sent')::boolean then v_told := v_told + 1; end if;
        else
          v_notice := jsonb_build_object('sent', false, 'lang', m->>'lang', 'reason', v_why);
        end if;
        update public.quote_quality_hold set customer_notice = v_notice where quote_id = h.quote_id;
      else
        v_left_to_spec := v_left_to_spec + 1;
      end if;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'hold_hours', v_hours, 'fixes_sent', v_sent, 'fixes_not_sent', v_not_sent,
    'released_corrected', v_corrected, 'released_after_wait', v_waited, 'left_to_the_spec_desk', v_left_to_spec,
    'customers_told', v_told, 'content_not_the_accepted_version', v_not_the_accepted,
    'open', (select count(*) from public.quote_quality_hold where released_at is null and superseded_at is null and (p_include_fixtures or not fixture)));
end
$function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_raises_undecided_submissions(p_include_fixtures boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v jsonb; rep jsonb; v_acted int := 0; v_raised int := 0; v_already int := 0; v_refused jsonb := '[]'::jsonb;
begin
  for r in select l.id, l.company_name, l.registration_submitted_at, l.approval_status
             from public.leads l
            where l.registration_submitted_at < now() - interval '24 hours'
              and coalesce(l.approval_status, '') in ('', 'pending')
              and coalesce(l.banned, false) = false
              and (p_include_fixtures or not (coalesce(l.is_demo, false) or coalesce(l.company_name, '') ~* '^\s*zz\s*demo'
                                              or public.fn_is_demo_email(l.email)))
            order by l.registration_submitted_at loop
    v := public.fn_sales_engineer_verifies_supplier(r.id, 'submission_24h_clock');
    if coalesce((v->>'ok')::boolean, false) and coalesce(v->>'approval_status', '') not in ('', 'pending') then
      v_acted := v_acted + 1;
      continue;
    end if;
    rep := public.fn_support_report_to_ceo(
      'supplier_submission_undecided:' || r.id || ':' || extract(epoch from r.registration_submitted_at)::bigint,
      'elevated',
      'A supplier registration submitted ' || floor(extract(epoch from now() - r.registration_submitted_at) / 3600)::int
        || ' h ago is still undecided — ' || left(coalesce(r.company_name, 'supplier #' || r.id), 120),
      jsonb_build_object('supplier_id', r.id, 'submitted_at', r.registration_submitted_at,
                         'approval_status', coalesce(v->>'approval_status', r.approval_status), 'verification', v),
      jsonb_build_array('sales_engineer re-ran its verification at the 24-hour mark: '
                        || coalesce(v->>'approval_status', 'the verification did not complete (' || coalesce(v->>'error', 'no error') || ')')),
      case when coalesce((v->>'auto_approve')::boolean, true) = false
           then 'Decide the approval. The six items are complete and pricing_config.auto_approve_suppliers is off, so the sales engineer may not approve alone.'
           else 'Decide why the verification cannot settle this registration, and settle it.' end,
      'leads#' || r.id, p_source_agent => 'sales_engineer');
    if not coalesce((rep->>'ok')::boolean, false) then
      v_refused := v_refused || jsonb_build_array(jsonb_build_object('supplier_id', r.id, 'reason', rep->>'reason'));
    elsif coalesce((rep->>'duplicate')::boolean, false) then v_already := v_already + 1;
    else v_raised := v_raised + 1;
    end if;
  end loop;
  return jsonb_build_object('acted', v_acted, 'raised_to_ceo', v_raised, 'already_raised', v_already, 'refused', v_refused);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_refiles_backup(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  a public.agent_actions; fin jsonb; fout jsonb := '[]'::jsonb; v_att int; v_row bigint; n int; v_out text;
  v_enq boolean := false; s record;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  v_att := coalesce((a.detail->>'refile_attempts')::int, 0) + 1;
  fin := coalesce(a.detail->'files',
           jsonb_build_array(jsonb_build_object('key', 'db:' || (a.detail->>'doc_backup_id'), 'reason', a.detail->>'reason',
                                                'doc_backup_id', (a.detail->>'doc_backup_id')::bigint)));
  for s in select e from jsonb_array_elements(fin) e loop
    v_row := (s.e->>'doc_backup_id')::bigint; v_out := null;
    if v_row is null then
      -- never queued: the enqueue first, then a row of our own for what it does not cover
      if not v_enq then perform public.fn_enqueue_doc_backups(); v_enq := true; end if;
      -- 22 SEP 2026: the row for THIS file, by the join rule of the expected-status view, on the file
      -- in hand. It used to recompute all ~10,600 expected items (2.7 s) once per file, and seven files
      -- put the IT engineer's daily check past PostgREST's 8 s. See the header.
      if s.e->>'kind' = 'generated' then
        select d.id into v_row from public.doc_backups d
         where d.gen_kind = s.e->>'gen_kind' and d.gen_ref = s.e->>'gen_ref'
         order by (d.status = 'done') desc, d.id desc limit 1;
      elsif s.e->>'bucket' is not null then
        select d.id into v_row from public.doc_backups d
         where d.bucket = s.e->>'bucket' and d.path = s.e->>'path'
         order by (d.status = 'done') desc, d.id desc limit 1;
      end if;
      if v_row is null and s.e->>'bucket' is not null and s.e->>'kind' <> 'conversation' then
        insert into public.doc_backups (entity, entity_id, doc_type, bucket, path, file_name, dropbox_path, source, dedupe_key)
        values (split_part(s.e->>'owner', ':', 1), split_part(s.e->>'owner', ':', 2), 'Refiled', s.e->>'bucket', s.e->>'path',
                regexp_replace(s.e->>'path', '^.*/', ''), '/QuotesDone Backup/Refiled/' || (s.e->>'bucket') || '/' || (s.e->>'path'),
                'storage', 'REFILE:' || (s.e->>'bucket') || ':' || (s.e->>'path'))
        on conflict do nothing returning id into v_row;
      elsif v_row is null and s.e->>'kind' = 'generated' then
        insert into public.doc_backups (entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key)
        values (split_part(s.e->>'owner', ':', 1), split_part(s.e->>'owner', ':', 2), 'Refiled', 'generated', s.e->>'gen_kind', s.e->>'gen_ref',
                '/QuotesDone Backup/Refiled/' || (s.e->>'gen_kind') || '/' || (s.e->>'gen_ref') || '.pdf', 'REFILE:' || (s.e->>'item_key'))
        on conflict do nothing returning id into v_row;
      end if;
      v_out := case when v_row is null then 'cannot_refile: no source to file from' else 'queued' end;
    end if;
    if v_row is not null and v_out is null then
      update public.doc_backups
         set status = 'pending', attempts = 0, verified_at = null, requeued_at = now(),
             error = left('refile ' || v_att || ': ' || coalesce(s.e->>'reason', 'requested') || ' (handoff ' || p_id || ')', 300)
       where id = v_row and status <> 'abandoned';
      get diagnostics n = row_count;
      v_out := case when n = 1 then 'requeued' else 'cannot_refile: row missing or abandoned' end;
    end if;
    fout := fout || (s.e || jsonb_build_object('doc_backup_id', v_row, 'refile', v_out));
  end loop;
  update public.agent_actions
     set detail = detail || jsonb_build_object('files', fout, 'refile_attempts', v_att, 'refiled_at', now(), 'sales_done_at', now())
   where id = p_id;
  return jsonb_build_object('waiting', 'it_engineer re-verification', 'refile_attempt', v_att, 'files', fout);
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_remediates(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d jsonb; v_tx uuid; v_req bigint; v_step text;
begin
  select detail into d from public.agent_actions where id = p_id;
  v_tx := (d->>'transaction_id')::uuid;
  v_step := case d->>'remedy_key' when 'final_call' then 'final_call' when 'chase' then 'chase' when 'customer_proof' then 'customer_proof' end;
  if v_step is null then
    return jsonb_build_object('waiting', 'no automatic remedy for ' || coalesce(d->>'remedy_key', '?'));
  end if;
  v_req := public.fn_sales_engineer_ladder_step(v_tx, v_step, (d->>'refund_id')::bigint, p_id);
  return jsonb_build_object('delivery_request', v_req,
    'waiting', case v_step when 'customer_proof' then 'the customer: the proof is requested and this closes when it arrives'
                           else 'the supplier: support is delivering the ' || replace(v_step, '_', ' ') || ' and watching every channel for a reply' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_reports_complete(p_report_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int;
begin
  update public.support_ceo_report r
     set status = 'completed', completed_at = now(),
         completion_note = 'sales_engineer saw the CEO''s receipt: ' || r.acceptance_receipt
           || coalesce(' Outcome: ' || (select a.evidence->>'verdict' from public.agent_actions a
                                         where a.kind = 'handoff' and a.agent = 'sales_engineer'
                                           and a.target_id = 'delivery.remediate:' || r.id and a.status = 'done'
                                         order by a.id desc limit 1), '')
   where r.source_agent = 'sales_engineer' and r.status = 'accepted' and r.acceptance_receipt is not null
     and (p_report_id is null or r.id = p_report_id)
     and not exists (select 1 from public.agent_actions a
                      where a.kind = 'handoff' and a.agent = 'sales_engineer'
                        and a.target_id = 'delivery.remediate:' || r.id and a.status <> 'done');
  get diagnostics n = row_count;
  return jsonb_build_object('completed_after_receipt', n);
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_rescue_pool(p_trades text[], p_emirate text)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select count(*)::int
    from public.leads l
   where l.id in (select e.id from public.fn_supplier_invite_eligible_ids() e(id))
     and l.invite_trades && coalesce(p_trades, '{}'::text[])
     and (p_emirate is null or p_emirate = 'UAE' or l.emirate = p_emirate)
$function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_reveal_followup_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  r record; v jsonb; v_lang text; v_ar boolean; v_name text; v_cat text; v_ref text; v_sent int := 0; v_seen int := 0;
begin
  for r in
    with q as (
      select coalesce(i.parent_inquiry_id, i.id) as root, min(qt.created_at) as first_at, count(*) as n
        from public.quotes qt join public.inquiries i on i.id = qt.inquiry_id
       where qt.status = 'submitted' and (qt.expires_at is null or qt.expires_at > now())
       group by 1)
    select q.root, q.first_at, q.n, p.rfq_no, p.category, c.id as cid, c.full_name, c.email, c.locale,
           case when q.first_at <= now() - interval '7 days' then 'day_seven' else 'day_two' end as stage
      from q join public.inquiries p on p.id = q.root join public.customers c on c.id = p.customer_id
     where ((q.first_at <= now() - interval '2 days' and q.first_at > now() - interval '6 days')
         or (q.first_at <= now() - interval '7 days' and q.first_at > now() - interval '21 days'))
       and p.hired_supplier_id is null and p.completed_at is null
       and coalesce(p.status, '') not in ('cancelled', 'closed', 'completed', 'revealed')
       and not coalesce(c.banned, false)
       and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
       and not exists (select 1 from public.transactions t join public.inquiries x on x.id = t.inquiry_id
                        where t.revealed_at is not null and coalesce(x.parent_inquiry_id, x.id) = q.root)
     order by q.first_at limit 200
  loop
    v_seen := v_seen + 1;
    v_lang := public.fn_customer_message_lang(r.root, r.locale);
    v_ar := v_lang = 'ar';
    v_name := coalesce(nullif(btrim(r.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
    v_cat := coalesce(public.fn_trade_label(r.category, v_lang), case when v_ar then 'طلبكم' else 'your request' end);
    v_ref := 'RFQ-' || coalesce(r.rfq_no::text, '-');
    v := public.fn_customer_support_duty_send('reveal.' || r.stage, r.root::text, 'customer', r.email, v_lang,
      case when v_ar then
        case when r.stage = 'day_two' then 'عروضكم جاهزة للمقارنة - ' || v_ref else 'تذكير أخير: عروض ' || v_ref || ' ما زالت بانتظاركم' end
      else
        case when r.stage = 'day_two' then 'Your quotes are ready to compare - ' || v_ref else 'Last reminder: your quotes on ' || v_ref || ' are waiting' end
      end,
      case when v_ar then
        case when nullif(btrim(r.full_name), '') is null then 'عميلنا الكريم،' else 'السادة/ ' || v_name || ' المحترمين،' end || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'وصلكم ' || r.n || ' من العروض على طلبكم ' || v_ref || ' (' || v_cat || ')، ويرتّب تقرير المقارنة أفضل ثلاثة منها من حيث القيمة. '
        || 'لا تكشفون إلا بيانات المورّد الذي تختارونه، ولا تدفعون 3% إلا حينها.' || chr(10) || chr(10)
        || 'وإن كان في أحد العروض ما يحتاج إلى توضيح - السعر أو النطاق أو الشروط - فأضيفوا ملاحظتكم أو سؤالكم من صفحة الطلب، فتصل إلى جميع المورّدين دون اسمكم أو رقمكم، أو ردّوا على هذه الرسالة لنساعدكم في المقارنة.' || chr(10) || chr(10)
        || 'افتحوا عروضكم من هنا: https://quotesdone.com/ar/me' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'You have ' || r.n || case when r.n = 1 then ' quote' else ' quotes' end || ' on ' || v_ref || ' (' || v_cat || '), and your comparison report ranks the top three by value. '
        || 'You reveal only the supplier you choose, and pay 3% only then.' || chr(10) || chr(10)
        || 'If anything in a quote needs explaining - the price, the scope or the terms - add your note or question on the request page and it reaches every supplier without your name or number, or reply to this e-mail and we will help you compare.' || chr(10) || chr(10)
        || 'Open your quotes: https://quotesdone.com/me' || chr(10) || chr(10)
        || 'Kind regards,'
      end,
      r.cid, null, r.root);
    if (v->>'sent')::boolean then v_sent := v_sent + 1; end if;
  end loop;
  return jsonb_build_object('seen', v_seen, 'sent', v_sent, 'fixture', v_fx);
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_self_review()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_seat_self_review((now() at time zone 'Asia/Dubai')::date, 'sales_engineer') $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_sends_registration_reminder(p_lead_id bigint, p_stage text, p_step integer, p_last_activity timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare l public.leads; v_to text; v_fixture boolean; v_go boolean; m jsonb; v_key text; v_out jsonb;
begin
  select * into l from public.leads where id = p_lead_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'lead_not_found'); end if;
  v_to := lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email)));
  v_fixture := public.fn_is_demo_email(v_to);
  v_go := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
          and public.fn_supplier_outreach_golive();
  if not v_fixture and not v_go then
    return jsonb_build_object('ok', false, 'held', true, 'reason', 'the supplier campaign is not open (invite_enabled / supplier_outreach_golive)');
  end if;
  if not v_fixture and not public.fn_supplier_outreach_reachable(l, v_to) then
    return jsonb_build_object('ok', false, 'reason', 'not reachable: fixture, banned, screened, closed, bounced, suppressed or unsendable');
  end if;
  m := public.fn_supplier_registration_reminder_compose(l, p_stage, p_step);
  v_key := 'supplier_registration_reminder:' || l.id || ':' || extract(epoch from p_last_activity)::bigint || ':' || p_step;
  v_out := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
    'type', 'supplier_registration_reminder', 'requested_by', 'sales_engineer', 'channel', 'email',
    'to_email', v_to, 'to_role', 'supplier', 'lead_id', l.id, 'lang', m->>'lang',
    'subject', m->>'subject', 'body', m->>'body', 'dedupe_key', v_key)));
  return jsonb_build_object('ok', true, 'lead_id', l.id, 'stage', p_stage, 'step', p_step, 'lang', m->>'lang', 'fixture', v_fixture,
                            'delivery', v_out->0);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_spec_handoff_waits(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object('waiting', coalesce(a.detail ->> 'waiting_for',
                                                'the sales engineer to help the customer settle the spec'))
    from public.agent_actions a where a.id = p_id
$function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_stalled_inquiry_notice(p_lang text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_ar boolean := coalesce(p_lang, '') like 'ar%';
  v_lang text := case when coalesce(p_lang, '') like 'ar%' then 'ar' else 'en' end;
  v_name text := nullif(btrim(coalesce(p->>'name', '')), '');
  v_hours int := coalesce((p->>'hours')::numeric, 48)::int;
  v_pool int := coalesce((p->>'pool')::int, 0);
  v_unreachable boolean := coalesce(p->>'reason', '') = 'no_reachable_supplier';
  v_site text; v_link text; v_trade text; v_trade_ar text; v_em text; v_em_ar text; v_where text; v_where_ar text;
  v_subj text; v_body text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  v_link := coalesce(v_site, 'https://quotesdone.com') || '/' || v_lang || '/portal';
  select t.label, coalesce(t.label_ar, t.label) into v_trade, v_trade_ar
    from public.taxonomy_trade t
   where t.code = (public.fn_taxonomy_trades_for(array[coalesce(p->>'category', '')]))[1];
  v_trade := coalesce(v_trade, nullif(p->>'category', ''), 'your trade');
  v_trade_ar := coalesce(v_trade_ar, nullif(p->>'category', ''), 'تخصصكم');
  v_em := nullif(btrim(coalesce(p->>'emirate', '')), '');
  v_em_ar := case lower(coalesce(v_em, '')) when 'dubai' then 'دبي' when 'abu dhabi' then 'أبوظبي' when 'sharjah' then 'الشارقة'
               when 'ajman' then 'عجمان' when 'umm al quwain' then 'أم القيوين' when 'ras al khaimah' then 'رأس الخيمة'
               when 'fujairah' then 'الفجيرة' else v_em end;
  v_where := v_trade || coalesce(' in ' || v_em, '');
  v_where_ar := v_trade_ar || coalesce(' في ' || v_em_ar, '');

  if v_ar then
    v_subj := 'مستجدات طلبكم — ' || v_where_ar;
    v_body := coalesce('السادة/ ' || v_name || ' المحترمين،', 'عميلنا العزيز،') || E'\n\nتحية طيبة وبعد،\n\n'
      || case when v_unreachable
           then 'لم يصل طلبكم في مجال ' || v_where_ar || ' بعدُ إلى مورّد يستطيع تسعيره، إذ لا يتوفر حاليًا أيٌّ من الموردين المسجّلين في هذا المجال لتولّيه. '
           else 'مضت ' || v_hours || ' ساعة على إرسال طلبكم في مجال ' || v_where_ar
                || ' إلى الموردين المطابقين، ولم يصلنا أي عرض سعر حتى الآن. ' end
      || case when v_pool > 0
           then 'ولذلك قدّمنا مجال طلبكم ومنطقته على غيرهما في دعوة الموردين الجدد، فيكون الموردون الذين ندعوهم تاليًا ممن يستطيعون تسعير طلبكم. '
           else 'وليس في قائمتنا حاليًا موردون آخرون في هذا المجال في ' || coalesce(v_em_ar, 'الإمارات')
                || '، ولذلك نعمل على استقطاب موردين جدد له. ' end
      || 'ويبقى طلبكم مفتوحًا، وسنُعلمكم فور وصول أول عرض سعر.'
      || E'\n\nيمكنكم متابعة طلبكم عبر بوابتكم:\n\n' || v_link
      || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
  else
    v_subj := 'An update on your request — ' || v_where;
    v_body := coalesce('Dear ' || v_name || ',', 'Dear Customer,') || E'\n\n'
      || case when v_unreachable
           then 'Your request for ' || v_where || ' has not yet reached a supplier who can quote it: none of the suppliers registered for it can take it on right now. '
           else 'It has been ' || v_hours || ' hours since your request for ' || v_where
                || ' was sent to the matching suppliers, and no quotation has arrived yet. ' end
      || case when v_pool > 0
           then 'We have therefore put your trade and area first in our supplier recruitment, so the next suppliers we invite are ones who can quote for your request. '
           else 'We have no further suppliers for this trade in ' || coalesce(v_em, 'the UAE')
                || ' on our list yet, so we are sourcing new ones for it. ' end
      || 'Your request stays open, and we will let you know as soon as the first quotation arrives.'
      || E'\n\nYou can follow your request in your portal:\n\n' || v_link;
  end if;
  return jsonb_build_object('lang', v_lang, 'subject', v_subj, 'body', v_body, 'link', v_link);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_stalled_inquiry_rescue(p_include_fixtures boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_hours numeric := public.fn_seat_clock_policy('stalled_inquiry_rescue_hours', 48);
  r record; rw record; v_codes text[]; v_pool int; v_rank int; v_key text; v_to text; v_why text; v_dedupe text;
  m jsonb; v jsonb; v_notice jsonb; v_enq jsonb;
  v_flagged int := 0; v_acted int := 0; v_real int := 0; v_told int := 0; v_no_pool int := 0; v_closed int := 0;
  v_refilled int := 0; v_quiet int := 0; v_not_told jsonb := '[]'::jsonb;
begin
  -- (a) a no-quote rescue ends when its request has a quote, or is no longer open (#1105's flag clears its own reason)
  update public.stalled_inquiry_rescue x
     set cleared_at = now(),
         cleared_why = case when exists (select 1 from public.quotes q where q.inquiry_id = x.inquiry_id
                                            and coalesce(q.status, '') not in ('withdrawn', 'cancelled', 'rejected'))
                            then 'quoted' else 'request closed' end
    from public.inquiries i
   where x.cleared_at is null and x.reason = 'no_quote_48h' and i.id = x.inquiry_id
     and (exists (select 1 from public.quotes q where q.inquiry_id = x.inquiry_id
                   and coalesce(q.status, '') not in ('withdrawn', 'cancelled', 'rejected'))
          or coalesce(i.status, '') in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost'));
  get diagnostics v_closed = row_count;

  -- (b) an open row that had nobody to invite is measured again: a lead may have been imported since
  for rw in select * from public.stalled_inquiry_rescue
             where cleared_at is null and acted_at is not null and uninvited_pool = 0 and cardinality(trades) > 0
               and (p_include_fixtures or not fixture) loop
    v_pool := public.fn_sales_engineer_rescue_pool(rw.trades, rw.emirate);
    if v_pool > 0 then
      update public.stalled_inquiry_rescue set uninvited_pool = v_pool, finding_key = null where inquiry_id = rw.inquiry_id;
      v_refilled := v_refilled + 1;
    end if;
  end loop;

  -- (c) the second way in: first matched v_hours ago or more (within 30 days), still open, no quote row at all, never
  --     rescued for this before. An open row of the other reason is already in the rescue.
  for r in
    select i.id, fm.first_sent, public.fn_seat_clock_customer_is_fixture(c) as fixture
      from public.inquiries i
      join public.customers c on c.id = i.customer_id
      join lateral (select min(mm.sent_at) as first_sent from public.inquiry_matches mm where mm.inquiry_id = i.id) fm on true
     where fm.first_sent is not null
       and now() >= fm.first_sent + make_interval(secs => (v_hours * 3600)::double precision)
       and fm.first_sent > now() - interval '30 days'
       and coalesce(i.status, '') not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
       and not exists (select 1 from public.quotes q where q.inquiry_id = i.id
                        and coalesce(q.status, '') not in ('withdrawn', 'cancelled', 'rejected'))
       and not exists (select 1 from public.stalled_inquiry_rescue x where x.inquiry_id = i.id
                        and (x.cleared_at is null or x.reason = 'no_quote_48h'))
       and (p_include_fixtures or not public.fn_seat_clock_customer_is_fixture(c))
     order by fm.first_sent
  loop
    insert into public.stalled_inquiry_rescue (inquiry_id, reason, detail, fixture, flagged_at, flagged_by, matched_at, stalled_hours)
    values (r.id, 'no_quote_48h', jsonb_build_object('first_sent', r.first_sent, 'hours', v_hours), r.fixture, now(),
            'sales_engineer.stalled_inquiry_rescue', r.first_sent, v_hours)
    on conflict (inquiry_id) do update
       set reason = excluded.reason, detail = excluded.detail, fixture = excluded.fixture, flagged_at = excluded.flagged_at,
           flagged_by = excluded.flagged_by, matched_at = excluded.matched_at, stalled_hours = excluded.stalled_hours,
           cleared_at = null, cleared_why = null, acted_at = null, customer_notice = null, enqueue_result = null,
           trades = null, uninvited_pool = null, plan_rank = null, finding_key = null;
    v_flagged := v_flagged + 1;
  end loop;

  -- (d) every open row not yet acted on, whichever way it came in: recruit its trade and area, tell the customer once
  for r in
    select x.inquiry_id as id, x.reason, x.fixture, i.category, i.trades, i.emirate, i.lang, c.email as cemail, c.full_name as cname
      from public.stalled_inquiry_rescue x
      join public.inquiries i on i.id = x.inquiry_id
      join public.customers c on c.id = i.customer_id
     where x.cleared_at is null and x.acted_at is null and (p_include_fixtures or not x.fixture)
     order by x.flagged_at
  loop
    v_codes := coalesce(public.fn_taxonomy_trades_for(case when coalesce(cardinality(r.trades), 0) > 0 then r.trades
                                                           else array[coalesce(r.category, '')] end), '{}'::text[]);
    v_pool := case when cardinality(v_codes) > 0 then public.fn_sales_engineer_rescue_pool(v_codes, r.emirate) else 0 end;
    select min(p.rank) into v_rank from public.marketing_gap_recruitment_plan p
     where p.trade = any(v_codes) and (p.emirate = 'UAE' or p.emirate = r.emirate);
    v_key := case when v_pool = 0 then 'stalled_inquiry_rescue:no_uninvited_leads:'
                  || coalesce(nullif(array_to_string(v_codes, '+'), ''), coalesce(nullif(r.category, ''), 'unknown'))
                  || ':' || coalesce(r.emirate, 'UAE') end;
    update public.stalled_inquiry_rescue
       set trades = v_codes, emirate = r.emirate, uninvited_pool = v_pool, plan_rank = v_rank, finding_key = v_key, acted_at = now()
     where inquiry_id = r.id;
    v_acted := v_acted + 1;
    if not r.fixture and v_pool > 0 then v_real := v_real + 1; end if;

    -- the customer, once, in the language of the request; a fixture only ever to a fixture address
    m := public.fn_sales_engineer_stalled_inquiry_notice(r.lang, jsonb_build_object('name', r.cname, 'category', r.category,
           'emirate', r.emirate, 'hours', v_hours, 'pool', v_pool, 'reason', r.reason));
    v_to := lower(btrim(coalesce(r.cemail, '')));
    v_dedupe := 'stalled_inquiry_rescue:' || r.id || ':' || r.reason;
    v_why := public.fn_seat_clock_refusal(r.fixture, v_to, 'inquiry_rescue_update');
    if v_why is null and public.fn_seat_clock_asked(v_dedupe) then v_why := 'already told'; end if;
    if v_why is null then
      v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
        'type', 'inquiry_rescue_update', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', v_to,
        'to_role', 'customer', 'inquiry_id', r.id, 'lang', m->>'lang', 'subject', m->>'subject', 'body', m->>'body',
        'dedupe_key', v_dedupe)));
      v_notice := jsonb_build_object('sent', coalesce(v->0->>'status', '') <> 'failed', 'lang', m->>'lang', 'delivery', v->0);
    else
      v_notice := jsonb_build_object('sent', false, 'lang', m->>'lang', 'reason', v_why);
    end if;
    if (v_notice->>'sent')::boolean then v_told := v_told + 1;
    else v_not_told := v_not_told || jsonb_build_array(jsonb_build_object('inquiry_id', r.id, 'reason', coalesce(v_notice->>'reason', v_notice#>>'{delivery,error}')));
    end if;
    update public.stalled_inquiry_rescue set customer_notice = v_notice where inquiry_id = r.id;

    -- nobody left to invite for this trade and area: marketing must find where they gather
    if v_pool = 0 then
      v_no_pool := v_no_pool + 1;
      perform public.fn_it_engineer_finding_upsert(v_key,
        left('A customer''s request is in the stalled-inquiry rescue and no uninvited supplier is left to invite for '
             || coalesce(nullif(array_to_string(v_codes, ', '), ''), coalesce(r.category, 'its trade')) || ' in '
             || coalesce(r.emirate, 'the UAE'), 300),
        'public.stalled_inquiry_rescue / fn_sales_engineer_stalled_inquiry_rescue', 'customer_facing', 1,
        jsonb_build_object('inquiry_id', r.id, 'reason', r.reason, 'trades', to_jsonb(v_codes), 'emirate', r.emirate,
                           'owner_seat', 'marketing', 'duty', 'sales_engineer.stalled_inquiry_rescue', 'demo', r.fixture),
        '{}'::text[], array['a directory, association, chamber or trade fair where suppliers of this trade in this area gather'],
        'sales_engineer');
    end if;
  end loop;

  -- (e) the queue is offered the rescued trades now, through the one door that holds every brake
  if v_real > 0 then
    begin
      v_enq := jsonb_build_object('queued', public.enqueue_supplier_invites(), 'at', now());
    exception when others then
      v_enq := jsonb_build_object('error', left(sqlerrm, 300), 'at', now());
    end;
    update public.stalled_inquiry_rescue set enqueue_result = v_enq where acted_at = now() and not fixture and uninvited_pool > 0;
  end if;

  -- (f) a finding whose trade and area now has somebody to invite, or no open row, is closed
  for rw in select f.issue_key from public.it_engineer_finding f
             where f.closed_at is null and f.issue_key like 'stalled_inquiry_rescue:no_uninvited_leads:%'
               and not exists (select 1 from public.stalled_inquiry_rescue y where y.cleared_at is null and y.finding_key = f.issue_key) loop
    perform public.fn_it_engineer_finding_close(rw.issue_key, 'closed by fn_sales_engineer_stalled_inquiry_rescue: the trade and area have an uninvited lead again, or the rescue ended');
    v_quiet := v_quiet + 1;
  end loop;

  return jsonb_build_object('ok', true, 'hours', v_hours, 'flagged_no_quote', v_flagged, 'acted', v_acted,
    'acted_real_with_pool', v_real, 'customers_told', v_told, 'not_told', v_not_told, 'no_uninvited_leads', v_no_pool,
    'closed', v_closed, 'refilled', v_refilled, 'findings_closed', v_quiet, 'enqueue', v_enq,
    'open', (select count(*) from public.stalled_inquiry_rescue where cleared_at is null and (p_include_fixtures or not fixture)));
end
$function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_supplier_documents_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_reconcile json; v_final json; v_rechecked int := 0; v_closed int := 0; v_kept int := 0; r record; v jsonb;
  v_missing text[]; v_items_en text; v_items_ar text; v_ar boolean; v_to text; v_opened text; v_out jsonb;
  v_label jsonb := jsonb_build_object(
    'reg_name',        jsonb_build_array('company name', 'اسم الشركة'),
    'reg_mobile',      jsonb_build_array('a verified UAE mobile number', 'رقم جوال إماراتي موثَّق'),
    'reg_email',       jsonb_build_array('a verified e-mail address', 'بريد إلكتروني موثَّق'),
    'reg_licence',     jsonb_build_array('trade licence', 'الرخصة التجارية'),
    'reg_profile',     jsonb_build_array('company profile', 'الملف التعريفي للشركة'),
    'reg_terms',       jsonb_build_array('the signed supplier terms', 'الموافقة الموقّعة على شروط المورّد'),
    'licence_expired', jsonb_build_array('a trade licence that is in date', 'رخصة تجارية سارية المفعول'));
begin
  v_reconcile := public.fn_reconcile_doc_blocks(0);
  v_final := public.fn_doc_final_notice(7);

  for r in select l.id from public.leads l
            where l.approval_status = 'approved' and cardinality(public.fn_supplier_mandatory_six(l)) > 0 loop
    perform public.fn_sales_engineer_verifies_supplier(r.id, 'daily_recheck');
    v_rechecked := v_rechecked + 1;
  end loop;

  for r in select l.id, l.company_name, l.claimed_by, l.email, l.exception_opened_at
             from public.leads l
            where l.approval_status = 'action_required' and l.exception_closed_at is null
              and l.exception_due_at <= now()
            order by l.id loop
    v := public.fn_sales_engineer_verifies_supplier(r.id, 'deadline');
    if v->>'approval_status' is distinct from 'action_required' then v_kept := v_kept + 1; continue; end if;

    v_missing := array(select jsonb_array_elements_text(v->'missing'));
    if cardinality(v_missing) = 0 then v_missing := array['licence_expired']; end if;
    select string_agg(v_label->k->>0, ', ' order by o), string_agg(v_label->k->>1, '، ' order by o)
      into v_items_en, v_items_ar from unnest(v_missing) with ordinality u(k, o);

    -- trg_leads_exception_invariant closes the window with outcome closed_rejected.
    update public.leads
       set approval_status = 'rejected', verified = false, approval_decided_by = 'sales_engineer',
           rejection_reason = 'registration incomplete after ' || public.fn_supplier_exception_days() || ' days: ' || array_to_string(v_missing, ', ')
     where id = r.id;

    v_ar := false;   -- suppliers are always written in English (founder, 28 Sep 2026)
    v_to := lower(nullif(btrim(coalesce(r.claimed_by, r.email)), ''));
    v_opened := to_char(r.exception_opened_at at time zone 'Asia/Dubai', 'DD Mon YYYY');
    if v_to is not null then
      perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
        'type', 'registration_closed', 'requested_by', 'sales_engineer', 'channel', 'email',
        'to_email', v_to, 'to_role', 'supplier', 'lead_id', r.id, 'lang', case when v_ar then 'ar' else 'en' end,
        'dedupe_key', 'registration_closed:' || r.id || ':' || extract(epoch from r.exception_opened_at)::bigint,
        'subject', case when v_ar then 'إغلاق طلب تسجيلكم كمورّد في QuotesDone'
                        else 'Your QuotesDone supplier registration has closed' end,
        'body', case when v_ar then
            'السادة/ ' || coalesce(r.company_name, 'المورّد') || ' المحترمين،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
            || 'فُتح طلب تسجيلكم كمورّد بتاريخ ' || v_opened || '، ولا يزال ينقصه: ' || v_items_ar || '. '
            || 'أبلغناكم أننا سنبقي الطلب مفتوحًا ' || public.fn_ar_days(public.fn_supplier_exception_days()) || '، وقد انقضت هذه المدة، لذلك أُغلق طلب التسجيل.' || chr(10) || chr(10)
            || 'يمكنكم التسجيل من جديد في أي وقت عبر https://quotesdone.com/portal، ويُفعَّل حسابكم فور اكتمال البنود الستة: '
            || 'اسم الشركة، ورقم جوال موثَّق، وبريد إلكتروني موثَّق، والرخصة التجارية، والملف التعريفي للشركة، والموافقة الموقّعة على شروط المورّد.' || chr(10) || chr(10)
            || 'وإن رأيتم أن في ذلك خطأً، فيسعدنا أن تردّوا على هذه الرسالة.' || chr(10) || chr(10) || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
          else
            'Dear ' || coalesce(r.company_name, 'supplier') || ',' || chr(10) || chr(10)
            || 'Your supplier registration was opened on ' || v_opened || ' and still needs: ' || v_items_en || '. '
            || 'We said we would keep it open for ' || public.fn_supplier_exception_days() || ' days; that time has passed, so the registration is now closed.' || chr(10) || chr(10)
            || 'You are welcome to register again at any time at https://quotesdone.com/portal. Your account activates as soon as the six required items are complete: '
            || 'company name, a verified mobile number, a verified e-mail address, your trade licence, your company profile and the signed supplier terms.' || chr(10) || chr(10)
            || 'If you believe this is wrong, reply to this e-mail.' end)));
    end if;

    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
    values ('sales_engineer', 'supplier_verification', 'auto_done', 'low',
            'Registration closed after the ' || public.fn_supplier_exception_days() || '-day window — ' || left(coalesce(r.company_name, 'supplier #' || r.id), 120),
            'No action required. The supplier was told in their language what was missing and that they may register again.',
            jsonb_build_object('supplier_id', r.id, 'decision', 'rejected', 'missing', v_missing, 'window_opened_at', r.exception_opened_at,
                               'notice', case when v_to is null then 'no e-mail on file' else 'queued through customer_support' end,
                               'source', 'fn_sales_engineer_supplier_documents_tick'),
            'leads', r.id::text);
    v_closed := v_closed + 1;
  end loop;

  v_out := jsonb_build_object('reconcile', v_reconcile, 'final_notice', v_final, 'approved_rechecked', v_rechecked,
                              'registrations_closed', v_closed, 'completed_at_deadline', v_kept);
  perform public.fn_it_duty_ran('supplier_docs', v_out);
  return v_out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_supplier_onboarding()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_nudged int := 0; v_to text; v_stages jsonb; v_inv jsonb;
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';   -- fixture run: ONLY demo rows
begin
  -- THE STAGE, from what the rows say happened (never from a status someone typed).
  with m as (
    select im.supplier_id, min(im.sent_at) as first_match_at,
           count(*) filter (where i.status not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
                              and not exists (select 1 from public.quotes q where q.inquiry_id = im.inquiry_id and q.supplier_id = im.supplier_id)) as open_matches
      from public.inquiry_matches im join public.inquiries i on i.id = im.inquiry_id
     group by im.supplier_id
  ), q as (
    select supplier_id, min(created_at) as first_quote_at from public.quotes group by supplier_id
  ), s as (
    select l.id,
           case when coalesce(l.banned, false) or coalesce(l.permanently_closed, false) or l.approval_status = 'rejected' then 'closed'
                when q.first_quote_at is not null then 'quoting'
                when l.approval_status = 'approved' and m.first_match_at is not null then 'matched'
                when l.approval_status = 'approved' then 'approved'
                when l.approval_status = 'action_required' then 'action_required'
                when l.registration_submitted_at is not null or coalesce(l.claimed, false) then 'registering'
                when l.invite_clicked_at is not null then 'clicked'
                else 'invited' end as stage,
           m.first_match_at, q.first_quote_at, coalesce(m.open_matches, 0) as open_matches
      from public.leads l
      left join m on m.supplier_id = l.id
      left join q on q.supplier_id = l.id
     where (l.invited_at is not null or coalesce(l.claimed, false) or l.approval_status is not null) and l.is_demo = v_fx
  )
  insert into public.supplier_onboarding as o (lead_id, stage, first_match_at, first_quote_at, open_matches)
  select id, stage, first_match_at, first_quote_at, open_matches from s
  on conflict (lead_id) do update set
    stage_since    = case when o.stage is distinct from excluded.stage then now() else o.stage_since end,
    stage          = excluded.stage,
    first_match_at = excluded.first_match_at, first_quote_at = excluded.first_quote_at,
    open_matches   = excluded.open_matches, updated_at = now();

  -- THE 'invited' STAGE (#1007): day 3 / 7 / 14 after the invitation the OUTBOX delivered (see the header).
  v_inv := public.fn_sales_engineer_nudges_invited_suppliers();

  -- THE NUDGE. Before approval the invitation reminders and the 14-day window already act; from approval to the
  -- first quote nothing did. Matched, requests open for him, not quoted 3 days after the first match: told, at
  -- most twice, a week apart, in his language, through customer_support.
  for r in
    select o.lead_id, o.open_matches, l.company_name, lower(nullif(btrim(coalesce(l.claimed_by, l.email)), '')) as to_email
      from public.supplier_onboarding o join public.leads l on l.id = o.lead_id and l.is_demo = v_fx
     where o.stage = 'matched' and o.open_matches > 0 and o.first_match_at < now() - interval '3 days'
       and o.nudges < 2 and (o.last_nudge_at is null or o.last_nudge_at < now() - interval '7 days')
     order by o.first_match_at
     limit 50
  loop
    continue when r.to_email is null;
    -- ENGLISH ONLY (#1007, review of 29 Sep 2026): #1065's body kept an Arabic branch behind a flag fixed to English; it is
    -- removed, not switched off. A matched supplier is registered, so the link is the English portal (no claim token).
    perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'supplier_first_quote_nudge', 'requested_by', 'sales_engineer', 'channel', 'email',
      'to_email', r.to_email, 'to_role', 'supplier', 'lead_id', r.lead_id, 'lang', 'en',
      'dedupe_key', 'first_quote_nudge:' || r.lead_id || ':' || (select nudges from public.supplier_onboarding where lead_id = r.lead_id),
      'subject', 'Customer requests are waiting for your quotation',
      -- #1070's greeting guard (#1007): an Arabic-script company name is not written into an English letter
      'body', 'Dear ' || coalesce(nullif(btrim(case when r.company_name ~ '[\u0600-\u06FF]' then '' else r.company_name end), ''), 'supplier') || ',' || chr(10) || chr(10)
          || r.open_matches || ' customer request(s) matched to your trade are open and have no quotation from you yet. '
          || 'You can read them and quote in your supplier portal: '
          || coalesce((select nullif(btrim(value), '') from public.app_secrets where key = 'public_site_url'), 'https://quotesdone.com')
          || '/en/portal' || chr(10) || chr(10)
          || 'QuotesDone')));
    update public.supplier_onboarding set nudges = nudges + 1, last_nudge_at = now() where lead_id = r.lead_id;
    v_nudged := v_nudged + 1;
  end loop;

  select coalesce(jsonb_object_agg(stage, n), '{}'::jsonb) into v_stages
    from (select stage, count(*) n from public.supplier_onboarding group by stage) x;
  return jsonb_build_object('stages', v_stages, 'nudged', v_nudged, 'invite_nudges', v_inv);
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_supplier_outreach_tick(p_force boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_now_dxb timestamp := now() at time zone 'Asia/Dubai';
  v_go boolean; v_weekend boolean; v_invited int; r record; s jsonb; v_cap int;
  v_due int := 0; v_sent int := 0; v_failed jsonb := '[]'::jsonb; v_clock jsonb; v_out jsonb; v_why text;
  v_gate text; v_daily_done boolean; v_batch_done boolean; v_batch_why text; v_batch_wait boolean := false;
begin
  select exists (select 1 from public.agent_runs a
                  where a.agent = 'sales_engineer' and a.counts->>'job' = 'supplier_outreach'
                    and a.started_at > now() - interval '1 day'
                    and (a.started_at at time zone 'Asia/Dubai')::date = v_now_dxb::date),
         exists (select 1 from public.agent_runs a
                  where a.agent = 'sales_engineer'
                    and ((a.counts->>'job' = 'supplier_outreach' and coalesce(a.counts->>'batch_waiting', 'false') <> 'true')
                         or a.counts->>'job' = 'supplier_outreach_batch')
                    and a.started_at > now() - interval '1 day'
                    and (a.started_at at time zone 'Asia/Dubai')::date = v_now_dxb::date)
    into v_daily_done, v_batch_done;
  if not p_force then
    if extract(hour from v_now_dxb) < 9 then return jsonb_build_object('due', false, 'reason', 'before 09:00 Dubai'); end if;
    if v_daily_done and v_batch_done then
      return jsonb_build_object('due', false, 'reason', 'already ran this Dubai day');
    end if;
  end if;

  v_go := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
          and public.fn_supplier_outreach_golive();
  v_weekend := extract(isodow from v_now_dxb) in (6, 7);
  v_why := case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive is false'
                when not v_go then 'invite_enabled is false'
                when v_weekend then 'it is the UAE weekend' end;

  -- 1. THE BATCH, behind the PLACEMENT GATE (24 Sep 2026, it_engineer). On an open day it goes only after that
  --    morning's seed landed in the Inbox of both seed mailboxes; while the check can still finish it waits (the
  --    next beat asks again); any other answer holds it (fail closed). enqueue_supplier_invites asks the same gate.
  if p_force or not v_batch_done then
    v_batch_why := v_why;
    if v_why is null then
      v_gate := public.fn_invite_placement_gate(v_now_dxb::date);
      if v_gate = 'wait' and not p_force then
        v_batch_wait := true;
      elsif v_gate <> 'pass' then
        v_batch_why := 'the morning inbox placement check did not clear (' || v_gate || ')';
      end if;
    end if;
    if not v_batch_wait then
      -- THE WARM-UP (22 Sep 2026). fn_invite_ramp sets today's invite_daily_cap from the last 48 h of bounces and
      -- complaints. Open days only: a held day sends nothing, so it must not move the cap.
      if v_batch_why is null then v_cap := public.fn_invite_ramp(); end if;
      -- enqueue_supplier_invites holds itself (gates, weekend, holiday, bounce brake, cap, placement).
      v_invited := public.enqueue_supplier_invites(null);
    end if;
  end if;

  -- A later beat of the same day: the daily work is done, only the batch was owed.
  if v_daily_done and not p_force then
    if v_batch_wait then
      return jsonb_build_object('due', false, 'reason', 'the batch waits for the morning inbox placement check');
    end if;
    v_out := jsonb_build_object('job', 'supplier_outreach_batch', 'dubai_day', v_now_dxb::date, 'held', v_batch_why is not null,
      'held_because', v_batch_why, 'placement_gate', v_gate, 'invites', jsonb_build_object('queued', v_invited, 'cap', v_cap));
    insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
    values ('sales_engineer', 'ok', now(), now(), v_out,
            case when v_batch_why is not null
                 then 'Supplier invitation batch HELD (' || v_batch_why || '): ' || coalesce(v_invited, 0) || ' queued.'
                 else 'Supplier invitation batch: ' || coalesce(v_invited, 0) || ' invitation(s) queued at a cap of ' || coalesce(v_cap::text, '?') || '.' end);
    return v_out;
  end if;

  -- 2. Reminders: always counted; written only on an open weekday (the campaign gates, not the placement gate).
  for r in select * from public.fn_supplier_registration_reminders_due() loop
    v_due := v_due + 1;
    if v_why is not null then continue; end if;
    s := public.fn_sales_engineer_sends_registration_reminder(r.lead_id, r.stage, r.step, r.last_activity);
    if coalesce((s->>'ok')::boolean, false) then v_sent := v_sent + 1;
    else v_failed := v_failed || jsonb_build_array(jsonb_build_object('lead_id', r.lead_id, 'reason', s->>'reason'));
    end if;
  end loop;

  -- 3. The 24-hour clock: internal, so not held by the campaign gates.
  v_clock := public.fn_sales_engineer_raises_undecided_submissions(false);

  v_out := jsonb_build_object('job', 'supplier_outreach', 'dubai_day', v_now_dxb::date, 'held', v_why is not null, 'held_because', v_why,
    'placement_gate', v_gate, 'batch_waiting', v_batch_wait, 'batch_held_because', v_batch_why,
    'invites', jsonb_build_object('queued', coalesce(v_invited, 0), 'cap', v_cap),
    'reminders', jsonb_build_object('due', v_due, 'sent', v_sent, 'failed', v_failed),
    'submissions', v_clock);
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('sales_engineer', case when jsonb_array_length(v_failed) > 0 then 'warn' else 'ok' end, now(), now(), v_out,
          case when v_why is not null
               then 'Supplier outreach HELD (' || v_why || '): ' || coalesce(v_invited, 0) || ' invitation(s) queued, ' || v_due
                    || ' reminder(s) due and none written; ' || coalesce(v_clock->>'raised_to_ceo', '0') || ' undecided submission(s) raised to the CEO.'
               else 'Supplier outreach: '
                    || case when v_batch_wait then 'the invitation batch waits for the morning inbox placement check'
                            when v_batch_why is not null then 'the invitation batch was HELD (' || v_batch_why || ')'
                            else coalesce(v_invited, 0) || ' invitation(s) queued at a cap of ' || coalesce(v_cap::text, '?') end
                    || ', ' || v_sent || ' of ' || v_due
                    || ' reminder(s) sent; ' || coalesce(v_clock->>'raised_to_ceo', '0') || ' undecided submission(s) raised to the CEO.' end);
  return v_out;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_supplier_performance()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_refreshed int; v_scored int; v_null int;
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';   -- fixture run: ONLY demo rows
begin
  v_refreshed := public.fn_supplier_score_refresh();
  -- WEIGHTED OVER WHAT WAS MEASURED: reliability 0.5, the customers' rating 0.3, disputes 0.2 (only once a customer
  -- has reviewed him). A part that does not exist is left out of both sides of the average, never counted as zero.
  -- Only a supplier whose lead still exists is scored: supplier_performance keys on leads(id).
  with parts as (
    select s.lead_id,
           case when s.reliability is not null then least(1, greatest(0, s.reliability / 100.0)) end as rel,
           case when s.quality_rating is not null then least(1, greatest(0, s.quality_rating / 100.0)) end as qual,
           case when coalesce(r.review_count, 0) > 0 then 1 - least(1, greatest(0, coalesce(r.dispute_rate_pct, 0) / 100.0)) end as disp
      from public.supplier_score s
      join public.leads l on l.id = s.lead_id and l.is_demo = v_fx
      left join public.supplier_reputation r on r.supplier_id = s.lead_id
     where s.reliability is not null or s.quality_rating is not null or coalesce(r.review_count, 0) > 0
  )
  insert into public.supplier_performance as p (lead_id, score, components, computed_at)
  select lead_id,
         round((coalesce(0.5 * rel, 0) + coalesce(0.3 * qual, 0) + coalesce(0.2 * disp, 0))
               / nullif((case when rel is not null then 0.5 else 0 end) + (case when qual is not null then 0.3 else 0 end)
                        + (case when disp is not null then 0.2 else 0 end), 0), 3),
         jsonb_build_object('reliability', rel, 'rating', qual, 'disputes', disp), now()
    from parts
  on conflict (lead_id) do update set score = excluded.score, components = excluded.components, computed_at = now();
  get diagnostics v_scored = row_count;
  -- a supplier who lost every measurement is unmeasured again, not scored on stale numbers
  delete from public.supplier_performance p where p.computed_at < now() - interval '1 minute'
     and public.fn_supplier_is_demo(p.lead_id) = v_fx;   -- a fixture run never drops a real supplier's score
  get diagnostics v_null = row_count;
  return jsonb_build_object('score_rows_refreshed', v_refreshed, 'scored', v_scored, 'dropped_unmeasured', v_null);
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_supplier_scorecard_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_month date := (date_trunc('month', (now() at time zone 'Asia/Dubai')) - interval '1 month')::date;
  r record; v_card jsonb; m jsonb; v_ok jsonb; v jsonb; v_sent int := 0; v_held int := 0;
begin
  for r in select l.id, l.company_name, lower(btrim(l.claimed_by)) as mail from public.leads l
            where l.approval_status = 'approved' and nullif(btrim(l.claimed_by), '') is not null
              and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false)
              and (coalesce(l.is_demo, false) or public.fn_is_demo_email(l.claimed_by)) = v_fx
              and not exists (select 1 from public.supplier_scorecard s where s.lead_id = l.id and s.month = v_month)
            order by l.id limit 500 loop
    v_card := public.fn_supplier_scorecard(r.id, v_month);
    m := public.fn_supplier_scorecard_text(v_card, r.company_name);
    v_ok := public.fn_email_sendable(r.mail);
    if not coalesce((v_ok->>'ok')::boolean, false) then
      insert into public.supplier_scorecard (lead_id, month, card, to_email, outcome)
      values (r.id, v_month, v_card, r.mail, 'not_sendable: ' || (v_ok->>'reason'));
      v_held := v_held + 1;
      continue;
    end if;
    v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'supplier_scorecard', 'requested_by', 'sales_engineer', 'channel', 'email',
      'to_email', r.mail, 'to_role', 'supplier', 'lead_id', r.id, 'lang', 'en',
      'dedupe_key', 'supplier_scorecard:' || r.id || ':' || to_char(v_month, 'YYYY-MM'),
      'subject', m->>'subject', 'body', m->>'body')));
    insert into public.supplier_scorecard (lead_id, month, card, to_email, outcome, handoff_id)
    values (r.id, v_month, v_card, r.mail, 'queued', (v->0->>'handoff_id')::bigint);
    v_sent := v_sent + 1;
  end loop;
  return jsonb_build_object('month', to_char(v_month, 'YYYY-MM'), 'sent', v_sent, 'not_sendable', v_held);
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_supply_gap(p_reason_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_target int := coalesce((select category_open_min_suppliers from public.pricing_config order by id limit 1), 10);
  v_rule int; v_closed int; v_reopened int; v_settled int; v_nobody int; v_held_settled int; v_forecast_settled int;
  v_emirates text[] := array['Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah'];
begin
  with sup as materialized (   -- every matchable supplier with his trades and the emirates he states (none stated = UAE-wide)
    select sc.supplier_id, sc.trades,
           array(select distinct lower(btrim(e)) from unnest(coalesce(sc.coverage_emirates, '{}'::text[]) || coalesce(l.service_emirates, '{}'::text[])) e
                  where nullif(btrim(e), '') is not null) as stated
      from public.supplier_capabilities sc join public.leads l on l.id = sc.supplier_id
     where sc.confirmed_at is not null
       and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
  ), inq as materialized (
    select i.id, i.emirate, i.trades, i.created_at,
           (i.created_at > now() - interval '30 days' and i.status not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
            and (select count(*) from public.quotes q where q.inquiry_id = i.id) < 3) as short
      from public.inquiries i left join public.customers c on c.id = i.customer_id
     where i.created_at > now() - interval '90 days'
       -- DEMO IS NEVER DEMAND: a fixture customer's request never starts real recruitment (the predicate the
       -- stalled-inquiry rescue already uses)
       and not coalesce(public.fn_seat_clock_customer_is_fixture(c), false)
  ), pool as materialized (
    select t, l.emirate, count(*) as n from public.leads l, unnest(l.invite_trades) t
     where l.invite_status is null and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false)
       and coalesce(l.is_demo, false) = false
     group by t, l.emirate
  ), keys as (
    select tt.code as trade, 'UAE'::text as emirate from public.taxonomy_trade tt where tt.active
    union
    select distinct t, i.emirate from inq i, unnest(i.trades) t
     where i.emirate = any(v_emirates) and t in (select code from public.taxonomy_trade where active)
  ), m as (
    select k.trade, k.emirate,
           (select count(*) from sup s where k.trade = any(s.trades)
             and (k.emirate = 'UAE' or cardinality(s.stated) = 0 or lower(k.emirate) = any(s.stated)))::int as matchable,
           (select count(*) from inq i where k.trade = any(i.trades) and (k.emirate = 'UAE' or i.emirate = k.emirate))::int as demand,
           (select count(*) from inq i where i.short and k.trade = any(i.trades) and (k.emirate = 'UAE' or i.emirate = k.emirate))::int as short,
           (select coalesce(sum(p.n), 0) from pool p where p.t = k.trade and (k.emirate = 'UAE' or p.emirate = k.emirate))::int as pool
      from keys k
  )
  insert into public.supply_gap as sg (trade, emirate, matchable, target, demand_90d, short_open, uninvited_pool, measured_at)
  select trade, emirate, matchable, v_target, demand, short, pool, now() from m
  on conflict (trade, emirate) do update set matchable = excluded.matchable, target = excluded.target,
    demand_90d = excluded.demand_90d, short_open = excluded.short_open, uninvited_pool = excluded.uninvited_pool, measured_at = now();

  -- An area row that no counted request names any more (its only requests were demo) was not re-measured above:
  -- it has no demand now, not the demand it had last run.
  update public.supply_gap set demand_90d = 0, short_open = 0, measured_at = now()
   where measured_at < now() and (demand_90d <> 0 or short_open <> 0);

  update public.supply_gap set status = 'closed', closed_at = now() where status <> 'closed' and matchable >= target;
  get diagnostics v_closed = row_count;
  update public.supply_gap set status = 'open', opened_at = now(), closed_at = null, decided_by = null, decided_at = null, held_id = null
   where (status = 'closed' and matchable < target) or (status = 'deferred' and decided_at < now() - interval '30 days');
  get diagnostics v_reopened = row_count;

  -- A RULE WHOSE CUSTOMER IS GONE IS UNDONE: a gap recruited for because a customer was waiting, where no counted
  -- (non-demo) request remains, goes back to open and is decided again below like any gap nobody waits on.
  update public.supply_gap set status = 'open', decided_by = null, decided_at = null, held_id = null
   where status = 'recruit' and decided_by = 'rule:customer_waiting' and short_open = 0 and demand_90d = 0;
  get diagnostics v_settled = row_count;

  -- A FORECAST THAT NO LONGER SHOWS DEMAND IS UNDONE (review of #1182): a gap fn_demand_forecast_tick recruited for
  -- goes back to open once no forecast from the last two days shows demand there (or the forecast stopped running),
  -- and is decided again below like any gap nobody waits on.
  update public.supply_gap g set status = 'open', decided_by = null, decided_at = null, held_id = null
   where g.status = 'recruit' and g.decided_by = 'rule:forecast_demand'
     and not exists (select 1 from public.demand_forecast f
                      where f.trade = g.trade and f.emirate = g.emirate and f.forecast_90d >= 1
                        and f.run_on > (now() at time zone 'Asia/Dubai')::date - 2);
  get diagnostics v_forecast_settled = row_count;

  -- A CUSTOMER IS ALREADY WAITING: recruited for at once, by rule. No judgement to make, so nothing waits on one.
  update public.supply_gap set status = 'recruit', decided_by = 'rule:customer_waiting', decided_at = now()
   where status in ('open', 'deciding', 'deferred') and (short_open > 0 or demand_90d > 0);
  get diagnostics v_rule = row_count;

  -- NO UNINVITED LEAD LEFT: nobody for marketing to recruit, so "defer" is the only answer - by rule, at no cost.
  update public.supply_gap set status = 'deferred', decided_by = 'rule:no_uninvited_leads', decided_at = now()
   where status = 'open' and uninvited_pool = 0;

  -- NOBODY IS WAITING: deferred by rule, at no cost (R8). A decision already held for the model is settled the same
  -- way, and the question it waited on is expired with the reason.
  update public.reasoning_held_question h
     set status = 'expired', result = coalesce(h.result, '{}'::jsonb) || jsonb_build_object('expired_by', 'fn_sales_engineer_supply_gap',
           'why', 'decided by code: nobody is waiting on this trade and area (rule:nobody_waiting)')
    from public.supply_gap s
   where s.status = 'deciding' and s.short_open = 0 and s.demand_90d = 0 and h.id = s.held_id and h.status = 'held';
  get diagnostics v_held_settled = row_count;
  update public.supply_gap set status = 'deferred', decided_by = 'rule:nobody_waiting', decided_at = now(), held_id = null
   where status in ('open', 'deciding') and short_open = 0 and demand_90d = 0;
  get diagnostics v_nobody = row_count;

  return jsonb_build_object('target', v_target, 'closed', v_closed, 'reopened', v_reopened, 'recruit_by_rule', v_rule, 'customer_rule_undone', v_settled, 'forecast_rule_undone', v_forecast_settled,
    'deferred_nobody_waiting', v_nobody, 'held_questions_settled', v_held_settled, 'filed_for_reasoning', 0,
    'by_status', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from public.supply_gap group by status) x));
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_supply_gap_recruitment()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_day_start timestamptz := date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai';
  v_budget int; v_reopened int; v_brief jsonb;
begin
  -- BEFORE LAUNCH NOBODY CAN BE WAITING (customers from Jan 2027), so 'nobody_waiting' would defer every gap forever.
  -- A senior sales engineer builds supply ahead of demand: up to 10 a Dubai day, largest uninvited pool first.
  v_budget := greatest(0, 10 - (select count(*) from public.supply_gap where decided_by = 'sales_engineer:recruitment_brief' and decided_at >= v_day_start)::int);
  update public.supply_gap g set status = 'open', decided_by = 'rule:pre_launch_build', decided_at = now(), held_id = null
   where (g.trade, g.emirate) in (select trade, emirate from public.supply_gap
                                   where status = 'deferred' and decided_by = 'rule:nobody_waiting' and uninvited_pool > 0 and matchable < target
                                   order by uninvited_pool desc, target - matchable desc, trade, emirate limit v_budget);
  get diagnostics v_reopened = row_count;
  v_brief := public.fn_sales_engineer_supply_gap_to_recruitment_brief(10);
  return jsonb_build_object('reopened_pre_launch', v_reopened, 'brief', v_brief,
    'briefs_open', (select count(*) from public.supply_recruitment_brief where status = 'open'),
    'briefs_unread_3d', (select count(*) from public.supply_recruitment_brief where status = 'open' and read_by_marketing_at is null and listed_at < now() - interval '3 days'),
    'gaps_by_status', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from public.supply_gap group by status) x));
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_supply_gap_to_recruitment_brief(p_daily_new integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_listed int; v_moved int; v_closed int; v_budget int;
  v_day_start timestamptz := date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai';
begin
  -- Close first: a gap at target is not recruited for.
  update public.supply_gap set status = 'closed', closed_at = now() where status <> 'closed' and matchable >= target;
  update public.supply_recruitment_brief b set status = 'closed', closed_at = now(), updated_at = now()
    from public.supply_gap g
   where b.status = 'open' and g.trade = b.trade and g.emirate = b.emirate and g.status = 'closed';
  get diagnostics v_closed = row_count;

  -- Today's promotions so far: a second run on the same day spends what is left, never a fresh 10.
  v_budget := greatest(0, coalesce(p_daily_new, 10) - (select count(*) from public.supply_gap
                where decided_by = 'sales_engineer:recruitment_brief' and decided_at >= v_day_start)::int);

  with pick as (
    select g.trade, g.emirate from public.supply_gap g where g.status = 'recruit' and g.matchable < g.target
    union all
    (select g.trade, g.emirate from public.supply_gap g where g.status = 'open' and g.matchable < g.target
      order by (g.short_open > 0) desc, (g.demand_90d > 0) desc, g.uninvited_pool desc, g.target - g.matchable desc, g.trade, g.emirate
      limit v_budget)
  ), gl as (
    select g.*,
           (select count(*) from public.leads l
             where g.trade = any(l.invite_trades) and l.invited_at is not null
               and coalesce(l.is_demo, false) = (g.trade like 'zz_demo%')
               and (g.emirate = 'UAE' or l.emirate = g.emirate))::int as invited,
           (select count(*) from public.leads l
             where g.trade = any(l.invite_trades) and (l.registration_submitted_at is not null or coalesce(l.claimed, false))
               and coalesce(l.is_demo, false) = (g.trade like 'zz_demo%')
               and (g.emirate = 'UAE' or l.emirate = g.emirate))::int as registered
      from public.supply_gap g join pick using (trade, emirate)
  )
  insert into public.supply_recruitment_brief as b (trade, emirate, matchable, target, shortfall, invited, registered,
         demand_90d, short_open, uninvited_pool, priority, suggested_sourcing)
  select trade, emirate, matchable, target, target - matchable, invited, registered, demand_90d, short_open, uninvited_pool,
         case when short_open > 0 then 'P1' when demand_90d > 0 then 'P2' else 'P3' end,
         -- ponytail: 20 invitations per registration is a planning ratio; swap in the measured funnel rate once it has volume.
         case when uninvited_pool >= (target - matchable) * 20 then 'invite from the existing lead pool'
              when uninvited_pool > 0 then 'invite the lead pool, then source new leads (trade directories, chambers of commerce, LinkedIn)'
              else 'source new leads: trade directories, chambers of commerce, LinkedIn, trade exhibitions' end
    from gl
  on conflict (trade, emirate) do update set matchable = excluded.matchable, target = excluded.target, shortfall = excluded.shortfall,
    invited = excluded.invited, registered = excluded.registered, demand_90d = excluded.demand_90d, short_open = excluded.short_open,
    uninvited_pool = excluded.uninvited_pool, priority = excluded.priority, suggested_sourcing = excluded.suggested_sourcing,
    status = 'open', closed_at = null, updated_at = now();
  get diagnostics v_listed = row_count;

  -- Only brief rows this call wrote (updated_at = now(), the transaction start) move a gap, so an
  -- 'open' gap outside today's pick keeps waiting. A promotion is stamped with this routine's name
  -- and time, which is exactly what the budget above counts.
  update public.supply_gap g set status = 'recruit', brief_id = b.id,
         decided_by = case when g.status = 'open' then 'sales_engineer:recruitment_brief'
                           else coalesce(g.decided_by, 'sales_engineer:recruitment_brief') end,
         decided_at = case when g.status = 'open' then now() else coalesce(g.decided_at, now()) end
    from public.supply_recruitment_brief b
   where b.trade = g.trade and b.emirate = g.emirate and b.status = 'open' and b.updated_at = now()
     and g.status in ('open', 'recruit')
     and (g.status <> 'recruit' or g.brief_id is distinct from b.id);
  get diagnostics v_moved = row_count;

  return jsonb_build_object('listed', v_listed, 'moved_to_recruit', v_moved, 'closed', v_closed, 'promotion_budget', v_budget);
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_takes_invite_reply(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  -- The sales engineer owns the company page. The handoff stays in its queue, waiting on that work, with the lead
  -- and the supplier's own words in front of it.
  return jsonb_build_object(
    'waiting', 'sales_engineer: set up the company page for lead #' || coalesce(a.detail->>'lead_id', '?') || ' from the trades in the reply',
    'lead_id', a.detail->'lead_id', 'inbound_message_id', a.detail->'inbound_message_id', 'reply_text', a.detail->'reply_text');
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_tells_customer_invoice_ready()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.kind <> 'handoff' or new.detail->>'type' is distinct from 'invoice.issued' then return new; end if;
  -- A failed answer is recorded on the row and in the stream; it never rolls back the filed invoice.
  begin
    perform public.fn_seat_handoff_act(new.id);
  exception when others then
    update public.agent_actions
       set status = 'failed', decided_at = now(),
           detail = detail || jsonb_build_object('error', left(sqlerrm, 500))
     where id = new.id;
    perform public.fn_seat_handoff_event(new.id, 'failed');
  end;
  return new;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_tells_the_supplier_he_is_approved()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_to text := lower(btrim(coalesce(new.claimed_by, ''))); v_why text; m jsonb;
begin
  if tg_op = 'UPDATE' and coalesce(old.approval_status, '') = 'approved' then return null; end if;   -- the transition only
  v_why := public.fn_seat_clock_refusal(public.fn_seat_clock_lead_is_fixture(new), v_to, 'supplier_approved');
  if v_why is null then
    m := public.fn_supplier_approved_notice_compose(new);
    perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'supplier_approved', 'requested_by', 'sales_engineer', 'channel', 'email',
      'to_email', v_to, 'to_role', 'supplier', 'lead_id', new.id, 'lang', m->>'lang',
      'subject', m->>'subject', 'body', m->>'body',
      'dedupe_key', 'supplier_approved:' || new.id)));
  end if;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('sales_engineer', 'supplier_approved_notice', case when v_why is null then 'auto_done' else 'skipped' end, 'low',
          left('Approval notice ' || case when v_why is null then 'queued' else 'not sent (' || v_why || ')' end
               || ' — ' || coalesce(new.company_name, 'supplier #' || new.id), 200),
          jsonb_build_object('supplier_id', new.id, 'to_email', nullif(v_to, ''), 'not_sent', v_why, 'categories', m->'categories'),
          'leads', new.id::text);
  return null;
exception when others then
  -- The approval stands whatever happens here; the failure is on the record for the sales engineer.
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('sales_engineer', 'supplier_approved_notice', 'failed', 'medium',
          left('Approval notice failed — ' || coalesce(new.company_name, 'supplier #' || new.id), 200),
          jsonb_build_object('supplier_id', new.id, 'error', left(sqlerrm, 500)), 'leads', new.id::text);
  return null;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_verifies_supplier(p_lead_id bigint, p_source text DEFAULT 'save_profile'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare l public.leads; v_missing text[]; v_expired boolean; v_name_mismatch boolean; v_name_unread boolean; v_name_taken boolean := false; v_old_name text; v_expiry_unread boolean; v_number_unread boolean; v_auto boolean; v_reason text; v_decision text; v_changed int; v_doc_reading boolean;
begin
  select * into l from public.leads where id = p_lead_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'lead_not_found'); end if;
  -- A registration closed for being incomplete (fn_sales_engineer_supplier_documents_tick) is re-opened
  -- by the supplier saving again: the closing notice tells them they may. Any other rejection stands.
  if coalesce(l.banned, false)
     or (coalesce(l.approval_status, '') = 'rejected'
         and not (p_source = 'save_profile' and coalesce(l.rejection_reason, '') like 'registration incomplete after %')) then
    return jsonb_build_object('ok', true, 'decision', 'unchanged', 'approval_status', l.approval_status);
  end if;

  v_missing := public.fn_supplier_mandatory_six(l);
  -- "Not known to be expired": license_extract leaves the expiry null when the licence prints none, and
  -- blocking on that would refuse suppliers whose licence genuinely has no date (29 Jul 2026 note).
  v_expired := l.license_expiry is not null and l.license_expiry < current_date;
  -- 24 Sep 2026: the licence must be this company's. Unread name = not a mismatch (nothing guessed).
  v_name_mismatch := public.fn_supplier_licence_name_mismatch(l);
  -- FOUNDER RULING 1176 (7 Oct 2026): "auto fill the name from the attachment instead of rejection". A licence name
  -- that was READ (code, or the model under its confidence rule - licence_legal_name is only ever written so) and
  -- differs from the registered name becomes the company name: the old name is kept in agent_actions, the supplier
  -- is told in English, and the gate goes on as for a matching name. Not a hold, not a review.
  -- The one exception is a licence naming a company ANOTHER claimed supplier already registered: copying that name
  -- would break leads_claimed_company_name_uidx and hand one company's identity to another, so it stays the
  -- licence_name_mismatch hold of #1275 for a person to look at.
  if v_name_mismatch then
    v_name_taken := exists (select 1 from public.leads o where o.id <> l.id and o.claimed
                              and public.fn_company_registration_name_key(o.company_name) = public.fn_company_registration_name_key(l.licence_legal_name));
    if not v_name_taken then
      v_old_name := l.company_name;
      update public.leads set company_name = btrim(l.licence_legal_name) where id = l.id;
      l.company_name := btrim(l.licence_legal_name);
      v_name_mismatch := false;
      insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
      values ('sales_engineer', 'supplier_name_from_licence', 'auto_done', 'low',
              'Company name updated from the trade licence — ' || left(l.company_name, 120),
              'No action required. The registered name did not match the name the trade licence prints; the licence name now is the company name (founder ruling 1176). The previous name is in detail.previous_name.',
              jsonb_build_object('supplier_id', l.id, 'previous_name', v_old_name, 'new_name', l.company_name,
                                 'licence_legal_name', l.licence_legal_name, 'license_doc_path', l.license_doc_path, 'source', p_source),
              'leads', l.id::text);
      if coalesce(nullif(btrim(l.claimed_by), ''), l.email, '') like '%@%' then
        perform public.fn_sales_engineer_writes('company_name_from_licence', 'supplier', coalesce(nullif(btrim(l.claimed_by), ''), l.email), l.id, null, null, null,
          'Your company name was updated to match your trade licence',
          'Your registered company name was "' || coalesce(v_old_name, '') || '". Your trade licence prints "' || l.company_name
            || '", so your company name on QuotesDone is now "' || l.company_name || '". This is the name customers, quotes and documents show. '
            || 'If this is not right, reply to this email or upload the correct trade licence.',
          null, null, '{}'::text[], 'company_name_from_licence:' || l.id || ':' || md5(l.company_name));
      end if;
    end if;
  end if;
  -- ...and an unread name is not a match: no name match, no automatic approval.
  v_name_unread := public.fn_company_name_norm(coalesce(l.licence_legal_name, '')) = '';
  -- 7 Oct 2026 (#1285): a licence on file whose expiry or number nobody could read is not a licence that was checked.
  v_expiry_unread := l.license_doc_path is not null and l.license_expiry is null;
  v_number_unread := l.license_doc_path is not null and coalesce(btrim(l.trade_license_no), '') = '';
  select coalesce(p.auto_approve_suppliers, false) into v_auto from public.pricing_config p where p.id = 1;
  -- 13 Oct 2026 (review of #1404): a profile or catalogue still being read ('reading', marked before its parse) holds
  -- approval: the gate never approves past a document whose read has not finished (or was killed mid-parse).
  v_doc_reading := exists (select 1 from public.supplier_capabilities c, jsonb_array_elements(coalesce(c.source_docs -> 'docs', '[]'::jsonb)) e
                            where c.supplier_id = l.id and e ->> 'status' = 'reading');
  v_reason := case when cardinality(v_missing) > 0 then v_missing[1]
                   when v_name_mismatch then 'licence_name_mismatch'
                   when v_expired then 'licence_expired' end;

  if coalesce(l.approval_status, '') = 'approved' and cardinality(v_missing) = 0 and not v_name_unread
     and not v_name_mismatch and not v_expiry_unread and not v_number_unread then
    -- An approved supplier whose licence has since expired stays approved: fn_reconcile_doc_blocks
    -- pauses their matching and restores it on renewal, without taking the registration away.
    v_decision := 'approved';
  -- 7 Oct 2026 (review of #1275): an APPROVED supplier whose licence names another company is held for
  -- review, whatever asked - a licence change or a save. The approved branch above used to keep him approved
  -- and log "the licence name matches", which was false. A supplier whose name matches is untouched by a save.
  elsif coalesce(l.approval_status, '') = 'approved' and cardinality(v_missing) = 0
        and v_name_mismatch then v_decision := 'pending'; v_reason := 'licence_name_mismatch';
  elsif v_reason is not null then v_decision := 'action_required';
  elsif v_name_unread then v_decision := 'pending'; v_reason := 'licence_unreadable';
  -- 7 Oct 2026 (#1285): an unread expiry or licence number is held, never approved on the name alone - also for
  -- an APPROVED supplier whose new licence (licence_changed) could not be dated or numbered.
  elsif v_expiry_unread then v_decision := 'pending'; v_reason := 'licence_expiry_unread';
  elsif v_number_unread then v_decision := 'pending'; v_reason := 'licence_number_unread';
  elsif v_doc_reading then v_decision := 'pending'; v_reason := 'documents_being_read';
  elsif coalesce(v_auto, false) then v_decision := 'approved';
  else v_decision := 'pending';
  end if;

  update public.leads
     set approval_status = v_decision,
         verified = (v_decision = 'approved'),
         approved_at = case when v_decision = 'approved' then coalesce(approved_at, now()) else approved_at end,
         approval_decided_by = 'sales_engineer',
         licence_gate_reason = v_reason
   where id = p_lead_id
     and (approval_status is distinct from v_decision or verified is distinct from (v_decision = 'approved')
          or licence_gate_reason is distinct from v_reason);
  get diagnostics v_changed = row_count;

  -- Every decision is recorded; a re-run by the trigger that changed nothing is not a decision.
  if v_changed > 0 or p_source not in ('mandatory_item_changed', 'licence_changed') then
  insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
  values ('sales_engineer', 'supplier_verification', case when v_reason in ('licence_unreadable', 'licence_expiry_unread', 'licence_number_unread', 'documents_being_read') or (v_decision = 'pending' and v_reason = 'licence_name_mismatch') then 'needs_review' else 'auto_done' end,
          case when v_decision = 'action_required' or v_reason in ('licence_unreadable', 'licence_name_mismatch', 'licence_expiry_unread', 'licence_number_unread') then 'medium' else 'low' end,
          'Supplier ' || v_decision || coalesce(' (' || v_reason || ')', '') || ' — ' || left(coalesce(l.company_name, 'supplier #' || l.id), 120),
          case v_decision
            when 'approved' then 'No action required. All six mandatory items are present, the licence name matches and the licence is not known to be expired.'
            when 'pending' then case when v_reason = 'documents_being_read'
              then 'Held: a company profile or catalogue of this supplier is still being read. The gate is run again when the read finishes; a read still unfinished after 30 minutes is marked unreadable and handed to you (document_read_stuck).'
              when v_reason = 'licence_name_mismatch'
              then 'Review: an approved supplier uploaded a new trade licence whose company name does not match the registered name. Matching is held. Compare the licence with the registered name, then re-approve or ask for the right licence.'
              when v_reason in ('licence_expiry_unread', 'licence_number_unread')
              then 'Review: complete, but the ' || case v_reason when 'licence_expiry_unread' then 'expiry date' else 'licence number' end || ' on the trade licence could not be read. Read it on the licence, record it, then approve or ask for a clearer copy. It is never approved automatically on the name alone.'
              when v_reason = 'licence_unreadable'
              then 'Review: complete, but the company name on the trade licence could not be read (a scan the document model could not read, or the model is held). Compare the licence with the registered name, then approve or ask for the right licence. It is never approved automatically without a name match.'
              else 'Complete, and waiting for the sales engineer: pricing_config.auto_approve_suppliers is off.' end
            else 'No action required. The supplier was told exactly what is missing; the verification re-runs when it arrives, and the registration closes after 14 days.' end,
          jsonb_build_object('supplier_id', l.id, 'decision', v_decision, 'previous_status', l.approval_status,
                             'missing', v_missing, 'licence_expired', v_expired, 'license_expiry', l.license_expiry,
                             'licence_name_mismatch', v_name_mismatch, 'licence_name_unread', v_name_unread,
                             'licence_expiry_unread', v_expiry_unread, 'licence_number_unread', v_number_unread,
                             'licence_legal_name', l.licence_legal_name, 'license_doc_path', l.license_doc_path,
                             'auto_approve', v_auto, 'source', p_source),
          'leads', l.id::text);
  end if;

  return jsonb_build_object('ok', true, 'decision', v_decision, 'approval_status', v_decision, 'missing', to_jsonb(v_missing),
                            'licence_expired', v_expired, 'licence_name_mismatch', v_name_mismatch, 'licence_name_unread', v_name_unread,
                            'reason', v_reason, 'auto_approve', v_auto);
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_weekly_quality_review(p_include_demo boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_from timestamptz := now() - interval '7 days';
  v_week text := to_char(now() at time zone 'Asia/Dubai', 'IYYY-"W"IW');
  v_inq int; v_matched int; v_held int; v_fixed int; v_fix_hours numeric; v_reasons jsonb; v_nomatch jsonb;
  v_rate numeric; v_top text; r record;
begin
  -- requests of the week (an inquiry older than a day has had its chance to be matched)
  with w as (
    select i.id, i.category, i.summary_masked from public.inquiries i
      left join public.customers c on c.id = i.customer_id
     where i.created_at >= v_from and i.created_at < now() - interval '1 day'
       and (p_include_demo or not coalesce(c.is_demo, false)))
  select count(*), count(*) filter (where exists (select 1 from public.inquiry_matches m where m.inquiry_id = w.id)),
         coalesce(jsonb_agg(jsonb_build_object('inquiry_id', w.id, 'trade', w.category, 'summary', w.summary_masked))
                  filter (where not exists (select 1 from public.inquiry_matches m where m.inquiry_id = w.id)), '[]')
    into v_inq, v_matched, v_nomatch from w;

  -- holds opened this week, and how fast the week's decided holds were fixed
  with h as (
    select sh.* from public.quote_spec_hold sh
      left join public.inquiries i on i.id = sh.inquiry_id left join public.customers c on c.id = i.customer_id
     where sh.opened_at >= v_from and (p_include_demo or not coalesce(c.is_demo, false)))
  select count(*), count(*) filter (where decided_at is not null),
         round(avg(extract(epoch from decided_at - opened_at) / 3600) filter (where decided_at is not null), 1)
    into v_held, v_fixed, v_fix_hours from h;

  select coalesce(jsonb_object_agg(reason, n order by n desc), '{}') into v_reasons from (
    select coalesce(e->>'attr', e #>> '{}') reason, count(*) n
      from public.quote_spec_hold sh
      left join public.inquiries i on i.id = sh.inquiry_id left join public.customers c on c.id = i.customer_id
      cross join lateral jsonb_array_elements(case when jsonb_typeof(sh.missing) = 'array' then sh.missing else '[]' end) e
     where sh.opened_at >= v_from and (p_include_demo or not coalesce(c.is_demo, false))
     group by 1) x;

  v_rate := case when v_inq > 0 then round(100.0 * v_matched / v_inq, 1) end;
  select key into v_top from jsonb_each(v_reasons) order by value::int desc limit 1;

  -- the learning loop: every request with no exact match is a case the seat recalls next time it sees one like it
  for r in select * from jsonb_to_recordset(v_nomatch) as x(inquiry_id uuid, trade text, summary text) loop
    perform public.fn_case_remember('sales_engineer', 'no_exact_match', 'inquiries.no_exact_match', r.inquiry_id::text,
      r.trade, coalesce(r.summary, 'request in ' || coalesce(r.trade, 'an unknown trade') || ' with no exact supplier match'),
      'no supplier confirmed this exact work; recruit for it', null, null, false, '{}', null,
      'Trade ' || coalesce(r.trade, 'unknown') || ' had a request no supplier could quote exactly: recruit for it before the next one.');
  end loop;

  -- the week itself
  perform public.fn_case_remember('sales_engineer', 'weekly_quality_review', 'sales_engineer.weekly_quality_review', v_week,
    null, format('Week %s: %s requests, %s matched (%s%%), %s quotes held, %s fixed (avg %s h), %s with no exact match.',
                 v_week, v_inq, v_matched, coalesce(v_rate::text, 'n/a'), v_held, v_fixed, coalesce(v_fix_hours::text, 'n/a'),
                 jsonb_array_length(v_nomatch)),
    null, null, null, true, '{}', null,
    case when v_top is not null then 'Most frequent reason a quote was held this week: ' || v_top
         || '. Ask for it in the supplier''s first review message.' end);

  return jsonb_build_object('week', v_week, 'requests', v_inq, 'matched', v_matched, 'match_rate_pct', v_rate,
    'held', v_held, 'held_fixed', v_fixed, 'avg_hours_to_fix', v_fix_hours, 'hold_reasons', v_reasons,
    'no_exact_match', jsonb_array_length(v_nomatch));
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_win_loss_review()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_m0 date := date_trunc('month', now() at time zone 'Asia/Dubai')::date; v_pm date := (v_m0 - interval '1 month')::date;
  v_from timestamptz := v_pm::timestamp at time zone 'Asia/Dubai'; v_to timestamptz := v_m0::timestamp at time zone 'Asia/Dubai';
  w public.sales_engineer_win_loss_month; v_imp bigint;
begin
  if exists (select 1 from public.sales_engineer_win_loss_month where month = v_pm) then
    return jsonb_build_object('month', v_pm, 'already_reviewed', true);
  end if;
  with i as (select i.* from public.inquiries i where i.created_at >= v_from and i.created_at < v_to and not public.fn_inquiry_is_demo(i.id)
                and exists (select 1 from public.quotes q where q.inquiry_id = i.id)),
       t as (select distinct t.inquiry_id from public.transactions t join i on i.id = t.inquiry_id where t.revealed_at is not null),
       f as (select distinct on (tx.inquiry_id) tx.inquiry_id, cf.hired from public.customer_followup cf join public.transactions tx on tx.id = cf.transaction_id
              join i on i.id = tx.inquiry_id where cf.answered_at is not null order by tx.inquiry_id, cf.answered_at desc)
  select v_pm, (select count(*) from i), (select count(*) from t),
         (select count(*) from f where hired = 'yes'), (select count(*) from f where hired = 'no'),
         (select count(*) from i where i.status in ('closed', 'expired', 'lost', 'cancelled') and i.id not in (select inquiry_id from t)),
         (select count(*) from i where (i.hired_supplier_id is not null or i.status = 'completed' or i.outcome ilike 'hired%') and i.id not in (select inquiry_id from t)),
         (select coalesce(jsonb_object_agg(reason, n), '{}'::jsonb) from (select coalesce(nullif(btrim(i.lost_reason), ''), 'not stated') reason, count(*) n
            from i where i.id not in (select inquiry_id from t) and i.status in ('closed', 'expired', 'lost', 'cancelled') group by 1) x),
         null, now()
    into w;
  if w.leakage_suspect > 0 or (w.requests_quoted >= 5 and w.no_decision > w.requests_quoted / 2) then
    v_imp := public.fn_ceo_improvement_open('self_review', 'win_loss:' || v_pm, 'sales_engineer',
      format('Win/loss %s: %s quoted requests, %s revealed, %s with no decision, %s suspected leakage (hired with no reveal). Call the no-decision and leaked customers, record why, and change the stage that loses them.',
             to_char(v_pm, 'Mon YYYY'), w.requests_quoted, w.revealed, w.no_decision, w.leakage_suspect),
      to_jsonb(w));
    w.improvement_id := v_imp;
  end if;
  insert into public.sales_engineer_win_loss_month select w.*;
  return to_jsonb(w) - 'recorded_at';
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_writes(p_msg_type text, p_role text, p_email text, p_lead bigint, p_customer uuid, p_inquiry uuid, p_quote uuid, p_subject_en text, p_body_en text, p_subject_ar text DEFAULT NULL::text, p_body_ar text DEFAULT NULL::text, p_cc text[] DEFAULT '{}'::text[], p_subject_id text DEFAULT NULL::text, p_watch_until timestamp with time zone DEFAULT NULL::timestamp with time zone, p_extra jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_locale text; v_h bigint; v_ar boolean;
begin
  -- A supplier: always English (fn_registered_locale answers 'en'). A customer: fn_customer_notice_locale
  -- (the inquiry's language, else the registered one, else English).
  v_locale := case when p_role = 'customer' then public.fn_customer_notice_locale(p_inquiry, p_customer)
                   else coalesce(public.fn_registered_locale(p_role, p_customer, p_lead, p_email), 'en') end;
  v_h := public.fn_seat_handoff('sales_engineer', 'customer_support', 'delivery.request', 'notifications',
    coalesce(p_subject_id, p_msg_type || ':' || coalesce(p_quote::text, p_inquiry::text, p_lead::text, p_customer::text, 'x')),
    coalesce(p_extra, '{}'::jsonb) || jsonb_build_object(
      'msg_type', p_msg_type, 'recipient_role', p_role, 'to_email', p_email, 'cc', to_jsonb(coalesce(p_cc, '{}'::text[])),
      'supplier_id', p_lead, 'customer_id', p_customer, 'inquiry_id', p_inquiry, 'quote_id', p_quote,
      'locale', v_locale,
      'subject_en', p_subject_en, 'body_en', p_body_en || E'\n\nQuotesDone sales engineer',
      'subject_ar', p_subject_ar,
      'body_ar', case when p_body_ar is null then null else p_body_ar || E'\n\nمهندس المبيعات في QuotesDone' end,
      'watch_until', p_watch_until));

  -- demo work (ruling 1199): no handoff was filed; the message is written for the record and captured, never sent
  if v_h is null and coalesce(p_email, '') ~ '@' then
    v_ar := v_locale = 'ar' and p_body_ar is not null;
    insert into public.notifications (type, kind, to_email, cc_emails, to_role, lead_id, inquiry_id, quote_id, channel,
                                      subject, body, status, last_error, requested_by)
    values (p_msg_type, p_msg_type, p_email, coalesce(p_cc, '{}'::text[]), p_role, p_lead, p_inquiry, p_quote, 'email',
            case when v_ar then coalesce(p_subject_ar, p_subject_en) else p_subject_en end,
            case when v_ar then p_body_ar || E'\n\nمهندس المبيعات في QuotesDone' else p_body_en || E'\n\nQuotesDone sales engineer' end,
            'suppressed', 'demo work (ruling 1199): written for the record, never sent', 'sales_engineer');
  end if;
  return v_h;
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_writes_money_notice(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  a public.agent_actions; d jsonb; v_notice text; v_sup record; v_tpl jsonb; v_vars jsonb;
  v_sub_en text; v_body_en text; v_sub_ar text; v_body_ar text; v_req bigint; v_msg text;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  -- THE KIND IS THE CONVERSATION'S TYPE (public.seat_handoff_kind, #648): fn_seat_handoff_act dispatches
  -- each of the five rows inserted below to this routine, and the type alone says which notice it is.
  v_notice := case a.detail->>'type'
                when 'nonresponse.charge_reminder'  then 'charge_reminder'
                when 'nonresponse.final_demand'     then 'final_demand'
                when 'subscription.renewal_reminder' then 'subscription_renewal'
                when 'subscription.dunning'         then 'subscription_dunning'
                when 'subscription.payment_failed'  then 'subscription_payment_failed' end;
  if not found or a.agent <> 'sales_engineer' or v_notice is null then
    raise exception 'fn_sales_engineer_writes_money_notice: % is not one of the accountant''s notice kinds', p_id;
  end if;
  d := a.detail;
  select l.id, l.company_name, coalesce(l.claimed_by, l.email) email into v_sup
    from public.leads l where l.id = (d->>'supplier_id')::bigint;
  if coalesce(v_sup.email, '') not like '%@%' then
    return jsonb_build_object('supplier_reachable', false, 'notice', v_notice);
  end if;
  v_vars := d || jsonb_build_object('company', coalesce(v_sup.company_name, ''),
                                   'reveal_ref', left(coalesce(d->>'transaction_id', ''), 8));

  if v_notice in ('charge_reminder', 'final_demand') then
    -- THE WORDING IS THE LEGAL DOCUMENT'S, NOT THIS FILE'S (founder, 14 Sep 2026: "make sure the form
    -- and the wordings is done correctly"). No template row, no send: the handoff fails and says why.
    select value into v_tpl from public.decision_policy
     where key = case v_notice when 'charge_reminder' then 'supplier_charge_reminder_template'
                               else 'supplier_charge_final_demand_template' end;
    if v_tpl is null or coalesce(v_tpl->>'body_en', '') = '' then
      raise exception 'no % template in decision_policy: the wording comes from docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md and has not been configured', v_notice;
    end if;
    v_sub_en := public.fn_render_template(v_tpl->>'subject_en', v_vars);
    v_body_en := public.fn_render_template(v_tpl->>'body_en', v_vars);
    v_sub_ar := public.fn_render_template(v_tpl->>'subject_ar', v_vars);
    v_body_ar := public.fn_render_template(v_tpl->>'body_ar', v_vars);
    v_msg := 'nonresponse_' || v_notice;
  elsif v_notice = 'subscription_renewal' then
    v_sub_en := 'Your QuotesDone supplier subscription renews on ' || (d->>'renews_on');
    v_body_en := 'Dear ' || coalesce(v_sup.company_name, 'there') || E',\n\nYour annual QuotesDone supplier subscription is paid until '
      || (d->>'paid_until') || '. The renewal of ' || coalesce(d->>'currency', 'AED') || ' ' || (d->>'fee')
      || ' falls due on ' || (d->>'renews_on') || E'.\n\nYou can renew from the Billing section of your supplier portal: https://quotesdone.com/suppliers. Stripe issues the invoice for the payment.\n\nYou keep paying no commission on the jobs you win.';
    v_sub_ar := 'موعد تجديد اشتراككم كمورّد في QuotesDone: ' || (d->>'renews_on');
    v_body_ar := 'اشتراككم السنوي مدفوع حتى ' || (d->>'paid_until') || '، ويستحق التجديد بقيمة ' || (d->>'fee')
      || ' درهم في ' || (d->>'renews_on') || '. ويمكنكم التجديد من قسم الفواتير في بوابة المورّد.';
    v_msg := 'subscription_renewal_reminder';
  elsif v_notice = 'subscription_dunning' then
    v_sub_en := 'Reminder ' || (d->>'dunning_no') || ': your QuotesDone subscription is unpaid';
    v_body_en := 'Dear ' || coalesce(v_sup.company_name, 'there') || E',\n\nYour annual supplier subscription of '
      || coalesce(d->>'currency', 'AED') || ' ' || (d->>'fee') || ' fell due on ' || (d->>'due_on') || ' and is still unpaid ('
      || (d->>'days_overdue') || E' days).\n\nPlease settle it from the Billing section of your supplier portal: https://quotesdone.com/suppliers. '
      || E'Until it is settled your profile does not receive new customer requests.\n\nIf you have already paid, reply to this email and we will check it against the payment record.';
    v_sub_ar := 'تذكير ' || (d->>'dunning_no') || ': اشتراككم في QuotesDone لم يُسدَّد بعد';
    v_body_ar := 'استحق اشتراككم السنوي كمورّد بقيمة ' || (d->>'fee') || ' درهم في ' || (d->>'due_on') || ' ولم يُسدَّد بعد ('
      || public.fn_ar_days((d->>'days_overdue')::int) || '). يُرجى السداد من قسم الفواتير في بوابة المورّد، علمًا بأن ملفكم لن يتلقى طلبات جديدة حتى السداد.';
    v_msg := 'subscription_dunning';
  elsif v_notice = 'subscription_payment_failed' then
    v_sub_en := 'Your QuotesDone subscription payment did not go through';
    v_body_en := 'Dear ' || coalesce(v_sup.company_name, 'there') || E',\n\nYour payment for the annual supplier subscription did not complete, and nothing was charged. '
      || E'You can try again at any time from the Billing section of your supplier portal: https://quotesdone.com/suppliers. If the card was declined, your bank can tell you why, and a different card also works.';
    v_sub_ar := 'لم يكتمل دفع اشتراككم في QuotesDone';
    v_body_ar := 'تعذّر إتمام دفع الاشتراك السنوي، ولم يُخصم أي مبلغ. يمكنكم إعادة المحاولة من قسم الفواتير في بوابة المورّد.';
    v_msg := 'subscription_payment_failed';
  else
    raise exception 'fn_sales_engineer_writes_money_notice: no words for notice %', v_notice;
  end if;

  if v_body_en ~ '\{\{[a-z_]+\}\}' or coalesce(v_body_ar, '') ~ '\{\{[a-z_]+\}\}' then
    raise exception 'notice % for handoff % still carries an unfilled placeholder; nothing was sent', v_notice, p_id;
  end if;
  -- A RECOVERY DOCUMENT IS SIGNED IN THE FOUNDER'S NAME (founder, 14 Sep 2026: "with stamp and signature
  -- of course"), so every one issued is logged before it leaves: what, which version, its hash, to whom.
  if v_notice in ('charge_reminder', 'final_demand') then
    insert into public.accountant_issued_document (document_kind, template_key, template_version, content_sha256, recipient,
      supplier_id, due_id, handoff_id, signed_as, stamp_required, signature_required)
    values (v_notice, case v_notice when 'charge_reminder' then 'supplier_charge_reminder_template' else 'supplier_charge_final_demand_template' end,
            coalesce(v_tpl->>'version', 'unversioned'),
            encode(sha256(convert_to(coalesce(v_sub_en, '') || E'\n' || v_body_en || E'\n' || coalesce(v_sub_ar, '') || E'\n' || coalesce(v_body_ar, ''), 'UTF8')), 'hex'),
            v_sup.email, v_sup.id, (d->>'due_id')::bigint, p_id, 'founder', true, true);
  end if;
  v_req := public.fn_sales_engineer_writes(v_msg, 'supplier', v_sup.email, v_sup.id, null,
    (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid, v_sub_en, v_body_en, v_sub_ar, v_body_ar,
    '{}', v_msg || ':' || (d->>'subject_id'), null,
    jsonb_build_object('transaction_id', d->>'transaction_id', 'due_id', d->>'due_id', 'notice', v_notice));
  return jsonb_build_object('notice', v_notice, 'delivery_request', v_req);
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_figure(p_value numeric, p_universe bigint, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'value', p_value,
    'basis', case when p_value is null then 'unknown'
                  when coalesce(p_universe, 0) = 0 then 'true_zero'
                  else 'measured' end,
    'denominator', p_universe,
    'note', p_note);
$function$


CREATE OR REPLACE FUNCTION public.fn_sales_knowledge_search_vector()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  new.search :=
      setweight(to_tsvector('english'::regconfig, coalesce(new.title,'')), 'A')
   || setweight(to_tsvector('english'::regconfig, coalesce(array_to_string(new.tags,' '),'')), 'B')
   || setweight(to_tsvector('english'::regconfig, coalesce(new.content,'')), 'C');
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_sales_portal_report(p_party_kind text, p_party_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_kind text := lower(coalesce(btrim(p_party_kind), ''));
  v_out  jsonb;
  -- The UNIVERSES. Every "0" below is interpreted against the size of the table it came from, so
  -- an empty table reports true_zero with its denominator instead of a bare 0 that could equally
  -- mean "this party has none" on a busy platform.
  u_inq   bigint := (select count(*) from inquiries);
  u_q     bigint := (select count(*) from quotes);
  u_tx    bigint := (select count(*) from transactions);
  u_rev   bigint := (select count(*) from reviews);
  u_match bigint := (select count(*) from inquiry_matches);
  u_proj  bigint := (select count(*) from projects);
  -- supplier
  s_id bigint; s_row leads%rowtype; s_cap supplier_capabilities%rowtype; s_score supplier_score%rowtype;
  s_won bigint; s_quoted bigint; s_matched bigint; s_reviews bigint; s_rating numeric;
  -- customer
  c_id uuid; c_row customers%rowtype;
  c_inq bigint; c_q bigint; c_spend numeric; c_tx bigint; c_proj bigint; c_suppliers jsonb;
begin
  if v_kind = 'supplier' then
    begin s_id := p_party_id::bigint; exception when others then
      return jsonb_build_object('ok', false, 'error', 'party_id_not_a_supplier_id', 'party_id', p_party_id); end;
    select * into s_row from leads where id = s_id;
    if not found then return jsonb_build_object('ok', false, 'error', 'unknown_supplier', 'party_id', p_party_id); end if;

    select * into s_cap   from supplier_capabilities where supplier_id = s_id;
    select * into s_score from supplier_score        where lead_id     = s_id;
    select count(*) into s_won     from inquiries       where hired_supplier_id = s_id;
    select count(*) into s_quoted  from quotes          where supplier_id = s_id;
    select count(*) into s_matched from inquiry_matches where supplier_id = s_id;
    select count(*), round(avg(rating)::numeric, 2) into s_reviews, s_rating
      from reviews where supplier_id = s_id;

    v_out := jsonb_build_object(
      'ok', true, 'party_kind', 'supplier', 'party_id', s_id,
      'company_name', s_row.company_name,
      'generated_at', now(),

      'jobs_won',         fn_sales_figure(s_won::numeric,     u_inq,   'inquiries where this supplier was hired'),
      'quotes_submitted', fn_sales_figure(s_quoted::numeric,  u_q,     'quotes rows carrying this supplier_id'),
      'rfqs_received',    fn_sales_figure(s_matched::numeric, u_match, 'inquiry_matches rows carrying this supplier_id'),
      'quotes_won',       fn_sales_figure(s_won::numeric,     u_q,     'a won quote is an inquiry hired to this supplier; counted against the quotes universe'),
      'win_rate_pct', case when coalesce(s_quoted,0) > 0
                           then jsonb_build_object('value', round(100.0 * s_won / s_quoted, 1), 'basis', 'measured')
                           else jsonb_build_object('value', null, 'basis', 'unknown',
                                  'note', 'no quote has been submitted, so there is no denominator; this is not a 0% win rate') end,

      -- RATINGS. Two numbers with the same name and completely different standing.
      'rating_earned_here', jsonb_build_object(
        'value', s_rating, 'review_count', s_reviews,
        'basis', case when s_rating is not null then 'measured'
                      when u_rev = 0 then 'true_zero' else 'unknown' end,
        'denominator', u_rev,
        'note', 'average of reviews left by customers on THIS platform'),
      'rating_from_directory', case when s_row.rating is not null then jsonb_build_object(
          'value', s_row.rating, 'basis', 'derived_not_earned',
          'note', 'scraped from a public business directory before this supplier ever registered. It is NOT performance on QuotesDone and must never be presented to a supplier as its rating here, nor to a customer as evidence.')
        else jsonb_build_object('value', null, 'basis', 'unknown') end,

      -- APPROVAL. null is not "no".
      'approval', case when s_row.approval_status is null then jsonb_build_object(
            'value', null, 'basis', 'unknown',
            'note', 'no approval decision has ever been recorded for this supplier. This is not a rejection and not a pending queue position.')
        else jsonb_build_object('value', s_row.approval_status, 'basis', 'measured') end,
      'registered', jsonb_build_object('value', coalesce(s_row.claimed, false), 'basis', 'measured',
        'note', 'claimed = the supplier took ownership of this directory record and registered'),

      'document_expiry', fn_supplier_expiries(s_id),

      'capability_confirmation', case when s_cap.supplier_id is null then jsonb_build_object(
            'state', 'none_on_file', 'basis', 'true_zero')
        else jsonb_build_object(
            'state', case when s_cap.confirmed_at is not null then 'confirmed_by_supplier'
                          else 'unconfirmed' end,
            'basis', case when s_cap.confirmed_at is not null then 'measured' else 'derived_not_earned' end,
            'extractor_version', s_cap.extractor_version,
            'review_status', s_cap.review_status,
            'confirmed_at', s_cap.confirmed_at,
            'completeness', s_cap.completeness,
            'note', case when s_cap.confirmed_at is null then
              'These capabilities were derived from a directory listing, not stated by the supplier. Until the supplier confirms them they are a starting point for a conversation, not a claim we may quote against.' end) end,

      'platform_score', case when s_score.lead_id is null then jsonb_build_object('basis', 'true_zero')
        else jsonb_build_object('basis', 'derived_not_earned',
          'quotes_submitted', s_score.quotes_submitted, 'quotes_won', s_score.quotes_won,
          'response_rate', s_score.response_rate, 'reliability', s_score.reliability,
          'computed_at', s_score.computed_at,
          'note', 'supplier_score rows were computed over the imported directory, not over activity on this platform. Read alongside jobs_won, which is the earned figure.') end);

  elsif v_kind = 'customer' then
    begin c_id := p_party_id::uuid; exception when others then
      return jsonb_build_object('ok', false, 'error', 'party_id_not_a_customer_id', 'party_id', p_party_id); end;
    select * into c_row from customers where id = c_id;
    if not found then return jsonb_build_object('ok', false, 'error', 'unknown_customer', 'party_id', p_party_id); end if;

    select count(*) into c_inq  from inquiries where customer_id = c_id;
    select count(*) into c_q    from quotes q join inquiries i on i.id = q.inquiry_id where i.customer_id = c_id;
    select count(*), coalesce(sum(t.quote_amount), 0) into c_tx, c_spend
      from transactions t where t.customer_id = c_id;
    select count(*) into c_proj from projects where customer_id = c_id;

    -- Supplier performance on THIS customer's own jobs. fn_customer_supplier_score already refuses
    -- to invent a relationship (basis 'no_shared_history'), so it is called rather than re-derived.
    select coalesce(jsonb_agg(fn_customer_supplier_score(c_id, s)), '[]'::jsonb) into c_suppliers
      from (select distinct hired_supplier_id s from inquiries
             where customer_id = c_id and hired_supplier_id is not null) x;

    v_out := jsonb_build_object(
      'ok', true, 'party_kind', 'customer', 'party_id', c_id,
      'email', c_row.email, 'full_name', c_row.full_name,
      'generated_at', now(),
      'inquiries',       fn_sales_figure(c_inq::numeric,  u_inq,  'inquiries this customer posted'),
      'quotes_received', fn_sales_figure(c_q::numeric,    u_q,    'quotes against this customer''s inquiries'),
      'reveals',         fn_sales_figure(c_tx::numeric,   u_tx,   'paid reveals; a transactions row is a reveal'),
      'total_spend_aed', jsonb_build_object(
        'value', case when u_tx = 0 then 0 else c_spend end,
        'basis', case when u_tx = 0 then 'true_zero' else 'measured' end,
        'denominator', u_tx,
        'note', 'sum of transactions.quote_amount for this customer. The reveal fee is 3% of it; this figure is the job value, not the fee.'),
      'projects',        fn_sales_figure(c_proj::numeric, u_proj, 'projects owned by this customer'),
      'supplier_performance', c_suppliers,
      'supplier_performance_basis', case when jsonb_array_length(c_suppliers) = 0
        then 'no supplier has been hired by this customer yet, so there is no performance to report'
        else 'per-relationship, from this customer''s own RFQs, quotes, reveals and reviews' end);
  else
    return jsonb_build_object('ok', false, 'error', 'unknown_party_kind', 'party_kind', p_party_kind,
                              'accepted', jsonb_build_array('supplier', 'customer'));
  end if;

  insert into sales_decision_log (actor, action, query, answered, subject, candidates)
  values ('sales_engineer', 'report', null, true, v_kind || ':' || p_party_id,
          jsonb_build_object('universes', jsonb_build_object(
            'inquiries', u_inq, 'quotes', u_q, 'transactions', u_tx,
            'reviews', u_rev, 'inquiry_matches', u_match, 'projects', u_proj)));

  return v_out;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_sales_rating_landed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_task     bigint;
  v_company  text;
  v_customer text;
  v_title    text;
  v_payload  jsonb;
begin
  select l.company_name into v_company from public.leads l where l.id = new.supplier_id;
  select coalesce(nullif(btrim(c.full_name), ''), c.email) into v_customer
    from public.customers c where c.id = new.customer_id;

  v_title := left('Customer rating landed: ' || coalesce(v_company, 'supplier #' || new.supplier_id)
             || ' — ' || new.rating || '/5', 200);

  v_payload := jsonb_build_object(
    'transaction_id', new.transaction_id,
    'review_id',      new.id,
    'supplier_id',    new.supplier_id,
    'supplier',       v_company,
    'customer_id',    new.customer_id,
    'customer',       v_customer,
    'inquiry_id',     new.inquiry_id,
    'rating',         new.rating,
    'comment',        left(coalesce(new.comment, ''), 500),
    'arrived_at',     now(),
    'op',             tg_op);

  -- UNFILTERED BY STATUS. Every task this transaction has ever opened, in any state.
  select t.id into v_task
    from public.org_tasks t
   where t.result -> 'sales_rating' ->> 'transaction_id' = new.transaction_id::text
   order by t.id desc
   limit 1;

  if v_task is not null then
    update public.org_tasks
       set result = jsonb_set(coalesce(result, '{}'::jsonb), '{sales_rating}',
                      coalesce(result -> 'sales_rating', '{}'::jsonb) || v_payload
                      || jsonb_build_object('revisions',
                           coalesce((result -> 'sales_rating' ->> 'revisions')::int, 1) + 1)),
           title      = v_title,
           updated_at = now()
     where id = v_task;
  else
    insert into public.org_tasks (title, detail, status, tier, needs_founder, decided_by,
                                  action_class, assigned_agent, priority, result)
    values (v_title,
            'A QuotesDone customer rated a supplier they paid to reveal and actually dealt with.'
              || E'\n\nSupplier: ' || coalesce(v_company, 'id ' || new.supplier_id)
              || E'\nCustomer: ' || coalesce(v_customer, 'id ' || new.customer_id)
              || E'\nTransaction: ' || new.transaction_id
              || coalesce(E'\nInquiry: ' || new.inquiry_id::text, '')
              || E'\nRating: ' || new.rating || '/5'
              || coalesce(E'\nComment: ' || nullif(btrim(new.comment), ''), '')
              || E'\n\nIncorporate it into the supplier record: recompute_supplier_rating() has'
              || ' already run on the aggregate, so what is left is the judgement this seat owns —'
              || ' whether this rating changes the supplier''s standing, their declared capability,'
              || ' or their eligibility for the trades they are matched on. If the customer changes'
              || ' their rating this task is updated, never duplicated.',
            'assigned', 'advisory', false, 'fn_sales_rating_landed',
            'routine_operational_decision', 'sales_engineer', 1,
            jsonb_build_object('sales_rating', v_payload || jsonb_build_object('revisions', 1)))
    returning id into v_task;
  end if;

  return new;
exception when others then
  -- THE RATING WINS. Always.
  return new;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_sanctioned_identity(p_name text, p_licence text, p_account_email text DEFAULT NULL::text, p_self bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select b.lead_id from public.sanctions_ban b
   where (p_self is null or b.lead_id <> p_self)
     and ( (b.name_key       is not null and b.name_key       = public.fn_screening_normalise(p_name))
        or (b.licence_key    is not null and b.licence_key    = public.fn_sanctions_identity_key(p_licence))
        or (b.account_email  is not null and b.account_email  = lower(btrim(coalesce(p_account_email, ''))))
        or (b.contact_email  is not null and b.contact_email  = lower(btrim(coalesce(p_account_email, '')))) )
   order by b.lead_id limit 1;
$function$


CREATE OR REPLACE FUNCTION public.fn_sanctions_ban_is_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  raise exception 'SANCTIONS_RECORD_IS_SEALED: public.sanctions_ban is append-only (founder instruction 516, 18 Sep 2026). % refused.', tg_op
    using errcode = '42501';
end $function$


CREATE OR REPLACE FUNCTION public.fn_sanctions_identity_key(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select nullif(upper(regexp_replace(coalesce(p, ''), '[^[:alnum:]]+', '', 'g')), '');
$function$


CREATE OR REPLACE FUNCTION public.fn_sanctions_screen_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'net', 'pg_temp'
AS $function$
declare v_ref text; v_secret text; v_req bigint;
begin
  select value into v_ref    from public.app_secrets where key = 'project_ref';
  select value into v_secret from public.app_secrets where key = 'cred_cron_compliance';
  if v_ref is null or v_secret is null then
    raise exception 'fn_sanctions_screen_tick: % is missing from app_secrets, so the weekly screening cannot be posted',
      case when v_ref is null then 'project_ref' else 'cred_cron_compliance' end;
  end if;
  select net.http_post(
    url     := 'https://' || v_ref || '.supabase.co/functions/v1/sanctions_screen',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body    := jsonb_build_object('__secret', v_secret, 'caller', 'fn_sanctions_screen_tick'),
    timeout_milliseconds := 120000
  ) into v_req;
  -- `posted` means the request was QUEUED, and nothing more. MEASURED 18 Sep 2026: a probe polled
  -- net._http_response for its own request id for 15 s inside the posting transaction (request 432566)
  -- and the row never appeared, because pg_net dispatches after commit. So there is no version of this
  -- routine that can return the real status, and saying so is the fix.
  return jsonb_build_object(
    'posted', true,
    'request_id', v_req,
    'response_status', null,
    'note', 'QUEUED ONLY. pg_net dispatches after this transaction commits, so the outcome is not '
         || 'knowable here — call public.fn_sanctions_screen_tick_status(' || v_req || ') a few seconds '
         || 'from now to read it. This routine is the MANUAL kick; the weekly clock is resilience_ping''s '
         || 'orphans step, which calls the function over HTTP and reads the response synchronously.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_sanctions_screen_tick_status(p_request_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'net', 'pg_temp'
AS $function$
  select coalesce(
    (select jsonb_build_object('request_id', r.id, 'status', r.status_code, 'timed_out', r.timed_out,
                               'error', r.error_msg, 'body', left(coalesce(r.content, ''), 2000),
                               'at', r.created)
       from net._http_response r where r.id = p_request_id),
    jsonb_build_object('request_id', p_request_id, 'status', null,
      'note', 'No response on record yet. pg_net writes it after the posting transaction commits, and '
           || 'prunes old rows, so this is either still in flight or already aged out.'));
$function$


CREATE OR REPLACE FUNCTION public.fn_schema_export()
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '15s'
AS $function$
with t as (
  select c.relname as rel,
    'CREATE TABLE IF NOT EXISTS public.'||quote_ident(c.relname)||E' (\n'||
    string_agg('  '||quote_ident(a.attname)||' '||format_type(a.atttypid,a.atttypmod)||
      case a.attidentity when 'a' then ' GENERATED ALWAYS AS IDENTITY' when 'd' then ' GENERATED BY DEFAULT AS IDENTITY' else '' end||
      case when a.attgenerated='s' then ' GENERATED ALWAYS AS ('||pg_get_expr(ad.adbin,ad.adrelid)||') STORED'
           when ad.adbin is not null then ' DEFAULT '||pg_get_expr(ad.adbin,ad.adrelid) else '' end||
      case when a.attnotnull then ' NOT NULL' else '' end, E',\n' order by a.attnum)
    ||E'\n);' as tbl_ddl
  from pg_class c join pg_namespace n on n.oid=c.relnamespace and n.nspname='public'
  join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
  left join pg_attrdef ad on ad.adrelid=c.oid and ad.adnum=a.attnum
  where c.relkind='r' and not exists(select 1 from pg_depend d where d.objid=c.oid and d.deptype='e')
  group by c.relname
)
select
  '-- QuotesDone — FULL SCHEMA EXPORT (generated from the live database)'||E'\n'
  ||'-- Excludes: secret VALUES (key names listed below), and table ROW DATA (PII).'||E'\n'
  ||'-- Order is best-effort; this is a faithful reference mirror, not a guaranteed one-click restore.'||E'\n\n'
  ||'-- ===== EXTENSIONS =====' ||E'\n'|| coalesce((select string_agg('CREATE EXTENSION IF NOT EXISTS '||quote_ident(extname)||' WITH SCHEMA '||quote_ident(nx.nspname)||';', E'\n' order by extname) from pg_extension e join pg_namespace nx on nx.oid=e.extnamespace),'')
  ||E'\n\n-- ===== SEQUENCES =====\n'|| coalesce((select string_agg('CREATE SEQUENCE IF NOT EXISTS public.'||quote_ident(sequence_name)||';', E'\n' order by sequence_name) from information_schema.sequences where sequence_schema='public'),'')
  ||E'\n\n-- ===== TABLES ('||(select count(*) from t)||E') =====\n'|| coalesce((select string_agg(tbl_ddl, E'\n\n' order by rel) from t),'')
  ||E'\n\n-- ===== CONSTRAINTS =====\n'|| coalesce((select string_agg('ALTER TABLE public.'||quote_ident(c.relname)||' ADD CONSTRAINT '||quote_ident(con.conname)||' '||pg_get_constraintdef(con.oid)||';', E'\n' order by case con.contype when 'p' then 1 when 'u' then 2 when 'c' then 3 else 9 end, c.relname, con.conname) from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace and n.nspname='public' where con.contype in ('p','u','c','f')),'')
  ||E'\n\n-- ===== INDEXES =====\n'|| coalesce((select string_agg(pg_get_indexdef(i.indexrelid)||';', E'\n' order by ic.relname) from pg_index i join pg_class ic on ic.oid=i.indexrelid join pg_namespace n on n.oid=ic.relnamespace and n.nspname='public' where not exists(select 1 from pg_constraint con where con.conindid=i.indexrelid) and not exists(select 1 from pg_depend d where d.objid=ic.oid and d.deptype='e')),'')
  ||E'\n\n-- ===== VIEWS =====\n'|| coalesce((select string_agg('CREATE OR REPLACE VIEW public.'||quote_ident(viewname)||' AS '||definition, E'\n\n' order by viewname) from pg_views where schemaname='public'),'')
  ||E'\n\n-- ===== FUNCTIONS =====\n'|| coalesce((select string_agg(pg_get_functiondef(p.oid), E'\n\n' order by p.proname, pg_get_function_identity_arguments(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.prokind in ('f','p') and not exists(select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')),'')
  ||E'\n\n-- ===== TRIGGERS =====\n'|| coalesce((select string_agg(pg_get_triggerdef(tg.oid)||';', E'\n' order by c.relname, tg.tgname) from pg_trigger tg join pg_class c on c.oid=tg.tgrelid join pg_namespace n on n.oid=c.relnamespace and n.nspname='public' where not tg.tgisinternal),'')
  ||E'\n\n-- ===== ROW LEVEL SECURITY (enable) =====\n'|| coalesce((select string_agg('ALTER TABLE public.'||quote_ident(relname)||' ENABLE ROW LEVEL SECURITY;', E'\n' order by relname) from pg_class c join pg_namespace n on n.oid=c.relnamespace and n.nspname='public' where relkind='r' and relrowsecurity),'')
  ||E'\n\n-- ===== POLICIES =====\n'|| coalesce((select string_agg('CREATE POLICY '||quote_ident(policyname)||' ON public.'||quote_ident(tablename)||' AS '||permissive||' FOR '||cmd||' TO '||array_to_string(roles,', ')||coalesce(' USING ('||qual||')','')||coalesce(' WITH CHECK ('||with_check||')','')||';', E'\n' order by tablename,policyname) from pg_policies where schemaname='public'),'')
  ||E'\n\n-- ===== CRON JOBS =====\n'|| coalesce((select string_agg('select cron.schedule('||quote_literal(jobname)||','||quote_literal(schedule)||',$CRON$'||command||'$CRON$);', E'\n' order by jobid) from cron.job),'')
  ||E'\n\n-- ===== APP_SECRETS KEY NAMES (values intentionally excluded) =====\n'|| coalesce((select string_agg('--   '||key, E'\n' order by key) from public.app_secrets),'')
  ||E'\n'
$function$


CREATE OR REPLACE FUNCTION public.fn_screening_normalise(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select nullif(btrim(regexp_replace(
           regexp_replace(
             ' ' || regexp_replace(
               translate(lower(coalesce(p, '')), 'áàâäãåéèêëíìîïóòôöõúùûüçñýÿ', 'aaaaaaeeeeiiiiooooouuuucnyy'),
               '[^[:alnum:][:space:]]+', ' ', 'g') || ' ',
             '\s(llc|l l c|fze|fzc|fzco|fz|ltd|limited|inc|co|company|corp|corporation|est|establishment|trading|general|contracting|contractors|services|group|international|technical|the|of|and|for|in|dmcc|plc|sarl|sal|gmbh|bv|sole|proprietorship)(?=\s)', ' ', 'g'),
           '\s+', ' ', 'g')), '');
$function$


CREATE OR REPLACE FUNCTION public.fn_screening_record_is_never_deleted()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if tg_table_name = 'screening_entry' and tg_op = 'DELETE' then
    if exists (select 1 from public.supplier_screening_hit h
                where h.entry_id = old.id
                   or (h.entry_source = old.source and h.entry_reference = old.reference)) then
      raise exception 'SANCTIONS_RECORD_IS_SEALED: screening_entry #% is cited by a supplier_screening_hit and cannot be deleted.', old.id
        using errcode = '42501';
    end if;
    return old;
  end if;
  raise exception 'SANCTIONS_RECORD_IS_SEALED: % on public.% is refused (founder instruction 516, 18 Sep 2026: never hard-delete a sanctions record).', tg_op, tg_table_name
    using errcode = '42501';
end $function$


CREATE OR REPLACE FUNCTION public.fn_screening_tokens(p text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(array(
    select distinct t from unnest(string_to_array(coalesce(public.fn_screening_normalise(p), ''), ' ')) t
     where length(t) >= 3
       and t <> all (array['abd','abdul','abdel','bin','ibn','abu','bint','umm','von','van','der','del','della','les','das','dos'])
     order by t), '{}'::text[]);
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_answers_ceo_root_cause(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions; v_held bigint;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  v_held := public.fn_ceo_root_cause_ask(a.agent, (a.detail->>'task_id')::bigint, a.detail - 'type' - 'from' - 'from_name' - 'to', a.id);
  return jsonb_build_object('accepted', true, 'seat', a.agent, 'reasoning_held_id', v_held,
                            'waiting', 'the seat reasons the root cause; the CEO closes this when the answer is applied');
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_answers_it_finding(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions; d jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' <> 'it.finding' then
    raise exception 'fn_seat_answers_it_finding: % is not an it.finding handoff', p_id;
  end if;
  d := a.detail;
  -- THE CEO OWNS THE HARNESS, AND CAN CLOSE A REHEARSAL WINDOW A RUN LEFT OPEN. An open window keeps
  -- the failed-run watcher from paging for anything it covers, so closing it is the remedy, not a risk.
  if d->>'duty' = 'demo' and (d->'finding_evidence'->>'rehearsal_window_id') is not null then
    update public.rehearsal_window set ended_at = now()
     where id = (d->'finding_evidence'->>'rehearsal_window_id')::bigint and ended_at is null;
    return jsonb_build_object('waiting', 'it_engineer re-verification', 'seat', a.agent, 'duty', 'demo',
      'remedy', 'closed rehearsal_window ' || (d->'finding_evidence'->>'rehearsal_window_id'),
      'reply', a.agent || ' closed rehearsal window ' || (d->'finding_evidence'->>'rehearsal_window_id')
               || ', which its run had left open.');
  end if;
  return jsonb_build_object(
    'waiting', 'it_engineer re-verification',
    'seat', a.agent,
    'duty', d->>'duty',
    'remedy', null,
    'reply', a.agent || ' acknowledged "' || coalesce(d->>'title', d->>'issue_key') || '". Its playbook has no '
             || 'deterministic remedy for a ' || coalesce(d->>'duty', 'fault') || ' finding on '
             || coalesce(d->>'subject', 'this subject') || ': it needs a code or configuration change.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_clock_asked(p_dedupe_key text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (select 1 from public.agent_actions a
                  where a.kind = 'handoff' and a.agent = 'customer_support'
                    and a.target_id = 'delivery.request:' || p_dedupe_key and a.status <> 'failed')
      or exists (select 1 from public.notifications n where n.dedupe_key = p_dedupe_key)
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_clock_compose(p_kind text, p_lang text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_ar boolean := coalesce(p_lang, '') like 'ar%';
  v_lang text := case when coalesce(p_lang, '') like 'ar%' then 'ar' else 'en' end;
  v_site text; v_link text; v_trade text; v_trade_ar text; v_em text; v_em_ar text; v_where text; v_where_ar text;
  v_name text := nullif(btrim(coalesce(p->>'name', '')), '');
  v_n int := coalesce((p->>'quotes')::int, 0);
  v_due text; v_subj text; v_body text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  v_link := coalesce(v_site, 'https://quotesdone.com') || '/' || v_lang || '/portal';
  select t.label, coalesce(t.label_ar, t.label) into v_trade, v_trade_ar
    from public.taxonomy_trade t
   where t.code = (public.fn_taxonomy_trades_for(array[coalesce(p->>'category', '')]))[1];
  v_trade := coalesce(v_trade, nullif(p->>'category', ''), 'your trade');
  v_trade_ar := coalesce(v_trade_ar, nullif(p->>'category', ''), 'تخصصكم');
  v_em := nullif(btrim(coalesce(p->>'emirate', '')), '');
  v_em_ar := case lower(coalesce(v_em, '')) when 'dubai' then 'دبي' when 'abu dhabi' then 'أبوظبي' when 'sharjah' then 'الشارقة'
               when 'ajman' then 'عجمان' when 'umm al quwain' then 'أم القيوين' when 'ras al khaimah' then 'رأس الخيمة'
               when 'fujairah' then 'الفجيرة' else v_em end;
  v_where := v_trade || coalesce(' in ' || v_em, '');
  v_where_ar := v_trade_ar || coalesce(' في ' || v_em_ar, '');
  v_due := to_char((p->>'deadline')::timestamptz at time zone 'Asia/Dubai', case when v_ar then 'DD/MM/YYYY HH24:MI' else 'DD Mon YYYY, HH24:MI' end);

  if p_kind = 'rfq_invite' then
    if v_ar then
      v_subj := 'طلب عرض سعر جديد: ' || v_where_ar || ' — QuotesDone';
      v_body := coalesce('السادة/ ' || v_name || ' المحترمين،', 'السادة الكرام،') || E'\n\nتحية طيبة وبعد،\n\n'
        || 'يسرّنا إفادتكم بأن أحد العملاء يطلب عروض أسعار في مجال ' || v_where_ar || '، ويتوافق طلبه مع نطاق أعمال شركتكم المسجّل لدينا. '
        || 'ويُرجى الاطّلاع على تفاصيل الطلب وتقديم عرضكم عبر بوابة الموردين:' || E'\n\n' || v_link
        || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
    else
      v_subj := 'New request for quotation: ' || v_where || ' — QuotesDone';
      v_body := coalesce('Dear ' || v_name || ',', 'Dear Sir or Madam,') || E'\n\n'
        || 'A customer is requesting quotations for ' || v_where || ', and the request matches the scope your company registered with us. '
        || 'Please review the details and submit your quotation in your supplier portal:' || E'\n\n' || v_link;
    end if;
  elsif p_kind = 'rfq_quote_reminder' then
    if v_ar then
      v_subj := 'تذكير: العميل بانتظار عرضكم — ' || v_where_ar;
      v_body := coalesce('السادة/ ' || v_name || ' المحترمين،', 'السادة الكرام،') || E'\n\nتحية طيبة وبعد،\n\n'
        || 'نودّ تذكيركم بطلب عرض السعر في مجال ' || v_where_ar || ' الذي أُرسل إليكم عبر QuotesDone، إذ لم يصلنا عرضكم بعد. '
        || 'والعميل بانتظار العروض، ونأمل تقديم عرضكم في أقرب وقت، ويُفضَّل قبل ' || v_due || ' بتوقيت دبي.'
        || E'\n\nيمكنكم تقديم عرضكم عبر بوابة الموردين:\n\n' || v_link
        || E'\n\nوفي حال عدم رغبتكم في التقدّم بعرض لهذا الطلب، يُرجى إبلاغنا بذلك عبر البوابة أو بالرد على هذه الرسالة.'
        || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
    else
      v_subj := 'Reminder: the customer is waiting for your quotation — ' || v_where;
      v_body := coalesce('Dear ' || v_name || ',', 'Dear Sir or Madam,') || E'\n\n'
        || 'This is a reminder of the request for quotation for ' || v_where || ' sent to you through QuotesDone; we have not yet received your quotation. '
        || 'The customer is waiting for quotations, and we would appreciate yours as soon as possible, ideally before ' || v_due || ' (Dubai time).'
        || E'\n\nSubmit your quotation in your supplier portal:\n\n' || v_link
        || E'\n\nIf you would rather not quote for this request, please let us know in the portal or by replying to this e-mail.';
    end if;
  elsif p_kind = 'rfq_short_of_quotes' then
    if v_ar then
      v_subj := 'مستجدات طلبكم لعروض الأسعار — ' || v_where_ar;
      v_body := coalesce('السادة/ ' || v_name || ' المحترمين،', 'عميلنا العزيز،') || E'\n\nتحية طيبة وبعد،\n\n'
        || case when v_n = 0 then 'نفيدكم بأن طلبكم في مجال ' || v_where_ar || ' لم يتلقَّ أي عرض سعر حتى الآن. '
                when v_n = 1 then 'نفيدكم بأن طلبكم في مجال ' || v_where_ar || ' تلقّى حتى الآن عرض سعر واحدًا، ونسعى إلى أن تصلكم ثلاثة عروض على الأقل للمقارنة. '
                else 'نفيدكم بأن طلبكم في مجال ' || v_where_ar || ' تلقّى حتى الآن عرضَي سعر، ونسعى إلى أن تصلكم ثلاثة عروض على الأقل للمقارنة. ' end
        || 'وقد دعونا موردين إضافيين مطابقين لطلبكم، وذكّرنا الموردين المدعوين بتقديم عروضهم، وسيبقى طلبكم مفتوحًا لاستلام العروض.'
        || E'\n\nيمكنكم متابعة العروض فور وصولها عبر بوابتكم:\n\n' || v_link
        || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
    else
      v_subj := 'An update on your request for quotations — ' || v_where;
      v_body := coalesce('Dear ' || v_name || ',', 'Dear Customer,') || E'\n\n'
        || case when v_n = 0 then 'Your request for ' || v_where || ' has not received a quotation yet. '
                when v_n = 1 then 'Your request for ' || v_where || ' has received one quotation so far; we aim for at least three for you to compare. '
                else 'Your request for ' || v_where || ' has received two quotations so far; we aim for at least three for you to compare. ' end
        || 'We have invited more suppliers who match your request, reminded the suppliers already invited, and your request stays open for quotations.'
        || E'\n\nYou can follow the quotations as they arrive in your portal:\n\n' || v_link;
    end if;
  elsif p_kind = 'reveal_outcome_check' then
    if v_ar then
      v_subj := 'هل تواصلتم مع ' || coalesce(p->>'supplier', 'المورّد') || '؟ — QuotesDone';
      v_body := coalesce('السادة/ ' || v_name || ' المحترمين،', 'عميلنا العزيز،') || E'\n\nتحية طيبة وبعد،\n\n'
        || 'مضى أسبوع على اطّلاعكم على بيانات التواصل مع ' || coalesce(p->>'supplier', 'المورّد')
        || ' بشأن طلبكم في مجال ' || v_trade_ar || '، ونودّ الاطمئنان على سير الأمور: هل تواصلتم معهم؟ وهل أُسند العمل إليهم؟'
        || E'\n\nوفي حال التعاقد معهم، يُرجى تأكيد ذلك من بوابتكم باختيار «تعاقدتُ مع هذا المورّد» على عرضهم:\n\n' || v_link
        || E'\n\nوإن لم يتواصلوا معكم، أو قرّرتم عدم المضي قدمًا، يكفي الرد على هذه الرسالة وسنتابع الأمر معكم.'
        || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
    else
      v_subj := 'Did you get in touch with ' || coalesce(p->>'supplier', 'the supplier') || '? — QuotesDone';
      v_body := coalesce('Dear ' || v_name || ',', 'Dear Customer,') || E'\n\n'
        || 'It has been a week since you revealed the contact details of ' || coalesce(p->>'supplier', 'the supplier')
        || ' for your ' || v_trade || ' request. We would like to know how it is going: have you been in touch, and did you award them the work?'
        || E'\n\nIf you hired them, please confirm it in your portal by choosing "I hired this supplier" on their quotation:\n\n' || v_link
        || E'\n\nIf they have not contacted you, or you decided not to go ahead, simply reply to this e-mail and we will follow it up with you.';
    end if;
  else
    raise exception 'fn_seat_clock_compose: unknown kind %', p_kind;
  end if;
  return jsonb_build_object('lang', v_lang, 'subject', v_subj, 'body', v_body, 'link', v_link);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_clock_customer_is_fixture(p customers)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(p.is_demo, false) or coalesce(p.full_name, '') ~* '^\s*zz\s*demo' or public.fn_is_demo_email(p.email)
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_clock_deliver(p_seat text, p_type text, p_to_role text, p_to text, p_subject_is_fixture boolean, p_lang text, p_kind text, p jsonb, p_dedupe_key text, p_inquiry_id uuid DEFAULT NULL::uuid, p_quote_id uuid DEFAULT NULL::uuid, p_lead_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare m jsonb; v jsonb; v_why text; v_key text := 'seat_clock_not_written:' || p_dedupe_key;
begin
  if public.fn_seat_clock_asked(p_dedupe_key) then return jsonb_build_object('ok', true, 'already', true); end if;
  v_why := public.fn_seat_clock_refusal(p_subject_is_fixture, p_to, p_type);
  if v_why is null then
    m := public.fn_seat_clock_compose(p_kind, p_lang, p);
    v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', p_type, 'requested_by', p_seat, 'channel', 'email', 'to_email', lower(btrim(p_to)), 'to_role', p_to_role,
      'lead_id', p_lead_id, 'inquiry_id', p_inquiry_id, 'quote_id', p_quote_id, 'lang', m->>'lang',
      'subject', m->>'subject', 'body', m->>'body', 'dedupe_key', p_dedupe_key)));
    if coalesce(v->0->>'status', '') <> 'failed' then
      return jsonb_build_object('ok', true, 'delivery', v->0, 'lang', m->>'lang');
    end if;
    v_why := 'the delivery request failed: ' || coalesce(v->0->>'error', 'no error recorded');
  end if;
  -- A SKIP IS RECORDED, NEVER ONLY COUNTED: one finding per message, owned by the seat that wanted to send
  -- it. An opt-out is the recipient's own choice (instruction 632) -- recorded and closed at once, so it is
  -- on the ledger without paging anybody; anything else stays open for the seat to act on. The same opt-out
  -- seen again on the next tick is already on the ledger and is not re-written.
  if v_why like 'opted out%' and exists (select 1 from public.it_engineer_finding
                                          where issue_key = v_key and closed_at is not null and evidence->>'reason' = v_why) then
    return jsonb_build_object('ok', false, 'reason', v_why, 'recorded_as', v_key);
  end if;
  perform public.fn_it_engineer_finding_upsert(v_key,
    left('Not sent (' || p_type || ' to the ' || p_to_role || '): ' || v_why, 300),
    'seat clock ' || p_seat || ' -> fn_seat_clock_deliver', case when v_why like 'opted out%' then 'agent_facing' else 'customer_facing' end, 1,
    jsonb_build_object('type', p_type, 'to_role', p_to_role, 'reason', v_why, 'dedupe_key', p_dedupe_key,
                       'inquiry_id', p_inquiry_id, 'quote_id', p_quote_id, 'lead_id', p_lead_id,
                       'owner_seat', p_seat, 'duty', 'seat_clock', 'demo', p_subject_is_fixture),
    '{}'::text[], '{}'::text[], p_seat);
  if v_why like 'opted out%' then
    perform public.fn_it_engineer_finding_close(v_key, 'recorded: the recipient opted out of this kind of mail, which is the rule (instruction 632)');
  end if;
  return jsonb_build_object('ok', false, 'reason', v_why, 'recorded_as', v_key);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_clock_lead_is_fixture(p leads)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(p.is_demo, false) or coalesce(p.company_name, '') ~* '^\s*zz\s*demo'
      or public.fn_is_demo_email(p.email) or public.fn_is_demo_email(p.claimed_by)
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_clock_policy(p_key text, p_default numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((select case when jsonb_typeof(value) = 'number' then (value #>> '{}')::numeric end
                     from public.decision_policy where key = p_key), p_default)
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_clock_refusal(p_subject_is_fixture boolean, p_to text, p_type text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_e text := lower(btrim(coalesce(p_to, ''))); v_reason text;
begin
  if v_e !~ '^[a-z0-9._%+-]+@[a-z0-9.-]+[.][a-z]{2,}$' then return 'no valid address'; end if;
  if p_subject_is_fixture then
    return case when public.fn_is_demo_email(v_e) then null else 'a fixture subject may not write to a real address' end;
  end if;
  if public.fn_is_demo_email(v_e) then return 'a real subject may not write to a fixture address'; end if;
  if v_e in (select lower(btrim(x)) from public.app_secrets s, unnest(string_to_array(coalesce(s.value, ''), ',')) x
              where s.key = 'admin_emails') then return 'the founder is never addressed by a seat clock'; end if;
  select s.reason into v_reason from public.email_suppressions s
   where lower(s.email) = v_e and public.fn_suppression_stops(s.reason, p_type) limit 1;
  if found then
    return case when lower(btrim(coalesce(v_reason, ''))) = 'unsubscribe' then 'opted out (unsubscribe) of ' || p_type
                else 'suppressed: ' || coalesce(v_reason, 'no reason recorded') end;
  end if;
  if exists (select 1 from public.email_domain_mx m where m.domain = split_part(v_e, '@', 2)
              and m.has_mx = false and m.kind in ('nxdomain', 'no_records')) then return 'the domain does not accept mail'; end if;
  select b.reason into v_reason from public.email_block_pattern b where b.active and v_e ~ b.pattern limit 1;
  if found then return 'blocked: ' || coalesce(v_reason, 'block pattern'); end if;
  return null;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_clocks_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_out jsonb := '{}'::jsonb; v jsonb; k text; v_ok boolean := true;
begin
  foreach k in array array['complaints', 'short_quotes', 'reveal_outcome', 'reply_watch', 'human_requests', 'portfolio_reminder'] loop
    begin
      v := case k when 'complaints' then public.fn_complaint_clock_tick(false)
                  when 'short_quotes' then public.fn_rfq_short_of_quotes_tick(false)
                  when 'reveal_outcome' then public.fn_reveal_outcome_check_tick(false)
                  when 'reply_watch' then public.fn_support_reply_watch_tick()
                  when 'portfolio_reminder' then public.fn_supplier_portfolio_reminder_tick(false)
                  else public.fn_wa_human_request_tick() end;
    exception when others then
      v := jsonb_build_object('ok', false, 'error', left(sqlerrm, 300));
    end;
    v_ok := v_ok and coalesce((v->>'ok')::boolean, false);
    v_out := v_out || jsonb_build_object(k, v);
  end loop;
  return jsonb_build_object('ok', v_ok) || v_out;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_deliberation_acts_on_handoff(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions; v_did bigint; v jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  v_did := nullif(a.detail->>'deliberation_id', '')::bigint;
  if v_did is null then raise exception 'handoff % names no deliberation', p_id; end if;
  -- open() sets handoff_id after fn_seat_handoff returns; the step below does not need it.
  v := public.fn_seat_deliberation_step(v_did);
  return jsonb_build_object('waiting', a.agent || '''s independent review (blind pass, then comparison), then '
                                       || (a.detail->>'from') || ' closes', 'deliberation_id', v_did, 'step', v);
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_deliberation_blind_payload(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.seat_deliberation; v jsonb;
begin
  select * into d from public.seat_deliberation where id = p_id;
  if not found then raise exception 'no seat_deliberation %', p_id; end if;
  -- Built from named columns only. The proposal column is read below solely to prove it is absent.
  v := jsonb_build_object(
    'phase', 'blind', 'deliberation_id', d.id, 'kind', d.kind,
    'author_seat', d.author_seat, 'reviewer_seat', d.reviewer_seat,
    'question', d.question, 'evidence', d.evidence,
    'independent_context', public.fn_seat_deliberation_independent_context(d.reviewer_seat),
    'instructions', 'You are the ' || d.reviewer_seat || ' seat. You have NOT seen what the ' || d.author_seat
      || ' seat proposes, on purpose. Answer the question from the evidence and the independent context alone. '
      || 'verdict: approve = proceed as the question asks; reject = do not; revise = proceed only with changes you name. '
      || 'Give the strongest case AGAINST your own verdict in steelman_against, even if you approve. Agree only if it is right.',
    'output_contract', jsonb_build_object('verdict', 'approve|reject|revise', 'recommendation', 'text',
      'reasoning', 'text', 'steelman_against', 'text, at least one full sentence'));
  if v ? 'proposal' or public.fn_seat_deliberation_proposal_leak(d.proposal, public.fn_seat_deliberation_strings(v)) is not null then
    raise exception 'BLIND_PASS_LEAK: the blind payload for deliberation % carries the proposal (was it pasted into the question or the evidence?)', p_id;
  end if;
  return v;
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_deliberation_budget(p_author_seat text, p_reviewer_seat text, p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object('ok', true, 'dept', c.dept_key, 'spent_aed', s.spent,
           'why', 'reviews ' || p_author_seat || ' -> ' || p_reviewer_seat || ' spent AED ' || s.spent
                  || ' this month' || coalesce(' (' || c.dept_key || ')', '') || '; no limit (founder_instruction 987)')
    from (select 1) one
    left join public.seat_deliberation_ceiling c on c.author_seat = p_author_seat and c.reviewer_seat = p_reviewer_seat
    left join lateral (select coalesce(sum(l.cost_aed), 0) spent from public.ai_cost_log l
                        where l.task_class in ('seat_deliberation_blind', 'seat_deliberation_compare') and l.agent_key = p_reviewer_seat
                          and l.occurred_at >= (date_trunc('month', p_at at time zone 'Asia/Dubai') at time zone 'Asia/Dubai')) s on true
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_deliberation_close(p_id bigint, p_closed_by text, p_outcome text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.seat_deliberation; c public.seat_deliberation_turn;
begin
  select * into d from public.seat_deliberation where id = p_id for update;
  if not found then raise exception 'no seat_deliberation %', p_id; end if;
  if p_closed_by is distinct from d.author_seat then
    raise exception 'only the originating seat % closes deliberation %', d.author_seat, p_id;
  end if;
  if d.status not in ('reviewed', 'no_independent_reviewer') or coalesce(btrim(p_outcome), '') = '' then
    raise exception 'deliberation % closes after the review (or its escalation), with an outcome', p_id;
  end if;
  select * into c from public.seat_deliberation_turn t
   where t.deliberation_id = p_id and t.phase = 'compare' and t.status = 'recorded' order by t.round desc limit 1;
  update public.seat_deliberation set status = 'closed', outcome = p_outcome, closed_at = now() where id = p_id;
  if d.handoff_id is not null then
    -- trg_handoff_only_originator_closes: the author seat names itself, only for this transaction.
    perform set_config('qd.handoff_closer', d.author_seat, true);
    perform public.fn_seat_handoff_complete(d.handoff_id, jsonb_build_object('kind', 'deliberation.review', 'deliberation_id', p_id,
      'final_verdict', c.verdict, 'reviewer_model', c.model, 'reviewer_provider', c.provider,
      'ended', d.status, 'outcome', p_outcome, 'closed_by', p_closed_by));
  end if;
  return jsonb_build_object('ok', true, 'deliberation_id', p_id, 'final_verdict', c.verdict, 'ended', d.status);
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_deliberation_compare_payload(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.seat_deliberation; b public.seat_deliberation_turn;
begin
  select * into d from public.seat_deliberation where id = p_id;
  if not found then raise exception 'no seat_deliberation %', p_id; end if;
  select * into b from public.seat_deliberation_turn t
   where t.deliberation_id = p_id and t.phase = 'blind' and t.status = 'recorded' order by t.round desc limit 1;
  if not found then
    raise exception 'BLIND_FIRST: deliberation % has no recorded blind verdict; the proposal is not revealed before it', p_id;
  end if;
  return jsonb_build_object(
    'phase', 'compare', 'deliberation_id', d.id, 'kind', d.kind, 'round', d.round,
    'author_seat', d.author_seat, 'reviewer_seat', d.reviewer_seat,
    'question', d.question, 'evidence', d.evidence,
    'independent_context', public.fn_seat_deliberation_independent_context(d.reviewer_seat),
    'your_blind_verdict', jsonb_build_object('verdict', b.verdict, 'steelman_against', b.steelman_against, 'output', b.output),
    'proposal', d.proposal,
    'instructions', 'The ' || d.author_seat || ' seat''s proposal is now revealed. Compare it with YOUR blind verdict above. '
      || 'State explicitly what you agree with and what you do not (write "none" if there is nothing). Give the strongest '
      || 'case AGAINST the proposal even if you approve; an approval without it is rejected as malformed. Do not agree '
      || 'because the proposal is confident, and do not disagree for its own sake.'
      || case when d.reviewer_seat = 'ceo' and d.kind <> 'marketing.monthly_plan'
              then ' As the chief executive your verdict is a decision: when you approve, your agreements are its logic; when you '
                || 'revise or reject, your disagreements are its reasons and go back to the ' || d.author_seat || ' seat to answer '
                || 'in a revised version. Write that side as at least one full sentence, never "none"; a decision without reasons is refused.'
              else '' end,
    'output_contract', jsonb_build_object('verdict', 'approve|reject|revise', 'agreements', 'text', 'disagreements', 'text',
      'steelman_against', 'text, at least one full sentence', 'reasoning', 'text',
      'changed_from_blind_because', 'text, or "unchanged"'));
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_deliberation_due(p_limit integer DEFAULT 3)
 RETURNS SETOF bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select d.id from public.seat_deliberation d
   where d.status = 'open'
     and (select count(*) from public.seat_deliberation_turn t
           where t.deliberation_id = d.id and t.round = d.round and t.status = 'failed') < 3
   order by (select max(t.created_at) from public.seat_deliberation_turn t
              where t.deliberation_id = d.id and t.phase <> 'proposal') asc nulls first, d.id
   limit greatest(p_limit, 0);
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_deliberation_independent_context(p_reviewer_seat text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_m0 date := date_trunc('month', now() at time zone 'Asia/Dubai')::date;
  v_f jsonb := public.fn_ceo_plan_funnel();
  v_mtd jsonb := v_f->'month_to_date';
  r numeric;
begin
  return jsonb_build_object(
    'assembled_by', 'fn_seat_deliberation_independent_context for the reviewing seat ' || p_reviewer_seat
                    || '; the author did not supply, filter or see this',
    'assembled_at', now(),
    'plan_targets', (select coalesce(jsonb_agg(to_jsonb(p) - 'updated_at' order by p.month), '[]'::jsonb)
                       from public.ceo_plan_month p where p.month in (v_m0, (v_m0 + interval '1 month')::date)),
    'funnel', v_f,
    'funnel_drop_offs', jsonb_build_object(
      'registered_per_invite',   round((v_mtd->>'registrations_submitted')::numeric / nullif((v_mtd->>'invitations_delivered')::numeric, 0), 4),
      'verified_per_registered', round((v_mtd->>'registrations_verified')::numeric  / nullif((v_mtd->>'registrations_submitted')::numeric, 0), 4),
      'reveals_per_inquiry',     round((v_mtd->>'reveals_paid')::numeric            / nullif((v_mtd->>'inquiries_posted')::numeric, 0), 4),
      'note', 'month to date; null where the denominator is zero'),
    'supplier_gap_by_trade', (select coalesce(jsonb_agg(to_jsonb(g) order by g.gap_to_target desc, g.sendable_shortfall desc), '[]'::jsonb)
                                from (select slug, name, approved, gap_to_target, sendable, invited, sendable_shortfall, status
                                        from public.v_supply_gap where status <> 'TARGET MET'
                                       order by gap_to_target desc, sendable_shortfall desc limit 12) g),
    'supplier_gap_totals', (select jsonb_build_object('trades', count(*),
                                     'target_met', count(*) filter (where status = 'TARGET MET'),
                                     'no_pool', count(*) filter (where status like 'NO POOL%'),
                                     'pool_too_thin', count(*) filter (where status like 'POOL TOO THIN%'))
                              from public.v_supply_gap));
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_deliberation_norm(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select btrim(regexp_replace(lower(coalesce(p, '')), '[^a-z0-9\u0600-\u06ff]+', ' ', 'g'))
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_deliberation_open(p_kind text, p_author_seat text, p_reviewer_seat text, p_question text, p_evidence jsonb, p_proposal jsonb, p_author_model text, p_author_task_class text DEFAULT NULL::text, p_subject_table text DEFAULT NULL::text, p_subject_id text DEFAULT NULL::text, p_demo boolean DEFAULT false)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint; v_h bigint; v_leak text; v_last text;
begin
  if not exists (select 1 from public.seat_handoff_kind k
                  where k.type = 'deliberation.review' and k.from_seat = p_author_seat and k.to_seat = p_reviewer_seat) then
    raise exception 'no deliberation.review conversation from % to % in seat_handoff_kind: register the pair in the file of the build that starts it',
      p_author_seat, p_reviewer_seat;
  end if;
  v_leak := public.fn_seat_deliberation_proposal_leak(p_proposal, coalesce(p_question, '') || ' ' || public.fn_seat_deliberation_strings(p_evidence));
  if v_leak is not null then
    raise exception 'BLIND_PASS_LEAK: the question or the evidence carries the proposal ("%"); the reviewer would not be blind', v_leak;
  end if;
  -- THE AUTHOR'S MODEL IS A MEASUREMENT, NOT A CLAIM: ai_gateway logged a call by this seat on this model in the
  -- last 24 hours, or the family the reviewer must avoid is unproven. Only a ZZ DEMO deliberation is exempt.
  -- The seat's LATEST successful call on the class that wrote the proposal must be on p_author_model.
  -- A decision taken by code ('deterministic') has no model call to prove (29 Sep 2026, instruction 1009).
  if not (coalesce(p_demo, false) and p_question like 'ZZ DEMO%') and p_author_model is distinct from 'deterministic' then
    if coalesce(btrim(p_author_task_class), '') = '' then
      raise exception 'AUTHOR_MODEL_UNPROVEN: name the task class the proposal was written on (p_author_task_class)';
    end if;
    select l.model_used into v_last from public.ai_cost_log l
     where l.ok and l.task_class = p_author_task_class and l.occurred_at > now() - interval '24 hours'
       and (l.agent_key = p_author_seat or l.seat = p_author_seat)
     order by l.occurred_at desc, l.id desc limit 1;
    if v_last is distinct from p_author_model then
      raise exception 'AUTHOR_MODEL_UNPROVEN: the latest successful % call by % in the last 24 hours was on %, not %',
        p_author_task_class, p_author_seat, coalesce(v_last, 'nothing'), p_author_model;
    end if;
  end if;
  insert into public.seat_deliberation (kind, author_seat, reviewer_seat, question, evidence, proposal, author_model,
                                        author_provider, subject_table, subject_id, demo)
  values (p_kind, p_author_seat, p_reviewer_seat, p_question, p_evidence, p_proposal, p_author_model, '?',
          p_subject_table, p_subject_id, coalesce(p_demo, false))
  returning id into v_id;
  insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, task_class, model, output)
  values (v_id, 1, 'proposal', p_author_seat, 'recorded', p_author_task_class, p_author_model, p_proposal);

  v_h := public.fn_seat_handoff(p_author_seat, p_reviewer_seat, 'deliberation.review', 'seat_deliberation', v_id::text,
           jsonb_build_object('deliberation_id', v_id, 'kind', p_kind, 'demo', coalesce(p_demo, false),
                              'question', left(p_question, 300)));
  update public.seat_deliberation set handoff_id = v_h where id = v_id;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_deliberation_proposal_leak(p_proposal jsonb, p_haystack text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_hay text := ' ' || public.fn_seat_deliberation_norm(p_haystack) || ' '; s text; n text; j jsonb; v text;
begin
  for s in select x #>> '{}' from jsonb_path_query(coalesce(p_proposal, 'null'::jsonb), 'strict $.**') x
            where jsonb_typeof(x) = 'string' loop
    n := public.fn_seat_deliberation_norm(s);
    if length(n) >= 24 and strpos(v_hay, ' ' || n || ' ') > 0 then return left(n, 80); end if;
    if btrim(s) ~ '^[\[{"]' then
      begin j := s::jsonb; exception when others then j := null; end;
      if j is not null then
        v := public.fn_seat_deliberation_proposal_leak(j, p_haystack);
        if v is not null then return v; end if;
      end if;
    end if;
  end loop;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_deliberation_record(p_id bigint, p_phase text, p_model text, p_output jsonb, p_prompt_tokens integer DEFAULT NULL::integer, p_output_tokens integer DEFAULT NULL::integer, p_status text DEFAULT 'recorded'::text, p_why text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.seat_deliberation; v_id bigint; o jsonb := coalesce(p_output, '{}'::jsonb); v_verdict text; v_reasons text;
begin
  select * into d from public.seat_deliberation where id = p_id for update;
  if not found then raise exception 'no seat_deliberation %', p_id; end if;
  if d.status <> 'open' then raise exception 'seat_deliberation % is %, not open', p_id, d.status; end if;
  if p_phase not in ('blind', 'compare') then raise exception 'only the reviewer''s blind and compare turns are recorded here'; end if;
  -- A gateway that held the call after the step did not: "held, not run" is recorded once per round and phase.
  if p_status = 'held_not_run' then
    select t.id into v_id from public.seat_deliberation_turn t where t.deliberation_id = p_id and t.round = d.round
       and t.phase = p_phase and t.status = 'held_not_run';
    if v_id is not null then return v_id; end if;
  end if;

  insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, task_class, model, verdict,
    steelman_against, agreements, disagreements, output, why, prompt_tokens, output_tokens, payload_sha256)
  values (p_id, d.round, p_phase, d.reviewer_seat, p_status, 'seat_deliberation_' || p_phase, p_model,
          case when p_status = 'recorded' then lower(o->>'verdict') end,
          case when jsonb_typeof(o->'steelman_against') = 'string' then o->>'steelman_against' end, o->>'agreements', o->>'disagreements', o, p_why, p_prompt_tokens, p_output_tokens,
          o->>'_payload_sha256')
  returning id into v_id;

  if p_status = 'recorded' and p_phase = 'compare' then
    update public.seat_deliberation set status = 'reviewed' where id = p_id;
    update public.agent_actions
       set evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('deliberation_id', p_id, 'round', d.round,
                        'verdict', lower(o->>'verdict'), 'compare_turn_id', v_id, 'reviewed_at', now()),
           detail = detail || jsonb_build_object('awaiting', d.author_seat || ' closes the deliberation')
     where id = d.handoff_id and kind = 'handoff';
    perform public.fn_seat_handoff_event(d.handoff_id, 'reviewed');
    -- THE CEO'S DECISION CARRIES ITS REASONS AND A REJECTION LOOPS BACK (founder_instruction 1059).
    if d.reviewer_seat = 'ceo' and d.kind <> 'marketing.monthly_plan' then
      v_verdict := lower(o->>'verdict');
      -- the reasons are the side the verdict rests on, with the CEO's own reasoning when that side is too thin
      v_reasons := btrim(coalesce(case when v_verdict = 'approve' then o->>'agreements' else o->>'disagreements' end, ''));
      if public.fn_ceo_reasons_problem(v_reasons) is not null and coalesce(btrim(o->>'reasoning'), '') <> '' then
        v_reasons := btrim(v_reasons || E'\n' || (o->>'reasoning'));
      end if;
      perform public.fn_ceo_decide('seat_deliberation', 'seat_deliberation:' || p_id, d.author_seat,
        case when v_verdict = 'approve' then 'approved' else 'rejected' end,
        v_reasons,
        jsonb_build_object('deliberation_id', p_id, 'kind', d.kind, 'round', d.round, 'verdict', v_verdict, 'compare_turn_id', v_id,
                           'subject_table', d.subject_table, 'subject_id', d.subject_id, 'question', left(d.question, 1000),
                           'proposal', case when length(d.proposal::text) <= 20000 then d.proposal
                                            else jsonb_build_object('cut_at_20000_chars', left(d.proposal::text, 20000)) end),
        'seat_deliberation_turn', v_id::text);
    end if;
  end if;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_deliberation_revise(p_id bigint, p_proposal jsonb, p_author_model text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.seat_deliberation; v_last text;
begin
  select * into d from public.seat_deliberation where id = p_id for update;
  if not found then raise exception 'no seat_deliberation %', p_id; end if;
  select t.verdict into v_last from public.seat_deliberation_turn t
   where t.deliberation_id = p_id and t.phase = 'compare' and t.status = 'recorded' and t.round = d.round;
  -- A CEO rejection is sent back to be revised (founder_instruction 1059); another seat's reject stays final (the
  -- accountant's second-seat refusal of a CEO money decision is not something the CEO re-argues round after round).
  if d.status <> 'reviewed' or not (v_last = 'revise' or (v_last = 'reject' and d.reviewer_seat = 'ceo')) or v_last is null then
    raise exception 'deliberation % can be revised only after the reviewer asked for a revision (or the CEO rejected it)', p_id;
  end if;
  if d.round >= d.max_rounds then
    raise exception 'deliberation % is at its last round (%); the author closes it with the reviewer''s verdict', p_id, d.max_rounds;
  end if;
  update public.seat_deliberation set round = round + 1, proposal = p_proposal, status = 'open' where id = p_id;
  insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, model, output)
  values (p_id, d.round + 1, 'proposal', d.author_seat, 'recorded', p_author_model, p_proposal);
  return public.fn_seat_deliberation_step(p_id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_deliberation_step(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  d public.seat_deliberation; a public.seat_deliberation_turn;
  v_phase text; v_class text; v_route jsonb; v_gate jsonb; v_payload jsonb; v_sha text; v_budget jsonb;
begin
  select * into d from public.seat_deliberation where id = p_id for update;
  if not found then raise exception 'no seat_deliberation %', p_id; end if;
  if d.status <> 'open' then return jsonb_build_object('action', 'none', 'status', d.status); end if;

  if not exists (select 1 from public.seat_deliberation_turn t where t.deliberation_id = p_id and t.phase = 'blind' and t.status = 'recorded') then
    v_phase := 'blind';
  elsif not exists (select 1 from public.seat_deliberation_turn t where t.deliberation_id = p_id and t.phase = 'compare'
                       and t.status = 'recorded' and t.round = d.round) then
    v_phase := 'compare';
  else
    return jsonb_build_object('action', 'none', 'status', d.status, 'why', 'round ' || d.round || ' is already compared');
  end if;
  v_class := 'seat_deliberation_' || v_phase;

  select * into a from public.seat_deliberation_turn t
   where t.deliberation_id = p_id and t.phase = 'proposal' and t.status = 'recorded' and t.round <= d.round
   order by t.round desc, t.id desc limit 1;

  -- THE PAIR'S CEILING comes first: a spent ceiling is held exactly like the founder's hold, before any routing.
  v_budget := public.fn_seat_deliberation_budget(d.author_seat, d.reviewer_seat);
  if not coalesce((v_budget->>'ok')::boolean, false) then
    insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, task_class, reviews_turn_id, why)
    values (p_id, d.round, v_phase, d.reviewer_seat, 'held_not_run', v_class, a.id, 'held, not run: pair_ceiling - ' || (v_budget->>'why'))
    on conflict (deliberation_id, round, phase) where status in ('held_not_run', 'no_independent_reviewer') do nothing;
    return jsonb_build_object('action', 'held', 'phase', v_phase, 'why', v_budget->>'why');
  end if;
  v_route := public.fn_ai_route_review(v_class, a.model, d.reviewer_seat, 'seat_deliberation', v_budget->>'dept');

  if coalesce((v_route->>'no_independent_reviewer')::boolean, false) then
    insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, task_class, reviews_turn_id, why)
    values (p_id, d.round, v_phase, d.reviewer_seat, 'no_independent_reviewer', v_class, a.id, v_route->>'why')
    on conflict (deliberation_id, round, phase) where status in ('held_not_run', 'no_independent_reviewer') do nothing;
    update public.seat_deliberation set status = 'no_independent_reviewer' where id = p_id;
    -- ESCALATE: the monitor duty carries it to the CEO and, through it_founder_decision_class, the founder.
    perform public.fn_it_deliberation_independence_watch(d.demo);
    return jsonb_build_object('action', 'escalated', 'phase', v_phase, 'why', v_route->>'why', 'route', v_route);
  end if;

  if not coalesce((v_route->>'use_llm')::boolean, false) then
    insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, task_class, reviews_turn_id, why)
    values (p_id, d.round, v_phase, d.reviewer_seat, 'held_not_run', v_class, a.id, 'held, not run: ' || coalesce(v_route->>'why', 'the router refused'))
    on conflict (deliberation_id, round, phase) where status in ('held_not_run', 'no_independent_reviewer') do nothing;
    return jsonb_build_object('action', 'held', 'phase', v_phase, 'why', v_route->>'why');
  end if;

  v_payload := case v_phase when 'blind' then public.fn_seat_deliberation_blind_payload(p_id)
                            else public.fn_seat_deliberation_compare_payload(p_id) end;
  v_sha := encode(sha256(convert_to(v_payload::text, 'UTF8')), 'hex');

  v_gate := public.fn_kernel_paid_provider_gate(v_route->>'model');
  if not coalesce((v_gate->>'allowed')::boolean, false) then
    insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, task_class, model, reviews_turn_id, payload_sha256, why)
    values (p_id, d.round, v_phase, d.reviewer_seat, 'held_not_run', v_class, v_route->>'model', a.id, v_sha,
            'held, not run: ' || coalesce(v_gate->>'rule', '?') || ' - ' || coalesce(v_gate->>'reason', ''))
    on conflict (deliberation_id, round, phase) where status in ('held_not_run', 'no_independent_reviewer') do nothing;
    return jsonb_build_object('action', 'held', 'phase', v_phase, 'model', v_route->>'model', 'why', v_gate->>'reason');
  end if;

  -- A DEMO DELIBERATION NEVER REACHES A PAID MODEL, hold or no hold.
  if d.demo then
    insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, task_class, model, reviews_turn_id, payload_sha256, why)
    values (p_id, d.round, v_phase, d.reviewer_seat, 'held_not_run', v_class, v_route->>'model', a.id, v_sha, 'held, not run: demo deliberation')
    on conflict (deliberation_id, round, phase) where status in ('held_not_run', 'no_independent_reviewer') do nothing;
    return jsonb_build_object('action', 'held', 'phase', v_phase, 'why', 'demo deliberation');
  end if;
  return jsonb_build_object('action', 'call_model', 'deliberation_id', p_id, 'phase', v_phase, 'round', d.round,
    'task_class', v_class, 'model', v_route->>'model', 'fallback', v_route->>'fallback',
    'counterpart_model', a.model, 'max_tokens', (v_route->>'max_tokens')::int,
    'reviewer_seat', d.reviewer_seat, 'dept', v_budget->>'dept', 'budget', v_budget,
    'payload', v_payload, 'payload_sha256', v_sha,
    'system', 'You are the ' || d.reviewer_seat || ' seat of Quotes Done reviewing work from the ' || d.author_seat
              || ' seat. Reply with ONE JSON object matching output_contract and nothing else.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_deliberation_strings(p jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(string_agg(x #>> '{}', ' '), '') from jsonb_path_query(coalesce(p, 'null'::jsonb), 'strict $.**') x
   where jsonb_typeof(x) = 'string'
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_deliberation_withdraw(p_id bigint, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.seat_deliberation; v_gone boolean; v_fixture boolean; v_id text;
begin
  select * into d from public.seat_deliberation where id = p_id for update;
  if not found then raise exception 'no seat_deliberation %', p_id; end if;
  if d.status <> 'open' then return jsonb_build_object('ok', false, 'reason', 'deliberation ' || p_id || ' is ' || d.status); end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'a withdrawal states its reason'; end if;
  v_id := split_part(coalesce(d.subject_id, ''), ':', 1);
  v_fixture := public.fn_deliberation_subject_is_fixture(d.subject_table, d.subject_id);
  v_gone := case d.subject_table
              when 'inquiries' then not exists (select 1 from public.inquiries i where i.id::text = v_id)
              when 'refunds'   then not exists (select 1 from public.refunds r where r.id::text = v_id)
              when 'quotes'    then not exists (select 1 from public.quotes q where q.id::text = v_id)
              else false end;
  if not (v_fixture or v_gone) then
    raise exception 'deliberation % is about a live, real subject (%:%): only a fixture or a vanished subject is withdrawn',
      p_id, d.subject_table, d.subject_id;
  end if;
  update public.seat_deliberation set status = 'closed', closed_at = now(),
         outcome = 'withdrawn before review: ' || left(p_reason, 400) where id = p_id;
  if d.handoff_id is not null then
    perform set_config('qd.handoff_closer', d.author_seat, true);
    perform public.fn_seat_handoff_complete(d.handoff_id, jsonb_build_object('kind', 'deliberation.review', 'deliberation_id', p_id,
      'ended', 'withdrawn', 'outcome', left(p_reason, 400), 'closed_by', d.author_seat,
      'subject_fixture', v_fixture, 'subject_gone', v_gone));
  end if;
  return jsonb_build_object('ok', true, 'deliberation_id', p_id, 'subject_fixture', v_fixture, 'subject_gone', v_gone);
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_duties_tick(p_limit integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.seat_duty; v_out jsonb := '[]'::jsonb; v_health jsonb; p jsonb; k record;
        v_t0 timestamptz := clock_timestamp(); v_ms integer;
begin
  -- A duty never measured gets its own job before anything else: it may be the 9 s one.
  perform public.fn_seat_duty_isolate(sd.duty) from public.seat_duty sd where sd.enabled and not sd.own_job and sd.avg_ms is null;
  -- Up to greatest(30, least(p_limit, 60)) candidates, the most overdue first; fn_seat_duty_run locks each.
  for d in
    select sd.* from public.seat_duty sd
     where enabled and not own_job and avg_ms is not null
       -- ONE PAUSE SWITCH (29 Sep 2026): a duty public.duty_pause names is not started.
       and not exists (select 1 from public.duty_pause dp where dp.duty = sd.duty)
       -- two minutes of tolerance, the same reasoning as fn_resilience_tick_plan: a tick is never exactly on the beat
       and (last_started_at is null or now() - last_started_at >= every - interval '2 minutes')
     order by last_started_at + every nulls first, duty
     limit greatest(30, least(coalesce(p_limit, 8), 60))
  loop
    -- NEVER START A DUTY THAT WILL NOT FIT (18 Oct 2026): nothing starts after 1.5 s, and a duty starts only if
    -- 1.5x its measured time ends before 4 s. The tick is one statement under an 8 s timeout no handler can catch.
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
    exit when v_ms > 1500;
    continue when v_ms + d.avg_ms * 1.5 > 4000;
    v_out := v_out || public.fn_seat_duty_run(d.duty);
  end loop;

  -- The check, every tick: each problem is a finding; a duty that recovered closes its own.
  v_health := public.fn_seat_duty_health();
  for p in select * from jsonb_array_elements(v_health) loop
    -- a paused duty is overdue on purpose; it is not a finding while the pause stands
    continue when exists (select 1 from public.duty_pause dp where dp.duty = p->>'duty');
    perform public.fn_it_engineer_finding_upsert(
      'seat_duty:' || (p->>'duty'),
      'Seat duty ' || (p->>'duty') || ' is not being done: ' || (p->>'problem'),
      'public.seat_duty / ' || coalesce(p->>'routine', '?'), 'agent_facing', 1, p,
      '{}'::text[], array['why the routine fails or is not reached'], 'it_engineer');
  end loop;
  update public.it_engineer_finding f
     set closed_at = now(), close_note = 'the duty is no longer overdue or failing: it ran on its clock again, or it was disabled or paused (fn_seat_duties_tick)'
   where f.issue_key like 'seat_duty:%' and f.closed_at is null
     and (not exists (select 1 from jsonb_array_elements(v_health) h where 'seat_duty:' || (h->>'duty') = f.issue_key)
          or exists (select 1 from public.duty_pause dp where 'seat_duty:' || dp.duty = f.issue_key));

  -- SKIPPED BECAUSE ITS ROW WAS LOCKED (19 Oct 2026): raised once the streak is longer than two of its intervals.
  for k in select s.duty, s.skips, s.first_skipped_at, sd.every from public.seat_duty_skip s
             join public.seat_duty sd on sd.duty = s.duty
            where now() - s.first_skipped_at > 2 * sd.every loop
    perform public.fn_it_engineer_finding_upsert(
      'seat_duty_skipped:' || k.duty,
      'Seat duty ' || k.duty || ' is skipped: its row was locked by another transaction ' || k.skips || ' times since ' || k.first_skipped_at,
      'public.fn_seat_duty_run (for update skip locked)', 'agent_facing', 1,
      jsonb_build_object('duty', k.duty, 'skips', k.skips, 'first_skipped_at', k.first_skipped_at, 'every', k.every),
      '{}'::text[], array['which transaction holds the seat_duty row (pg_locks), and why it holds it that long'], 'it_engineer');
  end loop;
  update public.it_engineer_finding f
     set closed_at = now(), close_note = 'the duty ran again: no skip streak is open (fn_seat_duties_tick)'
   where f.issue_key like 'seat_duty_skipped:%' and f.closed_at is null
     and not exists (select 1 from public.seat_duty_skip s where 'seat_duty_skipped:' || s.duty = f.issue_key);

  return jsonb_build_object('ran', v_out, 'problems', jsonb_array_length(v_health),
                            'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_duty_cross_review(p_kind text, p_author text, p_reviewer text, p_question text, p_evidence jsonb, p_proposal jsonb, p_result jsonb, p_subject_table text, p_subject_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint; v_demo boolean := coalesce(p_question like 'ZZ DEMO%', false);
begin
  v_id := public.fn_seat_deliberation_open(p_kind, p_author, p_reviewer, p_question, p_evidence, p_proposal,
            coalesce(nullif(p_result->>'model', ''), 'unknown'), 'internal_judgement' /* 1056: think()'s decision class */, p_subject_table, p_subject_id, v_demo);
  return jsonb_build_object('deliberation_id', v_id, 'reviewer', p_reviewer);
exception when others then
  -- Recorded for the CEO to see, never raised: the decision it reviews has already been applied or held.
  perform public.fn_it_engineer_finding_upsert('cross_review:' || p_kind || ':' || coalesce(p_subject_id, '?'),
    'A cross-family review could not be opened for ' || p_kind, 'public.fn_seat_duty_cross_review', 'agent_facing', 1,
    jsonb_build_object('error', left(sqlerrm, 500), 'author', p_author, 'reviewer', p_reviewer, 'owner_seat', 'ceo'),
    '{}'::text[], array['whether the author model was proven and the pair registered'], p_author);
  return jsonb_build_object('deliberation_id', null, 'error', left(sqlerrm, 300));
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_duty_health()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('duty', d.duty, 'owner_seat', d.owner_seat, 'routine', d.routine,
           'problem', x.problem, 'last_ok_at', d.last_ok_at, 'failures', d.failures, 'last_error', d.last_error)
           order by d.duty), '[]'::jsonb)
    from public.seat_duty d
    cross join lateral (select case
        when not public.fn_seat_duty_routine_exists(d.routine) then 'its routine public.' || d.routine || '() does not exist'
        when not exists (select 1 from public.org_role r where r.role_id = d.owner_seat and r.status = 'active')
          then 'its owner ' || d.owner_seat || ' is not an active seat'
        when d.failures >= 3 then 'failed ' || d.failures || ' times running: ' || coalesce(left(d.last_error, 200), '?')
        -- overdue: no success within twice the interval plus one 15-minute tick (a new row gets the same grace)
        when coalesce(d.last_ok_at, d.created_at) < now() - (2 * d.every) - interval '15 minutes'
          then 'no successful run since ' || coalesce(to_char(d.last_ok_at, 'YYYY-MM-DD HH24:MI'), 'it was registered')
      end as problem) x
   where d.enabled and x.problem is not null;
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_duty_isolate(p_duty text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  update public.seat_duty set own_job = true where duty = p_duty;
  if not found then raise exception 'no seat duty %', p_duty; end if;
  return cron.schedule('seat_duty:' || p_duty, '*/5 * * * *',
    format($c$set statement_timeout = '60s'; select public.fn_seat_duty_run(%L);$c$, p_duty));
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_duty_reason(p_seat text, p_surface text, p_question text, p_options jsonb, p_case jsonb, p_subject jsonb, p_dedupe_key text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if split_part(p_surface, '.', 1) <> p_seat then
    raise exception 'a duty''s decision point belongs to its seat: % is not %''s', p_surface, p_seat;
  end if;
  if jsonb_typeof(p_options) <> 'array' or jsonb_array_length(p_options) < 2 then
    raise exception 'a decision needs at least two options (%).', p_surface;
  end if;
  if coalesce(btrim(p_dedupe_key), '') = '' then raise exception 'a duty''s question needs a dedupe key (%)', p_surface; end if;
  return public.fn_reason_hold(p_seat, p_surface, p_question,
    jsonb_build_object('seat', p_seat, 'surface', p_surface, 'question', left(p_question, 8000),
      'context', jsonb_build_object('audience', 'internal', 'case', coalesce(p_case, '{}'::jsonb)),
      'decision', jsonb_build_object('name', p_surface, 'options', p_options),
      'stakes', 'high', 'research', false, 'subject', coalesce(p_subject, '{}'::jsonb), 'dedupeKey', p_dedupe_key),
    jsonb_build_object('pending', jsonb_build_array('decompose', 'resolve', 'retrieve', 'decide', 'verify'), 'filed_by', 'seat_duty'),
    coalesce(p_subject, '{}'::jsonb), 'seat_duty', p_dedupe_key);
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_duty_routine_exists(p_routine text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- A duty runs as: select public.<routine>(). Any public routine of that name whose arguments ALL have defaults.
  select exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = p_routine
                   and p.pronargs = p.pronargdefaults)
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_duty_run(p_duty text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.seat_duty; v_res jsonb; v_t0 timestamptz := clock_timestamp(); v_ms integer;
begin
  select sd.* into d from public.seat_duty sd
   where sd.duty = p_duty and sd.enabled
     and not exists (select 1 from public.duty_pause dp where dp.duty = sd.duty)
     and (sd.last_started_at is null or now() - sd.last_started_at >= sd.every - interval '2 minutes')
   for update skip locked;
  if not found then
    -- Due, enabled and not paused, yet not found: another transaction holds the row. Count it (19 Oct 2026).
    if exists (select 1 from public.seat_duty sd
                where sd.duty = p_duty and sd.enabled
                  and not exists (select 1 from public.duty_pause dp where dp.duty = sd.duty)
                  and (sd.last_started_at is null or now() - sd.last_started_at >= sd.every - interval '2 minutes')) then
      insert into public.seat_duty_skip as k (duty, skips) values (p_duty, 1)
      on conflict (duty) do update set skips = k.skips + 1, last_skipped_at = now();
      return jsonb_build_object('duty', p_duty, 'ran', false, 'skipped', 'row locked');
    end if;
    return jsonb_build_object('duty', p_duty, 'ran', false);
  end if;
  update public.seat_duty set last_started_at = now() where duty = d.duty;
  delete from public.seat_duty_skip where duty = d.duty;   -- it ran: the skip streak ends
  begin
    if not public.fn_seat_duty_routine_exists(d.routine) then
      raise exception 'routine public.%() does not exist', d.routine;
    end if;
    execute format('select public.%I()', d.routine) into v_res;
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
    update public.seat_duty set last_ok_at = now(), last_result = v_res, last_error = null, failures = 0,
           avg_ms = round(coalesce(avg_ms * 0.7 + v_ms * 0.3, v_ms)) where duty = d.duty;
    if not d.own_job and (select avg_ms from public.seat_duty where duty = d.duty) > 1000 then
      perform public.fn_seat_duty_isolate(d.duty);   -- too slow for the shared tick: its own job from now on
    end if;
    return jsonb_build_object('duty', d.duty, 'ok', true, 'ms', v_ms);
  exception when others then
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
    update public.seat_duty set last_error = left(sqlerrm, 1000), failures = failures + 1,
           avg_ms = round(coalesce(avg_ms * 0.7 + v_ms * 0.3, v_ms)) where duty = d.duty;
    if not d.own_job and (select avg_ms from public.seat_duty where duty = d.duty) > 1000 then
      perform public.fn_seat_duty_isolate(d.duty);
    end if;
    return jsonb_build_object('duty', d.duty, 'ok', false, 'ms', v_ms, 'error', left(sqlerrm, 300));
  end;
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_exam_grade(p_seat text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare e public.seat_exam_item; v_top jsonb; v_hit jsonb; v_pass boolean; v_found boolean; v_missing text[];
  v_out jsonb := '[]'::jsonb;
begin
  for e in select * from public.seat_exam_item where seat = p_seat order by item_id loop
    v_pass := false; v_found := false; v_missing := '{}';
    if e.q_vec is not null then
      select coalesce(jsonb_agg(x order by n), '[]'::jsonb) into v_top
        from jsonb_array_elements(public.fn_reason_retrieve(e.seat, e.q_vec, 6, p_audience => 'internal')) with ordinality t(x, n) where n <= 5;
      for v_hit in select x from jsonb_array_elements(v_top) x where x->>'id' = any(e.expected_entry_ids) loop
        if not v_found then   -- the facts reported missing are the first hit's, as in grade()
          v_missing := array(select f from unnest(e.expected_facts) f where strpos(lower(coalesce(v_hit->>'excerpt', '')), lower(f)) = 0);
        end if;
        v_found := true;
        if not exists (select 1 from unnest(e.expected_facts) f where strpos(lower(coalesce(v_hit->>'excerpt', '')), lower(f)) = 0) then
          v_pass := true;
        end if;
      end loop;
    end if;
    v_out := v_out || jsonb_build_object('id', e.item_id, 'checklist', e.checklist, 'pass', v_pass, 'found', v_found,
      'reason', case when v_pass then null
                     when e.q_vec is null then 'not embedded: run seat_qualification_exam.mjs --load'
                     when not v_found then 'expected entry not in the top 5'
                     else 'facts missing: ' || array_to_string(v_missing, ' | ') end);
  end loop;
  return v_out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_for_surface(p_signed_in boolean, p_surface text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_surface text := lower(btrim(coalesce(p_surface, '')));
  v_seat    text;
begin
  -- The doors a caller can arrive through. Adding one is a deliberate edit here, which is the
  -- point: a typo'd surface at a call site is a raise, not a silently different answer.
  if v_surface not in ('website_widget','whatsapp','inbound_email','customer_portal','supplier_portal') then
    raise exception 'fn_seat_for_surface: unknown surface %. Known surfaces are website_widget, whatsapp, inbound_email, customer_portal, supplier_portal.', coalesce(p_surface, '(null)');
  end if;

  -- THE FOUNDER'S RULE, AND NOTHING ELSE. Not signed in -> customer_support. Signed in as a
  -- customer or a supplier -> sales_engineer, "because he has all the data". The surface does NOT
  -- move the decision: an anonymous visitor reading /portal is still a stranger on the website and
  -- is still Support's. The surface is carried so it can be recorded beside the answer.
  v_seat := case when coalesce(p_signed_in, false) then 'sales_engineer' else 'customer_support' end;

  perform 1 from public.org_role where role_id = v_seat and status = 'active';
  if not found then
    raise exception 'fn_seat_for_surface: seat % is not an active role. The rule cannot route a caller to a seat that does not exist.', v_seat;
  end if;

  return v_seat;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_handoff(p_from text, p_to text, p_type text, p_subject_table text, p_subject_id text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint; v_key text := p_type || ':' || p_subject_id; v_known boolean;
begin
  if coalesce(btrim(p_subject_id), '') = '' then raise exception 'a handoff must name its subject'; end if;
  -- ruling 1199: a handoff raised from a demo row is not filed at all. One exception: a probe that sets
  -- qd.probe_files_demo_handoff for its own transaction and always rolls back. The IT duty checks walk a
  -- ZZ DEMO handoff end to end; without it fn_it_loop_open handed fn_it_incident_open a NULL id (19 Oct 2026).
  if public.fn_seat_work_is_demo(p_payload::text, p_payload, p_subject_table, p_subject_id)
     and coalesce(current_setting('qd.probe_files_demo_handoff', true), '') <> 'on' then return null; end if;
  v_known := exists (select 1 from public.seat_handoff_kind k
                      where k.type = p_type and k.from_seat = p_from and k.to_seat = p_to);

  select id into v_id from public.agent_actions
   where kind = 'handoff' and agent = p_to and target_id = v_key and status <> 'failed'
   order by id limit 1;
  if v_id is not null then return v_id; end if;

  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values (p_to, 'handoff', case when v_known then 'pending' else 'failed' end, 'low',
          left(p_type || ' from ' || p_from || ' about ' || p_subject_table || ' ' || p_subject_id, 200),
          coalesce(p_payload, '{}'::jsonb) || jsonb_build_object(
            'type', p_type, 'from', p_from, 'from_name', p_from, 'to', p_to,
            'subject_table', p_subject_table, 'subject_id', p_subject_id)
          || case when v_known then '{}'::jsonb
                  else jsonb_build_object('error', 'unregistered handoff kind: no row in public.seat_handoff_kind') end,
          p_subject_table, v_key)
  returning id into v_id;

  if not v_known then
    perform public.fn_seat_handoff_event(v_id, 'failed');
    perform public.fn_it_engineer_finding_upsert(
      'monitor:unregistered_handoff_kind:' || p_type || ':' || p_from || ':' || p_to,
      'Unregistered handoff kind: ' || p_from || ' tried to start "' || p_type || '" with ' || p_to,
      'public.fn_seat_handoff (caller: ' || p_from || ')', 'agent_facing', 1,
      jsonb_build_object('type', p_type, 'from', p_from, 'to', p_to, 'handoff_id', v_id, 'owner_seat', 'ceo',
                         'fix', 'insert the conversation into public.seat_handoff_kind with its handler, in the file of the build that starts it'),
      '{}'::text[], array['which build starts this conversation and which handler answers it'], 'fn_seat_handoff');
    return v_id;
  end if;
  perform public.fn_seat_handoff_event(v_id, 'sent');

  -- THE RECEIVING SEAT ACTS NOW. A failure is recorded on the row and in the stream and never
  -- rolls back the money event that raised it: a refund that settled stays settled.
  begin
    perform public.fn_seat_handoff_act(v_id);
  exception when others then
    update public.agent_actions
       set status = 'failed', decided_at = now(),
           detail = detail || jsonb_build_object('error', left(sqlerrm, 500))
     where id = v_id;
    perform public.fn_seat_handoff_event(v_id, 'failed');
  end;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_handoff_act(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions; k public.seat_handoff_kind; v jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff' for update;
  if not found then raise exception 'no handoff %', p_id; end if;
  if a.status = 'done' then return a.evidence; end if;

  select * into k from public.seat_handoff_kind
   where type = a.detail->>'type' and from_seat = a.detail->>'from' and to_seat = a.agent;
  if not found then
    raise exception 'no conversation % from % to % in public.seat_handoff_kind', a.detail->>'type', a.detail->>'from', a.agent;
  end if;
  execute format('select public.%I($1)', k.handler) into v using p_id;
  if v is null then raise exception '% answered nothing for handoff %', k.handler, p_id; end if;
  -- 1013: the receiver's answer cites the note it was handed.
  if jsonb_typeof(v) = 'object' and not v ? 'cites_note' then
    v := v || jsonb_build_object('cites_note', public.fn_handoff_note_citation(p_id));
  end if;

  if v ? 'waiting' or k.originator_closes then
    update public.agent_actions
       set detail = detail || jsonb_build_object('awaiting', coalesce(v->>'waiting', a.detail->>'from' || ' re-verification'),
                                                 'replied_at', now()),
           evidence = v
     where id = p_id;
    perform public.fn_seat_handoff_event(p_id, 'waiting');
    return v;
  end if;
  perform public.fn_seat_handoff_complete(p_id, v);
  return v;
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_handoff_complete(p_id bigint, p_evidence jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions; v_ev jsonb := coalesce(p_evidence, '{}'::jsonb);
begin
  -- 1013: every way a handoff closes, the answer cites the note.
  if jsonb_typeof(v_ev) = 'object' and not v_ev ? 'cites_note' then
    v_ev := v_ev || jsonb_build_object('cites_note', public.fn_handoff_note_citation(p_id));
  end if;
  update public.agent_actions
     set status = 'done', decided_at = now(), decided_by = agent,
         evidence = v_ev,
         detail = detail - 'awaiting'
   where id = p_id and kind = 'handoff' and status <> 'done'
  returning * into a;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no open handoff ' || p_id); end if;
  perform public.fn_seat_handoff_event(p_id, 'done');

  if a.detail->>'type' = 'refund.remediate' and (a.detail->>'refund_id') is not null then
    perform public.fn_ceo_refund_loop_advance((a.detail->>'refund_id')::bigint);
  elsif a.detail->>'type' = 'incident.fix' and (a.detail->>'incident_id') is not null then
    perform public.fn_ceo_incident_advance((a.detail->>'incident_id')::bigint);
  end if;
  return jsonb_build_object('ok', true, 'handoff_id', p_id, 'type', a.detail->>'type');
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_handoff_event(p_id bigint, p_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id;
  if not found then return; end if;
  insert into public.company_event (event_type, entity_type, entity_id, actor, payload)
  values ('handoff.' || coalesce(a.detail->>'type', '?') || '.' || p_status, 'agent_actions', a.id::text,
          coalesce(a.detail->>'from', 'system'),
          jsonb_build_object('handoff_id', a.id, 'type', a.detail->>'type', 'from', a.detail->>'from',
                             'to', a.agent, 'status', p_status, 'subject_table', a.detail->>'subject_table',
                             'subject_id', a.detail->>'subject_id', 'refund_id', a.detail->>'refund_id',
                             'transaction_id', a.detail->>'transaction_id', 'awaiting', a.detail->>'awaiting'));
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_handoff_notes(p_seat text, p_subject_table text DEFAULT NULL::text, p_subject_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('handoff_id', a.id, 'from', a.detail->>'from',
                                               'conversation', coalesce(a.detail->>'type', a.detail->>'subject'),
                                               'opened_at', a.created_at, 'status', a.status,
                                               'summary', a.detail->'summary') order by a.created_at desc), '[]'::jsonb)
    from (select * from public.agent_actions a
           where a.kind = 'handoff' and a.agent = p_seat
             and (a.status in ('pending','needs_review') or (a.detail ? 'awaiting' and a.status <> 'failed' and a.decided_at is null))
             and a.detail ? 'summary'
             and (p_subject_id is null
                  or (coalesce(a.detail->>'subject_id', a.target_id) = p_subject_id
                      and (p_subject_table is null or coalesce(a.detail->>'subject_table', a.target_table) = p_subject_table)))
           order by a.created_at desc limit 3) a;
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_handoff_types()
 RETURNS TABLE(type text, from_seat text, to_seat text, meaning text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select k.type, k.from_seat, k.to_seat, k.meaning from public.seat_handoff_kind k
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_knowledge_items(p_seat text)
 RETURNS TABLE(item_key text, title text, content text, updated_at timestamp with time zone, has_source boolean, review_due date, validation_status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select 'support_knowledge:' || record_id, title, body, imported_at, coalesce(cardinality(source_ids), 0) > 0, null::date, null::text
    from public.support_knowledge
   where p_seat = 'customer_support' and coalesce(runtime_index_eligible, true) and nullif(btrim(body), '') is not null
  union all
  select 'sales_knowledge:' || record_id, title, content, coalesce(updated_at, ingested_at), coalesce(cardinality(source_ids), 0) > 0, null, null
    from public.sales_knowledge
   where p_seat = 'sales_engineer' and coalesce(runtime_index_eligible, true) and nullif(btrim(content), '') is not null
  union all
  select 'accountant_knowledge:' || record_id, title, content, coalesce(updated_at, ingested_at), coalesce(cardinality(source_ids), 0) > 0, null, null
    from public.accountant_knowledge
   where p_seat = 'accountant' and coalesce(runtime_index_eligible, true) and nullif(btrim(content), '') is not null
  union all
  select 'it_engineer_knowledge:' || record_id, title, content, coalesce(updated_at, ingested_at), coalesce(cardinality(source_ids), 0) > 0, null, null
    from public.it_engineer_knowledge
   where p_seat = 'it_engineer' and coalesce(runtime_index_eligible, true) and nullif(btrim(content), '') is not null
  union all
  select 'ceo_knowledge:' || record_id, title, body, imported_at, coalesce(cardinality(source_ids), 0) > 0, null, null
    from public.ceo_knowledge
   where p_seat = 'ceo' and coalesce(runtime_index_eligible, true) and nullif(btrim(body), '') is not null
  union all
  select 'agent_knowledge:' || id, topic, content, coalesce(updated_at, created_at), nullif(btrim(source_ref), '') is not null,
         review_due, validation_status
    from public.agent_knowledge
   where p_seat = 'marketing' and agent_key like 'marketing%' and nullif(btrim(content), '') is not null;
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_learning_measure(p_day date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_day date := coalesce(p_day, (now() at time zone 'Asia/Dubai')::date); r public.seat_learning_daily; p public.seat_learning_daily;
  v_out jsonb := '[]'::jsonb; v_fell boolean;
begin
  insert into public.seat_learning_daily as d (seat, day, judgements_30d, outcomes_30d, correct_30d, accuracy_30d,
         recall_available_30d, cases_total, cases_with_outcome, lessons_approved)
  select s.seat, v_day,
         (select count(*) from public.seat_judgement j where j.seat = s.seat and j.status <> 'held' and j.made_at >= v_day - 30 and j.made_at < v_day + 1),
         (select count(*) from public.seat_judgement j where j.seat = s.seat and j.status <> 'held' and j.outcome_correct is not null and j.outcome_at >= v_day - 30 and j.outcome_at < v_day + 1),
         (select count(*) from public.seat_judgement j where j.seat = s.seat and j.status <> 'held' and j.outcome_correct and j.outcome_at >= v_day - 30 and j.outcome_at < v_day + 1),
         (select round(avg(case when j.outcome_correct then 1.0 else 0.0 end), 4) from public.seat_judgement j
           where j.seat = s.seat and j.status <> 'held' and j.outcome_correct is not null and j.outcome_at >= v_day - 30 and j.outcome_at < v_day + 1),
         (select count(*) from public.seat_judgement j where j.seat = s.seat and j.status <> 'held' and (j.recall->>'available')::boolean and j.made_at >= v_day - 30 and j.made_at < v_day + 1),
         (select count(*) from public.seat_case_memory m where m.seat = s.seat),
         (select count(*) from public.seat_case_memory m where m.seat = s.seat and m.outcome is not null),
         (select count(*) from public.reasoning_knowledge_candidate k join public.seat_lesson_cluster c on c.candidate_id = k.id
           where k.seat = s.seat and k.status = 'approved')
    from unnest(array['ceo','customer_support','sales_engineer','accountant','it_engineer','marketing']) s(seat)
  on conflict (seat, day) do update set judgements_30d = excluded.judgements_30d, outcomes_30d = excluded.outcomes_30d,
     correct_30d = excluded.correct_30d, accuracy_30d = excluded.accuracy_30d, recall_available_30d = excluded.recall_available_30d,
     cases_total = excluded.cases_total, cases_with_outcome = excluded.cases_with_outcome,
     lessons_approved = excluded.lessons_approved, measured_at = now();

  for r in select * from public.seat_learning_daily where day = v_day loop
    select * into p from public.seat_learning_daily where seat = r.seat and day = v_day - 7;
    v_fell := p.seat is not null and r.outcomes_30d >= 10 and p.outcomes_30d >= 10
              and r.accuracy_30d is not null and p.accuracy_30d is not null and r.accuracy_30d <= p.accuracy_30d - 0.10;
    if v_fell then
      perform public.fn_it_engineer_finding_upsert('learning_accuracy_fell:' || r.seat,
        'The ' || r.seat || ' seat''s decision accuracy fell from ' || round(p.accuracy_30d * 100) || '% to ' || round(r.accuracy_30d * 100) || '% in a week',
        'public.seat_learning_daily (' || r.seat || ')', 'agent_facing', r.outcomes_30d,
        jsonb_build_object('seat', r.seat, 'day', v_day, 'accuracy_now', r.accuracy_30d, 'accuracy_week_ago', p.accuracy_30d,
                           'outcomes_now', r.outcomes_30d, 'outcomes_week_ago', p.outcomes_30d),
        '{}'::text[], array['which judgements turned wrong: read seat_judgement where seat = ''' || r.seat || ''' and outcome_correct is false'], 'it_engineer');
    elsif exists (select 1 from public.it_engineer_finding f where f.issue_key = 'learning_accuracy_fell:' || r.seat and f.closed_at is null)
          and (p.seat is null or r.accuracy_30d is null or p.accuracy_30d is null or r.accuracy_30d > p.accuracy_30d - 0.10) then
      perform public.fn_it_engineer_finding_close('learning_accuracy_fell:' || r.seat,
        'Recovered: ' || r.seat || ' accuracy ' || coalesce(round(r.accuracy_30d * 100) || '%', 'not measurable') || ' on ' || v_day);
    end if;
    v_out := v_out || jsonb_build_object('seat', r.seat, 'accuracy_30d', r.accuracy_30d, 'outcomes_30d', r.outcomes_30d, 'fell', coalesce(v_fell, false));
  end loop;
  return jsonb_build_object('ok', true, 'day', v_day, 'seats', v_out);
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_learning_trend(p_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with d as (select coalesce(p_to, (now() at time zone 'Asia/Dubai')::date) as t)
  select coalesce(jsonb_object_agg(s.seat, jsonb_build_object(
    'accuracy_now',      (select x.accuracy_30d from public.seat_learning_daily x where x.seat = s.seat and x.day <= d.t order by x.day desc limit 1),
    'accuracy_week_ago', (select x.accuracy_30d from public.seat_learning_daily x where x.seat = s.seat and x.day <= d.t - 7 order by x.day desc limit 1),
    'accuracy_4w_ago',   (select x.accuracy_30d from public.seat_learning_daily x where x.seat = s.seat and x.day <= d.t - 28 order by x.day desc limit 1),
    'judgements_week',   (select count(*) from public.seat_judgement j where j.seat = s.seat and j.status <> 'held' and j.made_at >= d.t - 6),
    'outcomes_week',     (select count(*) from public.seat_judgement j where j.seat = s.seat and j.status <> 'held' and j.outcome_at >= d.t - 6),
    'cases_with_outcome',(select count(*) from public.seat_case_memory m where m.seat = s.seat and m.outcome is not null),
    'lessons_approved_week', (select count(*) from public.reasoning_knowledge_candidate k join public.seat_lesson_cluster c on c.candidate_id = k.id
                               where k.seat = s.seat and k.status = 'approved' and k.reviewed_at >= d.t - 6),
    'lessons_pending',   (select count(*) from public.reasoning_knowledge_candidate k join public.seat_lesson_cluster c on c.candidate_id = k.id
                               where k.seat = s.seat and k.status = 'pending_review'))), '{}'::jsonb)
  from d, unnest(array['ceo','customer_support','sales_engineer','accountant','it_engineer','marketing']) s(seat)
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_liveness(p_include_demo boolean DEFAULT false)
 RETURNS TABLE(seat text, verdict text, last_act timestamp with time zone, acts_24h integer, last_run timestamp with time zone, runs_24h integer, overdue integer, oldest_overdue timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with s as (select o.agent_key seat from public.org_agents o where o.active),
  x as (
    select s.seat,
           a.last_act, coalesce(a.n24, 0) acts_24h,
           r.last_run, coalesce(r.n24, 0) runs_24h,
           coalesce(d.n, 0) overdue, d.oldest oldest_overdue
      from s
      left join lateral (select max(h.decided_at) last_act,
                                count(*) filter (where h.decided_at > now() - interval '24 hours')::int n24
                           from public.agent_actions h
                          where h.kind = 'handoff' and h.decided_by = s.seat) a on true
      left join lateral (select max(ar.started_at) last_run,
                                count(*) filter (where ar.started_at > now() - interval '24 hours')::int n24
                           from public.agent_runs ar
                          where ar.agent in (s.seat, 'fn:' || s.seat)
                            and ar.started_at > now() - interval '7 days') r on true
      -- The overdue count is the handoff_sla duty's own reading, not a second copy of its rule: only
      -- handoffs the seat has not REPLIED to past their window (an it.finding it answered and the IT
      -- engineer has not yet closed is not the seat's delay), and founder-bound delivery requests are
      -- left to the delivery duty, which waits out the 19:00 Dubai digest hold.
      left join (select e->'evidence'->>'seat' seat, sum((e->>'affected')::int)::int n,
                        min((e->'evidence'->>'oldest_at')::timestamptz) oldest
                   from jsonb_array_elements(public.fn_it_handoff_sla_items(p_include_demo)) e
                  where e->'evidence'->>'state' = 'unanswered'
                  group by 1) d on d.seat = s.seat)
  select x.seat,
         case when x.overdue > 0 and (x.last_act is null or x.last_act < x.oldest_overdue) then 'stopped'
              when x.overdue > 0 then 'behind'
              when x.acts_24h + x.runs_24h > 0 then 'acting'
              else 'idle' end,
         x.last_act, x.acts_24h, x.last_run, x.runs_24h, x.overdue, x.oldest_overdue
    from x order by x.seat
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_playbook_build(p_seat text, p_reason text DEFAULT 'rebuilt on request'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_table   text := case p_seat when 'sales_engineer' then 'sales_knowledge' when 'customer_support' then 'support_knowledge'
                            when 'accountant' then 'accountant_knowledge' when 'it_engineer' then 'it_engineer_knowledge'
                            when 'ceo' then 'ceo_knowledge' when 'marketing' then 'marketing_knowledge' end;
  v_duties  jsonb; v_kinds jsonb; v_routes jsonb; v_rules jsonb := '[]'::jsonb; v_lessons jsonb;
  v_pb      jsonb; v_md text; v_md5 text; v_old public.seat_playbook; v_version int;
begin
  if v_table is null then raise exception 'no seat %', p_seat; end if;

  select coalesce(jsonb_agg(jsonb_build_object('duty', duty, 'every', every::text, 'what', what, 'routine', routine)
                            order by duty), '[]'::jsonb)
    into v_duties from public.seat_duty where owner_seat = p_seat and enabled;

  select coalesce(jsonb_agg(jsonb_build_object(
           'kind', type, 'from', from_seat, 'means', meaning,
           'steps', jsonb_build_array(
              'Read the handoff note first (known / tried / needed / evidence) - it leads my recall.',
              'Act through ' || handler || '.',
              'Reply ' || coalesce('within ' || reply_within::text, 'without a set deadline') || '.',
              case when originator_closes then from_seat || ' re-verifies my answer and closes the handoff.'
                   else 'I close the handoff with evidence when done.' end),
           'escalation', jsonb_build_array(
              'If ' || handler || ' fails, the handoff is marked failed and an it_engineer finding is opened (fn_seat_handoff).',
              case when reply_within is not null then 'Past ' || reply_within::text || ' the it_engineer SLA monitor (fn_it_handoff_sla_items) picks it up.'
                   else 'No reply window: the originator re-verifies (fn_originators_reverify_handoffs).' end))
         order by type, from_seat), '[]'::jsonb)
    into v_kinds from public.seat_handoff_kind where to_seat = p_seat;

  select coalesce(jsonb_agg(jsonb_build_object('to', to_seat, 'kind', type, 'means', meaning) order by to_seat, type), '[]'::jsonb)
    into v_routes from public.seat_handoff_kind where from_seat = p_seat;

  -- The decision rules the seat's verified knowledge states, one per entry that states one.
  if to_regclass('public.' || v_table) is not null then
    execute format($q$
      select coalesce(jsonb_agg(jsonb_build_object('entry', record_id, 'topic', title, 'rule', rule) order by record_id), '[]'::jsonb)
        from (select k.record_id, k.title,
                     btrim((regexp_match(coalesce(to_jsonb(k)->>'content', to_jsonb(k)->>'body', ''),
                                         -- [^\n], not '.': in a Postgres regex '.' matches a newline, and
                                         -- the first dry run swallowed each entry to its end.
                                         'Decision rules?:\s*([^\n]+)'))[1]) as rule
                from public.%I k
               where k.record_id like $1 || ':%%' and k.record_id not like '%%@ar') r
       where rule is not null$q$, v_table)
      into v_rules using p_seat;
  end if;

  select coalesce(jsonb_agg(x order by x->>'at' desc), '[]'::jsonb) into v_lessons from (
    select x from (
      select jsonb_build_object('lesson', l, 'case_id', m.id, 'case_kind', m.case_kind, 'at', m.updated_at) x
        from public.seat_case_memory m, unnest(m.lessons) l
       where m.seat = p_seat and btrim(l) <> ''
      union all
      select jsonb_build_object('lesson', c.finding, 'candidate_id', c.id, 'case_kind', 'approved finding', 'at', coalesce(c.reviewed_at, c.created_at))
        from public.reasoning_knowledge_candidate c
       where c.seat = p_seat and c.status = 'approved'
    ) u order by x->>'at' desc limit 25) z;

  v_pb := jsonb_build_object('seat', p_seat, 'duties', v_duties, 'case_kinds', v_kinds, 'hands_on_to', v_routes,
                             'decision_rules', coalesce(v_rules, '[]'::jsonb), 'lessons', v_lessons);
  v_md5 := md5(v_pb::text);

  select * into v_old from public.seat_playbook where seat = p_seat;
  if found and v_old.content_md5 = v_md5 then
    return jsonb_build_object('seat', p_seat, 'version', v_old.version, 'changed', false);
  end if;
  v_version := coalesce(v_old.version, 0) + 1;

  -- The Markdown an auditor reads. No clock in it: the file changes only when the playbook does.
  v_md := '# ' || initcap(replace(p_seat, '_', ' ')) || ' playbook' || E'\n\n'
    || '> Generated by `public.fn_seat_playbook_build` from the database (seat_duty, seat_handoff_kind, the seat''s verified knowledge, and its lessons). '
    || 'Do not edit by hand - it is rebuilt every time a lesson is recorded. Version ' || v_version || '.' || E'\n\n'
    || '## Standing duties (what I do without being asked)' || E'\n\n'
    || coalesce((select string_agg('- **' || (d->>'duty') || '** (every ' || (d->>'every') || '): ' || (d->>'what') || ' - `' || (d->>'routine') || '`', E'\n' order by ord)
                   from jsonb_array_elements(v_duties) with ordinality t(d, ord)), '- none') || E'\n\n'
    || '## Case kinds I handle' || E'\n\n'
    || coalesce((select string_agg('### ' || (c->>'kind') || ' (from ' || (c->>'from') || ')' || E'\n\n'
                                   || (c->>'means') || E'\n\n' || 'Steps:' || E'\n'
                                   || (select string_agg((n) || '. ' || s, E'\n' order by n) from jsonb_array_elements_text(c->'steps') with ordinality s2(s, n))
                                   || E'\n\n' || 'Escalation:' || E'\n'
                                   || (select string_agg('- ' || s, E'\n') from jsonb_array_elements_text(c->'escalation') s),
                                   E'\n\n' order by ord)
                   from jsonb_array_elements(v_kinds) with ordinality t(c, ord)), 'No case kind is handed to this seat.') || E'\n\n'
    || '## Where I hand work on' || E'\n\n'
    || coalesce((select string_agg('- to **' || (r->>'to') || '** as `' || (r->>'kind') || '`: ' || (r->>'means'), E'\n' order by ord)
                   from jsonb_array_elements(v_routes) with ordinality t(r, ord)), '- nowhere') || E'\n\n'
    || '## Decision rules from my verified knowledge' || E'\n\n'
    || coalesce((select string_agg('- **' || (r->>'topic') || '** (`' || (r->>'entry') || '`): ' || (r->>'rule'), E'\n' order by ord)
                   from jsonb_array_elements(coalesce(v_rules, '[]'::jsonb)) with ordinality t(r, ord)), '- none stated yet') || E'\n\n'
    || '## Lessons learned (newest 25, from the learning loop)' || E'\n\n'
    || coalesce((select string_agg('- ' || replace(l->>'lesson', E'\n', ' ')
                                   || coalesce(' (case #' || (l->>'case_id') || ')', ' (finding #' || (l->>'candidate_id') || ')'), E'\n' order by ord)
                   from jsonb_array_elements(v_lessons) with ordinality t(l, ord)), '- none recorded yet') || E'\n';

  insert into public.seat_playbook (seat, version, playbook, markdown, content_md5, rebuilt_reason, rebuilt_at)
  values (p_seat, v_version, v_pb, v_md, v_md5, left(coalesce(p_reason, 'rebuilt'), 300), now())
  on conflict (seat) do update set version = excluded.version, playbook = excluded.playbook, markdown = excluded.markdown,
                                   content_md5 = excluded.content_md5, rebuilt_reason = excluded.rebuilt_reason,
                                   rebuilt_at = excluded.rebuilt_at;
  return jsonb_build_object('seat', p_seat, 'version', v_version, 'changed', true);
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_playbook_build_all(p_reason text DEFAULT 'rebuilt on request'::text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_agg(public.fn_seat_playbook_build(s, p_reason) order by s)
    from unnest(array['accountant','ceo','customer_support','it_engineer','marketing','sales_engineer']) s;
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_revises_for_the_ceo(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions; v_held bigint; v_fields jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  v_held := public.fn_seat_duty_reason(a.agent, a.agent || '.ceo_revision',
    'The CEO sent your submission back (round ' || coalesce(a.detail->>'round', '?') || ', ' || coalesce(a.detail->>'rounds_left', '?')
      || ' more before the CEO must replace or withdraw it). Read each of the CEO''s reasons. Produce a revised version that answers '
      || 'every one of them, or where you are right keep it and answer each reason with evidence. The CEO reviews what you resubmit.',
    '[{"id":"revised","meaning":"the submission is revised so that it answers every reason the CEO gave"},{"id":"defended","meaning":"the submission stands, and each reason is answered with evidence"}]'::jsonb,
    jsonb_build_object('path', a.detail->>'path', 'item_key', a.detail->>'item_key', 'round', a.detail->'round',
                       'ceo_reasons', a.detail->>'reasons', 'submission', a.detail->'version'),
    jsonb_build_object('handoff_id', p_id, 'path', a.detail->>'path', 'item_key', a.detail->>'item_key'),
    'ceo_revision:' || (a.detail->>'item_key') || ':g' || coalesce(a.detail->>'generation', '1') || ':r' || coalesce(a.detail->>'round', '1')
      -- a re-filed question (fn_ceo_revision_refile, after the last one failed) is a new question, not the closed one
      || coalesce(':t' || (a.evidence->>'refiles'), ''));
  v_fields := jsonb_build_array(
    jsonb_build_object('key', 'revision', 'question', 'the revised submission, complete, as the CEO should now review it'),
    jsonb_build_object('key', 'answers', 'question', 'for each of the CEO''s reasons: what changed, or the evidence that answers it'));
  if a.detail->>'path' = 'ceo_experiment' then
    v_fields := v_fields || jsonb_build_array(
      jsonb_build_object('key', 'hypothesis', 'question', 'the revised hypothesis (blank keeps it)'),
      jsonb_build_object('key', 'approach', 'question', 'the revised approach (blank keeps it)'),
      jsonb_build_object('key', 'target', 'question', 'the revised target, a number (blank keeps it)'),
      jsonb_build_object('key', 'days', 'question', 'the revised run length in days, 7 to 365 (blank keeps it)'));
  end if;
  if a.detail->>'path' = 'marketing_month_plan' then
    -- the CEO reviews the idea list itself, so a revision that changes the plan must carry the changed list
    v_fields := v_fields || jsonb_build_array(jsonb_build_object('key', 'ideas', 'question',
      'the complete revised idea list as a JSON array, one object per video with n (1, 2, ...), date (YYYY-MM-DD, a UAE '
      || 'working day in the plan''s month), idea_key, title, hook, film_plan, cta, audience (supplier, customer or both) '
      || 'and why; every change the CEO asked for must be in it. Blank keeps the current list.'));
  end if;
  perform public.fn_ambition_ask_fields(v_held, v_fields);
  return jsonb_build_object('waiting', a.agent || ' revises and resubmits ' || coalesce(a.detail->>'item_key', '?') || ' (held question ' || v_held || ')',
                            'held_id', v_held);
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_self_review(p_month date, p_seat text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_m date := date_trunc('month', p_month)::date; g jsonb; prev public.seat_self_review;
  v_items int; v_pass int; v_rate numeric; v_lines int; v_lpass int; v_lrate numeric;
  v_pitems text[]; v_plines text[]; v_slip text[] := '{}'; v_trend text; v_imp bigint; v_closed bigint[] := '{}'; r record;
begin
  if exists (select 1 from public.seat_self_review where month = v_m and seat = p_seat) then
    return jsonb_build_object('ok', true, 'seat', p_seat, 'month', v_m, 'already', true);
  end if;
  if not exists (select 1 from public.org_role where role_id = p_seat and status = 'active') then
    return jsonb_build_object('ok', false, 'error', p_seat || ' is not an active seat');
  end if;

  g := public.fn_seat_exam_grade(p_seat);
  v_items := jsonb_array_length(g);
  v_pass := (select count(*) from jsonb_array_elements(g) x where (x->>'pass')::boolean);
  v_pitems := array(select x->>'id' from jsonb_array_elements(g) x where (x->>'pass')::boolean order by 1);
  -- a senior-hire checklist line passes when every exam item under it passes
  select count(*), count(*) filter (where ok), coalesce(array_agg(line order by line) filter (where ok), '{}')
    into v_lines, v_lpass, v_plines
    from (select x->>'checklist' as line, bool_and((x->>'pass')::boolean) as ok from jsonb_array_elements(g) x group by 1) c;
  v_rate := case when v_items > 0 then round(v_pass::numeric / v_items, 3) end;
  v_lrate := case when v_lines > 0 then round(v_lpass::numeric / v_lines, 3) end;

  select * into prev from public.seat_self_review where seat = p_seat and month < v_m order by month desc limit 1;

  if v_items = 0 then
    v_trend := 'no_exam';
    v_slip := v_slip || format('no qualification exam on file: write knowledge/exams/%s.json against the job description''s senior-hire checklist and load it (seat_qualification_exam.mjs --load)', p_seat);
  else
    v_trend := case when prev.month is null or prev.rate is null then 'first'
                    when v_rate > prev.rate then 'up' when v_rate < prev.rate then 'down' else 'flat' end;
    if prev.month is not null then
      v_slip := v_slip || array(select format('exam item %s passed in %s and fails now (%s)', x->>'id', to_char(prev.month, 'Mon YYYY'), x->>'reason')
                                  from jsonb_array_elements(g) x where not (x->>'pass')::boolean and x->>'id' = any(prev.passed_items) order by 1);
      v_slip := v_slip || array(select format('checklist line %s passed in %s and fails now', l, to_char(prev.month, 'Mon YYYY'))
                                  from unnest(prev.passed_lines) l where not (l = any(v_plines)) order by 1);
      if prev.rate is not null and v_rate < prev.rate then
        v_slip := v_slip || format('exam score fell from %s%% to %s%%', round(prev.rate * 100), round(v_rate * 100));
      end if;
      if prev.checklist_rate is not null and v_lrate < prev.checklist_rate then
        v_slip := v_slip || format('checklist score fell from %s%% to %s%%', round(prev.checklist_rate * 100), round(v_lrate * 100));
      end if;
    end if;
    if v_rate < 0.80 then v_slip := v_slip || format('exam score %s%% (%s of %s) is under the 80%% senior bar', round(v_rate * 100), v_pass, v_items); end if;
    if v_lrate < 0.80 then v_slip := v_slip || format('checklist score %s%% (%s of %s lines) is under the 80%% senior bar', round(v_lrate * 100), v_lpass, v_lines); end if;
    if exists (select 1 from jsonb_array_elements(g) x where x->>'reason' like 'not embedded%') then
      v_slip := v_slip || 'exam items not embedded: run seat_qualification_exam.mjs --load'::text;
    end if;
  end if;

  -- earlier self-review improvements of the seat close when nothing slipped this month
  if cardinality(v_slip) = 0 then
    for r in select id from public.ceo_improvement where source_kind = 'self_review' and seat = p_seat and status in ('open', 'assigned') loop
      perform public.fn_ceo_improvement_close(r.id, format('%s self-review of %s: nothing slipped (exam %s%%, checklist %s%%).',
        p_seat, to_char(v_m, 'Mon YYYY'), round(v_rate * 100), round(v_lrate * 100)));
      v_closed := v_closed || r.id;
    end loop;
  else
    v_imp := public.fn_ceo_improvement_open('self_review', p_seat || ':' || v_m, p_seat,
      format('%s self-review of %s, opened by the seat itself: %s. Due %s.', p_seat, to_char(v_m, 'Mon YYYY'),
             array_to_string(v_slip, '; '), to_char((v_m + interval '1 month')::date + 4, 'DD Mon YYYY')),
      jsonb_build_object('month', v_m, 'slipped', to_jsonb(v_slip), 'rate', v_rate, 'checklist_rate', v_lrate,
                         'failing', (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(g) x where not (x->>'pass')::boolean)));
    if v_imp is not null then
      update public.ceo_improvement set due_on = (v_m + interval '1 month')::date + 4,
             close_check = 'Closes when next month''s self-review finds nothing slipped.'
       where id = v_imp;
    end if;
  end if;

  insert into public.seat_self_review (month, seat, items, passed, rate, checklist_lines, checklist_passed, checklist_rate,
    prev_rate, prev_checklist_rate, trend, passed_items, passed_lines, failing, slipped, improvement_id, closed_improvements)
  values (v_m, p_seat, v_items, v_pass, v_rate, coalesce(v_lines, 0), coalesce(v_lpass, 0), v_lrate,
    prev.rate, prev.checklist_rate, v_trend, v_pitems, v_plines,
    (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(g) x where not (x->>'pass')::boolean),
    v_slip, v_imp, v_closed);
  return jsonb_build_object('ok', true, 'seat', p_seat, 'month', v_m, 'items', v_items, 'passed', v_pass, 'rate', v_rate,
    'checklist_rate', v_lrate, 'trend', v_trend, 'slipped', cardinality(v_slip), 'improvement_id', v_imp, 'closed', cardinality(v_closed));
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_takes_ceo_directive(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions; d jsonb; v_gates jsonb; v_duty text; v_block text;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  d := a.detail;
  select jsonb_build_object('on', coalesce(max(value) filter (where key='invite_enabled'),'') = 'true'
                                 and coalesce(max(value) filter (where key='supplier_outreach_golive'),'') = 'true',
                            'cap', max(value) filter (where key='invite_daily_cap'))
    into v_gates from public.app_secrets where key in ('invite_enabled','supplier_outreach_golive','invite_daily_cap');
  case d->>'stage'
    when 'invitations', 'registrations' then
      v_duty := 'fn_sales_engineer_supplier_outreach_tick: the daily invitation batch (cap '||coalesce(v_gates->>'cap','?')||') and the day-2/day-6 registration reminders';
      if not (v_gates->>'on')::boolean then v_block := 'held: the founder''s invitation switches are off'; end if;
    when 'verification' then
      v_duty := 'fn_sales_engineer_supplier_outreach_tick: the 24-hour clock on a submitted registration, and the mandatory-six check';
    when 'deliverability' then
      v_duty := 'fn_delivery_feedback_canary_tick and the outbox bounce brake: suppress the bouncing addresses, prove bounce reports arrive';
    when 'quotes' then
      v_duty := 'the RFQ dispatch and the spec-offer duty: widen the match inside the exact trade and chase the suppliers who have not quoted';
    when 'reveals' then
      v_duty := 'the comparison follow-up with the customer; the payment path is the accountant''s nightly test';
    when 'demand' then
      v_duty := 'the marketing seat''s duties (supabase/functions/marketing/duties.ts): approved posts, the social inbox and paid reach that bring buyers to post requests; its daily report (marketing.report) says what moved';
    else
      v_duty := 'no standing duty carries this stage'; v_block := 'no owner duty exists';
  end case;
  return jsonb_build_object('accepted', true, 'seat', a.agent, 'stage', d->>'stage', 'duty', v_duty, 'blocker', v_block,
    'measure_key', d->>'measure_key', 'target', d->'target', 'due_at', d->>'due_at',
    'reading_now', public.fn_ceo_plan_measure(d->>'measure_key', a.created_at, now()),
    'waiting', 'the CEO re-measures '||(d->>'measure_key')||' by '||(d->>'due_at'));
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_takes_ceo_improvement(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  return jsonb_build_object('accepted', true, 'seat', a.agent, 'improvement_id', a.detail->'improvement_id', 'proposal', a.detail->>'proposal',
    'waiting', 'the CEO closes this when its source recovers: the metric back on its path, the finding closed, or no repeat of the case');
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_takes_ceo_month_directive(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  return jsonb_build_object('accepted', true, 'seat', a.agent, 'month', a.detail->>'month', 'targets', a.detail->'targets', 'actions', a.detail->'actions',
    'waiting', 'the CEO reads each target daily and closes this at month end, met or missed');
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_takes_data_request(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object('accepted', true, 'seat', a.agent, 'request_id', a.detail->'request_id',
    'waiting', coalesce(a.detail->>'waiting_for', 'the correction of the person''s data, by the due date'))
    from public.agent_actions a where a.id = p_id
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_takes_knowledge_request(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object('accepted', true, 'seat', a.agent, 'gap_id', a.detail->'gap_id',
    'waiting', coalesce(a.detail->>'waiting_for', 'a knowledge entry that answers the question'))
    from public.agent_actions a where a.id = p_id
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_takes_support_root_cause(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  return jsonb_build_object('accepted', true, 'seat', a.agent, 'root_cause_id', a.detail->'root_cause_id', 'cause', a.detail->>'cause_key',
    'waiting', 'customer_support measures the cause''s weekly volume after the change and closes this when it falls');
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_takes_the_ceo_decision(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions; d public.seat_deliberation; v_closed jsonb; v_owed jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  if a.detail->>'path' = 'seat_deliberation' then
    select * into d from public.seat_deliberation where id = (a.detail->'version'->>'deliberation_id')::bigint;
    if d.id is not null and d.author_seat = a.agent and d.status in ('reviewed', 'no_independent_reviewer')
       and d.kind not like 'high_stakes.%' then
      v_closed := public.fn_seat_deliberation_close(d.id, a.agent,
        left(a.detail->>'decision' || ' by the CEO in round ' || coalesce(a.detail->>'round', '?') || ': ' || coalesce(a.detail->>'reasons', ''), 2000));
      perform set_config('qd.handoff_closer', '', true);
    elsif d.id is not null and d.author_seat = a.agent and d.kind like 'high_stakes.%' and d.handoff_id is not null
          and exists (select 1 from public.agent_actions h where h.id = d.handoff_id and h.status = 'pending') then
      perform set_config('qd.handoff_closer', a.agent, true);
      perform public.fn_seat_handoff_complete(d.handoff_id, jsonb_build_object('kind', 'deliberation.review', 'deliberation_id', d.id,
        'ceo_decision', a.detail->>'decision', 'reasons', left(a.detail->>'reasons', 2000), 'closed_by', a.agent));
      perform set_config('qd.handoff_closer', '', true);
      v_closed := jsonb_build_object('handoff_closed', d.handoff_id, 'deliberation_kept_for_the_gate', d.id);
    end if;
  end if;
  -- the seat that owed the CEO this decision re-verifies it against the ledger and closes its own question
  if a.detail->>'item_key' is not null then
    v_owed := public.fn_seat_verifies_the_ceo_decision_it_owed(a.agent, a.detail->>'item_key');
  end if;
  return jsonb_build_object('read_by', a.agent, 'decision', a.detail->>'decision', 'item_key', a.detail->>'item_key',
                            'reasons', left(a.detail->>'reasons', 600), 'deliberation_closed', v_closed, 'owed_closed', v_owed);
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_verifies_the_ceo_decision_it_owed(p_seat text, p_item_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare o record; r public.ceo_decision_round; v_closed bigint[] := '{}'; v_open bigint[] := '{}';
begin
  for o in select a.id, a.detail from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'ceo.decision_owed'
              and a.detail->>'from' = p_seat and a.detail->>'item_key' = p_item_key
            order by a.id loop
    -- the CEO's answer, read from the ledger rather than from the notice: a round on this item, by this seat,
    -- after the round the question was raised at
    r := null;
    select * into r from public.ceo_decision_round x
     where x.item_key = p_item_key and x.originator_seat = p_seat
       and (x.generation, x.round) > (coalesce((o.detail->>'generation')::int, 1), coalesce((o.detail->>'after_round')::int, 0))
     order by x.generation desc, x.round desc limit 1;
    if r.id is null and not (o.detail ? 'ceo_nothing_to_close') then
      v_open := v_open || o.id;
      continue;
    end if;
    perform set_config('qd.handoff_closer', p_seat, true);
    perform public.fn_seat_handoff_complete(o.id, jsonb_build_object(
      'verified_by', p_seat, 'checked_at', now(), 'round_id', r.id,
      'decision', coalesce(r.decision, 'nothing_to_close'),
      'reasons', left(coalesce(r.reasons, o.detail->'ceo_nothing_to_close'->>'reason'), 2000)));
    perform set_config('qd.handoff_closer', '', true);
    v_closed := v_closed || o.id;
  end loop;
  return jsonb_build_object('closed', to_jsonb(v_closed), 'still_owed', to_jsonb(v_open));
end $function$


CREATE OR REPLACE FUNCTION public.fn_seat_words(p_seat text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case p_seat when 'accountant' then 'finance' when 'customer_support' then 'customer support'
                     when 'it_engineer' then 'IT' when 'sales_engineer' then 'sales' when 'marketing' then 'marketing'
                     when 'ceo' then 'the CEO office' else replace(p_seat, '_', ' ') end
$function$


CREATE OR REPLACE FUNCTION public.fn_seat_work_is_demo(p_text text, p_ref jsonb, p_subject_table text DEFAULT NULL::text, p_subject_id text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_id text := split_part(coalesce(p_subject_id, ''), ':', 1);
  v_ref jsonb := case when jsonb_typeof(p_ref) = 'object' then p_ref else '{}'::jsonb end;
begin
  -- a rolled-back probe proving a seat loop on ZZ DEMO fixtures (never set outside one)
  if coalesce(current_setting('qd.probe_files_demo_handoff', true), '') = 'on' then return false; end if;

  if coalesce(p_text, '') ~* '(^|[^a-z])zz\s*demo' then return true; end if;

  -- the subject a handoff names, folded into the reference set
  if p_subject_table in ('leads', 'suppliers') then v_ref := v_ref || jsonb_build_object('zz_subject', jsonb_build_object('supplier_id', v_id));
  elsif p_subject_table = 'customers' then v_ref := v_ref || jsonb_build_object('zz_subject', jsonb_build_object('customer_id', v_id));
  elsif p_subject_table = 'inquiries' then v_ref := v_ref || jsonb_build_object('zz_subject', jsonb_build_object('inquiry_id', v_id));
  elsif p_subject_table = 'transactions' then v_ref := v_ref || jsonb_build_object('zz_subject', jsonb_build_object('transaction_id', v_id));
  elsif p_subject_table = 'reviews' and v_id ~ '^[0-9]{1,18}$' then
    v_ref := v_ref || coalesce((select jsonb_build_object('zz_subject', jsonb_build_object('customer_id', r.customer_id,
                       'supplier_id', r.supplier_id, 'transaction_id', r.transaction_id)) from public.reviews r where r.id = v_id::bigint), '{}');
  elsif p_subject_table is not null and public.fn_deliberation_subject_is_fixture(p_subject_table, p_subject_id) then
    return true;
  end if;

  if v_ref = '{}'::jsonb then return false; end if;
  if coalesce((public.fn_ai_subject_is_fixture(v_ref) ->> 'fixture')::boolean, false) then return true; end if;

  -- any customer / supplier / lead / inquiry / transaction / email named at any depth (a rating nests them)
  return exists (
    select 1
      from (values ('customer_id'), ('supplier_id'), ('lead_id'), ('inquiry_id'), ('transaction_id'), ('email')) k(key)
      cross join lateral jsonb_path_query(v_ref, ('lax $.**.' || k.key)::jsonpath) x(val)
      cross join lateral (select x.val #>> '{}' as s) s
     where case k.key
             when 'customer_id'    then public.fn_party_is_demo('customer', s.s)
             when 'supplier_id'    then public.fn_party_is_demo('supplier', s.s)
             when 'lead_id'        then public.fn_party_is_demo('lead', s.s)
             when 'email'          then public.fn_is_demo_email(s.s)
             when 'inquiry_id'     then case when s.s ~ v_uuid then public.fn_inquiry_is_demo(s.s::uuid) else false end
             when 'transaction_id' then case when s.s ~ v_uuid then public.fn_transaction_is_demo(s.s::uuid) else false end
           end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_security_audit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_old jsonb; v_new jsonb; v_pk text;
begin
  v_old := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end;
  v_new := case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end;
  if tg_table_name = 'app_secrets' then
    if v_old ? 'value' then v_old := jsonb_set(v_old, '{value}', '"***REDACTED***"'); end if;
    if v_new ? 'value' then v_new := jsonb_set(v_new, '{value}', '"***REDACTED***"'); end if;
  end if;
  v_pk := coalesce(v_new->>'id', v_old->>'id', v_new->>'key', v_old->>'key',
                   v_new->>'name', v_old->>'name', v_new->>'role', v_old->>'role');
  insert into public.security_audit_log(action, table_name, row_pk, old_data, new_data)
  values (tg_op, tg_table_name, v_pk, v_old, v_new);
  return coalesce(new, old);
end $function$


CREATE OR REPLACE FUNCTION public.fn_security_audit_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  raise exception 'security_audit_log is append-only; % is not permitted', tg_op;
end $function$


CREATE OR REPLACE FUNCTION public.fn_security_detect(p_window interval DEFAULT '24:00:00'::interval)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  v_since timestamptz := now() - p_window;
  v jsonb := '{}'::jsonb;
  n int;
begin
  -- D1 MALWARE. A recorded malicious verdict is the highest-confidence detection this estate has.
  with ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select 'malware_file', 'high', f.source, coalesce(f.subject, f.filename),
           jsonb_build_object('file_scan_id', f.id, 'sha256', f.sha256, 'filename', f.filename,
                              'mime', f.mime, 'bucket', f.bucket, 'path', f.path,
                              'engines_malicious', f.engines_malicious,
                              'engines_total', f.engines_total, 'blocked', f.blocked),
           'file_scan:' || f.id
      from public.file_scan f
     where f.verdict in ('malicious','suspicious')
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('malware_file', n);

  -- D2 UNJUDGED. A file that entered and still has no clean verdict after 24h is sitting in the
  -- estate unscanned. Low severity, but it must be VISIBLE — an unknown must never render as safe.
  with ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select 'file_unscanned', 'low', f.source, coalesce(f.subject, f.filename),
           jsonb_build_object('file_scan_id', f.id, 'sha256', f.sha256, 'verdict', f.verdict,
                              'filename', f.filename, 'bucket', f.bucket, 'path', f.path),
           'file_unscanned:' || f.id
      from public.file_scan f
     where f.verdict in ('unknown','unavailable')
       and f.created_at < now() - interval '24 hours'
       and not public.fn_file_is_cleared(f.sha256)
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('file_unscanned', n);

  -- D3 CREDENTIAL MISUSE. internal_credential_audit.allowed=false is a presented secret that was
  -- REFUSED: a wrong secret, a retired one, or one used outside its scope. 11 such rows exist today.
  with ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select 'credential_refused', 'medium', a.function_name, a.context,
           jsonb_build_object('audit_id', a.id, 'credential_id', a.credential_id,
                              'reason', a.reason, 'at', a.at, 'detail', a.detail),
           'cred_audit:' || a.id
      from public.internal_credential_audit a
     where a.allowed = false
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('credential_refused', n);

  -- D4 A DEAD CREDENTIAL THAT STILL WORKS. last_used_at after retired_at or after expires_at means
  -- a secret that should have stopped being accepted was accepted. That is containment-worthy:
  -- 83 of the 90 rows in internal_credential are active, so revoking one is a real action available
  -- today, and this detection is the trigger for it.
  with ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select 'credential_used_after_end', 'high', c.last_function, c.context,
           jsonb_build_object('credential_id', c.id, 'label', c.label, 'active', c.active,
                              'retired_at', c.retired_at, 'expires_at', c.expires_at,
                              'last_used_at', c.last_used_at, 'use_count', c.use_count),
           'cred_after_end:' || c.id || ':' || to_char(c.last_used_at at time zone 'utc','YYYYMMDDHH24')
      from public.internal_credential c
     where c.last_used_at is not null
       and ( (c.retired_at is not null and c.last_used_at > c.retired_at)
          or (c.expires_at is not null and c.last_used_at > c.expires_at)
          or (c.active = false and c.last_used_at > coalesce(c.retired_at, c.rotated_at, c.created_at)) )
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('credential_used_after_end', n);

  -- D5 OTP BRUTE FORCE. The login is a mobile number and a one-time code (there is no observe mode
  -- and no password), so guessing the code IS the attack on customer identity. attempts is
  -- incremented per wrong code by the verifier.
  with ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select 'otp_brute_force', 'medium', 'customer_phone_otps', o.phone,
           jsonb_build_object('otp_id', o.id, 'attempts', o.attempts, 'consumed', o.consumed,
                              'customer_id', o.customer_id, 'created_at', o.created_at),
           'otp_attempts:' || o.id
      from public.customer_phone_otps o
     where o.attempts >= 5
       and o.created_at >= v_since
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('otp_brute_force', n);

  -- D6 OTP ENUMERATION. Many codes ISSUED to one number in a short window is a different attack
  -- from many codes guessed: it is someone using our SMS to hammer a phone, or mapping which
  -- numbers exist. Bucketed to the hour so the fingerprint is stable across re-runs.
  with agg as (
    select o.phone, date_trunc('hour', o.created_at) as hr, count(*) as issued
      from public.customer_phone_otps o
     where o.created_at >= v_since
     group by 1,2
    having count(*) >= 5),
  ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select 'otp_enumeration', 'medium', 'customer_phone_otps', agg.phone,
           jsonb_build_object('issued', agg.issued, 'hour', agg.hr),
           'otp_issued:' || agg.phone || ':' || to_char(agg.hr at time zone 'utc','YYYYMMDDHH24')
      from agg
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('otp_enumeration', n);

  -- D7 SSRF. resend_inbound records a refused attachment URL into agent_runs with
  -- counts.ssrf_refused; accountant reports the same refusal in its run note. Both are read here
  -- rather than adding a second write path to two deployed functions.
  with ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select 'ssrf_refused', 'medium', r.agent, r.counts->>'stage',
           jsonb_build_object('agent_run_id', r.id, 'counts', r.counts,
                              'note', left(coalesce(r.note,''), 500), 'at', r.started_at),
           'agent_run_ssrf:' || r.id
      from public.agent_runs r
     where r.started_at >= v_since
       and ( r.counts ? 'ssrf_refused'
          or r.note ilike '%url_refused%'
          or r.note ilike '%url_refused_after_redirect%' )
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('ssrf_refused', n);

  -- D8 A REFUSED UPLOAD SHAPE. sanitizeUpload refusing an executable, an HTML polyglot or a zip
  -- bomb is the guard working — and a run of them from one sender is someone probing what we
  -- accept. Recorded low, because a single refusal is far more often a careless browser.
  with ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select 'upload_shape_refused', 'low', r.agent, null,
           jsonb_build_object('agent_run_id', r.id, 'counts', r.counts,
                              'note', left(coalesce(r.note,''), 500), 'at', r.started_at),
           'agent_run_upload:' || r.id
      from public.agent_runs r
     where r.started_at >= v_since
       and ( r.counts ? 'attachment_refused'
          or r.note ilike '%refused by sanitizeUpload%'
          or r.note ilike '%unsafe_file_type%'
          or r.note ilike '%unsafe_file_content%'
          or r.note ilike '%zip_expands_too_far%' )
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('upload_shape_refused', n);

  -- D9 SECRETS. security_audit_log is trigger-written and had 76 rows that nothing ever read.
  --
  -- THE FIRST VERSION OF THIS BRANCH WAS WRONG AND THE EXECUTION SHOWED IT. It raised one medium
  -- event per row, which on the first run produced 76 'secret_table_written' events against ONE
  -- malware event — a guard that fires when the system works, burying the signal it exists to
  -- surface. Measured: all 76 rows are app_secrets INSERT/UPDATE by db_user `postgres`, which is
  -- how EVERY secret in this estate is written, so "a secret was written" carries no information.
  -- The 76 noise rows were deleted with this correction; nothing else in security_events was
  -- touched, and the corrected rules below use different fingerprints so they evaluate freely.
  --
  -- What DOES carry information, and is rare enough to mean something:
  --   * a DELETE — no routine in this estate deletes a secret or a credential row;
  --   * a write by a db_user that is not one of ours;
  --   * a BURST. Measured over the whole table: the busiest hour ever recorded is 5 writes. 25 in
  --     one hour is five times the observed peak, so it cannot fire on ordinary operation, and it
  --     is raised ONCE per hour rather than once per row.
  with ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select case when s.action = 'DELETE' then 'secret_deleted' else 'secret_written_by_unexpected_role' end,
           'high', 'security_audit_log', s.db_user,
           jsonb_build_object('audit_id', s.id, 'action', s.action, 'table', s.table_name,
                              'row_pk', s.row_pk, 'at', s.at, 'old', s.old_data),
           'sec_audit:' || s.id
      from public.security_audit_log s
     where s.at >= v_since
       and s.table_name in ('app_secrets','internal_credential','internal_credential_audit')
       and ( s.action = 'DELETE'
          or s.db_user is null
          or s.db_user not in ('postgres','supabase_admin','supabase_storage_admin','service_role') )
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('secret_anomaly', n);

  with agg as (
    select date_trunc('hour', s.at) as hr, count(*) as writes
      from public.security_audit_log s
     where s.at >= v_since
       and s.table_name in ('app_secrets','internal_credential')
     group by 1
    having count(*) >= 25),
  ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select 'secret_write_burst', 'medium', 'security_audit_log', null,
           jsonb_build_object('writes', agg.writes, 'hour', agg.hr,
                              'observed_peak_before_this_rule', 5),
           'secret_burst:' || to_char(agg.hr at time zone 'utc','YYYYMMDDHH24')
      from agg
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('secret_write_burst', n);

  -- D10 A NEW SECURITY ADVISOR FINDING. in_baseline=false means the finding appeared after the
  -- baseline was taken. WARN is medium, INFO is low — a new table with RLS on and no policy is
  -- worth seeing but is not an intrusion.
  with ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select 'new_security_advisor',
           case when b.level in ('WARN','ERROR') then 'medium' else 'low' end,
           'supabase_advisors', b.name,
           jsonb_build_object('cache_key', b.cache_key, 'level', b.level, 'title', b.title,
                              'metadata', b.metadata, 'first_seen_at', b.first_seen_at),
           'advisor:' || b.cache_key
      from public.security_advisor_baseline b
     where b.in_baseline = false
       and b.cleared_at is null
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('new_security_advisor', n);

  return v || jsonb_build_object(
    'window', p_window::text,
    'at', now(),
    'total_new', (select coalesce(sum((value)::int), 0)
                    from jsonb_each_text(v) where key <> 'window'));
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_security_detect_on_evidence()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin
  -- Never let the watch break the thing it watches: a detector that raises stops a supplier
  -- registering, which is a worse outcome than a late event.
  begin
    perform public.fn_security_detect(interval '1 hour');
  exception when others then
    null;
  end;
  return null;
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_security_watch(p_window interval DEFAULT '7 days'::interval)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'at', now(),
    'window', p_window::text,
    'events_by_kind', coalesce((
        select jsonb_object_agg(kind, c) from (
          select kind, count(*) c from public.security_events
           where created_at >= now() - p_window group by 1) t), '{}'::jsonb),
    'events_by_severity', coalesce((
        select jsonb_object_agg(severity, c) from (
          select severity, count(*) c from public.security_events
           where created_at >= now() - p_window group by 1) t), '{}'::jsonb),
    'files_scanned', (select count(*) from public.file_scan where created_at >= now() - p_window),
    'files_by_verdict', coalesce((
        select jsonb_object_agg(verdict, c) from (
          select verdict, count(*) c from public.file_scan
           where created_at >= now() - p_window group by 1) t), '{}'::jsonb),
    'files_blocked', (select count(*) from public.file_scan
                       where blocked and created_at >= now() - p_window),
    'quarantined_total', (select count(*) from public.v_file_quarantine),
    'advisors_baseline', (select count(*) from public.security_advisor_baseline where in_baseline),
    'advisors_new', (select count(*) from public.security_advisor_baseline
                      where not in_baseline and cleared_at is null),
    'advisors_last_refreshed', (select max(last_seen_at) from public.security_advisor_baseline),
    'gaps_open', (select jsonb_agg(jsonb_build_object('name', name, 'status', status,
                                                      'needs', what_would_close_it))
                    from public.security_gap where status <> 'closed')
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_select_model(p_task_class text, p_dept_key text DEFAULT NULL::text, p_confidence numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select fn_ai_route(p_task_class, p_dept_key, p_confidence, null, false); $function$


CREATE OR REPLACE FUNCTION public.fn_self_review()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_found int := 0;
begin
  -- Stale knowledge: past its review date
  insert into self_review (review_type, subject, finding, evidence, proposal)
  select 'stale_knowledge', k.agent_key||' / '||k.topic,
         'Knowledge past its review date',
         'review_due '||k.review_due||', owner '||coalesce(k.owner_agent,'none')||', confidence '||coalesce(k.confidence::text,'unset'),
         'Re-research and revalidate, or mark superseded'
  from agent_knowledge k
  where k.review_due < current_date
    and not exists (select 1 from self_review s where s.review_type='stale_knowledge'
                     and s.subject = k.agent_key||' / '||k.topic and s.status='proposed');
  get diagnostics v_found = row_count;

  -- Departments that cannot act
  insert into self_review (review_type, subject, finding, evidence, proposal)
  select 'overloaded_dept', d.dept_key,
         'Department has authority but no wired executor',
         (select count(*)::text from org_authority a where a.dept_key=d.dept_key)||' authority rules, 0 executors',
         'Wire an executor or remove the authority rule'
  from org_departments d
  where d.active
    and not exists (select 1 from org_action_executor e where e.department=d.dept_key and e.active)
    and not exists (select 1 from self_review s where s.review_type='overloaded_dept' and s.subject=d.dept_key and s.status='proposed');

  -- Employees with no KPI
  insert into self_review (review_type, subject, finding, evidence, proposal)
  select 'missed_kpi', a.agent_key,
         'Employee has no measurable KPI',
         'title '||coalesce(a.title,'none')||', department '||a.department,
         'Assign a KPI tied to a company goal, or retire the role'
  from org_agents a
  where a.active
    and not exists (select 1 from employee_kpi k where k.agent_key=a.agent_key and k.active)
    and not exists (select 1 from self_review s where s.review_type='missed_kpi' and s.subject=a.agent_key and s.status='proposed');

  -- Recurring failures: any agent failing more than 3 times in 7 days
  insert into self_review (review_type, subject, finding, evidence, proposal)
  select 'recurring_failure', r.agent,
         'Agent failing repeatedly',
         count(*)||' failures in 7 days; latest: '||left(coalesce(max(r.note),''),160),
         'Diagnose root cause; this is an automation candidate if the fix is mechanical'
  from agent_runs r
  where r.started_at > now() - interval '7 days' and r.status='error'
  group by r.agent having count(*) > 3
    and not exists (select 1 from self_review s where s.review_type='recurring_failure' and s.subject=r.agent and s.status='proposed');

  -- Categories with supply but no standard knowledge
  insert into self_review (review_type, subject, finding, evidence, proposal)
  select 'stale_sop', v.catalog_slug,
         'Category has supplier supply but no standard knowledge base',
         v.supplier_supply||' suppliers in pipeline, coverage '||v.coverage,
         'Build the 14-module knowledge base; supplier supply is already there'
  from v_category_coverage v
  where v.coverage <> 'COMPLIANT' and v.supplier_supply >= 100
    and not exists (select 1 from self_review s where s.review_type='stale_sop' and s.subject=v.catalog_slug and s.status='proposed');

  return jsonb_build_object(
    'stale_knowledge', (select count(*) from self_review where review_type='stale_knowledge' and status='proposed'),
    'depts_cannot_act', (select count(*) from self_review where review_type='overloaded_dept' and status='proposed'),
    'employees_no_kpi', (select count(*) from self_review where review_type='missed_kpi' and status='proposed'),
    'recurring_failures', (select count(*) from self_review where review_type='recurring_failure' and status='proposed'),
    'categories_needing_knowledge', (select count(*) from self_review where review_type='stale_sop' and status='proposed'),
    'total_open', (select count(*) from self_review where status='proposed'));
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_seniority_rank(p text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case lower(coalesce(p,''))
           when 'executive' then 1 when 'director' then 2
           when 'manager'   then 3 when 'specialist' then 4 else 9 end;
$function$


CREATE OR REPLACE FUNCTION public.fn_services_effective(p_stated text[], p_trades text[] DEFAULT '{}'::text[], p_removed text[] DEFAULT '{}'::text[])
 RETURNS text[]
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with stated as (
    select distinct s.trade_code || '.' || s.code as key
    from public.taxonomy_trade_service s
    where s.active and s.trade_code || '.' || s.code = any(coalesce(p_stated, '{}'::text[]))
  ),
  src as (
    select key from stated
    union
    select t from unnest(coalesce(p_trades, '{}'::text[])) t
  ),
  implied as (
    select distinct i.implies_trade || '.' || i.implies_code as key
    from public.service_implication i
    join src on src.key = i.from_code
    where i.active
  )
  select coalesce(array_agg(distinct key order by key), '{}'::text[])
  from (select key from stated union select key from implied) all_keys
  where key <> all (coalesce(p_removed, '{}'::text[]));
$function$


CREATE OR REPLACE FUNCTION public.fn_should_escalate(ctx jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  reasons text[] := '{}';
  conf_min numeric; fin_review numeric; auto_max numeric; fraud_max numeric;
  legal jsonb; sens jsonb; owner text;
  c_conf numeric := nullif(ctx->>'confidence','')::numeric;
  c_amt  numeric := nullif(ctx->>'amount_aed','')::numeric;
  c_fraud numeric := nullif(ctx->>'fraud_score','')::numeric;
  c_cat  text := lower(coalesce(ctx->>'category',''));
  c_txt  text := lower(coalesce(ctx->>'text',''));
  c_kind text := lower(coalesce(ctx->>'kind',''));
  REPORTING_KINDS constant text[] := array['handoff','incident','report_task'];
  c_money boolean := coalesce((ctx->>'moves_money')::boolean,false);
  trg text;
  c_actor text := nullif(btrim(coalesce(ctx->>'actor', ctx->>'agent_key', '')), '');
  v_route text; v_basis text; v_note text;
  v_mgr text; v_mgr_dept text; v_pick jsonb;
  v_actor_res text;
  v_apex_backup text;   -- D11: the named deputy-apex
  v_key text; v_choice text; v_cands jsonb; v_needs jsonb;   -- the reasoned meaning of ctx.text (23 Sep 2026)
begin
  select value::numeric into conf_min   from decision_policy where key='confidence_min';
  select value::numeric into fin_review  from decision_policy where key='financial_review_aed';
  select value::numeric into auto_max    from decision_policy where key='auto_action_max_aed';
  select value::numeric into fraud_max   from decision_policy where key='fraud_score_max';
  select value into legal                from decision_policy where key='legal_triggers';
  select value into sens                 from decision_policy where key='sensitive_categories';
  select value #>> '{}' into owner       from decision_policy where key='review_owner';

  if c_conf is not null and c_conf < conf_min then
     reasons := array_append(reasons, 'confidence '||round(c_conf,2)::text||' < min '||round(conf_min,2)::text); end if;
  if c_amt is not null and c_amt >= fin_review then
     reasons := array_append(reasons, 'amount AED '||c_amt::text||' >= review threshold '||fin_review::text); end if;
  if c_money and (c_amt is null or c_amt > auto_max) then
     reasons := array_append(reasons, 'action moves money beyond autonomous limit'); end if;
  if c_fraud is not null and c_fraud >= fraud_max then
     reasons := array_append(reasons, 'fraud score '||round(c_fraud,2)::text||' >= max '||round(fraud_max,2)::text); end if;
  if c_cat <> '' and sens ? c_cat and (c_conf is null or c_conf < conf_min) then
     reasons := array_append(reasons, 'sensitive category "'||c_cat||'" with low/absent confidence'); end if;
  -- WHAT THE TEXT MEANS IS REASONED, NEVER SPOTTED (23 Sep 2026, founder_instruction 886-903). This read
  -- the legal_triggers list as substrings of the text and matched earlier failures by shared long words,
  -- so "is a refund dispute legal?" escalated and "the supplier sued us" did not. The question — does the
  -- matter carry a legal exposure, or repeat an attempt that ended worse? — is now filed for the CEO seat's
  -- reasoning (fn_decide files it) and read back here by its key. Until it is answered this routine says
  -- so ('needs_reasoning') and its caller waits; nothing is escalated on a word guess.
  if c_txt <> '' then
    -- One question per (decision kind, actor, text): stable fields only, never a per-call id or timestamp the
    -- caller may add to the context, so asking again never files (and pays for) a second question.
    v_key := 'ceo.escalation:' || md5(coalesce(ctx->>'decide_kind', '') || '|' || coalesce(c_actor, '') || '|' || c_txt);
    v_choice := public.fn_reason_route_answer(v_key);
    if v_choice is null then
      select coalesce(jsonb_agg(jsonb_build_object('id', 'repeats_failure_' || m.id,
               'meaning', 'it repeats this earlier attempt, which ended worse: ' || left(m.headline, 300)) order by m.created_at desc), '[]'::jsonb)
        into v_cands
        from (select * from institutional_memory m
               where m.outcome = 'worse' and coalesce(m.headline,'') <> '' and not (c_kind = any (REPORTING_KINDS))
               order by m.created_at desc limit 5) m;
      v_needs := jsonb_build_object('surface', 'ceo.escalation_meaning', 'dedupe_key', v_key,
        'question', left(ctx->>'text', 4000),
        'options', jsonb_build_array(jsonb_build_object('id', 'legal_matter',
                     'meaning', 'the matter itself carries a legal exposure for the company - for example '
                                || coalesce((select string_agg(x, ', ') from jsonb_array_elements_text(legal) x), 'a dispute or a liability')
                                || ' - however it is worded, in any language; merely mentioning such a word as a topic is not enough'))
                   || v_cands
                   || jsonb_build_array(jsonb_build_object('id', 'neither',
                     'meaning', 'neither a legal exposure nor a repeat of an attempt that ended worse')));
    elsif v_choice = 'legal_matter' then
      reasons := array_append(reasons, 'legal matter (reasoned by the CEO seat)');
    elsif left(v_choice, 16) = 'repeats_failure_' then
      select m.headline into trg from institutional_memory m where m.id::text = substr(v_choice, 17);
      reasons := array_append(reasons, 'a prior attempt on record ended worse (reasoned): "' || left(coalesce(trg, v_choice), 120) || '"');
    end if;
  end if;

  -- THE APEX ESCALATES TO THE FOUNDER. Resolved FIRST: the active agent with no manager_key (the CEO)
  -- reports to the founder, not to another agent.
  if c_actor is not null then
    v_actor_res := coalesce(public.fn_org_agent_resolve(c_actor), c_actor);
    perform 1 from org_agents a where a.agent_key = v_actor_res and a.active and a.manager_key is null;
    if found then
      v_route := 'founder'; v_basis := 'apex_to_founder';
      v_note  := 'the company apex ('||v_actor_res||') has no manager; the only party above it is the '
              || 'founder, whose major-issue channel is the single human signal the design allows';
    end if;
  end if;

  -- RESOLVE THE PARTY. The configured review_owner (employee / staffed department / title).
  if v_route is null and owner is not null and btrim(owner) <> '' then
    select a.agent_key into v_route from org_agents a
     where a.active and a.agent_key = owner limit 1;
    if v_route is not null then v_basis := 'employee'; end if;

    if v_route is null then
      select d.dept_key into v_route from org_departments d
       where d.dept_key = owner
         and exists (select 1 from org_agents a where a.department = d.dept_key and a.active)
       limit 1;
      if v_route is not null then v_basis := 'staffed_department'; end if;
    end if;

    if v_route is null then
      select a.agent_key into v_route from org_agents a
       where a.active and lower(btrim(a.title)) = lower(btrim(owner))   -- the configured title, exactly (23 Sep 2026: was a substring)
       order by a.agent_key limit 1;
      if v_route is not null then v_basis := 'employee_by_title'; end if;
    end if;
  end if;

  -- THE REPORTING LINE. The actor's manager (active AND available), else the standing deputy.
  if v_route is null and c_actor is not null then
    select a.manager_key into v_mgr from org_agents a where a.agent_key = c_actor and a.active;
    if v_mgr is not null and v_mgr <> c_actor then
      select a.agent_key into v_route from org_agents a
       where a.agent_key = v_mgr and a.active and a.available
         and (a.unavailable_until is null or a.unavailable_until < current_date);
      if v_route is not null then v_basis := 'reporting_line'; end if;

      if v_route is null then
        select a.department into v_mgr_dept from org_agents a where a.agent_key = v_mgr;
        begin v_pick := public.fn_pick_reviewer(v_mgr_dept);
        exception when others then v_pick := null; end;
        v_route := public.fn_route_party(v_pick->>'reviewer');
        if v_route = c_actor then v_route := null; end if;
        if v_route is not null then
          v_basis := 'reporting_line_delegated';
          v_note  := 'manager '||v_mgr||' is unavailable; '
                  || coalesce(v_pick->>'basis','delegation_rule standing deputy');
        end if;
      end if;
    end if;
  end if;

  -- D11: THE APEX BACKUP. Before the generic executive fallback, a named deputy-apex (the COO) takes
  -- an escalation that did not resolve up the line, so an apex-level item reaches a designated backup
  -- rather than whichever exec member the fallback names. Configured in decision_policy.apex_backup.
  if v_route is null then
    select value #>> '{}' into v_apex_backup from decision_policy where key='apex_backup';
    if v_apex_backup is not null and btrim(v_apex_backup) <> '' then
      select a.agent_key into v_route from org_agents a
       where a.active and a.agent_key = coalesce(public.fn_org_agent_resolve(v_apex_backup), v_apex_backup)
       limit 1;
      if v_route is not null then
        v_basis := 'apex_backup';
        v_note := 'no manager or configured owner resolved; the designated apex backup ('||v_route
               || ') stands in before the generic executive fallback';
      end if;
    end if;
  end if;

  -- The configured owner names nobody and no apex backup resolved. Escalate to the executive
  -- department's own head, recorded as a fallback so the configuration gap stays visible.
  if v_route is null then
    select coalesce(
             (select d.brain_agent from org_departments d where d.dept_key='exec'
               and exists (select 1 from org_agents a where a.agent_key=d.brain_agent and a.active)),
             (select d.lead_agent  from org_departments d where d.dept_key='exec'
               and exists (select 1 from org_agents a where a.agent_key=d.lead_agent and a.active)),
             (select a.agent_key from org_agents a where a.active and a.department='exec'
               order by a.agent_key limit 1))
      into v_route;
    if v_route is not null then
      v_basis := 'fallback_exec';
      v_note := 'configured review_owner "'||coalesce(owner,'(unset)')||'" names no active employee '
             || 'and no staffed department; escalation addressed to '||v_route||' instead';
    end if;
  end if;

  if v_route is null then
    v_route := owner; v_basis := 'unresolved';
    v_note := 'configured review_owner "'||coalesce(owner,'(unset)')||'" resolves to no party in the '
           || 'org model, and no active executive employee was available to take it';
  end if;

  return jsonb_build_object(
    'escalate', array_length(reasons,1) is not null,
    'reasons', to_jsonb(reasons),
    'route_to', v_route,
    'route_basis', v_basis,
    'route_note', v_note,
    'route_owner_configured', owner,
    'needs_reasoning', v_needs);
end $function$


CREATE OR REPLACE FUNCTION public.fn_signup_customer_held(p_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (select 1 from public.inquiries i where i.customer_id = cu.id)
      or exists (select 1 from public.transactions t where t.customer_id = cu.id)
      or exists (select 1 from public.po_orders p where p.customer_id = cu.id)
      or cu.signed_terms_path is not null
      or exists (select 1 from public.inquiry_intake ii where ii.customer_id = cu.id or lower(ii.email) = lower(cu.email))
      or exists (select 1 from public.messages m where m.customer_id = cu.id)
      or exists (select 1 from public.assistant_logs a where a.audience = 'customer:' || cu.id::text)
      or exists (select 1 from public.inbound_messages im where lower(im.from_email) = lower(cu.email))
      or exists (select 1 from public.contact_messages cm where lower(cm.email) = lower(cu.email))
      or exists (select 1 from public.complaint_tickets ct where lower(ct.email) = lower(cu.email))
    from public.customers cu where cu.id = p_id;
$function$


CREATE OR REPLACE FUNCTION public.fn_signup_email_kept_elsewhere(p_email text, p_role text, p_except_lead bigint DEFAULT NULL::bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (select 1 from public.leads l where lower(l.claimed_by) = lower(p_email)
                   and (p_role = 'customer' or l.id is distinct from p_except_lead)
                   and ((coalesce(l.owner_email_verified, false) and coalesce(l.owner_phone_verified, false)
                         and l.accepted_terms_at is not null and l.accepted_terms_ip is not null)
                        or public.fn_signup_supplier_held(l.id)
                        -- a sign-up in the other role still inside its own 30 minutes keeps the login too
                        or least(coalesce(l.portal_updated_at, l.created_at, now()), now()) > now() - interval '30 minutes'))
      or (p_role <> 'customer' and exists (select 1 from public.customers c where lower(c.email) = lower(p_email)
                   and ((coalesce(c.email_verified, false) and coalesce(c.phone_verified, false)
                         and c.tos_accepted_at is not null and c.tos_ip is not null)
                        or public.fn_signup_customer_held(c.id)
                        or c.created_at > now() - interval '30 minutes')));
$function$


CREATE OR REPLACE FUNCTION public.fn_signup_purge_backups(p_purge_id bigint, p_entity text, p_entity_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_listed int;
begin
  if p_entity not in ('customer', 'supplier') then raise exception 'fn_signup_purge_backups: customer or supplier only'; end if;
  -- EVERY record of the entity, whatever its status: a copy that never reached Dropbox answers not_found and its
  -- record still goes; nothing is stranded and nothing is orphaned (release review, round 4)
  insert into public.signup_purge_dropbox (purge_id, doc_backup_id, dropbox_file)
  select p_purge_id, d.id, d.dropbox_path from public.doc_backups d
   where d.entity = p_entity and d.entity_id = p_entity_id and d.dropbox_path is not null
  on conflict (doc_backup_id) do nothing;
  get diagnostics v_listed = row_count;
  update public.doc_backups d set status = 'signup_purge_pending', claimed_at = null, claimed_by = null,
         error = 'unfinished sign-up removed (signup_purge ' || p_purge_id || '): Dropbox copy and record to be deleted'
   where d.entity = p_entity and d.entity_id = p_entity_id;
  return jsonb_build_object('records_listed', v_listed);
end $function$


CREATE OR REPLACE FUNCTION public.fn_signup_purge_mail(p_purge_id bigint, p_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_pdf int; v_dbx int; v_rows int;
begin
  insert into public.signup_purge_object (purge_id, bucket, path)
  select p_purge_id, a.pdf_bucket, a.pdf_path
    from public.notifications n
    join public.conversation_archive a on a.source_table = 'notifications' and a.source_id = n.id::text
   where lower(n.to_email) = lower(p_email) and a.pdf_bucket is not null and a.pdf_path is not null
  on conflict do nothing;
  get diagnostics v_pdf = row_count;
  insert into public.signup_purge_dropbox (purge_id, doc_backup_id, dropbox_file)
  select p_purge_id, d.id, d.dropbox_path
    from public.notifications n
    join public.doc_backups d on d.dedupe_key = 'CONV:notifications:' || n.id
   where lower(n.to_email) = lower(p_email) and d.dropbox_path is not null
  on conflict (doc_backup_id) do nothing;
  get diagnostics v_dbx = row_count;
  update public.doc_backups d set status = 'signup_purge_pending', claimed_at = null, claimed_by = null,
         error = 'unfinished sign-up removed (signup_purge ' || p_purge_id || '): Dropbox copy and record to be deleted'
    from public.notifications n
   where d.dedupe_key = 'CONV:notifications:' || n.id and lower(n.to_email) = lower(p_email);
  delete from public.conversation_archive a using public.notifications n
   where a.source_table = 'notifications' and a.source_id = n.id::text and lower(n.to_email) = lower(p_email);
  get diagnostics v_rows = row_count;
  return jsonb_build_object('mail_pdfs_listed', v_pdf, 'mail_copies_listed', v_dbx, 'mail_archive_rows', v_rows);
end $function$


CREATE OR REPLACE FUNCTION public.fn_signup_supplier_held(p_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (select 1 from public.quotes q where q.supplier_id = l.id)
      or exists (select 1 from public.transactions t where t.supplier_id = l.id)
      or exists (select 1 from public.inquiry_matches im where im.supplier_id = l.id)
      or l.signed_terms_path is not null
      or exists (select 1 from public.messages m where m.supplier_id = l.id)
      or exists (select 1 from public.inbound_messages i2 where i2.lead_id = l.id or lower(i2.from_email) = lower(l.claimed_by))
    from public.leads l where l.id = p_id;
$function$


CREATE OR REPLACE FUNCTION public.fn_smoke()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_run bigint; v_owner text; v jsonb:='[]'::jsonb; v_fail int:=0; v_sig text;
  a int; b int; c int; d int; e int;
begin
  insert into agent_runs(agent,started_at) values('smoke',now()) returning id into v_run;
  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner from app_secrets where key='admin_emails';

  select count(*) into a from quotes q where q.status='revealed' and not exists(select 1 from transactions t where t.quote_id=q.id);
  if a>0 then v:=v||jsonb_build_object('check','revealed_quote_without_transaction','count',a); v_fail:=v_fail+1; end if;

  select count(*) into b from transactions where fee_status='paid' and coalesce(reveal_fee,0)<=0;
  if b>0 then v:=v||jsonb_build_object('check','paid_tx_zero_fee','count',b); v_fail:=v_fail+1; end if;

  -- 6 SEP 2026: EMAIL only. This counted the WhatsApp rows that wait on an unapproved Twilio template
  -- (the founder's input, not a broken write path) and paged him "data-integrity check failed" 20 times.
  -- 22 SEP 2026: 'sending' counts too — see the header. A claimed row whose sender never came back is
  -- the backlog this check exists to find, and it is the one shape it could not see.
  select count(*) into c from notifications where status in ('queued','sending') and channel='email' and created_at < now()-interval '2 hours';
  if c>0 then v:=v||jsonb_build_object('check','email_backlog_stuck','count',c); v_fail:=v_fail+1; end if;

  select count(*) into d from supplier_dues where coalesce(amount_due,0)<0 or amount_due is null;
  if d>0 then v:=v||jsonb_build_object('check','bad_due_amount','count',d); v_fail:=v_fail+1; end if;

  select count(*) into e from inquiries i where i.status='revealed' and not exists(select 1 from transactions t where t.inquiry_id=i.id);
  if e>0 then v:=v||jsonb_build_object('check','revealed_inquiry_without_tx','count',e); v_fail:=v_fail+1; end if;

  if v_fail>0 then
    insert into error_events(source,kind,severity,detail) values('smoke','integrity_violation','high',v);
    select coalesce(string_agg(x->>'check', ',' order by x->>'check'),'') into v_sig from jsonb_array_elements(v) x;
    if v_owner is not null and not exists(
         select 1 from notifications where type='smoke_alert'
           and created_at >= now() - interval '24 hours'
           and body like '%[sig:'||v_sig||']%') then
      insert into notifications(type,to_email,to_role,channel,subject,body)
        values('smoke_alert',v_owner,'admin','email','QuotesDone: data-integrity check failed',
          v_fail||' integrity check(s) failed: '||v::text||'. This usually means a recent change broke a write path. Open the IT agent. [sig:'||v_sig||']');
    end if;
  end if;
  update agent_runs set finished_at=now(),status='ok',counts=jsonb_build_object('checks',5,'failures',v_fail,'detail',v) where id=v_run;
  return jsonb_build_object('checks',5,'failures',v_fail,'detail',v);
end; $function$


CREATE OR REPLACE FUNCTION public.fn_spec_offer_answer(p_offer bigint, p_customer uuid, p_choice text, p_channel text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r public.spec_alternative_offer;
  v_alt jsonb;
  v_choice text := lower(btrim(coalesce(p_choice, '')));
begin
  if p_channel not in ('portal', 'whatsapp', 'email') then return jsonb_build_object('ok', false, 'error', 'bad_channel'); end if;
  select * into r from public.spec_alternative_offer where id = p_offer for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.customer_id is distinct from p_customer then return jsonb_build_object('ok', false, 'error', 'not_your_offer'); end if;
  if r.state <> 'open' then return jsonb_build_object('ok', false, 'error', 'not_open', 'state', r.state); end if;

  if v_choice in ('no', 'decline', 'declined') then
    update public.spec_alternative_offer set state = 'declined', closed_reason = 'no_exact_spec_declined', answered_at = now(),
           answer_channel = p_channel, updated_at = now() where id = r.id;
    perform public.fn_spec_offer_close_inquiry(r.inquiry_id, 'no_exact_spec_declined', r.id);
    return jsonb_build_object('ok', true, 'state', 'declined', 'offer_id', r.id, 'inquiry_id', r.inquiry_id, 'customer_id', r.customer_id, 'inquiry_closed', true);
  end if;

  select a into v_alt from jsonb_array_elements(r.alternatives) a where a->>'option_id' = v_choice limit 1;
  if v_alt is null then return jsonb_build_object('ok', false, 'error', 'unknown_option'); end if;
  update public.spec_alternative_offer set state = 'accepted', accepted_option = v_alt->>'option_id', accepted_value = v_alt->>'value',
         answered_at = now(), answer_channel = p_channel, updated_at = now() where id = r.id;
  update public.inquiries
     set accepted_alternatives = coalesce(accepted_alternatives, '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
           'offer_id', r.id, 'line_no', r.line_no, 'attr', r.attr, 'requested', r.requested,
           'accepted', v_alt->>'value', 'option_id', v_alt->>'option_id', 'at', now(), 'channel', p_channel))
   where id = r.inquiry_id;
  return jsonb_build_object('ok', true, 'state', 'accepted', 'offer_id', r.id, 'inquiry_id', r.inquiry_id, 'customer_id', r.customer_id,
    'accepted_value', v_alt->>'value', 'still_open', (select count(*) from public.spec_alternative_offer where inquiry_id = r.inquiry_id and state = 'open'));
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_spec_offer_candidates(p_limit integer DEFAULT 20)
 RETURNS TABLE(inquiry_id uuid, customer_id uuid, why text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with pol as (select coalesce((select (value #>> '{}')::numeric from public.decision_policy where key = 'spec_offer_quote_window_days'), 7) as days,
                      coalesce((select (value #>> '{}')::int from public.decision_policy where key = 'spec_offer_max_attempts'), 5) as max_attempts),
  inv as (
    select m.inquiry_id, count(distinct m.supplier_id) as invited, min(m.sent_at) as first_sent
      from public.inquiry_matches m group by m.inquiry_id),
  quoted as (
    select q.inquiry_id, count(distinct q.supplier_id) as quoted
      from public.quotes q where coalesce(q.status, '') <> 'draft' group by q.inquiry_id)
  select i.id, i.customer_id,
         case when coalesce(qd.quoted, 0) >= inv.invited then 'every_invited_supplier_quoted' else 'quote_window_closed' end
    from public.inquiries i
    join inv on inv.inquiry_id = i.id
    left join quoted qd on qd.inquiry_id = i.id
   where i.spec_offer_checked_at is null
     -- THE BACKOFF (22 Sep 2026): a failed check waits for its next attempt, and stops after the last one.
     and i.spec_offer_attempts < (select max_attempts from pol)
     and (i.spec_offer_next_attempt_at is null or i.spec_offer_next_attempt_at <= now())
     and coalesce(i.status, '') not in ('closed', 'completed', 'cancelled')
     and i.parent_inquiry_id is null
     -- THE TIMING GUARD (review of #652): at least one live (non-draft) quote.
     and exists (select 1 from public.quotes q1 where q1.inquiry_id = i.id and coalesce(q1.status, '') <> 'draft')
     and not exists (select 1 from public.transactions t join public.quotes q2 on q2.id = t.quote_id where q2.inquiry_id = i.id)
     and (coalesce(qd.quoted, 0) >= inv.invited or now() >= inv.first_sent + make_interval(days => (select days from pol)::int))
   order by i.created_at
   limit greatest(1, least(p_limit, 100));
$function$


CREATE OR REPLACE FUNCTION public.fn_spec_offer_close_inquiry(p_inquiry uuid, p_reason text, p_except bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_reason not in ('no_exact_spec_declined', 'no_exact_spec_no_reply') then raise exception 'spec offer: bad close reason %', p_reason; end if;
  update public.spec_alternative_offer set state = 'superseded', updated_at = now()
   where inquiry_id = p_inquiry and state = 'open' and id <> p_except;
  -- Nothing was revealed (a candidate never has a transaction), so nothing is charged.
  update public.inquiries set status = 'closed', lost_reason = p_reason, stage_changed_at = now() where id = p_inquiry;
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_spec_offer_due()
 RETURNS TABLE(offer_id bigint, action text, reminder_no integer, final boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with pol as (select coalesce((select value from public.decision_policy where key = 'spec_offer_reminder_after_hours'), '[24,48]'::jsonb) as hrs)
  select o.id,
         case when now() >= o.reply_by and o.reminders_sent >= jsonb_array_length((select hrs from pol)) then 'close_no_reply' else 'remind' end,
         o.reminders_sent + 1,
         o.reminders_sent + 1 = jsonb_array_length((select hrs from pol))
    from public.spec_alternative_offer o
   where o.state = 'open' and o.last_sent_at is not null
     and (
       (o.reminders_sent < jsonb_array_length((select hrs from pol))
        and now() >= o.opened_at + make_interval(secs => ((select hrs from pol) ->> o.reminders_sent)::numeric::int * 3600))
       or (now() >= o.reply_by and o.reminders_sent >= jsonb_array_length((select hrs from pol))))
   order by o.opened_at;
$function$


CREATE OR REPLACE FUNCTION public.fn_spec_offer_failed(p_inquiry uuid, p_error text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_max int := coalesce((select (value #>> '{}')::int from public.decision_policy where key = 'spec_offer_max_attempts'), 5);
  v_n int; v_next timestamptz;
begin
  update public.inquiries
     set spec_offer_attempts = spec_offer_attempts + 1,
         spec_offer_next_attempt_at = now() + make_interval(mins => (15 * power(2, least(spec_offer_attempts, 10)))::int)
   where id = p_inquiry
  returning spec_offer_attempts, spec_offer_next_attempt_at into v_n, v_next;
  if not found then return jsonb_build_object('ok', false, 'error', 'no_inquiry'); end if;
  if v_n >= v_max then
    perform public.fn_it_engineer_finding_upsert(
      'monitor:spec_offer_check_failed:' || p_inquiry,
      'The no-exact-spec check failed ' || v_n || ' times on inquiry ' || p_inquiry || ' and has stopped retrying',
      'sales_engineer spec_offer_sweep -> quote_compare (technical_only)', 'agent_facing', 1,
      jsonb_build_object('inquiry_id', p_inquiry, 'attempts', v_n, 'last_error', left(coalesce(p_error, ''), 300),
                         'owner_seat', 'sales_engineer',
                         'fix', 'find why quote_compare fails for this inquiry, then reset inquiries.spec_offer_attempts to 0 so the sweep checks it once more'),
      '{}'::text[], array['why quote_compare fails for this inquiry'], 'sales_engineer');
  end if;
  return jsonb_build_object('ok', true, 'attempts', v_n, 'next_attempt_at', v_next, 'handed_to_seat', v_n >= v_max);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_spec_offer_mark(p_offer bigint, p_action text, p_notification_ids jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.spec_alternative_offer;
begin
  select * into r from public.spec_alternative_offer where id = p_offer for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_action = 'sent' then
    update public.spec_alternative_offer set last_sent_at = now(), notification_ids = notification_ids || coalesce(p_notification_ids, '[]'::jsonb), updated_at = now() where id = r.id;
  elsif p_action = 'remind' then
    if r.state <> 'open' then return jsonb_build_object('ok', false, 'error', 'not_open', 'state', r.state); end if;
    update public.spec_alternative_offer set reminders_sent = reminders_sent + 1, last_sent_at = now(),
           notification_ids = notification_ids || coalesce(p_notification_ids, '[]'::jsonb), updated_at = now() where id = r.id;
  elsif p_action = 'close_no_reply' then
    if r.state <> 'open' then return jsonb_build_object('ok', false, 'error', 'not_open', 'state', r.state); end if;
    update public.spec_alternative_offer set state = 'no_reply', closed_reason = 'no_exact_spec_no_reply',
           notification_ids = notification_ids || coalesce(p_notification_ids, '[]'::jsonb), updated_at = now() where id = r.id;
    perform public.fn_spec_offer_close_inquiry(r.inquiry_id, 'no_exact_spec_no_reply', r.id);
  elsif p_action = 'answered' then
    update public.spec_alternative_offer set notification_ids = notification_ids || coalesce(p_notification_ids, '[]'::jsonb), updated_at = now() where id = r.id;
  else
    return jsonb_build_object('ok', false, 'error', 'bad_action');
  end if;
  return jsonb_build_object('ok', true, 'offer_id', r.id, 'action', p_action);
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_spec_offer_open(p_inquiry uuid, p_offers jsonb)
 RETURNS SETOF spec_alternative_offer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_hours numeric := coalesce((select (value #>> '{}')::numeric from public.decision_policy where key = 'spec_offer_reply_window_hours'), 72);
  v_cust uuid;
  o jsonb;
begin
  select customer_id into v_cust from public.inquiries where id = p_inquiry for update;
  if not found then raise exception 'spec offer: no inquiry %', p_inquiry; end if;
  update public.inquiries set spec_offer_checked_at = coalesce(spec_offer_checked_at, now()) where id = p_inquiry;
  for o in select * from jsonb_array_elements(coalesce(p_offers, '[]'::jsonb)) loop
    insert into public.spec_alternative_offer (inquiry_id, customer_id, line_no, item, attr, label_en, label_ar, requested, alternatives, reply_by)
    values (p_inquiry, v_cust, (o->>'line_no')::int, o->>'item', o->>'attr', o->>'label_en', o->>'label_ar', o->>'requested', o->'alternatives',
            now() + make_interval(secs => (v_hours * 3600)::int))
    on conflict (inquiry_id, line_no, attr) where state in ('open', 'accepted') do nothing;
  end loop;
  return query select * from public.spec_alternative_offer where inquiry_id = p_inquiry and state = 'open' order by line_no, attr;
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_spec_offer_restart_clock(p_offer bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  update public.spec_alternative_offer
     set reply_by = now() + (reply_by - opened_at), opened_at = now()
   where id = p_offer and state = 'open' and last_sent_at is null and opened_at < now();
  return found;
end $function$


CREATE OR REPLACE FUNCTION public.fn_spec_offer_whatsapp_reply(p_phone text, p_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_digits text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_cust uuid;
  v_matches int;
  v_ref text;
  r public.spec_alternative_offer;
  v_t text := lower(btrim(translate(coalesce(p_text, ''), '٠١٢٣٤٥٦٧٨٩', '0123456789')));
  v_n int;
  v_choice text;
begin
  if length(v_digits) < 8 then return jsonb_build_object('handled', false, 'reason', 'no_phone'); end if;
  -- The text's SHAPE first: only something that looks like an answer (a no, an option number, a bare
  -- yes) goes any further. Otherwise a number two customers share would open a support case for
  -- every "hello" it sends.
  v_t := regexp_replace(v_t, '[[:space:][:punct:]]+$', '');
  if not (v_t ~ '^(no|no thanks|decline|لا|لأ|لا شكرا|لا شكرًا)$'
          or v_t ~ '^(option |choice |yes |نعم |الخيار )?[0-9]{1,2}$'
          or v_t ~ '^(yes|ok|نعم|موافق)$') then
    return jsonb_build_object('handled', false, 'reason', 'not_a_reply');
  end if;
  -- Who the sender is: fn_whatsapp_owner alone decides (a verified 'other' WhatsApp number or a verified
  -- 'same' mobile). p_all, so a number several customers share is still reported below, never guessed.
  select count(*), min(w.customer_id::text)::uuid into v_matches, v_cust
    from public.fn_whatsapp_owner(p_phone, true) as w
   where w.party_kind = 'customer'
     and exists (select 1 from public.spec_alternative_offer o where o.customer_id = w.customer_id and o.state = 'open');
  if v_matches = 0 then return jsonb_build_object('handled', false, 'reason', 'no_verified_customer_with_open_offer'); end if;
  if v_matches > 1 then
    v_ref := 'SE-SPECOFFER-AMBIG-' || right(v_digits, 9) || '-' || to_char(now(), 'YYYYMMDD');
    insert into public.support_case (case_ref, party_kind, party_id, subject, owner_role_id)
    values (v_ref, 'unknown', null,
            'From the sales engineer: a WhatsApp answer to a no-exact-spec offer came from a number that ' || v_matches ||
            ' verified customers with open offers share. Nothing was recorded. Confirm with the customer which request it is for, then record it from the portal.',
            'customer_support')
    on conflict (case_ref) do nothing;
    return jsonb_build_object('handled', false, 'reason', 'ambiguous_sender', 'case_ref', v_ref, 'matches', v_matches);
  end if;
  select * into r from public.spec_alternative_offer where customer_id = v_cust and state = 'open' order by opened_at, id limit 1;
  if not found then return jsonb_build_object('handled', false, 'reason', 'no_open_offer'); end if;
  v_t := regexp_replace(v_t, '[[:space:][:punct:]]+$', '');
  if v_t ~ '^(no|no thanks|decline|لا|لأ|لا شكرا|لا شكرًا)$' then v_choice := 'no';
  elsif v_t ~ '^(option |choice |yes |نعم |الخيار )?[0-9]{1,2}$' then
    v_n := (regexp_replace(v_t, '\D', '', 'g'))::int;
    if v_n < 1 or v_n > jsonb_array_length(r.alternatives) then return jsonb_build_object('handled', true, 'ok', false, 'error', 'unknown_option', 'offer_id', r.id, 'options', jsonb_array_length(r.alternatives)); end if;
    v_choice := r.alternatives -> (v_n - 1) ->> 'option_id';
  elsif v_t ~ '^(yes|ok|نعم|موافق)$' and jsonb_array_length(r.alternatives) = 1 then v_choice := r.alternatives -> 0 ->> 'option_id';
  else return jsonb_build_object('handled', false, 'reason', 'not_a_reply', 'offer_id', r.id);
  end if;
  return jsonb_build_object('handled', true) || public.fn_spec_offer_answer(r.id, v_cust, v_choice, 'whatsapp');
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_stalled_inquiry_flag(p_inquiry_id uuid, p_by text DEFAULT 'sales_engineer'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  i public.inquiries; v_fixture boolean; v_quotes int; v_matched int; v_reach int; v_busy int; v_paused int;
  v_blocked int; v_back date; v_trades text[]; v_trade_busy int; v_trade_paused int; v_trade_back date;
  v_open boolean; v_detail jsonb; v_by text := coalesce(nullif(btrim(p_by), ''), 'sales_engineer');
  v_prev_reason text; v_prev_cleared timestamptz; v_had boolean; v_written int;   -- 29 Sep 2026 (review of #1106)
begin
  select * into i from public.inquiries where id = p_inquiry_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'no such inquiry'); end if;
  -- 29 Sep 2026 (review of #1106): only this intake's own reason
  v_open := exists (select 1 from public.stalled_inquiry_rescue where inquiry_id = i.id and cleared_at is null and reason = 'no_reachable_supplier');

  select count(*)::int into v_quotes from public.quotes q
   where q.inquiry_id = i.id
     and coalesce(q.status, '') not in ('draft', 'withdrawn', 'rejected', 'expired', 'held', 'cancelled')
     and q.stale_at is null;

  if coalesce(i.status, '') not in ('sent', 'quoted') or v_quotes > 0 then
    if v_open then
      update public.stalled_inquiry_rescue set cleared_at = now(),
             cleared_why = case when v_quotes > 0 then v_quotes || ' live quote(s)' else 'inquiry is ' || coalesce(i.status, 'null') end
       where inquiry_id = i.id and cleared_at is null and reason = 'no_reachable_supplier';   -- 29 Sep 2026: own reason only
    end if;
    return jsonb_build_object('ok', true, 'inquiry_id', i.id, 'flagged', false, 'cleared', v_open,
                              'why', case when v_quotes > 0 then 'quoted' else 'not open' end);
  end if;

  select count(*)::int,
         count(*) filter (where public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
                            and public.fn_supplier_available(av.state, av.busy_until))::int,
         count(*) filter (where not public.fn_supplier_available(av.state, av.busy_until) and av.state = 'busy')::int,
         count(*) filter (where not public.fn_supplier_available(av.state, av.busy_until) and av.state = 'paused')::int,
         count(*) filter (where not public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes))::int,
         min(av.busy_until) filter (where not public.fn_supplier_available(av.state, av.busy_until))
    into v_matched, v_reach, v_busy, v_paused, v_blocked, v_back
    from public.inquiry_matches m
    join public.leads l on l.id = m.supplier_id
    left join public.supplier_availability av on av.supplier_id = m.supplier_id
   where m.inquiry_id = i.id;

  if v_reach > 0 then
    if v_open then
      update public.stalled_inquiry_rescue set cleared_at = now(), cleared_why = v_reach || ' reachable supplier(s)'
       where inquiry_id = i.id and cleared_at is null and reason = 'no_reachable_supplier';   -- 29 Sep 2026: own reason only
    end if;
    return jsonb_build_object('ok', true, 'inquiry_id', i.id, 'flagged', false, 'cleared', v_open, 'reachable', v_reach);
  end if;

  -- Nobody can reach it. Say why, for the rescue: the matched suppliers' states, and the suppliers of its
  -- trades who confirmed their scope and are matchable but said busy or paused (the trade gate only: role,
  -- authority, value and emirate are the matcher's, not repeated here).
  v_trades := public.fn_taxonomy_trades_for(case when coalesce(cardinality(i.trades), 0) > 0 then i.trades
                                                 else array[coalesce(i.category, '')] end);
  select count(*) filter (where av.state = 'busy')::int, count(*) filter (where av.state = 'paused')::int, min(av.busy_until)
    into v_trade_busy, v_trade_paused, v_trade_back
    from public.supplier_capabilities sc
    join public.leads l on l.id = sc.supplier_id
    join public.supplier_availability av on av.supplier_id = sc.supplier_id
   where sc.confirmed_at is not null
     and sc.trades && coalesce(v_trades, '{}'::text[])
     and not (sc.excluded_trades && coalesce(v_trades, '{}'::text[]))
     and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
     and not public.fn_supplier_available(av.state, av.busy_until);

  select public.fn_seat_clock_customer_is_fixture(c) into v_fixture from public.customers c where c.id = i.customer_id;
  v_detail := jsonb_build_object(
    'matched', v_matched, 'reachable', 0, 'matched_busy', v_busy, 'matched_paused', v_paused, 'matched_not_matchable', v_blocked,
    'earliest_back', v_back, 'trades', to_jsonb(v_trades), 'category', i.category, 'emirate', i.emirate,
    'in_trade_busy', coalesce(v_trade_busy, 0), 'in_trade_paused', coalesce(v_trade_paused, 0), 'in_trade_earliest_back', v_trade_back,
    'matcher_unavailable', coalesce((i.routing->>'matcher_unavailable')::boolean, false), 'at', now());

  -- 29 Sep 2026 (review of #1106 at 3d1bbb8): the WRITE is filtered too. An open row of the other reason (no_quote_48h)
  -- is the rescue's, already acted on: it is not touched and not counted. A cleared row, of either reason, is reopened as
  -- this reason with the rescue's own record reset, so the rescue acts on it afresh and the customer hears this reason.
  select x.reason, x.cleared_at into v_prev_reason, v_prev_cleared from public.stalled_inquiry_rescue x where x.inquiry_id = i.id;
  v_had := found;
  insert into public.stalled_inquiry_rescue (inquiry_id, reason, detail, fixture, flagged_at, flagged_by)
  values (i.id, 'no_reachable_supplier', v_detail, coalesce(v_fixture, false), now(), v_by)
  on conflict (inquiry_id) do update
     set reason = excluded.reason, detail = excluded.detail, fixture = excluded.fixture,
         -- an open flag keeps the time it was first raised; a cleared one is raised again from now
         flagged_at = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.flagged_at else excluded.flagged_at end,
         flagged_by = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.flagged_by else excluded.flagged_by end,
         -- reopened: the rescue's record starts over (an open own-reason row keeps what the rescue already did)
         acted_at        = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.acted_at end,
         customer_notice = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.customer_notice end,
         enqueue_result  = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.enqueue_result end,
         trades          = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.trades end,
         uninvited_pool  = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.uninvited_pool end,
         plan_rank       = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.plan_rank end,
         finding_key     = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.finding_key end,
         matched_at      = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.matched_at end,
         stalled_hours   = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.stalled_hours end,
         cleared_at = null, cleared_why = null
   where stalled_inquiry_rescue.reason = 'no_reachable_supplier' or stalled_inquiry_rescue.cleared_at is not null;
  get diagnostics v_written = row_count;
  if v_written = 0 then
    -- open under the other reason: already in the rescue; nothing written, nothing counted
    return jsonb_build_object('ok', true, 'inquiry_id', i.id, 'flagged', false, 'new', false, 'in_rescue_as', v_prev_reason);
  end if;
  return jsonb_build_object('ok', true, 'inquiry_id', i.id, 'flagged', true,
                            'new', not v_had or v_prev_cleared is not null, 'detail', v_detail);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_strategy_metrics()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare res jsonb;
begin
  with dem as (select category, count(*) rfqs from inquiries
                where created_at > now()-interval '90 days' and category is not null and not public.fn_inquiry_is_demo(id)
                group by category),
  sup as (select i.category, count(distinct q.supplier_id) sups from quotes q join inquiries i on i.id=q.inquiry_id
           where q.created_at > now()-interval '90 days' and i.category is not null
             and not public.fn_inquiry_is_demo(i.id)
             and not exists (select 1 from leads l where l.id = q.supplier_id and l.is_demo)
           group by i.category)
  select jsonb_build_object(
    'under_supplied', (select coalesce(jsonb_agg(x order by x.rfqs desc),'[]'::jsonb) from (
        select d.category, d.rfqs, coalesce(s.sups,0) as active_suppliers
        from dem d left join sup s on s.category=d.category
        where coalesce(s.sups,0) < greatest(2, d.rfqs/3) order by d.rfqs desc limit 12) x),
    'coverage', jsonb_build_object(
        'categories_total', (select count(*) from category_specs),
        'with_requirements', (select count(*) from category_specs where supplier_requirements is not null),
        'with_playbook', (select count(distinct category) from qualification_playbooks where status='active'),
        'regulation_category_tags', (select count(distinct c) from regulations r, unnest(coalesce(r.categories,'{}')) c where r.status='active')),
    'funnel', (select coalesce(fn_marketplace_analytics(),'{}'::jsonb))
  ) into res;
  return res;
end $function$


CREATE OR REPLACE FUNCTION public.fn_stripe_dispute_counts_the_customer()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_c uuid;
begin
  select customer_id into v_c from public.transactions where id = new.transaction_id;
  if v_c is null then return new; end if;
  update public.customers c
     set disputes_filed = (select count(*) from public.stripe_dispute d join public.transactions t on t.id = d.transaction_id
                            where t.customer_id = v_c)
   where c.id = v_c;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_stripe_event_seen(p_event_id text, p_type text, p_status text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  INSERT INTO public.stripe_events (event_id, type, payment_status)
  VALUES (p_event_id, p_type, p_status)
  ON CONFLICT (event_id) DO UPDATE
    SET last_seen_at = now(),
        delivery_count = public.stripe_events.delivery_count + 1;
$function$


CREATE OR REPLACE FUNCTION public.fn_subscription_billing_run(p_dry_run boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_flagged int := 0; v_cfg record;
begin
  select * into v_cfg from public.fn_supplier_subscription();
  for r in
    select b.* from public.v_supplier_billing b
     where b.billing_status in ('due', 'past_due')
       and coalesce(b.email, '') <> ''
       and not exists (select 1 from public.notifications n
                        where n.type = 'subscription_due' and n.lead_id = b.supplier_id
                          and n.created_at > now() - interval '30 days')
  loop
    if not p_dry_run then
      update public.leads set registration_fee_due = v_cfg.fee, registration_status = 'due' where id = r.supplier_id;
      perform public.fn_seat_handoff('accountant', 'sales_engineer', 'subscription.due', 'leads',
        r.supplier_id || ':' || to_char(current_date, 'YYYY-MM'),
        jsonb_build_object('supplier_id', r.supplier_id, 'fee', v_cfg.fee, 'currency', v_cfg.currency));
    end if;
    v_flagged := v_flagged + 1;
  end loop;

  if v_flagged > 0 and not p_dry_run then
    perform public.fn_seat_handoff('accountant', 'customer_support', 'delivery.request', 'founder',
      'subscription_billing_summary:' || current_date,
      jsonb_build_object('recipient_role', 'founder', 'kind', 'finance_reminder', 'level', 'info',
        'event', 'Supplier subscriptions invoiced',
        'detail', v_flagged || ' supplier(s) were invoiced ' || v_cfg.currency || ' ' || v_cfg.fee
                  || ' for their annual subscription. Founding suppliers (first ' || v_cfg.free_limit || ') are exempt and were not billed.',
        'dedupe_key', 'subscription_billing_summary:' || current_date));
  end if;

  return json_build_object('billing_starts', v_cfg.start_date, 'fee', v_cfg.fee, 'currency', v_cfg.currency,
    'free_limit', v_cfg.free_limit, 'invoiced', v_flagged, 'dry_run', p_dry_run, 'ran_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_advisor(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with l as (select * from public.leads where id = p_lead_id),
  s as (select * from public.supplier_score where lead_id = p_lead_id),
  q as (
    select count(*)::int submitted,
           greatest(count(*) filter (where status = 'won')::int,
                    (select count(*)::int from public.inquiries where hired_supplier_id = p_lead_id)) won,
           count(*) filter (where status in ('rejected', 'lost', 'declined'))::int rejected
    from public.quotes where supplier_id = p_lead_id
  ),
  rr as (select coalesce((select rv_response_rate from l), (select response_rate from s)) rate),
  home as (select * from public.fn_supplier_document_home(p_lead_id)),
  cap as (select confirmed_at from public.supplier_capabilities where supplier_id = p_lead_id),
  live_inq as (
    select count(*) as n from public.inquiries i
    where coalesce(i.status, '') not in ('closed', 'cancelled', 'expired')
  ),
  gaps as (
    select g.* from (
      select 'trade_licence' as key, 'Upload your trade licence' as action, 'ارفع الرخصة التجارية' as action_ar,
             'You cannot be matched to any opportunity without a current trade licence.' as why,
             'لا يمكن مطابقتكم مع أي فرصة دون رخصة تجارية سارية.' as why_ar,
             'high' as severity, 'documents' as goes_to, 1 as sort
      where (select path from home where key = 'trade_licence') is null
      union all
      select 'licence_expired', 'Replace your expired trade licence', 'استبدل الرخصة التجارية المنتهية',
             'Your trade licence expired on ' || to_char(l.license_expiry, 'DD Mon YYYY') || '.',
             'انتهت صلاحية رخصتكم التجارية في ' || to_char(l.license_expiry, 'DD Mon YYYY') || '.',
             'high', 'documents', 2
      from l where (select path from home where key = 'trade_licence') is not null
                and l.license_expiry is not null and l.license_expiry < current_date
      union all
      select 'iso_certificate', 'Upload an ISO certificate', 'ارفع شهادة ISO',
             'Buyers filter on ISO 9001 and 14001. Adding one opens the projects that require it.',
             'يفرز العملاء المورّدين بحسب شهادتي ISO 9001 و14001، وإضافتها تتيح لكم المشاريع التي تشترطها.',
             'medium', 'documents', 3
      where (select path from home where key = 'iso') is null
      union all
      select 'iso_expired', 'Renew your ISO certificate', 'جدّد شهادة ISO',
             'Your ISO certificate expired on ' || to_char((select expiry from home where key = 'iso'), 'DD Mon YYYY') || '.',
             'انتهت صلاحية شهادة ISO في ' || to_char((select expiry from home where key = 'iso'), 'DD Mon YYYY') || '.',
             'high', 'documents', 4
      where (select expiry from home where key = 'iso') < current_date
      union all
      select 'not_verified', 'Complete verification', 'أكمل التحقق',
             'Unverified suppliers are excluded from matching entirely.',
             'لا يدخل المطابقة إلا المورّدون الموثَّقون.',
             'high', 'profile', 5
      from l where not coalesce(l.verified, false)
      union all
      -- The gate matching actually opens on (fn_match_capability: confirmed_at), pointed at the tab
      -- where it is confirmed. This replaced a "capability summary" gap that named a machine-filled
      -- column the supplier has no field for (audit 21 Sep 2026, finding 20).
      select 'services_unconfirmed', 'Confirm your services', 'أكّد الخدمات المقدَّمة',
             'Requests are matched on the services you confirm. Nothing reaches you until they are confirmed.',
             'تُطابَق الطلبات مع الخدمات التي تؤكّدونها، ولن يصلكم أي طلب قبل تأكيدها.',
             'high', 'services', 6
      where (select confirmed_at from cap) is null
      union all
      select 'no_products', 'Upload a product catalogue', 'ارفع كتالوج المنتجات',
             'Your catalogue is what buyers search. Without it you compete on company name alone.',
             'يبحث العملاء في الكتالوج، ومن دونه تنافسون باسم الشركة وحده.',
             'medium', 'products', 7
      from l where not exists (select 1 from public.supplier_product sp where sp.supplier_id = l.id)
      union all
      select 'no_service_area', 'Set the emirates you serve', 'حدّد الإمارات التي تغطيها',
             'Opportunities are filtered by location before anything else is considered.',
             'تُفرز الفرص بحسب الموقع قبل أي اعتبار آخر.',
             'medium', 'profile', 8
      from l where coalesce(array_length(l.service_emirates, 1), 0) = 0
      union all
      select 'slow_response', 'Improve your response time', 'حسّن سرعة الاستجابة',
             'Your response rate is ' || round((select rate from rr))::text || '%. Buyers see it, and it is 55% of your reliability score.',
             'معدل استجابتكم ' || round((select rate from rr))::text || '%، وهو ظاهر للعملاء ويشكّل 55% من تقييم موثوقيتكم.',
             'medium', 'twin', 9
      where (select rate from rr) is not null and (select rate from rr) < 60
    ) g
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'loss_analysis', jsonb_build_object(
      'quotes_submitted', (select submitted from q),
      'quotes_won',       (select won from q),
      'rejections',       (select rejected from q),
      'response_rate',    (select rate from rr),
      'loss_reasons', case
        when (select submitted from q) = 0 then '[]'::jsonb
        else jsonb_build_array(
          jsonb_build_object('reason', 'Rejected after quoting', 'reason_ar', 'رُفض بعد التسعير', 'count', (select rejected from q),
            'pct', round(100.0 * (select rejected from q) / nullif((select submitted from q), 0)))
        ) end,
      'basis', case when (select submitted from q) = 0 then 'no_completed_opportunities' else 'quotes_submitted' end
    ),
    'recommendations', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'key', g.key, 'action', g.action, 'action_ar', g.action_ar, 'why', g.why, 'why_ar', g.why_ar,
        'severity', g.severity, 'goes_to', g.goes_to,
        'impact_rfqs', (select n from live_inq)
      ) order by g.sort), '[]'::jsonb) from gaps g
    ),
    'gap_count', (select count(*) from gaps),
    'impact_basis', jsonb_build_object(
      'live_inquiries', (select n from live_inq),
      'note', 'impact_rfqs counts live inquiries a closed gap would let this supplier compete for'
    ),
    'headline', (
      select case
        when (select count(*) from gaps) = 0
          then 'Your profile is complete. You are eligible for every opportunity we can match.'
        when (select n from live_inq) = 0
          then 'You have ' || (select count(*) from gaps)::text
               || ' gap(s) blocking you from being matched at all. Start with: '
               || (select g.action from gaps g order by g.sort limit 1)
               || '. There are no live opportunities right now, so there is time to fix them.'
        else 'Your profile can qualify for ' || (select n from live_inq)::text
             || ' more opportunities if you close ' || (select count(*) from gaps)::text
             || ' gap(s), starting with: ' || (select g.action from gaps g order by g.sort limit 1) || '.'
      end
    ),
    'headline_ar', (
      select case
        when (select count(*) from gaps) = 0
          then 'ملفكم مكتمل، وأنتم مؤهَّلون لكل فرصة يمكننا مطابقتها.'
        when (select n from live_inq) = 0
          then 'عدد النواقص التي تحول دون مطابقتكم: ' || (select count(*) from gaps)::text
               || '. الخطوة الأولى: '
               || (select g.action_ar from gaps g order by g.sort limit 1)
               || '. لا توجد فرص مفتوحة حاليًا، فأمامكم متسع من الوقت لاستكمالها.'
        else 'يمكن أن يتأهّل ملفكم لعدد ' || (select n from live_inq)::text
             || ' من الفرص الإضافية إذا استكملتم النواقص (' || (select count(*) from gaps)::text
             || '). الخطوة الأولى: ' || (select g.action_ar from gaps g order by g.sort limit 1) || '.'
      end
    )
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_agreement_version_no(p_version text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select nullif(regexp_replace(coalesce(p_version, ''), '[^0-9]', '', 'g'), '')::int
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_apply_change(p_phone text, p_field text, p_value text, p_inbound text, p_quote_id uuid DEFAULT NULL::uuid, p_channel text DEFAULT 'whatsapp'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_lead bigint; v_num numeric; v_q record; v_n int; v_refusal text; v_old numeric; v_list text;
        v_company text;
begin
  -- SCOPE FIRST, AND FROM THE PHONE. Nothing downstream takes a supplier id from the caller.
  v_lead := public.fn_wa_lead_id(p_phone);
  if v_lead is null then
    insert into public.channel_directive(actor_type, actor_phone, channel, inbound, field, applied, refusal)
    values ('supplier', p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, false, 'no supplier account matches this number');
    return jsonb_build_object('ok', false, 'refusal',
      'This number is not linked to a supplier account, so there is nothing of yours I can change. Sign in at https://quotesdone.com/suppliers.');
  end if;
  select company_name into v_company from public.leads where id = v_lead;

  if not exists (select 1 from public.fn_supplier_changeable() c where c.field = p_field) then
    v_refusal := 'I cannot change "' || coalesce(p_field,'(nothing)') || '" from a message. What I can change this way: '
              || (select string_agg(c.field, ', ' order by c.field) from public.fn_supplier_changeable() c)
              || '. Everything else — your licence, your company details, and generating a new quotation — is in the portal.';
    insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, applied, refusal)
    values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, false, v_refusal);
    return jsonb_build_object('ok', false, 'refusal', v_refusal);
  end if;

  begin v_num := p_value::numeric; exception when others then v_num := null; end;
  if v_num is null or v_num <= 0 then
    v_refusal := '"' || coalesce(p_value,'') || '" is not an amount I can put on a quotation.';
    insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, applied, refusal)
    values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, false, v_refusal);
    return jsonb_build_object('ok', false, 'refusal', v_refusal);
  end if;

  -- WHICH QUOTATION. Editable means: theirs, still open, nobody has paid to reveal them, not
  -- committed, not already accepted. Each of those is a different reason and each gets said.
  select count(*) into v_n
    from public.quotes q
    join public.inquiries i on i.id = q.inquiry_id
   where q.supplier_id = v_lead
     and (p_quote_id is null or q.id = p_quote_id)
     and q.committed_at is null
     and coalesce(q.status,'') not in ('accepted','withdrawn','expired')
     and coalesce(i.status,'') not in ('concluded','closed','cancelled','awarded')
     and not exists (select 1 from public.transactions t
                      where t.inquiry_id = q.inquiry_id and t.supplier_id = q.supplier_id
                        and t.revealed_at is not null);

  if v_n = 0 then
    -- Say WHY there is nothing to change rather than "no quotation found", which is true of a
    -- supplier who has never quoted and of one whose customer paid an hour ago.
    select string_agg(distinct r, '; ') into v_refusal from (
      select case
               when q.committed_at is not null then 'one is committed and cannot be re-priced'
               when coalesce(q.status,'') = 'accepted' then 'one has already been accepted'
               when exists (select 1 from public.transactions t where t.inquiry_id = q.inquiry_id
                             and t.supplier_id = q.supplier_id and t.revealed_at is not null)
                 then 'the customer has already paid to reveal you on one, so the price they paid to see stands'
               else 'the request is closed on one' end as r
        from public.quotes q where q.supplier_id = v_lead
         and (p_quote_id is null or q.id = p_quote_id)) z;
    v_refusal := coalesce('I cannot change a price right now: ' || v_refusal || '.',
                          'You have no open quotation for me to re-price. You can send a new one from the portal.');
    insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, applied, refusal)
    values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, false, v_refusal);
    return jsonb_build_object('ok', false, 'refusal', v_refusal);
  end if;

  if v_n > 1 then
    select string_agg(i.category || ' in ' || coalesce(i.emirate,'the UAE') || ' (currently AED ' || q.quote_amount || ')', '; ' order by q.created_at desc)
      into v_list
      from public.quotes q join public.inquiries i on i.id = q.inquiry_id
     where q.supplier_id = v_lead and q.committed_at is null
       and coalesce(q.status,'') not in ('accepted','withdrawn','expired');
    v_refusal := 'You have ' || v_n || ' open quotations, so I will not guess which one you mean: ' || v_list
              || '. Tell me which, or change it in the portal.';
    insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, applied, refusal)
    values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, false, v_refusal);
    return jsonb_build_object('ok', false, 'refusal', v_refusal, 'open_quotes', v_n);
  end if;

  select q.* into v_q
    from public.quotes q join public.inquiries i on i.id = q.inquiry_id
   where q.supplier_id = v_lead
     and (p_quote_id is null or q.id = p_quote_id)
     and q.committed_at is null
     and coalesce(q.status,'') not in ('accepted','withdrawn','expired')
     and coalesce(i.status,'') not in ('concluded','closed','cancelled','awarded')
     and not exists (select 1 from public.transactions t
                      where t.inquiry_id = q.inquiry_id and t.supplier_id = q.supplier_id
                        and t.revealed_at is not null);
  v_old := v_q.quote_amount;

  -- THE FAT-FINGER BOUND. A supplier may price their own work at whatever they like — that is
  -- their commercial decision and not ours. But this arrives as a sentence typed on a phone, where
  -- a missing or extra zero is one keystroke, and a quotation is a number a customer will compare
  -- against others and pay to unlock. Beyond half up or half down, the portal asks for it twice.
  if v_old is not null and v_old > 0 and (v_num > v_old * 1.5 or v_num < v_old * 0.5) then
    v_refusal := 'That would move the price from AED ' || v_old || ' to AED ' || v_num
              || ', which is more than half up or down. I have not changed it — if you do mean that, please set it in the portal so you can see the whole quotation while you do.';
    insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, target_id, old_value, new_value, applied, refusal)
    values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, v_q.id::text, v_old::text, v_num::text, false, v_refusal);
    return jsonb_build_object('ok', false, 'refusal', v_refusal, 'old', v_old, 'asked', v_num);
  end if;

  if v_old is not distinct from v_num then
    insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, target_id, old_value, new_value, applied, refusal)
    values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, v_q.id::text, v_old::text, v_num::text, false, 'already at that value');
    return jsonb_build_object('ok', true, 'unchanged', true, 'old', v_old, 'new', v_num,
      'message', 'Your quotation is already AED ' || v_num || '. Nothing to change.');
  end if;

  update public.quotes set quote_amount = v_num where id = v_q.id;

  insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, target_id, old_value, new_value, applied)
  values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, v_q.id::text, v_old::text, v_num::text, true);

  insert into public.agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('supplier_directive', 'ok',
          jsonb_build_object('lead_id', v_lead, 'quote_id', v_q.id, 'old', v_old, 'new', v_num, 'channel', p_channel),
          coalesce(v_company,'lead ' || v_lead) || ' changed a quotation from AED ' || coalesce(v_old::text,'(unset)')
          || ' to AED ' || v_num || ' by ' || p_channel || '. Instruction: ' || left(coalesce(p_inbound,''),200),
          now(), now());

  return jsonb_build_object('ok', true, 'quote_id', v_q.id, 'old', v_old, 'new', v_num,
    'message', 'Done — your quotation is now AED ' || v_num || ' (it was AED ' || coalesce(v_old::text,'unset') || '). The customer sees the new price from now on.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_approved_notice_compose(p leads)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_site text; v_link text; v_name text := nullif(btrim(coalesce(p.company_name, '')), ''); v_cats text; v_n int; v_body text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  v_link := coalesce(v_site, 'https://quotesdone.com') || '/portal';
  select string_agg('• ' || coalesce(t.label, c), E'\n' order by coalesce(t.label, c)), count(*) into v_cats, v_n
    from public.supplier_capabilities sc
    cross join lateral unnest(case when sc.confirmed_at is not null and cardinality(sc.trades) > 0 then sc.trades
                                   else array(select x from unnest(coalesce(sc.proposed_trades, '{}')) x
                                               where x <> all (coalesce(sc.excluded_trades, '{}'))) end) c
    left join public.taxonomy_trade t on t.code = c
   where sc.supplier_id = p.id;

  v_body := coalesce('Dear ' || v_name || ',', 'Dear Sir or Madam,') || E'\n\n'
    || 'Your company is now verified on QuotesDone. Our sales engineer has reviewed your registration documents, and your supplier account is approved.'
    || E'\n\n'
    || case when coalesce(v_n, 0) > 0
         then 'From your documents we have set these categories for your company:' || E'\n' || v_cats
         else 'We could not read any categories from your documents, so none are set yet. Until you add them, no inquiry can reach you.' end
    || E'\n\nWhat to do now (about two minutes):'
    || E'\n1. Open your supplier portal: ' || v_link
    || E'\n2. In the Services tab, check that the categories are correct, and press "Remove this trade" for any your company does not work in.'
    || E'\n3. Add any categories and services we missed, then press "Confirm my services".'
    || E'\n\nInquiries are matched to the categories and services you confirm, so the sooner you confirm them, the sooner the right inquiries reach you.'
    || E'\n\nNeed help? Reply to this e-mail or message us on WhatsApp.'
    || E'\n\nKind regards,\nQuotesDone Customer Support';
  return jsonb_build_object('lang', 'en', 'subject', 'You are verified on QuotesDone: please confirm your categories',
                            'body', v_body, 'link', v_link, 'categories', coalesce(v_n, 0));
end
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_availability_of(p_supplier_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
    when a.supplier_id is null or public.fn_supplier_available(a.state, a.busy_until)
      then jsonb_build_object('state', 'available', 'busy_until', null, 'set_at', a.set_at, 'matched', true)
    else jsonb_build_object('state', a.state, 'busy_until', a.busy_until, 'set_at', a.set_at, 'matched', false)
  end
  from (select 1) one
  left join public.supplier_availability a on a.supplier_id = p_supplier_id;
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_available(p_state text, p_busy_until date)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(p_state, 'available') = 'available'
      or (p_state = 'busy' and p_busy_until <= (now() at time zone 'Asia/Dubai')::date);
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_beneficial_owner_record(p_lead_id bigint, p_full_name text, p_source text, p_nationality text DEFAULT NULL::text, p_share_pct numeric DEFAULT NULL::numeric)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint;
begin
  insert into public.supplier_beneficial_owner as o (lead_id, full_name, source, nationality, share_pct, verified_at)
  values (p_lead_id, btrim(p_full_name), p_source, nullif(btrim(p_nationality), ''), p_share_pct, now())
  on conflict (lead_id, lower(btrim(full_name))) do update
     set source = excluded.source, nationality = coalesce(excluded.nationality, o.nationality),
         share_pct = coalesce(excluded.share_pct, o.share_pct), verified_at = now()
  returning o.id into v_id;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_campaign_day_counts(p_day date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with d as (select coalesce(p_day, (now() at time zone 'Asia/Dubai')::date) as d_day)
  select jsonb_build_object('day', d.d_day,
    'sent', (select count(*) from public.notifications n where n.type = 'supplier_invite' and n.status = 'sent'
               and not public.fn_is_demo_email(n.to_email) and (n.sent_at at time zone 'Asia/Dubai')::date = d.d_day),
    'bounced', (select count(*) from public.email_suppressions s where s.reason ilike '%bounce%'
                  and (s.created_at at time zone 'Asia/Dubai')::date = d.d_day),
    'unsubscribed', (select count(*) from public.email_suppressions s where s.reason ilike 'unsub%'
                       and (s.created_at at time zone 'Asia/Dubai')::date = d.d_day),
    'registered', (select count(*) from public.leads l where coalesce(l.is_demo, false) = false
                     and (l.registration_submitted_at at time zone 'Asia/Dubai')::date = d.d_day))
  from d
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_campaign_next_list(p_after date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_after date := coalesce(p_after, (now() at time zone 'Asia/Dubai')::date);
  v_day date := v_after + 1; v_skipped jsonb := '[]'::jsonb; v_why text; i int := 0;
  v_cap int; v_pool int; v_n int; v_switch boolean; v_held text; v_rows jsonb;
begin
  loop
    v_why := public.fn_supplier_invites_hold_reason(v_day);
    exit when v_why is null;
    v_skipped := v_skipped || jsonb_build_object('day', v_day, 'why', v_why);
    v_day := v_day + 1; i := i + 1;
    if i > 20 then raise exception 'no supplier sending day within 20 days of %', v_after; end if;
  end loop;
  v_switch := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
              and public.fn_supplier_outreach_golive();
  v_held := case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive is false'
                 when not v_switch then 'invite_enabled is false' end;
  -- the sender's own numbers (enqueue_supplier_invites): cap, eligible pool, planned = least of the two
  v_cap := coalesce((select nullif(value, '')::int from public.app_secrets where key = 'invite_daily_cap'), 10);
  -- fn_invite_ramp runs before the batch on the sending day; with nothing sent in the 3 days before it, it resets
  -- the cap to invite_warmup.base_cap (a cold domain restarts). Show that number, not the stale stored cap.
  -- Scoped to the invitation lane exactly as the ramp is (fn_invite_lane_since; '-infinity' while it is off).
  if coalesce((select max(l.invited_at) from public.leads l where l.invited_at >= public.fn_invite_lane_since() and (public.fn_invite_lane_since() = '-infinity'::timestamptz or public.fn_invite_lane_sent(l.id)) and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(l.email)), '-infinity'::timestamptz) < (v_day::timestamp at time zone 'Asia/Dubai') - interval '3 days' then
    v_cap := coalesce((select (nullif(value, '')::jsonb->>'base_cap')::int from public.app_secrets where key = 'invite_warmup'), 30);
  end if;
  select count(*) into v_pool from public.fn_supplier_invite_eligible_ids();   -- the set, read once (see header)
  v_n := greatest(least(v_cap, v_pool), 0);
  select coalesce(jsonb_agg(jsonb_build_object('n', c.rn, 'lead_id', c.lead_id,
            'company', coalesce(nullif(btrim(c.company_name), ''), '(no company name)'),
            'emirate', coalesce(nullif(btrim(l.emirate), ''), '-'), 'language', c.lang,
            'email', public.fn_mask_email(c.to_email)) order by c.rn), '[]'::jsonb)
    into v_rows
    from (select x.*, row_number() over () rn from public.fn_supplier_invite_candidates(v_n) x) c
    join public.leads l on l.id = c.lead_id;
  return jsonb_build_object('send_day', v_day, 'skipped', v_skipped, 'switch_on', v_switch, 'held_because', v_held,
                            'cap', v_cap, 'pool', v_pool, 'planned', v_n, 'rows', v_rows);
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_capability_reading_record(p_lead_id bigint, p_summary_md5 text, p_kinds jsonb, p_held_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_status text := case when p_kinds is null then 'needs_reasoning' else 'reasoned' end;
begin
  if p_kinds is not null and not (jsonb_typeof(p_kinds->'manufacturing') = 'boolean' and jsonb_typeof(p_kinds->'installation') = 'boolean'
                                  and jsonb_typeof(p_kinds->'maintenance') = 'boolean' and jsonb_typeof(p_kinds->'design') = 'boolean') then
    raise exception 'a capability reading needs four booleans' using errcode = '22023';
  end if;
  insert into public.supplier_capability_reading as r (lead_id, summary_md5, manufacturing, installation, maintenance, design, status, held_id, reasoned_at, updated_at)
  values (p_lead_id, p_summary_md5, (p_kinds->>'manufacturing')::boolean, (p_kinds->>'installation')::boolean,
          (p_kinds->>'maintenance')::boolean, (p_kinds->>'design')::boolean, v_status, p_held_id,
          case when p_kinds is null then null else now() end, now())
  on conflict (lead_id) do update set summary_md5 = excluded.summary_md5, manufacturing = excluded.manufacturing,
    installation = excluded.installation, maintenance = excluded.maintenance, design = excluded.design,
    status = excluded.status, held_id = coalesce(excluded.held_id, r.held_id), reasoned_at = excluded.reasoned_at, updated_at = now()
  -- a queued reading never overwrites a reasoned one of the same text
  where not (excluded.status = 'needs_reasoning' and r.status = 'reasoned' and r.summary_md5 = excluded.summary_md5);
  return jsonb_build_object('lead_id', p_lead_id, 'status', v_status);
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_certifications(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with docs(key, label, label_ar, impact, impact_why, impact_why_ar) as (values
      ('trade_licence',     'Trade licence',              'الرخصة التجارية',           'critical', 'Approval is impossible without it — the licence gate refuses every profile that has none.', 'لا يُعتمد أي حساب من دونها، ويُرفض كل ملف لا يتضمنها.'),
      ('insurance',         'Insurance',                  'التأمين',                   'high',     'Many customers will not award work to an uninsured supplier.', 'كثير من العملاء لا يُرسون الأعمال على مورّد غير مؤمَّن عليه.'),
      ('iso',               'ISO certification',          'شهادة ISO',                 'medium',   'Strengthens your capability score and unlocks quality-gated requests.', 'تعزّز تقييم قدراتكم وتتيح لكم الطلبات المشروطة بمعايير الجودة.'),
      ('manufacturer_auth', 'Manufacturer authorisation', 'تفويض الشركة المصنّعة',     'medium',   'Proves you are authorised for the brands you carry.', 'تُثبت اعتمادكم لدى العلامات التجارية التي تورّدونها.'),
      ('establishment',     'Establishment card (EGR)',   'بطاقة المنشأة (EGR)',       'low',      'Administrative record. Does not gate work.', 'مستند إداري لا يؤثر في استلام الأعمال.')
  ),
  held as (
    select d.*, h.path, h.expiry, h.source
    from docs d left join public.fn_supplier_document_home(p_lead_id) h on h.key = d.key
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'certifications', coalesce((select jsonb_agg(jsonb_build_object(
        'key', h.key, 'label', h.label, 'label_ar', h.label_ar,
        'held', h.path is not null,
        'source', h.source,
        'expiry', h.expiry,
        'days_left', case when h.expiry is null then null else (h.expiry - current_date) end,
        'document_status', case
          when h.path is null then 'missing'
          when h.expiry is null then 'valid'
          when h.expiry < current_date then 'expired'
          when h.expiry < current_date + 60 then 'expiring'
          else 'valid' end,
        'impact_level', h.impact,
        'impact_why', h.impact_why, 'impact_why_ar', h.impact_why_ar)
      order by case h.impact when 'critical' then 0 when 'high' then 1 when 'medium' then 2 else 3 end, h.label)
      from held h), '[]'::jsonb),
    'impact_basis', 'impact_level is a stated QuotesDone policy about what each document gates — not a number derived from your history',
    'impact_basis_ar', 'يعكس مستوى الأثر سياسة QuotesDone المعلنة بشأن ما يتيحه كل مستند، وليس رقمًا مستخلصًا من سجلكم',
    'summary', jsonb_build_object(
      'held', (select count(*) from held where path is not null),
      'total', (select count(*) from held),
      'expired', (select count(*) from held where path is not null and expiry is not null and expiry < current_date),
      'expiring', (select count(*) from held where path is not null and expiry is not null
                     and expiry >= current_date and expiry < current_date + 60),
      'blocking_missing', (select count(*) from held where path is null and impact = 'critical'))
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_changeable()
 RETURNS TABLE(field text, kind text, description text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  select 'quote_price', 'number',
         'The amount on your open quotation. It can be changed while the customer has not paid to reveal you, the quotation is not committed, and the request is still open.';
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_collaboration_cooperated(p_lead bigint, p_quote uuid, p_hold bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_prev int;
begin
  select consecutive_ignored into v_prev from public.supplier_collaboration where lead_id = p_lead for update;
  if coalesce(v_prev, 0) = 0 then return false; end if;
  update public.supplier_collaboration set consecutive_ignored = 0, updated_at = now() where lead_id = p_lead;
  insert into public.supplier_collaboration_event (lead_id, kind, quote_id, hold_id, consecutive_after, actor, detail)
  values (p_lead, 'cooperated', p_quote, p_hold, 0, 'sales_engineer', jsonb_build_object('reset_from', v_prev));
  return true;
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_collaboration_event_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  raise exception 'supplier_collaboration_event is append-only: a supplier''s collaboration history is kept whole (founder, 14 Sep 2026)';
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_collaboration_hold_lift(p_lead bigint, p_founder_instruction bigint, p_why text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare fi record; l record; v_text text; v_n int;
begin
  if coalesce(btrim(p_why), '') = '' then raise exception 'lifting a matching hold needs the reason the founder gave'; end if;
  select id, instruction, coalesce(subject, '') as subject, coalesce(note, '') as note into fi from public.founder_instruction where id = p_founder_instruction;
  if not found then raise exception 'no founder_instruction %: only the founder lifts a matching hold (#160)', p_founder_instruction; end if;
  select id, company_name, collaboration_hold_at, matching_block_reason into l from public.leads where id = p_lead;
  if not found then raise exception 'no supplier %', p_lead; end if;
  v_text := lower(fi.instruction || ' ' || fi.subject || ' ' || fi.note);
  if not (v_text ~ ('(^|[^0-9])' || p_lead::text || '([^0-9]|$)')
          or (length(btrim(coalesce(l.company_name, ''))) >= 3 and position(lower(btrim(l.company_name)) in v_text) > 0)) then
    raise exception 'founder_instruction % does not name supplier % (%): the founder''s instruction must name who is lifted', p_founder_instruction, p_lead, l.company_name;
  end if;
  if l.collaboration_hold_at is null then raise exception 'supplier % is not on a collaboration matching hold', p_lead; end if;

  perform set_config('app.collaboration_hold_lift', 'founder', true);
  update public.leads
     set collaboration_hold_at = null,
         matching_blocked = case when matching_block_reason = 'collaboration_hold' then false else matching_blocked end,
         matching_block_reason = case when matching_block_reason = 'collaboration_hold' then null else matching_block_reason end
   where id = p_lead;
  perform set_config('app.collaboration_hold_lift', '', true);

  update public.supplier_collaboration set consecutive_ignored = 0, lifted_at = now(), updated_at = now() where lead_id = p_lead;
  select coalesce(max(consecutive_ignored), 0) into v_n from public.supplier_collaboration where lead_id = p_lead;
  insert into public.supplier_collaboration_event (lead_id, kind, consecutive_after, founder_instruction_id, actor, detail)
  values (p_lead, 'hold_lifted', v_n, p_founder_instruction, 'founder',
          jsonb_build_object('why', p_why, 'executed_by', session_user, 'at', now()));
  perform public.fn_supplier_notice(p_lead, 'supplier_matching_hold_lifted',
    'Welcome back to QuotesDone',
    $en$Dear {company},

Thank you for speaking with us. We have resumed new requests to your company, and matching requests will start reaching you again. Whenever a quote needs more detail, you can complete it on your supplier portal in a few minutes.

We look forward to working with you.

With thanks,
QuotesDone sales engineer$en$,
    'مرحبًا بعودتكم إلى QuotesDone',
    $ar$السادة/ {company} المحترمين،
تحية طيبة وبعد،

نشكركم على تواصلكم معنا. وقد استأنفنا إرسال الطلبات الجديدة إلى شركتكم، وستصلكم الطلبات المطابقة مجددًا. وعندما يحتاج أي عرض إلى تفاصيل إضافية، يمكنكم استكمالها من بوابة المورّدين خلال دقائق.

نتطلع إلى العمل معكم.

وتفضلوا بقبول فائق الاحترام والتقدير،
مهندس المبيعات في QuotesDone$ar$);
  return jsonb_build_object('ok', true, 'lead_id', p_lead, 'founder_instruction', p_founder_instruction, 'consecutive_ignored', v_n);
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_collaboration_incident(p_lead bigint, p_inquiry uuid, p_quote uuid, p_hold bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_n int; v_held timestamptz; v_warn int := 0; v_hold int := 0;
        v_ref text := upper(left(coalesce(p_inquiry::text, ''), 8));
begin
  insert into public.supplier_collaboration (lead_id) values (p_lead) on conflict (lead_id) do nothing;
  update public.supplier_collaboration
     set consecutive_ignored = consecutive_ignored + 1, total_ignored = total_ignored + 1, last_incident_at = now(), updated_at = now()
   where lead_id = p_lead returning consecutive_ignored into v_n;
  insert into public.supplier_collaboration_event (lead_id, kind, inquiry_id, quote_id, hold_id, consecutive_after, actor, detail)
  values (p_lead, 'ignored_hold', p_inquiry, p_quote, p_hold, v_n, 'sales_engineer', jsonb_build_object('rfq', v_ref));

  if v_n = 2 then
    insert into public.support_case (case_ref, party_kind, party_id, inquiry_ref, subject, owner_role_id)
    values ('SE-COLLAB-' || p_lead || '-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'), 'supplier', p_lead::text, p_inquiry::text,
            'From the sales engineer: this supplier has left 2 held quotes unanswered in a row (the customer decided before the missing details came). The warning was sent on email and WhatsApp; a third in a row puts them on matching hold.',
            'customer_support');
    v_warn := public.fn_supplier_notice(p_lead, 'supplier_collaboration_warning',
      'A note about your recent quotes on QuotesDone',
      $en$Dear {company},

Thank you for quoting on QuotesDone. We value the time you put into every request.

On your last two requests, your quotation was placed on hold because some details the customer needs to compare quotes fairly were missing (for example the exact material specification, the delivery date, installation or warranty), and the customer made their decision before those details arrived. Complete details help customers choose with confidence, and they give your offer the best chance of being selected.

Whenever a quote is on hold, you can fill in the missing details directly on your supplier portal (we then prepare the standardised quotation for your approval), or upload a revised quotation. It only takes a few minutes.

To keep matching fair for customers, if a third consecutive quotation is still on hold when the customer decides, we will pause new requests to your company until we have spoken with you. We would much rather keep working together, so please reach out if anything is making it difficult to respond.

With thanks,
QuotesDone sales engineer$en$,
      'ملاحظة بشأن عروضكم الأخيرة على QuotesDone',
      $ar$السادة/ {company} المحترمين،
تحية طيبة وبعد،

نشكركم على تقديم عروض الأسعار عبر QuotesDone، ونقدّر الوقت الذي تخصصونه لكل طلب.

في آخر طلبين، عُلّق عرضكم لنقص بعض التفاصيل التي يحتاجها العميل ليقارن العروض بإنصاف (مثل المواصفات الدقيقة للمواد أو موعد التسليم أو التركيب أو الضمان)، واتخذ العميل قراره قبل وصول هذه التفاصيل. فاكتمال التفاصيل يساعد العملاء على الاختيار بثقة، ويمنح عرضكم أفضل فرصة للفوز.

وعند تعليق أي عرض، يمكنكم استكمال التفاصيل الناقصة مباشرة من بوابة المورّدين (ونُعدّ لكم العرض بالصيغة الموحّدة لاعتماده)، أو رفع عرض معدّل، ولا يستغرق ذلك سوى دقائق.

وحرصًا على عدالة المطابقة للعملاء، إذا بقي عرض ثالث على التوالي معلّقًا عند اتخاذ العميل قراره، فسنوقف مؤقتًا إرسال الطلبات الجديدة إلى شركتكم إلى حين التحدث معكم. ونحرص كثيرًا على استمرار تعاوننا، فلا تترددوا في التواصل معنا إن كان هناك ما يصعّب عليكم الرد.

وتفضلوا بقبول فائق الاحترام والتقدير،
مهندس المبيعات في QuotesDone$ar$,
      p_inquiry, p_quote);
    update public.supplier_collaboration set warned_at = now(), updated_at = now() where lead_id = p_lead;
    insert into public.supplier_collaboration_event (lead_id, kind, inquiry_id, quote_id, hold_id, consecutive_after, actor, detail)
    values (p_lead, 'warning_sent', p_inquiry, p_quote, p_hold, v_n, 'sales_engineer', jsonb_build_object('delivery_requests', v_warn));

  elsif v_n >= 3 then
    select collaboration_hold_at into v_held from public.leads where id = p_lead;
    if v_held is null then
      update public.leads set collaboration_hold_at = now(), matching_blocked = true, matching_block_reason = 'collaboration_hold' where id = p_lead;
      update public.supplier_collaboration set held_at = now(), updated_at = now() where lead_id = p_lead;
      insert into public.support_case (case_ref, party_kind, party_id, inquiry_ref, subject, owner_role_id)
      values ('SE-HOLD-' || p_lead || '-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'), 'supplier', p_lead::text, p_inquiry::text,
              'From the sales engineer: supplier put on matching hold after 3 held quotes in a row were left unanswered. New requests are no longer matched to them. Lifting it is the founder''s decision after he calls the supplier (founder_instruction #160).',
              'customer_support');
      v_hold := public.fn_supplier_notice(p_lead, 'supplier_matching_hold',
        'New requests to your company are paused on QuotesDone',
        $en$Dear {company},

Thank you for your time on QuotesDone. On your last three consecutive requests, your quotation was still on hold for missing details when the customer made their decision. As we mentioned in our earlier message, we have therefore paused new requests to your company for now. Your account, your existing quotations and any revealed jobs are not affected.

Our team will be in touch to understand what happened and how we can make responding easier. You are welcome to reply to this message at any time.

With thanks,
QuotesDone sales engineer$en$,
        'إيقاف مؤقت لإرسال الطلبات الجديدة إلى شركتكم على QuotesDone',
        $ar$السادة/ {company} المحترمين،
تحية طيبة وبعد،

نشكركم على وقتكم في QuotesDone. في آخر ثلاثة طلبات متتالية، كان عرضكم لا يزال معلّقًا لنقص في التفاصيل عندما اتخذ العميل قراره؛ لذلك، وكما أشرنا في رسالتنا السابقة، أوقفنا مؤقتًا إرسال الطلبات الجديدة إلى شركتكم. ولا يتأثر بذلك حسابكم ولا عروضكم الحالية ولا الأعمال التي كُشف عنها.

سيتواصل معكم فريقنا للوقوف على ما حدث وبحث سبل تيسير ردّكم على الطلبات، ويسعدنا أن تردّوا على هذه الرسالة في أي وقت.

وتفضلوا بقبول فائق الاحترام والتقدير،
مهندس المبيعات في QuotesDone$ar$,
        p_inquiry, p_quote);
      insert into public.supplier_collaboration_event (lead_id, kind, inquiry_id, quote_id, hold_id, consecutive_after, actor, detail)
      values (p_lead, 'matching_hold', p_inquiry, p_quote, p_hold, v_n, 'sales_engineer', jsonb_build_object('delivery_requests', v_hold));
    end if;
  end if;
  return jsonb_build_object('lead_id', p_lead, 'consecutive', v_n, 'warning_requests', v_warn, 'hold_requests', v_hold);
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_doc_reading_escalate(p_minutes integer DEFAULT 30, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb := '[]'::jsonb; r record; d jsonb; docs jsonb; i int; changed boolean; v_since timestamptz;
begin
  for r in select c.supplier_id, c.source_docs, c.extracted_at from public.supplier_capabilities c
            where c.source_docs -> 'docs' @> '[{"status":"reading"}]'::jsonb
            order by c.supplier_id limit greatest(1, least(coalesce(p_limit, 50), 200)) for update skip locked loop
    docs := r.source_docs -> 'docs'; changed := false;
    for i in 0 .. jsonb_array_length(docs) - 1 loop
      d := docs -> i;
      -- since when it has been 'reading': its own mark, else the capability row's last read, else now (never escalated on
      -- the first run when nothing says how old it is)
      v_since := coalesce((d ->> 'read_at')::timestamptz, r.extracted_at, now());
      if d ->> 'status' = 'reading' and v_since <= now() - make_interval(mins => greatest(coalesce(p_minutes, 30), 1)) then
        docs := jsonb_set(docs, array[i::text], d || jsonb_build_object('status', 'unreadable',
                  'reason', 'the read did not finish (the reader stopped before it was done); the sales engineer has it'));
        insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
        select 'sales_engineer', 'document_read_stuck', 'pending', 'low',
                left('A supplier document was never read: ' || coalesce(d ->> 'name', d ->> 'path', '?'), 200),
                jsonb_build_object('supplier_id', r.supplier_id, 'path', d ->> 'path', 'kind', d ->> 'kind', 'reading_since', d ->> 'read_at',
                                   'waiting_for', 'sales_engineer to read it again, or to ask the supplier for a smaller or clearer copy'),
                'supplier_capabilities', r.supplier_id::text || ':' || coalesce(d ->> 'path', '')
         where not exists (select 1 from public.agent_actions a where a.kind = 'document_read_stuck' and a.status = 'pending'
                             and a.target_id = r.supplier_id::text || ':' || coalesce(d ->> 'path', ''));
        v := v || jsonb_build_array(jsonb_build_object('supplier_id', r.supplier_id, 'path', d ->> 'path'));
        changed := true;
      end if;
    end loop;
    if changed then
      update public.supplier_capabilities set source_docs = jsonb_set(r.source_docs, '{docs}', docs) where supplier_id = r.supplier_id;
      -- the supplier's status is made current: no longer held for 'documents_being_read' by a read that will never finish
      if exists (select 1 from public.leads l where l.id = r.supplier_id) then
        perform public.fn_sales_engineer_verifies_supplier(r.supplier_id, 'documents_read');
      end if;
    end if;
  end loop;
  return v;
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_document_home(p_lead_id bigint)
 RETURNS TABLE(key text, path text, name text, expiry date, source text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (select * from public.leads where id = p_lead_id),
  -- A live supporting document whose LABEL names the subject. The label is the supplier's own
  -- words for the file ("ISO 9001:2015", "شهادة الأيزو", "Public liability insurance"). WHICH subject it
  -- names is the sales engineer seat's reasoning (supplier_documents.subject, filed when the label is
  -- saved by trg_supplier_document_subject_asked), read back by its key — 23 Sep 2026, founder_instruction
  -- 886-903; a pattern list on the label decided it before. Until it is answered the file fills no slot.
  supp as (
    select d.path, d.file_name, d.created_at,
           nullif(public.fn_reason_route_answer('supdoc:' || d.id || ':' || md5(coalesce(d.file_name, ''))), 'none') as subject
    from public.documents d
    where d.ref_table = 'supplier_supporting' and d.ref_id = p_lead_id::text
      and coalesce(d.status, '') <> 'withdrawn'
  ),
  best as (
    select distinct on (subject) subject, path, file_name from supp
    where subject is not null order by subject, created_at desc
  ),
  fixed(key, path, name, expiry) as (
    select 'trade_licence',     (select license_doc_path from me),           (select license_doc_name from me), (select license_expiry from me)::date
    union all select 'company_profile',   (select company_profile_doc_path from me),   null, null::date
    union all select 'insurance',         (select insurance_doc_path from me),         null, (select insurance_expiry from me)::date
    union all select 'iso',               (select iso_doc_path from me),               null, (select iso_expiry from me)::date
    union all select 'manufacturer_auth', (select manufacturer_auth_doc_path from me), null, (select manufacturer_auth_expiry from me)::date
    union all select 'establishment',     (select egr_doc_path from me),               (select egr_doc_name from me), null::date
  )
  select f.key,
         coalesce(f.path, b.path)                                  as path,
         coalesce(f.name, case when f.path is null then b.file_name end, regexp_replace(coalesce(f.path, b.path, ''), '^.*/', '')) as name,
         case when f.path is not null then f.expiry end            as expiry,
         case when f.path is not null then 'leads' when b.path is not null then 'supporting' end as source
  from fixed f left join best b on b.subject = f.key;
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_document_impact(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (select * from public.leads where id = p_lead_id),
  flag as (select coalesce((select source from me), '') = 'qd_demo_fixture' as is_demo),
  mine as (select coalesce(sc.trades, '{}'::text[]) trades from public.supplier_capabilities sc where sc.supplier_id = p_lead_id),
  reachable as (
    select count(*) n from public.inquiries i, me, flag
    where i.status = 'open'
      and ((me.sector is not null and i.category = me.sector)
           or exists (select 1 from mine where i.trades && mine.trades))
      and (coalesce(i.brief_source, '') = 'qd_demo_fixture') = flag.is_demo
  ),
  priced as (
    select count(distinct q.inquiry_id) n from public.quotes q, flag
    where q.supplier_id = p_lead_id
      and (coalesce(q.source, '') = 'qd_demo_fixture') = flag.is_demo
  ),
  docs as (
    select h.key, case h.key when 'trade_licence' then 'Trade licence' when 'iso' then 'ISO certification'
                             when 'insurance' then 'Insurance' when 'manufacturer_auth' then 'Manufacturer authorisation'
                             when 'company_profile' then 'Company profile' end as label,
           h.path, h.expiry, h.source, h.key = 'trade_licence' as gates_matching
    from public.fn_supplier_document_home(p_lead_id) h
    where h.key in ('trade_licence', 'iso', 'insurance', 'manufacturer_auth', 'company_profile')
  ),
  scored as (
    select d.key, d.label, d.gates_matching, d.source,
           d.path is not null as on_file,
           d.expiry,
           coalesce(d.expiry < current_date, false) as expired,
           (d.path is not null and not coalesce(d.expiry < current_date, false)) as effective
    from docs d
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'open_in_my_trade', (select n from reachable),
    'basis', 'open enquiries in your trade, and the enquiries you have already priced',
    'documents', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'key', s.key, 'label', s.label, 'on_file', s.on_file, 'source', s.source,
        'expiry', s.expiry, 'expired', s.expired,
        'unlocked', case when s.effective then (select n from priced) else 0 end,
        'would_unlock', case when s.effective then 0 when s.gates_matching then (select n from reachable) else 0 end,
        'note', case
          when s.effective then 'On file and in force.'
          when s.expired and s.gates_matching then 'Expired. Renewing it reopens every open enquiry in your trade.'
          when s.expired then 'Expired. Customers see this as a gap when comparing you.'
          when s.gates_matching then 'Missing. It is the document that decides whether you can be matched at all.'
          else 'Missing. It is optional, but it is what a customer looks for when comparing two similar quotes.'
          end
      ) order by s.gates_matching desc, s.key), '[]'::jsonb)
      from scored s)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_document_subject_ask(p_id bigint, p_file_name text, p_kind text, p_ref_id text)
 RETURNS bigint
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.fn_reason_route_ask('sales_engineer', 'supplier_documents.subject',
    'A supplier uploaded a company document and labelled it: "' || p_file_name || '" (the type they chose: '
      || coalesce(p_kind, 'none') || '). Which document is it?',
    jsonb_build_array(
      jsonb_build_object('id', 'iso', 'meaning', 'an ISO management-system certificate (ISO 9001, 14001, 45001 ...)'),
      jsonb_build_object('id', 'insurance', 'meaning', 'an insurance policy or certificate (public liability, contractor all-risk, workmen compensation ...)'),
      jsonb_build_object('id', 'manufacturer_auth', 'meaning', 'a manufacturer, brand or distributor authorisation / agency letter'),
      jsonb_build_object('id', 'none', 'meaning', 'any other document')),
    jsonb_build_object('document_id', p_id, 'lead_id', p_ref_id),
    'supdoc:' || p_id || ':' || md5(coalesce(p_file_name, '')));
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_due_is_owed(p_status text, p_paid_at timestamp with time zone)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select p_paid_at is null
     and coalesce(p_status, '') not in ('paid', 'settled', 'waived', 'cancelled', 'reversed', 'void')
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_due_paid_records_payment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- any writer, insert or update: paid_at going from empty to set is a settlement
  if new.paid_at is not null and (tg_op = 'INSERT' or old.paid_at is null) then
    perform public.fn_supplier_due_record_settlement(new.id);
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_due_record_settlement(p_due_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.supplier_dues; v_rest numeric; v_id bigint; v_on date; v_owed numeric;
begin
  select * into d from public.supplier_dues where id = p_due_id;
  if not found or d.paid_at is null or coalesce(d.status, '') in ('reversed', 'refunded', 'cancelled') then return null; end if;
  v_on := (d.paid_at at time zone 'Asia/Dubai')::date;
  -- stripe_webhook's reference is always the payment intent or the session (pi_ / cs_); stripe_session_id alone is not
  -- evidence (supplier_pay writes it when a checkout is OPENED, paid or not)
  if d.payment_ref ~ '^(pi|cs)_' then
    -- a Stripe settlement records what the session charged for this due, stored at checkout; never a figure
    -- recomputed at paid_at (a day's interest apart when the checkout and the payment straddle midnight)
    select c.amount_aed into v_rest from public.supplier_due_checkouts c
     where c.session_id = d.stripe_session_id and c.due_id = d.id;
    if v_rest is null then
      perform public.fn_it_engineer_finding_upsert('acct:stripe_settlement_without_checkout_amount:' || d.id,
        'A Stripe settlement of supplier due ' || d.id || ' has no stored checkout amount, so no payment row was recorded',
        'public.fn_supplier_due_record_settlement', 'agent_facing', 1,
        jsonb_build_object('due_id', d.id, 'stripe_session_id', d.stripe_session_id, 'payment_ref', d.payment_ref,
                           'owner_seat', 'accountant', 'raised_by_seat', 'accountant'),
        '{}'::text[], '{}'::text[], 'accountant');
      return null;
    end if;
    -- Stripe took it, so it is recorded as taken; a stale session paid after a bank part payment is an overpayment
    v_owed := (public.fn_supplier_dues_outstanding(array[d.id], v_on) -> d.id::text ->> 'owed_aed')::numeric;
    if v_rest > coalesce(v_owed, 0) then
      perform public.fn_it_engineer_finding_upsert('acct:stripe_overpayment:' || d.id || ':' || d.payment_ref,
        'Stripe charged AED ' || v_rest || ' on supplier due ' || d.id || ', above the AED ' || coalesce(v_owed, 0) || ' still owed; the excess is the supplier''s',
        'public.fn_supplier_due_record_settlement', 'agent_facing', 1,
        jsonb_build_object('due_id', d.id, 'charged_aed', v_rest, 'owed_aed', v_owed, 'stripe_session_id', d.stripe_session_id,
                           'payment_ref', d.payment_ref, 'owner_seat', 'accountant', 'raised_by_seat', 'accountant'),
        '{}'::text[], '{}'::text[], 'accountant');
    end if;
  else
    -- any other writer of paid_at: what was still owed on the settlement date, before this settlement
    v_rest := (public.fn_supplier_dues_outstanding(array[d.id], v_on) -> d.id::text ->> 'owed_aed')::numeric;
    if v_rest is null or v_rest <= 0 then return null; end if;
  end if;
  insert into public.supplier_due_payments (due_id, paid_on, amount_aed, reference, entered_by)
  values (d.id, v_on, v_rest, coalesce(nullif(btrim(d.payment_ref), ''), 'supplier_dues.paid_at #' || d.id), 'service')
  on conflict (due_id, reference) do nothing returning id into v_id;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_dues_accrue_interest(p_as_of date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare x record; v jsonb; n int := 0; v_owed numeric;
begin
  for x in select id, transaction_id from public.supplier_dues
            where public.fn_supplier_due_is_owed(status, paid_at) and transaction_id is not null loop
    v := public.fn_accountant_nonresponse_charge(x.transaction_id, p_as_of);
    continue when not coalesce((v->>'ok')::boolean, false);
    -- 30 SEP 2026 (accountant): what is still owed, after every recorded payment
    v_owed := (public.fn_supplier_dues_outstanding(array[x.id], p_as_of) -> x.id::text ->> 'owed_aed')::numeric;
    update public.supplier_dues
       set interest_amount = (v->>'interest_aed')::numeric, total_claim = v_owed,
           due_date = (v->>'due_date')::date, due_date_30 = (v->>'due_date')::date + 23
     where id = x.id
       and (interest_amount is distinct from (v->>'interest_aed')::numeric
            or total_claim is distinct from v_owed
            or due_date is distinct from (v->>'due_date')::date);
    if found then n := n + 1; end if;
  end loop;
  return n;
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_dues_outstanding(p_due_ids bigint[], p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.supplier_dues; v jsonb; out jsonb := '{}'; v_paid numeric;
begin
  for d in select * from public.supplier_dues where id = any(p_due_ids) loop
    v_paid := coalesce((select sum(p.amount_aed) from public.supplier_due_payments p where p.due_id = d.id), 0);
    v := case when d.transaction_id is not null then public.fn_accountant_nonresponse_charge(d.transaction_id, p_as_of) end;
    if coalesce((v->>'ok')::boolean, false) then
      out := out || jsonb_build_object(d.id::text, jsonb_build_object(
        'owed_aed', round(greatest(0, (v->>'total_aed')::numeric + coalesce(d.fine_amount, 0)), 2),
        'unpaid_principal_aed', (v->>'unpaid_principal_aed')::numeric, 'interest_aed', (v->>'interest_aed')::numeric,
        'paid_aed', (v->>'paid_aed')::numeric, 'source', 'fn_accountant_nonresponse_charge'));
    else
      out := out || jsonb_build_object(d.id::text, jsonb_build_object(
        'owed_aed', round(greatest(0, coalesce(d.amount_due, 0) + coalesce(d.admin_fee, 0) + coalesce(d.interest_amount, 0) + coalesce(d.fine_amount, 0) - v_paid), 2),
        'unpaid_principal_aed', null, 'interest_aed', coalesce(d.interest_amount, 0), 'paid_aed', v_paid, 'source', 'stored columns less payments'));
    end if;
  end loop;
  return out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_exception_close(p_lead_id bigint, p_outcome text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update public.leads
     set exception_closed_at = now(),
         exception_outcome = p_outcome,
         licence_gate_reason = case when p_outcome = 'resolved' then null else licence_gate_reason end
   where id = p_lead_id and exception_closed_at is null;
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_exception_days()
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  select greatest(1, coalesce((select nullif(btrim(value),'')::int from app_secrets where key='supplier_exception_days'), 14));
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_exception_open(p_lead_id bigint, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_days int := public.fn_supplier_exception_days(); r public.leads;
begin
  select * into r from public.leads where id = p_lead_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'lead_not_found'); end if;

  if r.exception_opened_at is not null and r.exception_closed_at is null then
    return jsonb_build_object('ok', true, 'reopened', false, 'due_at', r.exception_due_at,
                              'note', 'already open - the clock does not restart on a repeat failure');
  end if;

  update public.leads
     set exception_opened_at = now(),
         exception_due_at = now() + make_interval(days => v_days),
         exception_reminders = 0, exception_last_reminder_at = null,
         exception_closed_at = null, exception_outcome = null,
         licence_gate_reason = coalesce(p_reason, licence_gate_reason)
   where id = p_lead_id;

  return jsonb_build_object('ok', true, 'reopened', true,
                            'due_at', now() + make_interval(days => v_days), 'days', v_days);
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_expiries(p_supplier_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with l as (select * from leads where id=p_supplier_id)
  select coalesce(jsonb_agg(e order by (e->>'days_left')::int), '[]'::jsonb) from (
    select jsonb_build_object('doc',d.label,'expiry',d.exp,
      'days_left',(d.exp - current_date),
      'status', case when d.exp < current_date then 'expired'
                     when d.exp <= current_date + 30 then 'expiring'
                     when d.exp <= current_date + 90 then 'soon' else 'ok' end) e
    from l, lateral (values
      ('Trade license', l.license_expiry),
      ('ISO certification', l.iso_expiry),
      ('Insurance', l.insurance_expiry),
      ('Manufacturer authorization', l.manufacturer_auth_expiry)
    ) as d(label,exp)
    where d.exp is not null
  ) q;
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_invite_candidates(p_limit integer)
 RETURNS TABLE(lead_id bigint, to_email text, company_name text, lang text, subject text, body text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_site text; v_target int;
  v_subj text; v_body text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from app_secrets where key = 'public_site_url';
  v_site := coalesce(v_site, 'https://quotesdone.com');
  select value into v_subj    from app_secrets where key = 'invite_subject';
  select value into v_body    from app_secrets where key = 'invite_body';
  -- 27 Oct 2026: the founder's invitation carries no link ("safer to not send links"); a supplier registers at
  -- quotesdone.com or replies. Only an EMPTY template is refused now. A template that still has {{link}} is filled.
  if btrim(coalesce(v_body, '')) = '' then
    raise exception 'app_secrets.invite_body is empty: no invitation is built from nothing';
  end if;
  v_target := coalesce((select nullif(value,'')::int from app_secrets where key='invite_target_per_category'),
                       (select nullif(value,'')::int from app_secrets where key='invite_target_per_trade'), 10);

  -- MATERIALIZED, 4 Aug 2026, and it is load-bearing (see enqueue_supplier_invites' history): both
  -- CTEs are read from a correlated subquery and would otherwise be recomputed per candidate.
  return query
  with activated as materialized (
    select ls.domain_slug, count(distinct l.id) ct
    from leads l join lead_subcategory ls on ls.lead_id = l.id
    where coalesce(l.claimed,false) = true
    group by ls.domain_slug
  ),
  under as materialized (
    select d.slug as domain_slug, coalesce(a.ct,0) as have
    from catalog_domains d left join activated a on a.domain_slug = d.slug
    where coalesce(a.ct,0) < v_target
  ),
  -- ONE COMPANY, ONE INVITATION (24 Sep 2026, marketing). A company is its email domain, unless the domain is
  -- a shared mailbox provider (gmail, emirates.net.ae ...: measured as a domain carrying 3+ different company
  -- names), where it is the address itself; and, independently, its normalised company name.
  shared as materialized (
    select split_part(lower(btrim(l.email)), '@', 2) as dom from leads l where coalesce(btrim(l.email), '') <> ''
    group by 1 having count(distinct lower(regexp_replace(coalesce(l.company_name, ''), '[^[:alnum:]]', '', 'g'))) >= 3
  ),
  keyed as materialized (
    select l.id,
           case when s.dom is null then split_part(lower(btrim(l.email)), '@', 2) else lower(btrim(l.email)) end as dkey,
           nullif(lower(regexp_replace(coalesce(l.company_name, ''), '[^[:alnum:]]', '', 'g')), '') as nkey,
           (l.invite_status is not null or l.invited_at is not null or coalesce(l.claimed, false)) as touched
    from leads l left join shared s on s.dom = split_part(lower(btrim(l.email)), '@', 2)
    where coalesce(btrim(l.email), '') <> ''
  ),
  touched_d as materialized (select distinct dkey from keyed where touched),
  touched_n as materialized (select distinct nkey from keyed where touched and nkey is not null),
  -- instr 1013: marketing's ranking of the trades below ten suppliers (the ranking orders the queue; since 27 Oct 2026
  -- every row stores the one approved text, not a per-trade variant)
  plans as materialized (select p.trade, p.emirate, p.rank from public.marketing_gap_recruitment_plan p),
  -- 29 Sep 2026 (ledger 1018): the trades and areas of the open, real stalled-request rescues (public.stalled_inquiry_rescue).
  -- A fixture rescue never moves the real queue.
  rescue as materialized (select x.trades, x.emirate from public.stalled_inquiry_rescue x where x.cleared_at is null and not x.fixture and cardinality(x.trades) > 0),
  cand as (
    select distinct on (lower(l.email)) l.id, l.email, l.company_name, l.claim_token, l.email_domain, l.email_verified,
           l.invite_trades, l.emirate, k.dkey, k.nkey,
           -- ALWAYS ENGLISH (24 Sep 2026, ledger 993 item 4; #1065): suppliers are always written in English.
           'en'::text as lang
    from leads l join keyed k on k.id = l.id
    where l.id in (select e.id from public.fn_supplier_invite_eligible_ids() e(id))   -- the set, read once (see header)
      -- a company already invited (bounced, unsubscribed or registered included) is not invited again at another address
      and not exists (select 1 from touched_d t where t.dkey = k.dkey)
      and (k.nkey is null or not exists (select 1 from touched_n t where t.nkey = k.nkey))
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name, c.claim_token, c.email_domain, c.lang, c.dkey, c.nkey,
      -- 29 Sep 2026 (ledger 1018): ahead of every tier below, a lead in the trade and area of a stalled request a customer waits on.
      -- 23 Sep 2026: a lead in a trade the sales engineer marked for recruitment (supply_gap 'recruit') goes first;
      -- 29 Sep 2026 (instr 1013): then a lead in any trade marketing planned, by the plan's rank.
      case when exists (select 1 from rescue x where x.trades && coalesce(c.invite_trades, '{}'::text[])
                          and (x.emirate is null or x.emirate = 'UAE' or x.emirate = c.emirate)) then -1
           when exists (select 1 from public.supply_gap g where g.status = 'recruit' and g.trade = any(coalesce(c.invite_trades, '{}'::text[]))
                          and (g.emirate = 'UAE' or g.emirate = c.emirate)) then 0
           when pl.rank is not null then 1 else 2 end as target_rank,
      coalesce(pl.rank, 2147483647) as plan_rank,
      coalesce((select u.domain_slug from lead_subcategory ls join under u on u.domain_slug = ls.domain_slug
                 where ls.lead_id = c.id order by u.have asc, ls.score desc limit 1), '~none') as pdomain,
      case when c.email_verified in ('verified','true') then 0 else 1 end as unverified_rank,
      case when split_part(lower(c.email),'@',1) in
             ('info','sales','admin','contact','enquiry','enquiries','inquiry','office','mail',
              'support','hello','marketing','general','accounts','reception','careers','hr')
           then 1 else 0 end as role_rank
    from cand c
    left join lateral (select p.rank from plans p
                        where p.trade = any(coalesce(c.invite_trades, '{}'::text[])) and (p.emirate = 'UAE' or p.emirate = c.emirate)
                        order by p.rank limit 1) pl on true
  ),
  elig as (
    select r.id, r.email, r.company_name, r.claim_token, r.lang from (
      select p.*,
        case when p.pdomain='~none' then 1 else 0 end as is_none,
        row_number() over (partition by p.pdomain order by p.unverified_rank, p.role_rank, p.id) as rk,
        row_number() over (partition by coalesce(p.email_domain, split_part(p.email,'@',2)) order by p.unverified_rank, p.role_rank, p.id) as domain_rk,
        -- the best contact per company: a verified, named mailbox before info@/sales@ (a role address goes only
        -- when it is the company's only one). ponytail: a lead that wins one key and loses the other waits a day.
        row_number() over (partition by p.dkey order by p.unverified_rank, p.role_rank, p.id) as company_rk,
        row_number() over (partition by coalesce(p.nkey, p.email) order by p.unverified_rank, p.role_rank, p.id) as name_rk
      from prio p
    ) r
    where r.domain_rk <= 5 and r.company_rk = 1 and r.name_rk = 1
    order by r.target_rank, r.plan_rank, r.is_none, r.rk, r.unverified_rank, r.role_rank, r.pdomain
    limit greatest(coalesce(p_limit, 0), 0)
  )
  select e.id, btrim(e.email), e.company_name, e.lang, v_subj,
         -- an Arabic-script company name is not written into an English letter (the 29 Sep probe found 11 of 200);
         -- with no usable name the greeting is the neutral "Hello," the Microsoft 365 lane also sends
         -- (a template that still carries {{link}} is filled as before; the approved one has none)
         replace(replace(case when n.nm = '' then replace(v_body, 'Hi {{company}} team,', 'Hello,') else v_body end,
                         '{{company}}', case when n.nm = '' then 'there' else n.nm end),
                 '{{link}}', public.fn_supplier_invite_link(v_site, e.claim_token, e.id))
  from elig e
  cross join lateral (select coalesce(nullif(btrim(case when e.company_name ~ '[؀-ۿ]' then '' else e.company_name end), ''), '') as nm) n;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_invite_eligible(p leads)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(btrim(p.email), '') <> ''
     and p.invite_status is null
     and coalesce(p.source, '') <> 'self_registered'
     and coalesce(p.claimed, false) = false
     and coalesce(p.banned, false) = false
     and coalesce(p.permanently_closed, false) = false
     -- a fixture is never a supplier: the flag, the naming convention, and the reserved domains
     and coalesce(p.is_demo, false) = false
     and coalesce(p.company_name, '') !~* '^\s*zz\s*demo'
     and not public.fn_is_demo_email(p.email)
     -- screened and matched but undecided is not cleared; a confirmed ban is total
     and not exists (select 1 from public.sanctions_ban b where b.lead_id = p.id)
     and not exists (select 1 from public.supplier_screening_hit h
                      where h.lead_id = p.id and h.status in ('open', 'confirmed'))
     -- never twice, read from the outbox rather than from a status column
     and not exists (select 1 from public.notifications n
                      where n.type = 'supplier_invite' and lower(btrim(n.to_email)) = lower(btrim(p.email)))
     and coalesce((public.fn_email_sendable(p.email)->>'ok')::boolean, false)
     -- 22 Sep 2026: a COLD invitation needs a measured MX. An A-record-only domain (361 leads), a lookup
     -- that errored (86) or a domain never asked is a bounce risk on a domain with no history to spend.
     and exists (select 1 from public.email_domain_mx m
                  where m.domain = split_part(lower(btrim(p.email)), '@', 2) and m.kind = 'mx')
     -- ... and never a mailbox whose reader is not the business (44 leads): a recruiter or a lawyer
     -- presses "spam", they do not register.
     and split_part(lower(btrim(p.email)), '@', 1) !~
         '^(careers?|jobs?|hr|recruit(ment|ing)?|cv|webmaster|hostmaster|mailer-daemon|privacy|legal|newsletters?|unsubscribe|donotreply)$'
     -- 24 Sep 2026 (marketing, ledger 993): never an address on a directory, marketplace, hosting, template or
     -- placeholder domain (public.email_platform_domain, exact domain equality, no word is read) -- the reader is not
     -- the company. The one exception is a platform that IS the lead: its own website host is that domain.
     and not exists (select 1 from public.email_platform_domain d
                      where d.domain = split_part(lower(btrim(p.email)), '@', 2)
                        and d.domain is distinct from lower(regexp_replace(regexp_replace(btrim(coalesce(nullif(btrim(p.website), ''), p.maps_website, '')),
                                                          '^[A-Za-z]+://', ''), '^www\.|[/:?#].*$', '', 'gi')))
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_invite_eligible_ids()
 RETURNS SETOF bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- The small reference tables (sanctions 46 rows, screening hits, 37 suppressions, block patterns,
  -- 47 platform domains) are read ONCE into arrays: with the leads estimate at 1 row the planner
  -- chose nested loops and re-read each of them 19,444 times (EXPLAIN ANALYZE, 4.8 s). NULLs are
  -- filtered out of each array, because `x <> all(array[..., null])` is null and would drop every lead.
  select p.id
    from public.leads p
   where coalesce(btrim(p.email), '') <> ''
     and p.invite_status is null
     and coalesce(p.source, '') <> 'self_registered'
     and coalesce(p.claimed, false) = false
     and coalesce(p.banned, false) = false
     and coalesce(p.permanently_closed, false) = false
     and coalesce(p.is_demo, false) = false
     and coalesce(p.company_name, '') !~* '^\s*zz\s*demo'
     and not public.fn_is_demo_email(p.email)
     and p.id <> all (array(select b.lead_id from public.sanctions_ban b where b.lead_id is not null))
     and p.id <> all (array(select h.lead_id from public.supplier_screening_hit h
                             where h.lead_id is not null and h.status in ('open', 'confirmed')))
     and not exists (select 1 from public.notifications n
                      where n.type = 'supplier_invite' and lower(btrim(n.to_email)) = lower(btrim(p.email)))
     -- fn_email_sendable(p.email)->>'ok', clause for clause
     and lower(btrim(p.email)) ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}$'
     and lower(btrim(p.email)) <> all (array(select lower(s.email) from public.email_suppressions s where s.email is not null))
     and not exists (select 1 from public.email_domain_mx m0
                      where m0.domain = split_part(lower(btrim(p.email)), '@', 2) and m0.has_mx = false
                        and m0.kind in ('nxdomain', 'no_records'))
     and not coalesce(lower(btrim(p.email)) ~ any (array(select bp.pattern from public.email_block_pattern bp
                                                         where bp.active and bp.pattern is not null)), false)
     -- a measured MX
     and exists (select 1 from public.email_domain_mx m
                  where m.domain = split_part(lower(btrim(p.email)), '@', 2) and m.kind = 'mx')
     and split_part(lower(btrim(p.email)), '@', 1) !~
         '^(careers?|jobs?|hr|recruit(ment|ing)?|cv|webmaster|hostmaster|mailer-daemon|privacy|legal|newsletters?|unsubscribe|donotreply)$'
     and not (split_part(lower(btrim(p.email)), '@', 2) = any (array(select d.domain from public.email_platform_domain d where d.domain is not null))
              and split_part(lower(btrim(p.email)), '@', 2) is distinct from
                  lower(regexp_replace(regexp_replace(btrim(coalesce(nullif(btrim(p.website), ''), p.maps_website, '')),
                                       '^[A-Za-z]+://', ''), '^www\.|[/:?#].*$', '', 'gi')))
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_invite_link(p_site text, p_token uuid, p_lead_id bigint)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(nullif(btrim(p_site), ''), 'https://quotesdone.com') || '/en/portal?t=' || p_token::text
         || '&utm_source=invite&utm_medium=email&utm_campaign=supplier_invite&utm_content=lead-' || p_lead_id::text
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_invite_nudges_due(p_now timestamp with time zone DEFAULT now(), p_include_fixtures boolean DEFAULT false)
 RETURNS TABLE(lead_id bigint, step integer, to_email text, lang text, dedupe_key text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with inv as (   -- the invitation as the OUTBOX recorded it, one per lead
    select n.lead_id, min(coalesce(n.sent_at, n.created_at)) as sent_at
      from public.notifications n
     where n.type = 'supplier_invite' and n.lead_id is not null
       and (n.status = 'sent' or n.sent_at is not null)
     group by n.lead_id
  ), c as (
    -- ALWAYS ENGLISH (review, 29 Sep 2026; founder rule: suppliers are always English, ledger 993). The column
    -- stays so the signature does not change; send_outbox would hold an Arabic row of this type anyway.
    select l.id, lower(btrim(l.email)) as to_email, 'en'::text as lang,
           l as lead,
           case when p_now >= i.sent_at + interval '14 days' then 3
                when p_now >= i.sent_at + interval '7 days'  then 2
                when p_now >= i.sent_at + interval '3 days'  then 1 end as step
      from inv i join public.leads l on l.id = i.lead_id
     where l.invite_clicked_at is null and not coalesce(l.claimed, false) and l.approval_status is null
       and l.registration_submitted_at is null
       and p_now < i.sent_at + interval '21 days'
  )
  select c.id, c.step, c.to_email, c.lang, 'supplier_invite_nudge:' || c.id || ':' || c.step
    from c
   where c.step is not null
     and coalesce((c.lead).invite_status, '') not in ('bounced', 'complained', 'unsubscribed')
     and not exists (select 1 from public.email_suppressions s where lower(s.email) = c.to_email)
     and case when p_include_fixtures
              -- the test path can only ever see a fixture: both marks, asserted, never assumed
              then (c.lead).company_name like 'ZZ DEMO%' and c.to_email like '%@example.invalid'
              else public.fn_supplier_outreach_reachable(c.lead, c.to_email) end
     and not exists (select 1 from public.agent_actions a
                      where a.kind = 'handoff' and a.agent = 'customer_support'
                        and a.target_id = 'delivery.request:supplier_invite_nudge:' || c.id || ':' || c.step)
   order by c.id
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_invite_test_send(p_lang text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_lang text := 'en';   -- suppliers are always written in English (founder, 28 Sep 2026); p_lang is ignored
  v_site text; v_subj text; v_body text; v_to text; v_id bigint; v_status text; v_err text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from app_secrets where key = 'public_site_url';
  select value into v_subj from app_secrets where key = 'invite_subject';
  select value into v_body from app_secrets where key = 'invite_body';
  v_to := 'zz-demo-supplier-invite-' || v_lang || '-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS') || '@example.invalid';
  if not public.fn_is_demo_email(v_to) then raise exception 'test address % is not a fixture address', v_to; end if;
  insert into notifications(type, to_email, to_role, subject, body, lang, status)
  values ('supplier_invite', v_to, 'supplier', v_subj,
          replace(replace(v_body, '{{company}}', 'ZZ DEMO Supplier'),
                  '{{link}}', coalesce(v_site, 'https://quotesdone.com') || '/' || v_lang || '/portal?t=00000000-0000-0000-0000-000000000000'),
          v_lang, 'queued')
  returning id, status, last_error into v_id, v_status, v_err;
  return jsonb_build_object('id', v_id, 'to', v_to, 'lang', v_lang, 'status', v_status, 'captured_note', v_err,
                            'subject', v_subj, 'never_reaches_resend', v_status = 'suppressed');
end
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_invites_hold_reason(p_day date)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(
    (select 'public holiday: ' || c.event_name from public.company_calendar c
      where c.kind = 'public_holiday' and p_day between c.starts_on and coalesce(c.ends_on, c.starts_on)
      order by c.starts_on limit 1),
    case when extract(isodow from p_day) in (6, 7) then 'the UAE weekend' end)
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_is_demo(p_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select coalesce((select l.is_demo from public.leads l where l.id = p_id), false) $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_knowledge_graph(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with mine as (
    select lc.slug, lc.is_primary, lc.score, 'lead_category' as src
    from lead_category lc where lc.lead_id = p_lead_id
    union
    select t, false, null::numeric, 'confirmed_trade'
    from public.supplier_capabilities sc, unnest(coalesce(sc.trades, '{}'::text[])) t
    where sc.supplier_id = p_lead_id
      and not exists (select 1 from lead_category lc where lc.lead_id = p_lead_id and lc.slug = t)
  ),
  neigh as (
    select case when e.src_ref = m.slug then e.dst_ref else e.src_ref end as slug,
           (e.props->>'companies')::int as companies
    from graph_edges e join mine m on m.slug in (e.src_ref, e.dst_ref)
    where e.rel = 'adjacent_to' and e.src_kind = 'category'
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'basis', 'the trades this company confirmed and the categories it is listed in, and the categories its competitors also serve',
    'my_categories', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'slug', m.slug,
        'label', coalesce((select n.label from graph_nodes n where n.kind='category' and n.ref_id=m.slug),
                          (select t.label from public.taxonomy_trade t where t.code = m.slug),
                          replace(m.slug, '_', ' ')),
        'label_ar', (select t.label_ar from public.taxonomy_trade t where t.code = m.slug),
        'companies', coalesce((select (n.props->>'companies')::int from graph_nodes n where n.kind='category' and n.ref_id=m.slug),
                              (select count(*)::int from public.supplier_capabilities sc where sc.trades && array[m.slug])),
        'primary', m.is_primary, 'source', m.src) order by m.is_primary desc nulls last, m.slug), '[]'::jsonb)
      from mine m),
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
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_licence_name_mismatch(p leads)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.fn_company_name_norm(p.licence_legal_name) <> ''
     and public.fn_company_name_norm(p.licence_legal_name) <> public.fn_company_name_norm(p.company_name)
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_mandatory_check(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare l public.leads; v_miss text[]; v_label jsonb := jsonb_build_object(
  'reg_name', 'Company name', 'reg_mobile', 'Verified UAE mobile number', 'reg_email', 'Verified email address',
  'reg_licence', 'Trade licence', 'reg_profile', 'Company profile', 'reg_terms', 'Signed terms and conditions');
begin
  select * into l from public.leads where id = p_lead_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'No such lead.'); end if;
  v_miss := public.fn_supplier_mandatory_six(l);
  return jsonb_build_object(
    'ok', true, 'party_kind', 'supplier', 'id', p_lead_id, 'name', l.company_name,
    'complete', cardinality(v_miss) = 0,
    'have', (select coalesce(jsonb_agg(v_label->>k order by o), '[]') from unnest(array['reg_name','reg_mobile','reg_email','reg_licence','reg_profile','reg_terms']) with ordinality u(k, o) where not (k = any (v_miss))),
    'missing', (select coalesce(jsonb_agg(v_label->>k order by o), '[]') from unnest(v_miss) with ordinality u(k, o)),
    'missing_codes', to_jsonb(v_miss),
    'missing_count', cardinality(v_miss),
    'mandatory_total', 6);
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_mandatory_six(p leads)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select array_remove(array[
    case when coalesce(btrim(p.company_name), '') = '' then 'reg_name' end,
    case when not (coalesce(p.owner_phone_verified, false)
                   and regexp_replace(coalesce(nullif(btrim(p.phone), ''), p.phone_e164, ''), '[^0-9]', '', 'g') ~ '^9715[0-9]{8}$')
         then 'reg_mobile' end,
    case when not coalesce(p.owner_email_verified, false) then 'reg_email' end,
    case when not exists (select 1 from storage.objects o where o.bucket_id = 'supplier-docs' and o.name = p.license_doc_path)
         then 'reg_licence' end,
    case when not exists (select 1 from storage.objects o where o.bucket_id = 'supplier-docs' and o.name = p.company_profile_doc_path)
         then 'reg_profile' end,
    case when coalesce(btrim(p.signed_terms_path), '') = '' then 'reg_terms' end
  ], null)
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_mandatory_six_for(p_lead_id bigint)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.fn_supplier_mandatory_six(l) from public.leads l where l.id = p_lead_id
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_market(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (select * from public.leads where id = p_lead_id),
  flag as (select coalesce((select source from me), '') = 'qd_demo_fixture' as is_demo),
  -- This supplier's trades: what it CONFIRMED in supplier_capabilities, plus its sector code.
  mine as (
    select array_remove(array_cat(coalesce((select trades from public.supplier_capabilities where supplier_id = p_lead_id), '{}'::text[]),
                                  array[(select sector from me)]), null) as trades
  ),
  -- Competitors: any lead whose confirmed trades overlap this supplier's (the population
  -- fn_customer_decision_support counts as "suppliers covering this trade"), or whose sector string
  -- equals this supplier's. Same side of the demo fence, never self.
  peers as (
    select l.*
    from public.leads l, me, flag, mine
    where l.id <> me.id
      and coalesce(l.permanently_closed, false) = false
      and (coalesce(l.source, '') = 'qd_demo_fixture') = flag.is_demo
      and ((l.sector is not null and me.sector is not null and l.sector = me.sector)
           or exists (select 1 from public.supplier_capabilities sc where sc.supplier_id = l.id and sc.trades && mine.trades))
  ),
  peers_here as (
    select p.* from peers p, me
    where me.service_emirates is null
       or coalesce(array_length(me.service_emirates, 1), 0) = 0
       or p.emirate is null
       or exists (select 1 from unnest(me.service_emirates) e where p.emirate ilike '%' || e || '%')
  ),
  demand_all as (
    select i.* from public.inquiries i, flag
    where (coalesce(i.brief_source, '') = 'qd_demo_fixture') = flag.is_demo
      and i.created_at >= now() - interval '28 days'
  ),
  -- An enquiry in this supplier's category: its trades overlap, or its category names one of them.
  demand_mine as (
    select d.* from demand_all d, mine, me
    where (d.trades is not null and d.trades && mine.trades)
       or (d.category is not null and (d.category = any (mine.trades) or public.fn_norm_trades(d.category) && mine.trades))
  ),
  priced as (
    select q.quote_amount amt
    from public.quotes q join demand_mine d on d.id = q.inquiry_id, flag
    where (coalesce(q.source, '') = 'qd_demo_fixture') = flag.is_demo
      and q.quote_amount is not null and q.quote_amount > 0
  ),
  figures as (
    select
      (with c as (
         select count(*) filter (where created_at >= now() - interval '14 days') as recent,
                count(*) filter (where created_at <  now() - interval '14 days') as earlier
         from demand_mine)
       select case when c.recent = 0 and c.earlier = 0
         then jsonb_build_object(
                'available', false, 'value', null, 'direction', null,
                'basis', 'enquiries in your category over the last 28 days',
                'population', 0,
                'note', 'no enquiries in your category yet, so there is no series to trend')
         else jsonb_build_object(
                'available', true,
                'category', (select sector from me),
                'value', c.recent,
                'prior', c.earlier,
                'direction', case when c.recent > c.earlier then 'up'
                                  when c.recent < c.earlier then 'down' else 'flat' end,
                'pct', case when c.earlier > 0
                            then round(((c.recent - c.earlier)::numeric / c.earlier) * 100, 1)
                            else null end,
                'from_zero', c.earlier = 0,
                'share_pct', case when (select count(*) from demand_all) > 0
                             then round((c.recent::numeric
                                  / nullif((select count(*) from demand_all), 0)) * 100, 1)
                             else null end,
                'series', (
                  select coalesce(jsonb_agg(jsonb_build_object('week', w.wk, 'count', w.c) order by w.wk), '[]'::jsonb)
                  from (select date_trunc('week', created_at)::date wk, count(*) c
                        from demand_mine group by 1) w),
                'basis', 'enquiries in your category, two 14-day halves',
                'population', (select count(*) from demand_mine),
                'note', case when c.earlier = 0
                        then 'first activity in this window, so there is no prior period to take a percentage against'
                        else null end)
         end from c) as trend_obj,
      (with r as (select category cat, count(*) c from demand_all
                  where category is not null group by 1 order by count(*) desc limit 1)
       select case when not exists (select 1 from r)
         then jsonb_build_object(
                'available', false, 'value', null,
                'basis', 'enquiries over the last 28 days',
                'population', (select count(*) from demand_all),
                'note', 'that is a fact about requests, and none have been made')
         else jsonb_build_object(
                'available', true,
                'value', (select cat from r),
                'count', (select c from r),
                'basis', 'enquiries over the last 28 days, grouped by category',
                'population', (select count(*) from demand_all))
         end) as topcat_obj,
      (with s as (
         select count(*) n, round(avg(amt)) mean,
                round(percentile_cont(0.5)  within group (order by amt)) mid,
                round(percentile_cont(0.25) within group (order by amt)) lo,
                round(percentile_cont(0.75) within group (order by amt)) hi,
                min(amt) lowest, max(amt) highest
         from priced)
       select case when s.n = 0
         then jsonb_build_object(
                'available', false, 'value', null, 'currency', 'AED',
                'basis', 'quotes on enquiries in your category',
                'population', 0,
                'note', 'nothing in your category has been priced, so there is no market price')
         else jsonb_build_object(
                'available', true, 'currency', 'AED',
                'value', s.mean, 'median', s.mid, 'p25', s.lo, 'p75', s.hi,
                'low', s.lowest, 'high', s.highest,
                'basis', 'quotes on enquiries in your category over the last 28 days',
                'population', s.n)
         end from s) as money_obj
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'sector', (select sector from me),
    'trades', (select to_jsonb(trades) from mine),
    'population', case when (select is_demo from flag) then 'demo' else 'live' end,
    'competitors', jsonb_build_object(
      'available', true,
      'basis', 'suppliers whose confirmed trades overlap yours, or share your sector',
      'total', (select count(*) from peers),
      'in_my_area', (select count(*) from peers_here),
      'matchable', (
        select count(*) from peers p
        where public.fn_is_matchable(p.verified, p.banned, p.matching_blocked,
                                     p.approval_status, p.permanently_closed, p.chat_strikes)
          and exists (select 1 from public.supplier_capabilities sc
                      where sc.supplier_id = p.id and sc.confirmed_at is not null)
      ),
      'me_matchable', (
        select public.fn_is_matchable(m.verified, m.banned, m.matching_blocked,
                                      m.approval_status, m.permanently_closed, m.chat_strikes)
           and exists (select 1 from public.supplier_capabilities sc
                       where sc.supplier_id = m.id and sc.confirmed_at is not null)
        from public.leads m where m.id = p_lead_id
      ),
      'by_emirate', (
        select coalesce(jsonb_agg(jsonb_build_object('emirate', s.em, 'count', s.c) order by s.c desc), '[]'::jsonb)
        from (
          select p.emirate as em, count(*) as c
          from peers p where p.emirate is not null
          group by p.emirate order by count(*) desc limit 8
        ) s
      )
    ),
    'market_composition', jsonb_build_object(
      'available', true,
      'basis', 'competitors, grouped by category',
      'segments', (
        select coalesce(jsonb_agg(jsonb_build_object('name', s.nm, 'count', s.c) order by s.c desc), '[]'::jsonb)
        from (
          select coalesce(nullif(btrim(split_part(p.categories, ',', 1)), ''), coalesce(p.sector, 'Uncategorised')) as nm,
                 count(*) as c
          from peers p group by 1 order by count(*) desc limit 8
        ) s
      )
    ),
    'demand_trend',     (select trend_obj  from figures),
    'most_requested',   (select topcat_obj from figures),
    'avg_market_price', (select money_obj  from figures)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_name_norm(p_name text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
    when length(coalesce(p_name, '')) < 10 then null
    when p_name !~* '\m(llc|l\.l\.c|fze|fzco|fzc|fz-llc|est|establishment|trading|contracting|contractors|co|company|group|ltd|limited|industries|factory|enterprises)\M' then null
    else (select case
                   when regexp_replace(x.n, '\m(llc|l\.l\.c|fze|fzco|fzc|fz-llc|est|establishment|trading|contracting|contractors|co|company|group|ltd|limited|industries|factory|enterprises|general|building|materials|technical|services|service|maintenance|works|and|the|of|for|uae|dubai|abu|dhabi|sharjah|ajman|international|global|middle|east)\M', '', 'g') ~ '[[:alpha:]]{3,}'
                   then x.n end
            from (select string_agg(regexp_replace(tok, '\.+$', ''), ' ' order by ord) n
                    from regexp_split_to_table(lower(p_name), '[^[:alnum:].&-]+') with ordinality s(tok, ord)
                   where regexp_replace(tok, '\.+$', '') <> '') x)
  end
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_named_in(p_text text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with w as (
    select array_agg(regexp_replace(tok, '\.+$', '') order by ord) a
      from regexp_split_to_table(lower(coalesce(p_text, '')), '[^[:alnum:].&-]+') with ordinality s(tok, ord)
     where regexp_replace(tok, '\.+$', '') <> ''),
  g as (
    select distinct array_to_string(w.a[i:i + n - 1], ' ') run
      from w, generate_series(1, coalesce(cardinality(w.a), 0)) i, generate_series(1, 12) n
     where i + n - 1 <= cardinality(w.a))
  select l.company_name
    from g join public.supplier_public_name p on p.norm = g.run join public.leads l on l.id = p.lead_id
   limit 1
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_notice(p_lead bigint, p_type text, p_subject_en text, p_body_en text, p_subject_ar text, p_body_ar text, p_inquiry uuid DEFAULT NULL::uuid, p_quote uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare l record; v_ar boolean; v_subject text; v_body text; n int := 0;
begin
  select id, company_name,
         coalesce(nullif(btrim(claimed_by), ''), nullif(btrim(email), '')) as mail,
         coalesce(nullif(btrim(whatsapp), ''), nullif(btrim(phone), ''))  as tel
    into l from public.leads where id = p_lead;
  if not found then return 0; end if;
  v_ar := public.fn_registered_locale('supplier', null, p_lead) = 'ar';
  v_subject := case when v_ar then p_subject_ar else p_subject_en end;
  v_body := replace(case when v_ar then p_body_ar else p_body_en end, '{company}',
                    coalesce(nullif(btrim(l.company_name), ''), case when v_ar then 'الشركاء' else 'partner' end));
  if l.mail is not null then
    insert into public.notifications (type, kind, to_email, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status, requested_by, sender, lang)
    values (p_type, 'sales_engineer_' || p_type, l.mail, 'supplier', p_lead, p_inquiry, p_quote, 'email', v_subject, v_body, 'queued', 'sales_engineer', 'customer_support',
            case when v_ar then 'ar' else 'en' end);
    n := n + 1;
  end if;
  -- trg_wa_fanout has already made a WhatsApp twin for a supplier who opted in; otherwise queue one.
  if l.tel is not null and not exists (select 1 from public.notifications
                                        where channel = 'whatsapp' and lead_id = p_lead and type = p_type and created_at = now()) then
    insert into public.notifications (type, kind, to_email, to_phone, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status, requested_by, sender, lang)
    values (p_type, 'sales_engineer_' || p_type, l.mail, l.tel, 'supplier', p_lead, p_inquiry, p_quote, 'whatsapp', v_subject, v_body, 'queued', 'sales_engineer', 'customer_support',
            case when v_ar then 'ar' else 'en' end);
    n := n + 1;
  end if;
  return n;
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_notice_channel(p_version_no integer, p_channel text, p_whatsapp_opt text, p_verified_mobile text, p_confirmed_whatsapp text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
    when p_channel = 'whatsapp' and coalesce(p_version_no, 0) >= 12 then
      jsonb_build_object('to', p_confirmed_whatsapp, 'basis', 'confirmed_whatsapp',
        'reason', case when p_confirmed_whatsapp is null then 'no WhatsApp number confirmed in the portal' end)
    when p_channel = 'whatsapp' and p_version_no = 11 then
      case when p_whatsapp_opt = 'none'
           then jsonb_build_object('to', null, 'basis', 'registered_mobile', 'reason', 'the supplier said it does not use WhatsApp')
           else jsonb_build_object('to', p_verified_mobile, 'basis', 'registered_mobile',
                  'reason', case when p_verified_mobile is null then 'no verified registered mobile' end) end
    when p_channel = 'sms' and coalesce(p_version_no, 0) >= 11 then
      jsonb_build_object('to', p_verified_mobile, 'basis', 'registered_mobile',
        'reason', case when p_verified_mobile is null then 'no verified registered mobile' end)
    else jsonb_build_object('to', null, 'basis', 'not_agreed',
           'reason', 'the Supplier Agreement version accepted (' || coalesce('v' || p_version_no, 'none') || ') does not make ' || coalesce(p_channel, '?') || ' a notice channel')
  end
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_notice_route(p_lead bigint, p_email text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint; v_accepted text; v_opt text; v_no int; v_mobile text; v_key text; v_clause jsonb;
begin
  select l.id, l.accepted_terms_version, l.whatsapp_opt into v_id, v_accepted, v_opt from public.leads l
   where l.id = p_lead or (p_lead is null and p_email is not null and lower(l.claimed_by) = lower(btrim(p_email)))
   order by l.id limit 1;
  v_no := public.fn_supplier_agreement_version_no(v_accepted);
  v_mobile := case when v_id is not null then public.fn_verified_mobile('supplier', null, v_id, null) end;
  v_key := case when coalesce(v_no, 0) >= 12 then '12' when v_no = 11 then '11' else '10' end;
  select value -> v_key into v_clause from public.decision_policy where key = 'supplier_agreement_notice_clause';
  return jsonb_build_object('supplier_id', v_id, 'agreement_version', v_accepted, 'version_no', v_no,
    'whatsapp', public.fn_supplier_notice_channel(v_no, 'whatsapp', v_opt, v_mobile,
                  case when coalesce(v_no, 0) >= 12 and v_id is not null then public.fn_whatsapp_destination('supplier', null, v_id, null) end),
    'sms', public.fn_supplier_notice_channel(v_no, 'sms', v_opt, v_mobile, null),
    'clause_en', v_clause->>'en', 'clause_ar', v_clause->>'ar');
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_notice_whatsapp_twin_under_v11()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint; v_accepted text; v_opt text;
begin
  if coalesce(new.channel, 'email') <> 'email' or coalesce(new.to_role, '') <> 'supplier' or new.to_email is null
     or not exists (select 1 from public.decision_policy p, jsonb_array_elements_text(p.value) t
                     where p.key = 'supplier_formal_notice_types' and t = new.type) then
    return null;
  end if;
  select l.id, l.accepted_terms_version, l.whatsapp_opt into v_id, v_accepted, v_opt from public.leads l
   where l.id = new.lead_id or (new.lead_id is null and lower(l.claimed_by) = lower(new.to_email)) order by l.id limit 1;
  -- Answered (same/other/none): trg_wa_fanout already made or recorded the twin. Only unanswered v11 is missing.
  if v_id is null or v_opt is not null or public.fn_supplier_agreement_version_no(v_accepted) is distinct from 11
     or public.fn_verified_mobile('supplier', null, v_id, null) is null then
    return null;
  end if;
  insert into public.notifications (type, to_email, to_role, lead_id, inquiry_id, quote_id, subject, body, channel, status)
  values (new.type, new.to_email, new.to_role, v_id, new.inquiry_id, new.quote_id, new.subject, new.body, 'whatsapp', 'queued');
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_opportunities(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (
    select l.id, lower(coalesce(l.sector, '')) sector, l.emirate,
           coalesce(l.service_emirates, '{}'::text[]) service_emirates,
           (select sc.trades from public.supplier_capabilities sc
             where sc.supplier_id = l.id and sc.confirmed_at is not null) confirmed_trades,
           l.verified
      from public.leads l where l.id = p_lead_id
  ),
  -- ONLY THE ENQUIRIES WE SENT THIS SUPPLIER (public.inquiry_matches is the answer to "what may this
  -- supplier quote for"; matching is exact trade or none).
  cand as (
    select i.id, i.category, i.emirate, i.summary_masked as summary, i.scope_type, i.created_at, i.budget_masked as budget,
           nullif(btrim(coalesce(i.raw_input_masked, '')), '') requirement,
           lower(coalesce(i.category, '')) cat
      from public.inquiries i
     where coalesce(i.status, 'open') = 'open'
       and exists (select 1 from public.inquiry_matches m
                    where m.inquiry_id = i.id and m.supplier_id = p_lead_id)
  ),
  scored as (
    select c.*,
      (c.cat = me.sector and me.sector <> '')                                    as trade_hit,
      (c.emirate is not null and (c.emirate = me.emirate
        or c.emirate = any(me.service_emirates)))                                as location_hit,
      (coalesce(cardinality(me.confirmed_trades), 0) > 0)                        as capacity_known,
      -- KEYED, NOT READ: the trades the supplier ticked against the enquiry's trade codes.
      (coalesce(cardinality(me.confirmed_trades), 0) > 0 and c.category is not null
        and public.fn_taxonomy_trades_for(array[c.category]) && me.confirmed_trades) as capacity_hit,
      (select count(*) from public.quotes q
         join public.inquiries qi on qi.id = q.inquiry_id
        where q.supplier_id = p_lead_id and lower(coalesce(qi.category,'')) = c.cat) as similar_jobs
      from cand c cross join me
  ),
  ranked as (
    select s.*,
      round(100.0 * (
        (case when s.trade_hit then 40 else 0 end)
      + (case when s.location_hit then 30 else 0 end)
      + (case when s.capacity_known and s.capacity_hit then 30 else 0 end)
      ) / nullif(40 + 30 + (case when s.capacity_known then 30 else 0 end), 0)) as fit_score
      from scored s
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'count', (select count(*) from ranked),
    'ordered_by', 'fit_score desc — a ranked list, never chronological',
    'population', jsonb_build_object(
      'matched_to_me', (select count(*) from public.inquiry_matches where supplier_id = p_lead_id),
      'open_for_me', (select count(*) from cand),
      'my_quotes', (select count(*) from public.quotes where supplier_id = p_lead_id)
    ),
    'note', case when (select count(*) from ranked) = 0
                 then 'no open opportunities yet — nothing has been matched to you'
                 else null end,
    'opportunities', coalesce((
      select jsonb_agg(x order by x->>'fit_score' desc) from (
        select jsonb_build_object(
          'inquiry_id', r.id,
          'project_title', coalesce(nullif(btrim(coalesce(public.fn_supplier_safe_text(r.id, r.summary), '')), ''), r.category, 'Untitled project'),
          'category', r.category,
          'emirate', r.emirate,
          'requirement', public.fn_supplier_safe_text(r.id, r.requirement),
          'estimated_value', public.fn_supplier_safe_text(r.id, r.budget),
          'fit_score', r.fit_score,
          'match_pct', r.fit_score,
          'reasons', jsonb_build_array(
            jsonb_build_object('key', 'trade', 'applies', r.trade_hit,
              'text', case when r.trade_hit then 'This is your trade — ' || coalesce(r.category,'the same category')
                           else 'Matched to you on capability rather than on your registered sector' end),
            jsonb_build_object('key', 'location', 'applies', r.location_hit,
              'text', case when r.location_hit then 'Nearby location — ' || coalesce(r.emirate,'your service area')
                           else 'Outside the emirates you serve' end),
            jsonb_build_object('key', 'capacity', 'applies', r.capacity_known and r.capacity_hit, 'available', r.capacity_known,
              'text', case when not r.capacity_known
                           then 'Your capacity fits: not assessable — you have not confirmed your services yet'
                           when r.capacity_hit
                           then 'Your capacity fits — this trade is among the services you confirmed'
                           else 'Not among the services you confirmed' end),
            jsonb_build_object('key', 'history', 'applies', r.similar_jobs > 0,
              'available', (select count(*) from public.quotes where supplier_id = p_lead_id) > 0,
              'similar_jobs', r.similar_jobs,
              'text', case when (select count(*) from public.quotes where supplier_id = p_lead_id) = 0
                           then 'Previous similar project: you have not quoted on QuotesDone yet'
                           when r.similar_jobs > 0
                           then 'You worked on ' || r.similar_jobs || ' previous similar project(s)'
                           else 'No previous similar project on record' end)
          )
        ) x from ranked r
      ) s
    ), '[]'::jsonb)
  )
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_outreach_golive()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'supplier_outreach_golive'), false);
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_outreach_reachable(p leads, p_to text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(btrim(p_to), '') <> ''
     and coalesce(p.is_demo, false) = false
     and coalesce(p.company_name, '') !~* '^\s*zz\s*demo'
     and not public.fn_is_demo_email(p_to)
     and not public.fn_is_demo_email(p.email)
     and coalesce(p.banned, false) = false
     and coalesce(p.permanently_closed, false) = false
     and coalesce(p.invite_status, '') <> 'bounced'
     and not exists (select 1 from public.sanctions_ban b where b.lead_id = p.id)
     and not exists (select 1 from public.supplier_screening_hit h where h.lead_id = p.id and h.status in ('open', 'confirmed'))
     and coalesce((public.fn_email_sendable(p_to)->>'ok')::boolean, false)
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_own_word_reading_record(p_supplier_id bigint, p_word text, p_service_key text, p_reasoned boolean, p_held_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_status text := case when p_reasoned then 'reasoned' else 'needs_reasoning' end;
begin
  if p_reasoned and p_service_key is not null and not exists (
       select 1 from public.taxonomy_trade_service s where s.active and s.trade_code || '.' || s.code = p_service_key) then
    raise exception 'not a listed service: %', p_service_key using errcode = '22023';
  end if;
  insert into public.supplier_own_word_reading as r (supplier_id, word, service_key, status, held_id, reasoned_at, updated_at)
  values (p_supplier_id, btrim(p_word), case when p_reasoned then p_service_key end, v_status, p_held_id,
          case when p_reasoned then now() end, now())
  on conflict (supplier_id, word) do update set service_key = excluded.service_key, status = excluded.status,
    held_id = coalesce(excluded.held_id, r.held_id), reasoned_at = excluded.reasoned_at, updated_at = now()
  where not (excluded.status = 'needs_reasoning' and r.status = 'reasoned');
  return jsonb_build_object('supplier_id', p_supplier_id, 'word', btrim(p_word), 'status', v_status);
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_portfolio_gaps(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with sc as (select * from public.supplier_capabilities where supplier_id = p_lead_id and confirmed_at is not null),
  keys as (select s.trade_code, s.trade_code || '.' || s.code as k from public.taxonomy_trade_service s where s.active),
  silent as (
    select t.code, t.label, coalesce(t.label_ar, t.label) as label_ar
      from sc, unnest(coalesce(sc.trades, '{}'::text[])) tr
      join public.taxonomy_trade t on t.code = tr
     where public.fn_supplier_portfolio_match_reads_ticks()
       and exists (select 1 from keys where keys.trade_code = tr)
       and not exists (select 1 from unnest(coalesce(sc.services, '{}'::text[])) s
                         join keys on keys.k = btrim(s)
                        where keys.trade_code = tr and btrim(s) <> all (coalesce(sc.services_removed, '{}'::text[])))
  ),
  own as (
    select distinct btrim(w) as w
      from sc, unnest(coalesce(sc.services, '{}'::text[])) w
     where nullif(btrim(w), '') is not null and btrim(w) not in (select k from keys)
  ),
  -- THE SERVICE A WORD NAMES IS A REASONED READING (supplier_own_word_reading), never an alias pattern.
  named as (
    select o.w, array[r.service_key] as keys,
           '"' || s.label_en || '" under ' || t.label as en_list,
           '«' || s.label_ar || '» ضمن ' || coalesce(t.label_ar, t.label) as ar_list
      from own o
      join public.supplier_own_word_reading r on r.supplier_id = p_lead_id and r.word = o.w and r.status = 'reasoned'
      join public.taxonomy_trade_service s on s.active and s.trade_code || '.' || s.code = r.service_key
      join public.taxonomy_trade t on t.code = s.trade_code
  ),
  unnamed as (select o.w from own o where o.w not in (select w from named)),
  proposed as (
    select exists (select 1 from public.taxonomy_trade_proposal p, unnamed u
                    where p.supplier_id = p_lead_id and p.status = 'pending'
                      and (btrim(p.label_en) = u.w or btrim(p.label_ar) = u.w)) as yes
  )
  select case
    when not exists (select 1 from sc) then jsonb_build_array(jsonb_build_object(
      'code', 'services_not_confirmed',
      'en', 'You have not confirmed the services your company provides yet, so no inquiry can reach you.',
      'ar', 'لم تؤكّدوا بعد الخدمات التي تقدّمها شركتكم، ولذلك لا يصلكم أي استفسار.'))
    else
      coalesce((select jsonb_agg(jsonb_build_object(
          'code', 'trade_without_service', 'trade', s.code,
          'en', s.label || ': no service is ticked yet, so inquiries that name a service in this trade do not reach you.',
          'ar', s.label_ar || ': لم تحدّدوا أي خدمة فيه بعد، ولذلك لا تصلكم الاستفسارات التي تذكر خدمة في هذا التخصص.')
          order by s.code) from silent s), '[]'::jsonb)
      || coalesce((select jsonb_agg(jsonb_build_object(
          'code', 'own_word_is_a_service', 'word', n.w, 'services', to_jsonb(n.keys),
          'en', '«' || n.w || '» is on our list as ' || n.en_list
                || '. Tick the ones you provide in the Services tab so the inquiries that name them reach you.',
          'ar', '«' || n.w || '» مدرجة في قائمتنا باسم ' || n.ar_list
                || '. يُرجى تحديد ما تقدّمونه منها في تبويب «الخدمات» لتصلكم الاستفسارات التي تذكرها.')
          order by n.w) from named n), '[]'::jsonb)
      || coalesce((select jsonb_build_array(jsonb_build_object(
          'code', 'own_words', 'words', jsonb_agg(u.w order by u.w),
          'en', 'Written in your own words and not on our list: '
                || string_agg('«' || u.w || '»', ', ' order by u.w)
                || '. As written they match no inquiry. If one of them is on the list under another name, tick it there'
                || case when (select yes from proposed) then '; our sales engineer is reviewing them for the list' else '' end || '.',
          'ar', 'خدمات كتبتموها بأسلوبكم وليست في قائمتنا: '
                || string_agg('«' || u.w || '»', '، ' order by u.w)
                || '. ولا تُطابَق بصيغتها هذه مع أي استفسار. وإن وجدتم أيًّا منها في القائمة باسم آخر، فحدّدوه هناك'
                || case when (select yes from proposed) then '، ويراجعها مهندس المبيعات حاليًا لإضافتها إلى القائمة' else '' end || '.'))
          from unnamed u having count(*) > 0), '[]'::jsonb)
  end
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_portfolio_match_reads_ticks()
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_set text := nullif(current_setting('qd.probe_match_reads_ticks', true), ''); v_def text; v_n int;
begin
  if v_set is not null then return v_set::boolean; end if;
  select count(*), min(pg_get_functiondef(p.oid)) into v_n, v_def
    from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname = 'public' and p.proname = 'fn_match_capability';
  if v_n <> 1 then return false; end if;
  v_def := regexp_replace(v_def, '--[^\n]*', '', 'g');
  return position('silent_in' in v_def) = 0 and position('never_asked' in v_def) > 0;
exception when others then
  return false;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_portfolio_reminder_compose(p leads, p_gaps jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_ar boolean := false;   -- suppliers are always written in English (founder, 28 Sep 2026)
  v_lang text := 'en';
  v_name text := nullif(btrim(coalesce(p.company_name, '')), '');
  v_site text; v_link text; v_items text; v_subj text; v_body text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  v_link := coalesce(v_site, 'https://quotesdone.com') || '/' || v_lang || '/portal';
  select string_agg('• ' || (g->>v_lang), E'\n' order by o) into v_items
    from jsonb_array_elements(coalesce(p_gaps, '[]'::jsonb)) with ordinality x(g, o);

  if v_ar then
    v_subj := 'خدماتكم لم تُستكمل بعد، وقد تفوتكم استفسارات العملاء';
    v_body := coalesce('السادة/ ' || v_name || ' المحترمين،', 'السادة الكرام،') || E'\n\nتحية طيبة وبعد،\n\n'
      || 'نشكركم على إتمام توثيق شركتكم لدى QuotesDone. وقد راجع مهندس المبيعات ملف أعمالكم، وتبيّن أن بعض بياناته لم تُستكمل بعد. '
      || 'وتعتمد مطابقة الاستفسارات على الخدمات التي أكّدتموها، لذا نرجو استكمال ما يلي:'
      || E'\n\n' || coalesce(v_items, '')
      || E'\n\nطريقة الاستكمال (تستغرق دقيقتين تقريبًا):'
      || E'\n1. سجّلوا الدخول إلى بوابة الموردين: ' || v_link
      || E'\n2. يظهر تبويب «الخدمات» أولًا. حدّدوا تحت كل تخصص جميع الخدمات التي تقدّمها شركتكم.'
      || E'\n3. إن ظهر تخصص لا تعمل فيه شركتكم، فاضغطوا «إزالة هذا التخصص».'
      || E'\n4. إن لم تجدوا في القائمة خدمة تقدّمونها، فاكتبوها في خانة «أضيفوا الخدمات التي تقدّمونها» ثم اضغطوا «إعادة صياغة خدماتي».'
      || E'\n5. اضغطوا «تأكيد خدماتي» لحفظ التغييرات، أو «تحديث خدماتي» إن سبق لكم الحفظ.'
      || E'\n\nالخيارات المتاحة لكم:'
      || E'\n• تحديد الخدمات التي تقدّمونها، فتصلكم الاستفسارات التي تذكرها.'
      || E'\n• إزالة التخصص الذي لا تعملون فيه، فلا تصلكم استفساراته بعد ذلك.'
      || E'\n• إن احتجتم إلى المساعدة، يكفي الرد على هذه الرسالة أو مراسلتنا عبر واتساب، وسيستكمل فريقنا البيانات معكم.'
      || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،\nفريق خدمة العملاء — QuotesDone';
  else
    v_subj := 'Your services are not complete yet, so you may miss inquiries';
    v_body := coalesce('Dear ' || v_name || ',', 'Dear Sir or Madam,') || E'\n\n'
      || 'Thank you for completing your verification with QuotesDone. Our sales engineer has reviewed your company''s portfolio, and some of it is still missing. '
      || 'Inquiries are matched against the services you have confirmed, so please complete the following:'
      || E'\n\n' || coalesce(v_items, '')
      || E'\n\nHow to complete it (about two minutes):'
      || E'\n1. Sign in to your supplier portal: ' || v_link
      || E'\n2. The Services tab opens first. Under each trade, tick every service your company provides.'
      || E'\n3. If a trade is listed that your company does not work in, press "Remove this trade".'
      || E'\n4. If a service you provide is not on the list, write it under "Add the services you provide" and press "Rewrite my services".'
      || E'\n5. Press "Confirm my services" to save, or "Update my services" if you have saved before.'
      || E'\n\nYour options:'
      || E'\n• Tick the services you provide: you will receive the inquiries that name them.'
      || E'\n• Remove a trade you do not work in: you will no longer receive inquiries for it.'
      || E'\n• Need help? Reply to this e-mail or message us on WhatsApp, and our team will complete it with you.'
      || E'\n\nKind regards,\nQuotesDone Customer Support';
  end if;
  return jsonb_build_object('lang', v_lang, 'subject', v_subj, 'body', v_body, 'link', v_link);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_portfolio_reminder_still_due(p_lead_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_array_length(public.fn_supplier_portfolio_gaps(p_lead_id)) > 0
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_portfolio_reminder_tick(p_include_fixtures boolean DEFAULT false, p_now timestamp with time zone DEFAULT now(), p_lead_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_days int := public.fn_seat_clock_policy('supplier_portfolio_reminder_working_days', 3)::int;
  h public.agent_actions; l public.leads; v_gaps jsonb; v_due timestamptz; v_ev jsonb;
  e public.notifications; w public.notifications; v_key text; v_failed int;
  v_local timestamp := p_now at time zone 'Asia/Dubai';
  v_open_hours boolean;
  v_opened int := 0; v_complete int := 0; v_closed int := 0; v_waiting int := 0; v_capped int := 0;
begin
  -- 1. RE-VERIFY WHAT SUPPORT ANSWERED; CLOSE ONLY WHEN EVERY LEG IS FINAL. Only the originator closes.
  for h in select a.* from public.agent_actions a
            where a.kind = 'handoff' and a.agent = 'customer_support' and a.detail->>'type' = 'supplier.portfolio_incomplete'
              and a.status not in ('done', 'failed') and a.detail ? 'replied_at'
              and (p_lead_id is null or a.detail->>'lead_id' = p_lead_id::text)
            order by a.id loop
    v_ev := coalesce(h.evidence, '{}'::jsonb);
    if v_ev ? 'not_sent' then
      v_ev := v_ev || jsonb_build_object('reverified', 'nothing was sent, and the reason is recorded');
    else
      e := null; w := null;
      select * into e from public.notifications n where n.id = (v_ev->>'notification_id')::bigint;
      select * into w from public.notifications n where n.id = (v_ev#>>'{whatsapp,notification_id}')::bigint;
      if e.id is null or e.status is null or e.status in ('queued', 'pending', 'sending', 'claimed')
         or (w.id is not null and (w.status is null or w.status in ('queued', 'pending', 'sending', 'claimed'))) then
        -- BOUNDED (review of #869): a leg that is still not final after 3 days never will be by itself
        -- (the WhatsApp copy expires at 24h, the email outbox holds stale mail sooner). Waiting forever
        -- would be as one-way as closing early, so it closes saying so, and sales_engineer gets a finding.
        if h.created_at > p_now - interval '3 days' then v_waiting := v_waiting + 1; continue; end if;
        v_ev := v_ev || jsonb_build_object('reverified', 'a leg never reached a final state',
          'email_state', coalesce(e.status, case when e.id is null then 'no email row recorded' end),
          'whatsapp_state', coalesce(w.status, v_ev#>>'{whatsapp,state}'));
        perform public.fn_it_engineer_finding_upsert('portfolio_reminder_unfinished:' || h.target_id,
          left('A portfolio reminder for supplier ' || coalesce(h.detail->>'lead_id', '?') || ' never reached a final delivery state in 3 days', 300),
          'fn_supplier_portfolio_reminder_tick', 'agent_facing', 1,
          jsonb_build_object('handoff_id', h.id, 'owner_seat', 'sales_engineer', 'email_state', v_ev->'email_state',
                             'whatsapp_state', v_ev->'whatsapp_state'),
          '{}'::text[], '{}'::text[], 'sales_engineer');
        perform set_config('qd.handoff_closer', 'sales_engineer', true);
        perform public.fn_seat_handoff_complete(h.id, v_ev || jsonb_build_object('reverified_by', 'sales_engineer', 'reverified_at', p_now));
        perform set_config('qd.handoff_closer', '', true);
        v_closed := v_closed + 1; continue;
      end if;
      v_ev := v_ev || jsonb_build_object(
        'reverified', 'both legs reached a final state',
        'email', jsonb_build_object('status', e.status, 'sent_at', e.sent_at, 'provider_message_id', e.provider_message_id, 'reason', e.last_error),
        'whatsapp_final', case when w.id is null then v_ev->'whatsapp'
                               else jsonb_build_object('status', w.status, 'sent_at', w.sent_at, 'provider_message_id', w.provider_message_id, 'reason', w.last_error) end);
    end if;
    perform set_config('qd.handoff_closer', 'sales_engineer', true);
    perform public.fn_seat_handoff_complete(h.id, v_ev || jsonb_build_object('reverified_by', 'sales_engineer', 'reverified_at', p_now));
    perform set_config('qd.handoff_closer', '', true);
    v_closed := v_closed + 1;
  end loop;

  -- 2. DETECT, in Dubai working hours only (09:00-18:00 on a working day): a message about his account
  --    lands while his office is open. So a supplier due Friday 17:50 is reached on Monday's first tick
  --    after 09:00 (the window, then the 30-minute clock), which is accepted.
  v_open_hours := public.fn_is_working_day(v_local::date) and v_local::time >= time '09:00' and v_local::time < time '18:00';
  if not v_open_hours then
    return jsonb_build_object('ok', true, 'opened', 0, 'outside_working_hours', true, 'closed', v_closed, 'awaiting_final_state', v_waiting);
  end if;
  for l in select * from public.leads x
            where x.verified and x.approval_status = 'approved' and x.approved_at is not null and not coalesce(x.banned, false)
              and public.fn_add_working_days(x.approved_at, v_days) <= p_now
              and public.fn_add_working_days(x.approved_at, v_days) > p_now - interval '14 days'
              and (p_lead_id is null or x.id = p_lead_id)
              -- fn_seat_clock_lead_is_fixture's own test, on the columns: the healthy-day replay reads leads
              -- through a view whose row type the leads-typed function does not accept.
              and (p_include_fixtures or not (coalesce(x.is_demo, false) or coalesce(x.company_name, '') ~* '^\s*zz\s*demo'
                                              or public.fn_is_demo_email(x.email) or public.fn_is_demo_email(x.claimed_by)))
              and not exists (select 1 from public.agent_actions a
                               where a.kind = 'handoff' and a.agent = 'customer_support' and a.status <> 'failed'
                                 and a.target_id = 'supplier.portfolio_incomplete:' || x.id || ':' || extract(epoch from x.approved_at)::bigint)
            order by x.id loop
    v_key := 'supplier.portfolio_incomplete:' || l.id || ':' || extract(epoch from l.approved_at)::bigint;
    -- A HANDLER THAT KEEPS FAILING IS TRIED THREE TIMES, then recorded once for its seat, not every 30 minutes.
    select count(*) into v_failed from public.agent_actions a
     where a.kind = 'handoff' and a.agent = 'customer_support' and a.status = 'failed' and a.target_id = v_key;
    if v_failed >= 3 then
      if not exists (select 1 from public.it_engineer_finding where issue_key = 'portfolio_reminder_failed:' || v_key and closed_at is null) then
        perform public.fn_it_engineer_finding_upsert('portfolio_reminder_failed:' || v_key,
          left('The portfolio reminder for supplier ' || l.id || ' failed ' || v_failed || ' times and is no longer retried', 300),
          'fn_supplier_portfolio_reminder_tick', 'agent_facing', 1,
          jsonb_build_object('lead_id', l.id, 'handoff_key', v_key, 'owner_seat', 'sales_engineer',
                             'last_error', (select a.detail->>'error' from public.agent_actions a where a.target_id = v_key and a.status = 'failed' order by a.id desc limit 1)),
          '{}'::text[], '{}'::text[], 'sales_engineer');
      end if;
      v_capped := v_capped + 1; continue;
    end if;
    v_gaps := public.fn_supplier_portfolio_gaps(l.id);
    if jsonb_array_length(v_gaps) = 0 then v_complete := v_complete + 1; continue; end if;   -- did it straight away
    v_due := public.fn_add_working_days(l.approved_at, v_days);
    perform public.fn_seat_handoff('sales_engineer', 'customer_support', 'supplier.portfolio_incomplete', 'leads', l.id || ':' || extract(epoch from l.approved_at)::bigint,
      jsonb_build_object('lead_id', l.id, 'verified_at', l.approved_at, 'due_at', v_due, 'gaps_at_detection', v_gaps,
                         'fixture', public.fn_seat_clock_lead_is_fixture(l)));
    v_opened := v_opened + 1;
  end loop;

  return jsonb_build_object('ok', true, 'opened', v_opened, 'complete_at_due', v_complete,
                            'closed', v_closed, 'awaiting_final_state', v_waiting, 'retries_exhausted', v_capped);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_product_match(p_inquiry_id uuid, p_lead_id bigint, p_asked uuid[] DEFAULT NULL::uuid[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with inq as (
    select coalesce(category, '') cat,
           concat_ws(' ', nullif(summary, ''), nullif(raw_input, ''), nullif(category, '')) want
      from public.inquiries where id = p_inquiry_id
  ),
  prod as (
    select p.id, p.name, p.brand, p.model, p.category_slug, left(coalesce(p.description, ''), 300) description
      from public.supplier_product p
     where p.supplier_id = p_lead_id
     order by p.id
     limit 40
  )
  select jsonb_build_object(
    'inquiry_id', p_inquiry_id,
    'supplier_id', p_lead_id,
    'status', case when p_asked is null then 'needs_reasoning' else 'reasoned' end,
    'basis', 'reasoned: which of your products the enquiry asks for is read by reasoning over the enquiry and each product record (think()), never by shared words. The category match is the category key itself.',
    'population', jsonb_build_object(
      'products', (select count(*) from prod),
      'note', case when (select count(*) from prod) = 0
                   then 'you have no products yet — upload a catalog and these become matchable' end),
    -- What the caller reasons over, handed back only while no reasoning has been supplied.
    'to_reason', case when p_asked is null then jsonb_build_object(
        'want', (select left(want, 4000) from inq),
        'products', coalesce((select jsonb_agg(jsonb_build_object('product_id', pr.id, 'name', pr.name, 'brand', pr.brand, 'model', pr.model,
                                  'category_slug', pr.category_slug, 'description', pr.description) order by pr.id) from prod pr), '[]'::jsonb)) end,
    'matches', case when p_asked is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
          'product_id', pr.id, 'name', pr.name, 'brand', pr.brand, 'model', pr.model,
          'asked', pr.id = any(p_asked),
          'category_match', pr.category_slug is not null and pr.category_slug = (select cat from inq))
        order by (pr.id = any(p_asked)) desc, pr.name)
      from prod pr), '[]'::jsonb) end
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_products(p_lead_id bigint, p_query text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with base as (
    select p.*
    from public.supplier_product p
    where p.supplier_id = p_lead_id
      and coalesce(p.status, 'active') <> 'archived'
  ),
  -- §7 "Searchable: YES". Matched over name, brand, model, category and the ATTRIBUTE VALUES, so a
  -- search for "5000 CFM" finds the unit whose spec says so rather than only matching its title.
  filtered as (
    select b.* from base b
    where p_query is null or btrim(p_query) = '' or (
         b.name              ilike '%' || btrim(p_query) || '%'
      or coalesce(b.brand, '')          ilike '%' || btrim(p_query) || '%'
      or coalesce(b.model, '')          ilike '%' || btrim(p_query) || '%'
      or coalesce(b.category_slug, '')  ilike '%' || btrim(p_query) || '%'
      or coalesce(b.subcategory_slug,'')ilike '%' || btrim(p_query) || '%'
      or coalesce(b.description, '')    ilike '%' || btrim(p_query) || '%'
      or exists (
           select 1 from jsonb_each_text(coalesce(b.attributes, '{}'::jsonb)) a
           where a.value ilike '%' || btrim(p_query) || '%'
              or a.key   ilike '%' || btrim(p_query) || '%')
      -- Certifications are a jsonb ARRAY and were unreachable by the attribute scan above, so
      -- "show me my Eurovent-certified units" returned nothing. A supplier searching their own
      -- catalogue by certification is the obvious case for §7's "Searchable: YES".
      or exists (
           select 1 from jsonb_array_elements_text(
             case when jsonb_typeof(b.certifications) = 'array' then b.certifications else '[]'::jsonb end) c
           where c ilike '%' || btrim(p_query) || '%')
    )
  )
  select jsonb_build_object(
    'supplier_id', p_lead_id,
    'query', p_query,

    -- ── §7's THREE COUNTS, over the supplier's whole catalogue, not the filtered page ───────────
    'product_count',  (select count(*) from base),
    -- coalesce(SUBcategory, category), not the reverse. category_slug is the broad family ('hvac')
    -- and is identical across a whole catalogue, so coalescing to it FIRST collapsed four distinct
    -- product categories into 1. The spec's "Categories: 18" means product categories, not sectors.
    'category_count', (select count(distinct coalesce(subcategory_slug, category_slug))
                       from base where coalesce(subcategory_slug, category_slug) is not null),
    -- The real number of specification keys the platform holds. Counted, never estimated.
    'attribute_count', (
      select coalesce(sum((select count(*) from jsonb_object_keys(coalesce(b.attributes, '{}'::jsonb)))), 0)
      from base b
    ),
    'searchable', true,

    -- ── §5's WAREHOUSE PANEL: the three quantities, over the SUPPLIER's own stock ────────────────
    -- inv_items is NOT this, and the distinction matters. Measured: inv_items has no supplier_id at
    -- all, and carries inventory_account / cogs_account / reorder_point — it is QuotesDone's OWN
    -- accounting ledger. A supplier's warehouse could never appear in it, so scoring §5 against it
    -- would have been unsatisfiable by any correct implementation.
    -- A supplier's stock lives on the variant, which is also where §8's "Available: 120" comes from.
    'stock', (
      select jsonb_build_object(
        'available',     coalesce(sum(nullif(v.attributes ->> 'available_units', '')::numeric), 0),
        'reserved',      coalesce(sum(nullif(v.attributes ->> 'reserved_units', '')::numeric), 0),
        'in_production', coalesce(sum(nullif(v.attributes ->> 'in_production_units', '')::numeric), 0),
        'skus', count(*)
      )
      from public.supplier_product_variant v
      join base b2 on b2.id = v.product_id
      where v.active
    ),

    'match_count', (select count(*) from filtered),

    'catalogs', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id, 'status', c.status, 'version', c.version,
        'extracted_at', c.extracted_at, 'source', c.source_document_path
      ) order by c.created_at desc), '[]'::jsonb)
      from public.supplier_catalog c where c.supplier_id = p_lead_id
    ),

    -- ── §8 AI PRODUCT CARDS ─────────────────────────────────────────────────────────────────────
    -- Every field the spec draws on a card, from real columns. `ai_match` is NOT invented: it is
    -- null unless the product carries a computed match in its attributes, because §8's "AI Match
    -- 96%" is a claim about a specific opportunity and there are 0 inquiries on production. A card
    -- showing a confident percentage against nothing would be the exact fabrication this row's
    -- scorer exists to catch.
    'products', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', f.id,
        'name', f.name,
        'category', coalesce(f.subcategory_slug, f.category_slug),
        'brand', f.brand,
        'model', f.model,
        'description', f.description,
        'attributes', coalesce(f.attributes, '{}'::jsonb),
        'attribute_count', (select count(*) from jsonb_object_keys(coalesce(f.attributes, '{}'::jsonb))),
        'certifications', coalesce(f.certifications, '[]'::jsonb),
        'documents', coalesce(f.documents, '[]'::jsonb),
        'status', f.status,
        -- Availability comes from the variants, which is where stock policy lives.
        'variants', (
          select coalesce(jsonb_agg(jsonb_build_object(
            'sku', v.sku, 'attributes', v.attributes,
            'price_policy', v.price_policy, 'lead_time_policy', v.lead_time_policy,
            'active', v.active) order by v.sku), '[]'::jsonb)
          from public.supplier_product_variant v where v.product_id = f.id
        ),
        'reserved_units', (
          select sum(nullif(v.attributes ->> 'reserved_units', '')::numeric)
          from public.supplier_product_variant v where v.product_id = f.id and v.active
        ),
        'in_production_units', (
          select sum(nullif(v.attributes ->> 'in_production_units', '')::numeric)
          from public.supplier_product_variant v where v.product_id = f.id and v.active
        ),
        'available_units', (
          select sum((v.attributes ->> 'available_units')::numeric)
          from public.supplier_product_variant v
          where v.product_id = f.id and v.active
            and (v.attributes ->> 'available_units') ~ '^[0-9]+$'
        ),
        -- §8's "Compatible Projects". Real when the extractor recorded it, null otherwise.
        'compatible_projects', coalesce(f.attributes -> 'compatible_projects', 'null'::jsonb),
        'ai_match', (f.attributes ->> 'ai_match')::numeric,
        'evidence_refs', coalesce(f.evidence_refs, '[]'::jsonb)
      ) order by f.name), '[]'::jsonb)
      from (select * from filtered order by name limit 200) f
    )
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_quote_recommend(p_lead_id bigint, p_inquiry_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (select * from public.leads where id = p_lead_id),
  flag as (select coalesce((select source from me), '') = 'qd_demo_fixture' as is_demo),
  -- THE MATCH IS THE PERMISSION. Without a row here this enquiry does not exist for this supplier,
  -- and nothing below is computed for them.
  matched as (
    select exists (select 1 from public.inquiry_matches m
                    where m.inquiry_id = p_inquiry_id and m.supplier_id = p_lead_id) as ok
  ),
  inq as (select * from public.inquiries_supplier_safe where id = p_inquiry_id),

  -- The competing bids. A DRAFT IS NOT A BID: a quote that was never sent to the customer is a figure
  -- somebody was still typing, and counting it moved the midpoint a real supplier prices against.
  bids as (
    select q.supplier_id, q.quote_amount amt, q.lead_time, q.warranty, q.payment_terms
    from public.quotes q, flag, matched
    where matched.ok
      and q.inquiry_id = p_inquiry_id
      and q.supplier_id is distinct from p_lead_id
      and q.status in ('submitted', 'revealed')
      and q.quote_amount is not null and q.quote_amount > 0
      and (coalesce(q.source, '') = 'qd_demo_fixture') = flag.is_demo
  ),
  -- n IS A COUNT OF COMPANIES, not of rows (review of #854). count(*) let ONE rival submitting three
  -- priced options clear a three-bid floor by itself, and the median of those three is that rival's
  -- middle option. lowest and highest are computed for the wide_spread signal only; neither, and no
  -- percentile, ever leaves this routine.
  stat as (
    select count(distinct supplier_id) n,
           count(*) n_rows,
           percentile_cont(0.5) within group (order by amt) mid_raw,
           min(amt) lowest, max(amt) highest
    from bids
  ),
  -- THE BRACKET, AND WHY A BRACKET RATHER THAN A FIGURE (review of #854, and one correction on top).
  --
  -- The first version published the median with its p25 and p75. For three sorted bids a < b < c that
  -- is p25 = (a+b)/2 and p75 = (b+c)/2, so a = 2*p25 - median and c = 2*p75 - median: all three bids
  -- recovered to the fils out of the very payload whose comment promised none of them. An ODD
  -- population also makes the median itself one company's exact number, so no raw statistic can carry
  -- the guarantee at all.
  --
  -- Rounding the median was the next attempt and it failed on its own probe: the fixtures
  -- 50000 / 61000 / 72000 have a median of 61000, which is already a multiple of a thousand, so
  -- "rounded to the nearest AED 1,000" published bid b unchanged. A SYMMETRIC band fails the same way
  -- for the same reason — its own midpoint is the number it was meant to hide.
  --
  -- What leaves this routine is therefore the BRACKET the midpoint falls in: [floor(mid/step)*step,
  -- +step), step being half an order of magnitude and never less than AED 1,000 (AED 5,000 wide around
  -- 61,000; AED 50,000 wide around 610,000). A bracket has no centre to invert and states only that
  -- the middle of the market is somewhere inside it.
  --
  -- THE GUARANTEE, STATED AS IT ACTUALLY HOLDS: this routine publishes no statistic of the competing
  -- bids finer than one bracket. It does not promise that no bid EQUALS a bracket edge — a rival whose
  -- price happens to be exactly AED 60,000 shares that number with the edge by coincidence, and
  -- nothing in the payload says which.
  band as (
    -- `mid` is the MIDDLE of the bracket, not its bottom edge (re-review of #854). The bottom edge was
    -- what the one-click accept sent, and it is up to a whole step low — a midpoint of 14,999 would
    -- have been quoted at 10,000, 33% under — so the Quote Builder systematically under-bid its users.
    -- The bracket's middle is derived from the bracket alone, reveals nothing the bracket does not,
    -- and is wrong by at most half a step in either direction rather than a whole step in one.
    select lo, lo + step as hi, lo + step / 2 as mid, step
    from (select floor(mid_raw / step) * step as lo, step
            from (select mid_raw, greatest(1000, power(10, floor(log(mid_raw)))::numeric / 2) as step
                    from stat) q) b
  ),

  -- The supplier's own habit, measured rather than assumed: across every enquiry they have priced,
  -- where did they sit against the midpoint of that enquiry's other bids? An index of 1.04 means
  -- this company prices 4% above the middle of the market, and it is computed from their own rows.
  -- ITS OWN FLOOR, AND THE SAME STATUS RULE (review of #854). This index was the leak the headline
  -- figure no longer is: idx = avg(my price / the median of the others') to three decimal places, with
  -- your_quotes_measured naming the denominator, so on a single measured enquiry a supplier could
  -- recover that median to about a tenth of a percent. It is now computed ONLY over enquiries where at
  -- least three OTHER COMPANIES submitted, rounded to two places, and published only when three or
  -- more enquiries went into it. The supplier's own drafts are excluded too: the outer query had no
  -- status filter at all, which contradicted this file's own rule that a draft is not a bid.
  habit as (
    select round(avg(ratio)::numeric, 2) idx, count(*) n
    from (
      select q.quote_amount / nullif((
               select percentile_cont(0.5) within group (order by o.quote_amount)
               from public.quotes o
               where o.inquiry_id = q.inquiry_id and o.supplier_id is distinct from q.supplier_id
                 and o.status in ('submitted', 'revealed') and o.quote_amount > 0
                 and (select count(distinct o2.supplier_id) from public.quotes o2
                       where o2.inquiry_id = q.inquiry_id and o2.supplier_id is distinct from q.supplier_id
                         and o2.status in ('submitted', 'revealed') and o2.quote_amount > 0) >= 3), 0) as ratio
      from public.quotes q, flag
      where q.supplier_id = p_lead_id and q.quote_amount > 0
        and q.status in ('submitted', 'revealed')
        and (coalesce(q.source, '') = 'qd_demo_fixture') = flag.is_demo
    ) r where r.ratio is not null
  ),
  -- DIFFERENCING (re-review of #854). your_index at two decimal places with an EXACT
  -- your_quotes_measured lets a supplier subtract one enquiry's contribution from the next and recover
  -- the new enquiry's median to about 3.5% — finer than a bracket, which would have made this the
  -- remaining way in. One decimal place, and the count as a band rather than a number.
  habit_out as (
    select case when n >= 3 then round(idx, 1) else null end idx,
           -- `when n < 3 then null` FIRST, and it is not decoration: without it a count of 0, 1 or 2
           -- failed the `n >= 3 and n <= 5` branch, fell through to `n <= 10`, and read "6-10" — a
           -- supplier with one measured enquiry told they had six to ten (reviewer's guard on #854).
           case when n < 3 then null
                when n <= 5 then '3-5' when n <= 10 then '6-10'
                when n <= 25 then '11-25' else 'more than 25' end n_band,
           n
    from habit
  ),

  -- ── DELIVERY, WARRANTY AND TERMS ARE TEXT, SO THEY ARE PICKED, NOT AVERAGED ───────────────────
  -- The average of "8-10 weeks" and "12-14 weeks" is not a promise anybody made.
  --
  -- WHAT THIS RETURNS AND WHAT IT NO LONGER RETURNS (22 Sep 2026, SP-N-02). It used to return
  -- `observed` — the distinct lead times and warranties every competitor had typed — and, when no two
  -- bids agreed, "the middle of the range", which is one named competitor's exact promise. A value
  -- only two or more suppliers independently gave is a market norm and may be suggested; anything
  -- else is a rival's answer and is now withheld, with `consensus` false saying so.
  ranked as (
    select 'lead' kind, lead_time v, count(*) c,
           min(coalesce(substring(lead_time from '\d+')::int, 999)) ord
    from bids where lead_time is not null group by 1, 2
    union all
    select 'warranty', warranty, count(*),
           min(coalesce(substring(warranty from '\d+')::int, 999))
    from bids where warranty is not null group by 1, 2
    union all
    select 'terms', payment_terms, count(*),
           min(coalesce(substring(payment_terms from '\d+')::int, 999))
    from bids where payment_terms is not null group by 1, 2
  ),
  picked as (
    select kind, v, c from (
      select r.kind, r.v, r.c,
             row_number() over (partition by r.kind order by r.c desc, r.ord) rn
      from ranked r
      where r.c >= 2
    ) z where z.rn = 1
  ),
  lead_pick  as (select v, c from picked where kind = 'lead'),
  warr_pick  as (select v, c from picked where kind = 'warranty'),
  terms_pick as (select v, c from picked where kind = 'terms'),

  -- ── RISK, AS NAMED SIGNALS RATHER THAN A MOOD ─────────────────────────────────────────────────
  risk as (
    select coalesce(jsonb_agg(jsonb_build_object('signal', s.k, 'detail', s.d)) filter (where s.hit), '[]'::jsonb) items,
           count(*) filter (where s.hit) n
    from (
      select 'not_matchable' k,
             not public.fn_is_matchable(m.verified, m.banned, m.matching_blocked,
                                        m.approval_status, m.permanently_closed, m.chat_strikes) hit,
             'Your account cannot currently receive work, so a quote sent now may not reach the customer.' d
      from me m
      union all
      select 'licence_missing',
             (select license_expiry is null from me),
             'No licence expiry is on file, and approval depends on it.'
      union all
      select 'licence_expired',
             (select coalesce(license_expiry < current_date, false) from me),
             'Your trade licence has expired.'
      union all
      select 'brief_incomplete',
             coalesce(((select completeness->>'score' from inq))::int < 60, true),
             'The customer brief is incomplete, so the scope you price may move after you send this.'
      union all
      -- The spread is computed here and the BOOLEAN leaves the routine; the two bids it is computed
      -- from never do.
      select 'wide_spread',
             (select case when mid_raw > 0 then (highest - lowest) / mid_raw > 0.4 else false end from stat),
             'The other bids disagree by more than 40%, which usually means the scope is being read differently.'
    ) s
  )

  select case
    when not (select ok from matched)
      -- Not 'forbidden': a job this supplier was not matched to must not be confirmed to exist.
      then jsonb_build_object(
        'available', false, 'reason', 'not_found',
        'lead_id', p_lead_id, 'inquiry_id', p_inquiry_id,
        'note', 'this enquiry is not one of yours')
    when (select n from stat) < 3
      -- THE THIN-MARKET FLOOR. With one competing company the midpoint IS its bid; with two, the pair
      -- brackets it. Three separate COMPANIES is the smallest population from which a rounded band
      -- describes a market rather than a named rival's quotation.
      then jsonb_build_object(
        'available', false, 'reason', 'thin_market',
        'lead_id', p_lead_id, 'inquiry_id', p_inquiry_id,
        'basis', 'quotes submitted by other suppliers on this enquiry',
        'population', (select n from stat),
        'note', 'fewer than three other companies have submitted a price for this enquiry, so there is '
                'no market midpoint to recommend against. With one or two, any figure we showed you '
                'would be their quotation, which is theirs and not ours to share.')
    else jsonb_build_object(
      'available', true,
      'lead_id', p_lead_id, 'inquiry_id', p_inquiry_id,
      -- The supplier-safe projection, scrubbed again: the raw inquiries.summary used to be read here,
      -- which walked around the inbox entirely (SP-N-02).
      'summary', public.fn_supplier_safe_text(p_inquiry_id, (select summary from inq)),
      'population', (select n from stat),
      'basis', 'the bracket the midpoint of every other company''s submitted bid on this enquiry falls in',

      -- The recommendation, as the bracket the market midpoint falls in. No median, no percentile, no
      -- lowest and no highest: every one of those is, or reconstructs, a figure a named competitor
      -- typed. `value` is the bottom of the bracket, because the portal's one-click accept has to send
      -- a number and that number must be one the routine derived from a bracket, not from a bid.
      'recommended_price', jsonb_build_object(
        'value', (select mid from band), 'currency', 'AED',
        'range_low', (select lo from band), 'range_high', (select hi from band),
        'bracket', (select step from band),
        'basis', 'the middle of the AED ' || (select step from band)::text || ' bracket that the midpoint of '
                 || (select n from stat)::text || ' competing companies'' bids falls in'),

      -- Where that recommendation sits, and where this supplier usually sits.
      -- THE VERDICT SAYS WHAT THE FIGURE IS (re-review of #854). It read "at the market midpoint",
      -- which was not true of a bracket edge and is not true of a bracket middle either: the real
      -- midpoint is somewhere inside the bracket and we deliberately do not say where.
      'market_position', jsonb_build_object(
        'verdict', 'inside the bracket the market midpoint falls in — we do not publish the midpoint itself',
        'your_index', (select idx from habit_out),
        'your_quotes_measured', (select n_band from habit_out),
        'detail', case when (select idx from habit_out) is null
                  then 'You have not priced enough enquiries yet for us to know where you usually sit.'
                  when (select idx from habit_out) > 1.02
                  then 'You normally price about ' || round(((select idx from habit_out) - 1) * 100)::text
                       || '% above the middle of the market, so this suggestion is lower than your habit.'
                  when (select idx from habit_out) < 0.98
                  then 'You normally price about ' || round((1 - (select idx from habit_out)) * 100)::text
                       || '% below the middle of the market, so this suggestion is higher than your habit.'
                  else 'You normally price close to the middle of the market, in line with this suggestion.' end),

      'delivery_estimate', jsonb_build_object(
        'value', (select v from lead_pick),
        'agreed_by', (select c from lead_pick),
        'consensus', (select count(*) from lead_pick) > 0,
        'basis', case when (select count(*) from lead_pick) > 0
                 then 'the lead time two or more of the competing bids gave'
                 else 'no two bids gave the same lead time, so there is no norm to suggest' end),

      'warranty', jsonb_build_object(
        'value', (select v from warr_pick),
        'agreed_by', (select c from warr_pick),
        'consensus', (select count(*) from warr_pick) > 0,
        'basis', case when (select count(*) from warr_pick) > 0
                 then 'the warranty two or more of the competing bids offered'
                 else 'no two bids offered the same warranty, so there is no norm to suggest' end),

      'payment_terms', jsonb_build_object(
        'value', (select v from terms_pick),
        'agreed_by', (select c from terms_pick),
        'consensus', (select count(*) from terms_pick) > 0,
        'basis', case when (select count(*) from terms_pick) > 0
                 then 'the payment terms two or more of the competing bids asked for'
                 else 'no two bids asked for the same terms, so there is no norm to suggest' end),

      'risk_level', jsonb_build_object(
        'value', case when (select n from risk) >= 3 then 'high'
                      when (select n from risk) >= 1 then 'medium' else 'low' end,
        'count', (select n from risk),
        'signals', (select items from risk),
        'recommended_action', case
          when (select n from risk) = 0
            then 'Nothing is working against this quote. We suggest sending it as proposed.'
          when exists (select 1 from jsonb_array_elements((select items from risk)) e
                       where e->>'signal' in ('not_matchable', 'licence_expired', 'licence_missing'))
            then 'We suggest fixing your account before you send this: a quote from an account that '
                 || 'cannot be matched may never reach the customer, whatever price is on it.'
          when exists (select 1 from jsonb_array_elements((select items from risk)) e
                       where e->>'signal' = 'wide_spread')
            then 'We suggest asking the customer to confirm the scope before you commit to a price. '
                 || 'The other bids disagree enough that they are probably not all pricing the same job.'
          when exists (select 1 from jsonb_array_elements((select items from risk)) e
                       where e->>'signal' = 'brief_incomplete')
            then 'We suggest putting your assumptions in writing with this quote, so a change of '
                 || 'scope later is a variation rather than an argument.'
          else 'We suggest treating the suggested price as indicative until more suppliers have priced this.'
          end,
        'basis', 'five checked signals on your account, the brief and the shape of the competing bids'))
  end;
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_readings_due(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with l as (select id, nullif(btrim(coalesce(capability_summary, '')), '') summary from public.leads where id = p_lead_id),
  sc as (select * from public.supplier_capabilities where supplier_id = p_lead_id and confirmed_at is not null),
  keys as (select s.trade_code || '.' || s.code as k from public.taxonomy_trade_service s where s.active),
  own as (
    select distinct btrim(w) as w from sc, unnest(coalesce(sc.services, '{}'::text[])) w
     where nullif(btrim(w), '') is not null and btrim(w) not in (select k from keys)
       and length(btrim(w)) <= 200   -- the reading table's own limit: a longer entry is never sent to a model it cannot be recorded for
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'capability', (select jsonb_build_object('summary', left(l.summary, 4000), 'summary_md5', md5(l.summary)) from l
                    where l.summary is not null
                      and not exists (select 1 from public.supplier_capability_reading r where r.lead_id = l.id and r.summary_md5 = md5(l.summary))),
    'own_words', coalesce((select jsonb_agg(o.w order by o.w) from own o
                    where not exists (select 1 from public.supplier_own_word_reading r where r.supplier_id = p_lead_id and r.word = o.w)), '[]'::jsonb),
    'candidates', coalesce((select jsonb_agg(jsonb_build_object('key', s.trade_code || '.' || s.code, 'label', s.label_en, 'label_ar', s.label_ar) order by s.trade_code, s.sort, s.code)
                    from public.taxonomy_trade_service s, sc
                   where s.active and s.trade_code = any(coalesce(sc.trades, '{}'::text[]))), '[]'::jsonb))
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_registration_reminder_compose(p leads, p_stage text, p_step integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_ar boolean := false;   -- suppliers are always written in English (founder, 28 Sep 2026)
  v_lang text; v_site text; v_link text; v_name text := nullif(btrim(coalesce(p.company_name, '')), '');
  v_items_en text; v_items_ar text; v_due_en text; v_due_ar text; v_last boolean := p_step >= 2;
  v_greet text; v_subj text; v_body text;
  v_label jsonb := jsonb_build_object(
    'reg_name',        jsonb_build_array('company name', 'اسم الشركة'),
    'reg_mobile',      jsonb_build_array('a verified UAE mobile number', 'رقم جوال إماراتي موثَّق'),
    'reg_email',       jsonb_build_array('a verified e-mail address', 'بريد إلكتروني موثَّق'),
    'reg_licence',     jsonb_build_array('trade licence', 'الرخصة التجارية'),
    'reg_profile',     jsonb_build_array('company profile', 'الملف التعريفي للشركة'),
    'reg_terms',       jsonb_build_array('the signed supplier terms', 'الموافقة الموقّعة على شروط المورِّد'));
begin
  if p_stage not in ('clicked', 'started', 'incomplete') or p_step not in (1, 2) then
    raise exception 'fn_supplier_registration_reminder_compose: unknown stage % or step %', p_stage, p_step;
  end if;
  v_lang := case when v_ar then 'ar' else 'en' end;
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  v_site := coalesce(v_site, 'https://quotesdone.com');
  v_link := v_site || '/' || v_lang || '/portal'
            || case when p_stage = 'clicked' and p.claim_token is not null then '?t=' || p.claim_token::text else '' end;

  if p_stage = 'incomplete' then
    select string_agg(coalesce(v_label->k->>0, k), ', ' order by o), string_agg(coalesce(v_label->k->>1, k), '، ' order by o)
      into v_items_en, v_items_ar from unnest(public.fn_supplier_mandatory_six(p)) with ordinality u(k, o);
    if p.license_expiry is not null and p.license_expiry < current_date then
      v_items_en := concat_ws(', ', v_items_en, 'a trade licence that is in date');
      v_items_ar := concat_ws('، ', v_items_ar, 'رخصة تجارية سارية المفعول');
    end if;
    v_items_en := coalesce(v_items_en, 'the items shown in your portal');
    v_items_ar := coalesce(v_items_ar, 'البنود الموضّحة في بوابتكم');
    v_due_en := to_char(coalesce(p.exception_due_at, now() + interval '14 days') at time zone 'Asia/Dubai', 'DD Mon YYYY');
    v_due_ar := to_char(coalesce(p.exception_due_at, now() + interval '14 days') at time zone 'Asia/Dubai', 'DD/MM/YYYY');
  end if;

  if v_ar then
    v_greet := case when v_name is null then 'السادة الكرام،' else 'السادة/ ' || v_name || ' المحترمين،' end;
    v_subj := case when v_last then 'تذكير أخير: ' else '' end
      || case p_stage when 'clicked' then 'دعوتكم للانضمام إلى الموردين المؤسِّسين في QuotesDone'
                      else 'استكمال تسجيلكم كمورِّد في QuotesDone' end;
    v_body := v_greet || E'\n\nتحية طيبة وبعد،\n\n'
      || case p_stage
           when 'clicked' then
             'نشكر لكم اطّلاعكم على دعوتنا للانضمام بصفة «مورِّد مؤسِّس» إلى QuotesDone، ونودّ إفادتكم بأن تسجيل شركتكم لم يبدأ بعد. '
             || 'ولا يستغرق التسجيل سوى دقائق معدودة، وهو مجاني دون أي عمولة على الأعمال التي تُرسى عليكم.'
             || E'\n\nللتسجيل، يُرجى الدخول إلى بوابة الموردين عبر الرابط التالي:\n\n' || v_link
           when 'started' then
             'نشكر لكم بدء تسجيل شركتكم مورِّدًا على منصة QuotesDone، ونودّ إفادتكم بأن طلب التسجيل لم يُستكمل بعد. '
             || 'ولا يستغرق استكماله سوى دقائق معدودة: بيانات الشركة، ورقم جوال وبريد إلكتروني موثَّقان، والرخصة التجارية، '
             || 'والملف التعريفي للشركة، والموافقة على شروط المورِّد.'
             || E'\n\nيمكنكم متابعة التسجيل من حيث توقفتم عبر الرابط التالي:\n\n' || v_link
           else
             'نفيدكم بأن طلب تسجيل شركتكم محفوظ لدينا، غير أنه ما زال ينقصه: ' || v_items_ar || '. '
             || 'ويُرجى استكماله في موعد أقصاه ' || v_due_ar || '، إذ يُغلق طلب التسجيل تلقائيًا بعد هذا التاريخ، ويمكنكم التسجيل من جديد في أي وقت.'
             || E'\n\nيمكنكم استكمال البنود المطلوبة عبر بوابة الموردين:\n\n' || v_link
         end
      || case when v_last then E'\n\nوهذا آخر تذكير نرسله إليكم بهذا الشأن.' else '' end
      || E'\n\nوفي حال عدم رغبتكم في تلقي هذه التذكيرات، يكفي الرد على هذه الرسالة لإزالة عنوانكم من القائمة.'
      || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
  else
    v_greet := case when v_name is null then 'Dear Sir or Madam,' else 'Dear ' || v_name || ',' end;
    v_subj := case when v_last then 'A last reminder: ' else '' end
      || case p_stage when 'clicked' then 'your invitation to join QuotesDone as a founding supplier'
                      else 'complete your QuotesDone supplier registration' end;
    v_body := v_greet || E'\n\n'
      || case p_stage
           when 'clicked' then
             'Thank you for opening our invitation to join QuotesDone as a founding supplier. Your company has not registered yet. '
             || 'It takes a few minutes, it is free, and there is no commission on the work you win.'
             || E'\n\nTo register, open your supplier portal here:\n\n' || v_link
           when 'started' then
             'Thank you for starting to register your company as a supplier on QuotesDone. The registration is not finished yet. '
             || 'It takes a few minutes: company details, a verified mobile number and e-mail address, your trade licence, '
             || 'your company profile and acceptance of the supplier terms.'
             || E'\n\nContinue where you left off:\n\n' || v_link
           else
             'Your registration is saved, but it still needs: ' || v_items_en || '. '
             || 'Please complete it by ' || v_due_en || '; after that date the registration closes automatically, and you are welcome to start again at any time.'
             || E'\n\nComplete the missing items in your supplier portal:\n\n' || v_link
         end
      || case when v_last then E'\n\nThis is the last reminder we will send about it.' else '' end
      || E'\n\nIf you would rather not receive these reminders, reply to this e-mail and we will remove your address.';
  end if;
  return jsonb_build_object('lang', v_lang, 'subject', v_subj, 'body', v_body, 'link', v_link);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_registration_reminders_due()
 RETURNS TABLE(lead_id bigint, stage text, step integer, last_activity timestamp with time zone, to_email text, dedupe_key text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with s as (
    select l.id, lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email))) as to_email,
           case when coalesce(l.approval_status, '') = 'action_required'
                     and l.exception_opened_at is not null and l.exception_closed_at is null
                     and coalesce(l.exception_due_at, 'infinity') > now() then 'incomplete'
                when coalesce(l.claimed, false) and l.registration_submitted_at is null
                     and coalesce(l.approval_status, '') not in ('approved', 'rejected', 'pending', 'action_required') then 'started'
                when not coalesce(l.claimed, false) and l.invite_clicked_at is not null then 'clicked'
           end as stage,
           case when coalesce(l.approval_status, '') = 'action_required'
                  then greatest(l.exception_opened_at, coalesce(l.portal_updated_at, l.exception_opened_at))
                when coalesce(l.claimed, false)
                  then coalesce(l.portal_updated_at, l.invite_clicked_at, l.invited_at, l.created_at)
                else l.invite_clicked_at end as last_activity,
           l as lead
      from public.leads l
     where l.invite_clicked_at is not null or coalesce(l.claimed, false) or l.approval_status = 'action_required'
  ), d as (
    select s.*, case when now() >= s.last_activity + interval '6 days' then 2
                     when now() >= s.last_activity + interval '2 days' then 1 end as step
      from s
     where s.stage is not null and s.last_activity is not null
       and now() < s.last_activity + interval '14 days'
  )
  select d.id, d.stage, d.step, d.last_activity, d.to_email,
         'supplier_registration_reminder:' || d.id || ':' || extract(epoch from d.last_activity)::bigint || ':' || d.step
    from d
   where d.step is not null
     and public.fn_supplier_outreach_reachable(d.lead, d.to_email)
     and not exists (select 1 from public.agent_actions a
                      where a.kind = 'handoff' and a.agent = 'customer_support'
                        and a.target_id = 'delivery.request:supplier_registration_reminder:' || d.id || ':'
                                          || extract(epoch from d.last_activity)::bigint || ':' || d.step)
   order by d.id
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_registration_state(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_exempt boolean; v_rank int; v_paid_until date; v_claimed boolean;
  v_fee numeric; v_ccy text; v_start date; v_free int;
  v_status text; v_due numeric; v_reason text;
begin
  select coalesce(l.subscription_exempt,false), l.founding_rank, l.subscription_paid_until, coalesce(l.claimed,false)
    into v_exempt, v_rank, v_paid_until, v_claimed
  from public.leads l where l.id = p_lead_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'lead_not_found', 'lead_id', p_lead_id);
  end if;

  select coalesce(p.supplier_reg_fee,1000), coalesce(p.supplier_reg_currency,'AED'), p.supplier_charging_starts, coalesce(p.supplier_free_count,1000)
    into v_fee, v_ccy, v_start, v_free
  from public.pricing_config p where p.id = 1;
  v_fee := coalesce(v_fee,1000); v_ccy := coalesce(v_ccy,'AED'); v_free := coalesce(v_free,1000);

  if v_exempt then
    v_status := 'exempt'; v_due := 0;
    v_reason := 'founding rank ' || coalesce(v_rank::text,'(unranked)') || ' is inside the permanently exempt founding cohort';
  elsif v_paid_until is not null and v_paid_until >= current_date then
    v_status := 'paid'; v_due := 0;
    v_reason := 'subscription paid until ' || v_paid_until::text;
  elsif v_start is not null and current_date < v_start then
    v_status := 'not_due'; v_due := 0;
    v_reason := 'charging does not start until ' || v_start::text;
  elsif v_start is null and (v_rank is null or v_rank <= v_free) then
    v_status := 'not_due'; v_due := 0;
    v_reason := case when v_rank is null then 'founding rank not yet stamped (stamped at verification); the first ' || v_free || ' verified registrations are free and there is no calendar start date'
                     else 'founding rank ' || v_rank || ' is within the first ' || v_free || ' free registrations; charging starts with registration ' || (v_free + 1) || ', on no calendar date' end;
  else
    v_status := 'due'; v_due := v_fee;
    v_reason := case when v_paid_until is null then 'never paid' else 'subscription lapsed on ' || v_paid_until::text end;
  end if;

  return jsonb_build_object(
    'ok', true, 'lead_id', p_lead_id, 'status', v_status, 'fee_due', v_due, 'currency', v_ccy,
    'may_quote', (v_status <> 'due'), 'exempt', v_exempt, 'founding_rank', v_rank,
    'paid_until', v_paid_until, 'charging_starts', v_start, 'free_count', v_free, 'claimed', v_claimed, 'reason', v_reason);
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_safe_text(p_inquiry uuid, p_text text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_out   text := p_text;
  v_seeds text[];
  v_seed  text;
begin
  if p_text is null or btrim(p_text) = '' then return p_text; end if;

  select array_remove(array[
           nullif(btrim(c.full_name), ''),
           nullif(btrim(c.email), ''),
           nullif(btrim(c.phone), ''),
           nullif(btrim(pr.name), '')
         ], null)
    into v_seeds
    from public.inquiries i
    left join public.customers c on c.id = i.customer_id
    left join public.projects  pr on pr.id = i.project_id
   where i.id = p_inquiry;

  foreach v_seed in array coalesce(v_seeds, array[]::text[]) loop
    -- Four characters is the floor _shared/anonymise.ts uses: below it a "seed" is a fragment that
    -- would mangle ordinary trade words rather than hide anybody.
    if length(v_seed) >= 4 then
      v_out := regexp_replace(v_out, regexp_replace(v_seed, '([.*+?^${}()|\[\]\\])', '\\\1', 'g'), '[hidden]', 'gi');
    end if;
  end loop;

  return public.mask_project_identity(v_out);
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_sanctions_screen(p_run_ids bigint[], p_rehearsal_tag text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_reh boolean := p_rehearsal_tag is not null;
  v_suppliers int := 0; v_entries int := 0; v_new int := 0; v_leads_hit int := 0; v_open int := 0;
  v_sources text; r record; h record; v_task bigint; v_hold bigint; v_title text; v_hold_title text; v_hits text;
begin
  select string_agg(distinct source || ' (' || entries || ' entries, fetched ' || to_char(fetched_at, 'DD Mon YYYY HH24:MI') || ' UTC, sha256 ' || left(coalesce(sha256, '?'), 12) || ')', '; ')
    into v_sources from public.screening_run where id = any(p_run_ids);

  create temp table tmp_screen_sup on commit drop as
    select l.id, f.field, f.val, public.fn_screening_normalise(f.val) as norm, public.fn_screening_tokens(f.val) as toks
      from public.leads l
      cross join lateral (values ('legal_name', l.company_name), ('licence_name', l.name_corrected_from),
                                 ('owner', l.signatory_name), ('contact', l.contact_name),
                                 ('email_domain', split_part(coalesce(l.email_domain, split_part(coalesce(l.email, ''), '@', 2)), '.', 1))) f(field, val)
     where (l.lifecycle_stage = 'registered' or l.approval_status = 'approved')
       and case when v_reh then l.company_name like 'ZZ DEMO — %'
                else coalesce(l.company_name, '') not like 'ZZ DEMO — %' and coalesce(l.email, '') not ilike '%@example.invalid' end
       and nullif(btrim(coalesce(f.val, '')), '') is not null;
  select count(distinct id) into v_suppliers from tmp_screen_sup;
  select count(*) into v_entries from public.screening_entry where run_id = any(p_run_ids);

  for h in
    select s.id as lead_id, s.field, s.val, e.id as entry_id, e.run_id, e.name, e.source, coalesce(e.reference, '') as reference, e.entry_type,
           case when s.field = 'email_domain' or s.norm = e.name_norm then 'exact' else 'token_overlap' end as kind,
           case when s.field = 'email_domain' or s.norm = e.name_norm then 1.0
                else round(least(cardinality(s.toks), cardinality(e.tokens))::numeric / greatest(cardinality(s.toks), cardinality(e.tokens), 1), 2) end as score
      from tmp_screen_sup s
      join public.screening_entry e
        on e.run_id = any(p_run_ids)
       and ((s.field <> 'email_domain' and s.norm = e.name_norm and length(s.norm) >= 6)
         or (s.field <> 'email_domain' and cardinality(s.toks) >= 2 and cardinality(e.tokens) >= 2
             and (s.toks <@ e.tokens or e.tokens <@ s.toks))
         or (s.field = 'email_domain' and length(s.norm) >= 6 and replace(e.name_norm, ' ', '') = s.norm))
  loop
    insert into public.supplier_screening_hit (run_id, lead_id, field, supplier_value, entry_id, entry_name, entry_source, entry_reference, entry_type, match_kind, score)
    values (h.run_id, h.lead_id, h.field, h.val, h.entry_id, h.name, h.source, h.reference, h.entry_type, h.kind, h.score)
    on conflict (lead_id, entry_source, entry_reference, field) do nothing;
    if found then v_new := v_new + 1; end if;
  end loop;

  -- THE TEAM UPDATE, ON SEATS THAT EXIST (18 Sep 2026). One DECISION task on the ceo, because a confirmed
  -- hit removes a supplier and every approval in this company is the CEO's; one HOLD on the sales_engineer,
  -- because supplier verification and supplier-facing outreach are that seat's work. Never the founder.
  for r in
    select x.lead_id, l.company_name, count(*) as n,
           string_agg(format('%s %L matched %L [%s %s] %s, score %s', x.field, x.supplier_value, x.entry_name, x.entry_source, x.entry_reference, x.match_kind, x.score), E'\n' order by x.score desc, x.id) as ev,
           string_agg(x.id::text, ', ' order by x.id) as ids
      from public.supplier_screening_hit x join public.leads l on l.id = x.lead_id
     where x.status = 'open' and x.task_id is null and x.run_id = any(p_run_ids)
     group by x.lead_id, l.company_name
  loop
    v_title := 'Sanctions screening hit: ' || coalesce(r.company_name, 'lead #' || r.lead_id) || ' — lead #' || r.lead_id;
    select id into v_task from public.org_tasks where title = v_title and status not in ('done', 'cancelled') order by id limit 1;
    if v_task is null then
      insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class, assigned_agent)
      values (null, v_title,
              'The weekly sanctions screening (' || coalesce(v_sources, 'fixture run') || ') matched a REGISTERED supplier. EVIDENCE:' || E'\n' || r.ev
              || E'\n\n' || 'No automatic removal has happened. Compare the supplier''s trade licence, owner and address against the listing and decide, per hit: '
              || 'select public.fn_supplier_screening_decide(<hit_id>, ''confirmed'' | ''false_positive'', ''ceo''). '
              || 'A confirmed hit moves the supplier through the existing status path (leads.banned + banned_reason, matching_blocked, approval_status rejected) and closes this task and the sales engineer''s hold; a false positive closes the hit. '
              || 'Hit id(s): ' || r.ids || '.',
              'assigned', 'supervised', false, 'compliance_check', 'ceo')
      returning id into v_task;
    end if;
    v_hold_title := 'Hold outreach and onboarding: ' || coalesce(r.company_name, 'lead #' || r.lead_id) || ' — lead #' || r.lead_id || ' (sanctions screening)';
    select id into v_hold from public.org_tasks where title = v_hold_title and status not in ('done', 'cancelled') order by id limit 1;
    if v_hold is null then
      insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class, assigned_agent)
      values (null, v_hold_title,
              'The CEO is reviewing a sanctions-screening match on this supplier (task #' || v_task || '). Send no invitation, follow-up or onboarding step to lead #' || r.lead_id
              || ' until the CEO decides; this task closes with that decision.',
              'assigned', 'autonomous', false, 'coordinate', 'sales_engineer')
      returning id into v_hold;
    end if;
    update public.supplier_screening_hit set task_id = v_task, bd_task_id = v_hold
     where lead_id = r.lead_id and status = 'open' and task_id is null;
    v_leads_hit := v_leads_hit + 1;
  end loop;

  -- retention: the latest fetch per source is the list; older entries go (their run rows stay as the record)
  if not v_reh then
    delete from public.screening_entry e
     where e.run_id not in (select max(id) from public.screening_run where status = 'ok' group by source)
       -- SANCTIONS_EVIDENCE_KEPT (18 Sep 2026): an entry a hit cites is evidence, not a stale copy of
       -- the list. Kept here, and a00_entry_cited_is_kept refuses it for every other caller.
       and not exists (select 1 from public.supplier_screening_hit sh
                        where sh.entry_id = e.id or (sh.entry_source = e.source and sh.entry_reference = e.reference));
  end if;

  select count(*) into v_open from public.supplier_screening_hit where status = 'open';
  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('supplier_sanctions_screen', 'ok',
          jsonb_build_object('suppliers', v_suppliers, 'entries', v_entries, 'hits_new', v_new, 'leads_hit', v_leads_hit, 'hits_open', v_open,
                             'runs', to_jsonb(p_run_ids), 'rehearsal', v_reh),
          'Sanctions screening: ' || v_suppliers || ' registered supplier(s) screened against ' || v_entries || ' list entries (' || coalesce(v_sources, 'no run') || '): '
          || v_new || ' new hit(s) on ' || v_leads_hit || ' supplier(s); ' || v_open || ' open. A hit opens ONE decision task on the ceo and ONE hold on the sales_engineer; nobody is removed automatically.'
          || case when v_reh then ' [rehearsal ' || p_rehearsal_tag || ']' else '' end, now(), now());
  return jsonb_build_object('suppliers', v_suppliers, 'entries', v_entries, 'hits_new', v_new, 'leads_hit', v_leads_hit, 'hits_open', v_open, 'sources', v_sources);
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_score_refresh()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n integer;
begin
  insert into supplier_score (lead_id, response_rate, avg_response_hours, quotes_submitted, quotes_won,
                              rejection_count, price_index, quality_rating, reliability, last_active, computed_at)
  select l.id,
         -- NO COALESCE. A null rv_response_rate means nobody has asked this supplier for anything,
         -- and 0% is a different claim entirely.
         l.rv_response_rate,
         null,
         coalesce(q.submitted, 0),
         coalesce(q.won, 0),
         coalesce(q.rejected, 0),
         q.price_index,
         -- QUALITY RATING IS EARNED ON THE PLATFORM, NOT SCRAPED FROM GOOGLE.
         -- Founder decision, 2026-08-08: rating exists only for VERIFIED suppliers, and comes from
         -- the customer's own 1-5 review after a job. leads.rating is the Google Maps star rating of
         -- a business we have never worked with; presenting it as a QuotesDone quality rating is a
         -- claim the platform has not earned. NULL when unverified or unreviewed -- an unrated
         -- supplier is unrated, and must never look like one every customer disliked.
         case when not coalesce(l.verified, false) then null
              else (select round(avg(rv.rating)::numeric * 20, 1)
                      from reviews rv where rv.supplier_id = l.id) end,
         -- Reliability: response behaviour dominates, win rate confirms it, rejections and refunds subtract.
         -- UNMEASURED IS NOT UNRELIABLE (12 Aug 2026). With no response history AND no quotes there is
         -- nothing to score, so this is NULL rather than 0 -- the same call the quality_rating comment
         -- above makes, and the same one fn_reputation_recompute now makes for employees. Note that
         -- verification alone must not manufacture a score either: the +20 below is a bonus on top of
         -- evidence, not evidence.
         case when l.rv_response_rate is null and coalesce(q.submitted, 0) = 0 then null
              else round(least(100, greatest(0,
                     coalesce(l.rv_response_rate,0) * 0.55
                   + (case when coalesce(q.submitted,0) > 0 then 100.0*coalesce(q.won,0)/q.submitted else 0 end) * 0.25
                   + (case when l.verified then 20 else 0 end)
                   - coalesce(q.rejected,0) * 2
                   - coalesce(l.rv_nonresponse_refunds,0) * 5
                 )), 1)
         end,
         greatest(l.portal_updated_at, l.approved_at, l.scraped_at),
         now()
  from leads l
  left join (
    select q.supplier_id,
           count(*) as submitted,
           count(*) filter (where q.status = 'won')      as won,
           count(*) filter (where q.status = 'rejected') as rejected,
           round(avg(q.quote_amount) filter (where q.quote_amount > 0), 2) as price_index
    from quotes q group by q.supplier_id
  ) q on q.supplier_id = l.id
  where l.id is not null
  on conflict (lead_id) do update set
    response_rate = excluded.response_rate, quotes_submitted = excluded.quotes_submitted,
    quotes_won = excluded.quotes_won, rejection_count = excluded.rejection_count,
    price_index = excluded.price_index, quality_rating = excluded.quality_rating,
    reliability = excluded.reliability, last_active = excluded.last_active, computed_at = now();
  get diagnostics n = row_count;
  return n;
end; $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_scorecard(p_lead bigint, p_month date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_month date := coalesce(date_trunc('month', p_month)::date,
                                 (date_trunc('month', (now() at time zone 'Asia/Dubai')) - interval '1 month')::date);
  v_trade text := public.fn_supplier_trade(p_lead); me record; a record; v_any boolean;
begin
  select * into me from public.fn_supplier_scorecard_month(v_month) s where s.lead_id = p_lead;
  -- the trade's average of each metric, only over suppliers who HAVE it, and only when there are at least three
  select case when count(s.response_hours) >= 3 then round(avg(s.response_hours), 1) end as resp,
         count(s.response_hours)::int as resp_n,
         case when count(s.win_rate) >= 3 then round(avg(s.win_rate), 3) end as win,
         count(s.win_rate)::int as win_n,
         case when count(s.rating) >= 3 then round(avg(s.rating), 2) end as rating,
         count(s.rating)::int as rating_n
    into a from public.fn_supplier_scorecard_month(v_month) s where v_trade is not null and s.trade = v_trade;
  v_any := me.response_hours is not null or me.win_rate is not null or me.rating is not null;
  return jsonb_build_object(
    'lead_id', p_lead, 'month', to_char(v_month, 'YYYY-MM'), 'month_label', to_char(v_month, 'FMMonth YYYY'),
    'trade', v_trade, 'trade_label', (select t.label from public.taxonomy_trade t where t.code = v_trade),
    'enough_data', v_any,
    'message', case when v_any then null else 'not enough data yet' end,
    'activity', jsonb_build_object('requests_sent', coalesce(me.invited, 0), 'quoted', coalesce(me.quoted, 0), 'won', coalesce(me.won, 0),
                                   'ratings', coalesce(me.ratings, 0)),
    'metrics', jsonb_build_object(
      'response_hours', jsonb_build_object('you', me.response_hours, 'trade_average', a.resp, 'trade_suppliers', coalesce(a.resp_n, 0), 'better', 'lower'),
      'win_rate',       jsonb_build_object('you', me.win_rate, 'trade_average', a.win, 'trade_suppliers', coalesce(a.win_n, 0), 'better', 'higher'),
      'rating',         jsonb_build_object('you', me.rating, 'trade_average', a.rating, 'trade_suppliers', coalesce(a.rating_n, 0), 'better', 'higher')),
    'min_suppliers_for_average', 3,
    'tip', public.fn_supplier_scorecard_tip(me.invited, me.quoted, me.response_hours, a.resp, me.win_rate, a.win, me.rating, a.rating));
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_scorecard_month(p_month date)
 RETURNS TABLE(lead_id bigint, trade text, invited integer, quoted integer, won integer, response_hours numeric, win_rate numeric, rating numeric, ratings integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with b as (   -- the month in Dubai, as timestamps
    select (date_trunc('month', p_month)::timestamp at time zone 'Asia/Dubai') as t0,
           ((date_trunc('month', p_month) + interval '1 month')::timestamp at time zone 'Asia/Dubai') as t1
  ), inv as (   -- sent a request in the month, and how long his first quote on it took
    select m.supplier_id, m.inquiry_id, min(m.sent_at) as sent_at,
           (select min(q.created_at) from public.quotes q where q.inquiry_id = m.inquiry_id and q.supplier_id = m.supplier_id) as quoted_at
      from public.inquiry_matches m, b
     where m.sent_at >= b.t0 and m.sent_at < b.t1 and m.supplier_id is not null
     group by m.supplier_id, m.inquiry_id
  ), quo as (   -- quoted in the month, and whether the customer chose him
    select q.supplier_id, q.inquiry_id,
           bool_or(exists (select 1 from public.transactions t where t.inquiry_id = q.inquiry_id and t.supplier_id = q.supplier_id and t.revealed_at is not null)
                   or exists (select 1 from public.inquiries i where i.id = q.inquiry_id and i.hired_supplier_id = q.supplier_id)) as won
      from public.quotes q, b
     where q.created_at >= b.t0 and q.created_at < b.t1 and q.supplier_id is not null
     group by q.supplier_id, q.inquiry_id
  ), rat as (
    select r.supplier_id, avg(r.rating)::numeric as rating, count(*)::int as n
      from public.reviews r, b where r.created_at >= b.t0 and r.created_at < b.t1 and r.supplier_id is not null
     group by r.supplier_id
  ), ids as (select supplier_id from inv union select supplier_id from quo union select supplier_id from rat)
  select s.supplier_id, public.fn_supplier_trade(s.supplier_id),
         (select count(*)::int from inv where inv.supplier_id = s.supplier_id),
         (select count(*)::int from quo where quo.supplier_id = s.supplier_id),
         (select count(*)::int from quo where quo.supplier_id = s.supplier_id and quo.won),
         (select round((percentile_cont(0.5) within group (order by extract(epoch from (inv.quoted_at - inv.sent_at)) / 3600.0))::numeric, 1)
            from inv where inv.supplier_id = s.supplier_id and inv.quoted_at >= inv.sent_at),
         (select round(avg(case when quo.won then 1.0 else 0.0 end), 3) from quo where quo.supplier_id = s.supplier_id),
         (select round(rat.rating, 2) from rat where rat.supplier_id = s.supplier_id),
         coalesce((select rat.n from rat where rat.supplier_id = s.supplier_id), 0)
    from ids s
    join public.leads l on l.id = s.supplier_id
   where not coalesce(l.banned, false)
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_scorecard_text(p_card jsonb, p_company text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare m jsonb := p_card->'metrics'; v_lines text := ''; k text; v jsonb; v_name text;
begin
  if coalesce((p_card->>'enough_data')::boolean, false) then
    foreach k in array array['response_hours', 'win_rate', 'rating'] loop
      v := m->k;
      v_name := case k when 'response_hours' then 'Response speed (median hours to your first quote)'
                       when 'win_rate' then 'Win rate (quotes the customer chose you on)' else 'Customer rating (out of 5)' end;
      v_lines := v_lines || '- ' || v_name || ': '
        || case when v->>'you' is null then 'not enough data yet'
                when k = 'win_rate' then round((v->>'you')::numeric * 100) || '%' else v->>'you' end
        || case when v->>'trade_average' is null then ' (trade average shown once 3 suppliers of your trade have this measure)'
                when k = 'win_rate' then ' (your trade: ' || round((v->>'trade_average')::numeric * 100) || '%)'
                else ' (your trade: ' || (v->>'trade_average') || ')' end || chr(10);
    end loop;
  else
    v_lines := 'There is not enough data yet for a scorecard: no request, quote or rating of yours in ' || (p_card->>'month_label') || '.' || chr(10);
  end if;
  return jsonb_build_object('lang', 'en',
    'subject', 'Your QuotesDone scorecard for ' || (p_card->>'month_label'),
    'body', 'Dear ' || coalesce(nullif(btrim(p_company), ''), 'partner') || ',' || chr(10) || chr(10)
      || 'Here is how you did in ' || (p_card->>'month_label')
      || coalesce(' against other ' || coalesce(p_card->>'trade_label', p_card->>'trade') || ' suppliers', '') || ':' || chr(10) || chr(10)
      || v_lines || chr(10)
      || 'One thing to improve: ' || (p_card->'tip'->>'text') || chr(10) || chr(10)
      || 'Your scorecard is always in your portal under Insights: https://quotesdone.com/supplier' || chr(10) || chr(10)
      || 'QuotesDone Sales Engineering');
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_scorecard_tip(p_invited integer, p_quoted integer, p_resp numeric, p_resp_avg numeric, p_win numeric, p_win_avg numeric, p_rating numeric, p_rating_avg numeric)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
    when coalesce(p_invited, 0) = 0 and coalesce(p_quoted, 0) = 0 and p_rating is null then jsonb_build_object('code', 'complete_profile',
      'text', 'Keep your services, the emirates you cover and your documents complete, so you are matched to more requests.')
    when coalesce(p_invited, 0) > 0 and coalesce(p_quoted, 0) = 0 then jsonb_build_object('code', 'answer_invitations',
      'text', 'You were sent ' || p_invited || ' request' || case when p_invited = 1 then '' else 's' end
        || ' and quoted none. Quoting even a few of them is the fastest way to win work.')
    when p_resp is not null and ((p_resp_avg is not null and p_resp > p_resp_avg) or (p_resp_avg is null and p_resp > 48)) then
      jsonb_build_object('code', 'respond_faster',
      'text', 'Your first quote took ' || p_resp || ' hours' || coalesce(' against your trade''s ' || p_resp_avg, '')
        || '. Customers compare the quotes that arrive first; aim to quote within 24 hours of a request.')
    when p_win is not null and ((p_win_avg is not null and p_win < p_win_avg) or (p_win_avg is null and p_win = 0 and p_quoted >= 3)) then
      jsonb_build_object('code', 'sharpen_quotes',
      'text', 'Customers chose ' || round(p_win * 100) || '% of your quotes' || coalesce(' against your trade''s ' || round(p_win_avg * 100) || '%', '')
        || '. Price every line, and state lead time, validity and warranty: the comparison reads them line by line.')
    when p_rating is not null and ((p_rating_avg is not null and p_rating < p_rating_avg) or (p_rating_avg is null and p_rating < 4)) then
      jsonb_build_object('code', 'lift_rating',
      'text', 'Your customers rated you ' || p_rating || '/5' || coalesce(' against your trade''s ' || p_rating_avg || '/5', '')
        || '. Call the customer within a day of a reveal and confirm the scope and dates in writing.')
    else jsonb_build_object('code', 'keep_going',
      'text', 'You are at or above your trade on every measure we have. Keep your services and documents current so you keep being matched.')
  end
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_screening_decide(p_hit_id bigint, p_decision text, p_actor text DEFAULT 'ceo'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare h record; l record; v_open int; v_closed int := 0; t bigint; v jsonb;
begin
  if p_decision not in ('confirmed', 'false_positive') then
    raise exception 'fn_supplier_screening_decide: decision must be confirmed or false_positive, not %', p_decision;
  end if;
  select * into h from public.supplier_screening_hit where id = p_hit_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such hit ' || p_hit_id); end if;
  if h.status <> 'open' then return jsonb_build_object('ok', false, 'reason', 'hit ' || p_hit_id || ' is already ' || h.status); end if;

  update public.supplier_screening_hit set status = p_decision, decided_by = p_actor, decided_at = now() where id = p_hit_id;

  if p_decision = 'confirmed' then
    select * into l from public.leads where id = h.lead_id;
    -- THE REGISTER FIRST. Every refusal below and in the surfaces asks public.sanctions_ban, so it
    -- has to exist before the leads UPDATE fires a00_leads_sanctioned_row_is_permanent.
    insert into public.sanctions_ban
      (lead_id, hit_id, entry_source, entry_reference, entry_name, name_key, licence_key,
       account_email, contact_email, decided_by, note)
    values (h.lead_id, p_hit_id, h.entry_source, h.entry_reference, h.entry_name,
            public.fn_screening_normalise(l.company_name),
            public.fn_sanctions_identity_key(l.trade_license_no),
            nullif(lower(btrim(coalesce(l.claimed_by, ''))), ''),
            nullif(lower(btrim(coalesce(l.email, ''))), ''),
            p_actor,
            'Confirmed sanctions hit on ' || h.entry_source || ' ' || h.entry_reference
            || ' (' || h.entry_name || ') matched ' || h.field || ' "' || coalesce(h.supplier_value, '') || '".')
    on conflict (lead_id) do nothing;
    -- do nothing, not do update: one register row per party, written by the FIRST confirmed hit.
    -- A second confirmed hit on the same party changes nothing here on purpose — the register says
    -- WHO is banned, and public.supplier_screening_hit, which is append-only from today, holds every
    -- entry that was ever matched. The audit trail is the join, not this row alone.

    -- the same columns fn_ban_overdue_dues writes: banned + reason, matching blocked, and the approval withdrawn
    update public.leads
       set banned = true,
           banned_reason = 'Sanctions screening hit confirmed by ' || p_actor || ' on ' || to_char(now(), 'DD Mon YYYY') || ': '
                           || h.entry_source || ' ' || h.entry_reference || ' (' || h.entry_name || ') matched ' || h.field || ' "' || coalesce(h.supplier_value, '') || '".',
           matching_blocked = true,
           matching_block_reason = 'Banned: sanctions screening hit confirmed (' || h.entry_source || ')',
           approval_status = case when approval_status = 'approved' then 'rejected' else approval_status end,
           rejection_reason = coalesce(rejection_reason, 'sanctions screening hit confirmed'),
           -- THE FRONT DOORS. claim_token is NOT NULL with a default, so the link is ROTATED
           -- rather than cleared: /{lang}/portal?t=<the token in the invitation e-mail> stops
           -- resolving, and the new value has never been sent to anybody. claimed goes false so no
           -- account continues to own the row.
           claim_token = gen_random_uuid(),
           claimed = false
     where id = h.lead_id;
    -- every other open hit on the same supplier is decided by the same fact
    update public.supplier_screening_hit set status = 'confirmed', decided_by = p_actor, decided_at = now()
     where lead_id = h.lead_id and status = 'open';

    -- THE SESSION THEY ALREADY HOLD (security review, 18 Sep 2026). login_otp refuses to MINT a
    -- session for a sanctioned party, and supplier_api / supplier_portal / kyc / supplier_pay /
    -- supplier_catalog_ingest re-ask on every request, so a token issued five minutes before the
    -- ban buys nothing. This closes the last of it at the identity provider itself: GoTrue refuses
    -- both sign-in and refresh for a user whose banned_until is in the future. Measured 18 Sep
    -- 2026: this function is owned by postgres, and has_table_privilege('postgres','auth.users',
    -- 'update') is true, so this line cannot fail for want of rights -- if it ever did, the whole
    -- decision would roll back rather than half-land, which is the correct failure.
    update auth.users u
       set banned_until = 'infinity'::timestamptz
     where lower(u.email) in (nullif(lower(btrim(coalesce(l.claimed_by, ''))), ''),
                              nullif(lower(btrim(coalesce(l.email, ''))), ''));
  end if;

  select count(*) into v_open from public.supplier_screening_hit where lead_id = h.lead_id and status = 'open';
  if v_open = 0 then
    foreach t in array array_remove(array[h.task_id, h.bd_task_id], null) loop
      v := public.fn_org_task_close_as_fact(t, p_actor,
             case when p_decision = 'confirmed'
                  then 'Sanctions screening hit CONFIRMED by ' || p_actor || ': ' || h.entry_source || ' ' || h.entry_reference || ' (' || h.entry_name || '). The supplier (lead #' || h.lead_id || ') is PERMANENTLY banned and recorded in public.sanctions_ban: not matched, not invited, not messaged, not shown, unable to sign in, and the name and trade licence cannot register again. The record is retained and sealed.'
                  else 'Sanctions screening hit reviewed by ' || p_actor || ' and recorded as a FALSE POSITIVE: ' || h.entry_source || ' ' || h.entry_reference || ' (' || h.entry_name || ') is not lead #' || h.lead_id || '. No status change; outreach and onboarding may continue.' end,
             jsonb_build_object('hit_id', p_hit_id, 'decision', p_decision, 'lead_id', h.lead_id, 'owner', p_actor));
      if coalesce((v ->> 'ok')::boolean, false) then v_closed := v_closed + 1; end if;
    end loop;
  end if;
  return jsonb_build_object('ok', true, 'hit_id', p_hit_id, 'decision', p_decision, 'lead_id', h.lead_id,
                            'open_hits_left', v_open, 'tasks_closed', v_closed,
                            'sanctions_ban', p_decision = 'confirmed');
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_set_availability(p_supplier_id bigint, p_state text, p_busy_until date DEFAULT NULL::date, p_by text DEFAULT 'supplier_api'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_today date := (now() at time zone 'Asia/Dubai')::date;
begin
  if p_state is null or p_state not in ('available', 'busy', 'paused') then
    return jsonb_build_object('ok', false, 'code', 'bad_state', 'error', 'Choose available, busy or paused.');
  end if;
  if p_state = 'busy' and (p_busy_until is null or p_busy_until <= v_today) then
    return jsonb_build_object('ok', false, 'code', 'busy_date_not_future', 'error', 'Choose the date you are available again: a date after today.');
  end if;
  if p_state = 'busy' and p_busy_until > v_today + 365 then
    return jsonb_build_object('ok', false, 'code', 'busy_date_too_far', 'error', 'A busy date must be within a year. To stop receiving requests for longer, pause instead.');
  end if;
  if not exists (select 1 from public.leads where id = p_supplier_id) then
    return jsonb_build_object('ok', false, 'code', 'no_company', 'error', 'No such supplier.');
  end if;
  insert into public.supplier_availability (supplier_id, state, busy_until, set_at, set_by)
  values (p_supplier_id, p_state, case when p_state = 'busy' then p_busy_until end, now(), coalesce(nullif(btrim(p_by), ''), 'supplier_api'))
  on conflict (supplier_id) do update
     set state = excluded.state, busy_until = excluded.busy_until, set_at = excluded.set_at, set_by = excluded.set_by;
  return jsonb_build_object('ok', true, 'availability', public.fn_supplier_availability_of(p_supplier_id));
end
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_stats(p_supplier_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v jsonb; v_quotes int; v_reveals int; v_hired int; v_lost int;
  v_qd_rev numeric; v_deal_val numeric; v_avg_lead numeric;
  v_pos jsonb; v_hist jsonb; v_rating numeric; v_rating_pct numeric; v_resp numeric;
  v_pending_reviews int; v_active_rfqs int;
begin
  select count(*) into v_quotes from quotes where supplier_id=p_supplier_id;
  select count(*) into v_reveals from transactions where supplier_id=p_supplier_id;
  select count(*) into v_hired from inquiries where hired_supplier_id=p_supplier_id;
  select count(*) into v_lost from inquiries i
     where i.hired_supplier_id is not null and i.hired_supplier_id<>p_supplier_id
       and exists (select 1 from quotes q where q.inquiry_id=i.id and q.supplier_id=p_supplier_id);
  select coalesce(sum(coalesce(reveal_fee,0)+coalesce(app_fee,0)),0),
         coalesce(sum(coalesce(quote_amount,0)),0)
    into v_qd_rev, v_deal_val
    from transactions where supplier_id=p_supplier_id and coalesce(refund_status,'')<>'approved';
  select round(avg(nullif(regexp_replace(coalesce(lead_time,''),'[^0-9.]','','g'),'')::numeric),1)
    into v_avg_lead from quotes where supplier_id=p_supplier_id and lead_time ~ '[0-9]';
  select app_rating, rv_response_rate into v_rating, v_resp from leads where id=p_supplier_id;
  if v_rating is not null then
    select round(100.0*(count(*) filter (where l2.app_rating <= v_rating))/nullif(count(*),0),0)
      into v_rating_pct
      from leads l2 where l2.sector = (select sector from leads where id=p_supplier_id) and l2.app_rating is not null;
  end if;
  select count(*) into v_pending_reviews from quotes where supplier_id=p_supplier_id and coalesce(review_status,'')='pending';
  select count(distinct q.inquiry_id) into v_active_rfqs from quotes q join inquiries i on i.id=q.inquiry_id
    where q.supplier_id=p_supplier_id and coalesce(i.status,'') in ('open','active','collecting','live');
  with myq as (select inquiry_id, quote_amount from quotes where supplier_id=p_supplier_id and quote_amount is not null and quote_amount>0),
  peer as (select inquiry_id, min(quote_amount) lo, avg(quote_amount) av, count(*) n
             from quotes where quote_amount is not null and quote_amount>0 group by inquiry_id),
  pos as (select m.quote_amount, p.lo, p.av,
                 case when p.lo>0 then (m.quote_amount-p.lo)/p.lo*100 end pct_low,
                 case when p.av>0 then (m.quote_amount-p.av)/p.av*100 end pct_avg,
                 (m.quote_amount<=p.lo*1.0001) as is_lowest
            from myq m join peer p using(inquiry_id) where p.n>=2)
  select jsonb_build_object('competitive_rfqs', count(*),'times_lowest', count(*) filter (where is_lowest),
    'lowest_rate', round(100.0*count(*) filter (where is_lowest)/nullif(count(*),0),0),
    'avg_pct_above_lowest', round(avg(pct_low)::numeric,1),'avg_pct_vs_average', round(avg(pct_avg)::numeric,1),
    'band', case when count(*)=0 then 'not enough data' when avg(pct_avg) <= -4 then 'below market average'
                 when avg(pct_avg) < 5 then 'around market average' else 'above market average' end
  ) into v_pos from pos;
  with months as (select date_trunc('month', (now() - (n||' month')::interval)) m from generate_series(0,11) n),
  qb as (select date_trunc('month',created_at) m, count(*) c from quotes where supplier_id=p_supplier_id group by 1),
  rb as (select date_trunc('month',revealed_at) m, count(*) c from transactions where supplier_id=p_supplier_id group by 1)
  select jsonb_agg(jsonb_build_object('month', to_char(months.m,'Mon YY'),'quotes', coalesce(qb.c,0), 'reveals', coalesce(rb.c,0)) order by months.m)
    into v_hist from months left join qb on qb.m=months.m left join rb on rb.m=months.m;
  v := jsonb_build_object('supplier_id', p_supplier_id,'quotes_total', v_quotes,'reveals', v_reveals,'hired', v_hired,
    'lost_to_others', v_lost,'win_ratio', round(100.0*v_hired/nullif(v_quotes,0),1),'reveal_ratio', round(100.0*v_reveals/nullif(v_quotes,0),1),
    'qd_revenue', v_qd_rev,'deal_value_awarded', v_deal_val,'avg_lead_time_days', v_avg_lead,'rating', v_rating,
    'rating_percentile', v_rating_pct,'response_rate', v_resp,'pending_reviews', v_pending_reviews,'active_rfqs', v_active_rfqs,
    'price_positioning', v_pos,'history_12m', v_hist,'document_expiries', fn_supplier_expiries(p_supplier_id));
  return v;
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_subscription()
 RETURNS TABLE(fee numeric, currency text, period text, start_date date, free_limit integer, fee_source text, start_source text, free_source text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with pc as (select * from public.pricing_config order by id limit 1),
       s as (
         select
           (select nullif(value,'')::numeric from public.app_secrets where key='supplier_subscription_aed')  as fee,
           (select nullif(value,'')::int     from public.app_secrets where key='founding_free_limit')         as free_limit
       )
  select
    coalesce((select supplier_reg_fee::numeric from pc), (select fee from s), 1000)                as fee,
    coalesce((select supplier_reg_currency from pc), 'AED')                                        as currency,
    coalesce((select supplier_reg_period   from pc), 'yearly')                                     as period,
    (select supplier_charging_starts from pc)                                                      as start_date,
    coalesce((select supplier_free_count from pc), (select free_limit from s), 1000)               as free_limit,
    case when (select supplier_reg_fee from pc) is not null then 'pricing_config'
         when (select fee from s) is not null then 'app_secrets' else 'default' end                as fee_source,
    case when (select supplier_charging_starts from pc) is not null then 'pricing_config'
         else 'no date: charging starts with the registration after the free count (founder, 6 Sep 2026)' end as start_source,
    case when (select supplier_free_count from pc) is not null then 'pricing_config'
         when (select free_limit from s) is not null then 'app_secrets' else 'default' end         as free_source;
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_target_by_trade_emirate(p_demo boolean DEFAULT false)
 RETURNS TABLE(trade text, label text, emirate text, registered integer, verified integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with sup as materialized (
    select sc.trades,
           public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes) as ok,
           array(select distinct lower(btrim(e)) from unnest(coalesce(sc.coverage_emirates, '{}'::text[]) || coalesce(l.service_emirates, '{}'::text[])) e
                  where nullif(btrim(e), '') is not null) as stated
      from public.supplier_capabilities sc join public.leads l on l.id = sc.supplier_id
     where sc.confirmed_at is not null and coalesce(l.is_demo, false) = p_demo
  ), em(emirate) as (
    values ('UAE'), ('Abu Dhabi'), ('Dubai'), ('Sharjah'), ('Ajman'), ('Umm Al Quwain'), ('Ras Al Khaimah'), ('Fujairah')
  )
  select t.code, t.label, em.emirate,
         count(s.trades)::int,
         (count(s.trades) filter (where s.ok))::int
    from public.taxonomy_trade t cross join em
    left join sup s on t.code = any(s.trades)
                   and (em.emirate = 'UAE' or cardinality(s.stated) = 0 or lower(em.emirate) = any(s.stated))
   where t.active
   group by t.code, t.label, em.emirate
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_tier(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with l as (
    select coalesce(verified, false) verified, rv_response_rate
      from public.leads where id = p_lead_id
  ),
  q as (
    select count(*)::int submitted,
           count(*) filter (where status = 'won')::int won_by_status
      from public.quotes where supplier_id = p_lead_id
  ),
  h as (
    select count(*)::int hired from public.inquiries where hired_supplier_id = p_lead_id
  ),
  s as (
    select (select submitted from q) submitted,
           greatest((select won_by_status from q), (select hired from h)) won,
           (select rv_response_rate from l) response_rate,
           -- NULL until a verified supplier has been reviewed: an unrated supplier is unrated.
           case when (select verified from l)
                then (select round(avg(rating)::numeric * 20, 1) from public.reviews where supplier_id = p_lead_id)
                else null end quality_rating
  ),
  -- ACTIVITY IS THE GATE. A supplier who has never quoted has no performance to measure.
  a as (select coalesce((select submitted from s), 0) > 0 active),
  t as (
    select case
      when not (select active from a) then 'unranked'
      when (select won from s) >= 10 and coalesce((select quality_rating from s), 0) >= 85 then 'platinum'
      when (select won from s) >= 5  and coalesce((select quality_rating from s), 0) >= 70 then 'gold'
      when (select won from s) >= 1                                                        then 'silver'
      else 'bronze'
    end tier
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'tier', (select tier from t),
    -- available:false is the difference between "we ranked you low" and "we cannot rank you yet".
    'available', (select active from a),
    'basis', case when (select active from a)
                  then 'quotes won and quality rating, from your quotes and reviews on QuotesDone'
                  else 'no quote has been submitted yet, so there is nothing to rank — this is not a low score' end,
    'basis_ar', case when (select active from a)
                  then 'الأعمال التي فزتم بها وتقييم الجودة، استنادًا إلى عروضكم وتقييماتكم على QuotesDone'
                  else 'لم تُقدَّم أي عروض أسعار بعد، فلا يوجد ما يُصنَّف، وهذا لا يعني تقييمًا منخفضًا' end,
    'ladder', jsonb_build_array(
      jsonb_build_object('tier','bronze',  'needs','submit your first quote',                              'needs_ar','قدّم أول عرض سعر'),
      jsonb_build_object('tier','silver',  'needs','win 1 job',                                            'needs_ar','فُز بعمل واحد'),
      jsonb_build_object('tier','gold',    'needs','win 5 jobs and hold a 70% quality rating',             'needs_ar','فُز بخمسة أعمال مع الحفاظ على تقييم جودة 70%'),
      jsonb_build_object('tier','platinum','needs','win 10 jobs and hold an 85% quality rating',           'needs_ar','فُز بعشرة أعمال مع الحفاظ على تقييم جودة 85%')
    ),
    'progress', jsonb_build_object(
      'quotes_submitted', (select submitted from s),
      'quotes_won', (select won from s),
      'quality_rating', (select quality_rating from s),
      'response_rate', (select response_rate from s)
    ),
    -- THE TIER DOES NOT AFFECT MATCHING. Founder, 2026-08-08: "a tier shouldnt effect a match."
    'benefits_active', false,
    'affects_matching', false,
    'benefits_note', 'Your tier never affects which work you are matched to, how you rank in search, '
      || 'or whether you are shown as preferred. Every supplier is matched on fit alone. '
      || 'This is a record of your track record, not a queue position.',
    'benefits_note_ar', 'لا يؤثر تصنيفكم إطلاقًا في الأعمال التي تُطابَقون معها، ولا في ترتيبكم في نتائج البحث، '
      || 'ولا في إبرازكم مورّدًا مفضّلًا؛ فكل مورّد يُطابَق وفق مدى الملاءمة وحدها. '
      || 'إنه سجلّ لأدائكم، لا ترتيب في طابور.'
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_trade(p_lead bigint)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(
    (select nullif(lower(btrim(c.trade_code)), '') from public.lead_trade_class c where c.lead_id = p_lead),
    (select nullif(lower(btrim(sc.trades[1])), '') from public.supplier_capabilities sc where sc.supplier_id = p_lead and sc.confirmed_at is not null),
    (select nullif(lower(btrim(l.sector)), '') from public.leads l where l.id = p_lead))
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_twin(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with l as (select * from public.leads where id = p_lead_id),
  s as (select *, quality_rating as q_pct from public.supplier_score where lead_id = p_lead_id),
  q as (
    select count(*)::int submitted,
           greatest(count(*) filter (where status = 'won')::int,
                    (select count(*)::int from public.inquiries where hired_supplier_id = p_lead_id)) won
    from public.quotes where supplier_id = p_lead_id
  ),
  home as (select * from public.fn_supplier_document_home(p_lead_id)),
  -- THE READING OF THE CURRENT SUMMARY ONLY: an edited summary is read again (its md5 changes).
  rd as (
    select r.* from public.supplier_capability_reading r, l
     where r.lead_id = l.id and r.status = 'reasoned'
       and r.summary_md5 = md5(nullif(btrim(coalesce(l.capability_summary, '')), ''))
  ),
  caps as (
    select
      (select coalesce(jsonb_array_length(case when jsonb_typeof(l.machinery)='array' then l.machinery else '[]'::jsonb end), 0) > 0 from l)
        or coalesce((select manufacturing from rd), false)                  as manufacturing,
      (select coalesce(l.engineers_count, 0) > 0 from l)
        or coalesce((select installation from rd), false)                   as installation,
      coalesce((select maintenance from rd), false)                         as maintenance,
      coalesce((select design from rd), false)                              as design
  ),
  conf as (
    select round(100.0 * (
        (case when l.company_name       is not null then 1 else 0 end)
      + (case when l.sector             is not null then 1 else 0 end)
      + (case when l.capability_summary is not null then 1 else 0 end)
      + (case when l.founded_year        is not null then 1 else 0 end)
      + (case when l.employee_count      is not null or l.team_size is not null then 1 else 0 end)
      + (case when coalesce(array_length(l.service_emirates, 1), 0) > 0 then 1 else 0 end)
      + (case when coalesce(l.certifications, '') <> ''
                or (jsonb_typeof(l.iso_certifications)='array' and jsonb_array_length(l.iso_certifications) > 0) then 1 else 0 end)
      + (case when l.products is not null and l.products <> '' then 1 else 0 end)
      + (case when l.website is not null then 1 else 0 end)
      + (case when l.description is not null then 1 else 0 end)
      ) / 10.0) as pct
    from l
  ),
  risk as (
    select case
      when l.banned then 'BANNED'
      when l.matching_blocked then 'BLOCKED'
      when (select path from home where key = 'trade_licence') is null
           and coalesce(l.chat_strikes, 0) = 0 and (select reliability from s) is null then null
      when l.license_expiry is not null and l.license_expiry < current_date then 'HIGH'
      when (select expiry from home where key = 'iso') < current_date then 'HIGH'
      when l.license_expiry is not null and l.license_expiry < current_date + 60 then 'MEDIUM'
      when coalesce(l.chat_strikes, 0) > 0 then 'MEDIUM'
      when (select reliability from s) is not null and (select reliability from s) < 60 then 'MEDIUM'
      else 'LOW' end as level
    from l
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'company_name', (select company_name from l),
    'verified', (select coalesce(verified, false) from l),
    'approval_status', (select approval_status from l),
    'intelligence_score', (
      select round(avg(v)) from (
        select (select q_pct from s) as v
        union all select (select reliability    from s)
        union all select (select response_rate  from s)
        union all select (select price_index    from s)
      ) t where v is not null
    ),
    'star_rating', (
      select case when avg(v) is null then null else greatest(1, least(5, round(avg(v) / 20.0))) end
      from (
        select (select q_pct from s) as v
        union all select (select reliability   from s)
        union all select (select response_rate from s)
      ) t where v is not null
    ),
    'health', jsonb_build_object(
      'quality', (select q_pct from s),
      'quality_raw',   (select quality_rating from s),
      'quality_scale', (select case when quality_rating is null then 'unrated' else 'earned_pct' end from s),
      'delivery', (select reliability    from s),
      'response', coalesce((select response_rate from s), (select rv_response_rate from l)),
      'pricing',  (select price_index    from s),
      'overall', (
        select round(avg(v)) from (
          select (select q_pct from s) as v
          union all select (select reliability   from s)
          union all select (select response_rate from s)
          union all select (select price_index   from s)
        ) t where v is not null
      ),
      'computed_at',        (select computed_at        from s),
      'avg_response_hours', (select avg_response_hours from s),
      'quotes_submitted',   (select submitted from q),
      'quotes_won',         (select won from q)
    ),
    'company_strength', (select capability_score from l),
    'capabilities', (
      select jsonb_build_array(
        jsonb_build_object('name', 'Manufacturing', 'has', (select manufacturing from caps)),
        jsonb_build_object('name', 'Installation',  'has', (select installation  from caps)),
        jsonb_build_object('name', 'Maintenance',   'has', (select maintenance   from caps)),
        jsonb_build_object('name', 'Design',        'has', (select design        from caps))
      )
    ),
    -- 'reasoned': the summary was read; 'needs_reasoning': it waits for the reasoning (shown from keyed
    -- data meanwhile); 'no_summary': there is nothing to read.
    'capability_reading', (select case when nullif(btrim(coalesce(l.capability_summary, '')), '') is null then 'no_summary'
                                       when exists (select 1 from rd) then 'reasoned' else 'needs_reasoning' end from l),
    'product_count', (
      select case when l.products is null or l.products = '' then 0
             else array_length(string_to_array(l.products, ','), 1) end from l
    ),
    'certifications', (
      select (case when jsonb_typeof(l.iso_certifications)='array' then l.iso_certifications else '[]'::jsonb end)
          || (case when coalesce(l.certifications,'') = '' then '[]'::jsonb
                   else to_jsonb(string_to_array(l.certifications, ',')) end) from l
    ),
    'production_capacity', (
      select jsonb_build_object(
        'estimated', case
          when l.team_size is null and l.engineers_count is null and l.warehouse_area is null then null
          else coalesce(l.team_size, 0) * 40 + coalesce(l.engineers_count, 0) * 120
               + coalesce(round(nullif(regexp_replace(coalesce(l.warehouse_area,''), '[^0-9]', '', 'g'), '')::numeric / 10.0), 0) end,
        'is_estimate', true,
        'basis', jsonb_build_object('team_size', l.team_size, 'engineers', l.engineers_count,
                                    'warehouse_area', l.warehouse_area,
                                    'machinery_lines', coalesce(jsonb_array_length(case when jsonb_typeof(l.machinery)='array' then l.machinery else '[]'::jsonb end), 0))
      ) from l
    ),
    'best_opportunities', (
      select case when coalesce(l.categories,'') = '' then '[]'::jsonb
                  else to_jsonb(string_to_array(l.categories, ',')) end from l
    ),
    'risk_level', (select level from risk),
    'risk_basis', case when (select level from risk) is null
                       then 'not assessed: no trade licence on file and no history yet'
                       else 'trade licence and certificate expiry, bans, strikes and computed reliability' end,
    'established_year', (select founded_year from l),
    'employee_count',   (select coalesce(l.employee_count, l.team_size) from l),
    'emirates',         (select coalesce(to_jsonb(coalesce(l.service_emirates, '{}'::text[])), '[]'::jsonb) from l),
    'countries',        (select coalesce(to_jsonb(coalesce(l.service_emirates, '{}'::text[])), '[]'::jsonb) from l),
    'ai_confidence',    (select pct from conf),
    'capability_map', (
      select jsonb_build_object(
        'root', coalesce(l.sector, 'Supplier'),
        'children', (
          select jsonb_agg(jsonb_build_object('name', c.name))
          from (
            select 'Manufacturing' as name where (select manufacturing from caps)
            union all select 'Installation' where (select installation from caps)
            union all select 'Maintenance'  where (select maintenance  from caps)
            union all select 'Design'       where (select design       from caps)
          ) c
        )
      ) from l
    ),
    'documents', (
      select jsonb_agg(jsonb_build_object(
        'kind', case h.key when 'trade_licence' then 'Trade licence' when 'iso' then 'ISO certification' else 'Manufacturer authorisation' end,
        'key', h.key, 'expiry', h.expiry, 'source', h.source,
        'doc_status', case when h.path is null then 'MISSING'
                           when h.expiry is null then 'UNDATED'
                           when h.expiry < current_date then 'EXPIRED'
                           else 'VALID' end)
        order by case h.key when 'trade_licence' then 0 when 'iso' then 1 else 2 end)
      from home h where h.key in ('trade_licence', 'iso', 'manufacturer_auth')
    ),
    -- the demo fence is the leads.is_demo flag, never a word found in the tags
    'is_demo', (select coalesce(l.is_demo, false) from l),
    'matchable', (select public.fn_is_matchable(l.verified, l.banned, l.matching_blocked,
                          l.approval_status, l.permanently_closed, l.chat_strikes) from l)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_workspaces(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with rel as (
    select distinct i.id as inquiry_id
    from public.inquiries i
    where exists (select 1 from public.inquiry_matches m
                  where m.inquiry_id = i.id and m.supplier_id = p_lead_id)
       or exists (select 1 from public.messages g
                  where g.inquiry_id = i.id and g.supplier_id = p_lead_id)
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'count', (select count(*) from rel),
    -- MATCHED TO ME, and nothing about the estate (review of #854: the same estate-wide count that was
    -- removed from fn_supplier_opportunities was still published here).
    'population', jsonb_build_object(
      'matches_for_me', (select count(*) from public.inquiry_matches where supplier_id = p_lead_id),
      'messaged_me', (select count(distinct inquiry_id) from public.messages where supplier_id = p_lead_id)
    ),
    'note', case when (select count(*) from rel) = 0
                 then 'no customer relationships yet — nothing has been matched or messaged'
                 else null end,
    'workspaces', (
      select coalesce(jsonb_agg(w order by w->>'last_activity' desc nulls last), '[]'::jsonb)
      from (
        select jsonb_build_object(
          'inquiry_id', i.id,
          'project', jsonb_build_object(
            -- THE TITLE IS A CUSTOMER'S OWN SENTENCE (22 Sep 2026, SP-N-05). It used to be i.summary,
            -- the raw column, printed at the top of the workspace before the reveal was paid for —
            -- the one place in the portal that read around the masking and the reveal gate at once.
            -- Post-reveal this supplier has paid for the customer's identity, so the unmasked summary
            -- is theirs to read; before it, the masked column through the inbox's seed scrub.
            'title', case when exists (select 1 from public.transactions t
                                        where t.inquiry_id = i.id and t.supplier_id = p_lead_id)
                          then coalesce(nullif(btrim(coalesce(i.summary, '')), ''), i.category,
                                        'RFQ ' || coalesce(i.rfq_no::text, i.id::text))
                          else coalesce(nullif(btrim(coalesce(public.fn_supplier_safe_text(i.id, i.summary_masked), '')), ''), i.category,
                                        'RFQ ' || coalesce(i.rfq_no::text, i.id::text)) end,
            'category', i.category,
            'emirate', i.emirate,
            'status', i.status,
            'created_at', i.created_at
          ),
          'files', (
            select coalesce(jsonb_agg(jsonb_build_object(
              'name', d.file_name, 'kind', d.kind, 'created_at', d.created_at,
              'category', case
                when d.kind ~* 'drawing|dwg|plan|layout'        then 'drawings'
                when d.kind ~* 'spec|datasheet|boq|schedule'    then 'specifications'
                when d.kind ~* 'contract|agreement|po|purchase' then 'contracts'
                else 'other' end
            ) order by d.created_at desc), '[]'::jsonb)
            from public.documents d
            where d.ref_table = 'inquiries' and d.ref_id = i.id::text
          ),
          'file_categories', (
            select jsonb_build_object(
              'drawings', count(*) filter (where d.kind ~* 'drawing|dwg|plan|layout'),
              'specifications', count(*) filter (where d.kind ~* 'spec|datasheet|boq|schedule'),
              'contracts', count(*) filter (where d.kind ~* 'contract|agreement|po|purchase'),
              'other', count(*) filter (where d.kind !~* 'drawing|dwg|plan|layout|spec|datasheet|boq|schedule|contract|agreement|po|purchase')
            )
            from public.documents d
            where d.ref_table = 'inquiries' and d.ref_id = i.id::text
          ),
          'message_count', (
            select count(*) from public.messages g
            where g.inquiry_id = i.id and g.supplier_id = p_lead_id and not coalesce(g.blocked, false)
          ),
          'unread', (
            select count(*) from public.messages g
            where g.inquiry_id = i.id and g.supplier_id = p_lead_id
              and g.sender = 'customer' and not coalesce(g.read_by_supplier, false)
              and not coalesce(g.blocked, false)
          ),
          'last_activity', (
            select max(g.created_at) from public.messages g
            where g.inquiry_id = i.id and g.supplier_id = p_lead_id
          ),
          'timeline', (
            select jsonb_build_object(
              'pct', case when total = 0 then null else round(100.0 * hit / total) end,
              'stages', jsonb_build_object(
                'matched', matched, 'messaged', messaged, 'quoted', quoted, 'awarded', awarded)
            )
            from (
              select 4 as total,
                (exists (select 1 from public.inquiry_matches m where m.inquiry_id = i.id and m.supplier_id = p_lead_id))::int
                  as matched,
                (exists (select 1 from public.messages g where g.inquiry_id = i.id and g.supplier_id = p_lead_id))::int
                  as messaged,
                (exists (select 1 from public.quotes q where q.inquiry_id = i.id and q.supplier_id = p_lead_id))::int
                  as quoted,
                (exists (select 1 from public.quotes q where q.inquiry_id = i.id and q.supplier_id = p_lead_id
                         and q.status = 'won'))::int as awarded
            ) s, lateral (select (s.matched + s.messaged + s.quoted + s.awarded) as hit) h
          )
        ) as w
        from rel r join public.inquiries i on i.id = r.inquiry_id
      ) t
    )
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_suppliers_board(p_search text DEFAULT ''::text, p_sector text DEFAULT ''::text, p_limit integer DEFAULT 60, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare out jsonb;
begin
  with base as (
    select l.id, l.company_name,
      coalesce(nullif(trim(l.sector),''),'general') as sector,
      coalesce(nullif(trim(l.emirate),''),'—') as emirate,
      l.app_rating as rating,
      l.verified, (l.approved_at is not null) as approved, l.banned,
      (l.invited_at is not null) as invited, l.claimed, (l.registration_submitted_at is not null) as registered,
      coalesce(l.capability_score,0) as capability_score, l.created_at,
      case when l.approved_at is not null then 'approved' when l.verified then 'verified'
           when l.registration_submitted_at is not null then 'registered' when l.invited_at is not null then 'invited'
           when l.contacted then 'contacted' else 'sourced' end as stage
    from leads l
    where (coalesce(p_search,'') = '' or l.company_name ilike '%'||p_search||'%' or l.sector ilike '%'||p_search||'%' or l.emirate ilike '%'||p_search||'%')
      and (coalesce(p_sector,'') = '' or l.sector = p_sector)
  ),
  ranked as (select *, row_number() over (partition by stage order by created_at desc, id desc) as rn from base),
  stagecounts as (select stage, count(*) as c from base group by stage)
  select jsonb_build_object(
    'total', (select count(*) from base),
    'stages', (
      select jsonb_agg(jsonb_build_object('key', s.key, 'label', s.label,
        'count', coalesce((select c from stagecounts sc where sc.stage=s.key),0),
        'cards', coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'company_name',r.company_name,'sector',r.sector,'emirate',r.emirate,'rating',r.rating,'verified',r.verified,'approved',r.approved,'banned',r.banned,'capability_score',r.capability_score) order by r.rn) from ranked r where r.stage=s.key and r.rn<=12),'[]'::jsonb))
        order by s.ord)
      from (values ('sourced','Sourced',1),('contacted','Contacted',2),('invited','Invited',3),('registered','Registered',4),('verified','Verified',5),('approved','Approved',6)) s(key,label,ord)
    ),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'company_name',b.company_name,'sector',b.sector,'emirate',b.emirate,'rating',b.rating,'verified',b.verified,'approved',b.approved,'banned',b.banned,'invited',b.invited,'registered',b.registered,'stage',b.stage,'capability_score',b.capability_score,'created_at',b.created_at) order by b.created_at desc, b.id desc),'[]'::jsonb)
             from (select * from base order by created_at desc, id desc limit greatest(1,least(p_limit,200)) offset greatest(0,p_offset)) b),
    'sectors', (select coalesce(jsonb_agg(jsonb_build_object('label',x.sector,'n',x.n) order by x.n desc),'[]'::jsonb) from (select sector, count(*) n from base group by sector order by count(*) desc limit 12) x)
  ) into out;
  return out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_anonymity_scan(p_text text, p_subject text, p_attachment_ref text, p_supplier_lead_id bigint, p_quote_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  s record; v_hay text; v_hits text[] := '{}'; v_digits text;
begin
  v_hay := lower(coalesce(p_text,'') || ' ' || coalesce(p_subject,'') || ' ' || coalesce(p_attachment_ref,''));

  select company_name, email, phone, trade_license_no into s from public.leads where id = p_supplier_lead_id;
  if not found then
    return jsonb_build_object('safe', false, 'reason',
      'the supplier row could not be read, so nothing about it could be checked for', 'hits', '[]'::jsonb);
  end if;

  if coalesce(btrim(s.company_name),'') <> '' and position(lower(btrim(s.company_name)) in v_hay) > 0
    then v_hits := array_append(v_hits, 'company_name'); end if;
  if coalesce(btrim(s.email),'') <> '' and position(lower(btrim(s.email)) in v_hay) > 0
    then v_hits := array_append(v_hits, 'email'); end if;
  v_digits := regexp_replace(coalesce(s.phone,''), '[^0-9]', '', 'g');
  if length(v_digits) >= 7 and position(v_digits in regexp_replace(v_hay, '[^0-9]', '', 'g')) > 0
    then v_hits := array_append(v_hits, 'phone'); end if;
  if coalesce(btrim(s.trade_license_no),'') <> '' and position(lower(btrim(s.trade_license_no)) in v_hay) > 0
    then v_hits := array_append(v_hits, 'trade_license_no'); end if;

  if p_quote_id is not null then
    if exists (select 1 from public.quotes q
                where q.id::text = p_quote_id and q.quote_amount is not null
                  and position(regexp_replace(round(q.quote_amount)::text, '[^0-9]', '', 'g')
                               in regexp_replace(v_hay, '[^0-9]', '', 'g')) > 0)
      then v_hits := array_append(v_hits, 'quoted_amount'); end if;
  end if;

  return jsonb_build_object(
    'safe', array_length(v_hits, 1) is null,
    'hits', to_jsonb(v_hits),
    'checked', jsonb_build_array('company_name','email','phone','trade_license_no','quoted_amount'),
    'scanned_at', now(),
    'note', case when array_length(v_hits,1) is null
                 then 'No supplier-identifying or commercial value from the live row appears in the subject, body or attachment name.'
                 else 'REFUSED: the message contains ' || array_to_string(v_hits, ', ') || ' from the live supplier row.' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_answer_identity_challenge(p_sender_ref text, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare ch record; v_filed int := 0;
begin
  select * into ch from public.support_identity_challenge
   where sender_ref = p_sender_ref and consumed_at is null
   order by created_at desc limit 1 for update;

  if not found then
    return jsonb_build_object('ok', false, 'verified', false, 'reason', 'no_open_challenge',
      'message', 'I do not have a code outstanding for you. Send me the email address you registered with and I will start again.');
  end if;

  if ch.expires_at <= now() then
    update public.support_identity_challenge
       set consumed_at = now(), outcome = 'expired' where challenge_id = ch.challenge_id;
    return jsonb_build_object('ok', true, 'verified', false, 'reason', 'expired',
      'message', 'That code has expired. Send me the email address again and I will issue a fresh one.');
  end if;

  if ch.attempts >= 4 then
    update public.support_identity_challenge
       set attempts = ch.attempts + 1, consumed_at = now(), outcome = 'exhausted'
     where challenge_id = ch.challenge_id;
    return jsonb_build_object('ok', true, 'verified', false, 'reason', 'exhausted',
      'message', 'Too many attempts on that code, so I have cancelled it. Send me the email address again for a new one.');
  end if;

  if encode(sha256(convert_to(btrim(p_code) || '|' || ch.lead_id::text, 'UTF8')), 'hex') <> ch.code_hash then
    update public.support_identity_challenge
       set attempts = ch.attempts + 1 where challenge_id = ch.challenge_id;
    return jsonb_build_object('ok', true, 'verified', false, 'reason', 'wrong_code',
      'attempts_left', 4 - ch.attempts,
      'message', 'That code does not match. Please check the email and try again.');
  end if;

  update public.support_identity_challenge
     set consumed_at = now(), outcome = 'verified' where challenge_id = ch.challenge_id;

  -- NOTE ON THE ORDERING BELOW: received_at alone is not a tie-break. Two documents that arrive in
  -- the SAME transaction carry the same now(), so "the latest licence" was decided by whichever row
  -- the planner returned first. The intake_id settles it, and the probe that caught this is the
  -- reason the tie-break is here rather than a comment saying it cannot happen.
  -- NOW the held documents may be filed -- and only the ones this sender actually sent, on this
  -- channel. Verifying an identity does not adopt every orphan document in the table.
  update public.support_document_intake i
     set lead_id = ch.lead_id, attached = classified_as <> 'unknown',
         attach_note = case when classified_as = 'unknown'
           then 'Owner confirmed by identity challenge; type still unknown, so still held.'
           else format('Attached as %s to lead %s after identity challenge %s.', classified_as, ch.lead_id, ch.challenge_id) end
   where i.sender_ref = p_sender_ref and i.lead_id is null;
  get diagnostics v_filed = row_count;

  update public.leads l set
    license_doc_path = coalesce((select storage_path from public.support_document_intake
      where lead_id = ch.lead_id and classified_as = 'licence' order by received_at desc, intake_id desc limit 1), l.license_doc_path),
    company_profile_doc_path = coalesce((select storage_path from public.support_document_intake
      where lead_id = ch.lead_id and classified_as = 'profile' order by received_at desc, intake_id desc limit 1), l.company_profile_doc_path),
    signed_terms_path = coalesce((select storage_path from public.support_document_intake
      where lead_id = ch.lead_id and classified_as = 'signed_terms' order by received_at desc, intake_id desc limit 1), l.signed_terms_path)
  where l.id = ch.lead_id;

  -- The same rule at the other door: the owner was unknown when the document arrived, so the chase
  -- could not be stopped then. It is stopped now, at the moment the account is proven.
  perform public.fn_licence_ask_close_for_lead(ch.lead_id, 'identity_challenge', null);

  return jsonb_build_object('ok', true, 'verified', true, 'lead_id', ch.lead_id,
    'documents_released', v_filed,
    'mandatory', public.fn_supplier_mandatory_check(ch.lead_id),
    'message', 'Confirmed, thank you. I have filed the document you sent against your account.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_artifact_attachable(p_artifact_id bigint, p_for_party_id text, p_max_bytes bigint DEFAULT 15000000)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a record;
begin
  select * into a from public.support_artifact where artifact_id = p_artifact_id;
  if not found then
    return jsonb_build_object('attachable', false, 'reason', 'unavailable',
      'note', 'no such artifact. Send the portal route and open a repair; do not describe a file that does not exist.');
  end if;
  if a.obsolete_at is not null then
    return jsonb_build_object('attachable', false, 'reason', 'obsolete',
      'note', 'this export was superseded. Attaching it would deliver an answer the company has already replaced.');
  end if;
  if a.privacy_state <> 'approved' then
    return jsonb_build_object('attachable', false, 'reason', 'unsafe',
      'note', format('privacy_state is %L. Only an artifact whose check RAN and passed may be attached.', a.privacy_state));
  end if;
  -- PER-PARTY ENTITLEMENT. "A payment for one supplier never reveals all suppliers; use
  -- per-customer, per-inquiry, per-supplier entitlements."
  if a.owner_party_id is not null and p_for_party_id is not null and a.owner_party_id <> p_for_party_id then
    return jsonb_build_object('attachable', false, 'reason', 'not_entitled',
      'note', 'this artifact belongs to a different party. Ownership is checked per artifact, not per payment.');
  end if;
  if a.byte_size is not null and a.byte_size > p_max_bytes then
    return jsonb_build_object('attachable', false, 'reason', 'oversized',
      'note', format('%s bytes exceeds the channel limit of %s. A link is the honest fallback and must be described as one.', a.byte_size, p_max_bytes));
  end if;
  return jsonb_build_object('attachable', true, 'checksum', a.checksum, 'version', a.version,
    'storage_path', a.storage_path,
    'note', 'Attachable. The message may say "attached" only because a file is genuinely going with it.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_case_classify(p_case_id bigint, p_source text, p_value text, p_tags text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_cat text;
begin
  if p_case_id is null then return; end if;
  select category into v_cat from public.support_signal_category where source = p_source and value = p_value;
  update public.support_case c
     set category = coalesce(c.category, v_cat),
         topic_tags = (select coalesce(array_agg(distinct t order by t), '{}')
                         from unnest(c.topic_tags || coalesce(p_tags, '{}')) t where coalesce(btrim(t), '') <> '')
   where c.case_id = p_case_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_case_close(p_ref text, p_reason text, p_by text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_case public.support_case; v_h public.agent_actions;
begin
  update public.support_case
     set state = 'closed', closed_at = now(), last_activity_at = now(),
         close_reason = left(coalesce(nullif(btrim(p_reason), ''), 'resolved') || ' (closed by ' || coalesce(nullif(btrim(p_by), ''), 'customer_support') || ')', 1000)
   where case_ref = upper(btrim(p_ref)) and state <> 'closed'
  returning * into v_case;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no open case ' || coalesce(p_ref, '')); end if;
  select * into v_h from public.agent_actions where kind = 'handoff' and target_id = 'support.case_open:' || v_case.case_id limit 1;
  return jsonb_build_object('ok', true, 'case_ref', v_case.case_ref, 'close_reason', coalesce(nullif(btrim(p_reason), ''), 'resolved'),
                            'phone_digits', v_h.detail ->> 'phone_digits', 'lang', coalesce(v_h.detail ->> 'lang', 'en'),
                            'handoff_status', (select status from public.agent_actions where id = v_h.id));
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_case_closed_asks_for_the_rating()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_p public.support_customer_profile; v_lang text := coalesce(new.lang, 'en'); v_body text; v_err text; v_phone text;
begin
  if new.state <> 'closed' or old.state = 'closed' or new.csat_requested_at is not null then return null; end if;
  if exists (select 1 from public.feedback f where f.case_id = new.case_id and f.kind = 'csat') then return null; end if;
  select * into v_p from public.support_customer_profile where id = new.customer_profile_id;
  v_body := case when v_lang = 'ar'
    then 'كيف كانت خدمتنا في البلاغ ' || new.case_ref || E'؟\nأرسلوا رقمًا من ١ (غير راضٍ) إلى ٥ (راضٍ جدًا)، '
         || 'ويمكنكم إضافة رقم ثانٍ من ١ (صعب جدًا) إلى ٧ (سهل جدًا) لمدى سهولة حل المشكلة. مثال: ٥ ٧'
    else 'How did we do on case ' || new.case_ref || E'?\nReply with a number from 1 (unhappy) to 5 (very happy). '
         || 'You can add a second number from 1 (very hard) to 7 (very easy) for how easy it was to get it solved, e.g. "5 7".' end;
  if new.last_channel = 'whatsapp' then
    v_phone := coalesce(case when new.party_id ~ '^\+?[0-9]{9,}$' then new.party_id end,
                        (select coalesce(c.whatsapp_phone, c.phone) from public.customers c where c.id = v_p.customer_id),
                        (select coalesce(l.whatsapp_phone, l.phone_e164, l.phone) from public.leads l where l.id = v_p.lead_id));
  end if;
  begin
    if v_phone is not null then
      insert into public.notifications (type, kind, to_phone, to_role, channel, lang, subject, body, requested_by, sender)
      values ('support_csat_request', 'support_csat_request', v_phone, new.party_kind, 'whatsapp', v_lang, 'Case ' || new.case_ref || ' rating', v_body, 'customer_support', 'customer_support');
    elsif v_p.email is not null then
      insert into public.notifications (type, kind, to_email, to_role, channel, lang, subject, body, requested_by, sender)
      values ('support_csat_request', 'support_csat_request', v_p.email, new.party_kind, 'email', v_lang,
              case when v_lang = 'ar' then 'قيّموا خدمتنا في البلاغ ' || new.case_ref else 'How did we do? Case ' || new.case_ref end,
              v_body, 'customer_support', 'customer_support');
    else
      v_err := 'no channel to ask on';
    end if;
  exception when others then
    v_err := left(sqlerrm, 500);   -- a refused notice never undoes the close
  end;
  update public.support_case set csat_requested_at = case when v_err is null then now() end, csat_request_error = v_err
   where case_id = new.case_id;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_case_closed_tells_the_reporter()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_h public.agent_actions; v_email text; v_lang text; v_notif bigint;
begin
  if new.state <> 'closed' or old.state = 'closed' then return null; end if;
  select * into v_h from public.agent_actions where kind = 'handoff' and target_id = 'support.case_open:' || new.case_id limit 1;
  v_lang := coalesce(v_h.detail ->> 'lang', 'en');
  if new.party_kind = 'customer' then
    select c.email into v_email from public.customers c where c.id::text = new.party_id;
  elsif new.party_kind = 'supplier' then
    select l.email into v_email from public.leads l where l.id::text = new.party_id;
  end if;
  if v_email ~ '@' then
   begin   -- a refused notice (a guard on notifications) must never undo the close itself
    insert into public.notifications (type, kind, to_email, to_role, channel, lang, subject, body, requested_by, sender)
    values ('support_case_closed', 'support_case_closed', v_email, new.party_kind, 'email', v_lang,
            case when v_lang = 'ar' then 'إغلاق البلاغ رقم ' || new.case_ref else 'Your case ' || new.case_ref || ' is closed' end,
            case when v_lang = 'ar'
                 then 'نفيدكم بإغلاق البلاغ رقم ' || new.case_ref || '، وملخص المعالجة: ' || new.close_reason
                      || E'.\nإن لم تُحلّ المشكلة فتفضلوا بالرد على هذه الرسالة وسنعيد فتحه.'
                 else 'Your case ' || new.case_ref || ' is now closed: ' || new.close_reason
                      || E'.\nIf the problem is not solved, just reply to this message and we will reopen it.' end,
            'customer_support', 'customer_support')
    returning id into v_notif;
   exception when others then
    raise warning 'fn_support_case_closed_tells_the_reporter: the email for % was refused: %', new.case_ref, sqlerrm;
   end;
  end if;
  if v_h.id is not null and v_h.status <> 'done' then
    perform public.fn_seat_handoff_complete(v_h.id, jsonb_build_object(
      'closed_at', new.closed_at, 'close_reason', new.close_reason,
      'reporter_email_notification', v_notif, 'reporter_phone_digits', v_h.detail ->> 'phone_digits'));
  end if;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_case_idle_close()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';   -- fixture run: ONLY demo cases
  v_days int := greatest(1, public.fn_seat_clock_policy('support_case_append_days', 7)::int); n int;
begin
  update public.support_case
     set state = 'closed', closed_at = now(),
         close_reason = 'resolved — answered, and no reply from the customer in ' || v_days || ' days (closed by customer_support)'
   where state = 'waiting_customer' and last_activity_at < now() - make_interval(days => v_days)
     and category is distinct from 'automated_decision_objection'   -- legal finding 1: closed only by a reply
     and public.fn_party_is_demo(party_kind, party_id) = v_fx;       -- a fixture run can never close a real case
  get diagnostics n = row_count;
  return jsonb_build_object('closed', n);
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_case_kind_category()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.category is null then
    select category into new.category from public.support_signal_category where source = 'case_kind' and value = new.case_kind;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_case_lifecycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if tg_op = 'INSERT' then
    if new.customer_profile_id is null then
      new.customer_profile_id := public.fn_support_profile_resolve(new.party_kind, new.party_id,
        case when new.party_id ~ '@' then new.party_id end,
        case when new.party_id ~ '^\+?[0-9]{9,}$' then new.party_id end);
    end if;
    if new.channel is null and new.subject ilike 'WhatsApp%' then new.channel := 'whatsapp'; end if;
    if new.channel is not null then
      new.last_channel := coalesce(new.last_channel, new.channel);
      if not new.channel = any(new.channels) then new.channels := new.channels || new.channel; end if;
    end if;
    return new;
  end if;
  if new.state = 'closed' and old.state <> 'closed' then
    new.resolved_at := coalesce(new.closed_at, now());
    new.resolution  := coalesce(new.resolution, new.close_reason);
  elsif old.state = 'closed' and new.state <> 'closed' then
    new.reopen_count := old.reopen_count + 1;
    new.reopened_at  := now();
    new.closed_at := null; new.close_reason := null; new.resolved_at := null; new.resolution := null;
    new.csat_requested_at := null; new.csat_request_error := null;
    new.last_activity_at := now();
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_case_new_ref()
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';   -- the QD-S- alphabet fn_wa_problem_report uses
  v_bytes bytea := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
  v_ref text := 'QD-S-'; i int;
begin
  for i in 0..5 loop v_ref := v_ref || substr(alphabet, (get_byte(v_bytes, i) % 32) + 1, 1); end loop;
  return v_ref;
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_classify_email()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_prof bigint; v_from text := lower(substring(coalesce(new.from_email, '') from '([^<>\s"]+@[^<>\s"]+)'));
begin
  if new.triaged_at is null or old.triaged_at is not null or coalesce(new.ai_category, '') = '' then return null; end if;
  begin
    select id into v_prof from public.support_customer_profile where email = v_from order by last_seen_at desc limit 1;
    if v_prof is null then return null; end if;
    perform public.fn_support_case_classify(public.fn_support_open_case_of(v_prof), 'email_category', new.ai_category,
                                            array['email:' || new.ai_category]);
  exception when others then
    raise warning 'fn_support_classify_email: inbound_messages % not classified: %', new.id, sqlerrm;
  end;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_classify_whatsapp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_prof bigint; v_tags text[] := '{}';
begin
  if coalesce(btrim(new.inbound), '') = '' or jsonb_typeof(new.meta) is distinct from 'object' then return null; end if;
  begin
    select id into v_prof from public.support_customer_profile
     where phone_tail = right(regexp_replace(coalesce(new.wa_from, ''), '[^0-9]', '', 'g'), 9) order by last_seen_at desc limit 1;
    if v_prof is null then return null; end if;
    if jsonb_typeof(new.meta->'topics') = 'array' then
      v_tags := v_tags || array(select 'topic:' || t from jsonb_array_elements_text(new.meta->'topics') t);
    end if;
    if jsonb_typeof(new.meta->'matched_faq_ids') = 'array' then
      v_tags := v_tags || array(select 'faq:' || f.section from public.company_faq f
                                 where f.id::text in (select jsonb_array_elements_text(new.meta->'matched_faq_ids')));
    end if;
    if new.meta->>'unanswered_reason' is not null then v_tags := v_tags || 'unanswered'::text; end if;
    perform public.fn_support_case_classify(public.fn_support_open_case_of(v_prof), 'wa_choice', new.meta->>'choice', v_tags);
    if new.meta->>'unanswered_reason' is not null then
      update public.support_case set category = coalesce(category, 'knowledge_gap') where case_id = public.fn_support_open_case_of(v_prof);
    end if;
  exception when others then
    raise warning 'fn_support_classify_whatsapp: wa_messages % not classified: %', new.id, sqlerrm;
  end;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_classify_widget()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_prof bigint; v_kind text := split_part(coalesce(new.audience, ''), ':', 1); v_id text := split_part(coalesce(new.audience, ''), ':', 2);
        v_tags text[] := '{}';
begin
  begin
    if v_kind = 'customer' and v_id ~ '^[0-9a-f-]{36}$' then
      select id into v_prof from public.support_customer_profile where customer_id = v_id::uuid;
    elsif v_kind = 'supplier' and v_id ~ '^[0-9]+$' then
      select id into v_prof from public.support_customer_profile where lead_id = v_id::bigint;
    end if;
    if v_prof is null then return null; end if;
    if new.matched_ids is not null then
      v_tags := v_tags || array(select 'faq:' || f.section from public.company_faq f
                                 where f.id::text = any (string_to_array(regexp_replace(new.matched_ids::text, '[{}\[\]" ]', '', 'g'), ',')));
    end if;
    if new.answered = false then v_tags := v_tags || 'unanswered'::text; end if;
    perform public.fn_support_case_classify(public.fn_support_open_case_of(v_prof), 'faq_section', null, v_tags);
    if new.answered = false then
      update public.support_case set category = coalesce(category, 'knowledge_gap') where case_id = public.fn_support_open_case_of(v_prof);
    elsif v_tags <> '{}' then
      update public.support_case set category = coalesce(category, 'general_question') where case_id = public.fn_support_open_case_of(v_prof);
    end if;
  exception when others then
    raise warning 'fn_support_classify_widget: assistant_logs % not classified: %', new.id, sqlerrm;
  end;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_context(p_query text, p_max_chars integer DEFAULT 12000, p_limit integer DEFAULT 5, p_embedding vector DEFAULT NULL::vector)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r record; v_out jsonb := '[]'::jsonb; v_used int := 0; v_n int := 0; v_how text;
begin
  for r in select * from public.fn_support_knowledge_search(p_query, p_limit, p_embedding => p_embedding) loop
    exit when v_used + length(r.body) > greatest(1500, p_max_chars);
    v_how := coalesce(v_how, r.matched_how);
    v_out := v_out || jsonb_build_object(
      'record_id', r.record_id, 'record_kind', r.record_kind, 'title', r.title,
      'body', r.body, 'source_ids', to_jsonb(r.source_ids), 'review_status', r.review_status,
      'relevance', r.relevance, 'matched_how', r.matched_how, 'warning', r.warning);
    v_used := v_used + length(r.body); v_n := v_n + 1;
  end loop;

  return jsonb_build_object(
    -- THE COMPANY BLOCK. Pinned, never retrieved and never rankable: it is here on every answer,
    -- including the refusals, because a seat with no retrieval hit is exactly the seat most likely
    -- to improvise a fee or a policy. Founder ruling, 9 Sep 2026.
    'company', public.fn_company_context(),
    
    'query', p_query,
    -- PINNED EVERY TIME, never retrieved and never rankable. These are the rules that must hold
    -- when the retrieval finds nothing, which is exactly when an agent is most tempted to improvise.
    'invariants', jsonb_build_array(
      'Never say you checked, sent, escalated, fixed, refunded or approved anything without tool evidence for it.',
      'A tool error means "cannot verify right now". It never means "no inquiry", "unpaid" or "no discount".',
      'Never reveal a supplier name, contact, logo, amount or quotation content in a notification. The quotation stays in the portal, including after a reveal payment.',
      'Never invent a fee, discount, promotion, policy, deadline or guaranteed outcome.',
      'A supplied email, number or reference is a search clue, never proof of account ownership.',
      'Never request a password, full card number or a banking OTP.',
      'Identify as QuotesDone Support. Never impersonate a person and never claim to be human.',
      'Escalation goes to the CEO. Never to the founder, and never to an invented department.'),
    'advisory_records', v_out,
    'record_count', v_n,
    'matched_how', v_how,
    'sufficient', v_n > 0,
    -- The caller fills this from the database. It is named rather than left implicit so that a
    -- caller who forgets it produces an obviously empty slot instead of a confident general answer.
    'account_facts', null,
    'account_facts_note', 'The CALLER must fill account_facts from authorised live data. Advisory records never contain this customer''s facts.',
    'signal', case when v_n = 0
                   then case when p_embedding is null then 'NO EMBEDDING was passed, so nothing was retrieved: this pack is read by meaning only. Answer from company policy and live account facts; do not improvise.'
                             else 'NO ADVISORY COVERAGE for this query. Answer from company policy and live account facts; do not improvise from these records.' end
                   else 'Advisory guidance only. Account facts come from the database.' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_corpus_search(p_query text, p_public boolean, p_limit integer DEFAULT 8)
 RETURNS TABLE(src text, src_id text, title text, content text, citation text, rank real)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.fn_support_deliver_artifact(p_artifact_id bigint, p_case_id bigint, p_recipient_party_id text, p_whatsapp text, p_email text, p_inquiry_ref text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  a record; e jsonb; v_portal text; v_body text; v_subject text; v_attach text;
  v_out jsonb := '[]'::jsonb; v_dedupe text; v_id bigint; v_grant jsonb;
begin
  v_grant := public.fn_support_may_act('notification');
  if (v_grant->>'may_act') <> 'true' then
    return jsonb_build_object('ok', false, 'reason', v_grant->>'reason');
  end if;

  select * into a from public.support_artifact where artifact_id = p_artifact_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such artifact'); end if;

  e := public.fn_support_artifact_attachable(p_artifact_id, p_recipient_party_id);
  v_portal := coalesce((select value from public.app_secrets where key = 'public_site_url'), 'https://quotesdone.com') || '/portal';

  if (e->>'attachable') = 'true' then
    v_attach := a.storage_path;
    v_body := case a.artifact_kind
      when 'comparison_report' then
        'Your comparison report for inquiry ' || p_inquiry_ref || ' is ready. A copy is attached, and you can view it in your portal: '
        || v_portal || '. Individual quotations are available in the portal.'
      else
        'Your reveal-fee payment for inquiry ' || p_inquiry_ref || ' has been confirmed. Your invoice ' || coalesce(a.subject_ref,'')
        || ' is attached. You can also access it in your portal: ' || v_portal || '.' end;
  else
    -- THE WORDING CHANGES BECAUSE THE FACT CHANGED. Not a softened version of the same sentence: the
    -- word "attached" is absent, the reason is stated, and the message says where the file is.
    v_attach := null;
    v_body := case a.artifact_kind
      when 'comparison_report' then
        'Your comparison report for inquiry ' || p_inquiry_ref || ' is ready. I could not include a copy with this message ('
        || (e->>'reason') || '), so please open it in your portal: ' || v_portal || '.'
      else
        'Your reveal-fee payment for inquiry ' || p_inquiry_ref || ' has been confirmed. I could not include the invoice with this message ('
        || (e->>'reason') || '), so please open it in your portal: ' || v_portal || '.' end;
  end if;
  v_subject := case a.artifact_kind when 'comparison_report'
                 then 'Your comparison report for inquiry ' || p_inquiry_ref
                 else 'Your invoice for inquiry ' || p_inquiry_ref end;

  -- THE DEDUPE KEY IS THE ARTIFACT PLUS ITS CHECKSUM. A re-send of the same file to the same person
  -- is silently absorbed; a REGENERATED file has a different checksum and is therefore a different
  -- delivery rather than a duplicate.
  if coalesce(btrim(p_whatsapp),'') <> '' then
    insert into public.support_notification (dedupe_key, case_id, purpose, channel, recipient,
      inquiry_ref, publication_version, subject, body, attachment_ref, anonymity_checked_at, anonymity_result)
    values ('artifact|' || p_artifact_id::text || '|' || coalesce(a.checksum,'nocs') || '|whatsapp|' || p_whatsapp,
            p_case_id, a.artifact_kind, 'whatsapp', p_whatsapp, p_inquiry_ref, a.version,
            null, v_body, v_attach, now(),
            jsonb_build_object('safe', true, 'note', 'deterministic artifact delivery; the artifact itself carries its own privacy result', 'artifact_privacy', a.privacy_result))
    on conflict (dedupe_key) do nothing returning id into v_id;
    v_out := v_out || jsonb_build_object('channel','whatsapp','queued', v_id is not null, 'attached', v_attach is not null);
  end if;

  if coalesce(btrim(p_email),'') <> '' then
    insert into public.support_notification (dedupe_key, case_id, purpose, channel, recipient,
      inquiry_ref, publication_version, subject, body, attachment_ref, anonymity_checked_at, anonymity_result)
    values ('artifact|' || p_artifact_id::text || '|' || coalesce(a.checksum,'nocs') || '|email|' || p_email,
            p_case_id, a.artifact_kind, 'email', p_email, p_inquiry_ref, a.version,
            v_subject, v_body, v_attach, now(),
            jsonb_build_object('safe', true, 'note', 'deterministic artifact delivery; the artifact itself carries its own privacy result', 'artifact_privacy', a.privacy_result))
    on conflict (dedupe_key) do nothing returning id into v_id;
    v_out := v_out || jsonb_build_object('channel','email','queued', v_id is not null, 'attached', v_attach is not null);
  end if;

  return jsonb_build_object(
    'ok', true, 'artifact_id', p_artifact_id, 'attachable', e->>'attachable',
    'refusal_reason', e->>'reason', 'queued', v_out,
    -- THE COUNT THE SPEC ASKS FOR. "Do not count a portal link as a delivered attachment."
    'file_copy_delivered', (e->>'attachable') = 'true',
    'note', case when (e->>'attachable') = 'true'
                 then 'A copy is attached and the message says so because it is true.'
                 else 'NOT a file-copy delivery. A link was sent instead, the reason was stated to the customer, and this must not be counted as an attachment.' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_email_is_a_customer_contact(p_from text, p_to text, p_owner_role text, p_subject text, p_fixtures boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(p_from, '') !~* '^[^@]*(mailer-daemon|postmaster|no-?reply|do-?not-?reply|bounces?)[^@]*@'
     and coalesce(p_to, '') !~* '^(expenses@|calendar\+|approve\+)'
     and coalesce(p_owner_role, '') <> 'accountant'
     and lower(btrim(coalesce(p_from, ''))) <> all (
           select lower(btrim(e)) from public.app_secrets s, unnest(string_to_array(s.value, ',')) e
            where s.key in ('admin_emails', 'founder_email') and btrim(e) <> '')
     and (public.fn_is_demo_email(p_from) or coalesce(p_subject, '') like 'ZZ DEMO%') = p_fixtures
$function$


CREATE OR REPLACE FUNCTION public.fn_support_faq_records_its_root_cause()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t text;
begin
  for t in select x from unnest(coalesce(new.tags, '{}')) x where x ~ '^root_cause:[0-9]+$' loop
    begin
      perform public.fn_support_root_cause_fix(substring(t from 12)::bigint, 'faq', 'company_faq', new.id::text, 'FAQ tagged ' || t);
    exception when others then
      raise warning 'company_faq % names % but the fix was not recorded: %', new.id, t, sqlerrm;
    end;
  end loop;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_feedback_record(p_case_ref text, p_csat numeric, p_ces numeric DEFAULT NULL::numeric, p_comment text DEFAULT NULL::text, p_channel text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_case public.support_case; n int := 0;
begin
  select * into v_case from public.support_case where case_ref = upper(btrim(p_case_ref));
  if not found then return jsonb_build_object('ok', false, 'reason', 'no case ' || coalesce(p_case_ref, '')); end if;
  if p_csat is not null then
    insert into public.feedback (source, subject_type, subject_id, rating, comment, case_id, kind, channel, profile_id)
    values ('support_case', 'support_case', v_case.case_ref, p_csat, left(p_comment, 2000), v_case.case_id, 'csat',
            coalesce(p_channel, v_case.last_channel), v_case.customer_profile_id)
    on conflict (case_id, kind) where case_id is not null and kind is not null do nothing;
    get diagnostics n = row_count;
  end if;
  if p_ces is not null then
    insert into public.feedback (source, subject_type, subject_id, rating, case_id, kind, channel, profile_id)
    values ('support_case', 'support_case', v_case.case_ref, p_ces, v_case.case_id, 'ces',
            coalesce(p_channel, v_case.last_channel), v_case.customer_profile_id)
    on conflict (case_id, kind) where case_id is not null and kind is not null do nothing;
  end if;
  return jsonb_build_object('ok', true, 'case_ref', v_case.case_ref, 'csat_recorded', n = 1);
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_investigate_refund(p_transaction_id uuid, p_reason text, p_case_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t record; v_grant jsonb; v_id bigint; v_elig text; v_why text; v_prior int;
begin
  v_grant := public.fn_support_may_act('refund');
  if (v_grant->>'may_act') <> 'true' then
    return jsonb_build_object('ok', false, 'reason', v_grant->>'reason', 'route', v_grant->>'route');
  end if;

  select id, quote_amount, reveal_fee, total_charged, fee_status, refund_status, refund_amount_aed
    into t from public.transactions where id = p_transaction_id;
  if not found then
    -- "A tool error means cannot verify now, not no inquiry." A missing transaction is a real answer;
    -- it is reported as one and not as an ineligibility.
    return jsonb_build_object('ok', false, 'reason',
      'no such transaction. This is not an eligibility finding -- nothing was assessed.');
  end if;

  -- AGGREGATE OVER-REFUNDING. Everything already refunded on this transaction, counted before
  -- anything new is proposed.
  select count(*) into v_prior from public.refund_case
   where transaction_id = p_transaction_id and state in ('succeeded','reconciled','communicated');

  if coalesce(t.fee_status,'') not in ('paid','collected','succeeded') then
    v_elig := 'ineligible';
    v_why := format('the reveal fee is %L, so nothing has settled. There is no payment to refund; this is a settlement question, not a refund one.', coalesce(t.fee_status,'(none)'));
  elsif v_prior > 0 then
    v_elig := 'ineligible';
    v_why := format('%s refund(s) already succeeded on this transaction. A second would be an aggregate over-refund.', v_prior);
  else
    v_elig := 'eligible';
    v_why := 'the reveal fee settled and no prior refund has succeeded on this transaction.';
  end if;

  insert into public.refund_case
    (transaction_id, case_id, state, amount_aed, requested_reason, investigated_at,
     evidence, eligibility, eligibility_reason)
  values
    (p_transaction_id, p_case_id,
     case when v_elig = 'eligible' then 'eligible' else 'ineligible' end,
     coalesce(t.total_charged, t.reveal_fee, 0), p_reason, now(),
     jsonb_build_object('fee_status', t.fee_status, 'reveal_fee', t.reveal_fee,
                        'prior_successful_refunds', v_prior, 'read_at', now()),
     v_elig, v_why)
  on conflict do nothing
  returning refund_id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'duplicate', true, 'reason',
      'a live refund already exists on this transaction. Concurrent remedies are prevented by index, not by hoping.');
  end if;

  return jsonb_build_object('ok', true, 'refund_id', v_id, 'eligibility', v_elig, 'why', v_why,
    'next', case when v_elig = 'eligible'
                 then 'Put it to the CEO. Support investigated; it does not decide.'
                 else 'No decision is needed: the investigation found it ineligible, with the reason recorded.' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_knowledge_gap(p_question text, p_refusal text, p_surface text DEFAULT 'website_widget'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_norm text;
  v_gap  public.sales_knowledge_gap%rowtype;
  v_task bigint;
  v_asks int := 0;
  -- TEST TRAFFIC FILES NOTHING (27 Oct 2026): a request carrying a sandbox run tag, or a ZZ DEMO question. The caller
  -- still gets ok and its reply text, with no task number, so its own reply path does not change.
  v_test boolean := public.fn_e2e_run_tag_current() is not null or public.fn_seat_work_is_demo(p_question, null);
begin
  if coalesce(btrim(p_question), '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'empty_question');
  end if;

  -- THE QUESTION ARRIVED WITH ITS SCRIPT STRIPPED, so there is nothing here to answer and
  -- nothing to file. org_tasks 578945 is what happens without this branch: a task that sat in
  -- the work queue for nine days titled in question marks, asked four times, with no reading of
  -- it possible by anyone.
  --
  -- BOTH KEYS CARRY BOTH LANGUAGES. site_assistant picks between reply_en and reply_ar with
  -- `/[؀-ۿ]/.test(message) || uiLang === 'ar'` — it reads the script of the message, and on this
  -- branch the script is exactly what was destroyed, so a stripped Arabic message is pure ASCII
  -- and that test says "English" for the one visitor who needs the Arabic. The language cannot be
  -- known here, so it is not guessed: whichever key the caller reads, the person gets both
  -- paragraphs. This is the fix for the defect the comment above would otherwise only describe.
  if public.fn_text_lost_its_script(p_question) then
    return jsonb_build_object(
      'ok', false, 'reason', 'text_lost_its_script',
      'reply_en', public.fn_text_did_not_survive_reply('en') || E'\n\n'
                  || public.fn_text_did_not_survive_reply('ar'),
      'reply_ar', public.fn_text_did_not_survive_reply('ar') || E'\n\n'
                  || public.fn_text_did_not_survive_reply('en'));
  end if;

  if not v_test then
    v_norm := left(lower(regexp_replace(btrim(p_question), '\s+', ' ', 'g')), 400);
    select * into v_gap from public.sales_knowledge_gap where question_norm = v_norm;

    if not found then
      insert into public.org_tasks (title, detail, status, tier, action_class, assigned_agent,
                                    priority, requires_evidence, needs_founder)
      values (
        left('Answer an unanswered support question: ' || btrim(p_question), 160),
        'Someone who was NOT signed in asked this on the ' || coalesce(nullif(btrim(p_surface), ''), 'website_widget')
          || ' and Customer Support could not source an answer from company knowledge.' || E'\n\n'
          || 'QUESTION: ' || btrim(p_question) || E'\n'
          || 'REFUSAL: ' || coalesce(nullif(btrim(p_refusal), ''), 'no_grounded_answer') || E'\n\n'
          || 'THERE IS NO ESCALATION TO A HUMAN -- founder ruling, 9 Sep 2026. This task IS what '
          || 'happens instead, and it is the only thing that happens.' || E'\n\n'
          || 'DONE MEANS: the answer exists in a corpus fn_support_corpus_search reads (company_faq, '
          || 'support_knowledge, ops_knowledge) and this question returns it. Then set '
          || 'sales_knowledge_gap.status to knowledge_added.',
        'assigned', 'advisory', 'knowledge_gap', 'customer_support', 3, true, false)
      returning id into v_task;

      insert into public.sales_knowledge_gap (question_norm, question, refusal, nearest_corpus, task_id)
      values (v_norm, left(btrim(p_question), 2000),
              coalesce(nullif(btrim(p_refusal), ''), 'no_grounded_answer'),
              'support_corpus', v_task);
      v_asks := 1;
    else
      v_task := v_gap.task_id;
      v_asks := v_gap.asks + 1;
      update public.sales_knowledge_gap
         set asks = asks + 1, last_asked_at = now(),
             refusal = coalesce(nullif(btrim(p_refusal), ''), refusal)
       where id = v_gap.id;
      -- Asked repeatedly is the definition of urgent, exactly as on the sales side.
      update public.org_tasks
         set priority = least(9, greatest(priority, 3 + v_gap.asks)), updated_at = now()
       where id = v_task and status not in ('done', 'cancelled');
    end if;
  end if;

  return jsonb_build_object(
    'ok', true, 'task_id', v_task, 'asks', v_asks, 'test_traffic', v_test,
    'reply_en', 'I do not have a sourced answer to that yet, and I will not guess at it. I have '
      || 'recorded your question exactly as you asked it so it gets answered properly. If you need '
      || 'it now, call or WhatsApp +971 50 931 9355 (Mon-Fri, 9am-6pm GST) or email '
      || 'management@quotesdone.com.',
    'reply_ar', 'لا تتوفر لديّ إجابة موثّقة عن ذلك حتى الآن، ولا أودّ التخمين. سجّلتُ سؤالكم كما كتبتموه '
      || 'تمامًا ليُجاب عنه إجابة دقيقة. وإن احتجتم إلى الإجابة الآن، يمكنكم الاتصال أو المراسلة عبر '
      || 'واتساب:' || E'\n' || '+971 50 931 9355' || E'\n' || 'أو البريد الإلكتروني:' || E'\n'
      || 'management@quotesdone.com');
end
$function$


CREATE OR REPLACE FUNCTION public.fn_support_knowledge_search(p_query text, p_limit integer DEFAULT 6, p_kind text DEFAULT NULL::text, p_embedding vector DEFAULT NULL::vector)
 RETURNS TABLE(record_id text, record_kind text, title text, body text, body_sha256 text, source_ids text[], source_path text, review_status text, authority_effect text, contains_synthetic_example boolean, structured_data jsonb, relevance real, matched_how text, warning text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_embedding is null then return; end if;
  return query
  select k.record_id, k.record_kind, k.title, k.body, k.body_sha256, k.source_ids, k.source_path, k.review_status,
         k.authority_effect, k.contains_synthetic_example, k.structured_data,
         (1 - (k.embedding_gte <=> p_embedding))::real as relevance, 'meaning'::text as matched_how,
         'Advisory only. authority_effect=none: this may not approve a refund, grant an entitlement, '
         || 'change a price or become policy. review_status=' || k.review_status || '. '
         || case when k.record_kind = 'message_template'
                 then 'DRAFT TEMPLATE -- not an approved provider template. Check wa_template_registry before sending. ' else '' end
         || case when k.contains_synthetic_example
                 then 'CONTAINS A SYNTHETIC EXAMPLE -- authored, not a real QuotesDone conversation. ' else '' end
         || 'Account facts come from the database, never from this record.' as warning
    from public.support_knowledge k
   where k.runtime_index_eligible and k.embedding_gte is not null
     and (p_kind is null or k.record_kind = p_kind)
     and 1 - (k.embedding_gte <=> p_embedding) >= 0.84
   order by k.embedding_gte <=> p_embedding, k.record_id
   limit greatest(1, least(coalesce(p_limit, 6), 30));
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_knowledge_search_vector()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  new.search :=
      setweight(to_tsvector('english'::regconfig, coalesce(new.title,'')), 'A')
   || setweight(to_tsvector('english'::regconfig, coalesce(array_to_string(new.tags,' '),'')), 'B')
   || setweight(to_tsvector('english'::regconfig, coalesce(new.body,'')), 'C');
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_low_csat_opens_recovery()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_case public.support_case; v_ref text; attempt int := 0;
begin
  select * into v_case from public.support_case where case_id = new.case_id;
  -- a recovery case that is itself rated low is not recovered again in a loop; the complaint event
  -- (t_emit_customer_complaint) still records it for the CEO.
  if not found or v_case.case_kind = 'service_recovery' then return null; end if;
  if exists (select 1 from public.support_case r where r.recovery_of_case_id = v_case.case_id) then return null; end if;
  loop
    attempt := attempt + 1;
    begin
      v_ref := public.fn_support_case_new_ref();
      insert into public.support_case (case_ref, party_kind, party_id, inquiry_ref, subject, state, identity_verified,
                                       verified_how, owner_role_id, case_kind, customer_profile_id, channel, channels,
                                       last_channel, lang, recovery_of_case_id)
      values (v_ref, v_case.party_kind, v_case.party_id, v_case.inquiry_ref,
              'Service recovery: rated ' || new.rating::int || '/5 on ' || v_case.case_ref
                || coalesce(' — "' || left(new.comment, 500) || '"', ''),
              'open', v_case.identity_verified, v_case.verified_how, 'customer_support', 'service_recovery',
              v_case.customer_profile_id, v_case.last_channel,
              case when v_case.last_channel is null then '{}'::text[] else array[v_case.last_channel] end,
              v_case.last_channel, v_case.lang, v_case.case_id);
      exit;
    exception when unique_violation then
      if attempt >= 5 then raise; end if;
    end;
  end loop;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_may_act(p_action_class text, p_amount_aed numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.fn_agent_may_act('customer_support', p_action_class, p_amount_aed);
$function$


CREATE OR REPLACE FUNCTION public.fn_support_notification_sync_state()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.status is distinct from old.status then
    update public.support_notification
       set state = case new.status
             when 'sent'       then 'sent'
             when 'suppressed' then 'suppressed'
             when 'failed'     then 'failed'
             when 'skipped'    then 'suppressed'
             when 'held'       then 'queued'
             else state end,
           sent_at = case when new.status = 'sent' then coalesce(new.sent_at, now()) else sent_at end,
           provider_id = coalesce(new.id::text, provider_id),
           provider_status = new.status,
           attempts = coalesce(new.attempts, attempts),
           -- The provider's own words, kept rather than summarised. A bounce reason is the only
           -- thing that distinguishes "the address is wrong" from "our domain is in trouble".
           failure_reason = case when new.status in ('failed','skipped')
                                 then new.last_error else failure_reason end
     where outbox_id = new.id;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_notification_to_outbox()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_role text; v_id bigint; v_kind text;
begin
  -- WHO IS THIS PERSON TO US. send_outbox routes the from-address, the reply-to, the template and
  -- the unsubscribe header off to_role, so getting it wrong sends a supplier a customer-branded
  -- email from the wrong mailbox. Read from the case rather than guessed.
  select case when c.party_kind = 'supplier' then 'supplier' else 'customer' end
    into v_role
    from public.support_case c where c.case_id = new.case_id;
  v_role := coalesce(v_role, 'customer');

  if new.channel = 'email' then
    if coalesce(btrim(new.recipient), '') = '' then
      new.bridge_note := 'no email address on the row; nothing to hand over';
      return new;
    end if;

    -- THE TYPE CARRIES THE PURPOSE, and that is load-bearing rather than cosmetic: send_outbox
    -- exempts anything matching licence/renew/expiry from the supplier bulk gate, because a
    -- document request is transactional. Passing the purpose through means a licence reminder is
    -- recognised as one instead of being held with the marketing.
    v_kind := coalesce(new.purpose, 'support');

    -- KIND CARRIES THE PURPOSE TOO, and this is not cosmetic. a10_notifications_founder_mail_policy
    -- governs anything addressed to the founder by KIND, reading it before type. An earlier version
    -- of this bridge stamped every row 'support_agent', which collapsed every kind of support mail
    -- into one governance decision: allow the label and he gets all of it, refuse it and he gets
    -- none -- and the policy table could not tell a refund decision from a licence reminder. The
    -- provenance that label was carrying is already on the support_notification row it came from,
    -- so nothing is lost by letting the purpose through.
    insert into public.notifications (type, kind, to_email, to_role, subject, body, status, channel)
    values (v_kind, v_kind, btrim(new.recipient), v_role,
            coalesce(new.subject, 'QuotesDone'), new.body, 'queued', 'email')
    returning id into v_id;

    new.outbox_id := v_id;
    new.bridged_at := now();
    new.bridge_note := format('handed to notifications #%s as a %L to a %s', v_id, v_kind, v_role);

  elsif new.channel = 'whatsapp' then
    -- NOT BRIDGED, AND SAYING SO. send_outbox is email only, and a business-initiated WhatsApp
    -- message needs an approved template and recorded opt-in, which no recipient has yet. Writing
    -- it into an email queue would produce a delivery that never happened; leaving it silent would
    -- be indistinguishable from working. It is held, with the reason on the row.
    new.bridge_note := 'not bridged: WhatsApp is business-initiated here and no recipient has recorded opt-in. '
                    || 'This is held deliberately, not lost. An inbound reply inside the 24-hour window goes '
                    || 'through wa_inbound and does not use this table.';
  end if;

  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_notify_new_quotation(p_quote_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  q record; c record; v_case bigint; v_ref text; v_portal text;
  v_body text; v_subject text; v_scan jsonb;
  v_queued jsonb := '[]'::jsonb; v_skipped jsonb := '[]'::jsonb;
  v_dedupe text; v_id bigint;
begin
  -- THE COMMITTED STATE, AND THE CURRENT ONE. Both are required: committed_at proves it was
  -- published, and the status re-read proves it has not been withdrawn since. A quotation withdrawn
  -- between publication and this call must not be announced, and only a fresh read can know that.
  select qq.id, qq.inquiry_id, qq.supplier_id, qq.committed_at, qq.committed_hash, qq.status, qq.anonymized
    into q from public.quotes qq where qq.id = p_quote_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', format('no quotation %s', p_quote_id::text));
  end if;
  if q.committed_at is null then
    return jsonb_build_object('ok', false, 'reason',
      'this quotation is not committed. A draft or a failed upload is not a publication and must never reach a customer.');
  end if;
  if coalesce(q.status,'') in ('withdrawn','cancelled','rejected','expired') then
    return jsonb_build_object('ok', false, 'reason',
      format('the quotation is %L now. It was committed once; it is not visible today, and the customer is not told about it.', q.status));
  end if;

  -- wa_dest: the CONFIRMED WhatsApp number (#322), or null. wa_optin is no longer read anywhere.
  select i.rfq_no, cu.id cust_id, cu.full_name, cu.phone, cu.email, cu.banned,
         public.fn_whatsapp_destination('customer', cu.id) as wa_dest
    into c
    from public.inquiries i
    join public.customers cu on cu.id = i.customer_id
   where i.id = q.inquiry_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason',
      'the inquiry or its owner could not be read. Nothing is sent: a notification with no verified recipient is a message to a guess.');
  end if;
  if coalesce(c.banned, false) then
    return jsonb_build_object('ok', false, 'reason', 'the inquiry owner is banned; no notification is sent.');
  end if;

  -- rfq_no is an INTEGER sequence number. The customer-facing reference is rendered from it when
  -- it exists and from the inquiry id when it does not, so the shape is stable either way.
  v_ref := case when c.rfq_no is not null then 'RFQ-' || c.rfq_no::text
                else 'INQ-' || q.inquiry_id::text end;
  v_portal := coalesce((select value from public.app_secrets where key = 'public_site_url'), 'https://quotesdone.com') || '/portal';

  -- DETERMINISTIC RENDERING. The spec requires it for notifications, and it is also the only way the
  -- anonymity scan means anything: a model could compose a different sentence next time, and the
  -- scan would be checking a message nobody will send.
  v_body := 'You have received a new quotation for inquiry ' || v_ref
         || '. Sign in to your QuotesDone portal to review it: ' || v_portal || '.';
  v_subject := 'A new quotation for inquiry ' || v_ref;

  -- THE SCAN, before anything is queued. It reads the live supplier row and the live quotation, so
  -- it is checking for THIS supplier's actual name, email, phone and amount -- not a word list.
  v_scan := public.fn_support_anonymity_scan(v_body, v_subject, null, q.supplier_id, q.id::text);
  if (v_scan->>'safe') <> 'true' then
    return jsonb_build_object('ok', false, 'blocked', true, 'reason', v_scan->>'note', 'scan', v_scan);
  end if;

  -- The case that owns this conversation.
  insert into public.support_case (case_ref, party_kind, party_id, inquiry_ref, subject)
  values ('case:quote:' || q.id::text, 'customer', c.cust_id::text, v_ref,
          'New quotation published for ' || v_ref)
  on conflict (case_ref) do update set last_activity_at = now()
  returning case_id into v_case;
  if v_case is null then
    select case_id into v_case from public.support_case where case_ref = 'case:quote:' || q.id::text;
  end if;

  -- BOTH CHANNELS, EACH JUDGED ON ITS OWN PERMISSION. The spec: "Check both-channel permissions
  -- independently and record blocked/suppressed outcomes honestly." A missing email is not a reason
  -- to skip WhatsApp, and no consent on WhatsApp is not a reason to skip email.
  --
  -- The dedupe key carries the publication version (committed_hash), so re-committing a changed
  -- quotation notifies again and the same commit arriving twice does not.
  if c.wa_dest is not null then
    v_dedupe := 'quote_published|' || q.id::text || '|' || coalesce(q.committed_hash,'nohash') || '|whatsapp|' || c.wa_dest;
    insert into public.support_notification
      (dedupe_key, case_id, purpose, channel, recipient, inquiry_ref, publication_version,
       subject, body, anonymity_checked_at, anonymity_result)
    values (v_dedupe, v_case, 'quote_published', 'whatsapp', c.wa_dest, v_ref, q.committed_hash,
            null, v_body, now(), v_scan)
    on conflict (dedupe_key) do nothing
    returning id into v_id;
    v_queued := v_queued || jsonb_build_object('channel','whatsapp','queued', v_id is not null,
                  'note', case when v_id is null then 'already queued for this publication version' else 'queued' end);
  else
    v_skipped := v_skipped || jsonb_build_object('channel','whatsapp','reason',
      'no confirmed WhatsApp number (the customer said they do not use WhatsApp, or has not confirmed one)');
  end if;

  if coalesce(btrim(c.email),'') <> '' then
    v_dedupe := 'quote_published|' || q.id::text || '|' || coalesce(q.committed_hash,'nohash') || '|email|' || c.email;
    insert into public.support_notification
      (dedupe_key, case_id, purpose, channel, recipient, inquiry_ref, publication_version,
       subject, body, anonymity_checked_at, anonymity_result)
    values (v_dedupe, v_case, 'quote_published', 'email', c.email, v_ref, q.committed_hash,
            v_subject, v_body, now(), v_scan)
    on conflict (dedupe_key) do nothing
    returning id into v_id;
    v_queued := v_queued || jsonb_build_object('channel','email','queued', v_id is not null,
                  'note', case when v_id is null then 'already queued for this publication version' else 'queued' end);
  else
    v_skipped := v_skipped || jsonb_build_object('channel','email','reason','no email on the customer record');
  end if;

  return jsonb_build_object(
    'ok', true, 'quote_id', q.id, 'inquiry_ref', v_ref, 'case_id', v_case,
    'publication_version', q.committed_hash,
    'queued', v_queued, 'skipped', v_skipped, 'anonymity', v_scan,
    'note', 'Queued only. Delivery is the sender''s job and its outcome is recorded on the row, never assumed here.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_open_case_of(p_profile bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case_id from public.support_case where customer_profile_id = p_profile and state <> 'closed'
   order by last_activity_at desc limit 1
$function$


CREATE OR REPLACE FUNCTION public.fn_support_open_identity_challenge(p_channel text, p_sender_ref text, p_claimed_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_lead bigint; v_to text; v_code text; v_id bigint; v_grant jsonb; v_open int;
begin
  v_grant := public.fn_support_may_act('document');
  if (v_grant->>'may_act') <> 'true' then
    return jsonb_build_object('ok', false, 'reason', v_grant->>'reason');
  end if;

  -- RATE LIMIT PER SENDER, not per account. Limiting per account would let a stranger lock a real
  -- supplier out of their own verification by spamming challenges at them.
  select count(*) into v_open from public.support_identity_challenge
   where sender_ref = p_sender_ref and created_at > now() - interval '1 hour';
  if v_open >= 5 then
    return jsonb_build_object('ok', true, 'challenge_opened', false, 'reason', 'rate_limited',
      'message', 'I have sent several codes to this account recently. Please use the most recent one, or try again in an hour.');
  end if;

  select id, email into v_lead, v_to from public.leads
   where lower(email) = lower(btrim(p_claimed_email)) order by id limit 1;

  v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');

  if v_lead is not null then
    insert into public.support_identity_challenge
      (channel, sender_ref, claimed_email, lead_id, sent_to, code_hash, expires_at)
    values (p_channel, p_sender_ref, p_claimed_email, v_lead, v_to,
            encode(sha256(convert_to(v_code || '|' || v_lead::text, 'UTF8')), 'hex'), now() + interval '15 minutes')
    returning challenge_id into v_id;

    insert into public.support_notification (dedupe_key, case_id, purpose, channel, recipient,
      subject, body, anonymity_checked_at, anonymity_result)
    values ('idchallenge|' || v_id::text, null, 'identity_challenge', 'email', v_to,
            'Your QuotesDone confirmation code',
            'Your confirmation code is ' || v_code || '. It expires in 15 minutes. If you did not ask '
            || 'to confirm a document upload, you can ignore this message and nothing will be filed.',
            now(), jsonb_build_object('safe', true, 'note', 'code to the address of record; no counterparty data'));
  end if;

  -- THE SAME ANSWER EITHER WAY. Whether or not that account exists, the sender is told a code was
  -- sent to the address they named. Saying "no account with that email" would turn this into a
  -- free tool for discovering who is registered with us.
  return jsonb_build_object('ok', true, 'challenge_opened', v_lead is not null,
    'message', 'I have sent a 6-digit code to ' || p_claimed_email || '. Reply with the code and I '
            || 'will file your document against that account. The code expires in 15 minutes.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_open_reports()
 RETURNS TABLE(report_id bigint, severity text, subject text, status text, owner_role_id text, age interval, next_review_at timestamp with time zone, attempts integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select r.id, r.severity, r.subject, r.status, r.owner_role_id,
         now() - r.created_at, r.next_review_at, r.delivery_attempts
    from public.support_ceo_report r
   where r.status in ('sent','failed','blocked')
   order by case r.severity when 'critical' then 0 when 'serious' then 1
                            when 'elevated' then 2 else 3 end,
            r.created_at;
$function$


CREATE OR REPLACE FUNCTION public.fn_support_portal_rate(p_party_kind text, p_party_id text, p_case_ref text, p_csat numeric, p_ces numeric DEFAULT NULL::numeric, p_comment text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_prof bigint := public.fn_support_profile_resolve(p_party_kind, p_party_id, null, null);
begin
  if p_csat is not null and p_csat not between 1 and 5 then return jsonb_build_object('ok', false, 'reason', 'csat is 1 to 5'); end if;
  if p_ces is not null and p_ces not between 1 and 7 then return jsonb_build_object('ok', false, 'reason', 'ces is 1 to 7'); end if;
  if v_prof is null or not exists (select 1 from public.support_case c where c.case_ref = upper(btrim(p_case_ref))
                                      and c.customer_profile_id = v_prof and c.state = 'closed') then
    return jsonb_build_object('ok', false, 'reason', 'no closed case ' || coalesce(p_case_ref, '') || ' for this account');
  end if;
  return public.fn_support_feedback_record(p_case_ref, p_csat, p_ces, p_comment, 'portal');
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_profile_resolve(p_kind text, p_party_id text, p_email text, p_phone text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_cust uuid; v_lead bigint; v_email text; v_tail text; v_name text; v_id bigint;
  v_kind text := case when p_kind in ('customer', 'supplier') then p_kind else 'unknown' end;
begin
  if v_kind = 'customer' and p_party_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    v_cust := p_party_id::uuid;
    select lower(btrim(c.email)), c.phone, c.full_name into v_email, p_phone, v_name
      from public.customers c where c.id = v_cust;
    v_email := coalesce(v_email, lower(btrim(p_email)));
  elsif v_kind = 'supplier' and p_party_id ~ '^[0-9]+$' then
    v_lead := p_party_id::bigint;
    select lower(btrim(l.email)), coalesce(l.phone_e164, l.phone), l.company_name into v_email, p_phone, v_name
      from public.leads l where l.id = v_lead;
    v_email := coalesce(v_email, lower(btrim(p_email)));
  else
    v_email := lower(btrim(p_email));
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+$' then v_email := null; end if;
  v_tail := right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 9);
  if length(v_tail) < 9 then v_tail := null; end if;
  if v_cust is null and v_lead is null and v_email is null and v_tail is null then return null; end if;

  select p.id into v_id from public.support_customer_profile p
   where (v_cust is not null and p.customer_id = v_cust)
      or (v_lead is not null and p.lead_id = v_lead)
      or (v_email is not null and p.email = v_email)
      or (v_tail is not null and p.phone_tail = v_tail)
   order by (p.customer_id = v_cust) desc nulls last, (p.lead_id = v_lead) desc nulls last,
            (p.email = v_email) desc nulls last, p.id
   limit 1;

  if v_id is null then
    insert into public.support_customer_profile (party_kind, customer_id, lead_id, email, phone_tail, display_name)
    values (v_kind, v_cust, v_lead, v_email, v_tail, v_name) returning id into v_id;
  else
    update public.support_customer_profile p
       set party_kind   = case when p.party_kind = 'unknown' then v_kind else p.party_kind end,
           customer_id  = coalesce(p.customer_id, case when not exists (select 1 from public.support_customer_profile x where x.customer_id = v_cust) then v_cust end),
           lead_id      = coalesce(p.lead_id, case when not exists (select 1 from public.support_customer_profile x where x.lead_id = v_lead) then v_lead end),
           email        = coalesce(p.email, v_email),
           phone_tail   = coalesce(p.phone_tail, v_tail),
           display_name = coalesce(p.display_name, v_name),
           last_seen_at = now()
     where p.id = v_id;
  end if;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_rating_due(p_party_kind text, p_party_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_prof bigint;
begin
  select p.id into v_prof from public.support_customer_profile p
   where (p_party_kind = 'customer' and p.customer_id::text = p_party_id)
      or (p_party_kind = 'supplier' and p.lead_id::text = p_party_id)
   limit 1;
  if v_prof is null then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('case_ref', c.case_ref, 'subject', left(c.subject, 140), 'closed_at', c.closed_at)
                                    order by c.closed_at desc)
                     from public.support_case c
                    where c.customer_profile_id = v_prof and c.state = 'closed'
                      and c.csat_requested_at > now() - interval '14 days'
                      and not exists (select 1 from public.feedback f where f.case_id = c.case_id and f.kind = 'csat')), '[]'::jsonb);
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_receive_document(p_channel text, p_sender_ref text, p_storage_path text, p_caption text DEFAULT NULL::text, p_media_kind text DEFAULT NULL::text, p_declared text DEFAULT NULL::text, p_lead_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c jsonb; v_lead bigint; v_id bigint; v_note text; v_reply text;
  v_before jsonb; v_after jsonb; v_grant jsonb; v_missing text;
begin
  v_grant := public.fn_support_may_act('document');
  if (v_grant->>'may_act') <> 'true' then
    return jsonb_build_object('ok', false, 'reason', v_grant->>'reason');
  end if;
  if p_channel not in ('email','portal') then
    return jsonb_build_object('ok', false, 'reason',
      'this function serves the email and portal paths; WhatsApp has fn_wa_attach_document.');
  end if;
  if coalesce(btrim(p_storage_path), '') = '' then
    return jsonb_build_object('ok', false, 'reason',
      'no stored file. A receipt for a document that was never stored is the lost-document failure with a friendlier message.');
  end if;

  -- WHO SENT IT. The portal already knows -- the session is the identity, which is why it may pass a
  -- lead directly. Email has only the From address, so it is matched against the address of record.
  if p_channel = 'portal' then
    v_lead := p_lead_id;
  else
    select id into v_lead from public.leads
     where lower(email) = lower(btrim(p_sender_ref)) order by id limit 1;
  end if;

  c := public.fn_document_classify(p_caption, p_storage_path, p_declared);

  if v_lead is not null then v_before := public.fn_supplier_mandatory_check(v_lead); end if;

  if v_lead is null then
    v_note := 'No account matches this sender. Held, and an identity challenge is the only route to attaching it.';
    v_reply := 'Thank you -- I have your file safely. I could not match it to a registered account '
            || 'from this address, so I have not filed it yet. Reply with the email address you '
            || 'registered with and I will send a short code to that address to confirm it is you.';
  elsif (c->>'kind') = 'unknown' then
    v_note := 'Owner known, type not. Held rather than filed on a guess.';
    v_reply := 'Thank you, I have saved that to your file. I could not tell which document it is, so '
            || 'to file it correctly please tell me: is it your trade licence, your company profile, '
            || 'or the signed terms?';
  else
    v_note := format('Attached as %s to lead %s.', c->>'kind', v_lead);
  end if;

  insert into public.support_document_intake
    (channel, sender_ref, lead_id, storage_path, media_kind, caption,
     classified_as, classified_by, confidence, attached, attach_note)
  values (p_channel, p_sender_ref, v_lead, p_storage_path, p_media_kind, p_caption,
          c->>'kind', c->>'by', c->>'confidence',
          v_lead is not null and (c->>'kind') <> 'unknown', coalesce(v_note, ''))
  returning intake_id into v_id;

  if v_lead is not null and (c->>'kind') <> 'unknown' then
    if (c->>'kind') = 'licence' then
      update public.leads set license_doc_path = p_storage_path where id = v_lead;
    elsif (c->>'kind') = 'profile' then
      update public.leads set company_profile_doc_path = p_storage_path where id = v_lead;
    else
      update public.leads set signed_terms_path = p_storage_path where id = v_lead;
    end if;

    -- A LICENCE THAT ARRIVED STOPS THE CHASE FOR IT. Without this the supplier keeps being asked
    -- for a document the company already holds, which is how a chase teaches people we do not read
    -- what they send.
    if (c->>'kind') = 'licence' then
      perform public.fn_licence_ask_close_for_lead(v_lead, p_channel, v_id);
    end if;

    v_after := public.fn_supplier_mandatory_check(v_lead);
    -- THE RECEIPT SAYS WHAT IS STILL MISSING, the same as the WhatsApp path. A receipt that only
    -- confirms arrival leaves the supplier believing they are finished when they are not, which is
    -- how 81 invitations became 0 registrations.
    if coalesce((v_after->>'complete')::boolean, false) then
      v_reply := 'Got it -- your ' || replace(c->>'kind','_',' ') || ' is saved. Your file is now '
              || 'complete and goes for verification. I will let you know when it is approved.';
    else
      select string_agg(value #>> '{}', ', ') into v_missing
        from jsonb_array_elements(v_after->'missing');
      v_reply := 'Got it -- your ' || replace(c->>'kind','_',' ') || ' is saved. Still needed: '
              || coalesce(v_missing, '(nothing listed)') || '. You can send them the same way.';
    end if;
  end if;

  return jsonb_build_object('ok', true, 'intake_id', v_id, 'channel', p_channel,
    'lead_id', v_lead, 'classified_as', c->>'kind', 'confidence', c->>'confidence',
    'attached', v_lead is not null and (c->>'kind') <> 'unknown',
    'needs_identity_challenge', v_lead is null,
    'mandatory_before', v_before, 'mandatory_after', v_after, 'reply', v_reply);
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_record_supplier_contact(p_transaction_id uuid, p_lead_id bigint, p_channel text, p_notification_id bigint DEFAULT NULL::bigint, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id bigint; v_n int;
begin
  if p_channel is null or p_channel not in ('email','whatsapp','sms','phone') then
    raise exception 'channel must be one of email, whatsapp, sms, phone (got %)', coalesce(p_channel,'null');
  end if;

  insert into public.supplier_response_watch (transaction_id, lead_id, attempts)
  values (p_transaction_id, p_lead_id, '[]'::jsonb)
  on conflict (transaction_id) do nothing;

  update public.supplier_response_watch
     set attempts = attempts || jsonb_build_object(
           'at', now(), 'channel', p_channel,
           'notification_id', p_notification_id, 'note', p_note)
   where transaction_id = p_transaction_id
   returning id, jsonb_array_length(attempts) into v_id, v_n;

  return jsonb_build_object('ok', true, 'watch_id', v_id, 'attempts', v_n, 'channel', p_channel);
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_record_supplier_response(p_transaction_id uuid, p_channel text, p_ref text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_row public.supplier_response_watch;
begin
  update public.supplier_response_watch
     set first_response_at = coalesce(first_response_at, now()),
         response_channel  = coalesce(response_channel, p_channel),
         response_ref      = coalesce(response_ref, p_ref)
   where transaction_id = p_transaction_id
   returning * into v_row;

  if v_row.id is null then
    return jsonb_build_object('ok', false, 'reason', 'no watch is open for this transaction');
  end if;
  return jsonb_build_object('ok', true, 'watch_id', v_row.id,
    'first_response_at', v_row.first_response_at,
    'note', 'This transaction can no longer produce a non-response refund. The supplier answered.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_reply_readability_log(p_channel text, p_lang text, p_path text, p_rewritten boolean, p_score integer, p_tone integer, p_issues text[], p_reason text, p_demo boolean)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  insert into public.support_reply_readability (channel, lang, path, rewritten, score, tone, issues, reason, demo)
  values (p_channel, p_lang, p_path, coalesce(p_rewritten, false), p_score, p_tone, coalesce(p_issues, '{}'),
          left(p_reason, 300), coalesce(p_demo, false));
$function$


CREATE OR REPLACE FUNCTION public.fn_support_reply_watch_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_sla numeric := public.fn_seat_clock_policy('support_first_reply_sla_hours', 24);
  v_cut timestamptz; v_founder text[]; c text; v_n int; v_oldest timestamptz; v_ids jsonb; v_median numeric;
  v_out jsonb := '{}'::jsonb;
begin
  v_cut := now() - make_interval(secs => (v_sla * 3600)::double precision);
  select coalesce(array_agg(right(regexp_replace(value, '[^0-9]', '', 'g'), 9)), '{}') into v_founder
    from public.app_secrets where key in ('founder_mobile', 'founder_public_phone', 'admin_mfa_phone')
     and length(regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g')) >= 9;

  foreach c in array array['email', 'whatsapp', 'chat'] loop
    if c = 'email' then
      select count(*), min(m.created_at), coalesce(jsonb_agg(m.id order by m.id), '[]'::jsonb)
        into v_n, v_oldest, v_ids
        from public.inbound_messages m
       where m.created_at > now() - interval '30 days' and m.created_at < v_cut and m.replied_at is null
         and coalesce(m.to_email, '') !~* '^expenses@' and coalesce(m.owner_role, '') <> 'accountant'
         -- 19 Oct 2026: a no-reply sender cannot be answered, and calendar+ is the founder's own approval inbox.
         -- Only the sender's local part is matched, so a real customer whose address merely contains the word stays counted.
         and coalesce(m.to_email, '') !~* '^calendar\+'
         and coalesce(substring(m.from_email from '([^<>\s"]+)@'), '') !~* '^(no-?reply|do-?not-?reply)'
         and not public.fn_is_demo_email(m.from_email);
      select percentile_cont(0.5) within group (order by extract(epoch from m.replied_at - m.created_at) / 60) into v_median
        from public.inbound_messages m
       where m.replied_at is not null and m.created_at > now() - interval '7 days'
         and coalesce(m.to_email, '') !~* '^expenses@' and coalesce(m.owner_role, '') <> 'accountant';
    elsif c = 'whatsapp' then
      select count(*), min(w.created_at), coalesce(jsonb_agg(w.id order by w.id), '[]'::jsonb)
        into v_n, v_oldest, v_ids
        from public.wa_messages w
       where w.created_at > now() - interval '30 days' and w.created_at < v_cut
         and coalesce(btrim(w.inbound), '') <> '' and (w.reply is null or not coalesce(w.sent, false))
         and not (right(regexp_replace(coalesce(w.wa_from, ''), '[^0-9]', '', 'g'), 9) = any (v_founder));
      v_median := null;   -- the WhatsApp reply is written in the same row as the inbound: minutes are not recorded
    else
      select count(*), min(g.created_at), coalesce(jsonb_agg(g.id order by g.id), '[]'::jsonb)
        into v_n, v_oldest, v_ids
        from public.assistant_logs g
        left join public.org_tasks t on t.id = g.gap_task_id
       where g.answered = false and g.created_at > now() - interval '30 days' and g.created_at < v_cut
         and coalesce(t.status, 'open') not in ('done', 'cancelled');
      select percentile_cont(0.5) within group (order by extract(epoch from t.updated_at - g.created_at) / 60) into v_median
        from public.assistant_logs g join public.org_tasks t on t.id = g.gap_task_id
       where g.answered = false and t.status = 'done' and t.updated_at > g.created_at and g.created_at > now() - interval '7 days';
    end if;

    if v_n > 0 then
      perform public.fn_it_engineer_finding_upsert('support_reply_sla:' || c,
        v_n || ' ' || c || ' message(s) have waited more than ' || v_sla || ' h for a first reply (oldest '
          || to_char(v_oldest at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI') || ' Dubai)',
        'customer_support first-reply watch (fn_support_reply_watch_tick) -> ' || c, 'customer_facing', v_n,
        jsonb_build_object('channel', c, 'sla_hours', v_sla, 'waiting', v_n, 'oldest', v_oldest,
                           'ids', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select x from jsonb_array_elements(v_ids) x limit 20) z),
                           'median_first_reply_minutes_7d', round(v_median), 'owner_seat', 'customer_support', 'duty', 'reply_time'),
        '{}'::text[], array['whether the customer was answered on another channel'], 'customer_support');
    elsif exists (select 1 from public.it_engineer_finding where issue_key = 'support_reply_sla:' || c and closed_at is null) then
      perform public.fn_it_engineer_finding_close('support_reply_sla:' || c,
        'every ' || c || ' message older than ' || v_sla || ' h has a first reply');
    end if;
    v_out := v_out || jsonb_build_object(c, jsonb_build_object('over_sla', v_n, 'median_first_reply_minutes_7d', round(v_median)));
  end loop;
  return jsonb_build_object('ok', true, 'sla_hours', v_sla) || v_out;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_support_report_to_ceo(p_idempotency_key text, p_severity text, p_subject text, p_evidence jsonb, p_attempted jsonb, p_requested text, p_case_ref text DEFAULT NULL::text, p_task_ref text DEFAULT NULL::text, p_review_in interval DEFAULT '1 day'::interval, p_source_agent text DEFAULT 'customer_support'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_parent text;
  v_id     bigint;
  v_agent  text := lower(btrim(coalesce(p_source_agent, '')));
  v_existing public.support_ceo_report%rowtype;
begin
  -- WHO IS REPORTING IS AN ARGUMENT NOW, NOT A LITERAL. It defaults to customer_support so every
  -- existing caller behaves exactly as it did, and it is used in all three of the places the
  -- literal used to sit: the edge lookup, source_agent, and owner_role_id. Getting only two of the
  -- three would be worse than none -- a report filed under the accountant's name but gated on
  -- support's edge is a report that can be sent when support is reorganised and refused when the
  -- accountant is.
  if v_agent = '' then
    return jsonb_build_object('ok', false, 'reason',
      'source_agent is required. A report with no sender cannot be routed, because the reporting '
      || 'edge that decides where it goes is the SENDER''s edge, not a constant.');
  end if;

  -- THE MANAGER IS READ, NOT ASSUMED. If the edge is gone or the parent is not active, this
  -- refuses rather than picking someone.
  select e.parent_role_id into v_parent
    from public.org_reporting_edge e
    join public.org_role r on r.role_id = e.parent_role_id and r.status = 'active'
   where e.child_role_id = v_agent;

  if v_parent is null then
    return jsonb_build_object('ok', false, 'reason',
      format('No active reporting parent for %s. The report is NOT sent and NOT silently '
             || 'redirected: inventing a recipient is how work goes to nobody.', v_agent));
  end if;

  if coalesce(btrim(p_requested), '') = '' then
    return jsonb_build_object('ok', false, 'reason',
      'requested_outcome is required. A report that does not say what it wants is a notification, '
      || 'and the CEO cannot act on it.');
  end if;

  -- IDEMPOTENT BY THE BUSINESS EVENT. A webhook that fires twice, a retry after a timeout and a
  -- restart mid-flight must all produce ONE report. Returning the existing row is the correct
  -- answer, not an error: the caller's intent was satisfied the first time.
  select * into v_existing from public.support_ceo_report where idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('ok', true, 'duplicate', true, 'report_id', v_existing.id,
      'status', v_existing.status,
      'note', 'This matter was already reported. Returning the original rather than sending a second.');
  end if;

  insert into public.support_ceo_report
    (idempotency_key, source_agent, case_ref, task_ref, severity, subject,
     verified_evidence, attempted_actions, requested_outcome, owner_role_id, next_review_at)
  values
    (p_idempotency_key, v_agent, p_case_ref, p_task_ref, p_severity, p_subject,
     p_evidence, coalesce(p_attempted, '[]'::jsonb), p_requested,
     v_agent,                       -- the sender keeps it until the CEO accepts
     now() + coalesce(p_review_in, interval '1 day'))
  returning id into v_id;

  return jsonb_build_object('ok', true, 'report_id', v_id, 'reported_to', v_parent,
    'owner', v_agent,
    'note', format('Sent. Ownership stays with %s until the CEO accepts it with a receipt.', v_agent));
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_request_ratings_due(p_limit integer DEFAULT 500)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_days     integer;
  v_site     text;
  v_founder  text;
  v_asked    integer := 0;
begin
  select nullif(regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g'), '')::int
    into v_days from public.app_secrets where key = 'rating_request_days_after_reveal';
  v_days := coalesce(v_days, 21);

  select coalesce(value, 'https://quotesdone.com') into v_site
    from public.app_secrets where key = 'public_site_url';
  v_site := coalesce(v_site, 'https://quotesdone.com');

  -- The founder's own address, so a customer record that happens to carry it is never asked.
  -- fn_notifications_founder_mail_policy intercepts founder-directed mail whose kind is not
  -- allowed_to_email and returns NULL: the row is silently not inserted, the unique key stays free,
  -- and this sweep would re-ask that one transaction every 15 minutes forever.
  select lower(nullif(split_part(coalesce(value, ''), ',', 1), '')) into v_founder
    from public.app_secrets where key = 'admin_emails';

  with due as (
    select t.id as tx_id, t.quote_id, t.inquiry_id, t.supplier_id,
           c.email as cemail, l.company_name, i.summary
      from public.transactions t
      join public.customers c on c.id = t.customer_id
      left join public.leads l on l.id = t.supplier_id
      left join public.inquiries i on i.id = t.inquiry_id
     where t.revealed_at is not null
       and t.revealed_at <= now() - make_interval(days => v_days)
       and t.quote_id is not null
       -- 4. NEVER ASK ABOUT A REFUNDED OR REVERSED REVEAL.
       -- MEASURED, NOT ASSUMED: trg_reveal_window sets refund_status := 'window_open' on EVERY
       -- reveal, so "refund_status is null" describes no real transaction at all — a guard written
       -- as `coalesce(refund_status,'none') = 'none'` asks nobody, ever, and its zero would have
       -- looked exactly like "nothing was due". The live vocabulary is
       -- none / window_open / requested / approved / refunded / declined.
       -- This is an ALLOWLIST of the states where the money is still ours and undisputed, plus
       -- 'declined' (the customer complained and the complaint was refused — their opinion is then
       -- the most informative rating on the platform). An unrecognised future state falls out of the
       -- list and is simply not asked, which is the safe direction to fail.
       and coalesce(t.refund_status, 'none') in ('none', 'window_open', 'declined')
       and coalesce(c.email, '') like '%@%'
       and lower(coalesce(c.email, '')) is distinct from coalesce(v_founder, '~none~')
       -- 3. STOP ASKING WHEN IT IS ANSWERED. A review closes the ask permanently.
       and not exists (select 1 from public.reviews r where r.transaction_id = t.id)
       -- 2. ASKED ONCE, EVER — looked up in ANY state.
       and not exists (select 1 from public.notifications n
                        where n.type = 'rating_request' and n.quote_id = t.quote_id)
     -- A deterministic order shared by every session, so two concurrent runs take the same key in
     -- the same sequence. With one target table, one lock per key and ON CONFLICT DO NOTHING, there
     -- is no second resource to hold and therefore no cycle: this cannot deadlock.
     order by t.revealed_at, t.quote_id
     limit greatest(coalesce(p_limit, 500), 1)
  ), ins as (
    -- 1. SUPPORT SENDS IT. public.notifications is the estate's one channel queue; kind
    -- 'support_agent' is already registered in founder_mail_policy as customer_support's own
    -- customer-facing mail. The Sales Engineer is not involved and no new send path exists.
    insert into public.notifications
      (type, kind, to_email, to_role, lead_id, inquiry_id, quote_id, subject, body, channel, status)
    select 'rating_request', 'support_agent', d.cemail, 'customer',
           d.supplier_id, d.inquiry_id, d.quote_id,
           'How did ' || coalesce(d.company_name, 'your supplier') || ' do?',
           'It has been about ' || v_days || ' days since you unlocked '
             || coalesce(d.company_name, 'this supplier')
             || coalesce(' for: ' || left(d.summary, 80), '')
             || '. Now that you have had the chance to actually work with them, please rate them out '
             || 'of 5 — communication, quality, punctuality, documentation and after-sales. Open the '
             || 'job in your portal and choose Rate supplier: ' || v_site || '/portal'
             || '. Ratings on QuotesDone come only from customers who have paid to reveal a supplier '
             || 'and dealt with them, so yours is what gives this company a score at all.',
           'email', 'queued'
      from due d
    on conflict (quote_id) where type = 'rating_request' and coalesce(channel, 'email') = 'email'
    do nothing
    returning 1
  )
  select count(*)::int into v_asked from ins;

  return jsonb_build_object('ok', true, 'asked', v_asked, 'days_after_reveal', v_days,
    'note', 'Enqueued into public.notifications as customer_support. send_outbox delivers; a row in any state means the ask was already made.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_root_cause_fix(p_root_cause_id bigint, p_kind text, p_target_table text, p_target_id text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare rc public.support_root_cause; v_exists boolean;
begin
  select * into rc from public.support_root_cause where id = p_root_cause_id for update;
  if rc.id is null then raise exception 'no root cause %', p_root_cause_id; end if;
  if not rc.support_fixes then raise exception 'root cause % belongs to %; support records fixes only for causes it owns', rc.id, rc.owner_seat; end if;
  if p_target_table not in ('company_faq', 'kb_chunks', 'seat_prompt', 'wa_template', 'company_knowledge', 'support_signal_category') then
    raise exception 'a support fix is an FAQ, a knowledge entry or wording; % is none of them', p_target_table;
  end if;
  execute format('select exists (select 1 from public.%I where %s::text = $1)', p_target_table,
                 case when p_target_table = 'support_signal_category' then 'source || '':'' || value' else 'id' end)
    into v_exists using p_target_id;
  if not v_exists then raise exception 'the fix names %.% which does not exist', p_target_table, p_target_id; end if;
  insert into public.support_root_cause_fix (root_cause_id, fix_kind, target_table, target_id, note)
  values (rc.id, p_kind, p_target_table, p_target_id, p_note)
  on conflict (root_cause_id, target_table, target_id) do nothing;
  update public.support_root_cause set status = 'measuring', acted_at = now() where id = rc.id and status in ('open', 'not_fallen');
  return jsonb_build_object('ok', true, 'root_cause_id', rc.id, 'status', 'measuring');
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_touch(p_channel text, p_direction text, p_party_kind text, p_party_id text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_text text DEFAULT NULL::text, p_rating_text text DEFAULT NULL::text, p_lang text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_days int := greatest(1, public.fn_seat_clock_policy('support_case_append_days', 7)::int);
  v_reopen_days int := greatest(1, public.fn_seat_clock_policy('support_case_reopen_days', 14)::int);
  v_gap interval := make_interval(hours => greatest(1, public.fn_seat_clock_policy('support_contact_gap_hours', 4)::int));
  v_prof bigint; v_case public.support_case; v_closed public.support_case; v_id bigint; v_ref text;
  v_digits text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  v_party_kind text := case when p_party_kind in ('customer', 'supplier') then p_party_kind else 'unknown' end;
  v_party_id text; v_rt text; m text[]; attempt int := 0;
begin
  if p_direction not in ('in', 'out') then raise exception 'fn_support_touch: direction must be in or out'; end if;
  v_prof := public.fn_support_profile_resolve(v_party_kind, p_party_id, p_email, p_phone);
  if v_prof is null then return jsonb_build_object('ok', false, 'reason', 'no identity'); end if;

  select * into v_case from public.support_case
   where customer_profile_id = v_prof and state <> 'closed' order by last_activity_at desc limit 1;

  if p_direction = 'out' then
    if v_case.case_id is null then return jsonb_build_object('ok', true, 'case', null, 'reason', 'no open case'); end if;
    update public.support_case
       set first_reply_at = coalesce(first_reply_at, now()), outbound_count = outbound_count + 1,
           state = case when state in ('open', 'waiting_service') then 'waiting_customer' else state end,
           last_activity_at = now()
     where case_id = v_case.case_id;
    return jsonb_build_object('ok', true, 'case_ref', v_case.case_ref, 'direction', 'out');
  end if;

  -- A rating answering the CSAT question of a recently closed case.
  v_rt := btrim(translate(coalesce(p_rating_text, p_text, ''), '٠١٢٣٤٥٦٧٨٩', '0123456789'));
  m := regexp_match(v_rt, '^([1-5])(?:\s*[,/ -]\s*([1-7]))?$');
  if m is not null then
    select * into v_closed from public.support_case c
     where c.customer_profile_id = v_prof and c.state = 'closed' and c.csat_requested_at > now() - make_interval(days => v_days)
       and not exists (select 1 from public.feedback f where f.case_id = c.case_id and f.kind = 'csat')
     order by c.csat_requested_at desc limit 1;
    if v_closed.case_id is not null then
      perform public.fn_support_feedback_record(v_closed.case_ref, m[1]::numeric, m[2]::numeric, null, p_channel);
      return jsonb_build_object('ok', true, 'case_ref', v_closed.case_ref, 'rated', m[1]::int, 'ces', m[2]::int);
    end if;
  end if;

  -- 5. A message naming a recently closed case of this person reopens it.
  if v_case.case_id is null then
    select * into v_closed from public.support_case c
     where c.customer_profile_id = v_prof and c.state = 'closed' and c.closed_at > now() - make_interval(days => v_reopen_days)
       and position(c.case_ref in upper(coalesce(p_text, ''))) > 0
     order by c.closed_at desc limit 1;
    if v_closed.case_id is not null then
      update public.support_case set state = 'open' where case_id = v_closed.case_id;
      select * into v_case from public.support_case where case_id = v_closed.case_id;
    end if;
  end if;

  -- An open case idle past the append window is closed and a new one starts.
  if v_case.case_id is not null and v_case.last_activity_at < now() - make_interval(days => v_days) then
    update public.support_case set state = 'closed', closed_at = now(),
           close_reason = 'resolved — no further contact in ' || v_days || ' days (closed by customer_support)'
     where case_id = v_case.case_id;
    v_case := null;
  end if;

  if v_case.case_id is null then
    select case when p.customer_id is not null then 'customer' when p.lead_id is not null then 'supplier' else 'unknown' end,
           coalesce(p.customer_id::text, p.lead_id::text, case when v_digits <> '' then '+' || v_digits end, p.email)
      into v_party_kind, v_party_id
      from public.support_customer_profile p where p.id = v_prof;
    loop
      attempt := attempt + 1;
      begin
        v_ref := public.fn_support_case_new_ref();
        insert into public.support_case (case_ref, party_kind, party_id, subject, state, identity_verified, verified_how,
                                         owner_role_id, customer_profile_id, channel, lang)
        values (v_ref, v_party_kind, v_party_id,
                initcap(p_channel) || ': ' || left(coalesce(nullif(btrim(p_text), ''), '(no text)'), 4000),
                'open', v_party_kind <> 'unknown',
                case when v_party_kind <> 'unknown' then 'matched on the ' || p_channel || ' identity' end,
                'customer_support', v_prof, p_channel,
                case when p_lang in ('en', 'ar') then p_lang end)
        returning * into v_case;
        exit;
      exception when unique_violation then
        if attempt >= 5 then raise; end if;
      end;
    end loop;
  end if;

  update public.support_case
     set inbound_count = inbound_count + 1,
         contact_count = contact_count + case when last_inbound_at is null or last_inbound_at < now() - v_gap then 1 else 0 end,
         first_customer_msg_at = coalesce(first_customer_msg_at, now()),
         last_inbound_at = now(), last_activity_at = now(),
         last_channel = p_channel,
         channels = case when p_channel = any(channels) then channels else channels || p_channel end,
         lang = coalesce(lang, case when p_lang in ('en', 'ar') then p_lang end),
         state = case when state = 'waiting_customer' then 'open' else state end
   where case_id = v_case.case_id;
  return jsonb_build_object('ok', true, 'case_ref', v_case.case_ref, 'case_id', v_case.case_id, 'direction', 'in');
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_wire_email()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_from text := lower(substring(coalesce(new.from_email, '') from '([^<>\s"]+@[^<>\s"]+)'));
        v_kind text := 'unknown'; v_id text; v_first text;
begin
  if v_from is null or v_from ~ '@(mail\.)?quotesdone\.(com|ae)$' then return null; end if;
  if coalesce(new.owner_role, 'customer_support') <> 'customer_support' then return null; end if;
  begin
    select 'customer', c.id::text into v_kind, v_id from public.customers c where lower(btrim(c.email)) = v_from limit 1;
    if v_id is null then
      select 'supplier', l.id::text into v_kind, v_id from public.leads l where lower(btrim(l.email)) = v_from order by l.id limit 1;
    end if;
    v_kind := coalesce(v_kind, 'unknown');
    if new.triaged_at is not null and old.triaged_at is null
       and coalesce(new.ai_category, '') not in ('spam', 'no_auto_reply', 'routine_queued') then
      v_first := substring(coalesce(new.body, '') from '^\s*([^\r\n]*)');
      perform public.fn_support_touch('email', 'in', v_kind, v_id, v_from, null,
                                      coalesce(new.subject, '') || E'\n' || coalesce(new.body, ''), v_first, null);
    end if;
    if new.replied_at is not null and old.replied_at is null then
      perform public.fn_support_touch('email', 'out', v_kind, v_id, v_from);
    end if;
  exception when others then
    raise warning 'fn_support_wire_email: inbound_messages % not recorded on a case: %', new.id, sqlerrm;
  end;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_wire_whatsapp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_kind text; v_cust uuid; v_lead bigint;
begin
  if coalesce(new.meta ->> 'audience', '') = 'founder' or coalesce(new.wa_from, '') = '' then return null; end if;
  begin
    select o.party_kind, o.customer_id, o.lead_id into v_kind, v_cust, v_lead from public.fn_whatsapp_owner(new.wa_from) o limit 1;
    if tg_op = 'INSERT' and nullif(btrim(new.inbound), '') is not null then
      perform public.fn_support_touch('whatsapp', 'in', v_kind, coalesce(v_cust::text, v_lead::text), null, new.wa_from,
                                      new.inbound, null, new.lang);
    end if;
    if new.reply is not null and new.sent and (tg_op = 'INSERT' or not coalesce(old.sent, false)) then
      perform public.fn_support_touch('whatsapp', 'out', v_kind, coalesce(v_cust::text, v_lead::text), null, new.wa_from);
    end if;
  exception when others then
    raise warning 'fn_support_wire_whatsapp: wa_messages % not recorded on a case: %', new.id, sqlerrm;
  end;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_support_wire_widget()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_kind text := split_part(coalesce(new.audience, ''), ':', 1); v_id text := split_part(coalesce(new.audience, ''), ':', 2);
        v_ch text := case when coalesce(new.path, '') = 'portal'
                            or coalesce(new.path, '') ~ '^(/(en|ar))?/(me|portal|supplier)(/|$|\?)' then 'portal' else 'widget' end;
begin
  if not ((v_kind = 'customer' and v_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
          or (v_kind = 'supplier' and v_id ~ '^[0-9]+$')) then
    return null;
  end if;
  begin
    if nullif(btrim(new.message), '') is not null then
      perform public.fn_support_touch(v_ch, 'in', v_kind, v_id, null, null, new.message);
    end if;
    if new.reply is not null and new.answered is distinct from false then
      perform public.fn_support_touch(v_ch, 'out', v_kind, v_id);
    end if;
  exception when others then
    raise warning 'fn_support_wire_widget: assistant_logs % not recorded on a case: %', new.id, sqlerrm;
  end;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_suppression_stops(p_reason text, p_type text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select lower(btrim(coalesce(p_reason, ''))) <> 'unsubscribe' or coalesce(p_type, '') = any (public.fn_opt_out_types())
$function$


