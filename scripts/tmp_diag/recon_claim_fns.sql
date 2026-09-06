

=========== fn_kernel_handoff_accept(jsonb)
CREATE OR REPLACE FUNCTION public.fn_kernel_handoff_accept(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  hr public.phase_c_handoff_run%rowtype;
  r  public.phase_c_workflow_run%rowtype;
  h  public.phase_b_handoff%rowtype;
  v_id     bigint := nullif(p_input->>'handoff_run_id','')::bigint;
  v_actor_in text := nullif(btrim(coalesce(p_input->>'actor_role_id','')), '');
  v_packet jsonb  := p_input->'packet';
  v_actor  text;
  v_kind   text;
  v_n      bigint;
  v_valid  record;
  v_dec    jsonb;
  v_opened jsonb;
  v_target text;
begin
  perform public.fn_kernel_assert_not_in_delivery('fn_kernel_handoff_accept');

  if v_id is null or v_actor_in is null then
    raise exception 'fn_kernel_handoff_accept: handoff_run_id and actor_role_id are both required'
      using errcode = '22023';
  end if;

  -- Same lock order as the engine: run, then handoff run.
  select run_id into v_n from public.phase_c_handoff_run where handoff_run_id = v_id;
  if v_n is null then
    raise exception 'fn_kernel_handoff_accept: no handoff run % (k3_handoff_not_found)', v_id
      using errcode = '23503';
  end if;
  select * into r from public.phase_c_workflow_run where run_id = v_n for update;
  if not found then
    raise exception 'fn_kernel_handoff_accept: handoff run % names workflow run %, which does not exist',
      v_id, v_n using errcode = '23503';
  end if;
  select * into hr from public.phase_c_handoff_run where handoff_run_id = v_id for update;
  if hr.status <> 'open' then
    raise exception 'fn_kernel_handoff_accept: handoff run % is % and cannot be accepted again (k3_handoff_not_open)',
      v_id, hr.status using errcode = '23514';
  end if;
  select * into h from public.phase_b_handoff where handoff_id = hr.handoff_id;
  if not found then
    raise exception 'fn_kernel_handoff_accept: handoff % is not in the frozen registry', hr.handoff_id
      using errcode = '23503';
  end if;

  select kind, role_id into v_kind, v_actor from public.fn_phase_c_resolve_actor(v_actor_in);
  if v_actor is null or v_kind is distinct from 'canonical' then
    raise exception 'fn_kernel_handoff_accept: actor % resolves to % (k3_actor_unresolved)',
      v_actor_in, coalesce(v_kind,'nothing') using errcode = '23514';
  end if;
  if v_actor is distinct from (select role_id from public.fn_phase_c_resolve_actor(hr.receiving_role_id)) then
    raise exception 'fn_kernel_handoff_accept: handoff run % is addressed to % and % may not accept it (k3_not_the_receiver)',
      v_id, hr.receiving_role_id, v_actor using errcode = '23514';
  end if;

  -- GATE-007 in substance: a packet that does not carry what the registry requires is not a
  -- complete handoff, and accepting it would transfer accountability for work nobody can do.
  select * into v_valid from public.fn_phase_c_handoff_packet_valid(hr.handoff_id, v_packet);
  if not v_valid.valid then
    raise exception 'fn_kernel_handoff_accept: handoff run % packet is incomplete [%]. Required packet: %. (k3_handoff_packet_incomplete)',
      v_id, v_valid.missing, left(h.required_packet, 160) using errcode = '23514';
  end if;

  v_dec := public.fn_phase_c_handoff_decide(v_id, 'accept', v_actor,
    jsonb_build_object('packet_hash', encode(sha256(convert_to(v_packet::text,'UTF8')),'hex')));
  if not coalesce((v_dec->>'ok')::boolean, false) then
    raise exception 'fn_kernel_handoff_accept: handoff run % refused acceptance: %',
      v_id, coalesce(v_dec->>'error','(no error given)') using errcode = '23514';
  end if;

  -- The receiving step run and its ONE task, from the accepted contract.
  select role_id into v_target from public.fn_phase_c_resolve_actor(
    (select b.accountable_role_id from public.phase_b_workflow_step b where b.step_id = h.to_step_id));
  if v_target is null or not public.fn_phase_c_actor_may_own(v_target) then
    raise exception 'fn_kernel_handoff_accept: step % names an owner that does not resolve to an active canonical role — no step run and no task are opened (k3_successor_owner_unresolved)',
      h.to_step_id using errcode = '23514';
  end if;

  -- The run is running again. waiting_handoff -> active and waiting_review -> active are both
  -- declared in phase_b_workflow_transition; the guard on phase_c_workflow_run enforces it.
  --
  -- E14 / PCCR-002. THIS STATEMENT USED TO SIT BELOW THE CALL BELOW IT, AND THAT ORDERING MEANT NO
  -- STEP IN THE ESTATE COULD EVER EXECUTE. Since D36, fn_kernel_open_step dispatches the Phase D
  -- handler for the step it opens. A KERNEL_ONLY_TRANSITION handler's declared effect is to complete
  -- that step through fn_kernel_step_complete -- which refuses, correctly, with
  -- k3_run_not_active, because at that instant this function had not yet moved the run out of
  -- waiting_handoff. The kernel opened the step, told Phase D to run it, and refused the only thing
  -- Phase D could do with it. Measured 2026-08-20: 207 dispatches across all thirty workflows, 0
  -- EXECUTED; with the run already active, the same W01-S05 step run returns EXECUTED, hdl_w01_s05,
  -- effect_id 7351.
  --
  -- Nothing else changes. Same condition, same statement, same target row; r is read at the top of
  -- the function and is unaffected by the move. If fn_kernel_open_step raises, the transaction rolls
  -- back exactly as before.
  if r.state is distinct from 'active' then
    update public.phase_c_workflow_run set state = 'active' where run_id = r.run_id;
  end if;

  v_opened := public.fn_kernel_open_step(jsonb_build_object(
    'run_id', r.run_id, 'step_id', h.to_step_id, 'owner_role_id', v_target,
    'source_kind','handoff_accepted', 'source_ref','handoff_run:' || v_id,
    'command_id', r.command_id, 'business_object_id', r.business_object_id,
    'priority', coalesce(nullif(p_input->>'priority',''), 'P2'),
    'input_hash', encode(sha256(convert_to(v_packet::text,'UTF8')),'hex'),
    'opened_because', format('handoff %s was accepted by %s', hr.handoff_id, v_actor)));

  return jsonb_build_object('ok', true, 'handoff_run_id', v_id, 'handoff_id', hr.handoff_id,
    'run_id', r.run_id, 'workflow_id', r.workflow_id,
    'accepted_by', v_actor, 'accountable_now', v_dec->>'accountable_now',
    'to_step_id', h.to_step_id,
    'step_run_id', v_opened->'step_run_id', 'task_id', v_opened->'task_id',
    'step_trace_id', v_opened->'step_trace_id', 'task_trace_id', v_opened->'task_trace_id',
    'handoff_trace_id', v_dec->'trace_id', 'run_state','active',
    'created', jsonb_build_object('step_runs',1,'tasks',1,'handoffs',0,'events',0));
end $function$


=========== fn_kernel_outbox_deliver(integer,text)
CREATE OR REPLACE FUNCTION public.fn_kernel_outbox_deliver(p_limit integer DEFAULT 25, p_worker text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c record; r record; v_attempt bigint; v_worker text;
  v_ok int := 0; v_retry int := 0; v_dead int := 0; v_claimed int := 0;
  v_err text; v_state text; v_retryable boolean;
begin
  v_worker := coalesce(nullif(btrim(p_worker),''), 'pid:' || pg_backend_pid()::text);

  -- Claim: FOR UPDATE SKIP LOCKED, one statement, attempts incremented at claim so a crash cannot
  -- lose the count. coalesce on next_attempt_at because the column is now nullable and a NULL
  -- there would silently make a row unclaimable forever. The 15-minute lease is the fix for the
  -- other half of the old defect: the raise aborted the pass and left every claimed row in
  -- 'claimed', which fn_phase_c_outbox_claim never looks at again.
  for c in
    update public.phase_c_event_outbox o set
      status = 'claimed', claimed_at = now(), attempts = o.attempts + 1
    where o.outbox_id in (
      select s.outbox_id from public.phase_c_event_outbox s
       where (s.status in ('pending','retry_wait') and coalesce(s.next_attempt_at, now()) <= now())
          or (s.status = 'claimed' and s.claimed_at < now() - interval '15 minutes')
       order by s.outbox_id
       for update skip locked
       limit greatest(1, coalesce(p_limit, 25)))
    returning o.*
  loop
    v_claimed := v_claimed + 1;

    -- BEFORE the consumer runs. This insert is outside the handler below on purpose: when the
    -- consumer raises, its subtransaction rolls back and this row is the only surviving evidence
    -- that the attempt happened at all.
    insert into public.phase_c_event_delivery_attempt
      (outbox_id, attempt_no, started_at, ok, worker_id)
    values (c.outbox_id, c.attempts, clock_timestamp(), false, v_worker)
    returning attempt_id into v_attempt;

    -- THE MARK GOES HERE, NOT ONLY IN THE CONSUMER. The first rehearsal of this file proved why:
    -- with the mark set only inside fn_kernel_event_consume, a consumer swapped for another body
    -- carried no mark, called fn_kernel_workflow_start, and CREATED A RUN FROM DELIVERY — status
    -- delivered, runs_created=1. Delivery is the thing that is delivery; whichever consumer runs
    -- inside it is inside it.
    perform set_config('kernel.in_delivery', '1', true);
    begin
      select * into r from public.fn_kernel_event_consume(c.outbox_id);
      if r is null or r.handled is null then
        v_err := 'consumer returned no verdict'; v_retryable := false;   -- null is not success
      elsif r.handled then
        v_err := null; v_retryable := null;
      else
        v_err := coalesce(r.reason, 'consumer declined without a reason'); v_retryable := false;
      end if;
    exception when others then
      v_err := SQLSTATE || ' ' || SQLERRM;
      -- Only infrastructure faults are worth trying again. A constraint violation or a bad payload
      -- fails identically forever, and retrying it hides it.
      v_retryable := SQLSTATE in ('40001','40P01','55P03','57014','53100','53200','53300',
                                  '08000','08003','08006');
      r := null;
    end;
    -- Reset outside the block so it happens on the exception path too. (A subtransaction abort
    -- would restore a GUC set inside the block, but not one set before it.)
    perform set_config('kernel.in_delivery', '0', true);

    if v_err is null then
      update public.phase_c_event_delivery_attempt set
        finished_at = clock_timestamp(), ok = true, downstream_ref = coalesce(r.downstream_ref,''),
        result_hash = encode(sha256(convert_to(coalesce(r.result::text,''), 'UTF8')), 'hex'),
        retryable = null
      where attempt_id = v_attempt;
      -- delivered is written in the success branch and nowhere else
      update public.phase_c_event_outbox set
        status = 'delivered', delivered_at = now(), last_error = '', next_attempt_at = null
      where outbox_id = c.outbox_id;
      v_ok := v_ok + 1;

    else
      v_state := case when v_retryable and c.attempts < c.max_attempts then 'retry_wait'
                      else 'dead_letter' end;
      update public.phase_c_event_delivery_attempt set
        finished_at = clock_timestamp(), ok = false, error = left(v_err, 500),
        result_hash = '', retryable = v_retryable
      where attempt_id = v_attempt;
      update public.phase_c_event_outbox set
        status = v_state,
        last_error = left(v_err, 500),
        last_sqlstate = left(coalesce(substring(v_err from '^[0-9A-Z]{5}'), ''), 5),
        -- the FIRST failure is the diagnosis; a retry must not overwrite it. Both sides are
        -- timestamptz now, and the column is nullable, so this coalesce can finally do its job.
        first_failure = coalesce(first_failure, now()),
        first_failure_reason = coalesce(first_failure_reason, left(v_err, 500)),
        next_attempt_at = case when v_state = 'retry_wait'
                               then now() + (interval '1 minute' * power(2, least(c.attempts, 6)))
                               else null end
      where outbox_id = c.outbox_id;
      if v_state = 'retry_wait' then v_retry := v_retry + 1; else v_dead := v_dead + 1; end if;
    end if;
  end loop;

  return jsonb_build_object('worker', v_worker, 'claimed', v_claimed, 'delivered', v_ok,
                            'retry_wait', v_retry, 'dead_letter', v_dead, 'at', now());
end $function$


=========== fn_kernel_step_complete(jsonb)
CREATE OR REPLACE FUNCTION public.fn_kernel_step_complete(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  sr  public.phase_c_workflow_step_run%rowtype;
  r   public.phase_c_workflow_run%rowtype;
  s   public.phase_b_workflow_step%rowtype;
  t   public.phase_c_task%rowtype;
  h   public.phase_b_handoff%rowtype;
  v_step_run  bigint := nullif(p_input->>'step_run_id','')::bigint;
  v_actor_in  text   := nullif(btrim(coalesce(p_input->>'actor_role_id','')), '');
  v_outcome   text   := lower(nullif(btrim(coalesce(p_input->>'outcome','')), ''));
  v_idem      text   := nullif(btrim(coalesce(p_input->>'idempotency_key','')), '');
  v_reason    text   := coalesce(btrim(p_input->>'reason'), '');
  v_output    jsonb  := p_input->'output';
  v_priority  text   := coalesce(nullif(p_input->>'priority',''), 'P2');
  v_actor     text;
  v_kind      text;
  v_owner     text;
  v_authority text;
  v_delegated boolean := false;
  v_target_st text;                       -- the step run's target state
  v_run_state text;                       -- the run's target state
  v_out_hash  text := '';
  v_ev_ref    text;
  v_gates     jsonb := '[]'::jsonb;
  v_gate      record;
  -- Separate scalars per callee. One shared RECORD would carry the shape of whichever
  -- set-returning function last filled it, and reading a field the new shape does not have
  -- RAISES rather than returning null.
  v_out_ok    boolean; v_out_reason text;
  v_gate_ok   boolean; v_gate_reason text;
  v_hop       text;
  v_from      text;
  v_now       text;
  v_hops      text[];
  v_tr        jsonb;
  v_completion bigint;
  v_prior     jsonb;
  -- progression
  v_sk        text; v_next_step text; v_next_owner text; v_handoff_id text;
  v_succ_state text; v_fail_state text; v_this_owner text; v_sk_reason text;
  v_opened    jsonb;
  v_handoff_run bigint;
  v_ho_trace  bigint;
  v_blockers  jsonb := '[]'::jsonb;
  v_n         bigint;
  v_rules     jsonb;
  v_step_ev   text;
  v_wf_ev     text;
  v_outbox_step bigint;
  v_outbox_wf   bigint;
  v_corr      text; v_caus text; v_src text;
  v_created_steps int := 0; v_created_tasks int := 0; v_created_handoffs int := 0;
  v_created_events int := 0;
  v_result    jsonb;
begin
  -- ---- 0. a consumer may not re-enter the producer ----------------------------------------
  perform public.fn_kernel_assert_not_in_delivery('fn_kernel_step_complete');

  if v_step_run is null or v_actor_in is null or v_idem is null then
    raise exception 'fn_kernel_step_complete: step_run_id, actor_role_id and idempotency_key are all required (got %, %, %)',
      coalesce(v_step_run::text,'(null)'), coalesce(v_actor_in,'(null)'), coalesce(v_idem,'(null)')
      using errcode = '22023';
  end if;
  if v_outcome is null or v_outcome not in ('pass','fail','block') then
    raise exception 'fn_kernel_step_complete: outcome must be pass, fail or block, got %',
      coalesce(v_outcome,'(null)') using errcode = '22023';
  end if;
  if v_outcome in ('fail','block') and v_reason = '' then
    raise exception 'fn_kernel_step_complete: outcome % requires a stated reason. An unexplained failure is not a record of anything.',
      v_outcome using errcode = '23514';
  end if;

  -- ---- 1. IDEMPOTENCY, claimed before any work --------------------------------------------
  select c.result into v_prior from public.phase_c_step_completion c where c.idempotency_key = v_idem;
  if v_prior is not null then
    return v_prior || jsonb_build_object('replay', true);
  end if;

  -- ---- 2. LOCK: run, then step run, then task. Always this order. --------------------------
  select run_id into v_n from public.phase_c_workflow_step_run where step_run_id = v_step_run;
  if v_n is null then
    raise exception 'fn_kernel_step_complete: no step run % (k3_step_run_not_found)', v_step_run
      using errcode = '23503';
  end if;
  select * into r from public.phase_c_workflow_run where run_id = v_n for update;
  if not found then
    raise exception 'fn_kernel_step_complete: step run % names workflow run %, which does not exist',
      v_step_run, v_n using errcode = '23503';
  end if;
  select * into sr from public.phase_c_workflow_step_run where step_run_id = v_step_run for update;
  if not found then
    raise exception 'fn_kernel_step_complete: no step run % (k3_step_run_not_found)', v_step_run
      using errcode = '23503';
  end if;
  select * into t from public.phase_c_task
   where run_id = r.run_id and step_id = sr.step_id order by task_id limit 1 for update;
  if not found then
    raise exception 'fn_kernel_step_complete: run % step % has no task. The kernel creates exactly one task per step run; completing a step with no task would close work nobody was ever asked to do. (k3_task_missing)',
      r.run_id, sr.step_id using errcode = '23503';
  end if;

  select * into s from public.phase_b_workflow_step where step_id = sr.step_id;
  if not found then
    raise exception 'fn_kernel_step_complete: step % is not in the frozen Phase B registry — fail closed',
      sr.step_id using errcode = '23503';
  end if;

  -- ---- 3. VERIFY -----------------------------------------------------------------------------
  -- 3a. the run must be running. Every path in this engine leaves the run at 'active' before the
  --     next step is executed, so anything else means this call is out of order.
  if r.state <> 'active' then
    raise exception 'fn_kernel_step_complete: workflow run % is in state %, not active — a step cannot be completed against a run that is not running (k3_run_not_active)',
      r.run_id, r.state using errcode = '23514';
  end if;

  -- 3b. the step run must be in a state the FROZEN step model allows to reach the target.
  v_target_st := case v_outcome when 'pass' then 'completed'
                                when 'fail' then 'failed' else 'blocked' end;
  if not exists (select 1 from public.phase_b_step_transition x
                  where x.from_state = sr.state and x.to_state = v_target_st) then
    raise exception 'fn_kernel_step_complete: step run % is in state % and the frozen Phase B step model declares no transition % -> % (k3_step_state_invalid)',
      v_step_run, sr.state, sr.state, v_target_st using errcode = '23514';
  end if;

  -- 3c. the ACTOR resolves, is active and canonical.
  select kind, role_id into v_kind, v_actor from public.fn_phase_c_resolve_actor(v_actor_in);
  if v_actor is null or v_kind is distinct from 'canonical' then
    raise exception 'fn_kernel_step_complete: actor % resolves to % — only an active canonical role may complete a step (k3_actor_unresolved)',
      v_actor_in, coalesce(v_kind,'nothing') using errcode = '23514';
  end if;

  -- 3d. the actor is the step run's accountable owner, or holds EXPLICIT delegated authority.
  --     Resolved on both sides, never string-matched: the registry may name a role and the caller
  --     an alias of it.
  v_owner := sr.accountable_role_id;
  if v_actor is distinct from (select role_id from public.fn_phase_c_resolve_actor(v_owner)) then
    select true into v_delegated
      from public.delegation_rule d
     where d.active
       and (select role_id from public.fn_phase_c_resolve_actor(d.when_agent)) = v_owner
       and (select role_id from public.fn_phase_c_resolve_actor(d.delegate_to)) = v_actor
     limit 1;
    if not coalesce(v_delegated, false) then
      raise exception 'fn_kernel_step_complete: step % is accountable to % and % holds no active delegation for it. Phase B froze step ownership; Phase C does not reassign it at runtime. (k3_not_the_accountable_owner)',
        sr.step_id, v_owner, v_actor using errcode = '23514';
    end if;
    v_authority := format('delegated: %s acted for %s under an active delegation_rule', v_actor, v_owner);
  else
    v_delegated := false;
    v_authority := format('accountable owner: %s', v_actor);
  end if;

  -- 3e. REQUIRED INPUTS. The registry states them as prose; K3 requires the caller to name what
  --     it actually used. An absent object is a refusal, never an empty pass.
  if coalesce(btrim(s.required_inputs),'') <> ''
     and coalesce(p_input->'inputs', 'null'::jsonb) in ('null'::jsonb, '{}'::jsonb) then
    raise exception 'fn_kernel_step_complete: step % declares required inputs (%) and the call names none. Send inputs as a non-empty object. (k3_required_inputs_missing)',
      sr.step_id, left(s.required_inputs, 120) using errcode = '22023';
  end if;

  -- 3f. OUTPUT. Three different absences are three different refusals, not one.
  if v_outcome = 'pass' then
    if not (p_input ? 'output') then
      raise exception 'fn_kernel_step_complete: step % passed with no output key at all. The step contract asks for %. (k3_output_key_absent)',
        sr.step_id, left(coalesce(s.required_output,'a structured output'), 120) using errcode = '22023';
    end if;
    if jsonb_typeof(v_output) = 'null' then
      raise exception 'fn_kernel_step_complete: step % sent output as a JSON null. A null is a stated absence of a result, not a result. (k3_output_is_json_null)',
        sr.step_id using errcode = '22023';
    end if;
    if jsonb_typeof(v_output) <> 'object' then
      raise exception 'fn_kernel_step_complete: step % sent output of type %, expected an object. (k3_output_not_an_object)',
        sr.step_id, jsonb_typeof(v_output) using errcode = '22023';
    end if;
    if v_output = '{}'::jsonb then
      raise exception 'fn_kernel_step_complete: step % sent an empty output object. An empty object is not evidence that anything was produced. (k3_output_empty)',
        sr.step_id using errcode = '22023';
    end if;
    select valid, reason into v_out_ok, v_out_reason
      from public.fn_phase_c_output_validate(s.required_output, v_output);
    if not coalesce(v_out_ok, false) then
      raise exception 'fn_kernel_step_complete: step % output is invalid: %. (k3_output_invalid)',
        sr.step_id, coalesce(v_out_reason,'(no reason returned)') using errcode = '22023';
    end if;
    -- The hash is over the OUTPUT. A constant is not evidence.
    v_out_hash := encode(sha256(convert_to(v_output::text, 'UTF8')), 'hex');
  end if;

  -- 3g. REVIEWER. Where Phase B names an independent reviewer for this step, a verdict from that
  --     reviewer must already exist. Independence is decided by fn_kernel_reviewer_independent —
  --     it is not re-implemented here.
  if v_outcome = 'pass' and coalesce(btrim(s.independent_reviewer_role_id),'') <> '' then
    if not exists (
      select 1 from public.phase_c_trace tr
       where tr.task_id = t.task_id
         and tr.trace_policy_id = 'TRACE-ROLE-ACTION'
         and tr.evidence_refs @> '[{"review_decision":"approved"}]'::jsonb
         and public.fn_kernel_reviewer_independent(sr.accountable_role_id, tr.reviewer_role_id)
         and (select role_id from public.fn_phase_c_resolve_actor(tr.reviewer_role_id))
             = (select role_id from public.fn_phase_c_resolve_actor(s.independent_reviewer_role_id))
    ) then
      raise exception 'fn_kernel_step_complete: step % names % as its independent reviewer and no approved, independent verdict from that role exists on task %. Record it with fn_kernel_review_decide first. (k3_reviewer_verdict_missing)',
        sr.step_id, s.independent_reviewer_role_id, t.task_id using errcode = '23514';
    end if;
  end if;

  -- 3h. GATES in scope. Hard gates block; phase_boundary gates are recorded, because they assert a
  --     property of the PHASE and not of this step's evidence.
  v_ev_ref := coalesce(nullif(p_input->>'evidence_ref',''),
                       'run:' || r.run_id || ':step:' || sr.step_id);
  for v_gate in select * from public.fn_phase_c_gates_for_step(sr.step_id) loop
    select passed, reason into v_gate_ok, v_gate_reason
      from public.fn_phase_c_gate_evaluate(v_gate.gate_id,
        jsonb_build_object('evidence_ref', v_ev_ref, 'actor_role_id', v_actor,
                           'step_id', sr.step_id, 'run_id', r.run_id, 'outcome', v_outcome));
    if v_gate.gate_type = 'hard' and not coalesce(v_gate_ok, false) and v_outcome = 'pass' then
      raise exception 'fn_kernel_step_complete: hard gate % refused step %: % (k3_gate_failed)',
        v_gate.gate_id, sr.step_id, coalesce(v_gate_reason,'(no reason returned)')
        using errcode = '23514';
    end if;
    v_gates := v_gates || jsonb_build_array(jsonb_build_object(
      'gate_id', v_gate.gate_id, 'gate_name', v_gate.gate_name, 'type', v_gate.gate_type,
      'passed', coalesce(v_gate_ok,false), 'reason', v_gate_reason,
      'blocking', (v_gate.gate_type = 'hard')));
  end loop;

  -- ---- 4. CLAIM THE IDEMPOTENCY KEY --------------------------------------------------------
  insert into public.phase_c_step_completion
    (idempotency_key, step_run_id, run_id, step_id, actor_role_id, outcome)
  values (v_idem, v_step_run, r.run_id, sr.step_id, v_actor, v_outcome)
  on conflict (idempotency_key) do nothing
  returning completion_id into v_completion;
  if v_completion is null then
    -- A concurrent caller committed the same key while we were verifying. Return THEIR result.
    select c.result into v_prior from public.phase_c_step_completion c where c.idempotency_key = v_idem;
    if v_prior is null then
      raise exception 'fn_kernel_step_complete: idempotency key % is claimed and carries no result — refusing to guess what the other caller did',
        v_idem using errcode = '23505';
    end if;
    return v_prior || jsonb_build_object('replay', true);
  end if;

  -- ---- 5. CLOSE THE TASK, then the STEP RUN, with their traces ------------------------------
  -- The task walks the Phase C task state model one declared hop at a time through
  -- fn_phase_c_task_transition, so every hop is guarded and traced. Hops that are not legal from
  -- the current state are skipped, and the ARRIVAL is asserted: an unreached terminal state raises
  -- rather than being reported as a close.
  v_hops := case v_outcome
              when 'pass'  then array['assigned','accepted','in_progress','completed']
              when 'fail'  then array['assigned','accepted','in_progress','failed']
              else              array['assigned','accepted','in_progress','blocked'] end;
  foreach v_hop in array v_hops loop
    select state into v_now from public.phase_c_task where task_id = t.task_id;
    continue when v_now = v_hop;
    continue when not public.fn_phase_c_task_transition_allowed(v_now, v_hop);
    v_tr := public.fn_phase_c_task_transition(t.task_id, v_hop, v_actor,
      jsonb_build_object('evidence', format('step %s %s by %s', sr.step_id, v_outcome, v_actor),
                         'output_hash', v_out_hash,
                         'blocker', case when v_hop = 'blocked' then v_reason else null end,
                         'blocker_owner_role_id', case when v_hop = 'blocked' then v_owner else null end));
    if not coalesce((v_tr->>'ok')::boolean, false) then
      raise exception 'fn_kernel_step_complete: task % refused the hop % -> %: %',
        t.task_id, v_now, v_hop, coalesce(v_tr->>'error','(no error given)') using errcode = '23514';
    end if;
  end loop;
  select state into v_now from public.phase_c_task where task_id = t.task_id;
  if v_now is distinct from v_hops[array_length(v_hops,1)] then
    raise exception 'fn_kernel_step_complete: task % stopped at % and never reached %. The Phase C task state model declares no path from there, so the step is NOT recorded as closed. (k3_task_close_failed)',
      t.task_id, v_now, v_hops[array_length(v_hops,1)] using errcode = '23514';
  end if;

  -- The output and the gates go on the trace while it is still OPEN; the state update below seals
  -- it through a00_phase_c_step_run_trace_guard.
  perform public.fn_phase_c_trace_advance(sr.trace_id, sr.state, false, jsonb_build_object(
    'output_hash', v_out_hash,
    'evidence_refs', jsonb_build_array(jsonb_build_object(
      'step_id', sr.step_id, 'outcome', v_outcome, 'actor_role_id', v_actor,
      'authority', v_authority, 'delegated', coalesce(v_delegated,false),
      'gates', v_gates, 'evidence_ref', v_ev_ref,
      'inputs_named', coalesce(p_input->'inputs', '{}'::jsonb),
      'reason', v_reason, 'idempotency_key', v_idem))));

  update public.phase_c_workflow_step_run
     set state = v_target_st, output_hash = v_out_hash, gates_evaluated = v_gates,
         authority_result = v_authority, finished_at = now(),
         failure_reason = case when v_outcome = 'pass' then '' else v_reason end
   where step_run_id = v_step_run;
  if not exists (select 1 from public.phase_c_workflow_step_run
                  where step_run_id = v_step_run and state = v_target_st) then
    raise exception 'fn_kernel_step_complete: step run % did not reach %', v_step_run, v_target_st
      using errcode = '23514';
  end if;

  -- ---- 6. PROGRESSION ------------------------------------------------------------------------
  select c.kind, c.next_step_id, c.next_owner_role_id, c.handoff_id, c.success_state,
         c.failure_state, c.this_owner_role_id, c.reason
    into v_sk, v_next_step, v_next_owner, v_handoff_id, v_succ_state, v_fail_state,
         v_this_owner, v_sk_reason
    from public.fn_kernel_step_successor(sr.step_id) c;

  if v_outcome in ('fail','block') then
    -- The FROZEN registry's failure target, never next_step_if_fail, which is prose in all 257.
    v_run_state := v_fail_state;

  elsif v_sk = 'closure' then
    v_run_state := v_succ_state;                                   -- 'completed' in all 30

    -- MANDATORY CLOSURE BLOCKERS. Each is measured, each can fire, and the current step and task
    -- are already closed above so they cannot count themselves.
    select count(*) into v_n from public.phase_c_workflow_step_run x
     where x.run_id = r.run_id
       and x.state not in ('completed','cancelled','failed','superseded','skipped');
    if v_n > 0 then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'blocker','open_step_runs', 'count', v_n,
        'detail',(select string_agg(x.step_id || '=' || x.state, ', ' order by x.step_id)
                    from public.phase_c_workflow_step_run x where x.run_id = r.run_id
                     and x.state not in ('completed','cancelled','failed','superseded','skipped'))));
    end if;

    select count(*) into v_n from public.phase_c_task x
     where x.run_id = r.run_id and x.state not in ('completed','cancelled','failed','superseded');
    if v_n > 0 then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'blocker','open_tasks', 'count', v_n,
        'detail',(select string_agg(x.task_id || '=' || x.state, ', ' order by x.task_id)
                    from public.phase_c_task x where x.run_id = r.run_id
                     and x.state not in ('completed','cancelled','failed','superseded'))));
    end if;

    select count(*) into v_n from public.phase_c_handoff_run x
     where x.run_id = r.run_id and x.status = 'open';
    if v_n > 0 then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'blocker','open_handoffs', 'count', v_n,
        'detail',(select string_agg(x.handoff_id, ', ' order by x.handoff_id)
                    from public.phase_c_handoff_run x
                   where x.run_id = r.run_id and x.status = 'open')));
    end if;

    -- Every step the workflow declares before the closure step must have been executed to a
    -- terminal state in THIS run. phase_b_workflow_step.step_no is 1..N with no gaps in all 30
    -- workflows, so this is exact rather than approximate.
    select count(*) into v_n from public.phase_b_workflow_step b
     where b.workflow_id = r.workflow_id and b.step_no < s.step_no
       and not exists (select 1 from public.phase_c_workflow_step_run x
                        where x.run_id = r.run_id and x.step_id = b.step_id
                          and x.state in ('completed','skipped','superseded'));
    if v_n > 0 then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'blocker','mandatory_steps_never_executed', 'count', v_n,
        'detail',(select string_agg(b.step_id, ', ' order by b.step_no)
                    from public.phase_b_workflow_step b
                   where b.workflow_id = r.workflow_id and b.step_no < s.step_no
                     and not exists (select 1 from public.phase_c_workflow_step_run x
                                      where x.run_id = r.run_id and x.step_id = b.step_id
                                        and x.state in ('completed','skipped','superseded')))));
    end if;

    -- The hard gates in scope were evaluated above and any failure already raised; they are
    -- restated in the closure evidence so the record names what was checked.
    if exists (select 1 from jsonb_array_elements(v_gates) g
                where (g->>'blocking')::boolean and not (g->>'passed')::boolean) then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'blocker','hard_gate_failed', 'count', 1, 'detail', v_gates::text));
    end if;

    if jsonb_array_length(v_blockers) > 0 then
      raise exception 'fn_kernel_step_complete: run % cannot close — % mandatory blocker class(es) are open: %. (k3_closure_blocked)',
        r.run_id, jsonb_array_length(v_blockers), v_blockers::text using errcode = '23514';
    end if;

    -- phase_b_business_rule holds 47 hard rules as PROSE with no machine predicate. They are
    -- RECORDED as the obligations in scope; they are not scored, because a scorer that always
    -- returns pass is worse than no scorer. This is a stated Phase C gap, not a silent one.
    select coalesce(jsonb_agg(jsonb_build_object('rule_id', b.rule_id, 'rule_name', b.rule_name)
                              order by b.rule_id), '[]'::jsonb)
      into v_rules
      from public.phase_b_business_rule b
     where b.rule_type = 'hard'
       and (lower(b.workflow_scope) = 'all'
            or r.workflow_id = any (string_to_array(replace(b.workflow_scope,' ',''), ';')));

  elsif v_sk = 'same_owner' then
    v_run_state := v_succ_state;

  elsif v_sk = 'cross_owner' then
    v_run_state := v_succ_state;

  else
    -- registry_gap_no_handoff, successor_owner_unresolved, successor_not_a_step,
    -- closure_flag_disagrees, unknown_step. A non-closure step with no valid successor FAILS
    -- VISIBLY. It never returns terminal success and never returns handled with no reason.
    raise exception 'fn_kernel_step_complete: step % passed and has no valid successor [%]: % (k3_no_valid_successor)',
      sr.step_id, v_sk, v_sk_reason using errcode = '23514';
  end if;

  -- ---- 7. WRITE THE NEXT THING ---------------------------------------------------------------
  if v_outcome = 'pass' and v_sk = 'same_owner' then
    -- No handoff is required and none is invented.
    v_opened := public.fn_kernel_open_step(jsonb_build_object(
      'run_id', r.run_id, 'step_id', v_next_step, 'owner_role_id', v_next_owner,
      'source_kind','workflow_progression',
      'source_ref', 'step_run:' || v_step_run, 'command_id', r.command_id,
      'business_object_id', r.business_object_id, 'priority', v_priority,
      'input_hash', v_out_hash,
      'opened_because', format('%s completed and %s keeps the same accountable owner', sr.step_id, v_next_step)));
    v_created_steps := 1; v_created_tasks := 1;

  elsif v_outcome = 'pass' and v_sk = 'cross_owner' then
    select * into h from public.phase_b_handoff where handoff_id = v_handoff_id;
    if not found then
      raise exception 'fn_kernel_step_complete: the classifier named handoff % and it is not in the registry',
        v_handoff_id using errcode = '23503';
    end if;
    -- The receiving step run and task are NOT created here. Accountability transfers on
    -- ACCEPTANCE, and fn_kernel_handoff_accept is where that happens.
    insert into public.phase_c_handoff_run
      (handoff_id, run_id, from_step_run_id, sending_role_id, receiving_role_id,
       business_object_id, object_version, packet_hash, requested_action, acceptance_criteria,
       return_owner_role_id, sla_policy_id, due_at, status, accountable_until_accept_role_id)
    values (h.handoff_id, r.run_id, v_step_run, h.sending_role_id, h.receiving_role_id,
            r.business_object_id, r.object_version,
            -- over the ACTUAL output that is being handed over
            encode(sha256(convert_to(jsonb_build_object(
              'from_step_id', sr.step_id, 'from_step_run_id', v_step_run,
              'business_object_id', r.business_object_id, 'object_version', r.object_version,
              'output', v_output)::text, 'UTF8')), 'hex'),
            h.required_packet, h.receiving_acceptance_criteria,
            h.return_owner_role_id, h.sla_policy_id,
            public.fn_kernel_sla_due(h.sla_policy_id), 'open', h.sending_role_id)
    returning handoff_run_id into v_handoff_run;
    if v_handoff_run is null then
      raise exception 'fn_kernel_step_complete: the registry declares handoff % for % and no handoff run was created',
        h.handoff_id, sr.step_id using errcode = '23502';
    end if;
    v_ho_trace := public.fn_phase_c_trace_write('TRACE-HANDOFF', jsonb_build_object(
      'subject_kind','handoff_run', 'subject_ref', v_handoff_run::text, 'run_id', r.run_id,
      'command_id', r.command_id, 'actor_role_id', h.sending_role_id,
      'system_actor_id','system.workflow_engine',
      'evidence_refs', jsonb_build_array(jsonb_build_object(
        'handoff_id', h.handoff_id, 'from_step_id', sr.step_id, 'to_step_id', v_next_step,
        'required_packet', h.required_packet, 'sla_policy_id', h.sla_policy_id,
        'output_hash', v_out_hash)),
      'output_hash', v_out_hash,
      'state_before','', 'state_after','open', 'status','open'));
    update public.phase_c_handoff_run set trace_id = v_ho_trace where handoff_run_id = v_handoff_run;
    update public.phase_c_trace set parent_trace_id = r.trace_id where trace_id = v_ho_trace;
    v_created_handoffs := 1;
  end if;

  -- ---- 8. MOVE THE RUN, as a declared and guarded transition ----------------------------------
  -- The closure evidence goes onto the run's root trace while it is still OPEN. The state update
  -- below then seals it through a00_kernel_workflow_run_trace_guard. Writing the evidence after
  -- the seal would create a superseding row instead of the record of this closure.
  if v_outcome = 'pass' and v_sk = 'closure' then
    perform public.fn_phase_c_trace_advance(r.trace_id, r.state, false, jsonb_build_object(
      'output_hash', v_out_hash,
      'evidence_refs', jsonb_build_array(jsonb_build_object(
        'closure_step_id', sr.step_id, 'closed_by', v_actor,
        'blockers_open_at_closure', v_blockers,
        'hard_business_rules_in_scope', coalesce(v_rules,'[]'::jsonb)))));
  end if;

  if v_run_state is distinct from r.state then
    update public.phase_c_workflow_run set state = v_run_state where run_id = r.run_id;
  end if;
  if v_outcome = 'pass' and v_sk = 'closure' then
    update public.phase_c_workflow_run
       set closed_at = now(),
           closure_evidence = jsonb_build_object(
             'closed_by', v_actor, 'closure_step_id', sr.step_id, 'step_run_id', v_step_run,
             'task_id', t.task_id, 'output_hash', v_out_hash, 'idempotency_key', v_idem,
             'gates_evaluated', v_gates,
             'hard_business_rules_in_scope', coalesce(v_rules,'[]'::jsonb),
             'blockers_open_at_closure', v_blockers, 'closed_at', now())
     where run_id = r.run_id;
  elsif v_outcome = 'pass' and v_sk = 'same_owner' then
    -- The successor step run is ACTIVE in this same transaction, so the run is running again.
    -- Both hops are declared in phase_b_workflow_transition; the guard enforces them.
    if v_run_state is distinct from 'active' then
      update public.phase_c_workflow_run set state = 'active' where run_id = r.run_id;
      v_run_state := 'active';
    end if;
  end if;

  -- ---- 9. EMIT, LAST, AND ONLY AFTER THE STATE CHANGE SUCCEEDED --------------------------------
  v_corr := coalesce(nullif(btrim(p_input->>'correlation_id'),''),
                     'run:' || r.run_id);
  v_caus := coalesce(nullif(btrim(p_input->>'causation_id'),''),
                     'step_run:' || v_step_run);
  v_src  := coalesce(nullif(btrim(p_input->>'source_id'),''),
                     'step_run:' || v_step_run);

  if v_outcome = 'pass' then
    v_step_ev := public.fn_phase_c_step_event(sr.step_id, 'completed');
    if v_step_ev is not null then
      v_outbox_step := public.fn_kernel_outbox_emit(jsonb_build_object(
        'event_id', v_step_ev, 'producer','kernel:step_complete',
        'object_version', r.object_version,
        'correlation_id', v_corr, 'causation_id', v_caus, 'source_id', v_src,
        'command_id', r.command_id, 'workflow_run_id', r.run_id, 'step_run_id', v_step_run,
        'trace_id', sr.trace_id,
        'dedupe_value', 'kernel:step_completed:' || v_step_run,
        'payload', jsonb_build_object(
          'fact','step.completed', 'workflow_id', r.workflow_id, 'run_id', r.run_id,
          'step_id', sr.step_id, 'step_run_id', v_step_run, 'task_id', t.task_id,
          'business_object_id', r.business_object_id, 'object_version', r.object_version,
          'actor_role_id', v_actor, 'accountable_role_id', v_owner,
          'delegated', coalesce(v_delegated,false),
          'output_hash', v_out_hash, 'successor_kind', v_sk, 'next_step_id', v_next_step,
          'handoff_run_id', v_handoff_run, 'run_state', v_run_state)));
      v_created_events := v_created_events + 1;
    end if;
  end if;

  if (v_outcome = 'pass' and v_sk = 'closure') then
    v_wf_ev := public.fn_phase_c_lifecycle_event(r.workflow_id, 'completed');
  elsif v_outcome in ('fail','block') then
    -- phase_b_event declares no .failed and no .cancelled event for any workflow. The factual
    -- record of a failed or blocked step is that the workflow is BLOCKED, which is exactly what
    -- failure_workflow_state says. Nothing is invented.
    v_wf_ev := public.fn_phase_c_lifecycle_event(r.workflow_id, 'blocked');
  end if;
  if v_wf_ev is not null then
    v_outbox_wf := public.fn_kernel_outbox_emit(jsonb_build_object(
      'event_id', v_wf_ev, 'producer','kernel:step_complete',
      'object_version', r.object_version,
      'correlation_id', v_corr, 'causation_id', v_caus, 'source_id', v_src,
      'command_id', r.command_id, 'workflow_run_id', r.run_id, 'step_run_id', v_step_run,
      'trace_id', r.trace_id,
      'dedupe_value', 'kernel:run_' || v_run_state || ':' || r.run_id || ':' || v_step_run,
      'payload', jsonb_build_object(
        'fact', 'workflow.' || v_run_state, 'workflow_id', r.workflow_id, 'run_id', r.run_id,
        'step_id', sr.step_id, 'step_run_id', v_step_run,
        'business_object_id', r.business_object_id, 'object_version', r.object_version,
        'accountable_role_id', r.accountable_role_id, 'closed_by', v_actor,
        'outcome', v_outcome, 'reason', v_reason,
        'closure_evidence', (select closure_evidence from public.phase_c_workflow_run
                              where run_id = r.run_id))));
    v_created_events := v_created_events + 1;
  end if;

  -- ---- 10. RESULT, stored on the claim so a replay returns THIS, not a recomputation ----------
  v_result := jsonb_build_object(
    'ok', true, 'replay', false,
    'run_id', r.run_id, 'workflow_id', r.workflow_id,
    'business_object_id', r.business_object_id, 'object_version', r.object_version,
    'step_id', sr.step_id, 'step_run_id', v_step_run, 'task_id', t.task_id,
    'outcome', v_outcome, 'step_run_state', v_target_st, 'run_state', v_run_state,
    'terminal_run', (v_run_state in (select state from public.phase_b_workflow_state where terminal)),
    'actor_role_id', v_actor, 'accountable_role_id', v_owner,
    'delegated', coalesce(v_delegated,false), 'authority', v_authority,
    'successor_kind', v_sk, 'successor_reason', v_sk_reason,
    'next_step_id', v_next_step, 'next_owner_role_id', v_next_owner,
    'handoff_id', v_handoff_id, 'handoff_run_id', v_handoff_run,
    'next_step_run_id', v_opened->'step_run_id', 'next_task_id', v_opened->'task_id',
    'output_hash', v_out_hash, 'gates_evaluated', v_gates,
    'closure_blockers', v_blockers,
    'hard_business_rules_in_scope', coalesce(v_rules,'[]'::jsonb),
    'run_trace_id', r.trace_id, 'step_trace_id', sr.trace_id, 'handoff_trace_id', v_ho_trace,
    'command_id', r.command_id, 'correlation_id', v_corr, 'causation_id', v_caus,
    'source_id', v_src, 'idempotency_key', v_idem,
    'event_step', v_step_ev, 'event_workflow', v_wf_ev,
    'outbox_step_id', v_outbox_step, 'outbox_workflow_id', v_outbox_wf,
    'created', jsonb_build_object('step_runs', v_created_steps, 'tasks', v_created_tasks,
                                  'handoffs', v_created_handoffs, 'events', v_created_events));

  update public.phase_c_step_completion set result = v_result where completion_id = v_completion;
  return v_result;
