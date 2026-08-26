-- DOWN. REMOVE THE PD-FIN-004 DISPOSITION ROW.
--
-- NO TRANSACTION CONTROL. One DELETE.
--
-- APPLYING THIS returns the disposition register to 0 rows, which is what regression item 16 of
-- PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1 froze -- and leaves PD-FIN-004 reporting NOT_RUN with a
-- named blocker and nobody's decision attached to it, which the deliverable builder refuses:
--
--   named in the disposition register  0 of 1
--   NOT IN THE REGISTER: PD-FIN-004
--
-- So this reverts one red into a different red. It exists so the change is reversible, not because
-- reverting is advisable. Regenerate the register after applying:
--
--   node scripts/phase_d/build_exemption_register.mjs

DELETE FROM public.phase_d_injected_defect_disposition WHERE defect_id = 'PD-FIN-004';
