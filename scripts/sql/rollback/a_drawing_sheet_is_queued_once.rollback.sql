-- ROLLBACK for scripts/sql/a_drawing_sheet_is_queued_once.sql (sales_engineer, 17 Nov 2026).
-- Drops the partial unique index. customer_api still reads an open job back before it queues (lib/drawings.ts queuePagesOnce),
-- so a drawing is still queued once in the ordinary case; only a race between two isolates is no longer refused.
set local lock_timeout = '3s';
drop index if exists public.cad_read_jobs_one_open_pages_job;
select case when to_regclass('public.cad_read_jobs_one_open_pages_job') is null then 'PROBE OK' else 'PROBE FAILED: the index is still there' end as verdict;
