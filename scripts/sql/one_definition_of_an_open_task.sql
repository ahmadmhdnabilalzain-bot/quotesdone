-- THREE COUNTS OF ONE CONCEPT BECOME ONE.
--
-- Measured in the OS on 6 Sep 2026:
--   Overview           "Open tasks 37 across every department"   fn_ws_exec_home: org_tasks not in (done, cancelled)
--   Where blocked      "Operations OS — Knowledge 94/27 open tasks"  v_resource_pressure: resource_pool.committed,
--                                                                    a number fn_os_health_brief last wrote on
--                                                                    10 Aug with status <> 'done' (so it counted
--                                                                    571 cancelled rows) and nothing refreshed since
--   Operations         "Open tasks 0"                             fn_ws_operations: crm_tasks (his to-do list)
--
-- ONE DEFINITION, IN ONE PLACE: public.v_org_open_tasks = org_tasks whose status is not 'done' and not
-- 'cancelled' (today that is 'assigned' and 'blocked'; 'in_progress' or any new working status counts
-- as open automatically — a task is open until it is finished or withdrawn). Everything that says
-- "open tasks" reads the view:
--   fn_ws_exec_home      tasks_open (+ brief_text, the overnight brief sentence — see the routine)
--   fn_ws_operations     tasks_open and the task list (org_tasks, not crm_tasks)
--   v_resource_pressure  committed for the 'open tasks' capacity rows is computed LIVE from the view
--                        per operating system, so the blocked list can never show a month-old number
--   fn_os_health_brief   the weekly refresh writes the same figure (same view) into resource_pool
--
--   node scripts/apply_sql.mjs scripts/sql/one_definition_of_an_open_task.sql --apply --ddl
begin;

create or replace view public.v_org_open_tasks as
  select t.*
    from public.org_tasks t
   where t.status not in ('done', 'cancelled');
comment on view public.v_org_open_tasks is
  'THE definition of an open task (6 Sep 2026): an org_tasks row whose status is neither done nor cancelled. '
  'Every "open tasks" figure in the OS (Overview, Operations, the blocked list / resource pressure, the '
  'weekly OS health brief, the overnight brief) counts THIS view. Do not re-derive the predicate elsewhere.';
revoke all on public.v_org_open_tasks from public, anon, authenticated;
grant select on public.v_org_open_tasks to service_role;

