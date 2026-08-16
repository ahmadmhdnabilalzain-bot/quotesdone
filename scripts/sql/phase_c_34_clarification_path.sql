-- Phase C correction 7 — a clarification the founder can actually answer, or close.
--
-- The audit sent "Make marketing better." The system did the right thing: one clarification, zero
-- tasks, zero side effects. Then it could not get rid of it. `founder_command_control(223,'cancel')`
-- returned HTTP 409 — "A command in 'clarification_required' cannot be cancelled; the state model
-- does not allow it" — and phase_c_command_transition confirmed that `clarification_required` was
-- the only one of the eight states with no terminal exit: its single legal move was back to
-- `interpreting`, and none of the four control operations performed it.
--
-- Command 223 was therefore stuck in the founder's inbox permanently, and so would every future
-- ambiguous command have been.
--
-- ON THE LIFECYCLE NAMES. The correction brief writes the required path as
--   received -> clarification_required -> interpreting -> planned -> tasks_created -> active -> completed
-- This model already implements that shape under the names it froze in phase_c_command_state:
-- `accepted` and `routed` are the planning pair, and `active` is `in_progress`. Renaming live
-- states would create a second vocabulary for the same thing, which is a defect this estate has
-- paid for before. The EDGES the brief requires are added; the names are left alone and the
-- crosswalk is written down in docs/phase-c-correction/PHASE_C_CLARIFICATION_PATH.md.

-- ---------------------------------------------------------------- the missing exit
insert into public.phase_c_command_transition (from_state, to_state, condition)
values ('clarification_required', 'cancelled',
        'The founder withdraws an instruction he was asked to clarify. No work exists to unwind, '
        'because a clarification never creates a task.')
on conflict do nothing;

