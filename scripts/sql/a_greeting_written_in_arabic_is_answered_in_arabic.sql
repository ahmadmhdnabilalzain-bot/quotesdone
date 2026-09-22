-- A GREETING WRITTEN IN ARABIC IS ANSWERED IN ARABIC (22 Sep 2026, documents-language audit DL-01).
--
-- SEAT: customer_support. One column, thirteen data rows, one routine:
-- public.fn_faq_answer(text, numeric, vector, numeric). No new table, no grant change.
--
-- MEASURED on production 22 Sep 2026, before this file (aborted-transaction probe of the live routine,
-- scratchpad/audit/documents-language/faq_probe.sql):
--   fn_faq_answer('مرحبا')      -> {"answered":true,"source":"template","key":"greeting",
--                                   "answer":"Hello, and thanks for contacting QuotesDone. ..."}
--   fn_faq_answer('شكرا جزيلا') -> {"answered":true,"source":"template","key":"thanks",
--                                   "answer":"Happy to help. Anything else you need?"}
-- WHY. Step 1 of fn_faq_answer matches the fixed intents in BOTH languages — the Arabic branch of the
-- greeting and thanks patterns is deliberate — and then returns response_template.body, which exists in
-- English only. So the one path the routine takes before any retrieval was the one path that could not
-- speak Arabic: the first word of the first Arabic conversation on the widget, the site assistant and
-- WhatsApp was English. greeting has been served 4 times and thanks 3.
--
-- CHANGES
--   1. response_template.body_ar, nullable. An intent with no Arabic copy keeps falling back to body,
--      so a future row cannot silently return nothing.
--   2. The Arabic copy for the only two intents that are reachable (see 3), written as Gulf business
--      Arabic and not as a translation of the English line.
--   3. The eleven never-selected rows are DEACTIVATED. They are unreachable — step 1 tests exactly two
--      intents, greeting and thanks — and every one of them promises something this product does not
--      do: an order being tracked, a delivery stage, appointment slots that are "actually open", a
--      shipping movement, payment instructions on an invoice we do not issue for an order. If one were
--      ever wired up it would answer a customer with a capability the company does not have. Their text
--      stays in the table (active = false) so the decision is legible rather than deleted; used_count is
--      0 on all eleven, so nothing that ever answered anybody is being switched off.
--   4. fn_faq_answer returns the Arabic body when the asker wrote Arabic. v_ar is already computed one
--      line above the template step; nothing else in the routine changes — not the keyword step, not the
--      corroborated semantic step, not the supplier-side rule, not a single FAQ row.
--
-- PROVED BY: the probe at the foot of this file. This file carries DDL, so the probe CLEANS UP AFTER
-- ITSELF and ends in `raise notice` (a `raise exception` here would roll back the column and the
-- routine with it). fn_faq_answer only reads and bumps a counter, so the probe can reach no person; it
-- restores used_count for the two keys it touches and asserts the restore.
--
--   node scripts/apply_sql.mjs scripts/sql/a_greeting_written_in_arabic_is_answered_in_arabic.sql --apply --ddl

-- 1. the column ------------------------------------------------------------------------------------
alter table public.response_template add column if not exists body_ar text;
comment on column public.response_template.body_ar is
  'The Arabic copy of body, written in Gulf business Arabic (instruction 586). NULL means no Arabic copy: fn_faq_answer falls back to body rather than answering with nothing.';

-- 2. the Arabic copy of the two reachable intents ---------------------------------------------------
update public.response_template
   set body_ar = 'أهلًا وسهلًا، ونشكر لكم تواصلكم مع QuotesDone. يُرجى إخبارنا بالعمل الذي تحتاجون عرض سعر له، وسنتولى الباقي.'
 where key = 'greeting';
update public.response_template
   set body_ar = 'يسعدنا ذلك دائمًا. هل من أمر آخر نساعدكم فيه؟'
 where key = 'thanks';

-- 3. the eleven the routine cannot reach, and must not promise ---------------------------------------
update public.response_template
   set active = false
 where key not in ('greeting', 'thanks') and active and used_count = 0;

-- 4. the routine: the asker's language decides which body comes back ---------------------------------
create or replace function public.fn_faq_answer(p_text text, p_min_rank numeric default 0.15, p_embedding vector default null::vector, p_min_similarity numeric default 0.86)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
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

-- PROOF, and it puts back what it borrowed --------------------------------------------------------
do $probe$
declare
  a jsonb; b jsonb; c jsonb; g0 int; t0 int; g1 int; t1 int; n_active int;
begin
  select used_count into g0 from public.response_template where key = 'greeting';
  select used_count into t0 from public.response_template where key = 'thanks';

  a := public.fn_faq_answer('مرحبا');
  b := public.fn_faq_answer('شكرا جزيلا');
  c := public.fn_faq_answer('hello');

  if (a->>'answer') !~ '[؀-ۿ]' then raise exception 'PROBE FAILED: an Arabic greeting still answers in English: %', a->>'answer'; end if;
  if (b->>'answer') !~ '[؀-ۿ]' then raise exception 'PROBE FAILED: an Arabic thanks still answers in English: %', b->>'answer'; end if;
  if (c->>'answer') ~ '[؀-ۿ]' then raise exception 'PROBE FAILED: an English greeting answered in Arabic: %', c->>'answer'; end if;
  if (c->>'answer') not like 'Hello, and thanks for contacting QuotesDone%' then raise exception 'PROBE FAILED: the English greeting changed: %', c->>'answer'; end if;

  select count(*) into n_active from public.response_template where active;
  if n_active <> 2 then raise exception 'PROBE FAILED: % active templates, expected exactly greeting and thanks', n_active; end if;

  -- put the counters back: the probe answered nobody, so it must leave no evidence that it did.
  update public.response_template set used_count = g0 where key = 'greeting';
  update public.response_template set used_count = t0 where key = 'thanks';
  select used_count into g1 from public.response_template where key = 'greeting';
  select used_count into t1 from public.response_template where key = 'thanks';
  if g1 <> g0 or t1 <> t0 then raise exception 'PROBE FAILED: used_count not restored (% -> %, % -> %)', g0, g1, t0, t1; end if;

  raise notice 'PROBE OK — ar greeting/thanks answer in Arabic, en greeting unchanged, 2 active templates, used_count restored (% / %)', g0, t0;
end $probe$;
