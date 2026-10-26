-- NOT ONE WORKFLOW STEP HAS EVER FINISHED.
--
-- Found by sweeping for columns that are 100% NULL in tables that have rows -- the generalisation of
-- the defect this session kept hitting, which is a value with nowhere to land. workflow_step_run has
-- 2,072 rows: 1,904 `queued`, 168 `ready`, and NOT ONE in a terminal state. finished_at, output and
-- error are null on every row, because `fn_workflow_step_done` -- which is complete, correct, marks
-- the step, advances the next one to `ready` and closes the run -- has no caller anywhere in the
-- estate. Workflows start on `workflow_start_due` every 15 minutes and nothing has ever advanced one.
--
-- The runner already exists too. workflow_step_run carries `action_class` and `idempotency_key`, the
-- same vocabulary as org_action_executor and the invoker built in part 9, and action_execution has a
-- `workflow_step_run_id` column that has been null on all 233 rows. Every piece was built and the
-- wire between them was not. So this is the wire, and it is deliberately the same shape as
-- fn_org_task_execute_sweep and fn_agent_action_work_sweep rather than a third design:
--
--   SETTLE  an execution that reached a terminal status hands its result to fn_workflow_step_done,
--           which is what advances the run. The link is the column that was always there.
--   QUEUE   a `ready` step whose action_class has a low + advisory_safe + reversible edge executor
--           becomes an action_execution. The invoker's risk order is untouched: this sweep chooses
--           nothing the invoker would refuse, and the invoker still refuses independently.
--
-- The idempotency guard excludes ALL statuses, not just the live ones, because idempotency_key is
-- UNIQUE and a step whose invocation FAILED once collides on the next sweep. That has now bitten
-- three separate sweeps in this estate; it does not get to bite a fourth.
--
-- 75 of the 168 ready steps have such an executor (recommend 45, health_report 19,
-- knowledge_acquire 11). The other 93 carry no action_class at all -- they are gates and human
-- steps, and they are left alone rather than given a machine to run them.
--
-- ponytail: a step marked `running` whose execution never reaches a terminal status stays running.
-- fn_execution_sweep already exists for stalled executions; wire it here if that starts happening.

create or replace function public.fn_workflow_step_sweep(p_limit integer default 5)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare s record; v_settled int := 0; v_q int := 0; v_key text; v_res text;
begin
  -- 1. SETTLE what the invoker has already finished.
  for s in
    select x.status, x.response, r.id sid, r.workflow_run_id, r.step_no
      from public.action_execution x
      join public.workflow_step_run r on r.id = x.workflow_step_run_id
     where x.workflow_step_run_id is not null
       and x.status in ('succeeded','failed')
       and r.finished_at is null
     order by r.id
     limit 50
  loop
    v_res := public.fn_workflow_step_done(
      s.workflow_run_id, s.step_no,
      coalesce(s.response, '{}'::jsonb),
      case when s.status = 'succeeded' then 'done' else 'failed' end);
    v_settled := v_settled + 1;
  end loop;

  -- 2. QUEUE the ready steps a registered, low-risk, reversible edge executor can actually run.
  for s in
    select r.id, r.workflow_run_id, r.step_no, r.actor, r.action_class, r.input,
           e.target, e.risk_tier, e.reversible
      from public.workflow_step_run r
      join public.org_action_executor e on e.action_class = r.action_class
     where r.status = 'ready' and r.finished_at is null
       and e.kind = 'edge' and e.active
       and e.risk_tier = 'low' and e.advisory_safe and e.reversible
       and coalesce(e.required_authority,'') <> 'founder'
       and not exists (select 1 from public.action_execution x
                        where x.idempotency_key = 'workflow_step:' || r.id)
     order by r.id
     limit greatest(coalesce(p_limit, 5), 1)
  loop
    v_key := 'workflow_step:' || s.id;
    insert into public.action_execution(id, correlation_id, action_class, executor, idempotency_key,
                                        risk_tier, reversible, request, status, attempts,
                                        workflow_step_run_id)
    values (gen_random_uuid(), gen_random_uuid(), s.action_class, s.target, v_key,
            s.risk_tier, s.reversible,
            jsonb_build_object('workflow_step_run_id', s.id,
                               'workflow_run_id', s.workflow_run_id,
                               'step_no', s.step_no,
                               'actor', s.actor,
                               'input', coalesce(s.input, '{}'::jsonb),
                               'source', 'fn_workflow_step_sweep'),
            'queued', 0, s.id)
    on conflict (idempotency_key) do nothing;

    update public.workflow_step_run set status = 'running' where id = s.id and status = 'ready';
    v_q := v_q + 1;
  end loop;

  return jsonb_build_object(
    'settled', v_settled, 'queued', v_q, 'ran_at', now(),
    'ready_with_executor', (select count(*) from public.workflow_step_run r
                              join public.org_action_executor e on e.action_class = r.action_class
                             where r.status = 'ready' and e.kind='edge' and e.active
                               and e.risk_tier='low' and e.advisory_safe and e.reversible),
    'ready_without_executor', (select count(*) from public.workflow_step_run r
                                where r.status = 'ready'
                                  and not exists (select 1 from public.org_action_executor e
                                                   where e.action_class = r.action_class
                                                     and e.kind='edge' and e.active)),
    'never_finished', (select count(*) from public.workflow_step_run where finished_at is null));
end $function$;

revoke execute on function public.fn_workflow_step_sweep(integer) from public, anon, authenticated;
