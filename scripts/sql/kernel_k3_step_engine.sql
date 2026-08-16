-- ============================================================================================
-- KERNEL K3 — THE CANONICAL STEP ENGINE
--
-- APPLY ORDER: after kernel_k5_factual_outbox.sql, kernel_k2_workflow_start.sql and
-- kernel_k6_trace_ledger.sql. K3 emits through fn_kernel_outbox_emit, refuses re-entry through
-- fn_kernel_assert_not_in_delivery, dates handoffs with fn_kernel_sla_due, and relies on K6's
-- DEFERRABLE trace constraint triggers to refuse a close without a trace.
-- Companion validator: scripts/sql/kernel_k3b_graph_validation.sql
--
-- WHAT WAS BROKEN
--
-- Nothing in this estate closed a workflow run. Measured 16 Aug 2026 22:34 UTC on
-- htdblwldjkcgjvmqkbeh: phase_c_workflow_run holds 4 cancelled, 4 queued, 1 active and ZERO
-- completed rows. fn_kernel_workflow_start opens a run, a step run and a task; after that the only
-- progression in the estate was fn_kernel_event_consume fanning out over phase_b_handoff during
-- EVENT DELIVERY, and fn_phase_c_step_advance, which INSERTS a fresh step run instead of closing
-- the live one, never reads next_step_if_pass, and never touches phase_c_workflow_run.state.
--
-- The consumer derived successors from phase_b_handoff alone. That is the wrong subject:
--
--   phase_b_workflow_step         257 rows
--   next_step_if_pass real step   227      next_step_if_pass = 'WORKFLOW_COMPLETE'   30
--   phase_b_handoff               161 rows, every one of them (from_step_id, to_step_id)
--                                 EQUAL to the sending step's next_step_if_pass
--
--   227 declared successors split EXACTLY:
--     161 change accountable owner  -> 161 have the handoff edge   (owner change with NO edge: 0)
--      66 keep the same owner       ->   0 have a handoff edge     (and none is owed)
--
-- So 66 steps declare a real successor, carry no handoff row, and were being reported by the
-- consumer as the end of the chain. 66 + the 30 legitimately terminal closure steps = the 96 the
-- session brief names. The brief's 96 counts the 30 closure steps as part of the defect; they are
-- not. The defect population is 66, and every one of them is a same-owner hop.
--
-- TERMINALITY IS NOT THE ABSENCE OF A HANDOFF ROW. It is next_step_if_pass = 'WORKFLOW_COMPLETE',
-- and in this registry that agrees with is_closure_step on all 257 rows (30 = 30, 0 disagreements).
-- K3 reads the sentinel and the flag and requires them to agree; it never infers terminality from
-- an empty join.
--
-- WHAT THE REGISTRY SAYS AND K3 OBEYS
--   * next_step_if_fail is PROSE in all 257 rows (WORKFLOW_BLOCKED_OR_ESCALATED 146,
--     CORRECTION_OR_REJECTION_PATH 82, WORKFLOW_BLOCKED 29). K3 NEVER parses it.
--     The machine-usable failure target is failure_workflow_state, which is 'blocked' in all 257.
--   * success_workflow_state is the run state after a pass: completed 30 (closure), active 55,
--     waiting_handoff 126, waiting_review 46. It is honoured as a declared, guarded transition.
--   * phase_b_workflow_state.terminal is TRUE for completed, cancelled and superseded ONLY.
--     'blocked' and 'failed' are recoverable states, so a failed step parks the run at 'blocked'
--     with a named reason; it does not end it. fn_kernel_cancel is the one way out.
--   * Every workflow declares EV-Wnn-STARTED, EV-Wnn-COMPLETED and EV-Wnn-BLOCKED, and every one
--     of the 257 steps declares EV-Wnn-Snn-COMPLETED. There is no .failed and no .cancelled event
--     in phase_b_event, so a failure is recorded factually as EV-Wnn-BLOCKED. Nothing is invented.
--
-- THE ONE REGISTRY DEFECT K3 REFUSES TO PAPER OVER
--   W14-S05 "Validate technical completeness" carries actor_kind = 'category_overlay' and
--   accountable_role_id = 'relevant_category_overlay'. That is a placeholder token, not an overlay
--   id: fn_phase_c_resolve_actor returns kind 'unknown'. It is the ONLY step of 257 whose owner
--   does not resolve. A category overlay advises and may never own a task —
--   z10_phase_c_overlay_not_accountable enforces exactly that on phase_c_task — so K3 REFUSES to
--   open W14-S05 and raises 23514 k3_successor_owner_unresolved when W14-S04 passes. W14 is
--   therefore the one workflow of 30 whose declared pass chain cannot reach closure. This is
--   reported, not repaired: Phase B is frozen and editing it to make a number green is forbidden.
--
-- WHAT K3 CREATES
--   phase_c_step_completion          the idempotency ledger for step completion
--   fn_kernel_step_successor(text)   the ONE registry-driven successor classifier
--   fn_kernel_open_step(jsonb)       the ONE creator of a non-entry step run + its single task
--   fn_kernel_step_complete(jsonb)   THE progression engine
--   fn_kernel_handoff_accept(jsonb)  the ONE place accountability transfers on acceptance
--   fn_kernel_event_consume(bigint)  REPLACED: it now projects, and creates nothing
-- ============================================================================================


