-- THE PRIORITY PICK READS ITS OWN INDEX (6 Sep 2026). Follows the_embedding_picker_reads_a_partial_index.sql.
--
-- MEASURED at 20:49:12Z by sampling pg_stat_activity around the hourly kb_embed timeout: the only
-- active statement was fn_kb_embed_claim, eight seconds into IO DataFileRead. EXPLAIN of the
-- priority-kinds pick (job 271: source_kind in company_faq/trade/regulation/material, oldest first):
--   Index Scan using kb_chunks_unembedded_created_idx ... Rows Removed by Filter: 2,561,789
--   Buffers: shared hit=202,172 read=370,481 ... Execution Time: 23,407 ms
-- against 49 buffers and 1.5 ms for the plain pick. The partial index on created_at cannot filter by
-- kind, so every minute that job walked the whole un-embedded set and read 370k pages from disk to
-- find the four regulation rows still waiting; through PostgREST it hit the 8 s wall, and its reads
-- evicted the cache the other picks depend on — the select-stage timeouts the error ledger records at
-- HH:49 every hour since 14:49Z.
--
-- This index holds the un-embedded rows by (source_kind, created_at), so the priority pick is an
-- index scan on the four kinds in date order. Built CONCURRENTLY as one statement.
--
--   node scripts/apply_sql.mjs scripts/sql/the_priority_pick_reads_its_own_index.sql --apply --ddl

create index concurrently if not exists kb_chunks_unembedded_kind_created_idx
  on public.kb_chunks using btree (source_kind, created_at)
  where embedding_gte is null;
