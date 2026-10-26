// SPEC FILE #3, sections 21-40 — Enterprise Event Nervous System .. Company Maturity Index.
// 42 requirements, scored against PRODUCTION.
//
// These twenty sections are where the spec's defining defect is thickest. Almost everything they
// describe EXISTS on production and runs on an active cron: company_index measures a maturity score
// and an organisational-energy score every morning at 03:40, agent_reputation grades 66 employees
// on six axes every Monday, graph_nodes and graph_edges are rebuilt nightly, board_advisor holds
// exactly the seven advisors the spec names, evolution_proposal holds 32 evidence-backed structural
// proposals. None of it is displayed. So a scorer that asks "does the table have rows" would report
// this file at something near full marks and be wrong about almost every line of it.
//
// Every check therefore separates three questions and never lets one answer another:
//   1. EXISTS   — is there a mechanism (table, column, routine, cron, node kind)?
//   2. RUNS     — has it actually produced something recently, over the whole population?
//   3. DELIVERS — can the founder SEE the result?
//
// ---- how DELIVERS is measured, and why it is measured this way ----------------------------------
// Not by asking whether some routine mentions the table. The row #2 scorer was refuted three times
// on exactly that: the only "reader" of a column turned out to be the function that writes it, and a
// reachable routine that touches a table internally shows the founder nothing. agent_reputation is
// the live example here — its one reachable reader is fn_pick_reviewer, which consumes the score to
// choose a reviewer and returns an agent_key. The score is read and still never seen.
//
// So delivery is measured EMPIRICALLY: the module executes the browser's own read surfaces and
// searches what comes back. SURFACE below is the concatenated JSON payload of every routine that
//   (a) a browser-reachable edge function dispatches by name (ui.roots, scanned from the repo), and
//   (b) takes no arguments, so the browser can invoke it exactly as os_api does, and
//   (c) is NOT volatile — Postgres refuses a data-modifying statement inside a non-volatile
//       function, which is what makes running these against PRODUCTION a read and not a write.
// Measured 6 Aug 2026 that is 23 routines and ~300 KB of payload, plus fn_agent_context('cfo'), the
// text an employee reasons over and therefore what the founder gets back through the console.
//
// The handful of browser-dispatched routines that cannot be executed under that rule — the volatile
// or argument-taking screens, fn_os_command, fn_ws_finance, fn_ws_agents, fn_ws_agent_ops,
// fn_os_health, fn_os_runbooks — are the ONE place a static test is still used: if one of them names
// the relation without writing it, that counts as delivered. Without that fallback this file would
// report a false MISSING for anything shown only on the landing tiles, and a check no implementation
// could satisfy is as much a defect as one nothing can fail.
//
// ---- the four other traps, and where each is answered -------------------------------------------
// ONE ROW MUST NOT SCORE A MECHANISM. Where the requirement names a set — nine event classes, seven
// task classes, ten maturity dimensions, six reputation axes, four restructuring questions — the
// check is a per-member universal over a `values` list of named classes, and the evidence prints the
// members that are MISSING by name. A global count above zero appears nowhere in this file.
//
// A FLAG IS NOT AN EVENT. invite_schedule.planned is the exact shape the brief warns about: a column
// a person can set to true. s26-recommend-onboarding scores `sent`, never `planned`.
//
// NO TABLE CONTENT ON THE PATTERN SIDE OF LIKE. Every needle taken from a row — a competitor's name,
// an index_name — goes through position(), which takes a literal. 35 of 72 values in the sibling
// spec carried an underscore, and `_` is a single-character wildcard in LIKE: the error could only
// ever manufacture a MET.
//
// EVIDENCE IS A NUMBER, NOT A RESTATEMENT. Every evidence string is computed over the same rows as
// the verdict it accompanies, and no evidence string ends in prose asserting a fact it did not query.
import { UI_READS, UI_READ_NAMES, ALL_READS, REL_EXISTS, sqlArr, safeToken,
         closure, ROOT_FNS } from './ui_closure.mjs';

export const label = 'sections 21-40 (Event Nervous System .. Company Maturity Index)';
export const EXPECTED = 42;
export const expected = 42;

