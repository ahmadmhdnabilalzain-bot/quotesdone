-- ============================================================================================
-- ROLLBACK FOR KERNEL K3 — THE CANONICAL STEP ENGINE
--
-- Undoes scripts/sql/kernel_k3_step_engine.sql AND scripts/sql/kernel_k3b_graph_validation.sql.
-- Apply this file as a whole; it is ordered so nothing is dropped while something still calls it.
--
-- K3 replaced two live routines. This file carries their PRE-K3 bodies VERBATIM, read out of
-- pg_get_functiondef on htdblwldjkcgjvmqkbeh on 16 Aug 2026 before K3 was rehearsed:
--   fn_kernel_event_consume(bigint)     restored to the phase_b_handoff fan-out
--   fn_phase_c_task_trace_guard()       restored to the version with no supersede-on-repoint
-- CREATE OR REPLACE preserves the ACL on both, so there is no grant or revoke here.
--
-- WHAT ROLLING BACK COSTS, stated plainly so the decision is made with the price visible:
--   * Nothing will close a workflow run again. The estate returns to 0 completed runs.
--   * Event delivery becomes a second creator of business work again, and it will hand a
--     receiving owner a task they never accepted.
--   * The 66 same-owner successors are reported as 'no_edge_for_declared_successor' and no step
--     run is opened for any of them.
--   * phase_c_workflow_run and phase_c_handoff_run stop advancing their traces on a state change.
--     Rows written while K3 was live keep their correct traces; new ones drift again.
--   * Any run left mid-flight by K3 stays where it is. This file DELETES NOTHING: no run, no step
--     run, no task, no handoff, no trace and no outbox row is removed. Evidence is superseded,
--     never removed, and a rollback that erased the record of what ran would be worse than the
--     defect it is rolling back.
--
-- The one row class this file does drop is phase_c_step_completion, K3's own idempotency ledger,
-- which has no meaning without fn_kernel_step_complete. If you intend to re-apply K3 later,
-- comment out the DROP TABLE: keeping it makes a replay after re-apply return the original result
-- instead of re-running the step.
-- ============================================================================================

-- ---- 1. the triggers K3 added ---------------------------------------------------------------
drop trigger if exists a00_kernel_workflow_run_trace_guard on public.phase_c_workflow_run;
drop trigger if exists a00_kernel_handoff_run_trace_guard  on public.phase_c_handoff_run;
drop function if exists public.fn_kernel_workflow_run_trace_guard();
drop function if exists public.fn_kernel_handoff_run_trace_guard();

-- ---- 2. K3b ----------------------------------------------------------------------------------
drop function if exists public.fn_kernel_workflow_graph_validate();

-- ---- 3. the engine, callers before callees ---------------------------------------------------
drop function if exists public.fn_kernel_step_complete(jsonb);
drop function if exists public.fn_kernel_handoff_accept(jsonb);
drop function if exists public.fn_kernel_open_step(jsonb);

