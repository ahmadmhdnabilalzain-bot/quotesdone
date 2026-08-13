-- "UNEXPLAINED" WAS A SUBTRACTION, AND THE EXPLANATION WAS ONE JOIN AWAY
--
-- fn_workflow_step_sweep runs every ten minutes and has been raising an error on production every
-- time for hours: "STALLED: 56 workflow step(s) are ready, carry an action_class, and are not
-- explained by the reflection ceiling." The count climbed 46 -> 46 -> 61 -> 56 across the night.
--
-- It reached that number by SUBTRACTION:
--
--   v_true_stall := greatest(v_parked - v_noclass - v_throttled, 0);
--
-- whatever is left after the two reasons the author thought of. A count of the reasons you did not
-- think of is not a stall; it is the size of your own blind spot, and this one has been paging a
-- human 144 times a day.
--
-- MEASURED ON PRODUCTION, THE 56 ARE THREE ACTION CLASSES AND EVERY ONE IS REFUSED ON PURPOSE:
--
--   coordinate      25 ready   risk_tier=medium, advisory_safe=false   the dispatcher takes only
--                                                                      low-risk advisory-safe work
--   health_report   18 ready   notifies_human=true                     the gate added on 13 Aug so
--                                                                      an executor cannot email him
--   knowledge_fill  13 ready   kind=rpc, not edge                      the dispatcher invokes edge
--
--   25 + 18 + 13 = 56, exactly the number it called unexplained.
--
-- Every one of those facts is in org_action_executor, and THIS FUNCTION ALREADY JOINS TO IT — two
-- lines below the subtraction, to compute ready_runnable. It had the answer in the same query plan
-- and reported a mystery.
--
-- WHAT CHANGES. The reasons are named, per class, in the payload and in the note. v_true_stall now
-- means what its name says: ready, classified, and ineligible for NO stated reason. That is the
-- only thing nobody has accounted for, and it is the only thing that still raises.
--
-- WHAT DOES NOT CHANGE. Nothing is hidden and no gate moves. The 56 steps still do not run, because
-- the three policies refusing them are correct and were each added deliberately — a medium-risk
-- coordinator, an executor that emails the founder, and an RPC the edge dispatcher cannot invoke.
-- They are now a named backlog with a stated cause instead of an alarm nobody can action. The
-- unclassed backlog keeps its own count, its own org_task and its own line in the note.
--
-- This is the same correction the function's own comment already describes making for the unclassed
-- leg: "it is counted, named in the note, and carried by one deduplicated org_task instead of 144
-- error rows a day ... Only the severity changed, and it changed to match what the numbers actually
-- say." That reasoning was applied to one leg and not to the one beside it.
--
-- CREATE OR REPLACE preserves the ACL; no GRANT/REVOKE belongs here.

