-- Phase C — two defects the Phase C guards found in Phase C's own code, on the first run of
-- the twenty command-routing acceptance cases.  scripts/sql is append-only, so they are fixed
-- here rather than by editing the files that shipped them.
--
-- 1. AN OVERLAY IS INVOKED, NOT ASSIGNED.
--    Acceptance case CC-002 ("Find 20 more scaffolding suppliers in Dubai by Friday") names
--    `category overlay opcat-004` in its child role list.  The command router treated every
--    child token as a task owner, so it tried to create a task owned by
--    category_overlay_004_formwork-and-scaffolding-suppliers, and the Phase C guard
--    z10_phase_c_overlay_not_accountable refused the write — correctly.  A category overlay may
--    advise and may never own work; that is the frozen Phase A/B rule and it is not the guard
--    that was wrong.
--
--    What was wrong was the router. An overlay named in a command plan is an INVOCATION: it is
--    called, it returns its advice to a named owner, and the advice is traced under
--    TRACE-CATEGORY-ADVICE. No task, no ownership. That is what this file makes it do.
--
-- 2. RAISE DOES NOT UNDERSTAND %L.
--    `%L` and `%I` are format() placeholders. In a RAISE statement only `%` substitutes, so
--    `raise exception 'owner %L ...', v` printed the value followed by a literal L — which is
--    how the message above read "…-suppliersL". Cosmetic, but an error message that garbles the
--    identifier it is complaining about is an error message that costs someone an hour.

set lock_timeout = '8s';
set statement_timeout = '600s';

-- ------------------------------------------------------------------ overlay invocations
create table if not exists public.founder_command_overlay_invocation (
  invocation_id bigint generated always as identity primary key,
  command_id    bigint not null references public.founder_command(command_id) on delete cascade,
  overlay_id    text not null,
  live_role_id  text not null,
  returns_to_role_id text not null,
  result        jsonb not null default '{}'::jsonb,
  trace_id      bigint,
  created_at    timestamptz not null default now()
);
create unique index if not exists founder_command_overlay_invocation_uk
  on public.founder_command_overlay_invocation (command_id, overlay_id);

-- ------------------------------------------------------------------ the two RAISE fixes
create or replace function public.fn_phase_c_overlay_may_not_dispatch()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $$
declare v_kind text;
begin
  select kind into v_kind from public.fn_phase_c_resolve_actor(new.accountable_role_id);
  if v_kind = 'overlay' then
    raise exception 'phase_c_task: category overlay % may advise but may never own a task or hold dispatch authority. Invoke it with fn_phase_c_overlay_invoke and return its advice to a canonical owner.',
      new.accountable_role_id using errcode = '23514';
  end if;
  return new;
end $$;

create or replace function public.fn_phase_c_task_create(p_body jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare v_id bigint; v_owner text; v_manager text; v_dept text; v_key text;
begin
  select role_id into v_owner from public.fn_phase_c_resolve_actor(p_body->>'accountable_role_id');
  if v_owner is null or not public.fn_phase_c_actor_may_own(v_owner) then
    raise exception 'fn_phase_c_task_create: owner % does not resolve to an active canonical role',
      coalesce(p_body->>'accountable_role_id', '(null)') using errcode = '23514';
  end if;
  select r.manager_role_id, r.primary_department_id into v_manager, v_dept
    from public.org_role r where r.role_id = v_owner;
  v_key := coalesce(nullif(p_body->>'idempotency_key',''),
    'task:' || md5(coalesce(p_body->>'source_ref','') || ':' || v_owner || ':' || coalesce(p_body->>'objective','')));
  insert into public.phase_c_task (
    source_kind, source_ref, command_id, run_id, workflow_id, step_id, accountable_role_id,
    manager_role_id, department_id, objective, required_inputs, requested_output,
    acceptance_criteria, closure_criteria, priority, due_at, sla_policy_id, reviewer_required,
    reviewer_role_id, authority_class, idempotency_key, state)
  values (
    coalesce(p_body->>'source_kind','management'), coalesce(p_body->>'source_ref',''),
    (p_body->>'command_id')::bigint, (p_body->>'run_id')::bigint,
    nullif(p_body->>'workflow_id',''), nullif(p_body->>'step_id',''),
    v_owner, coalesce(v_manager,''), coalesce(v_dept,''),
    coalesce(p_body->>'objective','(objective not stated)'),
    coalesce(p_body->>'required_inputs',''), coalesce(p_body->>'requested_output',''),
    coalesce(p_body->>'acceptance_criteria','Evidence-backed outcome accepted by the manager.'),
    coalesce(p_body->>'closure_criteria','Closure criteria of the bound workflow satisfied.'),
    coalesce(p_body->>'priority','P2'), (p_body->>'due_at')::timestamptz,
    coalesce(p_body->>'sla_policy_id',''),
    coalesce((p_body->>'reviewer_required')::boolean, false),
    coalesce(p_body->>'reviewer_role_id',''),
    coalesce(p_body->>'authority_class','routine_operational_decision'),
    v_key, 'queued')
  on conflict (idempotency_key) do nothing
  returning task_id into v_id;
  if v_id is null then
    select task_id into v_id from public.phase_c_task where idempotency_key = v_key;
  end if;
  if v_id is null then
    raise exception 'fn_phase_c_task_create wrote no row and found none for key %', v_key using errcode = '23502';
  end if;
  return v_id;
end $$;

-- ------------------------------------------------------------------ the router fix
create or replace function public.fn_founder_command_submit(
  p_founder_identity text, p_text text, p_idempotency_key text, p_ctx jsonb default '{}'::jsonb)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  c            record;
  v_msg        bigint;
  v_cmd        bigint;
  v_existing   bigint;
  v_trace      bigint;
  v_task       bigint;
  v_tasks      bigint[] := '{}';
  v_owners     text[] := '{}';
  v_overlays   text[] := '{}';
  v_wf         text;
  v_child      text;
  v_owner      text;
  v_kind       text;
  v_manager    text;
  v_dept       text;
  v_action     text;
  v_due        timestamptz;
  v_intent     public.phase_c_command_intent%rowtype;
  v_plan_id    bigint;
  v_qn         text;
  v_ov         jsonb;
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
    return public.fn_founder_command_status(v_existing::text)
           || jsonb_build_object('duplicate_of_idempotency_key', p_idempotency_key);
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
    (command_id, version, intent_id, confidence, matched_rule_id, workflow_ids,
     specificity_signals, reason)
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
    v_qn := case
      when c.matched_rule_id <> ''
        then 'I can route this, but not safely yet. What exactly do you want changed, by how much, and by when?'
      else 'I have no registered intent for that. What outcome do you want, in which area, and by when?'
    end;
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

  -- Children.  A canonical role gets a task.  A CATEGORY OVERLAY does not: it is invoked, its
  -- advice returns to a named canonical owner, and the invocation is traced.  Assigning work to
  -- an overlay is refused by z10_phase_c_overlay_not_accountable, and that guard is correct.
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
