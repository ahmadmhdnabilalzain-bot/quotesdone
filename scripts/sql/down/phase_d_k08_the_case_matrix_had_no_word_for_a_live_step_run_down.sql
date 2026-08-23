-- =================================================================================================
-- PHASE D DOWN — reverses scripts/sql/phase_d_k08_the_case_matrix_had_no_word_for_a_live_step_run.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql path. This file is a hand-run
-- rollback. A person opens it, reads the block below, accepts it, and runs it.
--
-- OBJECTS REVERSED, by name:
--   constraint public.phase_d_step_case_result.phase_d_step_case_result_level_ck — narrowed back to
--   the four values it held before K08, dropping 'live_step_run'.
--
-- IT REFUSES RATHER THAN LEAVING THE TABLE ILLEGAL. Dropping a value from a CHECK while rows still
-- carry it would leave public.phase_d_step_case_result holding a decided_at its own constraint
-- forbids -- readable, exportable, and invalid. The guard below counts those rows first and stops
-- with the count. Re-run the contract-level matrix (select public.fn_phase_d_run_step_cases();)
-- before this file if you mean to go back to the four levels.
--
-- ROW COUNT AT RISK: none. No row is deleted and no column is dropped; only the constraint changes.
-- =================================================================================================

begin;

do $down$
declare v_n bigint;
begin
  select count(*) into v_n from public.phase_d_step_case_result where decided_at = 'live_step_run';
  if v_n > 0 then
    raise exception
      'phase_d_step_case_result still holds % row(s) whose decided_at is live_step_run. Narrowing the constraint now would leave the table in a state its own CHECK forbids. Re-decide those cases at one of the four earlier levels first.', v_n
      using errcode = '23514';
  end if;
end $down$;

alter table public.phase_d_step_case_result
  drop constraint if exists phase_d_step_case_result_level_ck;

alter table public.phase_d_step_case_result
  add constraint phase_d_step_case_result_level_ck
  check (decided_at = any (array['step_contract'::text, 'executor_boundary'::text,
                                 'kernel_boundary'::text, 'structural_constraint'::text]));

commit;
