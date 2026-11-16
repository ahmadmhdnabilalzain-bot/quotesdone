-- THE DAILY EXPORT REACHES EVERY TABLE AGAIN.
--
-- Seat: it_engineer. 16 Nov 2026 (main session; found by the independent review of ceo-every-queue-is-worked-to-a-measured-result,
-- scratchpad REVIEW_ops.md; founder ledgers 1705, 1713: IT repairs, it does not report).
-- Measured on production 16 Nov ~02:35 UTC (SELECT):
--   table_export_run: 11 Nov done (1 attempt); 12, 14, 15, 16 Nov failed after 6 attempts; 13 Nov 'running' with 6 attempts.
--   Each stops at public.ceo_year_plan_archive: "has no primary key to page on". The table was made with LIKE ceo_year_plan on
--   11 Nov (12 rows, 12 distinct month values, no null month) and registered as exported; it is the ONLY public table without a
--   primary key. The export pages tables in name order, so about 115 tables after it -- customers, inquiries, leads, quotes,
--   suppliers among them -- have had no daily database export since 12 Nov. Those days cannot be re-exported; today's can.
-- WHAT THIS FILE DOES:
--   1. gives ceo_year_plan_archive the key its source table has (PRIMARY KEY (month)); 12 rows, unique, not null;
--   2. lets today's failed export run again from its saved page (attempts 0, heartbeat cleared): fn_table_export_due resumes it.
-- Not done here (after today's run reads 'done'): closing the never-written 12-15 Nov doc_backups pages as abandoned with
-- their reason, and making the export registry refuse a table with no primary key.
-- Rollback: alter table public.ceo_year_plan_archive drop constraint ceo_year_plan_archive_pkey;
set local lock_timeout = '1500ms';

alter table public.ceo_year_plan_archive add primary key (month);

update public.table_export_run set attempts = 0, heartbeat_at = null
 where stamp = (now() at time zone 'Asia/Dubai')::date and status = 'failed';

select case
  when exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                 left join pg_index i on i.indrelid = c.oid and i.indisprimary
                where n.nspname = 'public' and c.relkind = 'r' and i.indexrelid is null)
    then 'PROBE FAILED: a public table still has no primary key'
  when exists (select 1 from public.table_export_run
                where stamp = (now() at time zone 'Asia/Dubai')::date and status = 'failed' and attempts > 0)
    then 'PROBE FAILED: today''s export run was not reset'
  else 'PROBE OK: every public table has a primary key and today''s export can run again' end as verdict;
