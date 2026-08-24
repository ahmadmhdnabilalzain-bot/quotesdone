-- P03. TWO DECISION STEPS THE CATALOGUE NEVER TOLD WHAT WAS DECIDED.
--
-- NO TRANSACTION CONTROL. One implicit transaction under a simple-query batch; rehearsable.
--
-- P01 gave `decision` an enforced domain on the two steps where the estate holds an authority that
-- already refuses an out-of-domain value:
--
--   W17-S06   approved | rejected                    CHECK phase_c_refund_decision_ck, and
--                                                    fn_kernel_refund_decision_record by name
--   W08-S06   approved | rejected | changes_requested CHECK phase_d_file_revision_verdict_ck
--
-- and corrected the derivation so the field carries a decision instead of the frozen prose. The
-- committed catalogue was then the only source that could answer, and it held no EFFECT_PAYLOAD
-- `decision` row for either step. Measured immediately after P01 was applied, by re-running
-- scripts/phase_d/build_workflow_implementation_result.mjs against production in aborted
-- transactions:
--
--   W08   dispatches_executed  8 -> 7   business_effects_produced  8 -> 7
--   W17   dispatches_executed 11 -> 9   business_effects_produced 11 -> 9
--
-- The handler fell through to `coalesce(s.required_output,'')` — "Case decision with required
-- actions." — its own output contract refused it as outside the declared domain, and two steps that
-- worked stopped working. THE FIXTURE IS WHAT WAS MISSING, NOT THE CODE. Weakening the domain to
-- admit a prose sentence would be the guard that fires when the system works, corrected by removing
-- the guard.
--
-- WHY THESE VALUES. W17-S06 already carries PDF-4105, EFFECT_PAYLOAD `state` = 'rejected', and the
-- 2026-08-24 branch-coverage drive shows that value landing in public.refunds as "->rejected". The
-- decision it records IS that rejection, so the two rows now say the same thing in the two fields
-- that mean it. W08-S06 approves an immutable supplier-safe package and its frozen required_output
-- is "Approved immutable supplier-safe package"; the corresponding decision is 'approved', which is
-- also what BR-012 requires of phase_d_object_record.state for supplier_safe_package.
--
-- BOTH CARRY A MARKER EXEMPTION FOR THE SAME REASON THE EXISTING PDF-4105 DOES: the value is a
-- literal read by a CHECK constraint, and an embedded PHASE_D_FIXTURE_DO_NOT_PUBLISH marker is not
-- a decision — the write would be refused.
--
-- A ROW ADDED WITHOUT ITS ARTEFACT. docs/phase-d/PHASE_D_FIXTURE_CATALOGUE.csv is regenerated in
-- the same change by scripts/phase_d/build_fixture_catalogue.mjs, because
-- scripts/checks/phase_d_fixture_catalogue_matches_the_file.test.mjs fails in BOTH directions.

INSERT INTO public.phase_d_fixture_catalogue
  (fixture_id, fixture_version, workflow_id, step_id, scope, field_key, value, value_kind,
   expected_schema, expected_result, prohibited_external_use, marker_exemption)
VALUES
  ('PDF-4106', 1, 'W17', 'W17-S06', 'EFFECT_PAYLOAD', 'decision', '"rejected"'::jsonb, 'text',
   'a value of the canonical refund-decision domain — CHECK phase_c_refund_decision_ck '
   '(decision = ANY (ARRAY[''approved'',''rejected''])), enforced identically by name in '
   'public.fn_kernel_refund_decision_record. schema_output_w17_s06 declares the same two values.',
   'W17-S06 records a case decision of rejected in the field named decision, matching PDF-4105 '
   'which records the same outcome as the object state. No money moves: rejected is the outcome a '
   'non-founder may record, and approved is refused by z00_refund_founder_decision_only.',
   'Never treat as a decision on any real refund, dispute or fraud case; the founder decides every '
   'real refund at any amount, in a verified session.',
   'The value is the literal refund-decision rejected, read by CHECK phase_c_refund_decision_ck and '
   'by the declared domain of schema_output_w17_s06; an embedded marker is not a decision and both '
   'the constraint and the output contract would refuse it.'),

  ('PDF-4107', 1, 'W08', 'W08-S06', 'EFFECT_PAYLOAD', 'decision', '"approved"'::jsonb, 'text',
   'a value of CHECK phase_d_file_revision_verdict_ck on public.phase_d_file_revision — '
   'reviewer_verdict = ANY (ARRAY[''approved'',''rejected'',''changes_requested'']). '
   'schema_output_w08_s06 declares the same three values.',
   'W08-S06 records a decision of approved on the immutable supplier-safe package, which is what '
   'BR-012 requires of phase_d_object_record.state for supplier_safe_package and what the frozen '
   'required_output ("Approved immutable supplier-safe package") describes.',
   'Never treat as an approval of any real supplier-safe package or as clearance to publish one to '
   'a supplier; the package is created inside a transaction that is aborted.',
   'The value is the literal verdict approved, read by CHECK phase_d_file_revision_verdict_ck and '
   'by the declared domain of schema_output_w08_s06; an embedded marker is not a verdict and both '
   'the constraint and the output contract would refuse it.')
ON CONFLICT (fixture_id) DO UPDATE
  SET value = excluded.value, expected_schema = excluded.expected_schema,
      expected_result = excluded.expected_result,
      prohibited_external_use = excluded.prohibited_external_use,
      marker_exemption = excluded.marker_exemption;
