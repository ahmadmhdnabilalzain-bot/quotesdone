-- Down for claim_leaves_rpc_executor_steps_to_the_sweep.sql: restores fn_workflow_step_claim as it ran on production on 4 Sep 2026.
begin;
CREATE OR REPLACE FUNCTION public.fn_workflow_step_claim(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
       -- THE ORG_TASK LANE (§4.3). An employee_task run is the promotion of one org_task into the
       -- spine; the dispatcher works it while the task is still open, and the follow trigger owns it
       -- once the task has closed or parked. A run whose task is gone is nobody's work.
       and (r.workflow_key <> 'employee_task'
            or exists (select 1 from public.org_tasks t
                        where t.id::text = r.context->>'task_id'
                          and t.status in ('assigned','in_progress')))
       and coalesce(sr.input->>'gate','') <> 'founder'
       -- the reflection ceiling is untouched: it bounds PAID reasoning, and while the model is held
       -- (v_held) nothing here can reach a paid provider. When the hold lifts the lane obeys it.
       and (public.fn_task_is_demand(sr.action_class) or v_today < v_cap or v_held)
       and public.fn_workflow_actor_resolve(sr.workflow_run_id, sr.actor) is not null
       -- parked awaiting the model: not claimed again until the hold lifts
       and not (v_held and coalesce(sr.error->>'disposition','') = 'awaiting_model')
       and (
         -- the org_task lane is always the dispatcher's: its executor (cos_execute on coordinate) was
         -- retired on 3 Sep and the sweep's low-risk predicate never accepted it
         r.workflow_key = 'employee_task'
         -- (a) no safe executor owns it: the dispatcher's row, as before
         or not exists (
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
           -- THE ORG_TASK LANE: the work is the task, not the loop step it is recorded under.
           'lane',                 case when r.workflow_key = 'employee_task' and t.id is not null then 'org_task' else 'workflow_step' end,
           'org_task_id',           t.id,
           'org_task_title',        t.title,
           'org_task_detail',       left(coalesce(t.detail, ''), 2000),
           'org_task_dept',         t.dept_key,
           'org_task_action_class', t.action_class,
           'org_task_subject',      case when t.id is null then null
                                         else public.fn_org_task_subject(t.title, t.action_class, t.dept_key) end,
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
    left join public.workflow w on w.workflow_key = r.workflow_key
    left join public.org_tasks t on r.workflow_key = 'employee_task'
                                and t.id::text = r.context->>'task_id';

  return v_out;
end
$function$
;
commit;
