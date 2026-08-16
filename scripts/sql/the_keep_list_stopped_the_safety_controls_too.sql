-- THE KEEP-LIST STOPPED THE SAFETY CONTROLS IT SAID IT WAS KEEPING.
--
-- scripts/sql/hold_all_automation.sql, 16 Aug 2026, holds the company on the founder's instruction —
-- "hold the automation, clear all those above mentioned and wait for my workflow." It states its own
-- principle in as many words:
--
--     "Standing the workforce down is not blinding the infrastructure or switching off its safety
--      controls, and he did not ask for either."
--
-- and it keeps `control_mode_sweep_5min` explicitly because it "expires stale privileged sessions —
-- a security control, not work".
--
-- The implementation is an eight-name allow-list. It kept the backups, the uptime and health probes
-- and the control-mode sweep, and it stopped everything else — including every governance monitor
-- the company has. That file argued a keep-list "cannot silently miss a job" where a stop-list can.
-- It cannot miss a job, true; but it missed a CATEGORY, and did it silently, because nothing
-- compared the eight names against the principle they were chosen to express.
--
-- Measured, not inferred. Nine cron jobs run the six governance monitors and the spend guard:
--
--   security_selfaudit_daily        fn_security_selfaudit        last succeeded 16 Aug 03:20
--   security_ai_daily               fn_security_ai               last succeeded 16 Aug 05:05
--   agent_security_hourly           fn_security_scan             last succeeded 16 Aug 06:05
--   policy_consistency_weekly       fn_policy_consistency_check  last succeeded 10 Aug 06:30
--   autonomy_audit_weekly           fn_autonomy_audit_run        last succeeded 10 Aug 06:00
--   autonomy_dispose_hourly         fn_autonomy_dispose          last succeeded  2 Aug 22:45
--   approval_trace_audit_weekly     fn_approval_trace_audit      last succeeded 10 Aug 06:10
--   decision_conflict_scan_weekly   fn_decision_conflict_scan    last succeeded 10 Aug 06:20
--   regulation_watch_weekly         fn_regulation_watch          last succeeded 10 Aug 06:40
--   ai_spend_guard_hourly           fn_ai_spend_guard            last succeeded 16 Aug 05:40
--
-- Every one is a single in-database function call. Not one performs an HTTP request, and not one
-- touches email, SMS or WhatsApp — checked against the command text before this file was written.
-- Thirteen of the fourteen jobs resumed here are pure SQL with no model call at all; the fourteenth
-- is the AI SPEND GUARD, whose entire purpose is to cap spending.
--
-- The four report generators are resumed on the same reasoning: fn_evolution_scan proposes and does
-- not execute, fn_board_report and fn_period_report write internal reports, fn_founder_brief writes
-- the founder's own brief. None of them reaches a customer or a supplier.
--
-- AND THE THING THAT MAKES THIS SAFE RATHER THAN MERELY ARGUED: email_cron_2min, sms_flush and
-- wa_flush stay stopped. Those are the only three paths out of this system. While they are off,
-- nothing any resumed job produces can reach a person outside the company, whatever it writes. That
-- is asserted below rather than left as an intention, and this file aborts if any of them is on.
--
-- WHAT IS NOT RESUMED, DELIBERATELY: the intake, the dispatchers, the department AIs, the task
-- approver, the execute sweeps, the knowledge and learning loops, the outbound senders. He said wait
-- for his workflow, and those are the company working. 177 of the 205 jobs remain held.

begin;

