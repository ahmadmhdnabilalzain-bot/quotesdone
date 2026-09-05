-- NOTHING ROUTES TO THE FOUNDER EXCEPT A STRIPE REFUND — AND SIX SURFACES SAID OTHERWISE.
--
-- 5 Sep 2026. He opened the OS and saw non-refund things "waiting for his approval". A read-only
-- audit measured why: fn_ws_exec_home (decisions_open), fn_ws_operations (approvals, kpis.
-- approvals_pending), fn_ws_governance (kpis.open_for_review via the governance_kpis view),
-- fn_ws_notifications (the bell's "important" tier), fn_ws_exec (approvals) and fn_ops_dashboard
-- (operations.escalations, read by fn_os_command) all counted RAW
-- `agent_actions where status in ('pending','needs_review')` and labelled the result his.
-- Measured at 22:31 UTC: 14 such rows — legal_flag x3 (general_counsel), security_incident x2 and
-- backup_alert x1 (cto), objective_step x5, report_recommendation x2, autonomy_stall x1 (auto).
-- Only fn_founder_queue applied agent_action_kind_policy.policy = 'founder', and NO kind carries
-- that policy, so his real queue read 0 while every other surface read 14.
--
-- decision_policy said the same wrong thing in three rows: action_autonomy marked legal_flag,
-- security_incident, customer_escalation, content_review, prompt_approval and approve_supplier as
-- "founder"; founder_review_gates listed eight gates of which six are not refunds; and
-- fn_autonomy_class hard-coded strategy_change, legal_action, partnership,
-- security_incident_executive, deletes and supplier approvals as 'founder'. phase_c_action_class
-- was already right (founder_approval_required only for refund_decision) and the two triggers on
-- founder_approval_request already refuse a non-refund request. Policy and runtime now agree.
--
-- WHAT CHANGES
--   fn_founder_refund_approvals_open()  ONE count every founder-facing surface reads: pending
--                                       founder_approval_request rows (refund-only by trigger)
--                                       plus agent_actions whose kind policy is 'founder' (0 kinds).
--   fn_action_holder(kind, agent)       who a held row belongs to: the kind's authority_role, else
--                                       the role action_autonomy names, else the lead of the
--                                       raising agent's department, else chief_of_staff.
--   fn_founder_queue                    waiting_on_you now lists the refund requests themselves
--                                       (source = founder_approval_request) and carries
--                                       held_with_roles, the non-refund rows grouped by holder.
--   fn_ws_exec_home                     decisions_open = refunds only; + held_with_roles.
--   fn_ws_operations / fn_ws_exec       approvals = the founder queue; + held (holder named,
--                                       informational); kpis.approvals_pending = refunds only.
--   fn_ws_governance                    kpis.open_for_review = refunds only; + held_with_roles;
--                                       each escalation names its holder.
--   fn_ws_notifications                 critical = founder alerts only; important = refund
--                                       approvals only; + held tier (informational).
--   fn_ops_dashboard                    operations.escalations = refunds + severe alerts.
--   fn_os_command                       every held decision names its holder.
--   fn_autonomy_class                   'founder' only for a refund/money kind; the six APV-04
--                                       gates, deletes and supplier approvals are 'keep' (held
--                                       with their role); a role name in action_autonomy = 'keep'.
--   decision_policy                     action_autonomy names the accountable role instead of
--                                       "founder"; founder_review_gates = the two refund gates;
--                                       prompt_sensitive_pattern's description says cto, not founder.
--
-- The rows themselves are NOT touched here — draining them to their owners is a separate packet.

-- ── the one count ─────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_founder_refund_approvals_open()
 returns integer
 language sql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
  select (select count(*) from public.founder_approval_request where state = 'pending')::int
       + (select count(*) from public.agent_actions a
            join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'founder'
           where a.status in ('pending','needs_review')
             and a.created_at >= public.fn_os_fresh_start_at())::int;
$function$;

-- ── who holds a non-refund row ────────────────────────────────────────────────────────────────
create or replace function public.fn_action_holder(p_kind text, p_agent text)
 returns text
 language sql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
  select coalesce(
    (select p.authority_role from public.agent_action_kind_policy p
      where p.kind = p_kind and p.authority_role is not null),
    (select d.value->>p_kind from public.decision_policy d
      where d.key = 'action_autonomy'
        and exists (select 1 from public.org_role r
                     where r.role_id = d.value->>p_kind and r.status = 'active')),
    (select od.lead_agent from public.org_agents oa
       join public.org_departments od on od.dept_key = oa.department and od.active
      where oa.agent_key = p_agent limit 1),
    'chief_of_staff');
$function$;

-- ── the founder queue: refunds, then everything else by holder ────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_founder_queue(p_limit integer DEFAULT 12)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with yours as (
    -- A refund decision prepared for him. The two triggers on founder_approval_request refuse any
    -- action class that is not founder_approval_required, and only refund_decision is.
    select 'founder_approval_request:' || a.request_id as id, 'refund_decision' as kind,
           'Refund decision' as kind_label, coalesce(a.prepared_by_role_id, 'finance') as "from",
           left(coalesce(a.amount_note, 'Refund on ' || coalesce(a.subject_ref, '?')), 160) as title,
           a.created_at as raised, 'founder_approval_request' as source, a.subject_ref, true as yours
      from public.founder_approval_request a where a.state = 'pending'
    union all
    -- An agent_action whose kind policy is 'founder'. No kind carries that policy today; the arm
    -- stays so a future refund-shaped kind is listed here rather than silently dropped.
    select a.id::text, a.kind, public.fn_ui_label('action_kind', a.kind), a.agent,
           left(coalesce(a.title, a.recommendation, ''), 160), a.created_at, 'agent_actions',
           a.target_id, true
      from public.agent_actions a
      join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'founder'
     where a.status in ('pending','needs_review')
       and a.created_at >= public.fn_os_fresh_start_at()
  )
  select jsonb_build_object(
    'waiting_on_you_total', (select count(*) from yours),
    'oldest_days', (select round(extract(epoch from now() - min(raised)) / 86400)::int from yours),
    'waiting_on_you', coalesce((
      select jsonb_agg(x order by x->>'raised')
        from (select jsonb_build_object(
                       'id', y.id, 'kind', y.kind, 'kind_label', y.kind_label, 'from', y."from",
                       'title', y.title, 'raised', y.raised, 'source', y.source,
                       'subject_ref', y.subject_ref, 'yours', y.yours,
                       'age_days', round(extract(epoch from now() - y.raised) / 86400)::int) as x
                from yours y order by y.raised
               limit greatest(coalesce(p_limit, 12), 1)) z), '[]'::jsonb),
    -- NOT HIS. Every other open row belongs to a named role; it is shown so he can see the company
    -- working, never so he can approve it.
    'held_with_roles', coalesce((
      select jsonb_agg(jsonb_build_object('holder', h, 'count', n, 'oldest_days', d,
                                          'kinds', k) order by n desc)
        from (select public.fn_action_holder(a.kind, a.agent) h, count(*) n,
                     round(extract(epoch from now() - min(a.created_at)) / 86400)::int d,
                     jsonb_agg(distinct a.kind) k
                from public.agent_actions a
                left join public.agent_action_kind_policy p on p.kind = a.kind
               where a.status in ('pending','needs_review')
                 and a.created_at >= public.fn_os_fresh_start_at()
                 and coalesce(p.policy, '') <> 'founder'
               group by 1) g), '[]'::jsonb),
    'held_with_roles_total', (select count(*) from public.agent_actions a
                                left join public.agent_action_kind_policy p on p.kind = a.kind
                               where a.status in ('pending','needs_review')
                                 and a.created_at >= public.fn_os_fresh_start_at()
                                 and coalesce(p.policy, '') <> 'founder'),
    -- The machine's own work in flight, kept separate so the two are never added together again.
    'machine_is_working_on', (select count(*) from public.agent_actions a
                                join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'auto'
                               where a.status = 'pending'
                                 and a.created_at >= public.fn_os_fresh_start_at()),
    -- A kind nobody has classified. Fail-closed and NAMED: the sweep will not queue it and the
    -- worker will not settle it, so if this list is not empty, work is sitting still and this is
    -- the only place that says so.
    'unrouted_kinds', coalesce((
      select jsonb_agg(jsonb_build_object('kind', k,
                                          'kind_label', public.fn_ui_label('action_kind', k),
                                          'pending', n, 'oldest_days', d))
        from (select a.kind k, count(*) n,
                     round(extract(epoch from now() - min(a.created_at)) / 86400)::int d
                from public.agent_actions a
               where a.status = 'pending'
                 and a.created_at >= public.fn_os_fresh_start_at()
                 and not exists (select 1 from public.agent_action_kind_policy p where p.kind = a.kind)
               group by a.kind order by 2 desc) y), '[]'::jsonb),
    'fresh_start_at', public.fn_os_fresh_start_at());
$function$;

-- ── fn_ws_exec_home: decisions_open is refunds only ───────────────────────────────────────────
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
  fq as (select public.fn_founder_queue(1) j)
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
    'tasks_open',       (select count(*) from public.org_tasks where status not in ('done','cancelled')),
    'generated_at',     now()
  );
