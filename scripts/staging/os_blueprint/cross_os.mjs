// SPEC FILE #2 — the cross-OS contract (15 requirements, ids xos-01 .. xos-15).
//
// The eleven links of the cross-OS chain: an event is created, the bus carries it, the relevant
// OSes subscribe, each assesses impact, raises internal work, executes within its authority,
// returns the result, the Chief of Staff consolidates, the CEO re-prioritises, Knowledge captures
// the lesson and Intelligence updates the KPIs — plus the three rules that make the chain a
// contract rather than a diagram: no direct cross-OS calls, standard interfaces, full auditability.
//
// Every check asks the same three questions and never conflates them:
//   1. does the mechanism EXIST?   2. is it POPULATED / does it RUN?   3. does anything READ it?
// Two tables in this section (event_assessment, event_rollup) exist today with zero rows, zero
// writers and zero readers, which is precisely the failure mode this spec file is about, so the
// third question is never dropped from a check just because the first two answer yes.

// A LIVE reader: a routine, a cron command, or a view that is itself read by a routine or a cron.
// A view nothing reads is not a reader. The distinction is load-bearing and it cuts both ways here:
// v_os_health selects per-OS figures and no routine or cron selects v_os_health, so it proves
// nothing; v_operating_manual selects os_interface and fn_agent_context now selects
// v_operating_manual, so os_interface really does reach a running reader through it.
const rdSql = (t, excl = []) => {
  const ex = ["'" + t + "'"].concat(excl.map(e => "'" + e + "'")).join(',');
  return `(
    (select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind in ('f','p') and p.proname not in (${ex})
        and pg_get_functiondef(p.oid) ~* '\\y${t}\\y')
  + (select count(*) from cron.job j where j.command ~* '\\y${t}\\y')
  + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '\\y${t}\\y'
      and (exists (select 1 from pg_proc p2 join pg_namespace n2 on n2.oid=p2.pronamespace
             where n2.nspname='public' and p2.prokind in ('f','p') and p2.proname not in (${ex})
               and pg_get_functiondef(p2.oid) ~* ('\\y'||v.viewname||'\\y'))
        or exists (select 1 from cron.job j2 where j2.command ~* ('\\y'||v.viewname||'\\y')))))`;
};

// Row count for a table that may not exist. A bare reference would make the check ERROR if the
// table were dropped, and an errored check is an unmeasured requirement, not a MISSING verdict.
// query_to_xml is volatile, so the CASE genuinely short-circuits instead of being constant-folded.
const cnt = (t, w = 'true') => `(case when to_regclass('public.${t}') is null then 0 else
  (xpath('/row/c/text()', query_to_xml(
     'select count(*) c from public.${t} where ${w}', false, true, '')))[1]::text::int end)`;

// Same, for a column that may not exist yet (event_delivery has no result column today).
const cntCol = (t, c) => `(case when not exists (select 1 from information_schema.columns
    where table_schema='public' and table_name='${t}' and column_name='${c}') then 0 else
  (xpath('/row/c/text()', query_to_xml(
     'select count(*) c from public.${t} where ${c} is not null', false, true, '')))[1]::text::int end)`;

// Events that had a live subscriber and were never handed to it. This is the bus's own backlog:
// an event nobody subscribes to is not undelivered, it is unsubscribed, and counting those would
// make the dispatcher look broken for obeying its contract.
const UNDELIVERED = `(select count(*) from public.company_event e
   where exists (select 1 from public.event_subscription s
                  where s.active and s.event_type = e.event_type
                    and s.agent_key <> coalesce(e.actor,''))
     and not exists (select 1 from public.event_delivery d where d.event_id = e.id))`;

