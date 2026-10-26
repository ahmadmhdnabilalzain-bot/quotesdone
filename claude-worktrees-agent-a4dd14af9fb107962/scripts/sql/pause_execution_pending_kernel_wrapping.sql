-- PAUSE the deterministic execution crons pending kernel-compliant trace-wrapping.
--
-- Turning on the execution layer (turn_on_execution_layer.sql, department_ops_heartbeat.sql) re-enabled
-- action-pipeline crons that were never registered as traced phase_c kernel components. That turned the
-- kernel GATE active_state_changing_cron_components_not_wrapped red — and it is a gate, not a ratchet:
-- every state-changing cron must carry a kernel execution trace for accountability, and the required
-- count is 0. Rather than disclose that integrity gap away or rush the component registration and risk
-- another regression, the schedulers are held here until each cron is registered as a traced kernel
-- component (phase_c_component + phase_c_system_execution_wrapper, invoked via fn_kernel_cron_exec) and
-- re-enabled. The capability, the registered executors and the verified end-to-end proof all remain;
-- only the cron schedulers are paused. Re-enable them in the follow-up that makes them kernel-compliant.
--
--   node scripts/apply_sql.mjs scripts/sql/pause_execution_pending_kernel_wrapping.sql --apply --ddl

begin;
select cron.alter_job((select jobid from cron.job where jobname='action_invoke_dispatch_5min'), active := false);
select cron.alter_job((select jobid from cron.job where jobname='action_invoke_collect_5min'),  active := false);
select cron.alter_job((select jobid from cron.job where jobname='action_invoke_rpc_5min'),       active := false);
select cron.alter_job((select jobid from cron.job where jobname='action_head_drive_5min'),       active := false);
select cron.alter_job((select jobid from cron.job where jobname='dept_ops_heartbeat_hourly'),    active := false);
commit;
