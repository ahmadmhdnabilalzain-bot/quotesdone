-- DEPLOY THE CORPUS INTO THE TABLE THE PRODUCT ACTUALLY READS.
--
-- kb_stage.records holds all 115,148 pack records and exactly ONE consumer reads it: the database
-- function fn_kb_retrieve. Everything a customer touches reads kb_chunks instead —
--   kb_search       -> kb_chunks (websearch FTS) and kb_match (vector)
--   agent_brain     -> kb_chunks
--   inquiry_intake  -> kb_chunks, and its own comment records that grepping kb_stage across the
--                      edge functions "returned exactly one file, its own importer"
-- — and kb_chunks held 5,139 rows of a DIFFERENT corpus with zero QD-KB records. So the six packs
-- were imported and were not reachable by the product. That is what "still in staging" meant, and
-- the schema being NAMED kb_stage is exactly how it stayed hidden behind a green import.
--
-- The existing 5,139 rows carry duplicate (source_kind, source_id) pairs of their own — for
-- instance ('library','engineering') — so the uniqueness this import needs is scoped to its own
-- rows with a partial index and the older corpus is left exactly as it is.
--
-- source_id carries the pack's own stable record_id, so this is idempotent: a re-run updates in
-- place rather than duplicating. fts and category_norm are generated columns and fill themselves.
-- embedding_gte is left NULL on purpose: kb_search falls back to full-text search, which works
-- today, and kb_embed_backfill can populate vectors later as a separate spend decision.
create unique index if not exists kb_chunks_qdkb_source_uidx
  on public.kb_chunks (source_id) where source_kind = 'qd_kb_pack';

insert into public.kb_chunks (source_kind, source_id, category, title, content, citation, effective_date)
select 'qd_kb_pack',
       r.record_id,
       r.category_slug,
       left(r.title, 500),
       r.content,
       r.package_id || ' · ' || r.category_slug || ' / ' || r.subcategory_slug ||
         ' · ' || r.module || coalesce(' · ' || nullif(btrim(r.authority), ''), '') ||
         ' (QD-KB v2026.07.31)',
       case when r.effective_date ~ '^\d{4}-\d{2}-\d{2}$' then r.effective_date::date else null end
  from kb_stage.records r
 where coalesce(btrim(r.content), '') <> ''
on conflict (source_id) where source_kind = 'qd_kb_pack'
do update set category       = excluded.category,
              title          = excluded.title,
              content        = excluded.content,
              citation       = excluded.citation,
              effective_date = excluded.effective_date;
