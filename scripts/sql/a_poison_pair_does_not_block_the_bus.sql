-- A POISON PAIR DOES NOT BLOCK THE BUS (5 Sep 2026). MASTER_PLAN §4.1 / s21-no-polling.
--
-- MEASURED on htdblwldjkcgjvmqkbeh, 4 Sep 2026 05:45-09:00 UTC: one (event, subscriber) pair raised
-- 23514 inside fn_event_dispatch and, because the whole call is one transaction, EVERY pair in the
-- batch rolled back with it. The cron sweep (lookback 0, order by e.id limit 50) met the same pair at
-- the head of its batch on all fourteen ticks and delivered nothing for three hours; the trigger path
-- kept delivering only because its 20-minute window happened not to contain the poison pair. One bad
-- subscription is head-of-line blocking for the entire company bus, on both paths.
--
-- Each pair now runs inside its own sub-transaction. A pair that raises is counted, its sqlstate and
-- message kept, and the loop goes on to the next pair; the failed pair gets NO delivery row, so it is
-- retried on every later pass and delivers the moment its cause is fixed. When any pair failed, ONE
-- agent_runs error row per call names the count and the first failure, so fn_watch_failed_runs pages
-- it once per signature per day and the red view carries it as a watcher episode -- the failure moves
-- from "the kernel trace of the cron failed and the bus stopped" to "this pair failed and the bus went
-- on", it does not disappear. Every other line is the live definition of 4 Sep 2026, unchanged.
--
--   node scripts/apply_sql.mjs scripts/sql/a_poison_pair_does_not_block_the_bus.sql --apply --ddl
CREATE OR REPLACE FUNCTION public.fn_event_dispatch(p_lookback_minutes integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_delivered integer := 0; v_tasks integer := 0; v_gated integer := 0;
        v_unroutable integer := 0; v_assessed integer := 0; v_attached integer := 0;
        r record; v_task bigint; v_dept text; v_tier text; v_os text;
        v_impact text; v_subject_task bigint;
        v_title text; v_detail text; v_open_task bigint;
        -- RECURRENCE COOL-DOWN (14 Aug 2026). See the migration header: the open-task guard
        -- below cannot see a condition that is STILL TRUE after its task was closed, so a
        -- standing miss re-minted itself every tick and was answered again at the large tier.
        v_recur_task bigint; v_suppressed integer := 0; v_cooldown_days integer;
        v_open_bus integer; v_capped boolean; v_backpressured integer := 0;
        -- 5 SEP 2026: per-pair failures are counted and carried, never allowed to abort the batch.
        v_failed integer := 0; v_first_err text;
        -- BACK-PRESSURE. 25 OPEN BUS TASKS PER DEPARTMENT, MEASURED 6 Aug 2026 ON PRODUCTION.
        --
        -- The queue grows ~100x faster than it drains. The dispatcher mints up to 50 (event,
        -- subscriber) pairs per */15 tick — 329 events arrived in the last 24 hours — while the
        -- whole organisation closed 132 org_tasks in 30 days, 4.4 a day. Of those 132, ZERO were
        -- bus-minted: all 395 tasks this routine has ever authored are still open, none has ever
        -- reached 'done'. 395 pieces of work nobody will ever reach is the same built-and-never-
        -- read defect the blueprint exists to catch, one level up.
        --
        -- 25 is the cap because it is generous against the MEASURED drain of every department.
        -- Closures in 30d, by department: knowledge 41, exec 32, it 14, procurement 8,
        -- knowledge_eng 7, finance 7, marketing 6, legal 5, evolution 4, intelligence 4,
        -- supplier_success 2, hr 1, sales 1. At the FASTEST of those, 25 open bus tasks is
        -- eighteen days of queue; at the median (5/30d) it is five months. A department holding
        -- more than 25 is not busy, it is unreachable, and minting a 26th is writing into a
        -- surface with no reader.
        --
        -- Open bus queue when this cap was chosen: knowledge 102, exec 97, knowledge_eng 46,
        -- sales 36, marketing 32 (over) — finance 19, evolution 19, intelligence 19, legal 12,
        -- it 12, procurement 1 (under). So the bus keeps minting per-event work for six of the
        -- eleven departments and stops piling it onto the five that are already buried.
        c_max_open_per_dept integer := coalesce((select (value #>> '{}')::int from public.decision_policy where key = 'dispatch_max_open_per_dept'), 250);
        -- 50, MEASURED, NOT GUESSED. The backlog this uncovers is 147 undelivered (event,
        -- subscriber) pairs — 145 routable, 2 unroutable, across 99 events — against 182 open
        -- tasks today. Draining it in one tick would nearly double the open queue in fifteen
        -- minutes; at 50 it lands over three ticks and the first one can be inspected before the
        -- rest arrives. The cap bounds the RATE, not the total: the backlog is finite and the
        -- loop still delivers every pair.
        c_max_batch integer := coalesce((select (value #>> '{}')::int from public.decision_policy where key = 'dispatch_max_batch'), 500);
begin
  -- Policy, not deploy. 0 disables the cool-down and restores the pre-14-Aug behaviour exactly.
  select coalesce((value #>> '{}')::int, 7) into v_cooldown_days
    from decision_policy where key = 'event_recur_cooldown_days';
  v_cooldown_days := coalesce(v_cooldown_days, 7);
  -- ── PASS 1 · ASSESS EVERYTHING PENDING, BEFORE ACTING ON ANY OF IT ──────────────────────────
  -- xos-04. The severity is the OS's own declared reading of this input from os_interface; the
  -- impact names which of the OS's declared responsibilities the event touches. Both come from
  -- tables the founder populated, so this is a JOIN, not a judgement. A NULL severity is itself
  -- the finding: the OS received an event it never declared it consumes, which is exactly the
  -- os_interface/event_subscription drift comp-07 measures.
  --
  -- HOISTED OUT OF THE LOOP 6 Aug 2026, AND IT IS A CORRECTNESS FIX, NOT A TIDY-UP. It used to sit
  -- inside the loop, one insert per iteration, which made "assessed before acting" true PER EVENT
  -- and false ACROSS THE BATCH. Any branch that ATTACHES event j to a task minted for event i
  -- earlier in the same run stamps assessed_at(j) AFTER created_at(i's task) — and when that task
  -- was raised after event j occurred, that reads exactly like acting before assessing. MEASURED
  -- on staging with the back-pressure branch in the loop: 56 deliveries assessed after the task
  -- they attached to, 50 of them on a back-pressure task, from a production baseline of 0. The
  -- latent form of the same hazard was already there in the duplicate-subject attach.
  --
  -- One statement, before any org_tasks row in this run exists, so every assessment strictly
  -- precedes every task and every delivery this run creates. The order is real, not asserted.
  --
  -- DELIBERATELY UNBOUNDED, where the delivery loop below takes 50. The two queries are separate
  -- and the invariant between them is "pass 1 is a SUPERSET of pass 2", not "identical" — a much
  -- weaker thing to keep true. Assessing an event this tick that gets delivered three ticks later
  -- is free (the insert is idempotent on (event_id, os_key)) and still correct: it was assessed
  -- before it was acted on. Sharing a LIMIT, by contrast, could cut the two batches differently on
  -- an e.id tie and leave a delivered pair unassessed, which is the one outcome xos-04 forbids.
  --
  -- The inner joins to org_agents/os_department are the v_os test from the old inline form: a
  -- subscription pointing at an employee who does not exist, or a department belonging to no OS,
  -- produces no assessment here and is handled as unroutable in the loop, exactly as before.
  with pending as (
    select distinct on (e.id, od.os_key)
           e.id as event_id, e.event_type, od.os_key, s.agent_key, s.reason
      from company_event e
      join event_subscription s on s.active and s.event_type = e.event_type
                               and s.agent_key <> coalesce(e.actor, '')
      join org_agents a         on a.agent_key = s.agent_key
      join os_department od     on od.dept_key = a.department
      left join event_delivery d on d.event_id = e.id and d.agent_key = s.agent_key
     where d.id is null
       and (p_lookback_minutes <= 0
            or e.occurred_at > now() - make_interval(mins => p_lookback_minutes))
     order by e.id, od.os_key, s.agent_key
  )
  insert into event_assessment (event_id, os_key, agent_key, severity, impact, proposed_action,
                                assessed_at)
  select p.event_id, p.os_key, p.agent_key, coalesce(i.severity, 'medium'),
         format('%s affects %s: %s', p.event_type, p.os_key,
                coalesce(rs.resp, 'no declared responsibilities')),
         case when i.severity is null
              then 'UNDECLARED INPUT: os_interface does not list this event type for this OS'
              else coalesce(p.reason, 'act on the subscription') end,
         -- clock_timestamp(), NOT the column default. "BEFORE acting" was UNMEASURABLE while every
         -- timestamp here came from now(): now() is TRANSACTION start, so the assessment, the task
         -- and the delivery all carried the identical value and `assessed_at > created_at` read 0
         -- whatever order the statements ran in. clock_timestamp() is statement time, so the
         -- ordering below is stored rather than assumed. Move this block after the loop and
         -- xos-04 fails, which is the property that makes it a measurement.
         clock_timestamp()
    from pending p
    left join lateral (select i2.severity from os_interface i2
                        where i2.os_key = p.os_key and i2.event_type = p.event_type
                          and i2.direction = 'input' limit 1) i on true
    left join lateral (select string_agg(x.responsibility, ', ') as resp
                         from (select responsibility from os_responsibility
                                where os_key = p.os_key order by responsibility limit 3) x) rs on true
  on conflict (event_id, os_key) do nothing;
  get diagnostics v_assessed = row_count;

  -- ── PASS 2 · ROUTE, RAISE WORK, DELIVER ─────────────────────────────────────────────────────
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
    -- 5 SEP 2026: one sub-transaction per pair. See the header: a single raising pair used to roll
    -- back the whole batch, and at the head of the cron sweep it blocked every delivery behind it.
    begin
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
      --
      -- AND IT IS CLOSED HERE, 6 Aug 2026. An unroutable delivery is TERMINAL: no task exists, no
      -- task will ever exist, and no result can ever come back — so leaving result/closed_at NULL
      -- filed it forever as "loop still open". It is not open; it finished, badly, at this instant,
      -- and the reason it finished is already on the row. contract-consolidation asks whether the
      -- deliveries the bus made came back with a result; a broken subscription that can never come
      -- back dragged that ratio down permanently and no amount of correct work could ever clear it.
      -- The result is the reason, not a placeholder, and closed_at is now, not the delivery's past.
      insert into event_delivery (event_id, agent_key, event_type, os_key, task_id, delivered_at,
                                  unroutable_reason, result, closed_at)
      values (r.event_id, r.agent_key, r.event_type, v_os, null, clock_timestamp(),
              format('no org_agents row for subscriber %s — this subscription points at an '
                  || 'employee who does not exist, so the event reaches nobody', r.agent_key),
              left(format('unroutable: no org_agents row for subscriber %s; the event reached '
                  || 'nobody and nothing further will happen to this delivery', r.agent_key), 1000),
              clock_timestamp())
      on conflict do nothing;
      v_unroutable := v_unroutable + 1;
      v_delivered  := v_delivered + 1;
      continue;
    end if;

    -- 7.3 PRECONDITION. This used to hard-code tier 'autonomous', so a subscriber was granted
    -- autonomy by the dispatcher rather than by the authority model. It reads the tier now.
    v_tier := coalesce(public.fn_dept_authority(v_dept, 'analysis')->>'tier', 'gated');
    if v_tier <> 'autonomous' then v_gated := v_gated + 1; end if;

    -- xos-04. The assessment for this (event, OS) was written in PASS 1, before this loop began
    -- and therefore before any task in this run exists. Read the impact back for the task detail
    -- below rather than recomputing it, so the sentence the employee reads is the same sentence
    -- the OS recorded. NULL when the department resolves to no OS, which coalesce() handles.
    select a.impact into v_impact
      from event_assessment a where a.event_id = r.event_id and a.os_key = v_os;

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
    -- its assessment (pass 1) are all still written.
    --
    -- Scoped by the payload, not by an event-type list: any future emitter whose row names an
    -- org_task subject gets the same treatment, and one that does not still raises a task.
    v_subject_task := null;
    if r.payload->>'subject_type' = 'org_task' and coalesce(r.payload->>'subject_id','') ~ '^[0-9]+$' then
      select t.id into v_subject_task
        from org_tasks t where t.id = (r.payload->>'subject_id')::bigint;
    end if;
    if v_subject_task is not null then
      insert into event_delivery (event_id, agent_key, event_type, os_key, task_id, delivered_at)
      values (r.event_id, r.agent_key, r.event_type, v_os, v_subject_task, clock_timestamp())
      on conflict do nothing;
      v_attached  := v_attached + 1;
      v_delivered := v_delivered + 1;
      continue;
    end if;

    -- THE SAME SUBJECT, RAISED AGAIN, IS NOT A SECOND PIECE OF WORK.
    --
    -- The attach above handles an event that REPORTS ON a task. This is its sibling: an event that
    -- re-reports the SAME SUBJECT to the SAME department while that department's task for it is
    -- still open and untouched. MEASURED 6 Aug 2026 on production: of 372 open bus-minted tasks,
    -- 107 (29%) are duplicate copies — 'test.failed on scheduled_run uptime' had SIX open copies
    -- raised the same day, 'kpi.missed on metric open_p1' three. The Chief of Staff's executor
    -- closes 2 tasks an hour, so a condition that re-fires hourly minted copies faster than the
    -- company could ever work them, and every copy diluted the coverage the closing loop is scored
    -- on. The title is the subject identity the mint below already builds from event_type +
    -- entity_type + entity_id, so it is computed once here and reused rather than re-derived.
    --
    -- The delivery is STILL WRITTEN — the denominator does not shrink, and that is the point. When
    -- the department finally does the work, fn_event_consolidate closes EVERY delivery attached to
    -- that task, so all six events that reported the failure get the same result back. That is the
    -- contract ("the result comes back to the event that caused the work"), not an exemption from it.
    --
    -- Scoped to decided_by='fn_event_dispatch' so the bus can only ever attach to its OWN open
    -- task: a human's or another routine's task with a colliding title is never hijacked.
    -- ── BACK-PRESSURE ─────────────────────────────────────────────────────────────────────────
    -- THE BUS MUST NOT MINT NEW WORK INTO A DEPARTMENT WHOSE BUS QUEUE IS NOT DRAINING.
    --
    -- The two attach branches above stop the bus DUPLICATING work. Neither of them stops it
    -- OUTPACING the company: 395 bus tasks minted, 0 ever closed, against an organisation that
    -- closes 4.4 tasks a day across every department and every author. Deduplication cannot fix
    -- a rate mismatch — every one of those 395 is a distinct subject.
    --
    -- So the department's own open bus queue is the signal. Over the cap, this event does not get
    -- its own task; it is collapsed onto the department's single standing back-pressure task by
    -- rewriting v_title to a per-department constant. That makes the attach lookup immediately
    -- below do the work — the first over-cap event mints the standing task, every later one
    -- attaches to it — instead of adding a third near-identical branch beside the two above.
    --
    -- WHAT IS NOT SKIPPED, AND BOTH ARE THE POINT:
    --  * THE DELIVERY IS STILL WRITTEN, below, exactly as in every other branch. Skipping it would
    --    make the event permanently undeliverable again — the xos-02 defect at the top of this
    --    file — and would SHRINK the denominator of contract-consolidation, flattering that ratio
    --    while fixing nothing. Back-pressure regulates work, never the ledger.
    --  * THE ASSESSMENT IS ALREADY WRITTEN, in PASS 1, before this loop began — so it cannot be
    --    reached by any decision taken here. xos-04 says nothing is acted on unassessed, and no
    --    reordering of the branches in this loop can lose one or stamp one late.
    -- And when the department finally drains the standing task, fn_event_consolidate closes EVERY
    -- delivery attached to it, so all the queued events get their result back. Same contract as
    -- the duplicate-subject attach, one level up.
    select count(*) into v_open_bus
      from org_tasks t
     where t.decided_by = 'fn_event_dispatch'
       and t.dept_key = v_dept
       and t.status not in ('done','closed','cancelled');
    v_capped := v_open_bus >= c_max_open_per_dept;

    if v_capped then
      v_title  := left('bus.backpressure on department ' || v_dept, 200);
      v_detail := format('BUS BACK-PRESSURE — %s holds %s open task(s) raised by the event bus and '
                      || 'the bus has stopped minting more into it (cap %s). Events still arrive: '
                      || 'each one is delivered and assessed as normal and attached to THIS task '
                      || 'instead of raising its own, so nothing is lost and the queue stops '
                      || 'growing. Drain %s below %s open bus tasks and per-event tasks resume by '
                      || 'themselves. Close this one when the backlog is worked; every event '
                      || 'queued behind it gets that result back. Latest arrival: %s (%s %s) at %s.',
                         v_dept, v_open_bus, c_max_open_per_dept, v_dept, c_max_open_per_dept,
                         r.event_type, r.entity_type, coalesce(r.entity_id,'-'), r.occurred_at);
    else
      v_title  := left(r.event_type || ' on ' || r.entity_type || ' ' || coalesce(r.entity_id,''), 200);
      v_detail := format('Event %s (%s %s) raised by %s at %s. You subscribe to this because: %s. '
                      || 'Assessed impact: %s. Act on it or close it with a reason.',
                         r.event_type, r.entity_type, coalesce(r.entity_id,'-'),
                         coalesce(r.actor,'system'), r.occurred_at,
                         coalesce(r.reason,'subscription'), coalesce(v_impact,'not assessed'));
    end if;

    -- `status not in ('done','closed','cancelled')` rather than the old
    -- `in ('proposed','assigned','in_progress')`: the two lists disagreed about 'escalated', so an
    -- escalated task was open for the count above and closed for this lookup — which would mint a
    -- SECOND standing back-pressure task the moment the first one escalated, and had already been
    -- duplicating escalated subject tasks. One definition of open, used by both.
    select t.id into v_open_task
      from org_tasks t
     where t.decided_by = 'fn_event_dispatch'
       and t.dept_key = v_dept
       and t.title = v_title
       and t.status not in ('done','closed','cancelled')
     order by t.id
     limit 1;
    if v_open_task is not null then
      insert into event_delivery (event_id, agent_key, event_type, os_key, task_id, delivered_at)
      values (r.event_id, r.agent_key, r.event_type, v_os, v_open_task, clock_timestamp())
      on conflict do nothing;
      v_attached  := v_attached + 1;
      if v_capped then v_backpressured := v_backpressured + 1; end if;
      v_delivered := v_delivered + 1;
      continue;
    end if;

    -- ALREADY ANSWERED, INSIDE THE COOL-DOWN. The lookup above found nothing OPEN, which for a
    -- recurring condition means the last one was closed, not that the question is new. Attach
    -- to the task that already carries the answer rather than buying another one.
    if v_cooldown_days > 0 then
      select t.id into v_recur_task
        from org_tasks t
       -- Provenance is the delivery, not decided_by: the executor overwrites decided_by when
       -- it settles the row, so no closed task has ever carried 'fn_event_dispatch'.
       where exists (select 1 from event_delivery ed where ed.task_id = t.id)
         and t.dept_key = v_dept
         and t.title = v_title
         and t.status in ('done','closed','cancelled')
         and coalesce(t.updated_at, t.created_at) > clock_timestamp() - make_interval(days => v_cooldown_days)
       order by coalesce(t.updated_at, t.created_at) desc
       limit 1;
      if v_recur_task is not null then
        insert into event_delivery (event_id, agent_key, event_type, os_key, task_id, delivered_at)
        values (r.event_id, r.agent_key, r.event_type, v_os, v_recur_task, clock_timestamp())
        on conflict do nothing;
        v_suppressed := v_suppressed + 1;
        v_delivered  := v_delivered + 1;
        continue;
      end if;
    end if;

    insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class,
                           decided_by, created_at)
    values (v_dept,
            v_title,
            v_detail,
            case when v_tier = 'autonomous' then 'assigned' else 'proposed' end,
            v_tier,
            -- 4 SEP 2026: needs_founder was `v_tier <> 'autonomous'`, which reads "the department is
            -- not autonomous for this class" as "the founder must decide this". The company's rule is
            -- the opposite, and fn_kernel_founder_routing_is_refund_only enforces it: ONLY an action
            -- class marked founder_approval_required reaches him, which today is the refund class
            -- alone. A merely gated task goes up the INTERNAL chain -- it is written 'proposed' above
            -- and fn_task_approve resolves the entitled head. MASTER_PLAN 4.5.
            --
            -- It became visible only when the STAFF_ORG seating gave Supply its own head: supply
            -- grants 'analysis' at 'gated', so every event routed to a Supply subscriber tried to page
            -- the founder and the guard refused it with 23514. Fourteen failed kernel traces for
            -- cron:event_dispatch_15min between 05:45 and 09:00 UTC on 4 Sep; the wrapper swallows the
            -- failure so cron.job_run_details still said 'succeeded', and the red-view alerter built
            -- that morning is what surfaced it. needs_founder now reads the same table the guard reads,
            -- so the writer and the guard cannot disagree again.
            exists (select 1 from public.phase_c_action_class c
                     where c.action_class = 'analysis' and c.founder_approval_required),
            'analysis', 'fn_event_dispatch', clock_timestamp())
    returning id into v_task;
    v_tasks := v_tasks + 1;
    -- The standing task counts as back-pressured too: it is the one task the cap allows, not a
    -- per-event task that slipped through. Counted so `backpressured` in the return value is the
    -- full number of events the cap handled, and never silently one short.
    if v_capped then v_backpressured := v_backpressured + 1; end if;

    insert into event_delivery (event_id, agent_key, event_type, os_key, task_id, delivered_at)
    values (r.event_id, r.agent_key, r.event_type, v_os, v_task, clock_timestamp())
    on conflict do nothing;
    v_delivered := v_delivered + 1;
    exception when others then
      v_failed := v_failed + 1;
      if v_first_err is null then
        v_first_err := format('%s %s (event %s -> %s)', sqlstate, left(sqlerrm, 300), r.event_id, r.agent_key);
      end if;
    end;
  end loop;

  -- Leave no correlation bound to the session after the loop: a later statement on this
  -- connection is NOT part of the last event's chain, and inheriting it would be a false link.
  perform set_config('app.correlation_id', '', true);
  perform set_config('app.causation_event_id', '', true);

  -- 5 SEP 2026: a failed pair is a real failure and is said once per call, on the ledger the
  -- failed-runs watcher reads. It is not re-raised: re-raising is exactly the head-of-line block.
  if v_failed > 0 then
    insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
    values ('event_dispatch', clock_timestamp(), clock_timestamp(), 'error',
            jsonb_build_object('pairs_failed', v_failed, 'delivered', v_delivered, 'lookback_minutes', p_lookback_minutes),
            left(format('%s (event, subscriber) pair(s) failed and were left undelivered for the next pass; '
                     || 'the other %s pair(s) in the batch were delivered. First failure: %s', v_failed, v_delivered, v_first_err), 1000));
  end if;

  return jsonb_build_object('delivered', v_delivered, 'tasks_created', v_tasks,
                            'attached_to_existing_task', v_attached,
                            'backpressured', v_backpressured,
                            'suppressed_recurring', v_suppressed,
                            'recur_cooldown_days', v_cooldown_days,
                            'tasks_awaiting_a_human', v_gated,
                            'unroutable', v_unroutable, 'assessed', v_assessed,
                            'lookback_minutes', p_lookback_minutes,
                            'max_batch', c_max_batch,
                            'pairs_failed', v_failed,
                            'max_open_per_dept', c_max_open_per_dept);
end; $function$
