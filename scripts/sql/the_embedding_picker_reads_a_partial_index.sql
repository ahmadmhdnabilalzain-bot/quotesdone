-- THE EMBEDDING PICKER READS A PARTIAL INDEX (6 Sep 2026). Follows the_embedding_picker_orders_on_the_index.sql.
--
-- MEASURED at 10:43Z, one hour after that file: kb_embed timed out again at its select stage, under
-- the load of seven parallel sessions and a CI kernel gate. EXPLAIN of the oldest-first pick, idle:
--   Index Scan Backward using kb_chunks_created_at_desc_idx ... Rows Removed by Filter: 99466,
--   Buffers: shared hit=34280, 98 ms.
-- The backfill embeds oldest-first, so every success lengthens the embedded prefix the next pick has
-- to walk past before it meets an un-embedded row: 100,623 embedded today and growing by ~60 a
-- minute. Idle that is a tenth of a second; under load it is the 8 s PostgREST wall, and the picker
-- gets slower with every row it succeeds on. The existing partial index
-- kb_chunks_unembedded_cat_created_idx leads on category, so it cannot serve ORDER BY created_at.
--
-- This index holds only the un-embedded rows in created_at order; both branches of
-- fn_kb_embed_claim (oldest-first and newest-first) become a bounded index scan whose cost no
-- longer depends on how much has already been embedded. Built CONCURRENTLY, in one statement, so
-- kb_chunks writers (the embedder itself, the importers) are never blocked; the apply tool sends a
-- file as one query, and a single CREATE INDEX CONCURRENTLY statement is not a transaction block.
--
--   node scripts/apply_sql.mjs scripts/sql/the_embedding_picker_reads_a_partial_index.sql --apply --ddl
--   (then: select indisvalid from pg_index where indexrelid = 'public.kb_chunks_unembedded_created_idx'::regclass;)

create index concurrently if not exists kb_chunks_unembedded_created_idx
  on public.kb_chunks using btree (created_at)
  where embedding_gte is null;
