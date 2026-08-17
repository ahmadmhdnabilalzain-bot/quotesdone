-- ROOT CAUSE 2 — THE COMMAND CENTER'S CANCEL BUTTON REACHES THE KERNEL.
--
-- The final Phase C acceptance cancelled founder command 338 through the control the OS shell
-- actually calls. The command went to 'cancelled', its one task closed, and workflow run 538 and
-- step run 531 stayed ACTIVE with two traces unsealed. fn_founder_command_control never called
-- fn_kernel_cancel at all — prosrc ~ 'fn_kernel_' was false — so a second writer of business state
-- existed for the same subject, which is the shape Phase C exists to remove.
--
-- A second defect sat inside the canonical canceller itself. Its undelivered-outbox sweep matched
-- payload->>'run_id'. Only the step-complete producer writes that key; the workflow-START producer
-- writes 'workflow_run_id'. So every start event survived cancellation as 'pending'. The sweep's
-- own leftover check used the SAME predicate as the write, so it counted zero left behind and the
-- function returned success — an assertion written with the same mistake as the thing it guards.
--
-- Three changes, in the order they have to land:
--   1. phase_c_event_outbox gains task_id, the one normalised relationship column it lacked, and
--      fn_kernel_outbox_emit populates it. command_id, workflow_run_id, step_run_id,
--      correlation_id and causation_id were already columns and already populated.
--   2. fn_kernel_cancel sweeps and re-counts on COLUMNS — command, run, step run and task — never
--      on a JSON key again.
--   3. fn_founder_command_control delegates cancel and supersede to fn_kernel_cancel, verifies the
--      founder before and lets the kernel verify again, and is idempotent on an already-terminal
--      command.
--
-- Rollback: scripts/sql/rollback/rc2_cancellation_reaches_the_kernel.rollback.sql

alter table public.phase_c_event_outbox
  add column if not exists task_id bigint;

comment on column public.phase_c_event_outbox.task_id is
  'The operational task this event is about. Added 17 Aug 2026 (root cause 2) so a cancellation can '
  'follow a column instead of a JSON key. Nullable: not every event is about a task.';

create index if not exists phase_c_event_outbox_task_id_idx
  on public.phase_c_event_outbox (task_id) where task_id is not null;

