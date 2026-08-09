-- ROW #3 s38 — the operating manual documents a quarter of the company and calls itself complete.
-- 
-- ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
--   s38-manual-self-documenting  MISSING  1 of 4 documented categories; missing: policies,
--                                         decision rules, departments
-- 
--   undocumented, counted directly against v_operating_manual and os_runbooks:
--     workflow            0 of 14
--     governance_policy  16 of 16
--     decision_policy    27 of 27
--     org_departments     3 of 13
-- 
-- ── THE CAUSE IS THE VIEW, NOT THE CONTENT ──────────────────────────────────────────────────────
-- Nothing is missing from the company. governance_policy holds sixteen written policies with their
-- rule, their enforcement and the department that owns them; decision_policy holds twenty-seven
-- decision rules with a description and a live value; org_departments holds thirteen departments
-- with a charter and a north star. v_operating_manual unions four sources — operating_system,
-- workflow, priority_hierarchy and cron_registry — and opens none of those three.
-- 
-- So this is the row's own defect in its purest form: written down, and read by nothing. The fix
-- is three UNION ALL branches over tables that are already populated. No text is authored here; a
-- policy's summary is the rule as it is stored, a department's summary is its charter as it is
-- stored. Nothing is invented, because inventing manual entries to satisfy a manual check would be
-- the exact fraud the check exists to catch.
-- 
-- `key` and `title` coincide for a governance policy because the table names it once —
-- governance_policy.policy IS "No fabricated facts", and giving it a second, prettier name here
-- would be this file writing documentation rather than exposing it.
-- 
-- ── THE OTHER LEG WAS ALREADY GREEN ─────────────────────────────────────────────────────────────
-- The check also asks that the manual REACH a surface. fn_ws_company_os already carries the 81
-- runbooks into the browser payload — verified before this was written — so this change is the
-- whole remaining distance.
-- 
-- The view is read from the live database and appended to, with its existing text untouched, so
-- the four branches that already work stay byte-identical. CREATE OR REPLACE VIEW cannot rename or
-- reorder columns; adding UNION ALL branches leaves the column list alone, which is why the change
-- takes this shape rather than editing the select list.

create or replace view public.v_operating_manual as
 SELECT 'operating_system'::text AS section,
    o.os_key AS key,
    o.name AS title,
    o.mission AS summary,
    jsonb_build_object('purpose', o.charter, 'mandate', o.mandate, 'owner', o.owner_agent, 'adapts_by', o.adapts_by, 'departments', ( SELECT jsonb_agg(d.dept_key) AS jsonb_agg
           FROM os_department d
          WHERE d.os_key = o.os_key), 'owns', ( SELECT jsonb_agg(r.responsibility) AS jsonb_agg
           FROM os_responsibility r
          WHERE r.os_key = o.os_key), 'inputs', ( SELECT jsonb_agg(i.kind) AS jsonb_agg
           FROM os_interface i
          WHERE i.os_key = o.os_key AND i.direction = 'input'::text), 'outputs', ( SELECT jsonb_agg(i.kind) AS jsonb_agg
           FROM os_interface i
          WHERE i.os_key = o.os_key AND i.direction = 'output'::text), 'workflows', ( SELECT jsonb_agg(w.workflow_key) AS jsonb_agg
           FROM workflow w
          WHERE w.os_key = o.os_key), 'objectives', ( SELECT jsonb_object_agg(z.horizon, z.objective) AS jsonb_object_agg
           FROM ( SELECT DISTINCT ON (ob.horizon) ob.horizon,
                    ob.objective
                   FROM os_objective ob
                  WHERE ob.os_key = o.os_key
                  ORDER BY ob.horizon, ob.id) z)) AS detail
   FROM operating_system o
  WHERE o.active
UNION ALL
 SELECT 'workflow'::text AS section,
    w.workflow_key AS key,
    w.name AS title,
    w.description AS summary,
    jsonb_build_object('os', w.os_key, 'trigger', w.trigger_event, 'steps', ( SELECT jsonb_agg(jsonb_build_object('n', s.step_no, 'step', s.step, 'actor', s.actor_role, 'gate', s.gate) ORDER BY s.step_no) AS jsonb_agg
           FROM workflow_step s
          WHERE s.workflow_key = w.workflow_key)) AS detail
   FROM workflow w
UNION ALL
 SELECT 'policy'::text AS section,
    'priority_'::text || priority_hierarchy.rank::text AS key,
    priority_hierarchy.principle AS title,
    priority_hierarchy.meaning AS summary,
    jsonb_build_object('rank', priority_hierarchy.rank, 'overrides_below', priority_hierarchy.overrides_below) AS detail
   FROM priority_hierarchy
UNION ALL
 SELECT 'scheduled_job'::text AS section,
    cron_registry.jobname AS key,
    cron_registry.human_name AS title,
    cron_registry.purpose AS summary,
    jsonb_build_object('category', cron_registry.category) AS detail
   FROM cron_registry
UNION ALL
 -- SIXTEEN WRITTEN POLICIES THE MANUAL NEVER OPENED. The rule, the enforcement and the owning
 -- department are stored on the row; this exposes them, it does not compose them.
 SELECT 'governance_policy'::text AS section,
    gp.policy AS key,
    gp.policy AS title,
    gp.rule AS summary,
    jsonb_build_object('domain', gp.domain, 'enforced_by', gp.enforced_by,
                       'enforcement', gp.enforcement, 'owner_dept', gp.owner_dept) AS detail
   FROM governance_policy gp
UNION ALL
 -- TWENTY-SEVEN DECISION RULES, each with the live value it is currently set to. The title is the
 -- key made readable; the meaning is the description exactly as the row carries it.
 SELECT 'decision_rule'::text AS section,
    dp.key AS key,
    initcap(replace(dp.key, '_', ' ')) AS title,
    dp.description AS summary,
    jsonb_build_object('value', dp.value, 'updated_at', dp.updated_at) AS detail
   FROM decision_policy dp
UNION ALL
 -- THIRTEEN ACTIVE DEPARTMENTS. Ten were reachable only because their key happened to appear in
 -- some other entry's title; three appeared nowhere at all.
 SELECT 'department'::text AS section,
    d.dept_key AS key,
    d.name AS title,
    d.charter AS summary,
    jsonb_build_object('north_star', d.north_star, 'lead_agent', d.lead_agent,
                       'brain_agent', d.brain_agent, 'health_fn', d.health_fn) AS detail
   FROM org_departments d
  WHERE COALESCE(d.active, true);
