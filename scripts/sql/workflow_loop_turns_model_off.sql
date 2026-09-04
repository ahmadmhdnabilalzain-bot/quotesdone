-- THE WORKFLOW LOOP TURNS WHILE THE PAID MODEL IS HELD (MASTER_PLAN A1 / §4.2), 4 Sep 2026.
--
-- MEASURED on production before this file: since 3 Sep, workflow_run done 3 / failed 13 / running 60,
-- every running run parked on step 1 with attempts=0 — NOBODY had even claimed them. Two halves of the
-- engine each refused the same step, and there was no third answer:
--
--   * fn_workflow_step_sweep queues a step only for a low-risk edge executor, and would not re-queue
--     over a terminal action_execution. The executions behind those steps were terminal because
--       (a) analytics_recommend answers 200 {held:true} while the model is held -> parked 'held';
--       (b) fn_execution_sweep CANCELLED every queued row that carried no decision_record_id — which is
--           every row the workflow sweep creates (it never writes one) — so uptime_verify, health_report,
--           knowledge_acquire and content_calendar steps were cancelled before the invoker ran them;
--       (c) an invoker refusal ("blocked by an open remediation") left the row queued until (b) took it.
--   * fn_workflow_step_claim (the dispatcher's queue) refused any step that HAS a low-risk executor —
--     the sweep's row — so the stranded steps were nobody's. 144 dispatcher ticks/day: worked 0.
--   * The 13 failed runs: 8 x analytics_recommend 502 analytics_llm_unavailable (before it learned to
--     answer held), 5 x os_incidents 401 — cred_action_invoker (id 100) was scoped from the executor
--     registry the day it was issued and never widened when os_incidents / resilience_ping were added.
--
-- THE FIX, in the order the plan gives it. While fn_kernel_paid_provider_gate denies (the founder's
-- hold, 8/8 routes open until 2126):
--   1. the sweep does NOT queue a model-backed executor (it can only come back held);
--   2. the claim hands the dispatcher every step the sweep cannot finish — model-backed executor, or
--      stranded behind terminal executions — flagged deterministic_only; the reflection ceiling (a cost
--      control on model calls) is not applied to zero-cost deterministic work;
--   3. workflow_dispatch applies the nearest company playbook by meaning (fn_apply_playbook over the
--      embedded ops_knowledge substrate) and closes the step through fn_workflow_step_deterministic_done,
--      which REFUSES a determination without substance, seals a decision_trace, queues a review_queue
--      row (low-confidence deterministic disposition, never a silent pass), cancels the superseded held
--      execution so fn_action_release_held cannot re-run it at launch, and only then advances the run;
--   4. a step no playbook covers is released with a distinct, readable reason; after 3 such attempts it
--      is parked as disposition='awaiting_model' and not claimed again until the hold lifts — never an
--      endless retry, never the same value as success.
-- When the hold lifts every branch above is inert and the live-model behaviour is exactly what it was.
--
--   node scripts/apply_sql.mjs scripts/sql/workflow_loop_turns_model_off.sql --apply --ddl

begin;

-- ---------------------------------------------------------------------------------------------------
-- Which executors can only answer through the paid model. Read from fn_task_class (the gateway's own
-- routing registry) rather than asserted per row: a function that is routed to a reasoning/drafting/
-- research class calls the model to do its work. health_ping (ai_health: liveness only) and
-- json_extraction (knowledge_exam: runs "no model" under the hold) are not model-backed work.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_executor_needs_model(p_target text)
returns boolean
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  select exists (
    select 1 from public.fn_task_class c
     where c.fn = p_target and c.active
       and c.task_class not in ('health_ping', 'json_extraction'));
$function$;

-- ---------------------------------------------------------------------------------------------------
-- fn_execution_sweep: a queued row is cancelled for a MISSING or REFUSED decision record only when it
-- claims one. The workflow sweep's rows never carry decision_record_id; they wait for the invoker.
-- A row the invoker refused (response.invoker='refused') is cancelled WITH the invoker's reason kept.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_execution_sweep(p_stall_minutes integer default 60)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_exec integer := 0; v_trace integer := 0; v_queue jsonb;
begin
  with seen as (
    select a.id,
           case
             when a.response->>'invoker' = 'refused'                       then 'cancelled'
             when (a.request ? 'decision_record_id') and d.id is null      then 'cancelled'
             when d.id is not null and d.status = 'executed'               then 'succeeded'
             when d.id is not null and (d.gate_verdict = 'refused'
               or d.status not in ('approved','executed'))                 then 'cancelled'
             when a.created_at < now() - make_interval(mins => greatest(coalesce(p_stall_minutes,60), 1))
                                                                            then 'stalled'
             else a.status
           end as new_status,
           d.id as dr_id, d.status as dr_status, d.gate_verdict as dr_verdict
      from public.action_execution a
      left join public.decision_record d on d.id::text = a.request ->> 'decision_record_id'
     where a.status = 'queued')
  update public.action_execution a
     set status      = s.new_status,
         attempts    = coalesce(a.attempts, 0) + 1,
         started_at  = coalesce(a.started_at, now()),
         finished_at = case when s.new_status in ('succeeded','cancelled') then now() else a.finished_at end,
         response    = coalesce(a.response, '{}'::jsonb) || jsonb_build_object(
                         'swept_at', now(), 'observed', s.new_status,
                         'decision_record_id', s.dr_id,
                         'decision_status', s.dr_status, 'gate_verdict', s.dr_verdict)
    from seen s
   where s.id = a.id and s.new_status <> 'queued';
  get diagnostics v_exec = row_count;

  update public.decision_trace t
     set outcome_status = a.status,
         outcome        = jsonb_build_object('execution_id', a.id, 'status', a.status,
                            'action_class', a.action_class, 'attempts', a.attempts,
                            'finished_at', a.finished_at),
         evaluated_at   = now()
    from public.action_execution a
   where a.correlation_id = t.correlation_id
     and t.entity_type = 'decision_record'
     and coalesce(t.outcome_status,'') is distinct from a.status;
  get diagnostics v_trace = row_count;

  select jsonb_object_agg(status, n) into v_queue
    from (select status, count(*) n from public.action_execution group by 1) z;

  return jsonb_build_object('executions_settled', v_exec, 'traces_updated', v_trace,
                            'queue', coalesce(v_queue, '{}'::jsonb), 'swept_at', now());
end $function$;

-- ---------------------------------------------------------------------------------------------------
-- fn_workflow_step_sweep: (1) settle stamps how the step was worked and, while the model is held,
-- used_llm=false — under the hold no executor in this estate can reach a paid provider (ai_gateway is
-- the single door and kernel K12 denies it), so the stamp is a measurement, not a hope; (2) a
-- model-backed executor is not queued while held — the dispatcher works that step deterministically.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_workflow_step_sweep(p_limit integer default 5)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare s record; v_settled int := 0; v_q int := 0; v_key text; v_res text; v_out jsonb; v_parked int; v_noclass int;
        v_cap int; v_reflection_today int; v_throttled int; v_true_stall int; v_status text; v_note text;
        v_ineligible int; v_why text; v_held boolean;
begin
  v_held := coalesce((public.fn_kernel_paid_provider_gate('anthropic/claude-sonnet-5')->>'allowed')::boolean, false) = false;

  -- 1. SETTLE what the invoker has already finished.
  for s in
    select x.status, x.response, x.executor, r.id sid, r.workflow_run_id, r.step_no
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
      coalesce(s.response, '{}'::jsonb)
        || jsonb_build_object('worked_by', 'executor:' || coalesce(s.executor, '?'))
        || case when v_held then jsonb_build_object('used_llm', false, 'used_llm_basis', 'paid provider held (kernel K12) at settle time') else '{}'::jsonb end,
      case when s.status = 'succeeded' then 'done' else 'failed' end);
    v_settled := v_settled + 1;
  end loop;

  -- 1b. RE-QUEUE the executions the old fn_execution_sweep cancelled before the invoker ever ran them
  --     (observed=cancelled, never dispatched, no decision record, not superseded). A deterministic
  --     executor such as uptime_check or ai_health is simply run, late; a model-backed one stays for the
  --     dispatcher while the model is held. The idempotency key is the same row, so this is an UPDATE.
  for s in
    select x.id xid, r.id sid
      from public.action_execution x
      join public.workflow_step_run r on r.id = x.workflow_step_run_id
      join public.org_action_executor e on e.action_class = r.action_class and e.active
     where x.status = 'cancelled'
       and r.status = 'ready' and r.finished_at is null
       and x.response->>'invoker' is null
       and x.response->>'observed' = 'cancelled'
       and not (x.request ? 'decision_record_id')
       and not (x.response ? 'superseded_by')
       and e.kind in ('edge','rpc') and e.risk_tier = 'low' and e.advisory_safe and e.reversible
       and not e.notifies_human and coalesce(e.required_authority,'') <> 'founder'
       and not (v_held and public.fn_executor_needs_model(e.target))
     order by r.id
     limit greatest(coalesce(p_limit, 5), 1)
  loop
    update public.action_execution
       set status = 'queued', finished_at = null,
           response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
             'requeued_at', now(),
             'requeue_reason', 'cancelled by fn_execution_sweep before the invoker ran it (no decision record was ever expected); re-queued 4 Sep 2026')
     where id = s.xid;
    update public.workflow_step_run set status = 'running' where id = s.sid and status = 'ready';
    v_q := v_q + 1;
  end loop;

  -- 2. QUEUE the ready steps a registered, low-risk, reversible edge executor can run WITHOUT
  --    delivering a message to a person — and, while the model is held, without needing the model.
  for s in
    select r.id, r.workflow_run_id, r.step_no, r.actor, r.action_class, r.input,
           e.target, e.risk_tier, e.reversible
      from public.workflow_step_run r
      join public.org_action_executor e on e.action_class = r.action_class
     where r.status = 'ready' and r.finished_at is null
       and e.kind in ('edge','rpc') and e.active
       and e.risk_tier = 'low' and e.advisory_safe and e.reversible
       and not e.notifies_human
       and coalesce(e.required_authority,'') <> 'founder'
       and not (v_held and public.fn_executor_needs_model(e.target))
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

  select count(*), string_agg(distinct why, '; ') into v_ineligible, v_why from (
    select sr.id,
           case when e.action_class is null then 'no executor is mapped to ' || sr.action_class
                when e.kind not in ('edge','rpc') then sr.action_class || ' is a ' || e.kind || ' executor and no invoker handles that kind'
                when not e.active then sr.action_class || ' executor is inactive'
                when e.risk_tier <> 'low' then sr.action_class || ' is risk_tier ' || e.risk_tier
                when not e.advisory_safe then sr.action_class || ' is not advisory_safe'
                when not e.reversible then sr.action_class || ' is not reversible'
                when e.notifies_human then sr.action_class || ' notifies a human'
                when v_held and public.fn_executor_needs_model(e.target) then
                     sr.action_class || ' runs on the paid model, which is held; the dispatcher works it deterministically'
                when exists(select 1 from public.action_execution x where x.workflow_step_run_id = sr.id)
                     and not exists(select 1 from public.action_execution x
                                     where x.workflow_step_run_id = sr.id
                                       and x.status in ('queued','running','succeeded')) then
                     sr.action_class || ' has only a terminal (cancelled/failed/held) action_execution; while the model is held the dispatcher works it deterministically'
           end as why
      from public.workflow_step_run sr
      left join public.org_action_executor e on e.action_class = sr.action_class
     where sr.status = 'ready' and sr.finished_at is null and sr.action_class is not null
  ) q where why is not null;
  v_ineligible := coalesce(v_ineligible, 0);
  v_true_stall := greatest(v_parked - v_noclass - v_throttled - v_ineligible, 0);

  v_out := jsonb_build_object(
    'settled', v_settled, 'queued', v_q, 'ran_at', now(), 'model_held', v_held,
    'parked', v_parked, 'parked_without_action_class', v_noclass,
    'parked_throttled_by_reflection_ceiling', v_throttled,
    'reflection_worked_today', v_reflection_today, 'reflection_cap', v_cap,
    'parked_ineligible_by_policy', v_ineligible,
    'parked_ineligible_because', coalesce(v_why, ''),
    'parked_unexplained', v_true_stall,
    'ready_runnable', (select count(*) from public.workflow_step_run r
                         join public.org_action_executor e on e.action_class = r.action_class
                        where r.status = 'ready' and e.kind in ('edge','rpc') and e.active
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

  -- Stranded steps are the dispatcher's while the model is held (fn_workflow_step_claim). The dedup
  -- backlog task is raised only when the hold is NOT in force, i.e. when nothing else will take them.
  if not v_held and (select count(*) from public.workflow_step_run sr
               where sr.status='ready' and sr.finished_at is null and sr.action_class is not null
                 and exists(select 1 from public.action_execution x where x.workflow_step_run_id=sr.id)
                 and not exists(select 1 from public.action_execution x
                                 where x.workflow_step_run_id=sr.id and x.status in ('queued','running','succeeded'))) > 0 then
    begin
      insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
      select 'exec', 'Re-open workflow steps stranded by a cancelled action',
             (select count(*) from public.workflow_step_run sr
               where sr.status='ready' and sr.finished_at is null and sr.action_class is not null
                 and exists(select 1 from public.action_execution x where x.workflow_step_run_id=sr.id)
                 and not exists(select 1 from public.action_execution x
                                 where x.workflow_step_run_id=sr.id and x.status in ('queued','running','succeeded')))
             || ' workflow step(s) are ready but each has only a terminal (cancelled/failed) '
             || 'action_execution, so the sweep will not re-queue over it. Re-open them for a fresh '
             || 'attempt or drive the review-decision loop they await; a cancelled action must also settle its step.',
             'proposed', 'gated', false, 'incident_fix'
      where not exists (select 1 from public.org_tasks
                         where title = 'Re-open workflow steps stranded by a cancelled action'
                           and status <> 'done');
    exception when others then null; end;
  end if;

  return v_out;
end $function$;

-- ---------------------------------------------------------------------------------------------------
-- fn_workflow_step_claim: the dispatcher's queue. While the model is held it also hands over every
-- step the sweep cannot finish, flagged deterministic_only, and skips steps parked awaiting the model.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_workflow_step_claim(p_limit integer default 5)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_out jsonb; v_today int; v_cap int; v_demand_ready int; v_held boolean;
begin
  v_held := coalesce((public.fn_kernel_paid_provider_gate('anthropic/claude-sonnet-5')->>'allowed')::boolean, false) = false;

  update public.workflow_step_run sr
     set status = 'ready'
   where sr.status = 'running'
     and sr.finished_at is null
     and sr.started_at < now() - interval '15 minutes'
     and not exists (select 1 from public.action_execution x
                      where x.workflow_step_run_id = sr.id
                        and x.status in ('queued','running','succeeded'));

  select coalesce((value #>> '{}')::int, 6) into v_cap
    from public.decision_policy where key = 'workflow_reflection_steps_per_day';
  v_cap := coalesce(v_cap, 6);

  -- NON-DEMAND ONLY, and MODEL WORK ONLY: the ceiling exists to bound paid reasoning. A deterministic
  -- determination costs nothing and is not counted against it.
  select count(*) into v_today
    from public.workflow_step_run sr
   where sr.output->>'worked_by' = 'workflow_dispatch'
     and coalesce(sr.output->>'used_llm', 'true') <> 'false'
     and sr.finished_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc'
     and not public.fn_task_is_demand(sr.action_class);

  select count(*) into v_demand_ready
    from public.workflow_step_run sr
    join public.workflow_run r on r.id = sr.workflow_run_id
   where sr.status = 'ready'
     and sr.finished_at is null
     and r.status = 'running'
     and r.workflow_key <> 'employee_task'
     and coalesce(sr.input->>'gate','') <> 'founder'
     and public.fn_task_is_demand(sr.action_class)
     and public.fn_workflow_actor_resolve(sr.workflow_run_id, sr.actor) is not null
     and not exists (
           select 1 from public.org_action_executor e
            where e.action_class = sr.action_class and e.active and e.kind = 'edge'
              and e.risk_tier = 'low' and e.advisory_safe and e.reversible
              and not e.notifies_human
              and coalesce(e.required_authority,'') <> 'founder');

  if not v_held and v_today >= v_cap and v_demand_ready = 0 then
    return jsonb_build_object('capped', true, 'worked_today', v_today, 'cap', v_cap,
             'demand_ready', 0,
             'note', 'the daily reflection ceiling is spent and no revenue-path step is waiting; see '
                     || 'scripts/sql/the_dispatchers_ceiling_counted_revenue_work_against_reflection.sql');
  end if;

  with pick as (
    select sr.id
      from public.workflow_step_run sr
      join public.workflow_run r on r.id = sr.workflow_run_id
     where sr.status = 'ready'
       and sr.finished_at is null
       and r.status = 'running'
       and r.workflow_key <> 'employee_task'
       and coalesce(sr.input->>'gate','') <> 'founder'
       and (public.fn_task_is_demand(sr.action_class) or v_today < v_cap or v_held)
       and public.fn_workflow_actor_resolve(sr.workflow_run_id, sr.actor) is not null
       -- parked awaiting the model: not claimed again until the hold lifts
       and not (v_held and coalesce(sr.error->>'disposition','') = 'awaiting_model')
       and (
         -- (a) no safe executor owns it: the dispatcher's row, as before
         not exists (
             select 1 from public.org_action_executor e
              where e.action_class = sr.action_class and e.active and e.kind = 'edge'
                and e.risk_tier = 'low' and e.advisory_safe and e.reversible
                and not e.notifies_human
                and coalesce(e.required_authority,'') <> 'founder')
         -- (b) the model is held and the safe executor cannot finish it: it runs on the model, or it
         --     already left only terminal (held/cancelled/stalled) executions behind
         or (v_held and (
               exists (select 1 from public.org_action_executor e
                        where e.action_class = sr.action_class and e.active
                          and public.fn_executor_needs_model(e.target))
            -- stranded: parked held/stalled, or cancelled on a REFUSAL or a missing decision record.
            -- (A never-dispatched cancel is the sweep's to re-queue, not the dispatcher's.)
            or (exists (select 1 from public.action_execution x
                         where x.workflow_step_run_id = sr.id
                           and (x.status in ('held','stalled')
                                or (x.status = 'cancelled'
                                    and (x.response->>'invoker' = 'refused' or (x.request ? 'decision_record_id')))))
                and not exists (select 1 from public.action_execution x
                                 where x.workflow_step_run_id = sr.id
                                   and x.status in ('queued','running','succeeded')))))
       )
     -- fresh steps before retries: 24 change_deployment step-1 retries (3 attempts each before they
     -- park) must not starve a step that has never been looked at
     order by coalesce(sr.attempts, 0), sr.id
     limit greatest(least(coalesce(p_limit, 5),
                          case when v_held then coalesce(p_limit, 5)
                               else greatest(v_cap - v_today, 0) + v_demand_ready end), 1)
     for update of sr skip locked
  ), claimed as (
    update public.workflow_step_run sr
       set status = 'running', started_at = now()
      from pick
     where sr.id = pick.id
    returning sr.id, sr.workflow_run_id, sr.step_no, sr.actor, sr.action_class, sr.input, sr.attempts, sr.error
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'step_run_id',  c.id,
           'run_id',       c.workflow_run_id,
           'step_no',      c.step_no,
           'employee',     public.fn_workflow_actor_resolve(c.workflow_run_id, c.actor),
           'addressed_as', coalesce(c.input->>'addressed_as', c.actor),
           'action_class', c.action_class,
           'step',         c.input->>'step',
           'gate',         c.input->>'gate',
           'workflow_key', r.workflow_key,
           'workflow',     w.name,
           'context',      r.context,
           'attempts',     coalesce(c.attempts, 0),
           'model_held',   v_held,
           'deterministic_only', v_held,
           'stranded_reason', case
              when exists (select 1 from public.org_action_executor e
                            where e.action_class = c.action_class and e.active and e.kind = 'edge'
                              and e.risk_tier = 'low' and e.advisory_safe and e.reversible
                              and not e.notifies_human)
               then coalesce((select 'executor ' || coalesce(x.executor, e2.target) || ' left status=' || x.status
                                     || coalesce(' (' || (x.response->>'reason') || ')', '')
                                from public.action_execution x
                                join public.org_action_executor e2 on e2.action_class = c.action_class and e2.active
                               where x.workflow_step_run_id = c.id
                               order by x.created_at desc limit 1),
                             'executor runs on the held paid model; not queued')
              else null end,
           'prior_steps', (select coalesce(jsonb_agg(jsonb_build_object(
                                    'step_no', p.step_no,
                                    'step',    p.input->>'step',
                                    'by',      coalesce(p.output->>'employee', p.actor),
                                    'outcome', left(coalesce(p.output->>'outcome',
                                                             p.output->>'note', ''), 600))
                                  order by p.step_no), '[]'::jsonb)
                             from (select p2.* from public.workflow_step_run p2
                                    where p2.workflow_run_id = c.workflow_run_id
                                      and p2.step_no < c.step_no
                                      and p2.status = 'done'
                                      and coalesce(p2.output->>'outcome', p2.output->>'note','') <> ''
                                    order by p2.step_no desc
                                    limit 3) p)
         ) order by c.id), '[]'::jsonb)
    into v_out
    from claimed c
    join public.workflow_run r on r.id = c.workflow_run_id
    left join public.workflow w on w.workflow_key = r.workflow_key;

  return v_out;
end
$function$;

-- ---------------------------------------------------------------------------------------------------
-- fn_workflow_step_release: back to 'ready' with a readable reason. A step no playbook covers is
-- parked after 3 attempts as disposition='awaiting_model' — a distinct state from success and from a
-- fresh retry — and the claim leaves it alone until the hold lifts.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_workflow_step_release(p_step_run_id bigint, p_reason text)
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_attempts int; v_disp text;
begin
  select coalesce(attempts,0) + 1 into v_attempts from public.workflow_step_run
   where id = p_step_run_id and status = 'running' and finished_at is null;
  if not found then return 'not held'; end if;

  v_disp := case when v_attempts >= 3 and coalesce(p_reason,'') ~* '^no company playbook'
                 then 'awaiting_model' else 'retry' end;

  update public.workflow_step_run
     set status   = 'ready',
         attempts = v_attempts,
         error    = jsonb_build_object('released_at', now(), 'reason', left(coalesce(p_reason,''), 500),
                                       'released_by', 'workflow_dispatch',
                                       'attempts', v_attempts,
                                       'disposition', v_disp,
                                       'note', case when v_disp = 'awaiting_model'
                                                    then 'parked: no company playbook covered this step in ' || v_attempts
                                                      || ' deterministic attempts; it waits for the ~5% model path (held) and is not retried until the hold lifts'
                                                    else null end)
   where id = p_step_run_id and status = 'running' and finished_at is null;
  return case when v_disp = 'awaiting_model' then 'parked awaiting model' else 'released' end;
end
$function$;

-- ---------------------------------------------------------------------------------------------------
-- fn_workflow_step_deterministic_done: the ONLY way a deterministic determination closes a step.
-- Refuses a determination without substance (playbook id, similarity at/above the floor, deliverable
-- length), seals the decision_trace, queues the review, cancels the superseded held execution, then
-- advances through fn_workflow_step_done. p_output is the dispatcher's step output.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_workflow_step_deterministic_done(p_step_run_id bigint, p_output jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  sr           record;
  v_sim        numeric;
  v_floor      numeric := 0.42;
  v_deliv      text;
  v_employee   text;
  v_dept       text;
  v_trace      uuid;
  v_review     bigint;
  v_superseded int := 0;
  v_res        text;
  v_out        jsonb;
begin
  select s.id, s.workflow_run_id, s.step_no, s.actor, s.action_class, s.input, s.attempts,
         r.workflow_key, r.context, r.correlation_id, r.trigger_event_id
    into sr
    from public.workflow_step_run s
    join public.workflow_run r on r.id = s.workflow_run_id
   where s.id = p_step_run_id and s.status = 'running' and s.finished_at is null;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'step is not held running by a dispatcher');
  end if;

  v_deliv    := coalesce(p_output->>'deliverable', '');
  v_sim      := nullif(p_output->>'similarity', '')::numeric;
  v_employee := coalesce(nullif(p_output->>'employee',''), sr.actor);

  -- FALSE-SUCCESS GUARDS. Nothing below runs unless the determination has substance.
  if coalesce(p_output->>'playbook_record_id','') = '' then
    return jsonb_build_object('ok', false, 'reason', 'no playbook_record_id: a determination must cite the company knowledge it applied');
  end if;
  if v_sim is null or v_sim < v_floor then
    return jsonb_build_object('ok', false, 'reason', 'similarity ' || coalesce(v_sim::text,'null') || ' is below the apply floor ' || v_floor);
  end if;
  if length(v_deliv) < 300 then
    return jsonb_build_object('ok', false, 'reason', 'deliverable shorter than 300 characters is not a determination');
  end if;
  if not exists (select 1 from public.ops_knowledge k where k.record_id = p_output->>'playbook_record_id' and k.runtime_eligible) then
    return jsonb_build_object('ok', false, 'reason', 'playbook ' || (p_output->>'playbook_record_id') || ' is not a runtime-eligible ops_knowledge record');
  end if;

  select o.department into v_dept from public.org_agents o where o.agent_key = v_employee;

  -- The sealed record of what was decided, on what, by which rule, with what confidence.
  insert into public.decision_trace(
      correlation_id, causation_event_id, entity_type, entity_id, decision_type,
      proposed_by, decided_by, policy_keys, knowledge_refs, evidence_refs, alternatives,
      assumptions, risk, confidence, authority_result,
      decision, outcome_status, agent_key, department_id, task_class,
      knowledge_versions, source_freshness, tools_requested, tools_executed, tool_result_refs,
      uncertainty, escalation_decision, proposed_action, expected_outcome,
      model, provider, input_tokens, output_tokens, estimated_cost_aed, final_status, sealed_at)
  values (
      coalesce(sr.correlation_id, gen_random_uuid()), sr.trigger_event_id,
      'workflow_step_run', sr.id::text, 'deterministic_playbook_application',
      v_employee, 'fn_apply_playbook', array['deterministic_first']::text[],
      jsonb_build_array(jsonb_build_object('record_id', p_output->>'playbook_record_id',
                                           'title', p_output->>'playbook_title',
                                           'similarity', v_sim)),
      jsonb_build_array(jsonb_build_object('workflow_run_id', sr.workflow_run_id, 'workflow_key', sr.workflow_key,
                                           'step_no', sr.step_no, 'step', sr.input->>'step',
                                           'trigger_context', sr.context)),
      coalesce(p_output->'candidates', '[]'::jsonb),
      jsonb_build_array('the nearest company playbook by cosine similarity is the applicable one for this step'),
      jsonb_build_object('level', 'low', 'note', 'advisory determination; moves no money, sends nothing, approves nobody'),
      v_sim,
      jsonb_build_object('mode', 'advisory', 'gate', coalesce(sr.input->>'gate', 'none'), 'paid_provider', 'held'),
      jsonb_build_object('determination', left(v_deliv, 8000), 'outcome', p_output->>'outcome',
                         'basis', 'nearest company knowledge by meaning; no model call'),
      'pending', v_employee, v_dept, 'workflow_step',
      '{}'::jsonb, jsonb_build_object('ops_knowledge', 'live at decision time'), '{}'::text[], '{}'::text[], '[]'::jsonb,
      'low-confidence deterministic disposition: the nearest playbook was applied, not reasoned over; queued for review',
      'review_queued', 'mark the workflow step done with a deterministic disposition',
      'the run advances to its deterministic tail steps; a reviewer can overturn the determination',
      'none', 'deterministic', 0, 0, 0, 'auto_done', now())
  returning id into v_trace;

  -- Never a silent pass: the determination is queued for review, with everything needed to overturn it.
  insert into public.review_queue(kind, dept_key, title, summary, payload, status)
  values ('deterministic_step', v_dept,
          left('Deterministic determination: ' || sr.workflow_key || ' step ' || sr.step_no || ' — ' || coalesce(sr.input->>'step',''), 240),
          left(coalesce(p_output->>'outcome',''), 600),
          jsonb_build_object('workflow_run_id', sr.workflow_run_id, 'step_run_id', sr.id, 'step_no', sr.step_no,
                             'employee', v_employee, 'playbook_record_id', p_output->>'playbook_record_id',
                             'playbook_title', p_output->>'playbook_title', 'similarity', v_sim,
                             'decision_trace_id', v_trace, 'disposition', 'deterministic_low_confidence'),
          'pending')
  returning id into v_review;

  -- The executor's parked/stranded attempt is superseded: fn_action_release_held must not re-run it at
  -- launch over a step that is already closed.
  update public.action_execution
     set status = 'cancelled', finished_at = coalesce(finished_at, now()),
         response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
           'superseded_at', now(), 'superseded_by', 'deterministic determination',
           'decision_trace_id', v_trace, 'prior_status', status)
   where workflow_step_run_id = sr.id and status in ('held','stalled');
  get diagnostics v_superseded = row_count;

  v_out := coalesce(p_output, '{}'::jsonb) || jsonb_build_object(
             'used_llm', false,
             'disposition', 'deterministic_low_confidence',
             'decision_trace_id', v_trace,
             'review_queue_id', v_review,
             'review_status', 'pending',
             'superseded_executions', v_superseded);

  v_res := public.fn_workflow_step_done(sr.workflow_run_id, sr.step_no, v_out, 'done');

  return jsonb_build_object('ok', true, 'advanced', v_res, 'decision_trace_id', v_trace,
                            'review_queue_id', v_review, 'superseded_executions', v_superseded);
