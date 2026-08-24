-- DOWN for O10. Classification: DATA_ONLY — one committed file revision and the scan row recorded
-- against it. The scan goes first; phase_d_metadata_scan.revision_ref is a foreign key onto it.
DELETE FROM public.phase_d_metadata_scan WHERE revision_ref = 'zz-disp-003-rev-safe';
DELETE FROM public.phase_d_file_revision WHERE revision_ref = 'zz-disp-003-rev-safe';
