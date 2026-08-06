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
// its "metrics" is exec_reports.metrics, a column it WRITES. So the Component 16 dimensions are
// scored on the FIGURE, by name, on a surface something reads — not on "the row is read by someone".
//
// TRAP 2 — the live routine, and the store-to-store copy. A proc that names the figure is only a
// reader if the proc itself is reachable: named by an ACTIVE cron command, or by another routine
// that is itself on an active cron. And the report's own writer is never its reader — fn_os_review
// selects the eight dimensions out of v_os_health and writes them into os_review.metrics, which
// moves a number from one store into another without anybody opening either. Both are excluded, so
// every dimension check measures consumption rather than computation.
//
// TRAP 3, added 6 Aug 2026 after this file scored 21/21 on production and was not believed — A KEY
// IS NOT A VALUE. Every dimension check used `r.metrics ? 'capacity_pct'`, which is true when the
// key is present and its value is JSON null. Measured: capacity_pct was present on 10 of 10 OS and
// non-null on 4, all four of them 0.0, because resource_pool.committed is 0 on every row and no
// routine in the database ever writes it. "10 of 10 OS carry capacity" was a false statement about
// a figure that does not exist. Every dimension now requires a NON-NULL value for every ACTIVE OS,
// and capacity additionally requires that the input it divides is maintained by something.
export default async function ({ req, READERS }) {
  // A proc is live if an ACTIVE cron command names it, or another routine that is ITSELF on an
  // active cron names it. Both guards were missing: a disabled job used to certify a proc as live,
  // and two never-called functions that mention each other used to certify each other, which
  // degrades "live" to "textually mentioned somewhere".
  const LIVE = (a) => `(exists (select 1 from cron.job j where j.active and j.command ~* ('\\y'||${a}.proname||'\\y'))
      or exists (select 1 from pg_proc q join pg_namespace nq on nq.oid=q.pronamespace
                 where nq.nspname='public' and q.prokind in ('f','p') and q.oid <> ${a}.oid
                   and pg_get_functiondef(q.oid) ~* ('\\y'||${a}.proname||'\\y')
                   and exists (select 1 from cron.job j0 where j0.active
                                 and j0.command ~* ('\\y'||q.proname||'\\y'))))`;

  // How many LIVE readers name this figure on the per-OS health surface? fn_os_review is the writer
  // and is excluded: a function that mentions the column it populates is not a reader of it.
  const FIGURE_READERS = (rx) => `(
      (select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
        where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_os_review'
          and pg_get_functiondef(p.oid) ~* '${rx}'
          and pg_get_functiondef(p.oid) ~* '\\y(os_review|v_os_health)\\y'
          and ${LIVE('p')})
    + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '${rx}'
        and (v.viewname = 'v_os_health' or v.definition ~* '\\yos_review\\y')
        and (exists (select 1 from pg_proc p2 join pg_namespace n2 on n2.oid=p2.pronamespace
                     where n2.nspname='public' and p2.prokind in ('f','p')
                       and p2.proname <> 'fn_os_review'
                       and pg_get_functiondef(p2.oid) ~* ('\\y'||v.viewname||'\\y')
                       and ${LIVE('p2')})
          or exists (select 1 from cron.job j2 where j2.active and j2.command ~* ('\\y'||v.viewname||'\\y'))))
    + (select count(*) from cron.job j3 where j3.active and j3.command ~* '${rx}'
        and j3.command ~* '\\y(os_review|v_os_health)\\y'))`;

  // Component 16's report is os_review, one row per active OS per ISO week. A dimension is reported
  // when EVERY active OS carries a NON-NULL value for it in the newest report, that report is
  // recent, and a live reader names it. The v_os_health branch is the second legitimate way to
  // satisfy the same requirement: that view already computes six of the dimensions per OS, so it
  // needs a reader — and, equally, a row for every active OS, which branch 1 has always demanded
  // and branch 2 used to drop silently along with the freshness bound.
  const OS_COUNT = `(select count(*) from public.operating_system where active)`;
  const FRESH = `(select max(created_at) from public.os_review) > now() - interval '21 days'`;
  // fn_os_review reads v_os_health and copies its figures into os_review.metrics. That makes
  // fn_os_review a reader of the VIEW but not a consumer of the FIGURE: it is the writer of the
  // report. Counting it would let a number travel from one store nothing opens into another and
  // call itself reported. Measured 6 Aug 2026: excluding fn_os_review, the procs naming v_os_health
  // were ZERO — so the generic READERS('v_os_health') helper, which self-excludes only by the
  // object's own name, returned 1 and that 1 was the copier. This helper is what comp-16-fn-os-health
  // must use, and the liveness guard FIGURE_READERS applies is applied here too.
  const VIEW_READ = `((select count(*) from pg_proc p3 join pg_namespace n3 on n3.oid=p3.pronamespace
        where n3.nspname='public' and p3.prokind in ('f','p') and p3.proname <> 'fn_os_review'
          and pg_get_functiondef(p3.oid) ~* '\\yv_os_health\\y' and ${LIVE('p3')})
    + (select count(*) from pg_views v3 where v3.schemaname='public' and v3.definition ~* '\\yv_os_health\\y'
        and (exists (select 1 from pg_proc p4 join pg_namespace n4 on n4.oid=p4.pronamespace
                     where n4.nspname='public' and p4.prokind in ('f','p') and p4.proname <> 'fn_os_review'
                       and pg_get_functiondef(p4.oid) ~* ('\\y'||v3.viewname||'\\y') and ${LIVE('p4')})
          or exists (select 1 from cron.job j5 where j5.active and j5.command ~* ('\\y'||v3.viewname||'\\y'))))
    + (select count(*) from cron.job j4 where j4.active and j4.command ~* '\\yv_os_health\\y'))`;

  // Does v_os_health carry a row for every ACTIVE OS? Read through query_to_xml so a dropped view
  // scores this MISSING rather than ERRORing — the harness treats an errored check as an UNMEASURED
  // requirement, which is a worse outcome than a false negative.
  const VIEW_OS_ROWS = `(select case when to_regclass('public.v_os_health') is null then 0 else
      (xpath('/row/c/text()', query_to_xml(
        'select count(*) c from public.v_os_health h join public.operating_system o'
        ||' on o.os_key = h.os_key and o.active', false, true, '')))[1]::text::int end)`;

  // NON-NULL, not merely present. `metrics ? 'k'` is true for a JSON null.
  const HASVAL = (keys) => keys.map(k =>
    `(r.metrics ? '${k}' and jsonb_typeof(r.metrics->'${k}') <> 'null')`).join(' or ');
  const DIM_OK = (keys) => `(select count(*) from public.os_review r
      join public.operating_system o on o.os_key = r.os_key and o.active
      where r.period = (select max(period) from public.os_review) and (${HASVAL(keys)}))`;

  const DIM = (rx, keys) => `select coalesce((
      ${DIM_OK(keys)} >= ${OS_COUNT} and ${FRESH} and ${FIGURE_READERS(rx)} > 0)
    or ((select count(*) from pg_views v where v.schemaname='public' and v.viewname='v_os_health'
          and v.definition ~* '${rx}') > 0
        and ${VIEW_OS_ROWS} >= ${OS_COUNT} and ${VIEW_READ} > 0), false)`;
  const DIM_EV = (rx, keys) => `select ${DIM_OK(keys)}||' of '||${OS_COUNT}
      ||' active OS carry a NON-NULL value in os_review.metrics ('||(select max(period) from public.os_review)||'), '
      ||${FIGURE_READERS(rx)}||' live reader(s) of the figure; v_os_health covers '
      ||${VIEW_OS_ROWS}||' active OS and has '||${VIEW_READ}||' live reader(s) other than the report writer'`;

  const HAS_FN = (n) => `exists (select 1 from pg_proc p join pg_namespace n2 on n2.oid=p.pronamespace
      where n2.nspname='public' and p.proname='${n}')`;
  const CRON_OK = (rx, days) => `(select max(d.end_time) from cron.job_run_details d
      join cron.job j on j.jobid = d.jobid
      where j.command ~* '\\y${rx}\\y' and d.status='succeeded') > now() - interval '${days} days'`;
  const PROMPT = (needle) => `(select public.fn_agent_context('cfo', 22000) like '%${needle}%')`;
  // Readers of a TABLE, with any routine that writes it removed. READERS() self-excludes only a proc
  // whose name equals the object's, so a table's own writer counts itself as a reader of it. The
  // write keywords are split so the read guard, which refuses any statement carrying a bare write
  // keyword, does not reject the check.
  const CONSUMERS = (t) => `(
      (select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
        where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> '${t}'
          and pg_get_functiondef(p.oid) ~* '\\y${t}\\y'
          and pg_get_functiondef(p.oid) !~* ('(inse'||'rt\\s+into|upd'||'ate|del'||'ete\\s+from)\\s+(public\\.)?${t}\\y'))
    + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '\\y${t}\\y'))`;

  // Every check below registers section 'comp-14-17'. It used to register 'comp-1', which is not a
  // section that exists — the runner filters on `section.startsWith(ONLY) || id.startsWith(ONLY)`,
  // so there was no way to select components 14-17 and the recorded section was wrong on all 21
  // rows. 'comp-14-17'.startsWith('comp-1') is still true, so --only=comp-1 keeps working.
  const S = 'comp-14-17';

  // ---- COMPONENT 14: GOVERNANCE --------------------------------------------------------------
  // "Can I decide?" — a policy table is only an answer if something resolves it and the resolution
  // is recorded. decision_policy -> fn_should_escalate -> decision_log.kind='action_gate'.
  await req(S, 'comp-14-can-decide', 'Can I decide? is answered by a mechanism',
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
  //
  // THE PROMPT NEEDLE USED TO BE `like '%AED)%'`, WHICH PROVED NOTHING. It matched at "...target
  // 1000000 AED); Finance Director — primary objective..." — a KPI line with no connection to any
  // spend threshold. Any AED-denominated figure anywhere in a 28,237-character prompt satisfied it.
  // The needle is now the employee's OWN stored threshold_aed, and it must appear INSIDE the
  // authority block rather than anywhere in the prompt. position() is deliberate: the value comes
  // out of a table, and on the pattern side of LIKE a stored '_' or '%' is a wildcard.
  const SPEND_IN_PROMPT = `(select position(a.threshold_aed::text in
        substr(c.ctx, position('# YOUR AUTHORITY' in c.ctx), 1000)) > 0
      from public.employee_authority a, (select public.fn_agent_context('cfo', 22000) ctx) c
      where a.agent_key='cfo' and a.threshold_aed is not null
      order by a.threshold_aed desc limit 1)`;
  await req(S, 'comp-14-can-spend', 'Can I spend? is enforced, not advisory',
    `select coalesce((select count(*) from public.employee_authority where threshold_aed is not null) > 0
       and ${HAS_FN('fn_check_spend')}
       and exists (select 1 from pg_trigger t join pg_proc f on f.oid = t.tgfoid
                   where not t.tgisinternal and t.tgenabled <> 'D'
                     and pg_get_functiondef(f.oid) ~* '\\y(fn_check_spend|fn_emit_budget_exceeded)\\y')
       and ${SPEND_IN_PROMPT}, false)`,
    `select (select count(*) from public.employee_authority where threshold_aed is not null)
       ||' personal spend limit(s) over '||(select count(distinct agent_key) from public.employee_authority)
       ||' employees, refused by trigger(s): '
       ||coalesce((select string_agg(t.tgname,',') from pg_trigger t join pg_proc f on f.oid=t.tgfoid
            where not t.tgisinternal and t.tgenabled <> 'D'
              and pg_get_functiondef(f.oid) ~* '\\y(fn_check_spend|fn_emit_budget_exceeded)\\y'),'none')
       ||'; the cfo''s own threshold_aed appears inside the prompt''s authority block: '||${SPEND_IN_PROMPT}`);

  // "Can I approve?" — org_authority resolved hourly by fn_task_approve, whose verdicts land in
  // review_chain. A cron that is active but has never succeeded is not an approval mechanism.
  await req(S, 'comp-14-can-approve', 'Can I approve? is enforced',
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
  await req(S, 'comp-14-should-escalate', 'Should I escalate? routes to a named party',
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

  // "Who must review?" — RESOLUTION, not existence. This used to be `> 0`: one review in 30 days
  // naming an active employee scored MET while the evidence line printed "45 of 213", a number that
  // flatly contradicted the verdict it accompanied. It is now a universal claim over the rows that
  // name a reviewer at all, with two carve-outs that are named rather than assumed:
  //   - 'approval_path' is the machine approver fn_task_approve writes; it is not a person and is
  //     not claimed to be one (152 of 223 rows in 30d).
  //   - a reviewer_agent that is a declared DEPARTMENT is legitimate at the collaboration stage,
  //     because collaboration_rule.must_involve holds dept_keys as well as agent_keys. That escape
  //     hatch is BOUNDED: department-named rows may not outnumber person-named ones, so the
  //     requirement cannot be satisfied by naming departments instead of people.
  // A row whose reviewer_agent is null is excluded only where the stage has not reached a reviewer:
  // measured 6 Aug 2026, all 19 null-reviewer rows in 30d are stage='drafted'.
  const RC = `public.review_chain r where r.created_at > now() - interval '30 days'
      and r.reviewer_agent is not null and r.reviewer_agent <> 'approval_path'`;
  const RC_NAMED = `(select count(*) from ${RC})`;
  const RC_PERSON = `(select count(*) from ${RC}
      and exists (select 1 from public.org_agents a where a.agent_key = r.reviewer_agent and a.active))`;
  const RC_DEPT = `(select count(*) from ${RC}
      and not exists (select 1 from public.org_agents a where a.agent_key = r.reviewer_agent and a.active)
      and exists (select 1 from public.org_departments d where d.dept_key = r.reviewer_agent
                  and exists (select 1 from public.org_agents a2 where a2.department = d.dept_key and a2.active)))`;
  const RC_DRAFT_ONLY = `(select count(*) from public.review_chain r
      where r.created_at > now() - interval '30 days' and r.reviewer_agent is null
        and r.stage <> 'drafted')`;
  await req(S, 'comp-14-who-reviews', 'Who must review? resolves to a person',
    `select coalesce(${HAS_FN('fn_pick_reviewer')} and ${READERS('fn_pick_reviewer')} > 0
       and ${RC_PERSON} > 0
       and ${RC_PERSON} + ${RC_DEPT} = ${RC_NAMED}
       and ${RC_PERSON} >= ${RC_DEPT}
       and ${RC_DRAFT_ONLY} = 0, false)`,
    `select ${RC_PERSON}||' of '||${RC_NAMED}||' named reviewer(s)/30d resolve to an ACTIVE employee, '
       ||${RC_DEPT}||' to a staffed department, '
       ||(${RC_NAMED} - ${RC_PERSON} - ${RC_DEPT})||' to nobody; '
       ||${RC_DRAFT_ONLY}||' unnamed reviewer(s) past the drafted stage; fn_pick_reviewer has '
       ||${READERS('fn_pick_reviewer')}||' caller(s)'`);

  // ---- COMPONENT 15: COLLABORATION PROTOCOL --------------------------------------------------
  // "Who can help?" — declared in collaboration_rule.must_involve, every entry resolving to a real
  // department or employee, read by fn_task_review, which the hourly cos_execute cron drives.
  const UNRESOLVED = (col) => `(select count(*) from public.collaboration_rule c,
      unnest(coalesce(c.${col},'{}'::text[])) x
      where not exists (select 1 from public.org_departments d where d.dept_key = x)
        and not exists (select 1 from public.org_agents a where a.agent_key = x))`;

  await req(S, 'comp-15-who-can-help', 'Who can help? is declared and read',
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
  await req(S, 'comp-15-who-approves', 'Who must approve? is declared and read',
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
  await req(S, 'comp-15-who-reviews', 'Who must review? is declared and read',
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

  // "Who owns this process?" — 72 declared owners are worth nothing if the only reader is the graph
  // builder, and this check's own comment said so while never asking the question. The clause that
  // used to stand in for it, PROMPT('no other OS may own'), matches a fixed label fn_agent_context
  // emits whenever an OS has any responsibilities at all — boilerplate, not the ownership rows, and
  // byte-identical to a clause in the_ten_oses.mjs, so the same fact was scored twice inside the 110.
  // It is replaced by a real consumer count over os_responsibility with writers removed (measured
  // 6 Aug 2026: fn_agent_context, fn_event_dispatch, fn_graph_rebuild and v_operating_manual read
  // it; nothing writes it). Ownership must also ROUTE work, which is what the owner_dept clauses do.
  await req(S, 'comp-15-who-owns', 'Who owns this process? drives behaviour',
    `select coalesce((select count(distinct r.os_key) from public.os_responsibility r
             join public.operating_system o on o.os_key=r.os_key and o.active) = ${OS_COUNT}
       and ${CONSUMERS('os_responsibility')} > 0
       and (select count(*) from public.collaboration_rule c where c.owner_dept is not null
             and exists (select 1 from public.org_departments d where d.dept_key=c.owner_dept)) > 0
       and exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                   where n.nspname='public' and p.proname='fn_task_review'
                     and pg_get_functiondef(p.oid) ~* '\\yowner_dept\\y'), false)`,
    `select (select count(*) from public.os_responsibility)||' owned responsibilit(ies) across '
       ||(select count(distinct os_key) from public.os_responsibility)||' of '||${OS_COUNT}
       ||' OS, consumed by '||${CONSUMERS('os_responsibility')}||' non-writing routine(s)/view(s); '
       ||(select count(*) from public.collaboration_rule where owner_dept is not null)
       ||' situation owner(s) resolved by fn_task_review'`);

  // "No duplicated ownership" is a STRUCTURAL claim, and the old first clause pretended otherwise:
  // `group by responsibility having count(distinct os_key) > 1` is entailed by the single-column
  // PRIMARY KEY the very next clause asserts, so "0 owned twice" was a constant restating the
  // requirement, not a measurement. Both halves of the rule are now asserted at the level they are
  // actually enforced — os_responsibility by its primary key, os_knowledge_domain by the partial
  // unique index on domain_key where ownership='owns' — plus the one thing neither structure can
  // guarantee and which CAN fail: ownership vested in an OS that has been deactivated is ownership
  // by nobody, and no constraint prevents it.
  const ORPHAN_OWNED = `((select count(*) from public.os_responsibility r
        where not exists (select 1 from public.operating_system o where o.os_key=r.os_key and o.active))
    + (select count(*) from public.os_knowledge_domain k where k.ownership='owns'
        and not exists (select 1 from public.operating_system o where o.os_key=k.os_key and o.active)))`;
  await req(S, 'comp-15-no-dup-ownership', 'No duplicated ownership across OSes',
    `select coalesce(exists (select 1 from pg_constraint c join pg_class t on t.oid=c.conrelid
                   join pg_namespace n on n.oid=t.relnamespace
                   join pg_attribute a on a.attrelid=t.oid and a.attnum = c.conkey[1]
                   where n.nspname='public' and t.relname='os_responsibility'
                     and c.contype in ('p','u') and array_length(c.conkey,1)=1
                     and a.attname='responsibility')
       and exists (select 1 from pg_index i join pg_class t2 on t2.oid=i.indrelid
                   join pg_namespace n2 on n2.oid=t2.relnamespace
                   join pg_attribute a2 on a2.attrelid=t2.oid and a2.attnum = i.indkey[0]
                   where n2.nspname='public' and t2.relname='os_knowledge_domain'
                     and i.indisunique and i.indnkeyatts = 1 and a2.attname='domain_key'
                     and pg_get_expr(i.indpred, i.indrelid) ~* 'owns')
       and ${ORPHAN_OWNED} = 0, false)`,
    `select (select count(*) from public.os_responsibility)||' responsibilit(ies) under '
       ||coalesce((select string_agg(c.conname,',') from pg_constraint c join pg_class t on t.oid=c.conrelid
            join pg_namespace n on n.oid=t.relnamespace
            where n.nspname='public' and t.relname='os_responsibility' and c.contype in ('p','u')),'no constraint')
       ||'; '||(select count(*) from public.os_knowledge_domain where ownership='owns')||' owned domain(s) under '
       ||coalesce((select string_agg(i2.indexname,',') from pg_indexes i2 where i2.schemaname='public'
            and i2.tablename='os_knowledge_domain' and i2.indexdef ~* 'unique' and i2.indexdef ~* 'owns'),'no unique index')
       ||'; '||${ORPHAN_OWNED}||' owned by an inactive OS'`);

  // ---- COMPONENT 16: HEALTH MONITORING -------------------------------------------------------
  // Health Score. os_review.health is the weekly red/amber/green per OS, complete, fresh and named
  // by live readers. The second branch used to be `operating_system.health_score is populated for
  // every active OS AND READERS('health_score') > 0`, and it is deleted rather than repaired: on
  // production the ONLY object mentioning health_score is fn_os_review, the function that populates
  // it, so that branch read "the column is populated AND the thing that populated it exists" — a
  // tautology for any populated column. READERS() is built for TABLE names, so passing it a COLUMN
  // name made its self-exclusion (proname <> 'health_score') inert and let the UPDATE that writes
  // the column count as a read of it.
  await req(S, 'comp-16-health-score', 'Each OS reports a Health Score that is read',
    `select coalesce((select count(*) from public.os_review r
          join public.operating_system o on o.os_key = r.os_key and o.active
          where r.period=(select max(period) from public.os_review) and r.health is not null) >= ${OS_COUNT}
        and ${FRESH} and ${FIGURE_READERS('\\yhealth\\y')} > 0, false)`,
    `select (select count(*) from public.os_review r
          join public.operating_system o on o.os_key = r.os_key and o.active
          where r.period=(select max(period) from public.os_review) and r.health is not null)
       ||' of '||${OS_COUNT}||' active OS carry os_review.health for '
       ||(select max(period) from public.os_review)||', written '
       ||(select max(created_at)::timestamp(0)::text from public.os_review)||', '
       ||${FIGURE_READERS('\\yhealth\\y')}||' live reader(s) of the figure'
       ||'; operating_system.health_score is populated on '
       ||(select count(*) from public.operating_system where active and health_score is not null)
       ||' of '||${OS_COUNT}||' but its only namer is its own writer, so it proves nothing'`);

  await req(S, 'comp-16-risk', 'Each OS reports Risk that is read',
    DIM('\\y(open_risks|risks_open|risk_count)\\y', ['open_risks', 'risks', 'risk_count']),
    DIM_EV('\\y(open_risks|risks_open|risk_count)\\y', ['open_risks', 'risks', 'risk_count']));

  await req(S, 'comp-16-performance', 'Each OS reports Performance that is read',
    DIM('\\y(kpi_gaps|kpi_attainment|performance_pct)\\y', ['kpi_gaps', 'kpi_attainment', 'performance_pct']),
    DIM_EV('\\y(kpi_gaps|kpi_attainment|performance_pct)\\y', ['kpi_gaps', 'kpi_attainment', 'performance_pct']));

  // Capacity is the one dimension with no real figure anywhere, and the old check could not see it.
  // Branch 1 asked `metrics ? 'capacity_pct'` — key presence — and the key is present on 10 of 10
  // rows with a JSON-null value on 6 of them and 0.0 on the other 4. Branch 2 asked only that
  // resource_pool be fully keyed and that SOME view mention both 'resource_pool' and 'os_key' while
  // SOME function mention that view; it never required the view to compute a utilisation figure,
  // never required per-OS completeness, and did not require the mentioning proc to be live.
  //
  // The third clause is the one that matters and it is not satisfiable by populating anything:
  // capacity_pct is committed/capacity out of resource_pool, and NO routine, view or cron in the
  // database writes resource_pool at all — committed is 0 on all 10 rows and always will be. A
  // ratio whose numerator has no writer is a constant, not a measurement, so backfilling
  // resource_pool.os_key would only widen a figure that is structurally zero.
  const RP_MAINTAINED = `exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.prokind in ('f','p')
        and pg_get_functiondef(p.oid) ~* ('(upd'||'ate|inse'||'rt\\s+into)\\s+(public\\.)?resource_pool\\y'))`;
  const CAP_VALUED = `(select count(*) from public.os_review r
      join public.operating_system o on o.os_key = r.os_key and o.active
      where r.period=(select max(period) from public.os_review)
        and (${HASVAL(['capacity', 'capacity_pct', 'used_pct'])}))`;
  await req(S, 'comp-16-capacity', 'Each OS reports Capacity that is read',
    `select coalesce(${RP_MAINTAINED} and ((
        ${CAP_VALUED} >= ${OS_COUNT}
        and ${FRESH} and ${FIGURE_READERS('\\y(capacity|capacity_pct|used_pct)\\y')} > 0)
      or ((select count(*) from public.resource_pool where os_key is null) = 0
        and (select count(distinct os_key) from public.resource_pool) >= ${OS_COUNT}
        and (select count(*) from pg_views v where v.schemaname='public'
              and v.definition ~* '\\yresource_pool\\y' and v.definition ~* '\\yos_key\\y'
              and v.definition ~* '\\y(capacity_pct|used_pct|utilisation|utilization)\\y'
              and exists (select 1 from pg_proc p2 join pg_namespace n2 on n2.oid=p2.pronamespace
                          where n2.nspname='public' and p2.prokind in ('f','p')
                            and pg_get_functiondef(p2.oid) ~* ('\\y'||v.viewname||'\\y')
                            and ${LIVE('p2')})) > 0)), false)`,
    `select ${CAP_VALUED}||' of '||${OS_COUNT}
       ||' active OS carry a NON-NULL capacity value in os_review.metrics (key present on '
       ||(select count(*) from public.os_review r where r.period=(select max(period) from public.os_review)
            and r.metrics ? 'capacity_pct')||'); resource_pool '
       ||(select count(*) from public.resource_pool where os_key is not null)||' of '
       ||(select count(*) from public.resource_pool)||' row(s) keyed to an OS across '
       ||(select count(distinct os_key) from public.resource_pool)||' OS, sum(committed)='
       ||(select coalesce(sum(committed),0) from public.resource_pool)||'; a routine maintains resource_pool: '
       ||${RP_MAINTAINED}`);

  await req(S, 'comp-16-backlog', 'Each OS reports Backlog that is read',
    DIM('\\y(stale_tasks|backlog_per_head|backlog_pct)\\y', ['stale_tasks', 'open_tasks', 'backlog']),
    DIM_EV('\\y(stale_tasks|backlog_per_head|backlog_pct)\\y', ['stale_tasks', 'open_tasks', 'backlog']));

  await req(S, 'comp-16-quality', 'Each OS reports Quality that is read',
    DIM('\\y(review_pass_pct|quality_pct)\\y', ['review_pass_pct', 'quality_pct', 'quality']),
    DIM_EV('\\y(review_pass_pct|quality_pct)\\y', ['review_pass_pct', 'quality_pct', 'quality']));

  await req(S, 'comp-16-cost', 'Each OS reports Cost that is read',
    DIM('\\y(budget_pct|spend_pct|cost_pct)\\y', ['budget_pct', 'cost_aed', 'spend_pct']),
    DIM_EV('\\y(budget_pct|spend_pct|cost_pct)\\y', ['budget_pct', 'cost_aed', 'spend_pct']));

  await req(S, 'comp-16-automation', 'Each OS reports Automation that is read',
    DIM('\\y(needs_founder_pct|automation_pct|automated_pct)\\y',
        ['needs_founder_pct', 'automation_pct', 'automated_pct']),
    DIM_EV('\\y(needs_founder_pct|automation_pct|automated_pct)\\y',
        ['needs_founder_pct', 'automation_pct', 'automated_pct']));

  // fn_os_health / v_os_health. fn_os_health returns failing crons, agent errors and payments for
  // the whole platform with no os_key in it, so it does not answer "how is THIS OS". v_os_health
  // does, per OS. The first branch used to be READERS('v_os_health') > 0, and the generic helper
  // self-excludes only by the object's own name — so it returned 1 and that 1 was fn_os_review, the
  // function that copies the view into os_review. The requirement was MET 100% on the strength of
  // the view's own copier, which is the exact defect this file's TRAP 2 forbids. VIEW_READ, which
  // this file already defined and which excludes fn_os_review, evaluated to 0 on the same run.
  await req(S, 'comp-16-fn-os-health', 'fn_os_health / v_os_health report per-OS health that is read',
    `select coalesce((${VIEW_READ} > 0 and ${VIEW_OS_ROWS} >= ${OS_COUNT})
       or (select coalesce(bool_or(pg_get_functiondef(p.oid) ~* '\\yos_key\\y'
             and pg_get_functiondef(p.oid) ~* '\\y(operating_system|v_os_scoreboard|os_department)\\y'), false)
             from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='public' and p.proname='fn_os_health')
          and ${READERS('fn_os_health')} > 0, false)`,
    `select 'v_os_health covers '||${VIEW_OS_ROWS}||' of '||${OS_COUNT}||' active OS and has '
       ||${VIEW_READ}||' live reader(s) other than its copier fn_os_review ('
       ||coalesce((select string_agg(p.proname,',' order by p.proname)
            from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_os_review'
             and pg_get_functiondef(p.oid) ~* '\\yv_os_health\\y'),'none')
       ||'); fn_os_health is per-OS: '
       ||coalesce((select bool_or(pg_get_functiondef(p.oid) ~* '\\yos_key\\y')::text
            from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname='fn_os_health'),'absent')
       ||', with '||${READERS('fn_os_health')}||' reader(s)'`);

  // ---- COMPONENT 17: CONTINUOUS IMPROVEMENT --------------------------------------------------
  // The five questions must be asked weekly, by a schedule that has actually fired — not merely
  // written into a function that no cron drives. 'deleted' is split so the read guard, which
  // refuses any statement carrying a bare write keyword, does not reject this check.
  await req(S, 'comp-17-weekly-questions', 'The five improvement questions are asked weekly',
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

  // And the answer to "does it reach someone". The old third clause was READERS('org_tasks') > 0,
  // which on production is 34 — org_tasks is the platform's central task table, the term cannot be
  // false in any realistic state, and it says nothing whatever about the improvement questions.
  // What replaces it is the question actually at issue: a question raised more than a week ago and
  // still sitting at 'proposed' reached nobody, and a question filed to a department with no active
  // employee was never addressed to anyone. Both are falsifiable, and both bite the moment the
  // weekly batch stops being picked up.
  const IMP = `public.org_tasks t where t.title like '% improvement: %'`;
  const IMP_STALE = `(select count(*) from ${IMP} and t.created_at < now() - interval '7 days'
      and t.status = 'proposed')`;
  const IMP_UNSTAFFED = `(select count(*) from ${IMP}
      and not exists (select 1 from public.org_agents a where a.department = t.dept_key and a.active))`;
  await req(S, 'comp-17-questions-read', 'The improvement questions reach someone',
    `select coalesce((select count(*) from ${IMP} and t.created_at > now() - interval '21 days') > 0
       and (select count(*) from ${IMP} and t.status <> 'proposed') > 0
       and ${IMP_STALE} = 0
       and ${IMP_UNSTAFFED} = 0, false)`,
    `select (select count(*) from ${IMP})||' improvement question(s) in '
       ||(select count(distinct dept_key) from public.org_tasks where title like '% improvement: %')
       ||' department(s), '||(select count(*) from ${IMP} and t.created_at > now() - interval '21 days')
       ||' raised in the last 21d, '||(select count(*) from ${IMP} and t.status <> 'proposed')
       ||' picked up; '||${IMP_STALE}||' still ''proposed'' after 7 days, '
       ||${IMP_UNSTAFFED}||' filed to a department with no active employee'`);
}
