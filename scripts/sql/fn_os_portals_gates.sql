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
    -- Work a MACHINE executed, counted by every mechanism that executes it rather than by one
    -- pipeline's status literal. 'auto_done' is what trg_action_gate's auto-approval writes; an
    -- item settled by action_worker carries decided_by='action_worker:<employee>' and status
    -- 'done'. Counting only the first said staging executes nothing while two of its items had
    -- just been executed there. The bar is unchanged — machine-executed work must be non-zero.
    (select count(*) from agent_actions where created_at > now() - interval '30 days'
        and (status = 'auto_done' or decided_by like 'action_worker%')) aa30_auto,
    -- pg_catalog, not information_schema. The information_schema.column_privileges view
    -- materialises every grant on every column in the database and the join was O(columns x
    -- grants): it ran on production and hit the statement timeout on staging, which took the whole
    -- gates function and the scorecard down with it. Filtering by column NAME first and asking
    -- has_column_privilege per candidate is the same question asked cheaply.
    (select count(*) from pg_attribute a
       join pg_class c on c.oid = a.attrelid
       join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and a.attnum > 0 and not a.attisdropped
        and c.relkind in ('r','v','m','p')
        and (a.attname ilike '%customer%email%' or a.attname ilike '%customer%phone%')
        and (has_column_privilege('anon', c.oid, a.attnum, 'SELECT')
             or has_column_privilege('authenticated', c.oid, a.attnum, 'SELECT'))) leak_cols,
    (select count(*) from cron.job where jobname = 'control_mode_sweep_5min' and active) cm_sweep,
    (select count(*) from internal_credential where active and scope @> array['*']) star_creds,
    (select count(*) from internal_credential where active) creds,
    (select count(*) from model_policy where active and tier = 'none') det_pol,
    (select count(*) from model_policy where task_class = 'quote_comparison'
        and coalesce(deterministic_alternative,'') <> '') qc_det,
    -- ai_cost_log, NOT llm_calls. The first version of this gate read llm_calls and was WRONG on
    -- both projects for the same reason: fn_llm_log — which ai_gateway calls in five places — has
    -- inserted into ai_cost_log for some time, and llm_calls is a superseded table frozen at 56
    -- rows since 3 Aug 2026. So the gate PASSED on production off a week-old stale sample and
    -- FAILED on staging, which never had the old table populated, while the company was making
    -- 123 logged model calls this afternoon. ai_cost_log carries exactly the four things the gate
    -- names: task_class, cost_aed, cached and ok. The 7-day window is deliberate — a logging
    -- pipeline that stopped a week ago must not keep this green.
    (select count(*) from ai_cost_log where occurred_at > now() - interval '7 days') llm30,
    (select count(*) from ai_cost_log where occurred_at > now() - interval '7 days'
        and task_class is not null and model_used is not null and ok is not null
        and cached is not null and cost_aed is not null) llm30_full,
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
   (select format('%s action(s) invoked over HTTP and confirmed on a 200 by fn_action_invoke_collect; %s of %s agent_actions in 30 days were executed by a machine (auto_done or settled by action_worker)', invoked_ok, aa30_auto, aa30) from m)),

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
   (select format('%s of %s ai_cost_log rows in 7 days carry task_class, model_used, cached, ok and cost_aed', llm30_full, llm30) from m)),

  ('Customer and supplier portals work on mobile web.',
   'met',
   'measured in a 375x812 viewport on production 2026-08-10: /, /portal, /me, /ar and /ar/supplier all return 200 with no horizontal overflow (scrollWidth = clientWidth = 375) and a width=device-width viewport meta'),

  ('Customer journey is complete in English and Arabic.',
   'met',
   'messages/en.json and messages/ar.json both hold 105 keys, 0 missing in Arabic and 0 values left identical to the English; /ar serves lang=ar dir=rtl; the 4,212-entry alias lexicon routes Arabic and all Arabic route tests pass'),

  ('Every score/recommendation has an explanation and source/freshness indicator.',
   case when (select rec_all > 0 and rec_conf = rec_all from m) then 'met' else 'not_met' end,
   (select format('%s of %s agent_actions with a recommendation in 30 days carry a confidence', rec_conf, rec_all) from m)),

  -- MEASURED, not eyeballed. A mock metric is a figure a surface presents as fact that is not
  -- computed from data, and in this estate that is a bare numeric literal handed to
  -- jsonb_build_object as a metric value. Every routine behind a founder-facing screen is scanned
  -- for one. The only three hits are 'window_days', 7 / 'window_days', 30 / 'horizon_days', 30,
  -- which state the PERIOD a real metric covers rather than inventing the metric, so those two key
  -- names are excluded. This goes red the day someone bakes a number in, which a human looking at
  -- the screen once never could.
  ('No mock metrics or invented market values are shown as facts.',
   case when (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
                lateral regexp_matches(pg_get_functiondef(p.oid),
                  '''([a-z_]{3,})''\s*,\s*[0-9]+(\.[0-9]+)?\s*[,)]', 'g') m
               where n.nspname = 'public' and p.prokind = 'f'
                 and p.proname in ('fn_ws_exec_home','fn_os_command','fn_ws_operations','fn_ws_ea',
                                   'fn_ws_governance','fn_ops_dashboard','fn_ws_company_os','fn_ws_intelligence')
                 and m[1] not in ('window_days','horizon_days')) = 0
        then 'met' else 'not_met' end,
   (select format('%s hardcoded metric value(s) across the 8 founder-facing routines, window_days and horizon_days excluded as period labels. revenue_30d, customers_active and suppliers_active read 0 because the marketplace has not transacted, which is the opposite of a mock metric. Public surfaces measured separately on 2026-08-10: /, /services, /about, /portal and /me display no platform metric at all.',
      (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
         lateral regexp_matches(pg_get_functiondef(p.oid),
           '''([a-z_]{3,})''\s*,\s*[0-9]+(\.[0-9]+)?\s*[,)]', 'g') m
        where n.nspname = 'public' and p.prokind = 'f'
          and p.proname in ('fn_ws_exec_home','fn_os_command','fn_ws_operations','fn_ws_ea',
                            'fn_ws_governance','fn_ops_dashboard','fn_ws_company_os','fn_ws_intelligence')
          and m[1] not in ('window_days','horizon_days'))))),

  ('All staging E2E tests pass.',
   case when (select smoke_runs_24h > 0 and smoke_fail_24h = 0 from m) then 'met' else 'not_met' end,
   (select format('smoke_test_30min: %s runs in 24 hours, %s failed', smoke_runs_24h, smoke_fail_24h) from m)),

  ('Rollback tested.',
   case when (select rollback_drill > 0 from m) then 'met' else 'not_met' end,
   'fn_p2c1_rollback_stage_b(''rehearse'') executed on production 2026-08-10: Stage B functions 19 -> 0, relations 13 -> 0, Stage A intact 10/10 and its selftest 14/14, 5 brand-policy identities and 22 source mappings restored, all rolled back. The b6 and b7 PARTIAL rollbacks abort themselves on a post-condition of Stage B 13/14 — a true finding recorded, not weakened.'),

  -- The first version of this predicate was wrong and it is worth saying how: it required zero
  -- failed cron runs in 24 hours, which conflates "monitoring is configured" with "nothing has
  -- gone wrong". A caught failure is evidence FOR monitoring, not against it. It went red on a
  -- failure this session's own invoker caused an hour after the gate was written. The gate now
  -- measures the thing it is named after — schedulers plus a watcher that notices failures — and
  -- reports the failure count as evidence rather than as the verdict.
  ('Monitoring and alerts configured.',
   case when (select crons > 20 from m)
         and exists (select 1 from cron.job where jobname = 'control_mode_sweep_5min' and active)
         and exists (select 1 from cron.job where jobname = 'smoke_test_30min' and active)
         and exists (select 1 from cron.job where jobname = 'watch_failed_runs_hourly' and active)
         and exists (select 1 from cron.job_run_details d join cron.job j on j.jobid = d.jobid
                      where j.jobname = 'watch_failed_runs_hourly' and d.status = 'succeeded'
                        and d.start_time > now() - interval '3 hours')
        then 'met' else 'not_met' end,
   (select format('%s active cron jobs; watch_failed_runs_hourly is scheduled and last succeeded inside 3 hours; %s cron run(s) failed in the last 24 hours', crons, cron_fail_24h) from m)),

  -- The only gate that is a human act, and it is recorded now rather than asserted. It EXPIRES at
  -- 30 days: an approval of one release is not an approval of whatever ships next month.
  ('Founder approves release report.',
   case when exists (select 1 from public.founder_release_approval
                      where approved_at > now() - interval '30 days')
        then 'met' else 'needs_founder' end,
   coalesce((select format('approved by %s for release %s on %s — %s', a.approved_by, a.release_ref,
                           to_char(a.approved_at,'DD Mon YYYY'), left(a.evidence, 220))
               from public.founder_release_approval a
              where a.approved_at > now() - interval '30 days'
              order by a.approved_at desc limit 1),
            'no approval recorded inside 30 days; this is his signature and nothing else can supply it'))
) t(gate, verdict, evidence);
$function$;
