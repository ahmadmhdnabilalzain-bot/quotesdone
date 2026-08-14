-- A QUESTION THAT WAS ANSWERED THREE HOURS AGO, ASKED AGAIN AT FULL PRICE.
--
-- MEASURED ON PRODUCTION, 14 Aug 2026.
--   999 org_tasks rows. 282 of them are exact (dept_key, title) duplicates; 71 of those are still
--   open. `test.failed on scheduled_run route_inquiry` exists EIGHT times for `knowledge`;
--   `test.failed on scheduled_run day_conductor` eight times; fifteen distinct `Supply gap: …`
--   titles exist five times each. One completed task states the position in its own words:
--   "Closed the 27-July verified_suppliers event as the ninth duplicate."
--   416 tasks were minted on 6 Aug alone against a 3-9/day baseline.
--
-- WHY, EXACTLY. fn_event_dispatch already deduplicates — but only against an OPEN task:
--
--     where t.decided_by = 'fn_event_dispatch' and t.dept_key = v_dept and t.title = v_title
--       and t.status not in ('done','closed','cancelled')
--
-- That is the right guard for a burst of the same event while the work is still queued, and it is
-- the wrong guard for a CONDITION THAT STAYS TRUE. `verified_suppliers` is missed because we have
-- one confirmed supplier; `reveals_30d` is missed because we have not traded. Those do not stop
-- being true because an employee wrote 4,000 characters about them and closed the row. The next
-- tick sees no OPEN task with that title, mints a fresh one, and pays for another large-tier
-- deliverable answering the question that was answered three hours ago. Nine times, measured.
--
-- The cost is not the row, it is the call. Every one of these is executed by exec_agents or
-- cos_execute on task_class 'agent_reasoning' — model_policy routes that to anthropic/claude-
-- sonnet-5, the large tier. agent_reasoning is AED 148 of the AED 210 spent on AI in 30 days.
--
-- THE FIX IS A COOL-DOWN, NOT A DEDUPE. Deduplication cannot see this, because at the moment the
-- new task is minted there is genuinely nothing open to merge it into. What is needed is memory of
-- having ALREADY ANSWERED: if this department closed an identically-titled dispatcher task inside
-- the cool-down, the event is attached to THAT task instead of raising a new one.
--
-- NOTHING IS LOST AND NOTHING IS CLOSED BY THIS CHANGE.
--   * The event still gets its event_delivery row, pointing at the task that carries the answer,
--     so the trail from event to determination is intact and queryable.
--   * v_delivered still counts it. A new counter, suppressed_recurring, reports how many were
--     handled this way, so the saving is measurable and the suppression is never silent.
--   * No existing row is closed, deleted or back-dated. The 71 open duplicates measured above are
--     left exactly as they are — this stops the treadmill, it does not tidy up after it.
--   * Only rows minted by fn_event_dispatch are considered. A task a human or another routine
--     raised with the same title is not eligible and is never attached to.
--
-- THE WINDOW IS A POLICY ROW, NOT A DEPLOY. decision_policy.event_recur_cooldown_days, default 7.
-- Same reasoning as prompt_cache_enabled: this is arithmetic over how fast a condition can
-- meaningfully change, and that number will move. Set it to 0 to restore the previous behaviour
-- exactly — the lookup is skipped entirely at 0, so there is a way back that needs no deploy.
--
-- PATCHED, NOT RETYPED. fn_event_dispatch is 337 lines with a documented history of two lists
-- that disagreed about the word 'escalated'. It is not reconstructed here: pg_get_functiondef is
-- read at run time and three exact anchors are replaced. Every replacement is asserted, so a
-- future edit that moves an anchor fails this migration loudly instead of silently applying two
-- thirds of a change.

do $mig$
declare
  src text;
  before text;
  a_decl constant text := '        v_title text; v_detail text; v_open_task bigint;';
  a_mint constant text := '    insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class,';
  a_ret  constant text := '                            ''backpressured'', v_backpressured,';
