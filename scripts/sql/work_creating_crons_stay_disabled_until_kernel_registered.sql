-- WORK-CREATING CRONS STAY DISABLED UNTIL REGISTERED AS KERNEL CRON SOURCES.
--
-- The four crons added this session — incident_watchdog_hourly, department_conflict_scan_weekly,
-- remediation_escalate_consume_daily, promotion_review_weekly — write kernel-WATCHED relations
-- (os_incidents, org_tasks, company_event, org_agents). The kernel refuses an ACTIVE cron that reaches a
-- watched relation unless it is registered as a kernel cron source: the Phase D committed-scenario guard
-- `every_active_cron_that_reaches_a_watched_relation_is_registered` and `kernel_boards_are_green`
-- (sources_in_the_population_with_no_classification / active_state_changing_cron_components_not_wrapped)
-- both go red otherwise. (This is exactly why outcome_evaluate_daily is also left disabled.)
--
-- Their FUNCTIONS are built and proven by aborted-tx probes; the crons are the WIRING, and this session's
-- rule is to build the wiring and never rely on a cron actually running while the workforce is stood
-- down. They stay DISABLED here until they are classified in phase_c_source_cutover and wrapped through
-- fn_kernel_cron_exec — Phase C kernel work, deliberately not done in this pass. This file runs LAST in
-- the manifest, so a full re-apply (which the earlier files schedule active) lands on the disabled state.
--
--   node scripts/apply_sql.mjs scripts/sql/work_creating_crons_stay_disabled_until_kernel_registered.sql --apply --ddl

begin;

select cron.alter_job(jobid, active := false)
  from cron.job
 where jobname in ('incident_watchdog_hourly', 'department_conflict_scan_weekly',
                   'remediation_escalate_consume_daily', 'promotion_review_weekly');

commit;