end $function$


=========== fn_phase_c_outbox_claim(integer)
CREATE OR REPLACE FUNCTION public.fn_phase_c_outbox_claim(p_limit integer DEFAULT 20)
 RETURNS SETOF phase_c_event_outbox
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  return query
  update public.phase_c_event_outbox o set status = 'claimed', claimed_at = now(), attempts = o.attempts + 1
  where o.outbox_id in (
    select outbox_id from public.phase_c_event_outbox
    where status in ('pending','retry_wait') and next_attempt_at <= now()
    order by outbox_id for update skip locked limit greatest(1, coalesce(p_limit, 20)))
  returning *;
end $function$


=========== fn_workflow_step_claim(integer)
CREATE OR REPLACE FUNCTION public.fn_workflow_step_claim(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_out jsonb; v_today int; v_cap int; v_demand_ready int;
begin
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

  -- NON-DEMAND ONLY. A supplier registration step worked this morning must not make the company
  -- refuse an inquiry step this afternoon.
  select count(*) into v_today
    from public.workflow_step_run sr
   where sr.output->>'worked_by' = 'workflow_dispatch'
     and sr.finished_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc'
     and not public.fn_task_is_demand(sr.action_class);

  -- Is there revenue-path work waiting that the ceiling must not block? Same predicates as the pick,
  -- so this cannot claim the ceiling is irrelevant for a step the pick would reject anyway.
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

  if v_today >= v_cap and v_demand_ready = 0 then
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
       -- THE SPLIT. A revenue-path step is always claimable; a reflection step only while the
       -- day's ceiling holds.
       and (public.fn_task_is_demand(sr.action_class) or v_today < v_cap)
       and public.fn_workflow_actor_resolve(sr.workflow_run_id, sr.actor) is not null
       and not exists (
             select 1 from public.org_action_executor e
              where e.action_class = sr.action_class and e.active and e.kind = 'edge'
                and e.risk_tier = 'low' and e.advisory_safe and e.reversible
                and not e.notifies_human
                and coalesce(e.required_authority,'') <> 'founder')
     order by sr.id
     -- the reflection remainder PLUS whatever revenue-path work is waiting, so demand is not
     -- rationed by a counter that no longer counts it. See the overshoot note in the header.
     limit greatest(least(coalesce(p_limit, 5), greatest(v_cap - v_today, 0) + v_demand_ready), 1)
     for update of sr skip locked
  ), claimed as (
    update public.workflow_step_run sr
       set status = 'running', started_at = now()
      from pick
     where sr.id = pick.id
    returning sr.id, sr.workflow_run_id, sr.step_no, sr.actor, sr.action_class, sr.input
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
           -- WHAT THIS RUN HAS ALREADY CONCLUDED. See the header: without this the process does not
           -- accumulate. Skipped steps are excluded on purpose - their note says the work was never
           -- separately observed, and passing that on as a finding would be a fabrication.
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
$function$
