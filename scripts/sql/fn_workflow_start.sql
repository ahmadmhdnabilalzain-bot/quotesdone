-- comp-09-workflow-execution — "Workflows execute and are tracked."
--
-- workflow held 14 active rows and workflow_step 117 steps. workflow_run and workflow_step_run held
-- ZERO rows and had zero readers — the tables, their unique idempotency keys, their lease columns
-- and their retry columns were all built and nothing ever created a run. The workflow layer was a
-- diagram of how work is supposed to move, and no work has ever moved through it.
--
-- COORDINATION: fn_event_dispatch belongs to the bus agent this session, so this file does NOT
-- edit it. fn_workflow_start is exposed for it to call, and until it does, fn_workflow_start_due
-- picks up matching events on its own cron. The two are safe together: the idempotency key is
-- (workflow_key, trigger_event_id), so the same event starting a workflow twice — once from the
-- dispatcher and once from the catcher — produces one run, not two.
--   >>> NOTE FOR THE BUS AGENT: inside fn_event_dispatch, after the event's os_key is resolved, add
--   >>>   perform public.fn_workflow_start(w.workflow_key, v_event.id, 'company_event',
--   >>>                                    v_event.id::text, v_event.payload)
--   >>>     from public.workflow w where w.active and w.trigger_event = v_event.event_type;
--   >>> and fn_workflow_start_due's cron can then be dropped.
--
-- NO EVENT IS EMITTED FROM HERE, deliberately. review_chain -> company_event -> fn_event_dispatch
-- produced 169 tasks in one hour on 6 Aug. A workflow run that emitted an event on start would feed
-- the dispatcher that started it. workflow_run and workflow_step_run carry no triggers (checked),
-- so writing them is inert.

create or replace function public.fn_workflow_start(
  p_workflow_key text,
  p_trigger_event_id bigint DEFAULT NULL::bigint,
  p_entity_type text DEFAULT NULL::text,
  p_entity_id text DEFAULT NULL::text,
  p_context jsonb DEFAULT '{}'::jsonb)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_run uuid; v_key text; v_corr uuid; v_first int;
begin
  if not exists (select 1 from workflow w where w.workflow_key = p_workflow_key and coalesce(w.active,true))
    then return null; end if;

  -- One run per (workflow, triggering event). Without the event there is nothing to be idempotent
  -- against, so a manual start gets its own key rather than silently colliding with the last one.
  v_key := p_workflow_key || ':' || coalesce(p_trigger_event_id::text, gen_random_uuid()::text);

  select e.correlation_id into v_corr from company_event e where e.id = p_trigger_event_id;

  insert into workflow_run (workflow_key, trigger_event_id, correlation_id, entity_type, entity_id,
                            idempotency_key, status, current_step, context, started_at)
  values (p_workflow_key, p_trigger_event_id, v_corr, p_entity_type, p_entity_id,
          v_key, 'running', 0, coalesce(p_context,'{}'::jsonb), now())
  on conflict (idempotency_key) do nothing
  returning id into v_run;

  if v_run is null then
    select id into v_run from workflow_run where idempotency_key = v_key;
    return v_run;                      -- already started; nothing to re-plan
  end if;

  -- Plan every step of the workflow up front. A run whose steps are only materialised as they are
  -- reached cannot be read as "where is this piece of work", which is the entire value of the table.
  insert into workflow_step_run (workflow_run_id, step_no, actor, action_class, status,
                                 input, idempotency_key)
  select v_run, s.step_no, s.actor_role, s.action_class, 'queued',
         jsonb_build_object('step', s.step, 'gate', s.gate),
         v_key || '#' || s.step_no
    from workflow_step s
   where s.workflow_key = p_workflow_key
   order by s.step_no
  on conflict (idempotency_key) do nothing;

  select min(step_no) into v_first from workflow_step_run where workflow_run_id = v_run;
  if v_first is null then
    -- A workflow with no steps cannot be in flight. Closing it here stops it sitting in the
    -- in-flight list forever pretending to be work.
    update workflow_run set status = 'done', finished_at = now(), updated_at = now()
     where id = v_run;
    return v_run;
  end if;

  update workflow_step_run set status = 'ready', started_at = now()
   where workflow_run_id = v_run and step_no = v_first;
  update workflow_run set current_step = v_first, updated_at = now() where id = v_run;
  return v_run;
end $function$;


-- Close a step and hand the run to the next one. This is what makes workflow_run a live position
-- rather than a creation record: without it every run sits on step 1 forever and "tracked" is a
-- claim about a row that never changes.
create or replace function public.fn_workflow_step_done(
  p_run uuid, p_step_no integer, p_output jsonb DEFAULT '{}'::jsonb, p_status text DEFAULT 'done')
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_next int;
begin
  update workflow_step_run
     set status = p_status, output = coalesce(p_output,'{}'::jsonb), finished_at = now(),
         attempts = coalesce(attempts,0) + 1
   where workflow_run_id = p_run and step_no = p_step_no;
  if not found then return 'no such step'; end if;

  if p_status <> 'done' then
    update workflow_run set status = 'failed', finished_at = now(), updated_at = now(),
           error = jsonb_build_object('failed_step', p_step_no, 'status', p_status)
     where id = p_run;
    return 'failed at step ' || p_step_no;
  end if;

  select min(step_no) into v_next from workflow_step_run
   where workflow_run_id = p_run and step_no > p_step_no and status = 'queued';

  if v_next is null then
    update workflow_run set status = 'done', finished_at = now(), updated_at = now(),
           current_step = p_step_no
     where id = p_run;
    return 'run complete';
  end if;

  update workflow_step_run set status = 'ready', started_at = now()
   where workflow_run_id = p_run and step_no = v_next;
  update workflow_run set current_step = v_next, updated_at = now() where id = p_run;
  return 'advanced to step ' || v_next;
end $function$;


-- The catcher. Runs on a cron until fn_event_dispatch calls fn_workflow_start itself.
-- p_lookback_minutes = 0 means "every event ever", which is what a first run needs: 15 events
-- matching a workflow trigger already exist on production and none of them ever started anything.
create or replace function public.fn_workflow_start_due(p_lookback_minutes integer DEFAULT 1440)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; n int := 0;
begin
  for r in
    select w.workflow_key, e.id, e.event_type, e.payload
      from company_event e
      join workflow w on w.trigger_event = e.event_type and coalesce(w.active,true)
     where p_lookback_minutes = 0
        or e.occurred_at > now() - make_interval(mins => p_lookback_minutes)
     order by e.id
     limit 200
  loop
    if not exists (select 1 from workflow_run x
                    where x.idempotency_key = r.workflow_key || ':' || r.id::text) then
      perform public.fn_workflow_start(r.workflow_key, r.id, 'company_event', r.id::text,
                                       coalesce(r.payload,'{}'::jsonb));
      n := n + 1;
    end if;
  end loop;
  return n;
end $function$;

-- Every 15 minutes. Batch-capped at 200 per run so a backlog drains rather than arriving at once.
select cron.schedule('workflow_start_due', '*/15 * * * *',
                     'select public.fn_workflow_start_due(1440);');

-- Drain the existing backlog on BOTH projects: goal.at_risk and kpi.missed have fired 15 times
-- between them and started nothing. 0 = every event ever, not just the last day.
select public.fn_workflow_start_due(0);