export default async function ({ req }) {

  // LINK 1 — an event is created. Exists: company_event + trigger emitters. Runs: rows this week.
  // Read: fn_event_dispatch and 13 more routines.
  await req('xos', 'xos-01-event-created', 'Link 1 business events are published onto a bus',
    `select (select count(*) from public.company_event where occurred_at > now() - interval '7 days') > 0
        and (select count(*) from pg_trigger tg join pg_class c on c.oid=tg.tgrelid
               join pg_proc p on p.oid=tg.tgfoid
              where not tg.tgisinternal and p.prokind in ('f','p')
                and pg_get_functiondef(p.oid) ~* ('inser'||'t\\s+into\\s+(public\\.)?company_event')) > 0
        and ${rdSql('company_event')} > 0`,
    `select (select count(*) from public.company_event where occurred_at > now() - interval '7 days')::text
        || ' event(s)/7d, ' || (select count(*) from pg_trigger tg join pg_class c on c.oid=tg.tgrelid
               join pg_proc p on p.oid=tg.tgfoid
              where not tg.tgisinternal and p.prokind in ('f','p')
                and pg_get_functiondef(p.oid) ~* ('inser'||'t\\s+into\\s+(public\\.)?company_event'))::text
        || ' emitter trigger(s), ' || ${rdSql('company_event')}::text || ' live reader(s)'`);

  // LINK 2 — the bus runs AND delivers everything it receives. A dispatcher on an active cron that
  // leaves a backlog behind its lookback window is running, not delivering.
  await req('xos', 'xos-02-event-bus', 'Link 2 the bus runs and delivers every event it receives',
    `select (select count(*) from cron.job where active and command ~* '\\yfn_event_dispatch\\y') > 0
        and (select count(*) from cron.job_run_details d join cron.job j on j.jobid = d.jobid
              where j.command ~* '\\yfn_event_dispatch\\y' and d.status = 'succeeded'
                and d.end_time > now() - interval '2 days') > 0
        and ${UNDELIVERED} = 0`,
    `select ${UNDELIVERED}::text || ' event(s) with a live subscriber never delivered of '
        || (select count(*) from public.company_event)::text || ' ever'`);

  // LINK 3 — the subscribers ARE Operating Systems: every subscription resolves to one, every
  // active OS holds at least one, and the dispatcher routes on that resolution rather than on a
  // bare agent_key that happens to sit in a department.
  await req('xos', 'xos-03-oses-subscribe', 'Link 3 subscriptions resolve to Operating Systems',
    `select (select count(*) from public.event_subscription s where s.active
              and not exists (select 1 from public.org_agents a
                                join public.os_department od on od.dept_key = a.department
                               where a.agent_key = s.agent_key)) = 0
        and (select count(*) from public.operating_system o where o.active
              and not exists (select 1 from public.event_subscription s
                                join public.org_agents a on a.agent_key = s.agent_key
                                join public.os_department od on od.dept_key = a.department
                               where s.active and od.os_key = o.os_key)) = 0
        and (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname='public' and p.prokind in ('f','p')
                and pg_get_functiondef(p.oid) ~* '\\yevent_subscription\\y'
                and pg_get_functiondef(p.oid) ~* '\\yos_department\\y') > 0`,
    `select (select count(*) from public.event_subscription s where s.active
              and not exists (select 1 from public.org_agents a
                                join public.os_department od on od.dept_key = a.department
                               where a.agent_key = s.agent_key))::text || ' sub(s) resolve to no OS; '
        || (select count(*) from public.operating_system o where o.active
              and not exists (select 1 from public.event_subscription s
                                join public.org_agents a on a.agent_key = s.agent_key
                                join public.os_department od on od.dept_key = a.department
                               where s.active and od.os_key = o.os_key))::text || ' active OS with none'`);

  // LINK 4 — impact is assessed BEFORE acting. event_assessment exists; the question is whether
  // anything writes it and anything reads it.
  await req('xos', 'xos-04-assess-impact', 'Link 4 each OS assesses impact before acting',
    `select (select count(*) from information_schema.columns
              where table_schema='public' and table_name='event_assessment'
                and column_name in ('event_id','impact')) = 2
        and ${cnt('event_assessment')} > 0
        and ${rdSql('event_assessment')} > 0`,
    `select ${cnt('event_assessment')}::text || ' assessment(s), '
        || ${rdSql('event_assessment')}::text || ' live reader(s)'`);

  // LINK 5 — the event becomes internal work. A delivery row with no task is an OS that was told
  // and did nothing, which is the failure this link names.
  await req('xos', 'xos-05-internal-tasks', 'Link 5 each OS creates internal tasks from the event',
    `select (select count(*) from public.event_delivery where task_id is not null) > 0
        and (select count(*) from public.event_delivery where task_id is null) = 0
        and ${rdSql('org_tasks')} > 0`,
    `select (select count(*) from public.event_delivery where task_id is not null)::text || ' of '
        || (select count(*) from public.event_delivery)::text || ' deliveries carry a task'`);

  // LINK 6 — execution stays inside the authority model: the dispatcher resolves the tier from
  // fn_dept_authority instead of granting itself autonomy, nothing non-autonomous slipped through
  // unflagged, and event-derived work has actually completed. Note that all 95 event-derived tasks
  // today resolve to 'autonomous', so the middle leg passes over an empty population — it is the
  // regression guard for the hard-coded tier this dispatcher used to carry, not the proof.
  await req('xos', 'xos-06-execute-authority', 'Link 6 each OS executes within its authority',
    `select (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname='public' and p.proname='fn_event_dispatch'
                and pg_get_functiondef(p.oid) ~* '\\yfn_dept_authority\\y') > 0
        and (select count(*) from public.org_tasks t join public.event_delivery d on d.task_id = t.id
              where t.tier is distinct from 'autonomous' and t.needs_founder = false) = 0
        and (select count(*) from public.org_tasks t join public.event_delivery d on d.task_id = t.id
              where t.status in ('done','closed')) > 0`,
    `select (select count(*) from public.org_tasks t join public.event_delivery d on d.task_id = t.id
              where t.status in ('done','closed'))::text || ' event-derived task(s) closed, '
        || (select count(*) from public.org_tasks t join public.event_delivery d on d.task_id = t.id
              where t.tier is distinct from 'autonomous' and t.needs_founder = false)::text
        || ' executed above tier'`);

  // LINK 7 — the result comes back to the event that caused the work. Any of the three surfaces
  // counts (a result column on the delivery, a decision_trace caused by the event, a workflow_run
  // triggered by it, a rollup outcome) — but it must be populated AND read by something.
  await req('xos', 'xos-07-results-returned', 'Link 7 results returned to the originating event',
    `select (${cntCol('event_delivery','result')} + ${cntCol('event_delivery','outcome')}
           + ${cntCol('event_delivery','closed_at')}
           + (select count(*) from public.decision_trace where causation_event_id is not null)
           + (select count(*) from public.workflow_run where trigger_event_id is not null)
           + ${cnt('event_rollup', 'outcome is not null')}) > 0
        and (${rdSql('event_delivery', ['fn_event_dispatch'])} + ${rdSql('decision_trace')}
           + ${rdSql('workflow_run')} + ${rdSql('event_rollup')}) > 0`,
    `select (${cntCol('event_delivery','result')} + ${cntCol('event_delivery','outcome')}
           + ${cntCol('event_delivery','closed_at')}
           + (select count(*) from public.decision_trace where causation_event_id is not null)
           + (select count(*) from public.workflow_run where trigger_event_id is not null)
           + ${cnt('event_rollup', 'outcome is not null')})::text || ' result(s) returned, '
        || (${rdSql('event_delivery', ['fn_event_dispatch'])} + ${rdSql('decision_trace')}
           + ${rdSql('workflow_run')} + ${rdSql('event_rollup')})::text || ' reader(s)'`);

  // LINK 8 — the Chief of Staff consolidates ACROSS OSes. One rollup row per correlation touching
  // a single OS is a receipt, not a consolidation, so os_count > 1 is part of the measure.
  await req('xos', 'xos-08-cos-consolidates', 'Link 8 Chief of Staff consolidates outcomes across OSes',
    `select ${cnt('event_rollup')} > 0
        and ${cnt('event_rollup', 'os_count > 1')} > 0
        and ${rdSql('event_rollup')} > 0`,
    `select ${cnt('event_rollup')}::text || ' rollup(s), ' || ${cnt('event_rollup', 'os_count > 1')}::text
        || ' spanning >1 OS, ' || ${rdSql('event_rollup')}::text || ' live reader(s)'`);

  // LINK 9 — the CEO re-prioritises off outcomes, and the new priority travels as an event that
  // someone subscribes to. os_interface declares priority.updated; the bus has never carried one.
  await req('xos', 'xos-09-ceo-priorities', 'Link 9 CEO updates company priorities off event outcomes',
    `select (select count(*) from public.company_event where event_type ~* 'priorit') > 0
        and (select count(*) from public.event_subscription where active and event_type ~* 'priorit') > 0
        and (select count(*) from public.event_delivery d join public.company_event e on e.id = d.event_id
              where e.event_type ~* 'priorit') > 0`,
    `select (select count(*) from public.company_event where event_type ~* 'priorit')::text
        || ' priority event(s), ' || (select count(*) from public.event_subscription
              where active and event_type ~* 'priorit')::text || ' subscription(s), '
        || (select count(*) from public.event_delivery d join public.company_event e on e.id = d.event_id
              where e.event_type ~* 'priorit')::text || ' delivered'`);

  // LINK 10 — Knowledge captures the lesson from an EVENT outcome. institutional_memory is well
  // read (11 routines); the open question is whether any of its rows descend from a dispatched
  // event rather than from a task that arrived some other way.
  await req('xos', 'xos-10-knowledge-lessons', 'Link 10 Knowledge OS captures lessons from event outcomes',
    `select (select count(*) from public.institutional_memory m
              where exists (select 1 from public.event_delivery d
                             where d.task_id is not null and d.task_id::text = m.subject_id)) > 0
        and ${rdSql('institutional_memory')} > 0`,
    `select (select count(*) from public.institutional_memory m
              where exists (select 1 from public.event_delivery d
                             where d.task_id is not null and d.task_id::text = m.subject_id))::text
        || ' of ' || (select count(*) from public.institutional_memory)::text
        || ' lesson(s) trace to a dispatched event'`);

  // LINK 11 — Intelligence updates KPIs and forecasts off events. The kpi.missed emitter must have
  // a caller that actually runs, the events must be recent, and they must reach a subscriber.
  await req('xos', 'xos-11-intelligence-kpis', 'Link 11 Intelligence OS updates KPIs off events',
    `select (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname='public' and p.prokind in ('f','p')
                and pg_get_functiondef(p.oid) ~* 'kpi\\.missed'
                and ((select count(*) from pg_proc q join pg_namespace n2 on n2.oid = q.pronamespace
                       where n2.nspname='public' and q.prokind in ('f','p') and q.oid <> p.oid
                         and pg_get_functiondef(q.oid) ~* ('\\y'||p.proname||'\\y'))
                   + (select count(*) from cron.job j where j.command ~* ('\\y'||p.proname||'\\y'))) > 0) > 0
        and (select count(*) from public.company_event
              where event_type = 'kpi.missed' and occurred_at > now() - interval '14 days') > 0
        and (select count(*) from public.event_delivery where event_type = 'kpi.missed') > 0`,
    `select (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname='public' and p.prokind in ('f','p')
                and pg_get_functiondef(p.oid) ~* 'kpi\\.missed'
                and ((select count(*) from pg_proc q join pg_namespace n2 on n2.oid = q.pronamespace
                       where n2.nspname='public' and q.prokind in ('f','p') and q.oid <> p.oid
                         and pg_get_functiondef(q.oid) ~* ('\\y'||p.proname||'\\y'))
                   + (select count(*) from cron.job j where j.command ~* ('\\y'||p.proname||'\\y'))) > 0)::text
        || ' kpi.missed emitter(s) with a caller; ' || (select count(*) from public.company_event
              where event_type='kpi.missed' and occurred_at > now() - interval '14 days')::text || ' in 14d'`);

  // HARD RULE — no OS reaches into another for business logic. Met either by nothing writing another
  // OS's queue outside the bus, or by a guard on org_tasks that refuses the cross-OS write. The
  // count of routines that can drop work into any department is the evidence either way.
  await req('xos', 'xos-12-no-direct-cross-os', 'Hard rule no OS calls another OS directly',
    `select (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_event_dispatch'
                and pg_get_functiondef(p.oid) ~* ('inser'||'t\\s+into\\s+(public\\.)?org_tasks')) = 0
        or (select count(*) from pg_trigger tg join pg_class c on c.oid = tg.tgrelid
              join pg_proc p on p.oid = tg.tgfoid
             where c.relname='org_tasks' and not tg.tgisinternal and p.prokind in ('f','p')
               and pg_get_functiondef(p.oid) ~* '\\yos_department\\y'
               and pg_get_functiondef(p.oid) ~* '\\yraise\\y') > 0`,
    `select (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_event_dispatch'
                and pg_get_functiondef(p.oid) ~* ('inser'||'t\\s+into\\s+(public\\.)?org_tasks'))::text
        || ' routine(s) write org_tasks outside the bus; '
        || (select count(*) from pg_trigger tg join pg_class c on c.oid = tg.tgrelid
              join pg_proc p on p.oid = tg.tgfoid
             where c.relname='org_tasks' and not tg.tgisinternal and p.prokind in ('f','p')
               and pg_get_functiondef(p.oid) ~* '\\yos_department\\y')::text || ' cross-OS guard(s)'`);

  // STANDARD INTERFACES — os_interface is the declared contract. It is only an interface if the bus
  // carries what it declares AND something at runtime consults it; a catalogue read by one unread
  // documentation view is a diagram.
  await req('xos', 'xos-13-standard-interfaces', 'OSes expose standardized interfaces the bus carries',
    `select (select count(*) from public.os_interface where active and event_type is not null) > 0
        and (select count(*) from public.os_interface i where i.active and i.event_type is not null
              and not exists (select 1 from public.company_event e
                               where e.event_type = i.event_type)) = 0
        and ${rdSql('os_interface')} > 0`,
    `select (select count(*) from public.os_interface i where i.active and i.event_type is not null
              and not exists (select 1 from public.company_event e where e.event_type = i.event_type))::text
        || ' of ' || (select count(*) from public.os_interface where active and event_type is not null)::text
        || ' declared interfaces never fired; ' || ${rdSql('os_interface')}::text || ' live reader(s)'`);

  // AUDITABILITY — correlation ties one business episode together, causation ties an effect to its
  // cause. Both columns exist and both are empty, and nothing that runs reads either.
  await req('xos', 'xos-14-event-auditability', 'Event chain is auditable (correlation and causation)',
    `select (select count(*) from public.company_event where correlation_id is not null) > 0
        and (select count(*) from public.company_event where causation_id is not null) > 0
        and ((select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
               where ns.nspname='public' and p.prokind in ('f','p')
                 and pg_get_functiondef(p.oid) ~* '\\ycorrelation_id\\y')
           + (select count(*) from cron.job j where j.command ~* '\\ycorrelation_id\\y')
           + (select count(*) from pg_views v where v.schemaname='public'
                and v.definition ~* '\\ycorrelation_id\\y'
                and (exists (select 1 from pg_proc p2 join pg_namespace n2 on n2.oid = p2.pronamespace
                              where n2.nspname='public' and p2.prokind in ('f','p')
                                and pg_get_functiondef(p2.oid) ~* ('\\y'||v.viewname||'\\y'))
                  or exists (select 1 from cron.job j2 where j2.command ~* ('\\y'||v.viewname||'\\y'))))) > 0`,
    `select (select count(*) from public.company_event where correlation_id is not null)::text || '/'
        || (select count(*) from public.company_event)::text || ' correlated, '
        || (select count(*) from public.company_event where causation_id is not null)::text
        || ' caused, ' || ((select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
               where ns.nspname='public' and p.prokind in ('f','p')
                 and pg_get_functiondef(p.oid) ~* '\\ycorrelation_id\\y')
           + (select count(*) from cron.job j where j.command ~* '\\ycorrelation_id\\y'))::text
        || ' routine/cron reader(s)'`);

  // BUS OBSERVABILITY — v_event_backbone is the one surface that says which event types are live,
  // undelivered or never fired. It exists and is correct; the requirement is that somebody looks.
  await req('xos', 'xos-15-bus-observability', 'Bus health is observable: the backbone view is read',
    `select (select count(*) from pg_views where schemaname='public' and viewname='v_event_backbone') > 0
        and ${rdSql('v_event_backbone')} > 0`,
    `select 'v_event_backbone: ' || ${rdSql('v_event_backbone')}::text || ' live reader(s) over '
        || (select count(*) from public.event_subscription where active)::text || ' active subscription(s)'`);
}
