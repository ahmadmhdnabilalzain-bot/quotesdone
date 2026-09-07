-- Phase C correction 1 and 2 — the founder-command trace lifecycle, and the event that finally
-- names the workflow it belongs to.
--
-- The independent acceptance audit (docs/phase-c-final/) executed a real authenticated founder
-- command over HTTPS and found two things the SQL-only probes could not see:
--
--   * command 222 reached `tasks_created` while its own root trace still said `interpreting`,
--     status `open`, and all four child tasks carried `trace_id NULL`. The founder-facing thread
--     rendered that null straight through;
--   * a W20 marketing command emitted `EV-W01-STARTED`, workflow `W01`, accountable and consumer
--     `ceo`. Every founder-command outbox row ever written carries that literal.
--
-- Both are fixed here, and both are fixed in the SHARED place rather than in the one caller the
-- audit happened to exercise: a task gets its trace from a trigger on phase_c_task, so the
-- autonomous path (correction 3) inherits it without a second implementation.

-- ================================================================ 1. the parent link
-- "task trace references the root command trace; review traces reference the relevant task trace"
-- needs an edge, and phase_c_trace had none. Additive, nullable, self-referencing.
alter table public.phase_c_trace
  add column if not exists parent_trace_id bigint references public.phase_c_trace(trace_id);

create index if not exists phase_c_trace_parent_idx on public.phase_c_trace(parent_trace_id);

comment on column public.phase_c_trace.parent_trace_id is
  'The trace this one hangs from: a task trace points at its command''s root trace, a review trace '
  'at the task trace it judges. NULL means this IS a root.';

-- ================================================================ 2. the lifecycle event registry
-- The authoritative registry is public.phase_b_event, which carries one `.started` event for each
-- of the 30 frozen workflows. This resolves through it. It does NOT concatenate 'EV-' with a
-- workflow id and a suffix: a derived identifier would have produced a plausible string for a
-- workflow that has no such event, which is precisely how EV-W01-STARTED survived.
create or replace function public.fn_phase_c_lifecycle_event(p_workflow_id text, p_lifecycle text)
returns text language sql stable set search_path to 'public', 'pg_temp' as $$
  select e.event_id
    from public.phase_b_event e
   where e.workflow_id = nullif(btrim(coalesce(p_workflow_id, '')), '')
     and e.event_name like '%.' || lower(btrim(coalesce(p_lifecycle, '')))
   order by e.event_id
   limit 1;
$$;
revoke all on function public.fn_phase_c_lifecycle_event(text, text) from public;
grant execute on function public.fn_phase_c_lifecycle_event(text, text) to service_role;
comment on function public.fn_phase_c_lifecycle_event(text, text) is
  'The canonical event id for a workflow lifecycle moment, read out of the frozen Phase B event '
  'registry. Returns NULL when the workflow declares no such event, so the caller must decide '
  'what to do rather than emit a guess.';

-- ================================================================ 3. advancing an open trace
-- phase_c_trace is append-only ONLY once sealed (fn_phase_c_trace_append_only returns early while
-- sealed_at is null). A root trace therefore stays writable for exactly as long as its subject is
-- still moving, which is the behaviour this needs: advance while open, seal at the terminal state,
-- and after that supersede rather than edit.
create or replace function public.fn_phase_c_trace_advance(
  p_trace_id bigint, p_state_after text, p_seal boolean default false, p_body jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
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
      'status', case when p_seal then 'sealed' else 'open' end));
    update public.phase_c_trace set parent_trace_id = coalesce(t.parent_trace_id, t.trace_id)
      where trace_id = v_new;
    update public.phase_c_trace set superseded_by = v_new where trace_id = p_trace_id;
    if p_seal then update public.phase_c_trace set sealed_at = now() where trace_id = v_new; end if;
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
end $$;
revoke all on function public.fn_phase_c_trace_advance(bigint, text, boolean, jsonb) from public;
grant execute on function public.fn_phase_c_trace_advance(bigint, text, boolean, jsonb) to service_role;

-- ================================================================ 4. no task without a trace
-- Every creator of a task now gets this for free, including the autonomous path. The audit found
-- 12 of 12 tasks with a null trace_id and no invariant that could see it, because the only
-- trace invariant looked at CLOSED tasks and no task had ever closed.
-- ROUTINE REMOVED 7 September 2026. public.fn_phase_c_task_trace_guard was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- a00_ so it runs before the state guard, which is a90_-class work: the trace must exist before
-- anything decides whether the transition is legal. Postgres fires BEFORE triggers in NAME order.
drop trigger if exists a00_phase_c_task_trace_guard on public.phase_c_task;
create trigger a00_phase_c_task_trace_guard
  before insert or update on public.phase_c_task
  for each row execute function public.fn_phase_c_task_trace_guard();

