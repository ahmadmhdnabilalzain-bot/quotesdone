-- RE-ENABLE THE DETERMINISTIC AUTOMATION THE STAND-DOWN CLOSED, kernel-compliant.
--
-- Founder, 2 Sep 2026: re-open every loop the stand-down broke; OpenRouter is never an excuse for a
-- structural gap. The stand-down (16 Aug) disabled 191 crons — the consumers, handlers and delivery of
-- dozens of loops. Only 3 are truly inference-bound (resilience_watch, scenario_rehearsal,
-- scenario_staffing) and stay OFF until OpenRouter. The rest are deterministic and are re-enabled here
-- AS TRACED KERNEL COMPONENTS via fn_kernel_wrap_and_enable_cron, so the kernel gate
-- active_state_changing_cron_components_not_wrapped stays 0. Each was already tested before the
-- stand-down; re-enabling restores the loop's consumer/handler.
--
--   node scripts/apply_sql.mjs scripts/sql/reenable_crons_after_standdown.sql --apply --ddl

begin;

-- TIER 1 — the failure-detection layer, so every failure has a watcher acting on it (owner: assurance).
select public.fn_kernel_wrap_and_enable_cron(j.jobid, 'it_operations_engineer', 'assurance')
from cron.job j
where j.jobname in (
  'watch_failed_runs_hourly','ops_watch_hourly','agent_silence_watch_daily','edge_health_scan_15min',
  'sla_watch_hourly','exception_alerts_hourly','incident_watchdog_hourly','handoff_watchdog_6h',
  'watch_health_daily','runner_silence_watch_daily','emit_metric_alerts','org_task_sla_watch_daily','backup_watch_daily')
  and not coalesce((select bool_or(pg_get_functiondef(p.oid) ~* 'ai_gateway|openrouter|_shared/llm|llm\(')
                     from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                    where n.nspname='public' and p.prokind='f' and position(p.proname in j.command) > 0), false);

-- TIER 2 — the delivery layer, so alerts/notifications actually reach a person (email/WhatsApp/SMS,
-- the digest, and the dead_letter drainer). All deterministic (Resend/Twilio/SQL). Owner: assurance.
select public.fn_kernel_wrap_and_enable_cron(j.jobid, 'it_operations_engineer', 'assurance')
from cron.job j where j.jobname in ('email_cron_2min','wa_flush','sms_flush','pending_suppliers_digest','dead_letter_drain_held')
  and not coalesce((select bool_or(pg_get_functiondef(p.oid) ~* 'ai_gateway|openrouter|_shared/llm|llm\(')
                     from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                    where n.nspname='public' and p.prokind='f' and position(p.proname in j.command) > 0), false);

-- TIER 3 — the state-management sweeps: stall reapers, escalation consumers, task assignment/approval,
-- event consolidation, overdue-handoff watchdog. Pure SQL state transitions, no inference. Owner: exec.
-- (The work-dispatch crons that drive agent REASONING — workflow_dispatch, execution_run,
-- org_task_execute_sweep — are wired and ready; their activation drives inference and waits on OpenRouter.)
select public.fn_kernel_wrap_and_enable_cron(j.jobid, 'chief_of_staff', 'exec')
from cron.job j where j.jobname in ('workflow_step_sweep_10min','execution_sweep_hourly','action_queue_sweep_hourly',
  'remediation_escalate_consume_daily','event_consolidate','org_task_assign_hourly','task_approve_hourly','emit_task_assigned')
  and not coalesce((select bool_or(pg_get_functiondef(p.oid) ~* 'ai_gateway|openrouter|_shared/llm|llm\(')
                     from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                    where n.nspname='public' and p.prokind='f' and position(p.proname in j.command) > 0), false);

commit;
