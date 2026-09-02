-- THE OWNERSHIP LEDGER NAMED THE SWEEP FILE THE MANIFEST HAD SUPERSEDED.
--
-- NO TRANSACTION CONTROL. One UPDATE and an assertion.
--
-- CI "the Phase C kernel gate" runs application_source_of_truth, which reported:
--
--   6. ledger claims the repository denies             1 / 1225
--     public.fn_workflow_step_sweep(p_limit integer)  records source_file
--       scripts/sql/the_rpc_half_of_the_executor_table_had_no_runner.sql,
--       manifest order says scripts/sql/workflow_sweep_stranded_by_cancelled_action.sql
--
-- public.kernel_routine_ownership records, per routine, WHICH FILE the estate considers its source.
-- scripts/sql/MANIFEST.txt decides canon by position, so the moment a later file redefines a routine
-- the ledger's stored answer becomes the previous one. fn_workflow_step_sweep was redefined on
-- 2 Sep 2026 by scripts/sql/workflow_sweep_stranded_by_cancelled_action.sql (classifying a step
-- stranded by a terminal action_execution out of parked_unexplained), and the ledger was not updated
-- then. The routine did not drift -- lines 1-5 and 7 of that report are all 0 -- the ledger simply
-- had not been told which file now defines it.
--
-- WHY THIS IS A DATA FIX AND NOT A CODE FIX. The ledger is a recorded fact, not a derivation; the
-- canonical engine (fn_kernel_routine_ownership) computes the same answer live and line 7 reports 0.
-- That two instruments disagreed about one subject is precisely what line 6 exists to catch.
--
-- ROLLBACK: scripts/sql/down/the_ownership_ledger_named_the_sweep_file_the_manifest_superseded_down.sql

UPDATE public.kernel_routine_ownership
   SET source_file = 'scripts/sql/workflow_sweep_stranded_by_cancelled_action.sql'
 WHERE schema_name = 'public' AND routine_name = 'fn_workflow_step_sweep'
   AND source_file = 'scripts/sql/the_rpc_half_of_the_executor_table_had_no_runner.sql';

DO $assert$
DECLARE v_a text;
BEGIN
  SELECT source_file INTO v_a FROM public.kernel_routine_ownership
   WHERE schema_name = 'public' AND routine_name = 'fn_workflow_step_sweep';
  IF v_a IS DISTINCT FROM 'scripts/sql/workflow_sweep_stranded_by_cancelled_action.sql' THEN
    RAISE EXCEPTION 'fn_workflow_step_sweep still records source_file %', coalesce(v_a,'(none)')
      USING errcode = '23514';
  END IF;
  RAISE NOTICE 'ownership ledger: fn_workflow_step_sweep now names the manifest-canonical file';
END $assert$;
