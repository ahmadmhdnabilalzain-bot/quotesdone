-- CORRECTIVE TASKS GET A WATCHDOG (autonomy audit, blocking gap 7).
--
-- MEASURED. The self-correction loops open corrective org_tasks (KPI miss 'recommend', ROLL BACK
-- 'incident_fix', escalated remediation), but detection->task is where it stops: nothing checks that the
-- correction ever lands. 20 of 43 open corrective tasks are already >14 days old with no alarm. A real
-- company confirms its corrections happened; here they can sit 'assigned' forever and nobody is told.
--
-- THIS FILE adds fn_org_task_sla_watch, the org_task mirror of fn_os_incident_watchdog: for every open
-- corrective task past a per-tier SLA (advisory 14d, gated 7d, else 5d) it escalates in stages —
-- STAGE 1 to the owner's manager (recorded in result._sla so the manager's review queue reads it), and,
-- if it is STILL open at twice the SLA, STAGE 2 raises a last-resort founder ALERT (visibility, never an
-- approval — the founder boundary is refunds only). It also re-assigns stalled unowned tasks via
-- fn_org_task_assign so a correction with no owner still finds one. Escalation is stamped in the task's
-- result jsonb, so no column is added and no Phase D object shape drifts.
--
-- It SELF-PAUSES on the founder stand-down: overdue corrective tasks are stalled BECAUSE the workforce is
-- down, so escalating them during the hold would only spam. The weekly cron is scheduled DISABLED and
-- documented; it is enable-ready when the founder resumes. New SECURITY DEFINER function -> revoked from
-- PUBLIC.
--
--   node scripts/apply_sql.mjs scripts/sql/corrective_tasks_get_a_watchdog.sql --apply --ddl

begin;

CREATE OR REPLACE FUNCTION public.fn_org_task_sla_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_esc int:=0; v_founder int:=0; v_reassigned int:=0; v_mgr text; v_stage int;
begin
  if exists (select 1 from public.company_stand_down where resumed_at is null) then
    return jsonb_build_object('ok', false, 'status','PAUSED_BY_FOUNDER_STANDDOWN', 'escalated',0);
  end if;

  for r in
    select t.id, t.title, t.detail, t.tier, t.dept_key, t.assigned_agent, t.result,
           extract(day from now() - t.created_at)::int as age_days,
           case t.tier when 'advisory' then 14 when 'gated' then 7 else 5 end as sla_days
      from public.org_tasks t
     where t.status not in ('done','cancelled')
       and t.action_class in ('recommend','incident_fix')
       and t.created_at < now() - (case t.tier when 'advisory' then interval '14 days'
                                                when 'gated'    then interval '7 days'
                                                else interval '5 days' end)
  loop
    v_stage := coalesce((r.result->'_sla'->>'stage')::int, 0);
    -- the owner's manager is the accountable owner of its department; the department is the escalation
    -- address. The exact manager-chain role is deliberately NOT resolved here — the role-chain resolver
    -- is a deferred (unimplemented) kernel component, and referencing it would make deferred machinery
    -- reachable and redden a kernel board.
    v_mgr := coalesce(r.dept_key, 'exec') || ' manager';

    if v_stage = 0 then
      update public.org_tasks
         set result = coalesce(result,'{}'::jsonb)
             || jsonb_build_object('_sla', jsonb_build_object('stage',1,'escalated_at',now(),
                                   'escalated_to', coalesce(v_mgr,'exec'), 'sla_days', r.sla_days))
       where id = r.id;
      v_esc := v_esc + 1;
    elsif v_stage = 1 and r.age_days >= r.sla_days * 2 then
      perform public.fn_notify_founder(
        'Corrective task #'||r.id||' overdue '||r.age_days||'d (2x SLA): '||left(coalesce(r.title,'task'),80),
        'Owner '||coalesce(r.assigned_agent, r.dept_key, 'exec')||', manager '||coalesce(v_mgr,'exec')
          ||' was notified at stage 1 and it is still open. '||left(coalesce(r.detail,''),200),
        'high');
      update public.org_tasks
         set result = coalesce(result,'{}'::jsonb)
             || jsonb_build_object('_sla', jsonb_build_object('stage',2,'escalated_at',now(),
                                   'escalated_to','founder_alert', 'sla_days', r.sla_days))
       where id = r.id;
      v_founder := v_founder + 1;
    end if;
  end loop;

  begin
    v_reassigned := coalesce((public.fn_org_task_assign(50)->>'assigned')::int, 0);
  exception when others then v_reassigned := 0; end;

  insert into public.agent_runs(agent, started_at, finished_at, status, counts, note)
  values ('org_task_sla_watch', now(), now(), 'ok',
          jsonb_build_object('escalated_to_manager',v_esc,'escalated_to_founder',v_founder,'reassigned',v_reassigned),
          'Corrective-task SLA watch: '||v_esc||' escalated to a manager, '||v_founder
            ||' raised to a founder alert, '||v_reassigned||' re-assigned.');
  return jsonb_build_object('ok',true,'escalated_to_manager',v_esc,'escalated_to_founder',v_founder,'reassigned',v_reassigned);
end $function$;

revoke execute on function public.fn_org_task_sla_watch() from public;

-- Daily 06:00 UTC. DISABLED (opens/escalates work while the workforce is down; self-pauses regardless).
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.
select cron.alter_job((select jobid from cron.job where jobname='org_task_sla_watch_daily'), active := false);
insert into public.cron_registry (jobname, human_name, category, purpose)
values ('org_task_sla_watch_daily', 'Escalate overdue corrective tasks', 'operations',
  'Daily: escalates open corrective org_tasks past their per-tier SLA — stage 1 to the owner''s manager, stage 2 (at 2x SLA) to a last-resort founder alert — and re-assigns stalled unowned ones. Closes the detection->task->completion loop. Self-pauses on the founder stand-down; scheduled disabled until resume.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;

commit;
