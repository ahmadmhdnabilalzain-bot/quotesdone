-- THE EVENT BUS — links 2,3,4,5 and 14 of the cross-OS contract, in the one routine that already
-- runs them. Every change here is additive to a bus that works: 534 cron runs, 266 deliveries.
--
-- WHAT WAS WRONG, MEASURED:
--  xos-02  86 of 316 events were NEVER delivered. The loop filtered on
--          `occurred_at > now() - lookback`, so an event that was not delivered inside its window
--          became permanently undeliverable — the subscription existed, the event existed, and
--          nothing would ever bring them together again. Undelivered-ness is the correct predicate
--          and the left join already expresses it; the time filter was fighting it.
--  xos-03  Subscriptions resolved to an AGENT and stopped there. The spec's unit is the Operating
--          System, so a delivery that cannot name an OS cannot satisfy link 3.
--  xos-04  Nothing recorded what an event MEANT to the OS receiving it. Every subscriber of every
--          event got one fixed title/detail template at action_class='analysis'.
--  xos-05  179 deliveries carried task_id NULL and a NULL that means "unroutable" is
--          indistinguishable from one that means "not created yet". THE AUDIT'S STATED CAUSE WAS
--          WRONG and measuring it changed the fix: org_agents.department is NOT NULL, so "the
--          subscriber has no department" is not a state this schema can hold. v_dept IS NULL means
--          there is NO org_agents ROW — the subscription points at an employee who does not exist.
--          Measured: 171 of the 179 are review.step -> knowledge_director between 28 Jul and 6 Aug,
--          from before that row existed, and exactly ONE subscriber is unresolvable today
--          (cybersecurity_mgr, 8 deliveries, subscribed to security.event and reaching nobody).
--  xos-14  correlation_id/causation_id were 0 of 316. The column default now supplies them, but a
--          default cannot know that THIS event caused THAT one — only the dispatcher knows, and
--          only while it holds both.
-- THE SIGNATURE IS EXACTLY THE OLD ONE, AND THAT IS DELIBERATE. Adding a second parameter would
-- have created an OVERLOAD rather than a replacement: cron job 141 runs `select
-- public.fn_event_dispatch()`, which resolves to the one-argument function, so a two-argument
-- version would have deployed cleanly, reported success, and left the cron running the old body
-- forever. The batch cap is therefore a constant, not a parameter.
--
-- THE DEFAULT MOVES 1440 -> 0, AND THAT IS THE ACTUAL FIX. The cron passes no argument, so the
-- default IS the production behaviour; leaving it at 1440 would have shipped every change below
-- while the 86-event backlog stayed permanently undeliverable.
create or replace function public.fn_event_dispatch(p_lookback_minutes integer default 0)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_delivered integer := 0; v_tasks integer := 0; v_gated integer := 0;
        v_unroutable integer := 0; v_assessed integer := 0; v_attached integer := 0;
        r record; v_task bigint; v_dept text; v_tier text; v_os text;
        v_sev text; v_resp text; v_impact text; v_subject_task bigint;
        -- 50, MEASURED, NOT GUESSED. The backlog this uncovers is 147 undelivered (event,
        -- subscriber) pairs — 145 routable, 2 unroutable, across 99 events — against 182 open
        -- tasks today. Draining it in one tick would nearly double the open queue in fifteen
        -- minutes; at 50 it lands over three ticks and the first one can be inspected before the
        -- rest arrives. The cap bounds the RATE, not the total: the backlog is finite and the
        -- loop still delivers every pair.
        c_max_batch constant integer := 50;
