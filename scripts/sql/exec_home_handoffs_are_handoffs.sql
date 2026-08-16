-- ---------------------------------------------------------------------------------------------
-- "AI collaboration 26 handoffs/24h" WAS COUNTING EVENT DELIVERIES.
--
-- Measured on htdblwldjkcgjvmqkbeh, 16 Aug 2026 03:53 UTC, all three at the same instant:
--
--   rows the strip called "handoffs"            26   (count(*) from event_delivery, 24h)
--   actual handoff runs (phase_c_handoff_run)    0   (total, not just 24h)
--   handoff contracts (handoff_contract)         0
--
-- A handoff is one employee formally passing accountable work to another: a packet, acceptance
-- criteria, a return owner, an SLA. That is phase_c_handoff_run, and it has never been exercised.
-- event_delivery is message plumbing - a row per event delivered to a subscriber. Publishing
-- plumbing volume under a label that says departments are collaborating is the
-- "instrument reporting on the wrong subject" defect, and it is the only figure on the founder's
-- strip that is actively misleading rather than merely under-explained.
--
-- Both facts stay in the payload under names that say what they are:
--   handoffs_24h          -> phase_c_handoff_run opened in the last 24h. Reads 0 today.
--   events_delivered_24h  -> what handoffs_24h used to be. Unchanged number, honest name.
--
-- handoffs_24h dropping 26 -> 0 will read as a regression on the screen. It is not one: nothing
-- broke, the figure simply started measuring the thing it is named after. Nothing is fabricated to
-- soften it, and no threshold was moved to keep a tile green.
--
-- Only these two keys changed from exec_home_stops_scoring_the_unmeasured.sql.
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
    -- THE FOUNDER WAS BEING SHOWN 98% GOAL PROGRESS ON A DAY WITH AED 0 REVENUE AND 0 CUSTOMERS.
    --
    -- This CTE reimplemented fn_goal_attainment and got it wrong four ways:
    --   1. least(100.0, NULL) returns 100.0 in Postgres - least() ignores nulls. 115 of the 122
    --      goal_period rows carry a target and NO actual_value, so every unmeasured goal scored a
    --      perfect 100 and pulled the average UP. Measured on the same rows: 98.0 published,
    --      65.3 honest. For the current period alone: 50.0 from 2 measured of 61.
    --   2. It ignored company_goals.direction, scoring an 'at_most' goal as if it were 'at_least',
    --      so a cost goal that overshot still read as progress.
    --   3. It averaged every period_label of the horizon together - two months at once.
    --   4. count(*) was published as 'goal_count', so 122 goal_period ROWS read as 122 goals.
    --
    -- fn_goal_attainment already handles all four, and its own comment
    -- ("NOT least(100, ...): least() ignores nulls, so an unmeasured goal scored 100%") exists
    -- because this exact bug was found and fixed THERE and not HERE. One copy, not two.
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
  )
  select jsonb_build_object(
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
    -- THE RULE THIS SESSION ADOPTED: no surface publishes a percentage without the coverage it
    -- rests on. "50%" and "50% across 2 measured goals of 61" are different facts, and only the
    -- second one is safe to act on. The reader decides what to render; it can no longer be
    -- unaware of the denominator.
    'goal_measured',    (select measured from g),
    'customers_active', (select count(*) from public.customers where coalesce(banned, false) = false),
    'suppliers_active', coalesce((public.fn_marketplace_analytics()->>'active_suppliers_30d')::int, 0),
    'employees',        (select count(*) from public.org_agents where active),
    -- COUNTED CRON JOBS AND CALLED THEM EMPLOYEES (10 Aug 2026).
    -- This was count(distinct agent) from agent_runs with NO JOIN TO org_agents, and agent_runs is
    -- the cron and job log: 111 distinct agent values over 30 days, only NINE of them employee keys.
    -- An employee works in three places and agent_runs is the one they use least: agent_memory
    -- (a recorded thought), agent_chats (a reasoning turn), agent_runs (a run). Any of the three
    -- counts, and the count is over org_agents so a cron can never be mistaken for a colleague.
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
    -- HANDOFFS ARE HANDOFFS (16 Aug 2026). See the header. phase_c_handoff_run is the only table
    -- where one employee formally accepts accountable work from another; event_delivery is the
    -- message bus. They are published separately because they are separate facts, and collapsing
    -- them is how 0 read as 26.
    'handoffs_24h', (select count(*) from public.phase_c_handoff_run
                      where opened_at > now() - interval '24 hours'),
    'events_delivered_24h', (select count(*) from public.event_delivery
                              where delivered_at > now() - interval '24 hours'),
    'knowledge_revisions_7d', (select count(*) from public.kb_revisions
                                where created_at > now() - interval '7 days'),
    'uptime_pct_24h', (select round(100.0 * count(*) filter (where verdict = 'ALIVE')
                                    / nullif(count(*), 0), 1)
                         from public.edge_health_probe where checked_at > now() - interval '24 hours'),
    -- THE WORKING COMPANY. Added 10 Aug 2026 because seven of the nine business tiles can only be
    -- non-zero once the marketplace transacts, and meanwhile the founder was shown nothing of the
    -- 20,470 leads, 18,000+ runs and 800+ events that already exist.
    'leads_total',      (select count(*) from public.leads),
    'agent_runs_24h',   (select count(*) from public.agent_runs where started_at > now() - interval '24 hours'),
    'events_24h',       (select count(*) from public.company_event where occurred_at > now() - interval '24 hours'),
    'decisions_open',   (select count(*) from public.agent_actions where status in ('pending','needs_review')),
    'tasks_open',       (select count(*) from public.org_tasks where status not in ('done','cancelled')),
    'generated_at',     now()
  );
$function$;
