-- ROLLBACK for phase_d_n10_the_nine_that_remain_classified_rather_than_exempted.sql
--
-- Returns the nine open cases to PERMANENT_EXEMPTION, drops the classification and missing_control
-- columns and their constraints, and narrows the disposition vocabulary back to its two values.
--
-- ORDER MATTERS: the rows must be moved off REAL_PRODUCT_GAP before the CHECK that permits it is
-- dropped and re-added without it, or the ALTER fails on the estate's own rows.
--
-- WHAT IS LOST: each row stops saying WHICH of the seven A-G classifications it is and what
-- specific control is missing. The reason text in the older 'reason' and
-- 'what_would_make_it_executable' columns is untouched and still carries the narrative.
update public.phase_d_injected_defect_disposition
   set disposition = 'PERMANENT_EXEMPTION'
 where disposition = 'REAL_PRODUCT_GAP';
alter table public.phase_d_injected_defect_disposition
  drop constraint if exists phase_d_injected_defect_disposition_gap_names_control_ck;
alter table public.phase_d_injected_defect_disposition
  drop constraint if exists phase_d_injected_defect_disposition_classification_ck;
alter table public.phase_d_injected_defect_disposition
  drop column if exists classification,
  drop column if exists missing_control;
alter table public.phase_d_injected_defect_disposition
  drop constraint if exists phase_d_disposition_value_ck;
alter table public.phase_d_injected_defect_disposition
  add constraint phase_d_disposition_value_ck
  check (disposition = any (array['PERMANENT_EXEMPTION','DEFERRED_TO_A_BUILT_PATH']));
