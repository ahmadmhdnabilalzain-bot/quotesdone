-- ============================================================================================
-- KERNEL K2b — THE FOUNDER COMMAND ADAPTER CALLS THE KERNEL
--
-- APPLY ORDER: kernel_k5_factual_outbox.sql, then kernel_k2_workflow_start.sql, then this file.
-- Staged separately ON PURPOSE: K2 adds a new creator and breaks nothing; this file changes what
-- the founder's own Command Center does, and the lead should land it as its own decision.
--
-- WHAT THIS REPLACES, AND WHY
--
-- fn_founder_command_submit creates FOUR phase_c_task rows today — `cmd:N:primary` and up to three
-- `cmd:N:child:<role>` — and then emits EV-Wnn-STARTED, whose delivery reaches
-- fn_phase_c_event_ingress and creates a FIFTH task, `run:M:step:Wnn-S01`. Measured on
-- 16 Aug 2026: 6 of the 8 founder commands in this database carry both shapes. The same
-- marketing_director receives two tasks for one instruction, and the founder's own thread cannot
-- see the second, because the ingress writes it with command_id NULL.
--
-- The distinction the old body never drew:
--
--     A PLAN ITEM is the interpretation — "marketing_director contributes, finance reviews".
--     A TASK is work an employee is accountable for and can close.
--
-- Plan items now go to founder_command_plan_item, beside the founder_command_plan row that
-- already exists. The ONE operational task comes from fn_kernel_workflow_start, in the same
-- transaction, carrying command_id so the founder's thread can see it — and its event is emitted
-- as a RECORD of that work, not as an instruction to create it. Nothing consumes the event into
-- existence any more, so there is no fifth task and no second generation of the same event id.
--
-- ROLLBACK. There is no rollback file for this one on purpose: reverting it means restoring the
-- PREVIOUS BODY of fn_founder_command_submit, and a file containing a stale copy of that body is
-- exactly how a "rollback" ships a routine nobody has read since. Capture it before applying —
--   select pg_get_functiondef(oid) from pg_proc
--    where pronamespace='public'::regnamespace and proname='fn_founder_command_submit';
-- — and keep the output beside the change. founder_command_plan_item can stay: it holds records of
-- interpretations that really were made, and dropping it destroys them.
--
-- WHAT IS NOT CHANGED: classification, interpretation, clarification, refusal, control commands,
-- overlay invocation, the refund approval request, the founder trace, and the duplicate-submit
-- contract (fn_founder_command_duplicate_result). This is the same routine with the task writes
-- replaced by plan writes and one kernel call.
-- ============================================================================================

-- ------------------------------------------------------------------ 1. plan items are plan rows
-- founder_command_plan is UNIQUE (command_id) — one plan per command — so the items need their own
-- table. They are a record of what was decided, not a queue: they carry no state machine, no
-- accountable-role guard and no trace, because nobody is accountable for closing a plan item.
create table if not exists public.founder_command_plan_item (
  plan_item_id  bigint generated always as identity primary key,
  command_id    bigint not null references public.founder_command(command_id) on delete cascade,
  item_kind     text   not null,
  role_id       text   not null,
  department_id text   not null default '',
  summary       text   not null,
  priority      text   not null default 'P2',
  workflow_id   text,
  created_at    timestamptz not null default now()
);

