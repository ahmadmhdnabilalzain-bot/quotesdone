-- O10. THE NEW FILE-SET LEG REDDENED AN OLDER CASE THAT HAD NO FILE SET.
--
-- O07 gave BR-012 the leg PD-PRIV-002 needs: an approved supplier_safe_package is only approved if
-- EVERY live file revision registered against it is redaction-approved and metadata-clean, and a
-- package that registers no revision at all is refused (pd_revision_redaction_state_absent) --
-- because an empty file set is not an approved one, and treating it as one is the "absent input
-- scores as satisfied" shape this estate has been caught by twice.
--
-- That immediately turned PD-DISP-003 red, and it turned red on its CONTROL arm rather than its
-- injection: the case writes a supplier_safe_package with business_key 'zz-disp-003-approved' and
-- asks BR-012 to PASS on it. Under the new contract that package names no file, so it is refused.
-- Measured: build_injected_defect_result reported "FAILED TO REFUSE 1 -- PD-DISP-003".
--
-- THE FIX IS NOT TO WEAKEN BR-012. A rule that passes a package with no file set is the rule that
-- was there before, and PD-PRIV-002 exists because it passed a package with an UNREDACTED one.
-- What PD-DISP-003 actually asserts is that an unapproved package ref is refused and an approved
-- one is not; its control arm needs a package that satisfies the CURRENT contract, so the file
-- revision it always implied is registered here, committed, alongside the O05 fixtures.
--
-- ITS METADATA SCAN IS NOT RECORDED HERE. scripts/phase_d/run_metadata_scan_probe.mjs records a
-- verdict by scanning committed bytes; a scan row typed into a migration would be an expectation
-- wearing a measurement's clothes. This revision reuses the digest of the already-committed clean
-- fixture supplier_drawing_clean.pdf, so the scan the probe records for zz-demo-rev-drawing-safe
-- covers these bytes too -- and fn_phase_d_file_revision_dispatchable looks the scan up by
-- (revision_ref, safe_sha256), so the row below needs its own. The probe writes it: the REVISIONS
-- map in that script names this revision, and the build fails if the committed digest and the
-- committed bytes ever disagree.

INSERT INTO public.phase_d_file_revision
  (revision_ref, package_ref, source_revision_ref, file_name, media_type,
   source_sha256, safe_sha256, redaction_state, redaction_method, elements_removed,
   reviewer_role_id, reviewer_verdict, reviewed_at, authored_by_role_id)
VALUES
  ('zz-disp-003-rev-safe', 'zz-disp-003-approved', 'zz-demo-rev-drawing-unredacted',
   'supplier_drawing_clean.pdf', 'application/pdf',
   '617d50b1a1654b3b612d1981a55e84d8746f5f7821781a99b6b10da7948844a7',
   'd1311fb75b6d5c012a5dbf4513f098896b371dd65802526e9689951f6b2025a2',
   'APPROVED', 'title_block_mask_and_info_dictionary_cleared',
   '["pdf:/Info//Author","pdf:/Info//Subject","pdf:/Info//Keywords","pdf:/Info//Creator","title_block"]'::jsonb,
   'compliance_and_privacy_officer', 'approved', timestamptz '2026-08-24 00:00:00+00',
   'marketplace_content_privacy_reviewer')
ON CONFLICT (revision_ref) DO NOTHING;
