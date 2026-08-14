-- A 198,000-CHARACTER FAQ IN A PROMPT SLOT THAT HOLDS 24,000.
--
-- the_highest_priority_knowledge_row_reaches_nobody.sql made LAYER 1 truncate instead of drop, so
-- "Company FAQ (canonical answers)" — 197,956 chars, priority 96, the highest global row there is —
-- finally appears in fn_agent_context's output. Then I measured the CAPPED context that agent_brain
-- actually sends, and it is still absent:
--
--     select position('Company FAQ (canonical answers)' in fn_agent_context_capped('procurement',24000,'…'))
--     -- 0
--
-- The FAQ's first 1,500 characters now land at roughly position 19,400 of the standing context, and
-- the head is cut at 19,500. It is on the boundary, and chasing it with a bigger budget would be
-- the wrong fix twice over: it would raise every employee's token bill to deliver 1,500 characters
-- of an arbitrary 198,000, and the 1,500 delivered would be whichever questions happen to sort
-- first — not the ones the employee was asked about.
--
-- A STANDING PROMPT IS THE WRONG HOME FOR THIS AND ALWAYS WAS.
-- The FAQ is 484 sections, each a question and a founder-approved canonical answer, averaging ~409
-- characters. That is not one document, it is 484 retrievable facts — and agent_brain ALREADY runs
-- a relevance-ranked retrieval on every single turn (retrieve() -> kb_search, hybrid kb_match +
-- full-text with RRF, top 10). The right delivery mechanism has been running all along; the FAQ was
-- simply never put where it could reach it.
--
-- Measured before this change: kb_chunks carried 11 rows with a FAQ category or citation, against
-- 484 sections. The canonical core (`canon:core`) is there and retrievable, so employees were not
-- flying blind — but 473 founder-approved answers were reachable by neither retrieval nor prompt.
--
-- WHAT THIS DOES. Splits the FAQ on its own '## ' section boundaries and inserts one kb_chunk per
-- question, so kb_search returns the two or three answers relevant to what was actually asked
-- instead of the prompt carrying a fixed slice of all of them. Embedding is left to the existing
-- kb_embed path (in-region gte-small, free); until a row is embedded it is still reachable by
-- full-text, which is the half of kb_search's hybrid that does not need a vector.
--
-- IDEMPOTENT. kb_chunks has only a primary key on id — no natural key — so this adds a PARTIAL
-- unique index on source_id restricted to source_kind='company_faq'. Partial on purpose: a global
-- unique index on (source_kind, source_id) would have to hold for all 96,974 existing rows, which
-- was neither measured nor asked for, and source_id is nullable across the rest of the table.
-- Re-running this file then replaces sections rather than duplicating them, and clears the
-- embedding only on rows whose text actually changed.
--
-- THE agent_knowledge ROW IS NOT DELETED. It stays as the canonical source of record, and LAYER 1
-- keeps its now-truncating 1,500-character head of it, which is a reasonable "this exists, ask for
-- it" pointer. Deleting the source to save prompt tokens would be destroying the artefact to tidy
-- its shadow.

create unique index if not exists kb_chunks_company_faq_source_id
  on kb_chunks (source_id) where source_kind = 'company_faq';

with faq as (
  select content from agent_knowledge
   where agent_key = '_global' and topic = 'Company FAQ (canonical answers)'
   limit 1
), parts as (
  select i, btrim(s) body
    from faq, lateral unnest(string_to_array(faq.content, E'\n## ')) with ordinality t(s, i)
   where i > 1 and length(btrim(s)) > 40          -- i=1 is the preamble, not a question
), shaped as (
  select i,
         left(split_part(body, E'\n', 1), 300) question,
         body
    from parts
)
insert into kb_chunks (source_kind, source_id, category, title, content, citation, effective_date)
select 'company_faq',
       'company_faq#' || lpad(i::text, 4, '0'),
       '_global',
       question,
       '## ' || body,
       'QuotesDone Company FAQ — founder-approved canonical answer. Answer consistently with this; do not contradict it or invent beyond it.',
       current_date
  from shaped
on conflict (source_id) where source_kind = 'company_faq' do update
  set title = excluded.title,
      content = excluded.content,
      citation = excluded.citation,
      category = excluded.category,
      effective_date = excluded.effective_date,
      embedding_gte = case when kb_chunks.content is distinct from excluded.content
                           then null else kb_chunks.embedding_gte end;
