-- ============================================================================================
-- KERNEL K0 — FOUNDER AUTHENTICATION
--
-- The independent re-acceptance audit of 16 Aug 2026 proved the Command Center answered a request
-- with NO HEADERS AT ALL:
--
--   POST /functions/v1/os_api {action:'founder_command_inbox'}
--   -> HTTP 200 {"ok":true,"user":"build-mode@quotesdone.local","counts":{...}}
--
-- Two things made that possible and both are closed here.
--
--  (1) 'build-mode@quotesdone.local' was an ACTIVE row in phase_c_founder_identity, so every routine
--      that asks "is this a registered founder?" answered yes for the open door.
--  (2) Two of the three founder_gated actions never asked at all. fn_founder_command_clarify and
--      fn_founder_command_control took no actor, os_api passed none, and neither routine referenced
--      phase_c_founder_identity — while clarify creates tasks and emits the workflow start event.
--
-- The founder's build-mode instruction of 15 Aug ("leave the OS open until the build is finished")
-- is superseded by his instruction of 17 Aug: remove the build-mode founder fallback from
-- production. This file records the close, it does not erase the open: os_open_access_log is
-- append-only history and gains a 'closed' row rather than losing the 'open' one.
--
-- ONE VERIFIER, not three. fn_phase_c_require_founder is the single place that decides whether a
-- caller is the founder. Every founder entry point calls it. That is the K0 half of "one canonical
-- execution kernel" — the alternative is three routines that can disagree, which is the shape of
-- defect this rebuild exists to remove.
-- ============================================================================================

-- ------------------------------------------------------------------ 1. the single founder verifier
create or replace function public.fn_phase_c_require_founder(p_actor text)
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $$
declare v_id text;
begin
  -- An absent actor is refused, never defaulted. A default here would be the open door again,
  -- wearing the name of a parameter.
  if coalesce(btrim(p_actor), '') = '' then
    raise exception 'founder identity is required' using errcode = '28000';
  end if;

  select f.identity into v_id
    from public.phase_c_founder_identity f
   where f.identity = lower(btrim(p_actor))
     and f.active
     and f.kind = 'email';          -- a machine identity is never a founder, however it is flagged

  if v_id is null then
    raise exception 'not the founder: % is not an enabled founder identity', lower(btrim(p_actor))
      using errcode = '28000';
  end if;
  return v_id;
end $$;

revoke all on function public.fn_phase_c_require_founder(text) from public;
grant execute on function public.fn_phase_c_require_founder(text) to service_role;

-- ------------------------------------------------- 2. close the build-mode door, keep the history
update public.phase_c_founder_identity
   set active = false,
       note = note || ' | DISABLED 17 Aug 2026 (kernel K0): the founder instructed that the '
                   || 'build-mode fallback be removed from production. The row is retained so the '
                   || 'audit rows that name it still resolve.'
 where kind = 'build_mode' and active;

insert into public.os_open_access_log (actor, state, reason, detail)
values ('management@quotesdone.com', 'closed',
        'Founder instruction, 17 Aug 2026, opening the Phase C execution kernel rebuild: remove the '
     || 'build-mode founder fallback from production. The independent re-acceptance audit proved '
     || 'os_api answered an unauthenticated request as build-mode@quotesdone.local. Closed in two '
     || 'layers: this switch, and the removal of the fallback branch from os_api itself, so '
     || 're-opening this row alone cannot reopen the door.',
        jsonb_build_object(
          'superseded_row_id', (select max(id) from public.os_open_access_log where state = 'open'),
          'evidence', 'docs/phase-c-final/PHASE_C_FINAL_REACCEPTANCE_REPORT.md, FAIL 1',
          'code_change', 'supabase/functions/os_api/index.ts — BUILD_IDENTITY fallback deleted',
          'identity_row', 'build-mode@quotesdone.local set active=false'));

-- --------------------------------------- 3. a machine identity can never be an active founder again
create or replace function public.fn_phase_c_founder_identity_human_only()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
begin
  if new.active and new.kind <> 'email' then
    raise exception
      'phase_c_founder_identity: only an email identity may be active; % is kind %',
      new.identity, new.kind
      using errcode = '23514',
            hint = 'A build-mode or service identity must never be enabled as the founder. '
                || 'This is the defect the 16 Aug audit found (FAIL 1).';
  end if;
  return new;
end $$;

revoke all on function public.fn_phase_c_founder_identity_human_only() from public;

drop trigger if exists a00_phase_c_founder_identity_human_only on public.phase_c_founder_identity;
create trigger a00_phase_c_founder_identity_human_only
  before insert or update on public.phase_c_founder_identity
  for each row execute function public.fn_phase_c_founder_identity_human_only();

