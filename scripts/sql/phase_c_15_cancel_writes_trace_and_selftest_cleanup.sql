-- Phase C — the sixth defect the tests found, and the removal of one test artefact.
--
-- 1. CANCELLING A COMMAND CLOSED ITS TASKS WITHOUT A TRACE.
--    fn_founder_command_control cancelled and superseded child tasks with a bulk UPDATE, which
--    bypasses fn_phase_c_task_transition — the routine that writes TRACE-TASK.  Four tasks were
--    closed with trace_id null and the invariant `closed_tasks_without_trace` caught it at 4.
--
--    The invariant was right and the code was wrong.  A cancellation is a state change a manager
--    has to be able to explain later, so it needs its trace exactly as much as a completion does.
--    Both control paths now write one trace per task, and the trace records who cancelled it.
--
-- 2. ONE TEST ARTEFACT REMOVED, SAID OUT LOUD.
--    scripts/checks/phase_c_command_center_entry_point.test.mjs committed a real command to prove
--    the entry point had actually run, then could not clean up after itself: founder_command_message
--    is append-only, and the trigger refused the delete.  The trigger is correct — the founder's
--    own words must not be erasable — and it is not being weakened.
--
--    But the words in question are not the founder's.  Message 73 reads "Run the full security and
--    quality gate before the next release today.", and he never said it; a test harness did.
--    Leaving it would put an instruction in his inbox that he did not give, which is worse than
--    the tidiness problem it solves. So it is removed HERE, in a committed migration that names
--    the exact row and the reason, with the guard dropped and recreated in the same file rather
--    than left off. The test has been rewritten to run in an aborted transaction so no future run
--    can create another one.
--
--    Removed: founder_command_message 73 (client_idempotency_key = 'entrypoint-selftest'), its
--    command, its 4 cancelled tasks, their traces and its outbox row. Nothing else is touched.
--
-- scripts/sql is append-only.  To change any of this, add a new file.

set lock_timeout = '8s';
set statement_timeout = '600s';

-- ------------------------------------------------------------------ 1. the trace on cancel
create or replace function public.fn_founder_command_control(
  p_command_id bigint, p_op text, p_target text, p_value text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare v_target bigint; v_state text; v_n bigint := 0; t record; v_trace bigint;
begin
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
          jsonb_build_object('reason', 'founder ' || p_op || ' of command ' || v_target)),
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
      'child_tasks_closed', v_n);

  elsif p_op = 'reprioritize' then
    if coalesce(p_value,'') !~ '^P[0-3]$' then
      return jsonb_build_object('ok', false, 'error','priority_required', 'allowed','P0..P3');
    end if;
    update public.founder_command set priority = p_value where command_id = v_target;
    update public.phase_c_task set priority = p_value where command_id = v_target and closed_at is null;
    get diagnostics v_n = row_count;
    return jsonb_build_object('ok', true, 'command_id', v_target, 'priority', p_value, 'tasks_updated', v_n);

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
      'plan', (select p.summary from public.founder_command_plan p where p.command_id = v_target));
  end if;
  return jsonb_build_object('ok', false, 'error','unknown_control_operation', 'op', p_op);
end $$;

-- ------------------------------------------------------------------ 2. remove the artefact
-- The guard comes off for exactly one targeted delete and goes back on in the same file.
drop trigger if exists z10_founder_command_message_immutable on public.founder_command_message;

delete from public.phase_c_trace
 where command_id in (select command_id from public.founder_command
                      where message_id in (select message_id from public.founder_command_message
                                           where client_idempotency_key = 'entrypoint-selftest'));
delete from public.phase_c_event_outbox
 where dedupe_value in (select 'founder_command:' || command_id from public.founder_command
                        where message_id in (select message_id from public.founder_command_message
                                             where client_idempotency_key = 'entrypoint-selftest'));
delete from public.phase_c_task
 where command_id in (select command_id from public.founder_command
                      where message_id in (select message_id from public.founder_command_message
                                           where client_idempotency_key = 'entrypoint-selftest'));
delete from public.founder_command
 where message_id in (select message_id from public.founder_command_message
                      where client_idempotency_key = 'entrypoint-selftest');
delete from public.founder_command_message where client_idempotency_key = 'entrypoint-selftest';

create trigger z10_founder_command_message_immutable before update or delete
  on public.founder_command_message for each row
  execute function public.fn_founder_command_message_immutable();
