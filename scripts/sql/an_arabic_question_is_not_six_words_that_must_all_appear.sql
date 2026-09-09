-- AN ARABIC QUESTION IS NOT SIX WORDS THAT MUST ALL APPEAR.
--
-- Arabic retrieval was built and proved earlier today, and it worked on every phrase it was tested
-- with. It returned NOTHING for the first real question I asked it over HTTP:
--
--     "ما هي رسوم الكشف عن المورد؟"   (what is the supplier reveal fee?)
--
-- Measured, on production:
--
--   websearch_to_tsquery('arabic', …)  ->  'ما' & 'هي' & 'رسوم' & 'كشف' & 'عن' & 'مورد'
--   rows matching ALL six                ->  0
--   rows matching the SAME lexemes OR'd  ->  18
--   to_tsvector('arabic', 'ما هي عن')    ->  'ما':1 'هي':2 'عن':3
--
-- That last line is the whole defect. Postgres's `arabic` configuration has NO STOPWORD LIST — the
-- English config throws away "what", "is" and "about" before they ever reach the query, and the
-- Arabic one keeps ما, هي and عن as ordinary lexemes. `websearch_to_tsquery` ANDs everything it is
-- given, so an Arabic question is a demand that one record contain every filler word in it. The
-- shorter the test phrase, the more likely it passes: "رسوم الكشف" matches 11 rows, and the full
-- question matches none. That is why this shipped looking correct.
--
-- THE ESTATE ALREADY KNEW THIS. fn_accountant_assist and fn_ceo_knowledge_search both run all-terms
-- first and fall back to an OR of the lexemes, tagged so the caller knows the match was weaker.
-- fn_accountant_assist's own header records the measurement that forced it: 9 of 35 real questions
-- scored ts_rank exactly 0.0000 against the correct record. The same fix, not a new idea — and the
-- English arm needs it for the same reason, which is why it is applied to both.
--
-- WHY THE FALLBACK IS SECOND AND NOT INSTEAD. An OR match is genuinely weaker: it will return a
-- record that shares one common word. So all-terms runs first and wins on rank; the OR pass only
-- supplies rows when the strict pass found none, and it is ranked BELOW any strict hit by
-- construction (its rank is multiplied down). A caller cannot mistake one for the other.
--
-- WHAT IS NOT FIXED HERE: cross-script retrieval. An Arabic question sharing no lexeme with any
-- record still returns nothing, because lexical search cannot bridge scripts. That needs Arabic
-- content, and 22 rows exist today against 250 public English ones.

create or replace function public.fn_support_corpus_search(p_query text, p_public boolean, p_limit integer default 8)
 returns table(src text, src_id text, title text, content text, citation text, rank real)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
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
     where (case when p_public then c.is_public else true end)
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
$function$;

do $do$
declare
  v_ar_full int; v_ar_short int; v_en int; v_en_before int; v_first text;
begin
  -- THE QUESTION THAT FAILED. It must now return rows.
  select count(*) into v_ar_full from public.fn_support_corpus_search('ما هي رسوم الكشف عن المورد؟', true, 6);
  if v_ar_full = 0 then
    raise exception 'the natural Arabic question still returns nothing — the fallback did not engage';
  end if;

  -- And the top row must be an Arabic one, not an English row scraping in on a shared token.
  select title into v_first from public.fn_support_corpus_search('ما هي رسوم الكشف عن المورد؟', true, 1);
  if v_first !~ '[؀-ۿ]' then
    raise exception 'the best Arabic answer is an English record: %', v_first;
  end if;

  -- The short phrase that always worked must be UNCHANGED — the strict pass still owns it.
  select count(*) into v_ar_short from public.fn_support_corpus_search('رسوم الكشف', true, 6);
  if v_ar_short = 0 then raise exception 'the short Arabic phrase regressed to zero'; end if;

  -- ENGLISH IS THE CONTROL. A change that improves Arabic by degrading English is not a fix.
  select count(*) into v_en from public.fn_support_corpus_search('what is the 3% reveal fee', true, 6);
  if v_en = 0 then raise exception 'English retrieval returned nothing'; end if;
  select title into v_first from public.fn_support_corpus_search('what is the 3% reveal fee', true, 1);
  if v_first ~ '[؀-ۿ]' then
    raise exception 'an English question now answers in Arabic: %', v_first;
  end if;

  -- NEGATIVE CONTROL: nonsense must still return nothing. A fallback that answers everything is
  -- worse than one that answers too little.
  if (select count(*) from public.fn_support_corpus_search('zorblax quantum flibbertigibbet', true, 6)) > 0 then
    raise exception 'the loose pass answered a nonsense question — it is matching on nothing';
  end if;

  raise notice 'ARABIC ANSWERS A REAL QUESTION NOW. Full question % rows (was 0), short phrase % rows, English control % rows, nonsense 0. Cause: the arabic text-search config has no stopword list, so websearch_to_tsquery AND-ed ما/هي/عن as content words.',
    v_ar_full, v_ar_short, v_en;
end
$do$;
