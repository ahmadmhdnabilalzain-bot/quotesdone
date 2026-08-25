-- DOWN. RETURN THE DELEGATED ANSWER TO CLAIMING THE WORKFLOW HAS NO BOUNDARY.
--
-- NO TRANSACTION CONTROL. Two textual reversals applied to the live definition, so this file cannot
-- drift from the routine it reverses.
--
-- APPLYING THIS restores the sentence that reads, for W04-S04, "it names no boundary over W04" and
-- "reserves no decision in W04" while the same object's in_scope_of field says FDR-002. The VERDICT
-- is unchanged either way -- this only reverts what the resolver says about itself -- but it leaves
-- an untrue sentence next to a correct number, which is the shape this estate keeps being caught
-- by. It exists so the change is reversible, not because reverting is advisable.

DO $down$
DECLARE v_src text; v_new text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_src FROM pg_proc
   WHERE proname = 'fn_phase_d_founder_authority' AND pronamespace = 'public'::regnamespace;

  v_new := regexp_replace(v_src,
    E'\'source\',  \'public\\.phase_b_founder_boundary, the founder-approved frozen register of what he \'\n            \\|\\| \'reserves: \'\n.*?to the step\'\'s accountable role\',',
    E'''source'',  ''public.phase_b_founder_boundary, the founder-approved frozen register of what he ''\n            || ''reserves: it names no boundary over '' || v_wf || '', so the decision is delegated ''\n            || ''to the step''''s accountable role'',',
    'ns');

  v_new := regexp_replace(v_new,
    E'\'baseline and reserves no ACT in %s%s\',.*?end\\)\\);',
    E'''baseline and reserves no decision in %s'',\n                  (select count(*) from public.phase_b_founder_boundary),\n                  coalesce(left(v_digest, 16), ''(none)''),\n                  case when v_current then ''matches'' else ''DOES NOT match'' end, v_wf));',
    'ns');

  IF v_new = v_src THEN
    RAISE NOTICE 'fn_phase_d_founder_authority already carries the older sentences; nothing to revert';
    RETURN;
  END IF;
  EXECUTE v_new;
  RAISE NOTICE 'fn_phase_d_founder_authority: delegated answer no longer names the covering boundaries';
END $down$;
