-- a_scanned_drawing_is_queued_for_ocr_redaction.sql — a scanned drawing or a photo may be queued for the CAD
-- worker's OCR redaction (24 Sep 2026, sales_engineer; founder instruction 579: "OCR for scanned drawings").
--
-- MEASURED (production, read-only, 24 Sep 2026): a page with no text layer (a scanned PDF, a photo) is HELD by the
-- edge every time, since the server has no words to box and the model is held; drawing_redaction_runs holds 6
-- rows and none is 'complete'. customer_api now stores such a drawing's page rasters and queues them in
-- public.cad_read_jobs, and scripts/cad_read_worker.ts OCRs, boxes, re-reads and publishes them only when clean
-- (supabase/functions/_shared/scan_redact.ts). The queue's `why` check allows four reasons and refuses a fifth, so
-- until this file is applied the insert fails, queueCadRead answers null and the drawing stays held (fail closed).
--
-- WHAT THIS CHANGES: the `why` check constraint gains 'scan_needs_ocr', and (25 Sep 2026, third review of #967)
-- 'cad_needs_ocr': every CAD page is read back by the worker's OCR before it is published, so a CAD drawing that
-- draws cleanly on the edge is queued here too. The stored page paths travel in the
-- existing boq_in jsonb ({ "scan_pages": [...] }), so no column is added and nothing new holds a storage path.
-- WHAT IT DOES NOT CHANGE: no routine, no policy, no grant, no other column; fn_cad_read_claim is untouched (it
-- claims by status, not by reason).

alter table public.cad_read_jobs drop constraint if exists cad_read_jobs_why_check;
alter table public.cad_read_jobs add constraint cad_read_jobs_why_check
  check (why in ('over_edge_ceiling', 'edge_worker_died', 'edge_reader_failed', 'pdf_lengths_worker_died', 'scan_needs_ocr', 'cad_needs_ocr'));
