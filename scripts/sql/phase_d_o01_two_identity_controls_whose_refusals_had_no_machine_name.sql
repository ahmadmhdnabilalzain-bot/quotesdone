-- O01. TWO IDENTITY CONTROLS WHOSE REFUSALS WERE REAL AND HAD NO MACHINE NAME.
--
-- PD-AUTH-005 and PD-LEGAL-005 were both recorded NOT_RUN with the same stated blocker: that
-- closing them needs public.fn_phase_c_task_create, a KERNEL_INTERNAL_PRIMITIVE, and that a probe
-- calling it is the bypass public.fn_kernel_retired_path_state exists to catch.
--
-- THE BLOCKER WAS WRONG, and it was wrong about a routine that has been in the estate the whole
-- time. public.fn_kernel_open_step IS "a kernel entry point that accepts an owner and routes to
-- fn_phase_c_task_create" -- the exact thing the recorded blocker said had to be built. It takes
-- owner_role_id FROM THE CALLER (`p_input->>'owner_role_id'`), resolves it, opens the step run and
-- creates the task. It is an fn_kernel_* routine, so calling it is not a retired-path bypass; the
-- board's own exclusion covers it and no exclusion list is being lengthened.
--
-- DRIVEN ON PRODUCTION, 24 Aug 2026, in transactions that end in `raise exception`
-- (scripts/tmp_diag/probe_auth005d.mjs, scripts/tmp_diag/probe_legal005.mjs):
--
--   PD-AUTH-005  run 113865, W04, held at W04-S01, target W04-S02
--     A  owner = category_overlay_001_construction-materials-suppliers  -> REFUSED 23514
--     B  owner = opcat-001 (its registered packaged_role_id alias)      -> REFUSED 23514
--     C  owner = customer_onboarding (the standing accountable role)    -> ACCEPTED, task 295091
--     residue across A and B: tasks 57->57, traces 5839->5839, step runs 29->29,
--                             handoff runs 9->9, outbox 40->40
--
--   PD-LEGAL-005  run 113890, W08, held at W08-S03, target W08-S06
--                 ("Approve immutable supplier-safe package", a review-required privacy artifact;
--                  frozen owner marketplace_content_privacy_reviewer,
--                  frozen reviewer compliance_and_privacy_officer)
--     A  owner = compliance_and_privacy_officer (the declared reviewer) -> REFUSED 23514
--        "phase_c_task: reviewer compliance_and_privacy_officer is not independent of owner
--         compliance_and_privacy_officer"
--     B  owner = privacy_officer (legacy_role_id alias of the same)     -> REFUSED 23514,
--        and the message names the RESOLVED identity, so the alias disguised nothing
--     C  owner = marketplace_content_privacy_reviewer                   -> ACCEPTED, task 295148
--     residue across A and B: tasks 59->59, traces 5866->5866, step runs 31->31
--
-- The step run is inserted BEFORE the task inside fn_kernel_open_step, so arm A and arm B each
-- roll back a write that had already happened. That is the "no partial workflow effect on refusal"
-- the brief asks for, and it is measured above rather than asserted.
--
-- SO WHAT IS ACTUALLY MISSING, and it is two things, not nine:
--
--   1. NEITHER REFUSAL HAS A STABLE MACHINE NAME. The Phase D drive extractor matches
--      (pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+); both refusals above are prose. A control whose refusal
--      cannot be told from a neighbouring refusal by anything but an English sentence is a control
--      the next session will re-litigate. This file gives them
--      pd_overlay_cannot_own_task and pd_creator_reviewer_collision.
--
--   2. THE OVERLAY REFUSAL LIVES ONLY IN THE STEP ENGINE'S OWN OWNER CHECK. fn_kernel_open_step
--      calls fn_phase_c_actor_may_own and refuses before the step run is inserted, so
--      z10_phase_c_overlay_not_accountable on public.phase_c_task -- the guard that names overlays
--      -- is never reached on this path. public.phase_c_workflow_step_run itself carries NOTHING
--      that refuses an overlay accountable_role_id. Today only fn_kernel_open_step writes that
--      column with a caller-supplied value, so nothing is broken; the brief says in as many words
--      "do not rely only on Phase B currently containing no overlay-owned steps", and relying on
--      there being exactly one writer is the same bet one table over. The guard goes on the table.
--
-- MEASURED BEFORE THE GUARD WAS ADDED, so it cannot break work in flight: every
-- accountable_role_id on public.phase_c_workflow_step_run (24 rows) and on public.phase_c_task
-- (52 rows) resolves kind='canonical' today. The guard refuses nothing that exists.
--
-- WHY fn_phase_c_actor_may_own IS NOT THE PLACE FOR THE TOKEN, said out loud because it is the
-- shorter diff and it is wrong: fourteen routines call it, including fn_phase_c_invariants,
-- fn_phase_d_rule_check and fn_phase_d_gate_evaluate, which evaluate it as a BOOLEAN over many
-- rows. Making it raise would turn a rule that should report ENFORCED_FAIL into an exception five
-- frames down. A predicate stays a predicate.
--
-- WHAT THIS FILE DOES NOT TOUCH: fn_kernel_open_step, fn_kernel_step_complete and
-- fn_kernel_review_decide are FROZEN Phase C subjects and are not read, replaced or amended here.
-- fn_phase_c_overlay_may_not_dispatch and fn_phase_c_task_state_guard are not frozen subjects;
-- both are replaced below with their behaviour unchanged and a stable token added to the message.
-- The existing test that matches /does not resolve to an active canonical role/i
-- (scripts/checks/phase_b_guards_reject_injected_defects.test.mjs) still matches: the token is
-- appended, the sentence is not rewritten.