begin
  src := pg_get_functiondef('public.fn_event_dispatch(integer)'::regprocedure);

  -- 1. Declarations.
  before := src;
  src := replace(src, a_decl, a_decl || E'\n'
    || '        -- RECURRENCE COOL-DOWN (14 Aug 2026). See the migration header: the open-task guard' || E'\n'
    || '        -- below cannot see a condition that is STILL TRUE after its task was closed, so a' || E'\n'
    || '        -- standing miss re-minted itself every tick and was answered again at the large tier.' || E'\n'
    || '        v_recur_task bigint; v_suppressed integer := 0; v_cooldown_days integer;');
  if src = before then raise exception 'anchor 1 (declarations) not found in fn_event_dispatch — refusing to apply a partial patch'; end if;

  -- 2. The cool-down lookup, immediately before the mint.
  before := src;
  src := replace(src, a_mint,
       '    -- ALREADY ANSWERED, INSIDE THE COOL-DOWN. The lookup above found nothing OPEN, which for a' || E'\n'
    || '    -- recurring condition means the last one was closed, not that the question is new. Attach' || E'\n'
    || '    -- to the task that already carries the answer rather than buying another one.' || E'\n'
    || '    if v_cooldown_days > 0 then' || E'\n'
    || '      select t.id into v_recur_task' || E'\n'
    || '        from org_tasks t' || E'\n'
    || '       where t.decided_by = ''fn_event_dispatch''' || E'\n'
    || '         and t.dept_key = v_dept' || E'\n'
    || '         and t.title = v_title' || E'\n'
    || '         and t.status in (''done'',''closed'',''cancelled'')' || E'\n'
    || '         and coalesce(t.updated_at, t.created_at) > clock_timestamp() - make_interval(days => v_cooldown_days)' || E'\n'
    || '       order by coalesce(t.updated_at, t.created_at) desc' || E'\n'
    || '       limit 1;' || E'\n'
    || '      if v_recur_task is not null then' || E'\n'
    || '        insert into event_delivery (event_id, agent_key, event_type, os_key, task_id, delivered_at)' || E'\n'
    || '        values (r.event_id, r.agent_key, r.event_type, v_os, v_recur_task, clock_timestamp())' || E'\n'
    || '        on conflict do nothing;' || E'\n'
    || '        v_suppressed := v_suppressed + 1;' || E'\n'
    || '        v_delivered  := v_delivered + 1;' || E'\n'
    || '        continue;' || E'\n'
    || '      end if;' || E'\n'
    || '    end if;' || E'\n'
    || E'\n'
    || a_mint);
  if src = before then raise exception 'anchor 2 (org_tasks mint) not found in fn_event_dispatch — refusing to apply a partial patch'; end if;

  -- 3. Report it. A suppression nobody can count is indistinguishable from work that never arrived.
  before := src;
  src := replace(src, a_ret, a_ret || E'\n'
    || '                            ''suppressed_recurring'', v_suppressed,' || E'\n'
    || '                            ''recur_cooldown_days'', v_cooldown_days,');
  if src = before then raise exception 'anchor 3 (return object) not found in fn_event_dispatch — refusing to apply a partial patch'; end if;

  -- 4. Read the window once per invocation, at the top of the body.
  before := src;
  src := replace(src, E'begin\n',
       E'begin\n'
    || '  -- Policy, not deploy. 0 disables the cool-down and restores the pre-14-Aug behaviour exactly.' || E'\n'
    || '  select coalesce((value #>> ''{}'')::int, 7) into v_cooldown_days' || E'\n'
    || '    from decision_policy where key = ''event_recur_cooldown_days'';' || E'\n'
    || '  v_cooldown_days := coalesce(v_cooldown_days, 7);' || E'\n');
  if src = before then raise exception 'anchor 4 (body start) not found in fn_event_dispatch — refusing to apply a partial patch'; end if;

  execute src;
end $mig$;

-- The window itself. Kept out of the function so moving it is an UPDATE.
insert into decision_policy (key, value, description)
values ('event_recur_cooldown_days', '7'::jsonb,
        'fn_event_dispatch will not mint a second task for a (department, title) it already closed '
        'inside this many days; the event attaches to the closed task that carries the answer. '
        '0 disables the cool-down entirely.')
on conflict (key) do nothing;

-- CREATE OR REPLACE preserves the ACL, so there is no grant to restore and no revoke to add here.
