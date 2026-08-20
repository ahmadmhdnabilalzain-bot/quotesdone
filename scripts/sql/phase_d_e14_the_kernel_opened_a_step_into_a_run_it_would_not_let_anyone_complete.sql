-- E14 — the kernel opened a step into a run it would not let anyone complete
--
-- PCCR-002. FROZEN PHASE C SUBJECT: handoff_service / fn_kernel_handoff_accept(p_input jsonb).
-- Prior digest c84ba506288819caabe1a16df9a8a21b204ee2b47a761773ff6c08c0d941e90b, read from
-- phase_c_frozen_subject before this file was written. phase_c_frozen_subject.digest is NOT touched;
-- the move is recorded in public.phase_c_freeze_amendment pinned to that digest and carrying
-- change_request_ref 'PCCR-002', the column phase_d_e13 added so that an amendment can no longer
-- excuse a digest move on its own authority.
--
-- THE CHANGE IS ONE STATEMENT MOVED ELEVEN LINES UP. fn_kernel_open_step dispatches the Phase D
-- handler for the step it opens (D36). This function called it and only afterwards set the run back
-- to 'active'. A KERNEL_ONLY_TRANSITION handler completes its step through fn_kernel_step_complete,
-- which refuses with k3_run_not_active while the run is still in waiting_handoff. So the kernel
-- commissioned work and then refused it.
--
-- MEASURED, all in aborted transactions against htdblwldjkcgjvmqkbeh on 2026-08-20, residue 0 either
-- side of every probe:
--   * thirty workflows driven through the real kernel path: 207 dispatch rows, 0 EXECUTED,
--     phase_d_effect_ledger 0 -- the state Phase D has been in since it was built;
--   * W01-S05 clears every applicable hard rule and hard gate and is refused by the kernel, not by
--     any Phase D rule: 'workflow run 16563 is in state waiting_handoff, not active';
--   * the counterfactual through the real entry point, run before this file was written -- with the
--     run already active, fn_phase_d_dispatch_step returns
--     {"outcome":"EXECUTED","handler_id":"hdl_w01_s05","effect_id":7351} and the ledger holds one row.
--
-- The paid-inference and external-provider boundaries are untouched and still fail closed on any
-- execution_context other than 'test'; the kernel path hard-codes 'production'.
--
-- CREATE OR REPLACE preserves the ACL. No grant changes here.

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
;

-- The amendment record. prior_digest is the frozen baseline read BEFORE the change; new_digest is
-- computed from the body this file just applied, so it cannot drift from what is live.
insert into public.phase_c_freeze_amendment
  (subject, object_identity, prior_digest, new_digest, reason, evidence, change_request_ref)
select 'handoff_service',
       'fn_kernel_handoff_accept(p_input jsonb)',
       'c84ba506288819caabe1a16df9a8a21b204ee2b47a761773ff6c08c0d941e90b',
       encode(sha256(convert_to(pg_get_functiondef(p.oid),'UTF8')),'hex'),
       'E14 moved the existing "the run is running again" update above the fn_kernel_open_step call. '
       || 'Since D36 that call dispatches the Phase D handler, and a KERNEL_ONLY_TRANSITION handler '
       || 'completes its step through fn_kernel_step_complete, which refuses k3_run_not_active while '
       || 'the run is still in waiting_handoff. No step in the estate could reach EXECUTED. Same '
       || 'condition, same statement, same target row, eleven lines earlier.',
       'Aborted-transaction drive of all 30 workflows on 2026-08-20: 207 phase_d_dispatch rows, 0 '
       || 'EXECUTED, phase_d_effect_ledger 0. W01-S05 cleared every applicable hard rule and gate and '
       || 'was refused by the kernel with k3_run_not_active. Counterfactual through the real entry '
       || 'point with the run already active: fn_phase_d_dispatch_step returned EXECUTED, handler '
       || 'hdl_w01_s05, effect_id 7351, ledger 1 row. fn_phase_d_fixture_residue() 0 before and after.',
       'PCCR-002'
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'fn_kernel_handoff_accept'
   and pg_get_function_identity_arguments(p.oid) = 'p_input jsonb'
   and not exists (select 1 from public.phase_c_freeze_amendment a
                    where a.object_identity = 'fn_kernel_handoff_accept(p_input jsonb)'
                      and a.change_request_ref = 'PCCR-002');
