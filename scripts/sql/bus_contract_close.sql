-- SPEC FILE #2 — closing the cross-OS contract (xos-02..xos-15, comp-07, comp-08-out-alerts,
-- contract-consolidation).  Applied to BOTH projects with:
--   node scripts/apply_sql.mjs scripts/sql/bus_contract_close.sql --promote --ddl
-- Every statement is idempotent and safe to re-apply.
--
-- The chain up to link 6 already worked on 6 Aug: events are emitted, the bus dispatches them,
-- each OS assesses impact and raises a task, and the task executes inside the authority model.
-- Links 7-11 and the three hard rules did not: a task closed and the event that caused it never
-- heard about it, so nothing consolidated, nothing re-prioritised, no lesson was attached to an
-- event, and no OS was stopped from writing straight into another OS's queue.  This file closes
-- the loop back to the event, and it does it in ONE place — fn_event_consolidate — rather than
-- teaching every subscriber to report home.

-- ══ 1 · SUBSCRIPTIONS · the bus can only carry what someone is listening for ══════════════════
-- cybersecurity_mgr is not an employee.  It never was: org_agents has `security` in `it`, and the
-- subscription has been pointing at a name that does not exist, so ten security.event rows were
-- delivered to nobody and recorded `unroutable`.  Repointing is the fix; deactivating would be
-- deleting the requirement instead of meeting it.
update public.event_subscription
   set agent_key = 'security'
 where agent_key = 'cybersecurity_mgr'
   and exists (select 1 from public.org_agents a where a.agent_key = 'security');

-- The Evolution OS was the one active OS with no subscriber at all — it could not receive a single
-- company event.  os_interface already declares kpi.missed as one of its two inputs, so this adds
-- the subscription the interface was already promising rather than inventing a new contract.
insert into public.event_subscription (agent_key, event_type, reason, active)
select 'optimisation_eng', 'kpi.missed',
       'The Evolution OS declares kpi.missed as an input: a missed KPI is the trigger for an '
    || 'optimisation cycle. Without this subscription the Evolution OS received no events at all.',
       true
where not exists (select 1 from public.event_subscription
                   where agent_key='optimisation_eng' and event_type='kpi.missed');

-- xos-09.  Leadership declares priority.updated as an OUTPUT and nobody listened for it, so a
-- re-prioritisation had nowhere to land.  Strategy owns company priorities.
insert into public.event_subscription (agent_key, event_type, reason, active)
select 'strategy_director', 'priority.updated',
       'A consolidated event chain closed across more than one OS. Re-read the company priorities '
    || 'against what it cost and what it produced, and restate them if the evidence moved.', true
where not exists (select 1 from public.event_subscription
                   where agent_key='strategy_director' and event_type='priority.updated');

