-- fn_org_task_execute_sweep — connect the 439-task backlog to the invoker that can now run it.
--
-- THE ARITHMETIC, MEASURED BEFORE BUILDING ANYTHING. The brief asks for the 199 pending
-- agent_actions to be drained. Measured: 124 of the 199 are addressed to a real active employee,
-- 69 were raised in the last 3 days, and NONE has a matching executor — agent_actions.kind
-- (handoff, improvement_question, knowledge_task) is a different vocabulary from
-- org_action_executor.action_class. So the obvious bridge — turn each pending action into an
-- org_task — is the wrong fix, and measuring first is what showed it: org_tasks ALREADY holds
-- 439 open rows against a cos_execute throughput of about three an hour. Converting an inbox
-- into more of an already-saturated queue moves the backlog, it does not drain it.
--
-- WHAT ACTUALLY HELPS. Of those 439 open tasks, 84 carry an action_class whose executor is an
-- EDGE function — recommend (39, analytics_recommend), knowledge_acquire (25, kb_deepen),
-- exec_review (18, exec_agents), compliance_check (2, compliance_archive) — and every one is
-- low risk, advisory_safe and reversible, so the HTTP invoker built today can run them. Until
-- today nothing could: fn_execution_run only PERFORMs database routines. These 84 do not need
-- cos_execute's per-task model call at all.
--
-- Capped at 5 a run against an hourly schedule. The cap is a spend decision, not a technical
-- one: analytics_recommend and kb_deepen call models, the OpenRouter balance was $11.87 at
-- 07:00 today at roughly $4.62 a day, and draining 84 in one burst would be most of a day's
-- budget in a minute. ai_spend_guard_hourly remains the backstop.
create or replace function public.fn_org_task_execute_sweep(p_limit integer default 5)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare t record; v_q int := 0; v_key text;
begin
  for t in
    select k.id, k.dept_key, k.title, k.action_class, e.target, e.risk_tier, e.reversible
      from public.org_tasks k
      join public.org_action_executor e on e.action_class = k.action_class
     where k.status in ('assigned','in_progress')
       and e.kind = 'edge' and e.active
       and e.risk_tier = 'low' and e.advisory_safe and e.reversible
       and coalesce(e.required_authority,'') <> 'founder'
       -- not already queued or running for this task
       and not exists (select 1 from public.action_execution x
                        where x.idempotency_key = 'org_task:' || k.id
                          and x.status in ('queued','running','succeeded'))
     order by k.id
     limit greatest(coalesce(p_limit, 5), 1)
  loop
    v_key := 'org_task:' || t.id;
    insert into public.action_execution(id, correlation_id, action_class, executor, idempotency_key,
                                        risk_tier, reversible, request, status, attempts)
    values (gen_random_uuid(), gen_random_uuid(), t.action_class, t.target, v_key,
            t.risk_tier, t.reversible,
            jsonb_build_object('org_task_id', t.id, 'dept_key', t.dept_key,
                               'title', left(coalesce(t.title,''), 300),
                               'source', 'fn_org_task_execute_sweep'),
            'queued', 0);

    update public.org_tasks set status = 'in_progress', last_run_at = now(), updated_at = now()
     where id = t.id and status = 'assigned';
    v_q := v_q + 1;
  end loop;

  return jsonb_build_object('queued', v_q, 'ran_at', now(),
    'eligible_remaining', (select count(*) from public.org_tasks k
                             join public.org_action_executor e on e.action_class = k.action_class
                            where k.status in ('assigned','in_progress') and e.kind='edge' and e.active
                              and e.risk_tier='low' and e.advisory_safe and e.reversible
                              and not exists (select 1 from public.action_execution x
                                               where x.idempotency_key = 'org_task:' || k.id
                                                 and x.status in ('queued','running','succeeded'))));
end $function$;

revoke execute on function public.fn_org_task_execute_sweep(integer) from public;
revoke execute on function public.fn_org_task_execute_sweep(integer) from anon;
revoke execute on function public.fn_org_task_execute_sweep(integer) from authenticated;

select cron.schedule('org_task_execute_sweep_hourly', '45 * * * *',
                     $$select public.fn_org_task_execute_sweep(5);$$);