$function$;

-- ── fn_ws_operations: approvals are the founder queue; everything else is held with a role ────
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
      'tasks_open',(select count(*) from crm_tasks where coalesce(status,'open') not in ('done','cancelled')),
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
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'status',status,'priority',priority,'due',due_date,'source',source,'entity',entity)) from (select * from crm_tasks where coalesce(status,'open') not in ('done','cancelled') order by created_at desc limit 20) t),'[]'::jsonb)
  );
$function$;

-- ── fn_ws_governance: open_for_review is refunds only; escalations name their holder ──────────
CREATE OR REPLACE FUNCTION public.fn_ws_governance()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    -- governance_kpis.open_for_review counts every open agent_action; overridden here with the
    -- founder's real number and the held count published beside it under its own name.
    'kpis', (select to_jsonb(k) from public.governance_kpis k)
            || jsonb_build_object('open_for_review', public.fn_founder_refund_approvals_open(),
                                  'held_with_roles', (public.fn_founder_queue(1)->>'held_with_roles_total')::int),
    'universal_rules', (select universal_rules from public.agent_governance where active order by version desc limit 1),
    'response_structure', (select response_structure from public.agent_governance where active order by version desc limit 1),
    'recent_escalations', (select coalesce(jsonb_agg(e),'[]'::jsonb) from (
        select id, agent, title, coalesce(escalation_reason,'—') as reason, confidence,
               public.fn_action_policies(kind, confidence) as policies,
               public.fn_owning_os(agent) as os,
               public.fn_action_holder(kind, agent) as holder,
               false as yours,
               (select d.alternatives from public.decision_log d where d.id = decision_log_id) as alternatives,
               case when decided_at is not null
        then coalesce(status,'decided') || ' by ' || coalesce(decided_by,'the system') || ' on ' || decided_at::date
        else 'held with ' || public.fn_action_holder(kind, agent) || ' since ' || created_at::date end as outcome,
               to_char(created_at,'YYYY-MM-DD') as created
        from public.agent_actions
        where escalated
          and status in ('pending','needs_review')
          and created_at >= public.fn_os_fresh_start_at()
        order by created_at desc limit 15) e),
    'agent_coverage', (select coalesce(jsonb_agg(c),'[]'::jsonb) from (
        select ca.name as agent, (ca.persona is not null) as has_persona,
               exists(select 1 from public.agent_knowledge k where k.agent_key='cat:'||ca.slug or k.agent_key=ca.slug) as has_knowledge,
               (select count(*) from public.agent_actions a where a.agent=ca.slug) as audit_items
        from public.category_agents ca where ca.active order by ca.name limit 60) c),
    'fresh_start_at', public.fn_os_fresh_start_at()
  );
