-- E37 - the new guard made its table enforcing, and enforcing tables need a truncate guard
--
-- E36 put a BEFORE trigger on public.phase_c_freeze_amendment so that only a registered founder
-- identity can approve an amendment to a frozen Phase C contract. The estate's own board caught the
-- consequence within one suite run:
--
--     fn_kernel_truncate_protection_state
--       enforcing_tables_without_a_truncate_guard   expected 0, got 1 of 80
--       enforcing_tables_still_granting_truncate    expected 0, got 1 of 80
--
-- `phase_c_freeze_amendment` had never been an ENFORCING table -- it carried constraints but no
-- trigger -- so it was not in the population the truncate protection watches. Adding a trigger moved
-- it in, and it arrived without the two things every other enforcing table has: a
-- `z00_kernel_truncate_guard` and no TRUNCATE grant. The count went 79 -> 80 and the two checks went
-- red.
--
-- THIS IS THE BOARD DOING ITS JOB AND IT IS NOT A DISCLOSURE. A row that says "only the founder can
-- approve" is worth nothing on a table anybody can TRUNCATE: emptying it would erase four
-- amendments, and `fn_phase_c_freeze_drift()` reads the amendment rows to decide whether a moved
-- digest is excused -- so a truncate would not just lose the ledger, it would make 4 of 25 frozen
-- subjects read as DRIFTED. Adding a ratchet entry here would have been recording a hole I had just
-- opened, in the file that exists to stop exactly that.
--
-- The remedy is the estate's existing one, applied to one more table by the same statements
-- `the_truncate_protection_was_a_typed_list.sql` runs over the rest. Nothing new is invented: the
-- guard function and the trigger name are the ones already on the other 79.
--
-- Re-running that file wholesale would have worked too. This is scoped to the one table so the
-- change is readable and so a re-apply cannot quietly re-grant anything on the other 79.

REVOKE TRUNCATE ON public.phase_c_freeze_amendment FROM public, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.phase_c_freeze_amendment;
CREATE TRIGGER z00_kernel_truncate_guard
  BEFORE TRUNCATE ON public.phase_c_freeze_amendment
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_kernel_truncate_guard();
