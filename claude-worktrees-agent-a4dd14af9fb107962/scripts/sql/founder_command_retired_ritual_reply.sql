-- "I APPROVE PCCR-00x" IS ANSWERED, NOT BOUNCED.
--
-- Measured on production 5 Sep 2026: six founder_command rows at state 'clarification_required' — command
-- ids 68789, 47113, 47100, 45525, 39505 and 36607 — every one the founder's own "I approve PCCR-00x ..." or
-- "I approve PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1 ...", classified AMBIGUOUS ("no registered command
-- intent matches this instruction") and bounced back to him with a question he could not answer. Phase
-- freezes, PCCR/PACR/PBCR change requests and acceptance-standard signatures were abolished by the founder
-- on 2 September 2026 (memory: phase-freezes-removed-totally). The intent those messages named no longer
-- exists, so there is nothing to clarify and nothing to approve.
--
-- Three things, in one transaction:
--   1. a registered intent CMD-RETIRED-RITUAL and rule CR-005 (rule_order 5, before every other rule,
--      no specificity required) so a future "I approve PCCR-/PACR-/PBCR-nnn" or "... ACCEPTANCE_STANDARD"
--      classifies deterministically and gets the plain reply held in the rule's notes;
--   2. fn_founder_command_submit (full definition from production, one branch added before the AMBIGUOUS
--      branch) closes such a command as 'refused' (the Phase C state for "unsupported, with reason") and
--      returns the reply;
--   3. the six existing rows are resolved through the state model: clarification_required -> interpreting
--      (the only forward transition) -> refused, with a new interpretation row carrying the intent and the
--      reason, so fn_founder_command_thread shows why. Nothing is deleted; the founder's words are untouched.
--
--   node scripts/apply_sql.mjs scripts/sql/founder_command_retired_ritual_reply.sql --apply --ddl
begin;

insert into public.phase_c_command_intent
  (intent_id, intent_name, workflow_id, default_accountable_role_id, command_owner_role_id, classification_mode,
   immediate_task_required, founder_approval_required, founder_initiated_only, default_priority,
   low_confidence_behavior, notes)
values ('CMD-RETIRED-RITUAL', 'retired_governance_ritual_reply', 'NONE', 'chief_of_staff', 'chief_of_staff',
        'deterministic_registry_or_clarification', false, 'NO', 'NO', 'P3', 'reply_only',
        'Phase freezes, PCCR/PACR/PBCR change requests and acceptance-standard signatures were abolished on '
        || '2 Sep 2026. An approval of one is answered with a plain reply and closed; no task, no clarification.')
on conflict (intent_id) do nothing;

insert into public.phase_c_command_rule
  (rule_id, rule_order, pattern, antipattern, intent_id, outcome, workflow_ids, primary_role_id, child_role_ids,
   requires_specificity, priority, notes)
values ('CR-005', 5,
        '(^|[^A-Za-z0-9_])(PCCR|PACR|PBCR)-[0-9]+([^A-Za-z0-9_]|$)|PHASE_[A-E]_[A-Z_]*ACCEPTANCE|(^|[^A-Za-z0-9_])phase [a-e] (change request|freeze|amendment)([^A-Za-z0-9_]|$)',
        '', 'CMD-RETIRED-RITUAL', 'RETIRED_RITUAL_REPLY', '', 'chief_of_staff', '', false, 'P3',
        'Nothing to approve. Phase freezes, PCCR/PACR/PBCR change requests and acceptance-standard signatures '
        || 'were abolished on 2 September 2026: the loops run without them and no signature of yours is waited '
        || 'on. The only decision that still reaches you is a Stripe refund.')
on conflict (rule_id) do nothing;

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

  -- A RETIRED RITUAL GETS A PLAIN REPLY, NOT A CLARIFICATION LOOP (5 Sep 2026). "I approve PCCR-008 ..."
  -- names a Phase C change request; phase freezes, PCCR/PACR/PBCR amendments and acceptance-standard
  -- signatures were abolished on 2 Sep 2026. Six such messages bounced back as "no registered intent"
  -- and sat at clarification_required. Rule CR-005 now classifies them; the reply is the rule's note
  -- (recorded on the interpretation row) and the command closes as refused: unsupported, with reason.
  if c.outcome = 'RETIRED_RITUAL_REPLY' then
    update public.founder_command set state = 'refused', closed_at = now() where command_id = v_cmd;
    return jsonb_build_object('ok', true, 'command_id', v_cmd, 'status','refused',
      'intent', c.intent_id, 'interpretation', c.reason, 'workflow_ids','[]'::jsonb,
      'task_ids','[]'::jsonb, 'owner','chief_of_staff', 'tasks_created', 0,
      'reply', (select r.notes from public.phase_c_command_rule r where r.rule_id = c.matched_rule_id),
      'blocker', 'Nothing to approve: the ritual this names was retired on 2 September 2026.',
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
end $function$
;

-- 3. the six rows that bounced. Each gets an interpretation row naming the retired ritual, then walks
--    clarification_required -> interpreting -> refused through the guarded state model (the trace root is
--    advanced by a00_founder_command_trace_guard on each step).
insert into public.founder_command_interpretation
  (command_id, version, intent_id, confidence, matched_rule_id, workflow_ids, specificity_signals, reason)
select c.command_id,
       1 + coalesce((select max(i.version) from public.founder_command_interpretation i where i.command_id = c.command_id), 0),
       'CMD-RETIRED-RITUAL', 1.0, 'CR-005', '', '',
       'resolved 5 Sep 2026: the message approves a Phase C/D governance ritual (PCCR / acceptance standard) '
       || 'that the founder abolished on 2 Sep 2026; the intent it names no longer exists, so there is nothing '
       || 'to clarify and nothing to approve. Reply: ' || (select r.notes from public.phase_c_command_rule r where r.rule_id = 'CR-005')
  from public.founder_command c
  join public.founder_command_message m on m.message_id = c.message_id
 where c.state = 'clarification_required'
   and m.raw_text ~* '(^|[^A-Za-z0-9_])(PCCR|PACR|PBCR)-[0-9]+([^A-Za-z0-9_]|$)|PHASE_[A-E]_[A-Z_]*ACCEPTANCE';

update public.founder_command c
   set state = 'interpreting'
  from public.founder_command_message m
 where m.message_id = c.message_id and c.state = 'clarification_required'
   and m.raw_text ~* '(^|[^A-Za-z0-9_])(PCCR|PACR|PBCR)-[0-9]+([^A-Za-z0-9_]|$)|PHASE_[A-E]_[A-Z_]*ACCEPTANCE';

update public.founder_command c
   set state = 'refused', closed_at = now(), intent_id = 'CMD-RETIRED-RITUAL', outcome = 'RETIRED_RITUAL_REPLY'
  from public.founder_command_message m
 where m.message_id = c.message_id and c.state = 'interpreting'
   and exists (select 1 from public.founder_command_interpretation i
                where i.command_id = c.command_id and i.intent_id = 'CMD-RETIRED-RITUAL')
   and m.raw_text ~* '(^|[^A-Za-z0-9_])(PCCR|PACR|PBCR)-[0-9]+([^A-Za-z0-9_]|$)|PHASE_[A-E]_[A-Z_]*ACCEPTANCE';

commit;
