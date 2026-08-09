-- fn_ws_live_company — what the company is doing right now, and where it is going.
--
-- Three requirements, three stores that reached no surface:
--
--   vision_horizon   3 rows, zero browser-reachable readers. A long-horizon goal question
--                    ("where are we going, and how do we get there?") had nothing to answer from.
--   review_chain     1,093 rows and event_delivery 1,194 — work genuinely passing between
--                    departments, hop by hop, and no screen ever drew the sequence.
--   risk_register    19 rows, zero reachable readers.
--
-- THE GOAL PATH IS A SEQUENCE OF STEPS, not a statement. Each horizon year is a milestone, and the
-- goals owned inside it are its steps, so the answer to "how do we get there" is the ladder rather
-- than the slogan.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_ws_live_company.sql --promote
create or replace function public.fn_ws_live_company()
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_catalog'
as $function$
  select jsonb_build_object(

    -- ── THE PATH: milestone by milestone, with the steps inside each ─────────────────────────
    'goal_path', coalesce((select jsonb_agg(jsonb_build_object(
        'milestone', v.label, 'year_no', v.year_no, 'statement', v.statement,
        'steps', (select coalesce(jsonb_agg(jsonb_build_object(
                     'step', g.goal, 'metric', g.metric, 'target', g.target_value,
                     'unit', g.unit, 'owner_dept', g.owner_dept,
                     'actual', (select p.actual_value from public.goal_period p
                                 where p.goal_key = g.key order by p.updated_at desc limit 1))
                   order by g.sort nulls last), '[]'::jsonb)
                   from public.company_goals g
                  where g.active and coalesce(g.horizon, 'year_' || v.year_no::text) ~* ('year_?' || v.year_no::text)))
      order by v.year_no)
      from public.vision_horizon v where v.active), '[]'::jsonb),
    'roadmap_summary', (select count(*) from public.vision_horizon where active),

    -- ── THE HANDOFF CHAIN: work passing from department to department ────────────────────────
    'handoff_chain', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'subject_type', c.subject_type, 'subject_id', c.subject_id,
        'from_dept', c.dept_key, 'hop', c.stage, 'author_agent', c.author_agent,
        'to_dept', (select g.department from public.org_agents g where g.agent_key = c.reviewer_agent limit 1),
        'reviewer_agent', c.reviewer_agent, 'decision', c.decision,
        'reason', left(coalesce(c.reason, ''), 200), 'confidence', c.confidence,
        'delegated_from', c.delegated_from, 'at', c.created_at)
      order by c.created_at desc)
      from (select * from public.review_chain order by created_at desc limit 25) c), '[]'::jsonb),
    'handoffs_total', (select count(*) from public.review_chain),
    'handoff_stages', coalesce((select jsonb_agg(jsonb_build_object('hop', s.stage, 'n', s.n) order by s.n desc)
      from (select stage, count(*) n from public.review_chain group by 1) s), '[]'::jsonb),

    -- Where an event actually landed, which is the other half of the same sequence.
    'event_delivery', coalesce((select jsonb_agg(jsonb_build_object(
        'event_type', e.event_type, 'to_dept', (select g.department from public.org_agents g where g.agent_key = e.agent_key limit 1),
        'agent_key', e.agent_key, 'os_key', e.os_key, 'delivered_at', e.delivered_at,
        'unroutable_reason', e.unroutable_reason) order by e.delivered_at desc)
      from (select * from public.event_delivery order by delivered_at desc limit 15) e), '[]'::jsonb),

    -- ── THE RISK REGISTER ────────────────────────────────────────────────────────────────────
    'risk_register', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'risk', r.risk, 'category', r.category, 'dept_key', r.dept_key,
        'probability', r.probability, 'impact', r.impact, 'owner_agent', r.owner_agent,
        'mitigation', left(coalesce(r.mitigation, ''), 240), 'status', r.status,
        'review_due', r.review_due)
      -- probability and impact are TEXT on this table, not numbers, so they cannot be multiplied
      -- into a score here. Ordered by review urgency instead, and both values travel to the screen.
      order by r.review_due nulls last, r.updated_at desc nulls last)
      from public.risk_register r where coalesce(r.status, '') <> 'closed'), '[]'::jsonb),

    -- ── INFRASTRUCTURE, the last twin class with no reader ───────────────────────────────────
    -- edge_health_probe is the thirteenth twin object class and the only one nothing the browser
    -- can reach had ever read, so the founder's twin was complete except for the machine it runs on.
    'infrastructure', jsonb_build_object(
      'probes', (select count(*) from public.edge_health_probe),
      'rows', coalesce((select jsonb_agg(to_jsonb(p) order by p.id desc)
        from (select * from public.edge_health_probe order by id desc limit 12) p), '[]'::jsonb)),

    -- ── DEPARTMENT HEALTH, for the twin ──────────────────────────────────────────────────────
    'department_health', coalesce((select jsonb_agg(jsonb_build_object(
        'dept_key', h.dept_key, 'department', h.department, 'score', h.score,
        'status', h.status, 'basis', h.basis) order by h.score nulls first)
      from public.v_department_health h), '[]'::jsonb),

    'generated_at', now()
  );
$function$;