-- ================================================================ 5. no command ahead of its trace
-- "a command cannot reach tasks_created while its root trace remains interpreting."
create or replace function public.fn_founder_command_trace_guard()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare t public.phase_c_trace%rowtype;
begin
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
end $$;

drop trigger if exists a00_founder_command_trace_guard on public.founder_command;
create trigger a00_founder_command_trace_guard
  before update on public.founder_command
  for each row execute function public.fn_founder_command_trace_guard();

-- ================================================================ 6. the command router
-- Reproduced from the live definition with exactly two changes: the hard-coded EV-W01-STARTED
-- emit became a registry lookup on the workflow this command selected, and the two locals that
-- needs are declared.  Task traces and the root-trace advance are deliberately NOT here - they
-- are the triggers above, so the autonomous path gets the same behaviour without a second
-- implementation of it that could drift.
CREATE OR REPLACE FUNCTION public.fn_founder_command_submit(p_founder_identity text, p_text text, p_idempotency_key text, p_ctx jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_start_event text; v_wf_selected text;
  c record; v_msg bigint; v_cmd bigint; v_existing bigint; v_trace bigint; v_task bigint;
  v_tasks bigint[] := '{}'; v_owners text[] := '{}'; v_overlays text[] := '{}';
  v_wf text; v_child text; v_owner text; v_kind text; v_manager text; v_dept text;
  v_action text; v_due timestamptz; v_intent public.phase_c_command_intent%rowtype;
  v_plan_id bigint; v_qn text; v_ov jsonb;
begin
  if coalesce(p_founder_identity, '') = '' then
    raise exception 'founder identity is required' using errcode = '28000';
  end if;
  if not exists (select 1 from public.phase_c_founder_identity
                 where identity = lower(btrim(p_founder_identity)) and active) then
    return jsonb_build_object('ok', false, 'error', 'not_the_founder',
      'message', 'The Command Center accepts commands from the registered founder identity only.');
  end if;

  select m.message_id into v_msg from public.founder_command_message m
   where m.client_idempotency_key = p_idempotency_key;
  if v_msg is not null then
    select fc.command_id into v_existing from public.founder_command fc where fc.message_id = v_msg;
    -- SAME SHAPE AS THE CREATE PATH. Returning the status object here made every field the caller
    -- reads come back undefined on a repeated instruction.
    return public.fn_founder_command_duplicate_result(v_existing, p_idempotency_key);
  end if;

  insert into public.founder_command_message
    (session_id, founder_identity, raw_text, raw_text_hash, client_idempotency_key, channel)
  values ((p_ctx->>'session_id')::bigint, lower(btrim(p_founder_identity)), p_text,
          encode(sha256(convert_to(coalesce(p_text,''), 'UTF8')), 'hex'), p_idempotency_key,
          coalesce(p_ctx->>'channel', 'command_center'))
  returning message_id into v_msg;

  select * into c from public.fn_founder_command_classify(p_text);

  insert into public.founder_command
    (message_id, intent_id, outcome, state, priority, primary_role_id,
     founder_initiated_only, refund_semantics)
  values (v_msg, c.intent_id, c.outcome, 'received', c.priority,
          coalesce(nullif(c.primary_role_id,''), 'chief_of_staff'),
          c.outcome in ('FOUNDER_INITIATED_POLICY_CHANGE','FOUNDER_INITIATED_PHASE_A_CHANGE'),
          c.outcome = 'REFUND_APPROVAL')
  returning command_id into v_cmd;
  if v_cmd is null then
    raise exception 'fn_founder_command_submit wrote no command row' using errcode = '23502';
  end if;

  insert into public.founder_command_interpretation
    (command_id, version, intent_id, confidence, matched_rule_id, workflow_ids, specificity_signals, reason)
  values (v_cmd, 1, c.intent_id, c.confidence, c.matched_rule_id, c.workflow_ids, c.specificity, c.reason);

  update public.founder_command set state = 'interpreting' where command_id = v_cmd;

  v_trace := public.fn_phase_c_trace_write('TRACE-FOUNDER-COMMAND', jsonb_build_object(
    'subject_kind','command', 'subject_ref', v_cmd::text, 'command_id', v_cmd,
    'actor_role_id','founder', 'system_actor_id','system.command_router',
    'input_hash', encode(sha256(convert_to(coalesce(p_text,''), 'UTF8')), 'hex'),
    'state_before','received', 'state_after','interpreting', 'status','open'));
  update public.founder_command set trace_id = v_trace where command_id = v_cmd;

  if c.outcome = 'REFUSE_UNSCOPED_UNSAFE_COMMAND' then
    update public.founder_command set state = 'refused', closed_at = now() where command_id = v_cmd;
    return jsonb_build_object('ok', true, 'command_id', v_cmd, 'status','refused',
      'intent', c.intent_id, 'interpretation', c.reason, 'workflow_ids','[]'::jsonb,
      'task_ids','[]'::jsonb, 'owner','chief_of_staff', 'tasks_created', 0,
      'blocker', 'Unscoped destructive or financial instruction. Name the individual cases and the evidence, and it will route.',
      'trace_id', v_trace);
  end if;

  if c.intent_id = 'AMBIGUOUS' then
    v_qn := case when c.matched_rule_id <> ''
      then 'I can route this, but not safely yet. What exactly do you want changed, by how much, and by when?'
      else 'I have no registered intent for that. What outcome do you want, in which area, and by when?' end;
    insert into public.founder_command_clarification (command_id, question) values (v_cmd, v_qn);
    update public.founder_command set state = 'clarification_required' where command_id = v_cmd;
    return jsonb_build_object('ok', true, 'command_id', v_cmd, 'status','clarification_required',
      'intent','AMBIGUOUS', 'interpretation', c.reason, 'workflow_ids','[]'::jsonb,
      'task_ids','[]'::jsonb, 'owner','chief_of_staff', 'tasks_created', 0,
      'clarification', v_qn, 'trace_id', v_trace);
  end if;

  if c.intent_id in ('CMD-STATUS','CMD-CANCEL','CMD-REPRIORITIZE','CMD-EXPLAIN') then
    update public.founder_command set state = 'accepted' where command_id = v_cmd;
    return jsonb_build_object('ok', true, 'command_id', v_cmd, 'status','accepted',
      'intent', c.intent_id, 'interpretation', c.reason, 'control_command', true,
      'workflow_ids','[]'::jsonb, 'task_ids','[]'::jsonb, 'owner','chief_of_staff',
      'tasks_created', 0, 'trace_id', v_trace,
      'next', 'call fn_founder_command_control(command_id, op, target_ref, value)');
  end if;

  update public.founder_command set state = 'accepted' where command_id = v_cmd;
  select * into v_intent from public.phase_c_command_intent where intent_id = c.intent_id;

  v_due := now() + case c.priority when 'P0' then interval '4 hours'
                                   when 'P1' then interval '2 days'
                                   else interval '5 days' end;

  for v_wf in select btrim(x) from unnest(string_to_array(c.workflow_ids, ';')) x where btrim(x) <> '' loop
    if exists (select 1 from public.phase_b_workflow where workflow_id = v_wf) then
      insert into public.founder_command_workflow_link (command_id, workflow_id)
      values (v_cmd, v_wf) on conflict do nothing;
    end if;
  end loop;
  update public.founder_command set state = 'routed' where command_id = v_cmd;

  v_owner := coalesce(nullif(c.primary_role_id, ''), v_intent.default_accountable_role_id, 'chief_of_staff');
  if v_owner <> 'founder' then
    select role_id into v_owner from public.fn_phase_c_resolve_actor(v_owner);
    if v_owner is null then
      raise exception 'command %: primary owner does not resolve to an active canonical role', v_cmd
        using errcode = '23514';
    end if;
    select r.manager_role_id, r.primary_department_id into v_manager, v_dept
      from public.org_role r where r.role_id = v_owner;
    v_wf := btrim(split_part(c.workflow_ids, ';', 1));
    v_action := case when c.outcome = 'REFUND_APPROVAL' then 'refund_decision'
                     else coalesce((select authority_class from public.phase_c_component
                                    where workflow_id = v_wf limit 1), 'routine_operational_decision') end;
    if v_action = 'refund_decision' and c.outcome <> 'REFUND_APPROVAL' then
      v_action := 'routine_operational_decision';
    end if;

    insert into public.phase_c_task (
      source_kind, source_ref, command_id, workflow_id, accountable_role_id, manager_role_id,
      department_id, objective, requested_output, acceptance_criteria, closure_criteria,
      priority, due_at, authority_class, idempotency_key, state)
    values ('founder_command', 'CMD-' || v_cmd, v_cmd, nullif(v_wf, ''), v_owner,
            coalesce(v_manager, ''), coalesce(v_dept, ''), left(coalesce(p_text, ''), 2000),
            'Evidence-backed outcome for the founder instruction, with the decision and its basis recorded.',
            'Requested outcome delivered with evidence, within policy, authority and gates.',
            'Independent review passed where required and the closure criteria of the bound workflow are met.',
            c.priority, v_due, v_action, 'cmd:' || v_cmd || ':primary', 'queued')
    returning task_id into v_task;
    if v_task is null then
      raise exception 'command %: primary task insert produced no row', v_cmd using errcode = '23502';
    end if;
    insert into public.founder_command_task_link (command_id, task_id) values (v_cmd, v_task);
    v_tasks := v_tasks || v_task; v_owners := v_owners || v_owner;
  end if;

  for v_child in select btrim(x) from unnest(string_to_array(c.child_role_ids, ';')) x where btrim(x) <> '' loop
    select kind, role_id into v_kind, v_owner from public.fn_phase_c_resolve_actor(v_child);
    if v_kind = 'overlay' then
      v_ov := public.fn_phase_c_overlay_invoke(v_child, jsonb_build_object(
        'command_id', v_cmd, 'evidence_refs', jsonb_build_array('CMD-' || v_cmd)));
      insert into public.founder_command_overlay_invocation
        (command_id, overlay_id, live_role_id, returns_to_role_id, result, trace_id)
      values (v_cmd, coalesce(v_ov->>'overlay_id', v_child), v_owner,
              coalesce(v_ov->>'return_owner', coalesce(v_owners[1], 'chief_of_staff')),
              v_ov, (v_ov->>'trace_id')::bigint)
      on conflict (command_id, overlay_id) do nothing;
      v_overlays := v_overlays || coalesce(v_ov->>'overlay_id', v_child);
      continue;
    end if;
    continue when v_kind is distinct from 'canonical' or v_owner is null;
    select r.manager_role_id, r.primary_department_id into v_manager, v_dept
      from public.org_role r where r.role_id = v_owner;
    insert into public.phase_c_task (
      source_kind, source_ref, command_id, workflow_id, accountable_role_id, manager_role_id,
      department_id, objective, requested_output, acceptance_criteria, closure_criteria,
      priority, due_at, authority_class, idempotency_key, state)
    values ('founder_command', 'CMD-' || v_cmd, v_cmd,
            nullif(btrim(split_part(c.workflow_ids, ';', 1)), ''), v_owner,
            coalesce(v_manager, ''), coalesce(v_dept, ''), left(coalesce(p_text, ''), 2000),
            'Contribution required by the command plan for ' || v_child,
            'Contribution delivered with evidence to the command owner.',
            'Accepted by the primary owner or returned with a specific reason.',
            c.priority, v_due, 'routine_operational_decision',
            'cmd:' || v_cmd || ':child:' || v_owner, 'queued')
    on conflict (idempotency_key) do nothing
    returning task_id into v_task;
    if v_task is not null then
      insert into public.founder_command_task_link (command_id, task_id) values (v_cmd, v_task);
      v_tasks := v_tasks || v_task; v_owners := v_owners || v_owner;
    end if;
  end loop;

  insert into public.founder_command_plan (command_id, summary, child_task_count, departments)
  values (v_cmd,
          format('%s: %s. Command owner chief_of_staff; %s task(s) against %s%s.',
                 c.intent_id, c.outcome, cardinality(v_tasks),
                 coalesce(nullif(c.workflow_ids,''), 'no workflow'),
                 case when cardinality(v_overlays) > 0
                      then format('; %s category overlay invocation(s): %s',
                                  cardinality(v_overlays), array_to_string(v_overlays, ', '))
                      else '' end),
          cardinality(v_tasks),
          coalesce((select string_agg(distinct t.department_id, '; ')
                    from public.phase_c_task t where t.command_id = v_cmd and t.department_id <> ''), ''))
  on conflict (command_id) do update set summary = excluded.summary,
    child_task_count = excluded.child_task_count, departments = excluded.departments
  returning plan_id into v_plan_id;

  if c.outcome = 'REFUND_APPROVAL' then
    insert into public.founder_approval_request
      (command_id, action_class, subject_ref, prepared_by_role_id, amount_note, evidence, state)
    values (v_cmd, 'refund_decision',
            coalesce((regexp_match(p_text, '(TX-[A-Za-z0-9_-]+)'))[1], 'UNIDENTIFIED_TRANSACTION'),
            'payments_and_billing_manager',
            'amount, reason, customer/supplier impact and fraud checks required before decision',
            jsonb_build_object('raw_command', left(coalesce(p_text,''), 500)), 'pending');
  end if;

  -- The event, in the SAME transaction as the work it describes, and IDENTIFIED by the workflow
  -- this command actually selected.  A literal here announced EV-W01-STARTED - workflow W01,
  -- accountable and consumer 'ceo' - for every command the company had ever received, including
  -- three W20 marketing orders.  fn_phase_c_lifecycle_event reads the frozen Phase B registry and
  -- returns NULL when the workflow declares no such event; nothing is derived by concatenation, so
  -- an unregistered workflow produces no event rather than a plausible one.
  v_wf_selected := btrim(split_part(c.workflow_ids, ';', 1));
  v_start_event := public.fn_phase_c_lifecycle_event(v_wf_selected, 'started');
  if v_start_event is not null then
    perform public.fn_phase_c_outbox_emit(
      v_start_event, 'system.command_router',
      jsonb_build_object('command_id', v_cmd, 'intent', c.intent_id,
                         'workflow_id', v_wf_selected, 'tasks', to_jsonb(v_tasks)),
      'founder_command:' || v_cmd);
  end if;

  update public.founder_command set state = 'tasks_created', due_at = v_due where command_id = v_cmd;

  return jsonb_build_object(
    'ok', true, 'command_id', v_cmd, 'status', 'tasks_created', 'intent', c.intent_id,
    'outcome', c.outcome, 'interpretation', c.reason,
    'workflow_ids', coalesce((select jsonb_agg(workflow_id order by workflow_id)
                              from public.founder_command_workflow_link where command_id = v_cmd), '[]'::jsonb),
    'task_ids', to_jsonb(v_tasks),
    'owner', 'chief_of_staff', 'primary_owner', coalesce(v_owners[1], 'founder'),
    'child_owners', to_jsonb(v_owners[2:]),
    'category_overlays_invoked', to_jsonb(v_overlays),
    'tasks_created', cardinality(v_tasks),
    'priority', c.priority, 'due_at', v_due,
    'founder_approval_required', (c.outcome = 'REFUND_APPROVAL'),
    'founder_initiated_only', (c.outcome in ('FOUNDER_INITIATED_POLICY_CHANGE','FOUNDER_INITIATED_PHASE_A_CHANGE')),
    'plan_id', v_plan_id, 'trace_id', v_trace);
end $function$;
revoke all on function public.fn_founder_command_submit(text, text, text, jsonb) from public;
grant execute on function public.fn_founder_command_submit(text, text, text, jsonb) to service_role;

-- ================================================================ 7. the trace learns its task id
-- A BEFORE INSERT trigger cannot know the identity it is about to create, so the task trace was
-- written with task_id NULL and the task's own id nowhere in it. That is the same defect in
-- miniature as the one this file exists to fix: evidence that does not name its subject. The id is
-- stamped on immediately after the row exists.
create or replace function public.fn_phase_c_task_trace_subject()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
begin
  if new.trace_id is not null then
    update public.phase_c_trace
       set task_id = new.task_id, subject_ref = new.task_id::text
     where trace_id = new.trace_id and task_id is null;
  end if;
  return null;
end $$;

drop trigger if exists z90_phase_c_task_trace_subject on public.phase_c_task;
create trigger z90_phase_c_task_trace_subject
  after insert on public.phase_c_task
  for each row execute function public.fn_phase_c_task_trace_subject();

-- and the traces already written without one
update public.phase_c_trace tr
   set task_id = t.task_id, subject_ref = t.task_id::text
  from public.phase_c_task t
 where t.trace_id = tr.trace_id and tr.task_id is null
   -- a SEALED trace is append-only and the guard is right to refuse: those rows already carry the
   -- task id, put there by the retro-fit in phase_c_38 rather than by this stamp.
   and tr.sealed_at is null;