do $ck$
begin
  if not exists (select 1 from pg_constraint where conname = 'founder_command_plan_item_kind_ck') then
    alter table public.founder_command_plan_item
      add constraint founder_command_plan_item_kind_ck
      check (item_kind in ('primary','contribution'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'founder_command_plan_item_unique') then
    alter table public.founder_command_plan_item
      add constraint founder_command_plan_item_unique unique (command_id, item_kind, role_id);
  end if;
end $ck$;

alter table public.founder_command_plan_item enable row level security;   -- zero policies, as the
                                                                         -- other ten runtime tables
create index if not exists founder_command_plan_item_command_ix
  on public.founder_command_plan_item (command_id);

-- Reachable by service_role only, exactly like the ten runtime tables. A new table starts with no
-- grants at all, so this is the difference between a table the runtime can write and one it cannot.
grant all on table public.founder_command_plan_item to service_role;

-- ------------------------------------------------------------------ 2. the replacement submit
create or replace function public.fn_founder_command_submit(
  p_founder_identity text, p_text text, p_idempotency_key text, p_ctx jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $function$
declare
  v_start_event text; v_wf_selected text;
  c record; v_msg bigint; v_cmd bigint; v_existing bigint; v_trace bigint; v_task bigint;
  v_tasks bigint[] := '{}'; v_owners text[] := '{}'; v_overlays text[] := '{}';
  v_wf text; v_child text; v_owner text; v_kind text; v_manager text; v_dept text;
  v_action text; v_due timestamptz; v_intent public.phase_c_command_intent%rowtype;
  v_plan_id bigint; v_qn text; v_ov jsonb;
  v_kernel jsonb; v_items int := 0; v_status text;
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

  v_wf_selected := btrim(split_part(c.workflow_ids, ';', 1));

  -- ---- THE PLAN (was: four phase_c_task rows) ------------------------------------------------
  -- The primary interpretation.
  v_owner := coalesce(nullif(c.primary_role_id, ''), v_intent.default_accountable_role_id, 'chief_of_staff');
  if v_owner <> 'founder' then
    select role_id into v_owner from public.fn_phase_c_resolve_actor(v_owner);
    if v_owner is null then
      raise exception 'command %: primary owner does not resolve to an active canonical role', v_cmd
        using errcode = '23514';
    end if;
    select r.manager_role_id, r.primary_department_id into v_manager, v_dept
      from public.org_role r where r.role_id = v_owner;
    insert into public.founder_command_plan_item
      (command_id, item_kind, role_id, department_id, summary, priority, workflow_id)
    values (v_cmd, 'primary', v_owner, coalesce(v_dept,''),
            left(coalesce(p_text,''), 2000), c.priority, nullif(v_wf_selected,''))
    on conflict (command_id, item_kind, role_id) do nothing;
    v_items := v_items + 1;
    v_owners := v_owners || v_owner;
  end if;

  -- The contributions.
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
    insert into public.founder_command_plan_item
      (command_id, item_kind, role_id, department_id, summary, priority, workflow_id)
    values (v_cmd, 'contribution', v_owner, coalesce(v_dept,''),
            'Contribution required by the command plan for ' || v_child || ': '
              || left(coalesce(p_text,''), 1500),
            c.priority, nullif(v_wf_selected,''))
    on conflict (command_id, item_kind, role_id) do nothing;
    v_items := v_items + 1;
    v_owners := v_owners || v_owner;
  end loop;

  -- ---- THE WORK (was: an event that a consumer turned into a fifth task) ---------------------
  -- One call, one run, one operational task, one factual event. The task carries command_id, so
  -- the founder's thread can see the work his instruction actually produced.
  if v_wf_selected <> '' and exists (select 1 from public.phase_b_workflow where workflow_id = v_wf_selected) then
    v_kernel := public.fn_kernel_workflow_start(jsonb_build_object(
      'workflow_id', v_wf_selected,
      'business_object_id', 'founder_command:' || v_cmd,
      'source_kind','founder_command',
      'source_ref','founder_command:' || v_cmd,
      'command_id', v_cmd,
      'correlation_id','cmd:' || v_cmd,
      'causation_id','command:' || v_cmd,
      'requested_by', lower(btrim(p_founder_identity)),
      'priority', c.priority,
      'trigger_ctx', jsonb_build_object(
        'intent', c.intent_id, 'outcome', c.outcome, 'confidence', c.confidence,
        'matched_rule_id', c.matched_rule_id,
        'raw_text_hash', encode(sha256(convert_to(coalesce(p_text,''), 'UTF8')), 'hex'),
        'plan_items', v_items)));
    v_task := (v_kernel->>'task_id')::bigint;
    v_start_event := v_kernel->>'event_id';
    if v_task is null then
      raise exception 'command %: the kernel returned no operational task for workflow %',
        v_cmd, v_wf_selected using errcode = '23502';
    end if;
    insert into public.founder_command_task_link (command_id, task_id)
    values (v_cmd, v_task) on conflict do nothing;
    v_tasks := array[v_task];
    -- The command's due date is the founder's, and it is applied to the task the kernel made.
    update public.phase_c_task set due_at = coalesce(due_at, v_due) where task_id = v_task;
  end if;

  insert into public.founder_command_plan (command_id, summary, child_task_count, departments)
  values (v_cmd,
          format('%s: %s. Command owner chief_of_staff; %s plan item(s) and %s operational task(s) against %s%s.',
                 c.intent_id, c.outcome, v_items, cardinality(v_tasks),
                 coalesce(nullif(c.workflow_ids,''), 'no workflow'),
                 case when cardinality(v_overlays) > 0
                      then format('; %s category overlay invocation(s): %s',
                                  cardinality(v_overlays), array_to_string(v_overlays, ', '))
                      else '' end),
          greatest(v_items - 1, 0),
          coalesce((select string_agg(distinct i.department_id, '; ')
                    from public.founder_command_plan_item i
                   where i.command_id = v_cmd and i.department_id <> ''), ''))
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

  -- A command that produced no operational task did not create tasks, and does not claim to.
  if cardinality(v_tasks) > 0 then
    update public.founder_command set state = 'tasks_created', due_at = v_due where command_id = v_cmd;
    v_status := 'tasks_created';
  else
    update public.founder_command set due_at = v_due where command_id = v_cmd;
    v_status := 'routed';
  end if;

  return jsonb_build_object(
    'ok', true, 'command_id', v_cmd, 'status', v_status, 'intent', c.intent_id,
    'outcome', c.outcome, 'interpretation', c.reason,
    'workflow_ids', coalesce((select jsonb_agg(workflow_id order by workflow_id)
                              from public.founder_command_workflow_link where command_id = v_cmd), '[]'::jsonb),
    'task_ids', to_jsonb(v_tasks),
    'owner', 'chief_of_staff', 'primary_owner', coalesce(v_owners[1], 'founder'),
    'child_owners', to_jsonb(v_owners[2:]),
    'category_overlays_invoked', to_jsonb(v_overlays),
    'tasks_created', cardinality(v_tasks),
    'plan_items', v_items,
    'workflow_run_id', (v_kernel->>'run_id')::bigint,
    'step_run_id', (v_kernel->>'step_run_id')::bigint,
    'handoff_run_id', (v_kernel->>'handoff_run_id')::bigint,
    'event_id', v_start_event, 'outbox_id', (v_kernel->>'outbox_id')::bigint,
    'correlation_id', 'cmd:' || v_cmd,
    'blocker', case when cardinality(v_tasks) = 0
                    then 'The interpretation selected no registered workflow, so no operational task was '
                      || 'created. The plan is recorded; name the area and it will route.'
                    else null end,
    'priority', c.priority, 'due_at', v_due,
    'founder_approval_required', (c.outcome = 'REFUND_APPROVAL'),
    'founder_initiated_only', (c.outcome in ('FOUNDER_INITIATED_POLICY_CHANGE','FOUNDER_INITIATED_PHASE_A_CHANGE')),
    'plan_id', v_plan_id, 'trace_id', v_trace);
end $function$;

-- CREATE OR REPLACE preserves the ACL of the existing function, so no REVOKE here — re-revoking a
-- replaced function is how a live grant gets dropped by accident.
