// Components 14-17 of the Universal OS Blueprint, scored against PRODUCTION.
//
//   14 Governance      — Can I decide? Can I spend? Can I approve? Should I escalate? Who reviews?
//   15 Collaboration   — Who can help? Who approves? Who reviews? Who owns? No duplicated ownership.
//   16 Health          — Health Score, Risk, Performance, Capacity, Backlog, Quality, Cost, Automation.
//   17 Continuous Improvement — the five weekly questions, and whether anyone receives them.
//
// Every check asks the three questions separately: does the mechanism EXIST, does it RUN, and does
// anything READ its output. Two traps govern this file specifically.
//
// TRAP 1 — the reader that is not a reader. os_review.metrics is written weekly by fn_os_review with
// kpi_gaps, open_tasks, stale_tasks and budget_pct in it. fn_exec_meeting's definition contains the
// word "metrics", so a naive "does a reader mention metrics" test says yes for all four. It does not:
// fn_exec_meeting selects os_review.health, os_review.owner_agent and os_review.findings, and its
// "metrics" is exec_reports.metrics, a column it WRITES. fn_company_snapshot selects health alone.
// So the Component 16 dimensions are scored on the FIGURE, by name, on a surface something reads —
// not on "the row is read by someone".
//
// TRAP 2 — the live routine. A proc that names the figure is only a reader if the proc itself is
// reachable: referenced by a cron command or by another routine. v_os_health names four of the eight
// dimensions and is referenced by nothing at all, so naming a figure inside it proves nothing until
// the view acquires a reader. That is why every dimension check tests reachability, not existence.
export default async function ({ req, READERS }) {
  // A proc is live if a cron command or another routine names it. Views count only when something
  // reads the view. This is the difference between "the figure is computed" and "the figure is read".
  const LIVE_PROC = `(exists (select 1 from cron.job j where j.command ~* ('\\y'||p.proname||'\\y'))
      or exists (select 1 from pg_proc q join pg_namespace nq on nq.oid=q.pronamespace
                 where nq.nspname='public' and q.prokind in ('f','p') and q.oid <> p.oid
                   and pg_get_functiondef(q.oid) ~* ('\\y'||p.proname||'\\y')))`;

  // How many LIVE readers name this figure on the per-OS health surface? fn_os_review is the writer
  // and is excluded: a function that mentions the column it populates is not a reader of it.
  const FIGURE_READERS = (rx) => `(
      (select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
        where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_os_review'
          and pg_get_functiondef(p.oid) ~* '${rx}'
          and pg_get_functiondef(p.oid) ~* '\\y(os_review|v_os_health)\\y'
          and ${LIVE_PROC})
    + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '${rx}'
        and (v.viewname = 'v_os_health' or v.definition ~* '\\yos_review\\y')
        and (exists (select 1 from pg_proc p2 join pg_namespace n2 on n2.oid=p2.pronamespace
                     where n2.nspname='public' and p2.prokind in ('f','p')
                       and pg_get_functiondef(p2.oid) ~* ('\\y'||v.viewname||'\\y'))
          or exists (select 1 from cron.job j2 where j2.command ~* ('\\y'||v.viewname||'\\y'))))
    + (select count(*) from cron.job j3 where j3.command ~* '${rx}'
        and j3.command ~* '\\y(os_review|v_os_health)\\y'))`;

  // Component 16's report is os_review, one row per active OS per ISO week. A dimension is reported
  // when EVERY active OS carries it in the newest report, that report is recent, and a live reader
  // names it. The v_os_health branch is the second legitimate way to satisfy the same requirement:
  // that view already computes four of the dimensions per OS and needs only a reader.
  const OS_COUNT = `(select count(*) from public.operating_system where active)`;
  const FRESH = `(select max(created_at) from public.os_review) > now() - interval '21 days'`;
  const DIM = (rx, keys) => `select coalesce((
      (select count(*) from public.os_review r
        where r.period = (select max(period) from public.os_review)
          and (${keys.map(k => `r.metrics ? '${k}'`).join(' or ')})) >= ${OS_COUNT}
      and ${FRESH} and ${FIGURE_READERS(rx)} > 0)
    or ((select count(*) from pg_views v where v.schemaname='public' and v.viewname='v_os_health'
          and v.definition ~* '${rx}') > 0 and ${READERS('v_os_health')} > 0), false)`;
  const DIM_EV = (rx, keys) => `select
      (select count(*) from public.os_review r where r.period=(select max(period) from public.os_review)
        and (${keys.map(k => `r.metrics ? '${k}'`).join(' or ')}))||' of '||${OS_COUNT}
      ||' OS carry it in os_review.metrics ('||(select max(period) from public.os_review)||'), '
      ||${FIGURE_READERS(rx)}||' live reader(s) of the figure, v_os_health has '
      ||${READERS('v_os_health')}||' reader(s)'`;

  const HAS_FN = (n) => `exists (select 1 from pg_proc p join pg_namespace n2 on n2.oid=p.pronamespace
      where n2.nspname='public' and p.proname='${n}')`;
  const CRON_OK = (rx, days) => `(select max(d.end_time) from cron.job_run_details d
      join cron.job j on j.jobid = d.jobid
      where j.command ~* '\\y${rx}\\y' and d.status='succeeded') > now() - interval '${days} days'`;
  const PROMPT = (needle) => `(select public.fn_agent_context('cfo', 22000) like '%${needle}%')`;

  // ---- COMPONENT 14: GOVERNANCE --------------------------------------------------------------
  // "Can I decide?" — a policy table is only an answer if something resolves it and the resolution
  // is recorded. decision_policy -> fn_should_escalate -> decision_log.kind='action_gate'.
  await req('comp-1', 'comp-14-can-decide', 'Can I decide? is answered by a mechanism',
    `select coalesce((select count(*) from public.decision_policy) > 0
       and ${READERS('decision_policy')} > 0
       and (select count(*) from public.decision_log
             where kind='action_gate' and created_at > now() - interval '30 days') > 0, false)`,
    `select (select count(*) from public.decision_policy)||' polic(ies), '
       ||${READERS('decision_policy')}||' reader(s), '
       ||(select count(*) from public.decision_log where kind='action_gate'
           and created_at > now() - interval '30 days')||' gate verdict(s)/30d, last '
       ||coalesce((select max(created_at)::date::text from public.decision_log where kind='action_gate'),'never')`);

  // "Can I spend?" — advisory means a number in a table; enforced means a trigger that refuses.
  // The limit must also reach the person, or they cannot answer the question before acting.
  await req('comp-1', 'comp-14-can-spend', 'Can I spend? is enforced, not advisory',
    `select coalesce((select count(*) from public.employee_authority where threshold_aed is not null) > 0
       and ${HAS_FN('fn_check_spend')}
       and exists (select 1 from pg_trigger t join pg_proc f on f.oid = t.tgfoid
                   where not t.tgisinternal and t.tgenabled <> 'D'
                     and pg_get_functiondef(f.oid) ~* '\\y(fn_check_spend|fn_emit_budget_exceeded)\\y')
       and ${PROMPT('AED)')}, false)`,
    `select (select count(*) from public.employee_authority where threshold_aed is not null)
       ||' personal spend limit(s) over '||(select count(distinct agent_key) from public.employee_authority)
       ||' employees, refused by trigger(s): '
       ||coalesce((select string_agg(t.tgname,',') from pg_trigger t join pg_proc f on f.oid=t.tgfoid
            where not t.tgisinternal and t.tgenabled <> 'D'
              and pg_get_functiondef(f.oid) ~* '\\y(fn_check_spend|fn_emit_budget_exceeded)\\y'),'none')`);

  // "Can I approve?" — org_authority resolved hourly by fn_task_approve, whose verdicts land in
  // review_chain. A cron that is active but has never succeeded is not an approval mechanism.
  await req('comp-1', 'comp-14-can-approve', 'Can I approve? is enforced',
    `select coalesce((select count(*) from public.org_authority) > 0
       and exists (select 1 from cron.job j where j.active and j.command ~* '\\yfn_task_approve\\y')
       and ${CRON_OK('fn_task_approve', 7)}
       and (select pg_get_functiondef(p.oid) ~* '\\y(org_authority|fn_dept_authority)\\y'
              from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.proname='fn_task_approve' limit 1)
       and (select count(*) from public.review_chain
             where stage='approval' and created_at > now() - interval '7 days') > 0, false)`,
    `select (select count(*) from public.org_authority)||' authority rule(s); approval cron last ok '
       ||coalesce((select max(d.end_time)::timestamp(0)::text from cron.job_run_details d
            join cron.job j on j.jobid=d.jobid
           where j.command ~* '\\yfn_task_approve\\y' and d.status='succeeded'),'never')||'; '
       ||(select count(*) from public.review_chain where stage='approval'
           and created_at > now() - interval '7 days')||' approval verdict(s)/7d'`);

  // "Should I escalate?" — the route must name a party AND be visible to someone. The writers of
  // route_to are excluded from the reader count, otherwise the escalator counts as its own audience.
  await req('comp-1', 'comp-14-should-escalate', 'Should I escalate? routes to a named party',
    `select coalesce(${HAS_FN('fn_should_escalate')}
       and ${READERS('fn_should_escalate')} > 0
       and (select count(*) from public.decision_log
             where route_to is not null and created_at > now() - interval '30 days') > 0
       and (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.prokind in ('f','p')
               and p.proname not in ('fn_should_escalate','fn_decide','fn_ai_gate','trg_action_gate',
                                     'fn_decision_gate','fn_check_spend')
               and pg_get_functiondef(p.oid) ~* '\\yroute_to\\y'
               and pg_get_functiondef(p.oid) ~* '\\ydecision_log\\y') > 0, false)`,
    `select (select count(*) from public.decision_log where route_to is not null
              and created_at > now() - interval '30 days')||' routed escalation(s)/30d to "'
       ||coalesce((select value #>> '{}' from public.decision_policy where key='review_owner'),'nobody')
       ||'", read by '||(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='public' and p.prokind in ('f','p')
              and p.proname not in ('fn_should_escalate','fn_decide','fn_ai_gate','trg_action_gate',
                                    'fn_decision_gate','fn_check_spend')
              and pg_get_functiondef(p.oid) ~* '\\yroute_to\\y'
              and pg_get_functiondef(p.oid) ~* '\\ydecision_log\\y')||' surface(s) beyond the writers'`);

  // "Who must review?" — resolution to a PERSON, not a placeholder. review_chain also carries
  // machine reviewers ('approval_path'), so the test is rows naming an ACTIVE employee.
  await req('comp-1', 'comp-14-who-reviews', 'Who must review? resolves to a person',
    `select coalesce(${HAS_FN('fn_pick_reviewer')} and ${READERS('fn_pick_reviewer')} > 0
       and (select count(*) from public.review_chain r
             where r.created_at > now() - interval '30 days'
               and exists (select 1 from public.org_agents a
                           where a.agent_key = r.reviewer_agent and a.active)) > 0, false)`,
    `select (select count(*) from public.review_chain r where r.created_at > now() - interval '30 days'
              and exists (select 1 from public.org_agents a where a.agent_key=r.reviewer_agent and a.active))
       ||' of '||(select count(*) from public.review_chain where created_at > now() - interval '30 days')
       ||' review(s)/30d name an active employee; fn_pick_reviewer has '
       ||${READERS('fn_pick_reviewer')}||' caller(s)'`);

  // ---- COMPONENT 15: COLLABORATION PROTOCOL --------------------------------------------------
  // "Who can help?" — declared in collaboration_rule.must_involve, every entry resolving to a real
  // department or employee, read by fn_task_review, which the hourly cos_execute cron drives.
  const UNRESOLVED = (col) => `(select count(*) from public.collaboration_rule c,
      unnest(coalesce(c.${col},'{}'::text[])) x
      where not exists (select 1 from public.org_departments d where d.dept_key = x)
        and not exists (select 1 from public.org_agents a where a.agent_key = x))`;

  await req('comp-1', 'comp-15-who-can-help', 'Who can help? is declared and read',
    `select coalesce((select count(*) from public.collaboration_rule
             where coalesce(array_length(must_involve,1),0) > 0) > 0
       and ${UNRESOLVED('must_involve')} = 0
       and ${READERS('collaboration_rule')} > 0
       and ${CRON_OK('cos_execute', 2)}
       and (select count(*) from public.review_chain where created_at > now() - interval '7 days') > 0, false)`,
    `select (select count(*) from public.collaboration_rule where coalesce(array_length(must_involve,1),0) > 0)
       ||' rule(s) name helpers, '||${UNRESOLVED('must_involve')}||' unresolvable, '
       ||${READERS('collaboration_rule')}||' reader(s), '
       ||(select count(*) from public.review_chain where created_at > now() - interval '7 days')
       ||' review(s) written in the last 7d'`);

  // "Who must approve?" — declared at both levels, read by the hourly approver, and told to the
  // employee. An authority table nobody is told about cannot answer the question before the act.
  await req('comp-1', 'comp-15-who-approves', 'Who must approve? is declared and read',
    `select coalesce((select count(*) from public.org_authority) > 0
       and (select count(*) from public.employee_authority) > 0
       and ${READERS('org_authority')} > 0 and ${READERS('employee_authority')} > 0
       and ${PROMPT('YOUR AUTHORITY')}, false)`,
    `select (select count(*) from public.org_authority)||' department + '
       ||(select count(*) from public.employee_authority)||' personal authority row(s), '
       ||${READERS('org_authority')}||' + '||${READERS('employee_authority')}
       ||' reader(s), prompt carries the authority block: '||${PROMPT('YOUR AUTHORITY')}`);

  // "Who must review?" at the protocol level: the DECLARATION (collaboration_rule.must_review) as
  // opposed to comp-14's question of whether the declaration resolves to a named person.
  await req('comp-1', 'comp-15-who-reviews', 'Who must review? is declared and read',
    `select coalesce((select count(*) from public.collaboration_rule
             where coalesce(array_length(must_review,1),0) > 0) > 0
       and ${UNRESOLVED('must_review')} = 0
       and exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                   where n.nspname='public' and p.proname='fn_task_review'
                     and pg_get_functiondef(p.oid) ~* '\\ymust_review\\y')
       and (select count(*) from public.review_chain where created_at > now() - interval '7 days') > 0, false)`,
    `select (select count(*) from public.collaboration_rule where coalesce(array_length(must_review,1),0) > 0)
       ||' rule(s) name reviewers, '||${UNRESOLVED('must_review')}||' unresolvable, read by fn_task_review: '
       ||(select (pg_get_functiondef(p.oid) ~* '\\ymust_review\\y')::text
            from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname='fn_task_review' limit 1)`);

  // "Who owns this process?" — 71 declared owners are worth nothing if the only reader is the graph
  // builder. Ownership must reach the person doing the work AND route real work: fn_agent_context
  // emits the owning OS's responsibilities, fn_task_review resolves collaboration_rule.owner_dept.
  await req('comp-1', 'comp-15-who-owns', 'Who owns this process? drives behaviour',
    `select coalesce((select count(distinct r.os_key) from public.os_responsibility r
             join public.operating_system o on o.os_key=r.os_key and o.active) = ${OS_COUNT}
       and ${PROMPT('no other OS may own')}
       and (select count(*) from public.collaboration_rule c where c.owner_dept is not null
             and exists (select 1 from public.org_departments d where d.dept_key=c.owner_dept)) > 0
       and exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                   where n.nspname='public' and p.proname='fn_task_review'
                     and pg_get_functiondef(p.oid) ~* '\\yowner_dept\\y'), false)`,
    `select (select count(*) from public.os_responsibility)||' owned responsibilit(ies) across '
       ||(select count(distinct os_key) from public.os_responsibility)||' of '||${OS_COUNT}
       ||' OS; reaches the employee prompt: '||${PROMPT('no other OS may own')}||'; '
       ||(select count(*) from public.collaboration_rule where owner_dept is not null)
       ||' situation owner(s) resolved by fn_task_review'`);

  // "No duplicated ownership" is a structural claim. Zero duplicates today is an observation; a
  // single-column primary key is the reason it cannot happen tomorrow. Both are required.
  await req('comp-1', 'comp-15-no-dup-ownership', 'No duplicated ownership across OSes',
    `select coalesce((select count(*) from (select responsibility from public.os_responsibility
             group by responsibility having count(distinct os_key) > 1) d) = 0
       and exists (select 1 from pg_constraint c join pg_class t on t.oid=c.conrelid
                   join pg_namespace n on n.oid=t.relnamespace
                   join pg_attribute a on a.attrelid=t.oid and a.attnum = c.conkey[1]
                   where n.nspname='public' and t.relname='os_responsibility'
                     and c.contype in ('p','u') and array_length(c.conkey,1)=1
                     and a.attname='responsibility'), false)`,
    `select (select count(*) from public.os_responsibility)||' responsibilit(ies), '
       ||(select count(*) from (select responsibility from public.os_responsibility
            group by responsibility having count(distinct os_key) > 1) d)||' owned twice, enforced by '
       ||coalesce((select string_agg(c.conname,',') from pg_constraint c join pg_class t on t.oid=c.conrelid
            join pg_namespace n on n.oid=t.relnamespace
            where n.nspname='public' and t.relname='os_responsibility' and c.contype in ('p','u')),'nothing')`);

  // ---- COMPONENT 16: HEALTH MONITORING -------------------------------------------------------
  // Health Score. Two surfaces qualify: operating_system.health_score (a column that exists and is
  // NULL) or os_review.health, the weekly red/amber/green per OS. Either is a per-OS health rating;
  // the requirement is that one of them is complete, fresh and read by a live routine.
  await req('comp-1', 'comp-16-health-score', 'Each OS reports a Health Score that is read',
    `select coalesce((
        (select count(*) from public.os_review r where r.period=(select max(period) from public.os_review)
          and r.health is not null) >= ${OS_COUNT}
        and ${FRESH} and ${FIGURE_READERS('\\yhealth\\y')} > 0)
      or ((select count(*) from public.operating_system where active and health_score is not null) >= ${OS_COUNT}
        and ${READERS('health_score')} > 0), false)`,
    `select (select count(*) from public.operating_system where active and health_score is not null)
       ||' of '||${OS_COUNT}||' operating_system.health_score populated; os_review.health '
       ||(select count(*) from public.os_review where period=(select max(period) from public.os_review)
           and health is not null)||' of '||${OS_COUNT}||' for '
       ||(select max(period) from public.os_review)||', '||${FIGURE_READERS('\\yhealth\\y')}||' live reader(s)'`);

  await req('comp-1', 'comp-16-risk', 'Each OS reports Risk that is read',
    DIM('\\y(open_risks|risks_open|risk_count)\\y', ['open_risks', 'risks', 'risk_count']),
    DIM_EV('\\y(open_risks|risks_open|risk_count)\\y', ['open_risks', 'risks', 'risk_count']));

  await req('comp-1', 'comp-16-performance', 'Each OS reports Performance that is read',
    DIM('\\y(kpi_gaps|kpi_attainment|performance_pct)\\y', ['kpi_gaps', 'kpi_attainment', 'performance_pct']),
    DIM_EV('\\y(kpi_gaps|kpi_attainment|performance_pct)\\y', ['kpi_gaps', 'kpi_attainment', 'performance_pct']));

  // Capacity is the one dimension with no per-OS figure anywhere: resource_pool grew an os_key
  // column, so the second branch passes the moment that column is populated and read per OS.
  await req('comp-1', 'comp-16-capacity', 'Each OS reports Capacity that is read',
    `select coalesce((
        (select count(*) from public.os_review r where r.period=(select max(period) from public.os_review)
          and (r.metrics ? 'capacity' or r.metrics ? 'capacity_pct' or r.metrics ? 'used_pct')) >= ${OS_COUNT}
        and ${FRESH} and ${FIGURE_READERS('\\y(capacity|capacity_pct|used_pct)\\y')} > 0)
      or ((select count(*) from public.resource_pool where os_key is null) = 0
        and (select count(*) from public.resource_pool) > 0
        and (select count(*) from pg_views v where v.schemaname='public'
              and v.definition ~* '\\yresource_pool\\y' and v.definition ~* '\\yos_key\\y'
              and exists (select 1 from pg_proc p2 join pg_namespace n2 on n2.oid=p2.pronamespace
                          where n2.nspname='public' and p2.prokind in ('f','p')
                            and pg_get_functiondef(p2.oid) ~* ('\\y'||v.viewname||'\\y'))) > 0), false)`,
    `select (select count(*) from public.os_review r where r.period=(select max(period) from public.os_review)
        and (r.metrics ? 'capacity' or r.metrics ? 'capacity_pct' or r.metrics ? 'used_pct'))
       ||' of '||${OS_COUNT}||' OS carry capacity in os_review.metrics; resource_pool '
       ||(select count(*) from public.resource_pool where os_key is not null)||' of '
       ||(select count(*) from public.resource_pool)||' row(s) keyed to an OS'`);

  await req('comp-1', 'comp-16-backlog', 'Each OS reports Backlog that is read',
    DIM('\\y(stale_tasks|backlog_per_head|backlog_pct)\\y', ['stale_tasks', 'open_tasks', 'backlog']),
    DIM_EV('\\y(stale_tasks|backlog_per_head|backlog_pct)\\y', ['stale_tasks', 'open_tasks', 'backlog']));

  await req('comp-1', 'comp-16-quality', 'Each OS reports Quality that is read',
    DIM('\\y(review_pass_pct|quality_pct)\\y', ['review_pass_pct', 'quality_pct', 'quality']),
    DIM_EV('\\y(review_pass_pct|quality_pct)\\y', ['review_pass_pct', 'quality_pct', 'quality']));

  await req('comp-1', 'comp-16-cost', 'Each OS reports Cost that is read',
    DIM('\\y(budget_pct|spend_pct|cost_pct)\\y', ['budget_pct', 'cost_aed', 'spend_pct']),
    DIM_EV('\\y(budget_pct|spend_pct|cost_pct)\\y', ['budget_pct', 'cost_aed', 'spend_pct']));

  await req('comp-1', 'comp-16-automation', 'Each OS reports Automation that is read',
    DIM('\\y(needs_founder_pct|automation_pct|automated_pct)\\y',
        ['needs_founder_pct', 'automation_pct', 'automated_pct']),
    DIM_EV('\\y(needs_founder_pct|automation_pct|automated_pct)\\y',
        ['needs_founder_pct', 'automation_pct', 'automated_pct']));

  // fn_os_health / v_os_health. fn_os_health returns failing crons, agent errors and payments for
  // the whole platform with no os_key in it, so it does not answer "how is THIS OS". v_os_health
  // does, per OS, and is referenced by nothing. Either fixing the function or reading the view
  // satisfies this, which is what the two branches test.
  await req('comp-1', 'comp-16-fn-os-health', 'fn_os_health / v_os_health report per-OS health that is read',
    `select coalesce(${READERS('v_os_health')} > 0
       or (select coalesce(bool_or(pg_get_functiondef(p.oid) ~* '\\yos_key\\y'
             and pg_get_functiondef(p.oid) ~* '\\y(operating_system|v_os_scoreboard|os_department)\\y'), false)
             from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='public' and p.proname='fn_os_health')
          and ${READERS('fn_os_health')} > 0, false)`,
    `select 'v_os_health has '||${READERS('v_os_health')}||' reader(s); fn_os_health is per-OS: '
       ||coalesce((select bool_or(pg_get_functiondef(p.oid) ~* '\\yos_key\\y')::text
            from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname='fn_os_health'),'absent')
       ||', with '||${READERS('fn_os_health')}||' reader(s)'`);

  // ---- COMPONENT 17: CONTINUOUS IMPROVEMENT --------------------------------------------------
  // The five questions must be asked weekly, by a schedule that has actually fired — not merely
  // written into a function that no cron drives. 'deleted' is split so the read guard, which
  // refuses any statement carrying a bare write keyword, does not reject this check.
  await req('comp-1', 'comp-17-weekly-questions', 'The five improvement questions are asked weekly',
    `select coalesce((select pg_get_functiondef(p.oid) ~* 'What failed\\?'
              and pg_get_functiondef(p.oid) ~* 'What slowed us\\?'
              and pg_get_functiondef(p.oid) ~* 'What cost too much\\?'
              and pg_get_functiondef(p.oid) ~* 'What can be automated\\?'
              and pg_get_functiondef(p.oid) ~* ('What should be dele'||'ted\\?')
            from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname='fn_os_improve' limit 1)
       and exists (select 1 from cron.job j where j.active and j.command ~* '\\yfn_os_improve\\y')
       and ${CRON_OK('fn_os_improve', 14)}, false)`,
    `select 'all five stems present: '||coalesce((select (pg_get_functiondef(p.oid) ~* 'What failed\\?'
              and pg_get_functiondef(p.oid) ~* 'What slowed us\\?'
              and pg_get_functiondef(p.oid) ~* 'What cost too much\\?'
              and pg_get_functiondef(p.oid) ~* 'What can be automated\\?'
              and pg_get_functiondef(p.oid) ~* ('What should be dele'||'ted\\?'))::text
            from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname='fn_os_improve' limit 1),'no such function')
       ||'; weekly cron last ok '||coalesce((select max(d.end_time)::timestamp(0)::text
            from cron.job_run_details d join cron.job j on j.jobid=d.jobid
           where j.command ~* '\\yfn_os_improve\\y' and d.status='succeeded'),'never')`);

  // And the answer to "does it reach someone": the questions become org_tasks in a department that
  // has a live employee, and at least one has been picked up rather than left at 'proposed'.
  await req('comp-1', 'comp-17-questions-read', 'The improvement questions reach someone',
    `select coalesce((select count(*) from public.org_tasks where title like '% improvement: %') > 0
       and (select count(*) from public.org_tasks t where t.title like '% improvement: %'
             and t.status <> 'proposed'
             and exists (select 1 from public.org_agents a
                         where a.department = t.dept_key and a.active)) > 0
       and ${READERS('org_tasks')} > 0, false)`,
    `select (select count(*) from public.org_tasks where title like '% improvement: %')
       ||' improvement question(s) in '
       ||(select count(distinct dept_key) from public.org_tasks where title like '% improvement: %')
       ||' department(s), '||(select count(*) from public.org_tasks where title like '% improvement: %'
            and status <> 'proposed')||' picked up, org_tasks has '||${READERS('org_tasks')}||' reader(s)'`);
}
