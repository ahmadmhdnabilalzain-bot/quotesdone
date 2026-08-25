-- DOWN. RETURN PD-FIN-004 TO REPORTING NOT_REFUSED WHEN IT CANNOT REACH THE CONTROL.
--
-- NO TRANSACTION CONTROL. Two textual reversals applied to the live definition, so this file cannot
-- drift from the routine it reverses: a hand-copied 157KB body would be a second source of truth
-- for one object, and this routine is the one the Phase D injected-defect deliverable is built from.
--
-- APPLYING THIS restores the state that reddened CI: fn_phase_c_founder_subject_bind is called
-- bare, the PCCR-006 refusal aborts the subtransaction, and PD-FIN-004 comes out NOT_REFUSED --
-- which reads as "a founder refund decision can be updated or deleted" about a control the probe
-- never reached. The append-only trigger is not touched by either direction.

DO $down$
DECLARE v_src text; v_new text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_src FROM pg_proc
   WHERE proname = 'fn_phase_d_run_injected_defects' AND pronamespace = 'public'::regnamespace;

  -- 1. the emit: drop the NOT_RUN arm, back to two answers.
  v_new := regexp_replace(v_src,
    E'    if v_f4_msg like \'BIND_REFUSED%\'.*?    end if;\n', '', 'ns');
  IF v_new = v_src THEN
    RAISE NOTICE 'PD-FIN-004 already has no BIND_REFUSED arm; nothing to revert';
    RETURN;
  END IF;

  -- 2. the bind: back to a bare PERFORM.
  v_new := regexp_replace(v_new,
    E'      -- PCCR-006, 25 AUG 2026\\. THE BIND IS NOW A QUESTION.*?      end;\n',
    E'      perform public.fn_phase_c_founder_subject_bind(v_f4_sub);\n', 'ns');

  EXECUTE v_new;
  RAISE NOTICE 'PD-FIN-004: NOT_RUN arm removed, bind is bare again';
END $down$;
