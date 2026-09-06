CREATE OR REPLACE FUNCTION public.fn_kernel_review_decide(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_task     bigint := nullif(regexp_replace(coalesce(p_input->>'task_id',''), '\D', '', 'g'), '')::bigint;
  v_reviewer text   := coalesce(btrim(p_input->>'reviewer_role_id'), '');
  v_decision text   := lower(coalesce(btrim(p_input->>'decision'), ''));
  v_reason   text   := coalesce(btrim(p_input->>'reason'), '');
  t          public.phase_c_task%rowtype;
  v_declared text;
  v_trace    bigint;
begin
  if v_decision not in ('approved','rejected','changes_requested') then
    raise exception 'fn_kernel_review_decide: decision must be approved, rejected or changes_requested, got %',
      v_decision using errcode = '22023';
  end if;
  if v_reason = '' then
    raise exception 'fn_kernel_review_decide: a review with no stated reason is not a review'
      using errcode = '23514';
  end if;

  select * into t from public.phase_c_task where task_id = v_task;
  if not found then
    return jsonb_build_object('ok', false, 'error','task_not_found', 'task_id', v_task);
  end if;

  -- The declared reviewer comes from the FROZEN Phase B registry, read never written.
  select nullif(btrim(s.independent_reviewer_role_id), '') into v_declared
    from public.phase_b_workflow_step s where s.step_id = t.step_id;

  -- Compare RESOLVED, not literal: the registry may name a role and the caller an alias of it.
  -- fn_phase_c_resolve_actor is set-returning, so each side is pulled out in its own scalar
  -- subquery — calling it directly inside a boolean expression raises 42804.
  if v_declared is not null
     and (select role_id from public.fn_phase_c_resolve_actor(v_reviewer))
         is distinct from (select role_id from public.fn_phase_c_resolve_actor(v_declared)) then
    return jsonb_build_object('ok', false, 'error','not_the_declared_reviewer',
      'declared', v_declared, 'offered', v_reviewer, 'step_id', t.step_id,
      'message','Phase B names the independent reviewer for this step. It is frozen, and this is '
             || 'not that role.');
  end if;

  if not public.fn_kernel_reviewer_independent(t.accountable_role_id, v_reviewer) then
    return jsonb_build_object('ok', false, 'error','reviewer_not_independent',
      'creator', t.accountable_role_id, 'reviewer', v_reviewer,
      'message','The reviewer resolves to the same employee as the creator under at least one of '
             || 'the two identity vocabularies. A self-review is not a review.');
  end if;

  v_trace := public.fn_phase_c_trace_write('TRACE-ROLE-ACTION', jsonb_build_object(
    'subject_kind','task', 'subject_ref', t.task_id::text, 'task_id', t.task_id,
    'command_id', t.command_id, 'run_id', t.run_id,
    'actor_role_id', v_reviewer, 'reviewer_role_id', v_reviewer, 'reviewer_independent', true,
    'manager_role_id', t.manager_role_id, 'system_actor_id','system.workflow_engine',
    'state_before', t.state, 'state_after', t.state,
    'evidence_refs', jsonb_build_array(jsonb_build_object(
      'review_decision', v_decision, 'reason', v_reason,
      'declared_reviewer', coalesce(v_declared,'(none declared for this step)'))),
    'status','sealed'));

  update public.phase_c_task
     set reviewer_role_id = v_reviewer
   where task_id = v_task;

  return jsonb_build_object('ok', true, 'task_id', v_task, 'reviewer_role_id', v_reviewer,
    'decision', v_decision, 'declared_reviewer', v_declared, 'trace_id', v_trace,
    'independent', true);
end $function$


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