$function$;

-- ── fn_ws_notifications: the bell rings for refunds and critical alerts ───────────────────────
CREATE OR REPLACE FUNCTION public.fn_ws_notifications()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with fq as (select public.fn_founder_queue(8) j)
  select jsonb_build_object(
    -- CRITICAL — a founder alert raised at critical/high. An open agent_action at risk 'critical'
    -- used to be added here; it belongs to its role and is listed under 'held' instead.
    'critical', jsonb_build_object(
      'tier', 'critical',
      'count', (select count(*) from public.founder_alerts
                 where lower(coalesce(level,'')) in ('critical','high')
                   and created_at > now() - interval '7 days'
                   and created_at >= public.fn_os_fresh_start_at()),
      'rows', coalesce((select jsonb_agg(jsonb_build_object('title', a.event, 'detail', left(a.detail::text, 200),
                          'level', a.level, 'at', a.created_at) order by a.created_at desc)
                from (select * from public.founder_alerts
                       where lower(coalesce(level,'')) in ('critical','high')
                         and created_at > now() - interval '7 days'
                         and created_at >= public.fn_os_fresh_start_at()
                       order by created_at desc limit 8) a), '[]'::jsonb)),

    -- IMPORTANT — waiting on the founder. That is a refund approval and nothing else.
    'important', jsonb_build_object(
      'tier', 'important',
      'count', public.fn_founder_refund_approvals_open(),
      'rows', coalesce((select jsonb_agg(jsonb_build_object('title', x->>'title', 'detail', 'from ' || (x->>'from') || ' · ' || (x->>'kind_label'),
                          'kind', x->>'kind', 'agent', x->>'from', 'at', x->>'raised', 'id', x->>'id', 'source', x->>'source'))
                from fq, jsonb_array_elements(fq.j->'waiting_on_you') x), '[]'::jsonb)),

    -- HELD — open work that belongs to a named role. Informational: he is not asked to decide it.
    'held', jsonb_build_object(
      'tier', 'held',
      'count', (select (j->>'held_with_roles_total')::int from fq),
      'rows', coalesce((select jsonb_agg(jsonb_build_object(
                          'title', 'held with ' || (x->>'holder') || ': ' || (x->>'count'),
                          'detail', (select string_agg(k, ', ') from jsonb_array_elements_text(x->'kinds') k),
                          'holder', x->>'holder', 'count', x->>'count'))
                from fq, jsonb_array_elements(fq.j->'held_with_roles') x), '[]'::jsonb)),

    -- SUGGESTED — nothing is blocked, but the company thinks the founder should look.
    'suggested', jsonb_build_object(
      'tier', 'suggested',
      'count', (select count(*) from public.opportunity where status = 'open'
                 and created_at >= public.fn_os_fresh_start_at())
             + (select count(*) from public.evolution_proposal where status = 'proposed'
                 and created_at >= public.fn_os_fresh_start_at()),
      'rows', coalesce((select jsonb_agg(jsonb_build_object('title', o.title, 'detail', left(coalesce(o.detail,''), 200),
                          'kind', o.kind, 'at', o.created_at) order by o.value_score desc nulls last)
                from (select * from public.opportunity where status = 'open'
                       and created_at >= public.fn_os_fresh_start_at()
                       order by value_score desc nulls last limit 6) o), '[]'::jsonb)),

    -- COMPLETED TODAY — closed since midnight, whoever closed it.
    'completed_today', jsonb_build_object(
      'tier', 'completed_today',
      'count', (select count(*) from public.agent_actions where decided_at::date = current_date),
      'rows', coalesce((select jsonb_agg(jsonb_build_object('title', a.title, 'status', a.status,
                          'decided_by', a.decided_by, 'at', a.decided_at) order by a.decided_at desc)
                from (select * from public.agent_actions where decided_at::date = current_date
                       order by decided_at desc limit 8) a), '[]'::jsonb)),

    'auto_cleared_24h', (select round(100.0 * count(*) filter (where coalesce(escalated, false) = false)
                                 / greatest(count(*), 1))
                           from public.agent_actions where created_at > now() - interval '24 hours'),
    'auto_handled_30d', (select round(100.0 * count(*) filter (where coalesce(escalated, false) = false)
                                 / greatest(count(*), 1))
                           from public.agent_actions where created_at > now() - interval '30 days'),
    'actions_24h', (select count(*) from public.agent_actions where created_at > now() - interval '24 hours'),
    'actions_30d', (select count(*) from public.agent_actions where created_at > now() - interval '30 days'),
    'outbound_queue', (select count(*) from public.notifications where coalesce(status,'') not in ('sent','delivered')),
    'fresh_start_at', public.fn_os_fresh_start_at(),
    'generated_at', now()
  );
