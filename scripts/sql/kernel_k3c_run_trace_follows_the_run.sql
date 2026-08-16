-- ============================================================================================
-- KERNEL K3c — THE RUN'S TRACE FOLLOWS THE RUN
--
-- Found by the completion sweep, not by the increment that caused it — the second time that has
-- happened in this rebuild, and worth recording rather than smoothing over.
--
--   fn_kernel_trace_integrity -> trace_state_disagrees_with_subject_workflow_run = 6 of 11
--
-- Four of the six are pre-kernel history that S2 has already classified as
-- HISTORICAL_STATE_TRACE_MISMATCH. TWO ARE NOT: runs 156 and 158 were created by
-- fn_kernel_workflow_start today, their root trace was written at creation with
-- state_after = 'queued', and the run then moved to 'active' when its entry step run opened —
-- with nothing advancing the trace behind it.
--
-- founder_command has had exactly this guard since K6 (a00_founder_command_trace_guard: advance the
-- trace on every state change, then ASSERT the two agree). phase_c_workflow_run never got one. A
-- rule that exists for one subject and not its sibling is how the two drift apart, so this is the
-- same guard, on the run.
--
-- Also here: outbox 388, the only dead-lettered row in the estate. It is not a delivery failure —
-- it is the kernel consumer REFUSING an event that carried no workflow_run_id, because it was
-- produced as a command by the pre-K2c clarify path rather than as a record of a run that already
-- existed. The refusal is correct and the message says so. It is superseded with that reason, not
-- deleted, and not retried into a shape it never had.
-- ============================================================================================

-- ----------------------------------------------------- 1. advance the run trace, then assert it
create or replace function public.fn_kernel_workflow_run_trace_guard()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $k3c$
declare v_state text;
begin
  if new.state is not distinct from old.state then return new; end if;

  -- No trace yet is only legal while the run is still being built inside fn_kernel_workflow_start,
  -- which writes the run row and its trace in the same statement sequence. Any later state change
  -- without a trace is the defect this guard exists for.
  if new.trace_id is null then
    raise exception
      'phase_c_workflow_run %: state % -> % with no trace', new.run_id, old.state, new.state
      using errcode = '23514',
            hint = 'fn_kernel_workflow_start writes the run trace. Nothing else may move a run.';
  end if;

  -- A SEALED trace is never edited in place; fn_phase_c_trace_advance supersedes it with a new row
  -- and links the two. The append-only guard refuses an edit and it is right to.
  new.trace_id := public.fn_phase_c_trace_advance(
    new.trace_id, new.state,
    new.state in ('completed','cancelled','superseded','failed'),
    jsonb_build_object(
      'state_before', old.state,
      'subject_kind','workflow_run', 'subject_ref', new.run_id::text, 'run_id', new.run_id,
      'command_id', new.command_id));

  select t.state_after into v_state from public.phase_c_trace t where t.trace_id = new.trace_id;
  if v_state is distinct from new.state then
    raise exception
      'phase_c_workflow_run %: the run says % and its trace says %', new.run_id, new.state, v_state
      using errcode = '23514',
            hint = 'The trace must be advanced in the same transaction as the state it records.';
  end if;
  return new;
end $k3c$;

revoke all on function public.fn_kernel_workflow_run_trace_guard() from public;

drop trigger if exists a00_kernel_workflow_run_trace_guard on public.phase_c_workflow_run;
create trigger a00_kernel_workflow_run_trace_guard
  before update on public.phase_c_workflow_run
  for each row execute function public.fn_kernel_workflow_run_trace_guard();

-- ------------------------------------------ 2. the two live runs the guard would have caught
-- Their traces are OPEN, so they are advanced in place by the same routine the guard uses. This is
-- a repair of live state, and it is labelled as one: the trace records that the advance happened
-- now, not that it happened when the run moved.
do $k3c_fix$
declare r record; v_new bigint;
begin
  for r in
    select w.run_id, w.state, w.trace_id, t.state_after
      from public.phase_c_workflow_run w
      join public.phase_c_trace t on t.trace_id = w.trace_id
     where t.state_after is distinct from w.state
       and t.sealed_at is null                    -- sealed history is superseded, never rewritten
  loop
    v_new := public.fn_phase_c_trace_advance(
      r.trace_id, r.state,
      r.state in ('completed','cancelled','superseded','failed'),
      jsonb_build_object(
      'state_before', r.state_after,
      'subject_kind','workflow_run', 'subject_ref', r.run_id::text, 'run_id', r.run_id,
      'evidence_refs', jsonb_build_array(jsonb_build_object(
        'retrofitted', true,
        'reason', 'kernel K3c: the run trace was written at creation and nothing advanced it when '
               || 'the entry step run opened. Advanced now, on 2026-08-17, NOT at the time the run '
               || 'actually moved.'))));
    update public.phase_c_workflow_run set trace_id = v_new where run_id = r.run_id;
  end loop;
end $k3c_fix$;

-- ---------------------------------------------- 3. the dead-lettered row, superseded with its why
update public.phase_c_event_outbox
   set status = 'superseded',
       last_error = 'SUPERSEDED 2026-08-17 (kernel K3c): the kernel consumer correctly REFUSED this '
                 || 'row. It carries no workflow_run_id because the pre-K2c clarify path produced '
                 || 'EV-W20-STARTED as a COMMAND to create a run rather than as a record of a run '
                 || 'that already existed. K2c moved that path onto fn_kernel_workflow_start, so no '
                 || 'further row of this shape can be produced. Retained as evidence; not retried, '
                 || 'because retrying it would ask the kernel to accept the shape it exists to '
                 || 'refuse. Original: ' || left(coalesce(last_error, ''), 400)
 where status = 'dead_letter'
   and last_error like '%carries no workflow_run_id%';
