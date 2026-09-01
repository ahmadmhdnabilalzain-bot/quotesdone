-- CONSEQUENTIAL ACTIONS REACH THE APPROVAL GATE (autonomy audit, blocking gap 6).
--
-- MEASURED. org_action_executor holds 14 consequential (non-advisory) executors backed by real deployed
-- edge functions, but NO producer ever queues a non-advisory action: all 928 action_execution rows are
-- risk_tier='low' and 0 action_approval rows have ever been created. The AI-managerial approval tier
-- (fn_action_invoke_dispatch's spend/second-authority/autonomy gate) is unreachable dead code — the
-- company reasons about its consequential actions but never routes one to be approved and executed.
--
-- THIS FILE adds fn_action_queue_consequential_sweep: it inserts action_execution rows (status='queued')
-- for ready workflow steps and open org_tasks whose executor is active, EDGE (never rpc — fn_action_invoke_rpc
-- has no approval tier and would re-refuse them forever), NOT advisory_safe, NOT founder-reserved, and
-- reversible-or-compensatable — the gate-refusal INVERSE, so fn_action_invoke_dispatch routes them into
-- action_approval instead of refusing. Deterministic routing ONLY; the approver decision (who sets
-- action_approval.approval_decision) is model-bound and out of scope. Refunds/founder-reserved executors
-- are excluded by the predicate. SELF-PAUSES on the founder stand-down; disabled cron until resume.
--
--   node scripts/apply_sql.mjs scripts/sql/consequential_actions_reach_the_gate.sql --apply --ddl

begin;

create or replace function public.fn_action_queue_consequential_sweep(p_limit integer default 5)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare s record; t record; v_q_step int := 0; v_q_task int := 0; v_key text;
begin
  -- SELF-PAUSE: this queues real consequential business work; it pauses with the workforce.
  if exists (select 1 from public.company_stand_down where resumed_at is null) then
    return jsonb_build_object('ok', false, 'status','PAUSED_BY_FOUNDER_STANDDOWN', 'queued_steps',0, 'queued_tasks',0);
  end if;

  -- LOOP A: ready workflow steps whose executor is consequential AND the edge gate can PROGRESS on.
  for s in
    select r.id, r.workflow_run_id, r.step_no, r.actor, r.action_class, r.input, e.target, e.risk_tier, e.reversible
      from public.workflow_step_run r
      join public.org_action_executor e on e.action_class = r.action_class
     where r.status='ready' and r.finished_at is null
       and e.kind='edge' and e.active and not e.advisory_safe
       and coalesce(e.required_authority,'') <> 'founder'
       and (e.reversible or e.compensation_action_class is not null)
       and not exists (select 1 from public.action_execution x where x.idempotency_key = 'workflow_step:'||r.id)
     order by r.id limit greatest(coalesce(p_limit,5),1)
  loop
    v_key := 'workflow_step:'||s.id;
    insert into public.action_execution(id,correlation_id,action_class,executor,idempotency_key,risk_tier,reversible,request,status,attempts,workflow_step_run_id)
    values (gen_random_uuid(),gen_random_uuid(),s.action_class,s.target,v_key,s.risk_tier,s.reversible,
            jsonb_build_object('workflow_step_run_id',s.id,'workflow_run_id',s.workflow_run_id,'step_no',s.step_no,'actor',s.actor,'input',coalesce(s.input,'{}'::jsonb),'source','fn_action_queue_consequential_sweep'),
            'queued',0,s.id)
    on conflict (idempotency_key) do nothing;
    update public.workflow_step_run set status='running' where id=s.id and status='ready';
    v_q_step := v_q_step + 1;
  end loop;

  -- LOOP B: open org_tasks with a consequential edge executor (same predicate). incident_fix lands here.
  for t in
    select k.id,k.dept_key,k.title,k.action_class,e.target,e.risk_tier,e.reversible
      from public.org_tasks k
      join public.org_action_executor e on e.action_class = k.action_class
     where k.status in ('assigned','in_progress')
       and e.kind='edge' and e.active and not e.advisory_safe
       and coalesce(e.required_authority,'') <> 'founder'
       and (e.reversible or e.compensation_action_class is not null)
       and not exists (select 1 from public.action_execution x where x.idempotency_key = 'org_task:'||k.id)
     order by k.id limit greatest(coalesce(p_limit,5),1)
  loop
    v_key := 'org_task:'||t.id;
    insert into public.action_execution(id,correlation_id,action_class,executor,idempotency_key,risk_tier,reversible,request,status,attempts)
    values (gen_random_uuid(),gen_random_uuid(),t.action_class,t.target,v_key,t.risk_tier,t.reversible,
            jsonb_build_object('org_task_id',t.id,'dept_key',t.dept_key,'title',left(coalesce(t.title,''),300),'source','fn_action_queue_consequential_sweep'),
            'queued',0)
    on conflict (idempotency_key) do nothing;
    update public.org_tasks set status='in_progress',last_run_at=now(),updated_at=now() where id=t.id and status='assigned';
    v_q_task := v_q_task + 1;
  end loop;

  insert into public.agent_runs(agent,started_at,finished_at,status,counts,note)
  values ('action_queue_consequential_sweep',now(),now(),'ok',
    jsonb_build_object('queued_steps',v_q_step,'queued_tasks',v_q_task),
    'Queued '||v_q_step||' consequential workflow step(s) and '||v_q_task||' org_task(s) for the approval gate.');
  return jsonb_build_object('ok',true,'queued_steps',v_q_step,'queued_tasks',v_q_task,'ran_at',now(),
    'ready_consequential_remaining',(select count(*) from public.workflow_step_run r join public.org_action_executor e on e.action_class=r.action_class where r.status='ready' and r.finished_at is null and e.kind='edge' and e.active and not e.advisory_safe and coalesce(e.required_authority,'')<>'founder' and (e.reversible or e.compensation_action_class is not null)));
end $fn$;

revoke execute on function public.fn_action_queue_consequential_sweep(integer) from public;

-- Hourly, DISABLED (queues work-creating rows into a watched relation; self-pauses regardless).
select cron.schedule('action_queue_consequential_sweep_hourly','40 * * * *',$$select public.fn_action_queue_consequential_sweep(5);$$);
select cron.alter_job((select jobid from cron.job where jobname='action_queue_consequential_sweep_hourly'), active := false);
insert into public.cron_registry(jobname,human_name,category,purpose)
values ('action_queue_consequential_sweep_hourly','Queue consequential actions for approval','operations',
 'Hourly: queues action_execution rows for ready workflow steps and open org_tasks whose executor is active, edge, NOT advisory_safe, not founder-reserved, and reversible-or-compensatable, so fn_action_invoke_dispatch routes them into action_approval for AI-managerial (and any second-authority/spend) approval. Deterministic routing; the approver decision is model-bound. Self-pauses on the founder stand-down; scheduled disabled until resume.')
on conflict (jobname) do update set human_name=excluded.human_name,category=excluded.category,purpose=excluded.purpose;

commit;
