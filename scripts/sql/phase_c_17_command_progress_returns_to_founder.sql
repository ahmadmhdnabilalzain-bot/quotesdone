-- Phase C — the last two links of the founder's workflow.
--
-- The founder confirmed the chain he expects:
--
--   Founder -> Command Center -> Chief of Staff -> command understood -> exact workflow selected
--   -> exact department and employee receive immediate tasks -> company performs the work
--   -> PROGRESS AND COMPLETION RETURN TO THE FOUNDER
--
-- Links 1-5 were built and proved. The last one was not, and saying so is the point of this file:
-- a command reached `tasks_created` and STAYED there for ever. Nothing moved it to in_progress when
-- an employee started, nothing moved it to partially_blocked when one of them got stuck, and
-- nothing ever moved it to completed or wrote a completion summary. The founder would have watched
-- a command sit at "tasks created" while the work happened and finished underneath it.
--
-- The roll-up is done ON THE TASK TRANSITION, not by a sweep. Two reasons, and the second is the
-- one that matters:
--
--   * it needs no new cron row, so Phase C still changes no activation state;
--   * a sweep that does not run looks exactly like a company with nothing to report. Deriving the
--     command's state from its tasks at the moment a task moves means the state cannot lag, and
--     cannot silently stop.
--
-- scripts/sql is append-only.  To change any of this, add a new file.

set lock_timeout = '8s';
set statement_timeout = '600s';

-- ============================================================ 1. the roll-up
--
-- One command's state, derived from its tasks. Returns the state it moved to, or null when the
-- command was already there.
create or replace function public.fn_founder_command_rollup(p_command_id bigint)
returns text language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  c public.founder_command%rowtype;
  n_total bigint; n_open bigint; n_blocked bigint; n_started bigint; n_failed bigint; n_done bigint;
  v_want text; v_summary text;
begin
  select * into c from public.founder_command where command_id = p_command_id for update;
  if not found then return null; end if;
  -- a terminal command is not re-opened by a late task movement
  if c.state in ('completed','cancelled','refused','superseded','failed') then return null; end if;

  select count(*),
         count(*) filter (where closed_at is null),
         count(*) filter (where state = 'blocked'),
         count(*) filter (where state in ('in_progress','accepted','review_required','revision_required')),
         count(*) filter (where state = 'failed'),
         count(*) filter (where state = 'completed')
    into n_total, n_open, n_blocked, n_started, n_failed, n_done
  from public.phase_c_task where command_id = p_command_id;

  if n_total = 0 then return null; end if;

  v_want := case
    when n_open = 0 and n_failed > 0 then 'failed'
    when n_open = 0                  then 'completed'
    when n_blocked > 0               then 'partially_blocked'
    when n_started > 0               then 'in_progress'
    else c.state
  end;
  if v_want = c.state then return null; end if;

  -- The frozen command state model still decides. A move it does not allow is not forced; the
  -- command stays where it is and the task movement is unaffected.
  if not exists (select 1 from public.phase_c_command_transition
                 where from_state = c.state and to_state = v_want) then
    return null;
  end if;

  update public.founder_command set
    state = v_want,
    closed_at = case when v_want in ('completed','failed') then now() else closed_at end
  where command_id = p_command_id;

  if v_want in ('completed','failed') then
    v_summary := format(
      '%s of %s task(s) completed, %s failed. Owners: %s.',
      n_done, n_total, n_failed,
      coalesce((select string_agg(distinct accountable_role_id, ', ' order by accountable_role_id)
                from public.phase_c_task where command_id = p_command_id), 'none'));
    insert into public.founder_command_completion (command_id, summary, evidence)
    values (p_command_id, v_summary, jsonb_build_object(
      'tasks_total', n_total, 'tasks_completed', n_done, 'tasks_failed', n_failed,
      'task_ids', coalesce((select jsonb_agg(task_id order by task_id)
                            from public.phase_c_task where command_id = p_command_id), '[]'::jsonb),
      'traces', coalesce((select jsonb_agg(trace_id) from public.phase_c_task
                          where command_id = p_command_id and trace_id is not null), '[]'::jsonb)))
    on conflict (command_id) do update set summary = excluded.summary,
      evidence = excluded.evidence, closed_at = now();

    perform public.fn_phase_c_trace_write('TRACE-FOUNDER-COMMAND', jsonb_build_object(
      'subject_kind','command', 'subject_ref', p_command_id::text, 'command_id', p_command_id,
      'actor_role_id','chief_of_staff', 'system_actor_id','system.task_engine',
      'state_before', c.state, 'state_after', v_want, 'status','sealed',
      'evidence_refs', jsonb_build_array(jsonb_build_object('completion_summary', v_summary))));
  end if;

  return v_want;
