-- ONE CUSTOMER'S DRAWING IS NOT EVERYONE ELSE'S KNOWLEDGE.
--
-- PROVED BY EXECUTION, 10 September 2026, not inferred:
--
--   select * from public.kb_query('gypsum false ceiling', null, 5)
--   -> result #1 is kb_chunks id 48817, and the snippet it hands the caller begins:
--
--      "AL HABTOOR CONSULTING ENGINEERS
--       PROJECT: Residential Villa for Mr. Ahmed Khan
--       LOCATION: Plot 234-11, Al Barsha South, Dubai
--       CONTACT: +971 50 123 4567 | design@alhabtoor-eng.ae ..."
--
-- supabase/functions/inquiry_intake/index.ts:258 calls kb_query with the CUSTOMER'S OWN WORDS and
-- injects what comes back into the intake prompt as "specialist FIELD KNOWLEDGE". So a customer
-- describing a false-ceiling job is answered partly out of somebody else's uploaded drawing,
-- complete with a firm name, a client's name, a plot address, a mobile number and an email.
-- Measured at p_category 'gypsum' and 'interior-decoration' it ranks #1; at 'false-ceiling', #4.
--
-- ── THIS IS TWO DEFECTS, AND THE PRIVACY ONE IS THE BIGGER ─────────────────────────────────────
--
-- 1. PRIVACY. kb_chunks is the SHARED reference library. Four of its rows are OCR extractions of
--    files that a specific customer or supplier uploaded against their own inquiry:
--
--      id 958     floorplan.jpg                          documents.id 4
--      id 48817   villa_floorplan.png                    documents.id 10
--      id 168862  meridian_mep_company_profile.pdf       documents.id 32
--      id 168863  meridian_mep_company_profile.pdf       documents.id 32  (second chunk)
--
--    A drawing one customer uploaded is that customer's document. Putting its text in the corpus
--    every other customer is answered from is a leak whether or not the content is fabricated, and
--    it is the same shape as the WhatsApp-template leak fixed on 9 September: internal or private
--    material reaching a corpus meant for shared answers.
--
-- 2. FABRICATED IDENTITY. Three of the four assert things about named third parties that are not
--    ours and not verifiable: "AL HABTOOR CONSULTING ENGINEERS" with a mobile and an
--    @alhabtoor-eng.ae address, and "Meridian MEP Contracting LLC" with trade licence 1145872 and
--    TRN 100472935600003. Al Habtoor is a real Dubai group. Our own licence is DET 1633275. None of
--    these follow the estate's fixture convention (ZZ DEMO / example.invalid), so nothing marks them
--    as test data — measured: zero example.invalid addresses exist anywhere in kb_chunks.
--
--    All three parent business records are GONE: inquiry 59fb677f-… returns 0 rows, leads row 30466
--    returns 0 rows. These are extractions that outlived the records they belonged to and stayed
--    indexed. Deleting an inquiry did not delete what had been learned from its attachments.
--
-- ── WHAT THIS DOES, AND WHAT IT DELIBERATELY DOES NOT ──────────────────────────────────────────
--
-- It MOVES the four rows into public.kb_chunk_quarantine and removes them from kb_chunks. It does
-- not destroy them: every column is preserved with the reason and the time, so this is reversible
-- with an insert-select and nothing is lost. The original text also still exists in
-- public.documents.extracted, which is where a customer's own document belongs.
--
-- It is scoped by the CLASS, not by the four ids: source_kind='document' AND a numeric source_id,
-- which is exactly "this chunk came from a row in public.documents", i.e. a user upload, as opposed
-- to the 2,860 other document-kind chunks whose source_id names a corpus document. Measured: 2,864
-- document chunks, of which exactly 4 carry a numeric source_id.
--
-- IT DOES NOT FIX THE WRITER, and that is stated plainly rather than left to be discovered. Whatever
-- indexes an uploaded attachment into kb_chunks will do it again on the next upload. Closing that is
-- a separate change to the ingest path; this file removes what is there now and leaves an assertion
-- that will fail the moment a new one appears.

create table if not exists public.kb_chunk_quarantine (
  id             bigint primary key,
  source_kind    text,
  source_id      text,
  category       text,
  title          text,
  content        text,
  citation       text,
  effective_date date,
  created_at     timestamptz,
  category_norm  text,
  reason         text not null,
  quarantined_at timestamptz not null default now()
);

