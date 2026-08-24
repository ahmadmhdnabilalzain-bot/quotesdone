-- O09. THE REGISTER BECOMES HISTORY, AND TWO CHANGE REQUESTS ARE RECORDED AS DEFERRED.
--
-- PART 1 — THE DISPOSITION REGISTER.
--
-- public.phase_d_injected_defect_disposition held nine rows, every one classification
-- REAL_PRODUCT_GAP with a build order in what_would_make_it_executable. O01-O08 built all nine and
-- every one now executes with a discriminating result. The founder's instruction for this session
-- is explicit: "Retain the exemption register only as historical evidence. It may not be part of
-- the final passing denominator."
--
-- So the rows move rather than vanish. public.phase_d_injected_defect_disposition_history is
-- append-only and carries, for each, WHEN it closed, WHICH FILE closed it, and WITH WHAT STATUS --
-- and the live register is emptied, which is what makes it stop being a completion mechanism.
-- scripts/phase_d/build_injected_defect_result.mjs already fails in both directions (a case that
-- did not run with no row; a row for a case that now runs), so an empty live register is only
-- green while every case runs.
--
-- TWO OF THE NINE RECORDED REASONS WERE WRONG, AND THE HISTORY SAYS SO RATHER THAN QUIETLY
-- DROPPING THEM. PD-AUTH-005 and PD-LEGAL-005 both claimed that closing them required calling
-- fn_phase_c_task_create from outside the kernel. fn_kernel_open_step has accepted a
-- caller-supplied owner and routed to that primitive the whole time.
--
-- PART 2 — PCCR-004 AND PCCR-005.
--
-- Neither is applied, neither is approved, and this file does not deploy either proposed body.
-- public.phase_c_change_request had no way to say what happened to a change request: it carried
-- approved_by/approved_at and nothing else, so a raised-and-deferred request and a raised-and-
-- forgotten one were the same row. The disposition column below is that missing fact, and the
-- CHECK on it makes DEFERRED and REJECTED unable to carry an approval -- recording a deferral can
-- never be mistaken for granting one.

-- ---------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.phase_d_injected_defect_disposition_history (
  history_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  defect_id       text NOT NULL,
  category        text NOT NULL,
  disposition     text NOT NULL,
  classification  text,
  reason          text NOT NULL,
  missing_control text,
  what_would_make_it_executable text NOT NULL,
  decided_at      timestamptz,
  closed_at       timestamptz NOT NULL DEFAULT now(),
  closed_by       text NOT NULL,
  closing_status  text NOT NULL,
  note            text
);

COMMENT ON TABLE public.phase_d_injected_defect_disposition_history IS
  'O09. What the disposition register said, and what closed it. Historical evidence only: nothing '
  'reads this table to decide whether a case passed, and it is not part of any denominator.';

ALTER TABLE public.phase_d_injected_defect_disposition_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.phase_d_injected_defect_disposition_history FROM PUBLIC;
GRANT SELECT ON TABLE public.phase_d_injected_defect_disposition_history TO service_role;

INSERT INTO public.phase_d_injected_defect_disposition_history
  (defect_id, category, disposition, classification, reason, missing_control,
   what_would_make_it_executable, decided_at, closed_by, closing_status, note)
