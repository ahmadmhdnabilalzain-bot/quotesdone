-- Applied version: 20260802234218
-- Recovered from production, byte-for-byte as applied.

-- Phase 1 emergency containment, step 2 of 4 — AUTONOMY.
-- Freezes the system to manual mode and disables the 18 cron jobs that autonomously
-- deploy, approve, ban, bill, purge or execute assigned tasks.
-- Read-only monitoring jobs are deliberately left running.
-- cron.alter_job(active := false) preserves the job definition; nothing is unscheduled.

do $CONTAIN$
declare
  r record;
  v_before text;
  v_jobs bigint[] := array[
      5,   -- auto_deploy                     deploy
     31,   -- site_autodeploy                 deploy
    134,   -- github_org_sync_nightly         deploy (GitHub -> Vercel main)
    124,   -- cos_execute_hourly              executes assigned tasks
    141,   -- event_dispatch_15min            writes org_tasks as assigned/autonomous
    127,   -- dept_plan_daily                 writes tasks with a hard-coded tier
     37,   -- agent_autogen_daily             auto-creates agents
     64,   -- autonomy_dispose_hourly         auto-approves suppliers, auto-closes actions
    178,   -- supplier_exception_sweep_daily  auto-rejects suppliers
    114,   -- dues_ban_overdue_daily          bans
    105,   -- subscription_billing_daily      bills
    113,   -- dues_interest_daily             accrues interest
    104,   -- founding_rank_daily             stamps billing exemption
     62,   -- gl_sync_nightly                 posts to the general ledger
     89,   -- collections_legal_daily         escalates dues to legal
     98,   -- retention_purge_weekly          destructive purge
    145,   -- audit_prune_weekly              prunes audit evidence
     94    -- cron_history_prune              deletes cron.job_run_details (evidence)
  ];
  v_class jsonb := jsonb_build_object(
    '5','deploy','31','deploy','134','deploy',
    '124','execute_assigned_tasks','141','execute_assigned_tasks','127','execute_assigned_tasks','37','execute_assigned_tasks',
    '64','approve','178','approve','114','ban',
    '105','bill','113','bill','104','bill','62','bill','89','bill',
    '98','purge','145','purge','94','purge');
begin
  ----------------------------------------------------------------- secrets
  for r in select key, value from public.app_secrets
            where key in ('cos_frozen','agent_autonomy_enabled') loop
    insert into containment.change_log (area, change, before_value, after_value, rollback_sql)
    values ('A_autonomy', 'app_secrets.'||r.key, r.value,
            case when r.key='cos_frozen' then 'true' else 'false' end,
            format('update public.app_secrets set value = %L where key = %L;', r.value, r.key));
  end loop;

  update public.app_secrets set value = 'true'  where key = 'cos_frozen';
  update public.app_secrets set value = 'false' where key = 'agent_autonomy_enabled';

  -- agent_autonomy_from is a historical fact and is deliberately NOT changed.
  select value into v_before from public.app_secrets where key = 'agent_autonomy_from';
  insert into containment.change_log (area, change, before_value, after_value, rollback_sql)
  values ('A_autonomy', 'app_secrets.agent_autonomy_from (recorded, unchanged)', v_before, v_before,
          '-- no change was made; nothing to roll back');

  ----------------------------------------------------------------- cron
  for r in select j.jobid, j.jobname, j.schedule, j.command, j.active
             from cron.job j where j.jobid = any(v_jobs) loop
    insert into containment.cron_disabled (jobid, jobname, schedule, command, was_active, class, rollback_sql)
    values (r.jobid, r.jobname, r.schedule, r.command, r.active,
            coalesce(v_class->>r.jobid::text,'unclassified'),
            format('select cron.alter_job(%s, active := %L);', r.jobid, r.active))
    on conflict (jobid) do nothing;

    if r.active then
      perform cron.alter_job(r.jobid, active := false);
    end if;
  end loop;

  insert into containment.change_log (area, change, before_value, after_value, rollback_sql)
  values ('A_autonomy', 'cron jobs disabled',
          (select count(*)::text from containment.cron_disabled where was_active),
          '0 active of the 18 contained jobs',
          'select string_agg(rollback_sql, E''\n'') from containment.cron_disabled where restored_at is null;');
end
$CONTAIN$;;
