-- ROW #3 mission-control-flow-animation — the ten operating systems talk to each other 932 times a
-- week and no surface has ever drawn one of those connections.
-- 
-- ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
--   mission-control-flow-animation  MISSING  3 component(s) draw connections [AreaSpark AgentsApp
--                                            MiniLine], 0 of those animate, 0 bound to a flow
-- 
-- The check's second leg — a browser-reachable reader of os_interface or event_delivery — already
-- passes (fn_event_dispatch, fn_task_lesson, fn_ws_live_company). The drawing is the whole gap.
-- 
-- ── FINDING THE FLOW WITHOUT INVENTING IT ───────────────────────────────────────────────────────
-- The obvious source is os_interface, and it does not work. The ten systems declare 16 outputs and
-- 17 inputs and the two sets are DISJOINT except for `supply.gap`, which marketplace both emits
-- and consumes. Joining outputs to inputs on event_type yields exactly ZERO cross-OS edges.
-- Writing interface rows to make that graph connect would be inventing the company's own contract
-- table to fill a picture, so it is not done here — and it is worth the founder knowing that the
-- declared interface graph does not connect, because that is a real finding about the architecture.
-- 
-- graph_edges does not help either: 608 edges across 8 relations, none of them operating_system to
-- operating_system.
-- 
-- What DOES record real flow is event_delivery — 932 deliveries in 7 days, every one of the ten
-- systems represented. It carries the CONSUMER (os_key) and the event, and company_event carries
-- the ACTOR that emitted it. Resolving the actor through org_agents.department and os_department
-- gives the producer:
-- 
--     event_delivery.os_key                                    -> the receiving OS
--     company_event.actor -> org_agents.department             -> the sending OS
--                         -> os_department.dept_key (fallback: the actor IS a department)
-- 
-- 690 of 932 resolve. knowledge->commercial 78, marketplace->commercial 66, operations->commercial
-- 58, marketplace->knowledge 51, commercial->knowledge 48. Live, dated, and none of it composed.
-- 
-- The 242 that do not resolve are emitted by `system`, `fn_os_review` and `brief` — machinery
-- rather than an operating system. They are counted and reported as unattributed rather than
-- assigned to an OS, because guessing which system a cron belongs to is the same fabrication in a
-- smaller coat.
-- 
-- ── WHY fn_ws_company_os AND NOT A NEW ROUTINE ──────────────────────────────────────────────────
-- The map screen already exists and is fed by this routine. A new routine would need a new os_api
-- action, a new classification entry and a new module for a picture that belongs on the map that
-- is already there. One key on an existing payload is the whole change.
-- 
-- The routine is 14,475 characters of SQL. It is read from the live database and patched at one
-- asserted anchor, so every other key stays byte-identical.