-- The capacity rows (unit = 'open tasks', source_ref = 'org_agents.max_open_tasks') are measured live;
-- every other pooled resource keeps the numerator fn_os_health_brief writes weekly.
create or replace view public.v_resource_pressure as
  with live as (
    select r.*,
           case when r.source_ref = 'org_agents.max_open_tasks'
                then (select count(*)::numeric from public.v_org_open_tasks t
                        join public.os_department od on od.dept_key = t.dept_key
                       where od.os_key = r.os_key)
                else r.committed end as committed_live
      from public.resource_pool r
  )
  select resource, kind, owner_dept, unit, capacity,
         committed_live as committed,
         case when capacity > 0::numeric then round(100.0 * committed_live / capacity, 1) else null::numeric end as used_pct,
         case when capacity = 0::numeric then 'UNSET'::text
              when (100.0 * committed_live / capacity) >= halt_at_pct::numeric then 'HALT'::text
              when (100.0 * committed_live / capacity) >= degrade_at_pct::numeric then 'DEGRADE'::text
              else 'OK'::text end as state,
         note
    from live;

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
    -- fn_goal_attainment handles the four ways the inline version was wrong (least() ignoring
    -- nulls, direction, period, row-count-as-goal-count). One copy, not two.
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
  ),
  fq as (select public.fn_founder_queue(1) j),
  home as (select jsonb_build_object(
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
    'goal_measured',    (select measured from g),
    'customers_active', (select count(*) from public.customers where coalesce(banned, false) = false),
    'suppliers_active', coalesce((public.fn_marketplace_analytics()->>'active_suppliers_30d')::int, 0),
    'employees',        (select count(*) from public.org_agents where active),
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
    'handoffs_24h', (select count(*) from public.phase_c_handoff_run
                      where opened_at > now() - interval '24 hours'),
    'events_delivered_24h', (select count(*) from public.event_delivery
                              where delivered_at > now() - interval '24 hours'),
    'knowledge_revisions_7d', (select count(*) from public.kb_revisions
                                where created_at > now() - interval '7 days'),
    'uptime_pct_24h', (select round(100.0 * count(*) filter (where verdict = 'ALIVE')
                                    / nullif(count(*), 0), 1)
                         from public.edge_health_probe where checked_at > now() - interval '24 hours'),
    'leads_total',      (select count(*) from public.leads),
    'agent_runs_24h',   (select count(*) from public.agent_runs where started_at > now() - interval '24 hours'),
    'events_24h',       (select count(*) from public.company_event where occurred_at > now() - interval '24 hours'),
    -- HIS decisions: refund approvals and nothing else. The 14 open agent_actions this used to
    -- count are held with their roles and reported under that name.
    'decisions_open',   public.fn_founder_refund_approvals_open(),
    'held_with_roles',  (select (j->>'held_with_roles_total')::int from fq),
    'held_with',        (select j->'held_with_roles' from fq),
    -- ONE definition of an open task: public.v_org_open_tasks (see one_definition_of_an_open_task.sql).
    'tasks_open',       (select count(*) from public.v_org_open_tasks),
    'generated_at',     now()
  ) j)
  -- THE OVERNIGHT BRIEF, AS ONE SENTENCE. Written here so the Console's "speak the overnight brief"
  -- button and the founder command channel ("status", "brief", "how are we doing") read the SAME
  -- text from the SAME figures, instead of one composing it in the browser and the other having no
  -- answer at all (6 Sep 2026: "status" came back as "clarification required").
  select h.j || jsonb_build_object('brief_text',
       'Company health ' || coalesce(h.j->>'health_index', 'unknown') || ', mood ' || coalesce(h.j->>'mood', 'unknown') || '. '
    || 'Revenue today ' || coalesce(h.j->>'revenue_today', '0') || ' dirhams, ' || coalesce(h.j->>'revenue_30d', '0') || ' over thirty days. '
    || coalesce(h.j->>'suppliers_active', '0') || ' active suppliers, ' || coalesce(h.j->>'customers_active', '0') || ' active customers. '
    || coalesce(h.j->>'employees_working', '0') || ' of ' || coalesce(h.j->>'employees', '0') || ' AI employees worked overnight. '
    || 'Goal progress ' || coalesce(h.j->>'goal_progress_pct', '0') || ' percent. '
    || coalesce(h.j->>'tasks_open', '0') || ' open tasks across every department. '
    || case when jsonb_array_length(coalesce(h.j->'bottlenecks', '[]'::jsonb)) > 0
            then jsonb_array_length(h.j->'bottlenecks')::text || ' departments are over capacity.'
            else 'No department is over capacity.' end)
  from home h;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_ws_operations()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with fq as (select public.fn_founder_queue(30) j)
  select jsonb_build_object(
    'ops', jsonb_build_object(
      'health', (select (kpis->>'ops_health')::numeric from ops_kpi_snapshots order by snapshot_date desc limit 1),
      'kpis', (select to_jsonb(k) from ops_kpis k),
      'recommendations', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation)) from agent_actions where agent='operations_ai' and status in ('pending','needs_review')),'[]'::jsonb)
    ),
    'security', jsonb_build_object(
      'score', (select (kpis->>'security_score')::numeric from security_kpi_snapshots order by snapshot_date desc limit 1),
      'kpis', (select to_jsonb(k) from security_kpis k),
      'incidents', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk)) from agent_actions where agent='security_ai' and status in ('pending','needs_review')),'[]'::jsonb),
      'events', coalesce((select jsonb_agg(jsonb_build_object('kind',kind,'severity',severity,'source',source,'at',created_at) order by created_at desc) from (select * from security_events where created_at >= public.fn_os_fresh_start_at() order by created_at desc limit 10) e),'[]'::jsonb)
    ),
    'kpis', jsonb_build_object(
      'approvals_pending', public.fn_founder_refund_approvals_open(),
      'held_with_roles', (select (j->>'held_with_roles_total')::int from fq),
      'high_risk',(select count(*) from agent_actions where status='pending' and coalesce(risk,'') in ('high','critical')),
      -- ONE definition of an open task (was: crm_tasks, the founder's own to-do list, which is 0).
      'tasks_open',(select count(*) from public.v_org_open_tasks),
      'decisions_24h',(select count(*) from decision_log where created_at > now()-interval '24 hours' and created_at >= public.fn_os_fresh_start_at()),
      'disputes',(select count(*) from transactions where coalesce(refund_status,'') in ('requested','pending'))
    ),
    -- HIS: the refund queue, verbatim from fn_founder_queue.
    'approvals', (select j->'waiting_on_you' from fq),
    -- NOT HIS: open agent_actions with the role that holds each. No approve/reject for him.
    'held', coalesce((select jsonb_agg(jsonb_build_object('id',id,'agent',agent,'kind',kind,
        'kind_label', public.fn_ui_label('action_kind', kind),
        'holder', public.fn_action_holder(kind, agent),
        'risk',risk,'title',title,
        'policies', public.fn_action_policies(kind, confidence),
        'recommendation',recommendation,'status',status,'target_table',target_table,'created_at',created_at,
        'os', public.fn_owning_os(agent), 'confidence', confidence, 'yours', false,
        'alternatives', (select d.alternatives from public.decision_log d where d.id = decision_log_id),
        'outcome', 'held with ' || public.fn_action_holder(kind, agent) || ' since ' || created_at::date)) from (
        select a.* from agent_actions a
          left join agent_action_kind_policy p on p.kind = a.kind
         where a.status in ('pending','needs_review') and coalesce(p.policy,'') <> 'founder'
           and a.created_at >= public.fn_os_fresh_start_at()
         order by (coalesce(a.risk,'')='critical') desc, a.created_at desc limit 30) a),'[]'::jsonb),
    'decisions', coalesce((select jsonb_agg(jsonb_build_object('id',id,'actor',actor,'kind',kind,'decision',decision,
        'confidence',confidence,'route_to',route_to,'created_at',created_at)) from (select * from decision_log where created_at >= public.fn_os_fresh_start_at() order by created_at desc limit 20) d),'[]'::jsonb),
    -- The company's open org_tasks, owned by their departments' agents (not his to close: no Done button).
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'status',status,'priority',priority,'due',null,
        'source', coalesce(dept_key,'—') || case when assigned_agent is not null then ' · ' || assigned_agent else '' end,
        'entity','org_task','created_at',created_at)) from (select * from public.v_org_open_tasks order by created_at desc limit 20) t),'[]'::jsonb)
  );
