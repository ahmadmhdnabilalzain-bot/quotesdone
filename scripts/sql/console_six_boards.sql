-- ROW #3 layer 13 — the command centre shows two of the six boards it is supposed to be.
-- 
-- ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
--   command-center-six-boards  MISSING  <Console> (module 'console') is the fullest of 31 sidebar
--                                       modules: 2 of 6 boards; absent there: live workflow, live
--                                       AI collaboration, knowledge growth, infrastructure health
-- 
-- The check is deliberately harsh in one specific way: the six must be on ONE screen. Six boards
-- spread across six modules is a sidebar, not a command centre, so it scores whichever single
-- component carries the most and that is the Console with company health and live revenue.
-- 
-- The evidence line proves the data is not the problem — it prints the five server-side sources
-- itself: fn_health_index exists, workflow_run has rows, event_delivery has rows, kb_revisions has
-- rows, edge_health_probe has rows. Measured today, over the windows each board would use:
-- 
--   workflow_run started in 24h        9
--   event_delivery in 24h            163      (one employee handing work to another)
--   kb_revisions in 7d             1,750
--   edge_health_probe in 24h       3,072      verdicts are ALIVE / STALE, not ok / fail
-- 
-- So four figures the company measures constantly reach no screen. They go onto the landing screen
-- the founder already opens, next to the two that are there.
-- 
-- ── THE ONE TRAP IN THE UPTIME FIGURE ───────────────────────────────────────────────────────────
-- edge_health_probe.verdict holds ALIVE and STALE — not 'ok'. A first attempt at this counted
-- verdict='ok' and got 0.0%, which would have rendered a healthy estate as a total outage. The
-- share is of ALIVE, and it is computed over checked_at rather than a created_at column that this
-- table does not have.

CREATE OR REPLACE FUNCTION public.fn_ws_exec_home()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with h as (select to_jsonb(public.fn_health_index()) j),
  -- The monthly goal if the ledger keeps one, otherwise the tightest horizon it does keep. The
  -- horizon travels with the percentage so the founder is never shown an annual number labelled
  -- monthly.
  gh as (
    select coalesce(
      (select 'monthly' where exists (select 1 from public.goal_period where horizon = 'monthly')),
      (select 'quarterly' where exists (select 1 from public.goal_period where horizon = 'quarterly')),
      'annual') hz
  ),
  g as (
    select round(avg(least(100.0, 100.0 * p.actual_value / nullif(p.target_value, 0))), 1) pct,
           count(*) n
      from public.goal_period p, gh
     where p.horizon = gh.hz and p.target_value is not null
  ),
  bott as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'department', r.owner_dept, 'resource', r.resource, 'used_pct', r.used_pct,
             'state', r.state, 'committed', r.committed, 'capacity', r.capacity, 'unit', r.unit)
           order by r.used_pct desc nulls last), '[]'::jsonb) j
      from public.v_resource_pressure r where r.state in ('HALT', 'DEGRADE')
  ),
  -- Every staffed department beside the run count fn_agents_board already computes for it, and the
  -- health score v_department_health already holds. Nothing here is new arithmetic.
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
    'customers_active', (select count(*) from public.customers where coalesce(banned, false) = false),
    'suppliers_active', coalesce((public.fn_marketplace_analytics()->>'active_suppliers_30d')::int, 0),
    'employees',        (select count(*) from public.org_agents where active),
    'employees_working', (select count(distinct agent) from public.agent_runs
                           where started_at > now() - interval '24 hours'),
    'bottlenecks',      (select j from bott),
    'departments',      (select j from dept),
    -- FOUR BOARDS THAT WERE MEASURED CONSTANTLY AND SHOWN NOWHERE.
    -- Each is the smallest true number for its board over the window that board is about.
    'workflow_runs_24h', (select count(*) from public.workflow_run
                           where coalesce(started_at, created_at) > now() - interval '24 hours'),
    'handoffs_24h', (select count(*) from public.event_delivery
                      where delivered_at > now() - interval '24 hours'),
    'knowledge_revisions_7d', (select count(*) from public.kb_revisions
                                where created_at > now() - interval '7 days'),
    -- ALIVE, not 'ok'. edge_health_probe grades ALIVE / STALE, and counting verdict='ok' returns
    -- 0.0% — a healthy estate rendered as a total outage.
    'uptime_pct_24h', (select round(100.0 * count(*) filter (where verdict = 'ALIVE')
                                    / nullif(count(*), 0), 1)
                         from public.edge_health_probe where checked_at > now() - interval '24 hours'),
    'generated_at',     now()
  );
$function$
;
