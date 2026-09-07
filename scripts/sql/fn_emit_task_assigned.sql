-- comp-09-workflows / comp-09-workflow-execution — the fourteenth workflow had no trigger.
--
-- 13 of the 14 active workflows carry a declared event_type. The 14th, employee_task ("Standard
-- Employee Task Loop", 17 steps, os_key=operations), carried NULL: the bus had no token for a task
-- assignment. 642 org_tasks rows exist and 14 routines write them, so the work IS happening — it
-- was simply never announced, which is why the canonical per-employee loop could never start.
--
-- THE FEEDBACK LOOP, AND WHY THIS CANNOT ENTER IT. fn_event_dispatch CREATES org_tasks from events,
-- so anything that emits on task creation can feed the dispatcher that fed it — the same shape that
-- produced 169 tasks in one hour on 6 Aug. Two independent gates, both keyed on facts the dispatcher
-- itself writes:
--   1. decided_by = 'fn_event_dispatch' is excluded here. That is the literal the dispatcher stamps
--      on every task it mints (fn_event_dispatch, `..., 'analysis', 'fn_event_dispatch')`), so a
--      dispatch-created task can never be re-announced. Measured on production before deploying:
--      366 of the 476 assigned tasks are dispatch-created and are all excluded; the 110 that remain
--      are approval_path (105) and dept_plan (5), which no event produced.
--   2. The payload names the task as its SUBJECT. fn_event_dispatch already branches on
--      `payload->>'subject_type' = 'org_task'` and attaches the delivery to that existing task
--      instead of raising a new one — "the event that reports on work is not new work". So even if
--      somebody subscribes an agent to task.assigned tomorrow, the dispatcher attaches rather than
--      mints, and the loop has no second turn to take.
-- Nothing subscribes to task.assigned today, so the dispatcher does not act on it at all; the gates
-- are there for the day something does.
--
-- WHAT COUNTS AS THE MOMENT OF ASSIGNMENT. created_at, and nothing else. org_tasks has no
-- assigned_at column, and the first form of this function used coalesce(updated_at, created_at) —
-- which is a LAST-TOUCHED time, not an assignment time. It announced 50 tasks created before 30
-- July as assignments of the last day, because fn_task_approve and the executor bump updated_at on
-- work that was assigned days earlier. That emission is withdrawn in
-- scripts/sql/rollback_task_assigned_backdate.sql. created_at is the real thing for a task created
-- already assigned, which is how approval_path (105 rows) and dept_plan (5) raise theirs.
--
-- ponytail: a task created 'proposed' and moved to 'assigned' later is therefore NOT announced —
-- the transition leaves no timestamp anywhere, so announcing it would mean guessing when it
-- happened. 35 of 648 production tasks sit in 'proposed'. Give org_tasks an assigned_at column, or
-- an AFTER UPDATE OF status trigger, if that tail ever matters; both belong to the org_tasks
-- workstream, not this one.
--
-- ponytail: polls on a 15-minute cron rather than a trigger on org_tasks. A task created and closed
-- inside one interval is never announced. Same upgrade path, same reason for not taking it here.

create or replace function public.fn_emit_task_assigned(p_lookback_minutes integer DEFAULT 60)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; n int := 0;
begin
  for r in
    select t.id, t.dept_key, t.title, t.action_class, t.tier, t.needs_founder, t.decided_by,
           t.created_at as assigned_at
      from org_tasks t
     where t.status = 'assigned'
       -- GATE 1: never re-announce what the dispatcher itself raised from an event.
       and coalesce(t.decided_by, '') <> 'fn_event_dispatch'
       and (p_lookback_minutes <= 0
            or t.created_at > now() - make_interval(mins => p_lookback_minutes))
       -- One announcement per task, forever. This is the idempotency key: re-running the catch-up,
       -- or a task updated again while still assigned, emits nothing further.
       and not exists (select 1 from company_event e
                        where e.event_type = 'task.assigned'
                          and e.entity_type = 'org_task' and e.entity_id = t.id::text)
     order by t.created_at                 -- chronological: announce assignments in the order made
     limit 50                              -- rate cap, in line with fn_event_dispatch's c_max_batch
  loop
    perform public.fn_emit('task.assigned', 'org_task', r.id::text,
              coalesce(r.decided_by, 'system'),
              jsonb_build_object(
                -- GATE 2: the dispatcher reads these two and attaches to the task instead of
                -- creating one. Do not rename them.
                'subject_type', 'org_task',
                'subject_id',   r.id::text,
                'task_id',      r.id,
                'dept_key',     r.dept_key,
                'title',        r.title,
                'action_class', r.action_class,
                'tier',         r.tier,
                'needs_founder', r.needs_founder,
                'assigned_by',  r.decided_by,
                'assigned_at',  r.assigned_at));
    n := n + 1;
  end loop;
  return n;
end $function$;

-- Every 15 minutes, on the same tick as the workflow catcher, with an hour of overlap so a slow or
-- skipped tick loses nothing (the idempotency check above makes the overlap free).
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.

-- Announce the assignments already standing today. 1440 = the last day, NOT 0: an event carries
-- occurred_at = now(), so announcing a task assigned three days ago would date it wrongly. The
-- payload carries the real assigned_at either way. Older standing assignments are left unannounced
-- rather than back-dated into a lie.
select public.fn_emit_task_assigned(1440);
