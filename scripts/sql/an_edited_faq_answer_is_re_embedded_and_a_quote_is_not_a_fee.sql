-- AN EDITED FAQ ANSWER IS RE-EMBEDDED, AND A QUOTE IS NOT A FEE — customer_support, 23 Sep 2026.
--
-- 1. STALE VECTORS. public.company_faq.embedding_gte is the vector fn_faq_answer's semantic step reads
--    (WhatsApp, site assistant). Nothing invalidated it when question/answer changed: every earlier
--    rewrite cleared it by hand (the_faq_and_the_signed_texts_carry_the_ladder..., the_licence_we_name...,
--    an_unmatched_question_gets_a_proper_answer), and the two drawing files of #872 did not, so ids 16,
--    20, 116, 126 and 289 kept the vector of their OLD text. MEASURED 23 Sep 2026 before this file:
--    stored vs gte-small(question || E'\n' || answer) of the current text = 0.9749, 0.9529, 0.9914,
--    0.9862, 0.9728 (the recipe reproduces an unchanged row at 1.0000, embed_sales_knowledge.mjs).
--    FIX: a BEFORE UPDATE trigger nulls embedding_gte whenever question or answer changes, unless the
--    same statement also writes a new vector (the embedder does: it sets embedding_gte only). The
--    re-embed is then `node scripts/kb/embed_sales_knowledge.mjs --table=company_faq`, which takes
--    every row whose embedding_gte is null — free in-region gte-small, never OpenRouter.
--    The five rows are cleared below so that same run rebuilds them.
--
-- 2. "ما هي رسومكم" (what are your fees) WAS ANSWERED WITH A QUOTATION FAQ. fn_faq_concepts folds سعر /
--    اسعار (price) to the concept 'fee', but in Arabic عرض سعر / عروض الأسعار is "a quotation", not a
--    charge. 21 of the 30 approved Arabic FAQ questions that carried 'fee' carried it only from that
--    phrase, so an Arabic fee question (one concept, 'fee') was "corroborated" by any quote FAQ. MEASURED
--    23 Sep 2026: "ما هي رسومكم" -> "هل يمكنني رفض جميع عروض الأسعار؟" at 0.917, corroborated 1/1.
--    FIX: the price word right after عرض / عروض is dropped before the concepts are read, so a quotation
--    is concept عرض, and سعر on its own (the price of a job) is still 'fee'.
--
--   node scripts/apply_sql.mjs scripts/sql/an_edited_faq_answer_is_re_embedded_and_a_quote_is_not_a_fee.sql --apply --ddl
--   node scripts/kb/embed_sales_knowledge.mjs --table=company_faq
--   node --test scripts/checks/an_edited_faq_answer_is_re_embedded.test.mjs

create or replace function public.fn_company_faq_text_change_clears_embedding()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if (new.question is distinct from old.question or new.answer is distinct from old.answer)
     and new.embedding_gte is not distinct from old.embedding_gte then
    new.embedding_gte := null;
  end if;
  return new;
end $fn$;

revoke execute on function public.fn_company_faq_text_change_clears_embedding() from public, anon, authenticated;

drop trigger if exists trg_company_faq_text_change_clears_embedding on public.company_faq;
create trigger trg_company_faq_text_change_clears_embedding
  before update of question, answer on public.company_faq
  for each row execute function public.fn_company_faq_text_change_clears_embedding();

create or replace function public.fn_faq_concepts(p_text text, p_ar boolean)
 returns text[]
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  with fold(lexeme, concept) as (values
      ('fee','fee'),('charg','fee'),('cost','fee'),('price','fee'),('pay','fee'),('paid','fee'),('payment','fee'),
      ('much','fee'),('commiss','fee'),('free','fee'),('subscript','fee'),('expens','fee'),('cheap','fee'),
      ('رسوم','fee'),('رسم','fee'),('تكلف','fee'),('تكلفه','fee'),('سعر','fee'),('اسعار','fee'),('عمول','fee'),
      ('مجا','fee'),('دفع','fee'),('اشتر','fee'),
      ('supplier','supplier'),('vendor','supplier'),('contractor','supplier'),('مورد','supplier'),('موردين','supplier'))
  select coalesce(array_agg(distinct coalesce(f.concept, l)), '{}')
    from unnest(tsvector_to_array(case when p_ar then to_tsvector('arabic',
                    -- عرض سعر / عروض الأسعار is a quotation: its price word is not a fee.
                    regexp_replace(public.fn_ar_norm(coalesce(p_text, '')), '(عرض|عروض)\s+(ال)?(سعر|اسعار)', '\1', 'g'))
                                       else to_tsvector('english', coalesce(p_text, '')) end)) l
    left join fold f on f.lexeme = l
   where not (p_ar and l = any (array['كم','هل','ما','هي','هو','كيف','مع','في','من','على','عن','الي','او','لا','متي','ماذا','لماذا','اين','انا','نحن','انتم','لكم','لي']))
$function$;

revoke execute on function public.fn_faq_concepts(text, boolean) from public, anon, authenticated;

-- 4. THE FIVE NEAREST WERE NOT THE FIVE NEAREST, AND NOT THE RIGHT FIVE. company_faq_emb_idx was an ivfflat
--    index (lists = 20) read with the default probes = 1, so "order by embedding_gte <=> v limit 5" searched one
--    list of twenty. The table holds 638 rows: an exact scan is trivial, so the index goes. And the window of
--    five is now taken among records whose question shares a concept with the asker (fn_faq_answer below).
drop index if exists public.company_faq_emb_idx;

