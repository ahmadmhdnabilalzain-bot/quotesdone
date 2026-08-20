-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of
-- scripts/sql/phase_d_d10_seven_cases_for_every_one_of_the_257_steps.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the row count below, accepts it, and runs it.
--
-- OBJECT DROPPED, by name (never `cascade`):
--   public.phase_d_step_case_result — 8 columns, primary key (step_id, case_kind), with
--   phase_d_step_case_result_kind_ck (7 values), _level_ck (4 values), and
--   phase_d_step_case_result_step_fkey -> public.phase_b_workflow_step(step_id) ON DELETE CASCADE
--
-- ROW COUNT AT RISK — READ THIS ONE TWICE (measured on htdblwldjkcgjvmqkbeh; WORKLIST D.3 "Data at
-- risk on a drop" and D.1 item 17):
--
--   public.phase_d_step_case_result   1,799 rows
--
-- This is the largest single loss in the Phase D estate and the only Phase D table holding
-- substantial non-registry data: seven case results for each of the 257 frozen steps, minus the
-- combinations that do not apply. Every other Phase D table is a registry that can be re-derived by
-- re-running its own file. These rows are outcomes — they record what happened when each case ran,
-- and re-running the file does not reproduce a past run. Take a copy before running this file:
--
--     create table zz_backup_phase_d_step_case_result as
--       select * from public.phase_d_step_case_result;
--
-- (that backup is a suggestion in a comment, not a statement this file executes — a rollback script
-- that silently leaves tables behind is its own kind of surprise).
--
-- KNOWN CONSUMER: WORKLIST C.1 item 3 has scripts/phase_d/build_d0_crosswalk.mjs joining this table
-- so that PHASE_D_CURRENT_CODE_HANDLER_CROSSWALK.csv stops reading 257/257 NOT_RUN. After this
-- rollback that join returns nothing and the crosswalk goes back to NOT_RUN everywhere.
--
-- NOT TOUCHED: the three CREATE OR REPLACE FUNCTION bodies in d10. A create-or-replace has no down
-- — see scripts/sql/down/README.md.
-- =================================================================================================

begin;

drop table if exists public.phase_d_step_case_result;

do $ctl$
begin
  if to_regclass('public.phase_d_step_case_result') is not null then
    raise exception 'D10 down did not take: public.phase_d_step_case_result is still present.';
  end if;

  raise notice 'D10 down: phase_d_step_case_result is gone, and with it 1,799 recorded case outcomes.';
end $ctl$;

commit;
