

=========== fn_decision_trace_immutable
CREATE OR REPLACE FUNCTION public.fn_decision_trace_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if old.sealed_at is not null then
    -- Only the outcome may be graded after sealing. Everything the decision was BASED on is frozen.
    if (new.decision        is distinct from old.decision)
    or (new.evidence_refs   is distinct from old.evidence_refs)
    or (new.knowledge_refs  is distinct from old.knowledge_refs)
    or (new.tool_result_refs is distinct from old.tool_result_refs)
    or (new.confidence      is distinct from old.confidence)
    or (new.authority_result is distinct from old.authority_result)
    or (new.agent_key       is distinct from old.agent_key)
    or (new.role_id         is distinct from old.role_id)
    or (new.proposed_action is distinct from old.proposed_action) then
      raise exception 'decision_trace % is sealed. Evidence, confidence, authority and identity cannot be edited after the fact; grade the outcome instead.', old.id;
    end if;
  end if;
  return new;
end $function$


=========== fn_kernel_write_guard
CREATE OR REPLACE FUNCTION public.fn_kernel_write_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_ctx    text;
  v_reason text;
  v_owner  text;
  v_ok     boolean;
begin
  get diagnostics v_ctx = pg_context;

  -- Door 1: an authorised routine is on the stack. The stack cannot be forged.
  select exists (
    select 1 from public.kernel_write_authority a
     where a.table_name = tg_table_name
       and v_ctx ~ ('PL/pgSQL function (public\.)?' || a.routine_name || '\(')
  ) into v_ok;
  if v_ok then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  -- Door 2: an explicit, audited maintenance operation BY THE TABLE OWNER. Under SECURITY INVOKER
  -- current_user is the caller's own role — service_role stays service_role, and the comparison
  -- means what it says.
  v_reason := nullif(btrim(current_setting('kernel.maintenance_reason', true)), '');
  select tableowner into v_owner from pg_tables
   where schemaname = tg_table_schema and tablename = tg_table_name;
  if v_reason is not null and current_user = v_owner then
    perform public.fn_kernel_record_maintenance_write(
      current_user, session_user, tg_table_name, tg_op, v_reason, v_ctx);
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  raise exception
    '% on %.% is refused: no routine with write authority for this table is on the call stack.',
    tg_op, tg_table_schema, tg_table_name
    using errcode = '42501',
          detail = 'Call stack was:' || chr(10) || v_ctx,
          hint = 'Business work is created by the kernel and only by the kernel. New work goes '
              || 'through fn_kernel_trigger_submit; a signal about a run that already exists goes '
              || 'through fn_kernel_signal_submit; a step is completed with fn_kernel_step_complete. '
              || 'public.kernel_write_authority lists every routine permitted to write this table '
              || 'and why. Historical maintenance needs BOTH a stated reason — set local '
              || 'kernel.maintenance_reason — AND the table owner; stating a reason alone is not '
              || 'enough, and since K37 it never was.';
end
$function$


=========== fn_phase_c_step_run_trace_guard
CREATE OR REPLACE FUNCTION public.fn_phase_c_step_run_trace_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.state in ('active','waiting_review','waiting_input','blocked',
                   'completed','failed','cancelled','superseded','skipped')
     and new.trace_id is null then
    raise exception 'phase_c_workflow_step_run %: state % requires a trace and trace_id is null',
      new.step_run_id, new.state using errcode = '23514',
      hint = 'TRACE-STEP declares trace_required=YES and completed_without_trace_allowed=NO.';
  end if;

  if new.trace_id is distinct from old.trace_id and old.trace_id is not null then
    -- The trace being left behind is sealed where it stands and superseded by the new one. Both
    -- statements are what fn_phase_c_trace_append_only permits: the first only runs while the row
    -- is still unsealed, the second changes superseded_by alone.
    update public.phase_c_trace
       set status = 'sealed', sealed_at = now(),
           evidence_refs = coalesce(evidence_refs,'[]'::jsonb) || jsonb_build_array(jsonb_build_object(
             'superseded_reason','step_run ' || new.step_run_id || ' was repointed to trace '
               || new.trace_id || ', which carries the executed step: gates, authority and output.',
             'at', now()))
     where trace_id = old.trace_id and sealed_at is null;
    update public.phase_c_trace
       set superseded_by = new.trace_id
     where trace_id = old.trace_id and superseded_by is null;
  end if;

  if new.state is distinct from old.state and new.trace_id is not null
     and new.trace_id is not distinct from old.trace_id then
    perform public.fn_phase_c_trace_advance(
      new.trace_id, new.state,
      new.state in ('completed','failed','cancelled','superseded','skipped'),
      jsonb_build_object('evidence_refs', jsonb_build_array(
        jsonb_build_object('transition', old.state || ' -> ' || new.state, 'at', now()))));
  end if;
  return new;
end $function$