$function$
;

CREATE OR REPLACE FUNCTION public.fn_os_health_brief()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_period text; v_n int := 0; v_pool int := 0;
begin
  -- ---------------------------------------------------------------------------------------
  -- 1. ONE CAPACITY ROW PER ACTIVE OS, in the one unit every OS has: its own people's
  -- attention. The seed carried a single company-wide row (550 open tasks, keyed to
  -- leadership), which is why six operating systems reported no capacity at all. Both sides
  -- are measured live — org_agents.max_open_tasks is the declared ceiling, org_tasks the
  -- load — so this figure moves on its own and is falsifiable by looking at the org.
  delete from resource_pool where source_ref = 'org_agents.max_open_tasks';

  insert into resource_pool (resource, kind, owner_dept, unit, capacity, committed,
                             window_label, degrade_at_pct, halt_at_pct, source_ref, note, os_key)
  select 'Employee attention - ' || o.name, 'capacity',
         (select min(od.dept_key) from os_department od where od.os_key = o.os_key),
         'open tasks',
         coalesce((select sum(a.max_open_tasks) from os_department od
                     join org_agents a on a.department = od.dept_key and a.active
                    where od.os_key = o.os_key), 0),
         coalesce((select count(*) from os_department od
                     join public.v_org_open_tasks t on t.dept_key = od.dept_key
                    where od.os_key = o.os_key), 0),
         'rolling', 80, 100, 'org_agents.max_open_tasks',
         'Open tasks in this OS''s departments against the sum of max_open_tasks for its '
         || 'active staff. Refreshed weekly by fn_os_health_brief.', o.os_key
    from operating_system o where o.active;
  get diagnostics v_pool = row_count;

  -- 2. EVERY OTHER POOLED RESOURCE GETS A MEASURED NUMERATOR TOO. Each expression is the
  -- system of record for that resource; a resource whose consumption nothing records would
  -- otherwise sit at zero for ever and drag the OS's ratio down with it, which is the same
  -- "populated but never measured" defect one level down.
  update resource_pool rp set committed = m.v, updated_at = now()
    from (values
      ('AI token budget - company',
        (select coalesce(sum(cost_aed), 0)::numeric from ai_cost_log
          where occurred_at >= date_trunc('month', now()))),
      ('Supplier invites',
        (select coalesce(sum(sent), 0)::numeric from invite_schedule where day = current_date)),
      ('Outbound email',
        (select count(*)::numeric from notifications
          where coalesce(channel, 'email') = 'email' and created_at > now() - interval '1 day')),
      ('WhatsApp / SMS',
        (select count(*)::numeric from wa_messages where created_at > now() - interval '1 day')
      + (select count(*)::numeric from notifications
          where channel in ('sms', 'whatsapp') and created_at > now() - interval '1 day')),
      -- A FLOOR, NOT A TOTAL: this counts the scheduled invocations, which is every edge call
      -- the database itself can see. Browser and webhook traffic is not in cron.job_run_details.
      ('Edge function invocations',
        (select count(*)::numeric from cron.job_run_details d
           join cron.job j on j.jobid = d.jobid
          where j.command ~* 'net\.http_post' and d.start_time >= date_trunc('month', now()))),
      ('Database storage',
        round(pg_database_size(current_database()) / 1073741824.0, 2)::numeric),
      ('Document storage',
        (select round(coalesce(sum((o.metadata->>'size')::bigint), 0) / 1073741824.0, 2)::numeric
           from storage.objects o)),
      ('Scraping / enrichment',
        (select coalesce(sum(fetched), 0)::numeric from scrape_runs
          where created_at >= date_trunc('month', now()))),
      ('Payment processing',
        (select count(*)::numeric from transactions where revealed_at > now() - interval '1 day'))
    ) as m(resource, v)
   where rp.resource = m.resource;

  -- 3. The report is computed FROM those inputs, so recompute it now that they are current.
  -- Without this the week's capacity_pct would be derived from last Monday's numerator.
  perform fn_os_review();

  -- ---------------------------------------------------------------------------------------
  select max(period) into v_period from os_review;
  if v_period is null then
    return jsonb_build_object('written', 0, 'reason', 'os_review is empty');
  end if;

  -- Only active OSes with an ACTIVE owner: a brief addressed to a departed employee is another
  -- write with no reader, which is the defect this function exists to close.
  for r in
    select o.os_key, o.name, o.owner_agent, rv.health, rv.metrics
      from operating_system o
      join os_review rv  on rv.os_key = o.os_key and rv.period = v_period
      join org_agents  a on a.agent_key = o.owner_agent and a.active
     where o.active
     order by o.num
  loop
    -- Scoped to this function's own rows by source, so it can never touch a memory it did not
    -- write. This is what makes the weekly run idempotent instead of cumulative.
    delete from agent_memory
     where agent_key = r.owner_agent and source = 'fn_os_health_brief';

    -- ->> everywhere, never ->. text || jsonb resolves to jsonb || jsonb and silently builds an
    -- array instead of a sentence; that has already cost this project two call-time failures.
    insert into agent_memory (agent_key, kind, content, source, importance, horizon)
    values (r.owner_agent, 'os_health',
      'OS HEALTH, week ' || v_period || ' - ' || r.name || ' (' || r.os_key || '), which you own. '
      || 'HEALTH SCORE ' || coalesce(r.metrics->>'health_score', '?') || '/100 ('
        || coalesce(r.health, 'unrated') || '). '
      || 'RISK: open_risks ' || coalesce(r.metrics->>'open_risks', '0') || '. '
      || 'PERFORMANCE: kpi_gaps ' || coalesce(r.metrics->>'kpi_gaps', '0') || ' against '
        || coalesce(r.metrics->>'kpis', '0') || ' KPI(s). '
      || 'CAPACITY: capacity_pct ' || coalesce(r.metrics->>'capacity_pct', 'unmeasured') || '%. '
      || 'BACKLOG: ' || coalesce(r.metrics->>'open_tasks', '0') || ' open, stale_tasks '
        || coalesce(r.metrics->>'stale_tasks', '0') || ', backlog_per_head '
        || coalesce(r.metrics->>'backlog_per_head', '0') || '. '
      || 'QUALITY: review_pass_pct ' || coalesce(r.metrics->>'review_pass_pct', 'unmeasured') || '%. '
      || 'COST: budget_pct ' || coalesce(r.metrics->>'budget_pct', '0') || '% of the AI budget. '
      || 'AUTOMATION: needs_founder_pct ' || coalesce(r.metrics->>'needs_founder_pct', '0')
        || '% of open work still needs the founder. '
      || 'Act on the worst figure before it becomes a finding.',
      'fn_os_health_brief', 7, 'short');

    v_n := v_n + 1;
  end loop;

  return jsonb_build_object('period', v_period, 'written', v_n, 'capacity_rows', v_pool);
end
$function$
;

commit;
