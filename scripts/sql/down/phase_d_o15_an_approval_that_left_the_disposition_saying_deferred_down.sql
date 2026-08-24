-- DOWN for O15. Classification: ADDITIVE_DDL — one trigger, one routine, one backfill.
-- The backfill is reversed to the state O09 left: a request carrying an approver goes back to
-- disposition RAISED with no reason. That state is the defect O15 corrected (a governance register
-- saying "raised" about a request the founder had approved), so reverse it only alongside O09.
DROP TRIGGER IF EXISTS a15_phase_c_change_request_disposition_follows_approval
  ON public.phase_c_change_request;
DROP FUNCTION IF EXISTS public.fn_phase_c_change_request_disposition_follows_approval();
UPDATE public.phase_c_change_request
   SET disposition = 'RAISED', disposition_reason = NULL, disposition_recorded_at = NULL
 WHERE approved_by IS NOT NULL AND disposition = 'APPROVED';