$function$;

-- ── fn_ws_exec: approvals are the founder queue ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_ws_exec()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'command', fn_os_command(),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'status',status,'priority',priority,'due',due_date,'entity',entity)) from (select * from crm_tasks where coalesce(status,'') not in ('done','cancelled') and created_at >= fn_os_fresh_start_at() order by created_at desc limit 8) t),'[]'::jsonb),
    'approvals', public.fn_founder_queue(6)->'waiting_on_you',
    'held', coalesce((select jsonb_agg(jsonb_build_object('id',id,'agent',agent,'title',title,'kind',kind,'kind_label',fn_ui_label('action_kind',kind),'holder',public.fn_action_holder(kind, agent),'risk',risk,'status',status,'created_at',created_at,'yours',false))
                from (select a.* from agent_actions a left join agent_action_kind_policy p on p.kind = a.kind
                       where a.status in ('pending','needs_review') and coalesce(p.policy,'') <> 'founder'
                         and a.created_at >= fn_os_fresh_start_at() order by a.created_at desc limit 6) a),'[]'::jsonb),
    'activity', coalesce((select jsonb_agg(jsonb_build_object('actor',actor,'kind',kind,'kind_label',fn_ui_label('action_kind',kind),'decision',decision,'confidence',confidence,'route_to',route_to,'created_at',created_at)) from (select * from decision_log where created_at >= fn_os_fresh_start_at() order by created_at desc limit 10) d),'[]'::jsonb),
    'notifications', coalesce((select jsonb_agg(jsonb_build_object('type',type,'type_label',fn_ui_label('notification_type',type),'subject',subject,'status',status,'created_at',created_at)) from (select * from notifications where created_at >= fn_os_fresh_start_at() order by created_at desc limit 6) n),'[]'::jsonb)
  );