-- ---- 4. fn_kernel_event_consume, restored to its PRE-K3 body ---------------------------------
-- This is the version that derives successors from phase_b_handoff during delivery. It is the
-- defect K3 exists to remove; it is restored here exactly as it was so a rollback is a rollback
-- and not a third variant nobody has ever run.
create or replace function public.fn_kernel_event_consume(p_outbox_id bigint)
returns table(handled boolean, downstream_ref text, result jsonb, reason text)
language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare
  o public.phase_c_event_outbox%rowtype;
  e public.phase_b_event%rowtype;
  v_next record; v_tasks bigint[] := '{}'; v_task bigint; v_owner text;
  v_run bigint; v_step text; v_prior text;
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

    -- A row naming a command must be for a workflow that command actually selected. Three
    -- pre-fix rows announcing EV-W01-STARTED for W20 commands put three marketing orders in
    -- front of the CEO before the quarantine reached them.
    elsif coalesce(o.command_id::text, o.payload->>'command_id') is not null
      and not exists (select 1 from public.founder_command_workflow_link l
                       where l.command_id = coalesce(o.command_id, (o.payload->>'command_id')::bigint)
                         and l.workflow_id = o.workflow_id) then
      v_reason := format('event %s names workflow %s but command %s selected a different workflow',
                         o.event_id, o.workflow_id, coalesce(o.command_id::text, o.payload->>'command_id'));

    elsif e.event_name like '%.started' then
      -- THE WHOLE POINT. workflow.started is a RECORD of a run that fn_kernel_workflow_start
      -- already created in its own transaction. There is nothing to create here.
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

    elsif e.event_name like '%.completed' and (o.step_run_id is not null or o.payload ? 'step_id') then
      v_run  := coalesce(o.workflow_run_id, nullif(o.payload->>'run_id','')::bigint);
      v_step := coalesce(o.payload->>'step_id',
                         (select step_id from public.phase_c_workflow_step_run
                           where step_run_id = o.step_run_id));
      if v_run is null or v_step is null then
        v_reason := format('completed event %s carries no run (%s) or no step (%s)',
                           o.event_id, coalesce(v_run::text,'null'), coalesce(v_step,'null'));
      else
        -- Fan out to the subscribers the frozen registry declares. This creates TASKS on an
        -- existing run; it does not create a run, and it never calls the producer.
        for v_next in
          select h.to_step_id, s.accountable_role_id, s.independent_reviewer_role_id
            from public.phase_b_handoff h
            join public.phase_b_workflow_step s on s.step_id = h.to_step_id
           where h.from_step_id = v_step
           order by h.to_step_id
        loop
          select role_id into v_owner from public.fn_phase_c_resolve_actor(v_next.accountable_role_id);
          continue when v_owner is null or not public.fn_phase_c_actor_may_own(v_owner);
          v_task := public.fn_phase_c_task_create(jsonb_build_object(
            'source_kind','workflow_event', 'source_ref', o.event_id || ':' || v_next.to_step_id,
            'command_id', o.command_id, 'run_id', v_run,
            'workflow_id', e.workflow_id, 'step_id', v_next.to_step_id,
            'accountable_role_id', v_owner,
            'objective', format('%s completed; %s is now yours for run %s.', v_step, v_next.to_step_id, v_run),
            'requested_output','The step output required by the frozen Phase B contract, with evidence.',
            'reviewer_required', (coalesce(v_next.independent_reviewer_role_id,'') <> ''),
            'reviewer_role_id', coalesce(v_next.independent_reviewer_role_id,''),
            'idempotency_key', 'run:' || v_run || ':step:' || v_next.to_step_id));
          v_tasks := v_tasks || v_task;
        end loop;
        v_handled := true;
        if cardinality(v_tasks) = 0 then
          -- 66 steps declare next_step_if_pass and carry no handoff edge. Saying "terminal" over
          -- one of those is how the chain stops silently, so the two cases are NAMED apart.
          v_ref := case when exists (select 1 from public.phase_b_workflow_step s
                                      where s.step_id = v_step and s.next_step_if_pass = 'WORKFLOW_COMPLETE')
                        then 'terminal_step:' || v_step
                        else 'no_edge_for_declared_successor:' || v_step end;
          v_result := jsonb_build_object('successors', 0, 'run_id', v_run,
                        'declared_successor', (select next_step_if_pass from public.phase_b_workflow_step
                                                where step_id = v_step));
        else
          v_ref := 'tasks:' || array_to_string(v_tasks, ',');
          v_result := jsonb_build_object('tasks', to_jsonb(v_tasks), 'run_id', v_run);
        end if;
      end if;

    else
      v_reason := format('no canonical consumer for %s (%s)', o.event_id, e.event_name);
    end if;
  end if;

  perform set_config('kernel.in_delivery', v_prior, true);
  return query select v_handled, v_ref, v_result, v_reason;
end $fn$;

-- ---- 5. fn_phase_c_task_trace_guard, restored to its PRE-K3 body -----------------------------
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
  if new.state is distinct from old.state and new.trace_id is not null then
    perform public.fn_phase_c_trace_advance(
      new.trace_id, new.state,
      new.state in ('completed','failed','cancelled','superseded'),
      jsonb_build_object('evidence_refs', jsonb_build_array(
        jsonb_build_object('transition', old.state || ' -> ' || new.state, 'at', now()))));
  end if;
  return new;
end $fn$;

-- ---- 6. the classifier, last: K3b and the engine both called it -------------------------------
drop function if exists public.fn_kernel_step_successor(text);

-- ---- 7. the idempotency ledger ---------------------------------------------------------------
-- Comment this out if K3 will be re-applied and you want replays to keep returning their original
-- results. It holds no business state of its own; every row it references survives.
drop table if exists public.phase_c_step_completion;