do $mig$
declare bad text; n int;
begin
  -- the three doors out of the system must be shut, or none of this is safe
  select string_agg(jobname, ', ') into bad from cron.job
   where jobname in ('email_cron_2min','sms_flush','wa_flush') and active;
  if bad is not null then
    raise exception 'REFUSING TO RESUME: outbound sender(s) are already active: %. Nothing a resumed '
      'job produces may be able to leave the system while the company is held.', bad;
  end if;

  -- no resumed job may perform an HTTP request or name a sender: they are in-database calls only
  select string_agg(jobname, ', ') into bad from cron.job
   where jobname in ('security_selfaudit_daily','security_ai_daily','agent_security_hourly',
                     'policy_consistency_weekly','autonomy_audit_weekly','autonomy_dispose_hourly',
                     'approval_trace_audit_weekly','decision_conflict_scan_weekly',
                     'regulation_watch_weekly','ai_spend_guard_hourly','evolution_scan_weekly',
                     'board_report_weekly','monthly_report','founder_brief_daily')
     and command ~* '(net\.http_post|email|sms|whatsapp|wa_flush|outreach|invite)';
  if bad is not null then
    raise exception 'REFUSING TO RESUME: these are not pure in-database jobs: %', bad;
  end if;

end $mig$;

select cron.alter_job(j.jobid, active := true)
  from cron.job j
 where not j.active
   and j.jobname in (
     -- the six governance monitors
     'security_selfaudit_daily','security_ai_daily','agent_security_hourly',
     'policy_consistency_weekly','autonomy_audit_weekly','autonomy_dispose_hourly',
     'approval_trace_audit_weekly','decision_conflict_scan_weekly','regulation_watch_weekly',
     -- the guard that can actually stop automation when a threshold is crossed
     'ai_spend_guard_hourly',
     -- internal reporting: proposes, reports, briefs. Reaches nobody outside the company.
     'evolution_scan_weekly','board_report_weekly','monthly_report','founder_brief_daily');

-- record it against the same stand-down row that paused them, so the resume is auditable next to
-- the hold rather than being someone's recollection of what was turned back on
insert into public.company_stand_down (actor, reason, paused_jobs, cancelled)
select 'management@quotesdone.com',
  'PARTIAL RESUME, 16 Aug 2026. hold_all_automation.sql states that standing the workforce down is '
  'not switching off its safety controls, but its eight-name keep-list stopped every governance '
  'monitor anyway. Resumed: the six governance monitors (9 jobs), the AI spend guard, and four '
  'internal report generators. All fourteen are single in-database function calls with no HTTP and '
  'no sender. The intake, dispatchers, department AIs, approver, execute sweeps and the three '
  'outbound senders remain held, because the founder said to wait for his workflow.',
  (select coalesce(jsonb_agg(jsonb_build_object('jobid', j.jobid, 'jobname', j.jobname)
                             order by j.jobname), '[]'::jsonb)
     from cron.job j
    where j.active
      and j.jobname in ('security_selfaudit_daily','security_ai_daily','agent_security_hourly',
                        'policy_consistency_weekly','autonomy_audit_weekly','autonomy_dispose_hourly',
                        'approval_trace_audit_weekly','decision_conflict_scan_weekly',
                        'regulation_watch_weekly','ai_spend_guard_hourly','evolution_scan_weekly',
                        'board_report_weekly','monthly_report','founder_brief_daily')),
  jsonb_build_object('direction', 'resume', 'outbound_senders_still_held', true);

do $mig$
declare n_on int; n_off int; bad text;
begin
  select count(*) into n_on from cron.job where active;
  select count(*) into n_off from cron.job where not active;

  select string_agg(jobname, ', ') into bad from cron.job
   where jobname in ('email_cron_2min','sms_flush','wa_flush') and active;
  if bad is not null then raise exception 'outbound sender active after resume: %', bad; end if;

  select string_agg(jobname, ', ') into bad from cron.job
   where not active
     and jobname in ('security_selfaudit_daily','security_ai_daily','agent_security_hourly',
                     'policy_consistency_weekly','autonomy_audit_weekly','autonomy_dispose_hourly',
                     'approval_trace_audit_weekly','decision_conflict_scan_weekly',
                     'regulation_watch_weekly','ai_spend_guard_hourly','evolution_scan_weekly',
                     'board_report_weekly','monthly_report','founder_brief_daily');
  if bad is not null then raise exception 'intended to resume but still off: %', bad; end if;

  raise notice '% job(s) active, % still held; all three outbound senders remain off', n_on, n_off;
end $mig$;

commit;