$function$;

-- ── fn_os_command: a held decision names its holder ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_os_command()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_health jsonb; v_ops jsonb; v_counts jsonb; v_attention jsonb; v_pipeline jsonb;
begin
  v_health := to_jsonb(fn_health_index());
  v_ops    := to_jsonb(fn_ops_dashboard());

  select jsonb_build_object(
    'suppliers_total', (select count(*) from leads),
    'rfqs_total',      (select count(*) from inquiries),
    'rfqs_active',     (select count(*) from inquiries where status = 'quoted'),
    'rfqs_revealed',   (select count(*) from inquiries where status = 'revealed'),
    'rfqs_cancelled',  (select count(*) from inquiries where status = 'cancelled'),
    'quotes_total',    (select count(*) from quotes),
    'decisions_7d',    (select count(*) from decision_log where created_at > now() - interval '7 days'),
    'decisions_24h',   (select count(*) from decision_log where created_at > now() - interval '24 hours')
  ) into v_counts;

  select jsonb_build_object(
    'sent',      (select count(*) from inquiries where status = 'sent' and parent_inquiry_id is null),
    'matched',   (select count(distinct im.inquiry_id) from inquiry_matches im join inquiries i on i.id = im.inquiry_id where i.status = 'sent'),
    'quoted',    (select count(*) from inquiries where status = 'quoted'),
    'revealed',  (select count(*) from inquiries where status = 'revealed'),
    'completed', (select count(*) from inquiries where status in ('completed','won'))
  ) into v_pipeline;

  -- THE ESCALATIONS LOG. decision_log is append-only; this reads forward from the fresh-start
  -- watermark. A decision is listed only while its action is open, and each names the ROLE that
  -- holds it: none of these is the founder's to approve.
  select coalesce(jsonb_agg(x order by created_at desc), '[]'::jsonb) into v_attention
  from (
    select id, actor, kind, decision, confidence, route_to, created_at,
           jsonb_build_object('id', id, 'actor', actor, 'kind', kind,
             'kind_label', public.fn_ui_label('action_kind', kind), 'decision', decision,
             'policies', public.fn_action_policies(kind, confidence),
             'confidence', confidence, 'route_to', route_to, 'created_at', created_at,
             'os', public.fn_owning_os(actor),
             'holder', public.fn_action_holder(kind, actor),
             'yours', false,
             'reasons', reasons,
             'alternatives', alternatives,
             'outcome', case when exists (select 1 from public.agent_actions a where a.decision_log_id = decision_log.id)
                  then (select coalesce(a.status,'recorded') || ' — ' || coalesce(a.title,'action taken')
                          || ', held with ' || public.fn_action_holder(a.kind, a.agent)
                          from public.agent_actions a where a.decision_log_id = decision_log.id
                         order by a.created_at desc limit 1)
                  else 'held for ' || coalesce(route_to,'review') || ', no follow-up action recorded since ' || created_at::date end
           ) as x
    from decision_log
    where route_to is not null and route_to <> 'auto'
      and created_at >= public.fn_os_fresh_start_at()
      and exists (select 1 from public.agent_actions a
                   where a.decision_log_id = decision_log.id
                     and a.status in ('pending','needs_review'))
    order by created_at desc limit 8
  ) z;

  return jsonb_build_object(
    'health', v_health, 'health_index', v_health->>'index',
    'ops', v_ops, 'counts', v_counts, 'pipeline', v_pipeline,
    'attention', v_attention, 'generated_at', now());
