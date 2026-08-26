-- ROLLBACK for scripts/sql/phase_d_the_refund_probe_was_refused_before_its_own_guard.sql
--
-- NO TRANSACTION CONTROL. One UPDATE and an assertion; rehearsable.
--
-- TWO THINGS WENT FORWARD AND ONLY ONE COMES BACK HERE.
--
--   * The ROUTINE. fn_phase_d_run_injected_defects is restored by re-applying the file it was
--     forked from, which is still in the tree and still canonical for every other branch:
--       node scripts/apply_sql.mjs \
--         scripts/sql/phase_c_pd_fin_004_reported_a_control_it_could_not_reach.sql --apply --ddl
--     Doing that reinstates PD-FIN-003's original injection, which names no transaction and is
--     therefore refused by a00_refund_amount_is_the_fee_paid with 23514 before
--     z00_refund_founder_decision_only is reached -- so the builder goes back to reporting
--     FAILED TO REFUSE 1 about a defect that is refused twice over. That is the state this file
--     was written to end.
--
--   * The PD-FIN-004 REGISTER TEXT, restored below, verbatim as
--     phase_c_pd_fin_004_is_deferred_to_the_founder_session_path.sql wrote it on 25 Aug 2026.
--
-- WHAT RESTORING THAT TEXT REASSERTS, said plainly because it is the reason the text was replaced:
-- it claims "Only the founder can produce that token; nothing in this repository can". Measured on
-- 26 Aug 2026, fn_phase_c_founder_subject_bind takes the subject as an argument, never compares it
-- to the caller's own auth.uid(), and is EXECUTE-granted to service_role -- so a service_role call
-- through PostgREST can bind the founder's subject with no founder token in existence. Rolling this
-- back puts a sentence that contradicts the routine back into the register.

UPDATE public.phase_d_injected_defect_disposition SET
  reason =
    'The control asserts that a recorded founder refund decision cannot be updated or deleted. To '
    || 'assert it, the probe must first CREATE one, and public.fn_kernel_refund_decision_record writes '
    || 'decided_by from a verified founder identity resolved by fn_phase_c_require_founder -- never '
    || 'from the call. Since PCCR-006, fn_phase_c_founder_subject_bind refuses every connection that '
    || 'is not the PostgREST one which verified a founder bearer token '
    || '(pccr_founder_bind_untrusted_connection), so no management or migration connection can produce '
    || 'the row the append-only trigger exists to protect. The trigger itself is deployed, unchanged, '
    || 'and still asserted directly against its own 23514 refusals in '
    || 'scripts/checks/protected_table_guards_actually_fire.test.mjs.',
  what_would_make_it_executable =
    'A founder bearer token presented to /rest/v1/rpc through PostgREST, so that '
    || 'fn_phase_c_founder_subject_bind resolves a verified subject and fn_kernel_refund_decision_record '
    || 'can record a real decision for the probe to then fail to edit. Only the founder can produce '
    || 'that token; nothing in this repository can, and PCCR-006 exists to keep it that way.'
WHERE defect_id = 'PD-FIN-004';

DO $assert$
DECLARE v_n int; v_reason text;
BEGIN
  SELECT count(*) INTO v_n FROM public.phase_d_injected_defect_disposition;
  SELECT reason INTO v_reason FROM public.phase_d_injected_defect_disposition
   WHERE defect_id = 'PD-FIN-004';
  IF v_n <> 1 OR position('PCCR-006, fn_phase_c_founder_subject_bind' in coalesce(v_reason,'')) = 0 THEN
    RAISE EXCEPTION 'rollback did not restore the PD-FIN-004 register text (rows %)', v_n
      USING errcode = '23514';
  END IF;
  RAISE NOTICE 'PD-FIN-004 register text restored; register holds % row', v_n;
END $assert$;
