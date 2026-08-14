-- V3 REMEDIATION — STAGE 4 (continued): THE QUERY BUILDER
--
-- Fixing the dead `or true` in fn_context_slice exposed the defect underneath it, and this one is
-- the actual cause of KNOWLEDGE_NOT_RETRIEVED (1,706 questions).
--
-- MEASURED ON STAGING, 14 Aug 2026:
--   websearch_to_tsquery('english','cash reserve budget variance')
--     = 'cash' & 'reserv' & 'budget' & 'varianc'          <- AND across every word
--   rows matching that, in finance's own department layer :   0   (of 170 scoped, 8,256 total)
--   the same words ORed                                   :  49
--
-- fn_agent_context_v3 builds its task query with websearch_to_tsquery over the WHOLE TASK
-- SENTENCE. A task description is a sentence, not a search box: requiring every stemmed word to
-- co-occur in one knowledge record matches essentially nothing, every time. `tsv` is populated on
-- all 8,256 rows — the corpus was never the problem.
--
-- That explains the shape of the failure exactly. Retrieval returned nothing, so `or true` was
-- added to fn_context_slice to keep context non-empty; the tautology then made the query
-- irrelevant, and the runtime settled into fetching 46 records per call that were selected by
-- nothing at all. Two defects, each hiding the other.
--
-- THE FIX IS THE PATTERN THIS CODEBASE ALREADY USES. fn_ops_knowledge_search and
-- fn_dept_library_search both build `word | word | word` and rank by ts_rank — they work, and they
-- have worked all along. fn_agent_context_v3 is the one that reached for websearch_to_tsquery.

begin;

-- ---------------------------------------------------------------------------------------------
-- One place that turns a task sentence into a query, so the three retrieval paths cannot drift.
-- OR for membership, ts_rank for order: a record needs one meaningful term to be a candidate and
-- earns its position by how many it carries.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_task_tsquery(p_text text)
returns tsquery
language plpgsql immutable set search_path = public as $$
declare v_words text[]; v_q tsquery;
begin
  if p_text is null or btrim(p_text) = '' then return null; end if;

  -- Lexemes the text actually contains, after stemming and stop-word removal. Using to_tsvector
  -- rather than a hand-rolled split means the stop-word list is Postgres's own and the stems match
  -- the ones in the stored tsv, which is the whole point.
  select array_agg(distinct lexeme) into v_words
    from unnest(to_tsvector('english', left(p_text, 4000))) t(lexeme, positions, weights)
   where length(lexeme) > 2;

  if v_words is null or array_length(v_words, 1) = 0 then return null; end if;

  -- Cap the term count. A 60-word task ORed in full ranks almost the whole corpus as a weak match
  -- and the budget window then keeps whatever sorts first, which is the failure we are leaving.
  if array_length(v_words, 1) > 24 then v_words := v_words[1:24]; end if;

  v_q := to_tsquery('english', array_to_string(v_words, ' | '));
  return v_q;
exception when others then
  -- A malformed lexeme must degrade to "no query" (and therefore to labelled fallback), never to
  -- an exception that takes the agent's whole context down with it.
  return null;
end $$;
revoke all on function public.fn_task_tsquery(text) from public;
grant execute on function public.fn_task_tsquery(text) to service_role;

commit;
