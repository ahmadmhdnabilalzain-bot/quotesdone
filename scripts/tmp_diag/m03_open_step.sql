CREATE OR REPLACE FUNCTION public.fn_kernel_open_step(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_pd_dispatch jsonb := '{}'::jsonb;  -- D36
  s public.phase_b_workflow_step%rowtype;
  v_run       bigint := nullif(p_input->>'run_id','')::bigint;
  v_step      text   := nullif(btrim(coalesce(p_input->>'step_id','')), '');
  v_owner     text   := nullif(btrim(coalesce(p_input->>'owner_role_id','')), '');
  v_src_kind  text   := coalesce(nullif(p_input->>'source_kind',''), 'workflow_progression');
  v_src_ref   text   := coalesce(nullif(p_input->>'source_ref',''), 'kernel:step_engine');
  v_command   bigint := nullif(p_input->>'command_id','')::bigint;
  v_priority  text   := coalesce(nullif(p_input->>'priority',''), 'P2');
  v_object    text   := coalesce(nullif(p_input->>'business_object_id',''), '');
  v_in_hash   text   := coalesce(nullif(p_input->>'input_hash',''), '');
  v_reason    text   := coalesce(nullif(p_input->>'opened_because',''), '(no reason stated)');
  v_step_run  bigint;
  v_task      bigint;
  v_st_trace  bigint;
  v_tk_trace  bigint;
  v_tk_parent bigint;
  v_wf        text;
  v_idem      text;
begin
  if v_run is null or v_step is null or v_owner is null then
    raise exception 'fn_kernel_open_step: run_id, step_id and owner_role_id are all required (got %, %, %)',
      coalesce(v_run::text,'(null)'), coalesce(v_step,'(null)'), coalesce(v_owner,'(null)')
      using errcode = '22023';
  end if;

  select * into s from public.phase_b_workflow_step where step_id = v_step;
  if not found then
    raise exception 'fn_kernel_open_step: % is not in the frozen Phase B step registry — fail closed',
      v_step using errcode = '23503';
  end if;
  select workflow_id into v_wf from public.phase_c_workflow_run where run_id = v_run;
  if v_wf is null then
    raise exception 'fn_kernel_open_step: no workflow run %', v_run using errcode = '23503';
  end if;
  if v_wf is distinct from s.workflow_id then
    raise exception 'fn_kernel_open_step: run % is workflow % and step % belongs to % — refused',
      v_run, v_wf, v_step, s.workflow_id using errcode = '23514';
  end if;
  -- Owners are never defaulted. A step whose owner does not resolve is not opened.
  if not public.fn_phase_c_actor_may_own(v_owner) then
    raise exception 'fn_kernel_open_step: % does not resolve to an active canonical role, so step % is not opened',
      v_owner, v_step using errcode = '23514';
  end if;

  -- phase_c_step_run_live_uk is UNIQUE (run_id, step_id) WHERE state is not terminal, so a second
  -- live step run for the same step is refused by the index. Report it as the specific thing it is.
  if exists (select 1 from public.phase_c_workflow_step_run r
              where r.run_id = v_run and r.step_id = v_step
                and r.state not in ('completed','cancelled','failed','superseded','skipped')) then
    raise exception 'fn_kernel_open_step: run % already has a live step run for % — a second one would be a duplicate of work in flight',
      v_run, v_step using errcode = '23505';
  end if;

  v_idem := s.idempotency_scope || '|' || v_run || '|' || v_step || '|kernel';

  -- No trace_id on the insert: z90_phase_c_step_run_trace_subject mints TRACE-STEP AFTER INSERT
  -- and parents it to the run's root trace.
  insert into public.phase_c_workflow_step_run
    (run_id, step_id, accountable_role_id, reviewer_role_id, state, attempt_no,
     input_hash, output_hash, gates_evaluated, authority_result, idempotency_key)
  values (v_run, v_step, v_owner, coalesce(s.independent_reviewer_role_id,''), 'active', 1,
          v_in_hash, '', '[]'::jsonb, 'pending: the step has not been executed yet', v_idem)
  returning step_run_id into v_step_run;
  if v_step_run is null then
    raise exception 'fn_kernel_open_step: the step run insert produced no row for %', v_step
      using errcode = '23502';
  end if;

  select trace_id into v_st_trace from public.phase_c_workflow_step_run where step_run_id = v_step_run;
  if v_st_trace is null then
    raise exception 'fn_kernel_open_step: step run % has no trace', v_step_run using errcode = '23502';
  end if;

  -- EXACTLY ONE task, on the same deterministic key fn_kernel_workflow_start uses. That key is
  -- also what makes the legacy delivery fan-out a no-op rather than a duplicate.
  v_task := public.fn_phase_c_task_create(jsonb_build_object(
    'source_kind', v_src_kind, 'source_ref', v_src_ref,
    'command_id', v_command, 'run_id', v_run, 'workflow_id', s.workflow_id, 'step_id', v_step,
    'accountable_role_id', v_owner,
    'objective', format('%s (%s) for %s — opened because %s',
                        s.step_id, s.step_name, coalesce(nullif(v_object,''),'this run'), v_reason),
    'required_inputs', s.required_inputs,
    'requested_output', s.required_output,
    'acceptance_criteria', s.acceptance_criteria,
    'closure_criteria', s.closure_criteria,
    'priority', v_priority,
    'reviewer_required', (coalesce(s.independent_reviewer_role_id,'') <> ''),
    'reviewer_role_id', coalesce(s.independent_reviewer_role_id,''),
    'idempotency_key', 'run:' || v_run || ':step:' || v_step));
  if v_task is null then
    raise exception 'fn_kernel_open_step: no task was created for run % step %', v_run, v_step
      using errcode = '23502';
  end if;

  select trace_id into v_tk_trace from public.phase_c_task where task_id = v_task;
  select parent_trace_id into v_tk_parent from public.phase_c_trace where trace_id = v_tk_trace;
  if v_tk_trace is null or v_tk_parent is null then
    raise exception 'fn_kernel_open_step: task % has trace % with parent % — a task without its parented trace is refused',
      v_task, coalesce(v_tk_trace::text,'null'), coalesce(v_tk_parent::text,'null')
      using errcode = '23502';
  end if;

  -- ---- PHASE D DISPATCH (D36) ------------------------------------------------------------------
  -- The step is open, owned, tasked and traced. If the frozen registry binds a deterministic Phase D
  -- handler to it, this is where that handler runs — not in a harness, and not behind an endpoint
  -- nothing calls. fn_phase_d_dispatch_step never raises: a refusal is recorded in
  -- public.phase_d_dispatch, because a handler refusing five frames down must not roll back the
  -- business write that caused the step to open.
  v_pd_dispatch := public.fn_phase_d_dispatch_step(jsonb_build_object(
    'step_run_id', v_step_run, 'actor_role_id', v_owner,
    'opened_by_kind', v_src_kind, 'opened_by_ref', v_src_ref,
    'idempotency_key', v_idem, 'correlation_id', p_input->>'correlation_id'));

  return jsonb_build_object('step_run_id', v_step_run, 'task_id', v_task, 'step_id', v_step,
    'owner_role_id', v_owner, 'step_trace_id', v_st_trace, 'task_trace_id', v_tk_trace,
    'reviewer_required', (coalesce(s.independent_reviewer_role_id,'') <> ''),
    'reviewer_role_id', coalesce(s.independent_reviewer_role_id,''),
    'idempotency_key', v_idem);
end $function$
