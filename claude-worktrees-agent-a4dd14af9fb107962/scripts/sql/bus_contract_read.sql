-- SPEC FILE #2 — the READ half of the cross-OS contract (xos-04, xos-08).
--   node scripts/apply_sql.mjs scripts/sql/bus_contract_read.sql --promote --ddl
-- Idempotent, safe to re-apply. Apply AFTER scripts/sql/bus_contract_close.sql; the
-- fn_event_consolidate definition here SUPERSEDES the one in that file.
--
-- WHY THIS FILE EXISTS. scripts/sql/bus_contract_close.sql built the write half of links 4 and 8 —
-- fn_event_dispatch records one event_assessment per (event, OS) before it raises a task, and
-- fn_event_consolidate writes one event_rollup per business episode. Both landed populated and
-- READ BY NOTHING: on 6 Aug 2026 the only object in the database referencing event_assessment was
-- fn_event_dispatch's INSERT, and the only object referencing event_rollup was
-- fn_event_consolidate's INSERT. The scorer scored both MET on '1 live reader' because its reader
-- test matched a mention rather than a select, and the mention it matched was the write.
--
-- That is the exact defect this spec file exists to catch, so the check was hardened and the two
-- assets were given consumers rather than the check being softened to keep them green:
--
--   1. event_assessment now reaches the Chief of Staff's consolidation and, through it, the CEO.
--      The impact each OS recorded BEFORE acting is rolled up per episode into
--      event_rollup.priority_note and into the payload of the priority.updated event the CEO
--      re-prioritises on. An assessment that changes nothing downstream is a form filled in for
--      no reader; this is the smallest change that makes it load-bearing.
--   2. event_rollup now reaches v_event_backbone, the bus's own health surface, which
--      fn_company_reflect (cron company_reflect_nightly) and fn_event_consolidate (cron
--      event_consolidate) both already select. Consolidation backlog is bus health: an episode
--      that spans three OSes and never closes is exactly what that view is for.
--
-- KNOWN REMAINING GAP, deliberately not closed here because it is outside this session's
-- ownership: the strongest reader for event_rollup would be fn_agent_context surfacing open
-- cross-OS episodes in the Chief of Staff's and CEO's prompts. Until that exists, the leadership
-- OS learns about consolidation through the nightly reflection rather than in the moment.

-- ══ 1 · v_event_backbone · the bus health surface also reports consolidation ══════════════════
-- New columns are appended AFTER `state`: CREATE OR REPLACE VIEW can only add at the end, and the
-- two existing readers select `event_type` and `state` by name, so nothing downstream shifts.
create or replace view public.v_event_backbone as
  select s.event_type,
         count(distinct s.agent_key) as subscribers,
         (select count(*) from public.company_event e
           where e.event_type = s.event_type) as events_ever,
         (select count(*) from public.company_event e
           where e.event_type = s.event_type
             and e.occurred_at > now() - '24:00:00'::interval) as events_24h,
         (select count(*) from public.event_delivery d
           where d.event_type = s.event_type) as deliveries,
         case
           when (select count(*) from public.company_event e
                  where e.event_type = s.event_type) = 0 then 'NO_EVENTS_EVER'::text
           when (select count(*) from public.event_delivery d
                  where d.event_type = s.event_type) = 0 then 'UNDELIVERED'::text
           else 'LIVE'::text
         end as state,
         -- Consolidated business episodes rooted in this event type, and how many of them are
         -- still open. event_rollup.event_type is the ROOT type of the correlation, which is what
         -- makes this answerable per subscribed type at all.
         (select count(*) from public.event_rollup r
           where r.event_type = s.event_type) as chains,
         (select count(*) from public.event_rollup r
           where r.event_type = s.event_type
             and r.outcome in ('open','partial')) as chains_open
    from public.event_subscription s
   where s.active
   group by s.event_type
   order by s.event_type;

-- ══ 2 · fn_event_consolidate · the consolidation reads what each OS assessed ══════════════════
-- Unchanged from bus_contract_close.sql except for the two reads described above.
create or replace function public.fn_event_consolidate()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  r record; v_outcome text; v_note text; v_backbone text; v_lesson bigint; v_sev text;
  n_closed int := 0; n_lessons int := 0; n_rollups int := 0; n_priorities int := 0;
  v_open_chains bigint := 0;
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
  --
  -- LINK 4 IS READ HERE.  Each OS records an event_assessment — severity, impact, proposed action
  -- — before it raises a task, and until now nothing ever looked at one.  The episode's assessed
  -- severity travels with the consolidation into priority_note and into the priority.updated
  -- payload, so what the OSes said about impact reaches the person re-prioritising on it.
  for r in
    select e.correlation_id,
           min(e.id)                                        as root_event_id,
           (array_agg(e.event_type order by e.id))[1]       as root_type,
           count(distinct d.os_key)                         as os_count,
           count(d.task_id)                                 as tasks_total,
           count(*) filter (where d.closed_at is not null)   as tasks_closed,
           (select count(*) from event_assessment a
              join company_event ae on ae.id = a.event_id
             where ae.correlation_id = e.correlation_id)     as assessed,
           (select max(case a.severity when 'high' then 3 when 'medium' then 2 else 1 end)
              from event_assessment a
              join company_event ae on ae.id = a.event_id
             where ae.correlation_id = e.correlation_id)     as sev_rank
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
    v_sev := case r.sev_rank when 3 then 'high' when 2 then 'medium' when 1 then 'low'
                             else 'unassessed' end;
    v_note := format('%s across %s OS: %s of %s task(s) closed. Impact: %s assessment(s), highest severity %s.',
                     r.root_type, r.os_count, r.tasks_closed, r.tasks_total,
                     coalesce(r.assessed,0), v_sev);

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
                                   'assessments', coalesce(r.assessed,0), 'max_severity', v_sev,
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
  -- chains_open is the consolidation backlog the view now carries: episodes that reached an OS
  -- and have not finished.  Reported here so the number lands in agent_runs rather than only in
  -- the view definition.
  select coalesce(string_agg(event_type || ' ' || state, ', ' order by event_type),
                  'every subscribed event type is LIVE')
    into v_backbone
    from v_event_backbone where state <> 'LIVE';

  select coalesce(sum(chains_open), 0) into v_open_chains from v_event_backbone;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('event_consolidate', now(), now(), 'ok',
          jsonb_build_object('deliveries_closed', n_closed, 'lessons', n_lessons,
                             'rollups', n_rollups, 'priorities_emitted', n_priorities,
                             'chains_open', v_open_chains),
          'Cross-OS contract closed: ' || n_closed || ' delivery result(s) returned, ' || n_lessons
          || ' lesson(s) captured, ' || n_rollups || ' chain(s) consolidated, ' || n_priorities
          || ' re-prioritisation(s) emitted, ' || v_open_chains || ' episode(s) still open. '
          || 'Bus backbone: ' || v_backbone);

  return jsonb_build_object('deliveries_closed', n_closed, 'lessons', n_lessons,
                            'rollups', n_rollups, 'priorities_emitted', n_priorities,
                            'chains_open', v_open_chains, 'bus_backbone', v_backbone);
end $function$;