CREATE OR REPLACE FUNCTION public.fn_ws_company_os()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(

    -- ── THE TEN OPERATING SYSTEMS ────────────────────────────────────────────────────────────
    'operating_systems', coalesce((select jsonb_agg(jsonb_build_object(
        'os_key', o.os_key, 'num', o.num, 'name', o.name, 'mission', o.mission,
        'charter', o.charter, 'mandate', o.mandate, 'owner_agent', o.owner_agent,
        'health_score', o.health_score, 'last_health_at', o.last_health_at, 'active', o.active,
        'responsibilities', (select coalesce(jsonb_agg(r.responsibility order by r.responsibility), '[]'::jsonb)
                               from public.os_responsibility r where r.os_key = o.os_key),
        'objectives', (select coalesce(jsonb_agg(jsonb_build_object(
                          'objective', j.objective, 'horizon', j.horizon, 'measure', j.measure,
                          'actual_value', j.actual_value) order by j.id), '[]'::jsonb)
                         from public.os_objective j where j.os_key = o.os_key and j.active),
        -- Only 4 of the 72 os_responsibility rows name a department; the rest name capabilities.
        -- So this reports the departments the OS demonstrably owns and the headcount inside THEM,
        -- rather than a company-wide headcount that would read as 0 for Leadership and be wrong.
        'owned_departments', (select coalesce(jsonb_agg(d.dept_key order by d.dept_key), '[]'::jsonb)
                                from public.org_departments d
                               where exists (select 1 from public.os_responsibility r2
                                              where r2.os_key = o.os_key and r2.responsibility = d.dept_key)),
        'staff_in_owned_departments', (select count(*) from public.org_agents a where a.active
                    and a.department in (select r2.responsibility from public.os_responsibility r2 where r2.os_key = o.os_key)))
      order by o.num) from public.operating_system o where o.active), '[]'::jsonb),

    -- ── THE COMPANY BRAIN, AS ONE GRAPH ──────────────────────────────────────────────────────
    'graph', jsonb_build_object(
      'node_count', (select count(*) from public.graph_nodes),
      'edge_count', (select count(*) from public.graph_edges),
      'rebuilt_at', (select max(updated_at) from public.graph_nodes),
      'node_kinds', coalesce((select jsonb_agg(jsonb_build_object('kind', k.kind, 'n', k.n) order by k.n desc)
                     from (select kind, count(*) n from public.graph_nodes group by 1) k), '[]'::jsonb),
      'edge_kinds', coalesce((select jsonb_agg(jsonb_build_object('rel', e.rel, 'src_kind', e.src_kind, 'dst_kind', e.dst_kind, 'n', e.n) order by e.n desc)
                     from (select rel, src_kind, dst_kind, count(*) n from public.graph_edges group by 1,2,3) e), '[]'::jsonb),
      'nodes', coalesce((select jsonb_agg(jsonb_build_object('kind', n.kind, 'ref_id', n.ref_id, 'label', n.label) order by n.kind, n.label)
                 from (select * from public.graph_nodes order by kind, label limit 200) n), '[]'::jsonb),
      'edges', coalesce((select jsonb_agg(jsonb_build_object('src_kind', g.src_kind, 'src_ref', g.src_ref, 'rel', g.rel, 'dst_kind', g.dst_kind, 'dst_ref', g.dst_ref) order by g.src_kind, g.rel)
                 from (select * from public.graph_edges order by src_kind, rel limit 300) g), '[]'::jsonb)),

    -- ── THE AI BOARD ─────────────────────────────────────────────────────────────────────────
    'board', jsonb_build_object(
      'advisors', coalesce((select jsonb_agg(jsonb_build_object(
          'advisor_key', b.advisor_key, 'name', b.name, 'lens', b.lens, 'asks', b.asks, 'weight', b.weight)
        order by b.advisor_key) from public.board_advisor b where coalesce(b.active, true)), '[]'::jsonb),
      'opinion_count', (select count(*) from public.board_opinion),
      'opinions', coalesce((select jsonb_agg(jsonb_build_object(
          'subject', p.subject, 'advisor_key', p.advisor_key, 'recommendation', p.recommendation,
          'rationale', left(p.rationale, 300), 'confidence', p.confidence, 'at', p.created_at)
        order by p.created_at desc)
        from (select * from public.board_opinion order by created_at desc limit 12) p), '[]'::jsonb)),

    -- ── THE INDICES: MATURITY, MARKETPLACE HEALTH, ORGANISATIONAL ENERGY ─────────────────────
    'indices', coalesce((select jsonb_agg(jsonb_build_object(
        'index_name', c.index_name, 'score', c.score, 'band', c.band,
        'measured_on', c.measured_on, 'dimensions', c.dimensions) order by c.index_name)
      from public.company_index c
      where c.measured_on = (select max(measured_on) from public.company_index c2 where c2.index_name = c.index_name)), '[]'::jsonb),
    'marketplace_health', (select jsonb_build_object('score', c.score, 'band', c.band, 'measured_on', c.measured_on, 'dimensions', c.dimensions)
        from public.company_index c where c.index_name = 'marketplace_health'
        order by c.measured_on desc, c.id desc limit 1),

    -- ── EXECUTIVE REPLAY ─────────────────────────────────────────────────────────────────────
    'replay', jsonb_build_object(
      'days_on_file', (select count(*) from public.company_snapshot),
      'newest', (select max(snapshot_on) from public.company_snapshot),
      'company_snapshot', coalesce((select jsonb_agg(jsonb_build_object('snapshot_on', s.snapshot_on, 'state', s.state) order by s.snapshot_on desc)
        from (select * from public.company_snapshot order by snapshot_on desc limit 8) s), '[]'::jsonb)),

    -- ── REPUTATION ───────────────────────────────────────────────────────────────────────────
    'reputation', jsonb_build_object(
      'graded', (select count(*) from public.agent_reputation),
      'by_tier', coalesce((select jsonb_agg(jsonb_build_object('tier', t.tier, 'n', t.n) order by t.n desc)
                   from (select coalesce(tier, 'ungraded') tier, count(*) n from public.agent_reputation group by 1) t), '[]'::jsonb),
      'rows', coalesce((select jsonb_agg(jsonb_build_object(
          'agent_key', r.agent_key, 'score', r.score, 'tier', r.tier, 'correctness', r.correctness,
          'reliability', r.reliability, 'cost_efficiency', r.cost_efficiency,
          'learning_speed', r.learning_speed, 'collaboration', r.collaboration)
        order by r.score desc nulls last)
        from (select * from public.agent_reputation order by score desc nulls last limit 20) r), '[]'::jsonb)),

    -- ── STRUCTURAL PROPOSALS AND THE LESSON LEDGER ───────────────────────────────────────────
    'evolution_proposals', coalesce((select jsonb_agg(jsonb_build_object(
        'id', e.id, 'trigger_kind', e.trigger_kind, 'subject', e.subject,
        'observation', left(e.observation, 240), 'proposal', left(e.proposal, 240),
        'change_class', e.change_class, 'status', e.status, 'decided_by', e.decided_by, 'at', e.created_at)
      order by e.created_at desc)
      from (select * from public.evolution_proposal order by created_at desc limit 12) e), '[]'::jsonb),
    -- THE FOUR STRATEGIC QUEUES, named by their own tables so the screen and the store cannot drift
    -- apart: evolution_proposal, challenge_record, opportunity and board_opinion. The spec's
    -- "strategic decisions rather than operational tasks" is exactly this set against the pending
    -- agent_actions queue the founder was being shown instead.
    'strategic_queues', jsonb_build_object(
      'evolution_proposal', (select count(*) from public.evolution_proposal where status = 'proposed'),
      'challenge_record', (select count(*) from public.challenge_record where responded_at is null),
      'opportunity', (select count(*) from public.opportunity where status = 'open'),
      'board_opinion', (select count(*) from public.board_opinion),
      'operational_pending', (select count(*) from public.agent_actions where status in ('pending','needs_review'))),
    'opportunity', coalesce((select jsonb_agg(jsonb_build_object(
        'id', o.id, 'kind', o.kind, 'title', o.title, 'detail', left(o.detail, 240),
        'value_score', o.value_score, 'effort', o.effort, 'confidence', o.confidence, 'at', o.created_at)
      order by o.value_score desc nulls last)
      from (select * from public.opportunity where status = 'open'
             order by value_score desc nulls last limit 10) o), '[]'::jsonb),

    -- The AI disagreeing with the founder, and what it offered instead. 47 challenges on file, 31
    -- carrying alternatives, and no surface has ever shown one.
    'challenge_record', coalesce((select jsonb_agg(jsonb_build_object(
        'id', h.id, 'proposal', h.proposal, 'proposed_by', h.proposed_by, 'challenged_by', h.challenged_by,
        'stance', h.stance, 'confidence', h.confidence, 'reasoning', left(h.reasoning, 320),
        'alternatives', h.alternatives, 'violates_principle', h.violates_principle,
        'violates_rank', h.violates_rank, 'founder_response', h.founder_response,
        'responded_at', h.responded_at, 'at', h.created_at)
      order by h.created_at desc)
      from (select * from public.challenge_record order by created_at desc limit 12) h), '[]'::jsonb),

    'institutional_memory', jsonb_build_object(
      'lessons', (select count(*) from public.institutional_memory),
      'rows', coalesce((select jsonb_agg(jsonb_build_object(
          'kind', m.kind, 'headline', m.headline, 'outcome', m.outcome, 'lesson', left(m.detail, 240),
          'os_key', m.os_key, 'confidence', m.confidence, 'occurred_at', m.occurred_at)
        order by m.occurred_at desc nulls last)
        from (select * from public.institutional_memory order by occurred_at desc nulls last limit 12) m), '[]'::jsonb)),

    -- ── RESILIENCE ───────────────────────────────────────────────────────────────────────────
    'resilience', jsonb_build_object(
      'critical_capability', coalesce((select jsonb_agg(jsonb_build_object(
          'capability_key', c.capability_key, 'capability', c.capability, 'owner_dept', c.owner_dept,
          'test_kind', c.test_kind, 'last_verdict', c.last_verdict, 'last_checked', c.last_checked)
        order by c.capability_key) from public.critical_capability c), '[]'::jsonb),
      'continuity_plan', coalesce((select jsonb_agg(jsonb_build_object(
          'service', p.service, 'criticality', p.criticality, 'failure_mode', p.failure_mode,
          'fallback', p.fallback, 'recovery', p.recovery, 'rto_minutes', p.rto_minutes,
          'owner_agent', p.owner_agent, 'last_tested', p.last_tested)
        order by p.criticality, p.service) from public.continuity_plan p), '[]'::jsonb)),

    -- ── THE OPERATING MANUAL ─────────────────────────────────────────────────────────────────
    'operating_manual', jsonb_build_object(
      'runbooks', (select count(*) from public.os_runbooks),
      'by_category', coalesce((select jsonb_agg(jsonb_build_object('category', k.category, 'n', k.n) order by k.n desc)
                      from (select coalesce(category, 'uncategorised') category, count(*) n from public.os_runbooks group by 1) k), '[]'::jsonb),
      'rows', coalesce((select jsonb_agg(jsonb_build_object(
          'slug', r.slug, 'title', r.title, 'category', r.category, 'when_to_use', left(r.when_to_use, 200), 'os_key', r.os_key)
        order by r.sort nulls last, r.slug)
        from (select * from public.os_runbooks order by sort nulls last, slug limit 24) r), '[]'::jsonb)),

    -- ── RESOURCE MOVEMENT, AUTONOMY, SUPPLY AND THE EVENT BUS ────────────────────────────────
    'allocation_change', coalesce((select jsonb_agg(jsonb_build_object(
        'resource', a.resource, 'subject', a.subject, 'from_value', a.from_value, 'to_value', a.to_value,
        'reason', left(a.reason, 200), 'policy', a.policy, 'reverted', a.reverted, 'at', a.created_at)
      order by a.created_at desc)
      from (select * from public.allocation_change order by created_at desc limit 12) a), '[]'::jsonb),
    'autonomy', jsonb_build_object(
      'changes', (select count(*) from public.autonomy_control_audit),
      'rows', coalesce((select jsonb_agg(jsonb_build_object(
          'object', u.object, 'op', u.op, 'direction', u.direction, 'old_value', u.old_value,
          'new_value', u.new_value, 'reason', left(u.reason, 160), 'at', u.at)
        order by u.at desc)
        from (select * from public.autonomy_control_audit order by at desc limit 10) u), '[]'::jsonb)),
    'supply_health', jsonb_build_object(
      'snapshots', (select count(*) from public.supply_health_snapshots),
      'latest_period_end', (select max(period_end) from public.supply_health_snapshots),
      'coverage_gaps', coalesce((select jsonb_agg(to_jsonb(s) order by s.period_end desc)
        from (select * from public.supply_health_snapshots order by period_end desc limit 6) s), '[]'::jsonb)),
    'invite_schedule', coalesce((select jsonb_agg(jsonb_build_object(
        'day', i.day, 'planned', i.planned, 'sent', i.sent, 'status', i.status) order by i.day desc)
      from (select * from public.invite_schedule order by day desc limit 10) i), '[]'::jsonb),
    'events', jsonb_build_object(
      'total', (select count(*) from public.company_event),
      'last_7d', (select count(*) from public.company_event where occurred_at > now() - interval '7 days'),
      'by_class', coalesce((select jsonb_agg(jsonb_build_object('event_type', c.event_type, 'n', c.n) order by c.n desc)
                   from (select event_type, count(*) n from public.company_event
                          where occurred_at > now() - interval '30 days' group by 1) c), '[]'::jsonb)),

    -- ── MODEL MIX ────────────────────────────────────────────────────────────────────────────
    'model_mix', coalesce((select jsonb_agg(jsonb_build_object(
        'model_used', m.model_used, 'calls', m.calls, 'aed', m.aed, 'latency_ms', m.latency_ms,
        'cache_hits', m.cache_hits) order by m.aed desc)
      from (select coalesce(nullif(model_used,''),'unknown') model_used, count(*) calls,
                   round(coalesce(sum(cost_aed),0),4) aed,
                   round(avg(latency_ms)) latency_ms,
                   count(*) filter (where cached) cache_hits
              from public.ai_cost_log where occurred_at > now() - interval '30 days' group by 1) m), '[]'::jsonb),

    -- ── INFORMATION FLOWING BETWEEN THE TEN SYSTEMS ─────────────────────────────────────────
    -- Derived from what was actually DELIVERED, not from what os_interface declares: the declared
    -- outputs and inputs are disjoint sets and join to zero cross-OS edges. The consumer is
    -- event_delivery.os_key; the producer is company_event.actor resolved through its department,
    -- or the actor itself when the actor IS a department. Deliveries whose actor is machinery
    -- (system, a cron, the brief) are counted as unattributed rather than assigned to a system.
    'flow', (with res as (
        select d.os_key as to_os, d.event_type, d.delivered_at,
               coalesce((select od.os_key from public.org_agents a
                          join public.os_department od on od.dept_key = a.department
                         where a.agent_key = e.actor limit 1),
                        (select od2.os_key from public.os_department od2
                          where od2.dept_key = e.actor limit 1)) as from_os
          from public.event_delivery d
          join public.company_event e on e.id = d.event_id
         where d.os_key is not null and d.delivered_at > now() - interval '7 days')
      select jsonb_build_object(
        'window_days', 7,
        'deliveries', (select count(*) from res),
        'attributed', (select count(*) from res where from_os is not null),
        'unattributed', (select count(*) from res where from_os is null),
        'unroutable', (select count(*) from public.event_delivery
                        where unroutable_reason is not null
                          and delivered_at > now() - interval '7 days'),
        'nodes', coalesce((select jsonb_agg(jsonb_build_object(
            'os_key', o.os_key, 'num', o.num, 'name', o.name,
            'received', (select count(*) from res where res.to_os = o.os_key),
            'sent', (select count(*) from res where res.from_os = o.os_key)) order by o.num)
          from public.operating_system o where o.active), '[]'::jsonb),
        'edges', coalesce((select jsonb_agg(x) from (
            select from_os, to_os, count(*) as n,
                   count(distinct event_type) as event_types,
                   max(delivered_at) as newest,
                   (array_agg(distinct event_type))[1:3] as kinds
              from res where from_os is not null
             group by from_os, to_os order by count(*) desc limit 40) x), '[]'::jsonb))),

    'generated_at', now()
  );
$function$
;
