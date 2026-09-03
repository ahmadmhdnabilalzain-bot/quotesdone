-- REGISTER resilience_drill_daily (job 321) as a Phase D committed-scenario cron source.
--
-- fn_phase_d_committed_scenario_open refuses to open while any ACTIVE cron that reaches a
-- kernel-watched relation is unregistered ("every_active_cron_that_reaches_a_watched_relation_is_
-- registered: … 321 resilience_drill_daily"), which turned the kernel_positive_controls door
-- fn_phase_d_committed_scenario_close red the moment the drill was scheduled. Same pattern as
-- register_self_management_crons_phase_d.sql.
--
-- WHAT fn_dr_drill ACTUALLY WRITES, measured from its body rather than asserted:
--   committed  — public.critical_capability (last_verdict, last_checked), public.continuity_plan
--                (last_tested, last_result), public.agent_runs ('resilience_drill' and, through
--                fn_capability_verify, 'capability_verify'), public.agent_actions (one IT ticket per
--                day of failures), public.founder_alerts (fn_capability_verify, only for a suite
--                verdict of 'failing'), and net.http_request_queue when the restore drill is stale.
--   rolled back — every probe_sql runs inside a subtransaction that ends in RAISE: the
--                decision_record insert, fn_dispute_open, fn_llm_log, fn_brand_scan and
--                fn_bi_snapshot never commit a row.
--
--   node scripts/apply_sql.mjs scripts/sql/register_the_resilience_drill_cron_phase_d.sql --apply --ddl

begin;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine) values
  (321, 'resilience_drill_daily',
   'Probes every critical capability and tests each continuity_plan service: UPDATEs public.critical_capability and public.continuity_plan (verdict/tested columns only), INSERTs public.agent_runs (resilience_drill, capability_verify), INSERTs public.agent_actions (one IT ticket per day of failed probes) and, via fn_capability_verify, public.founder_alerts for a suite verdict of failing; enqueues net.http_request_queue when no restore drill succeeded in 45 days. Probe DML (decision_record, disputes, llm log, brand scan, bi snapshot) runs in subtransactions that always roll back.',
   'Resilience drill (3 Sep 2026). Own transaction on a daily 04:20 UTC tick; reads only real rows about the real estate and cannot see a scenario''s uncommitted ZZ DEMO fixture; writes no scenario table; close() asserts scenario rows by id/marker, so its writes do not move the watermark.')
on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;

commit;