end $$;
revoke all on function public.fn_founder_command_rollup(bigint) from public;
grant execute on function public.fn_founder_command_rollup(bigint) to service_role;

-- ============================================================ 2. attach it to the task move
--
-- fn_phase_c_task_transition is the only routine that moves a canonical task, so this is the one
-- place the roll-up has to hang. Everything before the roll-up is unchanged.
create or replace function public.fn_phase_c_task_transition(
  p_task_id bigint, p_to_state text, p_actor text, p_ctx jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare t public.phase_c_task%rowtype; v_trace bigint; v_cmd_state text;
begin
  select * into t from public.phase_c_task where task_id = p_task_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error','not_found','task_id', p_task_id);
  end if;
  if not public.fn_phase_c_task_transition_allowed(t.state, p_to_state) then
    return jsonb_build_object('ok', false, 'error','invalid_transition',
      'from', t.state, 'to', p_to_state,
      'message','The Phase C task state model does not allow that move.');
  end if;
  if p_to_state = 'completed' and t.reviewer_required
     and not public.fn_phase_c_reviewer_independent(t.accountable_role_id, t.reviewer_role_id) then
    return jsonb_build_object('ok', false, 'error','reviewer_not_independent',
      'owner', t.accountable_role_id, 'reviewer', t.reviewer_role_id);
  end if;
  if p_to_state = 'blocked' and coalesce(p_ctx->>'blocker','') = '' then
    return jsonb_build_object('ok', false, 'error','blocker_required',
      'message','A blocked task must name its blocker and the owner who resolves it.');
  end if;

  update public.phase_c_task set
    state = p_to_state,
    blocker = case when p_to_state = 'blocked' then p_ctx->>'blocker' else '' end,
    blocker_owner_role_id = case when p_to_state = 'blocked' then coalesce(p_ctx->>'blocker_owner_role_id','') else '' end,
    closed_at = case when p_to_state in ('completed','cancelled','failed','superseded') then now() else null end
  where task_id = p_task_id;

  v_trace := public.fn_phase_c_trace_write('TRACE-TASK', jsonb_build_object(
    'subject_kind','task', 'subject_ref', p_task_id::text, 'task_id', p_task_id,
    'command_id', t.command_id, 'actor_role_id', p_actor, 'manager_role_id', t.manager_role_id,
    'state_before', t.state, 'state_after', p_to_state, 'status', 'sealed'));
  update public.phase_c_task set trace_id = v_trace where task_id = p_task_id;

  -- The founder's half of the chain: the command follows its tasks.
  if t.command_id is not null then
    v_cmd_state := public.fn_founder_command_rollup(t.command_id);
  end if;

  return jsonb_build_object('ok', true, 'task_id', p_task_id, 'from', t.state, 'to', p_to_state,
                            'trace_id', v_trace, 'command_moved_to', v_cmd_state);
end $$;

-- ============================================================ 3. the founder-facing thread
--
-- One command, everything about it, in the order a person reads it: what he said, what was
-- understood, who has it, where each of them is, what is blocking, and how it ended.
create or replace function public.fn_founder_command_thread(p_command_id bigint)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select jsonb_build_object(
    'ok', c.command_id is not null,
    'command_id', c.command_id,
    'said', m.raw_text,
    'said_at', m.received_at,
    'said_by', m.founder_identity,
    'secretary', c.command_owner_role_id,
    'understood_as', (select i.reason from public.founder_command_interpretation i
                      where i.command_id = c.command_id order by i.version desc limit 1),
    'intent', c.intent_id,
    'outcome', c.outcome,
    'state', c.state,
    'priority', c.priority,
    'due_at', c.due_at,
    'workflows', coalesce((select jsonb_agg(w.workflow_id || ' — ' || b.workflow_name order by w.workflow_id)
                           from public.founder_command_workflow_link w
                           join public.phase_b_workflow b on b.workflow_id = w.workflow_id
                           where w.command_id = c.command_id), '[]'::jsonb),
    'plan', (select p.summary from public.founder_command_plan p where p.command_id = c.command_id),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object(
                          'task_id', t.task_id,
                          'owner', t.accountable_role_id,
                          'owner_name', (select r.display_name from public.org_role r where r.role_id = t.accountable_role_id),
                          'manager', t.manager_role_id,
                          'department', t.department_id,
                          'state', t.state,
                          'objective', left(t.objective, 300),
                          'acceptance', t.acceptance_criteria,
                          'closure', t.closure_criteria,
                          'reviewer', nullif(t.reviewer_role_id, ''),
                          'blocker', nullif(t.blocker, ''),
                          'blocker_owner', nullif(t.blocker_owner_role_id, ''),
                          'due_at', t.due_at,
                          'trace_id', t.trace_id) order by t.task_id)
                       from public.phase_c_task t where t.command_id = c.command_id), '[]'::jsonb),
    'overlays_invoked', coalesce((select jsonb_agg(o.overlay_id order by o.overlay_id)
                                  from public.founder_command_overlay_invocation o
                                  where o.command_id = c.command_id), '[]'::jsonb),
    'clarification', (select cl.question from public.founder_command_clarification cl
                      where cl.command_id = c.command_id order by cl.clarification_id desc limit 1),
    'completion', (select jsonb_build_object('summary', k.summary, 'evidence', k.evidence, 'at', k.closed_at)
                   from public.founder_command_completion k where k.command_id = c.command_id),
    'history', coalesce((select jsonb_agg(jsonb_build_object(
                            'from', h.from_state, 'to', h.to_state, 'at', h.at) order by h.history_id)
                         from public.founder_command_status_history h where h.command_id = c.command_id), '[]'::jsonb),
    'traces', coalesce((select jsonb_agg(jsonb_build_object(
                            'trace_id', tr.trace_id, 'policy', tr.trace_policy_id,
                            'subject', tr.subject_kind, 'state_after', tr.state_after) order by tr.trace_id)
                        from public.phase_c_trace tr where tr.command_id = c.command_id), '[]'::jsonb))
  from public.founder_command c
  join public.founder_command_message m on m.message_id = c.message_id
  where c.command_id = p_command_id;
