-- Rollback for K37. Restores fn_kernel_write_guard as SECURITY DEFINER:
--
--   node scripts/apply_sql.mjs scripts/sql/kernel_k18_write_guard.sql --apply --ddl
--
-- REFUSE THIS UNLESS YOU MEAN IT. Under SECURITY DEFINER, current_user inside the guard is the
-- function's owner whoever called it, so the maintenance door's owner check compares the owner
-- against itself and is always true. The door then reduces to "state any reason and pass", and any
-- Edge Function holding the service key can write phase_c_workflow_run, phase_c_task, the trigger
-- inbox or the founder's refund ledger by adding one line:
--
--   set local kernel.maintenance_reason = 'anything';
--
-- Proved by scripts/checks/kernel_write_guard_both_directions.test.mjs, which reported
-- "ACCEPTED — SERVICE_ROLE MANUFACTURED KERNEL CONTEXT" against the SECURITY DEFINER version and
-- refuses it under this one. Run that check after any change here.
--
-- fn_kernel_record_maintenance_write may stay: it is the one privileged act the guard needs, it is
-- executable by nobody, and leaving it costs nothing.
select 'K37 rollback: re-apply scripts/sql/kernel_k18_write_guard.sql — which reopens the '
       'maintenance door to any caller that can set a GUC. Read the comment block first.' as instruction;
