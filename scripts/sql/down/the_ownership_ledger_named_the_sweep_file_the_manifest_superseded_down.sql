-- ROLLBACK of the_ownership_ledger_named_the_sweep_file_the_manifest_superseded.sql.
-- Restores the ledger's prior (superseded) source_file for fn_workflow_step_sweep. Only meaningful
-- if workflow_sweep_stranded_by_cancelled_action.sql is also rolled out of the manifest.

UPDATE public.kernel_routine_ownership
   SET source_file = 'scripts/sql/the_rpc_half_of_the_executor_table_had_no_runner.sql'
 WHERE schema_name = 'public' AND routine_name = 'fn_workflow_step_sweep'
   AND source_file = 'scripts/sql/workflow_sweep_stranded_by_cancelled_action.sql';
