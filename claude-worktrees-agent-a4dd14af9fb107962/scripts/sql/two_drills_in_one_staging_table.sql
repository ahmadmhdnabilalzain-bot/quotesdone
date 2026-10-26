-- dr_restore gains a run_id, because two drills sharing one staging table lie about the backup.
--
-- MEASURED 13 Aug 2026. A dr_drill chain was started while an earlier chain was still hopping.
-- Hop 0 of the second wiped dr_restore, then BOTH chains inserted the same pages into it, and both
-- finished within one millisecond of each other reporting four and five failed tables:
--   kb_chunks    191,966 restored against  95,983 live  (exactly 2x)
--   dept_library   2,912 restored against   1,456 live  (exactly 2x)
--   ops_knowledge  7,470 restored against   3,735 live  (exactly 2x)
-- restored_rows is counted as "every dr_restore row with this kind", so one chain counted the
-- other chain's work as its own and concluded the backup did not match. That is the worst possible
-- direction for this particular instrument: a FALSE alarm on the only assertion that the company's
-- backups are restorable, which is exactly how a real alarm gets muted.
--
-- The monthly cron cannot collide with itself, but a manual verification run beside it can - and
-- did, twice, inside twenty minutes. Tagging every restored row with the chain that wrote it makes
-- the counts belong to a run instead of to a table name.
alter table public.dr_restore add column if not exists run_id uuid;
create index if not exists dr_restore_run_kind_idx on public.dr_restore (run_id, kind);