begin
  -- p_lookback_minutes is KEPT and now means what its name says: an optional narrowing for a
  -- manual catch-up run, not a wall that silently drops events. <= 0 means "every undelivered
  -- event, however old", which is the setting the cron uses.
  for r in
    select e.id as event_id, e.event_type, e.entity_type, e.entity_id, e.actor, e.occurred_at,
           e.correlation_id, e.payload, s.agent_key, s.reason
    from company_event e
    join event_subscription s on s.active and s.event_type = e.event_type
    left join event_delivery d on d.event_id = e.id and d.agent_key = s.agent_key
    where d.id is null
      and (p_lookback_minutes <= 0
           or e.occurred_at > now() - make_interval(mins => p_lookback_minutes))
      and s.agent_key <> coalesce(e.actor, '')
    order by e.id
    -- BOUNDED ON PURPOSE. Dropping the time filter exposes a real backlog, and this bus has
    -- already produced 169 tasks in one hour once. A batch cap drains it over consecutive ticks
    -- instead of in a single burst, and the cron runs every 15 minutes.
    limit c_max_batch
  loop
    select department into v_dept from org_agents where agent_key = r.agent_key;
    -- xos-03. The OS, not just the agent. Resolved through the same os_department link the rest
    -- of the blueprint uses, so a department that belongs to no OS is visibly null rather than
    -- silently defaulted to one.
    select od.os_key into v_os from os_department od where od.dept_key = v_dept;
    v_task := null;

    -- xos-14. Everything raised from here on belongs to THIS event's chain and was CAUSED by it.
    -- Set before any insert so a trigger firing downstream inherits both through the column
    -- defaults on company_event — that is why the defaults read a setting rather than a literal.
    perform set_config('app.correlation_id', coalesce(r.correlation_id::text, ''), true);
    perform set_config('app.causation_event_id', r.event_id::text, true);

    if v_dept is null then
      -- xos-05. Say why. An unroutable subscription is a real defect in the subscription table
      -- and it was previously indistinguishable from a task that had not been created yet.
      insert into event_delivery (event_id, agent_key, event_type, os_key, task_id, unroutable_reason)
      values (r.event_id, r.agent_key, r.event_type, v_os, null,
              format('no org_agents row for subscriber %s — this subscription points at an '
                  || 'employee who does not exist, so the event reaches nobody', r.agent_key))
      on conflict do nothing;
      v_unroutable := v_unroutable + 1;
      v_delivered  := v_delivered + 1;
      continue;
    end if;

    -- 7.3 PRECONDITION. This used to hard-code tier 'autonomous', so a subscriber was granted
    -- autonomy by the dispatcher rather than by the authority model. It reads the tier now.
    v_tier := coalesce(public.fn_dept_authority(v_dept, 'analysis')->>'tier', 'gated');
    if v_tier <> 'autonomous' then v_gated := v_gated + 1; end if;

    -- xos-04. ASSESS BEFORE ACTING. The severity is the OS's own declared reading of this input
    -- from os_interface; the impact names which of the OS's declared responsibilities the event
    -- touches. Both come from tables the founder populated, so this is a JOIN, not a judgement.
    -- A NULL severity is itself the finding: the OS received an event it never declared it
    -- consumes, which is exactly the os_interface/event_subscription drift comp-07 measures.
    if v_os is not null then
      select i.severity into v_sev
        from os_interface i
       where i.os_key = v_os and i.event_type = r.event_type and i.direction = 'input'
       limit 1;
      select string_agg(x.responsibility, ', ')
        into v_resp
        from (select responsibility from os_responsibility
               where os_key = v_os order by responsibility limit 3) x;
      v_impact := format('%s affects %s: %s',
                         r.event_type, v_os, coalesce(v_resp, 'no declared responsibilities'));
      insert into event_assessment (event_id, os_key, agent_key, severity, impact, proposed_action)
      values (r.event_id, v_os, r.agent_key, coalesce(v_sev, 'medium'), v_impact,
              case when v_sev is null
                   then 'UNDECLARED INPUT: os_interface does not list this event type for this OS'
                   else coalesce(r.reason, 'act on the subscription') end)
      on conflict (event_id, os_key) do nothing;
      v_assessed := v_assessed + 1;
    end if;

    -- xos-05 / contract-consolidation. THE EVENT THAT REPORTS ON WORK IS NOT NEW WORK.
    --
    -- MEASURED 6 Aug 2026, and it is a divergent feedback loop, not an inefficiency. Closing one
    -- task runs fn_task_review, which writes 3-4 review_chain rows; trg_event_review emits one
    -- review.step per row; knowledge_director subscribes to review.step; and this loop minted a
    -- fresh org_task for every one of them. review.step was 183 of the ~300 events of the last
    -- seven days and 217 of 576 deliveries all time. The Chief of Staff's executor closes 2 tasks
    -- an hour, so every closure created 3-4 new tasks and the queue grew by working it — 336 open
    -- event-derived tasks against 58 ever closed, and no coverage ratio for "the loop closes"
    -- could ever be satisfied while that held.
    --
    -- The row already says what the event is about: fn_emit_event copies the whole source row into
    -- payload, so a review_chain event carries subject_type='org_task' and subject_id. When the
    -- event REPORTS ON a task that exists, the work is that task. The delivery is attached to it,
    -- so the result that comes back is that task's own result and the loop closes on the work
    -- itself rather than on a duplicate of it. Nothing is dropped: the delivery, its os_key and
    -- its assessment (above) are all still written.
    --
    -- Scoped by the payload, not by an event-type list: any future emitter whose row names an
    -- org_task subject gets the same treatment, and one that does not still raises a task.
    v_subject_task := null;
    if r.payload->>'subject_type' = 'org_task' and coalesce(r.payload->>'subject_id','') ~ '^[0-9]+$' then
      select t.id into v_subject_task
        from org_tasks t where t.id = (r.payload->>'subject_id')::bigint;
    end if;
    if v_subject_task is not null then
      insert into event_delivery (event_id, agent_key, event_type, os_key, task_id)
      values (r.event_id, r.agent_key, r.event_type, v_os, v_subject_task)
      on conflict do nothing;
      v_attached  := v_attached + 1;
      v_delivered := v_delivered + 1;
      continue;
    end if;

    insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class, decided_by)
    values (v_dept,
            left(r.event_type || ' on ' || r.entity_type || ' ' || coalesce(r.entity_id,''), 200),
            format('Event %s (%s %s) raised by %s at %s. You subscribe to this because: %s. '
                || 'Assessed impact: %s. Act on it or close it with a reason.',
                   r.event_type, r.entity_type, coalesce(r.entity_id,'-'), coalesce(r.actor,'system'),
                   r.occurred_at, coalesce(r.reason,'subscription'), coalesce(v_impact,'not assessed')),
            case when v_tier = 'autonomous' then 'assigned' else 'proposed' end,
            v_tier, v_tier <> 'autonomous', 'analysis', 'fn_event_dispatch')
    returning id into v_task;
    v_tasks := v_tasks + 1;

    insert into event_delivery (event_id, agent_key, event_type, os_key, task_id)
    values (r.event_id, r.agent_key, r.event_type, v_os, v_task)
    on conflict do nothing;
    v_delivered := v_delivered + 1;
  end loop;

  -- Leave no correlation bound to the session after the loop: a later statement on this
  -- connection is NOT part of the last event's chain, and inheriting it would be a false link.
  perform set_config('app.correlation_id', '', true);
  perform set_config('app.causation_event_id', '', true);

  return jsonb_build_object('delivered', v_delivered, 'tasks_created', v_tasks,
                            'attached_to_existing_task', v_attached,
                            'tasks_awaiting_a_human', v_gated,
                            'unroutable', v_unroutable, 'assessed', v_assessed,
                            'lookback_minutes', p_lookback_minutes,
                            'max_batch', c_max_batch);
end; $function$;