-- ---------------------------------------------------------------- answering one
create or replace function public.fn_founder_command_clarify(p_command_id bigint, p_answer text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  cmd public.founder_command%rowtype;
  msg public.founder_command_message%rowtype;
  c record; v_combined text; v_qn text; v_owner text; v_child text;
  v_tasks bigint[] := '{}'; v_owners text[] := '{}'; v_task bigint;
  v_due timestamptz; v_wf text; v_start_event text; v_plan bigint; v_clar bigint;
begin
  if coalesce(btrim(p_answer),'') = '' then
    return jsonb_build_object('ok', false, 'error','answer_required',
      'message','Say what you want and I will route it. An empty reply cannot resolve a clarification.');
  end if;
  select * into cmd from public.founder_command where command_id = p_command_id;
  if not found then return jsonb_build_object('ok', false, 'error','not_found'); end if;
  if cmd.state <> 'clarification_required' then
    return jsonb_build_object('ok', false, 'error','not_awaiting_clarification',
      'state', cmd.state,
      'message','This command is not waiting for a clarification.');
  end if;
  select * into msg from public.founder_command_message where message_id = cmd.message_id;

  -- The original instruction is never edited. The reply is APPENDED, on its own row, with its own
  -- timestamp, and the exact words the founder used.
  update public.founder_command_clarification
     set answer_text = p_answer, answered_at = now()
   where clarification_id = (select max(cl.clarification_id) from public.founder_command_clarification cl
                             where cl.command_id = p_command_id)
  returning clarification_id into v_clar;

  update public.founder_command set state = 'interpreting' where command_id = p_command_id;

  -- Re-interpret the instruction AND its clarification together, through the same deterministic
  -- classifier the first attempt used. No model is consulted; nothing is guessed.
  v_combined := coalesce(msg.raw_text,'') || E'\n' || p_answer;
  select * into c from public.fn_founder_command_classify(v_combined);

  insert into public.founder_command_interpretation
    (command_id, version, intent_id, confidence, matched_rule_id, workflow_ids,
     specificity_signals, reason)
  values (p_command_id,
          1 + coalesce((select max(i.version) from public.founder_command_interpretation i
                         where i.command_id = p_command_id), 0),
          c.intent_id, c.confidence, c.matched_rule_id, c.workflow_ids, c.specificity,
          'after clarification: ' || c.reason);

  -- Still not routable. Ask once more; still create nothing.
  if c.outcome not in ('ROUTE_AND_CREATE_TASKS','FOUNDER_INITIATED_POLICY_CHANGE',
                       'FOUNDER_INITIATED_PHASE_A_CHANGE','REFUND_APPROVAL') then
    v_qn := coalesce(nullif(c.reason,''), 'I still cannot route this safely.')
            || ' What exactly do you want changed, by how much, and by when?';
    insert into public.founder_command_clarification (command_id, question)
    values (p_command_id, v_qn);
    update public.founder_command set state = 'clarification_required' where command_id = p_command_id;
    return jsonb_build_object('ok', true, 'command_id', p_command_id,
      'status','clarification_required', 'tasks_created', 0, 'task_ids','[]'::jsonb,
      'owner','chief_of_staff', 'clarification', v_qn,
      'answer_recorded', true, 'clarification_id', v_clar);
  end if;

  -- Routable now. One command id, the plan and the tasks, in this transaction.
  update public.founder_command
     set intent_id = c.intent_id, outcome = c.outcome, priority = c.priority,
         primary_role_id = coalesce(nullif(c.primary_role_id,''), 'chief_of_staff'),
         state = 'accepted'
   where command_id = p_command_id;
  update public.founder_command set state = 'routed' where command_id = p_command_id;

  v_due := now() + case c.priority when 'P0' then interval '4 hours' when 'P1' then interval '2 days'
                                   when 'P2' then interval '5 days' else interval '10 days' end;
  v_wf := btrim(split_part(c.workflow_ids, ';', 1));

  insert into public.founder_command_workflow_link (command_id, workflow_id)
  select p_command_id, btrim(x) from unnest(string_to_array(c.workflow_ids, ';')) x
   where btrim(x) <> '' on conflict do nothing;

  -- fn_phase_c_task_create is the shared creator: it resolves the owner, refuses a generic one, and
  -- the trigger in phase_c_20 gives every task its trace parented to this command's root.
  select role_id into v_owner from public.fn_phase_c_resolve_actor(
    coalesce(nullif(c.primary_role_id,''), 'chief_of_staff'));
  if v_owner is not null then
    v_task := public.fn_phase_c_task_create(jsonb_build_object(
      'source_kind','founder_command', 'source_ref','CMD-' || p_command_id,
      'command_id', p_command_id, 'workflow_id', nullif(v_wf,''),
      'accountable_role_id', v_owner, 'priority', c.priority, 'due_at', v_due,
      'objective', left(v_combined, 2000),
      'requested_output','Evidence-backed outcome for the founder instruction, with the decision and its basis recorded.',
      'acceptance_criteria','Requested outcome delivered with evidence, within policy, authority and gates.',
      'closure_criteria','Independent review passed where required and the closure criteria of the bound workflow are met.',
      'idempotency_key','cmd:' || p_command_id || ':primary'));
    insert into public.founder_command_task_link (command_id, task_id) values (p_command_id, v_task)
      on conflict do nothing;
    v_tasks := v_tasks || v_task; v_owners := v_owners || v_owner;
  end if;

  for v_child in select btrim(x) from unnest(string_to_array(c.child_role_ids, ';')) x where btrim(x) <> '' loop
    select role_id into v_owner from public.fn_phase_c_resolve_actor(v_child);
    continue when v_owner is null;
    v_task := public.fn_phase_c_task_create(jsonb_build_object(
      'source_kind','founder_command', 'source_ref','CMD-' || p_command_id,
      'command_id', p_command_id, 'workflow_id', nullif(v_wf,''),
      'accountable_role_id', v_owner, 'priority', c.priority, 'due_at', v_due,
      'objective', left(v_combined, 2000),
      'requested_output','Contribution required by the command plan for ' || v_child,
      'acceptance_criteria','Contribution delivered with evidence to the command owner.',
      'closure_criteria','Accepted by the primary owner or returned with a specific reason.',
      'idempotency_key','cmd:' || p_command_id || ':child:' || v_owner));
    insert into public.founder_command_task_link (command_id, task_id) values (p_command_id, v_task)
      on conflict do nothing;
    v_tasks := v_tasks || v_task; v_owners := v_owners || v_owner;
  end loop;

  insert into public.founder_command_plan (command_id, summary, child_task_count, departments)
  values (p_command_id,
          format('%s: %s after clarification. Command owner chief_of_staff; %s task(s) against %s.',
                 c.intent_id, c.outcome, cardinality(v_tasks), coalesce(nullif(c.workflow_ids,''),'no workflow')),
          cardinality(v_tasks),
          coalesce((select string_agg(distinct t.department_id, '; ') from public.phase_c_task t
                     where t.command_id = p_command_id and t.department_id <> ''), ''))
  returning plan_id into v_plan;

  v_start_event := public.fn_phase_c_lifecycle_event(v_wf, 'started');
  if v_start_event is not null then
    perform public.fn_phase_c_outbox_emit(v_start_event, 'system.command_router',
      jsonb_build_object('command_id', p_command_id, 'intent', c.intent_id,
                         'workflow_id', v_wf, 'tasks', to_jsonb(v_tasks)),
      'founder_command:' || p_command_id);
  end if;

  update public.founder_command set state = 'tasks_created', due_at = v_due
   where command_id = p_command_id;

  return jsonb_build_object('ok', true, 'command_id', p_command_id, 'status','tasks_created',
    'intent', c.intent_id, 'outcome', c.outcome, 'owner','chief_of_staff',
    'primary_owner', coalesce(v_owners[1],'founder'), 'task_ids', to_jsonb(v_tasks),
    'tasks_created', cardinality(v_tasks), 'workflow_id', v_wf,
    'event_emitted', v_start_event, 'plan_id', v_plan, 'clarification_id', v_clar,
    'answer_recorded', true, 'trace_id', cmd.trace_id,
    'interpretation','after clarification: ' || c.reason);
end $$;
revoke all on function public.fn_founder_command_clarify(bigint, text) from public;
grant execute on function public.fn_founder_command_clarify(bigint, text) to service_role;
comment on function public.fn_founder_command_clarify(bigint, text) is
  'The founder answers a clarification in the same thread: the original message is preserved, the '
  'reply is appended verbatim, one command id is retained, and interpretation resumes through the '
  'same deterministic classifier. No task exists while the clarification is unresolved.';
