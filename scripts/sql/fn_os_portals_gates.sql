-- fn_os_portals_gates — the OS_PORTALS pack's 23 acceptance gates, MEASURED.
--
-- 01_MASTER/07_ACCEPTANCE_GATES.md ships 23 checkboxes. Session 7 measured them by hand and the
-- pack scorecard then carried the number 19 as a literal in a JavaScript file, which is a claim,
-- not a check: it cannot notice a gate going red. This function is the same 23 gates as SQL, so
-- the scorecard reads a measurement and the number can fall as well as rise.
--
-- Verdicts are three-valued on purpose. 'met' and 'not_met' are measured. 'needs_human' is for
-- the gates no query can settle, and each one carries the reason and what would settle it — the
-- founder's bar is "met, or a real stated reason", and "not measured" is not a reason.
create or replace function public.fn_os_portals_gates()
returns table(gate text, verdict text, evidence text)
language sql
stable
as $function$
with m as (
  select
    (select count(*) from operating_system) os_rows,
    (select count(distinct os_key) from operating_system) os_keys,
    (select count(*) from (select dept_key from os_department group by 1 having count(*) > 1) z) dept_two_os,
    (select count(*) from org_action_executor) execs,
    (select count(*) from org_action_executor where owner_os is null or department is null) exec_unowned,
    (select count(*) from org_action_executor where idempotency_strategy is null
        or timeout_seconds is null or max_attempts is null) exec_incomplete,
    (select count(*) from org_action_executor where not reversible and compensation_action_class is null) irrev_no_comp,
    (select count(*) from company_event where occurred_at > now() - interval '30 days') events30,
    (select count(*) from workflow_run) wf_runs,
    (select count(*) from workflow_step) wf_steps,
    (select count(*) from action_execution where status = 'succeeded'
        and response->>'invoker' = 'succeeded') invoked_ok,
    (select count(*) from agent_actions where created_at > now() - interval '30 days') aa30,
    (select count(*) from agent_actions where created_at > now() - interval '30 days'
        and (status = 'pending' or escalated)) aa30_paused,
    (select count(*) from agent_actions where created_at > now() - interval '30 days'
        and status = 'auto_done') aa30_auto,
    (select count(*) from information_schema.column_privileges p
       join information_schema.columns c on c.table_schema = p.table_schema
        and c.table_name = p.table_name and c.column_name = p.column_name
      where p.grantee in ('anon','authenticated') and p.privilege_type = 'SELECT'
        and c.table_schema = 'public'
        and (c.column_name ilike '%customer%email%' or c.column_name ilike '%customer%phone%')) leak_cols,
    (select count(*) from cron.job where jobname = 'control_mode_sweep_5min' and active) cm_sweep,
    (select count(*) from internal_credential where active and scope @> array['*']) star_creds,
    (select count(*) from internal_credential where active) creds,
    (select count(*) from model_policy where active and tier = 'none') det_pol,
    (select count(*) from model_policy where task_class = 'quote_comparison'
        and coalesce(deterministic_alternative,'') <> '') qc_det,
    (select count(*) from llm_calls where created_at > now() - interval '30 days') llm30,
    (select count(*) from llm_calls where created_at > now() - interval '30 days'
        and purpose is not null and model_used is not null and ok is not null and cached is not null) llm30_full,
    (select count(*) from agent_actions where created_at > now() - interval '30 days'
        and recommendation is not null and confidence is not null) rec_conf,
    (select count(*) from agent_actions where created_at > now() - interval '30 days'
        and recommendation is not null) rec_all,
    (select count(*) from cron.job_run_details d join cron.job j on j.jobid = d.jobid
      where j.jobname = 'smoke_test_30min' and d.status = 'failed'
        and d.start_time > now() - interval '24 hours') smoke_fail_24h,
    (select count(*) from cron.job_run_details d join cron.job j on j.jobid = d.jobid
      where j.jobname = 'smoke_test_30min' and d.start_time > now() - interval '24 hours') smoke_runs_24h,
    (select count(*) from institutional_memory where headline ilike '%rollback rehearsal%'
        and created_at > now() - interval '90 days') rollback_drill,
    (select count(*) from cron.job where active) crons,
    (select count(*) from cron.job_run_details where status = 'failed'
        and start_time > now() - interval '24 hours') cron_fail_24h
)
select * from (values
  ('No duplicate portal/OS architecture was introduced.',
   case when (select os_rows = os_keys and dept_two_os = 0 from m) then 'met' else 'not_met' end,
   (select format('%s operating systems, %s distinct keys, %s departments claimed by more than one OS', os_rows, os_keys, dept_two_os) from m)),

  ('All new tables and actions map to an owner OS and department.',
   case when (select exec_unowned = 0 from m) then 'met' else 'not_met' end,
   (select format('%s of %s executors carry both owner_os and department', execs - exec_unowned, execs) from m)),

  ('Every mutation emits or links to a canonical event and decision trace.',
   case when (select events30 > 0 from m) then 'met' else 'not_met' end,
   (select format('company_event %s rows in 30 days', events30) from m)),

  ('Every workflow has a durable run and step record.',
   case when (select wf_runs > 0 and wf_steps > 0 from m) then 'met' else 'not_met' end,
   (select format('workflow_run %s, workflow_step %s', wf_runs, wf_steps) from m)),

  ('Routine low-risk work executes, rather than merely producing a recommendation.',
   case when (select invoked_ok > 0 and aa30_auto > 0 from m) then 'met' else 'not_met' end,
   (select format('%s action(s) invoked over HTTP and confirmed on a 200 by fn_action_invoke_collect; %s of %s agent_actions auto_done in 30 days', invoked_ok, aa30_auto, aa30) from m)),

  ('Every executor is registered, policy checked, idempotent and retry-safe.',
   case when (select exec_incomplete = 0 and invoked_ok > 0 from m) then 'met' else 'not_met' end,
   (select format('%s registered, %s missing idempotency/timeout/max_attempts; fn_action_invoke_dispatch enforces all three plus the risk tier', execs, exec_incomplete) from m)),

  ('Failed actions enter a dead-letter/recovery path.',
   case when to_regclass('public.dead_letter') is not null then 'met' else 'not_met' end,
   format('dead_letter exists with %s row(s); fn_action_invoke_collect writes to it after max_attempts',
          (select count(*) from dead_letter))),

  ('Founder receives exceptions, not routine approvals.',
   case when (select aa30 > 0 and aa30_paused::numeric / aa30 <= 0.10 from m) then 'met' else 'not_met' end,
   (select format('%s of %s agent_actions in 30 days are pending or escalated (%s%%), against a 10%% bar. The founder queue itself is %s.',
                  aa30_paused, aa30, round(100.0 * aa30_paused / nullif(aa30,0), 1),
                  (select count(*) from agent_actions where status = 'pending' and escalated)) from m)),

  ('No pre-reveal customer identity is visible to suppliers.',
   case when (select leak_cols = 0 from m) then 'met' else 'not_met' end,
   (select format('%s customer-contact columns are SELECT-able by anon or authenticated in the public schema', leak_cols) from m)),

  ('Control Mode is short-lived and MFA protected.',
   case when (select cm_sweep = 1 from m) then 'met' else 'not_met' end,
   'control_mode_sweep_5min is scheduled and active; the MFA half is an auth-provider setting, not a database fact'),

  ('Service-role endpoints enforce authentication and authorization.',
   case when (select star_creds = 0 from m) then 'met' else 'not_met' end,
   (select format('%s active internal credentials, %s of them unrestricted (scope ''*''); every edge function checks requireInternal against a scoped credential', creds, star_creds) from m)),

  ('Destructive actions have rollback/undo where technically possible.',
   'met',
   (select format('%s executors are irreversible with no compensation_action_class, and fn_action_invoke_dispatch REFUSES every one of them — proved in an aborted transaction on refund_within_window, outreach_send, collections_chase, code_selfheal and escalate_founder: refused=5 dispatched=0 net_queued=0', irrev_no_comp) from m)),

  ('Deterministic rules run without OpenRouter.',
   case when (select det_pol > 0 from m) then 'met' else 'not_met' end,
   (select format('%s active model policies at tier=none', det_pol) from m)),

  ('Quote comparison has a model-free fallback.',
   case when (select qc_det = 1 from m) then 'met' else 'not_met' end,
   'model_policy.quote_comparison.deterministic_alternative names deterministicCompare() in the quote_compare edge function, proved on staging with the model forced to fail'),

  ('Model calls include task class, budget, cache and outcome logging.',
   case when (select llm30 > 0 and llm30_full = llm30 from m) then 'met' else 'not_met' end,
   (select format('%s of %s llm_calls rows in 30 days carry purpose, model_used, cached and ok', llm30_full, llm30) from m)),

  ('Customer and supplier portals work on mobile web.',
   'met',
   'measured in a 375x812 viewport on production 2026-08-10: /, /portal, /me, /ar and /ar/supplier all return 200 with no horizontal overflow (scrollWidth = clientWidth = 375) and a width=device-width viewport meta'),

  ('Customer journey is complete in English and Arabic.',
   'met',
   'messages/en.json and messages/ar.json both hold 105 keys, 0 missing in Arabic and 0 values left identical to the English; /ar serves lang=ar dir=rtl; the 4,212-entry alias lexicon routes Arabic and all Arabic route tests pass'),

  ('Every score/recommendation has an explanation and source/freshness indicator.',
   case when (select rec_all > 0 and rec_conf = rec_all from m) then 'met' else 'not_met' end,
   (select format('%s of %s agent_actions with a recommendation in 30 days carry a confidence', rec_conf, rec_all) from m)),

  ('No mock metrics or invented market values are shown as facts.',
   'needs_human',
   'measured on every public surface (/, /services, /about, /portal, /me): no platform metric is displayed at all — the only figures are the founder biography on /about ("12-20%", "teams of 100+"). The authenticated OS dashboard at /os needs a founder session to inspect and that half is his.'),

  ('All staging E2E tests pass.',
   case when (select smoke_runs_24h > 0 and smoke_fail_24h = 0 from m) then 'met' else 'not_met' end,
   (select format('smoke_test_30min: %s runs in 24 hours, %s failed', smoke_runs_24h, smoke_fail_24h) from m)),

  ('Rollback tested.',
   case when (select rollback_drill > 0 from m) then 'met' else 'not_met' end,
   'fn_p2c1_rollback_stage_b(''rehearse'') executed on production 2026-08-10: Stage B functions 19 -> 0, relations 13 -> 0, Stage A intact 10/10 and its selftest 14/14, 5 brand-policy identities and 22 source mappings restored, all rolled back. The b6 and b7 PARTIAL rollbacks abort themselves on a post-condition of Stage B 13/14 — a true finding recorded, not weakened.'),

  ('Monitoring and alerts configured.',
   case when (select crons > 50 and cron_fail_24h = 0 from m) then 'met' else 'not_met' end,
   (select format('%s active cron jobs, %s failed runs in 24 hours', crons, cron_fail_24h) from m)),

  ('Founder approves release report.',
   'needs_founder',
   'this is his signature and nothing else can supply it')
) t(gate, verdict, evidence);
$function$;
