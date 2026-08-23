-- J02 — cancelling one workflow run was refused by the state model of a command nobody named
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh. Two Phase D drives of W01 inside one scenario
-- produced runs 47357 and 47358 under founder command 12773. The failure path was driven on the
-- first, which moved the COMMAND to 'failed'. fn_kernel_cancel on the SECOND run -- state
-- 'active', and phase_b_workflow_transition declares active -> cancelled -- returned:
--
--   {"ok": false, "from": "failed", "to": "cancelled", "error": "transition_not_permitted",
--    "message": "The command state model does not allow this move. Nothing was cancelled."}
--
-- and run 47358 was still active afterwards. phase_c_command_transition has no failed -> cancelled
-- and is right not to: a failed command is not cancelled. But the caller asked to cancel a
-- workflow run, and the command was derived inside this routine. The refusal was correct about a
-- subject nobody asked about, and it abandoned the one that was asked about.
--
-- The same derivation made the sweep too WIDE in the other direction: sections (e) tasks, (g)
-- outbox and (h) traces matched on command_id, so cancelling one run of a command closed the
-- derived work of its sibling runs while sections (c), (d) and (f) left those runs open. An active
-- run with cancelled tasks underneath it is not a state the kernel should be able to produce.
--
-- Both are the same root cause: one identifier was doing two jobs. v_command is now the command
-- the subject BELONGS to, reported and never acted on unless entitled; v_cmd is the command this
-- call may close and sweep, and it is set only when the founder named the command, or when the
-- named run is the command's LAST open run and the command's own model permits the move. Where it
-- is not set the run is still cancelled and the report carries command_closed=false with the
-- reason in command_note, instead of a refusal for something the caller never asked for.
--
-- Behaviour for subject_kind = 'founder_command' is unchanged, including the early refusal when
-- the command's state model forbids the move: there the command IS the subject.
--
-- ROLLBACK: re-apply the previous body of fn_kernel_cancel. No DDL, no grants: CREATE OR REPLACE
-- preserves the ACL.
--
-- GENERATED from the live body by scripts/tmp_diag/gen_j02.mjs.
CREATE OR REPLACE FUNCTION public.fn_kernel_cancel(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_kind     text := coalesce(p_input->>'subject_kind', '');
  v_ref      text := coalesce(p_input->>'subject_ref', '');
  v_op       text := coalesce(nullif(p_input->>'op',''), 'cancel');
  v_reason   text := coalesce(nullif(btrim(p_input->>'reason'),''), '');
  v_actor    text := coalesce(p_input->>'actor', '');
  v_terminal text;
  v_command  bigint;
  -- WHOSE STATE MODEL IS BEING ASKED. v_command is the command the subject BELONGS to; v_cmd is
  -- the command this call is entitled to close. They are the same when the founder named the
  -- command, and they differ when the caller named one workflow run.
  v_cmd      bigint;
  v_cmd_note text;
  v_runs     bigint[] := '{}';
  v_founder  text;
  r          record;
  v_trace    bigint;
  n_cmd int := 0; n_plan int := 0; n_run int := 0; n_step int := 0;
  n_task int := 0; n_handoff int := 0; n_outbox int := 0; n_trace int := 0;
  v_left_tasks int; v_left_runs int; v_left_steps int; v_left_handoffs int; v_left_outbox int;
begin
  if v_op not in ('cancel','supersede') then
    raise exception 'fn_kernel_cancel: op must be cancel or supersede, got %', v_op using errcode = '22023';
  end if;
  v_terminal := case when v_op = 'cancel' then 'cancelled' else 'superseded' end;

  -- A cancellation with no stated reason is an unexplained disappearance in the audit trail.
  if v_reason = '' then
    raise exception 'fn_kernel_cancel: a reason is required' using errcode = '23514';
  end if;

  -- ---- resolve the subject ------------------------------------------------------------------
  if v_kind = 'founder_command' then
    -- Only the founder may cancel his own instruction. K0 put the one verifier in the estate;
    -- this is the second caller of it, not a second copy of it.
    v_founder := public.fn_phase_c_require_founder(v_actor);
    v_command := nullif(regexp_replace(v_ref, '\D', '', 'g'), '')::bigint;
    if v_command is null or not exists (select 1 from public.founder_command where command_id = v_command) then
      return jsonb_build_object('ok', false, 'error', 'not_found', 'subject_ref', v_ref);
    end if;
    select coalesce(array_agg(run_id), '{}') into v_runs
      from public.phase_c_workflow_run where command_id = v_command;

  elsif v_kind = 'workflow_run' then
    -- An autonomous run has no founder in the loop; the actor is recorded, not authenticated as
    -- the founder, because requiring a founder here would make autonomous cleanup impossible.
    v_runs := array[nullif(regexp_replace(v_ref, '\D', '', 'g'), '')::bigint];
    if v_runs[1] is null or not exists (select 1 from public.phase_c_workflow_run where run_id = v_runs[1]) then
      return jsonb_build_object('ok', false, 'error', 'not_found', 'subject_ref', v_ref);
    end if;
    select command_id into v_command from public.phase_c_workflow_run where run_id = v_runs[1];

  else
    raise exception 'fn_kernel_cancel: subject_kind must be founder_command or workflow_run, got %',
      v_kind using errcode = '22023';
  end if;

  -- ---- CAN THIS CALL CLOSE THE COMMAND, AND MUST IT? ---------------------------------------
  -- MEASURED 23 Aug 2026. Driving W01 twice inside one Phase D scenario gives two runs under one
  -- founder command. Failing the first run moves the COMMAND to 'failed'. Cancelling the second
  -- run -- state 'active', and active -> cancelled is declared in phase_b_workflow_transition --
  -- then came back:
  --
  --   {"ok": false, "from": "failed", "to": "cancelled", "error": "transition_not_permitted",
  --    "message": "The command state model does not allow this move. Nothing was cancelled."}
  --
  -- and the run was still active. The caller named a WORKFLOW RUN. The command was derived here,
  -- the command's own model was consulted, and the run's cancellation was abandoned on the
  -- strength of it. That is a guard firing on a subject nobody asked about: the founder's command
  -- is not being cancelled and has no business refusing.
  --
  -- The same derivation made the sweep too wide in the other direction. Sections (e), (g) and (h)
  -- matched derived work on command_id, so cancelling ONE run of a command cancelled the tasks,
  -- outbox rows and traces of its SIBLING runs, while sections (c), (d) and (f) correctly left
  -- those runs themselves alone -- an active run with cancelled tasks underneath it.
  --
  -- So: the command is closed, and its derived work swept, only when this call is entitled to do
  -- it. Naming the command is entitlement. Naming a run is entitlement only when it is the last
  -- open run of that command AND the command's own state model permits the move. Where it is not,
  -- the run is still cancelled -- that was always the thing asked for -- and the report says in
  -- one field what happened to the command instead of returning a refusal for it.
  if v_kind = 'founder_command' then
    v_cmd := v_command;
  elsif v_command is not null then
    if exists (select 1 from public.phase_c_workflow_run
                where command_id = v_command and not (run_id = any(v_runs))
                  and state not in ('cancelled','superseded','completed','failed')) then
      v_cmd_note := 'another workflow run of this command is still open, so the command was left as it is';
    elsif exists (select 1 from public.founder_command
                   where command_id = v_command and state not in ('cancelled','superseded','completed'))
      and not exists (select 1 from public.phase_c_command_transition t
                       join public.founder_command c on c.command_id = v_command
                      where t.from_state = c.state and t.to_state = v_terminal) then
      v_cmd_note := format('the command is %s and the command state model declares no %s -> %s, so the command was left as it is',
        (select state from public.founder_command where command_id = v_command),
        (select state from public.founder_command where command_id = v_command), v_terminal);
    else
      v_cmd := v_command;
    end if;
  end if;

  -- ---- (a) the command --------------------------------------------------------------------
  if v_cmd is not null then
    if exists (select 1 from public.founder_command
                where command_id = v_cmd and state not in ('cancelled','superseded','completed')) then
      if not exists (select 1 from public.phase_c_command_transition t
                      join public.founder_command c on c.command_id = v_cmd
                     where t.from_state = c.state and t.to_state = v_terminal) then
        return jsonb_build_object('ok', false, 'error', 'transition_not_permitted',
          'from', (select state from public.founder_command where command_id = v_cmd),
          'to', v_terminal,
          'message', 'The command state model does not allow this move. Nothing was cancelled.');
      end if;
      update public.founder_command
         set state = v_terminal,
             superseded_by = case when v_op = 'supersede'
                                  then nullif(regexp_replace(coalesce(p_input->>'superseded_by',''), '\D','','g'),'')::bigint
                                  else superseded_by end,
             closed_at = now()
       where command_id = v_cmd;
      n_cmd := 1;
    end if;

    -- ---- (b) the command plan --------------------------------------------------------------
    update public.founder_command_plan
       set state = v_terminal, closed_at = now()
     where command_id = v_cmd and state = 'active';
    get diagnostics n_plan = row_count;
  end if;

  -- ---- (c) the workflow runs --------------------------------------------------------------
  for r in select * from public.phase_c_workflow_run
            where run_id = any(v_runs)
              and state not in ('cancelled','superseded','completed','failed') loop
    v_trace := public.fn_phase_c_trace_write('TRACE-WORKFLOW', jsonb_build_object(
      'subject_kind','workflow_run', 'subject_ref', r.run_id::text, 'run_id', r.run_id,
      'command_id', r.command_id, 'actor_role_id', coalesce(nullif(v_founder,''),'system'),
      'system_actor_id','system.workflow_engine',
      'state_before', r.state, 'state_after', v_terminal,
      'evidence_refs', jsonb_build_array(jsonb_build_object('reason', v_reason, 'actor', v_actor)),
      'status','sealed'));
    update public.phase_c_workflow_run
       set state = v_terminal, closed_at = now(),
           closure_evidence = coalesce(closure_evidence,'{}'::jsonb)
             || jsonb_build_object('cancelled_reason', v_reason, 'cancelled_by', v_actor,
                                   'cancelled_at', now(), 'trace_id', v_trace)
     where run_id = r.run_id;
    n_run := n_run + 1;
  end loop;

  -- ---- (d) the open step runs -------------------------------------------------------------
  for r in select * from public.phase_c_workflow_step_run
            where run_id = any(v_runs)
              and state not in ('cancelled','completed','failed','superseded') loop
    v_trace := public.fn_phase_c_trace_write('TRACE-STEP', jsonb_build_object(
      'subject_kind','step_run', 'subject_ref', r.step_run_id::text,
      'run_id', r.run_id, 'step_run_id', r.step_run_id,
      'actor_role_id', r.accountable_role_id, 'system_actor_id','system.workflow_engine',
      'state_before', r.state, 'state_after', v_terminal,
      'evidence_refs', jsonb_build_array(jsonb_build_object('reason', v_reason, 'actor', v_actor)),
      'status','sealed'));
    update public.phase_c_workflow_step_run
       set state = v_terminal, finished_at = now(), trace_id = coalesce(trace_id, v_trace),
           failure_reason = case when failure_reason = '' then 'cancelled: ' || v_reason else failure_reason end
     where step_run_id = r.step_run_id;
    n_step := n_step + 1;
  end loop;

  -- ---- (e) the tasks, BY COMMAND AND BY RUN ------------------------------------------------
  -- The old sweep matched on command_id alone. Task 794 carries command_id NULL and run_id 96, which
  -- is exactly how it survived its own command's cancellation.
  for r in select * from public.phase_c_task
            where ((v_cmd is not null and command_id = v_cmd) or run_id = any(v_runs))
              and state in ('queued','assigned','accepted','in_progress','blocked') loop
    v_trace := public.fn_phase_c_trace_write('TRACE-TASK', jsonb_build_object(
      'subject_kind','task', 'subject_ref', r.task_id::text, 'task_id', r.task_id,
      'command_id', r.command_id, 'run_id', r.run_id,
      'actor_role_id', coalesce(nullif(v_founder,''),'system'),
      'manager_role_id', r.manager_role_id, 'system_actor_id','system.command_router',
      'state_before', r.state, 'state_after', v_terminal,
      'evidence_refs', jsonb_build_array(jsonb_build_object('reason', v_reason, 'actor', v_actor)),
      'status','sealed'));
    update public.phase_c_task
       set state = v_terminal, closed_at = now(), trace_id = v_trace
     where task_id = r.task_id;
    n_task := n_task + 1;
  end loop;

  -- ---- (f) the pending handoffs ------------------------------------------------------------
  for r in select * from public.phase_c_handoff_run
            where run_id = any(v_runs) and status = 'open' loop
    v_trace := public.fn_phase_c_trace_write('TRACE-HANDOFF', jsonb_build_object(
      'subject_kind','handoff_run', 'subject_ref', r.handoff_run_id::text, 'run_id', r.run_id,
      'actor_role_id', r.sending_role_id, 'system_actor_id','system.workflow_engine',
      'state_before', r.status, 'state_after','cancelled',
      'evidence_refs', jsonb_build_array(jsonb_build_object('reason', v_reason, 'actor', v_actor)),
      'status','sealed'));
    update public.phase_c_handoff_run
       set status = 'cancelled', decided_at = now(), trace_id = coalesce(trace_id, v_trace)
     where handoff_run_id = r.handoff_run_id;
    n_handoff := n_handoff + 1;
  end loop;

  -- ---- (g) the undelivered outbox rows -----------------------------------------------------
  -- Delivered rows are NOT touched: a delivered event is a fact that happened, and rewriting it
  -- would be falsifying history. Only what has not yet left the queue is stopped.
  -- ROOT CAUSE 2. This matched on payload->>'run_id'. Only ONE producer writes that key: the
  -- step-complete event. The workflow-START event writes 'workflow_run_id', so every start event
  -- survived cancellation as 'pending' and was delivered afterwards. The leftover check below used
  -- the SAME predicate as this write, so it counted nothing left behind and the function reported
  -- success. Relationships are columns now, and the check reads the same columns this writes.
  update public.phase_c_event_outbox o
     set status = 'superseded',
         last_error = 'CANCELLED ' || to_char(now(),'YYYY-MM-DD') || ': ' || v_reason
                   || ' (fn_kernel_cancel, subject ' || v_kind || ':' || v_ref || ')'
   where o.status in ('pending','claimed','retry_wait')
     and ( (v_cmd is not null and o.command_id = v_cmd)
        or o.workflow_run_id = any(v_runs)
        or o.step_run_id in (select sr.step_run_id from public.phase_c_workflow_step_run sr
                              where sr.run_id = any(v_runs))
        or o.task_id in (select t.task_id from public.phase_c_task t
                          where (v_cmd is not null and t.command_id = v_cmd)
                             or t.run_id = any(v_runs)) );
  get diagnostics n_outbox = row_count;

  -- ---- (h) seal every open trace whose subject was just closed -----------------------------
  update public.phase_c_trace
     set status = 'sealed', sealed_at = now()
   where sealed_at is null
     and ( (v_cmd is not null and command_id = v_cmd)
        or run_id = any(v_runs)
        or task_id in (select task_id from public.phase_c_task
                        where (v_cmd is not null and command_id = v_cmd)
                           or run_id = any(v_runs)) );
  get diagnostics n_trace = row_count;

  -- ---- (i) THE POSTCONDITION ---------------------------------------------------------------
  -- "A cancelled command may leave no queued derived work." Asserted, not asserted about.
  select count(*) into v_left_tasks from public.phase_c_task
   where ((v_cmd is not null and command_id = v_cmd) or run_id = any(v_runs))
     and state in ('queued','assigned','accepted','in_progress','blocked');
  select count(*) into v_left_runs from public.phase_c_workflow_run
   where run_id = any(v_runs) and state not in ('cancelled','superseded','completed','failed');
  select count(*) into v_left_steps from public.phase_c_workflow_step_run
   where run_id = any(v_runs) and state not in ('cancelled','completed','failed','superseded');
  select count(*) into v_left_handoffs from public.phase_c_handoff_run
   where run_id = any(v_runs) and status = 'open';
  select count(*) into v_left_outbox from public.phase_c_event_outbox o
   where o.status in ('pending','claimed','retry_wait')
     and ( (v_cmd is not null and o.command_id = v_cmd)
        or o.workflow_run_id = any(v_runs)
        or o.step_run_id in (select sr.step_run_id from public.phase_c_workflow_step_run sr
                              where sr.run_id = any(v_runs))
        or o.task_id in (select t.task_id from public.phase_c_task t
                          where (v_cmd is not null and t.command_id = v_cmd)
                             or t.run_id = any(v_runs)) );

  if v_left_tasks + v_left_runs + v_left_steps + v_left_handoffs + v_left_outbox > 0 then
    raise exception
      'fn_kernel_cancel left derived work behind: tasks=% runs=% steps=% handoffs=% outbox=%',
      v_left_tasks, v_left_runs, v_left_steps, v_left_handoffs, v_left_outbox
      using errcode = '23514',
            hint = 'The propagation missed a table. Nothing was cancelled — the transaction is rolled back.';
  end if;

  return jsonb_build_object('ok', true, 'op', v_op, 'subject_kind', v_kind, 'subject_ref', v_ref,
    'command_id', v_command, 'command_closed', (v_cmd is not null),
    'command_note', v_cmd_note, 'run_ids', to_jsonb(v_runs), 'actor', v_actor, 'reason', v_reason,
    'closed', jsonb_build_object('command', n_cmd, 'plan', n_plan, 'workflow_runs', n_run,
      'step_runs', n_step, 'tasks', n_task, 'handoffs', n_handoff, 'outbox_superseded', n_outbox,
      'traces_sealed', n_trace),
    'queued_derived_work_remaining', 0);
end $function$;
