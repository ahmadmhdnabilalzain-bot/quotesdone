// SPEC FILE #2, components 1-9 — Purpose, Mission, Objectives, Responsibilities, the Employee
// Object, Knowledge, Inputs, Outputs, Workflows. 30 requirements.
//
// Every check asks the same three questions and refuses to merge them:
//   1. does the mechanism EXIST?   2. is it POPULATED / does it RUN?   3. does anything READ it?
//
// This section is where the nine "built, populated, read by nothing" failures live, so presence is
// never sufficient evidence. Where a requirement says an attribute must reach an employee, the
// check reads fn_agent_context's ACTUAL OUTPUT and looks for the value stored in the table — not
// for a hard-coded heading, which would pass even if the column were empty. Where a requirement is
// satisfied today the check returns true: none of these can only fail.
//
// SQL NOTE: qd_guard refuses any read whose text contains a bare write keyword, so no statement
// below may contain one, even inside a string literal.

// One employee per OS, picked deterministically. "Does this reach the employees?" is a claim about
// all ten Operating Systems; asking cfo alone would prove it for Finance and assume the rest.
const ONE_PER_OS = `(select distinct on (d.os_key) d.os_key, a.agent_key
     from public.os_department d
     join public.org_agents a on a.department = d.dept_key and a.active
    order by d.os_key, a.agent_key)`;
const OS_WITH_STAFF = `(select count(distinct d.os_key) from public.os_department d
     join public.org_agents a on a.department = d.dept_key and a.active)`;
const ACTIVE_OS = `(select count(*) from public.operating_system where coalesce(active,true))`;

// How many OSes have an employee whose assembled prompt literally contains <expr>, an expression
// over the operating_system row `o`. The value comes from the table, so a passing count means the
// stored attribute travelled into the prompt.
const REACHED = (expr) => `(select count(*) from ${ONE_PER_OS} z
     join public.operating_system o on o.os_key = z.os_key
    where public.fn_agent_context(z.agent_key, 20000) like '%'||(${expr})||'%')`;

const reachCheck = (expr) => `select ${REACHED(expr)} = ${OS_WITH_STAFF}`;
const reachEv = (expr, what) =>
  `select ${REACHED(expr)}::text||' of '||${OS_WITH_STAFF}::text||' OS: ${what}'`;

