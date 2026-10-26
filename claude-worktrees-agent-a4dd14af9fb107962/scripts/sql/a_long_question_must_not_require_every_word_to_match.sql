-- A LONG QUESTION MUST NOT REQUIRE EVERY WORD TO MATCH
--
-- MEASURED FIRST, then changed. The CEO retrieval evaluation over the pack's own 32 development
-- scenarios scored 0 of 32 -- not 32 wrong answers, but 32 queries that returned NOTHING AT ALL:
--
--   HIT 0 · PARTIAL 0 · MISS 0 · NO_COVERAGE 32 · full-hit rate 0.0%
--
-- The cause is websearch_to_tsquery's AND semantics. It is the right default for a short, deliberate
-- search: "cash commitments runway" should return records about all three. But a CEO does not arrive
-- with three words. A real question is a paragraph -- "Target 120 newly activated suppliers in 20
-- days. Registration rate 25%; activation conditional on registration 40%..." -- and requiring every
-- lexeme in a forty-word paragraph to appear in one record means no record can ever match. The
-- retrieval was not ranking badly; it was answering a question nobody could satisfy.
--
-- This is the failure mode the whole store was built to avoid, arriving from the other direction: an
-- empty result reads as "the pack has no guidance on this", when the truth was "the query demanded
-- the impossible". fn_ceo_context would have reported INSUFFICIENT CONTEXT with perfect confidence
-- on all 32.
--
-- THE FIX KEEPS PRECISION AND ADDS REACH. The strict AND query runs first and is preferred, so short
-- deliberate searches behave exactly as before and lose nothing. Only when it returns NOTHING does
-- the function fall back to an OR over the query's own lexemes, ranked -- so the paragraph finds the
-- records that share the most of its meaningful words rather than none.
--
-- The fallback is REPORTED, not hidden: matched_how says 'all_terms' or 'best_terms', because a
-- caller deserves to know whether it got a precise match or the closest thing available.
-- The return type gains matched_how, and Postgres will not change a function's OUT parameters in
-- place, so the old signature is dropped first. Both callers -- fn_ceo_context below and the
-- evaluation harness -- are updated in the same change.
drop function if exists public.fn_ceo_knowledge_search(text,int,text,text);

create or replace function public.fn_ceo_knowledge_search(
  p_query text,
  p_limit int default 8,
  p_kind  text default null,
  p_domain text default null)
returns table(
  record_id text, record_version text, record_kind text, title text, domain text,
  body text, body_sha256 text, source_ids text[], source_path text,
  review_status text, authority_effect text, contains_synthetic_example boolean,
  requires_current_verification boolean, relevance real, matched_how text, warning text)
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_q     tsquery;
  v_lex   text[];
  v_found boolean := false;
  v_how   text := 'all_terms';
