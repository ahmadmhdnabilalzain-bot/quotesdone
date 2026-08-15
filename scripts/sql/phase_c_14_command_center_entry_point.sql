-- Phase C — the Command Center's entry point, and the second gate it has to pass.
--
-- Phase B recorded five finished capabilities with no entry point, and the founder's lens for
-- this session is the same one: ask what the user CLICKS.  A command table that only a SQL
-- session can reach is not a command channel.  os_api gains four actions in the same commit as
-- this file:
--
--   founder_command          mutating   submit an instruction; returns command id, plan and tasks
--   founder_command_control  mutating   cancel, reprioritise, supersede, explain
--   founder_command_status   read-only  the state of one command and its tasks
--   founder_command_inbox    read-only  what the founder is looking at
--
-- os_api enforces TWO independent gates and they use one vocabulary: ACTION_CLASS in the edge
-- function, and public.control_mode_action in the database.  An action present in one and absent
-- from the other is the defect that made read-only screens demand a phone code, so all four are
-- registered in both, in the same change.
--
-- scripts/sql is append-only.  To change any of this, add a new file.

set lock_timeout = '8s';
set statement_timeout = '600s';

-- requires_control is a GENERATED column derived from classification, so it is not written here.
-- That is the right shape and worth keeping: it makes "mutating but ungated" unrepresentable
-- rather than merely discouraged.
insert into public.control_mode_action (action, description, risk, classification) values
  ('founder_command',
   'Founder Command Center: submit an instruction. Deterministically routed to existing Phase B workflows and canonical roles; creates a command plan and its immediate tasks in one transaction. No raw text reaches an executor.',
   'medium', 'mutating'),
  ('founder_command_control',
   'Founder Command Center: cancel, reprioritise, supersede or explain a command. Cancellation invokes the workflow''s cancellation policy; history is preserved.',
   'medium', 'mutating'),
  ('founder_command_status',
   'Founder Command Center: read one command, its plan, its tasks, their owners and blockers.',
   'low', 'read_only'),
  ('founder_command_inbox',
   'Founder Command Center: the founder''s own view — recent commands, what is open, what is blocked and what needs his refund decision.',
   'low', 'read_only')
on conflict (action) do update set description = excluded.description, risk = excluded.risk,
  classification = excluded.classification;

-- What the founder actually looks at.  Deliberately answers four questions in one call, because
-- the alternative is four round trips and a screen that shows a number without its cause.
create or replace function public.fn_founder_command_inbox(p_limit integer default 25)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select jsonb_build_object(
    'as_of', now(),
    'commands', coalesce((
      select jsonb_agg(x order by x->>'command_id' desc) from (
        select jsonb_build_object(
          'command_id', c.command_id, 'state', c.state, 'intent', c.intent_id,
          'outcome', c.outcome, 'priority', c.priority, 'due_at', c.due_at,
          'said', left(m.raw_text, 240), 'at', c.created_at,
          'owner', c.command_owner_role_id,
          'plan', (select p.summary from public.founder_command_plan p where p.command_id = c.command_id),
          'clarification', (select cl.question from public.founder_command_clarification cl
                            where cl.command_id = c.command_id and cl.answered_at is null
                            order by cl.clarification_id desc limit 1),
          'tasks_open', (select count(*) from public.phase_c_task t
                         where t.command_id = c.command_id and t.closed_at is null),
          'tasks_blocked', (select count(*) from public.phase_c_task t
                            where t.command_id = c.command_id and t.state = 'blocked'),
          'owners', (select coalesce(jsonb_agg(distinct t.accountable_role_id), '[]'::jsonb)
                     from public.phase_c_task t where t.command_id = c.command_id),
          'overlays_invoked', (select coalesce(jsonb_agg(o.overlay_id), '[]'::jsonb)
                               from public.founder_command_overlay_invocation o where o.command_id = c.command_id)
        ) x
        from public.founder_command c
        join public.founder_command_message m on m.message_id = c.message_id
        order by c.command_id desc
        limit greatest(1, coalesce(p_limit, 25))
      ) s), '[]'::jsonb),
    -- The ONE thing that is his to decide.  Nothing else in the company reaches this list.
    'awaiting_your_decision', coalesce((
      select jsonb_agg(jsonb_build_object(
        'request_id', a.request_id, 'transaction', a.subject_ref, 'prepared_by', a.prepared_by_role_id,
        'note', a.amount_note, 'since', a.created_at, 'command_id', a.command_id))
      from public.founder_approval_request a where a.state = 'pending'), '[]'::jsonb),
    'blocked_tasks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'task_id', t.task_id, 'owner', t.accountable_role_id, 'manager', t.manager_role_id,
        'blocker', t.blocker, 'resolution_owner', t.blocker_owner_role_id, 'since', t.updated_at))
      from public.phase_c_task t where t.state = 'blocked'), '[]'::jsonb),
    'overdue_handoffs', coalesce((
      select jsonb_agg(jsonb_build_object(
        'handoff_run_id', h.handoff_run_id, 'handoff', h.handoff_id, 'sender', h.sender,
        'receiver', h.receiver, 'hours_late', h.hours_late))
      from public.fn_phase_c_handoff_overdue() h), '[]'::jsonb),
    'counts', jsonb_build_object(
      'commands', (select count(*) from public.founder_command),
      'open_commands', (select count(*) from public.founder_command where closed_at is null),
      'open_tasks', (select count(*) from public.phase_c_task where closed_at is null),
      'awaiting_founder', (select count(*) from public.founder_approval_request where state = 'pending'),
      'non_refund_awaiting_founder', public.fn_phase_c_non_refund_founder_approvals())
  );
$$;
revoke all on function public.fn_founder_command_inbox(integer) from public;
grant execute on function public.fn_founder_command_inbox(integer) to service_role;