end $function$;

-- ── fn_ops_dashboard: escalations = refund approvals + severe alerts ──────────────────────────
CREATE OR REPLACE FUNCTION public.fn_ops_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  active_rfqs int; rfqs_today int; done_today int; ttfq numeric; qpr numeric;
  accept_rate numeric; conv numeric;
  rev_today numeric; rev_month numeric; pending_fees numeric; outstanding_inv int; cash_recv numeric;
  ai_conf numeric; waiting int; onboard_q int; disputes int; escalations int; held int;
  uptime numeric; queue_size int; failed int; last_backup timestamptz; api_lat numeric;
  health jsonb;
begin
  -- MARKETPLACE
  select count(*) into active_rfqs from inquiries where status not in ('completed','accepted','closed','cancelled');
  select count(*) into rfqs_today from inquiries where created_at::date=current_date;
  select count(*) into done_today from inquiries where (completed_at::date=current_date) or (status in ('completed','accepted') and stage_changed_at::date=current_date);
  select round(avg(extract(epoch from (fq - ic))/3600.0),1) into ttfq from (
    select i.created_at ic, min(q.created_at) fq from inquiries i join quotes q on q.inquiry_id=i.id
    where i.created_at>=now()-interval '30 days' group by i.id) z where fq is not null;
  select round(avg(qc),1) into qpr from (select count(*) qc from quotes q join inquiries i on i.id=q.inquiry_id where i.created_at>=now()-interval '30 days' group by q.inquiry_id) z;
  select round(avg(nullif(rv_response_rate,0)) ,1) into accept_rate from leads where coalesce(rv_reveals,0)>0;
  select round(100.0*count(distinct t.inquiry_id)/nullif(count(distinct i.id),0),1) into conv
    from inquiries i left join transactions t on t.inquiry_id=i.id where i.created_at>=now()-interval '30 days';

  -- REVENUE
  select coalesce(sum(reveal_fee),0) into rev_today from transactions where revealed_at::date=current_date and coalesce(refund_status,'')<>'approved';
  select coalesce(sum(reveal_fee),0) into rev_month from transactions where date_trunc('month',revealed_at)=date_trunc('month',now()) and coalesce(refund_status,'')<>'approved';
  begin select coalesce(sum(amount_due),0) into pending_fees from supplier_dues where coalesce(status,'')<>'paid'; exception when others then pending_fees:=0; end;
  begin select count(*) into outstanding_inv from reveal_invoices ri left join transactions t on t.id=ri.transaction_id where coalesce(t.fee_status,'')<>'paid'; exception when others then outstanding_inv:=0; end;
  select coalesce(sum(reveal_fee),0) into cash_recv from transactions where coalesce(fee_status,'')='paid';

  -- OPERATIONS
  begin select public.fn_health_index() into health; exception when others then health:=null; end;
  select round(100.0*count(*) filter (where nullif(quality->>'score','')::numeric>=60)/nullif(count(*) filter (where quality is not null),0),1) into ai_conf
    from quotes where created_at>=now()-interval '7 days';
  select count(*) into waiting from inquiries where status in ('clarify','clarifying','awaiting_customer','needs_info');
  select count(*) into onboard_q from leads where approval_status='pending';
  select count(*) into disputes from transactions where refund_status='requested';
  -- Escalations TO HIM: refund approvals and severe alerts. Open agent_actions belong to their
  -- roles and are published separately as held_with_roles.
  select public.fn_founder_refund_approvals_open()
        + (select count(*) from founder_alerts where public.fn_alert_severe(level) and created_at>=now()-interval '24 hours') into escalations;
  select count(*) into held from agent_actions a left join agent_action_kind_policy p on p.kind=a.kind
   where a.status in ('pending','needs_review') and coalesce(p.policy,'')<>'founder';

  -- INFRASTRUCTURE
  select round(100.0*count(*) filter (where ok)/nullif(count(*),0),1) into uptime from health_checks where created_at>=now()-interval '24 hours';
  select count(*) into queue_size from notifications where coalesce(status,'')in('queued','pending','');
  begin select count(*) into failed from agent_runs where status='error' and coalesce(finished_at,started_at)>=now()-interval '24 hours'; exception when others then failed:=0; end;
  select max(updated_at) into last_backup from storage.objects where bucket_id='backups' and name like '%/_manifest.json';
  select round(avg(latency_ms),0) into api_lat from health_checks where created_at>=now()-interval '1 hour' and latency_ms is not null;

  return jsonb_build_object(
    'as_of', now(),
    'marketplace', jsonb_build_object('active_rfqs',active_rfqs,'rfqs_today',rfqs_today,'completed_today',done_today,
        'avg_hours_to_first_quote',ttfq,'avg_quotes_per_rfq',qpr,'supplier_acceptance_pct',accept_rate,'conversion_pct',conv),
    'revenue', jsonb_build_object('today_aed',rev_today,'month_aed',rev_month,'pending_fees_aed',pending_fees,
        'outstanding_invoices',outstanding_inv,'cash_received_aed',cash_recv),
    'operations', jsonb_build_object('ai_confidence_pct',ai_conf,'rfqs_waiting_clarification',waiting,
        'onboarding_queue',onboard_q,'disputes',disputes,'escalations',escalations,'held_with_roles',held),
    'infrastructure', jsonb_build_object('uptime_pct',uptime,'queue_size',queue_size,'failed_jobs_24h',failed,
        'backup_age_hours', case when last_backup is null then null else round(extract(epoch from (now()-last_backup))/3600.0,1) end,
        'api_latency_ms',api_lat),
    'health_index', coalesce(health->>'index',null));