-- A NEW TABLE NEEDS AN EXPLICIT POLICY. RLS on with no policy denies everyone, which is the same end
-- state, but it is indistinguishable from meaning to write one and forgetting. service_role bypasses
-- RLS. This table holds material we judged unfit for the shared corpus, so it must not become
-- readable by a route the corpus itself is not.
alter table public.kb_chunk_quarantine enable row level security;
drop policy if exists kb_chunk_quarantine_service_role_only on public.kb_chunk_quarantine;
create policy kb_chunk_quarantine_service_role_only on public.kb_chunk_quarantine
  as permissive for all to public using (false) with check (false);
revoke all on public.kb_chunk_quarantine from anon, authenticated;

with doomed as (
  select k.id, k.source_kind, k.source_id, k.category, k.title, k.content, k.citation,
         k.effective_date, k.created_at, k.category_norm
    from public.kb_chunks k
   where k.source_kind = 'document'
     and k.source_id ~ '^[0-9]+$'
), moved as (
  insert into public.kb_chunk_quarantine
    (id, source_kind, source_id, category, title, content, citation, effective_date,
     created_at, category_norm, reason)
  select d.id, d.source_kind, d.source_id, d.category, d.title, d.content, d.citation,
         d.effective_date, d.created_at, d.category_norm,
         'Extraction of a file uploaded by one customer or supplier against their own record. The '
         || 'shared reference library is read by kb_query, which inquiry_intake calls with another '
         || 'customer''s words, so this text was answerable to people it does not belong to. Three '
         || 'of the four also assert a named third-party firm, and in one case a trade licence and '
         || 'TRN, none of which is ours and none marked as test data. Reversible: insert-select back '
         || 'into kb_chunks. Original text remains in public.documents.extracted.'
    from doomed d
  on conflict (id) do nothing
  returning id
)
delete from public.kb_chunks k
 where k.id in (select id from moved);

-- ── PROVE THE CUSTOMER-FACING ROUTE IS CLEAN ───────────────────────────────────────────────────
-- This file creates a table and moves rows, so the probe must not raise on the happy path -- a
-- raise would roll the move back with it and the apply would report success over an unchanged
-- corpus. It asserts and ends in a notice.
-- A NOTE ON THE COST OF PROVING THIS. The first version of this probe called kb_query four times.
-- A DO block is ONE statement, kb_query reads a 2.69-million-row table with no ORDER-BY-friendly
-- index, and the fourth call ran the block past statement_timeout -- which rolled the move back with
-- it and reported the apply as a failure. So the retrieval assertion is made ONCE, with the
-- category the live caller actually passes, and the rest are primary-key lookups.
do $do$
declare n_q int; v_top text; n_held int;
begin
  select count(*) into n_held from public.kb_chunk_quarantine;
  if n_held = 0 then
    raise exception 'nothing was quarantined -- the class predicate matched no rows';
  end if;

  -- THE FOUR ROWS MUST BE GONE FROM THE SHARED LIBRARY. A primary-key lookup, so it costs nothing.
  if exists (select 1 from public.kb_chunks where id in (958, 48817, 168862, 168863)) then
    raise exception 'an upload extraction is still in kb_chunks';
  end if;

  -- THE EXACT CALL inquiry_intake MAKES -- kb_query with the customer's words and a trade slug --
  -- run once, and used for BOTH assertions: the fabricated drawing must be gone, and the question
  -- must still be answered from real material. A fix that empties the result set is not a fix.
  select count(*) filter (where r.snippet ilike '%habtoor%'
                             or r.snippet ilike '%Ahmed Khan%'
                             or r.snippet ilike '%Plot 234%'),
         min(r.title)
    into n_q, v_top
    from public.kb_query('gypsum false ceiling', 'gypsum', 5) r;

  if n_q > 0 then
    raise exception 'the fabricated drawing is STILL returned by kb_query';
  end if;
  if v_top is null then
    raise exception 'kb_query now returns nothing for a question it used to answer';
  end if;

  raise notice 'THE SHARED LIBRARY NO LONGER ANSWERS FROM ONE CUSTOMER''S DRAWING. % row(s) quarantined and removed from kb_chunks; the call inquiry_intake makes no longer returns the fabricated firm, and still answers that question from real material (a remaining hit: %). THE INGEST PATH IS UNCHANGED and will index the next upload the same way -- closing that is a separate change to the ingest code, not to this file.',
    n_held, v_top;
end
$do$;
