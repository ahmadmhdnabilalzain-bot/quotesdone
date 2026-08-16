-- ---------------------------------------------------------------------------------------------
-- HOLD THE AUTOMATION. The full stop, not the partial one.
--
-- Founder, 16 Aug 2026: "hold the automation, clear all those above mentioned and wait for my
-- workflow."
--
-- The first stand-down paused the 69 cron jobs that INSERT into a work table. That was the wrong
-- boundary for what he asked. 117 jobs were still running, and reading the list makes the gap
-- obvious: agent_finance_weekly, legal_ai_daily, security_ai_daily, strategy_ai_daily,
-- operations_ai_daily, reporting_ai_daily, task_approve_hourly, org_task_execute_sweep_hourly,
-- agent_action_work_sweep_hourly, the three action_invoke_* dispatchers, the knowledge and
-- learning loops, the report generators. None of those matched the INSERT pattern and every one of
-- them is the company working.
--
-- So the rule is inverted. Instead of naming what to stop — which is how the first pass missed
-- half of it — this names the ONLY things allowed to keep running, and stops everything else.
-- A keep-list cannot silently miss a job; a stop-list can, and did.
--
-- STILL RUNNING, deliberately, and this is the whole list:
--   backup_daily             the backup
--   dropbox_backup_scan      the backup
--   dropbox_sync_daily       the backup
--   health_check             is the system up
--   uptime_check_15min       is the system up
--   ai_health_15min          is the system up
--   smoke_test_30min         is the system up
--   control_mode_sweep_5min  expires stale privileged sessions — a security control, not work
--
-- Standing the workforce down is not blinding the infrastructure or switching off its safety
-- controls, and he did not ask for either.
--
-- OUTBOUND SENDERS ARE STOPPED TOO — email_cron_2min, sms_flush, wa_flush. With every queue at
-- zero there is nothing legitimate to send, and a paused company that still emails people is not
-- paused. This is the one item that could surprise: no email, SMS or WhatsApp will leave the
-- system until the automation is resumed.
--
-- REVERSIBLE EXACTLY. Every paused jobid is recorded in public.company_stand_down.paused_jobs, so
-- the resume is a replay of that list rather than someone's memory of which jobs were on.
-- ---------------------------------------------------------------------------------------------

insert into public.company_stand_down (actor, reason, paused_jobs, cancelled)
select 'management@quotesdone.com',
  'Founder instruction, 16 Aug 2026: "hold the automation ... and wait for my workflow." Full '
  'hold. The earlier stand-down used a stop-list of work-INSERTing routines and missed 117 jobs, '
  'including every department AI, the task approver, the execute sweep and the three action '
  'dispatchers. This pass uses a KEEP-list instead — backup, uptime/health probes and the '
  'control-mode security sweep — and pauses everything else, because a keep-list cannot silently '
  'miss a job. Outbound senders are included: a paused company that still emails people is not '
  'paused.',
  (select coalesce(jsonb_agg(jsonb_build_object('jobid', j.jobid, 'jobname', j.jobname)
                             order by j.jobname), '[]'::jsonb)
     from cron.job j
    where j.active
      and j.jobname not in ('backup_daily','dropbox_backup_scan','dropbox_sync_daily',
                            'health_check','uptime_check_15min','ai_health_15min',
                            'smoke_test_30min','control_mode_sweep_5min')),
  jsonb_build_object('note', 'queues already at zero from the first stand-down')
 where exists (select 1 from cron.job j
                where j.active
                  and j.jobname not in ('backup_daily','dropbox_backup_scan','dropbox_sync_daily',
                                        'health_check','uptime_check_15min','ai_health_15min',
                                        'smoke_test_30min','control_mode_sweep_5min'));

select cron.alter_job(j.jobid, active := false)
  from cron.job j
 where j.active
   and j.jobname not in ('backup_daily','dropbox_backup_scan','dropbox_sync_daily',
                         'health_check','uptime_check_15min','ai_health_15min',
                         'smoke_test_30min','control_mode_sweep_5min');