-- ---------------------------------------------------------------------------------------------
-- 1. THE PREDICATE. Deterministic, side-effect free, one answer per identity, and it says WHICH
--    kind of inadmissible an inadmissible owner is. This is what the guards below raise from and
--    what the Phase D runner reads, so the token in the message and the token in the register can
--    never drift apart -- there is one source for both.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_phase_d_owner_admissibility(p_owner text)
 RETURNS TABLE(admissible boolean, refusal_code text, resolved_role_id text, resolved_kind text)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record;
begin
  if coalesce(btrim(p_owner),'') = '' then
    admissible := false; refusal_code := 'pd_owner_absent';
    resolved_role_id := null; resolved_kind := null; return next; return;
  end if;

  select a.kind, a.role_id into r from public.fn_phase_c_resolve_actor(p_owner) a;
  resolved_role_id := r.role_id;
  resolved_kind    := r.kind;

  -- A category overlay is the named case, and it is named because it is the one identity that
  -- RESOLVES to an active role and still may not own work. The others are refused for being
  -- absent, unknown or not an employee at all, which is a different fact and gets a different code.
  if r.kind = 'overlay' then
    admissible := false; refusal_code := 'pd_overlay_cannot_own_task'; return next; return;
  end if;
  if r.kind = 'canonical' then
    admissible := true; refusal_code := null; return next; return;
  end if;

  admissible := false; refusal_code := 'pd_owner_not_canonical'; return next; return;
end $function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_owner_admissibility(text) FROM PUBLIC;

-- ---------------------------------------------------------------------------------------------
-- 2. THE STEP-RUN BOUNDARY. Every writer of public.phase_c_workflow_step_run passes here, not just
--    the one that exists today.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_phase_c_step_run_owner_admissible()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a record;
begin
  -- Only a row that ARRIVES with an owner, or CHANGES its owner, is judged. An update that leaves
  -- accountable_role_id alone is none of this guard's business, so a row written before this guard
  -- existed cannot be made unfinishable by it.
  if tg_op = 'UPDATE' and NEW.accountable_role_id is not distinct from OLD.accountable_role_id then
    return NEW;
  end if;

  select * into a from public.fn_phase_d_owner_admissibility(NEW.accountable_role_id);
  if a.admissible then return NEW; end if;

  if a.refusal_code = 'pd_overlay_cannot_own_task' then
    raise exception 'phase_c_workflow_step_run: % resolves to category overlay %, which may advise and may never be accountable for a step run. Invoke it with fn_phase_c_overlay_invoke and return its advice to a standing accountable role. (pd_overlay_cannot_own_task)',
      NEW.accountable_role_id, coalesce(a.resolved_role_id, '(unresolved)')
      using errcode = '23514';
  end if;

  raise exception 'phase_c_workflow_step_run: owner % is %, not an active canonical role, so it may not be accountable for a step run. (%)',
    coalesce(nullif(btrim(NEW.accountable_role_id),''), '(empty)'),
    coalesce(a.resolved_kind, 'absent'), a.refusal_code
    using errcode = '23514';
end $function$;

REVOKE ALL ON FUNCTION public.fn_phase_c_step_run_owner_admissible() FROM PUBLIC;

-- a02_, after a00_kernel_write_guard and a01_phase_c_step_run_review_verdict. Postgres fires BEFORE
-- triggers in NAME order, and an unauthorised writer must still be refused by the write guard
-- first: "you may not write this table" is a truer answer than "your owner is wrong".
DROP TRIGGER IF EXISTS a02_phase_c_step_run_owner_admissible ON public.phase_c_workflow_step_run;
CREATE TRIGGER a02_phase_c_step_run_owner_admissible
  BEFORE INSERT OR UPDATE ON public.phase_c_workflow_step_run
  FOR EACH ROW EXECUTE FUNCTION public.fn_phase_c_step_run_owner_admissible();

-- ---------------------------------------------------------------------------------------------
-- 3. THE TASK BOUNDARY. Behaviour unchanged; the refusals gain the machine names the harness reads.
--    CREATE OR REPLACE preserves the ACL, so no revoke here -- see the session skill.
-- ---------------------------------------------------------------------------------------------
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
    raise exception 'phase_c_task: category overlay % may advise but may never own a task or hold dispatch authority. Invoke it with fn_phase_c_overlay_invoke and return its advice to a canonical owner. (pd_overlay_cannot_own_task)',
      new.accountable_role_id using errcode = '23514';
  end if;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_phase_c_task_state_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if tg_op = 'UPDATE' and new.state is distinct from old.state
     and not public.fn_phase_c_task_transition_allowed(old.state, new.state) then
    raise exception 'phase_c_task %: transition % -> % is not in the Phase C task state model (pd_task_transition_not_permitted)',
      old.task_id, old.state, new.state using errcode = '23514';
  end if;
  -- No generic Director, code-runner name, service-role name or unresolved alias may own a task.
  if not public.fn_phase_c_actor_may_own(new.accountable_role_id) then
    raise exception 'phase_c_task: owner % does not resolve to an active canonical role (%)',
      new.accountable_role_id,
      coalesce((select refusal_code from public.fn_phase_d_owner_admissibility(new.accountable_role_id)),
               'pd_owner_not_canonical')
      using errcode = '23514';
  end if;
  if new.reviewer_required
     and not public.fn_phase_c_reviewer_independent(new.accountable_role_id, new.reviewer_role_id) then
    raise exception 'phase_c_task: reviewer % is not independent of owner % (pd_creator_reviewer_collision)',
      new.reviewer_role_id, new.accountable_role_id using errcode = '23514';
  end if;
  new.updated_at := now();
  return new;
end $function$;
