// LAYERS 1-8 of OS 2.txt — Executive Lobby, Company Digital Twin, Executive Intelligence, Living
// Organization, Executive Meeting Room, Company Brain, Time Machine, Future Simulator.
//
// 20 requirements. Every one of them is a claim about what the FOUNDER SEES, so no check in this
// file can be satisfied by a table with rows in it. Each has two halves and both are measured:
//
//   DATABASE  — does the mechanism exist, is it fresh, is it complete over its own population, and
//               is it inside the UI closure (a routine the browser can actually cause to run)?
//   FRONTEND  — does a rendered React surface put the figure on screen? Taken from src/ at run time
//               via ui_closure.mjs's renderedKeys(), never asserted in prose.
//
// The five defect classes that made row #2's scorer wrong are pre-empted here by construction:
//
//  1 THE ONLY READER IS THE WRITER — every reader question goes through ui.UI_READS(), which strips
//    `insert into t` / `update t` / `delete from t` bodies and collapses pg_proc overloads with
//    count(DISTINCT proname). fn_graph_rebuild is inside the UI closure (the automation runner can
//    trigger it) and is still not a reader of graph_nodes, because it is its writer.
//  2 POPULATION STANDING IN FOR DELIVERY — this is the whole subject of the file. graph_nodes holds
//    323 nodes and 300 edges rebuilt at 04:05 every morning; company_snapshot holds nine days of
//    company state; challenge_record holds 47 recorded disagreements. Not one of them is rendered.
//    So no check here stops at "the row exists": it asks which rendered surface shows it, by key.
//  3 ONE ROW SCORES A WHOLE MECHANISM — where the requirement says EVERY or EACH (every twin object,
//    every employee, every participant, each of the four scenario classes) the check is a per-row
//    NOT EXISTS or a covered-count compared against the population count, never `count(*) > 0`.
//    Everything with a cadence carries a recency window: a meeting that last ran in March is not a
//    weekly meeting, and a snapshot from July does not restore six months ago.
//  4 SATISFIABLE BY FLIPPING A FLAG — no check in this file reads a boolean column as its verdict.
//    Liveness is a SUCCEEDED cron run joined to the artifact it produced, not `cron.job.active`.
//  5 EVIDENCE THAT DOES NOT COMPUTE THE VERDICT — every evidence string is built from the same
//    sub-expressions as the boolean beside it. Where it prints prose (the live health note, the
//    keys an agenda item actually carries) that prose is SELECTED from the row being judged.
//
// One further trap, specific to this file: three of these requirements are naturally scored by
// invoking the routine the UI invokes — fn_agents_board(), fn_ws_exec(), fn_ws_agent_ops() — which
// is the only way to see what actually reaches the browser rather than what a function body looks
// like. This workflow is READ-ONLY against production, so every such invocation is guarded by
// NOWRITE(): the routine's own body is checked for a write form first and the check scores MISSING
// rather than running it if one is ever added. fn_what_if and fn_simulate DO write and are
// therefore never invoked here, only inspected.
import { uiClosure, UI_READS, UI_READ_NAMES, ALL_READS, UI_EMITS, UI_EMIT_NAMES, REL_EXISTS,
         COUNT_IF_EXISTS, SRC, SHELL, slice, surface, renderedKeys, defaultModule, componentFor,
         sqlArr } from './ui_closure.mjs';

export const label = 'layers 1-8 (Executive Lobby .. Future Simulator)';
export const EXPECTED = 20;

