-- A FEE QUESTION THAT NAMES NO SIDE GETS THE CUSTOMER FEE, NOT WHAT SUPPLIERS PAY.
--
-- SEAT: customer_support. One routine: public.fn_faq_answer(text, numeric, vector, numeric). No table, no grant change.
--
-- MEASURED 22 Sep 2026 on production (scripts/checks/whatsapp_understands_a_question_asked_in_other_words
-- .test.mjs, the question embedded with the live gte-small, wa_inbound's 0.84 floor):
--   "كم رسومكم" (what are your fees) -> "هل يدفع الموردون رسوم اشتراك أو رسوم تسجيل؟" faq_semantic 0.883,
--   corroborated 1/1. That row is the Arabic supplier-fee twin of FAQ 500 that
--   scripts/sql/an_unmatched_question_gets_a_proper_answer.sql (#843) inserted; before it existed the same
--   question reached "ما هي رسوم المنصة؟" (0.8816). So #843 caused it: the new row is the nearest neighbour
--   and carries the asker's one concept (رسوم), which is all the corroboration rule asks of Arabic.
-- The live body was checked IDENTICAL to scripts/sql/the_whatsapp_menu_answers_like_a_senior_member_of_staff.sql
-- before this file was written from it.
--
-- CHANGE: in the semantic step only, a record whose QUESTION is about the supplier side ("for suppliers",
-- "do suppliers", "كمورد", "للموردين", "الموردون", "يدفع المورد") is a candidate only when the asker's own
-- text names suppliers (supplier / vendor / مورد). The next corroborated neighbour answers instead.
-- NOT CHANGED: the templates, the keyword step, the floor, the corroboration counts, every FAQ row.
--
-- PROVED BY: scripts/checks/whatsapp_understands_a_question_asked_in_other_words.test.mjs — asks production,
-- or applies this file in a transaction that is never committed while it is not yet live.
--
--   node scripts/apply_sql.mjs scripts/sql/a_fee_question_that_names_no_side_gets_the_customer_fee.sql --apply --ddl

create or replace function public.fn_faq_answer(p_text text, p_min_rank numeric default 0.15, p_embedding vector default null::vector, p_min_similarity numeric default 0.86)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare r record; v_q tsquery; k_q text; k_a text; k_src text; k_rank numeric; v_tpl record; v_ar boolean; v_qc text[]; v_best numeric; v_kq int;
begin
  if p_text is null or length(btrim(p_text)) < 2 then
    return jsonb_build_object('answered', false, 'reason', 'input too short');
  end if;

  v_ar := p_text ~ '[\u0600-\u06FF]';

  -- 1. Fixed intents. No retrieval, no model.
  select * into v_tpl from response_template
   where active and (
     (intent='greeting' and (p_text ~* '^\s*(hi|hey|hello|salam|marhaba|good (morning|afternoon|evening))\W*$'
                             or public.fn_ar_norm(p_text) ~ '^\s*(مرحبا|اهلا|السلام عليكم|صباح الخير|مساء الخير)\s*[؟!.]*\s*$')) or
     (intent='thanks'   and (p_text ~* '^\s*(thanks|thank you|thx|shukran|much appreciated)\W*$'
                             or public.fn_ar_norm(p_text) ~ '^\s*(شكرا|شكرا لك|شكرا جزيلا|مشكور)\s*[؟!.]*\s*$'))
   ) limit 1;
  if found then
    update response_template set used_count = used_count + 1 where key = v_tpl.key;
    return jsonb_build_object('answered', true, 'source', 'template', 'key', v_tpl.key,
                              'answer', v_tpl.body, 'confidence', 1.0);
  end if;

  -- 2. Keyword match, in the asker's language (Arabic records for an Arabic question, English
  --    records otherwise), exactly as before. Held in k, not returned yet.
  if v_ar then
    v_q := websearch_to_tsquery('arabic', public.fn_ar_norm(p_text));
    if v_q is not null then
      select f.question, f.answer, 'faq_keyword_ar',
             ts_rank(to_tsvector('arabic', public.fn_ar_norm(coalesce(f.question,'')||' '||coalesce(f.answer,''))), v_q) as rank
        into k_q, k_a, k_src, k_rank
        from company_faq f
       where f.public and f.status='approved' and f.language = 'ar'
         and to_tsvector('arabic', public.fn_ar_norm(coalesce(f.question,'')||' '||coalesce(f.answer,''))) @@ v_q
       order by rank desc limit 1;
      if k_rank < p_min_rank then k_q := null; end if;
    end if;
  end if;
  if k_q is null then
    v_q := websearch_to_tsquery('english', p_text);
    if v_q is not null then
      select f.question, f.answer, 'faq_keyword',
             ts_rank(to_tsvector('english', coalesce(f.question,'')||' '||coalesce(f.answer,'')), v_q) as rank
        into k_q, k_a, k_src, k_rank
        from company_faq f
       where f.public and f.status='approved' and f.language = 'en'
         and to_tsvector('english', coalesce(f.question,'')||' '||coalesce(f.answer,'')) @@ v_q
       order by rank desc limit 1;
      if k_rank < p_min_rank then k_q := null; end if;
    end if;
  end if;

  -- 3. Semantic, CORROBORATED (22 Sep 2026, instruction 763). Of the five nearest records in the
  --    asker's language, one is accepted only if cosine >= p_min_similarity, its own QUESTION carries at
  --    least one of the asker's concepts, and the record carries at least half of them (two when the
  --    asker used three or more; ALL of them for an Arabic question). Measured with the live gte-small:
  --      - "can i trust the suppliers on your site" -> "Can I invite my own supplier?" at 0.8885 with one
  --        concept of three: refused (the previous rule answered it);
  --      - "كم رسومكم" -> "متى يتم الكشف عن هويتي؟" 0.8873 (only its answer mentions the fee) lost to
  --        "ما هي رسوم المنصة؟" 0.8816 once the question's own concepts rank first;
  --      - gte-small is an English model: "ما هو سعر الذهب اليوم" (today's gold price) met "هل يمكنني
  --        استرداد المبلغ؟" at 0.9091 with two of three concepts. Arabic therefore needs every concept.
  if p_embedding is not null then
    v_qc := public.fn_faq_concepts(p_text, v_ar);
    select c.question, c.answer, c.sim,
           cardinality(array(select unnest(v_qc) intersect select unnest(public.fn_faq_concepts(c.question || ' ' || c.answer, v_ar)))) hits,
           cardinality(array(select unnest(v_qc) intersect select unnest(public.fn_faq_concepts(c.question, v_ar)))) qhits,
           cardinality(v_qc) nq
      into r
      from (select f.question, coalesce(f.answer, '') answer, round((1 - (f.embedding_gte <=> p_embedding))::numeric, 4) sim
              from company_faq f
             where f.public and f.status = 'approved' and f.embedding_gte is not null
               and f.language = case when v_ar then 'ar' else 'en' end
             order by f.embedding_gte <=> p_embedding limit 5) c
     where c.sim >= p_min_similarity
       -- A SUPPLIER-SIDE record answers only a question that names the supplier side (22 Sep 2026):
       -- "كم رسومكم" (what are your fees) met the Arabic supplier-fee twin #843 added at 0.883, above
       -- the customer platform-fee record, and a stranger was told what suppliers pay.
       and (c.question !~* '(for|as an?) suppliers?|suppliers? pay|do suppliers|كمورد|للموردين|الموردون|يدفع المورد'
            or p_text ~* 'supplier|vendor|مورد')
       and cardinality(array(select unnest(v_qc) intersect select unnest(public.fn_faq_concepts(c.question, v_ar)))) >= 1
       and cardinality(array(select unnest(v_qc) intersect select unnest(public.fn_faq_concepts(c.question || ' ' || c.answer, v_ar))))
           >= case when v_ar then cardinality(v_qc) when cardinality(v_qc) >= 3 then greatest(2, ceil(cardinality(v_qc) / 2.0)::int)
                   else ceil(cardinality(v_qc) / 2.0)::int end
     order by 5 desc, 3 desc limit 1;
    -- The keyword match keeps the answer when ITS question carries more of the asker's concepts:
    -- "what documents does a supplier need for verification" is that FAQ's own question, and the
    -- semantic neighbour "Supplier onboarding policy" shares one concept with it (measured on the site
    -- assistant's real questions, 22 Sep 2026).
    if r.question is not null then
      v_kq := case when k_q is null then -1
                   else cardinality(array(select unnest(v_qc) intersect select unnest(public.fn_faq_concepts(k_q, v_ar)))) end;
      if v_kq <= r.qhits then
        return jsonb_build_object('answered', true, 'source', 'faq_semantic', 'question', r.question,
                                  'answer', r.answer, 'confidence', r.sim, 'corroborated', r.hits || '/' || r.nq);
      end if;
    else
      select round(max(1 - (f.embedding_gte <=> p_embedding))::numeric, 4) into v_best from company_faq f
       where f.public and f.status = 'approved' and f.embedding_gte is not null and f.language = case when v_ar then 'ar' else 'en' end;
    end if;
  end if;

  if k_q is not null then
    return jsonb_build_object('answered', true, 'source', k_src, 'question', k_q,
                              'answer', k_a, 'confidence', round(k_rank::numeric, 4));
  end if;
  return jsonb_build_object('answered', false, 'reason', 'no confident FAQ match', 'best_similarity', v_best);
end $function$;
revoke execute on function public.fn_faq_answer(text, numeric, vector, numeric) from public, anon, authenticated;
