-- ============================================================================================
-- KERNEL K2c — THE CLARIFY PATH JOINS THE KERNEL
--
-- K2b moved fn_founder_command_submit onto fn_kernel_workflow_start and left fn_founder_command_clarify
-- exactly where it was. Measured through the real authenticated path on 17 Aug, command 270:
-- an ambiguous command asked its question and created nothing (correct), and the ANSWER then created
-- four phase_c_task rows, zero workflow runs and zero outbox rows (the old shape).
--
-- Two entry points into the same business outcome, one migrated and one not, is how the estate got
-- here in the first place. Clarify now builds plan ITEMS and calls the same kernel, so the two
-- cannot drift apart again.
-- ============================================================================================
CREATE OR REPLACE FUNCTION public.fn_founder_command_clarify(p_command_id bigint, p_answer text, p_actor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  cmd public.founder_command%rowtype;
  msg public.founder_command_message%rowtype;
  c record; v_combined text; v_qn text; v_owner text; v_child text;
  v_tasks bigint[] := '{}'; v_owners text[] := '{}'; v_task bigint;
  v_due timestamptz; v_wf text; v_start_event text; v_plan bigint; v_clar bigint;
  v_kernel jsonb; v_items int := 0; v_manager text; v_dept text;
  v_founder text;
begin
  v_founder := public.fn_phase_c_require_founder(p_actor);   -- raises 28000 for anyone else

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
      'answer_recorded', true, 'clarification_id', v_clar, 'actor', v_founder);
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

  select role_id into v_owner from public.fn_phase_c_resolve_actor(
    coalesce(nullif(c.primary_role_id,''), 'chief_of_staff'));
  -- ---- THE PLAN (not operational tasks) --------------------------------------------------
  -- K2 moved this for fn_founder_command_submit and left the clarify path behind, so answering a
  -- clarification still created four phase_c_task rows and no workflow run at all. Measured on
  -- command 270 through the real authenticated path on 17 Aug: tasks 4, runs 0, outbox 0.
  -- Plan items record who the command plan names. They are not work anybody is accountable for.
  if v_owner is not null then
    select r.manager_role_id, r.primary_department_id into v_manager, v_dept
      from public.org_role r where r.role_id = v_owner;
    insert into public.founder_command_plan_item
      (command_id, item_kind, role_id, department_id, summary, priority, workflow_id)
    values (p_command_id, 'primary', v_owner, coalesce(v_dept,''),
            left(v_combined, 1500), c.priority, nullif(v_wf,''))
    on conflict (command_id, item_kind, role_id) do nothing;
    v_items := v_items + 1; v_owners := v_owners || v_owner;
  end if;

  for v_child in select btrim(x) from unnest(string_to_array(c.child_role_ids, ';')) x where btrim(x) <> '' loop
    select role_id into v_owner from public.fn_phase_c_resolve_actor(v_child);
    continue when v_owner is null;
    select r.manager_role_id, r.primary_department_id into v_manager, v_dept
      from public.org_role r where r.role_id = v_owner;
    insert into public.founder_command_plan_item
      (command_id, item_kind, role_id, department_id, summary, priority, workflow_id)
    values (p_command_id, 'contribution', v_owner, coalesce(v_dept,''),
            'Contribution required by the command plan for ' || v_child || ': ' || left(v_combined, 1500),
            c.priority, nullif(v_wf,''))
    on conflict (command_id, item_kind, role_id) do nothing;
    v_items := v_items + 1; v_owners := v_owners || v_owner;
  end loop;

  -- ---- THE WORK --------------------------------------------------------------------------------
  -- One call, one run, one operational task, one factual event — the same kernel entry point the
  -- submit path uses, so the two can no longer drift apart.
  if coalesce(v_wf,'') <> '' and exists (select 1 from public.phase_b_workflow where workflow_id = v_wf) then
    v_kernel := public.fn_kernel_workflow_start(jsonb_build_object(
      'workflow_id', v_wf,
      'business_object_id', 'founder_command:' || p_command_id,
      'source_kind','founder_command',
      'source_ref','founder_command:' || p_command_id,
      'command_id', p_command_id,
      'correlation_id','cmd:' || p_command_id,
      'causation_id','command:' || p_command_id,
      'requested_by', v_founder,
      'priority', c.priority,
      'trigger_ctx', jsonb_build_object(
        'intent', c.intent_id, 'outcome', c.outcome, 'confidence', c.confidence,
        'matched_rule_id', c.matched_rule_id, 'after_clarification', true,
        'clarification_id', v_clar, 'plan_items', v_items)));
    v_task := (v_kernel->>'task_id')::bigint;
    v_start_event := v_kernel->>'event_id';
    if v_task is null then
      raise exception 'command %: the kernel returned no operational task for workflow %',
        p_command_id, v_wf using errcode = '23502';
    end if;
    insert into public.founder_command_task_link (command_id, task_id)
    values (p_command_id, v_task) on conflict do nothing;
    v_tasks := array[v_task];
    update public.phase_c_task set due_at = coalesce(due_at, v_due) where task_id = v_task;
  end if;

  insert into public.founder_command_plan (command_id, summary, child_task_count, departments)
  values (p_command_id,
          format('%s: %s after clarification. Command owner chief_of_staff; %s plan item(s), %s operational task against %s.',
                 c.intent_id, c.outcome, v_items, cardinality(v_tasks),
                 coalesce(nullif(c.workflow_ids,''),'no workflow')),
          v_items,
          coalesce((select string_agg(distinct t.department_id, '; ') from public.phase_c_task t
                     where t.command_id = p_command_id and t.department_id <> ''), ''))
  returning plan_id into v_plan;

  update public.founder_command set state = 'tasks_created', due_at = v_due
   where command_id = p_command_id;

  return jsonb_build_object('ok', true, 'command_id', p_command_id, 'status','tasks_created',
    'intent', c.intent_id, 'outcome', c.outcome, 'owner','chief_of_staff',
    'primary_owner', coalesce(v_owners[1],'founder'), 'task_ids', to_jsonb(v_tasks),
    'tasks_created', cardinality(v_tasks), 'workflow_id', v_wf,
    'event_emitted', v_start_event, 'plan_id', v_plan, 'clarification_id', v_clar,
    'answer_recorded', true, 'trace_id', cmd.trace_id, 'actor', v_founder,
    'interpretation','after clarification: ' || c.reason);
end $function$
;
