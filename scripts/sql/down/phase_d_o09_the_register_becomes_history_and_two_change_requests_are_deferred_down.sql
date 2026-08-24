-- DOWN for O09. Classification: mixed — one additive table, three additive columns with three
-- constraints, one identifier-class row, two change-request rows, and one DATA MOVE.
--
-- THE DATA MOVE IS REVERSED FIRST AND FROM THE HISTORY TABLE, because the history table is the only
-- surviving copy of the nine disposition rows once O09 has run. Restoring the live register from it
-- and only then dropping it keeps that true at every point.
INSERT INTO public.phase_d_injected_defect_disposition
  (defect_id, category, disposition, reason, what_would_make_it_executable, decided_at,
   classification, missing_control)
SELECT h.defect_id, h.category, h.disposition, h.reason, h.what_would_make_it_executable,
       h.decided_at, h.classification, h.missing_control
  FROM public.phase_d_injected_defect_disposition_history h
 WHERE NOT EXISTS (SELECT 1 FROM public.phase_d_injected_defect_disposition d
                    WHERE d.defect_id = h.defect_id);

DROP TABLE IF EXISTS public.phase_d_injected_defect_disposition_history;

DELETE FROM public.phase_d_personal_identifier_class WHERE identifier_class = 'document_author_field';
DELETE FROM public.phase_c_change_request WHERE change_request_ref IN ('PCCR-004','PCCR-005');

ALTER TABLE public.phase_c_change_request
  DROP CONSTRAINT IF EXISTS phase_c_change_request_disposition_is_reasoned,
  DROP CONSTRAINT IF EXISTS phase_c_change_request_deferral_is_not_approval,
  DROP CONSTRAINT IF EXISTS phase_c_change_request_disposition_ck;
ALTER TABLE public.phase_c_change_request
  DROP COLUMN IF EXISTS disposition_recorded_at,
  DROP COLUMN IF EXISTS disposition_reason,
  DROP COLUMN IF EXISTS disposition;
