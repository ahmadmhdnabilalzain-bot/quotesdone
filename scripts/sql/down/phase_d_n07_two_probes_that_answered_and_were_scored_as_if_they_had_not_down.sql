-- ROLLBACK for phase_d_n07_two_probes_that_answered_and_were_scored_as_if_they_had_not.sql
--
-- Narrows the section 8 verdict vocabulary back to the four refusal-shaped values, restores the two
-- probe verdicts to what they said before, and removes the PD-PROV-004 mapping.
--
-- THE VERDICTS MUST BE RESTORED BEFORE THE CONSTRAINT IS NARROWED, or the ALTER fails on its own
-- rows. That ordering is the whole content of this file.
--
-- WHAT IS LOST: P2-document-scope and P3-supplier-surface-body go back to describing a correct
-- safe-scoped 200 as either a refusal or as undiscriminated, and PD-AUTH-002's justification
-- reverts to text that stopped being true when the probe was improved. Those are the defects N07
-- corrected; this file reintroduces them, deliberately, as a rollback must.
update public.phase_d_section8_probe_result
   set verdict = 'REFUSED_AS_REQUIRED'
 where probe_id = 'P2-document-scope' and verdict = 'SAFE_SCOPED_RESULT_AS_REQUIRED';
update public.phase_d_section8_probe_result
   set verdict = 'NOT_DISCRIMINATED'
 where probe_id = 'P3-supplier-surface-body' and verdict = 'SAFE_SCOPED_RESULT_AS_REQUIRED';
delete from public.phase_d_section8_probe_result where probe_id = 'P9-provider-bypass-scan';
delete from public.phase_d_section8_defect_map   where defect_id = 'PD-PROV-004';
alter table public.phase_d_section8_probe_result
  drop constraint if exists phase_d_section8_probe_result_verdict_check;
alter table public.phase_d_section8_probe_result
  add constraint phase_d_section8_probe_result_verdict_check
  check (verdict = any (array['REFUSED_AS_REQUIRED','NOT_REFUSED','NOT_RUN','NOT_DISCRIMINATED']));
