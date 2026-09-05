-- THE SIGNAL INTAKE LOSES ITS RC4 NO-OP BLOCK (6 Sep 2026, MASTER_PLAN §5.2 cleanups).
--
-- fn_kernel_signal_submit carried an `if v_run_trace is not null then perform 1; end if;` left from
-- release-candidate 4, when the parent trace used to be set here. It did nothing and read as if it
-- might. Removed; the comment that explained it stays as one line. Every other line is the live
-- definition.
--
--   node scripts/apply_sql.mjs scripts/sql/the_signal_intake_loses_its_rc4_block.sql --apply --ddl
CREATE OR REPLACE FUNCTION public.fn_kernel_signal_submit(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_src_type  text   := nullif(btrim(coalesce(p_input->>'source_type','')), '');
  v_src_id    text   := nullif(btrim(coalesce(p_input->>'source_id','')), '');
  v_run       bigint := nullif(p_input->>'workflow_run_id','')::bigint;
  v_sig       text   := nullif(btrim(coalesce(p_input->>'signal_type','')), '');
  v_payload   jsonb  := coalesce(p_input->'payload', '{}'::jsonb);
  v_by        text   := nullif(btrim(coalesce(p_input->>'requested_by','')), '');
  v_idem      text;
  v_corr      text;
  v_caus      text;
  v_id        bigint;
  -- Scalars, never a RECORD read outside the branch that filled it.
  v_prior_id     bigint;
  v_prior_status text;
  v_prior_result jsonb;
  v_disp      text;
  v_sig_wf    text;
  v_sig_act   text;
  v_sig_sys   text;
  v_run_wf    text;
  v_run_state text;
  v_run_obj   text;
  v_run_trace bigint;
  v_step_run  bigint;
  v_step_id   text;
  v_step_owner text;
  v_task      bigint;
  v_trace     bigint;
  v_out       jsonb;
  v_refuse    text;
begin
  -- ---- 0. a delivery worker may never drive the request side -------------------------------
  perform public.fn_kernel_assert_not_in_delivery('fn_kernel_signal_submit');

  -- ---- 1. envelope. Nothing recordable in a malformed one -----------------------------------
  if v_src_type is null or v_src_id is null or v_sig is null or v_by is null then
    raise exception 'fn_kernel_signal_submit: source_type, source_id, signal_type and requested_by are all required (got %, %, %, %)',
      coalesce(v_src_type,'(null)'), coalesce(v_src_id,'(null)'), coalesce(v_sig,'(null)'),
      coalesce(v_by,'(null)') using errcode = '22023';
  end if;
  if jsonb_typeof(v_payload) <> 'object' then
    raise exception 'fn_kernel_signal_submit: payload must be a json object, got %',
      jsonb_typeof(v_payload) using errcode = '22023';
  end if;

  -- The key is the external identity of the signal. Defaulted from the source's own reference and
  -- the run it is about — never from now() or a sequence, because a key that differs every time
  -- is not a key and would let one webhook retry apply twice.
  v_idem := coalesce(nullif(btrim(p_input->>'idempotency_key'),''),
                     v_src_type || ':' || v_src_id || ':' || v_sig || ':' || coalesce(v_run::text,'-'));
  v_corr := coalesce(nullif(btrim(p_input->>'correlation_id'),''), 'signal:' || v_idem);
  v_caus := coalesce(nullif(btrim(p_input->>'causation_id'),''), v_src_type || ':' || v_src_id);

  -- ---- 2. idempotency, before anything is resolved and before anything happens --------------
  select s.signal_id, s.status, s.result into v_prior_id, v_prior_status, v_prior_result
    from public.kernel_signal_inbox s where s.idempotency_key = v_idem;
  if v_prior_id is not null then
    return jsonb_build_object('ok', v_prior_status <> 'refused', 'duplicate', true,
      'signal_id', v_prior_id, 'status', v_prior_status, 'result', v_prior_result,
      'reason', 'this signal has already been delivered; the first decision is the answer');
  end if;

  insert into public.kernel_signal_inbox
    (source_type, source_id, workflow_run_id, signal_type, payload, idempotency_key,
     correlation_id, causation_id, requested_by)
  values (v_src_type, v_src_id, v_run, v_sig, v_payload, v_idem, v_corr, v_caus, v_by)
  returning signal_id into v_id;

  -- ---- 3. the signal type must be registered and active ------------------------------------
  select t.disposition, t.workflow_id, t.activation_state, t.system_actor_id
    into v_disp, v_sig_wf, v_sig_act, v_sig_sys
    from public.kernel_signal_type t where t.signal_type = v_sig;
  if v_disp is null then
    v_refuse := format('signal type %L is not registered. A signal the kernel has never heard of '
                    || 'is not routed on a guess.', v_sig);
  elsif v_sig_act <> 'active' then
    v_refuse := format('signal type %L is registered with activation_state %L and does not accept '
                    || 'submissions.', v_sig, v_sig_act);
  end if;

  -- ---- 4. the run must exist, and must still be running -------------------------------------
  if v_refuse is null then
    if v_run is null then
      v_refuse := 'a signal about an existing workflow must name workflow_run_id. There is no '
               || 'lookup by business object here on purpose: guessing which run a signal belongs '
               || 'to is how one arrival lands on two runs.';
    else
      select r.workflow_id, r.state, r.business_object_id, r.trace_id
        into v_run_wf, v_run_state, v_run_obj, v_run_trace
        from public.phase_c_workflow_run r where r.run_id = v_run for update;
      if v_run_wf is null then
        v_refuse := format('workflow run %s does not exist.', v_run);
      elsif exists (select 1 from public.phase_b_workflow_state ws
                     where ws.state = v_run_state and ws.terminal) then
        v_refuse := format('workflow run %s is in terminal state %L. A closed run does not accept '
                        || 'signals; if this is new work it must come through '
                        || 'fn_kernel_trigger_submit and be judged on its own.', v_run, v_run_state);
      elsif v_sig_wf is not null and v_sig_wf is distinct from v_run_wf then
        v_refuse := format('signal type %L is declared for workflow %L and run %s is %L.',
                           v_sig, v_sig_wf, v_run, v_run_wf);
      end if;
    end if;
  end if;

  if v_refuse is not null then
    update public.kernel_signal_inbox
       set status = 'refused', refusal_reason = v_refuse, processed_at = now()
     where signal_id = v_id;
    return jsonb_build_object('ok', false, 'duplicate', false, 'signal_id', v_id,
      'status','refused', 'reason', v_refuse);
  end if;

  -- ---- 5. the signal is attached to the run it names, always --------------------------------
  -- Even a signal whose disposition changes nothing leaves a trace parented to the run's trace, so
  -- "we were told and did nothing" and "we were never told" can never be confused later.
  v_trace := public.fn_kernel_intake_execution('dbfn:fn_kernel_signal_submit(jsonb)', jsonb_build_object(
    'subject_kind','system_execution', 'subject_ref', 'signal:' || v_id::text, 'run_id', v_run,
    'actor_role_id', null, 'system_actor_id', v_sig_sys,
    'evidence_refs', jsonb_build_array(jsonb_build_object(
      'signal_id', v_id, 'signal_type', v_sig, 'disposition', v_disp,
      'source_type', v_src_type, 'source_id', v_src_id, 'idempotency_key', v_idem)),
    'state_before', v_run_state, 'state_after', v_run_state, 'status','complete'));
  update public.kernel_signal_inbox set trace_id = v_trace where signal_id = v_id;
  -- parent_trace_id is set by fn_kernel_intake_execution before the trace is sealed; a sealed trace
  -- is never edited here (fn_phase_c_trace_append_only refuses it). The rc4 no-op block that said
  -- this in an empty `if` was removed 6 Sep 2026 (MASTER_PLAN §5.2 cleanups).


  -- The run's currently active step, if it has one. Read once, used by three dispositions.
  select sr.step_run_id, sr.step_id, sr.accountable_role_id
    into v_step_run, v_step_id, v_step_owner
    from public.phase_c_workflow_step_run sr
   where sr.run_id = v_run and sr.state = 'active'
   order by sr.step_run_id limit 1;

  -- ---- 6. the declared disposition, and only that -------------------------------------------
  if v_disp = 'ATTACH_ONLY' then
    update public.kernel_signal_inbox
       set status = 'attached', step_run_id = v_step_run, processed_at = now(),
           result = jsonb_build_object('attached_to_run', v_run, 'active_step', v_step_id)
     where signal_id = v_id;
    return jsonb_build_object('ok', true, 'duplicate', false, 'signal_id', v_id,
      'status','attached', 'workflow_run_id', v_run, 'workflow_id', v_run_wf,
      'active_step_id', v_step_id, 'trace_id', v_trace, 'created_workflow_runs', 0);

  elsif v_disp = 'COMPLETE_STEP' then
    if v_step_run is null then
      v_refuse := format('run %s has no active step, so there is nothing for a COMPLETE_STEP '
                      || 'signal to complete.', v_run);
    elsif coalesce(jsonb_typeof(v_payload->'output'),'') <> 'object'
       or v_payload->'output' = '{}'::jsonb then
      v_refuse := format('signal type %L completes step %s and the payload carries no output '
                      || 'object. An output is what the step contract asks for; it is not '
                      || 'defaulted here, because a fabricated output certifies work nobody did.',
                         v_sig, v_step_id);
    end if;
    if v_refuse is not null then
      update public.kernel_signal_inbox
         set status = 'refused', refusal_reason = v_refuse, step_run_id = v_step_run,
             processed_at = now()
       where signal_id = v_id;
      return jsonb_build_object('ok', false, 'duplicate', false, 'signal_id', v_id,
        'status','refused', 'reason', v_refuse);
    end if;
    v_out := public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id',     v_step_run,
      'actor_role_id',   v_step_owner,
      'outcome',         coalesce(nullif(btrim(v_payload->>'outcome'),''), 'pass'),
      'idempotency_key', 'signal:' || v_idem,
      'reason',          coalesce(nullif(btrim(v_payload->>'reason'),''),
                                  'signal ' || v_sig || ' from ' || v_src_type || ':' || v_src_id),
      'inputs',          coalesce(v_payload->'inputs',
                                  jsonb_build_object('signal_id', v_id, 'signal_type', v_sig,
                                                     'source', v_src_type || ':' || v_src_id)),
      'output',          v_payload->'output',
      'evidence_ref',    'signal:' || v_id::text,
      'correlation_id',  v_corr, 'causation_id', v_caus));

  elsif v_disp = 'REVIEW_VERDICT' then
    select t.task_id into v_task from public.phase_c_task t
     where t.run_id = v_run and t.step_id = v_step_id order by t.task_id desc limit 1;
    if v_task is null or coalesce(btrim(v_payload->>'decision'),'') = '' then
      v_refuse := format('a REVIEW_VERDICT signal needs a task on the active step and a decision '
                      || 'in the payload (task %s, decision %L).',
                         coalesce(v_task::text,'none'), coalesce(v_payload->>'decision','(none)'));
      update public.kernel_signal_inbox
         set status = 'refused', refusal_reason = v_refuse, step_run_id = v_step_run,
             processed_at = now()
       where signal_id = v_id;
      return jsonb_build_object('ok', false, 'duplicate', false, 'signal_id', v_id,
        'status','refused', 'reason', v_refuse);
    end if;
    v_out := public.fn_kernel_review_decide(jsonb_build_object(
      'task_id',          v_task,
      'reviewer_role_id', v_payload->>'reviewer_role_id',
      'decision',         v_payload->>'decision',
      'reason',           coalesce(nullif(btrim(v_payload->>'reason'),''),
                                   'recorded from signal ' || v_id::text)));

  elsif v_disp = 'CANCEL' then
    v_out := public.fn_kernel_cancel(jsonb_build_object(
      'subject_kind', 'workflow_run',
      'subject_ref',  v_run::text,
      'op',           'cancel',
      'reason',       coalesce(nullif(btrim(v_payload->>'reason'),''),
                               'cancelled by signal ' || v_sig || ' from ' || v_src_type || ':' || v_src_id),
      'actor',        v_by));
  end if;

  update public.kernel_signal_inbox
     set status = 'applied', step_run_id = v_step_run, processed_at = now(), result = v_out
   where signal_id = v_id;

  return jsonb_build_object('ok', coalesce((v_out->>'ok')::boolean, true), 'duplicate', false,
    'signal_id', v_id, 'status','applied', 'disposition', v_disp,
    'workflow_run_id', v_run, 'workflow_id', v_run_wf, 'step_id', v_step_id,
    'trace_id', v_trace, 'created_workflow_runs', 0, 'result', v_out);
end
$function$
