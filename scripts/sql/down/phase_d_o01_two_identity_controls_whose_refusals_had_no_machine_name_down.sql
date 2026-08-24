-- DOWN for O01.
--
-- CLASSIFICATION: mixed. Two routine replacements (ROUTINE_RESTORE, no DDL to reverse) and one
-- genuinely additive object -- the trigger a02_phase_c_step_run_owner_admissible and the two
-- functions it and the task guard read. The additive half is what this file reverses; the two
-- replaced guards are restored to the bodies O01 found, byte-for-byte, below.

DROP TRIGGER IF EXISTS a02_phase_c_step_run_owner_admissible ON public.phase_c_workflow_step_run;
DROP FUNCTION IF EXISTS public.fn_phase_c_step_run_owner_admissible();

-- The task guard reads fn_phase_d_owner_admissibility, so the guard is restored FIRST and the
-- predicate dropped after it, or the drop would fail on the dependency.
CREATE OR REPLACE FUNCTION public.fn_phase_c_task_state_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if tg_op = 'UPDATE' and new.state is distinct from old.state
     and not public.fn_phase_c_task_transition_allowed(old.state, new.state) then
    raise exception 'phase_c_task %: transition % -> % is not in the Phase C task state model',
      old.task_id, old.state, new.state using errcode = '23514';
  end if;
  -- No generic Director, code-runner name, service-role name or unresolved alias may own a task.
  if not public.fn_phase_c_actor_may_own(new.accountable_role_id) then
    raise exception 'phase_c_task: owner % does not resolve to an active canonical role',
      new.accountable_role_id using errcode = '23514';
  end if;
  if new.reviewer_required
     and not public.fn_phase_c_reviewer_independent(new.accountable_role_id, new.reviewer_role_id) then
    raise exception 'phase_c_task: reviewer % is not independent of owner %',
      new.reviewer_role_id, new.accountable_role_id using errcode = '23514';
  end if;
  new.updated_at := now();
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_phase_c_overlay_may_not_dispatch()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_kind text;
begin
  select kind into v_kind from public.fn_phase_c_resolve_actor(new.accountable_role_id);
  if v_kind = 'overlay' then
    raise exception 'phase_c_task: category overlay % may advise but may never own a task or hold dispatch authority. Invoke it with fn_phase_c_overlay_invoke and return its advice to a canonical owner.',
      new.accountable_role_id using errcode = '23514';
  end if;
  return new;
end $function$;

DROP FUNCTION IF EXISTS public.fn_phase_d_owner_admissibility(text);
