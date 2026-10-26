-- THE ROUTINES THAT STILL ADDRESSED A SEAT NOBODY HOLDS
--
-- The founder removed the organisation chart on 7 Sep 2026. Two seats remain: ceo and
-- customer_support. Thirteen routine literals still named chief_of_staff, and one CHECK constraint
-- on founder_command insisted on it, so no founder command could be written at all and every
-- kernel door that opens one raised instead of returning its payload.
--
-- Only the three routines ON THAT PATH are changed here, and only the literal. 314 routines in this
-- schema still name a removed role somewhere; a blind replace across all of them would be a change
-- nobody measured. They are named in the hand-over as remaining work, to be done as each is next
-- touched -- one by one, which is how the founder asked for this rebuild.
--
-- The constraint founder_command_owner_ck was repointed in the same pass: it hard-coded a person
-- rather than a property, and the person is gone.
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
          coalesce(nullif(c.primary_role_id,''), 'ceo'),
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
      'task_ids','[]'::jsonb, 'owner','ceo', 'tasks_created', 0,
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
      'task_ids','[]'::jsonb, 'owner','ceo', 'tasks_created', 0,
      'reply', (select r.notes from public.phase_c_command_rule r where r.rule_id = c.matched_rule_id),
      'blocker', 'Nothing to approve: the ritual this names was retired on 2 September 2026.',
      'trace_id', v_trace);
  end if;

  -- A STATUS ASK GETS THE BRIEF, NOT A CLARIFICATION (6 Sep 2026). "status" typed into the Console —
  -- whose placeholder says "Ask for a status…" — matched CR-020 (command_or_task_status, which needs an
  -- identifier) and bounced back as "I can route this, but not safely yet" (command 81887). Rule CR-004
  -- classifies a bare "status" / "brief" / "how are we doing" as CMD-BRIEF: the reply is the overnight
  -- brief sentence fn_ws_exec_home writes (the same text the Console's "speak the overnight brief"
  -- button reads), the command closes as accepted, and no task is minted.
  if c.outcome = 'BRIEF_REPLY' then
    update public.founder_command set state = 'accepted', closed_at = now() where command_id = v_cmd;
    return jsonb_build_object('ok', true, 'command_id', v_cmd, 'status','accepted',
      'intent', c.intent_id, 'interpretation', c.reason, 'control_command', true,
      'workflow_ids','[]'::jsonb, 'task_ids','[]'::jsonb, 'owner','ceo', 'tasks_created', 0,
      'reply', coalesce(public.fn_ws_exec_home()->>'brief_text', 'The company brief is not available right now.'),
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
      'task_ids','[]'::jsonb, 'owner','ceo', 'tasks_created', 0,
      'clarification', v_qn, 'trace_id', v_trace);
  end if;

  if c.intent_id in ('CMD-STATUS','CMD-CANCEL','CMD-REPRIORITIZE','CMD-EXPLAIN') then
    update public.founder_command set state = 'accepted' where command_id = v_cmd;
    return jsonb_build_object('ok', true, 'command_id', v_cmd, 'status','accepted',
      'intent', c.intent_id, 'interpretation', c.reason, 'control_command', true,
      'workflow_ids','[]'::jsonb, 'task_ids','[]'::jsonb, 'owner','ceo',
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
  v_owner := coalesce(nullif(c.primary_role_id, ''), v_intent.default_accountable_role_id, 'ceo');
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
              coalesce(v_ov->>'return_owner', coalesce(v_owners[1], 'ceo')),
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
          format('%s: %s. Command owner ceo; %s plan item(s) and %s operational task(s) against %s%s.',
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
    'owner', 'ceo', 'primary_owner', coalesce(v_owners[1], 'founder'),
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

CREATE OR REPLACE FUNCTION public.fn_kernel_trigger_submit(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_class     text  := nullif(btrim(coalesce(p_input->>'source_class','')), '');
  v_system    text  := nullif(btrim(coalesce(p_input->>'source_system','')), '');
  v_ref       text  := nullif(btrim(coalesce(p_input->>'source_ref','')), '');
  v_ext       text  := nullif(btrim(coalesce(p_input->>'external_ref','')), '');
  v_type_in   text  := nullif(btrim(coalesce(p_input->>'trigger_type','')), '');
  v_by        text  := nullif(btrim(coalesce(p_input->>'requested_by','')), '');
  v_payload   jsonb := coalesce(p_input->'raw_payload', '{}'::jsonb);
  v_version   bigint := coalesce(nullif(p_input->>'object_version','')::bigint, 1);
  v_priority  text  := coalesce(nullif(p_input->>'priority',''), 'P2');
  v_idem      text;
  v_corr      text;
  v_caus      text;
  v_inbox     bigint;
  v_trace     bigint;
  v_obj       text;
  v_key       text;
  v_val       text;
  v_missing   text;
  v_start     jsonb;
  v_run       bigint;
  v_status    text;
  v_reason    text;
  v_actor     text;
  v_kind      text;
  v_owner     text;
  v_step_owner text;
  v_step_id   text;
  -- Scalars, never a RECORD: a plpgsql RECORD assigned only inside an if-branch raises when it is
  -- read, and a SELECT INTO that matched nothing NULLs every target rather than leaving the
  -- initialiser. Both traps have already been paid for in this estate.
  t_workflow  text;
  t_rule      text;
  t_sources   text[];
  t_actor     text;
  t_activation text;
  t_impl      text;
  t_class     text;
  t_note      text;
  p_inbox     bigint;
  p_status    text;
  p_run       bigint;
  p_trace     bigint;
  p_type      text;
  p_wf        text;
  p_obj       text;
  p_reason    text;
begin
  -- ---- 0. a consumer may never drive the request side --------------------------------------
  perform public.fn_kernel_assert_not_in_delivery('fn_kernel_trigger_submit');

  -- ---- 1. envelope. A malformed envelope has nothing recordable in it ----------------------
  --
  -- These raise rather than record: source_class is CHECK-constrained and requested_by is NOT NULL,
  -- so a row cannot be written to hold the refusal. Everything that CAN be recorded is recorded
  -- below instead of raised.
  if v_class is null or v_system is null or v_ref is null or v_type_in is null or v_by is null then
    raise exception
      'fn_kernel_trigger_submit: source_class, source_system, source_ref, trigger_type and '
      'requested_by are all required (got %, %, %, %, %)',
      coalesce(v_class,'(null)'), coalesce(v_system,'(null)'), coalesce(v_ref,'(null)'),
      coalesce(v_type_in,'(null)'), coalesce(v_by,'(null)')
      using errcode = '22023';
  end if;
  if jsonb_typeof(v_payload) <> 'object' then
    raise exception 'fn_kernel_trigger_submit: raw_payload must be a json object, got %',
      jsonb_typeof(v_payload) using errcode = '22023';
  end if;
  if v_class not in ('customer_event','supplier_event','scheduled_event','deadline_sla_event',
                     'kpi_deviation_event','system_health_event','webhook_provider_event',
                     'workflow_followup_event') then
    raise exception 'fn_kernel_trigger_submit: % is not one of the eight registered source classes',
      v_class using errcode = '22023';
  end if;

  -- The idempotency key is the external identity of the request. Defaulted from the source's own
  -- reference, never from now() or from a sequence: a key that is different every time is not a key.
  v_idem := coalesce(nullif(btrim(p_input->>'idempotency_key'),''),
                     v_system || ':' || coalesce(v_ext, v_ref));
  v_corr := coalesce(nullif(btrim(p_input->>'correlation_id'),''), 'trigger:' || v_idem);
  v_caus := coalesce(nullif(btrim(p_input->>'causation_id'),''), v_system || ':' || v_ref);

  -- ---- 2. idempotency, before anything is resolved and before anything is created ----------
  insert into public.kernel_trigger_inbox
    (source_class, source_system, source_ref, external_ref, raw_payload,
     correlation_id, causation_id, idempotency_key, status, requested_by)
  values (v_class, v_system, v_ref, v_ext, v_payload, v_corr, v_caus, v_idem, 'pending', v_by)
  on conflict (idempotency_key) do nothing
  returning inbox_id into v_inbox;

  if v_inbox is null then
    -- Seen before. Return the FIRST result and create nothing: no run, no task, no event, and no
    -- second inbox row. The first row's decision is the answer, whatever it was.
    select i.inbox_id, i.status, i.run_id, i.trace_id, i.trigger_type, i.workflow_id,
           i.business_object_id, i.refusal_reason
      into p_inbox, p_status, p_run, p_trace, p_type, p_wf, p_obj, p_reason
      from public.kernel_trigger_inbox i where i.idempotency_key = v_idem;
    -- An empty read here would mean the conflicting row belongs to a transaction that has not
    -- committed. Returning a jsonb full of nulls would make "someone else is mid-flight" look
    -- exactly like "refused with no reason", so it raises instead.
    if p_inbox is null then
      raise exception
        'fn_kernel_trigger_submit: idempotency key % conflicted but no committed row holds it — a '
        'concurrent submission of the same key is still open. Retry.', v_idem
        using errcode = '40001';
    end if;
    return jsonb_build_object(
      'ok', p_status in ('accepted','duplicate'), 'duplicate', true, 'status', p_status,
      'inbox_id', p_inbox, 'idempotency_key', v_idem, 'trigger_type', p_type,
      'workflow_id', p_wf, 'business_object_id', p_obj, 'run_id', p_run, 'trace_id', p_trace,
      'refusal_reason', p_reason,
      'created', jsonb_build_object('inbox_row',0,'run',0,'step_run',0,'task',0,'event',0),
      'note','idempotency_key already recorded; the first result is returned and nothing was created');
  end if;

  -- ---- 3. normalize to a REGISTERED trigger type -------------------------------------------
  select t.workflow_id, t.business_object_rule, t.allowed_source_systems, t.system_actor_id,
         t.activation_state, t.implementation_state, t.source_class, t.accountable_note
    into t_workflow, t_rule, t_sources, t_actor, t_activation, t_impl, t_class, t_note
    from public.kernel_trigger_type t where t.trigger_type = v_type_in;

  v_status := null; v_reason := null;

  if t_class is null then
    v_status := 'refused';
    v_reason := format('no registered trigger type named %s. An unmapped trigger is recorded and '
                    || 'refused; it is never resolved to the nearest workflow.', v_type_in);
  elsif t_class is distinct from v_class then
    v_status := 'refused';
    v_reason := format('trigger type %s is registered under source class %s and was submitted as %s',
                       v_type_in, t_class, v_class);
  elsif not (v_system = any (t_sources)) then
    v_status := 'refused';
    v_reason := format('source system %s is not permitted to submit %s. Permitted: %s',
                       v_system, v_type_in, array_to_string(t_sources, ', '));
  elsif t_impl = 'DEFERRED_HANDLER' then
    v_status := 'deferred';
    v_reason := format('trigger type %s is a DEFERRED_HANDLER: the frozen Phase B registry declares '
                    || 'no workflow that starts from this signal. %s', v_type_in, t_note);
  elsif t_activation <> 'active' then
    v_status := 'refused';
    v_reason := format('trigger type %s is registered with activation_state %s and does not accept '
                    || 'submissions', v_type_in, t_activation);
  end if;

  -- ---- 4. resolve the business object BY THE RECORDED RULE ---------------------------------
  if v_status is null then
    v_obj := t_rule;
    -- regexp_matches is set-returning, so it is driven by a FOR loop and never placed inside a
    -- boolean expression: a set-returning function in a boolean expression raises 42804.
    for v_key in select rr.mk[1] from regexp_matches(t_rule, '\{([a-zA-Z0-9_]+)\}', 'g') as rr(mk) loop
      v_val := nullif(btrim(coalesce(v_payload->>v_key,'')), '');
      if v_val is null then
        v_missing := coalesce(v_missing || ', ', '') || v_key;
      else
        v_obj := replace(v_obj, '{' || v_key || '}', v_val);
      end if;
    end loop;

    if v_missing is not null then
      v_status := 'refused';
      v_reason := format('business object rule %s needs payload key(s) %s and the payload does not '
                      || 'carry them. The object is refused, not guessed.', t_rule, v_missing);
    elsif v_obj ~ '[{}]' then
      v_status := 'refused';
      v_reason := format('business object rule %s did not fully resolve: %s', t_rule, v_obj);
    end if;
  end if;

  -- ---- 5. the founder boundary, checked again at call time ---------------------------------
  --
  -- The registry guard in §1 refuses such a row at write time. This is the second check, because a
  -- row could predate the guard, and because "normal autonomous work never routes through the
  -- founder or the Chief of Staff" is the kind of rule that must hold even when the table is wrong.
  if v_status is null then
    select kind, role_id into v_kind, v_owner
      from public.fn_phase_c_resolve_actor(
        (select w.accountable_role_id from public.phase_b_workflow w where w.workflow_id = t_workflow));
    select s.step_id, r.role_id into v_step_id, v_step_owner
      from public.phase_b_workflow_step s,
           lateral public.fn_phase_c_resolve_actor(s.accountable_role_id) r
     where s.workflow_id = t_workflow and s.step_no = 1;

    if v_owner is null or v_kind is distinct from 'canonical' then
      v_status := 'refused';
      v_reason := format('workflow %s names accountable role that resolves to %s — no run created',
                         t_workflow, coalesce(v_kind,'nothing'));
    elsif v_owner in ('founder','ceo') or coalesce(v_step_owner,'') in ('founder','ceo') then
      v_status := 'refused';
      v_reason := format('workflow %s would put autonomous work on %s / %s (step %s). Normal '
                      || 'autonomous work bypasses both the founder and the Chief of Staff.',
                         t_workflow, v_owner, coalesce(v_step_owner,'(none)'), coalesce(v_step_id,'(none)'));
    end if;
  end if;

  -- ---- 6. refusals and deferrals are RECORDED, with their own trace ------------------------
  if v_status is not null then
    v_actor := coalesce(t_actor, 'system.webhook_receiver');
    v_trace := public.fn_kernel_intake_execution('dbfn:fn_kernel_trigger_submit(jsonb)', jsonb_build_object(
      'subject_kind','trigger_inbox', 'subject_ref', v_inbox::text,
      'system_actor_id', v_actor,
      'actor_role_id', coalesce(nullif(v_owner,''), ''),
      'component_id','dbfn:fn_kernel_trigger_submit(jsonb)',
      'authority_result', v_status || ': ' || v_reason,
      'input_hash', encode(sha256(convert_to(v_idem || '|' || v_payload::text, 'UTF8')), 'hex'),
      'evidence_refs', jsonb_build_array(jsonb_build_object(
        'source_class', v_class, 'source_system', v_system, 'source_ref', v_ref,
        'external_ref', v_ext, 'submitted_trigger_type', v_type_in,
        'idempotency_key', v_idem, 'raw_payload', v_payload)),
      'state_before','pending', 'state_after', v_status, 'status','sealed'));

    update public.kernel_trigger_inbox
       set status = v_status, refusal_reason = v_reason, trace_id = v_trace,
           trigger_type = (case when t_class is null then null else v_type_in end),
           processed_at = now()
     where inbox_id = v_inbox;

    return jsonb_build_object(
      'ok', false, 'duplicate', false, 'status', v_status, 'inbox_id', v_inbox,
      'idempotency_key', v_idem, 'trigger_type', v_type_in, 'workflow_id', t_workflow,
      'business_object_id', null, 'run_id', null, 'trace_id', v_trace,
      'refusal_reason', v_reason, 'correlation_id', v_corr, 'causation_id', v_caus,
      'created', jsonb_build_object('inbox_row',1,'run',0,'step_run',0,'task',0,'event',0));
  end if;

  -- ---- 7. THE ONLY creator of business work is called ---------------------------------------
  --
  -- No insert into phase_c_task, phase_c_workflow_run, phase_c_workflow_step_run,
  -- phase_c_handoff_run or phase_c_event_outbox appears anywhere in this function. All six objects
  -- come from fn_kernel_workflow_start, atomically, or none of them does.
  v_start := public.fn_kernel_workflow_start(jsonb_build_object(
    'workflow_id',        t_workflow,
    'business_object_id', v_obj,
    'object_version',     v_version,
    'source_kind',        'autonomous',
    'source_ref',         'trigger_inbox:' || v_inbox,
    'correlation_id',     v_corr,
    'causation_id',       v_caus,
    'requested_by',       v_by,
    'priority',           v_priority,
    'trigger_ctx',        jsonb_build_object(
        'inbox_id', v_inbox, 'trigger_type', v_type_in, 'source_class', v_class,
        'source_system', v_system, 'source_ref', v_ref, 'external_ref', v_ext,
        'idempotency_key', v_idem, 'business_object_rule', t_rule, 'raw_payload', v_payload)));

  v_run    := (v_start->>'run_id')::bigint;
  v_status := case when coalesce((v_start->>'duplicate')::boolean, false)
                   then 'duplicate' else 'accepted' end;

  if v_run is null then
    raise exception 'fn_kernel_trigger_submit: fn_kernel_workflow_start returned no run_id for % / %',
      t_workflow, v_obj using errcode = '23502';
  end if;

  -- ---- 8. the adapter's own execution trace, parented to the run's root --------------------
  v_trace := public.fn_kernel_intake_execution('dbfn:fn_kernel_trigger_submit(jsonb)', jsonb_build_object(
    'subject_kind','trigger_inbox', 'subject_ref', v_inbox::text,
    'run_id', v_run, 'step_run_id', (v_start->>'step_run_id')::bigint,
    'task_id', (v_start->>'task_id')::bigint,
    'system_actor_id', t_actor,
    'actor_role_id', v_start->>'step_accountable_role_id',
    'manager_role_id', v_start->>'accountable_role_id',
    'component_id','dbfn:fn_kernel_trigger_submit(jsonb)',
    'authority_result', v_status || ': trigger type ' || v_type_in || ' -> ' || t_workflow
                     || ' by registry, business object by rule ' || t_rule,
    'input_hash', encode(sha256(convert_to(v_idem || '|' || v_payload::text, 'UTF8')), 'hex'),
    'output_hash', encode(sha256(convert_to(v_start::text, 'UTF8')), 'hex'),
    'evidence_refs', jsonb_build_array(jsonb_build_object(
      'source_class', v_class, 'source_system', v_system, 'source_ref', v_ref,
      'external_ref', v_ext, 'idempotency_key', v_idem,
      'business_object_rule', t_rule, 'business_object_id', v_obj, 'raw_payload', v_payload)),
    'event_ids', jsonb_build_array(v_start->>'event_id'),
    'state_before','pending', 'state_after', v_status, 'status','sealed',
    'parent_trace_id', (v_start->>'run_trace_id')::bigint));

  update public.kernel_trigger_inbox
     set status = v_status, trigger_type = v_type_in, workflow_id = t_workflow,
         business_object_id = v_obj, run_id = v_run, trace_id = v_trace, processed_at = now()
   where inbox_id = v_inbox;

  return jsonb_build_object(
    'ok', true, 'duplicate', (v_status = 'duplicate'), 'status', v_status,
    'inbox_id', v_inbox, 'idempotency_key', v_idem,
    'source_class', v_class, 'trigger_type', v_type_in, 'workflow_id', t_workflow,
    'business_object_id', v_obj, 'object_version', v_version,
    'run_id', v_run, 'step_run_id', (v_start->>'step_run_id')::bigint,
    'task_id', (v_start->>'task_id')::bigint,
    'accountable_role_id', v_start->>'accountable_role_id',
    'step_accountable_role_id', v_start->>'step_accountable_role_id',
    'handoff_run_id', (v_start->>'handoff_run_id')::bigint,
    'event_id', v_start->>'event_id', 'outbox_id', (v_start->>'outbox_id')::bigint,
    'trace_id', v_trace, 'run_trace_id', (v_start->>'run_trace_id')::bigint,
    'correlation_id', v_corr, 'causation_id', v_caus, 'system_actor_id', t_actor,
    'created', jsonb_build_object(
      'inbox_row', 1,
      'run',      (case when v_status = 'duplicate' then 0 else 1 end),
      'step_run', (case when v_status = 'duplicate' then 0 else 1 end),
      'task',     (case when v_status = 'duplicate' then 0 else 1 end),
      'event',    (case when v_status = 'duplicate' then 0 else 1 end),
      'adapter_trace', 1));
end
$function$;

CREATE OR REPLACE FUNCTION public.fn_kernel_workflow_start(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_pd_dispatch jsonb := '{}'::jsonb;  -- D36
  w  public.phase_b_workflow%rowtype;
  s  public.phase_b_workflow_step%rowtype;
  v_wf        text   := nullif(btrim(coalesce(p_input->>'workflow_id','')), '');
  v_object    text   := nullif(btrim(coalesce(p_input->>'business_object_id','')), '');
  v_source_k  text   := nullif(btrim(coalesce(p_input->>'source_kind','')), '');
  v_source_r  text   := nullif(btrim(coalesce(p_input->>'source_ref','')), '');
  v_by        text   := nullif(btrim(coalesce(p_input->>'requested_by','')), '');
  v_command   bigint := nullif(p_input->>'command_id','')::bigint;
  v_version   bigint := coalesce(nullif(p_input->>'object_version','')::bigint, 1);
  v_priority  text   := coalesce(nullif(p_input->>'priority',''), 'P2');
  v_ctx       jsonb  := coalesce(p_input->'trigger_ctx', '{}'::jsonb);
  v_corr      text;
  v_caus      text;
  v_dedupe    text;
  v_run       bigint;
  v_step_run  bigint;
  v_task      bigint;
  v_outbox    bigint;
  v_run_trace bigint;
  v_step_trace bigint;
  v_task_trace bigint;
  v_task_parent bigint;
  v_owner     text;
  v_step_owner text;
  v_kind      text;
  v_start_event text;
  v_input_hash text;
  -- Scalars, not a RECORD: a plpgsql record read after a SELECT INTO that matched nothing is a
  -- trap this estate has already paid for once.
  v_prior_run   bigint;
  v_prior_state text;
  v_prior_trace bigint;
  v_prior_step  bigint;
  v_prior_task  bigint;
begin
  -- ---- 0. a consumer may not re-enter the producer ----------------------------------------
  perform public.fn_kernel_assert_not_in_delivery('fn_kernel_workflow_start');

  if v_wf is null or v_object is null or v_source_r is null or v_by is null then
    raise exception 'fn_kernel_workflow_start: workflow_id, business_object_id, source_ref and requested_by are all required (got %, %, %, %)',
      coalesce(v_wf,'(null)'), coalesce(v_object,'(null)'), coalesce(v_source_r,'(null)'), coalesce(v_by,'(null)')
      using errcode = '22023';
  end if;
  if v_source_k not in ('founder_command','autonomous') then
    raise exception 'fn_kernel_workflow_start: source_kind must be founder_command or autonomous, got %',
      coalesce(v_source_k,'(null)') using errcode = '22023';
  end if;
  if v_source_k = 'founder_command' and v_command is null then
    raise exception 'fn_kernel_workflow_start: source_kind founder_command requires a command_id'
      using errcode = '22023';
  end if;
  v_corr := coalesce(nullif(btrim(p_input->>'correlation_id'),''), v_source_r);
  v_caus := coalesce(nullif(btrim(p_input->>'causation_id'),''), v_source_r);

  -- ---- (a) the workflow run ---------------------------------------------------------------
  select * into w from public.phase_b_workflow where workflow_id = v_wf;
  if not found then
    raise exception 'fn_kernel_workflow_start (a): % is not in the frozen Phase B workflow registry — fail closed',
      v_wf using errcode = '23503';
  end if;

  -- The accountable role comes from the registry and must RESOLVE. Never defaulted; there is no
  -- ceo fallback here and there will not be one.
  select kind, role_id into v_kind, v_owner from public.fn_phase_c_resolve_actor(w.accountable_role_id);
  if v_owner is null or v_kind is distinct from 'canonical' then
    raise exception 'fn_kernel_workflow_start (a): workflow % names accountable role %, which resolves to % — no run created',
      v_wf, w.accountable_role_id, coalesce(v_kind,'nothing') using errcode = '23514';
  end if;

  -- The start event is read from the frozen registry, never concatenated. A literal
  -- 'EV-W01-STARTED' once announced W01 for every command the company had ever received.
  v_start_event := public.fn_phase_c_lifecycle_event(v_wf, 'started');
  if v_start_event is null then
    raise exception 'fn_kernel_workflow_start (f): workflow % declares no .started event in phase_b_event',
      v_wf using errcode = '23503';
  end if;

  -- Idempotency, unchanged in shape from fn_phase_c_workflow_start so existing runs still match.
  v_dedupe := v_wf || ':' || v_object || ':' || v_version::text;
  select r.run_id, r.state, r.trace_id
    into v_prior_run, v_prior_state, v_prior_trace
    from public.phase_c_workflow_run r where r.dedupe_key = v_dedupe;
  if v_prior_run is not null then
    select sr.step_run_id into v_prior_step from public.phase_c_workflow_step_run sr
     where sr.run_id = v_prior_run order by sr.step_run_id limit 1;
    select t.task_id into v_prior_task from public.phase_c_task t
     where t.run_id = v_prior_run order by t.task_id limit 1;
    -- A second call creates NOTHING. Not a new run, not a second task, not a second event.
    return jsonb_build_object('ok', true, 'duplicate', true, 'run_id', v_prior_run,
      'workflow_id', v_wf, 'business_object_id', v_object, 'object_version', v_version,
      'state', v_prior_state, 'step_run_id', v_prior_step,
      'task_id', v_prior_task, 'trace_id', v_prior_trace,
      'dedupe_key', v_dedupe, 'created', '{}'::jsonb);
  end if;

  v_input_hash := encode(sha256(convert_to(
    v_wf || '|' || v_object || '|' || v_version::text || '|' || v_ctx::text, 'UTF8')), 'hex');

  insert into public.phase_c_workflow_run
    (workflow_id, business_object_id, object_version, start_event, accountable_role_id,
     state, dedupe_key, command_id)
  values (v_wf, v_object, v_version, v_start_event, v_owner, 'queued', v_dedupe, v_command)
  returning run_id into v_run;
  if v_run is null then
    raise exception 'fn_kernel_workflow_start (a): the workflow run insert produced no row for %', v_wf
      using errcode = '23502';
  end if;

  -- ---- (d.1) the ROOT trace, before anything hangs from it ---------------------------------
  v_run_trace := public.fn_phase_c_trace_write('TRACE-WORKFLOW', jsonb_build_object(
    'subject_kind','workflow_run', 'subject_ref', v_run::text, 'run_id', v_run,
    'command_id', v_command,
    'actor_role_id', v_owner, 'system_actor_id','system.workflow_engine',
    'input_hash', v_input_hash,
    'evidence_refs', jsonb_build_array(jsonb_build_object(
      'business_object_id', v_object, 'dedupe_key', v_dedupe, 'source_kind', v_source_k,
      'source_ref', v_source_r, 'requested_by', v_by, 'trigger_ctx', v_ctx)),
    'event_ids', jsonb_build_array(v_start_event),
    'state_before','', 'state_after','queued', 'status','open'));
  update public.phase_c_workflow_run set trace_id = v_run_trace where run_id = v_run;
  if v_run_trace is null then
    raise exception 'fn_kernel_workflow_start (d): the run has no root trace' using errcode = '23502';
  end if;

  -- The run is ACTIVE because its first step run is opened in this same transaction. The move is
  -- made as a declared transition (queued -> active) so z20_phase_c_workflow_state_guard and
  -- phase_b_workflow_transition are load-bearing rather than decorative.
  update public.phase_c_workflow_run set state = 'active' where run_id = v_run;

  -- ---- (b) the initial step run, at the REGISTRY entry step --------------------------------
  select * into s from public.phase_b_workflow_step
   where workflow_id = v_wf and step_no = 1;               -- UNIQUE (workflow_id, step_no)
  if not found then
    raise exception 'fn_kernel_workflow_start (b): workflow % declares no step_no = 1', v_wf
      using errcode = '23502';
  end if;

  select kind, role_id into v_kind, v_step_owner from public.fn_phase_c_resolve_actor(s.accountable_role_id);
  if v_step_owner is null or v_kind is distinct from 'canonical' then
    raise exception 'fn_kernel_workflow_start (c): step % names owner %, which resolves to % — no task created',
      s.step_id, s.accountable_role_id, coalesce(v_kind,'nothing') using errcode = '23514';
  end if;

  insert into public.phase_c_workflow_step_run
    (run_id, step_id, accountable_role_id, reviewer_role_id, state, attempt_no,
     input_hash, output_hash, gates_evaluated, authority_result, idempotency_key)
  values (v_run, s.step_id, v_step_owner, coalesce(s.independent_reviewer_role_id,''), 'active', 1,
          v_input_hash, '', '[]'::jsonb, 'pending: the step has not been executed yet',
          s.idempotency_scope || '|' || v_run || '|' || s.step_id || '|kernel')
  returning step_run_id into v_step_run;
  if v_step_run is null then
    raise exception 'fn_kernel_workflow_start (b): the step run insert produced no row for %', s.step_id
      using errcode = '23502';
  end if;

  -- The step run gets its own TRACE-STEP, parented to the run's root. phase_c_workflow_step_run
  -- has no trace guard trigger (only phase_c_task does), so an active step run with trace_id NULL
  -- is exactly what nobody notices — the first rehearsal of this file measured 6 of 11 step runs
  -- in that state, two of them created by this function.
  v_step_trace := public.fn_phase_c_trace_write('TRACE-STEP', jsonb_build_object(
    'subject_kind','step_run', 'subject_ref', v_step_run::text,
    'run_id', v_run, 'step_run_id', v_step_run, 'command_id', v_command,
    'actor_role_id', v_step_owner, 'system_actor_id','system.workflow_engine',
    'reviewer_role_id', coalesce(s.independent_reviewer_role_id,''),
    'authority_result','pending: the step has not been executed yet',
    'input_hash', v_input_hash,
    'evidence_refs', jsonb_build_array(jsonb_build_object(
      'step_id', s.step_id, 'step_name', s.step_name, 'entry_condition', s.entry_condition)),
    'state_before','', 'state_after','active', 'status','open'));
  update public.phase_c_workflow_step_run set trace_id = v_step_trace where step_run_id = v_step_run;
  update public.phase_c_trace set parent_trace_id = v_run_trace where trace_id = v_step_trace;
  if v_step_trace is null then
    raise exception 'fn_kernel_workflow_start (d): step run % has no trace', v_step_run
      using errcode = '23502';
  end if;

  -- ---- (c) EXACTLY ONE operational task -----------------------------------------------------
  -- Deterministic key. It is also the key the invariant check looks for: a founder command may
  -- have run:N:step:* work or cmd:N:* plan rows, never both.
  v_task := public.fn_phase_c_task_create(jsonb_build_object(
    'source_kind', v_source_k, 'source_ref', v_source_r,
    'command_id', v_command, 'run_id', v_run, 'workflow_id', v_wf, 'step_id', s.step_id,
    'accountable_role_id', v_step_owner,
    'objective', format('%s — %s: perform %s (%s) for %s.',
                        w.workflow_name, v_start_event, s.step_id, s.step_name, v_object),
    'required_inputs', s.required_inputs,
    'requested_output', s.required_output,
    'acceptance_criteria', s.acceptance_criteria,
    'closure_criteria', s.closure_criteria,
    'priority', v_priority,
    'reviewer_required', (coalesce(s.independent_reviewer_role_id,'') <> ''),
    'reviewer_role_id', coalesce(s.independent_reviewer_role_id,''),
    'idempotency_key', 'run:' || v_run || ':step:' || s.step_id));
  if v_task is null then
    raise exception 'fn_kernel_workflow_start (c): no operational task was created for run % step %',
      v_run, s.step_id using errcode = '23502';
  end if;

  -- ---- (d.2) the CHILD trace for the task, parented -----------------------------------------
  -- a00_phase_c_task_trace_guard mints it on INSERT and parents it to the command trace when the
  -- task carries a command_id, otherwise to the run trace. Both are roots; what is refused here is
  -- a task hanging from nothing.
  select trace_id into v_task_trace from public.phase_c_task where task_id = v_task;
  select parent_trace_id into v_task_parent from public.phase_c_trace where trace_id = v_task_trace;
  if v_task_trace is null or v_task_parent is null then
    raise exception 'fn_kernel_workflow_start (d): task % has trace % with parent % — a task without its parented trace is refused',
      v_task, coalesce(v_task_trace::text,'null'), coalesce(v_task_parent::text,'null')
      using errcode = '23502';
  end if;

  -- ---- (e) NO HANDOFF AT START -- K14 -------------------------------------------------------
  -- Deliberately empty, and named so a reader looking for the block that used to be here finds the
  -- reason rather than a gap. The entry step's outgoing handoff run is created by
  -- fn_kernel_step_complete when that step completes, from its accepted output. Creating it here
  -- as well produced TWO open handoff runs on one registry edge the moment the entry step
  -- completed, and the successor step could then never be opened.

  -- ---- (f) ONE factual event ----------------------------------------------------------------
  -- Emitted LAST, after the state it describes exists. Its consumer may not create any of it.
  v_outbox := public.fn_kernel_outbox_emit(jsonb_build_object(
    'event_id', v_start_event, 'producer', 'kernel:workflow_start',
    'object_version', v_version,
    'correlation_id', v_corr, 'causation_id', v_caus, 'source_id', v_source_r,
    'command_id', v_command, 'workflow_run_id', v_run, 'step_run_id', v_step_run,
    'trace_id', v_run_trace,
    'dedupe_value', 'kernel:started:' || v_dedupe,
    'payload', jsonb_build_object(
      'fact','workflow.started',
      'workflow_id', v_wf, 'workflow_run_id', v_run, 'step_id', s.step_id,
      'step_run_id', v_step_run, 'task_id', v_task, 'handoff_run_id', null,
      'business_object_id', v_object, 'object_version', v_version,
      'accountable_role_id', v_owner, 'step_accountable_role_id', v_step_owner,
      'source_kind', v_source_k, 'source_ref', v_source_r, 'requested_by', v_by,
      'trace_id', v_run_trace, 'input_hash', v_input_hash)));
  if v_outbox is null then
    raise exception 'fn_kernel_workflow_start (f): no event row was written for run %', v_run
      using errcode = '23502';
  end if;

  -- ---- all or nothing -----------------------------------------------------------------------
  if v_run is null or v_step_run is null or v_task is null or v_outbox is null
     or v_run_trace is null or v_step_trace is null or v_task_trace is null then
    raise exception 'fn_kernel_workflow_start incomplete: run=% step_run=% task=% outbox=% run_trace=% step_trace=% task_trace=%',
      v_run, v_step_run, v_task, v_outbox, v_run_trace, v_step_trace, v_task_trace
      using errcode = '23502';
  end if;

  -- ---- (g) PHASE D DISPATCH (D36) --------------------------------------------------------------
  -- THE FIRST STEP OF A RUN IS OPENED HERE, INLINE — this routine does not call fn_kernel_open_step.
  -- Wiring the dispatch only into fn_kernel_open_step therefore reached successors and handoffs and
  -- missed every run's first step, which is the step an autonomous arrival actually causes. Both
  -- openers call the same routine so the two paths cannot drift apart.
  v_pd_dispatch := public.fn_phase_d_dispatch_step(jsonb_build_object(
    'step_run_id', v_step_run, 'actor_role_id', v_step_owner,
    'opened_by_kind', v_source_k, 'opened_by_ref', v_source_r,
    'idempotency_key', s.idempotency_scope || '|' || v_run || '|' || s.step_id || '|kernel',
    'correlation_id', v_corr));

  return jsonb_build_object(
    'ok', true, 'duplicate', false,
    'run_id', v_run, 'workflow_id', v_wf, 'workflow_name', w.workflow_name,
    'business_object_id', v_object, 'object_version', v_version, 'dedupe_key', v_dedupe,
    'state','active', 'accountable_role_id', v_owner,
    'step_id', s.step_id, 'step_run_id', v_step_run, 'step_accountable_role_id', v_step_owner,
    'task_id', v_task, 'task_idempotency_key', 'run:' || v_run || ':step:' || s.step_id,
    'handoff_run_id', null, 'handoff_id', null,
    'run_trace_id', v_run_trace, 'step_trace_id', v_step_trace,
    'task_trace_id', v_task_trace, 'handoff_trace_id', null,
    'event_id', v_start_event, 'outbox_id', v_outbox,
    'correlation_id', v_corr, 'causation_id', v_caus, 'source_id', v_source_r,
    'command_id', v_command, 'source_kind', v_source_k, 'requested_by', v_by,
    'created', jsonb_build_object('run',1, 'step_run',1, 'task',1, 'traces',
      3,
      'handoff', 0, 'event',1));
end $function$;


CREATE OR REPLACE FUNCTION public.fn_phase_d_founder_authority_fixture(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_run   bigint := public.fn_phase_d_fixture_context();
  v_label text   := nullif(btrim(coalesce(p_input->>'label','')),'');
  v_id    bigint;
  v_msg   bigint;
  v_text  text;
  v_trace bigint;   -- G19: the root trace the guard requires before the command may move
begin
  if v_run is null then
    raise exception 'fn_phase_d_founder_authority_fixture: no verified Phase D fixture context. A founder command fixture exists only inside an audited fixture run, inside a transaction that is aborted. (pd_fixture_no_test_context)'
      using errcode = '42501';
  end if;
  if v_label is null then
    raise exception 'fn_phase_d_founder_authority_fixture: label is required (pd_fixture_label_missing)'
      using errcode = '22023';
  end if;

  v_text := format('PHASE_D_FIXTURE_DO_NOT_PUBLISH — Phase D fixture command for run %s (%s). '
                || 'This is not an instruction from the founder. It exists so that the six rules '
                || 'which resolve founder_authority_ref against public.founder_command have a row '
                || 'to resolve, and it is created inside a transaction that is aborted.',
                   v_run, v_label);

  -- founder_identity is DELIBERATELY a string that resolves to nobody. E39's finding was that a
  -- guard authenticating a string is not authenticating an actor; writing the founder's real
  -- identity here would be the same mistake made on purpose.
  insert into public.founder_command_message
    (founder_identity, raw_text, raw_text_hash, client_idempotency_key, channel)
  values ('PHASE_D_FIXTURE_DO_NOT_PUBLISH',
          v_text,
          encode(sha256(convert_to(v_text,'UTF8')),'hex'),
          format('phase_d_fixture:%s:%s', v_run, v_label),
          'phase_d_fixture')
  returning message_id into v_msg;

  insert into public.founder_command
    (message_id, intent_id, outcome, command_owner_role_id, state, priority, primary_role_id,
     founder_initiated_only, refund_semantics)
  values (v_msg,
          format('PHASE_D_FIXTURE_DO_NOT_PUBLISH:%s', v_label),
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a Phase D fixture founder command. It is not an instruction from the founder, it authorises nothing, and it is created inside a transaction that is aborted.',
          'ceo',
          'received',
          'low',
          'ceo',
          false,
          false)
  returning command_id into v_id;

  -- G19. THE ROOT TRACE, OPENED THE WAY THE ROUTER OPENS IT.
  -- Without this the command is stuck at 'received' for the rest of its life:
  -- fn_founder_command_trace_guard refuses every later transition with "cannot leave received
  -- without a root trace", and that refusal is correct. The command is created at received above
  -- (the one state the guard allows trace-less at birth) and the trace is stamped on it here, in
  -- the same transaction, which is the sequence the guard's own comment describes.
  v_trace := public.fn_phase_c_trace_write('TRACE-FOUNDER-COMMAND', jsonb_build_object(
    'subject_kind',   'founder_command',
    'subject_ref',    v_id::text,
    'command_id',     v_id,
    'actor_role_id',  'ceo',
    'system_actor_id','fn_phase_d_founder_authority_fixture',
    'state_before',   '',
    'state_after',    'received',
    'status',         'open',
    'evidence_refs',  jsonb_build_array(jsonb_build_object(
      'phase_d_fixture_run', v_run, 'label', v_label,
      'note', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — the root trace of a Phase D fixture founder command. It records that this command exists inside an aborted fixture transaction and authorises nothing.'))));

  update public.founder_command set trace_id = v_trace where command_id = v_id;

  perform public.fn_phase_d_scenario_record_write(jsonb_build_object(
    'fixture_id',        'PDS-founder_authority',
    'fixture_version',   1,
    'source_checksum',   encode(sha256(convert_to(v_text,'UTF8')),'hex'),
    'object_id',         'founder_command_fixture',
    'business_key',      v_id::text,
    'owner_ref',         'ceo',
    'ownership_scope',   'COMPANY',
    'state',             'received',
    'canonical_relation','public.founder_command',
    'canonical_service', 'fn_phase_d_founder_authority_fixture',
    'result_reference',  format('public.founder_command:command_id=%s', v_id),
    'contributes_ref',   'founder_authority_ref',
    'contributes_kind',  'RESULT_KEY',
    'contributed_value', format('founder_command:%s', v_id),
    'expected_effect',   'BR-003, BR-021..BR-024 and BR-043 resolve founder_authority_ref against public.founder_command and find this row. It authorises nothing: founder AUTHENTICATION is fn_phase_c_require_founder, which reads a verified auth subject and never this table.'));

  return jsonb_build_object('ok', true, 'command_id', v_id, 'message_id', v_msg,
    'founder_authority_ref', format('founder_command:%s', v_id),
    'founder_identity_on_the_message', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — resolves to nobody',
    'founder_initiated_only', false, 'refund_semantics', false,
    'note','a fixture command; it satisfies "a founder command exists" and nothing else');
end
$function$;

CREATE OR REPLACE FUNCTION public.fn_phase_c_invariants()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_bad bigint; v_pop bigint;
  v_deployed text[];
begin
  -- every routine any binding row names, so a binding cannot claim an undeployed function
  select array_agg(distinct p.proname) into v_deployed
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like 'fn_phase_c%' or p.proname like 'fn_founder_command%';

  -- ---------------------------------------------------------------- organisation properties
  -- 4 SEP 2026 (Phase E): the five rows that stood here compared production to org_phase_baseline —
  -- fn_phase_a_baseline_drift(), fn_phase_b_baseline_drift() and three frozen counts. The founder
  -- removed every phase freeze on 2 Sep, so a board that reddens when the organisation legitimately
  -- changes protected nothing and reddened for bookkeeping. What those rows DEFENDED is a property,
  -- asserted here directly: the organisation has no structural violation (every active department
  -- has a head, every canonical role resolves, no cycle in the reporting graph — see
  -- fn_phase_a_organization_violations), and every effective Phase B erratum is resolved.
  check_name := 'organization_structural_violations'; expected := '0';
  actual := (select count(*)::text from public.fn_phase_a_organization_violations());
  ok := actual = expected; return next;

  check_name := 'phase_b_unresolved_errata'; expected := '0';
  actual := (select count(*)::text from public.fn_phase_b_effective_errata() where not resolved);
  ok := actual = expected; return next;

  -- ---------------------------------------------------------------- binding coverage
  check_name := 'roles_bound';
  expected := (select count(*)::text from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay');
  actual := (select count(*)::text from public.phase_c_role_binding where connection_status = 'CONNECTED');
  ok := actual = expected; return next;

  check_name := 'roles_without_binding'; expected := '0';
  actual := (select count(*)::text from public.org_role r
             where r.status='active' and r.runtime_mode <> 'knowledge_overlay'
               and not exists (select 1 from public.phase_c_role_binding b
                               where b.canonical_role_id = r.role_id
                                  or b.canonical_role_id in (select alias from public.org_role_alias a where a.role_id = r.role_id)));
  ok := actual = expected; return next;

  check_name := 'overlays_bound';
  expected := (select count(*)::text from public.org_role where status='active' and runtime_mode = 'knowledge_overlay');
  actual := (select count(*)::text from public.phase_c_overlay_binding where connection_status = 'CONNECTED');
  ok := actual = expected; return next;

  check_name := 'overlay_bindings_resolve'; expected := '0';
  actual := (select count(*)::text from public.phase_c_overlay_binding b
             where not exists (select 1 from public.org_role r
                               where r.role_id = b.live_role_id and r.status='active'
                                 and r.runtime_mode='knowledge_overlay'));
  ok := actual = expected; return next;

  check_name := 'workflows_bound';
  expected := (select count(*)::text from public.phase_b_workflow);
  actual := (select count(*)::text from public.phase_c_workflow_binding);
  ok := actual = expected; return next;

  check_name := 'workflows_without_binding'; expected := '0';
  actual := (select count(*)::text from public.phase_b_workflow w
             where not exists (select 1 from public.phase_c_workflow_binding b where b.workflow_id = w.workflow_id));
  ok := actual = expected; return next;

  check_name := 'steps_bound_or_classified';
  expected := (select count(*)::text from public.phase_b_workflow_step);
  actual := (select count(*)::text from public.phase_c_step_binding);
  ok := actual = expected; return next;

  check_name := 'steps_without_binding'; expected := '0';
  actual := (select count(*)::text from public.phase_b_workflow_step s
             where not exists (select 1 from public.phase_c_step_binding b where b.step_id = s.step_id));
  ok := actual = expected; return next;

  -- A deferral is only acceptable with an owner, a safe entry boundary and the Phase D work.
  check_name := 'deferred_steps_without_owner_or_action'; expected := '0';
  actual := (select count(*)::text from public.phase_c_step_binding
             where connection_status = 'DEFERRED_RUNTIME_IMPLEMENTATION'
               and (accountable_role_id = '' or canonical_runtime_handler = '' or phase_d_action = ''));
  ok := actual = expected; return next;

  -- "Resolves" here means the FROZEN Phase B rule, not the narrower "is a standing employee":
  -- exactly one of the 257 steps (W14-S05, an analysis step in W14) is owned by the
  -- relevant_category_overlay placeholder, which master spec §12 permits for an analysis step in
  -- W05/W06/W07/W10/W14.  fn_phase_c_step_owner_valid encodes that and nothing wider; the
  -- absolute "an overlay may never own a TASK" guard is separate and unchanged.
  check_name := 'step_owners_resolve'; expected := '0';
  actual := (select count(*)::text from public.phase_c_step_binding b
             where not public.fn_phase_c_step_owner_valid(b.step_id, b.accountable_role_id));
  ok := actual = expected; return next;

  check_name := 'steps_owned_by_overlay_outside_declared_scope'; expected := '0';
  actual := (select count(*)::text from public.phase_c_step_binding b
             join public.phase_b_workflow_step s on s.step_id = b.step_id
             where not public.fn_phase_c_actor_may_own(b.accountable_role_id)
               and not (s.step_type = 'analysis' and s.workflow_id in ('W05','W06','W07','W10','W14')));
  ok := actual = expected; return next;

  check_name := 'handoffs_bound';
  expected := (select count(*)::text from public.phase_b_handoff);
  actual := (select count(*)::text from public.phase_c_handoff_binding);
  ok := actual = expected; return next;

  check_name := 'handoffs_without_binding'; expected := '0';
  actual := (select count(*)::text from public.phase_b_handoff h
             where not exists (select 1 from public.phase_c_handoff_binding b where b.handoff_id = h.handoff_id));
  ok := actual = expected; return next;

  check_name := 'events_classified';
  expected := (select count(*)::text from public.phase_b_event);
  actual := (select count(*)::text from public.phase_c_event_binding);
  ok := actual = expected; return next;

  check_name := 'events_without_producer_or_consumer'; expected := '0';
  actual := (select count(*)::text from public.phase_c_event_binding
             where outbox_writer = '' or delivery_worker = '' or dedupe_key = '');
  ok := actual = expected; return next;

  check_name := 'gates_classified';
  expected := (select count(*)::text from public.phase_b_gate);
  actual := (select count(*)::text from public.phase_c_gate_binding);
  ok := actual = expected; return next;

  check_name := 'rules_classified';
  expected := (select count(*)::text from public.phase_b_business_rule);
  actual := (select count(*)::text from public.phase_c_rule_binding);
  ok := actual = expected; return next;

  -- Every routine a binding names must actually be deployed.  This is the check that stops a
  -- binding CSV from being a document: it re-reads pg_proc.
  check_name := 'bindings_naming_undeployed_routines'; expected := '0';
  actual := (
    with named as (
      select distinct (regexp_match(x, 'public\.(fn_[a-z0-9_]+)'))[1] as fn
      from (
        select gate_enforcer x from public.phase_c_step_binding
        union all select authority_enforcer from public.phase_c_step_binding
        union all select review_enforcer from public.phase_c_step_binding
        union all select event_emitter from public.phase_c_step_binding
        union all select handoff_writer from public.phase_c_step_binding
        union all select canonical_runtime_handler from public.phase_c_step_binding
        union all select resolver_path from public.phase_c_role_binding
        union all select task_receiver_path from public.phase_c_role_binding
        union all select authority_binding_path from public.phase_c_role_binding
        union all select review_binding_path from public.phase_c_role_binding
        union all select knowledge_scope_path from public.phase_c_role_binding
        union all select tool_policy_path from public.phase_c_role_binding
        union all select invocation_entrypoint from public.phase_c_overlay_binding
        union all select runtime_entrypoint from public.phase_c_workflow_binding
        union all select event_outbox_writer from public.phase_c_workflow_binding
        union all select runtime_writer from public.phase_c_handoff_binding
        union all select runtime_receiver from public.phase_c_handoff_binding
        union all select packet_schema_validator from public.phase_c_handoff_binding
        union all select sla_timer_handler from public.phase_c_handoff_binding
        union all select enforcement_function from public.phase_c_gate_binding
        union all select enforcement_function from public.phase_c_rule_binding
      ) s where x is not null
    )
    select count(*)::text from named
    where fn is not null
      and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                      where n.nspname='public' and p.proname = named.fn));
  ok := actual = expected; return next;

  -- ---------------------------------------------------------------- runtime accountability
  check_name := 'components_inventoried'; expected := '>=1794';
  actual := (select count(*)::text from public.phase_c_component);
  ok := (select count(*) from public.phase_c_component) >= 1794; return next;  -- re-baselined 2026-09-02: 13 phase-freeze trigger components removed by founder order

  check_name := 'active_state_changing_without_role'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where mutates_state and activation_state not in ('inactive','disabled')
               and accountable_role_id = '');
  ok := actual = expected; return next;

  check_name := 'active_state_changing_without_system_actor'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where mutates_state and activation_state not in ('inactive','disabled')
               and canonical_system_actor = '');
  ok := actual = expected; return next;

  check_name := 'active_state_changing_without_scope'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where mutates_state and activation_state not in ('inactive','disabled')
               and workflow_id = '');
  ok := actual = expected; return next;

  -- WAS: where classification = '' — the empty string, which no row has ever held, while 286 rows
  -- carried the literal 'NO_CALLER_UNCLASSIFIED' and 99 of those were active and state-changing.
  -- The check now measures the population gate 4 actually names.
  check_name := 'unclassified_components'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where mutates_state and activation_state not in ('inactive','disabled')
               and classification in ('', 'NO_CALLER_UNCLASSIFIED'));
  ok := actual = expected; return next;

  check_name := 'unclassified_edge_functions'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where component_type = 'edge_function'
               and activation_state not in ('inactive','disabled')
               and classification in ('', 'NO_CALLER_UNCLASSIFIED'));
  ok := actual = expected; return next;

  check_name := 'unclassified_db_functions_and_triggers'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where component_type in ('database_function','database_trigger') and classification = '');
  ok := actual = expected; return next;

  check_name := 'unclassified_cron_jobs'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where component_type = 'cron_job' and classification = '');
  ok := actual = expected; return next;

  check_name := 'generic_owner_used'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where accountable_role_id in ('Director','director','service_role','pg_cron','postgres','system','admin','code_runner','unknown',''));
  ok := actual = expected; return next;

  check_name := 'component_owners_resolve'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component c
             where not public.fn_phase_c_actor_may_own(c.accountable_role_id));
  ok := actual = expected; return next;

  -- ---------------------------------------------------------------- founder autonomy
  check_name := 'non_refund_founder_approvals'; expected := '0';
  actual := public.fn_phase_c_non_refund_founder_approvals()::text;
  ok := actual = expected; return next;

  check_name := 'action_classes_requiring_founder_approval'; expected := '1';
  actual := (select count(*)::text from public.phase_c_action_class where founder_approval_required);
  ok := actual = expected; return next;

  check_name := 'the_founder_approval_class_is_refund_decision'; expected := 'refund_decision';
  actual := coalesce((select action_class from public.phase_c_action_class where founder_approval_required), 'NONE');
  ok := actual = expected; return next;

  check_name := 'refund_executions_without_founder_decision'; expected := '0';
  actual := (select count(*)::text from public.phase_c_refund_decision
             where executed_at is not null and decision <> 'approved');
  ok := actual = expected; return next;

  check_name := 'refund_executor_equals_reconciler'; expected := '0';
  actual := (select count(*)::text from public.phase_c_refund_decision
             where executor_role_id = reconciler_role_id);
  ok := actual = expected; return next;

  -- ---------------------------------------------------------------- founder commands
  check_name := 'founder_messages_without_command'; expected := '0';
  actual := (select count(*)::text from public.founder_command_message m
             where not exists (select 1 from public.founder_command c where c.message_id = m.message_id));
  ok := actual = expected; return next;

  check_name := 'routed_commands_without_tasks'; expected := '0';
  actual := (select count(*)::text from public.founder_command c
             where c.state in ('tasks_created','in_progress','partially_blocked','completed')
               and c.intent_id not in ('CMD-STATUS','CMD-CANCEL','CMD-REPRIORITIZE','CMD-EXPLAIN')
               and c.outcome <> 'REFUND_APPROVAL'
               and not exists (select 1 from public.founder_command_task_link l where l.command_id = c.command_id));
  ok := actual = expected; return next;

  check_name := 'ambiguous_commands_that_created_tasks'; expected := '0';
  actual := (select count(*)::text from public.founder_command c
             where c.intent_id = 'AMBIGUOUS'
               and exists (select 1 from public.founder_command_task_link l where l.command_id = c.command_id));
  ok := actual = expected; return next;

  check_name := 'command_tasks_without_canonical_owner'; expected := '0';
  actual := (select count(*)::text from public.phase_c_task t
             where t.command_id is not null and not public.fn_phase_c_actor_may_own(t.accountable_role_id));
  ok := actual = expected; return next;

  check_name := 'command_plans_without_ceo_owner'; expected := '0';
  actual := (select count(*)::text from public.founder_command where command_owner_role_id <> 'ceo');
  ok := actual = expected; return next;

  check_name := 'duplicate_command_from_same_idempotency_key'; expected := '0';
  actual := (select coalesce(sum(n - 1), 0)::text from (
               select count(*) n from public.founder_command_message group by client_idempotency_key having count(*) > 1) s);
  ok := actual = expected; return next;

  -- ---------------------------------------------------------------- authority and review
  check_name := 'creator_reviewer_collisions'; expected := '0';
  actual := (select count(*)::text from public.phase_c_task
             where reviewer_required and not public.fn_phase_c_reviewer_independent(accountable_role_id, reviewer_role_id));
  ok := actual = expected; return next;

  check_name := 'step_bindings_with_self_review'; expected := '0';
  actual := (select count(*)::text from public.phase_c_step_binding
             where independent_reviewer_role_id <> ''
               and not public.fn_phase_c_reviewer_independent(accountable_role_id, independent_reviewer_role_id));
  ok := actual = expected; return next;

  check_name := 'overlay_owning_a_task'; expected := '0';
  actual := (select count(*)::text from public.phase_c_task t
             where (select kind from public.fn_phase_c_resolve_actor(t.accountable_role_id)) = 'overlay');
  ok := actual = expected; return next;

  -- ---------------------------------------------------------------- traces
  -- DENOMINATOR-AWARE. This reported 0 over a table that held 0 rows, which is not coverage.
  check_name := 'completed_commands_without_trace'; expected := '0 of >0';
  select count(*) filter (where trace_id is null), count(*) into v_bad, v_pop from public.founder_command where state in ('completed','cancelled','failed','refused','superseded');
  actual := v_bad::text || ' of ' || v_pop::text;
  ok := (v_bad = 0 and v_pop > 0); return next;
  -- (the shared tail below is skipped for this check)

  -- DENOMINATOR-AWARE. This reported 0 over a table that held 0 rows, which is not coverage.
  check_name := 'closed_tasks_without_trace'; expected := '0 of >0';
  select count(*) filter (where trace_id is null), count(*) into v_bad, v_pop from public.phase_c_task where closed_at is not null;
  actual := v_bad::text || ' of ' || v_pop::text;
  ok := (v_bad = 0 and v_pop > 0); return next;
  -- (the shared tail below is skipped for this check)

  -- DENOMINATOR-AWARE. This reported 0 over a table that held 0 rows, which is not coverage.
  check_name := 'completed_step_runs_without_trace'; expected := '0 of >0';
  select count(*) filter (where trace_id is null), count(*) into v_bad, v_pop from public.phase_c_workflow_step_run where state = 'completed';
  actual := v_bad::text || ' of ' || v_pop::text;
  ok := (v_bad = 0 and v_pop > 0); return next;
  -- (the shared tail below is skipped for this check)

  -- DENOMINATOR-AWARE. This reported 0 over a table that held 0 rows, which is not coverage.
  check_name := 'handoff_runs_without_trace'; expected := '0 of >0';
  select count(*) filter (where trace_id is null), count(*) into v_bad, v_pop from public.phase_c_handoff_run;
  actual := v_bad::text || ' of ' || v_pop::text;
  ok := (v_bad = 0 and v_pop > 0); return next;
  -- (the shared tail below is skipped for this check)

  -- ---------------------------------------------------------------- idempotency and delivery
  check_name := 'duplicate_outbox_dedupe_values'; expected := '0';
  actual := (select coalesce(sum(n - 1), 0)::text from (
               select count(*) n from public.phase_c_event_outbox group by event_id, dedupe_value having count(*) > 1) s);
  ok := actual = expected; return next;

  check_name := 'delivered_without_downstream_record'; expected := '0';
  actual := (select count(*)::text from public.phase_c_event_outbox o
             where o.status = 'delivered'
               and not exists (select 1 from public.phase_c_event_delivery_attempt a
                               where a.outbox_id = o.outbox_id and a.ok and a.downstream_ref <> ''));
  ok := actual = expected; return next;

  check_name := 'retry_erased_the_first_failure'; expected := '0';
  actual := (select count(*)::text from public.phase_c_event_outbox
             where attempts > 1 and status = 'delivered' and first_failure is null
               and exists (select 1 from public.phase_c_event_delivery_attempt a
                           where a.outbox_id = phase_c_event_outbox.outbox_id and not a.ok));
  ok := actual = expected; return next;

  check_name := 'duplicate_task_idempotency_keys'; expected := '0';
  actual := (select coalesce(sum(n - 1), 0)::text from (
               select count(*) n from public.phase_c_task group by idempotency_key having count(*) > 1) s);
  ok := actual = expected; return next;

  -- ---------------------------------------------------------------- cost
  check_name := 'paid_inference_since_phase_c_started'; expected := '0';
  -- WAS anchored to max(recorded_at) from phase_c_package_erratum: recording any new erratum moved
  -- the window forward and the check went green over whatever spend it had just stepped over, and
  -- emptying that table moved the anchor to now()-1 day. The start of Phase C is a fixed instant,
  -- and BOTH cost ledgers are counted, not one.
  -- 4 SEP 2026: a row in a cost ledger is not a paid call. Since the company loop restarted, a HELD
  -- call writes an ai_cost_log row with model_used = 'none', cost 0 and no provider round trip
  -- (the gate said so in model_selected_because), and this line counted it as paid inference.
  -- "Paid" means a provider was reached: tokens, cost or an HTTP status on the attempt.
  actual := ((select count(*) from public.ai_cost_log
               where occurred_at > timestamptz '2026-08-15 02:51:36+00'
                 and (coalesce(cost_aed, 0) > 0 or coalesce(prompt_tokens, 0) > 0 or coalesce(model_used, 'none') <> 'none'))
           + (select count(*) from public.llm_attempt
               where created_at > timestamptz '2026-08-15 02:51:36+00'
                 and (coalesce(cost_aed, 0) > 0 or coalesce(prompt_tokens, 0) > 0 or http_status is not null)))::text;
  ok := actual = expected; return next;

  check_name := 'openrouter_routes_open'; expected := '0';
  actual := (select count(*)::text from public.llm_route_health where open_until <= now());
  ok := actual = expected; return next;

  -- ---------------------------------------------------------------- correction 2026-08-16
  -- Every one of these exists because the audit found the thing it measures, and found no check
  -- that could have seen it.

  check_name := 'tasks_without_trace'; expected := '0 of >0';
  select count(*) filter (where trace_id is null), count(*) into v_bad, v_pop from public.phase_c_task;
  actual := v_bad::text || ' of ' || v_pop::text;
  ok := (v_bad = 0 and v_pop > 0); return next;

  check_name := 'workflow_runs_without_trace'; expected := '0 of >0';
  select count(*) filter (where trace_id is null), count(*) into v_bad, v_pop
    from public.phase_c_workflow_run;
  actual := v_bad::text || ' of ' || v_pop::text;
  ok := (v_bad = 0 and v_pop > 0); return next;

  check_name := 'outbox_rows_without_trace'; expected := '0 of >0';
  select count(*) filter (where trace_id is null), count(*) into v_bad, v_pop
    from public.phase_c_event_outbox;
  actual := v_bad::text || ' of ' || v_pop::text;
  ok := (v_bad = 0 and v_pop > 0); return next;

  -- A command whose root trace describes a different moment than the command itself.
  check_name := 'commands_ahead_of_their_trace'; expected := '0';
  actual := (select count(*)::text from public.founder_command c
             join public.phase_c_trace t on t.trace_id = c.trace_id
             where t.state_after is distinct from c.state);
  ok := actual = expected; return next;

  -- The founder-command event must name the workflow the command actually selected.
  -- `superseded` rows are excluded because that status IS the finding: three rows emitted before
  -- the fix are quarantined there, unreachable by the claim (which takes only pending/retry_wait)
  -- and carrying the reason on the row. The companion check below makes that quarantine cost
  -- something, so this exclusion cannot become a hiding place.
  check_name := 'outbox_events_naming_another_workflow'; expected := '0';
  actual := (select count(*)::text from public.phase_c_event_outbox o
             where o.payload ? 'command_id' and o.status <> 'superseded'
               and not exists (select 1 from public.founder_command_workflow_link l2
                               where l2.command_id = (o.payload->>'command_id')::bigint
                                 and l2.workflow_id = o.workflow_id));
  ok := actual = expected; return next;

  check_name := 'outbox_superseded_without_a_stated_reason'; expected := '0';
  actual := (select count(*)::text from public.phase_c_event_outbox
             where status = 'superseded' and coalesce(btrim(last_error),'') = '');
  ok := actual = expected; return next;

  -- The queue has to have been drained by something, at least once.
  check_name := 'outbox_delivery_attempts_exist'; expected := '>0 when the outbox is non-empty';
  select count(*) into v_pop from public.phase_c_event_outbox;
  select count(*) into v_bad from public.phase_c_event_delivery_attempt;
  actual := v_bad::text || ' attempt(s) for ' || v_pop::text || ' outbox row(s)';
  ok := (v_pop = 0 or v_bad > 0); return next;

  check_name := 'outbox_rows_stuck_pending_over_an_hour'; expected := '0';
  actual := (select count(*)::text from public.phase_c_event_outbox
             where status = 'pending' and created_at < now() - interval '1 hour');
  ok := actual = expected; return next;

  check_name := 'outbox_dead_letter'; expected := '0';
  actual := (select count(*)::text from public.phase_c_event_outbox where status = 'dead_letter');
  ok := actual = expected; return next;

  -- An event binding may only claim CONNECTED when the derivation agrees.
  check_name := 'event_bindings_claiming_more_than_the_legs_support'; expected := '0';
  actual := (select count(*)::text from public.phase_c_event_binding b
             where b.connection_status
                   is distinct from (select status from public.fn_phase_c_event_binding_status(b.event_id)));
  ok := actual = expected; return next;

  check_name := 'active_state_changing_without_authority'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where mutates_state and activation_state not in ('inactive','disabled')
               and coalesce(authority_class,'') = '');
  ok := actual = expected; return next;

  check_name := 'active_state_changing_without_trace_policy'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where mutates_state and activation_state not in ('inactive','disabled')
               and coalesce(trace_policy_id,'') = '');
  ok := actual = expected; return next;

  -- A clarification the founder can never close was the seventh audit failure.
  check_name := 'clarification_required_has_an_exit'; expected := '2';
  actual := (select count(*)::text from public.phase_c_command_transition
             where from_state = 'clarification_required');
  ok := actual = expected; return next;

  return;
end $function$;

