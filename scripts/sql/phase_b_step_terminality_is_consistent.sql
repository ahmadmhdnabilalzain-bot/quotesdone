-- A workflow step's terminality is stated twice in phase_b_workflow_step: next_step_if_pass =
-- 'WORKFLOW_COMPLETE' AND is_closure_step. They must AGREE — a step cannot be a nonterminal step and a
-- closure step at once. All 257 baseline rows already agree.
--
-- Removing the Phase B freeze (founder order 2026-09-02) made the baseline editable, which is intended
-- — but "editable" is not "corruptible": flipping is_closure_step on a nonterminal step writes a
-- self-contradictory step, which the freeze had incidentally been the only thing refusing (Phase D
-- injected defect PD-STATE-003). This restores that refusal as a proper DATA-INTEGRITY CHECK, not a
-- change-control freeze: the architecture stays freely editable, a contradictory step stays refused,
-- and the refusal now comes from the invariant itself rather than a digest guard.
--
--   node scripts/apply_sql.mjs scripts/sql/phase_b_step_terminality_is_consistent.sql --apply --ddl

begin;

alter table public.phase_b_workflow_step
  drop constraint if exists phase_b_workflow_step_terminality_consistent;

alter table public.phase_b_workflow_step
  add constraint phase_b_workflow_step_terminality_consistent
  check ((next_step_if_pass = 'WORKFLOW_COMPLETE') = coalesce(is_closure_step, false));

commit;
