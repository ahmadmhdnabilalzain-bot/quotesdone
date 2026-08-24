-- O15. AN APPROVAL THAT LEFT THE DISPOSITION SAYING DEFERRED.
--
-- O09 added `disposition` to public.phase_c_change_request with the CHECK that matters —
-- `phase_c_change_request_deferral_is_not_approval` — so a DEFERRED or REJECTED request may not
-- carry an approver, and recording "he decided not to decide this yet" can never later be read as
-- "he approved it".
--
-- That CHECK immediately refused a legitimate approval, and the estate's own check caught it:
--
--   scripts/checks/freeze_amendment_names_a_real_change_request.test.mjs
--   "the founder's own registered identity was refused on phase_c_change_request —
--    the guard refuses everything and approval is impossible"
--
-- Its positive control updates `approved_by` across the WHOLE register, which now includes
-- PCCR-004 (DEFER_OR_REJECT) and PCCR-005 (DEFERRED). The CHECK is right and the approval is right;
-- what was missing is that THEY ARE THE SAME EVENT. A request that has just been approved is not
-- deferred any more, and leaving the caller to say so twice is how two columns come to disagree.
--
-- The trigger below makes the estate satisfy the invariant instead of refusing the approval:
-- setting an approver moves the disposition to APPROVED in the same statement. Clearing an approver
-- moves it back to RAISED, because a request with no approver is not an approved one — and doing
-- only the first half would leave the reverse able to produce exactly the row the CHECK forbids.
--
-- PCCR-003 is corrected in the same file. It has carried approved_by = management@quotesdone.com
-- since 21 Aug and its disposition defaulted to RAISED when O09 added the column, so the register
-- said "raised" about a request the founder had already approved. That is a stale value in a
-- governance register, which is the thing this column exists to stop.

CREATE OR REPLACE FUNCTION public.fn_phase_c_change_request_disposition_follows_approval()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.approved_by is not null and (TG_OP = 'INSERT' or OLD.approved_by is null) then
    NEW.disposition := 'APPROVED';
    if coalesce(NEW.disposition_reason,'') = '' then
      NEW.disposition_reason := format('Approved by %s. Disposition set by '
        || 'a15_phase_c_change_request_disposition_follows_approval: an approved request is not a '
        || 'deferred one, and the two columns may not disagree.', NEW.approved_by);
    end if;
    NEW.disposition_recorded_at := coalesce(NEW.disposition_recorded_at, NEW.approved_at, now());
  elsif TG_OP = 'UPDATE' and NEW.approved_by is null and OLD.approved_by is not null then
    -- The reverse, or the CHECK could still be walked into: an APPROVED row whose approver is
    -- cleared would be an approval nobody gave.
    NEW.disposition := 'RAISED';
    NEW.disposition_reason := null;
    NEW.disposition_recorded_at := null;
  end if;
  return NEW;
end $function$;

REVOKE ALL ON FUNCTION public.fn_phase_c_change_request_disposition_follows_approval() FROM PUBLIC;

-- a15_, after the E36 approver guard (a10_) so "you are not the founder" still answers first: an
-- unauthorised approval must be refused for being unauthorised, not tidied into a disposition.
DROP TRIGGER IF EXISTS a15_phase_c_change_request_disposition_follows_approval
  ON public.phase_c_change_request;
CREATE TRIGGER a15_phase_c_change_request_disposition_follows_approval
  BEFORE INSERT OR UPDATE ON public.phase_c_change_request
  FOR EACH ROW EXECUTE FUNCTION public.fn_phase_c_change_request_disposition_follows_approval();

UPDATE public.phase_c_change_request
   SET disposition = 'APPROVED',
       disposition_reason = 'Approved by ' || approved_by || ' on ' || approved_at::date
         || '. Backfilled by phase_d_o15: the column was added by phase_d_o09 and defaulted to '
         || 'RAISED on a request that already carried an approver.',
       disposition_recorded_at = approved_at
 WHERE approved_by IS NOT NULL AND disposition = 'RAISED';