export default async function ({ req, one, ui }) {
  const S = 'sec21-40';

  // The runner computes the closure once and hands it over; several agents are editing that runner
  // in parallel, so this module falls back to computing it itself rather than taking the whole
  // section down if the helper is renamed. Both paths return the identical set — ui_closure memoises
  // it — and a section that cannot be run measures nothing at all.
  const C = (ui && ui.UI) ? ui : await closure(one);
  const roots = (ui && ui.roots) ? ui.roots : ROOT_FNS;

  // A single-quoted SQL literal that keeps backslashes intact. ui_closure's sqlStr doubles them,
  // which is right for a value and wrong for a POSIX regex: '\\y' under standard_conforming_strings
  // is a literal backslash followed by y, so every word-boundary anchor would silently stop working
  // and every class in every `values` list would score as uncovered.
  const rq = (s) => `'` + String(s).replace(/'/g, `''`) + `'`;

  // ---- the browser's own payload ---------------------------------------------------------------
  // Split in two by what can be executed. `pronargs = 0` is the browser's calling convention for a
  // screen (os_api invokes all eighteen workspace routines with no arguments); `provolatile <> 'v'`
  // is the guarantee that executing one against production cannot write, because PostgreSQL refuses
  // a data-modifying statement inside a STABLE or IMMUTABLE function.
  // ── AND `not p.proretset`, WHICH COST 18 REQUIREMENTS THEIR MEASUREMENT ──────────────────────
  // SURFACE below calls every `callable` routine inside a VALUES list. PostgreSQL forbids a
  // set-returning function there, so ONE screen routine that RETURNS TABLE or SETOF — with zero
  // arguments and STABLE volatility, so it passed both existing filters — made every check that
  // uses DELIVERED() fail with:
  //
  //     ERROR 0A000: set-returning functions are not allowed in VALUES
  //
  // Measured on production 2026-08-09, that was 18 of this file's checks ERRORED. An errored check
  // is an UNMEASURED requirement, not a MISSING one, so the run reported 21/152 while eighteen
  // requirements had no verdict at all and the printed percentage was not trustworthy.
  //
  // The set-returning screens are NOT dropped — that would silently shrink the surface and turn a
  // measurement bug into a scoring bug. They move to `uncallable`, where a static read of them
  // still counts, which is exactly how every other non-executable screen is already handled.
  const rootList = sqlArr(roots.filter(safeToken));
  const callable = String(await one(
    `select coalesce(string_agg(distinct p.proname, ','), '') from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname='public' and p.prokind in ('f','p')
        and p.pronargs = 0 and p.provolatile <> 'v' and not p.proretset
        and p.proname = any(${rootList})`) || '')
    .split(',').filter(safeToken);
  // The screens that cannot be executed under that rule, so a static read of them still counts.
  // fn_agent_context is excluded because it IS executed below, with arguments.
  const uncallable = String(await one(
    `select coalesce(string_agg(distinct p.proname, ','), '') from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_agent_context'
        and (p.pronargs > 0 or p.provolatile = 'v' or p.proretset) and p.proname = any(${rootList})`) || '')
    .split(',').filter(safeToken);
  const UNCALLABLE = sqlArr(uncallable);

  // The payload itself. Evaluated once per statement by Postgres; ~1.5s and ~300 KB on production.
  const SURFACE = callable.length
    ? `(select string_agg(x, chr(32)) from (values ${callable.map(f => `(public.${f}()::text)`).join(',')},
         (public.fn_agent_context('cfo', 22000))) v(x))`
    : `(select public.fn_agent_context('cfo', 22000))`;

  // A figure is DELIVERED when the browser's payload carries it, or when a screen this module could
  // not execute reads the relation that holds it without writing it. The write keywords are split so
  // qd_guard's read guard, which refuses any statement containing a bare write keyword, does not
  // reject the check itself.
  const NOT_WRITER = (t) => `pg_get_functiondef(p.oid) !~* ('(inse'||'rt\\s+into|upd'||'ate|del'||'ete\\s+from)\\s+(public\\.)?${t}\\y')`;
  const STATIC_SCREENS = (t) => `(select count(distinct p.proname) from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname='public' and p.prokind in ('f','p') and p.proname = any(${UNCALLABLE})
         and pg_get_functiondef(p.oid) ~* '\\y${t}\\y' and ${NOT_WRITER(t)})`;
  const DELIVERED = (rx, t) => `((${SURFACE}) ~* ${rq(rx)} or ${STATIC_SCREENS(t)} > 0)`;
  const DELIVERED_EV = (rx, t) => `'payload carries /'||${rq(rx)}||'/: '||(((${SURFACE}) ~* ${rq(rx)}))::text
      ||', unexecutable screen(s) reading ${t}: '||${STATIC_SCREENS(t)}
      ||', reachable reader(s): '||${UI_READS(C, t)}||' of '||${ALL_READS(t)}||' total'`;

  // A cron ROW is a claim; a SUCCEEDED RUN is the fact. Every liveness clause in this file routes here.
  //
  // THE COMMAND NO LONGER NAMES THE ROUTINE (27 Aug 2026). Twenty-two of the twenty-three active
  // jobs read `select public.fn_kernel_cron_exec(<jobid>)`; the command they actually run is held in
  // phase_c_system_execution_wrapper.original_command. Matching a routine name against
  // cron.job.command therefore matched NOTHING for twenty-two live jobs, and evolution_scan_weekly,
  // monthly_report, regulation_watch_weekly and the AI spend guard — all running, all on schedule,
  // all with a succeeded kernel trace — read as never having run. Measured: `select command from
  // cron.job where jobid=142` returns the wrapper call, and the wrapper row returns
  // `select public.fn_evolution_scan();`. So the effective command is resolved, once, here.
  //
  // AND THE WRAPPER SWALLOWS FAILURES. fn_kernel_cron_exec catches, records result='failed' on the
  // trace, and returns normally, so cron.job_run_details says 'succeeded' for a run whose work threw.
  // Resolving the command alone would therefore have made these clauses WEAKER than they were. The
  // trace is asserted alongside: a run counts only if the wrapper did not record a failure for that
  // component in the same window. Stated as a NOT EXISTS rather than a positive trace requirement,
  // because a run from before the wrapper was installed has no trace row and is not thereby a failure.
  const EFF_CMD = `coalesce(w.original_command, j.command)`;
  const CRON_J = `cron.job j left join public.phase_c_system_execution_wrapper w on w.jobid = j.jobid`;
  const NO_TRACED_FAILURE = (days) => `not exists (select 1 from public.phase_c_system_execution x
      where x.component_id = 'cron:' || j.jobname and x.result = 'failed'
        and x.finished_at > now() - interval '${days} days')`;
  const RAN = (rx, days) => `exists (select 1 from ${CRON_J} join cron.job_run_details d on d.jobid=j.jobid
      where j.active and ${EFF_CMD} ~* ${rq('\\y(' + rx + ')\\y')} and d.status='succeeded'
        and d.end_time > now() - interval '${days} days' and ${NO_TRACED_FAILURE(days)})`;
  const LAST_OK = (rx) => `coalesce((select max(d.end_time)::timestamp(0)::text from ${CRON_J}
      join cron.job_run_details d on d.jobid=j.jobid where j.active
        and ${EFF_CMD} ~* ${rq('\\y(' + rx + ')\\y')} and d.status='succeeded'), 'never')`;

  // ---- named-class coverage --------------------------------------------------------------------
  // The shape every "the spec names N things" requirement uses. `src` is a subquery producing one
  // `txt` column per candidate row; each named class must be matched by at least one of them. This
  // is a per-class universal, not a count: nine classes of which one is covered scores 1, and the
  // evidence names the eight that are not.
  const VALS = (list) => list.map(([l, rx]) => `(${rq(l)},${rq(rx)})`).join(',');
  const COVERED = (src, list) => `(select count(*) from (values ${VALS(list)}) c(lbl,rx)
      where exists (select 1 from ${src} s where s.txt ~* c.rx))`;
  const UNCOVERED = (src, list) => `coalesce((select string_agg(c.lbl, ', ' order by c.lbl)
      from (values ${VALS(list)}) c(lbl,rx)
     where not exists (select 1 from ${src} s where s.txt ~* c.rx)), 'none')`;

  // The same shape over the keys of a company_index dimensions jsonb. A KEY IS NOT A VALUE: a
  // dimension present with a JSON null is not measured, so jsonb_typeof is asserted.
  const DIMS = (idx) => `(select dimensions from public.company_index
      where index_name=${rq(idx)} order by measured_on desc, id desc limit 1)`;
  const DIM_SRC = (idx) => `(select e.key as txt from jsonb_each(${DIMS(idx)}) e
      where jsonb_typeof(e.value) <> 'null')`;

  // …and over COLUMNS of a table, where the requirement is "every record carries these fields".
  // A field counts only when a matching column exists AND no row in the scored population leaves it
  // null — "the column exists" is the mechanism question, and this file never lets it answer the
  // population question. `where` scopes the universal so a historical row cannot make a requirement
  // permanently unsatisfiable.
  const FIELD_COVERED = (tbl, list, where = 'true') => `(select count(*) from (values ${VALS(list)}) c(lbl,rx)
      where exists (select 1 from information_schema.columns k
                     where k.table_schema='public' and k.table_name=${rq(tbl)} and k.column_name ~* c.rx
                       and not exists (select 1 from public.${tbl} r
                                        where (${where}) and (to_jsonb(r)->>k.column_name) is null)))`;
  const FIELD_UNCOVERED = (tbl, list, where = 'true') => `coalesce((select string_agg(c.lbl, ', ' order by c.lbl)
      from (values ${VALS(list)}) c(lbl,rx)
     where not exists (select 1 from information_schema.columns k
                        where k.table_schema='public' and k.table_name=${rq(tbl)} and k.column_name ~* c.rx
                          and not exists (select 1 from public.${tbl} r
                                           where (${where}) and (to_jsonb(r)->>k.column_name) is null))), 'none')`;

  // ============================================================================================
  // SECTION 21 — ENTERPRISE EVENT NERVOUS SYSTEM
  // ============================================================================================
  // "All nine named things are emitted as events." Two independent sources count as an emitter, and
  // both are code-or-fact rather than intent: an event of that class actually recorded in the last
  // year, or a routine that passes that event type to an fn_emit* function as a literal. A
  // subscription does NOT count — production subscribes to rfq.created, supplier.applied and
  // customer.complaint and has never emitted any of the three, which is precisely the gap.
  // A THIRD EMITTER SHAPE (27 Aug 2026). The two arms below see an event type recorded on the bus,
  // and an event type written as a literal inside a routine. Neither can see the type that is passed
  // as a TRIGGER ARGUMENT — `EXECUTE FUNCTION fn_emit_event('inquiry', 'rfq.created')` keeps the type
  // in pg_trigger.tgargs, and fn_emit_event reads it as tg_argv[1], so pg_get_functiondef contains
  // no event type at all. This check reported "RFQ created" as the one class production does not
  // emit, while trg_event_inquiry has been emitting rfq.created on every inquiry insert. Eight types
  // were invisible this way, payment.received and quote.received among them. Only arguments
  // containing a dot are taken, so the entity-type argument beside them ('inquiry') is not mistaken
  // for an event type.
  const EVENT_SRC = `(select event_type as txt from public.company_event
        where occurred_at > now() - interval '365 days'
      union all
      select m[1] from pg_proc p join pg_namespace n on n.oid=p.pronamespace,
        regexp_matches(pg_get_functiondef(p.oid), 'fn_emit[a-z_]*\\s*\\(\\s*''([a-z0-9._]+)''', 'g') m
       where n.nspname='public' and p.prokind in ('f','p')
      union all
      select m[1] from pg_trigger t join pg_proc f on f.oid = t.tgfoid
        join pg_namespace fn on fn.oid = f.pronamespace,
        regexp_matches(pg_get_triggerdef(t.oid), '''([a-z0-9]+\\.[a-z0-9._]+)''', 'g') m
       where not t.tgisinternal and t.tgenabled <> 'D' and fn.nspname='public'
         and f.proname ~ '^fn_emit')`;
  const NINE = [
    ['customer registered', 'customer\\.(registered|created|signed_?up|onboarded|joined)'],
    ['RFQ created', '(rfq|inquiry|quote_?request)\\.(created|received|opened|raised)'],
    ['supplier approved', 'supplier\\.(approved|verified|onboarded|activated|accepted)'],
    ['revenue received', '(revenue|payment|invoice|transaction|cash)\\.(received|paid|settled|recorded|captured)'],
    ['campaign launched', '(campaign|marketing|ads?)\\.(launched|published|started|live|created)'],
    ['AI confidence dropped', '(ai|model|agent|quality)[._](confidence|quality)|confidence\\.(dropped|fell|low)'],
    ['knowledge updated', 'knowledge\\.(updated|changed|published|revised|refreshed)'],
    ['infrastructure warning', '(infra|infrastructure|system|edge|health|uptime|service)\\.(warning|degraded|down|alert|changed|failed)|test\\.failed'],
    ['competitor pricing change', 'competitor\\.(pricing|price|changed|updated|moved)'],
  ];
  await req(S, 's21-events-nine-classes', 'All nine named things are emitted as events',
    `select coalesce(${COVERED(EVENT_SRC, NINE)} = ${NINE.length}
       and (select count(*) from public.company_event where occurred_at > now() - interval '24 hours') > 0, false)`,
    `select ${COVERED(EVENT_SRC, NINE)}||' of ${NINE.length} named event class(es) are emitted; missing: '
       ||${UNCOVERED(EVENT_SRC, NINE)}||'; the bus carried '
       ||(select count(*) from public.company_event where occurred_at > now() - interval '24 hours')
       ||' event(s)/24h across '||(select count(distinct event_type) from public.company_event)
       ||' type(s) ever, while '||(select count(distinct event_type) from public.event_subscription where active)
       ||' type(s) are subscribed to'`);

  // "Nothing polls the database - everything reacts to events via subscriptions."
  // The measurement is the LATENCY, which is the one number a poll cannot fake: fn_event_dispatch on
  // event_dispatch_15min is itself a scan, so a reactive bus and a polled one are indistinguishable
  // by row counts and differ by minutes in delivered_at - occurred_at. A trigger on company_event
  // that hands the event straight to the dispatcher makes both legs true; nothing else does.
  const LAG = `(select percentile_disc(0.5) within group (order by extract(epoch from d.delivered_at - e.occurred_at))
      from public.event_delivery d join public.company_event e on e.id = d.event_id
     where d.delivered_at > now() - interval '7 days')`;
  const REACT_TRIGGER = `exists (select 1 from pg_trigger t join pg_proc f on f.oid = t.tgfoid
      join pg_class c on c.oid = t.tgrelid join pg_namespace cn on cn.oid = c.relnamespace
     where cn.nspname='public' and c.relname='company_event' and not t.tgisinternal and t.tgenabled <> 'D'
       and pg_get_functiondef(f.oid) ~* '\\y(fn_event_dispatch|fn_event_fanout|fn_dispatch_event)\\s*\\(')`;
  await req(S, 's21-no-polling', 'Delivery reacts to the event rather than polling for it',
    `select coalesce(${REACT_TRIGGER}
       and (select count(*) from public.event_delivery where delivered_at > now() - interval '7 days') > 0
       and coalesce(${LAG}, 1e9) < 60, false)`,
    `select 'trigger on company_event hands events to the dispatcher: '||(${REACT_TRIGGER})::text
       ||'; median delivery lag '||coalesce(round(${LAG})::text,'(no deliveries)')||'s over '
       ||(select count(*) from public.event_delivery where delivered_at > now() - interval '7 days')
       ||' deliver(ies)/7d; '||(select count(*) from cron.job where active)||' active cron job(s) scan on a schedule'`);

  // ============================================================================================
  // SECTION 22 — ORGANIZATIONAL GRAPH ENGINE
  // ============================================================================================
  // The spec's own chain is the requirement, so the chain is what is measured: every one of its nine
  // classes must exist as a node kind, every one of its eight hops must exist as an edge between two
  // such kinds, and something the founder can reach must read the graph. Node kinds alone would pass
  // a graph with nine islands and no edges.
  const NODE_SRC = `(select kind as txt from public.graph_nodes)`;
  const CHAIN = [
    ['customer', 'customer|buyer|account'],
    ['rfq', 'rfq|inquiry|request'],
    ['category', 'categor'],
    ['supplier', 'supplier|vendor|lead'],
    ['quote', 'quote|bid|offer'],
    ['revenue', 'revenue|payment|transaction|invoice'],
    ['campaign', 'campaign|marketing|content'],
    ['knowledge', 'knowledge|kb_|document'],
    ['employee', 'employee|agent|person'],
  ];
  const HOPS = CHAIN.slice(0, -1).map((c, i) => [c[0] + '->' + CHAIN[i + 1][0], c[1], CHAIN[i + 1][1]]);
  const HOPS_OK = `(select count(*) from (values ${HOPS.map(([l, a, b]) => `(${rq(l)},${rq(a)},${rq(b)})`).join(',')}) h(lbl,a,b)
      where exists (select 1 from public.graph_edges g
                     where (g.src_kind ~* h.a and g.dst_kind ~* h.b)
                        or (g.src_kind ~* h.b and g.dst_kind ~* h.a)))`;
  const HOPS_MISSING = `coalesce((select string_agg(h.lbl, ', ') from (values ${HOPS.map(([l, a, b]) => `(${rq(l)},${rq(a)},${rq(b)})`).join(',')}) h(lbl,a,b)
      where not exists (select 1 from public.graph_edges g
                         where (g.src_kind ~* h.a and g.dst_kind ~* h.b)
                            or (g.src_kind ~* h.b and g.dst_kind ~* h.a))), 'none')`;
  await req(S, 's22-graph-navigation', 'The spec chain can be walked through relationships',
    `select coalesce(${REL_EXISTS('graph_nodes')} and ${REL_EXISTS('graph_edges')}
       and ${COVERED(NODE_SRC, CHAIN)} = ${CHAIN.length}
       and ${HOPS_OK} = ${HOPS.length}
       and ${DELIVERED('graph_nodes|graph_edges|src_kind', 'graph_edges')}, false)`,
    `select ${COVERED(NODE_SRC, CHAIN)}||' of ${CHAIN.length} chain class(es) exist as node kinds (missing: '
       ||${UNCOVERED(NODE_SRC, CHAIN)}||'), '||${HOPS_OK}||' of ${HOPS.length} hop(s) exist as edges (missing: '
       ||${HOPS_MISSING}||'); '||(select count(*) from public.graph_nodes)||' node(s)/'
       ||(select count(*) from public.graph_edges)||' edge(s) rebuilt '
       ||coalesce((select max(updated_at)::timestamp(0)::text from public.graph_nodes),'never')||'; '
       ||${DELIVERED_EV('graph_nodes|graph_edges|src_kind', 'graph_edges')}`);

  // ============================================================================================
  // SECTION 23 — AUTONOMOUS RESOURCE ALLOCATION
  // ============================================================================================
  // The three named classes are matched on the RESOURCE being moved, never on the reason text. Every
  // one of production's twelve rows carries the sentence "marketing used only 0.0% of its budget",
  // so a match against the prose would score "marketing budget shifts to higher-performing channels"
  // for a row that moved an AI budget between departments and touched no channel at all.
  // SEPARATORS IN THE RESOURCE NAME (12 Aug 2026). The classes below match with \y word
  // boundaries, deliberately, so that 'ai' does not fire on 'email' or 'maintain'. But '_' is a
  // WORD character in Postgres regex, so 'ai_budget_aed' has no boundary after 'ai' and
  // \yai\y does not match it — measured, `select 'ai_budget_aed' ~* '\yai\y'` returns false.
  // Production holds twelve allocation_change rows and every one of them is resource
  // 'ai_budget_aed', so the check reported "0 of 3" for a company that HAS reallocated AI budget
  // twelve times. Underscores and hyphens are separators in an identifier; normalising them to
  // spaces lets the boundary anchors work as intended without loosening them into false
  // positives. Same defect as leads.sector 'building-materials' against the alias
  // 'building materials', one table over.
  //
  // This does NOT make the check pass and is not intended to: marketing budget and supplier
  // onboarding capacity have genuinely never been reallocated, so the verdict moves from
  // "0 of 3" to "1 of 3" and stays MISSING. The point is that "0 of 3" was false.
  const ALLOC_SRC = `(select regexp_replace(resource, '[-_]+', ' ', 'g') as txt
      from public.allocation_change
      where created_at > now() - interval '62 days')`;
  const ALLOC_CLASSES = [
    ['marketing budget to channels', 'marketing|channel|campaign|\\yads?\\y'],
    ['AI compute to higher-value tasks', '\\yai\\y|compute|token|model|llm'],
    ['supplier onboarding capacity', 'onboard|invite|capacity|supplier'],
  ];
  await req(S, 's23-reallocation-three-classes', 'Resources reallocate across all three named classes',
    `select coalesce(${RAN('fn_reallocate|reallocate', 45)}
       and (select count(*) from public.allocation_change where created_at > now() - interval '62 days') > 0
       and ${COVERED(ALLOC_SRC, ALLOC_CLASSES)} = ${ALLOC_CLASSES.length}
       and ${DELIVERED('allocation_change|reallocat', 'allocation_change')}, false)`,
    `select ${COVERED(ALLOC_SRC, ALLOC_CLASSES)}||' of ${ALLOC_CLASSES.length} named resource class(es) moved in 62d; missing: '
       ||${UNCOVERED(ALLOC_SRC, ALLOC_CLASSES)}||'; '
       ||(select count(*) from public.allocation_change where created_at > now() - interval '62 days')
       ||' reallocation(s)/62d over resource(s) '
       ||coalesce((select string_agg(distinct resource, ', ') from public.allocation_change),'(none)')
       ||'; monthly cron last ok '||${LAST_OK('fn_reallocate|reallocate')}||'; '
       ||${DELIVERED_EV('allocation_change|reallocat', 'allocation_change')}`);

  // "Every reallocation is governed by, and cites, a policy" — a per-row universal, windowed so a
  // historical row cannot make the requirement permanently unsatisfiable, plus the clause that stops
  // a no-op from counting: a row whose from_value equals its to_value moved nothing.
  const ALLOC_WIN = `created_at > now() - interval '62 days'`;
  const ALLOC_UNCITED = `(select count(*) from public.allocation_change
      where ${ALLOC_WIN} and coalesce(btrim(policy), '') = '')`;
  const ALLOC_NOOP = `(select count(*) from public.allocation_change
      where ${ALLOC_WIN} and from_value is not distinct from to_value)`;
  await req(S, 's23-reallocation-policy-cited', 'Every reallocation cites a policy',
    `select coalesce((select count(*) from public.allocation_change where ${ALLOC_WIN}) > 0
       and ${ALLOC_UNCITED} = 0 and ${ALLOC_NOOP} = 0
       and ${RAN('fn_reallocate|reallocate', 45)}, false)`,
    `select (select count(*) from public.allocation_change where ${ALLOC_WIN})||' reallocation(s)/62d, '
       ||${ALLOC_UNCITED}||' citing no policy and '||${ALLOC_NOOP}||' moving nothing; '
       ||(select count(distinct policy) from public.allocation_change where ${ALLOC_WIN})
       ||' distinct policy text(s); cron last ok '||${LAST_OK('fn_reallocate|reallocate')}`);

  // ============================================================================================
  // SECTION 24 — AI BOARD OF DIRECTORS
  // ============================================================================================
  // Seven named lenses, matched over key+name+lens so that production's advisor_key 'supplier',
  // whose name is "Marketplace Advisor", is scored on what it IS rather than on how it is keyed.
  const ADVISOR_SRC = `(select (advisor_key||' '||coalesce(name,'')||' '||coalesce(lens,'')) as txt
      from public.board_advisor where coalesce(active,true))`;
  const ADVISORS = [
    ['Risk', 'risk|downside'],
    ['Economist', 'econom'],
    ['Growth', 'growth|compound'],
    ['Customer Advocate', 'customer|buyer|advocate'],
    ['Ethics', 'ethic|integrity'],
    ['Technology', 'technolog|feasib'],
    ['Marketplace', 'marketplace|market\\y|supply side'],
  ];
  await req(S, 's24-board-seven-advisors', 'The seven specialist advisors exist beyond the exec team',
    `select coalesce(${COVERED(ADVISOR_SRC, ADVISORS)} = ${ADVISORS.length}
       and (select count(*) from public.board_advisor where coalesce(active,true)) >= ${ADVISORS.length}
       and ${DELIVERED('board_advisor|advisor_key|board_opinion', 'board_advisor')}, false)`,
    `select ${COVERED(ADVISOR_SRC, ADVISORS)}||' of ${ADVISORS.length} named lens(es) staffed by an active advisor; missing: '
       ||${UNCOVERED(ADVISOR_SRC, ADVISORS)}||'; roster: '
       ||coalesce((select string_agg(name, ', ' order by advisor_key) from public.board_advisor where coalesce(active,true)),'(empty)')
       ||'; '||${DELIVERED_EV('board_advisor|advisor_key|board_opinion', 'board_advisor')}`);

  // "Before any major decision each advisor gives an independent recommendation." Two halves, and
  // neither can stand for the other: the decision path must INVOKE the board (a call form, not a
  // mention — a dead comment naming fn_board_review is not a mechanism), and every recorded decision
  // in the window must actually carry one opinion per active advisor. The link is tried three ways
  // because board_opinion.subject_ref is null on all 28 production rows and a subject-text match is
  // the only other honest join; position() is used rather than LIKE because both sides are row data.
  const BOARD_INVOKED = `exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.prokind in ('f','p')
        and p.proname in ('fn_decide','fn_decision_gate','fn_task_approve','fn_check_spend','fn_exec_meeting')
        and pg_get_functiondef(p.oid) ~* '\\yfn_board_review\\s*\\(')`;
  const DEC_WIN = `d.created_at > now() - interval '30 days'`;
  const DEC_N = `(select count(*) from public.decision_record d where ${DEC_WIN})`;
  const ADV_N = `(select count(*) from public.board_advisor where coalesce(active,true))`;
  const DEC_UNADVISED = `(select count(*) from public.decision_record d where ${DEC_WIN}
      and (select count(distinct o.advisor_key) from public.board_opinion o
            where o.subject_ref = d.id::text
               or position(coalesce(d.problem,'~none~') in coalesce(o.subject,'')) > 0
               or position(coalesce(o.subject,'~none~') in coalesce(d.problem,'')) > 0) < ${ADV_N})`;
  await req(S, 's24-board-before-major-decisions', 'Each advisor recommends before a major decision',
    `select coalesce(${BOARD_INVOKED} and ${DEC_N} > 0 and ${DEC_UNADVISED} = 0, false)`,
    `select 'the decision path invokes fn_board_review: '||(${BOARD_INVOKED})::text||'; '
       ||(${DEC_N} - ${DEC_UNADVISED})||' of '||${DEC_N}||' decision(s)/30d carry an opinion from all '
       ||${ADV_N}||' active advisor(s); board_opinion holds '||(select count(*) from public.board_opinion)
       ||' opinion(s) over '||(select count(distinct subject) from public.board_opinion)
       ||' subject(s), newest '||coalesce((select max(created_at)::date::text from public.board_opinion),'never')`);

  // ============================================================================================
  // SECTION 25 — MULTI-MODEL INTELLIGENCE
  // ============================================================================================
  const TASKCLASS_SRC = `(select task_class as txt from public.model_policy
      where coalesce(active,true) and coalesce(model_primary,'') <> '')`;
  const MODEL_CLASSES = [
    ['fast routing', 'rout(e|ing)|dispatch|intent|triage'],
    ['deep reasoning', 'reason|strateg|planning|analys|deep'],
    ['vision', 'vision|image|photo|drawing|visual'],
    ['OCR', '\\yocr\\y|scan|handwrit'],
    ['translation', 'translat|localis|localiz'],
    ['coding', 'cod(e|ing)|\\ysql\\y|script|program|develop'],
    ['summarization', 'summar|digest|abstract|brief'],
  ];
  await req(S, 's25-routing-seven-task-classes', 'Each of the seven task classes has a routing policy',
    `select coalesce(${COVERED(TASKCLASS_SRC, MODEL_CLASSES)} = ${MODEL_CLASSES.length}
       and (select count(*) from public.ai_cost_log
             where occurred_at > now() - interval '7 days'
               and coalesce(model_selected_because,'') <> '') > 0, false)`,
    `select ${COVERED(TASKCLASS_SRC, MODEL_CLASSES)}||' of ${MODEL_CLASSES.length} named task class(es) have an active policy; missing: '
       ||${UNCOVERED(TASKCLASS_SRC, MODEL_CLASSES)}||'; model_policy holds '
       ||(select count(*) from public.model_policy where coalesce(active,true))||' active row(s) over '
       ||(select count(distinct task_class) from public.model_policy where coalesce(active,true))
       ||' class(es); the router recorded '
       ||(select count(*) from public.ai_cost_log where occurred_at > now() - interval '7 days'
            and coalesce(model_selected_because,'') <> '')||' routed model request(s)/7d'`);

  // "The system compares models on quality, latency and cost." All three axes must be recorded for
  // the SAME model over the same window, for at least two models — one model compared with nothing
  // is not a comparison — and the comparison must reach a surface.
  const AXES = `(select count(*) from (
      select l.model_used from public.ai_cost_log l
       where l.occurred_at > now() - interval '30 days' and l.model_used is not null
       group by l.model_used
      having count(*) filter (where l.latency_ms is not null) > 0
         and count(*) filter (where l.cost_aed is not null) > 0
         and count(*) filter (where l.confidence is not null) > 0) z)`;
  await req(S, 's25-quality-latency-cost', 'Models are compared on quality, latency and cost',
    `select coalesce(${AXES} >= 2 and ${RAN('fn_model_benchmark|model_benchmark', 3)}
       and ${DELIVERED('model_used|model_mix|latency_ms|benchmark', 'ai_cost_log')}, false)`,
    `select ${AXES}||' model(s) carry all three axes (latency, cost, quality) in 30d out of '
       ||(select count(distinct model_used) from public.ai_cost_log where occurred_at > now() - interval '30 days')
       ||' routed; model_outcome holds '||(select count(*) from public.model_outcome)
       ||' benchmark row(s); benchmark cron last ok '||${LAST_OK('fn_model_benchmark|model_benchmark')}||'; '
       ||${DELIVERED_EV('model_used|model_mix|latency_ms|benchmark', 'ai_cost_log')}`);

  // ============================================================================================
  // SECTION 26 — AUTONOMOUS PROCUREMENT
  // ============================================================================================
  // "Identify missing suppliers." The conditional is deliberate and is not an excuse flag: when the
  // scan finds no gap there is nothing to act on, so the delivery clause binds only when a gap
  // exists. It cannot be satisfied by setting a column, because the antecedent is the measured gap.
  const SH_LAST = `(select s.metrics from public.supply_health_snapshots s order by s.period_end desc, s.id desc limit 1)`;
  const SH_FRESH = `(select max(period_end) from public.supply_health_snapshots) >= current_date - 2`;
  // ->>'coverage_gaps' then ::numeric assumed the key holds a SCALAR. On production it holds an
  // ARRAY, so the cast raised 22P02 and the check ERRORED — an unmeasured requirement reported with
  // no verdict at all, which is worse than either answer. Both shapes are handled and anything else
  // counts as zero gaps rather than throwing, because a snapshot with an unexpected shape is a
  // snapshot this check cannot read, not a supply crisis.
  const SH_GAP = `(case jsonb_typeof(${SH_LAST} -> 'coverage_gaps')
        when 'array'  then jsonb_array_length(${SH_LAST} -> 'coverage_gaps')::numeric
        when 'number' then (${SH_LAST} ->> 'coverage_gaps')::numeric
        else 0 end)`;
  const GAP_ACTED = `(${SH_GAP} = 0 or exists (select 1 from public.agent_actions a
      where a.kind in ('coverage_gap','supply_gap','sla_no_supply')
        and a.created_at > now() - interval '7 days'))`;
  await req(S, 's26-missing-suppliers', 'The AI identifies missing suppliers',
    `select coalesce(${RAN('fn_supply_gap_scan|supply_gap_scan|fn_supply_health', 2)} and ${SH_FRESH}
       and (${SH_LAST}) ? 'coverage_gaps' and (${SH_LAST}) ? 'no_supply' and ${GAP_ACTED}
       and ${DELIVERED('coverage_gaps|no_supply|supply_gap', 'supply_health_snapshots')}, false)`,
    `select 'latest supply snapshot '||coalesce((select max(period_end)::text from public.supply_health_snapshots),'never')
       ||' with coverage_gaps='||${SH_GAP}||' and no_supply='
       ||coalesce((${SH_LAST} ->> 'no_supply'),'(absent)')||'; '
       ||(select count(*) from public.agent_actions where kind in ('coverage_gap','supply_gap','sla_no_supply')
           and created_at > now() - interval '7 days')||' gap action(s)/7d; scan cron last ok '
       ||${LAST_OK('fn_supply_gap_scan|supply_gap_scan|fn_supply_health')}||'; '
       ||${DELIVERED_EV('coverage_gaps|no_supply|supply_gap', 'supply_health_snapshots')}`);

  // "Discover new suppliers" is a live pipeline claim, so both ends are windowed: a scrape that ran
  // and leads that arrived. A scraper that last ran in June discovers nothing today.
  await req(S, 's26-discover-suppliers', 'The AI discovers new suppliers',
    `select coalesce((select count(*) from public.scrape_runs where created_at > now() - interval '30 days') > 0
       and (select count(*) from public.leads where created_at > now() - interval '30 days') > 0, false)`,
    `select (select count(*) from public.scrape_runs where created_at > now() - interval '30 days')
       ||' scrape run(s)/30d (last ever '||coalesce((select max(created_at)::date::text from public.scrape_runs),'never')
       ||'), '||(select count(*) from public.leads where created_at > now() - interval '30 days')
       ||' new lead(s)/30d against '||(select count(*) from public.leads)||' total and '
       ||(select count(*) from public.yello_staging)||' staged discovery row(s)'`);

  await req(S, 's26-compare-capabilities', 'The AI compares supplier capabilities',
    `select coalesce((select count(*) from public.supplier_capabilities) > 0
       and (select count(*) from public.supplier_capabilities
             where coalesce(extracted_at, updated_at) > now() - interval '180 days') > 0
       and ${UI_READS(C, 'supplier_capabilities')} > 0, false)`,
    `select (select count(*) from public.supplier_capabilities)||' capability record(s) against '
       ||(select count(*) from public.leads where approval_status = 'approved')||' approved supplier(s), '
       ||(select count(*) from public.supplier_capabilities where coalesce(extracted_at, updated_at) > now() - interval '180 days')
       ||' extracted in 180d; '||(select count(*) from public.supplier_opportunity_score)
       ||' comparison score(s) on file; reachable reader(s): '||${UI_READ_NAMES(C, 'supplier_capabilities')}`);

  // "Verify supplier documentation" — a per-row universal over the documents actually received in
  // the window, because a verification rate of 44% is what "verifies documentation" is being asked
  // about, and a global count above zero would report it as done.
  const DOC_WIN = `created_at > now() - interval '90 days'`;
  const DOC_N = `(select count(*) from public.documents where ${DOC_WIN})`;
  const DOC_UNVERIFIED = `(select count(*) from public.documents where ${DOC_WIN} and extracted is null)`;
  await req(S, 's26-verify-documentation', 'The AI verifies supplier documentation',
    `select coalesce(${RAN('fn_doc_expiry_scan|doc_expiry', 2)} and ${DOC_N} > 0 and ${DOC_UNVERIFIED} = 0, false)`,
    `select (${DOC_N} - ${DOC_UNVERIFIED})||' of '||${DOC_N}||' document(s)/90d have been read and verified ('
       ||(select count(*) from public.documents where extracted is not null)||' of '
       ||(select count(*) from public.documents)||' ever), newest '
       ||coalesce((select max(created_at)::date::text from public.documents),'never')
       ||'; expiry scan last ok '||${LAST_OK('fn_doc_expiry_scan|doc_expiry')}`);

  await req(S, 's26-negotiate-limits', 'The AI negotiates within defined limits',
    `select coalesce((select count(*) from public.supplier_negotiation_policy) > 0
       and ${ALL_READS('supplier_negotiation_policy')} > 1
       and (select count(*) from public.employee_authority where threshold_aed is not null) > 0, false)`,
    `select (select count(*) from public.supplier_negotiation_policy)||' negotiation policy row(s) with '
       ||${ALL_READS('supplier_negotiation_policy')}||' routine(s)/view(s) naming the table and '
       ||${UI_READS(C, 'supplier_negotiation_policy')}||' reachable; the spend limit source holds '
       ||(select count(*) from public.employee_authority where threshold_aed is not null)||' threshold(s)'`);

  // "Recommend which suppliers to onboard." invite_schedule.planned is the excuse flag this brief
  // warns about — a number a person can raise without an invitation existing — so the check scores
  // `sent`, the event, and never `planned`, the intention.
  await req(S, 's26-recommend-onboarding', 'The AI recommends which suppliers to onboard',
    `select coalesce(${RAN('enqueue_supplier_invites|supplier_invites|fn_invite', 2)}
       and (select coalesce(sum(sent),0) from public.invite_schedule
             where day > current_date - 7) > 0
       and ${DELIVERED('invite_schedule|invite_funnel|onboard', 'invite_schedule')}, false)`,
    `select coalesce((select sum(sent) from public.invite_schedule where day > current_date - 7),0)
       ||' invitation(s) sent in 7d against '
       ||coalesce((select sum(planned) from public.invite_schedule where day > current_date - 7),0)
       ||' planned; newest schedule row '||coalesce((select max(day)::text from public.invite_schedule),'never')
       ||'; invite cron last ok '||${LAST_OK('enqueue_supplier_invites|supplier_invites|fn_invite')}||'; '
       ||${DELIVERED_EV('invite_schedule|invite_funnel|onboard', 'invite_schedule')}`);

  // ============================================================================================
  // SECTION 27 — KNOWLEDGE CONFIDENCE LAYER
  // ============================================================================================
  // "EVERY piece of knowledge carries" the seven fields. A field is covered only when a column
  // matching it exists AND no row leaves it null — production carries confidence on 1,786 of 1,936
  // agent_knowledge rows, which is a column that exists and a requirement that is not met.
  const KFIELDS = [
    ['confidence', 'confidence|certainty'],
    ['source', 'source|citation|provenance'],
    ['last validation', 'validat|verified_at|checked_at|last_reviewed'],
    ['owner', 'owner'],
    ['expiry', 'expir|valid_until|\\yttl\\y|sunset'],
    ['review date', 'review'],
    ['supporting evidence', 'evidence|proof|support'],
  ];
  // THE kb_chunks HALF OF THE EVIDENCE TIMED OUT, EVERY RUN (3 Sep 2026). kb_chunks is 2.69M rows
  // and 6.9 GB; FIELD_COVERED evaluates to_jsonb(r)->>column on every row for every matching
  // column, which is a serialisation of the whole table per field. The verdict is over
  // agent_knowledge (2k rows) and was never the problem; the evidence string carried the timeout
  // and reported ERROR for a requirement that had a verdict. Same regexes, one column at a time:
  // for each named field, the columns of kb_chunks whose NAME matches are listed from the
  // catalogue, and each is asked ONE question under an 8-second cap — is there a row where it is
  // null? A null found refutes the universal; a scan that completes without one proves it; a scan
  // the cap stops is reported as unmeasured, by field, rather than as a verdict.
  const kbRows = Number(await one(`select count(*) from public.kb_chunks`)) || 0;
  const kbCols = String(await one(`select coalesce(string_agg(k.column_name, ','), '') from information_schema.columns k
      where k.table_schema='public' and k.table_name='kb_chunks'`) || '').split(',').filter(safeToken);
  const kbState = [];
  for (const [lbl, rx] of KFIELDS) {
    const cols = kbCols.filter(c => new RegExp(rx.replace(/\\y/g, '\\b'), 'i').test(c));
    if (!cols.length) { kbState.push(`${lbl}: no column`); continue; }
    let verdict = 'null found';
    for (const c of cols) {
      try {
        const hasNull = String(await one(`set local statement_timeout = '8000';
          select exists (select 1 from public.kb_chunks where "${c}" is null)`)) === 'true';
        if (!hasNull) { verdict = `covered by ${c}`; break; }
      } catch { verdict = `unmeasured (${c} scan exceeded 8s)`; }
    }
    kbState.push(`${lbl}: ${verdict}`);
  }
  const kbCovered = kbState.filter(s => / covered by /.test(s)).length;
  await req(S, 's27-knowledge-seven-fields', 'Every piece of knowledge carries all seven metadata fields',
    `select coalesce(${FIELD_COVERED('agent_knowledge', KFIELDS)} = ${KFIELDS.length}, false)`,
    `select ${FIELD_COVERED('agent_knowledge', KFIELDS)}||' of ${KFIELDS.length} metadata field(s) present on EVERY one of '
       ||(select count(*) from public.agent_knowledge)||' agent_knowledge row(s); missing or partial: '
       ||${FIELD_UNCOVERED('agent_knowledge', KFIELDS)}
       ||${rq(`; on kb_chunks (${kbRows} rows, probed per column under an 8s cap) that is ${kbCovered} of ${KFIELDS.length}: ${kbState.join('; ')}`)}`);

  // "An employee is warned BEFORE relying on stale knowledge." The warning has to be attached to
  // what the employee receives, so the second leg reads fn_agent_context's actual output rather than
  // a column. Vacuous while nothing is stale, which is correct: there is nothing to warn about.
  const KB_STALE = `(select count(*) from public.agent_knowledge where review_due < now())`;
  const KB_WARNS = `(coalesce((select pg_get_functiondef(p.oid) ~* '\\y(review_due|stale|expired)\\y'
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.prokind in ('f','p') and p.proname='fn_kb_retrieve' limit 1), false)
      or (select public.fn_agent_context('cfo', 22000)) ~* '\\y(stale|out of date|review due|expired)\\y')`;
  await req(S, 's27-stale-warning', 'An employee is warned before relying on stale knowledge',
    `select coalesce(${RAN('fn_knowledge_decay|knowledge_decay', 2)} and (${KB_STALE} = 0 or ${KB_WARNS}), false)`,
    `select ${KB_STALE}||' knowledge item(s) past review_due of '
       ||(select count(*) from public.agent_knowledge where review_due is not null)||' dated and '
       ||(select count(*) from public.agent_knowledge)||' total; the retrieval path attaches a staleness '
       ||'warning: '||(${KB_WARNS})::text||'; decay cron last ok '||${LAST_OK('fn_knowledge_decay|knowledge_decay')}`);

  // ============================================================================================
  // SECTION 28 — STRATEGIC MEMORY
  // ============================================================================================
  // "Remember decisions and what they CAUSED." The consequence is the requirement, so the check is a
  // per-row universal on the outcome half: an outcome whose measurement date has passed and which
  // was never observed recorded a decision and forgot its effect.
  const IM_WIN = `occurred_at > now() - interval '30 days'`;
  const IM_N = `(select count(*) from public.institutional_memory where ${IM_WIN})`;
  const IM_NO_OUTCOME = `(select count(*) from public.institutional_memory
      where ${IM_WIN} and coalesce(btrim(outcome), '') = '' and coalesce(btrim(detail), '') = '')`;
  const OC_OVERDUE = `(select count(*) from public.outcome_record
      where due_at < now() - interval '1 day' and observed_at is null)`;
  await req(S, 's28-decisions-with-outcomes', 'The company remembers decisions and what they caused',
    `select coalesce(${IM_N} > 0 and ${IM_NO_OUTCOME} = 0 and ${OC_OVERDUE} = 0
       and ${DELIVERED('institutional_memory|outcome_record|lesson', 'institutional_memory')}, false)`,
    `select ${IM_N}||' institutional memor(ies)/30d of which '||${IM_NO_OUTCOME}
       ||' record no consequence; outcome_record holds '||(select count(*) from public.outcome_record)
       ||' open outcome(s), '||(select count(*) from public.outcome_record where observed_at is not null)
       ||' observed, '||(select count(*) from public.outcome_record where closed_at is not null)||' closed, '
       ||${OC_OVERDUE}||' past their measurement date and never observed; '
       ||${DELIVERED_EV('institutional_memory|outcome_record|lesson', 'institutional_memory')}`);

  // "The company never unknowingly repeats a failed strategy" — the memory must be consulted at the
  // moment of the decision, not merely appended to. A gate that has never run is not a gate either,
  // so the verdict ledger is asserted alongside the body.
  const MEM_CONSULTED = `(select count(distinct p.proname) from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.prokind in ('f','p')
         and p.proname in ('fn_decide','fn_decision_gate','fn_check_spend','fn_task_approve','fn_should_escalate')
         and pg_get_functiondef(p.oid) ~* '\\y(institutional_memory|outcome_record|org_memory)\\y')`;
  await req(S, 's28-blocks-repeat-failures', 'A failed strategy is checked for before a decision',
    `select coalesce(${MEM_CONSULTED} > 0
       and (select count(*) from public.decision_log
             where kind='action_gate' and created_at > now() - interval '30 days') > 0, false)`,
    `select ${MEM_CONSULTED}||' of 5 decision-path routine(s) consult institutional_memory, outcome_record or '
       ||'org_memory before deciding; the memory holds '||(select count(*) from public.institutional_memory)
       ||' item(s) and '||(select count(*) from public.memory_promotions)||' promotion(s); the gate recorded '
       ||(select count(*) from public.decision_log where kind='action_gate' and created_at > now() - interval '30 days')
       ||' verdict(s)/30d'`);

  // ============================================================================================
  // SECTION 29 — AUTONOMOUS OPPORTUNITY DETECTION
  // ============================================================================================
  const OPP_SRC = `(select (kind||' '||coalesce(title,'')||' '||coalesce(detail,'')) as txt
      from public.opportunity where created_at > now() - interval '90 days')`;
  const OPP_QUESTIONS = [
    ['underserved categories', 'underserved|under_served|coverage.?gap|no.?supply'],
    ['growing industries', 'industr|sector|growing|growth'],
    ['rising keywords', 'keyword|search.?term|query|rising|trend'],
    ['unmet demand by location', 'unmet|location|emirate|city|region|geograph'],
    ['weak competitors', 'competitor|rival|weak'],
  ];
  await req(S, 's29-scan-five-questions', 'The scan covers all five named questions',
    `select coalesce(${RAN('fn_opportunity_scan|opportunity_scan', 2)}
       and ${COVERED(OPP_SRC, OPP_QUESTIONS)} = ${OPP_QUESTIONS.length}, false)`,
    `select ${COVERED(OPP_SRC, OPP_QUESTIONS)}||' of ${OPP_QUESTIONS.length} question class(es) appear among '
       ||(select count(*) from public.opportunity where created_at > now() - interval '90 days')
       ||' opportunit(ies)/90d; missing: '||${UNCOVERED(OPP_SRC, OPP_QUESTIONS)}||'; kinds on file: '
       ||coalesce((select string_agg(distinct kind, ', ') from public.opportunity),'(none)')
       ||'; scan cron last ok '||${LAST_OK('fn_opportunity_scan|opportunity_scan')}`);

  // Auto-creation has two halves the daily cron can pass separately: it succeeds every morning and
  // has produced nothing since 28 July. A cron that runs and writes nothing, read by nobody, is a
  // stall that is invisible from both ends, so both ends are asserted.
  const OPP_NEW = `(select count(*) from public.opportunity where created_at > now() - interval '14 days')`;
  const OPP_UNATTRIBUTED = `(select count(*) from public.opportunity
      where created_at > now() - interval '90 days' and coalesce(btrim(detected_by),'') = '')`;
  await req(S, 's29-opportunities-auto-created', 'Opportunities are created automatically and reach the founder',
    `select coalesce(${RAN('fn_opportunity_scan|opportunity_scan', 2)} and ${OPP_NEW} > 0
       and ${OPP_UNATTRIBUTED} = 0
       and ${DELIVERED('opportunit', 'opportunity')}, false)`,
    `select ${OPP_NEW}||' opportunit(ies) detected in 14d, '||(select count(*) from public.opportunity)
       ||' on file (newest '||coalesce((select max(created_at)::date::text from public.opportunity),'never')
       ||', '||(select count(*) from public.opportunity where status='open')||' still open), '
       ||${OPP_UNATTRIBUTED}||' with no detector named; '||${DELIVERED_EV('opportunit', 'opportunity')}`);

  // ============================================================================================
  // SECTION 30 — MARKETPLACE HEALTH INDEX
  // ============================================================================================
  const IDX_FRESH = (idx) => `(select max(measured_on) from public.company_index where index_name=${rq(idx)})
      >= current_date - 1`;
  const IDX_ROW = (idx) => `(select to_jsonb(c) from public.company_index c
      where c.index_name=${rq(idx)} order by c.measured_on desc, c.id desc limit 1)`;
  await req(S, 's30-marketplace-single-score', 'Marketplace health is one score the founder can see',
    `select coalesce(${IDX_FRESH('marketplace_health')}
       and (${IDX_ROW('marketplace_health')} ->> 'score') is not null
       and (${IDX_ROW('marketplace_health')} ->> 'band') is not null
       and ${DELIVERED('marketplace[_ ]health', 'company_index')}, false)`,
    `select 'marketplace_health = '||coalesce((${IDX_ROW('marketplace_health')} ->> 'score'),'(null)')
       ||' band '||coalesce((${IDX_ROW('marketplace_health')} ->> 'band'),'(null)')||' measured '
       ||coalesce((select max(measured_on)::text from public.company_index where index_name='marketplace_health'),'never')
       ||'; '||${DELIVERED_EV('marketplace[_ ]health', 'company_index')}`);

  const MH_INPUTS = [
    ['supplier quality', 'supplier'],
    ['customer satisfaction', 'satisf|\\ynps\\y|csat|customer'],
    ['quote speed', 'quote|speed|hours'],
    ['RFQ completion', 'rfq|complet|fill'],
    ['revenue', 'revenue|gmv|sales'],
    ['fraud', 'fraud'],
    ['churn', 'churn|retention|lapsed'],
    ['AI confidence', '\\yai\\y|confidence'],
  ];
  await req(S, 's30-marketplace-eight-inputs', 'The marketplace score is built from all eight inputs',
    `select coalesce(${COVERED(DIM_SRC('marketplace_health'), MH_INPUTS)} = ${MH_INPUTS.length}
       and ${IDX_FRESH('marketplace_health')}, false)`,
    `select ${COVERED(DIM_SRC('marketplace_health'), MH_INPUTS)}||' of ${MH_INPUTS.length} named input(s) carry a '
       ||'non-null value in the newest marketplace_health row; missing: '
       ||${UNCOVERED(DIM_SRC('marketplace_health'), MH_INPUTS)}||'; dimensions present: '
       ||coalesce((select string_agg(e.key, ', ' order by e.key) from jsonb_each(${DIMS('marketplace_health')}) e),'(none)')
       ||'; the supply snapshot beside it carries '
       ||coalesce((select string_agg(k, ', ') from jsonb_object_keys(${SH_LAST}) k),'(none)')`);

  // ============================================================================================
  // SECTION 31 — ORGANIZATIONAL ENERGY
  // ============================================================================================
  const OE_MEASURES = [
    ['decision velocity', 'decision|velocity'],
    ['backlog growth', 'backlog'],
    ['collaboration efficiency', 'collab'],
    ['knowledge creation', 'knowledge'],
    ['automation rate', 'automat'],
  ];
  await req(S, 's31-energy-five-measures', 'Organizational energy is built from all five measures',
    `select coalesce(${COVERED(DIM_SRC('organizational_energy'), OE_MEASURES)} = ${OE_MEASURES.length}
       and ${IDX_FRESH('organizational_energy')}, false)`,
    `select ${COVERED(DIM_SRC('organizational_energy'), OE_MEASURES)}||' of ${OE_MEASURES.length} named measure(s) carry a '
       ||'non-null value; missing: '||${UNCOVERED(DIM_SRC('organizational_energy'), OE_MEASURES)}
       ||'; score '||coalesce((${IDX_ROW('organizational_energy')} ->> 'score'),'(null)')||' band '
       ||coalesce((${IDX_ROW('organizational_energy')} ->> 'band'),'(null)')||' measured '
       ||coalesce((select max(measured_on)::text from public.company_index where index_name='organizational_energy'),'never')`);

  // "If momentum slows, the cause is investigated." A per-fall universal: every index that lost more
  // than a point since its previous measurement in the last week must have an artefact dated after
  // that measurement naming it. position() takes the index_name as a literal needle — every one of
  // them contains an underscore, and on the pattern side of LIKE that is a wildcard that could only
  // ever manufacture a match.
  const FALLS = `(select z.index_name, z.measured_on from (
      select c.index_name, c.measured_on, c.score,
             lag(c.score) over (partition by c.index_name order by c.measured_on) prev
        from public.company_index c where c.measured_on > current_date - 30) z
     where z.prev is not null and z.score < z.prev - 1 and z.measured_on > current_date - 7)`;
  const UNINVESTIGATED = `(select count(*) from ${FALLS} f
      where not exists (select 1 from public.founder_alerts a where a.created_at::date >= f.measured_on
                         and position(f.index_name in coalesce(a.event,'')||' '||coalesce(a.detail::text,'')) > 0)
        and not exists (select 1 from public.evolution_proposal p where p.created_at::date >= f.measured_on
                         and position(f.index_name in coalesce(p.subject,'')||' '||coalesce(p.observation,'')) > 0)
        and not exists (select 1 from public.agent_actions g where g.created_at::date >= f.measured_on
                         and position(f.index_name in coalesce(g.title,'')||' '||coalesce(g.detail::text,'')) > 0))`;
  const INDEX_WATCHER = `(select count(distinct p.proname) from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_company_indices'
         and pg_get_functiondef(p.oid) ~* '\\ycompany_index\\y'
         and pg_get_functiondef(p.oid) ~* '\\y(founder_alerts|evolution_proposal|agent_actions)\\y')`;
  await req(S, 's31-slowdown-investigated', 'A fall in momentum is investigated',
    `select coalesce(${INDEX_WATCHER} > 0 and ${UNINVESTIGATED} = 0, false)`,
    `select (select count(*) from ${FALLS} f2)||' index fall(s) over 1 point in 7d, of which '
       ||${UNINVESTIGATED}||' produced no alert, proposal or action afterwards; '
       ||${INDEX_WATCHER}||' routine(s) other than the writer read company_index and raise something; '
       ||'company_index has '||${ALL_READS('company_index')}||' namer(s) in total and '
       ||${UI_READS(C, 'company_index')}||' reachable'`);

  // ============================================================================================
  // SECTION 32 — AI REPUTATION SYSTEM
  // ============================================================================================
  // Six named axes, each requiring a column that is non-null for EVERY graded employee, plus the
  // coverage question the column check cannot answer: an active employee with no reputation row has
  // earned no reputation at all.
  const REP_AXES = [
    ['correctness', 'correct|accura'],
    ['decision quality', 'decision|judg|quality'],
    ['learning speed', 'learn'],
    ['cost efficiency', 'cost'],
    ['collaboration', 'collab'],
    ['reliability', 'reliab|uptime|depend'],
  ];
  const REP_UNGRADED = `(select count(*) from public.org_agents a where a.active
      and not exists (select 1 from public.agent_reputation r where r.agent_key = a.agent_key))`;
  await req(S, 's32-reputation-six-dimensions', 'Every AI employee earns reputation on all six dimensions',
    `select coalesce(${FIELD_COVERED('agent_reputation', REP_AXES)} = ${REP_AXES.length}
       and ${REP_UNGRADED} = 0
       and (select max(computed_at) from public.agent_reputation) > now() - interval '14 days'
       and ${DELIVERED('reputation|\\mtier\\M', 'agent_reputation')}, false)`,
    `select ${FIELD_COVERED('agent_reputation', REP_AXES)}||' of ${REP_AXES.length} named dimension(s) scored on EVERY one of '
       ||(select count(*) from public.agent_reputation)||' graded employee(s); missing: '
       ||${FIELD_UNCOVERED('agent_reputation', REP_AXES)}||'; '||${REP_UNGRADED}||' of '
       ||(select count(*) from public.org_agents where active)||' active employee(s) have no reputation row; '
       ||'computed '||coalesce((select max(computed_at)::timestamp(0)::text from public.agent_reputation),'never')
       ||'; '||${DELIVERED_EV('reputation|\\mtier\\M', 'agent_reputation')}`);

  // "Higher reputation increases autonomous authority." The authority path is named explicitly, and
  // the reputation table has to appear inside one of those routines — a score nothing consults
  // changes no one's authority however carefully it is computed.
  const REP_IN_AUTHORITY = `(select count(distinct p.proname) from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.prokind in ('f','p')
         and p.proname in ('fn_decide','fn_decision_gate','fn_check_spend','fn_task_approve','fn_dept_authority')
         and pg_get_functiondef(p.oid) ~* '\\yagent_reputation\\y')`;
  await req(S, 's32-reputation-drives-authority', 'Reputation changes an employee autonomous authority',
    `select coalesce(${REP_IN_AUTHORITY} > 0
       and (select max(computed_at) from public.agent_reputation) > now() - interval '14 days'
       and (select count(*) from public.decision_log
             where kind='action_gate' and created_at > now() - interval '30 days') > 0, false)`,
    `select ${REP_IN_AUTHORITY}||' of 5 authority routine(s) consult agent_reputation; '
       ||(select count(*) from public.agent_reputation where tier='probation')||' employee(s) on probation and '
       ||(select count(*) from public.agent_reputation where tier <> 'probation')||' above it, against '
       ||(select count(*) from public.employee_authority)||' authority row(s); the gate recorded '
       ||(select count(*) from public.decision_log where kind='action_gate' and created_at > now() - interval '30 days')
       ||' verdict(s)/30d; agent_reputation namers: '||${ALL_READS('agent_reputation')}`);

  // ============================================================================================
  // SECTION 33 — EXECUTIVE REPLAY
  // ============================================================================================
  // "ANY past day can be replayed" is a universal over days, so it is scored per day rather than by
  // the row count: nine snapshots prove nine days, not any day.
  const SNAP_MISSING = `(select count(*) from generate_series(current_date - 7, current_date - 1, interval '1 day') g
      where not exists (select 1 from public.company_snapshot s where s.snapshot_on = g::date))`;
  await req(S, 's33-replay-any-day', 'Any past day can be replayed',
    `select coalesce(${SNAP_MISSING} = 0
       and ${DELIVERED('company_snapshot|snapshot_on|replay', 'company_snapshot')}, false)`,
    `select (7 - ${SNAP_MISSING})||' of the last 7 day(s) have a company_snapshot ('
       ||(select count(*) from public.company_snapshot)||' on file, newest '
       ||coalesce((select max(snapshot_on)::text from public.company_snapshot),'never')||'); '
       ||${DELIVERED_EV('company_snapshot|snapshot_on|replay', 'company_snapshot')}`);

  // The six tracks, each scored on the same day, plus the question that decides whether it is a
  // REPLAY rather than six separate tables: one reachable routine that spans all six and takes a day.
  const DAY = `(select coalesce(max(snapshot_on), current_date - 1) from public.company_snapshot)`;
  const TRACKS = `(select count(*) from (values
      ('decisions',     exists (select 1 from public.decision_log      where created_at::date = ${DAY})),
      ('conversations', exists (select 1 from public.agent_chats       where created_at::date = ${DAY})),
      ('approvals',     exists (select 1 from public.agent_actions     where coalesce(decided_at, created_at)::date = ${DAY})),
      ('workflows',     exists (select 1 from public.workflow_step_run where coalesce(started_at, finished_at)::date = ${DAY})),
      ('KPIs',          exists (select 1 from public.metric_snapshot   where taken_at::date = ${DAY})),
      ('outcomes',      exists (select 1 from public.outcome_record    where coalesce(observed_at, created_at)::date = ${DAY}))
     ) t(lbl, ok) where t.ok)`;
  const TRACKS_MISSING = `coalesce((select string_agg(t.lbl, ', ') from (values
      ('decisions',     exists (select 1 from public.decision_log      where created_at::date = ${DAY})),
      ('conversations', exists (select 1 from public.agent_chats       where created_at::date = ${DAY})),
      ('approvals',     exists (select 1 from public.agent_actions     where coalesce(decided_at, created_at)::date = ${DAY})),
      ('workflows',     exists (select 1 from public.workflow_step_run where coalesce(started_at, finished_at)::date = ${DAY})),
      ('KPIs',          exists (select 1 from public.metric_snapshot   where taken_at::date = ${DAY})),
      ('outcomes',      exists (select 1 from public.outcome_record    where coalesce(observed_at, created_at)::date = ${DAY}))
     ) t(lbl, ok) where not t.ok), 'none')`;
  const SPANNER = `(select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.prokind in ('f','p') and p.proname = any(${C.UI})
        and pg_get_functiondef(p.oid) ~* '\\ydecision_log\\y'
        and pg_get_functiondef(p.oid) ~* '\\yagent_chats\\y'
        and pg_get_functiondef(p.oid) ~* '\\yagent_actions\\y'
        and pg_get_functiondef(p.oid) ~* '\\yworkflow_step_run\\y'
        and pg_get_functiondef(p.oid) ~* '\\ymetric_snapshot\\y'
        and pg_get_functiondef(p.oid) ~* '\\youtcome_record\\y')`;
  await req(S, 's33-replay-six-tracks', 'The replay shows all six tracks for a chosen day',
    `select coalesce(${TRACKS} = 6 and ${SPANNER} > 0, false)`,
    `select ${TRACKS}||' of 6 track(s) have rows on '||${DAY}||' (missing: '||${TRACKS_MISSING}
       ||'); '||${SPANNER}||' reachable routine(s) span all six tables at once'`);

  // ============================================================================================
  // SECTION 34 — ORGANIZATIONAL STRESS TESTING
  // ============================================================================================
  const SCEN_SRC = `(select (scenario_key||' '||coalesce(name,'')||' '||coalesce(category,'')||' '
        ||coalesce(situation,'')||' '||coalesce(expected_behaviour,'')) as txt
      from public.scenario_library where last_run > now() - interval '180 days')`;
  const SCENARIOS = [
    ['OpenRouter outage', 'openrouter|model provider|llm.{0,20}(outage|down|unavailab)|ai provider'],
    ['Supabase outage', 'supabase|database.{0,20}(outage|down|unavailab)|platform outage'],
    ['supplier fraud spike', 'fraud'],
    ['cyberattack', 'cyber|attack|breach|intrusion|ransom'],
    ['cash-flow reduction', 'cash.?flow|liquidity|runway|cash.{0,12}(dr[o]p|reduc|short|dip)'],
    ['campaign failure', '(campaign|marketing).{0,30}(fail|underperform|flop|no return)'],
  ];
  await req(S, 's34-stress-six-scenarios', 'All six named failure scenarios can be simulated',
    `select coalesce(${COVERED(SCEN_SRC, SCENARIOS)} = ${SCENARIOS.length}, false)`,
    `select ${COVERED(SCEN_SRC, SCENARIOS)}||' of ${SCENARIOS.length} named scenario(s) exist and were exercised in 180d; missing: '
       ||${UNCOVERED(SCEN_SRC, SCENARIOS)}||'; the library holds '||(select count(*) from public.scenario_library)
       ||' scenario(s) in categor(ies) '
       ||coalesce((select string_agg(distinct category, ', ') from public.scenario_library),'(none)')
       ||', newest run '||coalesce((select max(last_run)::date::text from public.scenario_library),'never')`);

  // "Resilience is measured BEFORE real incidents occur" — a per-capability universal. A capability
  // whose last_verdict is null was never tested, and sixteen of sixteen in that state is the
  // measurement this requirement exists to take.
  const CAP_UNTESTED = `(select count(*) from public.critical_capability
      where last_verdict is null or last_checked is null or last_checked < now() - interval '30 days')`;
  await req(S, 's34-resilience-measured', 'Resilience is measured before incidents and is visible',
    `select coalesce(${CAP_UNTESTED} = 0 and ${RAN('dr_drill|fn_dr_drill', 40)}
       and ${DELIVERED('resilien|continuity_plan|critical_capability', 'critical_capability')}, false)`,
    `select ((select count(*) from public.critical_capability) - ${CAP_UNTESTED})||' of '
       ||(select count(*) from public.critical_capability)||' critical capabilit(ies) carry a verdict from the '
       ||'last 30 days; continuity_plan holds '||(select count(*) from public.continuity_plan)||' service(s), '
       ||(select count(*) from public.continuity_plan where last_tested > now() - interval '90 days')
       ||' tested in 90d; dr drill last ok '||${LAST_OK('dr_drill|fn_dr_drill')}||'; '
       ||${DELIVERED_EV('resilien|continuity_plan|critical_capability', 'critical_capability')}`);

  // ============================================================================================
  // SECTION 35 — AUTONOMOUS HIRING & RESTRUCTURING
  // ============================================================================================
  const EVO_SRC = `(select (coalesce(trigger_kind,'')||' '||coalesce(change_class,'')||' '||coalesce(subject,'')
        ||' '||coalesce(observation,'')||' '||coalesce(proposal,'')) as txt
      from public.evolution_proposal where created_at > now() - interval '180 days')`;
  const EVO_QUESTIONS = [
    ['a new specialist is needed', 'new .{0,12}(specialist|role|agent|employee|hire)|hire|recruit|staff up'],
    ['should two roles merge', 'merge|combine|consolidat'],
    ['is one role overloaded', 'overload|saturat|too many|backlog per|beyond capacity'],
    ['is another role idle', 'idle|under.?util|unused|no work|dormant'],
  ];
  await req(S, 's35-restructure-four-questions', 'The Evolution OS asks all four structural questions',
    `select coalesce(${RAN('fn_evolution_scan|evolution_scan', 14)}
       and ${COVERED(EVO_SRC, EVO_QUESTIONS)} = ${EVO_QUESTIONS.length}, false)`,
    `select ${COVERED(EVO_SRC, EVO_QUESTIONS)}||' of ${EVO_QUESTIONS.length} structural question(s) appear among '
       ||(select count(*) from public.evolution_proposal where created_at > now() - interval '180 days')
       ||' proposal(s)/180d; missing: '||${UNCOVERED(EVO_SRC, EVO_QUESTIONS)}||'; trigger kinds on file: '
       ||coalesce((select string_agg(distinct trigger_kind, ', ') from public.evolution_proposal),'(none)')
       ||'; change classes: '
       ||coalesce((select string_agg(distinct change_class, ', ') from public.evolution_proposal),'(none)')
       ||'; scan cron last ok '||${LAST_OK('fn_evolution_scan|evolution_scan')}`);

  const EVO_WIN = `created_at > now() - interval '180 days'`;
  const EVO_N = `(select count(*) from public.evolution_proposal where ${EVO_WIN})`;
  const EVO_UNEVIDENCED = `(select count(*) from public.evolution_proposal
      where ${EVO_WIN} and (coalesce(btrim(evidence::text),'') in ('','null','{}','[]')
                         or coalesce(btrim(observation),'') = ''))`;
  await req(S, 's35-proposals-evidence-backed', 'Every structural proposal is backed by evidence and is seen',
    `select coalesce(${EVO_N} > 0 and ${EVO_UNEVIDENCED} = 0
       and ${DELIVERED('evolution_proposal|change_class|restructur', 'evolution_proposal')}, false)`,
    `select (${EVO_N} - ${EVO_UNEVIDENCED})||' of '||${EVO_N}||' proposal(s)/180d carry both evidence and an '
       ||'observation; '||(select count(*) from public.evolution_proposal where status='proposed')||' of '
       ||(select count(*) from public.evolution_proposal)||' are still awaiting a decision and '
       ||(select count(*) from public.evolution_proposal where decided_by is not null)||' name a decider; '
       ||${DELIVERED_EV('evolution_proposal|change_class|restructur', 'evolution_proposal')}`);

  // ============================================================================================
  // SECTION 36 — EXPLAINABLE AI WORKSPACE
  // ============================================================================================
  // "Every recommendation includes" the seven fields, so the population is the recommendations the
  // founder is actually shown — agent_actions rows carrying a recommendation — and the universal is
  // over that population rather than over the whole table, which would make one historical row
  // permanently unsatisfiable.
  const REC_WIN = `r.created_at > now() - interval '30 days' and coalesce(r.recommendation,'') <> ''`;
  const REC_N = `(select count(*) from public.agent_actions r where ${REC_WIN})`;
  const REC_FIELDS = [
    ['evidence', 'evidence'],
    ['assumptions', 'assumption|premise'],
    ['risks', 'risk'],
    ['alternatives', 'alternativ|option'],
    ['expected impact', 'impact|expected'],
    ['confidence', 'confidence'],
    ['cost', 'cost|\\yaed\\y|price|spend'],
  ];
  await req(S, 's36-recommendation-seven-fields', 'Every rendered recommendation carries all seven fields',
    `select coalesce(${REC_N} > 0
       and ${FIELD_COVERED('agent_actions', REC_FIELDS, REC_WIN)} = ${REC_FIELDS.length}, false)`,
    `select ${FIELD_COVERED('agent_actions', REC_FIELDS, REC_WIN)}||' of ${REC_FIELDS.length} field(s) present on EVERY one of '
       ||${REC_N}||' recommendation(s)/30d; missing or partial: '
       ||${FIELD_UNCOVERED('agent_actions', REC_FIELDS, REC_WIN)}
       ||'; the unread queues hold challenge_record '||(select count(*) from public.challenge_record)
       ||', board_opinion '||(select count(*) from public.board_opinion)
       ||', evolution_proposal '||(select count(*) from public.evolution_proposal)||' row(s)'`);

  // ============================================================================================
  // SECTION 37 — CONTINUOUS BENCHMARKING
  // ============================================================================================
  // A track counts when it is STRUCTURED — a column named for it on either competitor table — or
  // when at least three competitor records describe it and were verified inside 60 days. Three
  // rather than one, because "competitors are tracked on pricing" is a claim about the field and not
  // about a single sentence in a single record.
  const COMP_COLS = (rx) => `exists (select 1 from information_schema.columns k
      where k.table_schema='public' and k.table_name in ('competitor','competitive_position')
        and k.column_name ~* ${rq(rx)})`;
  const COMP_ROWS = (rx) => `(select count(*) from public.competitor c
      where c.verified_at > now() - interval '60 days'
        and (coalesce(c.what_they_do,'')||' '||coalesce(c.business_model,'')||' '||coalesce(c.overlap,'')||' '
             ||coalesce(c.strength,'')||' '||coalesce(c.weakness,'')) ~* ${rq(rx)})`;
  const TRACKS37 = [
    ['pricing', 'pric|\\yfee'],
    ['categories', 'categor|vertical|trade'],
    ['supplier coverage', 'supplier|vendor|coverage|network'],
    ['website changes', 'website|\\ysite\\y|\\yurl\\y|landing|page'],
    ['marketing activity', 'marketing|campaign|\\yads?\\y|\\yseo\\y|social'],
    ['customer reviews', 'review|rating|testimonial|feedback'],
  ];
  const T37_OK = `(select count(*) from (values ${TRACKS37.map(([l, rx]) => `(${rq(l)}, (${COMP_COLS(rx)} or ${COMP_ROWS(rx)} >= 3))`).join(',')}) t(lbl, ok) where t.ok)`;
  const T37_MISSING = `coalesce((select string_agg(t.lbl, ', ') from (values ${TRACKS37.map(([l, rx]) => `(${rq(l)}, (${COMP_COLS(rx)} or ${COMP_ROWS(rx)} >= 3))`).join(',')}) t(lbl, ok) where not t.ok), 'none')`;
  await req(S, 's37-benchmark-six-tracks', 'Competitors are tracked on all six named tracks',
    `select coalesce(${T37_OK} = ${TRACKS37.length}
       and ${DELIVERED('competitor|competitive', 'competitor')}, false)`,
    `select ${T37_OK}||' of ${TRACKS37.length} competitor track(s) are structured or freshly evidenced; missing: '
       ||${T37_MISSING}||'; competitor holds '||(select count(*) from public.competitor)||' record(s), '
       ||(select count(*) from public.competitor where verified_at > now() - interval '60 days')
       ||' verified in 60d (newest '||coalesce((select max(verified_at)::date::text from public.competitor),'never')
       ||'); competitive_position holds '||(select count(*) from public.competitive_position)
       ||' dimension(s) with no timestamp; '||${DELIVERED_EV('competitor|competitive', 'competitor')}`);

  // "A competitive intelligence report is generated monthly" — a report that mentions no competitor
  // is not competitive intelligence, so the body is matched against the competitor roster itself.
  // Each name is a literal needle inside position(); on the pattern side of LIKE a name containing
  // an underscore would match anything.
  const MONTHLY_WITH_COMPETITOR = `(select count(*) from public.board_reports b
      where b.created_at > now() - interval '40 days'
        and exists (select 1 from public.competitor c where coalesce(btrim(c.name),'') <> ''
                     and position(c.name in coalesce(b.body,'')) > 0))`;
  await req(S, 's37-benchmark-monthly-report', 'A monthly competitive intelligence report is produced',
    `select coalesce(${RAN('fn_period_report|monthly_report', 40)} and ${MONTHLY_WITH_COMPETITOR} > 0
       and ${DELIVERED('board_report|report_registry', 'board_reports')}, false)`,
    `select ${MONTHLY_WITH_COMPETITOR}||' of '
       ||(select count(*) from public.board_reports where created_at > now() - interval '40 days')
       ||' report(s)/40d name a competitor from the roster of '||(select count(*) from public.competitor)
       ||'; market_intel holds '||(select count(*) from public.market_intel)||' row(s); monthly cron last ok '
       ||${LAST_OK('fn_period_report|monthly_report')}||'; '
       ||${DELIVERED_EV('board_report|report_registry', 'board_reports')}`);

  // ============================================================================================
  // SECTION 38 — DIGITAL OPERATING MANUAL
  // ============================================================================================
  // Four named categories, each a per-row universal against the manual. A manual documenting 14 of
  // 14 workflows and none of the 15 departments documents the company by a quarter.
  const MANUAL = (where) => `(select count(*) from public.v_operating_manual m where ${where})`;
  const UNDOC = (src, keyExpr) => `(select count(*) from ${src} x
      where not exists (select 1 from public.v_operating_manual m
                         where position(${keyExpr} in coalesce(m.key,'')||' '||coalesce(m.title,'')) > 0)
        and not exists (select 1 from public.os_runbooks b
                         where position(${keyExpr} in coalesce(b.slug,'')||' '||coalesce(b.title,'')) > 0))`;
  const DOC_CATS = `(select count(*) from (values
      ('workflows',     ${UNDOC('public.workflow', 'x.workflow_key')} = 0),
      ('policies',      ${UNDOC('public.governance_policy', 'x.policy')} = 0),
      ('decision rules',${UNDOC('public.decision_policy', 'x.key')} = 0),
      ('departments',   ${UNDOC('(select * from public.org_departments where coalesce(active,true))', 'x.dept_key')} = 0)
     ) t(lbl, ok) where t.ok)`;
  const DOC_CATS_MISSING = `coalesce((select string_agg(t.lbl, ', ') from (values
      ('workflows',     ${UNDOC('public.workflow', 'x.workflow_key')} = 0),
      ('policies',      ${UNDOC('public.governance_policy', 'x.policy')} = 0),
      ('decision rules',${UNDOC('public.decision_policy', 'x.key')} = 0),
      ('departments',   ${UNDOC('(select * from public.org_departments where coalesce(active,true))', 'x.dept_key')} = 0)
     ) t(lbl, ok) where not t.ok), 'none')`;
  await req(S, 's38-manual-self-documenting', 'The manual documents workflows, policies, rules and departments',
    `select coalesce(${DOC_CATS} = 4
       and ${DELIVERED('operating_manual|runbook', 'os_runbooks')}, false)`,
    `select ${DOC_CATS}||' of 4 documented categor(ies); missing: '||${DOC_CATS_MISSING}||'; undocumented rows — '
       ||${UNDOC('public.workflow', 'x.workflow_key')}||' of '||(select count(*) from public.workflow)||' workflow(s), '
       ||${UNDOC('public.governance_policy', 'x.policy')}||' of '||(select count(*) from public.governance_policy)||' polic(ies), '
       ||${UNDOC('public.decision_policy', 'x.key')}||' of '||(select count(*) from public.decision_policy)||' decision rule(s), '
       ||${UNDOC('(select * from public.org_departments where coalesce(active,true))', 'x.dept_key')}||' of '
       ||(select count(*) from public.org_departments where coalesce(active,true))||' department(s); '
       ||'the manual carries '||${MANUAL('true')}||' entr(ies); '||${DELIVERED_EV('operating_manual|runbook', 'os_runbooks')}`);

  // "Always current" is measured as DRIFT in both directions: automation that runs and is not
  // documented, and documentation for automation that no longer exists. One number would hide the
  // other.
  const DRIFT_UNDOC = `(select count(*) from cron.job j where j.active
      and not exists (select 1 from public.cron_registry r where r.jobname = j.jobname))`;
  const DRIFT_GHOST = `(select count(*) from public.cron_registry r
      where not exists (select 1 from cron.job j where j.jobname = r.jobname))`;
  await req(S, 's38-manual-always-current', 'The manual is current with what actually runs',
    `select coalesce(${DRIFT_UNDOC} = 0 and ${DRIFT_GHOST} = 0
       and ${RAN('fn_sop_update|sop_update', 14)}, false)`,
    `select ${DRIFT_UNDOC}||' active cron job(s) are undocumented and '||${DRIFT_GHOST}
       ||' documented job(s) no longer exist, against '||(select count(*) from cron.job where active)
       ||' active job(s) and '||(select count(*) from public.cron_registry)||' registry row(s); '
       ||'runbooks '||(select count(*) from public.os_runbooks)||'; sop cron last ok '
       ||${LAST_OK('fn_sop_update|sop_update')}`);

  // ============================================================================================
  // SECTION 39 — AUTONOMOUS GOVERNANCE
  // ============================================================================================
  // Six monitors, each requiring an ACTIVE cron that has SUCCEEDED inside a fortnight. A view with
  // no schedule behind it monitors nothing, which is the state of the approval trace today.
  // Same wrapper resolution as RAN above: 'regulatory changes' was reported missing while
  // regulation_watch_weekly was active and had succeeded three days earlier, because its jobname
  // matches none of the four alternatives and its command is the kernel wrapper call. The command it
  // runs is `select public.fn_regulation_watch();`, which matches fn_regulation.
  const MONITOR = (rx) => `exists (select 1 from ${CRON_J} join cron.job_run_details d on d.jobid=j.jobid
      where j.active and (${EFF_CMD} ~* ${rq(rx)} or j.jobname ~* ${rq(rx)}) and d.status='succeeded'
        and d.end_time > now() - interval '14 days' and ${NO_TRACED_FAILURE(14)})`;
  const MONITORS = [
    ['policy violations', 'policy_consistency|policy_violation|fn_policy'],
    ['excessive autonomy', 'autonomy_audit|fn_autonomy'],
    ['missing approvals', 'approval_audit|missing_approval|fn_approval|approval_trace'],
    ['conflicting decisions', 'decision_conflict|conflicting_decision|fn_conflict'],
    ['regulatory changes', 'regulation_propagate|fn_regulation|reg_watch|regulatory'],
    ['security exceptions', 'security_selfaudit|fn_security|security_scan'],
  ];
  const MON_OK = `(select count(*) from (values ${MONITORS.map(([l, rx]) => `(${rq(l)}, ${MONITOR(rx)})`).join(',')}) t(lbl, ok) where t.ok)`;
  const MON_MISSING = `coalesce((select string_agg(t.lbl, ', ') from (values ${MONITORS.map(([l, rx]) => `(${rq(l)}, ${MONITOR(rx)})`).join(',')}) t(lbl, ok) where not t.ok), 'none')`;
  await req(S, 's39-governance-six-monitors', 'All six governance monitors run on a live schedule',
    `select coalesce(${MON_OK} = ${MONITORS.length}, false)`,
    `select ${MON_OK}||' of ${MONITORS.length} governance monitor(s) have an active cron that succeeded in 14d; missing: '
       ||${MON_MISSING}||'; the sources hold governance_policy '||(select count(*) from public.governance_policy)
       ||', governance_rule '||(select count(*) from public.governance_rule)
       ||', policy_rules '||(select count(*) from public.policy_rules)
       ||', security_events '||(select count(*) from public.security_events)||' row(s)'`);

  // "It can pause automation when thresholds are exceeded." A guard that only writes a warning row
  // pauses nothing, so the body must be able to stop something — a scheduler change, an autonomy
  // flag, or a halt verdict — and the pause must be auditable and visible.
  // THIS EXPRESSION TIMED OUT ON THE MANAGEMENT API SEVEN TIMES RUNNING (3 Sep 2026) and the
  // requirement had no verdict at all. Its shape was a correlated EXISTS per candidate routine over
  // cron.job_run_details (236k rows, indexed on runid only) joined to every job, with a regex built
  // from the routine name on the join side — twelve full scans of the run log plus the trace table,
  // one per routine that mentions a pause primitive. The fact it measures is small: which routines
  // that CAN stop automation ran successfully on a live schedule in the last two days. So the live
  // set is computed once — one pass over the run log for the jobs that succeeded in the window, one
  // over the trace table for the components that failed — and the routine names are matched against
  // that set. Same predicate, same window, same wrapper-resolved command; 2.9 s measured.
  const PAUSER = `(with ran as (select d.jobid from cron.job_run_details d
                    where d.status='succeeded' and d.end_time > now() - interval '2 days' group by d.jobid),
      failed as (select x.component_id from public.phase_c_system_execution x
                  where x.result='failed' and x.finished_at > now() - interval '2 days' group by x.component_id),
      live as (select ${EFF_CMD} cmd from ${CRON_J} join ran on ran.jobid = j.jobid
                where j.active and not exists (select 1 from failed f where f.component_id = 'cron:'||j.jobname)),
      pausers as (select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                   where n.nspname='public' and p.prokind in ('f','p')
                     and pg_get_functiondef(p.oid) ~* '\\y(cron\\.alter_job|cron\\.unschedule|autonomy_enabled|automation_paused|halt)\\y')
      select count(distinct p.proname) from pausers p join live l on l.cmd ~* ('\\y'||p.proname||'\\y'))`;
  await req(S, 's39-governance-can-pause', 'Governance can pause automation, audibly and visibly',
    `select coalesce(${PAUSER} > 0
       and (select count(*) from public.autonomy_control_audit) > 0
       and ${DELIVERED('autonomy|paused|halt', 'autonomy_control_audit')}, false)`,
    `select ${PAUSER}||' live routine(s) can stop automation (scheduler change, autonomy flag or halt verdict); '
       ||(select count(*) from public.autonomy_control_audit)||' control change(s) recorded, newest '
       ||coalesce((select max(at)::date::text from public.autonomy_control_audit),'never')||'; '
       ||(select count(*) from public.control_mode_action where requires_control)||' of '
       ||(select count(*) from public.control_mode_action)||' action(s) are gated; '
       ||${DELIVERED_EV('autonomy|paused|halt', 'autonomy_control_audit')}`);

  // ============================================================================================
  // SECTION 40 — COMPANY MATURITY INDEX
  // ============================================================================================
  await req(S, 's40-maturity-single-score', 'Company maturity is one score the founder can see',
    `select coalesce(${IDX_FRESH('company_maturity')}
       and (${IDX_ROW('company_maturity')} ->> 'score') is not null
       and (${IDX_ROW('company_maturity')} ->> 'band') is not null
       and ${DELIVERED('maturity', 'company_index')}, false)`,
    `select 'company_maturity = '||coalesce((${IDX_ROW('company_maturity')} ->> 'score'),'(null)')
       ||' band '||coalesce((${IDX_ROW('company_maturity')} ->> 'band'),'(null)')||' measured '
       ||coalesce((select max(measured_on)::text from public.company_index where index_name='company_maturity'),'never')
       ||' by a daily cron that is currently active='
       -- MEASURED, NOT ASSERTED. This read 'by an active daily cron' as a literal, beside a verdict
       -- whose only failing leg was freshness. company_indices_daily has been active=false since the
       -- 16 Aug stand-down, so the evidence stated the premise the predicate was testing.
       ||coalesce((select bool_or(j.active)::text from cron.job j
                    left join public.phase_c_system_execution_wrapper w on w.jobid = j.jobid
                   where coalesce(w.original_command, j.command) ~* '\\yfn_company_indices\\y'), '(no such job)')
       ||'; '||${DELIVERED_EV('maturity', 'company_index')}`);

  const MAT_DIMS = [
    ['automation', 'automat'],
    ['knowledge quality', 'knowledge'],
    ['decision accuracy', 'decision'],
    ['financial health', 'financ|cash|revenue'],
    ['customer trust', 'customer|trust'],
    ['supplier ecosystem', 'supplier|ecosystem'],
    ['security', 'securit'],
    ['operational resilience', 'resilien|operational'],
    ['innovation', 'innovat'],
    ['strategic execution', 'strateg'],
  ];
  await req(S, 's40-maturity-ten-dimensions', 'Maturity is built from all ten named dimensions',
    `select coalesce(${COVERED(DIM_SRC('company_maturity'), MAT_DIMS)} = ${MAT_DIMS.length}
       and ${IDX_FRESH('company_maturity')}, false)`,
    `select ${COVERED(DIM_SRC('company_maturity'), MAT_DIMS)}||' of ${MAT_DIMS.length} named dimension(s) carry a non-null '
       ||'value in the newest company_maturity row; missing: '||${UNCOVERED(DIM_SRC('company_maturity'), MAT_DIMS)}
       ||'; dimensions present: '
       ||coalesce((select string_agg(e.key||'='||(e.value #>> '{}'), ', ' order by e.key)
                    from jsonb_each(${DIMS('company_maturity')}) e),'(none)')`);
}
