-- O05. FOUR COMMITTED SUPPLIER-FACING REVISIONS THAT DIFFER IN ONE RESPECT EACH.
--
-- The registry O04 built is only worth as much as the cases it can be asked about, and a probe that
-- creates its own subject answers its own question. These rows are committed by the migration and
-- their digests are the digests of files committed under scripts/staging/fixtures/metadata/,
-- generated deterministically by scripts/phase_d/metadata_scan.mjs --write-fixtures:
--
--   supplier_drawing_dirty.pdf  1005 bytes  617d50b1a1654b3b612d1981a55e84d8746f5f7821781a99b6b10da7948844a7
--   supplier_drawing_clean.pdf   736 bytes  d1311fb75b6d5c012a5dbf4513f098896b371dd65802526e9689951f6b2025a2
--   supplier_photo_dirty.png     258 bytes  4c32d0a313273a09717d2cc02f8863d400cf3b4eb3a8271db7cb75eb8fd32faa
--   supplier_photo_clean.png      72 bytes  4d44c07cf62f61efdc4fe0ea126031bc958585f934e0ef8c1c7d2baca829aeae
--
-- The dirty PDF's /Info dictionary carries, in this estate's ZZ DEMO convention:
--   /Author (ZZ DEMO Omar Bin Faisal)                    -- a person's name
--   /Subject (contact zz.customer@example.invalid or 0501234567)
--   /Keywords (PHASE_D_FIXTURE_DO_NOT_PUBLISH wa.me/971501234567)
--   /Creator (C:\Users\zz.demo.customer\AutoCAD)         -- a filesystem username
-- The clean PDF is the same page with the dictionary reduced to /Producer (QuotesDone).
-- The scan VERDICT is not committed here: it is recorded by
-- scripts/phase_d/run_metadata_scan_probe.mjs --write, which reads the committed bytes and judges
-- them against public.phase_d_personal_identifier_class. A verdict typed into a migration would be
-- an expectation, not a measurement.
--
-- THE SIX CASES THESE ROWS MAKE ASKABLE, each isolating one arm of
-- fn_phase_d_file_revision_dispatchable:
--   zz-demo-rev-drawing-unredacted  PENDING          -> pd_revision_redaction_unapproved
--   zz-demo-rev-drawing-rejected    REJECTED         -> pd_revision_redaction_rejected
--   zz-demo-rev-drawing-safe        APPROVED, clean  -> DISPATCHABLE (the control)
--   zz-demo-rev-photo-unredacted    APPROVED at the DIRTY digest -> the scan refuses it
--                                   (pd_hidden_metadata_identifier_found), which is the whole point:
--                                   a redaction reviewer approving a file does not make its hidden
--                                   metadata clean, and the two verdicts are separate facts.
--   zz-demo-rev-photo-safe          APPROVED, clean  -> DISPATCHABLE
--   zz-demo-rev-drawing-superseded  SUPERSEDED       -> pd_revision_superseded
--
-- REVIEWER INDEPENDENCE IS REAL ON THESE ROWS. Every approved revision is authored by
-- marketplace_content_privacy_reviewer and approved by compliance_and_privacy_officer;
-- a10_phase_d_file_revision_reviewer refuses the row outright if the two resolve to one employee,
-- so the fixtures could not have been written the wrong way round.

INSERT INTO public.phase_d_file_revision
  (revision_ref, package_ref, source_revision_ref, file_name, media_type,
   source_sha256, safe_sha256, redaction_state, redaction_method, elements_removed,
   reviewer_role_id, reviewer_verdict, reviewed_at, authored_by_role_id)