SELECT d.defect_id, d.category, d.disposition, d.classification, d.reason, d.missing_control,
       d.what_would_make_it_executable, d.decided_at,
       CASE d.defect_id
         WHEN 'PD-AUTH-005'  THEN 'phase_d_o01 + phase_d_o08'
         WHEN 'PD-LEGAL-005' THEN 'phase_d_o01 + phase_d_o08'
         WHEN 'PD-FIN-004'   THEN 'phase_d_o02 + phase_d_o08'
         WHEN 'PD-LEGAL-004' THEN 'phase_d_o03 + phase_d_o07 + phase_d_o08'
         WHEN 'PD-PRIV-002'  THEN 'phase_d_o04 + phase_d_o05 + phase_d_o07 + phase_d_o08'
         WHEN 'PD-PRIV-005'  THEN 'phase_d_o04 + phase_d_o05 + phase_d_o07 + phase_d_o08'
         WHEN 'PD-QUOTE-001' THEN 'phase_d_o06 + phase_d_o08'
         WHEN 'PD-QUOTE-004' THEN 'phase_d_o06 + phase_d_o07 + phase_d_o08'
         WHEN 'PD-QUOTE-005' THEN 'phase_d_o06 + phase_d_o07 + phase_d_o08'
         ELSE '(unrecorded)' END,
       CASE d.defect_id WHEN 'PD-QUOTE-005' THEN 'IDEMPOTENT_NO_DUPLICATE'
                        ELSE 'REFUSED_AS_REQUIRED' END,
       CASE d.defect_id
         WHEN 'PD-AUTH-005' THEN 'THE RECORDED REASON WAS WRONG. It said closing this needs '
           || 'fn_phase_c_task_create, a KERNEL_INTERNAL_PRIMITIVE. fn_kernel_open_step is a '
           || 'kernel entry point that takes owner_role_id FROM THE CALLER and routes to exactly '
           || 'that primitive, and has done throughout. Driven 24 Aug 2026: overlay REFUSED 23514, '
           || 'its packaged alias REFUSED 23514, the standing role ACCEPTED, and tasks, step runs '
           || 'and traces unchanged across both refusals.'
         WHEN 'PD-LEGAL-005' THEN 'THE RECORDED REASON WAS WRONG, in the same way and for the same '
           || 'routine as PD-AUTH-005. Driven on W08-S06 ("Approve immutable supplier-safe '
           || 'package"): the declared reviewer presented as the step''s own owner was refused '
           || 'pd_creator_reviewer_collision, its legacy alias privacy_officer was refused the '
           || 'same way naming the RESOLVED identity, and the frozen canonical owner was accepted.'
         WHEN 'PD-FIN-004' THEN 'The append-only control was always real and always correct. What '
           || 'was missing was a PRODUCER: kernel_write_authority held zero rows for '
           || 'phase_c_refund_decision, so no routine could create the row the trigger protects. '
           || 'O02 registered fn_kernel_refund_decision_record. The second half of the old reason '
           || 'stands and was honoured: nothing forged a founder decision, and the subject was '
           || 'bound through the estate''s own server door inside a block that always rolls back.'
         ELSE 'The control the case named did not exist and now does; the build order in '
           || 'what_would_make_it_executable was followed rather than reinterpreted.' END
FROM public.phase_d_injected_defect_disposition d
WHERE NOT EXISTS (SELECT 1 FROM public.phase_d_injected_defect_disposition_history h
                   WHERE h.defect_id = d.defect_id);

DELETE FROM public.phase_d_injected_defect_disposition;

-- ---------------------------------------------------------------------------------------------
-- The identifier class the measurement asked for. BR-011 could not decide a bare personal NAME --
-- a regex cannot, which is why person_name_freeform is registered HUMAN_REVIEW. But a POPULATED
-- author-style metadata field in a supplier-facing artefact is a leak by construction, whatever the
-- value is, and that IS machine-decidable. Measured before adding it: '/Author (ZZ DEMO Omar Bin
-- Faisal)' returned ENFORCED_PASS.
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.phase_d_personal_identifier_class
  (identifier_class, description, detection, pattern, supplier_facing_allowed)
VALUES
  ('document_author_field',
   'A populated author, creator, owner or last-modified-by field in document metadata. The VALUE '
   || 'need not be recognised: a supplier-facing artefact that names who made it has already '
   || 'identified somebody.', 'REGEX',
   '/(Author|Creator|Owner|LastModifiedBy|Company)\s*\(\s*[^)\s][^)]*\)', false)
ON CONFLICT (identifier_class) DO NOTHING;

