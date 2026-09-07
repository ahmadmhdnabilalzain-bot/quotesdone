-- ============================================================================================
-- KERNEL K6 — THE TRACE LEDGER
--
-- WHAT WAS MEASURED, LIVE, ON 17 Aug 2026, AFTER K4 HAD BEEN APPLIED.
-- The audit brief was written before K4; every number below was re-measured against the live
-- database rather than carried over, and four of them had moved.
--
--   1. phase_c_workflow_step_run: 3 rows are state='active' with trace_id NULL (the brief said 7;
--      K4 cancelled four of them). There is NO trigger of ANY kind on that table. Proven by
--      execution on 17 Aug: a step run was inserted 'active' with a null trace and driven to
--      'completed' in the same transaction, and nothing refused either statement.
--
--   2. phase_c_trace: 10 rows have subject_kind='task' with task_id NULL and subject_ref set to a
--      task IDEMPOTENCY KEY string ('run:136:step:W20-S01'). The brief called all ten orphans of a
--      failed insert. Re-measurement says they are TWO different things:
--        - 3 of them (485, 487, 489) ARE the trace of a real task: tasks 779, 780 and 781 carry
--          trace_id = 485/487/489. Only the reverse link is missing, because
--          z90_phase_c_task_trace_subject (which stamps task_id) was created after those rows were.
--        - 7 of them (490, 491, 492, 534, 536, 537, 827) are true orphans: no phase_c_task row
--          anywhere carries their trace_id. a00_phase_c_task_trace_guard was BEFORE INSERT, so it
--          wrote the trace and THEN the insert was discarded by phase_c_task_idem_uk. Proven by
--          execution on 17 Aug: one `on conflict (idempotency_key) do nothing` insert that
--          inserted zero task rows created exactly 1 trace row.
--
--   3. phase_c_trace: 3 rows have status='sealed' with sealed_at NULL (the brief said 7; K4's
--      step (h) stamped four). fn_phase_c_trace_append_only reads sealed_at, so all three are
--      evidence that presents as sealed and is rewritable in place.
--
--   4. founder_command: a00_founder_command_trace_guard was BEFORE UPDATE ONLY. Proven by
--      execution on 17 Aug: a command was INSERTED directly at state='in_progress' with trace_id
--      NULL and the guard never saw it.
--
--   5. Terminal objects holding an open trace: 3, not the brief's 12 (K4 closed the rest) — one
--      accepted handoff, one completed step run, one completed task. TWO of the three (traces 525
--      and 529) are the rows in (3), so repairing (3) repairs them. The THIRD is handoff run 48:
--      it points at trace 522, which was never sealed and still says state_after='open'. That one
--      is the pointer defect in (6), not the seal defect, and it is NOT repaired here.
--
--   6. STILL TRUE AND NOT FIXED HERE: 4 cancelled workflow runs (91, 92, 93, 96) and 1 accepted
--      handoff (48) whose BOUND trace's state_after still says 'queued' / 'open'. This is a K4
--      defect, not a K6 one: fn_kernel_cancel writes a fresh cancellation trace, records its id in
--      closure_evidence, seals the run's ORIGINAL trace where it stands, and never repoints
--      run.trace_id. The accepted handoff is the same shape — its accept trace (523) exists and
--      says 'accepted', and handoff_run.trace_id still points at the trace opened before it.
--      K6 measures it and leaves it red. There was no invariant for this at all before K6; the
--      brief's item 8 is exactly that gap. Repointing those pointers is a decision about what
--      trace_id means on a run, and it is not made by quietly editing sealed evidence.
--
--   7. TRACE-SYSTEM-EXECUTION: 656 components are scoped to it, 609 of them state-changing, and
--      ZERO traces have ever been written under it — 0 of 72 traces in the table. K6 does NOT
--      weaken the policy. fn_kernel_trace_integrity() measures it and reports 609 of 656 with
--      ok=false, and it will stay false until scheduled execution actually writes traces.
--
--   8. superseded_by is NULL on all 72 traces; the supersede mechanism has never fired.
--
-- WHAT THIS FILE DOES
--
--   A. NO ORPHAN TRACE AFTER A FAILED INSERT. Task-trace creation moves off BEFORE INSERT. An
--      AFTER INSERT trigger writes the trace and stamps phase_c_task.trace_id, so a row that is
--      never inserted leaves nothing behind; a DEFERRABLE INITIALLY DEFERRED constraint trigger
--      asserts at COMMIT that the task still has a trace that exists and names it, so a row that
--      IS inserted cannot commit without one. The trace's subject_ref becomes the task_id, not the
--      idempotency key — which is what made these rows unresolvable in the first place.
--
--   B. THE SAME SHAPE ON phase_c_workflow_step_run, which today has no trigger at all.
--      One collision had to be resolved: fn_phase_c_step_advance already writes its own rich
--      TRACE-STEP row (gates, authority, reviewer independence) and repoints step_run.trace_id.
--      Rather than edit that routine, the BEFORE UPDATE guard SUPERSEDES the trigger-written trace
--      when trace_id is repointed: T1 "the step run was created" is sealed and superseded_by T2
--      "the step was executed with these gates". Two linked ledger entries, not a duplicate — and
--      it is the first path in this database that makes superseded_by fire at all.
--
--   C. THE INSERT-SIDE HOLE ON founder_command. a00_founder_command_trace_guard becomes BEFORE
--      INSERT OR UPDATE. On INSERT the only trace-less state permitted is 'received'. The
--      received -> interpreting exemption on UPDATE is kept, because that is the transition the
--      router makes IN ORDER to open the trace. No other exemption.
--
--   D. SEALED MEANS SEALED. A CHECK constraint makes status='sealed' and sealed_at NOT NULL
--      agree in both directions, and fn_phase_c_trace_write — which is where the three bad rows
--      came from, because it inserted the caller's status and never the timestamp — now stamps
--      sealed_at itself. The 3 existing rows are repaired from their OWN created_at and carry an
--      evidence_ref saying so. A backfilled seal is labelled a backfill; no plausible time is
--      invented and no backfill is presented as contemporaneous.
--
--   E. THE 10 ORPHAN TRACES ARE NOT DELETED. They are the evidence of the defect. The 3 whose task
--      exists get their reverse link backfilled from the task that names them. The 7 true orphans
--      get an evidence_ref stating that no task ever carried this trace and why, and are sealed.
--      They are excluded from coverage numerators BY KIND: fn_kernel_trace_integrity() reports
--      orphan_traces_task as its own numerator over the full trace table, so they are counted in
--      the open, not filtered out of it.
--
--   F. fn_kernel_trace_integrity() — every check numerator AND denominator over the FULL table.
--      No check has a population filter. The invariant that read "0 of 1" did so because its FROM
--      carried `where state='completed'`; the seven failing rows were outside the only check that
--      could have seen them. Here the denominator is every row of the kind, always.
--
--   G. TRACE-SYSTEM-EXECUTION is measured, not weakened. The gap stays visible.
--
-- ONE FREEZE IS DELIBERATELY OPENED. 7 of the 10 orphan traces and all 3 sealed-status rows that
-- need annotating are protected by z10_phase_c_trace_append_only. The repair block drops that
-- trigger, makes the annotations, and recreates it in the same transaction — the K1 change-request
-- protocol. The drop stays in this file as the permanent record that the freeze was opened.
--
-- 16 trace rows leave this migration carrying an evidence_ref keyed 'k6_backfill' — 3 sealed_at
-- stamps, 3 reverse links, 7 orphan annotations, 3 reconstructed step traces. That is disclosed,
-- not hidden: fn_kernel_trace_integrity() reports the count as its own row.
--
-- WHAT fn_kernel_trace_integrity() RETURNS IMMEDIATELY AFTER THIS FILE IS APPLIED, measured in an
-- aborted production transaction on 17 Aug 2026. Six checks are RED and none of them is tuned:
--
--   FAIL orphan_traces_task ............................ 7 of 75   (E: preserved on purpose)
--   FAIL system_execution_components_with_no_trace ..... 609 of 656 (G: the real gap)
--   FAIL traces_written_under_trace_system_execution ... 0 of 75    (G: the real gap)
--   FAIL terminal_objects_with_open_trace_handoff_run .. 1 of 1     (the K4 pointer defect)
--   FAIL trace_state_disagrees_with_subject_handoff_run  1 of 1     (the K4 pointer defect)
--   FAIL trace_state_disagrees_with_subject_workflow_run 4 of 8     (the K4 pointer defect)
--
--   ok   active_objects_without_trace_*  0 of 8 / 8 / 8 / 32 / 1 — all five kinds, open objects
--        included; step_run was 3 of 8 before this file
--   ok   terminal_objects_with_open_trace_founder_command / step_run / task / workflow_run  0
--   ok   traces_sealed_with_no_sealed_at  0 of 75 — was 3 of 72
--   ok   completed_traces_still_mutable   0 of 75
--   ok   orphan_traces_founder_command / workflow_run / step_run  0 of 75
--
-- NOTHING IN PHASE A OR PHASE B IS READ FOR WRITING. No department, role, overlay, workflow, step,
-- state, rule, gate, handoff or founder boundary is modified by this file.
--
-- Rollback: scripts/sql/rollback/kernel_k6_trace_ledger.rollback.sql
-- Rehearsal: scripts/sql/kernel_k6_trace_ledger.REHEARSAL.md
-- ============================================================================================