=========== fn_phase_c_trace_advance
CREATE OR REPLACE FUNCTION public.fn_phase_c_trace_advance(p_trace_id bigint, p_state_after text, p_seal boolean DEFAULT false, p_body jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t public.phase_c_trace%rowtype; v_new bigint;
begin
  if p_trace_id is null then return null; end if;
  select * into t from public.phase_c_trace where trace_id = p_trace_id;
  if not found then
    raise exception 'fn_phase_c_trace_advance: no trace %', p_trace_id using errcode = '23503';
  end if;

  -- A sealed trace is evidence. It is superseded, never rewritten.
  if t.sealed_at is not null then
    v_new := public.fn_phase_c_trace_write(t.trace_policy_id, jsonb_build_object(
      'subject_kind', t.subject_kind, 'subject_ref', t.subject_ref,
      'command_id', t.command_id, 'run_id', t.run_id, 'step_run_id', t.step_run_id,
      'task_id', t.task_id, 'actor_role_id', t.actor_role_id,
      'manager_role_id', t.manager_role_id, 'system_actor_id', t.system_actor_id,
      'state_before', t.state_after, 'state_after', p_state_after,
      'evidence_refs', coalesce(p_body->'evidence_refs', '[]'::jsonb),
      'parent_trace_id', coalesce(t.parent_trace_id, t.trace_id),
      'status', case when p_seal then 'sealed' else 'open' end));
    update public.phase_c_trace set superseded_by = v_new where trace_id = p_trace_id;
    return v_new;
  end if;

  update public.phase_c_trace set
    state_before  = coalesce(nullif(t.state_before,''), t.state_after),
    state_after   = p_state_after,
    status        = case when p_seal then 'sealed' else 'open' end,
    sealed_at     = case when p_seal then now() else null end,
    output_hash   = coalesce(nullif(p_body->>'output_hash',''), t.output_hash),
    evidence_refs = case when p_body ? 'evidence_refs'
                         then coalesce(t.evidence_refs,'[]'::jsonb) || (p_body->'evidence_refs')
                         else t.evidence_refs end
  where trace_id = p_trace_id;
  return p_trace_id;
end $function$


=========== fn_phase_c_trace_append_only
CREATE OR REPLACE FUNCTION public.fn_phase_c_trace_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if old.sealed_at is null then return new; end if;
  if new.superseded_by is distinct from old.superseded_by
     and to_jsonb(new) - 'superseded_by' = to_jsonb(old) - 'superseded_by' then
    return new;
  end if;
  raise exception 'phase_c_trace %: sealed trace evidence is append-only; write a superseding row instead of editing it', old.trace_id
    using errcode = '23514';
end $function$


=========== fn_phase_c_trace_write
CREATE OR REPLACE FUNCTION public.fn_phase_c_trace_write(p_policy text, p_body jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint; v_status text;
begin
  if not exists (select 1 from public.phase_c_trace_policy where trace_policy_id = p_policy) then
    raise exception 'unknown trace policy %', p_policy using errcode = '23503';
  end if;
  v_status := coalesce(p_body->>'status','open');
  insert into public.phase_c_trace (
    trace_policy_id, subject_kind, subject_ref, command_id, run_id, step_run_id, task_id,
    actor_role_id, manager_role_id, system_actor_id, component_id, authority_result,
    reviewer_role_id, reviewer_independent, gates, rules, evidence_refs, input_hash,
    output_hash, state_before, state_after, event_ids, status, sealed_at, parent_trace_id)
  values (
    p_policy,
    coalesce(p_body->>'subject_kind', 'unknown'), coalesce(p_body->>'subject_ref', ''),
    (p_body->>'command_id')::bigint, (p_body->>'run_id')::bigint,
    (p_body->>'step_run_id')::bigint, (p_body->>'task_id')::bigint,
    coalesce(p_body->>'actor_role_id',''), coalesce(p_body->>'manager_role_id',''),
    coalesce(p_body->>'system_actor_id',''), coalesce(p_body->>'component_id',''),
    coalesce(p_body->>'authority_result',''), coalesce(p_body->>'reviewer_role_id',''),
    (p_body->>'reviewer_independent')::boolean,
    coalesce(p_body->'gates','[]'::jsonb), coalesce(p_body->'rules','[]'::jsonb),
    coalesce(p_body->'evidence_refs','[]'::jsonb), coalesce(p_body->>'input_hash',''),
    coalesce(p_body->>'output_hash',''), coalesce(p_body->>'state_before',''),
    coalesce(p_body->>'state_after',''), coalesce(p_body->'event_ids','[]'::jsonb),
    v_status,
    case when v_status = 'sealed' then now() end,
    (p_body->>'parent_trace_id')::bigint)
  returning trace_id into v_id;
  if v_id is null then
    raise exception 'phase_c_trace_write produced no row for policy %', p_policy using errcode = '23502';
  end if;
  return v_id;
end $function$


=========== fn_seal_decision_trace
CREATE OR REPLACE FUNCTION public.fn_seal_decision_trace(p_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update decision_trace set sealed_at = now() where id = p_id and sealed_at is null returning true;
$function$