end
$function$;

revoke execute on function public.fn_workflow_step_deterministic_done(bigint, jsonb) from public;
revoke execute on function public.fn_executor_needs_model(text) from public;

-- ---------------------------------------------------------------------------------------------------
-- fn_workflow_run_follow_task: an employee_task run mirrors ONE org_task. It now also closes when the
-- owning task is CANCELLED (80 runs from August sat 'running' behind cancelled tasks because the
-- trigger only knew done/failed/escalated), and carries the task's used_llm marker into the closure.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_workflow_run_follow_task()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_run uuid; v_run_status text;
begin
  if new.status is not distinct from old.status then return new; end if;
  if new.status not in ('done','failed','escalated','cancelled') then return new; end if;

  v_run_status := case when new.status = 'done' then 'done'
                       when new.status = 'cancelled' then 'cancelled'
                       else 'failed' end;

  for v_run in
    select r.id from public.workflow_run r
     where r.workflow_key = 'employee_task'
       and r.status = 'running'
       and (r.context->>'task_id') = new.id::text
  loop
    update public.workflow_step_run
       set status = 'skipped', finished_at = now(),
           output = coalesce(output, '{}'::jsonb) || jsonb_build_object(
             'closed_by', 'owning_org_task', 'org_task_id', new.id,
             'org_task_status', new.status,
             'used_llm', case when (new.result->>'used_llm') in ('true','false') then (new.result->>'used_llm')::boolean else null end,
             'note', case when new.status = 'cancelled'
                          then 'the owning task was cancelled; this step was never separately observed, so it is skipped rather than claimed as done'
                          else 'the owning task was performed and reviewed as one act; this step was never '
                            || 'separately observed, so it is skipped rather than claimed as done' end)
     where workflow_run_id = v_run and finished_at is null;

    update public.workflow_run
       set status      = v_run_status,
           finished_at = now(),
           updated_at  = now(),
           context     = coalesce(context,'{}'::jsonb)
                         || jsonb_build_object('closed_by','owning_org_task',
                                               'org_task_status', new.status,
                                               'used_llm', case when (new.result->>'used_llm') in ('true','false') then (new.result->>'used_llm')::boolean else null end),
           error       = case when new.status = 'done' then null
                              else jsonb_build_object('owning_org_task', new.id,
                                                      'org_task_status', new.status,
                                                      'reason', case when new.status = 'cancelled' then 'the owning org_task was cancelled' else 'the owning org_task ended ' || new.status end) end
     where id = v_run;
  end loop;
  return new;
end
$function$;

-- ---------------------------------------------------------------------------------------------------
-- cred_action_invoker (context action.invoker) was scoped from the executor registry the day it was
-- issued. Widen it to every low-risk advisory-safe reversible edge executor registered SINCE, with the
-- same predicate — os_incidents and resilience_ping today. Idempotent: a target already in scope is
-- not appended twice.
-- ---------------------------------------------------------------------------------------------------
do $$
declare v_missing text[];
begin
  select array_agg(distinct e.target order by e.target) into v_missing
    from public.org_action_executor e
    join public.internal_credential c on c.context = 'action.invoker' and c.active
   where e.kind = 'edge' and e.active and e.risk_tier = 'low' and e.advisory_safe and e.reversible
     and not (e.target = any(c.scope));
  if v_missing is not null then
    update public.internal_credential
       set scope = (select array_agg(distinct t order by t) from unnest(scope || v_missing) t)
     where context = 'action.invoker' and active;
    raise notice 'action.invoker scope widened by %', v_missing;
  end if;
end $$;

commit;
