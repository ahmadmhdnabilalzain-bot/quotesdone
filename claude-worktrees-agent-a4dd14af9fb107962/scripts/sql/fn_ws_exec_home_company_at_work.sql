-- Five more figures for the Command Center, and the reason they are needed.
--
-- The founder opened the OS on 10 Aug 2026 and said it "looks extremely basic still. Definitely
-- not what I was expecting." Measured, his landing screen renders nine tiles of which SEVEN are
-- zero or a dash, because seven of them describe a marketplace that has never transacted:
--
--   revenue_today 0 · revenue_30d 0 · customers_active 0 · suppliers_active 0 · pipeline all zero
--
-- That is the screen being honest, not broken. But the company IS working, and the same function
-- already computes proof of it that the screen never shows:
--
--   handoffs_24h 241 · workflow_runs_24h 76 · knowledge_revisions_7d 1,754 · uptime_pct_24h 96.4
--
-- Those four were added under a comment reading "FOUR BOARDS THAT WERE MEASURED CONSTANTLY AND
-- SHOWN NOWHERE" — and then the Overview component never rendered them. The same defect the whole
-- Row #3 spec exists to catch, one layer further up: computed, returned over the API, and still
-- not on a screen.
--
-- These five add the rest of the working company, each from the table that owns it:
--   leads_total       20,470 sourced suppliers — the largest real asset the company holds
--   agent_runs_24h    what the workforce actually did today
--   events_24h        the company's own nervous system
--   decisions_open    the review queue, which is where autonomy is actually blocked
--   tasks_open        open org_tasks
--
-- Additive only: every existing key keeps its name, type and meaning, so nothing that reads this
-- endpoint can break. CREATE OR REPLACE preserves the ACL.
create or replace function public.fn_ws_exec_home()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public', 'pg_catalog'
as $function$
  with h as (select to_jsonb(public.fn_health_index()) j),
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
    'handoffs_24h', (select count(*) from public.event_delivery
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

revoke execute on function public.fn_ws_exec_home() from public, anon, authenticated;