-- ================================================================ 4. clarify — now takes an actor
-- Body unchanged from the definition read back out of production on 17 Aug, with exactly one
-- addition: the actor check on the first line. The two-argument signature is DROPPED at the end of
-- this file, so there is no unverified way in.
create or replace function public.fn_founder_command_clarify(
  p_command_id bigint, p_answer text, p_actor text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  cmd public.founder_command%rowtype;
  msg public.founder_command_message%rowtype;
  c record; v_combined text; v_qn text; v_owner text; v_child text;
  v_tasks bigint[] := '{}'; v_owners text[] := '{}'; v_task bigint;
  v_due timestamptz; v_wf text; v_start_event text; v_plan bigint; v_clar bigint;
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
    'answer_recorded', true, 'trace_id', cmd.trace_id, 'actor', v_founder,
    'interpretation','after clarification: ' || c.reason);
end $$;

revoke all on function public.fn_founder_command_clarify(bigint, text, text) from public;
grant execute on function public.fn_founder_command_clarify(bigint, text, text) to service_role;

-- ================================================================ 5. control — now takes an actor
create or replace function public.fn_founder_command_control(
  p_command_id bigint, p_op text, p_target text, p_value text, p_actor text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare v_target bigint; v_state text; v_n bigint := 0; t record; v_trace bigint; v_founder text;
begin
  v_founder := public.fn_phase_c_require_founder(p_actor);   -- raises 28000 for anyone else

  v_target := nullif(regexp_replace(coalesce(p_target,''), '\D', '', 'g'), '')::bigint;
  if v_target is null then
    return jsonb_build_object('ok', false, 'error','identifier_required');
  end if;
  select state into v_state from public.founder_command where command_id = v_target;
  if v_state is null then return jsonb_build_object('ok', false, 'error','not_found'); end if;

  if p_op in ('cancel','supersede') then
    if not exists (select 1 from public.phase_c_command_transition
                   where from_state = v_state
                     and to_state = case when p_op = 'cancel' then 'cancelled' else 'superseded' end) then
      return jsonb_build_object('ok', false, 'error','transition_not_permitted',
        'from', v_state, 'to', case when p_op = 'cancel' then 'cancelled' else 'superseded' end,
        'message', format('A command in %L cannot be %s; the state model does not allow it.',
                          v_state, case when p_op = 'cancel' then 'cancelled' else 'superseded' end));
    end if;
    update public.founder_command set
      state = case when p_op = 'cancel' then 'cancelled' else 'superseded' end,
      superseded_by = case when p_op = 'supersede' then p_command_id else superseded_by end,
      closed_at = now()
    where command_id = v_target;

    -- One task at a time, each with its own trace.  A bulk UPDATE closed them silently before,
    -- and a completed state change with no trace is the thing this phase exists to make impossible.
    for t in select * from public.phase_c_task
             where command_id = v_target
               and state in ('queued','assigned','accepted','in_progress','blocked') loop
      v_trace := public.fn_phase_c_trace_write('TRACE-TASK', jsonb_build_object(
        'subject_kind','task', 'subject_ref', t.task_id::text, 'task_id', t.task_id,
        'command_id', v_target, 'actor_role_id','founder',
        'system_actor_id','system.command_router', 'manager_role_id', t.manager_role_id,
        'state_before', t.state,
        'state_after', case when p_op = 'cancel' then 'cancelled' else 'superseded' end,
        'evidence_refs', jsonb_build_array(
          jsonb_build_object('reason', 'founder ' || p_op || ' of command ' || v_target,
                             'actor', v_founder)),
        'status','sealed'));
      update public.phase_c_task set
        state = case when p_op = 'cancel' then 'cancelled' else 'superseded' end,
        closed_at = now(), trace_id = v_trace
      where task_id = t.task_id;
      v_n := v_n + 1;
    end loop;

    return jsonb_build_object('ok', true, 'command_id', v_target,
      'status', case when p_op = 'cancel' then 'cancelled' else 'superseded' end,
      'superseded_by', case when p_op = 'supersede' then p_command_id else null end,
      'child_tasks_closed', v_n, 'actor', v_founder);

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
end $$;

revoke all on function public.fn_founder_command_control(bigint, text, text, text, text) from public;
grant execute on function public.fn_founder_command_control(bigint, text, text, text, text) to service_role;

-- ---------------------------------------------------- 6. no unverified way in remains
-- Dropped LAST, so the replacements exist before the old doors close. If either drop fails the
-- whole file fails and nothing is half-applied.
drop function if exists public.fn_founder_command_clarify(bigint, text);
drop function if exists public.fn_founder_command_control(bigint, text, text, text);
