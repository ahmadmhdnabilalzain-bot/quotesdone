-- DOWN for O05. Classification: DATA_ONLY — six committed fixture revisions and nothing else.
-- The scan rows recorded against them by scripts/phase_d/run_metadata_scan_probe.mjs go first,
-- because phase_d_metadata_scan.revision_ref is a foreign key onto these rows.
DELETE FROM public.phase_d_metadata_scan
 WHERE revision_ref LIKE 'zz-demo-rev-%';
UPDATE public.phase_d_file_revision
   SET superseded_by = NULL, supersession_reason = NULL
 WHERE revision_ref LIKE 'zz-demo-rev-%';
DELETE FROM public.phase_d_file_revision
 WHERE revision_ref LIKE 'zz-demo-rev-%';
