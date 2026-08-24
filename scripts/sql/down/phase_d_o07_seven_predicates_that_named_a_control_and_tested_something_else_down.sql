-- DOWN for O07. Classification: mixed. One additive table + trigger + routine (reversed here), four
-- register-row UPDATEs (restored here to the exact prior strings), and two ROUTINE_RESTORE
-- replacements of fn_phase_d_rule_check and fn_phase_d_gate_evaluate.
--
-- THE TWO ROUTINE BODIES ARE NOT REPRODUCED IN THIS FILE. They are ~1,200 lines each and a
-- hand-copied duplicate is the shape that has already put a wrong body live in this estate. The
-- restore is: re-apply the last file before O07 that defines each routine, chosen by
-- scripts/sql/MANIFEST.txt position -- which is what scripts/checks/canonical_routine_manifest.mjs
-- reads -- and confirm with `node scripts/checks/canonical_routine_manifest.mjs --all` reporting
-- 0 repository -> production drift. Verification after rollback: BR-018 with
-- {'quote_revision_ref':'x','platform_edited':'false'} returns ENFORCED_PASS again (its pre-O07
-- behaviour, and the defect), and GATE-027 with all declared evidence returns PASSED.

DROP TRIGGER IF EXISTS a10_phase_d_legal_assertion_source ON public.phase_d_legal_assertion;
DROP FUNCTION IF EXISTS public.fn_phase_d_legal_assertion_source_is_current();
DROP TABLE IF EXISTS public.phase_d_legal_assertion;

UPDATE public.phase_d_gate_contract SET evidence_source =
  'the approved supplier-safe package revision and its independent reviewer' WHERE gate_id = 'GATE-013';
UPDATE public.phase_d_gate_contract SET evidence_source =
  'public.quote_comparisons ownership' WHERE gate_id = 'GATE-018';
UPDATE public.phase_d_gate_contract SET evidence_source =
  'critical reconciliations and control exceptions' WHERE gate_id = 'GATE-027';
UPDATE public.phase_d_gate_contract SET evidence_source =
  'the legal, compliance and risk review, plus the founder gate where required' WHERE gate_id = 'GATE-028';
