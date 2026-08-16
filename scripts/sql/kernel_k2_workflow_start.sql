-- ============================================================================================
-- KERNEL K2 — fn_kernel_workflow_start: THE ONE AUTHORITATIVE CREATOR OF BUSINESS WORK
--
-- APPLY ORDER: scripts/sql/kernel_k5_factual_outbox.sql FIRST, THEN THIS FILE.
-- K2 emits through fn_kernel_outbox_emit, reads fn_kernel_assert_not_in_delivery and dates its
-- handoff with fn_kernel_sla_due — all three are created by K5.
-- Then, when the lead is ready to move the founder path over:
--   scripts/sql/kernel_k2b_founder_submit_calls_kernel.sql
--
-- WHAT THIS REPLACES, AND WHY
--
-- fn_phase_c_workflow_start creates a run and nothing else, and has exactly one caller:
-- fn_phase_c_event_ingress, which is itself only reachable from fn_kernel_event_consume /
-- fn_phase_c_event_consume — that is, FROM EVENT DELIVERY.  So the sequence in production is:
--
--     fn_founder_command_submit  ->  emits EV-Wnn-STARTED   (a COMMAND wearing an event's name)
--     cron 278 -> deliver -> consume -> ingress -> creates the run, the step run, the task
--                                              -> AND EMITS EV-Wnn-STARTED AGAIN
--
-- Outbox 250, 251 and 317 are that second generation.  Dedupe never caught it because the ingress
-- writes a different dedupe_value than the router did.  An event is not an instruction.
--
-- In the kernel the order is inverted and made atomic: the RUN, the STEP RUN, the TASK, the two
-- TRACES and the HANDOFF are created first, in one transaction, and the event is emitted last as a
-- RECORD OF WHAT WAS DONE.  fn_kernel_event_consume may then notify, project or fan out; it may
-- not call back in.  That refusal is enforced, not documented: the first statement of this
-- function asks K5 whether the transaction is inside delivery and raises 23514 if it is.
--
-- WHAT IT WILL NOT DO
--   * It will not default the accountable role.  phase_b_workflow.accountable_role_id is resolved
--     through fn_phase_c_resolve_actor and must come back canonical and active.  There is no
--     chief_of_staff fallback: a workflow whose owner does not resolve does not start.
--   * It will not guess the entry step.  fn_phase_c_entry_step returns min(step_id) over steps
--     with no incoming handoff edge; that agrees with the registry today only by the coincidence
--     that 'S01' < 'S02' lexically, and for W09 all nine steps qualify.  The registry states the
--     order in phase_b_workflow_step.step_no, UNIQUE per workflow — this reads step_no = 1.
--   * It will not create a task without its trace, or a run without its root trace: every one of
--     a-f below is asserted before the function returns, each with its own errcode and a message
--     naming which one is missing.
--
-- INPUT (p_input jsonb)
--   workflow_id         text     required, must exist in phase_b_workflow
--   business_object_id  text     required, the thing the work is about
--   source_kind         text     required, 'founder_command' | 'autonomous'
--   source_ref          text     required, the record that caused this (e.g. 'founder_command:227')
--   command_id          bigint   nullable, set iff source_kind = 'founder_command'
--   correlation_id      text     optional, defaults to source_ref — stable for the causal chain
--   causation_id        text     optional, defaults to source_ref — the immediate cause
--   trigger_ctx         jsonb    optional, the evidence that the trigger condition held
--   requested_by        text     required, who or what asked
--   object_version      bigint   optional, default 1 — part of the idempotency key
--   priority            text     optional, default P2
--
-- IDEMPOTENT on (workflow_id, business_object_id, object_version): a second call returns the SAME
-- run id with duplicate:true and creates nothing.  The dedupe_key format is unchanged from
-- fn_phase_c_workflow_start ('W20:outbox:245:1'), so the eight existing runs keep deduplicating.
-- ============================================================================================

create or replace function public.fn_kernel_workflow_start(p_input jsonb)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare
  w  public.phase_b_workflow%rowtype;
  s  public.phase_b_workflow_step%rowtype;
  h  public.phase_b_handoff%rowtype;
  v_wf        text   := nullif(btrim(coalesce(p_input->>'workflow_id','')), '');
  v_object    text   := nullif(btrim(coalesce(p_input->>'business_object_id','')), '');
  v_source_k  text   := nullif(btrim(coalesce(p_input->>'source_kind','')), '');
  v_source_r  text   := nullif(btrim(coalesce(p_input->>'source_ref','')), '');
  v_by        text   := nullif(btrim(coalesce(p_input->>'requested_by','')), '');
  v_command   bigint := nullif(p_input->>'command_id','')::bigint;
  v_version   bigint := coalesce(nullif(p_input->>'object_version','')::bigint, 1);
  v_priority  text   := coalesce(nullif(p_input->>'priority',''), 'P2');
  v_ctx       jsonb  := coalesce(p_input->'trigger_ctx', '{}'::jsonb);
  v_corr      text;
  v_caus      text;
  v_dedupe    text;
  v_run       bigint;
  v_step_run  bigint;
  v_task      bigint;
  v_handoff   bigint;
  v_outbox    bigint;
  v_run_trace bigint;
  v_step_trace bigint;
  v_task_trace bigint;
  v_task_parent bigint;
  v_ho_trace  bigint;
  v_owner     text;
  v_step_owner text;
  v_kind      text;
  v_start_event text;
  v_input_hash text;
  -- Scalars, not a RECORD: a plpgsql record read after a SELECT INTO that matched nothing is a
  -- trap this estate has already paid for once.
  v_prior_run   bigint;
  v_prior_state text;
  v_prior_trace bigint;
  v_prior_step  bigint;
  v_prior_task  bigint;
begin
  -- ---- 0. a consumer may not re-enter the producer ----------------------------------------
  perform public.fn_kernel_assert_not_in_delivery('fn_kernel_workflow_start');

  if v_wf is null or v_object is null or v_source_r is null or v_by is null then
    raise exception 'fn_kernel_workflow_start: workflow_id, business_object_id, source_ref and requested_by are all required (got %, %, %, %)',
      coalesce(v_wf,'(null)'), coalesce(v_object,'(null)'), coalesce(v_source_r,'(null)'), coalesce(v_by,'(null)')
      using errcode = '22023';
  end if;
  if v_source_k not in ('founder_command','autonomous') then
    raise exception 'fn_kernel_workflow_start: source_kind must be founder_command or autonomous, got %',
      coalesce(v_source_k,'(null)') using errcode = '22023';
  end if;
  if v_source_k = 'founder_command' and v_command is null then
    raise exception 'fn_kernel_workflow_start: source_kind founder_command requires a command_id'
      using errcode = '22023';
  end if;
  v_corr := coalesce(nullif(btrim(p_input->>'correlation_id'),''), v_source_r);
  v_caus := coalesce(nullif(btrim(p_input->>'causation_id'),''), v_source_r);

  -- ---- (a) the workflow run ---------------------------------------------------------------
  select * into w from public.phase_b_workflow where workflow_id = v_wf;
  if not found then
    raise exception 'fn_kernel_workflow_start (a): % is not in the frozen Phase B workflow registry — fail closed',
      v_wf using errcode = '23503';
  end if;

  -- The accountable role comes from the registry and must RESOLVE. Never defaulted; there is no
  -- chief_of_staff fallback here and there will not be one.
  select kind, role_id into v_kind, v_owner from public.fn_phase_c_resolve_actor(w.accountable_role_id);
  if v_owner is null or v_kind is distinct from 'canonical' then
    raise exception 'fn_kernel_workflow_start (a): workflow % names accountable role %, which resolves to % — no run created',
      v_wf, w.accountable_role_id, coalesce(v_kind,'nothing') using errcode = '23514';
  end if;

  -- The start event is read from the frozen registry, never concatenated. A literal
  -- 'EV-W01-STARTED' once announced W01 for every command the company had ever received.
  v_start_event := public.fn_phase_c_lifecycle_event(v_wf, 'started');
  if v_start_event is null then
    raise exception 'fn_kernel_workflow_start (f): workflow % declares no .started event in phase_b_event',
      v_wf using errcode = '23503';
  end if;

  -- Idempotency, unchanged in shape from fn_phase_c_workflow_start so existing runs still match.
  v_dedupe := v_wf || ':' || v_object || ':' || v_version::text;
  select r.run_id, r.state, r.trace_id
    into v_prior_run, v_prior_state, v_prior_trace
    from public.phase_c_workflow_run r where r.dedupe_key = v_dedupe;
  if v_prior_run is not null then
    select sr.step_run_id into v_prior_step from public.phase_c_workflow_step_run sr
     where sr.run_id = v_prior_run order by sr.step_run_id limit 1;
    select t.task_id into v_prior_task from public.phase_c_task t
     where t.run_id = v_prior_run order by t.task_id limit 1;
    -- A second call creates NOTHING. Not a new run, not a second task, not a second event.
    return jsonb_build_object('ok', true, 'duplicate', true, 'run_id', v_prior_run,
      'workflow_id', v_wf, 'business_object_id', v_object, 'object_version', v_version,
      'state', v_prior_state, 'step_run_id', v_prior_step,
      'task_id', v_prior_task, 'trace_id', v_prior_trace,
      'dedupe_key', v_dedupe, 'created', '{}'::jsonb);
  end if;

  v_input_hash := encode(sha256(convert_to(
    v_wf || '|' || v_object || '|' || v_version::text || '|' || v_ctx::text, 'UTF8')), 'hex');

  insert into public.phase_c_workflow_run
    (workflow_id, business_object_id, object_version, start_event, accountable_role_id,
     state, dedupe_key, command_id)
  values (v_wf, v_object, v_version, v_start_event, v_owner, 'queued', v_dedupe, v_command)
  returning run_id into v_run;
  if v_run is null then
    raise exception 'fn_kernel_workflow_start (a): the workflow run insert produced no row for %', v_wf
      using errcode = '23502';
  end if;

  -- ---- (d.1) the ROOT trace, before anything hangs from it ---------------------------------
  v_run_trace := public.fn_phase_c_trace_write('TRACE-WORKFLOW', jsonb_build_object(
    'subject_kind','workflow_run', 'subject_ref', v_run::text, 'run_id', v_run,
    'command_id', v_command,
    'actor_role_id', v_owner, 'system_actor_id','system.workflow_engine',
    'input_hash', v_input_hash,
    'evidence_refs', jsonb_build_array(jsonb_build_object(
      'business_object_id', v_object, 'dedupe_key', v_dedupe, 'source_kind', v_source_k,
      'source_ref', v_source_r, 'requested_by', v_by, 'trigger_ctx', v_ctx)),
    'event_ids', jsonb_build_array(v_start_event),
    'state_before','', 'state_after','queued', 'status','open'));
  update public.phase_c_workflow_run set trace_id = v_run_trace where run_id = v_run;
  if v_run_trace is null then
    raise exception 'fn_kernel_workflow_start (d): the run has no root trace' using errcode = '23502';
  end if;

  -- The run is ACTIVE because its first step run is opened in this same transaction. The move is
  -- made as a declared transition (queued -> active) so z20_phase_c_workflow_state_guard and
  -- phase_b_workflow_transition are load-bearing rather than decorative.
  update public.phase_c_workflow_run set state = 'active' where run_id = v_run;

  -- ---- (b) the initial step run, at the REGISTRY entry step --------------------------------
  select * into s from public.phase_b_workflow_step
   where workflow_id = v_wf and step_no = 1;               -- UNIQUE (workflow_id, step_no)
  if not found then
    raise exception 'fn_kernel_workflow_start (b): workflow % declares no step_no = 1', v_wf
      using errcode = '23502';
  end if;

  select kind, role_id into v_kind, v_step_owner from public.fn_phase_c_resolve_actor(s.accountable_role_id);
  if v_step_owner is null or v_kind is distinct from 'canonical' then
    raise exception 'fn_kernel_workflow_start (c): step % names owner %, which resolves to % — no task created',
      s.step_id, s.accountable_role_id, coalesce(v_kind,'nothing') using errcode = '23514';
  end if;

  insert into public.phase_c_workflow_step_run
    (run_id, step_id, accountable_role_id, reviewer_role_id, state, attempt_no,
     input_hash, output_hash, gates_evaluated, authority_result, idempotency_key)
  values (v_run, s.step_id, v_step_owner, coalesce(s.independent_reviewer_role_id,''), 'active', 1,
          v_input_hash, '', '[]'::jsonb, 'pending: the step has not been executed yet',
          s.idempotency_scope || '|' || v_run || '|' || s.step_id || '|kernel')
  returning step_run_id into v_step_run;
  if v_step_run is null then
    raise exception 'fn_kernel_workflow_start (b): the step run insert produced no row for %', s.step_id
      using errcode = '23502';
  end if;

  -- The step run gets its own TRACE-STEP, parented to the run's root. phase_c_workflow_step_run
  -- has no trace guard trigger (only phase_c_task does), so an active step run with trace_id NULL
  -- is exactly what nobody notices — the first rehearsal of this file measured 6 of 11 step runs
  -- in that state, two of them created by this function.
  v_step_trace := public.fn_phase_c_trace_write('TRACE-STEP', jsonb_build_object(
    'subject_kind','step_run', 'subject_ref', v_step_run::text,
    'run_id', v_run, 'step_run_id', v_step_run, 'command_id', v_command,
    'actor_role_id', v_step_owner, 'system_actor_id','system.workflow_engine',
    'reviewer_role_id', coalesce(s.independent_reviewer_role_id,''),
    'authority_result','pending: the step has not been executed yet',
    'input_hash', v_input_hash,
    'evidence_refs', jsonb_build_array(jsonb_build_object(
      'step_id', s.step_id, 'step_name', s.step_name, 'entry_condition', s.entry_condition)),
    'state_before','', 'state_after','active', 'status','open'));
  update public.phase_c_workflow_step_run set trace_id = v_step_trace where step_run_id = v_step_run;
  update public.phase_c_trace set parent_trace_id = v_run_trace where trace_id = v_step_trace;
  if v_step_trace is null then
    raise exception 'fn_kernel_workflow_start (d): step run % has no trace', v_step_run
      using errcode = '23502';
  end if;

  -- ---- (c) EXACTLY ONE operational task -----------------------------------------------------
  -- Deterministic key. It is also the key the invariant check looks for: a founder command may
  -- have run:N:step:* work or cmd:N:* plan rows, never both.
  v_task := public.fn_phase_c_task_create(jsonb_build_object(
    'source_kind', v_source_k, 'source_ref', v_source_r,
    'command_id', v_command, 'run_id', v_run, 'workflow_id', v_wf, 'step_id', s.step_id,
    'accountable_role_id', v_step_owner,
    'objective', format('%s — %s: perform %s (%s) for %s.',
                        w.workflow_name, v_start_event, s.step_id, s.step_name, v_object),
    'required_inputs', s.required_inputs,
    'requested_output', s.required_output,
    'acceptance_criteria', s.acceptance_criteria,
    'closure_criteria', s.closure_criteria,
    'priority', v_priority,
    'reviewer_required', (coalesce(s.independent_reviewer_role_id,'') <> ''),
    'reviewer_role_id', coalesce(s.independent_reviewer_role_id,''),
    'idempotency_key', 'run:' || v_run || ':step:' || s.step_id));
  if v_task is null then
    raise exception 'fn_kernel_workflow_start (c): no operational task was created for run % step %',
      v_run, s.step_id using errcode = '23502';
  end if;

  -- ---- (d.2) the CHILD trace for the task, parented -----------------------------------------
  -- a00_phase_c_task_trace_guard mints it on INSERT and parents it to the command trace when the
  -- task carries a command_id, otherwise to the run trace. Both are roots; what is refused here is
  -- a task hanging from nothing.
  select trace_id into v_task_trace from public.phase_c_task where task_id = v_task;
  select parent_trace_id into v_task_parent from public.phase_c_trace where trace_id = v_task_trace;
  if v_task_trace is null or v_task_parent is null then
    raise exception 'fn_kernel_workflow_start (d): task % has trace % with parent % — a task without its parented trace is refused',
      v_task, coalesce(v_task_trace::text,'null'), coalesce(v_task_parent::text,'null')
      using errcode = '23502';
  end if;

  -- ---- (e) the initial handoff, where and ONLY where the registry declares one --------------
  -- 16 of the 30 entry steps carry an outgoing edge in phase_b_handoff; the other 14 declare
  -- none, and inventing one for them would be a handoff nobody owes. No row is a legitimate
  -- outcome here, and it is reported as such rather than treated as a failure.
  select * into h from public.phase_b_handoff where from_step_id = s.step_id;
  if found then
    insert into public.phase_c_handoff_run
      (handoff_id, run_id, from_step_run_id, sending_role_id, receiving_role_id,
       business_object_id, object_version, packet_hash, requested_action, acceptance_criteria,
       return_owner_role_id, sla_policy_id, due_at, status, accountable_until_accept_role_id)
    values (h.handoff_id, v_run, v_step_run, h.sending_role_id, h.receiving_role_id,
            v_object, v_version,
            -- the hash is over what actually exists at start: the trigger, not a work product.
            -- A packet hash over a fabricated 'output' would certify an output nobody produced.
            encode(sha256(convert_to(jsonb_build_object(
              'opened_by','fn_kernel_workflow_start', 'run_id', v_run, 'step_run_id', v_step_run,
              'business_object_id', v_object, 'object_version', v_version,
              'trigger_ctx', v_ctx)::text, 'UTF8')), 'hex'),
            h.required_packet, h.receiving_acceptance_criteria,
            h.return_owner_role_id, h.sla_policy_id,
            public.fn_kernel_sla_due(h.sla_policy_id), 'open', h.sending_role_id)
    returning handoff_run_id into v_handoff;
    if v_handoff is null then
      raise exception 'fn_kernel_workflow_start (e): the registry declares handoff % for entry step % and no handoff run was created',
        h.handoff_id, s.step_id using errcode = '23502';
    end if;

    v_ho_trace := public.fn_phase_c_trace_write('TRACE-HANDOFF', jsonb_build_object(
      'subject_kind','handoff_run', 'subject_ref', v_handoff::text, 'run_id', v_run,
      'command_id', v_command, 'actor_role_id', h.sending_role_id,
      'system_actor_id','system.workflow_engine',
      'evidence_refs', jsonb_build_array(jsonb_build_object(
        'handoff_id', h.handoff_id, 'required_packet', h.required_packet,
        'sla_policy_id', h.sla_policy_id)),
      'state_before','', 'state_after','open', 'status','open'));
    update public.phase_c_handoff_run set trace_id = v_ho_trace where handoff_run_id = v_handoff;
    update public.phase_c_trace set parent_trace_id = v_run_trace where trace_id = v_ho_trace;
  end if;

  -- ---- (f) ONE factual event ----------------------------------------------------------------
  -- Emitted LAST, after the state it describes exists. Its consumer may not create any of it.
  v_outbox := public.fn_kernel_outbox_emit(jsonb_build_object(
    'event_id', v_start_event, 'producer', 'kernel:workflow_start',
    'object_version', v_version,
    'correlation_id', v_corr, 'causation_id', v_caus, 'source_id', v_source_r,
    'command_id', v_command, 'workflow_run_id', v_run, 'step_run_id', v_step_run,
    'trace_id', v_run_trace,
    'dedupe_value', 'kernel:started:' || v_dedupe,
    'payload', jsonb_build_object(
      'fact','workflow.started',
      'workflow_id', v_wf, 'workflow_run_id', v_run, 'step_id', s.step_id,
      'step_run_id', v_step_run, 'task_id', v_task, 'handoff_run_id', v_handoff,
      'business_object_id', v_object, 'object_version', v_version,
      'accountable_role_id', v_owner, 'step_accountable_role_id', v_step_owner,
      'source_kind', v_source_k, 'source_ref', v_source_r, 'requested_by', v_by,
      'trace_id', v_run_trace, 'input_hash', v_input_hash)));
  if v_outbox is null then
    raise exception 'fn_kernel_workflow_start (f): no event row was written for run %', v_run
      using errcode = '23502';
  end if;

  -- ---- all or nothing -----------------------------------------------------------------------
  if v_run is null or v_step_run is null or v_task is null or v_outbox is null
     or v_run_trace is null or v_step_trace is null or v_task_trace is null then
    raise exception 'fn_kernel_workflow_start incomplete: run=% step_run=% task=% outbox=% run_trace=% step_trace=% task_trace=%',
      v_run, v_step_run, v_task, v_outbox, v_run_trace, v_step_trace, v_task_trace
      using errcode = '23502';
  end if;

  return jsonb_build_object(
    'ok', true, 'duplicate', false,
    'run_id', v_run, 'workflow_id', v_wf, 'workflow_name', w.workflow_name,
    'business_object_id', v_object, 'object_version', v_version, 'dedupe_key', v_dedupe,
    'state','active', 'accountable_role_id', v_owner,
    'step_id', s.step_id, 'step_run_id', v_step_run, 'step_accountable_role_id', v_step_owner,
    'task_id', v_task, 'task_idempotency_key', 'run:' || v_run || ':step:' || s.step_id,
    'handoff_run_id', v_handoff, 'handoff_id', (case when v_handoff is null then null else h.handoff_id end),
    'run_trace_id', v_run_trace, 'step_trace_id', v_step_trace,
    'task_trace_id', v_task_trace, 'handoff_trace_id', v_ho_trace,
    'event_id', v_start_event, 'outbox_id', v_outbox,
    'correlation_id', v_corr, 'causation_id', v_caus, 'source_id', v_source_r,
    'command_id', v_command, 'source_kind', v_source_k, 'requested_by', v_by,
    'created', jsonb_build_object('run',1, 'step_run',1, 'task',1, 'traces',
      (case when v_ho_trace is null then 3 else 4 end),
      'handoff', (case when v_handoff is null then 0 else 1 end), 'event',1));
end $fn$;

revoke all on function public.fn_kernel_workflow_start(jsonb) from public;
grant execute on function public.fn_kernel_workflow_start(jsonb) to service_role;
