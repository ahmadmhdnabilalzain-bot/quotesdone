-- THE IT LOOP READS HAND-OVERS BY KIND, TYPE AND SENDER ON AN INDEX BUILT CONCURRENTLY (13 Nov 2026; seat: it_engineer).
--
-- fn_it_loop_reverify, fn_it_daily_line and fn_it_ceo_silence_watch (the_it_engineer_closes_every_loop_it_opens.sql) filter
-- public.agent_actions by (kind, detail->>'type', detail->>'from'). That file built this index inside its own transaction,
-- which holds a SHARE lock on agent_actions (41,242 rows, 173 MB, read 13 Nov 2026) for the whole build: every write to the
-- company's hand-over table waits meanwhile. Coordinator's review 3, item 2: the index is built CONCURRENTLY, alone, here.
-- Production already has it (read 13 Nov 2026), so applying this file is a no-op there; it exists so a fresh database, and
-- a re-apply of the owner file, never build it under a lock again.
--
--   node scripts/apply_sql.mjs scripts/sql/the_it_loop_reads_handoffs_by_kind_type_and_sender_on_an_index_built_concurrently.sql --apply --ddl
-- Pending: scripts/sql/pending/the_it_loop_reads_handoffs_by_kind_type_and_sender_on_an_index_built_concurrently.txt.

create index concurrently if not exists agent_actions_kind_type_from_idx
  on public.agent_actions (kind, (detail->>'type'), (detail->>'from'));