-- --------------------------------------------------------------------------------------------
-- 0. THE IDEMPOTENCY LEDGER
--
-- A replay must return the EXISTING result and create zero additional step runs, tasks, handoffs
-- and events. That requires the result to be stored, and the outbox cannot store it: its dedupe
-- key protects the event, not the caller's return value.
--
-- The claim row is inserted BEFORE any work, so a concurrent replay blocks on the unique index
-- and then reads the committed result rather than racing it. A refusal raises, which rolls the
-- claim back with everything else: a refused call must never burn its key.
-- --------------------------------------------------------------------------------------------
create table if not exists public.phase_c_step_completion (
  completion_id   bigint generated always as identity primary key,
  idempotency_key text        not null,
  step_run_id     bigint      not null references public.phase_c_workflow_step_run(step_run_id),
  run_id          bigint      not null references public.phase_c_workflow_run(run_id),
  step_id         text        not null references public.phase_b_workflow_step(step_id),
  actor_role_id   text        not null,
  outcome         text        not null,
  result          jsonb       not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  constraint phase_c_step_completion_idem_uk unique (idempotency_key),
  constraint phase_c_step_completion_outcome_ck check (outcome in ('pass','fail','block'))
);

alter table public.phase_c_step_completion enable row level security;
revoke all on table public.phase_c_step_completion from public, anon, authenticated;
grant select, insert, update on table public.phase_c_step_completion to service_role;


-- --------------------------------------------------------------------------------------------
-- 0b. TWO TRACE GUARDS THE ESTATE WAS MISSING
--
-- phase_c_workflow_step_run and phase_c_task each carry a BEFORE UPDATE guard that advances the
-- subject's trace when its state moves (a00_phase_c_step_run_trace_guard,
-- a00_phase_c_task_trace_guard). phase_c_workflow_run and phase_c_handoff_run carried NO such
-- guard, so their traces stayed on whatever state_after they were written with.
--
-- Measured before this file, on live data: fn_kernel_trace_integrity reported
--   trace_state_disagrees_with_subject_workflow_run   6 of 10
--   trace_state_disagrees_with_subject_handoff_run    1 of 3
--   terminal_objects_with_open_trace_handoff_run      1 of 3
-- The first rehearsal of K3 pushed those to 10 of 15, 5 of 10 and 5 of 10 — K3's own runs and
-- accepted handoffs, all four of each. Patching K3's call sites would have left every other
-- writer of these two tables producing the same drift, so the fix goes where all of them route:
-- one BEFORE UPDATE trigger per table, in the shape the other two already use.
--
-- These guards do NOT back-date the pre-existing rows. A trace whose subject moved before the
-- guard existed keeps saying what it said; advancing it now would be writing evidence for a
-- transition nobody recorded. Those rows stay in the numerator and are reported as pre-existing.
-- --------------------------------------------------------------------------------------------
create or replace function public.fn_kernel_workflow_run_trace_guard()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
begin
  if new.state is distinct from old.state and new.trace_id is not null then
    perform public.fn_phase_c_trace_advance(
      new.trace_id, new.state,
      -- the terminal vocabulary fn_kernel_trace_integrity itself uses for a workflow_run
      new.state in ('completed','cancelled','failed','superseded','expired','rejected'),
      jsonb_build_object('evidence_refs', jsonb_build_array(
        jsonb_build_object('transition', old.state || ' -> ' || new.state, 'at', now()))));
  end if;
  return new;
