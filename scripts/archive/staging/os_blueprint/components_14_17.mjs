// Components 14-17 of the Universal OS Blueprint, scored against PRODUCTION.
//
//   14 Governance      — Can I decide? Can I spend? Can I approve? Should I escalate? Who reviews?
//   15 Collaboration   — Who can help? Who approves? Who reviews? Who owns? No duplicated ownership.
//   16 Health          — Health Score, Risk, Performance, Capacity, Backlog, Quality, Cost, Automation.
//   17 Continuous Improvement — the five weekly questions, and whether anyone receives them.
//
// Every check asks the three questions separately: does the mechanism EXIST, does it RUN, and does
// anything READ its output. Four traps govern this file specifically.
//
// TRAP 1 — the reader that is not a reader. os_review.metrics is written weekly by fn_os_review with
// kpi_gaps, open_tasks, stale_tasks and budget_pct in it. fn_exec_meeting's definition contains the
// word "metrics", so a naive "does a reader mention metrics" test says yes for all four. It does not:
// its "metrics" is exec_reports.metrics, a column it WRITES. So the Component 16 dimensions are
// scored on the FIGURE, by name, on a surface something reads — not on "the row is read by someone".
//
// TRAP 2 — the live routine, and the store-to-store copy. A proc that names the figure is only a
// reader if the proc itself is reachable, and the report's own writer is never its reader:
// fn_os_review selects the eight dimensions out of v_os_health and writes them into
// os_review.metrics, which moves a number from one store into another without anybody opening
// either. Both are excluded, so every dimension check measures consumption rather than computation.
//
// TRAP 3 — A KEY IS NOT A VALUE. Every dimension check once used `r.metrics ? 'capacity_pct'`, true
// when the key is present and its value is JSON null. Every dimension now requires a NON-NULL value
// for every ACTIVE OS.
//
// TRAP 4, added 6 Aug 2026 after this file scored 21/21 and was refuted a second time — A SCHEDULE
// IS NOT A RUN, AND A MENTION IS NOT A CALL. The old LIVE() was satisfied by `cron.job.active`, a
// boolean: a job that had never fired once certified every reader in Component 16, and production's
// os_health_brief_weekly is exactly that job (scheduled 6 Aug, runs=0). Liveness now goes through
// cron.job_run_details — a succeeded run inside a window — for every liveness claim in the file,
// and the three "read by X" legs that pointed at functions with no callers were replaced by the
// rows those functions write, which is the only evidence that survives an app-layer caller
// (cos_execute drives fn_task_review over RPC, and no pg_proc scan can see that).
export default async function ({ req }) {
  // A cron ROW is a claim; a succeeded RUN is the fact. Every liveness assertion below routes here.
  // THE COMMAND NO LONGER NAMES THE ROUTINE (27 Aug 2026). Twenty-two of the twenty-three active
  // jobs read `select public.fn_kernel_cron_exec(<jobid>)`; what they run is in
  // phase_c_system_execution_wrapper.original_command. A pattern matched against cron.job.command
  // therefore matched nothing for any of them. Resolved here, once, for every liveness claim below.
  const EFF = `coalesce(w.original_command, j.command)`;
  const RAN = (cmd, days) => `exists (select 1 from cron.job j
      left join public.phase_c_system_execution_wrapper w on w.jobid = j.jobid
      join cron.job_run_details d on d.jobid = j.jobid
     where j.active and ${EFF} ~* ${cmd} and d.status='succeeded'
       and d.end_time > now() - interval '${days} days')`;
  const CRON_OK = (rx, days) => RAN(`'\\y${rx}\\y'`, days);

  // LIVE IS BACK IN ITS ORIGINAL CORRELATED SHAPE, ON PURPOSE (27 Aug 2026, second pass).
  //
  // The first pass replaced it with an uncorrelated name list to stop seven comp-16 requirements
  // timing out. It did not stop them — and it MADE ONE WORSE: comp-16-capacity had been returning a
  // real verdict ("10 of 10 active OS carry a NON-NULL capacity value … highest 348%") and came back
  // "transport failed after 7 attempts" instead. Trading a measured requirement for an unmeasured
  // one to chase six others is a net loss, and leaving it in would have been a check made worse by a
  // repair. Measured, not reasoned: the on-cron set and the live set are each instant on their own,
  // and arm 1 consuming the live set through a CTE — even MATERIALIZED — times out, so the cost is
  // the planner re-evaluating it per candidate row. The shape that will work here is the one
  // ui_closure.mjs already uses for spec #3: resolve the names in JavaScript with one query and pass
  // them in as a literal array. That is the next attempt. It was written down in the Phase D spec
  // scoreboard of 27 Aug 2026 rather than half-done here; that documentation was deleted on
  // 9 Sep 2026 and now lives only in git history.
  //
  // What IS kept from the first pass is the correctness half: RAN above now resolves the cron
  // command through phase_c_system_execution_wrapper, so liveness can see the twenty-two active jobs
  // whose command is `select public.fn_kernel_cron_exec(<jobid>)` and names no routine at all.
  const LIVE = (a) => `(${RAN(`('\\y'||${a}.proname||'\\y')`, 14)}
      or exists (select 1 from pg_proc q join pg_namespace nq on nq.oid=q.pronamespace
                 where nq.nspname='public' and q.prokind in ('f','p') and q.oid <> ${a}.oid
                   and pg_get_functiondef(q.oid) ~* ('\\y'||${a}.proname||'\\y')
                   and ${RAN(`('\\y'||q.proname||'\\y')`, 14)}))`;

  // How many LIVE readers name this figure on the per-OS health surface? fn_os_review is the writer
  // and is excluded: a function that mentions the column it populates is not a reader of it.
  // count(DISTINCT proname), because pg_proc holds one row per OVERLOAD — fn_agent_context has two
  // on production, and a reader counted twice inflates every leg it appears in.
  // LIVENESS IS ASKED FIRST, AND THAT IS THE DIFFERENCE BETWEEN A VERDICT AND A TIMEOUT. With the
  // LIVE clause written last, this rendered pg_get_functiondef for all 1,291 public routines — twice,
  // once per regex — and only then discarded all but the live ones. `\yhealth\y` matches enough of
  // them that the statement blew past the database's own statement_timeout and came back
  // "57014: canceled". Only a LIVE routine can be counted here at all, so the name filter is moved
  // ahead of the source render: 40 definitions instead of 1,291, same set, same count.
  const FIGURE_READERS = (rx) => `(
      (select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
        where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_os_review'
          and pg_get_functiondef(p.oid) ~* '${rx}'
          and pg_get_functiondef(p.oid) ~* '\\y(os_review|v_os_health)\\y'
          and ${LIVE('p')})
    + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '${rx}'
        and (v.viewname = 'v_os_health' or v.definition ~* '\\yos_review\\y')
        and exists (select 1 from pg_proc p2 join pg_namespace n2 on n2.oid=p2.pronamespace
                    where n2.nspname='public' and p2.prokind in ('f','p')
                      and p2.proname <> 'fn_os_review'
                      and pg_get_functiondef(p2.oid) ~* ('\\y'||v.viewname||'\\y')
                      and ${LIVE('p2')}))
    + (select count(*) from cron.job j3
        left join public.phase_c_system_execution_wrapper w3 on w3.jobid = j3.jobid
       where j3.active and coalesce(w3.original_command, j3.command) ~* '${rx}'
        and coalesce(w3.original_command, j3.command) ~* '\\y(os_review|v_os_health)\\y'
        and exists (select 1 from cron.job_run_details d3 where d3.jobid=j3.jobid
                      and d3.status='succeeded' and d3.end_time > now() - interval '14 days')))`;

  // Component 16's report is os_review, one row per active OS per ISO week.
  const OS_COUNT = `(select count(*) from public.operating_system where active)`;
  const PERIOD = `(select max(period) from public.os_review)`;
  // FRESHNESS AND THE SCORED POPULATION MUST BE THE SAME ROWS. The old FRESH was
  // `max(created_at) over the WHOLE table > now() - 21 days` while every coverage clause scored
  // `period = max(period)`: one backfilled row for any period kept the file "fresh" while the
  // scored period was arbitrarily old. It is now the newest row OF THE SCORED PERIOD, and the
  // scored period itself must be one of the last three ISO weeks — compared by generating those
  // three labels rather than by a lexicographic max, which is only correct while weeks stay
  // zero-padded inside one year.
  const FRESH = `((select max(created_at) from public.os_review where period = ${PERIOD})
        > now() - interval '21 days'
      and ${PERIOD} in (to_char(now(),'IYYY-"W"IW'),
                        to_char(now() - interval '7 days','IYYY-"W"IW'),
                        to_char(now() - interval '14 days','IYYY-"W"IW')))`;

  // fn_os_review reads v_os_health and copies its figures into os_review.metrics. That makes
  // fn_os_review a reader of the VIEW but not a consumer of the FIGURE: it is the writer of the
  // report. Counting it would let a number travel from one store nothing opens into another and
  // call itself reported.
  const VIEW_READ = `((select count(distinct p3.proname) from pg_proc p3
        join pg_namespace n3 on n3.oid=p3.pronamespace
        where n3.nspname='public' and p3.prokind in ('f','p') and p3.proname <> 'fn_os_review'
          and pg_get_functiondef(p3.oid) ~* '\\yv_os_health\\y' and ${LIVE('p3')})
    + (select count(*) from pg_views v3 where v3.schemaname='public' and v3.definition ~* '\\yv_os_health\\y'
        and exists (select 1 from pg_proc p4 join pg_namespace n4 on n4.oid=p4.pronamespace
                    where n4.nspname='public' and p4.prokind in ('f','p') and p4.proname <> 'fn_os_review'
                      and pg_get_functiondef(p4.oid) ~* ('\\y'||v3.viewname||'\\y') and ${LIVE('p4')})))`;

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
      where r.period = ${PERIOD} and (${HASVAL(keys)}))`;

  // THE SECOND BRANCH IS DELETED, NOT REPAIRED. It read: v_os_health's DEFINITION TEXT contains the
  // dimension's name, the view covers every active OS, and some live proc names the view. Measured
  // 6 Aug 2026 on production, that disjunct was TRUE for all six of risk/performance/backlog/
  // quality/cost/automation simultaneously and independently of the report — it asserted no value,
  // no per-OS completeness of the figure, and no freshness, so os_review could be emptied and six
  // requirements would still score MET on the strength of a view definition containing a column
  // name. One fact was scoring six requirements. v_os_health's own reader question is the subject
  // of comp-16-fn-os-health, where it belongs and is asked once.
  const DIM = (rx, keys) => `select coalesce(
      ${DIM_OK(keys)} >= ${OS_COUNT} and ${FRESH} and ${FIGURE_READERS(rx)} > 0, false)`;
  const DIM_EV = (rx, keys) => `select ${DIM_OK(keys)}||' of '||${OS_COUNT}
      ||' active OS carry a NON-NULL value in os_review.metrics ('||${PERIOD}||' written '
      ||(select max(created_at)::timestamp(0)::text from public.os_review where period = ${PERIOD})
      ||'), '||${FIGURE_READERS(rx)}||' live reader(s) of the figure: '
      ||coalesce((select string_agg(distinct p.proname,',') from pg_proc p
           join pg_namespace n on n.oid=p.pronamespace
          where n.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_os_review'
            and pg_get_functiondef(p.oid) ~* '${rx}'
            and pg_get_functiondef(p.oid) ~* '\\y(os_review|v_os_health)\\y'
            and ${LIVE('p')}),'none')`;

  const HAS_FN = (n) => `exists (select 1 from pg_proc p join pg_namespace n2 on n2.oid=p.pronamespace
      where n2.nspname='public' and p.proname='${n}')`;

  // Readers of an object, with any routine that WRITES it removed and overloads collapsed. The
  // harness's generic READERS() self-excludes only a proc whose name equals the object's, which is
  // inert for every table name because no routine is ever called org_authority or decision_policy —
  // so a table's own writer and its guard trigger counted themselves as its readers. The write
  // keywords are split so the read guard, which refuses any statement carrying a bare write
  // keyword, does not reject the check itself.
  const CONSUMERS = (t) => `(
      (select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
        where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> '${t}'
          and pg_get_functiondef(p.oid) ~* '\\y${t}\\y'
          and pg_get_functiondef(p.oid) !~* ('(inse'||'rt\\s+into|upd'||'ate|del'||'ete\\s+from)\\s+(public\\.)?${t}\\y'))
    + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '\\y${t}\\y'))`;

  // …and the same set narrowed to consumers that are REACHABLE. This is the clause the file kept
  // promising and applying only inside Component 16.
  const LIVE_CONSUMERS = (t) => `(select count(distinct p.proname) from pg_proc p
        join pg_namespace ns on ns.oid=p.pronamespace
       where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> '${t}'
         and pg_get_functiondef(p.oid) ~* '\\y${t}\\y'
         and pg_get_functiondef(p.oid) !~* ('(inse'||'rt\\s+into|upd'||'ate|del'||'ete\\s+from)\\s+(public\\.)?${t}\\y')
         and ${LIVE('p')})`;
  const LIVE_CONSUMER_NAMES = (t) => `coalesce((select string_agg(distinct p.proname,',')
        from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
       where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> '${t}'
         and pg_get_functiondef(p.oid) ~* '\\y${t}\\y'
         and pg_get_functiondef(p.oid) !~* ('(inse'||'rt\\s+into|upd'||'ate|del'||'ete\\s+from)\\s+(public\\.)?${t}\\y')
         and ${LIVE('p')}),'none')`;

  // A PARTY THE ORG MODEL CONTAINS: an ACTIVE employee, or a department with at least one active
  // employee in it. Written once and used by every leg in this file that claims a name "resolves",
  // because the alternative is what was measured on 6 Aug 2026 — comp-14-who-reviews demanded
  // `org_agents.active`, the escalation leg demanded only `is not null`, and comp-15's UNRESOLVED
  // demanded mere EXISTENCE of a row. Under the weakest of those three, 'supplier_success' passed
  // as a helper and as an owner while org_agents held ZERO employees in it, and 1,101 of 1,101
  // escalations routed to 'Secretary', a string that matches no agent_key, no title and no
  // dept_key. An unstaffed department is the same nobody a missing one is.
  const IS_PARTY = (expr) => `(exists (select 1 from public.org_agents a
        where a.agent_key = ${expr} and a.active)
      or exists (select 1 from public.org_departments d where d.dept_key = ${expr}
                 and exists (select 1 from public.org_agents a2
                              where a2.department = d.dept_key and a2.active)))`;

  // Every check below registers section 'comp-14-17'. 'comp-14-17'.startsWith('comp-1') is true, so
  // --only=comp-1 keeps working.
  const S = 'comp-14-17';

  // ---- COMPONENT 14: GOVERNANCE --------------------------------------------------------------
  // "Can I decide?" — a policy table is only an answer if something resolves it and the resolution
  // is recorded. decision_policy -> fn_should_escalate -> decision_log.kind='action_gate'.
  // READERS('decision_policy') was 13 and could not go false: it counted every routine that names
  // the table including its own writers, for a config table the whole platform touches. What
  // replaces it is the reachable subset, which on production is fn_task_approve and
  // fn_match_capability and which drops to zero the moment those crons stop succeeding.
  await req(S, 'comp-14-can-decide', 'Can I decide? is answered by a mechanism',
    `select coalesce((select count(*) from public.decision_policy) > 0
       and ${LIVE_CONSUMERS('decision_policy')} > 0
       and (select count(*) from public.decision_log
             where kind='action_gate' and created_at > now() - interval '30 days') > 0, false)`,
    `select (select count(*) from public.decision_policy)||' polic(ies), '
       ||${CONSUMERS('decision_policy')}||' non-writing reader(s) of which '
       ||${LIVE_CONSUMERS('decision_policy')}||' reachable ('||${LIVE_CONSUMER_NAMES('decision_policy')}||'), '
       ||(select count(*) from public.decision_log where kind='action_gate'
           and created_at > now() - interval '30 days')||' gate verdict(s)/30d, last '
       ||coalesce((select max(created_at)::date::text from public.decision_log where kind='action_gate'),'never')`);

  // "Can I spend?" — advisory means a number in a table; enforced means a gate that changes the
  // outcome. The limit must also reach the person, or they cannot answer the question before acting.
  //
  // ADVISORY USED TO PASS AS ENFORCED, which is the one distinction the requirement names. The old
  // trigger clause accepted ANY enabled non-internal trigger whose function text merely MENTIONS
  // fn_check_spend or fn_emit_budget_exceeded, on any table, having fired or not. Production has
  // exactly one such trigger and it does not raise: fn_decision_gate stamps gate_verdict and raises
  // a WARNING. Three things now have to hold instead.
  //   1. The trigger function must CALL the spend check — `\s*\(`, not a mention, so a comment or a
  //      string literal naming it is not a mechanism.
  //   2. It must REFUSE. A BEFORE trigger refuses in exactly three ways: it raises an exception, it
  //      returns null, or it rewrites the row into a state other than the one requested. Production
  //      does the third (`new.status := 'blocked_by_gate'`), which is a real refusal and leaves the
  //      reason on the row; a function that only annotates matches none of the three.
  //   3. It must have RUN, over the whole population and not once: every decision that reached an
  //      approved state carries a verdict and a checked-at stamp. Disable the trigger and the next
  //      approval fails this leg. `tgenabled <> 'D'` is a flag; this is the event.
  const GATE_REFUSES = `exists (select 1 from pg_trigger t join pg_proc f on f.oid = t.tgfoid
      join pg_class c on c.oid = t.tgrelid join pg_namespace cn on cn.oid = c.relnamespace
      where not t.tgisinternal and t.tgenabled <> 'D' and cn.nspname='public'
        and pg_get_functiondef(f.oid) ~* '\\y(fn_check_spend|fn_emit_budget_exceeded)\\s*\\('
        and pg_get_functiondef(f.oid) ~* '(raise\\s+exception|return\\s+null|new\\.status\\s*:=)'
        and exists (select 1 from information_schema.columns col
                    where col.table_schema='public' and col.table_name = c.relname
                      and col.column_name = 'gate_verdict'))`;
  const DR_UNGATED = `(select count(*) from public.decision_record
      where status in ('approved','executed') and (gate_verdict is null or gate_checked_at is null))`;
  const DR_GATED = `(select count(*) from public.decision_record where gate_verdict is not null)`;
  // …and the semantic of "enforced", stated generically: a refused decision may not be sitting in
  // an approved state. `new.status :=` alone would be satisfied by a trigger that reassigns the
  // status it was handed, so this is the clause that distinguishes a gate from a rubber stamp.
  // Vacuous while nothing has been refused (production: 0), which is why it is carried alongside
  // the two non-vacuous legs and never instead of them; it binds the first time the gate says no.
  const DR_REFUSED_LIVE = `(select count(*) from public.decision_record
      where gate_verdict='refused' and status in ('approved','executed'))`;
  // The needle is the employee's OWN stored threshold_aed, and it must appear INSIDE the authority
  // block rather than anywhere in the prompt. position() is deliberate: the value comes out of a
  // table, and on the pattern side of LIKE a stored '_' or '%' is a wildcard.
  const SPEND_IN_PROMPT = `(select position(a.threshold_aed::text in
        substr(c.ctx, position('# YOUR AUTHORITY' in c.ctx), 1200)) > 0
      from public.employee_authority a, (select public.fn_agent_context('cfo', 22000) ctx) c
      where a.agent_key='cfo' and a.threshold_aed is not null
      order by a.threshold_aed desc limit 1)`;
  await req(S, 'comp-14-can-spend', 'Can I spend? is enforced, not advisory',
    `select coalesce((select count(*) from public.employee_authority where threshold_aed is not null) > 0
       and ${HAS_FN('fn_check_spend')}
       and ${GATE_REFUSES}
       and ${DR_GATED} > 0 and ${DR_UNGATED} = 0 and ${DR_REFUSED_LIVE} = 0
       and ${SPEND_IN_PROMPT}, false)`,
    `select (select count(*) from public.employee_authority where threshold_aed is not null)
       ||' personal spend limit(s) over '||(select count(distinct agent_key) from public.employee_authority)
       ||' employees; refusing trigger(s): '
       ||coalesce((select string_agg(t.tgname||' on '||c.relname,',')
            from pg_trigger t join pg_proc f on f.oid=t.tgfoid join pg_class c on c.oid=t.tgrelid
            where not t.tgisinternal and t.tgenabled <> 'D'
              and pg_get_functiondef(f.oid) ~* '\\y(fn_check_spend|fn_emit_budget_exceeded)\\s*\\('
              and pg_get_functiondef(f.oid) ~* '(raise\\s+exception|return\\s+null|new\\.status\\s*:=)'),'none')
       ||'; '||${DR_GATED}||' decision(s) carry a gate verdict, '||${DR_UNGATED}
       ||' reached an approved state without one and '||${DR_REFUSED_LIVE}
       ||' are approved despite a refusal; the cfo''s own threshold_aed appears inside the '
       ||'prompt''s authority block: '||${SPEND_IN_PROMPT}`);

  // "Can I approve?" — org_authority resolved hourly by fn_task_approve, whose verdicts land in
  // review_chain. A cron that is active but has never succeeded is not an approval mechanism.
  await req(S, 'comp-14-can-approve', 'Can I approve? is enforced',
    `select coalesce((select count(*) from public.org_authority) > 0
       and ${CRON_OK('fn_task_approve', 7)}
       and (select pg_get_functiondef(p.oid) ~* '\\y(org_authority|fn_dept_authority)\\y'
              from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.proname='fn_task_approve' limit 1)
       and (select count(*) from public.review_chain
             where stage='approval' and created_at > now() - interval '7 days') > 0, false)`,
    `select (select count(*) from public.org_authority)||' authority rule(s); approval cron last ok '
       ||coalesce((select max(d.end_time)::timestamp(0)::text from cron.job_run_details d
            join cron.job j on j.jobid=d.jobid
           where j.active and j.command ~* '\\yfn_task_approve\\y' and d.status='succeeded'),'never')||'; '
       ||(select count(*) from public.review_chain where stage='approval'
           and created_at > now() - interval '7 days')||' approval verdict(s)/7d'`);

  // "Should I escalate?" — the route must name a party AND be visible to someone. The writers of
  // route_to are excluded from the reader count, otherwise the escalator counts as its own audience.
  // The caller leg is the CALL form `fn_should_escalate\s*\(` and not a bare mention: a dead
  // `-- superseded by fn_should_escalate` comment used to satisfy the only mechanism-exists clause
  // this step has. Measured 6 Aug 2026: all three namers (fn_ai_gate, fn_decide, trg_action_gate)
  // do call it, so this hardening does not move the verdict — it removes the way it could be faked.
  //
  // A NAMED PARTY, NOT A NON-NULL COLUMN (6 Aug 2026). The routing leg was
  // `decision_log where route_to is not null > 0` and it was MET while being 100% wrong: all 1,101
  // escalations of the last 30 days carried route_to='Secretary', a label that resolves to no
  // org_agent and no org_departments row, so every escalation the company raised this month was
  // addressed to nobody. Three legs replace it, and none of them can be satisfied by a string.
  //
  //   ESC_LIVE_PARTY  — the ROUTER itself is executed and its answer must resolve to a party. This
  //                     is the only leg that cannot be satisfied by history at all: it is the
  //                     mechanism answering the question now, and it goes false the moment
  //                     decision_policy.review_owner is repointed at a ghost.
  //   ESC_UNRESOLVED  — a per-row universal over the LEDGER, so a router that answers correctly
  //                     when asked but writes something else is caught.
  //   ESC_ROUTED      — non-emptiness, so the universal above is never a zero over nothing.
  //
  // THE WINDOW ON THE UNIVERSAL IS 24 HOURS AND IT IS NOT A GRANDFATHER CLAUSE. The 1,101 legacy
  // rows cannot be un-written and no future work can make them resolve, so a universal over 30 days
  // would be a requirement no implementation can satisfy — the defect comp-17's own comment names.
  // A window excuses nothing by name, by flag, by content or by a repair timestamp: it measures the
  // live system, and production writes ~36 routed escalations a day, so it bites within hours of
  // any regression and is asserted non-empty by ESC_ROUTED on the same window.
  const ESC_ROUTED = (win) => `(select count(*) from public.decision_log
      where route_to is not null and created_at > now() - interval '${win}')`;
  const ESC_UNRESOLVED = (win) => `(select count(*) from public.decision_log l
      where l.route_to is not null and l.created_at > now() - interval '${win}'
        and not ${IS_PARTY('l.route_to')})`;
  const ESC_LIVE_PARTY = `(select ${IS_PARTY('z.r')} from
      (select public.fn_should_escalate('{}'::jsonb)->>'route_to' r) z)`;
  const ESC_LIVE_NAME = `coalesce((select z.r from
      (select public.fn_should_escalate('{}'::jsonb)->>'route_to' r) z), '(null)')`;
  const ESC_CALLERS = `(select count(distinct p.proname) from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_should_escalate'
         and pg_get_functiondef(p.oid) ~* '\\yfn_should_escalate\\s*\\(')`;
  const ESC_SURFACES = `(select count(distinct p.proname) from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.prokind in ('f','p')
         and p.proname not in ('fn_should_escalate','fn_decide','fn_ai_gate','trg_action_gate',
                               'fn_decision_gate','fn_check_spend')
         and pg_get_functiondef(p.oid) ~* '\\yroute_to\\y'
         and pg_get_functiondef(p.oid) ~* '\\ydecision_log\\y')`;
  await req(S, 'comp-14-should-escalate', 'Should I escalate? routes to a named party',
    `select coalesce(${HAS_FN('fn_should_escalate')} and ${ESC_CALLERS} > 0
       and ${ESC_LIVE_PARTY}
       and ${ESC_ROUTED('24 hours')} > 0
       and ${ESC_UNRESOLVED('24 hours')} = 0
       and ${ESC_SURFACES} > 0, false)`,
    // The party is taken FROM THE ROWS COUNTED, never from decision_policy. The old evidence read
    // the label out of decision_policy.review_owner and rendered it as `1100 routed escalation(s)
    // to "Secretary"` — a sentence that stayed true-looking however the ledger was rewritten, and
    // that was already false for the 9 rows routed to 'cat:*' values.
    `select ${ESC_ROUTED('24 hours')}||' routed escalation(s)/24h of which '
       ||${ESC_UNRESOLVED('24 hours')}||' name no active employee and no staffed department; '
       ||'over 30d that is '||${ESC_UNRESOLVED('30 days')}||' of '||${ESC_ROUTED('30 days')}
       ||' unresolvable; the router answers "'||${ESC_LIVE_NAME}||'" which resolves to a party: '
       ||${ESC_LIVE_PARTY}||'; top routes/24h: '
       ||coalesce((select string_agg(t.rt||' x'||t.n, ', ' order by t.n desc) from
            (select l.route_to rt, count(*) n from public.decision_log l
              where l.route_to is not null and l.created_at > now() - interval '24 hours'
              group by l.route_to order by count(*) desc limit 4) t),'none')
       ||'; called by '||${ESC_CALLERS}||' routine(s), read by '||${ESC_SURFACES}
       ||' surface(s) beyond the writers'`);

  // "Who must review?" — RESOLUTION, not existence, and the resolver must have RUN.
  //
  // The mechanism leg was `READERS('fn_pick_reviewer') > 0`, which returns 1, and that 1 is
  // fn_review_submit — a function with zero SQL callers. So the mechanism half of this requirement
  // was certified by two functions that no pg_proc scan can show running. The answer is not to
  // demand a cron, because there is not one: cos_execute (an edge function on an active hourly
  // cron) calls fn_task_review over RPC, which calls fn_review_submit, which calls fn_pick_reviewer.
  // What IS visible is what fn_review_submit writes — a review_chain row at stage 'dept_review'
  // whose reviewer_agent is fn_pick_reviewer's pick. A recent one of those naming an ACTIVE
  // employee proves the resolver ran and resolved to a person, which is the requirement verbatim.
  const PICK_RAN = `(select count(*) from public.review_chain r
      where r.stage='dept_review' and r.created_at > now() - interval '7 days'
        and exists (select 1 from public.org_agents a where a.agent_key=r.reviewer_agent and a.active))`;
  // The universals over the rows that name a reviewer at all, with two carve-outs that are named
  // rather than assumed: 'approval_path' is the machine approver fn_task_approve writes and is not
  // claimed to be a person; a reviewer_agent that is a STAFFED DEPARTMENT is legitimate at the
  // collaboration stage, because collaboration_rule.must_review holds dept_keys as well as
  // agent_keys — and that escape hatch is bounded, department-named rows may not outnumber
  // person-named ones. A null reviewer is excused only before the stage reaches a reviewer.
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
    `select coalesce(${HAS_FN('fn_pick_reviewer')}
       and ${PICK_RAN} > 0 and ${CRON_OK('cos_execute', 2)}
       and ${RC_PERSON} > 0
       and ${RC_PERSON} + ${RC_DEPT} = ${RC_NAMED}
       and ${RC_PERSON} >= ${RC_DEPT}
       and ${RC_DRAFT_ONLY} = 0, false)`,
    `select ${RC_PERSON}||' of '||${RC_NAMED}||' named reviewer(s)/30d resolve to an ACTIVE employee, '
       ||${RC_DEPT}||' to a staffed department, '
       ||(${RC_NAMED} - ${RC_PERSON} - ${RC_DEPT})||' to nobody; '
       ||${RC_DRAFT_ONLY}||' unnamed reviewer(s) past the drafted stage; fn_pick_reviewer resolved '
       ||${PICK_RAN}||' department review(s) to an active employee in the last 7d; CoS driver ok in 2d: '
       ||${CRON_OK('cos_execute', 2)}`);

  // ---- COMPONENT 15: COLLABORATION PROTOCOL --------------------------------------------------
  // The three checks in this component all turn on the same measured fact, so it is stated once.
  // fn_task_review is the only reader of collaboration_rule and it has ZERO SQL callers — but it is
  // not dead: supabase/functions/cos_execute/index.ts:286 calls it by RPC on the hourly
  // cos_execute cron, and it is the only caller of fn_review_submit, which writes review_chain at
  // stages 'dept_review', 'cos_review' and 'published'. Rows at those stages inside a window are
  // therefore proof that the reader RAN, and they are the only proof a database-side scorer can
  // obtain of an app-layer caller. `read by fn_task_review: true` — a mentions test on a function
  // with no visible callers — is replaced by this everywhere it appeared.
  const REVIEWER_RAN = `(select count(*) from public.review_chain
      where stage in ('dept_review','cos_review','published')
        and created_at > now() - interval '7 days')`;
  // …and those rows prove the DECLARATION was read only if every routine able to drive that chain
  // reads it. Measured 6 Aug 2026: the sole caller of fn_review_submit is fn_task_review, and
  // fn_task_review selects collaboration_rule unconditionally for the task's department. Asserted
  // rather than assumed — add a second driver that skips the collaboration loop and this goes
  // non-zero, and the "the reader ran" evidence stops meaning what these checks read it as.
  const REVIEW_DRIVERS = `(select count(distinct p.proname) from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_review_submit'
         and pg_get_functiondef(p.oid) ~* '\\yfn_review_submit\\s*\\(')`;
  const REVIEW_DRIVERS_BLIND = `(select count(distinct p.proname) from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_review_submit'
         and pg_get_functiondef(p.oid) ~* '\\yfn_review_submit\\s*\\('
         and pg_get_functiondef(p.oid) !~* '\\ycollaboration_rule\\y')`;
  // A DECLARED HELPER MUST BE SOMEBODY. This asked only that the name EXISTED in org_departments or
  // org_agents — not that the agent is ACTIVE or the department STAFFED, which is exactly the
  // distinction comp-14-who-reviews makes sixty lines earlier. Measured 6 Aug 2026 under the old
  // form: 0 unresolvable, while collaboration_rule #5 and #8 both named 'supplier_success' as a
  // helper and `select count(*) from org_agents where department='supplier_success'` was 0 — not
  // inactive, ZERO ROWS. Two of the nine rules that "name helpers" summoned a department with no
  // employees at all and the check read them as resolved.
  const UNRESOLVED = (col) => `(select count(*) from public.collaboration_rule c,
      unnest(coalesce(c.${col},'{}'::text[])) x
      where not ${IS_PARTY('x')})`;
  const UNRESOLVED_NAMES = (col) => `coalesce((select string_agg(distinct x, ', ')
      from public.collaboration_rule c, unnest(coalesce(c.${col},'{}'::text[])) x
      where not ${IS_PARTY('x')}), 'none')`;
  // When a rule DID fire, fn_task_review records it as `collaboration_rule #<id> applies ("...")`.
  // position() against a needle built from the id, never LIKE: the pattern would otherwise carry
  // the '_' in 'collaboration_rule' as a single-character wildcard.
  const COLLAB_APPLIED = `(select count(*) from public.review_chain r
      where r.stage='collaboration' and r.created_at > now() - interval '30 days')`;
  const COLLAB_ORPHAN = `(select count(*) from public.review_chain r
      where r.stage='collaboration' and r.created_at > now() - interval '30 days'
        and not exists (select 1 from public.collaboration_rule c
                        where position('collaboration_rule #'||c.id||' applies' in r.reason) > 0))`;

  await req(S, 'comp-15-who-can-help', 'Who can help? is declared and read',
    `select coalesce((select count(*) from public.collaboration_rule
             where coalesce(array_length(must_involve,1),0) > 0) > 0
       and ${UNRESOLVED('must_involve')} = 0
       and ${CONSUMERS('collaboration_rule')} > 0
       and ${CRON_OK('cos_execute', 2)}
       and ${REVIEWER_RAN} > 0
       and ${REVIEW_DRIVERS} > 0 and ${REVIEW_DRIVERS_BLIND} = 0
       and ${COLLAB_ORPHAN} = 0, false)`,
    `select (select count(*) from public.collaboration_rule where coalesce(array_length(must_involve,1),0) > 0)
       ||' rule(s) name helpers, '||${UNRESOLVED('must_involve')}||' naming no active employee and '
       ||'no staffed department ('||${UNRESOLVED_NAMES('must_involve')}||'), read by '
       ||${CONSUMERS('collaboration_rule')}||' non-writing routine(s)/view(s) ('
       ||coalesce((select string_agg(distinct p.proname,',') from pg_proc p
            join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.prokind in ('f','p')
             and pg_get_functiondef(p.oid) ~* '\\ycollaboration_rule\\y'),'none')
       ||'); the reader ran '||${REVIEWER_RAN}||' time(s) in 7d across '||${REVIEW_DRIVERS}
       ||' review driver(s) of which '||${REVIEW_DRIVERS_BLIND}||' never open collaboration_rule; '
       ||${COLLAB_APPLIED}||' rule(s) fired in 30d of which '||${COLLAB_ORPHAN}||' name no existing rule`
       + `; CoS driver ok in 2d: '||${CRON_OK('cos_execute', 2)}`);

  // "Who must approve?" — declared at both levels, told to the employee, and consulted when they
  // act. All four of the old conjuncts were permanently true once the tables were seeded: two bare
  // `count > 0`, two READERS() counts on config tables, and PROMPT('YOUR AUTHORITY') — a heading
  // fn_agent_context emits for a personally-granted authority AND for one inherited from the
  // department ("# YOUR AUTHORITY (delegated to <dept>, no personal grant on file)"), so the needle
  // is identically true whether or not any personal grant exists. Nothing could go false.
  //
  // What is asked instead: every ACTIVE employee has an answer at one level or the other; the
  // employee's OWN stored grant, action_class and max_tier as the prompt renders them, appears
  // inside the authority block; org_authority has a REACHABLE reader; and employee_authority is
  // consulted at the moment of the act, which is what a gate verdict on a decision record is.
  const AUTH_UNCOVERED = `(select count(*) from public.org_agents a where a.active
      and not exists (select 1 from public.employee_authority e where e.agent_key = a.agent_key)
      and not exists (select 1 from public.org_authority o where o.dept_key = a.department))`;
  const AUTH_IN_PROMPT = `(select count(*) from public.employee_authority a,
        (select public.fn_agent_context('cfo', 22000) ctx) c
      where a.agent_key='cfo'
        and position(a.action_class||' -> '||a.max_tier in
              substr(c.ctx, position('# YOUR AUTHORITY' in c.ctx), 1200)) > 0)`;
  const AUTH_CFO_ROWS = `(select count(*) from public.employee_authority where agent_key='cfo')`;
  await req(S, 'comp-15-who-approves', 'Who must approve? is declared and read',
    `select coalesce((select count(*) from public.org_authority) > 0
       and (select count(*) from public.employee_authority) > 0
       and ${AUTH_UNCOVERED} = 0
       and ${AUTH_IN_PROMPT} = ${AUTH_CFO_ROWS} and ${AUTH_CFO_ROWS} > 0
       and ${LIVE_CONSUMERS('org_authority')} > 0
       and ${DR_GATED} > 0 and ${DR_UNGATED} = 0, false)`,
    `select (select count(*) from public.org_authority)||' department + '
       ||(select count(*) from public.employee_authority)||' personal authority row(s); '
       ||${AUTH_UNCOVERED}||' of '||(select count(*) from public.org_agents where active)
       ||' active employee(s) have neither; '||${AUTH_IN_PROMPT}||' of '||${AUTH_CFO_ROWS}
       ||' of the cfo''s own grants appear verbatim in the prompt''s authority block; org_authority '
       ||'has '||${LIVE_CONSUMERS('org_authority')}||' reachable reader(s) ('
       ||${LIVE_CONSUMER_NAMES('org_authority')}||'); '||${DR_GATED}
       ||' decision(s) carry a verdict from the gate that resolves employee_authority'`);

  // "Who must review?" at the protocol level: the DECLARATION (collaboration_rule.must_review) as
  // opposed to comp-14's question of whether the declaration resolves to a named person. The read
  // leg was `fn_task_review's body mentions must_review` and its evidence printed "read by
  // fn_task_review: true", which is a mentions test on a function with no visible callers. The body
  // test is kept — it is what identifies the reader — but it is now joined to the reader having RUN
  // and, where a rule actually fired, to the declared value having TRAVELLED: the reviewer recorded
  // on the collaboration row must be the one the rule names, not merely a reviewer.
  const MUSTREV_MISMATCH = `(select count(*) from public.review_chain r
      join public.collaboration_rule c
        on position('collaboration_rule #'||c.id||' applies' in r.reason) > 0
      where r.stage='collaboration' and r.created_at > now() - interval '30 days'
        and r.reviewer_agent is distinct from coalesce((c.must_review)[1],'exec'))`;
  await req(S, 'comp-15-who-reviews', 'Who must review? is declared and read',
    `select coalesce((select count(*) from public.collaboration_rule
             where coalesce(array_length(must_review,1),0) > 0) > 0
       and ${UNRESOLVED('must_review')} = 0
       and exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                   where n.nspname='public' and p.proname='fn_task_review'
                     and pg_get_functiondef(p.oid) ~* '\\ymust_review\\y')
       and ${CRON_OK('cos_execute', 2)}
       and ${REVIEWER_RAN} > 0
       and ${REVIEW_DRIVERS} > 0 and ${REVIEW_DRIVERS_BLIND} = 0
       and ${MUSTREV_MISMATCH} = 0, false)`,
    `select (select count(*) from public.collaboration_rule where coalesce(array_length(must_review,1),0) > 0)
       ||' rule(s) name reviewers, '||${UNRESOLVED('must_review')}||' naming nobody staffed ('
       ||${UNRESOLVED_NAMES('must_review')}||'); fn_task_review '
       ||'selects must_review: '||coalesce((select (pg_get_functiondef(p.oid) ~* '\\ymust_review\\y')::text
            from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname='fn_task_review' limit 1),'absent')
       ||' and ran '||${REVIEWER_RAN}||' time(s) in 7d; of '||${COLLAB_APPLIED}
       ||' rule(s) fired in 30d, '||${MUSTREV_MISMATCH}||' recorded a reviewer the rule did not name'`);

  // "Who owns this process?" — 72 declared owners are worth nothing if the only reader is the graph
  // builder. The consumer count is over os_responsibility with writers removed AND narrowed to
  // reachable routines (fn_event_dispatch on event_dispatch_15min, fn_graph_rebuild on
  // graph_rebuild_daily).
  //
  // TWO GLOBAL COUNTS STOOD IN FOR TWO UNIVERSALS, AND A DECLARATION ROUTED NOTHING (6 Aug 2026).
  //
  //  (a) The ownership leg was `count(*) from collaboration_rule where owner_dept is not null and
  //      exists(dept) > 0` — ONE resolvable owner among any number of rules made it MET for ever,
  //      and "resolves" meant a row existed: rule #2's owner_dept was 'supplier_success', a
  //      department with zero employees, so one of the ten situations was owned by nobody and
  //      scored as owned. It is now the per-row NOT EXISTS this file already uses for
  //      AUTH_UNCOVERED: every rule must name a STAFFED department.
  //
  //  (b) "drives behaviour" was `fn_task_review's definition contains the word owner_dept` — a
  //      mention test, and the wrong object besides: os_responsibility is what declares who owns
  //      what, and its 72 rows drove nothing at all. fn_task_review now resolves the task's subject
  //      against those declarations and addresses the review to the OWNING OS's own accountable
  //      employee, recorded as review_chain stage='ownership'. The leg is those ROWS: they exist in
  //      the window, and every one of them names a party — which is the requirement, and which no
  //      amount of text in a function body can fake.
  const OWNER_UNSTAFFED = `(select count(*) from public.collaboration_rule c
      where c.owner_dept is null or not exists (select 1 from public.org_departments d
              where d.dept_key = c.owner_dept
                and exists (select 1 from public.org_agents a
                             where a.department = d.dept_key and a.active)))`;
  const OWN_ROUTED = `(select count(*) from public.review_chain r
      where r.stage='ownership' and r.created_at > now() - interval '7 days')`;
  const OWN_UNRESOLVED = `(select count(*) from public.review_chain r
      where r.stage='ownership' and r.created_at > now() - interval '7 days'
        and not ${IS_PARTY('r.reviewer_agent')})`;
  const OWN_FROM_DECLARATION = `(select count(*) from public.review_chain r
      where r.stage='ownership' and r.created_at > now() - interval '7 days'
        and exists (select 1 from public.os_responsibility s
                     where position('responsibility "'||s.responsibility||'"' in r.reason) > 0))`;
  await req(S, 'comp-15-who-owns', 'Who owns this process? drives behaviour',
    `select coalesce((select count(distinct r.os_key) from public.os_responsibility r
             join public.operating_system o on o.os_key=r.os_key and o.active) = ${OS_COUNT}
       and ${LIVE_CONSUMERS('os_responsibility')} > 0
       and ${OWNER_UNSTAFFED} = 0
       and ${OWN_ROUTED} > 0 and ${OWN_UNRESOLVED} = 0
       and ${REVIEWER_RAN} > 0, false)`,
    `select (select count(*) from public.os_responsibility)||' owned responsibilit(ies) across '
       ||(select count(distinct r.os_key) from public.os_responsibility r
            join public.operating_system o on o.os_key=r.os_key and o.active)||' of '||${OS_COUNT}
       ||' ACTIVE OS, consumed by '||${CONSUMERS('os_responsibility')}||' non-writing routine(s)/view(s) '
       ||'of which '||${LIVE_CONSUMERS('os_responsibility')}||' reachable ('
       ||${LIVE_CONSUMER_NAMES('os_responsibility')}||'); '||${OWNER_UNSTAFFED}||' of '
       ||(select count(*) from public.collaboration_rule)
       ||' situation(s) owned by a department with no active employee; the declaration routed '
       ||${OWN_ROUTED}||' review(s) to an owning OS in 7d ('||${OWN_FROM_DECLARATION}
       ||' of them matched to a named responsibility), '||${OWN_UNRESOLVED}
       ||' of which reached nobody; the reviewer ran '||${REVIEWER_RAN}||' time(s) in 7d'`);

  // "No duplicated ownership" is a STRUCTURAL claim. Both halves are asserted at the level they are
  // actually enforced — os_responsibility by its single-column primary key, os_knowledge_domain by
  // the partial unique index on domain_key where ownership='owns' — plus the one thing neither
  // structure can guarantee and which CAN fail: ownership vested in an OS that has been deactivated
  // is ownership by nobody, and no constraint prevents it. The index predicate is PINNED to
  // `ownership = 'owns'`: matching only the word 'owns' would equally accept an index partial on
  // `ownership <> 'owns'`, which permits exactly the duplicate the requirement forbids.
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
                     and pg_get_expr(i.indpred, i.indrelid) ~* 'ownership\\s*=\\s*''owns''')
       and ${ORPHAN_OWNED} = 0, false)`,
    `select (select count(*) from public.os_responsibility)||' responsibilit(ies) under '
       ||coalesce((select string_agg(c.conname,',') from pg_constraint c join pg_class t on t.oid=c.conrelid
            join pg_namespace n on n.oid=t.relnamespace
            where n.nspname='public' and t.relname='os_responsibility' and c.contype in ('p','u')),'no constraint')
       ||'; '||(select count(*) from public.os_knowledge_domain where ownership='owns')||' owned domain(s) under '
       ||coalesce((select string_agg(i.indexrelid::regclass::text||' where '
              ||coalesce(pg_get_expr(i.indpred, i.indrelid),'(unpinned)'),',')
            from pg_index i join pg_class t2 on t2.oid=i.indrelid
            join pg_namespace n2 on n2.oid=t2.relnamespace
           where n2.nspname='public' and t2.relname='os_knowledge_domain' and i.indisunique
             and i.indpred is not null),'no partial unique index')
       ||'; '||${ORPHAN_OWNED}||' owned by an inactive OS'`);

  // ---- COMPONENT 16: HEALTH MONITORING -------------------------------------------------------
  // Health Score. os_review.health is the weekly red/amber/green per OS, complete, fresh and named
  // by live readers. The evidence used to end with the literal string "but its only namer is its
  // own writer, so it proves nothing" — prose printed verbatim whatever the database contained,
  // including after a genuine reader of operating_system.health_score is added, at which point it
  // actively misleads. It now prints the computed namer count and lets a reader draw the conclusion.
  const HS_NAMERS = `(select count(distinct p.proname) from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_os_review'
         and pg_get_functiondef(p.oid) ~* '\\yhealth_score\\y')`;
  await req(S, 'comp-16-health-score', 'Each OS reports a Health Score that is read',
    `select coalesce((select count(*) from public.os_review r
          join public.operating_system o on o.os_key = r.os_key and o.active
          where r.period = ${PERIOD} and r.health is not null) >= ${OS_COUNT}
        and ${FRESH} and ${FIGURE_READERS('\\yhealth\\y')} > 0, false)`,
    `select (select count(*) from public.os_review r
          join public.operating_system o on o.os_key = r.os_key and o.active
          where r.period = ${PERIOD} and r.health is not null)
       ||' of '||${OS_COUNT}||' active OS carry os_review.health for '||${PERIOD}||', written '
       ||(select max(created_at)::timestamp(0)::text from public.os_review where period = ${PERIOD})||', '
       ||${FIGURE_READERS('\\yhealth\\y')}||' live reader(s) of the figure'
       ||'; operating_system.health_score is populated on '
       ||(select count(*) from public.operating_system where active and health_score is not null)
       ||' of '||${OS_COUNT}||' and named by '||${HS_NAMERS}||' routine(s) other than its writer'`);

  await req(S, 'comp-16-risk', 'Each OS reports Risk that is read',
    DIM('\\y(open_risks|risks_open|risk_count)\\y', ['open_risks', 'risks', 'risk_count']),
    DIM_EV('\\y(open_risks|risks_open|risk_count)\\y', ['open_risks', 'risks', 'risk_count']));

  await req(S, 'comp-16-performance', 'Each OS reports Performance that is read',
    DIM('\\y(kpi_gaps|kpi_attainment|performance_pct)\\y', ['kpi_gaps', 'kpi_attainment', 'performance_pct']),
    DIM_EV('\\y(kpi_gaps|kpi_attainment|performance_pct)\\y', ['kpi_gaps', 'kpi_attainment', 'performance_pct']));

  // CAPACITY. The old check gated BOTH its branches on RP_MAINTAINED — "some pg_proc contains
  // `insert into resource_pool`" — which is a different object from the one the requirement names.
  // An implementation computing per-OS capacity from headcount, open task load or agent throughput
  // and publishing it in os_review.metrics with a live reader scored MISSING. It is now scored
  // exactly like the other seven dimensions, with ONE extra clause and a reason for it: TRAP 3 was
  // found here, where capacity_pct was 0.0 on every OS that had a value at all because
  // resource_pool.committed was 0 on all ten rows and no routine in the database ever wrote it. A
  // ratio whose numerator has no writer is a constant wearing a percentage sign, and a per-OS
  // figure that is zero for EVERY active OS is that constant. The clause names no table and no
  // implementation — it asks the published figure to be something other than uniformly zero.
  const CAP_KEYS = ['capacity', 'capacity_pct', 'used_pct'];
  const CAP_MAX = `(select max((r.metrics->>k)::numeric) from public.os_review r
      join public.operating_system o on o.os_key = r.os_key and o.active,
      unnest(array['capacity','capacity_pct','used_pct']) k
     where r.period = ${PERIOD} and jsonb_typeof(r.metrics->k) = 'number')`;
  await req(S, 'comp-16-capacity', 'Each OS reports Capacity that is read',
    `select coalesce(${DIM_OK(CAP_KEYS)} >= ${OS_COUNT} and ${FRESH}
       and ${FIGURE_READERS('\\y(capacity|capacity_pct|used_pct)\\y')} > 0
       and coalesce(${CAP_MAX}, 0) > 0, false)`,
    `select ${DIM_OK(CAP_KEYS)}||' of '||${OS_COUNT}
       ||' active OS carry a NON-NULL capacity value in os_review.metrics ('||${PERIOD}
       ||'), highest '||coalesce(${CAP_MAX}::text,'(none)')||'%, '
       ||${FIGURE_READERS('\\y(capacity|capacity_pct|used_pct)\\y')}||' live reader(s) of the figure; '
       ||'resource_pool: '||(select count(*) from public.resource_pool where os_key is not null)||' of '
       ||(select count(*) from public.resource_pool)||' row(s) keyed to an OS across '
       ||(select count(distinct os_key) from public.resource_pool)||' OS, sum(committed)='
       ||(select round(coalesce(sum(committed),0),2) from public.resource_pool)`);

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
  // does, per OS. VIEW_READ excludes the view's own copier fn_os_review and requires the remaining
  // reader to be reachable; the fn_os_health branch takes the same treatment, so a reader that is
  // itself unreachable no longer certifies the routine.
  await req(S, 'comp-16-fn-os-health', 'fn_os_health / v_os_health report per-OS health that is read',
    `select coalesce((${VIEW_READ} > 0 and ${VIEW_OS_ROWS} >= ${OS_COUNT})
       or (select coalesce(bool_or(pg_get_functiondef(p.oid) ~* '\\yos_key\\y'
             and pg_get_functiondef(p.oid) ~* '\\y(operating_system|v_os_scoreboard|os_department)\\y'), false)
             from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='public' and p.proname='fn_os_health')
          and ${LIVE_CONSUMERS('fn_os_health')} > 0, false)`,
    `select 'v_os_health covers '||${VIEW_OS_ROWS}||' of '||${OS_COUNT}||' active OS and has '
       ||${VIEW_READ}||' reachable reader(s) other than its copier fn_os_review ('
       ||coalesce((select string_agg(distinct p.proname,',')
            from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_os_review'
             and pg_get_functiondef(p.oid) ~* '\\yv_os_health\\y' and ${LIVE('p')}),'none')
       ||'); fn_os_health is per-OS: '
       ||coalesce((select bool_or(pg_get_functiondef(p.oid) ~* '\\yos_key\\y')::text
            from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname='fn_os_health'),'absent')
       ||', with '||${LIVE_CONSUMERS('fn_os_health')}||' reachable reader(s) ('
       ||${LIVE_CONSUMER_NAMES('fn_os_health')}||')'`);

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
           where j.active and j.command ~* '\\yfn_os_improve\\y' and d.status='succeeded'),'never')`);

  // And the answer to "does it reach someone": a question raised more than a week ago and still
  // sitting at 'proposed' reached nobody, and a question filed to a department with no active
  // employee was never addressed to anyone.
  //
  // BOTH UNIVERSALS ARE WINDOWED, and they were not. They ranged over every improvement task ever
  // created, so ONE historical row left at 'proposed' for eight days — exactly what the first
  // un-picked-up weekly batch produces — made this requirement MISSING for ever, because no future
  // action can un-create it. The same for a task filed to a department that later loses its last
  // active employee. A requirement no future work can satisfy is not a measurement. The window is
  // the same 21 days the "raised recently" clause uses, so the check still bites within a fortnight
  // of the batch stopping and still recovers when the backlog is worked.
  // A STATUS IS NOT A RECIPIENT (6 Aug 2026). "Picked up" was `status <> 'proposed' > 0`, and all
  // 13 rows that satisfied it had status='assigned' AND decided_by='approval_path' — moved by
  // fn_task_approve's hourly sweep, which resolves the department's authority tier and reads
  // nothing whatever about the question. Six questions raised on 2026-07-28 sat at 'proposed' for
  // nine days and were flipped at the identical timestamp 2026-08-06 03:59:06. Nobody received
  // them; a column changed value.
  //
  // Nor did the question travel by itself: fn_agent_context's workload block is
  // `order by t.id limit 6` over the department's open tasks, so a question raised into a
  // department with a backlog is never in anybody's prompt. Measured across the 15 questions of the
  // last 21 days, 2 reached any employee and 13 reached nobody.
  //
  // The leg is now a per-row universal on DELIVERY: every improvement question raised in the window
  // must sit in a NAMED ACTIVE EMPLOYEE's own queue — an agent_actions row keyed to that task,
  // whose `agent` resolves to an active employee. agent_actions is the queue an employee actually
  // reads (supabase/functions/agent_brain/index.ts:139 selects it by `.eq('agent', key)` into the
  // context that employee reasons over), and fn_improvement_handover on improvement_handover_hourly
  // is what puts it there. The `> 0` it replaces could be satisfied by one row out of fifteen; this
  // cannot be satisfied while a single question is undelivered, and it goes false again the hour
  // after the sweep stops.
  const IMP = `public.org_tasks t where t.title like '% improvement: %'`;
  const IMP_RECENT = `and t.created_at > now() - interval '21 days'`;
  const IMP_STALE = `(select count(*) from ${IMP} ${IMP_RECENT}
      and t.created_at < now() - interval '7 days' and t.status = 'proposed')`;
  const IMP_UNSTAFFED = `(select count(*) from ${IMP} ${IMP_RECENT}
      and not exists (select 1 from public.org_agents a where a.department = t.dept_key and a.active))`;
  const IMP_UNDELIVERED = `(select count(*) from ${IMP} ${IMP_RECENT}
      and not exists (select 1 from public.agent_actions q
                       where q.kind = 'improvement_question' and q.target_table = 'org_tasks'
                         and q.target_id = t.id::text
                         and exists (select 1 from public.org_agents g
                                      where g.agent_key = q.agent and g.active)))`;
  const IMP_RECIPIENTS = `(select count(distinct q.agent) from public.agent_actions q
      where q.kind = 'improvement_question'
        and exists (select 1 from public.org_tasks t2 where t2.id::text = q.target_id
                     and t2.title like '% improvement: %'
                     and t2.created_at > now() - interval '21 days'))`;
  await req(S, 'comp-17-questions-read', 'The improvement questions reach someone',
    `select coalesce((select count(*) from ${IMP} ${IMP_RECENT}) > 0
       and ${IMP_UNDELIVERED} = 0
       and ${IMP_STALE} = 0
       and ${IMP_UNSTAFFED} = 0, false)`,
    `select (select count(*) from ${IMP})||' improvement question(s) in '
       ||(select count(distinct dept_key) from public.org_tasks where title like '% improvement: %')
       ||' department(s), '||(select count(*) from ${IMP} ${IMP_RECENT})
       ||' raised in the last 21d, of which '||${IMP_UNDELIVERED}
       ||' are in no active employee''s queue; the rest are held by '||${IMP_RECIPIENTS}
       ||' named employee(s); '||${IMP_STALE}||' still ''proposed'' after 7 days, '
       ||${IMP_UNSTAFFED}||' filed to a department with no active employee; handover cron last ok '
       ||coalesce((select max(d.end_time)::timestamp(0)::text from cron.job_run_details d
            join cron.job j on j.jobid=d.jobid
           where j.active and j.command ~* '\\yfn_improvement_handover\\y'
             and d.status='succeeded'),'never')`);
}