-- ------------------------------------------------------------------ 1. the writer stamps the seal
-- This is where the three status='sealed' / sealed_at NULL rows came from: the function inserted
-- coalesce(p_body->>'status','open') and never touched sealed_at, so every caller that asked for a
-- sealed trace got one the append-only guard would not protect. It also gains parent_trace_id,
-- because the two callers that set a parent did it with a follow-up UPDATE — and a follow-up UPDATE
-- on a row that is now correctly sealed at birth is refused by the append-only guard. The write has
-- to be complete in one statement or the guard fires on the correct behaviour.
-- CREATE OR REPLACE preserves the ACL; no REVOKE here.
create or replace function public.fn_phase_c_trace_write(p_policy text, p_body jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
end $fn$;


-- --------------------------------------------------------- 2. advance stops rewriting sealed rows
-- The supersede branch called fn_phase_c_trace_write with status 'sealed' and then issued TWO
-- follow-up UPDATEs on the row it had just written. With (1) applied, that row is sealed the
-- instant it exists, so both UPDATEs are refused by fn_phase_c_trace_append_only — a guard firing
-- on the correct behaviour. Both are folded into the write. The one surviving UPDATE sets
-- superseded_by alone on the OLD row, which is the single change the append-only guard permits.
create or replace function public.fn_phase_c_trace_advance(
  p_trace_id bigint, p_state_after text, p_seal boolean default false, p_body jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
end $fn$;


-- ==================================================== 3. THE REPAIRS, WITH THE FREEZE OPENED ONCE
-- z10_phase_c_trace_append_only refuses any UPDATE to a row whose sealed_at is set, except a
-- superseded_by-only change. 7 of the 10 orphan traces are already sealed and cannot be annotated
-- with the trigger in place. This block drops it, repairs, and recreates it — the same
-- change-request protocol K1 prescribes for org_phase_baseline. The drop is the record.
drop trigger if exists z10_phase_c_trace_append_only on public.phase_c_trace;

do $repair$
declare n_seal int; n_link int; n_orph int; n_step int; r record; v_trace bigint;
begin
  -- ---- (D) status='sealed' with sealed_at NULL --------------------------------------------
  -- The seal time is taken from the row's OWN created_at. That is a lower bound the row already
  -- carries, not a guess at when the seal was intended; the evidence_ref says exactly that, so
  -- nobody downstream can read this timestamp as a contemporaneous observation.
  update public.phase_c_trace t
     set sealed_at = t.created_at,
         evidence_refs = coalesce(t.evidence_refs,'[]'::jsonb) || jsonb_build_array(jsonb_build_object(
           'k6_backfill','sealed_at',
           'reason','This row was written status=sealed with sealed_at NULL by the pre-K6 '
                 || 'fn_phase_c_trace_write, so fn_phase_c_trace_append_only — which reads '
                 || 'sealed_at — did not protect it and the evidence was rewritable in place.',
           'sealed_at_source','this row''s own created_at',
           'not_contemporaneous','The seal time was NOT recorded when the row was sealed. This is '
                 || 'a backfilled lower bound, not an observation of when sealing happened.',
           'migration','kernel_k6_trace_ledger.sql', 'backfilled_at', now()))
   where t.status = 'sealed' and t.sealed_at is null;
  get diagnostics n_seal = row_count;

  -- ---- (E1) the orphans that are not orphans ----------------------------------------------
  -- A task exists and carries this trace_id; only the reverse link is missing. The task_id is
  -- READ from the task that names the trace — nothing is inferred and nothing is chosen.
  update public.phase_c_trace t
     set task_id = k.task_id,
         subject_ref = k.task_id::text,
         evidence_refs = coalesce(t.evidence_refs,'[]'::jsonb) || jsonb_build_array(jsonb_build_object(
           'k6_backfill','task_id_reverse_link',
           'reason','subject_kind was task with task_id NULL and subject_ref set to the task '
                 || 'IDEMPOTENCY KEY. phase_c_task ' || k.task_id || ' carries trace_id '
                 || t.trace_id || ', so the subject is known from the task side. The reverse link '
                 || 'was missing because z90_phase_c_task_trace_subject, which stamps task_id, was '
                 || 'created after this row.',
           'task_id_source','phase_c_task.trace_id = this trace_id',
           'previous_subject_ref', t.subject_ref,
           'migration','kernel_k6_trace_ledger.sql', 'backfilled_at', now()))
    from (select tr.trace_id, ta.task_id
            from public.phase_c_trace tr
            join public.phase_c_task ta on ta.trace_id = tr.trace_id
           where tr.subject_kind = 'task' and tr.task_id is null) k
   where t.trace_id = k.trace_id;
  get diagnostics n_link = row_count;

  -- ---- (E2) the true orphans --------------------------------------------------------------
  -- No task row anywhere carries this trace_id. They are NOT deleted: they are the only surviving
  -- evidence that a BEFORE INSERT trace guard wrote evidence for an insert that never landed.
  update public.phase_c_trace t
     set status = 'sealed',
         sealed_at = coalesce(t.sealed_at, t.created_at),
         evidence_refs = coalesce(t.evidence_refs,'[]'::jsonb) || jsonb_build_array(jsonb_build_object(
           'k6_backfill','orphan_trace_no_subject',
           'reason','ORPHAN. This trace was written by a00_phase_c_task_trace_guard, which was '
                 || 'BEFORE INSERT on phase_c_task, for an insert that was then discarded by the '
                 || 'phase_c_task_idem_uk conflict. The trace persisted; the task was never '
                 || 'created. No phase_c_task row carries trace_id ' || t.trace_id || '.',
           'subject_ref_is','a task idempotency key, not a task_id',
           'note','A task with this idempotency key may exist, created by an EARLIER insert; it '
                 || 'carries a different trace. This row describes an insert that did not happen.',
           'excluded_from_coverage','Counted by kind in fn_kernel_trace_integrity() as '
                 || 'orphan_traces_task. Not filtered out of any denominator.',
           'sealed_at_source', case when t.sealed_at is null then 'this row''s own created_at (backfill)'
                                    else 'unchanged' end,
           'migration','kernel_k6_trace_ledger.sql', 'backfilled_at', now()))
   where t.subject_kind = 'task' and t.task_id is null
     and not exists (select 1 from public.phase_c_task ta where ta.trace_id = t.trace_id);
  get diagnostics n_orph = row_count;

  -- ---- (B, pre-existing rows) the step runs that are active with no trace ------------------
  -- Without this they would be permanently un-updatable: the deferred constraint trigger below
  -- fires on the first UPDATE they ever receive and refuses it. The trace is RECONSTRUCTED from
  -- the step run's own row, and says so in its own evidence. It is not presented as a record of
  -- an execution nobody recorded.
  n_step := 0;
  for r in select * from public.phase_c_workflow_step_run
            where trace_id is null
              and state in ('active','completed','failed','cancelled','superseded','skipped')
            order by step_run_id loop
    v_trace := public.fn_phase_c_trace_write('TRACE-STEP', jsonb_build_object(
      'subject_kind','step_run', 'subject_ref', r.step_run_id::text,
      'run_id', r.run_id, 'step_run_id', r.step_run_id,
      'actor_role_id', r.accountable_role_id, 'reviewer_role_id', r.reviewer_role_id,
      'system_actor_id','system.workflow_engine',
      'authority_result', r.authority_result, 'gates', r.gates_evaluated,
      'input_hash', r.input_hash, 'output_hash', r.output_hash,
      'state_before','', 'state_after', r.state,
      'evidence_refs', jsonb_build_array(jsonb_build_object(
        'k6_backfill','reconstructed_step_trace',
        'reason','This step run reached state ' || r.state || ' with trace_id NULL because '
              || 'phase_c_workflow_step_run had no trigger of any kind before K6. TRACE-STEP '
              || 'declares trace_required=YES and completed_without_trace_allowed=NO, so the row '
              || 'was already out of policy when it was written.',
        'reconstructed_from','the step run row itself: run_id, step_id, accountable_role_id, '
              || 'state, input_hash, output_hash, gates_evaluated, authority_result',
        'not_contemporaneous','No trace was written when this step ran. Nothing here observes the '
              || 'execution; it records what the surviving row says about it.',
        'started_at', r.started_at, 'finished_at', r.finished_at,
        'migration','kernel_k6_trace_ledger.sql', 'backfilled_at', now())),
      'status', case when r.state = 'active' then 'open' else 'sealed' end));
    update public.phase_c_workflow_step_run set trace_id = v_trace where step_run_id = r.step_run_id;
    n_step := n_step + 1;
  end loop;

  raise notice 'K6 repairs: sealed_at backfilled=%, reverse links=%, orphans annotated=%, step traces reconstructed=%',
    n_seal, n_link, n_orph, n_step;
end $repair$;

create trigger z10_phase_c_trace_append_only
  before update on public.phase_c_trace
  for each row execute function public.fn_phase_c_trace_append_only();


-- ------------------------------------------------------------------ 4. sealed means sealed, hard
-- A biconditional, not an implication. status='sealed' without sealed_at bypasses the append-only
-- guard; sealed_at without status='sealed' presents rewritable-looking evidence that is frozen.
-- Both directions are wrong and both are refused. Measured before adding: 0 rows violate it once
-- the repairs above have run.
do $ck$
begin
  if not exists (select 1 from pg_constraint where conname = 'phase_c_trace_sealed_ck') then
    alter table public.phase_c_trace
      add constraint phase_c_trace_sealed_ck
      check ((status = 'sealed') = (sealed_at is not null));
  end if;
end $ck$;


-- ============================================================ 5. TASK: THE TRACE CANNOT BE ORPHAN
-- The INSERT branch is removed from the BEFORE trigger entirely. What is left is the UPDATE
-- behaviour, unchanged: a task may not become active or terminal with no trace, and a state change
-- advances the trace.
-- ROUTINE REMOVED 7 September 2026. public.fn_phase_c_task_trace_guard was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


drop trigger if exists a00_phase_c_task_trace_guard on public.phase_c_task;
create trigger a00_phase_c_task_trace_guard
  before update on public.phase_c_task
  for each row execute function public.fn_phase_c_task_trace_guard();

-- The AFTER INSERT writer. It runs only for a row that actually landed, so an insert discarded by
-- ON CONFLICT leaves nothing behind. subject_ref is the task_id — the idempotency key as subject_ref
-- is what made ten rows unresolvable — and task_id is set in the same statement that creates the
-- row, so there is no window in which the trace exists without naming its subject.
create or replace function public.fn_phase_c_task_trace_subject()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_parent bigint; v_trace bigint;
begin
  if new.trace_id is not null then
    -- A caller supplied the trace. Stamp the subject on it if it does not already carry one.
    update public.phase_c_trace
       set task_id = new.task_id, subject_ref = new.task_id::text
     where trace_id = new.trace_id and task_id is null and sealed_at is null;
    return null;
  end if;

  -- The root this task hangs from: its command's trace, or its workflow run's trace.
  select c.trace_id into v_parent from public.founder_command c where c.command_id = new.command_id;
  if v_parent is null then
    select r.trace_id into v_parent from public.phase_c_workflow_run r where r.run_id = new.run_id;
  end if;

  v_trace := public.fn_phase_c_trace_write('TRACE-TASK', jsonb_build_object(
    'subject_kind','task', 'subject_ref', new.task_id::text, 'task_id', new.task_id,
    'command_id', new.command_id, 'run_id', new.run_id,
    'actor_role_id', new.accountable_role_id, 'manager_role_id', new.manager_role_id,
    'system_actor_id', case when new.command_id is not null
                            then 'system.command_router' else 'system.workflow_engine' end,
    'authority_result', coalesce(new.authority_class,''),
    'reviewer_role_id', coalesce(new.reviewer_role_id,''),
    'input_hash', encode(sha256(convert_to(coalesce(new.objective,''), 'UTF8')), 'hex'),
    'evidence_refs', jsonb_build_array(jsonb_build_object(
      'idempotency_key', new.idempotency_key, 'source_kind', new.source_kind,
      'source_ref', new.source_ref)),
    'parent_trace_id', v_parent,
    'state_before','', 'state_after', coalesce(new.state,'queued'), 'status','open'));

  update public.phase_c_task set trace_id = v_trace where task_id = new.task_id;
  return null;
end $fn$;

drop trigger if exists z90_phase_c_task_trace_subject on public.phase_c_task;
create trigger z90_phase_c_task_trace_subject
  after insert on public.phase_c_task
  for each row execute function public.fn_phase_c_task_trace_subject();

-- The commit-time assertion. It re-reads the row rather than trusting the NEW snapshot, because
-- between the trigger being queued and COMMIT the trace can be deleted, the pointer can be moved,
-- or the row itself can be deleted. A row that no longer exists needs no trace; a row that does
-- exist must have one that exists and names it.
create or replace function public.fn_phase_c_task_trace_committed()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_trace bigint; v_state text; t public.phase_c_trace%rowtype;
begin
  select state, trace_id into v_state, v_trace
    from public.phase_c_task where task_id = new.task_id;
  if not found then return null; end if;          -- deleted in this transaction; nothing to assert

  if v_trace is null then
    raise exception 'phase_c_task %: committed in state % with no trace', new.task_id, v_state
      using errcode = '23514',
            hint = 'TRACE-TASK declares trace_required=YES and completed_without_trace_allowed=NO. '
                || 'The trace is written by z90_phase_c_task_trace_subject on AFTER INSERT; if it '
                || 'is missing at commit, something cleared trace_id after the row was created.';
  end if;

  select * into t from public.phase_c_trace where trace_id = v_trace;
  if not found then
    raise exception 'phase_c_task %: trace % does not exist at commit', new.task_id, v_trace
      using errcode = '23503',
            hint = 'The task points at a trace that was deleted in this transaction. Evidence is '
                || 'superseded, never removed.';
  end if;
  if t.task_id is distinct from new.task_id then
    raise exception 'phase_c_task %: trace % names task % — the ledger and the task disagree',
      new.task_id, v_trace, coalesce(t.task_id::text,'NULL')
      using errcode = '23514',
            hint = 'A trace whose task_id does not resolve is exactly the orphan class K6 exists '
                || 'to make impossible.';
  end if;
  return null;
end $fn$;

revoke all on function public.fn_phase_c_task_trace_committed() from public;
grant execute on function public.fn_phase_c_task_trace_committed() to service_role;

drop trigger if exists z95_phase_c_task_trace_committed on public.phase_c_task;
create constraint trigger z95_phase_c_task_trace_committed
  after insert or update on public.phase_c_task
  deferrable initially deferred
  for each row execute function public.fn_phase_c_task_trace_committed();


-- ==================================================== 6. STEP RUN: THE TABLE THAT HAD NO TRIGGERS
create or replace function public.fn_phase_c_step_run_trace_subject()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_parent bigint; v_trace bigint;
begin
  if new.trace_id is not null then
    update public.phase_c_trace
       set step_run_id = new.step_run_id, subject_ref = new.step_run_id::text
     where trace_id = new.trace_id and step_run_id is null and sealed_at is null;
    return null;
  end if;

  select r.trace_id into v_parent from public.phase_c_workflow_run r where r.run_id = new.run_id;

  v_trace := public.fn_phase_c_trace_write('TRACE-STEP', jsonb_build_object(
    'subject_kind','step_run', 'subject_ref', new.step_run_id::text,
    'run_id', new.run_id, 'step_run_id', new.step_run_id,
    'actor_role_id', new.accountable_role_id, 'reviewer_role_id', new.reviewer_role_id,
    'system_actor_id','system.workflow_engine',
    'authority_result', new.authority_result, 'gates', new.gates_evaluated,
    'input_hash', new.input_hash, 'output_hash', new.output_hash,
    'evidence_refs', jsonb_build_array(jsonb_build_object(
      'step_id', new.step_id, 'attempt_no', new.attempt_no,
      'idempotency_key', new.idempotency_key)),
    'parent_trace_id', v_parent,
    'state_before','', 'state_after', new.state, 'status','open'));

  update public.phase_c_workflow_step_run set trace_id = v_trace where step_run_id = new.step_run_id;
  return null;
end $fn$;

revoke all on function public.fn_phase_c_step_run_trace_subject() from public;
grant execute on function public.fn_phase_c_step_run_trace_subject() to service_role;

drop trigger if exists z90_phase_c_step_run_trace_subject on public.phase_c_workflow_step_run;
create trigger z90_phase_c_step_run_trace_subject
  after insert on public.phase_c_workflow_step_run
  for each row execute function public.fn_phase_c_step_run_trace_subject();

-- BEFORE UPDATE. Three jobs, in order:
--   1. refuse active-or-terminal with no trace;
--   2. when the pointer is REPOINTED (fn_phase_c_step_advance writes its own rich TRACE-STEP row
--      and moves trace_id onto it), seal the trace being left behind and record the supersession,
--      so the ledger keeps both entries linked instead of stranding the first;
--   3. advance the trace on a state change.
-- ROUTINE REMOVED 7 September 2026. public.fn_phase_c_step_run_trace_guard was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


revoke all on function public.fn_phase_c_step_run_trace_guard() from public;
grant execute on function public.fn_phase_c_step_run_trace_guard() to service_role;

drop trigger if exists a00_phase_c_step_run_trace_guard on public.phase_c_workflow_step_run;
create trigger a00_phase_c_step_run_trace_guard
  before update on public.phase_c_workflow_step_run
  for each row execute function public.fn_phase_c_step_run_trace_guard();

create or replace function public.fn_phase_c_step_run_trace_committed()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_trace bigint; v_state text;
begin
  select state, trace_id into v_state, v_trace
    from public.phase_c_workflow_step_run where step_run_id = new.step_run_id;
  if not found then return null; end if;

  if v_state not in ('active','waiting_review','waiting_input','blocked',
                     'completed','failed','cancelled','superseded','skipped') then
    return null;                          -- not_ready / ready: the step has not started
  end if;

  if v_trace is null then
    raise exception 'phase_c_workflow_step_run %: committed in state % with no trace',
      new.step_run_id, v_state using errcode = '23514',
      hint = 'TRACE-STEP declares trace_required=YES and completed_without_trace_allowed=NO. The '
          || 'trace is written by z90_phase_c_step_run_trace_subject on AFTER INSERT.';
  end if;
  if not exists (select 1 from public.phase_c_trace where trace_id = v_trace) then
    raise exception 'phase_c_workflow_step_run %: trace % does not exist at commit',
      new.step_run_id, v_trace using errcode = '23503',
      hint = 'Evidence is superseded, never removed.';
  end if;
  return null;
end $fn$;

revoke all on function public.fn_phase_c_step_run_trace_committed() from public;
grant execute on function public.fn_phase_c_step_run_trace_committed() to service_role;

drop trigger if exists z95_phase_c_step_run_trace_committed on public.phase_c_workflow_step_run;
create constraint trigger z95_phase_c_step_run_trace_committed
  after insert or update on public.phase_c_workflow_step_run
  deferrable initially deferred
  for each row execute function public.fn_phase_c_step_run_trace_committed();


-- ============================================= 7. FOUNDER COMMAND: THE INSERT SIDE OF THE GUARD
create or replace function public.fn_founder_command_trace_guard()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare t public.phase_c_trace%rowtype;
begin
  if tg_op = 'INSERT' then
    -- A command is BORN at 'received'. That is the only state a row may be created in with no
    -- trace, because the trace is opened by the router on the next statement. Creating one at a
    -- LATER state with a null trace was how a command became invisible to both command trace
    -- checks: commands_ahead_of_their_trace uses an INNER JOIN, which drops a null trace_id.
    if new.trace_id is null then
      if new.state <> 'received' then
        raise exception
          'founder_command: cannot be created at state % with no trace; only received is trace-less at birth',
          new.state using errcode = '23514',
          hint = 'Insert the command at received and transition it, or supply the root trace on '
              || 'the insert. TRACE-FOUNDER-COMMAND declares trace_required=YES.';
      end if;
      return new;
    end if;
    select * into t from public.phase_c_trace where trace_id = new.trace_id;
    if not found then
      raise exception 'founder_command: root trace % does not exist', new.trace_id
        using errcode = '23503';
    end if;
    return new;
  end if;

  if new.state is not distinct from old.state then return new; end if;
  if new.state = 'received' then return new; end if;

  -- received -> interpreting is the one move that legitimately precedes the trace: it is the
  -- transition the router makes in order to open the trace, in the same transaction, on the very
  -- next statement. Requiring the trace here would make it impossible to ever write one. Every
  -- state after that must have it, which is what the assertion below enforces.
  if old.state = 'received' and new.state = 'interpreting' and new.trace_id is null then
    return new;
  end if;

  if new.trace_id is null then
    raise exception 'founder_command %: cannot leave % without a root trace', new.command_id, old.state
      using errcode = '23514';
  end if;
  select * into t from public.phase_c_trace where trace_id = new.trace_id;
  if not found then
    raise exception 'founder_command %: root trace % does not exist', new.command_id, new.trace_id
      using errcode = '23503';
  end if;

  -- Advance the root so the two can never disagree, then assert it. The assertion is not
  -- decoration: if a future path sets state without going through this trigger, it fails here
  -- rather than shipping a command whose evidence describes a different moment.
  perform public.fn_phase_c_trace_advance(
    new.trace_id, new.state,
    new.state in ('completed','failed','cancelled','refused','superseded'),
    jsonb_build_object('evidence_refs', jsonb_build_array(
      jsonb_build_object('command_transition', old.state || ' -> ' || new.state, 'at', now()))));

  select * into t from public.phase_c_trace where trace_id = new.trace_id;
  if t.state_after is distinct from new.state then
    raise exception 'founder_command %: state % but root trace % still says %',
      new.command_id, new.state, new.trace_id, t.state_after using errcode = '23514';
  end if;
  return new;
end $fn$;

drop trigger if exists a00_founder_command_trace_guard on public.founder_command;
create trigger a00_founder_command_trace_guard
  before insert or update on public.founder_command
  for each row execute function public.fn_founder_command_trace_guard();


-- ================================================================== 8. THE INVARIANT THAT WATCHES
-- Every numerator is a `filter (where ...)` and every denominator is `count(*)` over the WHOLE
-- table for that kind. No check has a population filter in its FROM. The check that read "0 of 1"
-- did so because its FROM said `where state = 'completed'`; the seven rows it should have caught
-- were not in its population at all. A denominator that can only ever contain passing rows is not
-- a denominator.
-- ROUTINE REMOVED 7 September 2026. public.fn_kernel_trace_integrity was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


revoke all on function public.fn_kernel_trace_integrity() from public;
grant execute on function public.fn_kernel_trace_integrity() to service_role;