-- ---------------------------------------------------------------------------------------------
-- PCCR DISPOSITIONS.
-- ---------------------------------------------------------------------------------------------
ALTER TABLE public.phase_c_change_request
  ADD COLUMN IF NOT EXISTS disposition text NOT NULL DEFAULT 'RAISED',
  ADD COLUMN IF NOT EXISTS disposition_reason text,
  ADD COLUMN IF NOT EXISTS disposition_recorded_at timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid = 'public.phase_c_change_request'::regclass
                    AND conname = 'phase_c_change_request_disposition_ck') THEN
    ALTER TABLE public.phase_c_change_request ADD CONSTRAINT phase_c_change_request_disposition_ck
      CHECK (disposition IN ('RAISED','DEFERRED','DEFER_OR_REJECT','REJECTED','APPROVED','WITHDRAWN'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid = 'public.phase_c_change_request'::regclass
                    AND conname = 'phase_c_change_request_deferral_is_not_approval') THEN
    -- THE POINT OF THE COLUMN. A deferred or rejected change request may not carry an approver, so
    -- recording "he decided not to decide this yet" can never be read later as "he approved it".
    ALTER TABLE public.phase_c_change_request
      ADD CONSTRAINT phase_c_change_request_deferral_is_not_approval
      CHECK (disposition NOT IN ('DEFERRED','DEFER_OR_REJECT','REJECTED','WITHDRAWN')
             OR approved_by IS NULL);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid = 'public.phase_c_change_request'::regclass
                    AND conname = 'phase_c_change_request_disposition_is_reasoned') THEN
    ALTER TABLE public.phase_c_change_request
      ADD CONSTRAINT phase_c_change_request_disposition_is_reasoned
      CHECK (disposition = 'RAISED'
             OR (COALESCE(disposition_reason,'') <> '' AND disposition_recorded_at IS NOT NULL));
  END IF;
END $$;

INSERT INTO public.phase_c_change_request
  (change_request_ref, document_path, subject, raised_at, disposition, disposition_reason,
   disposition_recorded_at)
VALUES
  ('PCCR-004', 'docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-004.md',
   'canonical_cancellation_service — fn_kernel_cancel refuses a workflow run on the state model of '
   || 'a command nobody named, and sweeps sibling runs'' tasks, outbox rows and traces on command_id. '
   || 'Written, applied, measured and REVERTED 23 Aug 2026. Not applied.',
   timestamptz '2026-08-23 00:00:00+00', 'DEFER_OR_REJECT',
   'Founder disposition, 24 Aug 2026. The frozen cancellation service passes 30 of 30 Phase D '
   || 'cancellation cases. No current production path performs partial cancellation of one run '
   || 'while preserving sibling runs. Phase D does not depend on the amendment. Not approved, not '
   || 'applied, and no proposed body is deployed by this or any other file in this session.',
   timestamptz '2026-08-24 00:00:00+00'),
  ('PCCR-005', 'docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-005.md',
   'internal_review_service — fn_kernel_review_decide accepts a verdict for a step that declares no '
   || 'reviewer, and the only two predicates that read a verdict are guarded on the step declaring '
   || 'one. Raised 24 Aug 2026. Never built, never applied.',
   timestamptz '2026-08-24 00:00:00+00', 'DEFERRED',
   'Founder disposition, 24 Aug 2026. Review correctness is enforced at the Phase D review and step '
   || 'boundary: N02 added a01_phase_c_step_run_review_verdict (pd_review_verdict_rejected), which '
   || 'refuses a completion while the latest sealed verdict is rejected or changes_requested on ANY '
   || 'step, and O01 gave the task boundary the stable identity pd_creator_reviewer_collision. No '
   || 'demonstrated requirement justifies changing the frozen Phase C review contract. Not '
   || 'approved, not applied, no proposed body deployed.',
   timestamptz '2026-08-24 00:00:00+00')
ON CONFLICT (change_request_ref) DO UPDATE
  SET disposition = excluded.disposition,
      disposition_reason = excluded.disposition_reason,
      disposition_recorded_at = excluded.disposition_recorded_at;
