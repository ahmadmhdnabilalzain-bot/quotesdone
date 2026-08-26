-- DOWN. RETURN FDR-002 TO RESERVING EVERY RUN OF THE WORKFLOWS IT NAMES.
--
-- NO TRANSACTION CONTROL. One DELETE and a restore of the resolver's old coverage line.
--
-- APPLYING THIS puts back the reading the founder overruled on 26 Aug 2026: a workflow named in any
-- boundary's workflow_scope cannot proceed on delegated authority, whatever the boundary says. Its
-- measured effect is that W04-S04 "Capture canonical terms acceptance", W09-S06 "Capture canonical
-- supplier terms acceptance" and W15-S06 "Calculate founder-approved reveal charge" refuse every
-- run with pd_evidence_absent -- i.e. a customer cannot accept the terms and the reveal charge
-- cannot be calculated without a founder command per run, which is the opposite of what he said
-- ("it's automated. It doesn't need me").
--
-- It exists so the change is reversible, not because reverting is advisable. It does NOT drop the
-- register: the classification and the ruling that produced it are a record, and deleting a record
-- of what he decided is not a rollback of code.

-- 1. Take FDR-002 out of the classification, which is all the resolver reads.
DELETE FROM public.phase_d_founder_boundary_disposition WHERE boundary_id = 'FDR-002';

-- 2. Restore the one-line coverage test, by rewriting the live definition rather than pasting a
--    body: a hand-copied routine would be a second source of truth for one object.
DO $down$
DECLARE v_src text; v_new text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_src FROM pg_proc
   WHERE proname = 'fn_phase_d_founder_authority' AND pronamespace = 'public'::regnamespace;
  v_new := regexp_replace(v_src,
    E'  -- HIS RULING OF 26 AUG 2026.*?  v_covers  := v_reserving is null;',
    E'  v_covers  := v_reserved is null;', 'ns');
  IF v_new = v_src THEN
    RAISE NOTICE 'fn_phase_d_founder_authority already reads v_reserved; nothing to revert';
    RETURN;
  END IF;
  EXECUTE v_new;
  RAISE NOTICE 'fn_phase_d_founder_authority: coverage is presence-in-scope again';
END $down$;