create or replace function public.fn_faq_answer(p_text text, p_min_rank numeric DEFAULT 0.15, p_embedding vector DEFAULT NULL::vector, p_min_similarity numeric DEFAULT 0.86)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_q tsquery; k_q text; k_a text; k_src text; k_rank numeric; v_tpl record; v_ar boolean; v_qc text[]; v_best numeric; v_kq int;
begin
  if p_text is null or length(btrim(p_text)) < 2 then
    return jsonb_build_object('answered', false, 'reason', 'input too short');
  end if;

  v_ar := p_text ~ '[؀-ۿ]';

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
    -- 22 SEP 2026 (DL-01): the Arabic body for an Arabic greeting. coalesce, not a second branch: an
    -- intent whose Arabic copy has not been written yet answers in English rather than in nothing.
    return jsonb_build_object('answered', true, 'source', 'template', 'key', v_tpl.key,
                              'answer', case when v_ar then coalesce(v_tpl.body_ar, v_tpl.body) else v_tpl.body end,
                              'lang', case when v_ar and v_tpl.body_ar is not null then 'ar' else 'en' end,
                              'confidence', 1.0);
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
               -- 23 Sep 2026: the five nearest are taken among records whose QUESTION shares a concept with
               -- the asker's. gte-small is an English model: for "كم رسومكم" the fee FAQ 609 (0.8816) ranked
               -- sixth behind five unrelated Arabic records, and the window of five dropped it.
               and public.fn_faq_concepts(f.question, v_ar) && v_qc
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

-- 3. THE ARABIC MIRRORS STILL PROMISED AUTOMATIC REDACTION. #872 corrected ids 16, 20, 116 and 126 in
--    English only; their Arabic mirrors 605, 663, 718 and 741 (source_note "Arabic mirror of company_faq
--    id N") still said identifying details are removed automatically, so an Arabic drawing question got
--    the claim the English was withdrawn for. Same meaning as the English text, guarded on the old
--    sentence; the trigger above clears their vectors as they change.
update public.company_faq set answer = regexp_replace(answer,
         'كما تُحجب تلقائي.. أي بيانات تعريفية من المخططات التي ترفعها.',
         'ولا يُشارَك مخططك مع الموردين إلا بعد تغطية بياناتك عليه (خانة العنوان واسمك وهاتفك وبريدك الإلكتروني)، وإذا تعذّرت تغطيتها لا يُشارَك المخطط، ويسعّر الموردون حينها على أساس نطاق العمل والكميات.'),
       updated_at = now()
 where id = 605 and answer like '%تُحجب تلقائي__ أي بيانات تعريفية%';
update public.company_faq set answer = replace(answer,
         'وتُنقّى المخططات تلقائيًا من أي تفاصيل تكشف الهوية قبل أن يطّلع عليها الموردون.',
         'ولا يُشارَك المخطط مع الموردين إلا بعد تغطية بياناتكم عليه (خانة العنوان واسمكم وهاتفكم وبريدكم الإلكتروني)؛ والمخطط الذي تتعذّر تغطيته لا يُشارَك، ويسعّر الموردون حينها على أساس نطاق العمل والكميات.'),
       updated_at = now()
 where id = 663 and answer like '%تُنقّى المخططات تلقائيًا%';
update public.company_faq set answer = replace(answer,
         'كما تُحجب تلقائيًا التفاصيل التعريفية من مخططات العميل قبل أن يراها أي مورّد.',
         'ولا يُشارَك مخطط العميل مع الموردين إلا بعد تغطية التفاصيل التعريفية عليه، والمخطط الذي تتعذّر تغطيته لا يُشارَك.'),
       updated_at = now()
 where id = 718 and answer like '%تُحجب تلقائيًا التفاصيل التعريفية%';
update public.company_faq set answer = replace(answer,
         'ويحجب تلقائيًا التفاصيل التي تكشف هويّتكم قبل أن يراه أي مورّد، فتبقون مجهولين.',
         'ولا يصل المخطط إلى الموردين إلا بعد تغطية بياناتكم عليه (خانة العنوان واسمكم وهاتفكم وبريدكم الإلكتروني)، فتبقون مجهولين؛ والمخطط الذي تتعذّر تغطيته لا يُشارَك.'),
       updated_at = now()
 where id = 741 and answer like '%ويحجب تلقائيًا التفاصيل%';

-- The five rows #872 rewrote without clearing their vectors. Guarded: only while the vector is set, so a
-- re-run after the re-embed would clear them again — run the embedder after every apply of this file.
update public.company_faq set embedding_gte = null
 where id in (16, 20, 116, 126, 289) and embedding_gte is not null;

-- PROOF (writes nothing — this file carries DDL, so it returns a verdict row instead of raising). The
-- trigger's behaviour on a real edit is proved by scripts/checks/an_edited_faq_answer_is_re_embedded.test.mjs
-- inside a transaction it never commits.
select case
  when not exists (select 1 from pg_trigger where tgname = 'trg_company_faq_text_change_clears_embedding' and tgenabled = 'O')
    then 'PROBE FAILED: trigger missing or disabled'
  when 'fee' = any (public.fn_faq_concepts('هل يمكنني رفض جميع عروض الأسعار؟', true))
    then 'PROBE FAILED: a quotation still reads as a fee'
  when not ('fee' = any (public.fn_faq_concepts('ما هي رسومكم', true)))
    then 'PROBE FAILED: a fee question lost its fee concept'
  when exists (select 1 from public.company_faq where id in (605, 663, 718, 741) and answer ~ 'تلقائي')
    then 'PROBE FAILED: an Arabic mirror still promises automatic redaction'
  when exists (select 1 from public.company_faq where id in (16, 20, 116, 126, 289) and embedding_gte is not null)
    then 'PROBE FAILED: a rewritten row kept its old vector'
  else 'PROBE OK' end as verdict;
