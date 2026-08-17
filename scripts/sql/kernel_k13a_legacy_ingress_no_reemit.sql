-- ============================================================================================
-- KERNEL K13a — THE LEGACY INGRESS STOPS RE-EMITTING ITS OWN INPUT
--
-- scripts/sql/phase_c_39_consumer_must_not_reemit.sql carried this fix and it never reached
-- production: phase_c_31 and phase_c_39 both define fn_phase_c_event_ingress and landed in the
-- same commit, so sql_files_match_live resolved the tie to phase_c_31 and certified the UNFIXED
-- body at 0 drift. K1 made that visible; this file closes it.
--
-- The kernel does not need this routine - cron 278 now calls fn_kernel_outbox_deliver, whose
-- consumer never calls a producer, and fn_kernel_workflow_start is the only creator of business
-- work. This file exists so the LEGACY path cannot re-emit either, for as long as it is still
-- deployed. Retiring it entirely is the rest of K13.
--
-- Body taken verbatim from phase_c_39, which is what the manifest names as canonical. Applying it
-- makes the repository and production agree about what this routine IS, which is the thing the
-- parity gate is for.
-- ============================================================================================
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
