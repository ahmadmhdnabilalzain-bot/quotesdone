-- ============================================================================================
-- KERNEL K7 — ONE INTERNAL-REVIEW SERVICE, AND AN INDEPENDENCE TEST THAT SURVIVES TWO VOCABULARIES
--
-- Most of this area was already correct and is left alone, stated so the next reader does not
-- re-fix it: fn_phase_c_reviewer_independent already RESOLVES both sides before comparing (it does
-- not string-match role ids), fn_pick_reviewer already resolves the author through
-- fn_org_agent_resolve (the 14 Aug fix for the 182 self-approvals), no Phase B step declares a
-- reviewer that collapses to its own accountable role, and both Phase C invariants read 0.
--
-- WHAT IS NOT SAFE IS THAT THERE ARE TWO RESOLVERS.
--
--   select count(*) from public.org_role r
--    where public.fn_org_agent_resolve(r.role_id)
--          is distinct from (select role_id from public.fn_phase_c_resolve_actor(r.role_id));
--   -> 149 of 180
--
-- 149 of 180 canonical roles resolve to a DIFFERENT identity depending on which resolver you ask.
-- The reviewer-picker asks one; the independence test asks the other. Today no pair collapses, so
-- nothing is wrong; the day one does, one function will say "independent" and the other will say
-- "the same employee", and the estate has paid for that exact shape before — a rule that held
-- because the two sides happened to agree, not because anything kept them in step.
--
-- fn_kernel_reviewer_independent asks BOTH and requires BOTH to say independent. It cannot be
-- defeated by an alias that only one vocabulary knows about, and it does not require the two
-- vocabularies to be merged first — which is Phase D work, not a change to make underneath a
-- frozen Phase A.
-- ============================================================================================

-- --------------------------------------------------- 1. independence under EVERY known vocabulary
create or replace function public.fn_kernel_reviewer_independent(p_creator text, p_reviewer text)
returns boolean language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $$
declare
  a_pc text; b_pc text;   -- the Phase C canonical resolver
  a_or text; b_or text;   -- the org-layer alias resolver
begin
  -- An absent reviewer is not an independent reviewer. Absence is never a pass.
  if coalesce(btrim(p_reviewer), '') = '' or coalesce(btrim(p_creator), '') = '' then
    return false;
  end if;

  select role_id into a_pc from public.fn_phase_c_resolve_actor(p_creator);
  select role_id into b_pc from public.fn_phase_c_resolve_actor(p_reviewer);
  -- An identity that does not resolve is refused, not waved through. A null here used to mean
  -- "cannot tell", and "cannot tell" must not be spendable as "yes".
  if a_pc is null or b_pc is null then return false; end if;
  if a_pc = b_pc then return false; end if;

  a_or := coalesce(public.fn_org_agent_resolve(p_creator), a_pc);
  b_or := coalesce(public.fn_org_agent_resolve(p_reviewer), b_pc);
  if a_or = b_or then return false; end if;

  -- Cross-vocabulary collapse: the creator under one resolver and the reviewer under the other.
  if a_pc = b_or or a_or = b_pc then return false; end if;

  return true;
end $$;

revoke all on function public.fn_kernel_reviewer_independent(text, text) from public;
grant execute on function public.fn_kernel_reviewer_independent(text, text) to service_role;

-- ------------------------------------------------------------- 2. the one review-decision service
-- Every routine review decision goes through here. It refuses a self-review under either
-- vocabulary, refuses a reviewer the frozen Phase B registry did not name where it named one, and
-- writes the decision's trace in the same transaction as the decision.
create or replace function public.fn_kernel_review_decide(p_input jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
end $fn$;

revoke all on function public.fn_kernel_review_decide(jsonb) from public;
grant execute on function public.fn_kernel_review_decide(jsonb) to service_role;

-- ------------------------------------------------------------------- 3. the invariant, with both
create or replace function public.fn_kernel_review_integrity()
returns table (check_name text, expected text, actual text, ok boolean)
language sql stable security definer set search_path to 'public', 'pg_temp' as $q$
  select 'phase_b_steps_declaring_a_self_review', '0 of steps with a declared reviewer',
         count(*) filter (where not public.fn_kernel_reviewer_independent(
                                   s.accountable_role_id, s.independent_reviewer_role_id))::text
           || ' of ' || count(*)::text,
         count(*) filter (where not public.fn_kernel_reviewer_independent(
                                   s.accountable_role_id, s.independent_reviewer_role_id)) = 0
    from public.phase_b_workflow_step s
   where coalesce(btrim(s.independent_reviewer_role_id), '') <> ''
  union all
  select 'tasks_reviewed_by_their_own_owner', '0 of tasks with a reviewer',
         count(*) filter (where not public.fn_kernel_reviewer_independent(
                                   t.accountable_role_id, t.reviewer_role_id))::text
           || ' of ' || count(*)::text,
         count(*) filter (where not public.fn_kernel_reviewer_independent(
                                   t.accountable_role_id, t.reviewer_role_id)) = 0
    from public.phase_c_task t
   where coalesce(btrim(t.reviewer_role_id), '') <> ''
  union all
  select 'tasks_requiring_review_with_no_reviewer', '0 of tasks requiring review',
         count(*) filter (where coalesce(btrim(t.reviewer_role_id), '') = '')::text
           || ' of ' || count(*)::text,
         count(*) filter (where coalesce(btrim(t.reviewer_role_id), '') = ''
                            and t.state in ('completed')) = 0
    from public.phase_c_task t where t.reviewer_required
  union all
  -- NOT a pass/fail gate. It is reported because it is the thing that would make the two
  -- independence answers diverge, and a number nobody prints is a number nobody watches.
  select 'roles_whose_two_resolvers_disagree', 'reported, not gated',
         count(*) filter (where public.fn_org_agent_resolve(r.role_id)
                            is distinct from (select role_id from public.fn_phase_c_resolve_actor(r.role_id)))::text
           || ' of ' || count(*)::text,
         true
    from public.org_role r;
$q$;

revoke all on function public.fn_kernel_review_integrity() from public;
grant execute on function public.fn_kernel_review_integrity() to service_role;
