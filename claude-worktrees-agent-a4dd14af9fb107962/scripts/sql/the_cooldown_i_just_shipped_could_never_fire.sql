-- THE COOL-DOWN I SHIPPED TWENTY MINUTES AGO COULD NEVER FIRE.
--
-- a_question_that_was_answered_three_hours_ago.sql added a recurrence cool-down to
-- fn_event_dispatch and copied the discriminator from the open-task guard directly above it:
--
--     where t.decided_by = 'fn_event_dispatch' and t.dept_key = ... and t.title = ...
--       and t.status in ('done','closed','cancelled')
--
-- That condition is correct for an OPEN task and impossible for a CLOSED one. decided_by is not
-- provenance, it is WHO DECIDED — the executor overwrites it when it settles the row. Measured on
-- production immediately after deploying:
--
--     select count(*) from org_tasks
--      where decided_by='fn_event_dispatch' and status in ('done','closed','cancelled');   -- 0
--
-- Zero. Not "few": there has never been one and there never will be. The smoke test passed anyway
-- (the function returned the new suppressed_recurring and recur_cooldown_days keys), because a
-- guard that cannot match returns 0 suppressions and 0 is exactly what an idle bus returns too.
-- Shipping on that smoke test would have left a cool-down that reports success and does nothing.
--
-- THE DISCRIMINATOR THAT ACTUALLY EXISTS. A task the bus raised has an event_delivery row pointing
-- at it — that is what event_delivery is for, it survives the row being decided by someone else,
-- and 362 closed tasks carry one today. It is also strictly more correct than decided_by ever was:
-- it identifies a task the bus DELIVERED TO, which is the thing the cool-down is reasoning about.
--
-- Same three protections as before: only bus tasks are eligible, no row is closed or modified, and
-- the count is reported so the suppression is never silent.

do $mig$
declare
  src text;
  before text;
  -- Unique to the block added by the previous migration: the open-task guard above it selects into
  -- v_open_task and is indented two spaces less, so this anchor cannot match the wrong one.
  a_wrong constant text :=
       '      select t.id into v_recur_task' || E'\n'
    || '        from org_tasks t' || E'\n'
    || '       where t.decided_by = ''fn_event_dispatch''';
  a_right constant text :=
       '      select t.id into v_recur_task' || E'\n'
    || '        from org_tasks t' || E'\n'
    || '       -- Provenance is the delivery, not decided_by: the executor overwrites decided_by when' || E'\n'
    || '       -- it settles the row, so no closed task has ever carried ''fn_event_dispatch''.' || E'\n'
    || '       where exists (select 1 from event_delivery ed where ed.task_id = t.id)';
begin
  src := pg_get_functiondef('public.fn_event_dispatch(integer)'::regprocedure);

  before := src;
  src := replace(src, a_wrong, a_right);
  if src = before then
    raise exception 'the recurrence cool-down block is not in fn_event_dispatch in the shape this migration expects — refusing to guess; re-read the function before retrying';
  end if;

  execute src;
end $mig$;
