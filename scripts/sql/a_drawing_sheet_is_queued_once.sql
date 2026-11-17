-- A DRAWING'S SHEETS ARE QUEUED FOR THE CAD READER ONCE. 17 Nov 2026 (evening). Seat: sales_engineer.
-- Founder ledger 580 (a customer's drawing always reaches the matched suppliers, redacted and verified); paid proof 6244a525.
--
-- MEASURED (production, 17 Nov 2026 19:11-19:24 UTC): of an 8-sheet set, 7 sheets were lost to HTTP 546 and 1 came back
-- unverified, and cad_read_jobs got 0 rows because only sheets held for TIME were queued. customer_api now queues EVERY sheet
-- the request did not verify (supabase/functions/_shared/drawing_pages_queued.ts), and the CAD read routine retries a sheet
-- and keeps the ones it verified on the job. A second open job for the same stored drawing would make the routine check (and
-- pay the model for) the same sheets twice and attach two sets. customer_api reads an open job back before it queues
-- (lib/drawings.ts queuePagesOnce); this index makes the database say the same, so a race between two isolates cannot.
--
-- WHAT THIS CHANGES: one partial unique index on public.cad_read_jobs (source_path) for why 'pages_need_time' while the job is
-- queued or running. A finished or failed job does not count, so a drawing uploaded again later can be queued again.
-- Read on production 17 Nov 2026 (SELECT): cad_read_jobs holds 2 rows in the last 3 days and no 'pages_need_time' row, so the
-- build cannot meet a duplicate. WHAT IT DOES NOT CHANGE: no column, no constraint, no routine, no policy, no grant.
-- Rollback: scripts/sql/rollback/a_drawing_sheet_is_queued_once.rollback.sql. Probe: a_drawing_sheet_is_queued_once_probe.sql.
-- Ends with ONE verdict row (PROBE OK / PROBE FAILED: ...).

set local lock_timeout = '3s';

create unique index if not exists cad_read_jobs_one_open_pages_job
  on public.cad_read_jobs (source_path)
  where why = 'pages_need_time' and status in ('queued', 'running');

select case
  when (select count(*) from pg_index x join pg_class c on c.oid = x.indexrelid
         where c.relname = 'cad_read_jobs_one_open_pages_job' and x.indrelid = 'public.cad_read_jobs'::regclass and x.indisunique
           and pg_get_expr(x.indpred, x.indrelid) like '%pages_need_time%') = 1
  then 'PROBE OK'
  else 'PROBE FAILED: cad_read_jobs_one_open_pages_job is missing or not unique'
end as verdict;
