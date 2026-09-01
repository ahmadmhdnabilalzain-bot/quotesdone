-- PCCR-007: THE FROZEN KERNEL CAN REJECT A HANDOFF (autonomy audit, blocking gap 5).
--
-- Rejection is a first-class, frozen outcome on all 159 handoffs, but the kernel exposed only
-- fn_kernel_handoff_accept — there was no fn_kernel_handoff_reject. fn_phase_d_handoff_reject therefore
-- recorded the refusal on the Phase D side and, by its own disclosure, left the kernel handoff run
-- status='open' FOREVER: an open handoff is a hard closure blocker, no remediation opened for the return
-- owner, and one receiver refusal stranded the run until a human cancelled it. Half the handoff lifecycle
-- had no door.
--
-- PCCR-007 adds fn_kernel_handoff_reject(jsonb), the mirror of fn_kernel_handoff_accept, reusing the
-- existing kernel primitives (no new mechanism):
--   * same lock order (run, then handoff run); same receiver check;
--   * records the rejection through fn_phase_c_handoff_decide('reject', …) — the kernel-internal path
--     that moves the handoff run to 'rejected' and returns accountability to the frozen return owner;
--   * moves the run back to 'active' (a rejected handoff must not leave the run parked in waiting_handoff);
--   * opens a remediation step run + task for the return owner at the sending step, so the work goes
--     somewhere — UNLESS a live step for it already exists, in which case that is the remediation venue.
-- A rejection advances no NEW downstream work and transfers accountability to nobody but the return owner.
--
-- fn_phase_d_handoff_reject is repointed to call this primitive (in a companion file) so a rejected
-- handoff closes and remediates instead of only being logged. Frozen-kernel change, stated as PCCR-007;
-- verified by aborted-tx rehearsal that the run leaves 'open', the run is active, and the kernel boards
-- stay green. New SECURITY DEFINER function -> revoked from PUBLIC.
--
--   node scripts/apply_sql.mjs scripts/sql/pccr_007_the_kernel_can_reject_a_handoff.sql --apply --ddl

begin;