CREATE OR REPLACE FUNCTION public.fn_workflow_step_sweep(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s record; v_settled int := 0; v_q int := 0; v_key text; v_res text; v_out jsonb; v_parked int; v_noclass int;
        v_cap int; v_reflection_today int; v_throttled int; v_true_stall int; v_status text; v_note text;
        v_ineligible int; v_why text;
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
  -- IT CALLED A WORKING THROTTLE A STALLED ENGINE (12 Aug 2026). The verdict below used to be
  --     case when v_parked > 0 and v_q = 0 and v_settled = 0 then 'error' else 'ok' end
  -- which reads "something is ready and this tick moved nothing, therefore the engine is stuck".
  -- That was true when it was written. It stopped being true the moment the reflection ceiling
  -- shipped: once the day's non-demand allowance is spent, moving nothing is the CORRECT behaviour
  -- and it stays correct until midnight UTC.
  --
  -- Measured on production today: 108 ready steps. 67 carry no action_class. The other 41 -
  -- health_report 21, knowledge_fill 19, coordinate 1 - pass every predicate in
  -- fn_workflow_step_claim: parent running, not employee_task, not founder-gated, actor resolves,
  -- and no safe executor owns them. They are unclaimed for exactly one reason:
  -- fn_task_is_demand() is false for all three, 24 reflection steps have already run today, and the
  -- cap is 6. The gate the founder asked for on 11 Aug is doing its job.
  --
  -- The old message asserted the opposite - "the rest match no eligible executor" - and raised
  -- status='error' on it every ten minutes, 144 times a day. it_health reads those rows, and I
  -- found its incident in decision_log verbatim: "10 agent run(s) failed in last 24h review failing
  -- jobs: workflow_step_sweep", risk medium, routed to the CTO. A whole escalation chain standing
  -- on a misread of a deliberate throttle.
  --
  -- So the verdict now separates three populations that were being added together:
  --   * throttled  - explained by the ceiling, a named policy with a number. Not an error.
  --   * unclassed  - steps no executor can EVER pick up. A real defect, but a standing backlog
  --                  rather than a ten-minute incident, so it is counted, named in the note, and
  --                  carried by one deduplicated org_task instead of 144 error rows a day.
  --   * true stall - ready, classified, and NOT explained by either. That is the only thing left
  --                  that nobody has accounted for, and it is the only thing that still raises.
  -- Nothing is hidden: every count stays in the payload and in the note. Only the severity changed,
  -- and it changed to match what the numbers actually say.
  select count(*), count(*) filter (where action_class is null)
    into v_parked, v_noclass
    from public.workflow_step_run where status = 'ready' and finished_at is null;

  select coalesce((value #>> '{}')::int, 6) into v_cap
    from public.decision_policy where key = 'workflow_reflection_steps_per_day';
  v_cap := coalesce(v_cap, 6);

  select count(*) into v_reflection_today
    from public.action_execution x
   where x.workflow_step_run_id is not null
     and x.created_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc'
     and not public.fn_task_is_demand(x.action_class);

  -- Classified, unfinished, ready, and held back only because the day's reflection budget is gone.
  select count(*) into v_throttled
    from public.workflow_step_run sr
    join public.workflow_run r on r.id = sr.workflow_run_id
   where sr.status = 'ready' and sr.finished_at is null
     and sr.action_class is not null
     and r.status = 'running'
     and r.workflow_key <> 'employee_task'
     and coalesce(sr.input->>'gate','') <> 'founder'
     and not public.fn_task_is_demand(sr.action_class)
     and v_reflection_today >= v_cap;

  -- "UNEXPLAINED" WAS A SUBTRACTION, AND THE EXPLANATION WAS ONE JOIN AWAY (13 Aug 2026).
  --
  -- v_true_stall was parked - noclass - throttled: whatever is left after the two known reasons,
  -- declared a stall and raised every ten minutes. Measured on production, ALL 56 of those steps
  -- were three action_classes, and every one is refused by a deliberate rule this same function
  -- already knows how to read - it uses exactly this join for ready_runnable two lines below:
  --
  --   coordinate      25 ready   risk_tier=medium, advisory_safe=false  -> the dispatcher takes
  --                                                                        only low-risk advisory-safe
  --   health_report   18 ready   notifies_human=true                    -> the gate added 13 Aug so
  --                                                                        an executor cannot email him
  --   knowledge_fill  13 ready   kind=rpc, not edge                     -> the dispatcher invokes edge
  --
  -- A count reached by subtracting the reasons you thought of is a count of the reasons you did
  -- not, and calling that a stall pages a human 144 times a day about a policy working correctly.
  -- The reasons are now named, and only a step that is ready, classified, and ineligible for NO
  -- stated reason still raises - which is the thing nobody has accounted for.
  select count(*), string_agg(distinct why, '; ') into v_ineligible, v_why from (
    select sr.id,
           case when e.action_class is null then 'no executor is mapped to ' || sr.action_class
                when e.kind <> 'edge' then sr.action_class || ' is a ' || e.kind || ' executor and the dispatcher invokes edge'
                when not e.active then sr.action_class || ' executor is inactive'
                when e.risk_tier <> 'low' then sr.action_class || ' is risk_tier ' || e.risk_tier
                when not e.advisory_safe then sr.action_class || ' is not advisory_safe'
                when not e.reversible then sr.action_class || ' is not reversible'
                when e.notifies_human then sr.action_class || ' notifies a human'
           end as why
      from public.workflow_step_run sr
      left join public.org_action_executor e on e.action_class = sr.action_class
     where sr.status = 'ready' and sr.finished_at is null and sr.action_class is not null
  ) q where why is not null;
  v_ineligible := coalesce(v_ineligible, 0);
  v_true_stall := greatest(v_parked - v_noclass - v_throttled - v_ineligible, 0);

  v_out := jsonb_build_object(
    'settled', v_settled, 'queued', v_q, 'ran_at', now(),
    'parked', v_parked, 'parked_without_action_class', v_noclass,
    'parked_throttled_by_reflection_ceiling', v_throttled,
    'reflection_worked_today', v_reflection_today, 'reflection_cap', v_cap,
    'parked_ineligible_by_policy', v_ineligible,
    'parked_ineligible_because', coalesce(v_why, ''),
    'parked_unexplained', v_true_stall,
    'ready_runnable', (select count(*) from public.workflow_step_run r
                         join public.org_action_executor e on e.action_class = r.action_class
                        where r.status = 'ready' and e.kind='edge' and e.active
                          and e.risk_tier='low' and e.advisory_safe and e.reversible
                          and not e.notifies_human),
    'ready_held_notifies_human', (select count(*) from public.workflow_step_run r
                                    join public.org_action_executor e on e.action_class = r.action_class
                                   where r.status = 'ready' and e.notifies_human),
    'never_finished', (select count(*) from public.workflow_step_run where finished_at is null));

  v_status := case when v_true_stall > 0 and v_q = 0 and v_settled = 0 then 'error' else 'ok' end;
  v_note := 'settled ' || v_settled || ', queued ' || v_q || ', parked ' || v_parked
         || ' (' || v_noclass || ' awaiting an action_class, ' || v_throttled
         || ' held by the reflection ceiling at ' || v_reflection_today || '/' || v_cap || ' today, '
         || v_ineligible || ' ineligible by policy'
         || case when v_why is null or v_why = '' then '' else ' (' || left(v_why, 300) || ')' end
         || ', ' || v_true_stall || ' unexplained)';
  if v_status = 'error' then
    v_note := 'STALLED: ' || v_true_stall || ' workflow step(s) are ready, carry an action_class, '
           || 'and are not explained by the reflection ceiling. ' || v_note;
  end if;

  insert into public.agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('workflow_step_sweep', v_status, v_out, v_note, now(), now());

  -- The unclassified backlog is a real defect and must not become invisible again just because it
  -- stopped shouting. One task, deduplicated on title, carries it.
  if v_noclass > 0 then
    begin
      insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
      select 'exec', 'Classify the workflow steps no executor can run',
             v_noclass || ' workflow_step_run row(s) are ready with no action_class, so nothing can '
             || 'ever pick them up and their runs never complete. The gap is in the DEFINITIONS: '
             || 'employee_task, rfq_handling, payment, refund, complaint, supplier_onboarding, '
             || 'customer_registration, invoice_approval, campaign_publishing and '
             || 'supplier_suspension carry no action_class on any step. Classifying them will make '
             || 'the queued backlog FIRE, so check org_action_executor.notifies_human, risk_tier '
             || 'and reversible per class first - refund reaches Stripe and needs the founder.',
             'proposed', 'gated', false, 'incident_fix'
      where not exists (select 1 from public.org_tasks
                         where title = 'Classify the workflow steps no executor can run'
                           and status <> 'done');
    exception when others then null; end;
  end if;

  return v_out;
end $function$
;