end $fn$;

create or replace function public.fn_kernel_handoff_run_trace_guard()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
begin
  if new.status is distinct from old.status and new.trace_id is not null then
    perform public.fn_phase_c_trace_advance(
      new.trace_id, new.status,
      new.status in ('accepted','rejected','cancelled','superseded'),
      jsonb_build_object('evidence_refs', jsonb_build_array(
        jsonb_build_object('transition', old.status || ' -> ' || new.status, 'at', now(),
                           'rejection_reason', nullif(new.rejection_reason,''),
                           'missing_items', nullif(new.missing_items,'')))));
  end if;
  return new;
end $fn$;

-- The same asymmetry, one table over. fn_phase_c_step_run_trace_guard seals and supersedes the
-- trace a step run is being repointed AWAY from; fn_phase_c_task_trace_guard never did. Every
-- task that walks queued -> assigned -> accepted -> in_progress -> completed therefore leaves the
-- trace z90_phase_c_task_trace_subject minted for it OPEN and pointed at by nothing: measured at
-- exactly 7 per 7-task run in the K3 rehearsal, 0 of which carried superseded_by. No check counts
-- them, which is why they accumulated unnoticed. CREATE OR REPLACE preserves the ACL, so no revoke.
create or replace function public.fn_phase_c_task_trace_guard()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
begin
  -- A task may not become active or terminal with no trace. Absence is refused, not defaulted:
  -- inventing one here would certify work that was never traced.
  if new.state in ('assigned','accepted','in_progress','review_required','revision_required',
                   'completed','failed','cancelled','superseded','blocked')
     and new.trace_id is null then
    raise exception 'phase_c_task %: state % requires a trace and trace_id is null',
      new.task_id, new.state using errcode = '23514';
  end if;

  -- The trace being left behind is sealed where it stands and superseded by the new one. Both
  -- statements are what fn_phase_c_trace_append_only permits: the first only runs while the row is
  -- still unsealed, the second changes superseded_by alone.
  if new.trace_id is distinct from old.trace_id and old.trace_id is not null then
    update public.phase_c_trace
       set status = 'sealed', sealed_at = now(),
           evidence_refs = coalesce(evidence_refs,'[]'::jsonb) || jsonb_build_array(jsonb_build_object(
             'superseded_reason','task ' || new.task_id || ' was repointed to trace '
               || new.trace_id || ', which carries the transition and its evidence.',
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
      new.state in ('completed','failed','cancelled','superseded'),
      jsonb_build_object('evidence_refs', jsonb_build_array(
        jsonb_build_object('transition', old.state || ' -> ' || new.state, 'at', now()))));
  end if;
  return new;
end $fn$;

-- a00_ so they run before the z-guards, which is the convention BEFORE triggers here follow:
-- Postgres fires BEFORE triggers in NAME order.
drop trigger if exists a00_kernel_workflow_run_trace_guard on public.phase_c_workflow_run;
create trigger a00_kernel_workflow_run_trace_guard
  before update on public.phase_c_workflow_run
  for each row execute function public.fn_kernel_workflow_run_trace_guard();

drop trigger if exists a00_kernel_handoff_run_trace_guard on public.phase_c_handoff_run;
create trigger a00_kernel_handoff_run_trace_guard
  before update on public.phase_c_handoff_run
  for each row execute function public.fn_kernel_handoff_run_trace_guard();


-- --------------------------------------------------------------------------------------------
-- 1. fn_kernel_step_successor — THE ONE SUCCESSOR CLASSIFIER
--
-- Registry only: it reads phase_b_workflow_step and phase_b_handoff and resolves owners. It takes
-- no run, so the graph validator and the engine cannot disagree about what a step's successor is.
--
-- kind is one of
--   closure                    next_step_if_pass = 'WORKFLOW_COMPLETE' and is_closure_step
--   same_owner                 successor resolves to the SAME owner; no handoff is owed
--   cross_owner                successor resolves to a DIFFERENT owner and the edge is declared
--   registry_gap_no_handoff    owner changes and NO edge is declared               -> REFUSE
--   successor_owner_unresolved successor's owner does not resolve to active canonical -> REFUSE
--   successor_not_a_step       next_step_if_pass names nothing in the registry      -> REFUSE
--   closure_flag_disagrees     the sentinel and is_closure_step disagree            -> REFUSE
--   unknown_step               p_step_id is not in the registry                     -> REFUSE
--
-- The four refusing kinds are satisfiable predicates, not decoration. Measured on today's frozen
-- registry: successor_owner_unresolved 1 (W14-S05 via W14-S04), registry_gap_no_handoff 0 of 227,
-- successor_not_a_step 0 of 227, closure_flag_disagrees 0 of 257. They stay because the registry
-- can be re-approved and because failing closed is the only safe answer when it is.
-- --------------------------------------------------------------------------------------------
create or replace function public.fn_kernel_step_successor(p_step_id text)
returns table(kind text, next_step_id text, next_owner_role_id text, handoff_id text,
              success_state text, failure_state text, this_owner_role_id text, reason text)
language plpgsql stable security definer set search_path to 'public','pg_temp' as $fn$
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
end $fn$;

revoke all on function public.fn_kernel_step_successor(text) from public;
grant execute on function public.fn_kernel_step_successor(text) to service_role;


-- --------------------------------------------------------------------------------------------
-- 2. fn_kernel_open_step — THE ONE CREATOR OF A NON-ENTRY STEP RUN
--
-- fn_kernel_workflow_start owns the ENTRY step. Everything after it comes through here, from
-- exactly two callers: fn_kernel_step_complete (same-owner successor) and fn_kernel_handoff_accept
-- (the receiving side of an accepted handoff). One step run, EXACTLY one task, both traces.
--
-- The traces are minted by the existing K6 triggers — z90_phase_c_step_run_trace_subject and
-- z90_phase_c_task_trace_subject — which already parent to the run trace and the command trace.
-- Writing a second trace here and repointing trace_id would seal and supersede a trace that was
-- correct, so it is not done. The trace ids are read back and asserted instead.
-- --------------------------------------------------------------------------------------------
create or replace function public.fn_kernel_open_step(p_input jsonb)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare
  s public.phase_b_workflow_step%rowtype;
  v_run       bigint := nullif(p_input->>'run_id','')::bigint;
  v_step      text   := nullif(btrim(coalesce(p_input->>'step_id','')), '');
  v_owner     text   := nullif(btrim(coalesce(p_input->>'owner_role_id','')), '');
  v_src_kind  text   := coalesce(nullif(p_input->>'source_kind',''), 'workflow_progression');
  v_src_ref   text   := coalesce(nullif(p_input->>'source_ref',''), 'kernel:step_engine');
  v_command   bigint := nullif(p_input->>'command_id','')::bigint;
  v_priority  text   := coalesce(nullif(p_input->>'priority',''), 'P2');
  v_object    text   := coalesce(nullif(p_input->>'business_object_id',''), '');
  v_in_hash   text   := coalesce(nullif(p_input->>'input_hash',''), '');
  v_reason    text   := coalesce(nullif(p_input->>'opened_because',''), '(no reason stated)');
  v_step_run  bigint;
  v_task      bigint;
  v_st_trace  bigint;
  v_tk_trace  bigint;
  v_tk_parent bigint;
  v_wf        text;
  v_idem      text;
begin
  if v_run is null or v_step is null or v_owner is null then
    raise exception 'fn_kernel_open_step: run_id, step_id and owner_role_id are all required (got %, %, %)',
      coalesce(v_run::text,'(null)'), coalesce(v_step,'(null)'), coalesce(v_owner,'(null)')
      using errcode = '22023';
  end if;

  select * into s from public.phase_b_workflow_step where step_id = v_step;
  if not found then
    raise exception 'fn_kernel_open_step: % is not in the frozen Phase B step registry — fail closed',
      v_step using errcode = '23503';
  end if;
  select workflow_id into v_wf from public.phase_c_workflow_run where run_id = v_run;
  if v_wf is null then
    raise exception 'fn_kernel_open_step: no workflow run %', v_run using errcode = '23503';
  end if;
  if v_wf is distinct from s.workflow_id then
    raise exception 'fn_kernel_open_step: run % is workflow % and step % belongs to % — refused',
      v_run, v_wf, v_step, s.workflow_id using errcode = '23514';
  end if;
  -- Owners are never defaulted. A step whose owner does not resolve is not opened.
  if not public.fn_phase_c_actor_may_own(v_owner) then
    raise exception 'fn_kernel_open_step: % does not resolve to an active canonical role, so step % is not opened',
      v_owner, v_step using errcode = '23514';
  end if;

  -- phase_c_step_run_live_uk is UNIQUE (run_id, step_id) WHERE state is not terminal, so a second
  -- live step run for the same step is refused by the index. Report it as the specific thing it is.
  if exists (select 1 from public.phase_c_workflow_step_run r
              where r.run_id = v_run and r.step_id = v_step
                and r.state not in ('completed','cancelled','failed','superseded','skipped')) then
    raise exception 'fn_kernel_open_step: run % already has a live step run for % — a second one would be a duplicate of work in flight',
      v_run, v_step using errcode = '23505';
  end if;

  v_idem := s.idempotency_scope || '|' || v_run || '|' || v_step || '|kernel';

  -- No trace_id on the insert: z90_phase_c_step_run_trace_subject mints TRACE-STEP AFTER INSERT
  -- and parents it to the run's root trace.
  insert into public.phase_c_workflow_step_run
    (run_id, step_id, accountable_role_id, reviewer_role_id, state, attempt_no,
     input_hash, output_hash, gates_evaluated, authority_result, idempotency_key)
  values (v_run, v_step, v_owner, coalesce(s.independent_reviewer_role_id,''), 'active', 1,
          v_in_hash, '', '[]'::jsonb, 'pending: the step has not been executed yet', v_idem)
  returning step_run_id into v_step_run;
  if v_step_run is null then
    raise exception 'fn_kernel_open_step: the step run insert produced no row for %', v_step
      using errcode = '23502';
  end if;

  select trace_id into v_st_trace from public.phase_c_workflow_step_run where step_run_id = v_step_run;
  if v_st_trace is null then
    raise exception 'fn_kernel_open_step: step run % has no trace', v_step_run using errcode = '23502';
  end if;

  -- EXACTLY ONE task, on the same deterministic key fn_kernel_workflow_start uses. That key is
  -- also what makes the legacy delivery fan-out a no-op rather than a duplicate.
  v_task := public.fn_phase_c_task_create(jsonb_build_object(
    'source_kind', v_src_kind, 'source_ref', v_src_ref,
    'command_id', v_command, 'run_id', v_run, 'workflow_id', s.workflow_id, 'step_id', v_step,
    'accountable_role_id', v_owner,
    'objective', format('%s (%s) for %s — opened because %s',
                        s.step_id, s.step_name, coalesce(nullif(v_object,''),'this run'), v_reason),
    'required_inputs', s.required_inputs,
    'requested_output', s.required_output,
    'acceptance_criteria', s.acceptance_criteria,
    'closure_criteria', s.closure_criteria,
    'priority', v_priority,
    'reviewer_required', (coalesce(s.independent_reviewer_role_id,'') <> ''),
    'reviewer_role_id', coalesce(s.independent_reviewer_role_id,''),
    'idempotency_key', 'run:' || v_run || ':step:' || v_step));
  if v_task is null then
    raise exception 'fn_kernel_open_step: no task was created for run % step %', v_run, v_step
      using errcode = '23502';
  end if;

  select trace_id into v_tk_trace from public.phase_c_task where task_id = v_task;
  select parent_trace_id into v_tk_parent from public.phase_c_trace where trace_id = v_tk_trace;
  if v_tk_trace is null or v_tk_parent is null then
    raise exception 'fn_kernel_open_step: task % has trace % with parent % — a task without its parented trace is refused',
      v_task, coalesce(v_tk_trace::text,'null'), coalesce(v_tk_parent::text,'null')
      using errcode = '23502';
  end if;

  return jsonb_build_object('step_run_id', v_step_run, 'task_id', v_task, 'step_id', v_step,
    'owner_role_id', v_owner, 'step_trace_id', v_st_trace, 'task_trace_id', v_tk_trace,
    'reviewer_required', (coalesce(s.independent_reviewer_role_id,'') <> ''),
    'reviewer_role_id', coalesce(s.independent_reviewer_role_id,''),
    'idempotency_key', v_idem);
end $fn$;

revoke all on function public.fn_kernel_open_step(jsonb) from public;
grant execute on function public.fn_kernel_open_step(jsonb) to service_role;


-- --------------------------------------------------------------------------------------------
-- 3. fn_kernel_step_complete — THE PROGRESSION ENGINE
--
-- INPUT (p_input jsonb)
--   step_run_id      bigint  required
--   actor_role_id    text    required — the accountable owner, or an active delegation_rule deputy
--   outcome          text    required — 'pass' | 'fail' | 'block'
--   idempotency_key  text    required
--   output           jsonb   required for 'pass'; a structured, non-empty object
--   inputs           jsonb   required when the step declares required_inputs
--   reason           text    required for 'fail' and 'block'
--   evidence_ref     text    optional; defaults to run:N:step:X
--   closure_evidence jsonb   optional; recorded on the run at closure
--
-- ORDER OF OPERATIONS, and why it is that order:
--   lock -> verify -> close this step and this task -> evaluate progression -> write the next
--   thing -> move the run -> emit. The current step and task are closed BEFORE the closure
--   blockers are counted, because they would otherwise count themselves as open work and closure
--   could never happen. Everything is one transaction, so a refusal anywhere rolls back the close.
-- --------------------------------------------------------------------------------------------
create or replace function public.fn_kernel_step_complete(p_input jsonb)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
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
end $fn$;

revoke all on function public.fn_kernel_step_complete(jsonb) from public;
grant execute on function public.fn_kernel_step_complete(jsonb) to service_role;


-- --------------------------------------------------------------------------------------------
-- 4. fn_kernel_handoff_accept — WHERE ACCOUNTABILITY ACTUALLY TRANSFERS
--
-- fn_kernel_step_complete opens the handoff and stops. The receiving step run and its single task
-- are created HERE and only here, from the accepted contract. That is the frozen handoff rule: the
-- sender retains accountability until acceptance (z30_phase_c_handoff_sender_retains enforces it),
-- and until then the receiver has no task, because they have not agreed to one.
--
-- A rejection is fn_phase_c_handoff_decide's business and is left to it; it returns the run's
-- accountability to the declared return owner and creates nothing.
--
-- INPUT: handoff_run_id, actor_role_id, packet (jsonb).
-- --------------------------------------------------------------------------------------------
create or replace function public.fn_kernel_handoff_accept(p_input jsonb)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
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

  v_opened := public.fn_kernel_open_step(jsonb_build_object(
    'run_id', r.run_id, 'step_id', h.to_step_id, 'owner_role_id', v_target,
    'source_kind','handoff_accepted', 'source_ref','handoff_run:' || v_id,
    'command_id', r.command_id, 'business_object_id', r.business_object_id,
    'priority', coalesce(nullif(p_input->>'priority',''), 'P2'),
    'input_hash', encode(sha256(convert_to(v_packet::text,'UTF8')),'hex'),
    'opened_because', format('handoff %s was accepted by %s', hr.handoff_id, v_actor)));

  -- The run is running again. waiting_handoff -> active and waiting_review -> active are both
  -- declared in phase_b_workflow_transition; the guard on phase_c_workflow_run enforces it.
  if r.state is distinct from 'active' then
    update public.phase_c_workflow_run set state = 'active' where run_id = r.run_id;
  end if;

  return jsonb_build_object('ok', true, 'handoff_run_id', v_id, 'handoff_id', hr.handoff_id,
    'run_id', r.run_id, 'workflow_id', r.workflow_id,
    'accepted_by', v_actor, 'accountable_now', v_dec->>'accountable_now',
    'to_step_id', h.to_step_id,
    'step_run_id', v_opened->'step_run_id', 'task_id', v_opened->'task_id',
    'step_trace_id', v_opened->'step_trace_id', 'task_trace_id', v_opened->'task_trace_id',
    'handoff_trace_id', v_dec->'trace_id', 'run_state','active',
    'created', jsonb_build_object('step_runs',1,'tasks',1,'handoffs',0,'events',0));
end $fn$;

revoke all on function public.fn_kernel_handoff_accept(jsonb) from public;
grant execute on function public.fn_kernel_handoff_accept(jsonb) to service_role;


-- --------------------------------------------------------------------------------------------
-- 5. fn_kernel_event_consume — THE CONSUMER STOPS BEING THE PROGRESSION ENGINE
--
-- CREATE OR REPLACE preserves the ACL, so there is no revoke here.
--
-- What changes: the `.completed` branch used to loop over phase_b_handoff and call
-- fn_phase_c_task_create for every to_step_id. That made event delivery a second, competing
-- creator of business work — one that skipped handoff acceptance entirely and could not see the 66
-- same-owner successors at all. It now PROJECTS: it reports what the kernel already did and what
-- the registry says comes next, and creates nothing.
--
-- The `.started` branch is unchanged in behaviour and kept verbatim in substance.
-- --------------------------------------------------------------------------------------------
create or replace function public.fn_kernel_event_consume(p_outbox_id bigint)
returns table(handled boolean, downstream_ref text, result jsonb, reason text)
language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare
  o public.phase_c_event_outbox%rowtype;
  e public.phase_b_event%rowtype;
  v_run bigint; v_step text; v_prior text;
  v_sk text; v_next text; v_next_owner text; v_ho text; v_sk_reason text;
  v_handled boolean := false; v_ref text; v_result jsonb; v_reason text;
begin
  v_prior := coalesce(nullif(current_setting('kernel.in_delivery', true),''), '0');
  perform set_config('kernel.in_delivery', '1', true);

  select * into o from public.phase_c_event_outbox where outbox_id = p_outbox_id;
  if not found then
    v_reason := 'unknown_outbox_row';
  else
    select * into e from public.phase_b_event where event_id = o.event_id;
    if not found then
      v_reason := format('%s is not in the frozen Phase B event registry', o.event_id);

    -- A row naming a command must be for a workflow that command actually selected.
    elsif coalesce(o.command_id::text, o.payload->>'command_id') is not null
      and not exists (select 1 from public.founder_command_workflow_link l
                       where l.command_id = coalesce(o.command_id, (o.payload->>'command_id')::bigint)
                         and l.workflow_id = o.workflow_id) then
      v_reason := format('event %s names workflow %s but command %s selected a different workflow',
                         o.event_id, o.workflow_id, coalesce(o.command_id::text, o.payload->>'command_id'));

    elsif e.event_name like '%.started' then
      -- workflow.started is a RECORD of a run fn_kernel_workflow_start already created.
      v_run := coalesce(o.workflow_run_id, nullif(o.payload->>'run_id','')::bigint);
      if v_run is null then
        v_reason := format('%s carries no workflow_run_id: it was produced as a command, not as a '
                        || 'record of a run. The kernel creates the run and then emits.', o.event_id);
      elsif not exists (select 1 from public.phase_c_workflow_run where run_id = v_run) then
        v_reason := format('%s names workflow run %s, which does not exist', o.event_id, v_run);
      else
        v_handled := true;
        v_ref     := 'run:' || v_run;
        v_result  := jsonb_build_object('projected','workflow_run', 'run_id', v_run,
                       'workflow_id', o.workflow_id, 'correlation_id', o.correlation_id,
                       'step_run_id', o.step_run_id, 'created_by', o.producer);
      end if;

    -- WORKFLOW-level lifecycle first. EV-Wnn-COMPLETED is named 'phase_b.wnn.completed', so it
    -- matches '%.completed' too, and K3 stamps a step_run_id on it. Without this branch the run
    -- closure would be read as a step completion and reported against the closure step.
    elsif o.event_id in (public.fn_phase_c_lifecycle_event(o.workflow_id, 'completed'),
                         public.fn_phase_c_lifecycle_event(o.workflow_id, 'blocked')) then
      v_run := coalesce(o.workflow_run_id, nullif(o.payload->>'run_id','')::bigint);
      if v_run is null then
        v_reason := format('%s carries no workflow_run_id', o.event_id);
      elsif not exists (select 1 from public.phase_c_workflow_run where run_id = v_run) then
        v_reason := format('%s names workflow run %s, which does not exist', o.event_id, v_run);
      else
        v_handled := true;
        v_ref := 'run_' || (select state from public.phase_c_workflow_run where run_id = v_run)
                 || ':' || v_run;
        v_result := jsonb_build_object('projected','workflow_lifecycle', 'created', 0,
          'run_id', v_run, 'workflow_id', o.workflow_id,
          'state', (select state from public.phase_c_workflow_run where run_id = v_run),
          'closed_at', (select closed_at from public.phase_c_workflow_run where run_id = v_run),
          'fact', o.payload->>'fact');
      end if;

    elsif e.event_name like '%.completed' and (o.step_run_id is not null or o.payload ? 'step_id') then
      v_run  := coalesce(o.workflow_run_id, nullif(o.payload->>'run_id','')::bigint);
      v_step := coalesce(o.payload->>'step_id',
                         (select step_id from public.phase_c_workflow_step_run
                           where step_run_id = o.step_run_id));
      if v_run is null or v_step is null then
        v_reason := format('completed event %s carries no run (%s) or no step (%s)',
                           o.event_id, coalesce(v_run::text,'null'), coalesce(v_step,'null'));
      else
        -- PROJECTION ONLY. fn_kernel_step_complete is the single authoritative progression path
        -- and has already created whatever comes next, inside the transaction that closed the
        -- step. Creating a task here would be a second creator racing the first, and it would
        -- hand a receiving owner work they never accepted.
        -- aliased: this function's OUT parameter `reason` would otherwise shadow the
        -- classifier's column of the same name and raise 42702.
        select c.kind, c.next_step_id, c.next_owner_role_id, c.handoff_id, c.reason
          into v_sk, v_next, v_next_owner, v_ho, v_sk_reason
          from public.fn_kernel_step_successor(v_step) c;
        v_handled := true;
        v_ref := case v_sk
                   when 'closure'    then 'closure_step:' || v_step
                   when 'same_owner' then 'kernel_opened:' || coalesce(v_next,'?')
                   when 'cross_owner' then 'kernel_handoff:' || coalesce(v_ho,'?')
                   else 'registry_defect:' || v_sk || ':' || v_step end;
        v_result := jsonb_build_object(
          'projected','step_completed', 'created', 0,
          'run_id', v_run, 'step_id', v_step, 'successor_kind', v_sk,
          'next_step_id', v_next, 'next_owner_role_id', v_next_owner, 'handoff_id', v_ho,
          'successor_reason', v_sk_reason,
          'note','fn_kernel_step_complete is the only creator of business work; delivery projects.');
      end if;

    else
      v_reason := format('no canonical consumer for %s (%s)', o.event_id, e.event_name);
    end if;
  end if;

  perform set_config('kernel.in_delivery', v_prior, true);
  return query select v_handled, v_ref, v_result, v_reason;
end $fn$;