export default async function ({ req, q, one, Q: Qesc, B: Bhelp }) {
  const S = 'layers-1-8';
  const B = Bhelp || ((v) => (v ? 'true' : 'false'));
  const N = (v) => String(Number(v) || 0);
  const Q = (s) => (Qesc || ((x) => `'${String(x).replace(/'/g, "''")}'`))(String(s).slice(0, 220));

  // The closure is computed here rather than taken from the runner so this module keeps working
  // whichever shape the shared harness settles on. `q` returns one row; uiClosure wants the rowset.
  const ui = await uiClosure(async (sql) => [await q(sql)]);

  // ---- FRONTEND MEASUREMENT --------------------------------------------------------------------
  // The lobby is what is on screen before the founder clicks anything: the shell chrome plus the
  // module `cur` defaults to — plus Overview, the command centre, which the spec's own howMeasured
  // points at. Including Overview is deliberate generosity: over-hardening a check is as much a
  // failure as loosening one, and if a figure is on either surface this file says so.
  const LANDING_ID = defaultModule();
  const LANDING_COMP = componentFor(LANDING_ID);
  const LOBBY_COMPS = [...new Set(['OsxShell', LANDING_COMP, 'AgentStatus', 'NotificationsBell',
                                   'PipelineTracker', 'Overview'].filter(Boolean))];
  const compSrc = (n) => slice(n);
  const compKeys = (n) => renderedKeys(compSrc(n));
  const LOBBY_KEYS = renderedKeys(surface(...LOBBY_COMPS));
  const SHELL_KEYS = renderedKeys(SHELL);

  // A surface refreshes itself when it polls on a timer, or when a realtime handler re-runs its
  // loader. `postgres_changes` that only bumps a counter is neither, and is not counted.
  const POLLS = (n) => /setInterval\s*\(/.test(compSrc(n));
  const RT_RELOADS = (n) => /postgres_changes[\s\S]{0,600}?\b(load|reload|refresh|refetch|mutate)\s*\(/.test(compSrc(n));
  const SELF_REFRESHING = (n) => POLLS(n) || RT_RELOADS(n);

  // Which tables does src/ actually subscribe to over Realtime?
  const RT_TABLES = [...new Set([...SRC.matchAll(/postgres_changes[^)]{0,200}?table:\s*'([a-z0-9_]+)'/g)]
    .map(m => m[1]))].sort();

  // ---- SHARED SQL FRAGMENTS --------------------------------------------------------------------
  // A routine is only invoked below if its own body carries no write form. The keywords are split
  // so qd_guard's read guard, which refuses any statement containing a bare write keyword, does not
  // reject the check itself.
  const NOWRITE = (fn) => `(select coalesce(bool_and(pg_get_functiondef(p.oid)
        !~* ('(inse'||'rt\\s+into|upd'||'ate\\s|del'||'ete\\s+from|trunc'||'ate)')), false)
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname='${fn}')`;
  const IN_CLOSURE = (fn) => B(ui.routines.includes(fn));
  const OS_ACTIVE = `(select count(*) from public.operating_system where active)`;
  const AGENTS_ACTIVE = `(select count(*) from public.org_agents where active)`;
  // The newest executive meeting: the CEO row fn_exec_meeting writes, one per meeting.
  const MEETING = `(select r.id from public.exec_reports r where r.officer='ceo'
      order by r.created_at desc limit 1)`;
  const MEETING_AT = `(select r.created_at from public.exec_reports r where r.id = ${MEETING})`;

  // ================================================================================================
  // LAYER 1 — EXECUTIVE LOBBY
  // ================================================================================================

  // "Departments visibly glow/indicate when busy on entry."
  //
  // Two things have to be true and they fail independently, so both are asserted. The FIGURE must
  // exist for every STAFFED department — a department with no active employee cannot be busy, and
  // demanding a row for it would be a requirement no implementation could satisfy — and it must be
  // taken from what the browser is actually handed, which is why fn_agents_board() is invoked rather
  // than read. Then the LOBBY must render it. Production splits exactly here: the per-department
  // runs figure is computed and returned, and the only surface that draws it is the Smart Engine
  // kanban, three clicks from the landing screen.
  const BOARD = `public.fn_agents_board()->'departments'`;
  const DEPT_STAFFED = `(select count(*) from public.org_departments d
      where exists (select 1 from public.org_agents a where a.department=d.dept_key and a.active))`;
  const DEPT_UNLIT = `(select case when ${NOWRITE('fn_agents_board')} then (
        select count(*) from public.org_departments d
         where exists (select 1 from public.org_agents a where a.department=d.dept_key and a.active)
           and not exists (select 1 from jsonb_array_elements(${BOARD}) e
                           where e->>'key' = d.dept_key and (e->'runs') is not null))
      else -1 end)`;
  const DEPT_ON_LOBBY = LOBBY_COMPS.filter(n => {
    const k = compKeys(n);
    return k.some(x => /dept|department/i.test(x)) && k.some(x => /run|busy|activ|load|inflight/i.test(x));
  });
  const DEPT_ANYWHERE = ['Overview', 'AgentsApp', 'AgentDrawer', 'CompanyApp', 'OperationsApp', 'HealthPanel',
                         'Escalations', 'AnalyticsApp', 'StrategyApp'].filter(n => {
    const k = compKeys(n);
    return k.some(x => /dept|department/i.test(x)) && k.some(x => /run|busy|activ|load|inflight/i.test(x));
  });
  await req(S, 'lobby-departments-busy-indicator', 'Departments indicate when busy on entry',
    `select coalesce(${DEPT_UNLIT} = 0 and ${DEPT_STAFFED} > 0 and ${B(DEPT_ON_LOBBY.length > 0)}, false)`,
    `select ${DEPT_STAFFED}||' staffed department(s), '||${DEPT_UNLIT}
       ||' of them missing a runs figure in what fn_agents_board() hands the browser; lobby is '
       ||${Q(LOBBY_COMPS.join('+'))}||' (landing module '||${Q(LANDING_ID + ' -> ' + LANDING_COMP)}
       ||'), of which '||${N(DEPT_ON_LOBBY.length)}||' render a per-department activity indicator ('
       ||${Q(DEPT_ON_LOBBY.join(',') || 'none')}||'); '||${N(DEPT_ANYWHERE.length)}
       ||' surface(s) elsewhere in the shell render one ('||${Q(DEPT_ANYWHERE.join(',') || 'none')}||')'`);

  // "Revenue, customers and suppliers refresh live on the lobby without a reload."
  //
  // A per-COUNTER universal, because the requirement names three and two of them being present would
  // otherwise score the third. Each counter must be rendered on the lobby BY A SURFACE THAT REFRESHES
  // ITSELF. And the realtime half is checked at the only place it can actually fail: the shell does
  // open a postgres_changes channel, but a subscription to a table that is not in the
  // supabase_realtime publication delivers nothing at all, so the publication is part of the verdict
  // rather than a footnote.
  const COUNTERS = [['revenue', /revenue|income|turnover|mrr|gmv|cash/i],
                    ['customers', /customer|buyer/i],
                    ['suppliers', /supplier|vendor/i]];
  const counterState = COUNTERS.map(([nm, rx]) => {
    const on = LOBBY_COMPS.filter(c => compKeys(c).some(k => rx.test(k)));
    return { nm, on, live: on.filter(SELF_REFRESHING) };
  });
  const LIVE_COUNTERS = counterState.filter(c => c.live.length > 0).length;
  // A counter whose only refresh path is a Realtime channel is live only if the tables that channel
  // watches are actually published. Written as a conditional rather than a plain equality because
  // `published = subscribed` is vacuously TRUE when nothing is subscribed at all, and a clause that
  // cannot go false is a clause that measures nothing.
  const RT_ONLY = counterState.filter(c => c.live.length > 0 && !c.live.some(POLLS));
  const RT_PUBLISHED = `(select count(*) from pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public' and tablename = any(${sqlArr(RT_TABLES)}))`;
  await req(S, 'lobby-live-counters', 'Revenue, customers and suppliers refresh live on the lobby',
    `select coalesce(${N(LIVE_COUNTERS)} = ${N(COUNTERS.length)}
       and (${B(RT_ONLY.length === 0)}
            or (${N(RT_TABLES.length)} > 0 and ${RT_PUBLISHED} = ${N(RT_TABLES.length)})), false)`,
    `select ${N(LIVE_COUNTERS)}||' of '||${N(COUNTERS.length)}
       ||' named counter(s) are rendered on the lobby by a self-refreshing surface — '
       ||${Q(counterState.map(c => `${c.nm}: rendered by [${c.on.join(',') || 'nothing'}], self-refreshing [${c.live.join(',') || 'nothing'}]`).join('; '))}
       ||'; src/ subscribes over Realtime to '||${N(RT_TABLES.length)}||' table(s) ('
       ||${Q(RT_TABLES.join(',') || 'none')}||') of which '||${RT_PUBLISHED}
       ||' are in the supabase_realtime publication'`);

  // ================================================================================================
  // LAYER 2 — COMPANY DIGITAL TWIN
  // ================================================================================================

  // "All 13 named object classes exist as first-class twin objects."
  //
  // Per-class, never a total: twelve of thirteen would otherwise be a pass. A class is present when
  // its relation exists AND something the browser can reach READS it. Row count is deliberately NOT
  // required — QuotesDone is pre-traction and customers, inquiries and transactions are all at zero
  // today, so a population clause would make this unsatisfiable for reasons that have nothing to do
  // with the twin. The 13 tables are the ones the spec's own howMeasured names.
  const TWIN = [['Customers', 'customers'], ['Suppliers', 'leads'], ['Employees', 'org_agents'],
    ['Knowledge', 'kb_chunks'], ['RFQs', 'inquiries'], ['Payments', 'transactions'],
    ['Revenue', 'gl_journal'], ['AI', 'ai_cost_log'], ['Workflows', 'workflow'],
    ['Infrastructure', 'edge_health_probe'], ['Risks', 'risk_register'], ['Costs', 'expenses'],
    ['Strategy', 'vision_horizon']];
  const twinOk = (t) => `(${REL_EXISTS(t)} and ${UI_READS(ui, t)} > 0)`;
  const TWIN_COVERED = `(${TWIN.map(([, t]) => `(case when ${twinOk(t)} then 1 else 0 end)`).join(' + ')})`;
  const TWIN_MISSING = `concat_ws(', ', ${TWIN.map(([l, t]) =>
    `case when ${twinOk(t)} then null else '${l} (${t})' end`).join(', ')})`;
  await req(S, 'twin-object-model-complete', 'All 13 named object classes are first-class twin objects',
    `select coalesce(${TWIN_COVERED} = ${N(TWIN.length)}, false)`,
    `select ${TWIN_COVERED}||' of '||${N(TWIN.length)}
       ||' twin object classes are read by a routine or view the browser can reach; unreachable: '
       ||coalesce(nullif(${TWIN_MISSING}, ''), 'none')||'; those unreachable relations are named by '
       ||${TWIN.map(([, t]) => `(case when ${twinOk(t)} then 0 else ${ALL_READS(t)} end)`).join(' + ')}
       ||' routine(s)/view(s) in total'`);

  // "Every twin object refreshes in real time."
  //
  // Realtime means the DATABASE PUSHES. Two things are needed per class and neither is a flag: the
  // relation must be in the supabase_realtime publication (without that, a subscription is a silent
  // no-op), and src/ must actually subscribe to it. Measured 6 Aug 2026 the publication is EMPTY,
  // so the shell's one channel — INSERT on inquiries, all events on notifications — cannot fire.
  const twinRT = (t) => `(exists (select 1 from pg_publication_tables
        where pubname='supabase_realtime' and schemaname='public' and tablename='${t}')
      and ${B(RT_TABLES.includes(t))})`;
  const TWIN_RT = `(${TWIN.map(([, t]) => `(case when ${twinRT(t)} then 1 else 0 end)`).join(' + ')})`;
  const TWIN_PUB = `(select count(*) from pg_publication_tables where pubname='supabase_realtime'
      and schemaname='public' and tablename = any(${sqlArr(TWIN.map(x => x[1]))}))`;
  await req(S, 'twin-realtime-updates', 'Every twin object refreshes in real time',
    `select coalesce(${TWIN_RT} = ${N(TWIN.length)}, false)`,
    `select ${TWIN_RT}||' of '||${N(TWIN.length)}||' twin classes are both published and subscribed; '
       ||${TWIN_PUB}||' of '||${N(TWIN.length)}||' are in the supabase_realtime publication (which holds '
       ||(select count(*) from pg_publication_tables where pubname='supabase_realtime')
       ||' table(s) in all), and src/ subscribes to '||${N(RT_TABLES.length)}||' ('
       ||${Q(RT_TABLES.join(',') || 'none')}||')'`);

  // ================================================================================================
  // LAYER 3 — EXECUTIVE INTELLIGENCE
  // ================================================================================================

  // "The AI states an insight in prose with a cause, instead of a chart."
  //
  // The strongest available evidence, and the only one a nightly cron cannot fake: take the prose
  // key the lobby actually renders and READ THE VALUE BEHIND IT out of the routine that supplies it.
  // fn_ws_exec is STABLE and writes nothing, so it can be invoked. A cause is a causal connective —
  // and a cause without a magnitude is not the requirement's example ("revenue will miss by 6%
  // BECAUSE supplier response time rose 14%"), so a digit is required alongside it, in the same
  // string. The exec_reports counts beside it are the same test over the company's other prose, so
  // a MISSING verdict shows whether the gap is production or delivery.
  const CAUSAL = `'\\y(because|due to|driven by|caused by|owing to|as a result of|attributable to|led to|following a)\\y'`;
  const LIVE_NOTE = `(select case when ${NOWRITE('fn_ws_exec')}
      then public.fn_ws_exec()->'command'->'health'->>'note' else null end)`;
  const PROSE_ON_LOBBY = LOBBY_COMPS.filter(c => compKeys(c).some(k => /^(note|summary|insight|narrative|headline|why|rationale)$/i.test(k)));
  const SUM_RECENT = `(select count(*) from public.exec_reports where created_at > now() - interval '14 days')`;
  const SUM_CAUSAL = `(select count(*) from public.exec_reports where created_at > now() - interval '14 days'
      and summary ~* ${CAUSAL} and summary ~ '[0-9]')`;
  await req(S, 'exec-intel-narrative-insight', 'A prose insight naming a cause reaches the landing view',
    `select coalesce(${B(PROSE_ON_LOBBY.length > 0)}
       and ${LIVE_NOTE} is not null and ${LIVE_NOTE} ~* ${CAUSAL} and ${LIVE_NOTE} ~ '[0-9]', false)`,
    // Every leg is coalesced: a null note makes the whole concatenation null in Postgres, and an
    // evidence string that prints "null" states nothing at all about why the verdict fell.
    `select ${N(PROSE_ON_LOBBY.length)}||' lobby surface(s) render a prose key ('
       ||${Q(PROSE_ON_LOBBY.join(',') || 'none')}||'); the value behind it right now is '
       ||coalesce('"'||left(${LIVE_NOTE}, 120)||'"', '(null)')||', causal: '
       ||coalesce((${LIVE_NOTE} ~* ${CAUSAL})::text, 'n/a')||', quantified: '
       ||coalesce((${LIVE_NOTE} ~ '[0-9]')::text, 'n/a')
       ||'; of '||${SUM_RECENT}||' exec_reports summaries written in 14d, '||${SUM_CAUSAL}
       ||' name a cause AND carry a number, and exec_reports.summary is emitted by '
       ||${UI_EMITS(ui, `'\\ysummary\\y'`)}||' reachable routine(s)'`);

  // "The insight carries a quantified recommendation."
  //
  // A per-OFFICER universal over the newest report each officer filed in the window, so one good
  // recommendation cannot certify the rest, and an empty `recommendations` array cannot pass by
  // being vacuously true. `confidence` is stripped from every entry before the digit test: a
  // recommendation whose only number is its own confidence score is a direction, not a numeric ask —
  // which is precisely the distinction the requirement draws.
  const REC_LATEST = `(select distinct on (officer) id, officer, recommendations
      from public.exec_reports where created_at > now() - interval '14 days'
      order by officer, created_at desc)`;
  const REC_QUANT = `(select count(*) from ${REC_LATEST} r
      where jsonb_typeof(r.recommendations)='array' and jsonb_array_length(r.recommendations) > 0
        and exists (select 1 from jsonb_array_elements(r.recommendations) e
                    where (case when jsonb_typeof(e)='object' then (e - 'confidence')::text else e::text end)
                          ~ '[0-9]'))`;
  const REC_TOT = `(select count(*) from ${REC_LATEST} r)`;
  await req(S, 'exec-intel-quantified-recommendation', 'The insight carries a quantified recommendation',
    `select coalesce(${REC_TOT} > 0 and ${REC_QUANT} = ${REC_TOT}, false)`,
    `select ${REC_QUANT}||' of '||${REC_TOT}
       ||' officer(s) with a report in 14d carry a numeric recommendation (confidence excluded); '
       ||(select count(*) from ${REC_LATEST} r where coalesce(jsonb_array_length(
            case when jsonb_typeof(r.recommendations)='array' then r.recommendations else '[]'::jsonb end), 0) = 0)
       ||' filed an empty recommendations array; the entries of the newest one are '
       ||coalesce((select left(string_agg(e::text, ' | '), 150) from ${REC_LATEST} r,
            jsonb_array_elements(r.recommendations) e
           where r.id = (select max(id) from ${REC_LATEST} r2)), '(none)')`);

  // ================================================================================================
  // LAYER 4 — LIVING ORGANIZATION
  // ================================================================================================

  // "An employee's current goal is visible in their workspace."
  //
  // The workspace is AgentDrawer, fed by os_api 'ws.agent' -> fn_ws_agent_ops. So the universal runs
  // over what that routine returns FOR EVERY ACTIVE EMPLOYEE — not over what a goal table contains —
  // and the drawer must render the key. fn_ws_agent_ops is VOLATILE but writes nothing, so the
  // invocation is guarded by NOWRITE and the check degrades to MISSING (never to a write) if that
  // ever changes. The objective rows beside it are the built-but-undelivered count.
  const WS_AGENT_GOAL = `(select case when ${NOWRITE('fn_ws_agent_ops')} then (
        select count(*) from public.org_agents a where a.active
          and (public.fn_ws_agent_ops(a.agent_key)
               ?| array['goal','goals','objective','objectives','current_goal','target'])) else -1 end)`;
  const DRAWER_GOAL = renderedKeys(slice('AgentDrawer')).filter(k => /^(goal|goals|objective|objectives|current_goal|target)$/i.test(k));
  await req(S, 'employee-current-goal', "An employee's current goal is visible in their workspace",
    `select coalesce(${WS_AGENT_GOAL} = ${AGENTS_ACTIVE} and ${AGENTS_ACTIVE} > 0
       and ${B(DRAWER_GOAL.length > 0)}, false)`,
    `select ${WS_AGENT_GOAL}||' of '||${AGENTS_ACTIVE}
       ||' active employee(s) are handed a goal by fn_ws_agent_ops; AgentDrawer renders '
       ||${N(DRAWER_GOAL.length)}||' goal key(s) ('||${Q(DRAWER_GOAL.join(',') || 'none')}
       ||'); meanwhile department_objective holds '||${COUNT_IF_EXISTS('department_objective')}
       ||' and os_objective '||${COUNT_IF_EXISTS('os_objective')}||' objective(s), with '
       ||${UI_READS(ui, 'department_objective')}||' and '||${UI_READS(ui, 'os_objective')}
       ||' reachable reader(s) respectively'`);

  // "Which knowledge an employee used is visible."
  //
  // Usage, not holdings. AgentDrawer already lists the agent's knowledge TOPICS; the requirement is
  // which knowledge fed a decision. Three legs, and the first is a PER-EMPLOYEE universal rather
  // than a row count: every employee who decided something this week must have a knowledge-usage
  // record this week, so a single seed row in kb_usage_log cannot make the mechanism permanently
  // present. The decision-side citation ratio is reported beside it over the same window.
  const KBU_RECENT = COUNT_IF_EXISTS('kb_usage_log', "created_at > now() - interval '7 days'");
  const DECIDERS = `(select count(distinct l.actor) from public.decision_log l
      where l.created_at > now() - interval '7 days' and l.actor is not null)`;
  const DECIDERS_UNTRACED = `(select case when to_regclass('public.kb_usage_log') is null then -1 else
      (xpath('/row/c/text()', query_to_xml(
        'select count(distinct l.actor) c from public.decision_log l'
        ||' where l.created_at > now() - interval ''7 days'' and l.actor is not null'
        ||' and not exists (select 1 from public.kb_usage_log u where u.agent = l.actor'
        ||' and u.created_at > now() - interval ''7 days'')', false, true, '')))[1]::text::int end)`;
  const DEC_TOT = `(select count(*) from public.decision_log where created_at > now() - interval '7 days')`;
  const DEC_CITED = `(select count(*) from public.decision_log where created_at > now() - interval '7 days'
      and sources is not null and sources::text not in ('null','[]','{}','""'))`;
  const CITE_KEYS = SHELL_KEYS.filter(k => /^(sources|citations|knowledge_used|used_knowledge|evidence)$/i.test(k));
  await req(S, 'employee-knowledge-used', 'Which knowledge an employee used is visible',
    `select coalesce(${DECIDERS} > 0 and ${DECIDERS_UNTRACED} = 0
       and ${UI_READS(ui, 'kb_usage_log')} > 0 and ${B(CITE_KEYS.length > 0)}, false)`,
    `select ${DECIDERS_UNTRACED}||' of '||${DECIDERS}
       ||' employee(s) who decided something in 7d have no knowledge-usage record in that window; '
       ||'kb_usage_log holds '||${COUNT_IF_EXISTS('kb_usage_log')}||' row(s) in all and '||${KBU_RECENT}
       ||' in 7d; '||${DEC_CITED}||' of '||${DEC_TOT}
       ||' decisions logged in 7d name their sources; reachable reader(s) of kb_usage_log: '
       ||${UI_READ_NAMES(ui, 'kb_usage_log')}||'; rendered citation key(s) anywhere in the shell: '
       ||${N(CITE_KEYS.length)}||' ('||${Q(CITE_KEYS.join(',') || 'none')}||')'`);

  // "Performance is shown as a trend, not a point value."
  //
  // A trend needs two things a point value does not: more than one observation PER EMPLOYEE inside a
  // window, and a surface that draws a series. Both sources the spec names are counted separately
  // because they fail differently — employee_kpi is reachable but was written in one batch on
  // 28 July, ai_quality_snapshots genuinely is a per-agent time series and nothing can reach it.
  const KPI_TREND = `(select count(*) from (select agent_key from public.employee_kpi
      where created_at > now() - interval '90 days' group by agent_key having count(distinct created_at) > 1) z)`;
  const AIQ_TREND = `(select case when to_regclass('public.ai_quality_snapshots') is null then 0 else
      (xpath('/row/c/text()', query_to_xml('select count(*) c from (select agent from public.ai_quality_snapshots'
        ||' where at > now() - interval ''90 days'' group by agent having count(distinct at) > 1) z',
        false, true, '')))[1]::text::int end)`;
  // SUMMING THE TWO SOURCES WOULD DOUBLE-COUNT an employee who appears in both, and double-counting
  // can only ever push this check towards a false MET. Reachability is resolved to a JS boolean
  // first so the population can be a genuine UNION of employees rather than a sum of two counts.
  const kpiReach = Number(await one(`select ${UI_READS(ui, 'employee_kpi')}`)) > 0;
  const aiqReach = Number(await one(`select ${UI_READS(ui, 'ai_quality_snapshots')}`)) > 0;
  const TREND_SRC = [
    kpiReach ? `select agent_key k, created_at ts from public.employee_kpi where created_at > now() - interval '90 days'` : null,
    aiqReach ? `select agent k, at ts from public.ai_quality_snapshots where at > now() - interval '90 days'` : null,
  ].filter(Boolean);
  const TREND_REACHABLE = TREND_SRC.length
    ? `(select count(*) from (select z.k from (${TREND_SRC.join(' union all ')}) z
          group by z.k having count(distinct z.ts) > 1) y)`
    : `0`;
  const SERIES_IN_DRAWER = (slice('AgentDrawer').match(/<(MiniLine|AreaSpark|HBars|Sparkline|LineChart)\b/g) || []).length;
  await req(S, 'employee-performance-trend', 'Performance is shown as a trend, not a point value',
    `select coalesce(${TREND_REACHABLE} >= ${AGENTS_ACTIVE} and ${AGENTS_ACTIVE} > 0
       and ${N(SERIES_IN_DRAWER)} > 0, false)`,
    `select ${TREND_REACHABLE}||' of '||${AGENTS_ACTIVE}
       ||' active employee(s) have more than one performance observation in 90d in a REACHABLE source; '
       ||'employee_kpi gives '||${KPI_TREND}||' such employee(s) ('||${UI_READS(ui, 'employee_kpi')}
       ||' reachable reader(s), '||${COUNT_IF_EXISTS('employee_kpi')}||' rows across '
       ||(select count(distinct created_at::date) from public.employee_kpi)
       ||' distinct day(s)) and ai_quality_snapshots gives '||${AIQ_TREND}||' ('
       ||${UI_READS(ui, 'ai_quality_snapshots')}||' reachable reader(s)); AgentDrawer draws '
       ||${N(SERIES_IN_DRAWER)}||' series component(s)'`);

  // ================================================================================================
  // LAYER 5 — EXECUTIVE MEETING ROOM
  // ================================================================================================

  // "The CEO AI starts an executive meeting every Monday without a human."
  //
  // A SCHEDULE IS NOT A RUN and a run is not an outcome. Three legs: the job is active with a Monday
  // schedule, it SUCCEEDED inside a window wide enough for one missed Monday and no wider, and the
  // report it exists to write landed next to that success. The last leg is what makes this immune to
  // a cron that fires and throws.
  const MJOB = `(select j.jobid from cron.job j where j.active and j.command ~* '\\yfn_exec_meeting\\y' limit 1)`;
  const MRUN = `(select max(d.end_time) from cron.job_run_details d
      where d.jobid = ${MJOB} and d.status='succeeded')`;
  await req(S, 'exec-meeting-weekly-autostart', 'The CEO AI starts the meeting weekly, unprompted',
    `select coalesce(${MJOB} is not null
       and (select j.schedule from cron.job j where j.jobid=${MJOB}) ~ '\\*\\s*1$'
       and ${MRUN} > now() - interval '14 days'
       and exists (select 1 from public.exec_reports r where r.officer='ceo'
                   and r.created_at between ${MRUN} - interval '10 minutes' and ${MRUN} + interval '60 minutes'), false)`,
    `select coalesce((select j.jobname||' ('||j.schedule||', active '||j.active||')'
        from cron.job j where j.jobid=${MJOB}), 'no active fn_exec_meeting cron')
       ||'; last succeeded '||coalesce(${MRUN}::timestamp(0)::text, 'never')||' after '
       ||coalesce((select count(*)::text from cron.job_run_details d where d.jobid=${MJOB}), '0')
       ||' run(s); ceo report(s) written within the hour after that success: '
       ||(select count(*) from public.exec_reports r where r.officer='ceo'
           and r.created_at between ${MRUN} - interval '10 minutes' and ${MRUN} + interval '60 minutes')`);

  // "The ten named officers participate."
  //
  // A per-OS NOT EXISTS against operating_system, which holds exactly the ten the spec names, scored
  // over the LATEST meeting only — a meeting in March that had all ten does not make this week's
  // meeting complete. Matching is on the OS's own `name` from the table rather than on a list
  // written here, so renaming an OS cannot silently drop a participant. A contribution with no owner
  // is not a participant, so that is asserted too. position(), never LIKE: the name comes out of a
  // table, and on the pattern side of LIKE a stored '_' is a single-character wildcard that can only
  // ever produce a false MET — 35 of row #2's 72 interpolated values carried exactly that character.
  const MITEMS = `(select jsonb_array_elements(r.findings) e from public.exec_reports r
      where r.id = ${MEETING} and jsonb_typeof(r.findings)='array')`;
  const OS_ABSENT = `(select count(*) from public.operating_system o where o.active
      and not exists (select 1 from (${MITEMS}) f
                      where position(lower(o.name) in lower(f.e->>'item')) > 0 or f.e->>'owner' = o.owner_agent))`;
  const ITEMS_UNOWNED = `(select count(*) from (${MITEMS}) f where coalesce(f.e->>'owner','') = '')`;
  await req(S, 'exec-meeting-ten-participants', 'All ten named officers participate in the meeting',
    `select coalesce(${MEETING} is not null and ${OS_ABSENT} = 0 and ${ITEMS_UNOWNED} = 0
       and ${OS_ACTIVE} = 10, false)`,
    `select (${OS_ACTIVE} - ${OS_ABSENT})||' of '||${OS_ACTIVE}
       ||' active operating system(s) contributed to the meeting of '
       ||coalesce(${MEETING_AT}::timestamp(0)::text, 'never')||' ('
       ||(select count(*) from (${MITEMS}) f)||' agenda item(s), '||${ITEMS_UNOWNED}
       ||' with no owner); absent: '
       ||coalesce((select string_agg(o.name, ', ') from public.operating_system o where o.active
            and not exists (select 1 from (${MITEMS}) f
                where position(lower(o.name) in lower(f.e->>'item')) > 0 or f.e->>'owner' = o.owner_agent)), 'none')`);

  // "Each participant presents wins, problems, KPIs, risks, opportunities and requests."
  //
  // Per SECTION and per ITEM, both: six sections over every contribution, not six sections somewhere
  // in the meeting. Synonyms are accepted for each section so the check does not demand one
  // particular vocabulary, and the evidence prints the keys the items ACTUALLY carry, so a MISSING
  // verdict says what was found instead of restating what was wanted.
  const AGENDA = [['wins', 'win|achiev|success|delivered'], ['problems', 'problem|issue|blocker|concern'],
    ['kpis', 'kpi|metric|attainment|measure'], ['risks', 'risk'],
    ['opportunities', 'opportunit'], ['requests', 'request|ask|needs_from|support_needed']];
  // Keys of the contribution, and keys of any object one level inside it: an implementation that
  // groups the six under a `sections` object is presenting them, and a check that only looked at the
  // top level would score that MISSING. A key whose value is JSON null or empty is not a section —
  // row #2's TRAP 3, where `metrics ? 'k'` was true for a JSON null, applies to an agenda verbatim.
  const secCovered = (rx) => `(select count(*) from (${MITEMS}) f
      where exists (select 1 from jsonb_object_keys(f.e) k where k ~* '${rx}'
                    and jsonb_typeof(f.e->k) <> 'null' and coalesce(f.e->>k, '') <> '')
         or exists (select 1 from jsonb_each(f.e) t, jsonb_object_keys(t.value) k2
                    where jsonb_typeof(t.value)='object' and k2 ~* '${rx}'
                      and jsonb_typeof(t.value->k2) <> 'null' and coalesce(t.value->>k2, '') <> ''))`;
  const ITEMS_N = `(select count(*) from (${MITEMS}) f)`;
  const AGENDA_FULL = `(${AGENDA.map(([, rx]) => `(case when ${secCovered(rx)} = ${ITEMS_N} then 1 else 0 end)`).join(' + ')})`;
  await req(S, 'exec-meeting-agenda-six', 'Each participant presents all six agenda sections',
    `select coalesce(${ITEMS_N} > 0 and ${AGENDA_FULL} = ${N(AGENDA.length)}, false)`,
    `select ${AGENDA_FULL}||' of '||${N(AGENDA.length)}||' agenda sections are present on ALL '
       ||${ITEMS_N}||' contribution(s) of the latest meeting — '
       ||${AGENDA.map(([nm, rx]) => `'${nm} '||${secCovered(rx)}`).join(`||', '||`)}
       ||'; the keys those contributions actually carry are: '
       ||coalesce((select string_agg(distinct k, ',') from (${MITEMS}) f, jsonb_object_keys(f.e) k), 'none')`);

  // "Participants debate and challenge each other."
  //
  // The debate has to happen INSIDE the meeting, which is the distinction the spec's howMeasured
  // draws. Two legs, and neither is a mention: fn_exec_meeting must CALL fn_challenge (`\s*\(`, so a
  // comment naming it is not a mechanism), and challenges must be RECORDED in the meeting's own
  // window. The 47 historical rows cannot satisfy a window bound to the latest meeting, which is
  // exactly the point — they were written by a separate routine three weeks ago.
  const MEET_CALLS_CHALLENGE = `(select coalesce(bool_or(pg_get_functiondef(p.oid) ~* '\\yfn_challenge\\s*\\('), false)
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname='fn_exec_meeting')`;
  const CH_IN_MEETING = COUNT_IF_EXISTS('challenge_record',
    "created_at between (select max(created_at) from public.exec_reports where officer='ceo') - interval '30 minutes'"
    + " and (select max(created_at) from public.exec_reports where officer='ceo') + interval '6 hours'");
  await req(S, 'exec-meeting-debate', 'Participants debate and challenge each other in the meeting',
    `select coalesce(${MEET_CALLS_CHALLENGE} and ${CH_IN_MEETING} > 0, false)`,
    `select 'fn_exec_meeting invokes fn_challenge: '||${MEET_CALLS_CHALLENGE}::text||'; '
       ||${CH_IN_MEETING}||' challenge(s) recorded in the window of the latest meeting ('
       ||coalesce(${MEETING_AT}::timestamp(0)::text, 'never')||'), against '
       ||${COUNT_IF_EXISTS('challenge_record')}||' in the table overall, newest '
       ||coalesce((select max(created_at)::date::text from public.challenge_record), 'never')
       ||', spanning '||(select count(distinct stance) from public.challenge_record)||' stance(s)'`);

  // "The meeting ends with agreed priorities."
  //
  // A per-MEETING universal over the last 60 days, because a priorities list attached to one meeting
  // is not a mechanism. And priorities are ORDERED and OWNED: the artifact must be a non-empty array
  // whose every entry carries a rank, a priority, an order or an owner. A list of prose sentences is
  // a summary. priority_hierarchy is not accepted as the artifact — it is the standing constitution,
  // six rows with no timestamp, identical for every meeting ever held, and letting it answer this
  // would be one static fact scoring a recurring requirement.
  const MEETINGS_60 = `(select r.id, r.created_at, r.recommendations from public.exec_reports r
      where r.officer='ceo' and r.created_at > now() - interval '60 days')`;
  const PRIO_OK = `(select count(*) from ${MEETINGS_60} m
      where jsonb_typeof(m.recommendations)='array' and jsonb_array_length(m.recommendations) > 0
        and not exists (select 1 from jsonb_array_elements(m.recommendations) e
                        where jsonb_typeof(e) <> 'object'
                           or not (e ?| array['rank','priority','order','owner','sequence'])))`;
  const MEETINGS_N = `(select count(*) from ${MEETINGS_60} m)`;
  await req(S, 'exec-meeting-priorities-agreed', 'The meeting ends with agreed, ranked priorities',
    `select coalesce(${MEETINGS_N} > 0 and ${PRIO_OK} = ${MEETINGS_N}, false)`,
    `select ${PRIO_OK}||' of '||${MEETINGS_N}
       ||' meeting(s) in 60d end with a ranked/owned priority list; the latest one carries '
       ||coalesce((select jsonb_array_length(r.recommendations)::text from public.exec_reports r
            where r.id = ${MEETING} and jsonb_typeof(r.recommendations)='array'), 'no array of')
       ||' recommendation entr(ies), of type(s) '
       ||coalesce((select string_agg(distinct jsonb_typeof(e), ',') from public.exec_reports r,
            jsonb_array_elements(r.recommendations) e where r.id = ${MEETING}), 'none')
       ||'; priority_hierarchy holds '||${COUNT_IF_EXISTS('priority_hierarchy')}
       ||' standing principle(s) with '||${UI_READS(ui, 'priority_hierarchy')}||' reachable reader(s)'`);

  // "The meeting is recorded and can be replayed."
  //
  // Stored, reachable, and PLAYED IN SEQUENCE — three separate failures. Production stores the whole
  // ordered transcript in exec_reports.findings and report_registry is inside the UI closure, but
  // the view projects only title/period/id: the contributions themselves are never handed to the
  // browser, and no surface iterates them. So the transcript leg and the reachability-of-the-BODY
  // leg are asked separately, and the rendering leg is asked of the key, not of the table.
  const TRANSCRIPT_OK = `(select coalesce((select jsonb_array_length(r.findings) >= ${OS_ACTIVE}
      from public.exec_reports r where r.id = ${MEETING} and jsonb_typeof(r.findings)='array'), false))`;
  // The body is reachable only if a routine the browser can run names the transcript column AND the
  // table it lives in. `findings` on its own is a common enough word that a routine using it for
  // something else would certify a transcript it never touches.
  const FINDINGS_RX = `'\\yexec_reports\\y[\\s\\S]*\\yfindings\\y|\\yfindings\\y[\\s\\S]*\\yexec_reports\\y'`;
  const BODY_REACHABLE = UI_EMITS(ui, FINDINGS_RX);
  const REPLAY_KEYS = SHELL_KEYS.filter(k => /^(findings|transcript|contributions|agenda|minutes|timeline)$/i.test(k));
  await req(S, 'exec-meeting-replayable', 'The meeting is recorded and replayable in sequence',
    `select coalesce(${TRANSCRIPT_OK} and ${BODY_REACHABLE} > 0 and ${B(REPLAY_KEYS.length > 0)}, false)`,
    `select 'latest meeting stores '
       ||coalesce((select jsonb_array_length(r.findings)::text from public.exec_reports r
            where r.id = ${MEETING} and jsonb_typeof(r.findings)='array'), '0')
       ||' ordered contribution(s) for '||${OS_ACTIVE}||' active OS; reachable routine(s) emitting the '
       ||'findings body: '||${BODY_REACHABLE}||' ('||${UI_EMIT_NAMES(ui, FINDINGS_RX)}
       ||'); exec_reports itself is reached by '||${UI_READ_NAMES(ui, 'exec_reports')}
       ||'; surfaces rendering a transcript key: '||${N(REPLAY_KEYS.length)}||' ('
       ||${Q(REPLAY_KEYS.join(',') || 'none')}||')'`);

  // ================================================================================================
  // LAYER 6 — COMPANY BRAIN
  // ================================================================================================

  // "The entire company knowledge graph is on one page."
  //
  // The archetype of this whole spec file: 323 nodes and 300 edges, rebuilt by an active cron at
  // 04:05 this morning, and nothing anywhere opens them. Freshness is asserted so a graph that stops
  // rebuilding cannot pass on stale rows; the reader count goes through UI_READS so fn_graph_rebuild,
  // which is inside the UI closure and names both tables, is excluded as their writer; and the src/
  // count is the half no database query can answer.
  const NODES = COUNT_IF_EXISTS('graph_nodes');
  const EDGES = COUNT_IF_EXISTS('graph_edges');
  const GRAPH_FRESH = `(select coalesce(max(updated_at) > now() - interval '3 days', false) from public.graph_nodes)`;
  const GRAPH_IN_SRC = (SRC.match(/\bgraph_(nodes|edges)\b/g) || []).length;
  await req(S, 'company-brain-one-page-graph', 'The company knowledge graph is on one page',
    `select coalesce(${NODES} > 0 and ${EDGES} > 0 and ${GRAPH_FRESH}
       and ${UI_READS(ui, 'graph_nodes')} > 0 and ${UI_READS(ui, 'graph_edges')} > 0
       and ${N(GRAPH_IN_SRC)} > 0, false)`,
    `select ${NODES}||' node(s) and '||${EDGES}||' edge(s), rebuilt '
       ||coalesce((select max(updated_at)::timestamp(0)::text from public.graph_nodes), 'never')
       ||'; reachable reader(s) of graph_nodes: '||${UI_READ_NAMES(ui, 'graph_nodes')}||', of graph_edges: '
       ||${UI_READ_NAMES(ui, 'graph_edges')}||'; named in total by '||${ALL_READS('graph_nodes')}
       ||' routine(s)/view(s); referenced '||${N(GRAPH_IN_SRC)}||' time(s) in src/'`);

  // "You can navigate the company by following relationships instead of menus."
  //
  // RecordDrawer genuinely does hop, with an unbounded breadcrumb stack — that leg is measured from
  // the source and it passes. What it hops along is a literal map compiled into the bundle, so the
  // relationships it can follow are fixed at build time and the company graph it should be walking
  // is unread. Both are asserted: unbounded depth AND the relationship set coming from the graph.
  const DRAWER = slice('RecordDrawer');
  const HOP_MAP = new Set([...SHELL.matchAll(/const (?:REL_ENTITY|FK_ENTITY): Record<string, string> = \{([^}]*)\}/g)]
    .flatMap(m => [...m[1].matchAll(/([a-z_]+)\s*:/g)].map(x => x[1])));
  const UNBOUNDED = /setStack\s*\(\s*\(?s\)?\s*=>\s*\[\s*\.\.\.\s*s\s*,/.test(DRAWER);
  const EDGE_KINDS = `(select case when to_regclass('public.graph_edges') is null then 0 else
      (xpath('/row/c/text()', query_to_xml('select count(distinct rel) c from public.graph_edges',
        false, true, '')))[1]::text::int end)`;
  await req(S, 'company-brain-navigate-by-relationship', 'Navigation follows relationships, not menus',
    `select coalesce(${B(UNBOUNDED)} and ${UI_READS(ui, 'graph_edges')} > 0
       and ${EDGE_KINDS} > 0, false)`,
    `select 'RecordDrawer hops through a compiled-in map of '||${N(HOP_MAP.size)}
       ||' entity key(s), with an unbounded stack: '||${B(UNBOUNDED)}
       ||'; graph_edges holds '||${EDGES}||' relationship(s) across '||${EDGE_KINDS}
       ||' kind(s) and has '||${UI_READS(ui, 'graph_edges')}||' reachable reader(s) ('
       ||${UI_READ_NAMES(ui, 'graph_edges')}||'); relationship kinds present in the graph but absent '
       ||'from the compiled-in map: '
       ||coalesce((select string_agg(distinct g.rel, ',') from public.graph_edges g
                    where g.rel <> all(${sqlArr([...HOP_MAP])})), 'none')`);

  // ================================================================================================
  // LAYER 7 — TIME MACHINE
  // ================================================================================================

  // "You can slide backward to see the company last week, last month, six months ago."
  //
  // Per-HORIZON, because nine consecutive days of snapshots answer one of the three and a global
  // count would score all three. Each horizon needs a snapshot within a tolerance proportional to
  // it. Then the state has to be reachable — company_snapshot's only reader is the writer that
  // fills it — and a date control has to exist in the OS UI, measured as a date input the shell
  // actually binds to a historical view rather than any <input type=date> anywhere (the two in the
  // shell today are a journal-entry date and a report filter).
  const HORIZONS = [['last week', 7, 3], ['last month', 30, 5], ['six months ago', 182, 20]];
  const horizonOk = (d, tol) => `(select count(*) > 0 from public.company_snapshot s
      where s.snapshot_on between (now() - interval '${d} days')::date - ${tol}
                              and (now() - interval '${d} days')::date + ${tol})`;
  const HORIZ_COVERED = `(${HORIZONS.map(([, d, t]) => `(case when ${horizonOk(d, t)} then 1 else 0 end)`).join(' + ')})`;
  const DATE_CONTROLS = (SHELL.match(/type='date'/g) || []).length;
  const SCRUB_BOUND = /\b(as_of|asOf|snapshot_on|snapshotOn|history_date|replay_date)\b/.test(SRC);
  await req(S, 'time-machine-scrub', 'The founder can slide back a week, a month, six months',
    `select coalesce(${HORIZ_COVERED} = ${N(HORIZONS.length)}
       and ${UI_READS(ui, 'company_snapshot')} > 0 and ${B(SCRUB_BOUND)}, false)`,
    `select ${HORIZ_COVERED}||' of '||${N(HORIZONS.length)}||' horizons have a snapshot — '
       ||${HORIZONS.map(([nm, d, t]) => `'${nm} '||${horizonOk(d, t)}::text`).join(`||', '||`)}
       ||'; company_snapshot holds '||${COUNT_IF_EXISTS('company_snapshot')}||' day(s) from '
       ||coalesce((select min(snapshot_on)::text from public.company_snapshot), '-')||' to '
       ||coalesce((select max(snapshot_on)::text from public.company_snapshot), '-')
       ||', reachable reader(s): '||${UI_READ_NAMES(ui, 'company_snapshot')}||' (named in total by '
       ||${ALL_READS('company_snapshot')}||'); the shell holds '||${N(DATE_CONTROLS)}
       ||' date input(s), and src/ binds a historical-state parameter: '||${B(SCRUB_BOUND)}`);

  // "A past date shows KPIs, employees, knowledge, decisions, revenue and customers as they were."
  //
  // Per DIMENSION and per SNAPSHOT: every snapshot in the window must carry a non-null value for
  // each of the six, so one richly populated day cannot answer for the rest, and a key present with
  // a JSON null does not count — that was row #2's TRAP 3 and it applies verbatim to a jsonb state
  // blob. Synonyms per dimension, again so the check does not demand one particular vocabulary.
  const DIMS = [['KPIs', 'kpi'], ['employees', 'employee|headcount|agents'], ['knowledge', 'knowledge|kb_'],
    ['decisions', 'decision'], ['revenue', 'revenue|income|turnover'], ['customers', 'customer|buyer']];
  const SNAPS = `(select s.snapshot_on, s.state from public.company_snapshot s
      where s.snapshot_on > (now() - interval '14 days')::date)`;
  const SNAPS_N = `(select count(*) from ${SNAPS} s)`;
  const dimOk = (rx) => `(select count(*) from ${SNAPS} s
      where exists (select 1 from jsonb_object_keys(s.state) k
                    where k ~* '${rx}' and jsonb_typeof(s.state->k) <> 'null'))`;
  const DIMS_FULL = `(${DIMS.map(([, rx]) => `(case when ${dimOk(rx)} = ${SNAPS_N} then 1 else 0 end)`).join(' + ')})`;
  await req(S, 'time-machine-restores-six-dimensions', 'A past date restores all six named dimensions',
    `select coalesce(${SNAPS_N} > 0 and ${DIMS_FULL} = ${N(DIMS.length)}, false)`,
    `select ${DIMS_FULL}||' of '||${N(DIMS.length)}||' dimensions are non-null on ALL '||${SNAPS_N}
       ||' snapshot(s) of the last 14 days — '
       ||${DIMS.map(([nm, rx]) => `'${nm} '||${dimOk(rx)}`).join(`||', '||`)}
       ||'; the newest snapshot carries the keys: '
       ||coalesce((select string_agg(k, ',' order by k) from public.company_snapshot s,
            jsonb_object_keys(s.state) k
           where s.snapshot_on = (select max(snapshot_on) from public.company_snapshot)), 'none')`);

  // ================================================================================================
  // LAYER 8 — FUTURE SIMULATOR
  // ================================================================================================

  // "The OS answers 'what will happen if...' for pricing changes, vendor cost shocks, channel
  //  failure and geographic expansion."
  //
  // Per QUESTION CLASS over the four the spec names, and then the leg that decides it: the simulator
  // has to be ASKABLE from the browser. fn_what_if and fn_simulate both exist and both WRITE, which
  // is why they are inspected and never invoked here; the question is whether any edge function the
  // browser can reach dispatches either of them. os_api's ACTION_CLASS has no simulate action, so
  // the four scenario classes could all be covered and the founder still could not ask one.
  const CLASSES = [['pricing change', 'pric|fee|discount|tariff|rate card'],
    ['vendor cost shock', 'vendor|supplier cost|cost shock|price increase|key_supplier|supply shock'],
    ['channel failure', 'channel|campaign fail|traffic|ad(s)? (outage|failure)|lead source'],
    ['geographic expansion', 'geograph|expansion|new market|new city|new country|emirate|abu dhabi|saudi']];
  const clsHit = (rx) => COUNT_IF_EXISTS('scenario_library',
    `(scenario_key||' '||name||' '||coalesce(situation,'')||' '||coalesce(category,'')) ~* '${rx}'`);
  const CLASSES_COVERED = `(${CLASSES.map(([, rx]) => `(case when ${clsHit(rx)} > 0 then 1 else 0 end)`).join(' + ')})`;
  const SIM_ASKABLE = ui.roots.includes('fn_what_if') || ui.roots.includes('fn_simulate')
    || ui.routines.includes('fn_what_if') || ui.routines.includes('fn_simulate');
  await req(S, 'future-simulator-forward-questions', 'Forward what-if questions can be asked and answered',
    `select coalesce(${CLASSES_COVERED} = ${N(CLASSES.length)} and ${B(SIM_ASKABLE)}
       and ${COUNT_IF_EXISTS('simulations')} > 0, false)`,
    `select ${CLASSES_COVERED}||' of '||${N(CLASSES.length)}
       ||' named question classes appear in scenario_library ('||${COUNT_IF_EXISTS('scenario_library')}
       ||' scenarios) — '||${CLASSES.map(([nm, rx]) => `'${nm} '||${clsHit(rx)}`).join(`||', '||`)}
       ||'; fn_what_if/fn_simulate reachable from a browser-reachable edge function: '||${B(SIM_ASKABLE)}
       ||'; simulations holds '||${COUNT_IF_EXISTS('simulations')}||' result(s), newest '
       ||coalesce((select max(created_at)::date::text from public.simulations), 'never')
       ||', with '||${UI_READS(ui, 'simulations')}||' reachable reader(s)'`);
}