$$;
revoke all on function public.fn_founder_command_thread(bigint) from public;
grant execute on function public.fn_founder_command_thread(bigint) to service_role;

-- ============================================================ 4. progress the founder can add to
--
-- "Report progress back to me through the Command Center" means the thread has to accept an
-- update from the OWNER, not only a state change. This is the note an employee attaches; it lands
-- against the task, is traced, and appears in the thread above.
create table if not exists public.founder_command_progress_note (
  note_id      bigint generated always as identity primary key,
  command_id   bigint not null references public.founder_command(command_id) on delete cascade,
  task_id      bigint references public.phase_c_task(task_id) on delete cascade,
  author_role_id text not null,
  note         text not null,
  evidence     jsonb not null default '{}'::jsonb,
  trace_id     bigint,
  created_at   timestamptz not null default now()
);
create index if not exists founder_command_progress_note_cmd_ix
  on public.founder_command_progress_note (command_id, created_at desc);

-- ROUTINE REMOVED 7 September 2026. public.fn_founder_command_progress_add was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

revoke all on function public.fn_founder_command_progress_add(bigint, bigint, text, text, jsonb) from public;
grant execute on function public.fn_founder_command_progress_add(bigint, bigint, text, text, jsonb) to service_role;

-- The thread carries the notes too. Redefined here rather than above because the table it reads
-- is created in this file, after the first definition — a thread that silently omitted the
-- progress notes would be the exact "report progress back to me" gap this file exists to close.
create or replace function public.fn_founder_command_thread(p_command_id bigint)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select jsonb_build_object(
    'ok', c.command_id is not null,
    'command_id', c.command_id,
    'said', m.raw_text,
    'said_at', m.received_at,
    'said_by', m.founder_identity,
    'secretary', c.command_owner_role_id,
    'understood_as', (select i.reason from public.founder_command_interpretation i
                      where i.command_id = c.command_id order by i.version desc limit 1),
    'intent', c.intent_id,
    'outcome', c.outcome,
    'state', c.state,
    'priority', c.priority,
    'due_at', c.due_at,
    'workflows', coalesce((select jsonb_agg(w.workflow_id || ' — ' || b.workflow_name order by w.workflow_id)
                           from public.founder_command_workflow_link w
                           join public.phase_b_workflow b on b.workflow_id = w.workflow_id
                           where w.command_id = c.command_id), '[]'::jsonb),
    'plan', (select p.summary from public.founder_command_plan p where p.command_id = c.command_id),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object(
                          'task_id', t.task_id,
                          'owner', t.accountable_role_id,
                          'owner_name', (select r.display_name from public.org_role r where r.role_id = t.accountable_role_id),
                          'manager', t.manager_role_id,
                          'department', t.department_id,
                          'state', t.state,
                          'objective', left(t.objective, 300),
                          'acceptance', t.acceptance_criteria,
                          'closure', t.closure_criteria,
                          'reviewer', nullif(t.reviewer_role_id, ''),
                          'blocker', nullif(t.blocker, ''),
                          'blocker_owner', nullif(t.blocker_owner_role_id, ''),
                          'due_at', t.due_at,
                          'trace_id', t.trace_id) order by t.task_id)
                       from public.phase_c_task t where t.command_id = c.command_id), '[]'::jsonb),
    'progress', coalesce((select jsonb_agg(jsonb_build_object(
                            'note_id', n.note_id, 'at', n.created_at, 'by', n.author_role_id,
                            'by_name', (select r.display_name from public.org_role r where r.role_id = n.author_role_id),
                            'task_id', n.task_id, 'note', n.note, 'evidence', n.evidence,
                            'trace_id', n.trace_id) order by n.note_id)
                          from public.founder_command_progress_note n
                          where n.command_id = c.command_id), '[]'::jsonb),
    'overlays_invoked', coalesce((select jsonb_agg(o.overlay_id order by o.overlay_id)
                                  from public.founder_command_overlay_invocation o
                                  where o.command_id = c.command_id), '[]'::jsonb),
    'clarification', (select cl.question from public.founder_command_clarification cl
                      where cl.command_id = c.command_id order by cl.clarification_id desc limit 1),
    'completion', (select jsonb_build_object('summary', k.summary, 'evidence', k.evidence, 'at', k.closed_at)
                   from public.founder_command_completion k where k.command_id = c.command_id),
    'history', coalesce((select jsonb_agg(jsonb_build_object(
                            'from', h.from_state, 'to', h.to_state, 'at', h.at) order by h.history_id)
                         from public.founder_command_status_history h where h.command_id = c.command_id), '[]'::jsonb),
    'traces', coalesce((select jsonb_agg(jsonb_build_object(
                            'trace_id', tr.trace_id, 'policy', tr.trace_policy_id,
                            'subject', tr.subject_kind, 'state_after', tr.state_after) order by tr.trace_id)
                        from public.phase_c_trace tr where tr.command_id = c.command_id), '[]'::jsonb))
  from public.founder_command c
  join public.founder_command_message m on m.message_id = c.message_id
  where c.command_id = p_command_id;
$$;
revoke all on function public.fn_founder_command_thread(bigint) from public;
grant execute on function public.fn_founder_command_thread(bigint) to service_role;
