-- fn_agent_action_work_sweep — feed the employees' own inbox to the worker that settles it.
--
-- agent_actions had no consumer. cos_execute PRODUCES rows here; agent_act is the founder's chat
-- surface and puts him in the loop by design. So 200 items sat pending, 89 of them handoffs
-- addressed to an employee that runs, and the approval-centre check read 16.1% founder-paused
-- against a 10% bar.
--
-- The sweep only queues. action_worker does the work and asserts the deliverable before anything
-- closes, and the HTTP invoker carries it — so the risk gate, the idempotency key, the timeout,
-- the retry ceiling and the dead-letter path are the ones already built and proved, not a second
-- set. Two independent refusals guard the same thing from opposite ends: this query will not queue
-- an ineligible kind, and the worker refuses it again by name if something else ever queues one.
create or replace function public.fn_agent_action_work_sweep(p_limit integer default 10)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_q int := 0; r record;
begin
  for r in
    select a.id, a.kind
      from public.agent_actions a
      join public.org_agents o on o.agent_key = a.agent and o.active
     where a.status = 'pending'
       and a.kind in ('handoff','improvement_question','knowledge_task','report_recommendation',
                      'report_task','objective_step','strategy_rec','ops_recommendation',
                      'marketing_recommendation','ai_improvement','doc_task','supply_health',
                      'decision.route_category','autonomy_stall')
       and not exists (select 1 from public.action_execution x
                        where x.idempotency_key = 'agent_action:' || a.id
                          -- ALL statuses, not just the live ones: idempotency_key is UNIQUE, so an item that already
                          -- FAILED once collides on re-sweep. Cycle 3 of the first drain died on
                          -- 23505 for exactly that. A failed attempt is a recorded attempt.
                          and true)
     order by a.created_at
     limit greatest(coalesce(p_limit, 10), 1)
  loop
    insert into public.action_execution(id, correlation_id, action_class, executor, idempotency_key,
                                        risk_tier, reversible, request, status, attempts)
    values (gen_random_uuid(), gen_random_uuid(), 'agent_action_work', 'action_worker',
            'agent_action:' || r.id, 'low', true,
            jsonb_build_object('action_id', r.id, 'kind', r.kind,
                               'source', 'fn_agent_action_work_sweep'),
            'queued', 0)
    on conflict (idempotency_key) do nothing;
    v_q := v_q + 1;
  end loop;

  return jsonb_build_object('queued', v_q, 'ran_at', now(),
    'eligible_remaining', (select count(*) from public.agent_actions a
                             join public.org_agents o on o.agent_key = a.agent and o.active
                            where a.status = 'pending'
                              and a.kind in ('handoff','improvement_question','knowledge_task','report_recommendation',
                                             'report_task','objective_step','strategy_rec','ops_recommendation',
                                             'marketing_recommendation','ai_improvement','doc_task','supply_health',
                                             'decision.route_category','autonomy_stall')
                              and not exists (select 1 from public.action_execution x
                                               where x.idempotency_key = 'agent_action:' || a.id
                                                 -- ALL statuses, not just the live ones: idempotency_key is UNIQUE, so an item that already
                          -- FAILED once collides on re-sweep. Cycle 3 of the first drain died on
                          -- 23505 for exactly that. A failed attempt is a recorded attempt.
                          and true)),
    'never_auto_settled', (select count(*) from public.agent_actions
                            where status = 'pending'
                              and kind in ('customer_escalation','legal_flag','security_incident',
                                           'prompt_approval','compliance_update','finance_alert',
                                           'finance_marketing_budget','incident')));
end $function$;

revoke execute on function public.fn_agent_action_work_sweep(integer) from public;
revoke execute on function public.fn_agent_action_work_sweep(integer) from anon;
revoke execute on function public.fn_agent_action_work_sweep(integer) from authenticated;

-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.

insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('agent_action_work_sweep_hourly', 'Employee inbox drain', 'Operations',
   'Queues pending agent_actions addressed to an active employee into action_worker, which settles each one by producing the deliverable. Never queues customer_escalation, legal_flag, security_incident, prompt_approval, compliance_update or anything touching money — those stay in the founder queue.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