-- xos-12.  fn_company_reflect wrote a task straight into procurement's queue — Leadership reaching
-- into the Marketplace OS, which is exactly what the hard rule forbids.  The work is NOT dropped:
-- the reflection now emits supply.gap (marketplace's own declared output kind) and procurement
-- subscribes, so the same one task arrives through the bus instead of around it.
insert into public.event_subscription (agent_key, event_type, reason, active)
select 'procurement', 'supply.gap',
       'A category has a viable supplier pool and no invitations sent. Queue the invitations, or '
    || 'record why the pool is not usable.', true
where not exists (select 1 from public.event_subscription
                   where agent_key='procurement' and event_type='supply.gap');

-- ══ 2 · HONEST DELIVERY RECORD ═══════════════════════════════════════════════════════════════
-- 173 deliveries carry neither a task nor a reason.  They are not a live defect — they were all
-- written before 07:00 today by the dispatcher body that predated unroutable_reason, and every
-- delivery since carries one — but a NULL that means "the old dispatcher did not raise tasks" is
-- indistinguishable from "this event was dropped", and that ambiguity is the whole point of the
-- column.  Naming it is the fix; inventing 173 retrospective tasks would not be.
update public.event_delivery
   set unroutable_reason = 'Delivered by the pre-2026-08-06 dispatcher, which recorded the '
     || 'delivery without raising a task. No task exists for this delivery and none will be '
     || 'created retrospectively; the event type is still subscribed and still routes today.'
 where task_id is null and unroutable_reason is null;

-- ══ 3 · os_interface · a declared interface that cannot fire yet must say so ══════════════════
-- The founder's 6 Aug ruling: traffic-gated kinds are marked planned with a reason rather than
-- faked into firing, because production has zero customers.  This extends the same honesty to the
-- kinds that are condition-gated (the emitter is wired, the condition has not occurred) and to the
-- ones that have no emitter at all — each says which it is, in its own words.
update public.os_interface set event_type = kind where event_type is null;

update public.os_interface i set planned = true, planned_reason = v.why
from (values
  -- traffic-gated: cannot fire until a real customer or supplier acts (founder ruling, 6 Aug)
  ('inquiry.created',     'Traffic-gated: fires when a customer submits an inquiry. Production has zero customers.'),
  ('supplier.applied',    'Traffic-gated: fires when a supplier applies. Production has zero supplier applications.'),
  ('invoice.received',    'Traffic-gated: fires when a supplier invoice arrives. Production has zero invoices.'),
  ('contract.submitted',  'Traffic-gated: fires when a contract is submitted for review. Production has zero contracts.'),
  ('rfq.dispatched',      'Traffic-gated: fires when an RFQ goes out to a supplier pool. Production has dispatched none.'),
  ('lead.qualified',      'Traffic-gated: fires when a lead is qualified. Production has zero leads.'),
  ('payment.settled',     'Traffic-gated: fires when a payment settles. Production has zero payments.'),
  -- condition-gated: the emitter is wired and proven, the triggering condition has not occurred
  ('outcome.graded',      'Condition-gated: fn_outcome_evaluate emits it as it grades. The first outcome_record falls due 2026-08-11; nothing is gradable before then.'),
  ('rollback.required',   'Condition-gated: fn_outcome_evaluate emits it when an outcome grades WORSE. No outcome has been graded yet (first window 2026-08-11).'),
  ('budget.exceeded',     'Condition-gated: fn_budget_rollup emits it when a department crosses its halt threshold. The heaviest department is at 0.8% of its monthly budget.'),
  -- no emitter: an honest gap, named rather than hidden behind a NULL
  ('campaign.published',  'No emitter: there is no campaign object in the schema. Commercial publishes through content.published until one exists.'),
  ('regulation.changed',  'No emitter: compliance_sources lists 17 watched regulators and nothing fetches them, so no change can be detected. Eight agents subscribe and have never received one.'),
  ('sla.breached',        'No emitter: no SLA is recorded anywhere in the schema, so no service level exists to breach.'),
  ('health.degraded',     'No emitter: operating_system.health_score is populated (75-97 today) but no routine turns a drop into an event.'),
  ('forecast.published',  'No emitter: the Intelligence OS produces forecasts into tables, not onto the bus.'),
  ('policy.updated',      'No emitter: policy changes are recorded in the governance tables and never announced on the bus.'),
  ('process.changed',     'No emitter: workflow edits are not announced on the bus.'),
  ('deploy.completed',    'No emitter: deployments are driven from the repository, outside the database.'),
  ('incident.opened',     'No emitter: incidents are raised as org_tasks directly and never announced on the bus.'),
  ('decision.executive',  'No emitter: executive decisions are written to decision_trace and never announced on the bus.')
) as v(kind, why)
where i.kind = v.kind;

-- Anything that HAS flowed is not planned, whatever a previous run said.  This is the self-healing
-- half: the flag is derived from reality on every apply, so it cannot rot into a false excuse.
-- BOTH names must have flowed. One row declares kind='campaign.published' with
-- event_type='content.published' — an aspirational name beside the one the bus really carries —
-- and keying this on event_type alone cleared the planned flag off an interface whose own declared
-- kind has never fired once.  A promise is only kept when the thing that was promised arrives.
update public.os_interface i set planned = false, planned_reason = null
 where coalesce(i.planned,false)
   and exists (select 1 from public.company_event e where e.event_type = i.event_type)
   and exists (select 1 from public.company_event e where e.event_type = i.kind);

-- ══ 4 · fn_task_lesson · a lesson from an event-derived task is not a review verdict ══════════
-- The existing branches describe a review_chain outcome ("cleared the quality standard", "returned
-- by review").  An event-derived task closes because the OS finished the work, not because a
-- reviewer passed it, so calling it 'published' would put words in the reviewer's mouth. One new
-- branch, keyed on p_outcome='event_closed', records what the task itself reported.
create or replace function public.fn_task_lesson(p_task_id bigint, p_outcome text, p_review jsonb)
 returns bigint
 language plpgsql
 security definer
 set search_path to 'public', 'pg_catalog'
as $function$
declare
  t record; v_id bigint; v_kind text; v_conf numeric; v_detail text; v_what text;
begin
  select o.id, o.dept_key, o.title, o.action_class, o.tier, o.result from org_tasks o
    into t where o.id = p_task_id;
  if t.id is null then return null; end if;

  -- What the review actually found, in the review's own words. Violations first because a failure
  -- is the lesson; dissents next; otherwise the approval and who gave it.
  select string_agg(distinct (v->>'rule') || ' (' || (v->>'severity') || '): ' || coalesce(v->>'why',''), ' | ')
    into v_detail from jsonb_array_elements(coalesce(p_review->'violations','[]'::jsonb)) v;

  if v_detail is null or v_detail = '' then
    select string_agg((d->>'by') || ' ' || (d->>'stance') || ': ' || left(coalesce(d->>'reasoning',''), 300), ' | ')
      into v_detail from jsonb_array_elements(coalesce(p_review->'dissents','[]'::jsonb)) d;
  end if;

  if p_outcome = 'event_closed' then
    -- xos-10. The Knowledge OS captures what a DISPATCHED EVENT produced. Confidence is 0.6 —
    -- the floor fn_agent_institutional_memory serves from — because one closed task is weak
    -- evidence on its own but is exactly the raw material the lesson index is built from.
    v_kind   := 'lesson';
    v_conf   := 0.6;
    v_detail := 'Raised by ' || coalesce(p_review->>'event_type','a company event')
             || ' on the bus and closed by ' || t.dept_key || '. Result: '
             -- org_tasks.result is JSONB, not text: the OS writes {at, mode, brain, summary} and
             -- the summary is the part that is a lesson. `nullif(t.result,'')` casts '' to jsonb
             -- at CALL time — it survived a staging apply that had no closed tasks to iterate and
             -- failed on production's 58. ->> returns text and never has to cast.
             || left(coalesce(nullif(t.result->>'summary',''), 'closed with no recorded result'), 600)
             || '. Correlation ' || coalesce(p_review->>'correlation_id','unknown') || '.';
    v_what   := 'success';
  elsif p_outcome = 'published' and (v_detail is null or v_detail = '') then
    v_kind   := 'lesson';
    v_conf   := 0.5;   -- recorded for the audit trail; below fn_agent_institutional_memory's 0.6 floor
    v_detail := 'Cleared the quality standard for a department deliverable on the first pass and was '
             || 'approved by ' || coalesce(p_review->>'reviewer','the department head') || ' and the Chief of Staff.';
    v_what   := 'success';
  elsif p_outcome = 'published' then
    v_kind   := 'lesson_learned';
    v_conf   := 0.85;  -- shipped OVER a recorded objection: the most useful thing to remember
    v_detail := 'Approved and published despite a recorded objection. ' || v_detail;
    v_what   := 'success_over_dissent';
  else
    v_kind   := 'lesson_learned';
    v_conf   := 0.85;
    v_detail := 'Returned by review (' || p_outcome || '). ' || coalesce(v_detail, 'see review_chain');
    v_what   := 'worse';
  end if;

  insert into institutional_memory
    (kind, subject_type, subject_id, headline, detail, outcome, learned_by, confidence,
     evidence_ref, visible_to, occurred_at)
  values (v_kind, 'org_task', t.id::text,
          left(t.dept_key || ': ' || coalesce(t.title,'(untitled task)'), 200),
          left(v_detail, 2000), v_what, t.dept_key, v_conf,
          case when p_outcome = 'event_closed'
               then 'event_delivery:org_task:' || t.id
               else 'review_chain:org_task:' || t.id end,
          array[t.dept_key], now())
  returning id into v_id;

  return v_id;
end $function$;

-- ══ 5 · fn_event_consolidate · links 7, 8, 9, 10 and the bus's own health ═════════════════════
-- ONE routine closes the loop, on purpose.  The alternative — every subscriber reporting its own
-- outcome home — is eleven places to get wrong and eleven places that can silently stop.
--
-- FEEDBACK-LOOP GUARD, because this bus has produced 169 tasks in one hour before.  The
-- re-prioritisation it emits carries the SAME correlation_id as the chain it summarises, so:
--   * the priority.updated event joins the chain it came from rather than starting a new one;
--   * the `not exists ... priority.updated with this correlation_id` test therefore blocks a
--     second emission for that chain forever, on this run and every later one;
--   * a chain whose ROOT is itself a priority.updated is skipped outright, as a second defence.
-- Both are needed: the first stops the loop, the second stops it from ever starting.
--
-- SUPERSEDED — the current definition of fn_event_consolidate lives in
-- scripts/sql/bus_contract_read.sql, which adds the two reads that were missing here: the
-- event_assessment each OS wrote before acting (link 4, previously written and read by nothing)
-- and the consolidation backlog off v_event_backbone. Apply that file after this one.
create or replace function public.fn_event_consolidate()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  r record; v_outcome text; v_note text; v_backbone text; v_lesson bigint;
  n_closed int := 0; n_lessons int := 0; n_rollups int := 0; n_priorities int := 0;
  -- Bounded like the dispatcher's batch, for the same reason: an unbounded first run on a backlog
  -- is how a burst happens.  The work is finite and the cron is hourly.
  c_max_close    constant int := 200;
  c_max_priority constant int := 25;
begin
  -- ── LINK 7 · the result comes back to the event that caused the work ────────────────────────
  -- A delivery whose task has closed but whose result column is still NULL is precisely the gap:
  -- the OS did the work and the event never heard.  org_tasks.result is the OS's own words; the
  -- status is the fallback when it closed without writing one.
  for r in
    select d.id as delivery_id, d.event_id, d.task_id, d.os_key,
           t.status, t.result, t.title, t.updated_at, e.correlation_id, e.event_type
      from event_delivery d
      join org_tasks t     on t.id = d.task_id
      join company_event e on e.id = d.event_id
     where d.closed_at is null and t.status in ('done','closed')
     order by d.id
     limit c_max_close
  loop
    update event_delivery
       -- ->> not nullif(...,''): org_tasks.result is jsonb and event_delivery.result is text.
       set result    = left(coalesce(nullif(r.result->>'summary',''),
                                     r.status || ': ' || coalesce(r.title,'')), 1000),
           closed_at = coalesce(r.updated_at, now())
     where id = r.delivery_id;
    n_closed := n_closed + 1;

    -- ── LINK 10 · Knowledge captures the lesson from an EVENT outcome ─────────────────────────
    -- Joined through event_delivery.task_id, which is what makes the lesson traceable to a
    -- dispatched event rather than to a task that arrived some other way.
    if not exists (select 1 from institutional_memory m
                    where m.subject_type = 'org_task' and m.subject_id = r.task_id::text) then
      v_lesson := public.fn_task_lesson(r.task_id, 'event_closed',
                    jsonb_build_object('event_type', r.event_type,
                                       'correlation_id', r.correlation_id::text,
                                       'os_key', r.os_key));
      if v_lesson is not null then n_lessons := n_lessons + 1; end if;
    end if;
  end loop;

  -- ── LINK 8 · the Chief of Staff consolidates ACROSS OSes ───────────────────────────────────
  -- One row per business episode, not per event: correlation_id is the episode.  os_count is the
  -- number of distinct Operating Systems the episode touched, which is the difference between a
  -- consolidation and a receipt.
  for r in
    select e.correlation_id,
           min(e.id)                                        as root_event_id,
           (array_agg(e.event_type order by e.id))[1]       as root_type,
           count(distinct d.os_key)                         as os_count,
           count(d.task_id)                                 as tasks_total,
           count(*) filter (where d.closed_at is not null)   as tasks_closed
      from company_event e
      join event_delivery d on d.event_id = e.id
     where e.correlation_id is not null
     group by e.correlation_id
  loop
    -- Defence 2: never consolidate a chain a re-prioritisation started.
    if r.root_type = 'priority.updated' then continue; end if;

    v_outcome := case when r.tasks_total = 0                  then 'no_work'
                      when r.tasks_closed = 0                 then 'open'
                      when r.tasks_closed < r.tasks_total     then 'partial'
                      else 'closed' end;
    v_note := format('%s across %s OS: %s of %s task(s) closed.',
                     r.root_type, r.os_count, r.tasks_closed, r.tasks_total);

    insert into event_rollup (correlation_id, root_event_id, event_type, os_count,
                              tasks_total, tasks_closed, outcome, priority_note, consolidated_at)
    values (r.correlation_id, r.root_event_id, r.root_type, r.os_count,
            r.tasks_total, r.tasks_closed, v_outcome, v_note, now())
    on conflict (correlation_id) do update
      set os_count = excluded.os_count, tasks_total = excluded.tasks_total,
          tasks_closed = excluded.tasks_closed, outcome = excluded.outcome,
          priority_note = excluded.priority_note, consolidated_at = excluded.consolidated_at;
    n_rollups := n_rollups + 1;

    -- ── LINK 9 · the CEO re-prioritises off the consolidated outcome ──────────────────────────
    -- The episode must have crossed an OS boundary — a single-OS chain is that OS's own business
    -- and does not move company priorities — and at least one OS must have RETURNED something,
    -- because a priority cannot be revised against an outcome that does not exist yet.
    --   Deliberately not 'closed' only. Measured on production: all 22 cross-OS episodes sit at
    --   0/4 or 1/4 tasks closed, and one task that never closes would hold the whole episode — and
    --   the company's priorities — hostage forever. Link 9 says "off event OUTCOMES", not "off all
    --   of them". One re-prioritisation per episode either way: the dedupe is on correlation_id.
    if v_outcome in ('closed','partial') and r.os_count > 1 and n_priorities < c_max_priority
       and not exists (select 1 from company_event ce
                        where ce.event_type = 'priority.updated'
                          and ce.correlation_id = r.correlation_id) then
      -- xos-14. This event is CAUSED by the root of the chain and belongs to the same chain. The
      -- settings are read by company_event's column defaults, which is why fn_emit does not name
      -- either column.  Defence 1 lives here: same correlation_id => the `not exists` above is
      -- permanently true for this episode from the next run onward.
      perform set_config('app.correlation_id',      r.correlation_id::text, true);
      perform set_config('app.causation_event_id',  r.root_event_id::text,  true);
      perform public.fn_emit('priority.updated', 'event_chain', r.correlation_id::text, 'ceo',
                jsonb_build_object('root_event_id', r.root_event_id, 'root_type', r.root_type,
                                   'os_count', r.os_count, 'tasks_closed', r.tasks_closed,
                                   'note', v_note));
      perform set_config('app.correlation_id',     '', true);
      perform set_config('app.causation_event_id', '', true);
      n_priorities := n_priorities + 1;
    end if;
  end loop;

  -- The Knowledge OS's declared output. One per run rather than one per lesson: the bus carries
  -- the fact that institutional memory moved, not 58 copies of it.
  if n_lessons > 0 then
    perform public.fn_emit('knowledge.updated', 'institutional_memory', 'event_lessons',
              'knowledge_director', jsonb_build_object('lessons_added', n_lessons));
  end if;

  -- ── xos-15 · somebody looks at the bus ─────────────────────────────────────────────────────
  -- v_event_backbone is the one surface that says which subscribed event types are live, which
  -- have never fired and which are undelivered.  It had zero readers, which made it a diagram.
  select coalesce(string_agg(event_type || ' ' || state, ', ' order by event_type),
                  'every subscribed event type is LIVE')
    into v_backbone
    from v_event_backbone where state <> 'LIVE';

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('event_consolidate', now(), now(), 'ok',
          jsonb_build_object('deliveries_closed', n_closed, 'lessons', n_lessons,
                             'rollups', n_rollups, 'priorities_emitted', n_priorities),
          'Cross-OS contract closed: ' || n_closed || ' delivery result(s) returned, ' || n_lessons
          || ' lesson(s) captured, ' || n_rollups || ' chain(s) consolidated, ' || n_priorities
          || ' re-prioritisation(s) emitted. Bus backbone: ' || v_backbone);

  return jsonb_build_object('deliveries_closed', n_closed, 'lessons', n_lessons,
                            'rollups', n_rollups, 'priorities_emitted', n_priorities,
                            'bus_backbone', v_backbone);
end $function$;

-- ══ 6 · fn_company_reflect · route the one cross-OS write through the bus ════════════════════
-- Unchanged except for the supply-gap branch and one added answer.  Leadership no longer writes
-- into procurement's queue; it emits marketplace's own declared output kind and the bus delivers
-- it to procurement, which subscribes.  ONE task before, ONE task after — the work is routed, not
-- dropped, which is the condition the founder attached to this change.
-- ROUTINE REMOVED 7 September 2026. public.fn_company_reflect was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ══ 7 · fn_emit_metric_alerts · the Intelligence OS's declared output ════════════════════════
-- Unchanged except for the third block. metric.alert is intelligence's declared OUTPUT kind and
-- had no emitter at all. One event per run rather than one per metric: the alert is that the
-- scorecard moved, and nine copies of it would be nine tasks per subscriber.
-- ROUTINE REMOVED 7 September 2026. public.fn_emit_metric_alerts was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ══ 8 · fn_budget_rollup · budget.exceeded is finance's declared input and had no emitter ═════
-- Only the halt branch changes: crossing the halt threshold is the event, and the founder alert it
-- already raises is the same fact told to one person instead of to the company.
-- ROUTINE REMOVED 7 September 2026. public.fn_budget_rollup was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ══ 9 · fn_outcome_evaluate · outcome.graded and rollback.required ═══════════════════════════
-- Two emissions added, nothing else touched. The first outcome_record falls due 2026-08-11, so
-- neither fires today and neither should be made to: manufacturing a graded row to turn a gate
-- green is the failure this project has been burned by. The wiring is what is being built here.
-- ROUTINE REMOVED 7 September 2026. public.fn_outcome_evaluate was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ══ 10 · fn_os_improve · improvement.proposed is Evolution's declared output ══════════════════
-- One emission per improvement question actually raised, so the count on the bus equals the count
-- in the queue. Nothing else in the routine changes.
-- ROUTINE REMOVED 7 September 2026. public.fn_os_improve was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ══ 11 · xos-12 · the hard rule, enforced rather than declared ════════════════════════════════
-- "No OS calls another OS directly."  What that forbids is one OS COMMANDING another — putting
-- assigned work into a department it does not own, around the bus.  It does not forbid an OS
-- opening its own internal work: link 5 of this same contract REQUIRES that, so a rule reading
-- "nothing may insert into org_tasks" would contradict its own neighbour.
--
-- So the guard refuses exactly the commanding case, and permits the three things the blueprint
-- explicitly allows:
--   * anything the bus routed (decided_by = 'fn_event_dispatch') — that IS the sanctioned path;
--   * anything merely PROPOSED — a recommendation the receiving OS may decline is not a command;
--   * the Chief of Staff layer (cos / approval_path / dept_plan), whose entire job in this
--     blueprint is cross-OS coordination (link 8).
-- Measured against all 466 org_tasks rows on production before deploying: zero would have been
-- refused, so this changes no existing behaviour and bites the first genuine violation instead.
create or replace function public.fn_org_task_cross_os_guard()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_target_os text; v_author_os text;
begin
  if coalesce(new.status,'proposed') = 'proposed' then return new; end if;
  if coalesce(new.decided_by,'') in ('fn_event_dispatch','cos','approval_path','dept_plan') then
    return new;
  end if;

  select od.os_key into v_target_os from os_department od where od.dept_key = new.dept_key;

  select od.os_key into v_author_os
    from org_agents a join os_department od on od.dept_key = a.department
   where a.agent_key = new.decided_by;

  -- An unattributed writer is a company-level routine, not an Operating System, and the blueprint
  -- does not forbid those. Only a named OS reaching across is refused.
  if v_author_os is null or v_target_os is null or v_author_os = v_target_os then
    return new;
  end if;

  raise exception
    'org_tasks: % (%) cannot ASSIGN work to % (%). No OS calls another OS directly — emit the '
    'event and let the bus route it, or lower this to status=''proposed'' so the receiving OS can '
    'decline it.', new.decided_by, v_author_os, new.dept_key, v_target_os
    using errcode = 'check_violation';
end $function$;

drop trigger if exists trg_org_task_cross_os_guard on public.org_tasks;
create trigger trg_org_task_cross_os_guard
  before insert on public.org_tasks
  for each row execute function public.fn_org_task_cross_os_guard();

-- ══ 12 · schedules ═══════════════════════════════════════════════════════════════════════════
-- fn_emit_metric_alerts is the ONLY kpi.missed emitter in the database and had no caller of any
-- kind, so the Intelligence OS could not tell anybody a KPI had been missed. Weekly, not daily:
-- nine metrics are OFF_TARGET and three OSes subscribe to kpi.missed, so a daily run would put
-- ~30 tasks a day into the queue for facts that change on a weekly cadence. It runs an hour
-- before fn_kpi_review's Monday slot so the events exist when the review reads them.
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.

-- Hourly, four times the dispatcher's cadence, so a delivery closed at 07:05 is consolidated the
-- same morning rather than the next day.
