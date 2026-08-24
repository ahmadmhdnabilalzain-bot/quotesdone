-- N10. THE NINE THAT REMAIN, CLASSIFIED RATHER THAN EXEMPTED.
--
-- The register opened this session with NINETEEN rows, every one saying PERMANENT_EXEMPTION. Ten of
-- them were closed by executing the case, and in eight of those ten the RECORDED BLOCKER WAS
-- SIMPLY WRONG about its own reason:
--
--   PD-CONC-001   "a second claimant cannot exist"        -> two management-endpoint statements run
--                                                            on two distinct backends whose
--                                                            transactions overlap. Raced, with a
--                                                            control. And the other half of its
--                                                            reason -- "a committed outbox row
--                                                            sends for real within 60s" -- is also
--                                                            wrong: neither fn_kernel_outbox_deliver
--                                                            nor fn_kernel_event_consume contains
--                                                            net.*, http, or any send. Delivery is
--                                                            an in-database projection.
--   PD-OUTBOX-004 "no consumer runs under the hold"       -> fn_kernel_event_consume runs in the
--                                                            caller's own transaction; consumed
--                                                            twice, no re-emission.
--   PD-TRACE-001  "doing it raw would test the kernel"    -> fn_phase_d_object_write's own refusal,
--   PD-TRACE-002                                             pd_object_kernel_owned, IS the control.
--   PD-TRACE-005  "Phase D has no path that requests it"  -> the absence of the path is the answer;
--                                                            the door refuses, pd_object_unbound.
--   PD-STATE-003  "the subject is frozen"                 -> the frozen registry REFUSING is the
--   PD-STATE-004                                             discriminating result, and the two
--                                                            refusals differ, which is the control.
--   PD-PROV-002   "not representable"                     -> it was not BUILT. N06 built it.
--   PD-PROV-004   "the subject is outside the database"   -> that is a description of a test, and
--                                                            the test now exists.
--   PD-AUTH-002   "both fixtures held zero documents"     -> true when written; the probe was
--   PD-PRIV-004                                              improved and the reason was not re-read.
--
-- NINE REMAIN, and none of them is a hold, a provider mode, an empty table or a frozen registry.
-- Every one is the same shape: THE CONTROL THE CASE NAMES DOES NOT EXIST IN THIS ESTATE. That is
-- classification G — REAL_PRODUCT_GAP — under the taxonomy this session was asked to apply, and it
-- is the only honest one for all nine. A gap is not an exemption: an exemption says "we chose not
-- to test", and a gap says "there is nothing here to test yet, and here is what would have to be
-- built". The `what_would_make_it_executable` column on every row is that build order.
--
-- WHAT WAS TRIED AND IS NOT AVAILABLE, said plainly rather than left as a silent absence:
-- classification E, EXECUTABLE_IN_LOCAL_EPHEMERAL_DATABASE, could not be attempted. Docker Desktop
-- on this machine fails to start -- stale unix-socket entries under AppData\Local that Windows
-- cannot delete, in two separate directories -- so no local Postgres could be built from the
-- committed schema. It would not have changed any of these nine: a database this harness builds
-- itself cannot answer whether the ESTATE has a control, only whether a copy of it does.
--
-- The register survives as historical evidence of what was blocked and why. It is no longer a
-- completion mechanism: fn_phase_d_disposition_state and build_injected_defect_result now fail the
-- build in BOTH directions -- a case that did not run and has no row, and a row for a case that has
-- since been closed.

-- The disposition vocabulary admitted only PERMANENT_EXEMPTION and DEFERRED_TO_A_BUILT_PATH.
-- Neither is true of these nine: they are not exempted and they are not deferred to a path that
-- exists. REAL_PRODUCT_GAP is added so the row can say what is actually the case, and the two
-- older values are kept so history reads correctly.
ALTER TABLE public.phase_d_injected_defect_disposition
  DROP CONSTRAINT IF EXISTS phase_d_disposition_value_ck;
