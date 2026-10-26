-- I FLOODED THE FOUNDER'S INBOX. THIS IS THE ROOT-CAUSE FIX, NOT A PATCH ON MY SWEEP.
--
-- fn_workflow_step_sweep queued five `forecast` steps at 00:26 UTC. `forecast` targets the
-- cost_snapshot edge function, which EMAILS THE WEEKLY BURN SNAPSHOT. He got four identical copies
-- inside the same second, on top of four identical "AI credit low" alerts from the health_report
-- steps in the batch before it. He noticed before I did.
--
-- The sweep's eligibility predicate is the estate's own: low + advisory_safe + reversible. Every one
-- of those flags was TRUE for cost_snapshot, and every one of them was correct on its own terms --
-- which is what makes this worth fixing properly rather than special-casing one target.
--
--   `advisory_safe` means "does not change business state". Sending mail does not change business
--   state. It changes his morning.
--   `reversible` means "the data effect can be undone". A sent email cannot be unsent, so
--   reversible=true is describing the row it writes, not the message it delivers.
--
-- Six executors are marked low + advisory_safe + reversible AND write to `notifications`:
-- capability_review, expense_log, forecast, health_report, money_verify, security_review. Any of the
-- three sweeps in this estate could have picked any of them; mine got there first because `forecast`
-- and `health_report` only appear as workflow steps.
--
-- So the classification gains the fact it was missing. `notifies_human` is not a risk tier and does
-- not overlap one: an action can be perfectly safe, perfectly reversible, and still be something a
-- machine must not do on a ten-minute loop because a person receives it. All three sweeps exclude it,
-- so this cannot bite the fourth sweep either. Cron and the invoker still call these directly --
-- cost_snapshot_weekly on Monday and cost_snapshot_balance_daily at 05:00 are how he is SUPPOSED to
-- get it, and they are untouched.

alter table public.org_action_executor
  add column if not exists notifies_human boolean not null default false;

comment on column public.org_action_executor.notifies_human is
  'True when invoking this executor delivers a message to a person (email, SMS, WhatsApp). Excluded '
  'from every automatic sweep regardless of risk_tier, because advisory_safe describes business '
  'state and reversible describes the data effect -- neither describes an inbox, and a sent message '
  'cannot be unsent. Set on 2026-08-11 after fn_workflow_step_sweep sent the founder four identical '
  'burn snapshots inside one second.';

update public.org_action_executor
   set notifies_human = true
 where action_class in ('forecast','health_report','capability_review','expense_log',
                        'money_verify','security_review','escalate_founder','nudge',
                        'outreach_send','collections_chase');

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

  return jsonb_build_object(
    'settled', v_settled, 'queued', v_q, 'ran_at', now(),
    'ready_runnable', (select count(*) from public.workflow_step_run r
                         join public.org_action_executor e on e.action_class = r.action_class
                        where r.status = 'ready' and e.kind='edge' and e.active
                          and e.risk_tier='low' and e.advisory_safe and e.reversible
                          and not e.notifies_human),
    'ready_held_notifies_human', (select count(*) from public.workflow_step_run r
                                    join public.org_action_executor e on e.action_class = r.action_class
                                   where r.status = 'ready' and e.notifies_human),
    'never_finished', (select count(*) from public.workflow_step_run where finished_at is null));
end $function$;

-- The other two sweeps share the predicate and the exposure, so they get the same clause. Neither has
-- fired a notifying executor yet only because none of their action classes happens to be one.
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
       and not e.notifies_human
       and coalesce(e.required_authority,'') <> 'founder'
       -- ALL statuses. idempotency_key is UNIQUE, so a task whose invocation FAILED once collides on
       -- the next sweep: org_task:260 failed org_task_execute_sweep_hourly at 14:45, 15:45 and 16:45
       -- on 10 Aug. A failed attempt is a recorded attempt.
       and not exists (select 1 from public.action_execution x
                        where x.idempotency_key = 'org_task:' || k.id)
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
            'queued', 0)
    on conflict (idempotency_key) do nothing;

    update public.org_tasks set status = 'in_progress', last_run_at = now(), updated_at = now()
     where id = t.id and status = 'assigned';
    v_q := v_q + 1;
  end loop;

  return jsonb_build_object('queued', v_q, 'ran_at', now(),
    'eligible_remaining', (select count(*) from public.org_tasks k
                             join public.org_action_executor e on e.action_class = k.action_class
                            where k.status in ('assigned','in_progress') and e.kind='edge' and e.active
                              and e.risk_tier='low' and e.advisory_safe and e.reversible
                              and not e.notifies_human
                              and not exists (select 1 from public.action_execution x
                                               where x.idempotency_key = 'org_task:' || k.id)));
end $function$;
