-- PCCR-007 (companion): PHASE D REJECT NOW CALLS THE KERNEL DOOR.
--
-- With fn_kernel_handoff_reject now in the frozen kernel (pccr_007_the_kernel_can_reject_a_handoff.sql),
-- fn_phase_d_handoff_reject stops merely LOGGING the refusal and disclosing that the kernel run is left
-- open. It now calls the kernel primitive, which moves the handoff run to 'rejected', returns
-- accountability to the frozen return owner, reactivates the run and opens (or finds) the remediation
-- step. The two assertions that a rejection must NOT move the run or open a step are removed — they
-- guarded the old "the kernel exposes no reject" invariant, which PCCR-007 replaces. The Phase D
-- acceptance record (the audit trail) is still written exactly as before.
--
-- Supersedes the prior definition; ledger synced alongside. CREATE OR REPLACE preserves the ACL.
--
--   node scripts/apply_sql.mjs scripts/sql/pccr_007b_phase_d_reject_calls_the_kernel_door.sql --apply --ddl

begin;

CREATE OR REPLACE FUNCTION public.fn_phase_d_handoff_reject(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c       public.phase_d_handoff_contract%rowtype;
  hr      public.phase_c_handoff_run%rowtype;
  prior   public.phase_d_handoff_acceptance%rowtype;
  v_id    bigint := nullif(p_input->>'handoff_run_id','')::bigint;
  v_actor text   := nullif(btrim(coalesce(p_input->>'actor_role_id','')),'');
  v_reason text  := nullif(btrim(coalesce(p_input->>'reason','')),'');
  v_missing text := nullif(btrim(coalesce(p_input->>'missing','')),'');
  v_return text  := nullif(btrim(coalesce(p_input->>'return_owner','')),'');
  v_code  text   := nullif(btrim(coalesce(p_input->>'rejection_code','')),'');
  v_idem  text   := nullif(btrim(coalesce(p_input->>'idempotency_key','')),'');
  v_resolved text;
  v_before int; v_after int;
  v_state_before text; v_state_after text;
  v_hstatus_before text; v_hstatus_after text;
  v_aid   bigint;
begin
  if v_id is null or v_actor is null then
    raise exception 'fn_phase_d_handoff_reject: handoff_run_id and actor_role_id are both required (pd_handoff_input_invalid)'
      using errcode = '22023';
  end if;
  v_idem := coalesce(v_idem, format('pd-handoff-reject:%s', v_id));

  select * into hr from public.phase_c_handoff_run where handoff_run_id = v_id;
  if not found then
    raise exception 'fn_phase_d_handoff_reject: no handoff run % (pd_handoff_not_found)', v_id
      using errcode = '23503';
  end if;

  select * into prior from public.phase_d_handoff_acceptance where handoff_run_id = v_id;
  if found then
    return jsonb_build_object('ok', false, 'replay', true, 'handoff_run_id', v_id,
      'outcome', prior.outcome, 'rejection_code', prior.rejection_code,
      'note', 'this handoff run already carries a Phase D decision');
  end if;

  select * into c from public.phase_d_handoff_contract where handoff_id = hr.handoff_id;
  if not found then
    raise exception 'fn_phase_d_handoff_reject: handoff % carries no Phase D contract (pd_handoff_uncontracted)',
      hr.handoff_id using errcode = '23503';
  end if;

  if hr.status <> 'open' then
    raise exception 'fn_phase_d_handoff_reject: handoff run % is % and only an open handoff may be decided (pd_handoff_not_open)',
      v_id, hr.status using errcode = '23514';
  end if;

  -- A REJECTION MUST BE ACTIONABLE. "Rejected" with no missing item leaves the work nowhere, which
  -- is the accountability gap the frozen closure_condition is written against.
  if v_reason is null or v_missing is null then
    raise exception 'fn_phase_d_handoff_reject: handoff % must be rejected with BOTH a reason and the exact missing item. Its frozen rejection_condition is: % (pd_handoff_rejection_unspecific)',
      c.handoff_id, left(c.rejection_condition, 160) using errcode = '22023';
  end if;

  select role_id into v_resolved from public.fn_phase_c_resolve_actor(v_actor);
  if v_resolved is null
     or v_resolved is distinct from (select role_id from public.fn_phase_c_resolve_actor(c.receiving_role_id)) then
    raise exception 'fn_phase_d_handoff_reject: handoff % is addressed to % and % may not decide it (pd_handoff_wrong_receiver)',
      c.handoff_id, c.receiving_role_id, v_actor using errcode = '23514';
  end if;

  -- The return owner defaults to the frozen contract's, never to whoever happens to be calling.
  v_return := coalesce(v_return, c.return_owner_role_id);

  select count(*) into v_before from public.phase_c_workflow_step_run where run_id = hr.run_id;
  select state into v_state_before from public.phase_c_workflow_run where run_id = hr.run_id;
  v_hstatus_before := hr.status;

  -- PCCR-007. Close the handoff through the kernel door: it moves the run to 'rejected', returns
  -- accountability to the return owner, reactivates the run, and opens or finds the remediation step.
  perform public.fn_kernel_handoff_reject(jsonb_build_object(
    'handoff_run_id', v_id, 'actor_role_id', v_actor,
    'reason', v_reason, 'missing', v_missing, 'return_owner', v_return));

  select count(*) into v_after from public.phase_c_workflow_step_run where run_id = hr.run_id;
  select state into v_state_after from public.phase_c_workflow_run where run_id = hr.run_id;
  select status into v_hstatus_after from public.phase_c_handoff_run where handoff_run_id = v_id;

  insert into public.phase_d_handoff_acceptance
    (handoff_run_id, handoff_id, run_id, workflow_id, outcome, actor_role_id,
     accountable_before, accountable_after, to_step_id,
     packet_digest, packet_keys_present, rejection_code, rejection_reason, missing_items,
     return_owner_role_id, sla_policy_id, due_at, idempotency_key)
  values (v_id, c.handoff_id, hr.run_id, c.workflow_id, 'rejected', v_resolved,
          c.accountable_before_accept,
          -- ACCOUNTABILITY DOES NOT TRANSFER ON A REJECTION. It returns to the named return owner.
          v_return, c.to_step_id,
          encode(sha256(convert_to(coalesce(p_input->'packet','{}'::jsonb)::text,'UTF8')),'hex'),
          '{}', coalesce(v_code, c.rejection_code), v_reason, v_missing, v_return,
          c.sla_policy_id, hr.due_at, v_idem)
  returning acceptance_id into v_aid;

  return jsonb_build_object(
    'ok', true, 'outcome', 'rejected', 'acceptance_id', v_aid,
    'handoff_run_id', v_id, 'handoff_id', c.handoff_id, 'run_id', hr.run_id,
    'rejection_code', coalesce(v_code, c.rejection_code),
    'reason', v_reason, 'missing', v_missing,
    'return_owner_role_id', v_return, 'accountable_now', v_return,
    'step_runs_before', v_before, 'step_runs_after', v_after,
    'run_state_before', v_state_before, 'run_state_after', v_state_after,
    'workflow_advanced', false,
    'kernel_handoff_status', v_hstatus_after,
    'kernel_handoff_still_open', (v_hstatus_after = 'open'),
    'note', 'PCCR-007: the kernel handoff run is closed to rejected and the return owner holds the remediation step');
end $function$;

commit;