CREATE OR REPLACE FUNCTION public.fn_kernel_handoff_reject(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  hr public.phase_c_handoff_run%rowtype;
  r  public.phase_c_workflow_run%rowtype;
  h  public.phase_b_handoff%rowtype;
  v_id      bigint := nullif(p_input->>'handoff_run_id','')::bigint;
  v_actor_in text  := nullif(btrim(coalesce(p_input->>'actor_role_id','')), '');
  v_reason  text   := nullif(btrim(coalesce(p_input->>'reason','')), '');
  v_missing text   := nullif(btrim(coalesce(p_input->>'missing','')), '');
  v_actor  text; v_kind text; v_n bigint; v_return text; v_target text; v_dec jsonb; v_opened jsonb;
begin
  perform public.fn_kernel_assert_not_in_delivery('fn_kernel_handoff_reject');

  if v_id is null or v_actor_in is null then
    raise exception 'fn_kernel_handoff_reject: handoff_run_id and actor_role_id are both required'
      using errcode = '22023';
  end if;
  -- A rejection with no missing item leaves the work nowhere; the frozen rejection_condition wants both.
  if v_reason is null or v_missing is null then
    raise exception 'fn_kernel_handoff_reject: a rejection needs BOTH a reason and the exact missing item'
      using errcode = '22023';
  end if;

  select run_id into v_n from public.phase_c_handoff_run where handoff_run_id = v_id;
  if v_n is null then
    raise exception 'fn_kernel_handoff_reject: no handoff run % (k3_handoff_not_found)', v_id using errcode = '23503';
  end if;
  select * into r  from public.phase_c_workflow_run where run_id = v_n for update;
  select * into hr from public.phase_c_handoff_run where handoff_run_id = v_id for update;
  if hr.status <> 'open' then
    raise exception 'fn_kernel_handoff_reject: handoff run % is % and cannot be rejected (k3_handoff_not_open)',
      v_id, hr.status using errcode = '23514';
  end if;
  select * into h from public.phase_b_handoff where handoff_id = hr.handoff_id;
  if not found then
    raise exception 'fn_kernel_handoff_reject: handoff % is not in the frozen registry', hr.handoff_id using errcode = '23503';
  end if;

  select kind, role_id into v_kind, v_actor from public.fn_phase_c_resolve_actor(v_actor_in);
  if v_actor is null or v_kind is distinct from 'canonical' then
    raise exception 'fn_kernel_handoff_reject: actor % resolves to % (k3_actor_unresolved)',
      v_actor_in, coalesce(v_kind,'nothing') using errcode = '23514';
  end if;
  if v_actor is distinct from (select role_id from public.fn_phase_c_resolve_actor(hr.receiving_role_id)) then
    raise exception 'fn_kernel_handoff_reject: handoff run % is addressed to % and % may not reject it (k3_not_the_receiver)',
      v_id, hr.receiving_role_id, v_actor using errcode = '23514';
  end if;

  -- The return owner is the frozen contract's, never the caller's.
  v_return := coalesce(nullif(hr.return_owner_role_id,''), nullif(h.return_owner_role_id,''), h.sending_role_id);
  select role_id into v_target from public.fn_phase_c_resolve_actor(v_return);
  if v_target is null or not public.fn_phase_c_actor_may_own(v_target) then
    raise exception 'fn_kernel_handoff_reject: return owner % does not resolve to an active canonical role (k3_return_owner_unresolved)',
      coalesce(v_return,'(none)') using errcode = '23514';
  end if;

  -- Record the rejection through the kernel-internal decide path: status -> rejected, accountable -> return owner.
  v_dec := public.fn_phase_c_handoff_decide(v_id, 'reject', v_actor,
    jsonb_build_object('reason', v_reason, 'missing', v_missing, 'return_owner', v_return));
  if not coalesce((v_dec->>'ok')::boolean, false) then
    raise exception 'fn_kernel_handoff_reject: handoff run % refused rejection: %',
      v_id, coalesce(v_dec->>'error','(no error given)') using errcode = '23514';
  end if;

  -- The run runs again; a rejected handoff must not leave it parked.
  if r.state is distinct from 'active' then
    update public.phase_c_workflow_run set state = 'active' where run_id = r.run_id;
  end if;

  -- Open a remediation step for the return owner at the sending step, so the work goes somewhere. If a
  -- live step for it already exists, that IS the remediation venue — not a second, duplicate one.
  begin
    v_opened := public.fn_kernel_open_step(jsonb_build_object(
      'run_id', r.run_id, 'step_id', h.from_step_id, 'owner_role_id', v_target,
      'source_kind','handoff_rejected', 'source_ref','handoff_run:' || v_id,
      'command_id', r.command_id, 'business_object_id', r.business_object_id,
      'priority', coalesce(nullif(p_input->>'priority',''), 'P2'),
      'opened_because', format('handoff %s was rejected by %s: %s (missing: %s)',
                               hr.handoff_id, v_actor, v_reason, v_missing)));
  exception when unique_violation then
    v_opened := jsonb_build_object('note', 'the return owner already holds a live step at '||h.from_step_id||' to remediate');
  end;

  return jsonb_build_object('ok', true, 'outcome', 'rejected', 'handoff_run_id', v_id,
    'handoff_id', hr.handoff_id, 'run_id', r.run_id, 'workflow_id', r.workflow_id,
    'rejected_by', v_actor, 'accountable_now', v_return, 'return_owner_role_id', v_target,
    'remediation_step', h.from_step_id, 'reason', v_reason, 'missing', v_missing,
    'step_run_id', v_opened->'step_run_id', 'task_id', v_opened->'task_id',
    'handoff_trace_id', v_dec->'trace_id', 'run_state','active',
    'kernel_handoff_status', (select status from public.phase_c_handoff_run where handoff_run_id = v_id));
end $function$;

revoke execute on function public.fn_kernel_handoff_reject(jsonb) from public;

-- Write authority, mirroring fn_kernel_handoff_accept: this routine writes exactly one protected table
-- directly — phase_c_workflow_run, to move the run back to active. Everything else it does goes through
-- fn_phase_c_handoff_decide and fn_kernel_open_step, which carry their own authority.
insert into public.kernel_write_authority (routine_name, table_name, why, added_at)
select 'fn_kernel_handoff_reject', 'phase_c_workflow_run',
       'K3/PCCR-007. Moves the run out of waiting_handoff back to active when the receiving owner rejects the packet — the mirror of fn_kernel_handoff_accept.', now()
where not exists (select 1 from public.kernel_write_authority
                   where routine_name='fn_kernel_handoff_reject' and table_name='phase_c_workflow_run');

commit;