CREATE OR REPLACE FUNCTION public.fn_kernel_outbox_emit(p_input jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  e public.phase_b_event%rowtype;
  v_id bigint;
  v_event  text := nullif(btrim(coalesce(p_input->>'event_id','')), '');
  v_dedupe text := nullif(btrim(coalesce(p_input->>'dedupe_value','')), '');
  v_prod   text := coalesce(nullif(btrim(p_input->>'producer'),''), 'kernel:unnamed');
  v_corr   text := nullif(btrim(coalesce(p_input->>'correlation_id','')), '');
  v_caus   text := nullif(btrim(coalesce(p_input->>'causation_id','')), '');
  v_src    text := nullif(btrim(coalesce(p_input->>'source_id','')), '');
  v_consumer text;
begin
  select * into e from public.phase_b_event where event_id = v_event;
  if not found then
    raise exception 'fn_kernel_outbox_emit: % is not in the frozen Phase B event registry — fail closed',
      coalesce(v_event,'(null)') using errcode = '23503';
  end if;
  if v_dedupe is null then
    raise exception 'fn_kernel_outbox_emit: dedupe_value is required for %', v_event using errcode = '23502';
  end if;
  if v_corr is null or v_caus is null or v_src is null then
    raise exception 'fn_kernel_outbox_emit: % is missing identity (correlation_id=%, causation_id=%, source_id=%)',
      v_event, coalesce(v_corr,'(null)'), coalesce(v_caus,'(null)'), coalesce(v_src,'(null)')
      using errcode = '23514';
  end if;

  select role_id into v_consumer from public.fn_phase_c_resolve_actor(e.primary_consumer_role_id);
  v_consumer := coalesce(v_consumer, e.primary_consumer_role_id);

  insert into public.phase_c_event_outbox
    (event_id, workflow_id, object_version, producer, accountable_role_id, primary_consumer_role_id,
     payload, dedupe_value, status, correlation_id, causation_id, source_id,
     command_id, workflow_run_id, step_run_id, task_id, trace_id)
  values (e.event_id, e.workflow_id, coalesce((p_input->>'object_version')::bigint, 1),
          v_prod, v_consumer, coalesce(e.primary_consumer_role_id,''),
          coalesce(p_input->'payload', '{}'::jsonb), v_dedupe, 'pending',
          v_corr, v_caus, v_src,
          nullif(p_input->>'command_id','')::bigint,
          nullif(p_input->>'workflow_run_id','')::bigint,
          nullif(p_input->>'step_run_id','')::bigint,
          -- ROOT CAUSE 2. The relationship a cancellation follows must be a COLUMN. task_id was the
          -- one missing normalised link: every producer already carries it in the payload it emits,
          -- so it is read from the explicit input first and from the payload second, and never
          -- looked up from JSON again after this point.
          coalesce(nullif(p_input->>'task_id','')::bigint,
                   nullif(p_input->'payload'->>'task_id','')::bigint),
          nullif(p_input->>'trace_id','')::bigint)
  on conflict (event_id, dedupe_value) do nothing
  returning outbox_id into v_id;

  -- A duplicate is not a new row and it is not an error: re-read the one that already exists.
  if v_id is null then
    select outbox_id into v_id from public.phase_c_event_outbox
     where event_id = e.event_id and dedupe_value = v_dedupe;
  end if;
  -- Error and empty must not return the same value.
  if v_id is null then
    raise exception 'fn_kernel_outbox_emit wrote no row and found none for %/%', v_event, v_dedupe
      using errcode = '23502';
  end if;
  return v_id;
end $function$;

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

  -- ---- (a) the command --------------------------------------------------------------------
  if v_command is not null then
    if exists (select 1 from public.founder_command
                where command_id = v_command and state not in ('cancelled','superseded','completed')) then
      if not exists (select 1 from public.phase_c_command_transition t
                      join public.founder_command c on c.command_id = v_command
                     where t.from_state = c.state and t.to_state = v_terminal) then
        return jsonb_build_object('ok', false, 'error', 'transition_not_permitted',
          'from', (select state from public.founder_command where command_id = v_command),
          'to', v_terminal,
          'message', 'The command state model does not allow this move. Nothing was cancelled.');
      end if;
      update public.founder_command
         set state = v_terminal,
             superseded_by = case when v_op = 'supersede'
                                  then nullif(regexp_replace(coalesce(p_input->>'superseded_by',''), '\D','','g'),'')::bigint
                                  else superseded_by end,
             closed_at = now()
       where command_id = v_command;
      n_cmd := 1;
    end if;

    -- ---- (b) the command plan --------------------------------------------------------------
    update public.founder_command_plan
       set state = v_terminal, closed_at = now()
     where command_id = v_command and state = 'active';
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
            where ((v_command is not null and command_id = v_command) or run_id = any(v_runs))
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
     and ( (v_command is not null and o.command_id = v_command)
        or o.workflow_run_id = any(v_runs)
        or o.step_run_id in (select sr.step_run_id from public.phase_c_workflow_step_run sr
                              where sr.run_id = any(v_runs))
        or o.task_id in (select t.task_id from public.phase_c_task t
                          where (v_command is not null and t.command_id = v_command)
                             or t.run_id = any(v_runs)) );
  get diagnostics n_outbox = row_count;

  -- ---- (h) seal every open trace whose subject was just closed -----------------------------
  update public.phase_c_trace
     set status = 'sealed', sealed_at = now()
   where sealed_at is null
     and ( (v_command is not null and command_id = v_command)
        or run_id = any(v_runs)
        or task_id in (select task_id from public.phase_c_task
                        where (v_command is not null and command_id = v_command)
                           or run_id = any(v_runs)) );
  get diagnostics n_trace = row_count;

  -- ---- (i) THE POSTCONDITION ---------------------------------------------------------------
  -- "A cancelled command may leave no queued derived work." Asserted, not asserted about.
  select count(*) into v_left_tasks from public.phase_c_task
   where ((v_command is not null and command_id = v_command) or run_id = any(v_runs))
     and state in ('queued','assigned','accepted','in_progress','blocked');
  select count(*) into v_left_runs from public.phase_c_workflow_run
   where run_id = any(v_runs) and state not in ('cancelled','superseded','completed','failed');
  select count(*) into v_left_steps from public.phase_c_workflow_step_run
   where run_id = any(v_runs) and state not in ('cancelled','completed','failed','superseded');
  select count(*) into v_left_handoffs from public.phase_c_handoff_run
   where run_id = any(v_runs) and status = 'open';
  select count(*) into v_left_outbox from public.phase_c_event_outbox o
   where o.status in ('pending','claimed','retry_wait')
     and ( (v_command is not null and o.command_id = v_command)
        or o.workflow_run_id = any(v_runs)
        or o.step_run_id in (select sr.step_run_id from public.phase_c_workflow_step_run sr
                              where sr.run_id = any(v_runs))
        or o.task_id in (select t.task_id from public.phase_c_task t
                          where (v_command is not null and t.command_id = v_command)
                             or t.run_id = any(v_runs)) );

  if v_left_tasks + v_left_runs + v_left_steps + v_left_handoffs + v_left_outbox > 0 then
    raise exception
      'fn_kernel_cancel left derived work behind: tasks=% runs=% steps=% handoffs=% outbox=%',
      v_left_tasks, v_left_runs, v_left_steps, v_left_handoffs, v_left_outbox
      using errcode = '23514',
            hint = 'The propagation missed a table. Nothing was cancelled — the transaction is rolled back.';
  end if;

  return jsonb_build_object('ok', true, 'op', v_op, 'subject_kind', v_kind, 'subject_ref', v_ref,
    'command_id', v_command, 'run_ids', to_jsonb(v_runs), 'actor', v_actor, 'reason', v_reason,
    'closed', jsonb_build_object('command', n_cmd, 'plan', n_plan, 'workflow_runs', n_run,
      'step_runs', n_step, 'tasks', n_task, 'handoffs', n_handoff, 'outbox_superseded', n_outbox,
      'traces_sealed', n_trace),
    'queued_derived_work_remaining', 0);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_founder_command_control(p_command_id bigint, p_op text, p_target text, p_value text, p_actor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_target bigint; v_state text; v_n bigint := 0; t record; v_trace bigint; v_founder text;
        v_out jsonb;
begin
  v_founder := public.fn_phase_c_require_founder(p_actor);   -- raises 28000 for anyone else

  v_target := nullif(regexp_replace(coalesce(p_target,''), '\D', '', 'g'), '')::bigint;
  if v_target is null then
    return jsonb_build_object('ok', false, 'error','identifier_required');
  end if;
  select state into v_state from public.founder_command where command_id = v_target;
  if v_state is null then return jsonb_build_object('ok', false, 'error','not_found'); end if;

  if p_op in ('cancel','supersede') then
    -- ROOT CAUSE 2. THIS BRANCH USED TO BE A SECOND CANCELLER. It set founder_command.state itself
    -- and closed the child tasks one by one, and it stopped there: the workflow run, its open step
    -- runs, its handoffs, its queued outbox rows and its open traces were left live beneath a
    -- command the founder had cancelled. The final Phase C acceptance cancelled command 338 through
    -- this exact path and left run 538 and step run 531 active.
    --
    -- It now delegates. fn_kernel_cancel is the canonical canceller and the only one: it walks the
    -- command, its plan, its runs, their step runs, tasks, handoffs, undelivered outbox rows and
    -- open traces, refuses a transition the state model does not declare, and counts what it left
    -- behind before returning. The founder identity is verified twice on purpose — once above, and
    -- again inside the kernel for the founder_command subject — because the kernel may not trust a
    -- caller's word about who is asking.
    v_out := public.fn_kernel_cancel(jsonb_build_object(
      'subject_kind', 'founder_command',
      'subject_ref',  v_target::text,
      'op',           p_op,
      'actor',        p_actor,
      'reason',       coalesce(nullif(btrim(p_value),''),
                               'founder ' || p_op || ' of command ' || v_target
                               || ' through the Command Center control')));

    -- IDEMPOTENT. A command already in its terminal state is not an error and must not become one:
    -- the second click of Cancel returns the same answer as the first and changes nothing.
    if coalesce((v_out->>'ok')::boolean, false) is not true
       and v_state in ('cancelled','superseded') then
      return jsonb_build_object('ok', true, 'command_id', v_target, 'status', v_state,
        'already_terminal', true, 'child_tasks_closed', 0, 'actor', v_founder,
        'kernel', v_out);
    end if;
    if coalesce((v_out->>'ok')::boolean, false) is not true then
      return jsonb_build_object('ok', false, 'command_id', v_target,
        'error', coalesce(v_out->>'error', 'cancellation_refused'), 'kernel', v_out);
    end if;

    return jsonb_build_object('ok', true, 'command_id', v_target,
      'status', case when p_op = 'cancel' then 'cancelled' else 'superseded' end,
      'superseded_by', case when p_op = 'supersede' then p_command_id else null end,
      'child_tasks_closed', coalesce((v_out->'closed'->>'tasks')::int, 0),
      'closed', v_out->'closed', 'actor', v_founder);

  elsif p_op = 'reprioritize' then
    if coalesce(p_value,'') !~ '^P[0-3]$' then
      return jsonb_build_object('ok', false, 'error','priority_required', 'allowed','P0..P3');
    end if;
    update public.founder_command set priority = p_value where command_id = v_target;
    update public.phase_c_task set priority = p_value where command_id = v_target and closed_at is null;
    get diagnostics v_n = row_count;
    return jsonb_build_object('ok', true, 'command_id', v_target, 'priority', p_value,
      'tasks_updated', v_n, 'actor', v_founder);

  elsif p_op = 'explain' then
    return jsonb_build_object('ok', true, 'command_id', v_target,
      'explanation', coalesce((select i.reason from public.founder_command_interpretation i
                               where i.command_id = v_target order by i.version desc limit 1),
                              'no interpretation recorded'),
      'traces', coalesce((select jsonb_agg(jsonb_build_object(
                              'trace_id', tr.trace_id, 'policy', tr.trace_policy_id,
                              'subject', tr.subject_kind, 'state_after', tr.state_after,
                              'status', tr.status) order by tr.trace_id)
                          from public.phase_c_trace tr where tr.command_id = v_target), '[]'::jsonb),
      'plan', (select p.summary from public.founder_command_plan p where p.command_id = v_target),
      'actor', v_founder);
  end if;
  return jsonb_build_object('ok', false, 'error','unknown_control_operation', 'op', p_op);
end $function$;


-- ---------------------------------------------------------------------------------------------
-- DELIVERY REFUSES A CANCELLED SUBJECT.
--
-- Requirement 8. The sweep above stops every row that is queued at the moment of cancellation, but
-- a row CLAIMED a fraction earlier is already in a worker's hand, and a worker written tomorrow is
-- not this worker. Putting the refusal in one worker's body protects one worker.
--
-- So the refusal lives on the table. A BEFORE UPDATE trigger cannot be bypassed by a second worker,
-- a hand-typed update or a future rewrite, and it does not abort the batch: it REWRITES the row to
-- 'superseded' with the reason instead of raising, so one cancelled event cannot fail the pass for
-- the twenty-four beside it.
--
-- A DELIVERED event is never touched. It is a fact that happened, and rewriting it would falsify
-- history; what is stopped is the delivery that has not happened yet.
create or replace function public.fn_kernel_outbox_refuse_cancelled_subject()
returns trigger
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $rc2$
declare v_why text;
begin
  -- Only the transition INTO delivered is guarded. Claiming, retrying and superseding are allowed.
  if new.status is distinct from 'delivered' or old.status = 'delivered' then
    return new;
  end if;

  select string_agg(x, '; ') into v_why from (
    select 'founder command ' || c.command_id || ' is ' || c.state as x
      from public.founder_command c
     where c.command_id = new.command_id and c.state in ('cancelled','superseded')
    union all
    select 'workflow run ' || r.run_id || ' is ' || r.state
      from public.phase_c_workflow_run r
     where r.run_id = new.workflow_run_id and r.state in ('cancelled','superseded')
    union all
    select 'step run ' || sr.step_run_id || ' is ' || sr.state
      from public.phase_c_workflow_step_run sr
     where sr.step_run_id = new.step_run_id and sr.state in ('cancelled','superseded')
    union all
    select 'task ' || t.task_id || ' is ' || t.state
      from public.phase_c_task t
     where t.task_id = new.task_id and t.state in ('cancelled','superseded')
  ) s;

  if v_why is null then
    return new;
  end if;

  new.status       := 'superseded';
  new.delivered_at := null;
  new.last_error   := 'DELIVERY REFUSED ' || to_char(now(),'YYYY-MM-DD HH24:MI') || ': '
                   || v_why || ' (fn_kernel_outbox_refuse_cancelled_subject). The event is kept as '
                   || 'the record that it was produced; it is not delivered, because the work it '
                   || 'describes has been cancelled.';
  return new;
end
$rc2$;

revoke execute on function public.fn_kernel_outbox_refuse_cancelled_subject() from public, anon, authenticated;

drop trigger if exists z05_outbox_refuse_cancelled_subject on public.phase_c_event_outbox;
create trigger z05_outbox_refuse_cancelled_subject
  before update on public.phase_c_event_outbox
  for each row execute function public.fn_kernel_outbox_refuse_cancelled_subject();