begin
  if coalesce(btrim(p_query), '') = '' then
    return;  -- an empty query retrieves nothing rather than everything
  end if;

  -- PASS 1: every term. Precise, and unchanged from before.
  v_q := websearch_to_tsquery('english', p_query);
  if v_q is not null then
    select exists (select 1 from public.ceo_knowledge k
                    where k.runtime_index_eligible and k.search @@ v_q
                      and (p_kind is null or k.record_kind = p_kind)
                      and (p_domain is null or k.domain = p_domain))
      into v_found;
  end if;

  -- PASS 2: the best terms. Only when pass 1 found nothing, so precision is never traded away --
  -- it is only used where the alternative is an empty answer.
  if not v_found then
    v_lex := tsvector_to_array(to_tsvector('english'::regconfig, p_query));
    if v_lex is null or array_length(v_lex, 1) is null then
      return;
    end if;
    -- Lexemes are already normalised and stripped of stop words by to_tsvector. Quoting each one
    -- keeps a lexeme containing punctuation from being parsed as an operator.
    begin
      v_q := to_tsquery('english'::regconfig,
                        array_to_string(array(select '''' || replace(x, '''', '''''') || '''' from unnest(v_lex) x), ' | '));
    exception when others then
      return;  -- an unparseable query returns nothing rather than an error the caller cannot act on
    end;
    v_how := 'best_terms';
  end if;

  return query
  select k.record_id, k.record_version, k.record_kind, k.title, k.domain,
         k.body, k.body_sha256, k.source_ids, k.source_path,
         k.review_status, k.authority_effect, k.contains_synthetic_example,
         k.requires_current_verification,
         ts_rank(k.search, v_q) as relevance,
         v_how as matched_how,
         'Advisory only. authority_effect=none: this may not approve an action, change a target or '
         || 'become policy. review_status=' || k.review_status || '. '
         || case when v_how = 'best_terms'
                 then 'MATCHED ON BEST TERMS, not all of them -- read the title before relying on it. ' else '' end
         || case when k.contains_synthetic_example
                 then 'CONTAINS A SYNTHETIC EXAMPLE -- it is authored, not QuotesDone experience. ' else '' end
         || case when k.requires_current_verification
                 then 'REQUIRES CURRENT VERIFICATION against an authoritative company source. ' else '' end
         || 'Current company facts come from the application, never from this record.' as warning
    from public.ceo_knowledge k
   where k.runtime_index_eligible
     and k.search @@ v_q
     and (p_kind is null or k.record_kind = p_kind)
     and (p_domain is null or k.domain = p_domain)
   order by ts_rank(k.search, v_q) desc, k.record_id
   limit greatest(1, least(coalesce(p_limit, 8), 50));
end $function$;

comment on function public.fn_ceo_knowledge_search(text,int,text,text) is
  'Lexical retrieval over the CEO knowledge pack. Tries every term first, then falls back to the best terms only when the strict query returns nothing, and says which it did in matched_how. relevance is a ranking score and NEVER a probability that the content is true.';

-- fn_ceo_context selects from the search function by name, so it inherits the fallback. Its column
-- list is restated here only because the function's return type gained matched_how, and a caller
-- that selected * would otherwise break.
create or replace function public.fn_ceo_context(
  p_query text,
  p_max_chars int default 18000,
  p_limit int default 8)
returns jsonb
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $function$
declare
  r record;
  v_out jsonb := '[]'::jsonb;
  v_used int := 0;
  v_n int := 0;
  v_how text := null;
begin
  for r in select * from public.fn_ceo_knowledge_search(p_query, p_limit) loop
    exit when v_used + length(r.body) > greatest(2000, p_max_chars);
    v_how := coalesce(v_how, r.matched_how);
    v_out := v_out || jsonb_build_object(
      'record_id', r.record_id, 'record_kind', r.record_kind, 'title', r.title,
      'domain', r.domain, 'body', r.body, 'body_sha256', r.body_sha256,
      'source_ids', to_jsonb(r.source_ids), 'source_path', r.source_path,
      'review_status', r.review_status, 'authority_effect', r.authority_effect,
      'relevance', r.relevance, 'matched_how', r.matched_how, 'warning', r.warning);
    v_used := v_used + length(r.body);
    v_n := v_n + 1;
  end loop;

  return jsonb_build_object(
    'query', p_query,
    'records', v_out,
    'record_count', v_n,
    'chars_used', v_used,
    'matched_how', v_how,
    'sufficient', v_n > 0,
    'signal', case when v_n = 0
                   then 'INSUFFICIENT CONTEXT -- nothing in the CEO knowledge pack matched this query. Say so rather than answering from memory.'
                   when v_how = 'best_terms'
                   then 'Advisory context, matched on the best terms rather than all of them. Read each title before relying on it. Company facts, targets, budgets and permissions must be read from the application, not from these records.'
                   else 'Advisory context only. Company facts, targets, budgets and permissions must be read from the application, not from these records.' end,
    'pack_fingerprint', (select max(pack_fingerprint) from public.ceo_knowledge));
end $function$;
