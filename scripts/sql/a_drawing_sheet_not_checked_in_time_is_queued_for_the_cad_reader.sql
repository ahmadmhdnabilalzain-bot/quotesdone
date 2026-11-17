-- A DRAWING SHEET NOT CHECKED IN TIME IS QUEUED FOR THE CAD READER. 17 Nov 2026.
-- Seat: sales_engineer. Founder ledger 580 (the drawing reaches the suppliers, redacted); paid proof 623d9200.
--
-- MEASURED (production 17 Nov 2026, function logs and ai_cost_log): analyze_drawing starts no sheet after 100 s, and an
-- 8-sheet set took 20.5 s of plan read and 20.5-27.5 s a sheet, one after another, so 4 sheets were begun and the whole
-- drawing was held. customer_api now checks four sheets side by side with their views cut a few to a worker
-- (drawing_redact mode 'tiles'); the local timing model checks 8 sheets in ~60 s and 19 of 20 in ~119 s. A sheet still held
-- for time, when every other sheet of the set was verified, is queued in public.cad_read_jobs with why 'pages_need_time'
-- (supabase/functions/_shared/drawing_pages_queued.ts); scripts/cad_read_worker.ts checks it through the same drawing_redact
-- manual path and publishes the set only when every sheet is verified.
--
-- WHAT THIS CHANGES: cad_read_jobs_why_check, read on production 17 Nov 2026 as the six values over_edge_ceiling,
-- edge_worker_died, edge_reader_failed, pdf_lengths_worker_died, scan_needs_ocr, site_photo_check, is re-created with every
-- value it held, in its order, plus pages_need_time. Without it the insert is refused and the drawing stays held, as before.
-- WHAT IT DOES NOT CHANGE: no column, no policy, no grant, no routine. The job's input lives in boq_in.queued_pages.
-- Ends with ONE verdict row (PROBE OK / PROBE FAILED: ...).

set local lock_timeout = '3s';

alter table public.cad_read_jobs drop constraint if exists cad_read_jobs_why_check;
alter table public.cad_read_jobs add constraint cad_read_jobs_why_check
  check (why = any (array['over_edge_ceiling', 'edge_worker_died', 'edge_reader_failed', 'pdf_lengths_worker_died', 'scan_needs_ocr', 'site_photo_check', 'pages_need_time']));

select case
  when (select count(*) from pg_constraint where conrelid = 'public.cad_read_jobs'::regclass and conname = 'cad_read_jobs_why_check'
        and pg_get_constraintdef(oid) like '%pages_need_time%' and pg_get_constraintdef(oid) like '%site_photo_check%' and pg_get_constraintdef(oid) like '%scan_needs_ocr%') = 1
  then 'PROBE OK'
  else 'PROBE FAILED: cad_read_jobs_why_check does not hold every value'
end as verdict;