ALTER TABLE public.phase_d_injected_defect_disposition
  ADD CONSTRAINT phase_d_disposition_value_ck
  CHECK (disposition = ANY (ARRAY['PERMANENT_EXEMPTION','DEFERRED_TO_A_BUILT_PATH','REAL_PRODUCT_GAP']));

ALTER TABLE public.phase_d_injected_defect_disposition
  ADD COLUMN IF NOT EXISTS classification text,
  ADD COLUMN IF NOT EXISTS missing_control text;

ALTER TABLE public.phase_d_injected_defect_disposition
  DROP CONSTRAINT IF EXISTS phase_d_injected_defect_disposition_classification_ck;
ALTER TABLE public.phase_d_injected_defect_disposition
  ADD CONSTRAINT phase_d_injected_defect_disposition_classification_ck
  CHECK (classification IS NULL OR classification IN (
    'TEST_CONTRACT_OBSOLETE',                      -- A
    'SAFE_SCOPED_SUCCESS',                         -- B
    'EXECUTABLE_WITH_TRANSACTION_LOCAL_FIXTURE',   -- C
    'EXECUTABLE_WITH_TEMPORARY_COMMITTED_CANARY',  -- D
    'EXECUTABLE_IN_LOCAL_EPHEMERAL_DATABASE',      -- E
    'DUPLICATE_CASE',                              -- F
    'REAL_PRODUCT_GAP'));                          -- G

-- A ROW THAT NAMES NO MISSING CONTROL IS AN EXEMPTION WEARING A CLASSIFICATION. The table refuses
-- to hold a REAL_PRODUCT_GAP that does not say what is missing.
ALTER TABLE public.phase_d_injected_defect_disposition
  DROP CONSTRAINT IF EXISTS phase_d_injected_defect_disposition_gap_names_control_ck;
ALTER TABLE public.phase_d_injected_defect_disposition
  ADD CONSTRAINT phase_d_injected_defect_disposition_gap_names_control_ck
  CHECK (classification IS DISTINCT FROM 'REAL_PRODUCT_GAP'
         OR coalesce(btrim(missing_control),'') <> '');

UPDATE public.phase_d_injected_defect_disposition SET
  disposition = 'REAL_PRODUCT_GAP',
  classification = 'REAL_PRODUCT_GAP',
  missing_control = v.missing
