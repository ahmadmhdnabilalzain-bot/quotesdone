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
    -- COUNTED CRON JOBS AND CALLED THEM EMPLOYEES (10 Aug 2026).
    -- This was count(distinct agent) from agent_runs with NO JOIN TO org_agents, and agent_runs is
    -- the cron and job log: 111 distinct agent values over 30 days, only NINE of them employee keys.
    -- Measured on production the moment it was found: this key reported 54 against an 'employees'
    -- key of 66, so the founder's landing screen said 82% of the workforce was working. Nine of
    -- those 54 were employees. The honest figure was THIRTEEN.
    --
    -- The same table, read the same wrong way, was simultaneously telling the founder the opposite
    -- in fn_evolution_scan: "57 of 66 employees are dormant", i.e. nine working. One screen said 54,
    -- one proposal said 9, and the answer is 13. Both are fixed to the same definition.
    --
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
