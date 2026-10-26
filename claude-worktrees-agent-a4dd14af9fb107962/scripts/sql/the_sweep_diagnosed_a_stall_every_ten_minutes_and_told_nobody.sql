-- THE WORKFLOW SWEEP DIAGNOSED A STALLED ENGINE EVERY TEN MINUTES AND TOLD NOBODY.
--
-- fn_workflow_step_sweep already computed ready_runnable, ready_held_notifies_human and
-- never_finished, and RETURNED them to `select public.fn_workflow_step_sweep(5);` in cron, which
-- discards the return value. It has been running every ten minutes producing an accurate diagnosis
-- and writing it nowhere. It writes no agent_runs row at all, so a stalled engine and a healthy one
-- are indistinguishable from outside the function.
--
-- MEASURED ON PRODUCTION 2026-08-12:
--
--   workflow_run          195 running · 7 failed · 5 done
--   workflow_step_run   2,655 total · 195 ready and unfinished
--   of those 195:           0 executable
--                         132 carry NO action_class at all
--                          63 carry one that matches no eligible executor
--   eligible executors     22 (edge, active, low risk, advisory-safe, reversible, no human notice)
--
-- Every in-flight workflow run is parked on a step nothing can pick up. That is the whole reason
-- the engine has completed five runs in its lifetime.
--
-- THIS COMMIT DOES NOT FIX THAT, AND SAYS SO. The sweep queues work only for a registered low-risk
-- reversible EDGE EXECUTOR. Most workflow steps name an actor_role - an employee - and nothing
-- routes a ready step to the employee who owns it. That is the missing half of the engine and it is
-- a real build: an employee-side dispatcher beside the executor-side sweep. What this commit does
-- is make the stall REPORTABLE, which is the precondition for anyone noticing it exists.

CREATE OR REPLACE FUNCTION public.fn_workflow_step_sweep(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s record; v_settled int := 0; v_q int := 0; v_key text; v_res text; v_out jsonb; v_parked int; v_noclass int;
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

  -- 2. QUEUE the ready steps a registered, low-risk, reversible edge executor can run WITHOUT
  --    delivering a message to a person. See the note above: that last clause is why this exists.
  for s in
    select r.id, r.workflow_run_id, r.step_no, r.actor, r.action_class, r.input,
           e.target, e.risk_tier, e.reversible
      from public.workflow_step_run r
      join public.org_action_executor e on e.action_class = r.action_class
     where r.status = 'ready' and r.finished_at is null
       and e.kind = 'edge' and e.active
       and e.risk_tier = 'low' and e.advisory_safe and e.reversible
       and not e.notifies_human
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

  -- IT KNEW ALL OF THIS AND TOLD NOBODY (12 Aug 2026). This function already computed
  -- ready_runnable, ready_held_notifies_human and never_finished, and returned them to
  -- `select public.fn_workflow_step_sweep(5);` in cron - which discards the value. So it has run
  -- every ten minutes computing an accurate diagnosis of a stalled engine and writing it nowhere.
  --
  -- Measured on production the day this line was added: 2,655 workflow_step_run rows, 195 ready and
  -- unfinished, and ZERO of the 195 executable - 132 carry no action_class at all and the other 63
  -- match no eligible executor. Every one of the 195 in-flight workflow runs is parked on a step
  -- nothing can pick up, which is why the whole table holds 5 'done' against 195 'running'.
  --
  -- The row below does not fix that. It makes it VISIBLE, which is the precondition: silence and
  -- health looked identical from outside this function.
  select count(*), count(*) filter (where action_class is null)
    into v_parked, v_noclass
    from public.workflow_step_run where status = 'ready' and finished_at is null;

  v_out := jsonb_build_object(
    'settled', v_settled, 'queued', v_q, 'ran_at', now(),
    'parked', v_parked, 'parked_without_action_class', v_noclass,
    'ready_runnable', (select count(*) from public.workflow_step_run r
                         join public.org_action_executor e on e.action_class = r.action_class
                        where r.status = 'ready' and e.kind='edge' and e.active
                          and e.risk_tier='low' and e.advisory_safe and e.reversible
                          and not e.notifies_human),
    'ready_held_notifies_human', (select count(*) from public.workflow_step_run r
                                    join public.org_action_executor e on e.action_class = r.action_class
                                   where r.status = 'ready' and e.notifies_human),
    'never_finished', (select count(*) from public.workflow_step_run where finished_at is null));

  insert into public.agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('workflow_step_sweep',
          case when v_parked > 0 and v_q = 0 and v_settled = 0 then 'error' else 'ok' end,
          v_out,
          case when v_parked > 0 and v_q = 0 and v_settled = 0
               then 'STALLED: ' || v_parked || ' workflow step(s) ready and none runnable - '
                    || v_noclass || ' carry no action_class and the rest match no eligible executor. '
                    || 'A workflow run parked on a step nothing can pick up never completes.'
               else 'settled ' || v_settled || ', queued ' || v_q || ', parked ' || v_parked end,
          now(), now());

  return v_out;
end $function$;