FROM (VALUES
  ('PD-AUTH-005',
   'A door that opens a task with a caller-supplied accountable owner and is not itself a '
|| 'kernel-internal primitive. The refusal EXISTS and was observed — trigger '
|| 'z10_phase_c_overlay_not_accountable refuses a category overlay as the accountable owner, and '
|| 'the canonical owner is accepted in the same shape. What is missing is a legitimate caller: the '
|| 'only authorised writer of public.phase_c_task from outside the kernel''s own progression is '
|| 'fn_phase_c_task_create, which public.kernel_retired_path classifies KERNEL_INTERNAL_PRIMITIVE. '
|| 'A probe calling it takes fn_kernel_retired_path_state from 0 of 9 to 1 of 9 — it becomes the '
|| 'bypass that board exists to catch. Build either an authenticated API path that opens a task, or '
|| 'a kernel entry point that accepts an owner and routes to the primitive.'),
  ('PD-LEGAL-005',
   'The same missing door as PD-AUTH-005. The independence refusal exists and was observed — '
|| 'z20_phase_c_task_state_guard refuses the owner of W28-S04 ("Assess compliance and privacy") as '
|| 'its own reviewer and accepts general_counsel in the same shape — so the rule holds for a '
|| 'COMPLIANCE review as it does for an ordinary one. What is missing is a compliance-review path '
|| 'that opens a task without calling the kernel-internal primitive. W28-S04 is a task step and no '
|| 'Phase D route opens one.'),
  ('PD-FIN-004',
   'A registered write route for public.phase_c_refund_decision in public.kernel_write_authority — '
|| 'it holds ZERO rows for that table, so a00_kernel_write_guard refuses every write and the table '
|| 'holds 0 rows, leaving nothing for the append-only trigger to refuse. The append-only control '
|| 'itself is real and named: a00_phase_c_refund_decision_immutable, BEFORE DELETE OR UPDATE. '
|| 'THE SECOND HALF IS NOT A GAP AND MUST NOT BE BUILT: the subject would have to be a founder '
|| 'refund decision the founder himself made. His standing rule is that a fixture may never forge '
|| 'one, and this harness will not. Even though a founder session CAN be driven from this '
|| 'repository — measured, fn_phase_c_founder_subject_bind returns ok=true as postgres — doing so '
|| 'to manufacture a refund decision is the fabrication the whole register exists to prevent.'),
  ('PD-LEGAL-004',
   'A predicate that judges a legal or tax artefact STALE. Measured: public.legal_documents holds '
|| '12 rows and none is a tax or legal-interpretation source; the table carries effective_date and '
|| 'updated_at and NO routine in the estate compares either against now(); BR-025 reads it for '
|| 'version and hash equality only. Build a registered interpretation artefact carrying a review-by '
|| 'date and a predicate that refuses an assertion resting on one past it. Then the injection is a '
|| 'claim citing the expired artefact and the control is the identical claim citing the current one.'),
  ('PD-PRIV-002',
   'A business object for a drawing revision that carries its redaction-approval state, and a '
|| 'predicate that reads it. Measured: public.phase_d_object_state_contract holds 0 object_ids '
|| 'matching draw|redact|metadata and public.phase_d_object_write_map binds no revision or '
|| 'redaction relation. The nearest live rule, BR-035, compares approved_revision_ref with '
|| 'publishing_revision_ref and reads no redaction state at all — scoring this case on BR-035 would '
|| 'be a refusal about a different fact.'),
  ('PD-PRIV-005',
   'A rendering path that produces a supplier-facing file, and a scanner over the produced BYTES '
|| '(EXIF/XMP/document properties) invoked before the file is exposed. Measured: no fn_phase_d_* '
|| 'routine produces a PDF, DOCX or image, and public.phase_d_acceptance_document is a registry of '
|| 'slugs rather than an artefact store. There is no object to strip and no scanner to refuse it.'),
  ('PD-QUOTE-001',
   'Two committed quotes, one per supplier, and a supplier-facing edit path whose authorisation is '
|| 'testable. Measured: public.quotes has row security ENABLED and ZERO policies, so every '
|| 'non-bypassing role — supplier A and supplier B alike — sees and writes nothing, and a control '
|| 'differing in exactly one respect behaves identically. No routine in public whose source touches '
|| 'public.quotes resolves a supplier from auth.uid(); the decision lives in an edge function. The '
|| 'marketplace holds 0 quotes.'),
  ('PD-QUOTE-004',
   'A publication or visibility state on the comparison a customer reads, and a BR-019 predicate '
|| 'that reads it. Measured on the live bodies: BR-019 and GATE-018 both evaluate count(*) from '
|| 'public.quote_comparisons where id = comparison_id AND customer_id = caller — OWNERSHIP, never '
|| 'publication — and no column matching publish|visib exists on quote_comparisons or on quotes. An '
|| 'unpublished comparison belonging to the caller passes both, so injecting "unpublished" changes '
|| 'nothing a control could separate.'),
  ('PD-QUOTE-005',
   'A normalisation path that writes a normalised projection ALONGSIDE the supplier''s immutable '
|| 'quotation revision, and a BR-018 predicate comparing the two records. Measured on the live '
|| 'body, BR-018 is: quote_revision_ref is non-empty AND platform_edited = ''false''. It compares '
|| 'nothing — it reads the caller''s own claim about itself, so a normalisation that genuinely '
|| 'overwrote the supplier''s figure and reported platform_edited=false would pass. There is also '
|| 'nothing to overwrite: the normalisation path is not built.')
) AS v(defect_id, missing)
WHERE public.phase_d_injected_defect_disposition.defect_id = v.defect_id;
