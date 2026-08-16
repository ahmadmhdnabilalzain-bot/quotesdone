-- Phase C correction 4b — a consumer that re-emitted the event it was consuming, and the rollback
-- of what that cost.
--
-- WHAT HAPPENED, said plainly, because it happened during this correction and not before it.
-- phase_c_32 deployed the delivery worker on a one-minute cron. phase_c_38 was supposed to
-- quarantine the three pre-fix outbox rows carrying EV-W01-STARTED for W20 commands BEFORE anything
-- could deliver them. It was applied second. At 10:28 the worker took all three, called
-- fn_phase_c_event_ingress, and created exactly the thing the quarantine existed to prevent: three
-- W01 workflow runs accountable to the CEO, with tasks for the Chief of Staff, from three marketing
-- commands. The increment is rolled back below.
--
-- The delivery itself then exposed a second defect, this one in the code rather than the order:
-- fn_phase_c_event_ingress EMITS the event it was given, because it is the producer path. Called
-- from the consumer it therefore re-emitted the same event — outbox rows 239, 240 and 241, one
-- minute later. Dedupe stopped it converging into a loop, but a queue that feeds itself is not a
-- queue. The producer path keeps its emit; the consumer path is told not to.

-- ================================================================ 1. the emit is the producer's
create or replace function public.fn_phase_c_event_ingress(
  p_event_id text, p_business_object_id text, p_ctx jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  e public.phase_b_event%rowtype;
  s public.phase_b_workflow_step%rowtype;
  v_run bigint; v_step text; v_step_run bigint; v_task bigint; v_outbox bigint;
  v_owner text; v_input_hash text; v_run_trace bigint; v_task_trace bigint; v_emit boolean;
begin
  select * into e from public.phase_b_event where event_id = p_event_id;
  if not found then
    raise exception 'fn_phase_c_event_ingress: % is not a canonical Phase B event — fail closed',
      p_event_id using errcode = '23503';
  end if;
  if coalesce(btrim(p_business_object_id),'') = '' then
    raise exception 'fn_phase_c_event_ingress: a business object id is required' using errcode = '23502';
  end if;

  -- Default true: called as the PRODUCER (a real business event arriving), the durable record is
  -- the whole point. Called by the delivery worker, the record already exists — that row is the
  -- one being delivered — and emitting again feeds the queue its own output.
  v_emit := coalesce((p_ctx->>'emit')::boolean, true);

  v_input_hash := encode(sha256(convert_to(
    p_event_id || '|' || p_business_object_id || '|' || coalesce(p_ctx::text,'{}'), 'UTF8')), 'hex');

  v_run := public.fn_phase_c_workflow_start(e.workflow_id, p_business_object_id,
             p_ctx || jsonb_build_object('start_event', p_event_id));
  select trace_id into v_run_trace from public.phase_c_workflow_run where run_id = v_run;

  v_step := public.fn_phase_c_entry_step(e.workflow_id);
  if v_step is null then
    raise exception 'fn_phase_c_event_ingress: workflow % declares no entry step', e.workflow_id
      using errcode = '23502';
  end if;
  select * into s from public.phase_b_workflow_step where step_id = v_step;

  select role_id into v_owner from public.fn_phase_c_resolve_actor(s.accountable_role_id);
  if v_owner is null or not public.fn_phase_c_actor_may_own(v_owner) then
    raise exception 'fn_phase_c_event_ingress: step % owner % does not resolve to an active canonical role',
      v_step, s.accountable_role_id using errcode = '23514';
  end if;

  select step_run_id into v_step_run from public.phase_c_workflow_step_run
   where run_id = v_run and step_id = v_step and state = 'active';
  if v_step_run is null then
    insert into public.phase_c_workflow_step_run
      (run_id, step_id, accountable_role_id, reviewer_role_id, state, attempt_no,
       input_hash, output_hash, gates_evaluated, authority_result, idempotency_key)
    values (v_run, v_step, v_owner, coalesce(s.independent_reviewer_role_id,''), 'active', 1,
            v_input_hash, '', '[]'::jsonb, 'pending: the step has not been executed yet',
            s.idempotency_scope || '|' || v_run || '|' || v_step || '|ingress')
    on conflict (idempotency_key) do nothing
    returning step_run_id into v_step_run;
    if v_step_run is null then
      select step_run_id into v_step_run from public.phase_c_workflow_step_run
       where idempotency_key = s.idempotency_scope || '|' || v_run || '|' || v_step || '|ingress';
    end if;
  end if;

  v_task := public.fn_phase_c_task_create(jsonb_build_object(
    'source_kind','workflow_event', 'source_ref', p_event_id || ':' || p_business_object_id,
    'run_id', v_run, 'workflow_id', e.workflow_id, 'step_id', v_step,
    'accountable_role_id', v_owner,
    'objective', format('%s: perform %s for %s.', e.event_name, v_step, p_business_object_id),
    'required_inputs', coalesce(p_ctx->>'required_inputs',''),
    'requested_output', 'The step output required by the frozen Phase B contract, with evidence.',
    'reviewer_required', (coalesce(s.independent_reviewer_role_id,'') <> ''),
    'reviewer_role_id', coalesce(s.independent_reviewer_role_id,''),
    'idempotency_key', 'run:' || v_run || ':step:' || v_step));
  select trace_id into v_task_trace from public.phase_c_task where task_id = v_task;

  if v_emit then
    v_outbox := public.fn_phase_c_outbox_emit(
      p_event_id, coalesce(p_ctx->>'producer', e.emitted_by),
      jsonb_build_object('run_id', v_run, 'step_id', v_step, 'task_id', v_task,
                         'business_object_id', p_business_object_id,
                         'workflow_id', e.workflow_id, 'input_hash', v_input_hash),
      'ingress:' || p_event_id || ':' || p_business_object_id);
    update public.phase_c_event_outbox set trace_id = v_run_trace
      where outbox_id = v_outbox and trace_id is null;
  else
    v_outbox := (p_ctx->>'outbox_id')::bigint;   -- the row being delivered IS the durable record
  end if;

  if v_run is null or v_step_run is null or v_task is null or v_outbox is null
     or v_run_trace is null or v_task_trace is null then
    raise exception 'fn_phase_c_event_ingress incomplete: run=% step_run=% task=% outbox=% run_trace=% task_trace=%',
      v_run, v_step_run, v_task, v_outbox, v_run_trace, v_task_trace using errcode = '23502';
  end if;

  return jsonb_build_object(
    'ok', true, 'event_id', p_event_id, 'workflow_id', e.workflow_id,
    'business_object_id', p_business_object_id, 'run_id', v_run, 'step_id', v_step,
    'step_run_id', v_step_run, 'accountable_role_id', v_owner, 'task_id', v_task,
    'outbox_id', v_outbox, 'run_trace_id', v_run_trace, 'task_trace_id', v_task_trace,
    'input_hash', v_input_hash, 'emitted', v_emit);
end $$;
revoke all on function public.fn_phase_c_event_ingress(text, text, jsonb) from public;
grant execute on function public.fn_phase_c_event_ingress(text, text, jsonb) to service_role;

-- ================================================================ 2. the consumer says so
create or replace function public.fn_phase_c_event_consume(p_outbox_id bigint)
returns table (handled boolean, downstream_ref text, result jsonb, reason text)
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  o public.phase_c_event_outbox%rowtype;
  e public.phase_b_event%rowtype;
  v_ing jsonb; v_next record; v_tasks bigint[] := '{}'; v_task bigint;
  v_owner text; v_run bigint; v_step text;
begin
  select * into o from public.phase_c_event_outbox where outbox_id = p_outbox_id;
  if not found then
    return query select false, null::text, null::jsonb, 'unknown_outbox_row'; return;
  end if;
  select * into e from public.phase_b_event where event_id = o.event_id;
  if not found then
    return query select false, null::text, null::jsonb,
      format('%s is not in the frozen Phase B event registry', o.event_id); return;
  end if;

  -- A row whose payload names a command must be for a workflow that command actually selected.
  -- Three pre-fix rows announcing EV-W01-STARTED for W20 commands were delivered before the
  -- quarantine reached them and put three marketing orders in front of the CEO. Refused here as
  -- well, so the order of two migrations can never decide that again.
  if o.payload ? 'command_id'
     and not exists (select 1 from public.founder_command_workflow_link l
                     where l.command_id = (o.payload->>'command_id')::bigint
                       and l.workflow_id = o.workflow_id) then
    return query select false, null::text, null::jsonb,
      format('event %s names workflow %s but command %s selected a different workflow',
             o.event_id, o.workflow_id, o.payload->>'command_id'); return;
  end if;

  if e.event_name like '%.started' then
    v_ing := public.fn_phase_c_event_ingress(
      o.event_id,
      coalesce(o.payload->>'business_object_id', 'outbox:' || o.outbox_id::text),
      jsonb_build_object('source','outbox_delivery', 'producer', o.producer,
                         'command_id', o.payload->>'command_id',
                         'outbox_id', o.outbox_id,
                         -- the durable record already exists: it is the row being delivered
                         'emit', false));
    if v_ing is null or coalesce((v_ing->>'ok')::boolean, false) is not true then
      return query select false, null::text, v_ing, 'ingress_did_not_confirm'; return;
    end if;
    return query select true, 'task:' || (v_ing->>'task_id'), v_ing, null::text; return;
  end if;

  if e.event_name like '%.completed' and o.payload ? 'step_id' then
    v_run  := (o.payload->>'run_id')::bigint;
    v_step := o.payload->>'step_id';
    if v_run is null then
      return query select false, null::text, null::jsonb, 'completed event carries no run_id'; return;
    end if;
    for v_next in
      select h.to_step_id, s.accountable_role_id, s.independent_reviewer_role_id, s.idempotency_scope
        from public.phase_b_handoff h
        join public.phase_b_workflow_step s on s.step_id = h.to_step_id
       where h.from_step_id = v_step
       order by h.to_step_id
    loop
      select role_id into v_owner from public.fn_phase_c_resolve_actor(v_next.accountable_role_id);
      continue when v_owner is null or not public.fn_phase_c_actor_may_own(v_owner);
      v_task := public.fn_phase_c_task_create(jsonb_build_object(
        'source_kind','workflow_event', 'source_ref', o.event_id || ':' || v_next.to_step_id,
        'run_id', v_run, 'workflow_id', e.workflow_id, 'step_id', v_next.to_step_id,
        'accountable_role_id', v_owner,
        'objective', format('%s completed; %s is now yours for run %s.',
                            v_step, v_next.to_step_id, v_run),
        'requested_output','The step output required by the frozen Phase B contract, with evidence.',
        'reviewer_required', (coalesce(v_next.independent_reviewer_role_id,'') <> ''),
        'reviewer_role_id', coalesce(v_next.independent_reviewer_role_id,''),
        'idempotency_key', 'run:' || v_run || ':step:' || v_next.to_step_id));
      v_tasks := v_tasks || v_task;
    end loop;
    if cardinality(v_tasks) = 0 then
      return query select true, 'terminal_step:' || v_step,
        jsonb_build_object('successors', 0, 'run_id', v_run), null::text; return;
    end if;
    return query select true, 'tasks:' || array_to_string(v_tasks, ','),
      jsonb_build_object('tasks', to_jsonb(v_tasks), 'run_id', v_run), null::text; return;
  end if;

  return query select false, null::text, null::jsonb,
    format('no canonical consumer for %s (%s)', o.event_id, e.event_name);
end $$;
revoke all on function public.fn_phase_c_event_consume(bigint) from public;
grant execute on function public.fn_phase_c_event_consume(bigint) to service_role;

-- ================================================================ 3. roll the increment back
do $rollback$
declare r record; n_tasks int := 0; n_runs int := 0; n_box int := 0;
begin
  -- the three W01 runs the mis-addressed events produced, and their tasks. Cancelled with the
  -- reason on the row, not deleted: what the worker did is the evidence for why the order of two
  -- migrations mattered.
  for r in select t.task_id from public.phase_c_task t
            join public.phase_c_workflow_run w on w.run_id = t.run_id
           where w.workflow_id = 'W01' and w.business_object_id like 'outbox:%'
             and t.state not in ('cancelled','completed','failed') loop
    update public.phase_c_task set state = 'cancelled', closed_at = now() where task_id = r.task_id;
    n_tasks := n_tasks + 1;
  end loop;

  update public.phase_c_workflow_run
     set state = 'cancelled', closed_at = now(),
         closure_evidence = jsonb_build_object(
           'rolled_back', true, 'at', now(),
           'reason', 'Created 2026-08-16 10:28 by the delivery worker consuming three pre-fix '
                     'outbox rows that carried EV-W01-STARTED for W20 marketing commands. The '
                     'events were wrong, so this run should never have opened. Cancelled, not '
                     'deleted.')
   where workflow_id = 'W01' and business_object_id like 'outbox:%' and state <> 'cancelled';
  get diagnostics n_runs = row_count;

  -- every outbox row that named a workflow its command had not selected, delivered or not
  update public.phase_c_event_outbox o
     set status = 'superseded',
         last_error = 'SUPERSEDED 2026-08-16: emitted as ' || o.event_id || ' / workflow '
                      || o.workflow_id || ' by the hard-coded literal in fn_founder_command_submit '
                      || 'while its command had selected another workflow. '
                      || case when o.status = 'delivered'
                              then 'It WAS delivered at 10:28 before the quarantine reached it; the '
                                   || 'run and tasks it created have been cancelled. '
                              else '' end
                      || 'Retained as the evidence for that finding.'
   where o.payload ? 'command_id'
     and not exists (select 1 from public.founder_command_workflow_link l
                     where l.command_id = (o.payload->>'command_id')::bigint
                       and l.workflow_id = o.workflow_id);
  get diagnostics n_box = row_count;

  -- and the three rows the ingress re-emitted back into its own queue
  update public.phase_c_event_outbox
     set status = 'superseded',
         last_error = 'SUPERSEDED 2026-08-16: written by fn_phase_c_event_ingress while it was '
                      'being called BY the delivery worker, so the queue emitted its own output. '
                      'Fixed in phase_c_39: the consumer passes emit=false. Retained as evidence.'
   where dedupe_value like 'ingress:EV-W01-STARTED:outbox:%';

  raise notice 'rollback: % task(s), % run(s), % outbox row(s) superseded', n_tasks, n_runs, n_box;
end $rollback$;
