-- THE CORPUS HAS TO ANSWER AN ARABIC QUESTION, and the first version could not.
--
-- fn_support_corpus_search was written with to_tsvector('english', ...) on both sides. Tested live
-- against the deployed widget:
--
--     "what happens if a supplier does not respond after I paid to reveal them?"  -> grounded answer
--     "ما هي رسوم الكشف؟"  (what is the reveal fee?)                              -> canned deflection
--
-- The English configuration stems and stop-words English. Against Arabic it produces no usable
-- lexemes, so the query matched nothing, the corpus contributed nothing, and the model fell back to
-- the contact-us line. This is a UAE marketplace whose own site ships in Arabic and English; an
-- Arabic visitor getting "I can help with questions about how QuotesDone works" instead of the answer
-- is the product failing quietly, which is the worst way for it to fail.
--
-- THE FIX IS A UNION OF TWO CONFIGURATIONS, not a swap. 'simple' tokenises on word boundaries with no
-- stemming and no stop-word list, so it handles Arabic, French, a product code or a phone number.
-- 'english' keeps the stemming that makes "refunds" find "refund" for the English half of the
-- corpus. A row matches if EITHER matches, and its rank is the better of the two. Swapping to
-- 'simple' alone would have fixed Arabic by making English retrieval measurably worse.
--
--   node scripts/apply_sql.mjs scripts/sql/the_corpus_answers_in_arabic_too.sql --apply --ddl

begin;

create or replace function public.fn_support_corpus_search(
  p_query text,
  p_public boolean,
  p_limit int default 8
) returns table (src text, src_id text, title text, content text, citation text, rank real)
language sql
stable
security definer
set search_path to 'public'
as $fn$
  with q as (
    select websearch_to_tsquery('english', coalesce(p_query, '')) as qe,
           websearch_to_tsquery('simple',  coalesce(p_query, '')) as qs
  ),
  hay as (
    select c.src, c.src_id, c.title, c.content, c.citation, c.is_public,
           to_tsvector('english', coalesce(c.title,'') || ' ' || coalesce(c.content,'')) as te,
           to_tsvector('simple',  coalesce(c.title,'') || ' ' || coalesce(c.content,'')) as ts
      from public.v_support_corpus c
     where (case when p_public then c.is_public else true end)
  )
  select h.src, h.src_id, h.title, h.content, h.citation,
         greatest(ts_rank(h.te, q.qe), ts_rank(h.ts, q.qs)) as rank
    from hay h, q
   where h.te @@ q.qe or h.ts @@ q.qs
   order by rank desc
   limit greatest(1, least(coalesce(p_limit, 8), 25))
$fn$;

commit;