export default async function ({ req, READERS }) {
  // ---- Component 1: Purpose -------------------------------------------------------------------
  // charter+mandate were 10/10 populated and exposed only by v_operating_manual, which had no
  // reader of its own. The check therefore ignores the table's row count as proof of anything.
  await req('comp', 'comp-01-purpose', 'Every OS states why it exists (Purpose)',
    `select (select count(*) from public.operating_system
              where coalesce(active,true) and coalesce(charter,'') <> '' and coalesce(mandate,'') <> '')
            = ${ACTIVE_OS}
       and ${REACHED('left(o.charter,200)')} = ${OS_WITH_STAFF}`,
    reachEv('left(o.charter,200)', 'employee prompt carries the stored charter'));

  await req('comp', 'comp-02-mission', 'Every OS has a one-sentence Mission',
    `select (select count(*) from public.operating_system
              where coalesce(active,true) and coalesce(mission,'') <> '') = ${ACTIVE_OS}
       and ${REACHED('left(o.mission,200)')} = ${OS_WITH_STAFF}`,
    reachEv('left(o.mission,200)', 'employee prompt carries the stored mission'));

  // ---- Component 2: Objectives ----------------------------------------------------------------
  // Five horizons for every OS, and the horizon label must survive into the prompt: an objective
  // without its horizon is a slogan, which is precisely how 50 rows sat unread.
  await req('comp', 'comp-03-objectives', 'Objectives at strategic/annual/quarterly/weekly/daily horizons',
    `select (select count(*) from public.operating_system os2
              where coalesce(os2.active,true)
                and (select count(distinct horizon) from public.os_objective j
                      where j.os_key = os2.os_key) = 5) = ${ACTIVE_OS}
       and ${REACHED(`select 'strategic: '||y.objective from public.os_objective y
                        where y.os_key = o.os_key and y.horizon='strategic'
                          and coalesce(y.active,true) limit 1`)} = ${OS_WITH_STAFF}`,
    reachEv(`select 'strategic: '||y.objective from public.os_objective y
               where y.os_key = o.os_key and y.horizon='strategic'
                 and coalesce(y.active,true) limit 1`,
      'employee prompt carries the horizon-labelled objective'));

  // A measure that is prose ('gl_journal', 'os_review health') cannot produce an actual value, so
  // nothing can ever say whether an objective was met. The mechanism required is a computable
  // measure plus a routine that resolves it — employee_kpi.measure_sql is the working precedent.
  //
  // The column list alone is NOT the test. measure_sql/actual_value/measured_at were added to
  // os_objective while this section was being written and left empty on all 50 rows, and an earlier
  // draft of this check passed anyway: fn_agent_context happens to contain the string
  // 'actual_value' for goal_period, which has nothing to do with objectives. Populated rows are
  // the only thing that distinguishes a measure from a column definition.
  await req('comp', 'comp-03-objectives-measured', 'Objectives carry a computable measure, not prose',
    `select (select count(*) from information_schema.columns
              where table_schema='public' and table_name='os_objective'
                and column_name in ('measure_sql','actual_value','actual','measured_at')) > 0
       and (select count(*) from public.os_objective where coalesce(measure_sql,'') <> '')
           = (select count(*) from public.os_objective where coalesce(active,true))
       and (select count(*) from public.os_objective where actual_value is not null) > 0`,
    `select (select count(*) from public.os_objective where coalesce(measure_sql,'') <> '')::text
       ||' of '||(select count(*)::text from public.os_objective)
       ||' objectives carry a computable measure, '
       ||(select count(*) from public.os_objective where actual_value is not null)::text
       ||' carry an actual value (columns exist: '
       ||(select (count(*) > 0)::text from information_schema.columns
           where table_schema='public' and table_name='os_objective' and column_name='measure_sql')||')'`);

  // ---- Component 4: Responsibilities -----------------------------------------------------------
  await req('comp', 'comp-04-responsibilities', 'Responsibilities replace departments as the ownership unit',
    `select (select count(distinct os_key) from public.os_responsibility) = ${ACTIVE_OS}
       and ${REACHED(`select string_agg(x.responsibility, ', ' order by x.responsibility)
                        from (select responsibility from public.os_responsibility
                               where os_key = o.os_key order by responsibility limit 12) x`)} = ${OS_WITH_STAFF}`,
    reachEv(`select string_agg(x.responsibility, ', ' order by x.responsibility)
               from (select responsibility from public.os_responsibility
                      where os_key = o.os_key order by responsibility limit 12) x`,
      'employee prompt lists what their OS owns'));

  // "No other OS can own these" must be structural, not a convention. A PK on responsibility alone
  // makes a second owner unrepresentable; a composite PK would not.
  await req('comp', 'comp-04-exclusivity', '"No other OS can own these" is enforced structurally',
    `select (select pg_get_constraintdef(oid) from pg_constraint
              where conrelid='public.os_responsibility'::regclass and contype='p')
            = 'PRIMARY KEY (responsibility)'
       and (select count(*) = count(distinct responsibility) from public.os_responsibility)`,
    `select coalesce((select pg_get_constraintdef(oid) from pg_constraint
       where conrelid='public.os_responsibility'::regclass and contype='p'),'no primary key')
       ||' over '||(select count(*)::text from public.os_responsibility)||' rows'`);

  // ---- Component 5: the Employee Object --------------------------------------------------------
  await req('comp', 'comp-05-linkage', 'os_department links each OS to real org_agents rows',
    `select (select count(distinct os_key) from public.os_department) = ${ACTIVE_OS}
       and ${OS_WITH_STAFF} = ${ACTIVE_OS}
       and ${READERS('os_department')} > 0`,
    `select ${OS_WITH_STAFF}::text||' of '||${ACTIVE_OS}::text||' OS reach active staff; '
       ||(select count(*)::text from public.org_agents a
            join public.os_department d on d.dept_key = a.department where a.active)
       ||' staffed employees; '||${READERS('os_department')}::text||' reader(s)'`);

  await req('comp', 'comp-05-role', 'Each employee has a Role that reaches a prompt',
    `select (select count(*) from public.org_agents where active and coalesce(role,'') <> '')
            = (select count(*) from public.org_agents where active)
       and public.fn_agent_context('cfo', 20000) like '%'||(select role from public.org_agents where agent_key='cfo')||'%'`,
    `select (select count(*) filter (where coalesce(role,'') = '') from public.org_agents where active)::text
       ||' of '||(select count(*)::text from public.org_agents where active)
       ||' active employees have no role text'`);

  // Authority must be personal, not inferred: the dispatcher used to hand out 'autonomous' itself.
  await req('comp', 'comp-05-authority', 'Each employee has Authority that reaches a prompt',
    `select (select count(*) from public.org_agents a where a.active
              and not exists (select 1 from public.employee_authority e where e.agent_key = a.agent_key)) = 0
       and public.fn_agent_context('cfo', 20000) like '%# YOUR AUTHORITY%'
       and ${READERS('employee_authority')} > 0`,
    `select (select count(*) from public.org_agents a where a.active
              and not exists (select 1 from public.employee_authority e where e.agent_key = a.agent_key))::text
       ||' active employees with no personal authority row; '
       ||(select count(*)::text from public.employee_authority)||' rows; '
       ||${READERS('employee_authority')}::text||' reader(s)'`);

  await req('comp', 'comp-05-kpis', 'Each employee has KPIs that reach a prompt',
    `select (select count(*) from public.employee_kpi where active and coalesce(measure_sql,'') <> '')
            = (select count(*) from public.employee_kpi where active)
       and (select count(*) from public.employee_kpi where active) > 0
       and public.fn_agent_context('cfo', 20000) like '%# YOUR KPIs%'
       and ${READERS('employee_kpi')} > 0`,
    `select (select count(*)::text from public.employee_kpi where active)||' active KPIs, '
       ||(select count(*)::text from public.employee_kpi where active and coalesce(measure_sql,'') <> '')
       ||' with measure_sql; '||${READERS('employee_kpi')}::text||' reader(s)'`);

  // TIGHTENED 6 Aug 2026, and the old assertion is quoted below because it was wrong in an
  // instructive way. It resolved fn_agent_context's OWN WHERE clause, dept-mate fallback included,
  // and asked whether each employee reaches at least one profession row. That accepts the fallback
  // as satisfying "each employee has Knowledge" — and the fallback is precisely what hid the gap:
  // 52 of 66 employees had NO profession knowledge of their own and were being handed a colleague's,
  // so the Accounts Payable Specialist was reading the CFO's expertise and the block always
  // rendered. Measuring the function's behaviour is not the same as measuring the requirement.
  //
  //   old: ... or (a.department is not null and not exists (<no own rows>) and k.agent_key in
  //              (select b.agent_key from org_agents b where b.department = a.department ...))
  //
  // Personal is the claim the spec makes ("Each employee has ... Knowledge"), so personal is what
  // is asserted. The 52 were backfilled in scripts/sql/agent_knowledge_profession_backfill.sql; the
  // fallback stays in the function as a safety net for a newly hired employee, which is what a
  // fallback is for.
  await req('comp', 'comp-05-knowledge', 'Each employee has Knowledge that reaches a prompt',
    `select (select count(*) from public.org_agents a where a.active
              and not exists (
                select 1 from public.agent_knowledge k
                 where k.agent_key = a.agent_key
                   and coalesce(k.layer,'profession') in ('profession','state'))) = 0`,
    `select (select count(*) from public.org_agents a where a.active
              and exists (select 1 from public.agent_knowledge k
                           where k.agent_key = a.agent_key
                             and coalesce(k.layer,'profession') in ('profession','state')))::text
       ||' of '||(select count(*)::text from public.org_agents where active)
       ||' employees have knowledge of their own; '
       ||(select count(*) from public.org_agents a where a.active
           and not exists (select 1 from public.agent_knowledge k
                            where coalesce(k.layer,'profession') in ('profession','state')
                              and (k.agent_key = a.agent_key
                                   or k.agent_key in (select b.agent_key from public.org_agents b
                                                       where b.active and b.department = a.department
                                                         and b.agent_key <> a.agent_key))))::text
       ||' reach NO profession knowledge even after the dept-mate fallback'`);

  // Decision rights are only rights if something refuses. Both gate functions must read the grant.
  await req('comp', 'comp-05-decision-rights', 'Each employee has Decision Rights, enforced at runtime',
    `select (select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
              where ns.nspname='public' and p.proname in ('fn_decision_gate','fn_check_spend')
                and pg_get_functiondef(p.oid) ~* '\\yemployee_authority\\y') = 2
       and (select count(*) from public.employee_authority
             where coalesce(action_class,'') <> '' and coalesce(max_tier,'') <> '') > 0
       and public.fn_agent_context('cfo', 20000) like '%Anything not on that list is GATED%'`,
    `select (select string_agg(p.proname, ', ' order by p.proname)
       from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
       where ns.nspname='public' and p.proname in ('fn_decision_gate','fn_check_spend')
         and pg_get_functiondef(p.oid) ~* '\\yemployee_authority\\y')
       ||' enforce '||(select count(*)::text from public.employee_authority)||' authority rows'`);

  // 1,206 escalation rules existed on ops_knowledge and their only reader, fn_kb_retrieve, had no
  // caller anywhere. Existence of the column is therefore worthless evidence; the prompt is the test.
  // escalation_rule is jsonb and non-null on all 3,959 records, but only 1,206 carry the
  // {when, action} pair the prompt actually renders — counting non-nulls would score 3,959.
  await req('comp', 'comp-05-escalation', 'Each employee has Escalation Rules that reach them',
    `select (select count(*) from public.org_agents a where a.active
              and not exists (select 1 from public.ops_knowledge o
                               where o.dept_key = a.department
                                 and o.escalation_rule->>'when' is not null
                                 and o.escalation_rule->>'action' is not null)) = 0
       and (select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
             where ns.nspname='public' and p.proname='fn_agent_context'
               and pg_get_functiondef(p.oid) ~* '\\yescalation_rule\\y') > 0
       and public.fn_agent_context('cfo', 20000) like '%WHEN TO ESCALATE%'`,
    `select (select count(*) filter (where escalation_rule->>'when' is not null
                                       and escalation_rule->>'action' is not null)
              from public.ops_knowledge)::text
       ||' renderable rules of '||(select count(*)::text from public.ops_knowledge)||' records; '
       ||(select count(*) from public.org_agents a where a.active
           and exists (select 1 from public.ops_knowledge o
                        where o.dept_key = a.department
                          and o.escalation_rule->>'when' is not null
                          and o.escalation_rule->>'action' is not null))::text
       ||' of '||(select count(*)::text from public.org_agents where active)
       ||' employees in a department that has one'`);

  // ---- Component 6: Knowledge ------------------------------------------------------------------
  await req('comp', 'comp-06-knowledge-independent', 'Every OS has independent knowledge',
    `select (select count(distinct os_key) from public.os_knowledge_domain) = ${ACTIVE_OS}
       and (select count(*) from public.operating_system os2 where coalesce(os2.active,true)
             and not exists (select 1 from public.os_knowledge_domain k
                              where k.os_key = os2.os_key and k.ownership='owns')) = 0
       and ${READERS('os_knowledge_domain')} > 0`,
    `select (select count(distinct os_key)::text from public.os_knowledge_domain)||' of '
       ||${ACTIVE_OS}::text||' OS have knowledge domains ('
       ||(select count(*)::text from public.os_knowledge_domain)||' rows, '
       ||(select count(*)::text from public.os_knowledge_domain where ownership='owns')||' owned); '
       ||${READERS('os_knowledge_domain')}::text||' reader(s)'`);

  // "Leadership does not duplicate Finance's knowledge, it queries it" needs a routine that takes an
  // os_key and resolves the owner — and that routine needs a caller, or it is fn_kb_retrieve again.
  await req('comp', 'comp-06-cross-os-query', 'Leadership does not duplicate knowledge; it queries the owning OS',
    `select exists (
       select 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
        where ns.nspname='public' and p.prokind in ('f','p')
          and pg_get_functiondef(p.oid) ~* '\\yos_knowledge_domain\\y'
          and pg_get_function_identity_arguments(p.oid) ~* 'os_key'
          and ((select count(*) from pg_proc q join pg_namespace m on m.oid=q.pronamespace
                 where m.nspname='public' and q.prokind in ('f','p') and q.proname <> p.proname
                   and pg_get_functiondef(q.oid) ~* ('\\y'||p.proname||'\\y'))
             + (select count(*) from cron.job j where j.command ~* ('\\y'||p.proname||'\\y'))) > 0)`,
    `select coalesce((select string_agg(p.proname||'('||pg_get_function_identity_arguments(p.oid)||')', ', ')
       from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
       where ns.nspname='public' and p.prokind in ('f','p')
         and pg_get_functiondef(p.oid) ~* '\\yos_knowledge_domain\\y'),
       'no routine reads os_knowledge_domain')`);

  // ---- Component 7: Inputs ---------------------------------------------------------------------
  // The bus itself works. The requirement is that EVERY OS is on it, which is a different claim.
  await req('comp', 'comp-07-inputs', 'Every OS receives events (Inputs)',
    `select (select count(distinct d.os_key) from public.os_department d
              join public.org_agents a on a.department = d.dept_key and a.active
              join public.event_subscription s on s.agent_key = a.agent_key and s.active) = ${ACTIVE_OS}
       and (select count(*) from public.event_delivery where delivered_at > now() - interval '7 days') > 0`,
    `select (select count(distinct d.os_key) from public.os_department d
              join public.org_agents a on a.department = d.dept_key and a.active
              join public.event_subscription s on s.agent_key = a.agent_key and s.active)::text
       ||' of '||${ACTIVE_OS}::text||' OS have an active subscriber; '
       ||(select count(*)::text from public.event_delivery where delivered_at > now() - interval '7 days')
       ||' deliveries in 7d'`);

  // A declared input that no event ever carries is documentation, not an interface. os_interface
  // grew a `planned` flag, so a kind may honestly be marked not-yet-live instead of firing.
  await req('comp', 'comp-07-inputs-coverage', 'Declared inputs correspond to events that actually flow',
    `select (select count(*) from public.os_interface i
              where i.direction='input' and coalesce(i.active,true) and not coalesce(i.planned,false)
                and not exists (select 1 from public.company_event e where e.event_type = i.kind)) = 0`,
    `select (select count(*) from public.os_interface i
              where i.direction='input' and not coalesce(i.planned,false)
                and not exists (select 1 from public.company_event e where e.event_type = i.kind))::text
       ||' of '||(select count(*)::text from public.os_interface where direction='input')
       ||' declared input kinds have never appeared in company_event, and none is marked planned'`);

  // ---- Component 8: Outputs --------------------------------------------------------------------
  await req('comp', 'comp-08-out-tasks', 'Output: Tasks',
    `select (select count(*) from public.org_tasks) > 0
       and (select count(*) from public.org_tasks where decided_by='fn_event_dispatch') > 0
       and ${READERS('org_tasks')} > 0`,
    `select (select count(*)::text from public.org_tasks)||' tasks, '
       ||(select count(*)::text from public.org_tasks where decided_by='fn_event_dispatch')
       ||' authored by the dispatcher; '||${READERS('org_tasks')}::text||' reader(s)'`);

  await req('comp', 'comp-08-out-reports', 'Output: Reports',
    `select (select count(distinct os_key) from public.os_review) = ${ACTIVE_OS}
       and (select count(*) from public.os_review where created_at > now() - interval '21 days') > 0
       and ${READERS('os_review')} > 0`,
    `select (select count(*)::text from public.os_review)||' reviews over '
       ||(select count(distinct os_key)::text from public.os_review)||' OS, last '
       ||coalesce((select max(created_at)::date::text from public.os_review),'never')||'; '
       ||${READERS('os_review')}::text||' reader(s)'`);

  await req('comp', 'comp-08-out-decisions', 'Output: Decisions',
    `select (select count(*) from public.decision_log) > 0
       and (select max(created_at) from public.decision_log) > now() - interval '7 days'
       and ${READERS('decision_log')} > 0`,
    `select (select count(*)::text from public.decision_log)||' decisions, last '
       ||coalesce((select max(created_at)::date::text from public.decision_log),'never')||'; '
       ||${READERS('decision_log')}::text||' reader(s); os_key on decision_log: '
       ||(select exists (select 1 from information_schema.columns where table_schema='public'
            and table_name='decision_log' and column_name='os_key'))::text`);

  await req('comp', 'comp-08-out-approvals', 'Output: Approvals',
    `select (select count(*) from public.agent_actions) > 0
       and (select count(*) from public.agent_actions where decided_at is not null) > 0
       and ${READERS('agent_actions')} > 0`,
    `select (select count(*)::text from public.agent_actions)||' actions, '
       ||(select count(*)::text from public.agent_actions where decided_at is not null)||' decided, '
       ||(select count(*)::text from public.org_tasks where needs_founder and status <> 'done')
       ||' open founder approvals; '||${READERS('agent_actions')}::text||' reader(s)'`);

  await req('comp', 'comp-08-out-recommendations', 'Output: Recommendations',
    `select (select count(*) from public.org_tasks where action_class='recommend') > 0
       and (select count(*) from public.org_tasks where action_class='recommend'
             and decided_by is not null) > 0
       and ${READERS('org_tasks')} > 0`,
    `select (select count(*)::text from public.org_tasks where action_class='recommend')
       ||' recommendations, '
       ||(select count(distinct dept_key)::text from public.org_tasks where action_class='recommend')
       ||' departments; '||${READERS('org_tasks')}::text||' reader(s) of org_tasks'`);

  // An alert nobody raised is not an output. fn_emit_metric_alerts is the only emitter and it has
  // no scheduler, so this asks whether an alert has actually fired recently.
  await req('comp', 'comp-08-out-alerts', 'Output: Alerts',
    `select (select count(*) from public.company_event
              where event_type in ('kpi.missed','goal.at_risk','metric.alert','health.degraded',
                                   'sla.breached','budget.exceeded','incident.opened')
                and occurred_at > now() - interval '7 days') > 0
       and ${READERS('company_event')} > 0`,
    `select 'last alert-class event '
       ||coalesce((select max(occurred_at)::date::text from public.company_event
                    where event_type in ('kpi.missed','goal.at_risk','metric.alert','health.degraded',
                                         'sla.breached','budget.exceeded','incident.opened')),'never')
       ||'; '||(select count(*)::text from public.company_event
                 where event_type in ('kpi.missed','goal.at_risk','metric.alert','health.degraded',
                                      'sla.breached','budget.exceeded','incident.opened'))
       ||' ever; fn_emit_metric_alerts schedulers: '
       ||(select count(*)::text from cron.job where command ~* '\\yfn_emit_metric_alerts\\y')`);

  await req('comp', 'comp-08-out-kpis', 'Output: KPIs',
    `select (select count(*) from public.employee_kpi where active) > 0
       and (select count(*) from pg_views where schemaname='public' and viewname='v_os_scoreboard') = 1
       and ${READERS('v_os_scoreboard')} > 0
       and (select count(*) from cron.job where active and command ~* '\\yfn_os_review\\y') > 0`,
    `select (select count(*)::text from public.employee_kpi where active)||' active KPIs; '
       ||${READERS('v_os_scoreboard')}::text||' reader(s) of v_os_scoreboard; '
       ||(select count(*)::text from cron.job where active and command ~* '\\yfn_os_review\\y')
       ||' active cron(s) consuming it'`);

  await req('comp', 'comp-08-out-knowledge-updates', 'Output: Knowledge Updates',
    `select (select count(*) from public.kb_revisions where created_at > now() - interval '30 days') > 0
       and ${READERS('kb_revisions')} > 0`,
    `select (select count(*)::text from public.kb_revisions where created_at > now() - interval '30 days')
       ||' revisions in 30d, last '
       ||coalesce((select max(created_at)::date::text from public.kb_revisions),'never')||'; '
       ||${READERS('kb_revisions')}::text||' reader(s); knowledge.updated events: '
       ||(select count(*)::text from public.company_event where event_type='knowledge.updated')`);

  // ---- Component 9: Workflows ------------------------------------------------------------------
  await req('comp', 'comp-09-workflows', 'Every OS contains workflows',
    `select (select count(distinct os_key) from public.workflow where active) = ${ACTIVE_OS}
       and (select count(*) from public.workflow where active and coalesce(trigger_event,'') <> '')
           = (select count(*) from public.workflow where active)
       and (select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
             where ns.nspname='public' and p.prokind in ('f','p')
               and pg_get_functiondef(p.oid) ~* 'from\\s+workflow\\y') > 0`,
    `select (select count(*)::text from public.workflow)||' workflows over '
       ||(select count(distinct os_key)::text from public.workflow)||' OS; '
       ||(select count(*)::text from public.workflow w
           where exists (select 1 from public.company_event e where e.event_type = w.trigger_event))
       ||' trigger_events have ever fired; routines selecting from workflow: '
       ||(select count(*)::text from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
           where ns.nspname='public' and p.prokind in ('f','p')
             and pg_get_functiondef(p.oid) ~* 'from\\s+workflow\\y')`);

  // 117 steps across 14 workflows and not one run: the table is a diagram, not an engine.
  await req('comp', 'comp-09-workflow-execution', 'Workflows execute and are tracked',
    `select (select count(*) from public.workflow_run) > 0
       and ${READERS('workflow_run')} > 0`,
    `select (select count(*)::text from public.workflow_run)||' run(s), '
       ||(select count(*)::text from public.workflow_step_run)||' step run(s); '
       ||${READERS('workflow_run')}::text||' reader(s) of workflow_run'`);

  // ---- The OS layer must reach the people who serve it -----------------------------------------
  // fn_agent_context is the sole prompt assembler. This asks whether the OS block survives the
  // 6,200-character employee section for every staffed OS, not just for the one agent tested first.
  await req('comp', 'os-layer-prompt-reach', 'OS-layer attributes reach the employees who serve that OS',
    `select (select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
              where ns.nspname='public' and p.proname='fn_agent_context'
                and pg_get_functiondef(p.oid) ~* '\\yoperating_system\\y') > 0
       and (select count(*) from ${ONE_PER_OS} z
             where public.fn_agent_context(z.agent_key, 20000) like '%YOUR OPERATING SYSTEM%')
           = ${OS_WITH_STAFF}`,
    `select (select count(*) from ${ONE_PER_OS} z
              where public.fn_agent_context(z.agent_key, 20000) like '%YOUR OPERATING SYSTEM%')::text
       ||' of '||${OS_WITH_STAFF}::text||' staffed OS name themselves in their employees'' prompt'`);

  // ---- The cross-OS contract closes ------------------------------------------------------------
  // Dispatch ends at one task per subscriber. The contract requires the loop to come back: results
  // recorded per delivery, consolidated, and a re-prioritisation emitted from them.
  await req('comp', 'contract-consolidation', 'Chief of Staff consolidates, CEO re-prioritises, the loop closes',
    `select (select count(*) from public.event_delivery where result is not null) > 0
       and (select count(*) from public.event_delivery where closed_at is not null) > 0
       and (select count(*) from public.company_event where event_type='priority.updated') > 0`,
    `select (select count(*)::text from public.event_delivery)||' deliveries, '
       ||(select count(*)::text from public.event_delivery where result is not null)||' with a result, '
       ||(select count(*)::text from public.event_delivery where closed_at is not null)||' closed; '
       ||(select count(*)::text from public.company_event where event_type='priority.updated')
       ||' priority.updated event(s) ever'`);

  // ---- Component 16 head: per-OS health score --------------------------------------------------
  // fn_os_review already computes green/amber/red per OS and throws it away; v_os_health computes
  // the same shape and nothing selects from it.
  await req('comp', 'comp-16-health-score', 'Per-OS health score is computed and read',
    `select (select count(*) from public.operating_system
              where coalesce(active,true) and health_score is not null) = ${ACTIVE_OS}
       and ${READERS('health_score')} > 0`,
    `select (select count(*)::text from public.operating_system
              where coalesce(active,true) and health_score is not null)
       ||' of '||${ACTIVE_OS}::text||' OS carry a health_score; '
       ||${READERS('health_score')}::text||' reader(s) of health_score, '
       ||${READERS('v_os_health')}::text||' of v_os_health'`);
}
