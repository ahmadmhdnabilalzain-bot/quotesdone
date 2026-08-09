-- fn_ws_exec_home — the Executive Home, server side.
--
-- Screen 1 of the executive-UI spec: "logging in lands on a live company state, not a menu tree."
-- Production computes every one of these figures nightly and hands the browser NONE of them: the
-- landing screen renders zero company figures, and ten separate requirements fail on that one fact.
--
-- Every figure below is taken from the routine or view that already owns it, never recomputed with
-- a second definition — a landing screen that disagrees with the Finance module is worse than a
-- landing screen with nothing on it:
--
--   health_index / mood      fn_health_index()          the company health index and its band
--   revenue_today/_30d       transactions.reveal_fee    the same definition fn_company_snapshot uses
--   goal_progress_pct        goal_period               refreshed daily at 02:45 by the goal cron
--   customers_active         customers
--   suppliers_active         fn_marketplace_analytics()  same figure the Analytics module shows
--   employees / _working     org_agents + agent_runs    active headcount, and how many ran in 24h
--   bottlenecks              v_resource_pressure        real capacity pressure, per owning department
--   departments              fn_agents_board()          per-department run counts, already computed
--
--   node scripts/apply_sql.mjs scripts/sql/fn_ws_exec_home.sql --promote
create or replace function public.fn_ws_exec_home()
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_catalog'
as $function$
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
    'generated_at',     now()
  );
$function$;
