-- PD-FIN-004 IS DEFERRED TO A PATH THAT EXISTS AND THAT CI CANNOT WALK.
--
-- NO TRANSACTION CONTROL. One INSERT and an assertion.
--
-- phase_c_pd_fin_004_reported_a_control_it_could_not_reach.sql stopped this control reporting
-- NOT_REFUSED about a guard it never reached, and made it report NOT_RUN instead. The builder then
-- said the next true thing:
--
--   NOT_RUN with a named blocker       1
--   named in the disposition register  0 of 1
--   NOT IN THE REGISTER: PD-FIN-004
--   a case that did not run and that nobody decided is not a case anyone can check.
--
-- That is the estate refusing to let a case sit in limbo, and it is right. A defect that does not
-- execute needs a recorded decision or it is simply missing.
--
-- DEFERRED_TO_A_BUILT_PATH, not PERMANENT_EXEMPTION and not REAL_PRODUCT_GAP:
--   * not a product gap -- a00_phase_c_refund_decision_immutable is deployed and unchanged, and its
--     raw UPDATE and DELETE arms are driven and asserted today in
--     scripts/checks/protected_table_guards_actually_fire.test.mjs;
--   * not permanent -- the path is BUILT. fn_kernel_refund_decision_record is registered in
--     kernel_write_authority and records a founder decision the moment a verified founder subject
--     is present. What CI lacks is the token, not the route.
--
-- WHAT THIS COSTS, said here so it is not discovered later: regression item 16 of
-- PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1 froze "live exemption register 0 rows" at a time when
-- nothing was deferred. This row makes it 1. That is a real change to a frozen expectation and it
-- is recorded in docs/phase-d/PHASE_D_FINDING_W04S04_REGRESSION.md as a finding, not smuggled in:
-- section E of the standard reserves moving a pass condition to a change request. The alternative
-- was to leave a refund control undecided, which the builder correctly refuses to accept.
--
-- ROLLBACK: scripts/sql/down/phase_c_pd_fin_004_is_deferred_to_the_founder_session_path_down.sql

INSERT INTO public.phase_d_injected_defect_disposition
  (defect_id, category, disposition, reason, what_would_make_it_executable, decided_at)
VALUES (
  'PD-FIN-004', 'FINANCE', 'DEFERRED_TO_A_BUILT_PATH',
  'The control asserts that a recorded founder refund decision cannot be updated or deleted. To '
  || 'assert it, the probe must first CREATE one, and public.fn_kernel_refund_decision_record writes '
  || 'decided_by from a verified founder identity resolved by fn_phase_c_require_founder -- never '
  || 'from the call. Since PCCR-006, fn_phase_c_founder_subject_bind refuses every connection that '
  || 'is not the PostgREST one which verified a founder bearer token '
  || '(pccr_founder_bind_untrusted_connection), so no management or migration connection can produce '
  || 'the row the append-only trigger exists to protect. The trigger itself is deployed, unchanged, '
  || 'and still asserted directly against its own 23514 refusals in '
  || 'scripts/checks/protected_table_guards_actually_fire.test.mjs.',
  'A founder bearer token presented to /rest/v1/rpc through PostgREST, so that '
  || 'fn_phase_c_founder_subject_bind resolves a verified subject and fn_kernel_refund_decision_record '
  || 'can record a real decision for the probe to then fail to edit. Only the founder can produce '
  || 'that token; nothing in this repository can, and PCCR-006 exists to keep it that way.',
  now())
ON CONFLICT (defect_id) DO NOTHING;

DO $assert$
DECLARE v_disp text; v_n int;
BEGIN
  SELECT disposition INTO v_disp FROM public.phase_d_injected_defect_disposition
   WHERE defect_id = 'PD-FIN-004';
  IF v_disp IS DISTINCT FROM 'DEFERRED_TO_A_BUILT_PATH' THEN
    RAISE EXCEPTION 'PD-FIN-004 disposition is % and should be DEFERRED_TO_A_BUILT_PATH',
      coalesce(v_disp,'(absent)') USING errcode = '23514';
  END IF;

  -- THE REGISTER MUST NOT GROW BY ACCIDENT. One deferred case is a stated cost; a second one
  -- appearing without its own file is the shape this estate has been bitten by before.
  SELECT count(*) INTO v_n FROM public.phase_d_injected_defect_disposition;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'the disposition register holds % row(s); this file accounts for exactly 1', v_n
      USING errcode = '23514';
  END IF;
  RAISE NOTICE 'PD-FIN-004 deferred; disposition register holds % row', v_n;
END $assert$;