VALUES
  ('zz-demo-rev-drawing-unredacted', 'zz-demo-pkg-priv-002', NULL,
   'supplier_drawing_dirty.pdf', 'application/pdf',
   '617d50b1a1654b3b612d1981a55e84d8746f5f7821781a99b6b10da7948844a7', NULL,
   'PENDING', NULL, '[]'::jsonb, NULL, NULL, NULL, 'marketplace_content_privacy_reviewer'),

  ('zz-demo-rev-drawing-rejected', 'zz-demo-pkg-priv-002-rejected', 'zz-demo-rev-drawing-unredacted',
   'supplier_drawing_dirty.pdf', 'application/pdf',
   '617d50b1a1654b3b612d1981a55e84d8746f5f7821781a99b6b10da7948844a7', NULL,
   'REJECTED', 'manual_title_block_mask', '["title_block"]'::jsonb,
   'compliance_and_privacy_officer', 'rejected', timestamptz '2026-08-24 00:00:00+00',
   'marketplace_content_privacy_reviewer'),

  ('zz-demo-rev-drawing-safe', 'zz-demo-pkg-priv-002-clean', 'zz-demo-rev-drawing-unredacted',
   'supplier_drawing_clean.pdf', 'application/pdf',
   '617d50b1a1654b3b612d1981a55e84d8746f5f7821781a99b6b10da7948844a7',
   'd1311fb75b6d5c012a5dbf4513f098896b371dd65802526e9689951f6b2025a2',
   'APPROVED', 'title_block_mask_and_info_dictionary_cleared',
   '["pdf:/Info//Author","pdf:/Info//Subject","pdf:/Info//Keywords","pdf:/Info//Creator","title_block"]'::jsonb,
   'compliance_and_privacy_officer', 'approved', timestamptz '2026-08-24 00:00:00+00',
   'marketplace_content_privacy_reviewer'),

  ('zz-demo-rev-photo-unredacted', 'zz-demo-pkg-priv-005-dirty', NULL,
   'supplier_photo_dirty.png', 'image/png',
   '4c32d0a313273a09717d2cc02f8863d400cf3b4eb3a8271db7cb75eb8fd32faa',
   '4c32d0a313273a09717d2cc02f8863d400cf3b4eb3a8271db7cb75eb8fd32faa',
   'APPROVED', 'visual_review_only_no_metadata_pass', '["site_address"]'::jsonb,
   'compliance_and_privacy_officer', 'approved', timestamptz '2026-08-24 00:00:00+00',
   'marketplace_content_privacy_reviewer'),

  ('zz-demo-rev-photo-safe', 'zz-demo-pkg-priv-005-clean', 'zz-demo-rev-photo-unredacted',
   'supplier_photo_clean.png', 'image/png',
   '4c32d0a313273a09717d2cc02f8863d400cf3b4eb3a8271db7cb75eb8fd32faa',
   '4d44c07cf62f61efdc4fe0ea126031bc958585f934e0ef8c1c7d2baca829aeae',
   'APPROVED', 'text_chunks_stripped', '["png:tEXt/Author","png:tEXt/Comment","png:tEXt/Source"]'::jsonb,
   'compliance_and_privacy_officer', 'approved', timestamptz '2026-08-24 00:00:00+00',
   'marketplace_content_privacy_reviewer'),

  ('zz-demo-rev-drawing-superseded', 'zz-demo-pkg-priv-002-superseded', NULL,
   'supplier_drawing_clean.pdf', 'application/pdf',
   'd1311fb75b6d5c012a5dbf4513f098896b371dd65802526e9689951f6b2025a2',
   'd1311fb75b6d5c012a5dbf4513f098896b371dd65802526e9689951f6b2025a2',
   'APPROVED', 'title_block_mask', '["title_block"]'::jsonb,
   'compliance_and_privacy_officer', 'approved', timestamptz '2026-08-24 00:00:00+00',
   'marketplace_content_privacy_reviewer')
ON CONFLICT (revision_ref) DO NOTHING;

UPDATE public.phase_d_file_revision
   SET superseded_by = 'zz-demo-rev-drawing-safe',
       supersession_reason = 'ZZ DEMO. Replaced by the revision whose /Info dictionary was cleared.'
 WHERE revision_ref = 'zz-demo-rev-drawing-superseded' AND superseded_by IS NULL;
