-- scripts/sql/the_live_routines_stop_naming_the_phase_machinery.sql
-- agent: ceo
-- WRITTEN 9 September 2026. NOT APPLIED by the session that wrote it.
--
-- THE RULING (founder, 8 September 2026, on the Phase A-D programme and its kernel):
--   "remove them totally. i dont want to see their names popping anymore."
-- He has explicitly accepted that the website may break in the meantime and will be rebuilt
-- correctly later with the right agents. So this file does NOT try to preserve phase behaviour. It
-- removes the phase and kernel calls from the routines that must SURVIVE the removal, leaving the
-- rest of each routine's work intact, so that when the drop file runs nothing live is left naming
-- an object that no longer exists.
--
-- APPLY ORDER: this file runs BEFORE scripts/sql/the_phase_programme_and_its_kernel_are_removed.sql
-- and is listed immediately before it in scripts/sql/MANIFEST.txt. Applied the other way round, the
-- drop would either fail on dependencies or leave fourteen routines raising 42P01 at runtime.
--
-- ---------------------------------------------------------------------------------------------
-- WHAT WAS MEASURED, 9 September 2026, against production (read-only)
-- ---------------------------------------------------------------------------------------------
-- The list of affected routines was re-derived here rather than taken on trust:
--
--   select p.proname from pg_proc p
--    where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p')
--      and p.prosrc ~ '(phase_[abcd]_|fn_kernel_)'
--      and p.proname !~ '^(fn_kernel_|fn_phase_|phase_)';
--
-- 16 rows. Two of them (fn_workflow_step_claim, fn_workflow_step_sweep) match ONLY because they
-- call fn_kernel_paid_provider_gate, which is KEPT (see below), so they are not rewritten. The
-- other 14 are rewritten in this file. Two routines named in the brief that prompted this work --
-- fn_notifications_founder_mail_policy and fn_founder_mail_route -- were checked and do NOT name
-- the machinery at all; they are untouched. One routine the brief did not name --
-- qd_notify_refund_request -- does, and is included.
--
-- Also measured, because the rewrite of fn_event_dispatch depends on it:
--   select action_class, founder_approval_required from public.phase_c_action_class;
--   -> 26 rows. 'analysis' is NOT among them; only 'refund_decision' requires founder approval.
--   Therefore the exists() that routine used to evaluate was a constant FALSE, and replacing it
--   with the literal false changes nothing about what the routine writes.
--
-- ---------------------------------------------------------------------------------------------
-- WHAT IS DELIBERATELY NOT TOUCHED
-- ---------------------------------------------------------------------------------------------
-- * public.fn_kernel_paid_provider_gate is KEPT AS A ROUTINE, name and all. Its body was read on
--   9 Sep 2026: it reads app_secrets ('no_paid_ai'), llm_route_health and model_registry, and no
--   phase table whatsoever. supabase/functions/_shared/paid_gate.ts calls it, so dropping it would
--   turn the paid-provider hold -- the founder's one standing limit -- into an unguarded path. It
--   keeps its 'kernel' name only because renaming it is a separate, riskier change than this one.
-- * fn_workflow_step_claim and fn_workflow_step_sweep call that gate and nothing else from the
--   machinery. Not rewritten.
-- * fn_phase1_disarmed / phase1_rollback_log (Control Mode's phase 1) are a different thing from
--   the Phase A-D programme and are out of scope. Untouched.
-- * The drops themselves are not here. This file only stops the naming.
--
-- ---------------------------------------------------------------------------------------------
-- THE FOURTEEN ROUTINES REWRITTEN HERE, and what came out of each
-- ---------------------------------------------------------------------------------------------
--   fn_event_dispatch             the phase_c_action_class exists() -> the literal false (proved
--                                 equivalent above); the comment naming the kernel routing guard
--                                 reworded.
--   fn_page_high_agent_action     the fn_kernel_source_emit that opened a W29 run. The founder page
--                                 (the notifications row) stays.
--   trg_reveal_receipt            the fn_kernel_source_emit that opened a W16 run. Both receipts
--                                 stay.
--   qd_notify_refund_request      the guarded fn_kernel_source_emit that opened a W17 run. The
--                                 fn_notify_founder call stays.
--   qd_on_refund_resolved         the fn_kernel_source_emit + fn_kernel_run_for that attached the
--                                 resolution to an open W17 run. The supplier due, the matching
--                                 block and the customer refund email stay.
--   fn_agent_silence_watch        the phase_c_system_execution_wrapper activation floor, rebuilt on
--                                 cron_job_seen.first_seen. LOSS DISCLOSED IN THE ROUTINE: a job
--                                 disabled and re-enabled long after first registration can page
--                                 once before its next success.
--   fn_refund_decide              the phase_c_founder_identity register. NOT removed to nothing --
--                                 it now refuses a decided_by of the form 'policy:...', because
--                                 removing the test outright would restore the auto-approval of
--                                 customer refunds that the register was introduced to stop.
--   fn_refund_founder_decision_only  same register, same reasoning: the trigger REFUSES an approval
--                                 with no decider or a policy-string decider.
--   fn_refund_amount_is_the_fee_paid  comment only; it named a deleted guard. No behaviour change.
--   fn_control_mode_require       comment and audit-reason text only; the founder_gated branch
--                                 never read a phase table. No behaviour change.
--   fn_ws_exec_home               the 'handoffs_24h' key, which counted phase_c_handoff_run. The
--                                 key is dropped, not zeroed: an absent number and a measured zero
--                                 are different statements.
--   fn_customer_terms_accept      the phase_d acceptance-document lookup, the phase_d object read
--                                 and write, and the phase_c W04-S01 re-dispatch. What the product
--                                 needs -- version + digest from legal_documents, written onto
--                                 public.customers -- stays, and the return keys are kept as nulls
--                                 so callers do not break on a second, separate day.
--   fn_company_self_knowledge_sync  the founder address moves from phase_c_founder_identity to
--                                 app_secrets.founder_email (it was display text, never an
--                                 authority check); the phase_b_workflow funnel listing is dropped
--                                 from the marketplace knowledge record.
--   fn_company_org_directory_sync  section 5, "The 30 Workflows We Run", built from
--                                 phase_b_workflow. The section goes and the already-published
--                                 ops_knowledge row is deleted in the same transaction.
--
-- Every rewrite uses CREATE OR REPLACE with the signature byte-for-byte unchanged, so triggers,
-- grants and dependent views survive. No CASCADE anywhere in this file.
--
-- ---------------------------------------------------------------------------------------------
-- HONEST NOTE ON THE COMMENTS INSIDE THE ROUTINES
-- ---------------------------------------------------------------------------------------------
-- The founder asked not to see these names again. The closing check in this file matches routine
-- BODIES, comments included, so the new comments describe what was removed in prose ("the
-- programme's action-class table", "the kernel source table") instead of quoting the identifiers.
-- The identifiers are spelled out here, in this file's header, because a file whose whole job is
-- to record a removal has to say what it removed.

begin;

-- ---------------------------------------------------------------------------------------------
-- fn_event_dispatch -- the bus no longer asks phase_c_action_class who needs the founder
-- ---------------------------------------------------------------------------------------------

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
           e.correlation_id, e.payload, s.agent_key, s.reason,
           -- 6 SEP 2026: the subscription may name the executor class its task carries (see the
           -- header of scripts/sql/the_onboarding_specialist_checks_every_registration.sql).
           s.action_class as sub_action_class
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
            -- 9 SEP 2026 -- THE PROGRAMME AND ITS KERNEL ARE REMOVED, founder ruling of 8 Sep
            -- 2026: "remove them totally. i dont want to see their names popping anymore."
            --
            -- This argument used to be an exists() against the programme's action-class table,
            -- asking whether the 'analysis' class required founder approval. It read that table
            -- because the kernel's refund-only routing guard enforced the SAME table one level up,
            -- so the writer and the guard could not disagree and mint a task the guard then
            -- refused with 23514. Both the table and that guard are dropped in this same sweep.
            --
            -- MEASURED 9 Sep 2026, BEFORE REMOVAL: 'analysis' was not a row in that table at all
            -- (26 rows; only 'refund_decision' required founder approval). The exists() was
            -- therefore a constant FALSE, and every bus task this routine has ever minted was
            -- already written needs_founder = false. The literal below is that same answer with
            -- the dependency gone -- it is not a policy change. A gated task still goes up the
            -- INTERNAL chain: it is written 'proposed' above and fn_task_approve resolves the
            -- entitled head. Nothing on this path pages the founder.
            false,
            -- 6 SEP 2026: 'analysis' unless the subscription names a class. The tier above and the
            -- needs_founder test stay on 'analysis' -- the department's authority to work bus tasks
            -- is unchanged; only the executor the org_task lane looks up by this class differs.
            coalesce(r.sub_action_class, 'analysis'), 'fn_event_dispatch', clock_timestamp())
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
end; $function$;


-- ---------------------------------------------------------------------------------------------
-- fn_page_high_agent_action -- the W29 kernel emit goes; the founder page stays
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_page_high_agent_action()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_founder text; v_kind text;
BEGIN
  IF lower(coalesce(NEW.risk,'')) IN ('high','critical')
     -- K21. Was: NEW.agent IN ('finance_ai','security_ai','operations_ai'). That set could never
     -- match a security action. a00_agent_action_resolve_addressee runs BEFORE this trigger and
     -- resolves the addressee through org_agents, so a row written as 'security_ai' arrives here
     -- as 'security'. Measured: inserting agent='security_ai' reads back as 'security', and
     -- notifications has 0 rows of type 'agent_escalation' in its entire history — the founder has
     -- never been paged by this trigger. A prefix match survives the resolver in both directions
     -- and does not need a keep-list that has to be remembered every time an agent is renamed.
     AND NEW.agent ~ '^(finance|security|operations)'
     AND lower(coalesce(NEW.status,'pending')) = 'pending' THEN
  -- 9 SEP 2026 -- PHASE MACHINERY REMOVED. An emit into the kernel source table stood here that
  -- declared this action the start of a W29 kernel run. The kernel, its source table and its
  -- W-numbered programme are all deleted in this sweep and nothing else consumed that event, so
  -- the emit is gone rather than re-pointed. Everything below it -- the founder_email lookup, the
  -- founder_mail_policy kind, the 24-hour dedupe and the notifications row -- is unchanged, and is
  -- now the whole of what this trigger does.
    v_founder := coalesce(
      (SELECT value FROM app_secrets WHERE key='founder_email'),
      nullif(split_part((SELECT value FROM app_secrets WHERE key='admin_emails'), ',', 1), ''),
      'management@quotesdone.com');
    -- 6 SEP 2026: the founder_mail_policy key is the action's own kind; a CRITICAL security action is
    -- the one security kind that may reach him (founder_mail_policy.security_critical).
    v_kind := CASE WHEN lower(coalesce(NEW.risk,'')) = 'critical' AND NEW.agent ~ '^security' THEN 'security_critical'
                   ELSE coalesce(nullif(NEW.kind,''), 'agent_escalation') END;
    IF NOT EXISTS (
      SELECT 1 FROM notifications
      WHERE type='agent_escalation' AND body LIKE '%action #'||NEW.id||'%'
        AND created_at > now() - interval '24 hours'
    ) THEN
      INSERT INTO notifications(type, kind, to_email, to_role, channel, status, subject, body)
      VALUES('agent_escalation', v_kind, v_founder, 'admin', 'email', 'queued',
        '['||upper(NEW.risk)||'] '||coalesce(NEW.title, NEW.kind, 'Agent escalation'),
        coalesce(NEW.recommendation, NEW.title, '')||E'\n\nAgent: '||coalesce(NEW.agent,'?')||' · action #'||NEW.id||' · open the OS to decide.');
    END IF;
  END IF;
  RETURN NEW;
END
$function$;


-- ---------------------------------------------------------------------------------------------
-- trg_reveal_receipt -- the W16 kernel emit goes; both receipts stay
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.trg_reveal_receipt()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  cemail  text;
  semail  text;
  comp    text;
  inq     record;
  v_window int; v_chase int;
begin
  if NEW.revealed_at is not null and (TG_OP = 'INSERT' or OLD.revealed_at is null) then
    -- 9 SEP 2026 -- PHASE MACHINERY REMOVED. An emit into the kernel source table stood here that
    -- declared the reveal payment the start of a W16 kernel run. The kernel is deleted; nothing
    -- consumed the event. The two receipts below (customer, supplier) and the WhatsApp fan-out
    -- they feed are the real work of this trigger and are untouched.

    select email into cemail from public.customers where id = NEW.customer_id;
    select company_name, email into comp, semail from public.leads where id = NEW.supplier_id;
    select summary, category into inq from public.inquiries where id = NEW.inquiry_id;
    -- 6 Sep 2026: both receipts state the ladder from pricing_config (window 5, chase 3), one source.
    select refund_window_working_days, chase_after_working_days into v_window, v_chase
      from public.pricing_config order by id limit 1;
    v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3);

    -- 1. customer email
    if cemail is not null then
      insert into public.notifications (type, to_email, to_role, inquiry_id, quote_id, subject, body, status)
      values ('reveal_receipt', cemail, 'customer', NEW.inquiry_id, NEW.quote_id,
              'Reveal confirmed — ' || coalesce(comp, 'supplier'),
              'You have unlocked ' || coalesce(comp, 'the supplier') || '''s contact details'
                || coalesce(' for: ' || left(inq.summary, 80), '')
                || '. You can now message them directly in the app. We track this reveal from the moment you paid: if the supplier has not responded within '
                || v_chase::text || ' working days we chase them for you and copy you; if there is still no response by working day '
                || v_window::text || ' the case goes to our founder for a final call, and if the supplier does not respond to it your reveal fee is refunded in full. '
                || 'Banks usually take 7-14 working days to show a refund. You can also open the request and Report an issue at any time.',
              'queued');
    end if;

    -- 2. supplier email (moved here from stripe_webhook)
    if semail is not null and semail like '%@%' then
      insert into public.notifications (type, to_email, to_role, lead_id, inquiry_id, quote_id, subject, body, status)
      values ('quote_accepted', semail, 'supplier', NEW.supplier_id, NEW.inquiry_id, NEW.quote_id,
              'A customer revealed your quote on QuotesDone',
              'A customer paid to reveal your contact for: ' || coalesce(inq.summary, '')
                || '. Please respond promptly — under the Supplier Agreement you must respond within ' || v_window::text
                || ' working days of the reveal. If you have not responded after ' || v_chase::text
                || ' working days we chase you with the customer copied; if there is still no response on working day ' || v_window::text
                || ' our founder makes a final call, the customer is refunded, and the reveal fee plus an AED 250 administrative fee and 9% p.a. interest is recovered from your account.',
              'queued');
    end if;

    -- 3 and 4: the WhatsApp to each opted-in party is queued by trg_wa_fanout from the two email rows above.
  end if;
  return NEW;
end
$function$;


-- ---------------------------------------------------------------------------------------------
-- qd_on_refund_resolved -- the W17 kernel emit goes; the due, the block and the refund email stay
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.qd_on_refund_resolved()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_fee numeric; v_admin numeric; v_cust record; v_min int; v_max int; v_window int; v_amount numeric; v_amounts jsonb;
begin
  if NEW.refund_status in ('refunded','approved') and (OLD.refund_status is distinct from NEW.refund_status) then
    v_fee   := coalesce(NEW.reveal_fee, NEW.app_fee, 0);
    v_admin := coalesce((select num_value from public.gl_settings where key='clawback_admin_fee_aed'), 250);
    -- 6 Sep 2026: the one arithmetic. The supplier's charge at issue = the refunded fee + the AED 250
    -- administrative fee (unchanged, from gl_settings as before) + 9% p.a. simple interest pro-rated
    -- by calendar days from the customer's payment to this issue (founder ruling, verbatim in
    -- decision_policy.refund_policy_founder_decision_2026_09_06). collections_legal keeps accruing on
    -- the overdue balance from the due date exactly as before.
    v_amounts := public.fn_refund_amount_aed(v_fee, NEW.revealed_at, now());
  -- 9 SEP 2026 -- PHASE MACHINERY REMOVED. An emit into the kernel source table stood here, carrying
  -- a run id resolved by the kernel run-lookup routine so the resolution attached to the transaction's
  -- existing W17 run instead of opening a second one. Both routines are deleted in this sweep. The
  -- supplier_dues row, the matching block on the supplier and the customer's refund_issued email
  -- below are the money-and-customer effects of this trigger and are unchanged.


    if not exists (select 1 from public.supplier_dues where transaction_id=NEW.id and coalesce(status,'')<>'cancelled') then
      insert into public.supplier_dues(
        transaction_id, supplier_id, quote_id, quote_amount, commission_pct,
        amount_due, admin_fee, interest_amount, currency,
        reveal_date, due_date, due_date_30, status, created_at)
      values(
        NEW.id, NEW.supplier_id, NEW.quote_id, NEW.quote_amount, 3,
        v_fee,          -- the 3% reveal fee QuotesDone already refunded to the customer
        v_admin,        -- flat administration fee, charged immediately per the supplier terms
        coalesce((v_amounts->>'interest_aed')::numeric, 0),  -- 9% p.a. from the customer's payment to this issue (fn_refund_amount_aed)
        'AED',
        NEW.revealed_at, (now()+interval '7 days'), (now()+interval '30 days'), 'due', now());
    end if;

    update public.leads
      set matching_blocked = true,
          matching_block_reason = 'Unsettled non-response charge (customer refunded due to no response)',
          rv_nonresponse_refunds = coalesce(rv_nonresponse_refunds,0)+1
    where id = NEW.supplier_id;

    if NEW.refund_resolved_at is null then NEW.refund_resolved_at := now(); end if;

    -- 6 Sep 2026: once the money has actually moved ('refunded' is written by refunds_api after
    -- Stripe returned it), the customer is told, and told what the bank takes.
    if NEW.refund_status = 'refunded' then
      select email, full_name into v_cust from public.customers where id = NEW.customer_id;
      select bank_settlement_working_days_min, bank_settlement_working_days_max, refund_window_working_days
        into v_min, v_max, v_window from public.pricing_config order by id limit 1;
      v_amount := round(coalesce(NEW.refund_amount_aed, v_fee), 2);
      if v_cust.email is not null and not exists (
           select 1 from public.notifications n where n.type = 'refund_issued' and n.inquiry_id = NEW.inquiry_id
              and n.to_email = v_cust.email and n.lead_id = NEW.supplier_id) then
        insert into public.notifications(type, kind, to_email, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status)
        values ('refund_issued', 'refund_issued', v_cust.email, 'customer', NEW.supplier_id, NEW.inquiry_id, NEW.quote_id, 'email',
          'Your QuotesDone reveal fee refund of AED ' || v_amount::text || ' has been issued',
          'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || ',' || chr(10) || chr(10) ||
          'We have issued a refund of AED ' || v_amount::text || ' — the full reveal fee you paid on ' ||
            coalesce(to_char(NEW.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY'), 'the reveal date') ||
            ' — to your original payment method, because the supplier did not respond within ' ||
            coalesce(v_window, 5)::text || ' working days. No administrative charge is deducted from your refund.' || chr(10) || chr(10) ||
          'Banks and card issuers usually take ' || coalesce(v_min, 7)::text || '–' || coalesce(v_max, 14)::text ||
            ' working days to show it on your statement. If it has not appeared after ' || coalesce(v_max, 14)::text ||
            ' working days, reply to this email and we will trace it with the payment processor.' || chr(10) || chr(10) ||
          'You are welcome to post the request again; we will introduce you to another supplier.' || chr(10) || chr(10) ||
          'QuotesDone', 'queued');
      end if;
    end if;
  end if;
  return NEW;
end;
$function$;


-- ---------------------------------------------------------------------------------------------
-- qd_notify_refund_request -- the conditional W17 emit goes; the notification stays
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.qd_notify_refund_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_company text; v_window int; v_chase int;
begin
  select company_name into v_company from leads where id = NEW.supplier_id;
  select refund_window_working_days, chase_after_working_days into v_window, v_chase
    from pricing_config order by id limit 1;
  -- 6 Sep 2026: the complaint is the Customer Success Director's to work (founder_mail_policy
  -- refund_complaint, allowed_to_email = false). The founder hears about a refund exactly twice: the
  -- day-5 final call (refund_final_call) and the approval itself.
  perform public.fn_notify_founder(
    p_event => 'Refund requested — supplier not responding: ' || coalesce(v_company, '(id ' || NEW.supplier_id::text || ')'),
    p_detail => 'A customer has asked for the reveal fee back because a revealed supplier is not responding.' || chr(10) ||
    'Supplier: ' || coalesce(v_company, '(id ' || NEW.supplier_id::text || ')') || chr(10) ||
    'Inquiry: ' || coalesce(NEW.inquiry_id::text, '') || ' · Transaction: ' || NEW.id::text ||
      ' · Reveal fee: AED ' || coalesce(NEW.reveal_fee::text, '0') || ' · paid ' ||
      coalesce(to_char(NEW.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY'), '?') || chr(10) || chr(10) ||
    'Ladder: the supplier has ' || coalesce(v_window, 5)::text || ' working days from payment. The sweep chases at day ' ||
      coalesce(v_chase, 3)::text || ' and files the refund for the founder''s final call at day ' || coalesce(v_window, 5)::text ||
      '. Reach the supplier now; if they respond, record it (supplier_ack_at or a portal message) so the case closes. ' ||
      'Read fn_refund_state(''' || NEW.id::text || ''') for where it stands.',
    p_level => 'high', p_kind => 'refund_complaint', p_dedupe_key => 'refund_complaint:' || NEW.id::text, p_owner_agent => null);
  -- 9 SEP 2026 -- PHASE MACHINERY REMOVED. A guarded emit into the kernel source table stood here that
  -- opened a W17 kernel run once the refunds row existed. The kernel is deleted; nothing consumed
  -- it. The fn_notify_founder call above -- the notification a person actually reads, routed
  -- through founder_mail_policy as refund_complaint -- is unchanged.
  return NEW;
end $function$;


-- ---------------------------------------------------------------------------------------------
-- fn_agent_silence_watch -- the re-activation floor stops reading phase_c_system_execution_wrapper
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_agent_silence_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n int:=0; f int:=0; g int:=0; nr int:=0; v_email text; v_run bigint;
begin
  insert into agent_runs(agent, started_at) values ('agent_silence_watch', clock_timestamp()) returning id into v_run;

  select to_email into v_email from notifications
   where type='founder_brief' and to_email is not null order by created_at desc limit 1;

  insert into cron_job_seen (jobid, jobname, schedule)
  select j.jobid, j.jobname, j.schedule from cron.job j where j.active
  on conflict (jobid) do update set last_seen = now(), jobname = excluded.jobname, schedule = excluded.schedule;

  -- Record successes BEFORE evaluating, so they survive the 14-day history prune.
  update cron_job_seen s
     set last_success = h.last_ok
    from (select jobid, max(start_time) as last_ok
            from cron.job_run_details where status='succeeded' group by jobid) h
   where h.jobid = s.jobid
     and (s.last_success is null or s.last_success < h.last_ok);

  for r in
    -- ONE AGGREGATE, NOT THREE CORRELATED SUBQUERIES PER JOB. This loop used to ask
    -- cron.job_run_details three separate questions for each of 165 active jobs against an 80 MB
    -- heap with no usable index, and on 11 Aug 2026 it began exceeding the statement timeout and
    -- stopped watching anything at all. A watchdog that dies silently is worse than no watchdog:
    -- fn_agent_silence_watch is the routine that would have reported its own absence.
    with h as (
      select jobid,
             count(*)                                                        as history_rows,
             max(start_time) filter (where status='succeeded')               as last_ok_live,
             count(*) filter (where status='failed'
                              and start_time > now() - interval '24 hours')  as fails_24h
        from cron.job_run_details
       group by jobid)
    select j.jobid, j.jobname,
           case when split_part(j.schedule,' ',5) <> '*' then 336
                when split_part(j.schedule,' ',3) <> '*' then 1440
                when split_part(j.schedule,' ',2) =  '*' then 6
                else 72 end as thresh_h,
           coalesce(h.history_rows, 0) as history_rows,
           greatest(h.last_ok_live, s.last_success) as last_ok,
           coalesce(h.fails_24h, 0) as fails_24h,
           s.first_seen,
           s.last_success as stored_ok
      from cron.job j
      left join h on h.jobid = j.jobid
      left join cron_job_seen s on s.jobid = j.jobid
     where j.active
  loop
    -- 9 SEP 2026 -- PHASE MACHINERY REMOVED, and this one loses a little accuracy, said plainly.
    -- The guard here read the kernel cron wrapper table (its wrapped_at column) as an ACTIVATION
    -- FLOOR: a job put back on today, whose last success predates the 16 Aug stand-down, is not
    -- silent. Without a floor this watch paged the founder about 15 such jobs in one day (3 Sep
    -- 2026). That table is deleted in this sweep and nothing else in the database records when a
    -- cron job was re-enabled, so the floor is rebuilt from the one durable fact this routine
    -- already keeps for itself: cron_job_seen.first_seen, the moment this watch first saw the job.
    -- It is the same floor the never-run branch below already applies.
    --
    -- WHAT THIS NO LONGER COVERS, so nobody is surprised in a year: a job registered long ago,
    -- disabled, then re-enabled today keeps its OLD first_seen, so it can page once as silent
    -- before its next success. Pages are deduped per silence episode (job, last_success), so that
    -- is one alert per such job, not a daily repeat. If it ever becomes noisy the fix is a
    -- re-activation column on cron_job_seen -- not a resurrected phase table.
    if r.first_seen is not null and r.first_seen > now() - (r.thresh_h||' hours')::interval then
      g := g + 1;
      continue;
    end if;
    -- Never-run: only when there is NO history AND we have never recorded a success.
    if r.history_rows = 0 and r.stored_ok is null then
      if r.first_seen is not null and r.first_seen < now() - (r.thresh_h||' hours')::interval then
        if not exists (select 1 from founder_alerts where event='cron_never_ran'
                        and detail like '%"'||r.jobname||'"%'
                        and created_at > now() - interval '24 hours') then
          insert into founder_alerts(level,event,detail,channel)
          values ('high','cron_never_ran', jsonb_build_object(
            'job', r.jobname,
            'first_seen', r.first_seen::text,
            'known_for_hours', round(extract(epoch from (now()-r.first_seen))/3600),
            'expected_within_hours', r.thresh_h)::text, 'email');
          -- 6 SEP 2026: routed to the IT operations engineer as one org_task per job, never emailed
          -- (founder_mail_policy.agent_silence); this watcher's own founder_alerts row above is its ledger.
          perform public.fn_founder_mail_route('agent_silence', 'Scheduled job has never run: '||r.jobname,
              'Job "'||r.jobname||'" is active but has no run history at all. It has been registered since '||
              r.first_seen::text||' and should have run at least every '||r.thresh_h||' hours. It is likely misregistered.', 'high');
          nr := nr + 1;
        end if;
      else
        g := g + 1;
      end if;
      continue;
    end if;

    if r.last_ok is null or r.last_ok < now() - (r.thresh_h||' hours')::interval then
      -- ONCE PER SILENCE EPISODE (3 Sep 2026): the episode is (job, last_success). It is paged the
      -- first time it is seen and never again until the job succeeds again — the 24-hour dedupe
      -- this replaced re-paged every silent job every day.
      if not exists (select 1 from founder_alerts where event='cron_silent'
                      and detail like '%"job": "'||r.jobname||'"%'
                      and detail like '%"last_success": "'||coalesce(r.last_ok::text,'no success on record')||'"%') then
        insert into founder_alerts(level,event,detail,channel)
        values ('high','cron_silent', jsonb_build_object(
          'job',r.jobname,'last_success',coalesce(r.last_ok::text,'no success on record'),
          'silent_hours',round(extract(epoch from (now()-r.last_ok))/3600),
          'expected_within_hours',r.thresh_h)::text,'email');
        perform public.fn_founder_mail_route('agent_silence', 'Scheduled job stopped: '||r.jobname,
            'Job "'||r.jobname||'" last succeeded '||coalesce(r.last_ok::text,'unknown')||
            '. Expected at least every '||r.thresh_h||' hours.', 'high');
        n := n + 1;
      end if;
    end if;

    if r.fails_24h > 0 then
      if not exists (select 1 from founder_alerts where event='cron_failing'
                      and detail like '%"'||r.jobname||'"%'
                      and created_at > now() - interval '24 hours') then
        insert into founder_alerts(level,event,detail,channel)
        values ('high','cron_failing',
          jsonb_build_object('job',r.jobname,'failures_24h',r.fails_24h,
                             'last_success',coalesce(r.last_ok::text,'unknown'))::text,'email');
        perform public.fn_founder_mail_route('agent_silence', 'Scheduled job failing: '||r.jobname,
            'Job "'||r.jobname||'" has failed '||r.fails_24h||' time(s) in the last 24 hours. Last success: '||
            coalesce(r.last_ok::text,'unknown')||'. Check cron.job_run_details for the error text.', 'high');
        f := f + 1;
      end if;
    end if;
  end loop;

  update agent_runs
     set finished_at=clock_timestamp(), status='ok',
         counts=jsonb_build_object('active_jobs',(select count(*) from cron.job where active),
                                   'in_grace',g,'silent',n,'failing',f,'never_ran',nr)
   where id=v_run;

  return jsonb_build_object('ran_at',now(),
    'active_jobs',(select count(*) from cron.job where active),
    'in_grace',g,'silent_alerts',n,'failing_alerts',f,'never_ran_alerts',nr);
exception when others then
  update agent_runs set finished_at=clock_timestamp(), status='error', note=left(sqlerrm,500) where id=v_run;
  raise;
end $function$;


-- ---------------------------------------------------------------------------------------------
-- fn_refund_decide -- the founder-identity register goes; an automatic decider is still refused
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_refund_decide(p_refund_id bigint, p_approve boolean, p_decided_by text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.refunds; v_new text;
begin
  select * into r from public.refunds where id = p_refund_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status <> 'requested' then
    return jsonb_build_object('ok', false, 'error', 'not_decidable', 'status', r.status);
  end if;
  if coalesce(btrim(p_decided_by),'') = '' then
    return jsonb_build_object('ok', false, 'error', 'decider_required');
  end if;

  -- 9 SEP 2026 -- PHASE MACHINERY REMOVED, and this one is deliberately NOT removed to nothing.
  --
  -- WHAT STOOD HERE: a lookup in the founder-identity register that refused any decider who was
  -- not an active row in that register. The founder has retired the whole concept -- he approves
  -- nothing now, every approval is the CEO's -- and the register is deleted in this sweep.
  --
  -- WHY IT IS NOT SIMPLY DELETED: without any test, decided_by falls back to "a non-empty string",
  -- which is exactly the state that let fn_refund_request auto-approve every refund inside the
  -- promised window under org_authority(customer_success, refund_within_window), writing
  -- decided_by = 'policy:auto_window' and moving customer money with nobody deciding. Removing the
  -- check outright would re-open that, so this REFUSES instead: a refund may be decided by a named
  -- actor, never by a policy string. It no longer asks WHICH actor, because there is no longer a
  -- register that could answer, and naming the CEO here would just rebuild the same thing under a
  -- new name. Re-point it at whatever the CEO seat uses for identity when that seat has a runtime.
  if lower(btrim(p_decided_by)) like 'policy:%' then
    return jsonb_build_object('ok', false, 'error', 'automatic_decider_refused',
      'hint', 'A refund is decided by an actor, not by a rule. decided_by = ' || btrim(p_decided_by)
           || ' is an automatic window policy, which is how refunds were auto-approved before '
           || '17 Aug 2026. Approvals belong to the CEO; pass the deciding actor.');
  end if;

  v_new := case when p_approve then 'approved' else 'rejected' end;
  update public.refunds set status = v_new, decided_by = p_decided_by, decided_at = now(), decision_note = p_note
   where id = p_refund_id;
  if r.transaction_id is not null then
    update public.transactions set refund_status = v_new, refund_resolved_at = now(),
           refund_note = coalesce(p_note, refund_note) where id = r.transaction_id;
  end if;
  return jsonb_build_object('ok', true, 'refund_id', p_refund_id, 'status', v_new, 'decided_by', p_decided_by);
end
$function$;


-- ---------------------------------------------------------------------------------------------
-- fn_refund_amount_is_the_fee_paid -- a comment stops naming a deleted routine
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_refund_amount_is_the_fee_paid()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t public.transactions%rowtype;
  v_expected bigint;
  -- 9 SEP 2026: this list used to be described as "the same three originators
  -- the refund-execution guard named, read the same way". That routine is
  -- deleted with the phase programme; the list is now defined here and nowhere else, and its
  -- contents are unchanged. No behaviour changed in this routine, only the comment.
  -- A refund Stripe already issued is a fact to be recorded, not a request to be approved.
  v_external constant text[] := array['stripe_webhook','stripe_dashboard','stripe'];
begin
  if lower(coalesce(NEW.requested_by,'')) = any(v_external) then
    return NEW;
  end if;

  if NEW.transaction_id is null then
    raise exception 'refunds: a refund must name the transaction it reverses. transaction_id is null, so this row asserts money is owed without saying which payment it came from. (refund_names_no_payment)'
      using errcode = '23514',
            hint = 'Set transaction_id to the public.transactions row whose reveal_fee is being returned. A refund this platform did not issue is recorded through fn_refund_settle with requested_by stripe_webhook, and that path is exempt.';
  end if;

  select * into t from public.transactions where id = NEW.transaction_id;
  if not found then
    raise exception 'refunds: transaction % does not exist. (refund_transaction_absent)',
      NEW.transaction_id using errcode = '23503';
  end if;

  if t.reveal_fee is null or t.reveal_fee <= 0 then
    raise exception 'refunds: transaction % records no reveal fee (reveal_fee %), so there is nothing to give back. A refund of an unpaid reveal is a payment, not a refund. (refund_no_fee_was_paid)',
      NEW.transaction_id, coalesce(t.reveal_fee::text,'null') using errcode = '23514';
  end if;

  if t.refund_deadline is null then
    raise exception 'refunds: transaction % has no refund window. trg_reveal_window opens one at reveal, so a transaction without it was never revealed and no refund can be due yet. (refund_window_not_open)',
      NEW.transaction_id using errcode = '23514';
  end if;
  if now() < t.refund_deadline then
    raise exception 'refunds: the refund window on transaction % opens at % and it is now %. The customer waits the founder-set period of working days after the reveal before a refund can be claimed. (refund_window_not_yet_open)',
      NEW.transaction_id, t.refund_deadline, now() using errcode = '23514';
  end if;

  v_expected := round(t.reveal_fee * 100)::bigint;
  if NEW.amount_fils is not null and NEW.amount_fils <> v_expected then
    raise exception 'refunds: the amount must equal the reveal fee the customer actually paid on transaction % — expected % fils (AED %), got % fils (AED %). A refund figure is read off the payment, never typed. (refund_amount_is_not_the_fee_paid)',
      NEW.transaction_id, v_expected, round(t.reveal_fee,2), NEW.amount_fils, round(NEW.amount_fils/100.0,2)
      using errcode = '23514';
  end if;

  return NEW;
end
$function$;


-- ---------------------------------------------------------------------------------------------
-- fn_control_mode_require -- the founder_gated branch stops naming the identity register
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_control_mode_require(p_actor_email text, p_action text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_class text; v_s record;
begin
  -- AUDIT 8.3 TIER 0. Phase 1 rolled back to observe-only. Still audited, deliberately: during an
  -- incident, the record of what was done under the relaxed control is the most valuable thing here.
  if public.fn_phase1_disarmed() then
    insert into public.control_mode_audit (actor_email, event, action, allowed, reason)
    values (p_actor_email, 'action_allowed_phase1_disarmed', p_action, true,
            'Phase 1 Control Mode is disarmed - see public.phase1_rollback_log for who disarmed it and why');
    return jsonb_build_object('allowed', true, 'mode', 'disarmed',
      'reason', 'Phase 1 Control Mode is disarmed (rollback tier 0)');
  end if;

  select classification into v_class from public.control_mode_action where action = p_action;

  -- FAIL CLOSED. An action nobody classified is an action nobody thought about, and the cost of
  -- being wrong is asymmetric: refusing a read is an inconvenience, allowing an unreviewed mutation
  -- is the incident. The refusal is audited so the missing classification is discoverable.
  if v_class is null then
    insert into public.control_mode_audit (actor_email, event, action, allowed, reason)
    values (p_actor_email, 'action_unclassified', p_action, false, 'action is not in control_mode_action');
    return jsonb_build_object(
      'allowed', false, 'mode', 'observe', 'error', 'action_classification_required',
      'message', 'This action has not been classified as read-only or mutating, so it is refused. '
              || 'Classify it in control_mode_action (and in os_api ACTION_CLASS) before using it.');
  end if;

  if v_class = 'read_only' then
    return jsonb_build_object('allowed', true, 'mode', 'observe', 'reason', 'action is registered read-only');
  end if;

  if v_class = 'mode_control' then
    return jsonb_build_object('allowed', true, 'mode', 'observe', 'reason', 'Control Mode plumbing; handled before the gate');
  end if;

  -- FOUNDER-GATED (15 Aug 2026, reworded 9 Sep 2026). The founder's own command channel. It
  -- writes, so it is audited exactly like a Control Mode action; it is not gated by Control Mode,
  -- because the identity check inside fn_founder_command_submit is the control, and it is a
  -- stronger one than a fifteen-minute session -- a stolen admin session is not the founder.
  --
  -- NOTHING EXECUTABLE CHANGED HERE on 9 Sep 2026. This branch never read a phase table; only this
  -- comment and the audit reason below named the founder-identity register, which is deleted in
  -- this sweep. Both now name the routine that actually enforces the identity.
  if v_class = 'founder_gated' then
    insert into public.control_mode_audit (actor_email, event, action, allowed, reason)
    values (p_actor_email, 'action_allowed_founder_gated', p_action, true,
            'founder-identity gated: writes a work plan only, and fn_founder_command_submit refuses a caller it does not recognise');
    return jsonb_build_object('allowed', true, 'mode', 'founder',
      'reason', 'founder-identity gated; Control Mode does not apply to the founder''s own command channel');
  end if;

  select * into v_s from public.control_mode_session
   where actor_email = p_actor_email and closed_at is null and expires_at > now()
   order by opened_at desc limit 1;

  if not found then
    insert into public.control_mode_audit (actor_email, event, action, allowed, reason)
    values (p_actor_email, 'action_denied', p_action, false, 'no active Control Mode session');
    return jsonb_build_object('allowed', false, 'mode', 'observe', 'error', 'control_mode_required',
      'message', 'This changes something, so it needs Control Mode. Open it with a code sent to your phone, and say why.');
  end if;

  update public.control_mode_session set actions_used = actions_used + 1 where id = v_s.id;
  insert into public.control_mode_audit (actor_email, event, action, session_id, allowed, reason)
  values (p_actor_email, 'action_allowed', p_action, v_s.id, true, v_s.reason);

  return jsonb_build_object('allowed', true, 'mode', 'control', 'session_id', v_s.id, 'reason', v_s.reason,
                            'seconds_remaining', greatest(0, extract(epoch from (v_s.expires_at - now()))::int));
end $function$;


-- ---------------------------------------------------------------------------------------------
-- fn_ws_exec_home -- the handoffs tile goes with the table it counted
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_ws_exec_home()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with h as (select to_jsonb(public.fn_health_index()) j),
  gh as (
    select coalesce(
      (select 'monthly' where exists (select 1 from public.goal_period where horizon = 'monthly')),
      (select 'quarterly' where exists (select 1 from public.goal_period where horizon = 'quarterly')),
      'annual') hz
  ),
  g as (
    -- fn_goal_attainment handles the four ways the inline version was wrong (least() ignoring
    -- nulls, direction, period, row-count-as-goal-count). One copy, not two.
    select (a.j->>'pct')::numeric        pct,
           (a.j->>'goals_total')::int    n,
           (a.j->>'goals_measured')::int measured
      from gh, lateral (select public.fn_goal_attainment(gh.hz) j) a
  ),
  bott as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'department', r.owner_dept, 'resource', r.resource, 'used_pct', r.used_pct,
             'state', r.state, 'committed', r.committed, 'capacity', r.capacity, 'unit', r.unit)
           order by r.used_pct desc nulls last), '[]'::jsonb) j
      from public.v_resource_pressure r where r.state in ('HALT', 'DEGRADE')
  ),
  dept as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'department', coalesce(dh.department, e->>'label', e->>'key'),
             'dept_key', e->>'key',
             'runs', (e->'runs'),
             'busy', coalesce((e->>'runs')::int, 0) > 0,
             'health', dh.score, 'status', dh.status)
           order by coalesce((e->>'runs')::int, 0) desc), '[]'::jsonb) j
      from jsonb_array_elements(public.fn_agents_board()->'departments') e
      left join public.v_department_health dh on dh.dept_key = e->>'key'
  ),
  -- fn_founder_queue and fn_founder_refund_approvals_open were dropped earlier today with the rest
  -- of the founder-approval machinery: "all approvals are from CEO. nothing goes to me". The apply
  -- guard refused this file until these two calls came out, which is the guard doing its job -- a
  -- plpgsql body resolves its callees at RUN time, so without it this would have applied cleanly and
  -- thrown the first time the tile was rendered.
  fq as (select null::jsonb j),
  home as (select jsonb_build_object(
    'health_index',     (select (j->>'index')::numeric from h),
    'mood',             (select j->>'band' from h),
    'health_note',      (select j->>'note' from h),
    'revenue_today',    (select coalesce(sum(coalesce(reveal_fee, app_fee, 0)), 0)
                           from public.transactions where revealed_at::date = current_date),
    'revenue_30d',      (select coalesce(sum(coalesce(reveal_fee, app_fee, 0)), 0)
                           from public.transactions where revealed_at > now() - interval '30 days'),
    'goal_progress_pct', (select pct from g),
    'goal_horizon',     (select hz from gh),
    'goal_count',       (select n from g),
    'goal_measured',    (select measured from g),
    'customers_active', (select count(*) from public.customers where coalesce(banned, false) = false),
    'suppliers_active', coalesce((public.fn_marketplace_analytics()->>'active_suppliers_30d')::int, 0),
    'employees',        (select count(*) from public.org_agents where active),
    'employees_working', (select count(*) from public.org_agents o where o.active and (
                             exists (select 1 from public.agent_runs r
                                      where r.agent = o.agent_key and r.started_at > now() - interval '24 hours')
                          or exists (select 1 from public.agent_memory m
                                      where m.agent_key = o.agent_key and m.created_at > now() - interval '24 hours')
                          or exists (select 1 from public.agent_chats c
                                      where c.agent_key = o.agent_key and c.created_at > now() - interval '24 hours'))),
    'bottlenecks',      (select j from bott),
    'departments',      (select j from dept),
    'workflow_runs_24h', (select count(*) from public.workflow_run
                           where coalesce(started_at, created_at) > now() - interval '24 hours'),
    -- 9 SEP 2026 -- PHASE MACHINERY REMOVED. A 'handoffs_24h' key stood here counting
    -- the kernel handoff-run table over 24 hours. That table is deleted in this sweep, so the key is
    -- gone rather than pinned to a hard-coded zero: an absent number and a measured zero are
    -- different statements, and the OS must not be told "no handoffs" by a routine that can no
    -- longer count them. Any surface reading home.handoffs_24h now reads undefined; the founder
    -- has accepted that the website may break in the meantime and be rebuilt correctly.
    'events_delivered_24h', (select count(*) from public.event_delivery
                              where delivered_at > now() - interval '24 hours'),
    'knowledge_revisions_7d', (select count(*) from public.kb_revisions
                                where created_at > now() - interval '7 days'),
    'uptime_pct_24h', (select round(100.0 * count(*) filter (where verdict = 'ALIVE')
                                    / nullif(count(*), 0), 1)
                         from public.edge_health_probe where checked_at > now() - interval '24 hours'),
    'leads_total',      (select count(*) from public.leads),
    'agent_runs_24h',   (select count(*) from public.agent_runs where started_at > now() - interval '24 hours'),
    'events_24h',       (select count(*) from public.company_event where occurred_at > now() - interval '24 hours'),
    -- HIS decisions: refund approvals and nothing else. The 14 open agent_actions this used to
    -- count are held with their roles and reported under that name.
    -- HIS decision queue is empty by ruling, not by measurement: nothing is routed to him at all.
    'decisions_open',   0,
    'held_with_roles',  (select (j->>'held_with_roles_total')::int from fq),
    'held_with',        (select j->'held_with_roles' from fq),
    -- ONE definition of an open task: public.v_org_open_tasks (see one_definition_of_an_open_task.sql).
    'tasks_open',       (select count(*) from public.v_org_open_tasks),
    'generated_at',     now()
  ) j)
  -- THE OVERNIGHT BRIEF, AS ONE SENTENCE. Written here so the Console's "speak the overnight brief"
  -- button and the founder command channel ("status", "brief", "how are we doing") read the SAME
  -- text from the SAME figures, instead of one composing it in the browser and the other having no
  -- answer at all (6 Sep 2026: "status" came back as "clarification required").
  select h.j || jsonb_build_object('brief_text',
       'Company health ' || coalesce(h.j->>'health_index', 'unknown') || ', mood ' || coalesce(h.j->>'mood', 'unknown') || '. '
    || 'Revenue today ' || coalesce(h.j->>'revenue_today', '0') || ' dirhams, ' || coalesce(h.j->>'revenue_30d', '0') || ' over thirty days. '
    || coalesce(h.j->>'suppliers_active', '0') || ' active suppliers, ' || coalesce(h.j->>'customers_active', '0') || ' active customers. '
    || coalesce(h.j->>'employees_working', '0') || ' of ' || coalesce(h.j->>'employees', '0') || ' AI employees worked overnight. '
    || 'Goal progress ' || coalesce(h.j->>'goal_progress_pct', '0') || ' percent. '
    || coalesce(h.j->>'tasks_open', '0') || ' open tasks across every department. '
    || case when jsonb_array_length(coalesce(h.j->'bottlenecks', '[]'::jsonb)) > 0
            then jsonb_array_length(h.j->'bottlenecks')::text || ' departments are over capacity.'
            else 'No department is over capacity.' end)
  from home h;
$function$;


-- ---------------------------------------------------------------------------------------------
-- fn_company_self_knowledge_sync -- the company stops describing itself in phase vocabulary
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_company_self_knowledge_sync()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_state jsonb := public.fn_company_state();
  v_snap  jsonb := public.fn_company_snapshot();
  v_brief text  := public.fn_company_brief(6000);
  v_fee   numeric; v_sup_fee numeric; v_charge date; v_refund_wd int; v_cur text; v_free_n int; v_cat_min int;
  v_chase_wd int; v_bank_min int; v_bank_max int; v_admin numeric; v_pct numeric; v_founder_words text;
  v_target text; v_deadline text;
  v_social text; v_social_at text; v_blog text; v_blog_at text;
  v_founder text;
  v_tmpl text;
  v_rev numeric; v_exp numeric; v_pnl text;
  v_stance record; v_decisions text; v_cat_open text;
  v_records jsonb; r jsonb; v_rid text; v_n int := 0;
  reg public.company_registration%rowtype;
  -- 6 SEP 2026: the two supplier loops (acquisition, sanctions screening) — live values for the record below
  v_golive boolean; v_reg_target text; v_reg_month text; v_bd text; v_co text; v_last_un text; v_last_uae text;
  v_hits_open int; v_invited int; v_registered int; v_followups int; v_intake int;
begin
  v_golive := public.fn_supplier_outreach_golive();
  select coalesce(target_value::text, '300') into v_reg_target from public.company_goals where key = 'suppliers_registered_monthly';
  select coalesce(actual_value::text, '0') || ' (measured ' || coalesce(to_char(measured_at, 'DD Mon YYYY HH24:MI'), 'not yet') || ' UTC)'
    into v_reg_month from public.employee_kpi where agent_key = 'bd' and kpi = 'Suppliers registered per month' and active;
  select display_name into v_bd from public.org_role where role_id = 'business_development';
  select display_name into v_co from public.org_role where role_id = 'ceo';
  select entries || ' entries, fetched ' || to_char(fetched_at, 'DD Mon YYYY HH24:MI') || ' UTC, sha256 ' || left(coalesce(sha256, '?'), 12) || ', ' || status
    into v_last_un from public.screening_run where source = 'un_consolidated' and run_tag is null order by id desc limit 1;
  select entries || ' entries, fetched ' || to_char(fetched_at, 'DD Mon YYYY HH24:MI') || ' UTC, sha256 ' || left(coalesce(sha256, '?'), 12) || ', ' || status
    into v_last_uae from public.screening_run where source = 'uae_local_terrorist_list' and run_tag is null order by id desc limit 1;
  select count(*) into v_hits_open from public.supplier_screening_hit where status = 'open';
  select count(*) filter (where invite_status is not null), count(*) filter (where lifecycle_stage = 'registered'), coalesce(sum(invite_followups), 0)
    into v_invited, v_registered, v_followups from public.leads where coalesce(email, '') not ilike '%@example.invalid';
  select count(*) into v_intake from public.supplier_lead_intake where run_tag is null;
  select * into reg from public.company_registration order by recorded_at desc limit 1;
  -- the founder identity (who leads the company). 9 SEP 2026 -- PHASE MACHINERY REMOVED: this read
  -- the founder-identity register, which is deleted in this sweep. It was never an authority
  -- check here, only the address printed in the "who we are" knowledge record, so it is read from
  -- app_secrets.founder_email -- the same place fn_page_high_agent_action already reads it -- and
  -- falls back to the same literal the record already carried.
  select value into v_founder from public.app_secrets where key = 'founder_email';
  -- the live P&L (financial state beyond headline revenue)
  select coalesce(sum(amount) filter (where type='revenue'),0), coalesce(sum(amount) filter (where type='expense'),0),
         string_agg(case when amount <> 0 then '  - '||type||': '||name||' = AED '||amount::text else null end, E'\n' order by type, code)
    into v_rev, v_exp, v_pnl from public.gl_pnl;
  select standard_reveal_rate, supplier_reg_fee, supplier_charging_starts, refund_window_working_days,
         coalesce(reveal_currency,'AED'), chase_after_working_days, bank_settlement_working_days_min, bank_settlement_working_days_max,
         coalesce(supplier_free_count,1000), coalesce(category_open_min_suppliers,10)
    into v_fee, v_sup_fee, v_charge, v_refund_wd, v_cur, v_chase_wd, v_bank_min, v_bank_max, v_free_n, v_cat_min
    from public.pricing_config order by id limit 1;
  -- 6 SEP 2026: the refund ladder's money side and the founder's own words, from decision_policy
  v_admin := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_admin_fee_aed'), 250);
  v_pct   := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_late_fee_annual_pct'), 9);
  v_founder_words := (select d.value #>> '{}' from public.decision_policy d where d.key = 'refund_policy_founder_decision_2026_09_06');
  -- 6 SEP 2026: the founder's budget stance and his decisions on record (company_financial_stance,
  -- company_policy_decision), and the category-open count (v_category_open)
  select * into v_stance from public.company_financial_stance where id = 1;
  select string_agg('- ' || upper(decision_key) || ' (decided ' || to_char(decided_on,'DD Mon YYYY') || ' by the ' || decided_by
                    || case when never_ask_again then '; NEVER ask about it again' else '' end || '): ' || decision_text
                    || case when cardinality(applies_to) > 0 then ' [applies to: ' || array_to_string(applies_to, ', ') || ']' else '' end,
                    E'\n' order by decision_key)
    into v_decisions from public.company_policy_decision;
  select count(*) filter (where is_open) || ' of ' || count(*) || ' categories are OPEN today (' ||
         coalesce(max(verified_registered_suppliers),0) || ' is the highest verified-registered count in any category)'
    into v_cat_open from public.v_category_open;

  select coalesce(target_value::text,'1000000'), coalesce(to_char(deadline,'DD Mon YYYY'),'31 Aug 2027')
    into v_target, v_deadline
    from public.company_goals
   where active and (lower(coalesce(key,'')) like '%revenue%' or lower(coalesce(goal,'')) like '%revenue%'
                     or category = 'Financial')
   order by sort nulls last limit 1;

  select left(coalesce(content->>'text', content->>'body', content::text), 240), to_char(created_at,'DD Mon YYYY')
    into v_social, v_social_at from public.social_posts order by created_at desc limit 1;
  select title, to_char(coalesce(published_at, updated_at),'DD Mon YYYY')
    into v_blog, v_blog_at from public.blog_posts where published order by published_at desc nulls last limit 1;

  -- 9 SEP 2026 -- PHASE MACHINERY REMOVED. v_funnel was a listing of W04..W18 read from
  -- the programme workflow registry, appended to the marketplace knowledge record as "The 30 workflows
  -- that run this". The workflow registry is deleted in this sweep and the company is two agents
  -- with no departments and no W-numbered programme, so the sentence is dropped rather than left
  -- describing an organisation that no longer exists. The prose above still explains the funnel in
  -- plain words, which is what an agent answering a question actually needs.

  -- 6 SEP 2026: the WhatsApp template ledger (messaging_template), one line per template, live.
  select coalesce(string_agg('  - ' || template_key || ' [' || lang || ']: ' || upper(status) || ' (' || sid
           || coalesce(', ' || category, '') || coalesce(', submitted ' || to_char(submitted_at, 'DD Mon YYYY'), '')
           || coalesce(', approved (first seen ' || to_char(approved_at, 'DD Mon YYYY') || ')', '')
           || coalesce(', reason: ' || left(rejection_reason, 90), '') || coalesce(', ' || note, '') || ')',
           E'\n' order by template_key, lang), '  (no templates recorded)')
    into v_tmpl from public.messaging_template where channel = 'whatsapp';

  v_records := jsonb_build_array(

    -- 6 SEP 2026: the company's registration and tax status, from company_registration (the founder
    -- supplied the trade licence and ruled on VAT, Corporate Tax and the auditor that day; all are
    -- closed facts, never questions).
    jsonb_build_object('rid','registration','module','company_registration',
      'title','QuotesDone — Trade licence, registration and tax status',
      'kw', to_jsonb(array['trade licence','trade license','licence number','license number','DET','department of economy and tourism',
        'issuing authority','licence expiry','renewal','activity code','portal','software design','trader licence','e-trader',
        'VAT','vat registered','TRN','tax registration number','FTA','federal tax authority','threshold','375,000','corporate tax',
        'corporate tax registration','CT registration','small business relief','auditor','external auditor','audit firm','who audits us',
        'are we vat registered','do we charge vat','company registration','legal entity','owner','who owns the licence']),
      'content',
        case when reg.license_no is null then 'REGISTRATION: not recorded.' else
        'TRADE LICENCE: ' || reg.authority || ' ' || reg.license_type || ' no. ' || reg.license_no || ', trade name "' || reg.trade_name || '"; issued ' ||
        to_char(reg.issued_on,'DD Mon YYYY') || ', expires ' || to_char(reg.expires_on,'DD Mon YYYY') || ' (renew before then; renewal is a company task, not a founder question).' || E'\n' ||
        'OWNER: ' || reg.owner_name || ' (' || reg.owner_share || '); licensed activities: ' || reg.activities || '.' || E'\n' ||
        'REGISTERED CONTACT: ' || reg.registered_email || ', ' || reg.registered_mobile || '; e-stores on the licence: ' || reg.e_stores || '.' || E'\n' ||
        'LICENCE CLASS: ' || reg.license_class_note || E'\n' ||
        'TAX STATUS: ' || case when reg.vat_registered then 'VAT-registered, TRN ' || coalesce(reg.trn,'?') else
          'NOT VAT-registered (founder ruling ' || to_char(reg.vat_ruling_on,'DD Mon YYYY') || '): no VAT is charged or shown on any QuotesDone invoice until taxable supplies reach the FTA mandatory registration threshold of AED ' ||
          to_char(reg.vat_threshold_aed,'FM999,999,999') || ' in a rolling 12 months. Do not ask the founder about VAT or the TRN; when revenue approaches the threshold the CFO opens a registration task.' end || E'\n' ||
        'CORPORATE TAX: ' || coalesce(reg.corporate_tax_note,'registration status not recorded.') || E'\n' ||
        'AUDITOR: ' || coalesce(reg.auditor,'not recorded.')
        end),

    jsonb_build_object('rid','identity','module','company_identity',
      'title','QuotesDone — Identity, Vision and Mission',
      'kw', to_jsonb(array['vision','mission','what is quotesdone','who are we','company','marketplace','target','revenue goal','anonymous','uae','b2b',
        'who is the founder','company founder','who owns quotesdone','founder name','ahmad alzain','the owner',
        'company target and deadline','revenue target','what is our goal','aed 1 million target','1000000 by 2027','when is the deadline']),
      'content',
        'WHO WE ARE. ' || coalesce(v_state->>'mission','') || E'\n' ||
        'VISION: ' || coalesce(v_state->>'vision','') || E'\n' ||
        'TARGET: AED ' || v_target || ' in revenue by ' || v_deadline ||
          ' — every department''s objectives trace to this one number.' || E'\n' ||
        'HOW IT WORKS IN ONE LINE: an anonymous UAE B2B quotation marketplace — buyers post an RFQ, verified UAE '
        'suppliers submit quotes, and the buyer pays a small reveal fee to unlock and contact a chosen supplier. '
        'Every department is an autonomous AI expert that plans and executes toward the vision.' || E'\n' ||
        'FOUNDER / OWNER: Ahmad Alzain (' || coalesce(v_founder,'management@quotesdone.com') || '). The company is '
        'founder-led: he sets the vision, the target and the boundaries, and he is the ONLY approver of refunds. '
        'The AI departments run everything else on their own.'),

    jsonb_build_object('rid','financials','module','financials',
      'title','QuotesDone — Our Financials (live P&L) and the Budget Policy',
      'kw', to_jsonb(array['financials','finance','p&l','profit and loss','expenses','costs','revenue','how much did we spend','what were our expenses','net','burn','money','accounting','are we profitable',
        'budget','budget limit','budget policy','do we have a budget','budget variance','over budget','spending limit','when do we set budgets','profitable']),
      'content',
        'LIVE FINANCIAL STATE (from the general ledger; refreshes):' || E'\n' ||
        '  Total revenue: AED ' || round(coalesce(v_rev,0),2)::text || '  ·  Total expenses: AED ' || round(coalesce(v_exp,0),2)::text ||
        '  ·  Net: AED ' || round(coalesce(v_rev,0)-coalesce(v_exp,0),2)::text || E'\n' ||
        'By account (non-zero lines):' || E'\n' || coalesce(v_pnl,'  (no posted amounts yet)') || E'\n' ||
        'Read it honestly: revenue is ' || case when coalesce(v_rev,0)=0 then 'AED 0 because the marketplace is pre-launch' else 'as above' end ||
        '; the spend so far is mostly software and AI infrastructure while the company is being built.' || E'\n' ||
        'BUDGET POLICY (founder, ' || coalesce(to_char(v_stance.decided_on,'DD Mon YYYY'),'6 Sep 2026') || '): ' ||
          coalesce(v_stance.policy_text, 'No budget limit while costs are subscriptions; budgets come with profitability.') ||
          ' Current stance: ' || case when coalesce(v_stance.is_profitable,false) then 'PROFITABLE - budgets apply and budget-variance alerts are live.'
                                     else 'NOT YET PROFITABLE - budget_mode ' || coalesce(v_stance.budget_mode,'unlimited_until_profitable') ||
                                          '; there is no budget limit, and budget-variance alerts and budget-limit checks are inert. Do not ask the founder for a budget.' end),

    jsonb_build_object('rid','operating-model','module','operating_model',
      'title','QuotesDone — How the Marketplace Works, End to End',
      'kw', to_jsonb(array['funnel','operating model','how it works','journey','inquiry','rfq','routing','packaging','dispatch','reveal','pipeline','workflow']),
      'content',
        'THE FUNNEL. A customer''s job travels the pipeline autonomously:' || E'\n' ||
        '  W04 register/onboard the customer → W05 intake and qualify the inquiry (RFQ) → W06 route it to the right '
        'category → W07 process any drawings/BOQ/documents → W08 build and approve a supplier-SAFE package (customer '
        'identity and any contact details stripped) → W09/W10 onboard and verify suppliers → W12 match and dispatch to '
        'enough confirmed suppliers → W13 notify them → W14 suppliers submit and we evaluate quotations → W15 build the '
        'top-3 comparison and reveal path → W16 the customer pays the reveal fee and gets supplier contact → W17 handles '
        'any refund/dispute, W18 support and retention.' || E'\n' ||
        'ANONYMITY: buyers and suppliers never see each other until the buyer pays to reveal. Quotes are anonymized/'
        'masked until then.' ),

    jsonb_build_object('rid','commercials','module','commercials',
      'title','QuotesDone — Fees, Pricing and Refund Terms (live)',
      'kw', to_jsonb(array['fee','reveal fee','review fee','pricing','how much','commission','refund','supplier fee','registration fee','late fee','cost','price','supplier charging','when does supplier charging start','how much do suppliers pay','are suppliers charged','supplier registration','supplier pays',
        'discount','promo','promotion','coupon','free reveal','cap','fee cap','maximum fee','first 1000','first 1,000','open category','category open','when is a category open','how many suppliers to open a category']),
      'content',
        'REVEAL FEE (what the customer pays to unlock a supplier): ' || round(v_fee*100,2) || '% of the deal, in ' || v_cur ||
          ' — read live from pricing_config, so this figure is always the current one. NO cap, NO discount, NO promotional rate, '
          'NO coupon and NO free reveal exist or may be offered (founder, 6 Sep 2026; pricing_config forbids them by constraint).' || E'\n' ||
        'SUPPLIERS: ' || case when v_charge is null
          then 'registration is FREE for the first ' || v_free_n || ' registrations (those suppliers are exempt permanently); every registration after them pays ' ||
               coalesce(v_sup_fee::text,'1000') || ' ' || v_cur || ' per year. There is NO calendar start date and never will be: charging begins with registration ' ||
               (v_free_n + 1) || ', whenever that happens (founder, 6 Sep 2026). Never state a date; never ask the founder for one.'
          else 'registration is FREE until ' || to_char(v_charge,'DD Mon YYYY') || ', then ' || coalesce(v_sup_fee::text,'1000') || ' ' || v_cur || ' per year.' end ||
          ' Suppliers are auto-approved on a verified file.' || E'\n' ||
        'CATEGORY OPENING: a category is OPEN once it has ' || v_cat_min || ' verified registered suppliers (public.v_category_open); ' ||
          coalesce(v_cat_open, '') || '. Matching an RFQ still needs at least one confirmed supplier.' || E'\n' ||
        'REFUNDS: the supplier has ' || coalesce(v_refund_wd::text,'5') || ' UAE working days from the customer''s payment (Mon-Fri; Sat+Sun off; public holidays excluded). '
        'No response by working day ' || coalesce(v_chase_wd::text,'3') || ': the Customer Success Director chases the supplier, customer copied. Still silent on working day ' || coalesce(v_refund_wd::text,'5') ||
        ': the founder is notified for his final call. No response to that: the customer is refunded the FULL reveal fee (the 3% paid, no deduction) - EVERY refund of any amount is the founder''s approval - and told banks take '
        || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days. The supplier then owes that fee + AED ' || v_admin::text || ' administrative fee + '
        || v_pct::text || '% p.a. simple interest (fn_refund_amount_aed). Full record: qd-company:refunds.' || E'\n' ||
        'LATE FEE on overdue recoverables: 9% per annum (UAE Federal Decree-Law 50/2022).'),

    jsonb_build_object('rid','comparison-report','module','comparison_report',
      'title','QuotesDone — The Top-3 Comparison Report',
      'kw', to_jsonb(array['comparison report','compare','top 3','top three','quote comparison','ranking','shortlist','quote_compare','how do we compare','side by side']),
      'content',
        'THE COMPARISON REPORT IS ALWAYS THE TOP 3. However many quotations arrive — 3 or 100 — quote_compare ranks '
        'them ALL and returns the top three (ranks 1, 2, 3). It is NOT cheapest-wins: quotes are scored across multiple '
        'technical and commercial factors — price positioned across the range of offers, lead time, warranty, scope match, '
        'payment terms — so the strongest overall quote wins, not merely the lowest. The ranking is deterministic; the model '
        'writes the plain-language explanation of why the top three are the top three. The customer sees an anonymized '
        'side-by-side comparison table, saveable as a PDF, and only then decides whom to reveal.'),

    jsonb_build_object('rid','quotation-format','module','quotation_format',
      'title','QuotesDone — What a Supplier Quotation Contains',
      'kw', to_jsonb(array['quotation format','quote format','what is in a quote','quote fields','lead time','validity','payment terms','warranty','scope','exclusions','anonymized']),
      'content',
        'A supplier quotation carries: the quote amount, lead time, validity period, payment terms, warranty, scope of '
        'supply, conditions, exclusions, and notes. It may be typed or extracted from an uploaded file, then structured '
        'and committed (hashed) so it cannot be silently changed. BEFORE the customer sees it, the supplier''s identity '
        'and any contact details are anonymized/masked. The price the customer sees (customer_price) includes the '
        'platform margin/app fee on top of the supplier''s amount.'),

    jsonb_build_object('rid','terms','module','terms_and_conditions',
      'title','QuotesDone — Terms, Anonymity and Working Days',
      'kw', to_jsonb(array['terms','conditions','t&c','anonymous','reveal','working days','jurisdiction','policy','rules','uae']),
      'content',
        'QuotesDone is an ANONYMOUS UAE B2B marketplace. Suppliers are verified before they can quote. Buyer and supplier '
        'identities are hidden from each other until the buyer pays the reveal fee to contact a chosen supplier. All time '
        'windows use UAE working days (Asia/Dubai; Friday is a working day; the weekend is Saturday and Sunday; public '
        'holidays excluded). The reveal refund ladder is ' || coalesce(v_refund_wd::text,'5') || ' working days from payment: chase at '
        || coalesce(v_chase_wd::text,'3') || ', founder''s final call on day ' || coalesce(v_refund_wd::text,'5') || ', refund in full on no response, banks '
        || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days. Late fees '
        'follow UAE Federal Decree-Law 50/2022 (9% p.a.). The platform mediates disputes through a defined escalation ladder.'),

    jsonb_build_object('rid','governance','module','governance',
      'title','QuotesDone — How the Company Governs Itself',
      'kw', to_jsonb(array['governance','who approves','autonomy','refund approval','founder','escalation','boundaries','decisions','authority']),
      'content',
        'QuotesDone runs as ten autonomous AI departments (90 brain agents) that plan and execute toward the vision '
        'WITHOUT needing the founder''s approval for ordinary work. The founder is escalated to only for: money that '
        'leaves the company (every refund, any amount, needs his approval), destructive/irreversible production changes, '
        'and decisions only he holds (his intentions, external credentials, commercial direction). Everything else — '
        'routing, packaging, matching, pricing within policy, content — the agents decide and own. Colleagues hand work '
        'to one another through defined handoffs; nothing is left unowned.'),

    -- DYNAMIC: regenerated from the live org every run.
    jsonb_build_object('rid','organization','module','organization',
      'title','QuotesDone — The Organization: Departments, Colleagues and Roles',
      'kw', to_jsonb(array['organization','org chart','departments','how many agents','who works here','colleagues','roles','manager','line manager','team','north star','who does what','name the ten departments','list the departments','what are our departments','department names','the 10 departments']),
      'content', 'THE COMPANY YOU WORK IN (live roster — these are your colleagues; know who does what and who leads each team).' || E'\n' ||
        'THE TEN DEPARTMENTS: ' || coalesce((select string_agg(name, ', ' order by sort nulls last, dept_key) from public.org_departments where active),'') || E'\n' ||
        coalesce(v_brief,'')),

    -- DYNAMIC: the live snapshot every run.
    jsonb_build_object('rid','live-state','module','live_state',
      'title','QuotesDone — Live Company State (current)',
      'kw', to_jsonb(array['live','current','right now','revenue','last month revenue','how much revenue','customers','suppliers','open tasks','kpi','last social post','last blog','latest post','state','status','how are we doing']),
      'content',
        'LIVE STATE as of ' || to_char(now(),'DD Mon YYYY HH24:MI') || ' UTC (this refreshes; if a figure is 0 the company '
        'is pre-launch, not broken):' || E'\n' ||
        '  Revenue (last 30 days): ' || coalesce(v_snap->>'revenue_30d_aed','0') || ' AED' || E'\n' ||
        '  Customers: ' || coalesce(v_snap->>'customers','0') || ' (with an inquiry: ' || coalesce(v_snap->>'customers_with_inquiry','0') || ')' || E'\n' ||
        '  Approved suppliers: ' || coalesce(v_snap->>'approved_suppliers','0') || ' · Sendable supplier pool: ' || coalesce(v_snap->>'sendable_pool','0') || E'\n' ||
        '  Employees (brain agents): ' || coalesce(v_snap->>'employees','90') || ' · Departments: ' || coalesce(v_snap->>'departments','10') || E'\n' ||
        '  KPIs tracked: ' || coalesce(v_snap->>'kpis','0') || ' (open gaps: ' || coalesce(v_snap->>'kpi_gaps_open','0') || ')' || E'\n' ||
        '  Open tasks: ' || coalesce(v_snap->>'open_tasks','0') || ' · Items needing the founder: ' || coalesce(v_snap->>'needs_founder','0') || E'\n' ||
        '  AI spend (last 30 days): ' || coalesce(v_snap->>'ai_cost_30d_aed','0') || ' AED' || E'\n' ||
        '  Last social post: ' || coalesce(nullif(v_social,''),'(none yet)') || case when v_social_at is not null then ' [' || v_social_at || ']' else '' end || E'\n' ||
        '  Last blog post: ' || coalesce(nullif(v_blog,''),'(none yet)') || case when v_blog_at is not null then ' [' || v_blog_at || ']' else '' end),

    jsonb_build_object('rid','stage','module','company_stage',
      'title','QuotesDone — What Stage the Company Is At',
      'kw', to_jsonb(array['stage','pre-launch','have we launched','are we live','do we have customers','how many customers','are we operating','company status','how far along','launched yet','traction','are we making money']),
      'content',
        'COMPANY STAGE — READ THIS BEFORE ANSWERING ANYTHING ABOUT TRACTION. QuotesDone is PRE-LAUNCH. The '
        'platform and the AI organization are built and being readied; there are ' || coalesce(v_snap->>'customers','0') ||
        ' real customers and AED ' || coalesce(v_snap->>'revenue_30d_aed','0') || ' revenue so far. What is already in place: '
        '10 departments and ' || coalesce(v_snap->>'employees','90') || ' AI agents, 30 workflows, 86 supplier categories, '
        'the knowledge base and ' || coalesce(v_snap->>'approved_suppliers','1') || ' approved supplier(s). What is still pending before real '
        'operation: the marketplace go-live, real customer inquiries arriving, and funded AI inference so the agents can reason. '
        'NEVER claim customers, revenue, or results the numbers above do not show — we are building toward AED 1,000,000 by 31 Aug 2027, not there yet.'),

    -- 6 SEP 2026 (added at the END: sibling files restate this function; keep this the last element): the
    -- refund ladder, from pricing_config + decision_policy, the founder's ruling verbatim. Never re-ask him.
    jsonb_build_object('rid','refunds','module','refunds',
      'title','QuotesDone — The Refund Ladder (live): 5 working days, chase at 3, founder''s final call at 5',
      'kw', to_jsonb(array['refund','refund ladder','refund policy','refund window','non-response','supplier not responding','not responding','no response',
        'chase','chase the supplier','final call','founder final call','working days','5 working days','five working days','3 working days',
        'bank','7-14 working days','how long does a refund take','admin fee','administrative fee','250','9%','interest','9% per annum',
        'who chases','who owns refunds','refund amount','how much is refunded','supplier charge','non-response charge','fn_refund_amount_aed','fn_refund_state','refund_ladder_sweep']),
      'content',
        'THE REFUND LADDER (founder ruling 6 Sep 2026, final; read live from pricing_config and decision_policy):' || E'\n' ||
        '  Day 0: the customer pays the reveal fee (' || round(v_fee*100,2) || '% of the quotation, no cap). The clock starts at PAYMENT; nothing the customer does or does not do moves it.' || E'\n' ||
        '  Working day ' || coalesce(v_chase_wd::text,'3') || ' with no supplier response: the Customer Success Director (runtime agent followup, customer_experience) chases the supplier by email, customer copied, WhatsApp when opted in, and holds an org_task until the supplier responds. Deterministic: fn_refund_ladder_sweep, cron refund_ladder_sweep_hourly.' || E'\n' ||
        '  Working day ' || coalesce(v_refund_wd::text,'5') || ' with still no response: the refund request is filed through fn_refund_request (the ONE door) and the founder is notified for his FINAL CALL (founder_mail_policy kind refund_final_call - one of only two refund signals that reach his inbox; the other is the approval itself).' || E'\n' ||
        '  No response to his call: he approves the refund in the OS (fn_refund_decide; every refund, any amount, is his decision, never automatic).' || E'\n' ||
        '  The customer is refunded the FULL fee paid - no deduction - and told that banks take ' || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days to show it.' || E'\n' ||
        '  The supplier whose silence caused it owes: the refunded fee (the 3%) + AED ' || v_admin::text || ' administrative fee + ' || v_pct::text || '% per annum simple interest (the UAE statutory maximum), and is blocked from matching until settled. One function states the arithmetic: fn_refund_amount_aed(paid, paid_at, refund_at).' || E'\n' ||
        '  Working days are Monday to Friday, UAE public holidays excluded (fn_is_working_day). fn_refund_state(transaction) says where any case stands.' || E'\n' ||
        'WHO OWNS WHAT: chase = Customer Success Director (existing owner of supplier follow-up); final call + approval = the founder; execution on Stripe = Payments & Billing Manager; reconciliation = Financial Controller; recovery from the supplier = Accounts Receivable via collections_legal. No new employee was created for this.' || E'\n' ||
        'THE FOUNDER''S WORDS (verbatim, 6 Sep 2026 - never ask him about refunds again): "' || coalesce(v_founder_words, '(decision_policy.refund_policy_founder_decision_2026_09_06)') || '"'),

    -- 6 SEP 2026: the brand kit, from company_brand (the founder attached the kit that day: "make sure it's
    -- in company knowledge so you never ask me about it again"). Appended LAST on purpose: sibling files add
    -- qd-company:decisions and qd-company:refunds to this same array; they merge ahead of this record.
    jsonb_build_object('rid','brand','module','brand',
      'title','QuotesDone — Brand Kit: colours, typography, logo rules, voice and asset files',
      'kw', to_jsonb(array['brand','brand kit','brand guide','brand guidelines','logo','logo files','lockup','wordmark','mark','favicon','app icon',
        'colour','color','colours','colors','hex','palette','teal','gold','navy','ink','brand colours','what are our colours','primary colour','primary color',
        'font','typeface','typography','poppins','plus jakarta sans','tajawal','arabic font','type scale',
        'tagline','clear space','minimum size','logo usage','social image size','cover size','avatar','banner','post template',
        'tone of voice','voice','wording','bilingual','arabic','rtl','email template','pdf header','letterhead','business card','trademark','ip filing','vector','svg',
        'where is the logo','which logo file','brand assets','brand bucket','contrast','wcag','accessibility','button colour','link colour']),
      'content',
        'THE BRAND KIT IS ON FILE (the founder attached QuotesDone_Brand_Kit.zip on 6 Sep 2026 and ruled it company knowledge: never ask him for a logo, a colour or a font again). '
        || 'Files: ' || (select count(*) from public.brand_assets where bucket = 'brand')::text
        || ' assets in the public brand bucket under kit/ (public.brand_assets holds kind, platform, path, size and usage per file; WHERE_TO_USE.txt is the kit index). '
        || 'The full guide is docs/brand/QUOTESDONE_BRAND_GUIDE.md and the "QuotesDone Brand Guide" PDF in the OS Reports panel.' || E'\n'
        || coalesce((select string_agg(g.block, E'\n' order by g.grp_sort)
                       from (select cb."group", min(cb.sort) as grp_sort,
                                    upper(cb."group") || ':' || E'\n'
                                    || string_agg('  - ' || cb.key || ': ' || cb.value || coalesce(' — ' || cb.note, ''), E'\n' order by cb.sort) as block
                               from public.company_brand cb group by cb."group") g),
                    '  (company_brand is empty)')),

    -- 6 SEP 2026: the founder's decisions, verbatim in substance, from company_policy_decision. Added at the
    -- END on purpose: the renderer is code-driven and sibling packets (the refund ladder and the brand kit
    -- above, messaging) add their records before it. Whichever packet lands last keeps its record last;
    -- order carries no meaning here.
    jsonb_build_object('rid','decisions','module','founder_decisions',
      'title','QuotesDone — The Founder''s Standing Decisions (never ask about these again)',
      'kw', to_jsonb(array['founder decision','founder decisions','standing decision','ruling','policy decision','what did the founder decide','never ask again',
        'corporate tax','auditor','meta token','daily budget cap','30 aed','cost per lead target','cpl target','openrouter','open router credit','recharge','receipts','expenses email',
        'discount','no discounts','reveal cap','category open','10 suppliers','finance budget','budget limit','profitable','supplier registration fee','first 1000','1000 aed per year','no deadline','no date']),
      'content',
        'THE FOUNDER''S STANDING DECISIONS. Each line is final. None is a question; none is asked again; every table, document and agent head is kept in sync with them.' || E'\n' ||
        coalesce(v_decisions, '(none recorded)'))
,

    -- 6 SEP 2026 (appended at the END, code-driven): the two supplier loops the founder decided on that day.
    jsonb_build_object('rid','supplier-loops','module','supplier_loops',
      'title','QuotesDone — Supplier acquisition loop and weekly sanctions screening (owners, cadence, switch)',
      'kw', to_jsonb(array['supplier acquisition','invite campaign','supplier invites','follow-up','follow up','300 suppliers','suppliers per month',
        'registered suppliers target','lead intake','inbound email','new leads','lead sourcing','supplier_outreach_golive','outreach switch','is outreach on',
        'sanctions','sanctions screening','UN consolidated list','UAE terrorist list','local terrorist list','screening hit','banned supplier',
        'who owns supplier acquisition','who screens suppliers','compliance officer','business development manager','weekly screening','when do we screen']),
      'content',
        'SUPPLIER ACQUISITION LOOP (founder decision 6 Sep 2026). Owner: ' || coalesce(v_bd, 'Business Development Manager') || ' (org_role business_development, agent bd, department supply) — '
        'no new employee was created; this is that role''s existing responsibility. Target: at least ' || v_reg_target || ' suppliers registered every month '
        '(company_goals.suppliers_registered_monthly; the BD scorecard KPI "Suppliers registered per month", measured from leads registration timestamps). '
        'This month so far: ' || coalesce(v_reg_month, '0 (not measured yet)') || '. Sources: the leads we already hold (' || v_invited || ' invited to date, '
        || v_registered || ' registered), inbound e-mail (senders on business domains become leads; supplier-intent replies are classified by keyword — no model — into '
        'register / question / document / decline / bounce and become ONE reply task on the BD manager; ' || v_intake || ' classified so far), and the staged directory '
        'promoted daily by supplier_discovery_daily. No scraping (Apify paused) and no paid inference anywhere in the loop. Cadence: supplier_invites_daily 09:00 UTC '
        '(the invitation batch, capped, deliverability-guarded) and supplier_outreach_daily 05:30 UTC (follow-ups at +3 and +7 WORKING days after a delivered '
        'invitation, at most two, never to a lead that replied, registered, bounced or is suppressed; ' || v_followups || ' follow-ups sent to date; inbox intake; lead sourcing). '
        'THE SWITCH: app_secrets.supplier_outreach_golive is ' || case when v_golive then 'TRUE — outreach is LIVE.' else 'FALSE — every part of the loop is HELD and records "held" on each run; the founder flips it when the app is ready ("none of this will run till the app is perfect").' end
        || ' Both it and invite_enabled must be true before an invitation is written.' || E'\n\n' ||
        'WEEKLY SANCTIONS SCREENING (founder decision 6 Sep 2026). Owner: ' || coalesce(v_co, 'Compliance & Privacy Officer') || ' (org_role compliance_and_privacy_officer, agent compliance_mgr, '
        'department legal — the actor of supplier_onboarding step 4 "Compliance screen before anything is activated"). Cadence: sanctions_screen_weekly, Mondays 03:00 UTC (07:00 Dubai). '
        'Sources: the UN Security Council consolidated list (XML; last: ' || coalesce(v_last_un, 'not fetched yet') || ') and the UAE Local Terrorist List from the Executive Office '
        'for Control & Non-Proliferation (published as PDF and legacy Excel only — the Excel is parsed, the PDF is not; last: ' || coalesce(v_last_uae, 'not fetched yet') || '). '
        'Every registered supplier is screened on legal name, licence name, owner, contact and e-mail domain by normalised exact match and conservative token overlap. '
        'A hit opens ONE task on the compliance officer with the evidence and ONE hold on the BD manager — the team is updated, never the founder — and NOBODY is removed automatically: '
        'the compliance officer decides (fn_supplier_screening_decide), and a CONFIRMED hit moves the supplier through the existing status path (banned, matching blocked, approval withdrawn). '
        'Open hits right now: ' || v_hits_open || '. Records: screening_run (source, entries, fetched_at, sha256), screening_entry, supplier_screening_hit.'),

    -- 6 SEP 2026 (LAST on purpose — every sibling file of the day restates this function and the last record
    -- is the one a later restatement can carry forward without touching the others): the WhatsApp templates
    -- and their Meta approval status, live from messaging_template (the founder said "fix the template
    -- yourself"; the status is company knowledge, never his question).
    jsonb_build_object('rid','messaging-templates','module','messaging_templates',
      'title','QuotesDone — WhatsApp templates and their Meta approval status (live)',
      'kw', to_jsonb(array['whatsapp template','whatsapp templates','template approval','meta approval','twilio','content sid','contentsid',
        'founder alert whatsapp','whatsapp alert','whatsapp alerts to the founder','is the whatsapp template approved','pending template',
        'template pending','template rejected','63016','utility template','messaging template','messaging_template','wa_template_sids',
        'can we send whatsapp','why did the whatsapp not arrive','send_whatsapp','wa_template_setup','business-initiated message','24-hour session']),
      'content',
        'WHATSAPP TEMPLATES (Twilio Content API, approved by Meta; live from messaging_template):' || E'\n' || v_tmpl || E'\n' ||
        'THE RULES. A business-initiated WhatsApp (an alert to the founder, a job / quote / reveal / document notice to a supplier or '
        'customer) is deliverable ONLY through a Meta-APPROVED template sent by ContentSid; a freeform body is delivered only inside the '
        '24-hour session the recipient opened by messaging us first (Twilio error 63016 otherwise). A template still pending approval is a '
        'HELD message, never a failed one: send_whatsapp keeps supplier and customer rows queued until the template lands, marks founder-alert '
        'rows skipped with the reason (the email already carried the alert), and refuses a direct send with the reason instead of erroring. '
        'Templates are created and submitted by the wa_template_setup function (category UTILITY, language en/ar, the body opens AND closes '
        'with literal text because Meta rejects a variable at the start or end); the sender refreshes each pending status from Twilio at most '
        'every ten minutes and only ever sends with a status of APPROVED. The sender number is registered with Meta as "QuotesDone" '
        '(quality rating and messaging tier are read from Twilio, not assumed). Nobody asks the founder about WhatsApp templates: the '
        'status above is the answer, and a pending line means Meta has not answered yet.')
  );

  for r in select * from jsonb_array_elements(v_records) loop
    v_rid := 'qd-company:' || (r->>'rid');
    insert into public.ops_knowledge(
      record_id, scope_type, scope_key, layer, module, record_type, title, content,
      structured_data, source_ids, implementation_status, validation_status, authority_tier,
      risk_level, version, keywords, dependencies, escalation_rule, jurisdiction, source_freshness,
      confidentiality, runtime_eligible, deterministic, supersession_state, embedding_status,
      effective_date)
    values (
      v_rid, 'company', 'company_core', 'company_core', r->>'module', 'md', r->>'title',
      -- fold the keyword vocabulary into the content so the generated tsv (title+content) indexes the
      -- phrasings agents actually ask in, not only the prose. This is what makes deep questions match.
      (r->>'content') || E'\n\nYou can answer questions about: ' ||
        array_to_string(array(select jsonb_array_elements_text(r->'kw')), ', ') || '.',
      '{}'::jsonb, array['fn_company_self_knowledge_sync'], 'active', 'validated', 'autonomous',
      'low', '1', array(select jsonb_array_elements_text(r->'kw')), '{}'::text[], '{}'::jsonb, 'UAE', 'current',
      'internal', true, true, 'current', 'pending', current_date)
    on conflict (record_id) do update set
      module = excluded.module, title = excluded.title, content = excluded.content,
      keywords = excluded.keywords, effective_date = excluded.effective_date,
      supersession_state = 'current', embedding_status = 'pending';
    v_n := v_n + 1;
  end loop;

  -- The org directory (everyone knows everyone: role, line manager, KPI, live rating) and the
  -- published content (FAQ, social, blog, website) are recomposed in the same refresh.
  perform public.fn_company_org_directory_sync();

  return jsonb_build_object('ok', true, 'records', v_n, 'ran_at', now(),
    'revenue_30d_aed', v_snap->>'revenue_30d_aed', 'reveal_fee_pct', round(v_fee*100,2),
    'employees', v_snap->>'employees');
end $function$;


-- ---------------------------------------------------------------------------------------------
-- fn_company_org_directory_sync -- the "30 workflows" knowledge record goes
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_company_org_directory_sync()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d record; s record; a_txt text; sec_txt text; v_social text; v_blog text; v_web text; v_cat text;
        v_legal text; v_compl text; v_biz jsonb; v_n int := 0;
begin
  -- 1. THE WHOLE ORG DIRECTORY — one record per department; everyone knows everyone's role, line
  --    manager, what they are measured on and their live rating.
  for d in select dept_key, name, charter, north_star, lead_agent from public.org_departments where active order by dept_key loop
    select string_agg(
             '  - ' || a.agent_key || ' (' || coalesce(a.title, a.role, '') || ') — reports to ' || coalesce(a.manager_key,'—')
             || coalesce((select ' — measured on: ' || string_agg(k.kpi || ' [target ' || coalesce(k.target_value::text,'—')
                          || ', current ' || coalesce(k.actual_value::text,'—') || ']', '; ')
                          from public.employee_kpi k where k.agent_key = a.agent_key and coalesce(k.active,true)), ''),
             E'\n' order by a.agent_key)
      into a_txt from public.org_agents a where a.active and a.department = d.dept_key;
    perform public.fn_company_knowledge_upsert(
      'org-' || d.dept_key, 'organization',
      'QuotesDone Org — the ' || coalesce(d.name, d.dept_key) || ' team',
      'DEPARTMENT: ' || coalesce(d.name, d.dept_key) || ' [' || d.dept_key || ']. Lead: ' || coalesce(d.lead_agent,'—')
      || '. North star: ' || coalesce(d.north_star,'—') || E'\n'
      || 'Members — agent — role — reports to (line manager) — measured on [target, current rating]:' || E'\n'
      || coalesce(a_txt, '(none)'),
      array[d.dept_key, coalesce(d.name,''), 'who works in ' || coalesce(d.name,d.dept_key), 'department team',
            'line manager', 'who reports to whom', 'kpi', 'measured on', 'current rating', 'colleagues',
            'who leads ' || coalesce(d.name,d.dept_key)]);
    v_n := v_n + 1;
  end loop;

  -- 2. THE PUBLISHED FAQ — grouped by section; the 484 answers a colleague could give a customer or supplier.
  for s in select coalesce(nullif(btrim(section),''),'general') sec, string_agg('Q: '||question||E'\n'||'A: '||coalesce(answer,''), E'\n' order by sort nulls last, id) qa
             from public.company_faq where coalesce(public,true) and coalesce(status,'approved') <> 'rejected'
             group by 1 loop
    perform public.fn_company_knowledge_upsert(
      'faq-' || regexp_replace(lower(s.sec),'[^a-z0-9]+','-','g'), 'faq',
      'QuotesDone FAQ — ' || s.sec,
      'FREQUENTLY ASKED (published answers — you may give these to customers and suppliers):' || E'\n' || left(s.qa, 6000),
      array['faq', 'frequently asked', s.sec, 'question', 'answer', 'how do i', 'what is', 'customer question', 'supplier question']);
    v_n := v_n + 1;
  end loop;

  -- 3. SOCIAL, BLOG, WEBSITE — the company's own published content.
  select string_agg('  - ['||to_char(created_at,'DD Mon YYYY')||', '||coalesce(channels::text,'')||', '||coalesce(status,'')||'] '
                    || left(coalesce(content->>'text', content->>'body', content::text), 200), E'\n' order by created_at desc)
    into v_social from public.social_posts;
  perform public.fn_company_knowledge_upsert('content-social','content','QuotesDone — Our Social Media Posts',
    'SOCIAL MEDIA POSTS (most recent first):' || E'\n' || coalesce(v_social,'(none yet)'),
    array['social media','social post','last post','latest post','instagram','linkedin','what did we post','our content','marketing post']);
  v_n := v_n + 1;

  select string_agg('  - ['||coalesce(to_char(published_at,'DD Mon YYYY'),'draft')||', '||coalesce(category,'')||'] '||title
                    ||coalesce(' — '||excerpt,''), E'\n' order by published_at desc nulls last)
    into v_blog from public.blog_posts where published;
  perform public.fn_company_knowledge_upsert('content-blog','content','QuotesDone — Our Blog Articles',
    'BLOG ARTICLES (published):' || E'\n' || left(coalesce(v_blog,'(none yet)'), 6000),
    array['blog','article','blog post','our articles','what have we written','content','seo','latest blog']);
  v_n := v_n + 1;

  select string_agg('  - /'||slug, E'\n' order by slug) into v_web from public.pages;
  perform public.fn_company_knowledge_upsert('content-website','content','QuotesDone — Our Website Pages',
    'WEBSITE PAGES we publish (the public site an agent should know exists):' || E'\n' || coalesce(v_web,'(none)')
    || E'\n\nThe published legal terms, services and marketing copy live on these pages; the terms and commercials are also summarised in the company terms and commercials knowledge.',
    array['website','web page','our site','pages','website content','what is on our website','public site']);
  v_n := v_n + 1;

  -- 4. THE SUPPLIER CATEGORY TAXONOMY — every category an RFQ can be routed to.
  select string_agg('  ' || num || '. ' || name || case when regulated then ' (regulated)' else '' end, E'\n' order by sort, num)
    into v_cat from public.catalog_supplier_categories;
  perform public.fn_company_knowledge_upsert('categories', 'taxonomy',
    'QuotesDone — The Supplier Categories We Cover',
    'SUPPLIER CATEGORIES (' || (select count(*) from public.catalog_supplier_categories)::text
      || ' in total) — every category an RFQ can be routed to, in order:' || E'\n' || coalesce(v_cat, '(none)'),
    array['categories','supplier categories','what do we cover','category list','taxonomy','trades','how many categories','what categories','regulated categories','which category','list the categories']);
  v_n := v_n + 1;

  -- 5. 9 SEP 2026 -- PHASE MACHINERY REMOVED. Section 5 published a company knowledge record
  --    titled "The 30 Workflows We Run", built by reading the programme workflow registry. That registry
  --    is deleted in this sweep, and the company is two agents (ceo, customer_support) with no
  --    departments and no W-numbered programme, so the record described an organisation that does
  --    not exist. The whole section is removed; the already-published copy is deleted below, in
  --    this same transaction, so no agent keeps reciting it out of ops_knowledge. Sections 1-4 and
  --    6-7 are unchanged and the record count in the return value simply drops by one.

  -- 6. LEGAL, COMPLIANCE AND POLICY FRAMEWORK.
  select string_agg('  - ' || coalesce(title, slug) || case when coalesce(category,'') <> '' then ' [' || category || ']' else '' end
         || case when coalesce(summary,'') <> '' then ': ' || left(summary,140) else '' end, E'\n' order by category, title)
    into v_legal from public.legal_documents;
  select string_agg('  - ' || requirement || ' (' || case when present then 'in place' else 'pending' end || ')', E'\n' order by priority nulls last, id)
    into v_compl from public.legal_checklist;
  perform public.fn_company_knowledge_upsert('legal', 'legal_compliance',
    'QuotesDone — Legal, Compliance and Policy Framework',
    'LEGAL & COMPLIANCE. QuotesDone operates under UAE law (Asia/Dubai; PDPL data protection). Published legal documents:' || E'\n'
    || coalesce(v_legal,'(none)') || E'\n' || 'Compliance checklist:' || E'\n' || coalesce(v_compl,'(none)') || E'\n'
    || 'Posture: anonymous marketplace, buyer/supplier identities protected until reveal, EVERY refund is founder-approved, '
    || 'late fees under UAE Federal Decree-Law 50/2022, disputes handled through a defined escalation ladder.',
    array['legal','compliance','regulatory','policy','terms of service','privacy policy','pdpl','data protection','uae law','are we compliant','legal documents','what laws apply','governing law','gdpr']);
  v_n := v_n + 1;

  -- 7. THE BUSINESS ENTITIES — the live customer/supplier/order landscape, and HOW to look up any one.
  begin v_biz := public.fn_business_entity_summary(); exception when others then v_biz := '{}'::jsonb; end;
  perform public.fn_company_knowledge_upsert('business-entities', 'business_data',
    'QuotesDone — Our Customers, Suppliers and Orders (live), and how to look them up',
    'THE BUSINESS RIGHT NOW (live counts):' || E'\n' ||
    '  Customers: ' || coalesce(v_biz->>'customers','0') || ' (with an inquiry: ' || coalesce(v_biz->>'customers_with_inquiry','0') || ')' || E'\n' ||
    '  Suppliers: ' || coalesce(v_biz->>'suppliers_total','0') || ' total — ' || coalesce(v_biz->>'suppliers_approved','0') || ' approved, '
      || coalesce(v_biz->>'suppliers_prospective','0') || ' prospective; sendable pool ' || coalesce(v_biz->>'sendable_supplier_pool','0') || E'\n' ||
    '  Inquiries/RFQs: ' || coalesce(v_biz->>'inquiries','0') || '  ·  Quotes: ' || coalesce(v_biz->>'quotes','0') || '  ·  Transactions/orders: ' || coalesce(v_biz->>'transactions','0') || E'\n' ||
    '  Categories: ' || coalesce(v_biz->>'categories_total','0') || ' (' || coalesce(v_biz->>'categories_at_target','0') || ' at the 10-supplier target)' || E'\n' ||
    'HOW TO KNOW A SPECIFIC ONE (do not memorise the records — look them up live):' || E'\n' ||
    '  - fn_business_entity_lookup(entity, key): one customer/supplier/inquiry/quote/transaction by id, email, company name or phone -> its full profile.' || E'\n' ||
    '  - fn_business_entity_list(entity, filter, limit): list or search them (e.g. all approved suppliers, recent inquiries).' || E'\n' ||
    '  - fn_business_entity_summary(): these live counts. Call these functions directly — you run with the database access to do so.',
    array['customers','suppliers','how many customers','how many suppliers','who are our customers','who are our suppliers','their profiles','their orders','look up a supplier','find a customer','list suppliers','our orders','the crm','business data','inquiries','quotes','transactions','entity lookup']);
  v_n := v_n + 1;

  return jsonb_build_object('ok', true, 'records', v_n, 'ran_at', now());
end $function$;

-- ---------------------------------------------------------------------------------------------
-- fn_refund_founder_decision_only -- the register goes; the guard REFUSES rather than disappears
-- ---------------------------------------------------------------------------------------------
--
-- WHAT STOOD HERE: this BEFORE trigger let a refunds row reach 'approved' only when decided_by was
-- an active row in the founder-identity register. The founder has retired that concept -- he
-- approves nothing now, every approval is the CEO's -- and the register is deleted in this sweep.
--
-- WHY IT IS NOT DELETED TO NOTHING. This is the money path. Before this guard existed,
-- fn_refund_request auto-approved anything inside the promised window and under
-- org_authority(customer_success, refund_within_window) -- AED 2,000 -- writing
-- decided_by = 'policy:auto_window' and setting transactions.refund_status = 'approved', so a
-- refund was paid with nobody deciding it. A guard that simply vanished would restore exactly
-- that. So the guard stays and REFUSES the case it was built for: an approval with no decider, or
-- one whose "decider" is a policy string rather than an actor. It no longer asks WHICH actor,
-- because no register survives that could answer, and re-pointing it at a CEO table would rebuild
-- the same machinery under a new name. When the CEO seat has a runtime with an identity of its
-- own, this is the one line to tighten.
create or replace function public.fn_refund_founder_decision_only()
 returns trigger
 language plpgsql
 set search_path to 'public', 'pg_temp'
as $function$
begin
  if new.status <> 'approved' then return new; end if;

  if coalesce(btrim(new.decided_by), '') <> ''
     and lower(btrim(new.decided_by)) not like 'policy:%' then
    return new;
  end if;

  raise exception
    'refund %: approved by %, which is not an actor.',
    coalesce(new.id::text, '(new)'), coalesce(nullif(btrim(new.decided_by), ''), '(nobody)')
    using errcode = '42501',
          hint = 'A refund reaches ''approved'' only through fn_refund_decide, and only with a '
              || 'decided_by naming the actor who decided it. An empty decider, or one of the form '
              || '''policy:...'', means a rule approved the money and no one did: that is how '
              || 'fn_refund_request auto-approved every in-window refund before 17 Aug 2026. '
              || 'Approvals are the CEO''s (founder ruling, 8 Sep 2026); pass the deciding actor.';
end
$function$;

-- ---------------------------------------------------------------------------------------------
-- fn_customer_terms_accept -- the acceptance is recorded on the customer, and nowhere else
-- ---------------------------------------------------------------------------------------------
--
-- WHAT WAS REMOVED, and what it contributed:
--   1. a lookup of the document slug in the programme's acceptance-document registry -- it only
--      ever resolved to 'customer-terms', which was already the coded fallback;
--   2. a read of the programme's object-record store to find an existing acceptance for
--      (customer, version), and a write of a new one through the object-write routine -- an audit
--      object in a store that is deleted in this sweep;
--   3. a re-dispatch of the open W04-S01 step: find the customer's W04 run in the workflow-run
--      table, find its active step run, and push it through the step-dispatch routine.
--
-- None of that survives the removal of the programme, so all three are gone rather than
-- re-pointed. WHAT REMAINS IS THE PRODUCT EFFECT, unchanged: the published version and its sha256
-- digest are read from public.legal_documents (never trusted from the caller, newest
-- effective_date wins because version is a label and not an order), and public.customers gets
-- tos_accepted_at / tos_version / tos_ip written idempotently. That is what makes the customer
-- terms-accepted everywhere the product asks.
--
-- THE RETURN SHAPE IS DEPRECATED, NOT CHANGED. Callers already read ok / acceptance_ref /
-- terms_version / terms_hash, and some read run_id / step_run_id / dispatch_outcome / effect_id /
-- dispatch. Dropping those five keys would break those callers on a different day from this
-- change, so they are still present and are now always null, with 'dispatch_removed' saying why.
-- acceptance_ref keeps its old '<customer_id>:<version>' shape: it is the natural key of the
-- acceptance and remains true even though nothing stores a row under it any more.
create or replace function public.fn_customer_terms_accept(p_customer_id uuid, p_ip text default null::text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  c            public.customers%rowtype;
  v_slug       text := 'customer-terms';
  v_version    text;
  v_digest     text;
  v_owner      text := p_customer_id::text;
begin
  select * into c from public.customers where id = p_customer_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no such customer ' || p_customer_id);
  end if;

  -- The currently published document: newest effective_date wins (version is a label, not an
  -- order). The version and digest are read here and never trusted from the caller.
  select d.version, encode(sha256(convert_to(coalesce(d.body_html,''),'UTF8')),'hex')
    into v_version, v_digest
    from public.legal_documents d where d.slug = v_slug
    order by d.effective_date desc nulls last, d.version desc limit 1;
  if v_version is null then
    return jsonb_build_object('ok', false, 'reason', 'no published document for slug ' || v_slug);
  end if;

  -- Idempotent: a second acceptance does not move the first acceptance's timestamp.
  update public.customers
     set tos_accepted_at = coalesce(tos_accepted_at, now()),
         tos_version = v_version,
         tos_ip = coalesce(nullif(btrim(p_ip),''), tos_ip)
   where id = p_customer_id;

  return jsonb_build_object(
    'ok', true,
    'acceptance_ref', v_owner || ':' || v_version,
    'terms_version', v_version,
    'terms_hash', v_digest,
    'document_slug', v_slug,
    -- Kept null so existing callers keep parsing. See the header above.
    'run_id', null,
    'step_run_id', null,
    'dispatch_outcome', 'dispatch_removed',
    'effect_id', null,
    'dispatch', null);
end $function$;

-- ---------------------------------------------------------------------------------------------
-- The knowledge record that recited the programme is withdrawn
-- ---------------------------------------------------------------------------------------------
--
-- fn_company_org_directory_sync published 'qd-company:workflows' -- "QuotesDone - The 30 Workflows
-- We Run" -- from the registry that is deleted in this sweep. The section is gone from the routine
-- above, but the row it already wrote would sit in ops_knowledge for ever and every agent
-- retrieving company knowledge would keep reciting an organisation that does not exist. Deleted in
-- the same transaction as the routine that wrote it, so the two can never disagree.
delete from public.ops_knowledge where record_id = 'qd-company:workflows';

-- ---------------------------------------------------------------------------------------------
-- THE CHECK: no surviving routine still names the programme or its kernel
-- ---------------------------------------------------------------------------------------------
--
-- Scope: every function and procedure in public whose OWN name is not part of the machinery (those
-- are dropped by their own file, and until they are, their bodies naturally still name it).
--
-- One deliberate exemption: fn_kernel_paid_provider_gate -- KEPT. supabase/functions/_shared/
-- paid_gate.ts calls it, and it reads only app_secrets, llm_route_health and model_registry: no
-- programme table at all. Verified 9 Sep 2026 by reading its body. Its callers
-- (fn_workflow_step_claim, fn_workflow_step_sweep) are therefore correct as they stand and were
-- NOT rewritten -- their only reference to the machinery is that gate, so the check erases the
-- gate's name before matching rather than exempting the two routines wholesale.
--
-- The truncate guard the sweep also carries needs no exemption here: measured 9 Sep 2026, no
-- routine outside the machinery matches on account of it. It is handled in its own later file.
do $check$
declare v_bad text;
begin
  select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', E'\n  '
                    order by p.proname)
    into v_bad
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.prokind in ('f','p')
     and p.proname !~ '^(fn_kernel_|fn_phase_|phase_)'
     and regexp_replace(p.prosrc, 'fn_kernel_paid_provider_gate', '', 'g') ~ '(phase_[abcd]_|fn_kernel_)';
  if v_bad is not null then
    raise exception
      E'the programme is still named by % surviving routine(s):\n  %',
      array_length(string_to_array(v_bad, E'\n  '), 1), v_bad
      using errcode = '23514',
            hint = 'Each of these still reaches into a table or routine that the removal file is '
                || 'about to drop. Rewrite it here, in this file, before the drop runs -- do not '
                || 'weaken this check, and do not drop the object out from under a live routine.';
  end if;
end $check$;

commit;

-- HOW TO PROVE IT AFTER APPLYING (read-only, against production):
--   select p.proname
--     from pg_proc p
--    where p.pronamespace = 'public'::regnamespace
--      and p.proname !~ '^(fn_kernel_|fn_phase_|phase_)'
--      and replace(p.prosrc, 'fn_kernel_paid_provider_gate', '') ~ '(phase_[abcd]_|fn_kernel_)';
--   -- expected: 0 rows.
