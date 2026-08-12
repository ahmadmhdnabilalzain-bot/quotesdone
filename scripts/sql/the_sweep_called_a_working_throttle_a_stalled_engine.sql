-- The sweep called a working throttle a stalled engine
-- ====================================================
--
-- workflow_step_sweep has written status='error' every ten minutes all day, saying:
--   "STALLED: 107 workflow step(s) ready and none runnable - 66 carry no action_class and the rest
--    match no eligible executor."
--
-- The first clause is true. The second is not, and the severity is wrong.
--
-- Measured on production: of 108 ready steps, 67 carry no action_class. The other 41 -
-- health_report 21, knowledge_fill 19, coordinate 1 - DO have active executors, and they satisfy
-- every predicate in fn_workflow_step_claim: parent run running, not employee_task, not
-- founder-gated, actor resolves, and no low-risk/reversible/non-notifying executor owns them (so
-- the dispatcher is the right claimant). They sit unclaimed for one reason only:
-- fn_task_is_demand() is false for all three, 24 reflection steps have already run today, and
-- decision_policy.workflow_reflection_steps_per_day is 6. The spend gate shipped on 11 Aug is
-- working exactly as designed.
--
-- The cost of getting this wrong is not cosmetic. it_health reads agent_runs, and its incident is
-- in decision_log verbatim - "10 agent run(s) failed in last 24h review failing jobs:
-- workflow_step_sweep", risk medium, routed to the CTO. 144 false error rows a day, an incident
-- raised off them, and a decision logged and routed on top of that. An instrument reporting on the
-- wrong subject, and three layers above it believing the instrument.
--
-- This separates the three populations the old verdict added together - throttled by a named
-- policy, awaiting classification, and genuinely unexplained - and raises only on the last. The
-- other two stay fully visible in the payload and the note; the unclassified backlog additionally
-- gets ONE deduplicated org_task instead of 144 error rows a day, because it is a standing defect
-- rather than a ten-minute incident.
--
-- NOT FIXED HERE, deliberately: the 67 unclassified steps come from ten workflow DEFINITIONS -
-- employee_task, rfq_handling, payment, refund, complaint, supplier_onboarding,
-- customer_registration, invoice_approval, campaign_publishing, supplier_suspension - none of
-- which carries an action_class on any step. Classifying them would make ~1,049 queued steps
-- become executable at once, and 'refund' reaches Stripe. That is a per-class review against
-- org_action_executor.notifies_human / risk_tier / reversible, not a sweep, and it is what the
-- task this function now opens is for.

CREATE OR REPLACE FUNCTION public.fn_workflow_step_sweep(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s record; v_settled int := 0; v_q int := 0; v_key text; v_res text; v_out jsonb; v_parked int; v_noclass int;
        v_cap int; v_reflection_today int; v_throttled int; v_true_stall int; v_status text; v_note text;
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
    from public.workflow_step_run sr
   where sr.output->>'worked_by' = 'workflow_dispatch'
     and sr.finished_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc'
     and not public.fn_task_is_demand(sr.action_class);

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

  v_true_stall := greatest(v_parked - v_noclass - v_throttled, 0);

  v_out := jsonb_build_object(
    'settled', v_settled, 'queued', v_q, 'ran_at', now(),
    'parked', v_parked, 'parked_without_action_class', v_noclass,
    'parked_throttled_by_reflection_ceiling', v_throttled,
    'reflection_worked_today', v_reflection_today, 'reflection_cap', v_cap,
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
         || v_true_stall || ' unexplained)';
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
end $function$;
