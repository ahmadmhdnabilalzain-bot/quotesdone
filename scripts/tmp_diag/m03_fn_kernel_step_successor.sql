CREATE OR REPLACE FUNCTION public.fn_kernel_step_successor(p_step_id text)
 RETURNS TABLE(kind text, next_step_id text, next_owner_role_id text, handoff_id text, success_state text, failure_state text, this_owner_role_id text, reason text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  s public.phase_b_workflow_step%rowtype;
  n public.phase_b_workflow_step%rowtype;
  v_this text;
  v_next text;
  v_edge text;
begin
  select * into s from public.phase_b_workflow_step where step_id = p_step_id;
  if not found then
    kind := 'unknown_step';
    reason := format('%L is not a step in the frozen Phase B registry — fail closed', p_step_id);
    return next; return;
  end if;

  success_state := s.success_workflow_state;
  failure_state := s.failure_workflow_state;
  select role_id into v_this from public.fn_phase_c_resolve_actor(s.accountable_role_id);
  this_owner_role_id := v_this;

  -- Terminality: the sentinel AND the flag. Never an empty join against phase_b_handoff.
  if s.next_step_if_pass = 'WORKFLOW_COMPLETE' or s.is_closure_step then
    if not (s.next_step_if_pass = 'WORKFLOW_COMPLETE' and s.is_closure_step) then
      kind := 'closure_flag_disagrees';
      reason := format('step %s: next_step_if_pass=%L but is_closure_step=%s — the two statements '
                    || 'of terminality disagree and neither may be preferred silently',
                       s.step_id, s.next_step_if_pass, s.is_closure_step);
      return next; return;
    end if;
    kind := 'closure';
    reason := format('step %s is the declared closure step of %s', s.step_id, s.workflow_id);
    return next; return;
  end if;

  select * into n from public.phase_b_workflow_step where step_id = s.next_step_if_pass;
  if not found then
    kind := 'successor_not_a_step'; next_step_id := s.next_step_if_pass;
    reason := format('step %s declares successor %L, which is not a step in the registry',
                     s.step_id, s.next_step_if_pass);
    return next; return;
  end if;
  next_step_id := n.step_id;

  select role_id into v_next from public.fn_phase_c_resolve_actor(n.accountable_role_id);
  next_owner_role_id := v_next;
  if v_next is null or not public.fn_phase_c_actor_may_own(v_next) then
    kind := 'successor_owner_unresolved';
    reason := format('step %s declares successor %s, whose accountable_role_id %L does not resolve '
                  || 'to an active canonical role (%s). A category overlay advises and may never '
                  || 'own a task, so no step run and no task may be opened for it.',
                     s.step_id, n.step_id, n.accountable_role_id,
                     coalesce((select r.reason from public.fn_phase_c_resolve_actor(n.accountable_role_id) r),
                              'no reason returned'));
    return next; return;
  end if;

  select h.handoff_id into v_edge from public.phase_b_handoff h
   where h.from_step_id = s.step_id and h.to_step_id = n.step_id;
  handoff_id := v_edge;

  if v_this is not null and v_next = v_this then
    if v_edge is not null then
      -- Both owners resolve to one identity yet a formal handoff is declared. 0 of 227 today.
      kind := 'cross_owner';
      reason := format('step %s -> %s: the registry declares handoff %s; it is honoured even '
                    || 'though both owners resolve to %L', s.step_id, n.step_id, v_edge, v_this);
      return next; return;
    end if;
    kind := 'same_owner';
    reason := format('step %s -> %s: owner stays %L, so no handoff is owed and none is invented',
                     s.step_id, n.step_id, v_this);
    return next; return;
  end if;

  if v_edge is null then
    kind := 'registry_gap_no_handoff';
    reason := format('step %s declares successor %s and accountability moves from %L to %L, but '
                  || 'phase_b_handoff declares no edge for it. A handoff nobody owes will not be '
                  || 'invented; this is a Phase B registry gap and is refused visibly.',
                     s.step_id, n.step_id, coalesce(v_this,'(unresolved)'), v_next);
    return next; return;
  end if;

  kind := 'cross_owner';
  reason := format('step %s -> %s via handoff %s: accountability moves from %L to %L',
                   s.step_id, n.step_id, v_edge, coalesce(v_this,'(unresolved)'), v_next);
  return next;
end $function$