end $function$;

-- ── fn_autonomy_class: 'founder' means a refund ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_autonomy_class(p_kind text, p_target_table text, p_recommendation text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare pol jsonb; d text;
begin
  -- THE ONE HARD RAIL. Money and refunds reach the founder (17 Aug 2026 ruling, restated 5 Sep
  -- 2026: nothing else does). Everything that used to return 'founder' below — the APV-04 gates,
  -- deletes on leads/customers, a supplier the sweep may not auto-approve — is 'keep': it stays
  -- open, held with its accountable role, and no surface may call it his.
  if p_kind ~* 'refund|payout|payment|withdraw|transfer|invoice_pay|money|charge' then return 'founder'; end if;
  if p_kind in ('strategy_change','legal_action','partnership','security_incident_executive') then return 'keep'; end if;
  if p_kind ~* 'delete|purge|remove_record' and coalesce(p_target_table,'') in ('leads','customers') then return 'keep'; end if;
  if p_kind='approve_supplier' and coalesce(p_recommendation,'')='approve' then return 'clean_supplier'; end if;
  if p_kind='approve_supplier' then return 'keep'; end if;
  -- POLICY: per-kind disposition. 'ack' clears; a role name (or 'keep') holds it with that role.
  -- 'founder' is honoured only for a kind the rail above already accepted, i.e. never here.
  select value into pol from public.decision_policy where key='action_autonomy';
  d := pol->>p_kind;
  if d = 'ack' then return 'ack'; end if;
  if d is not null then return 'keep'; end if;
  -- LEGACY FALLBACK
  if p_kind in ('security_alert','compliance_update','incident','supply_health','sla_no_supply') then return 'ack'; end if;
  return 'keep';
end $function$;

-- ── decision_policy says what phase_c_action_class says ───────────────────────────────────────
update public.decision_policy
   set value = (select jsonb_object_agg(k, case v
                  when 'founder' then coalesce(
                    (select p.authority_role from public.agent_action_kind_policy p where p.kind = k),
                    case k when 'legal_flag' then 'general_counsel'
                           when 'security_incident' then 'cto'
                           when 'customer_escalation' then 'customer_success_director'
                           when 'content_review' then 'marketplace_content_privacy_reviewer'
                           when 'prompt_approval' then 'cto'
                           when 'approve_supplier' then 'supplier_verification'
                           else 'chief_of_staff' end)
                  else v end)
                  from jsonb_each_text(value) e(k, v)),
       description = 'Per-kind disposition: ack = the sweep clears it; a role_id = held with that accountable role. '
                  || 'No kind here routes to the founder: the only founder approval is a refund '
                  || '(phase_c_action_class.founder_approval_required), which never comes through agent_actions.',
       updated_at = now()
 where key = 'action_autonomy';

update public.decision_policy
   set value = '["refund_decision","refund_outside_policy"]'::jsonb,
       description = 'The founder-review list. Refunds only (founder ruling 17 Aug 2026, restated 5 Sep 2026): '
                  || 'marketing, budget, legal, strategy, partnership and security decisions belong to their accountable roles.',
       updated_at = now()
 where key = 'founder_review_gates';

update public.decision_policy
   set description = 'Prompt keys matching this pattern are not auto-promoted by prompt_gate; the draft is held as a '
                  || 'prompt_approval agent_action for the cto (agent_action_kind_policy.authority_role), never for the founder.',
       updated_at = now()
 where key = 'prompt_sensitive_pattern';

-- ── proof ─────────────────────────────────────────────────────────────────────────────────────
do $$
declare v_auto jsonb; v_gates jsonb; v_bad text; v_fq jsonb; v_ops jsonb; v_n int;
begin
  select value into v_auto from public.decision_policy where key = 'action_autonomy';
  select string_agg(k, ',') into v_bad from jsonb_each_text(v_auto) e(k, v) where v = 'founder';
  if v_bad is not null then raise exception 'action_autonomy still names the founder for: %', v_bad; end if;
  select string_agg(k || '=' || v, ',') into v_bad from jsonb_each_text(v_auto) e(k, v)
   where v <> 'ack' and not exists (select 1 from public.org_role r where r.role_id = v and r.status = 'active');
  if v_bad is not null then raise exception 'action_autonomy names a role that is not active: %', v_bad; end if;

  select value into v_gates from public.decision_policy where key = 'founder_review_gates';
  select string_agg(g, ',') into v_bad from jsonb_array_elements_text(v_gates) g where g !~* 'refund';
  if v_bad is not null then raise exception 'founder_review_gates still lists a non-refund gate: %', v_bad; end if;

  if public.fn_autonomy_class('legal_action', null, null) = 'founder'
     or public.fn_autonomy_class('legal_flag', null, null) = 'founder'
     or public.fn_autonomy_class('approve_supplier', 'leads', 'reject') = 'founder'
     or public.fn_autonomy_class('delete_customer', 'customers', null) = 'founder' then
    raise exception 'fn_autonomy_class still returns founder for a non-refund kind';
  end if;
  if public.fn_autonomy_class('refund_request', null, null) <> 'founder' then
    raise exception 'fn_autonomy_class no longer returns founder for a refund';
  end if;

  v_fq := public.fn_founder_queue(50);
  if (v_fq->>'waiting_on_you_total')::int <> public.fn_founder_refund_approvals_open() then
    raise exception 'fn_founder_queue and fn_founder_refund_approvals_open disagree';
  end if;
  if exists (select 1 from jsonb_array_elements(v_fq->'waiting_on_you') x where x->>'kind' !~* 'refund') then
    raise exception 'fn_founder_queue lists a non-refund item as his';
  end if;
  v_ops := public.fn_ws_operations();
  if (v_ops#>>'{kpis,approvals_pending}')::int <> public.fn_founder_refund_approvals_open()
     or (public.fn_ws_exec_home()->>'decisions_open')::int <> public.fn_founder_refund_approvals_open()
     or (public.fn_ws_governance()#>>'{kpis,open_for_review}')::int <> public.fn_founder_refund_approvals_open()
     or (public.fn_ws_notifications()#>>'{important,count}')::int <> public.fn_founder_refund_approvals_open() then
    raise exception 'a founder-facing surface still counts something other than refund approvals';
  end if;
  select count(*) into v_n from jsonb_array_elements(v_ops->'held') h where h->>'holder' is null or h->>'holder' = '';
  if v_n > 0 then raise exception '% held rows have no holder', v_n; end if;
  raise notice 'founder surfaces: refund approvals open = %, held with roles = %, holders = %',
    public.fn_founder_refund_approvals_open(), v_fq->>'held_with_roles_total', v_fq->'held_with_roles';
end $$;
