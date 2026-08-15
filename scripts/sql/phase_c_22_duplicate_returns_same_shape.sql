-- Phase C — a repeat command must answer in the SAME SHAPE as the first one.
--
-- Found by using the Command Console in a browser, which became possible ten minutes ago. I sent
-- the same sentence twice. The first time it rendered correctly. The second time the console said:
--
--     "undefined task(s) created."
--
-- The cause: os_api derives the idempotency key from the message text, so an identical sentence is
-- correctly recognised as a duplicate — and the duplicate branch returned
-- fn_founder_command_status(), which is a DIFFERENT OBJECT. It has no `control_command`, no
-- `tasks_created`, no `outcome`, no `interpretation`. Every field the caller reads was absent, and
-- absent renders as "undefined".
--
-- The idempotency was right. The response contract was not. This is the same family as the rule
-- this project already keeps — error and empty must not return the same value — in its other
-- direction: two DIFFERENT shapes from one function, where the caller cannot tell which it got.
--
-- The duplicate branch now returns the create-path shape, populated from the existing command,
-- plus `duplicate: true` and the key that matched. A caller that ignores the duplicate flag still
-- renders correctly; a caller that wants it can say "already running" instead of pretending it
-- created something.
--
-- scripts/sql is append-only.  To change any of this, add a new file.

set lock_timeout = '8s';
set statement_timeout = '600s';

create or replace function public.fn_founder_command_duplicate_result(p_command_id bigint, p_key text)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select jsonb_build_object(
    'ok', true,
    'command_id', c.command_id,
    'status', c.state,
    'intent', c.intent_id,
    'outcome', c.outcome,
    'interpretation', coalesce(
      (select i.reason from public.founder_command_interpretation i
        where i.command_id = c.command_id order by i.version desc limit 1), ''),
    'control_command', c.intent_id in ('CMD-STATUS','CMD-CANCEL','CMD-REPRIORITIZE','CMD-EXPLAIN'),
    'workflow_ids', coalesce((select jsonb_agg(l.workflow_id order by l.workflow_id)
                              from public.founder_command_workflow_link l
                              where l.command_id = c.command_id), '[]'::jsonb),
    'task_ids', coalesce((select jsonb_agg(t.task_id order by t.task_id)
                          from public.phase_c_task t where t.command_id = c.command_id), '[]'::jsonb),
    'tasks_created', (select count(*) from public.phase_c_task t where t.command_id = c.command_id),
    'owner', c.command_owner_role_id,
    'primary_owner', coalesce((select t.accountable_role_id from public.phase_c_task t
                               where t.command_id = c.command_id order by t.task_id limit 1), ''),
    'child_owners', coalesce((select jsonb_agg(x.accountable_role_id order by x.task_id)
                              from (select t.task_id, t.accountable_role_id from public.phase_c_task t
                                    where t.command_id = c.command_id order by t.task_id offset 1) x), '[]'::jsonb),
    'category_overlays_invoked', coalesce((select jsonb_agg(o.overlay_id order by o.overlay_id)
                                           from public.founder_command_overlay_invocation o
                                           where o.command_id = c.command_id), '[]'::jsonb),
    'priority', c.priority,
    'due_at', c.due_at,
    'founder_approval_required', c.refund_semantics,
    'founder_initiated_only', c.founder_initiated_only,
    'clarification', (select cl.question from public.founder_command_clarification cl
                      where cl.command_id = c.command_id order by cl.clarification_id desc limit 1),
    'trace_id', c.trace_id,
    -- the two fields that make it honest rather than merely well-shaped
    'duplicate', true,
    'duplicate_of_idempotency_key', p_key)
  from public.founder_command c
  where c.command_id = p_command_id;
$$;
revoke all on function public.fn_founder_command_duplicate_result(bigint, text) from public;
grant execute on function public.fn_founder_command_duplicate_result(bigint, text) to service_role;

-- Only the duplicate branch changes. Everything else in this function is byte-identical to
-- phase_c_10, which is why the whole body is restated rather than patched: scripts/sql is
-- append-only and a reader of the newest file must see what actually runs.
create or replace function public.fn_founder_command_submit(
  p_founder_identity text, p_text text, p_idempotency_key text, p_ctx jsonb default '{}'::jsonb)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
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

  perform public.fn_phase_c_outbox_emit(
    'EV-W01-STARTED', 'system.command_router',
    jsonb_build_object('command_id', v_cmd, 'intent', c.intent_id, 'tasks', to_jsonb(v_tasks)),
    'founder_command:' || v_cmd)
  where exists (select 1 from public.phase_b_event where event_id = 'EV-W01-STARTED');

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
end $$;
