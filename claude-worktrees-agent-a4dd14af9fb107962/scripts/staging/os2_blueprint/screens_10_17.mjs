// SPEC FILE #3, part 2 of the seventeen screens — Executive Reports .. Voice, plus the three
// explicit design principles. 32 requirements, scored against PRODUCTION.
//
// THE ONE RULE THIS FILE ENFORCES: a requirement is MET only when the FOUNDER CAN SEE IT.
// This spec is a description of a screen, so a number that exists, is fresh, is correct and is
// rendered nowhere is MISSING however well the backend works. Production computes an autonomous
// company every night and displays almost none of it, so every check below has a FRONTEND half
// measured from the repository and a DATABASE half measured from production, and neither half
// alone can carry a verdict.
//
// The five defect classes that made row #2's scorer wrong, and what each one costs here:
//
//   1. THE ONLY READER IS THE WRITER. Reader counts come from ui_closure.mjs's UI_READERS(), which
//      excludes any routine whose body WRITES the object and collapses pg_proc overloads
//      (fn_agent_context has two rows on production and inflated every count it appeared in). A
//      view that merely names a table is not a reader unless a reachable routine names the VIEW.
//   2. POPULATION STANDING IN FOR DELIVERY. Row counts never decide a verdict on their own. Every
//      check pairs "how many rows exist" with "which rendered component puts them on screen", and
//      the evidence prints both numbers so the gap between them is visible rather than implied.
//   3. ONE ROW SCORES A WHOLE MECHANISM. Where the requirement says EVERY (every simulation
//      carries a confidence, every recommend_against carries alternatives) the check is a per-row
//      universal — count of rows FAILING the property must be zero — never a global count > 0.
//   4. SATISFIABLE BY FLIPPING A FLAG. No check anywhere below can be turned green by setting a
//      boolean column; every one of them requires either a rendered control in src/ or a row that
//      only the mechanism itself can produce.
//   5. EVIDENCE THAT DOES NOT COMPUTE THE VERDICT. Every evidence string is measured over the same
//      population as the boolean: the frontend numbers come from the same regex scan that decides
//      the frontend half, the database numbers from the same query shape that decides the other.
//
// THE FRONTEND IS MEASURED, NOT ASSERTED. Everything before the first `await req` is a scan of
// src/ and supabase/functions/: component bodies are split out of OsxShell.tsx by their top-level
// `function Name(` markers, so "is this rendered" is answered against the component that would
// render it rather than against the file as a whole. Two consequences worth stating:
//   * A key that no component names cannot be on screen: OsxShell's bespoke module components
//     destructure the response by key (StrategyApp reads d.risks, d.market_intel, …), so anything
//     the routine returns under a key nobody names is dropped before paint. Only the generic
//     Workspace fallback renders whatever arrives.
//   * A regex on the whole file would score the customer portal's microphone as the founder's
//     voice input, so the OS surface (src/components/osx + the /os route + osClient) is scanned
//     separately from src/ as a whole, and both numbers are printed.
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { closure, UI_READS, UI_READ_NAMES, UI_EMITS, UI_EMIT_NAMES, ALL_READS, sqlArr } from './ui_closure.mjs';

export const EXPECTED = 32;
export const expected = 32;   // both spellings: the runner's contract was renamed mid-flight
export const label = 'screens 10-17 (Executive Reports .. Voice) + design principles';

const S = 'screens-10-17';

const walk = (dir, out = []) => {
  if (!existsSync(dir)) return out;
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (['.ts', '.tsx'].includes(extname(p))) out.push(p);
  }
  return out;
};
const read = (p) => { try { return readFileSync(p, 'utf8'); } catch { return ''; } };
const hits = (txt, re) => (String(txt).match(new RegExp(re.source, re.flags.includes('g') ? re.flags : re.flags + 'g')) || []).length;
const lineOf = (txt, re) => { const m = String(txt).match(re); return m && m.index != null ? String(txt).slice(0, m.index).split('\n').length : 0; };

// Top-level component bodies of a .tsx file, in source order. Everything in OsxShell.tsx is a
// top-level `function Name(` at column 0, so this is exact for that file and harmless elsewhere.
function components(text) {
  const marks = [...text.matchAll(/^(?:export\s+default\s+)?function\s+([A-Za-z0-9_]+)\s*\(/gm)];
  return marks.map((m, i) => ({
    name: m[1],
    line: text.slice(0, m.index).split('\n').length,
    body: text.slice(m.index, i + 1 < marks.length ? marks[i + 1].index : text.length),
  }));
}

export default async function ({ req, one, ROOT }) {
  const root = ROOT || fileURLToPath(new URL('../../../', import.meta.url));
  // The UI closure — which routines a logged-in founder can cause to run — is computed once per
  // process by ui_closure.mjs and memoised, so asking for it here costs nothing if another section
  // already did.
  const C = await closure(one);

  // ---- FRONTEND SCAN -------------------------------------------------------------------------
  const SHELLP = join(root, 'src', 'components', 'osx', 'OsxShell.tsx');
  const shell = read(SHELLP);
  const comps = components(shell);
  const body = (n) => (comps.find((c) => c.name === n) || { body: '' }).body;
  const osFiles = walk(join(root, 'src', 'components', 'osx'))
    .concat(walk(join(root, 'src', 'app')).filter((p) => /[\\/]os[\\/]/.test(p)))
    .concat([join(root, 'src', 'lib', 'osClient.ts')]);
  const osSrc = osFiles.map(read).join('\n');           // what the FOUNDER's console is made of
  const allSrc = walk(join(root, 'src')).map(read).join('\n');   // every surface in the product
  const osApiSrc = read(join(root, 'supabase', 'functions', 'os_api', 'index.ts'));
  const reportBodySrc = read(join(root, 'supabase', 'functions', 'report_body', 'index.ts'));
  // Every action os_api will route, from its own classification table. An action absent from it is
  // refused at runtime, so this list is exactly what the browser can ask for.
  const actions = [...osApiSrc.matchAll(/([A-Za-z0-9_]+|'[A-Za-z0-9_.]+')\s*:\s*'(?:read_only|mutating|mode_control)'/g)]
    .map((m) => m[1].replace(/'/g, ''));
  const moduleCount = hits(shell.slice(shell.indexOf('const MODULES'), shell.indexOf('const PIPELINE')), /\{\s*id:\s*'/g);

  // ---- SQL helpers ---------------------------------------------------------------------------
  const T = (s) => `'${String(s).replace(/'/g, "''")}'`;
  const B = (v) => (v ? 'true' : 'false');
  const N = (t, w = 'true') => `(select count(*) from public.${t} where ${w})`;
  // Readers of an object, restricted to the browser closure, with the object's own WRITERS removed
  // and pg_proc overloads collapsed — the two exclusions row #2 learned the hard way.
  const UIR = (t) => UI_READS(C, t);
  const UIN = (t) => UI_READ_NAMES(C, t);
  // "Is anything the browser can run even capable of emitting this?", asked separately from "is any
  // of it on screen", because reachability is not delivery.
  const EMITS = (rx) => UI_EMITS(C, `'${rx}'`);
  const EMIT_NAMES = (rx) => UI_EMIT_NAMES(C, `'${rx}'`);
  const EMITS_BOTH = (rx1, rx2) => `(select count(distinct p.proname) from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind in ('f','p')
        and p.proname = any(${C.UI})
        and pg_get_functiondef(p.oid) ~* '${rx1}' and pg_get_functiondef(p.oid) ~* '${rx2}')`;
  // One NAMED reachable routine's body against a pattern: "does the surface the founder opens carry
  // this at all", asked of that surface rather than of the schema in general.
  const FN_MATCHES = (fn, rx) => `(select count(distinct p.proname) from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind in ('f','p')
        and p.proname='${fn}' and p.proname = any(${C.UI}) and pg_get_functiondef(p.oid) ~* '${rx}')`;
  const REACHABLE = (n) => C.fns.includes(n);
  const ARGS_OF = (n) => `coalesce((select pg_get_function_arguments(p.oid) from pg_proc p
      join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname='${n}' limit 1), '(absent)')`;

  // ================================================================================================
  // SCREEN 10 — EXECUTIVE REPORTS. "Never PDFs. Interactive. Click a number, drill down, see why,
  // see contributors, see recommendations, approve suggested actions."
  // ================================================================================================
  const repView = body('ReportViewer'), repDrawer = body('ReportViewerDrawer'), repApp = body('ReportsApp');
  const repSurface = repView + repDrawer;
  // Controls bound to the report's CONTENT, with the document actions removed: a Print button is
  // what a document offers, not what makes a report interactive.
  const repClicks = hits(repSurface, /onClick=/g);
  const repDocClicks = hits(repSurface, /onClick=\{printIt\}/g);
  const repContentClicks = repClicks - repDocClicks;
  const repFlattened = hits(repSurface, /\{rep\.body\}/g);
  const repPdfPaths = hits(repSurface, /Save as PDF|w\.print\(/g) + hits(osApiSrc, /make_pdf|report_pdf/g);
  // report_body is the ONLY non-PDF report reader the browser has. Which store does it serve?
  const bodyServesExec = /exec_reports/.test(reportBodySrc) ? 1 : 0;
  const bodyServesBoard = /board_reports/.test(reportBodySrc) ? 1 : 0;

  await req(S, 'exec-reports-interactive-not-pdf', 'Executive reports are interactive, never PDFs',
    `select coalesce(${B(repContentClicks > 0 && bodyServesExec === 1)}
       and ${N('exec_reports')} > 0, false)`,
    `select ${T(`ui: ReportViewer has ${repContentClicks} control(s) on report content (${repDocClicks} print/PDF), ` +
      `body rendered as preformatted text ${repFlattened}x, ${repPdfPaths} PDF path(s); report_body serves ` +
      `board_reports=${bodyServesBoard} exec_reports=${bodyServesExec}`)}
       || ' | db: ' || (select count(*) from public.exec_reports
            where jsonb_typeof(findings) in ('object','array'))
       || ' of ' || ${N('exec_reports')} || ' exec_reports carry structured findings; browser-reachable routines naming exec_reports: '
       || ${EMIT_NAMES('\\yexec_reports\\y')}`);

  // "Click a number → why it moved and who contributed." Two halves: a clickable figure, and a
  // backend that can answer for a figure. The figures exist (board_reports.kpis is a jsonb object
  // rendered as tiles); nothing binds a click to them and no reachable routine takes a metric.
  const kpiBlock = (repView.match(/rep\.kpis[\s\S]{0,800}/) || [''])[0];
  const kpiClickable = hits(kpiBlock, /onClick=/g);
  const drillActions = actions.filter((a) => /drill|contribut|explain|why/i.test(a)).length;
  const METRIC_ARG = `(select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.proname = any(${C.UI})
        and pg_get_function_arguments(p.oid) ~* '(metric|figure|kpi|measure|contribut)')`;
  await req(S, 'exec-reports-drilldown', 'Clicking a number in a report drills into why it moved and who contributed',
    `select coalesce(${B(kpiClickable > 0 && drillActions > 0)} and ${METRIC_ARG} > 0, false)`,
    `select ${T(`ui: ${kpiClickable} clickable figure(s) in the report KPI block, ${drillActions} drill-down action(s) ` +
      `among os_api's ${actions.length} routable actions`)}
       || ' | db: ' || (select count(*) from public.board_reports where jsonb_typeof(kpis)='object')
       || ' report(s) carry a KPI object, ' || ${METRIC_ARG} || ' reachable routine(s) take a metric argument'`);

  const repApproveControls = hits(repSurface + repApp, /Approve/g);
  const REC_ROWS = `(select count(*) from public.exec_reports
      where recommendations is not null and jsonb_typeof(recommendations) in ('object','array')
        and recommendations::text not in ('[]','{}'))`;
  const REC_APPROVALS = `(select count(*) from public.agent_actions
      where target_table in ('exec_reports','board_reports') or kind ~* 'report_recommend')`;
  await req(S, 'exec-reports-recommendations-approvable', 'Recommended actions can be approved from inside the report',
    `select coalesce(${B(repApproveControls > 0)} and ${REC_APPROVALS} > 0, false)`,
    `select ${T(`ui: ${repApproveControls} approve control(s) on the report surface`)}
       || ' | db: ' || ${REC_ROWS} || ' of ' || ${N('exec_reports')} || ' exec_reports carry recommendations, '
       || ${REC_APPROVALS} || ' approval row(s) reference a report'`);

  // ================================================================================================
  // SCREEN 11 — INTELLIGENCE CENTER. "One screen. AI tells you: top risks, top opportunities,
  // predictions, forecast, competitors, supplier health, customer behaviour, AI spending, growth
  // probability."
  //
  // Nine requirements, one screen. Each is scored on ITS OWN datum — a per-item DATABASE leg (is
  // this populated and can anything the browser runs emit it) and a per-item FRONTEND leg (which
  // component renders it) — plus one shared property that the requirement's own wording carries:
  // the surface has to be an INTELLIGENCE surface. The threshold is stated once here and applied
  // identically to all nine: the component that renders the item must carry at least four of the
  // nine. Below that it is a functional module — Finance showing a cash forecast, Strategy showing
  // a risk list — which is exactly the case the spec's "one screen" wording excludes, and which is
  // what production has today. It is a satisfiable bar: building the screen the spec describes
  // passes all nine at once, and building half of it passes that half.
  const NINE = {
    risks:              /\brisks\b/,
    opportunities:      /opportunit/i,
    predictions:        /\bpredict/i,
    forecast:           /forecast/i,
    competitors:        /\bcompetitors?\b/i,
    supplier_health:    /supplier_health|supply_health|fill_rate|coverage_gaps/i,
    customer_behavior:  /customer_health|customer_score|customer_ltv|customer_preference|churn/i,
    ai_spending:        /ai_cost|ai_spend|llm_cost|cost_aed/i,
    growth_probability: /probabilit/i,
  };
  const CO_LOC = 4;
  const rendering = comps.filter((c) => /<[A-Za-z]/.test(c.body) && /return/.test(c.body));
  const surfaces = rendering.map((c) => ({ name: c.name, line: c.line,
    items: Object.keys(NINE).filter((k) => NINE[k].test(c.body)) }));
  const surfaceFor = (k) => surfaces.filter((s) => s.items.includes(k))
    .sort((a, b) => b.items.length - a.items.length)[0] || null;
  const intel = async (id, name, key, dbBool, dbEv) => {
    const s = surfaceFor(key);
    const co = s ? s.items.length : 0;
    await req(S, id, name,
      `select coalesce(${B(!!s && co >= CO_LOC)} and (${dbBool}), false)`,
      `select ${T(`ui: ${s ? `${s.name}() OsxShell.tsx:${s.line} renders it and carries ${co} of the 9 ` +
        `intelligence items (${s.items.join('+')}), threshold ${CO_LOC}`
        : `no rendered component names it (0 of ${rendering.length} components)`}`)} || ' | db: ' || (${dbEv})`);
  };

  // Risks: two stores. strategy_risks is what the rendered Strategy module reads; risk_register is
  // the register the rest of the company keeps. Either satisfies "shows top risks" — both numbers
  // are printed so a rendered-but-disconnected risk list is visible as such.
  await intel('intel-top-risks', 'Intelligence Center shows top risks', 'risks',
    `(${N('strategy_risks')} > 0 and ${UIR('strategy_risks')} > 0)
      or (${N('risk_register')} > 0 and ${UIR('risk_register')} > 0)`,
    `${N('strategy_risks')} || ' strategy_risks row(s) read by ' || ${UIN('strategy_risks')}
      || '; ' || ${N('risk_register')} || ' risk_register row(s) read by ' || ${UIN('risk_register')}`);

  await intel('intel-top-opportunities', 'Intelligence Center shows top opportunities', 'opportunities',
    `${N('opportunity', "status='open'")} > 0 and ${UIR('opportunity')} > 0`,
    `${N('opportunity', "status='open'")} || ' open opportunit(ies) of ' || ${N('opportunity')}
      || ', newest ' || coalesce((select max(created_at)::date::text from public.opportunity), 'never')
      || ', browser-reachable reader(s): ' || ${UIN('opportunity')}`);

  await intel('intel-predictions', 'Intelligence Center shows predictions', 'predictions',
    `${N('simulations')} > 0 and ${UIR('simulations')} > 0`,
    `${N('simulations')} || ' simulation(s) read by ' || ${UIN('simulations')}
      || '; ' || ${N('scenario_library')} || ' scenario(s) read by ' || ${UIN('scenario_library')}`);

  await intel('intel-forecast', 'Intelligence Center shows a forecast', 'forecast',
    `${EMITS('\\yforecast\\y')} > 0`,
    `${EMITS('\\yforecast\\y')} || ' browser-reachable routine(s)/view(s) emit a forecast: '
      || ${EMIT_NAMES('\\yforecast\\y')}`);

  // Competitors: competitor (27 rows) is reachable through strategy_kpis, but the Strategy module
  // renders market_intel — a table with zero rows — so the reachable competitor state has no
  // rendered key to arrive in. Both counts are the evidence.
  await intel('intel-competitors', 'Intelligence Center shows competitor state', 'competitors',
    `${N('competitor')} > 0 and ${UIR('competitor')} > 0`,
    `${N('competitor')} || ' competitor(s) read by ' || ${UIN('competitor')}
      || '; competitive_position ' || ${N('competitive_position')} || ' row(s) read by ' || ${UIN('competitive_position')}
      || '; the key the Strategy module renders (market_intel) holds ' || ${N('market_intel')} || ' row(s)'`);

  await intel('intel-supplier-health', 'Intelligence Center shows supplier health', 'supplier_health',
    `${UIR('supplier_health')} > 0 or ${UIR('supply_health_snapshots')} > 0`,
    `'supplier_health view read by ' || ${UIN('supplier_health')} || ', supply_health_snapshots ('
      || ${N('supply_health_snapshots')} || ' row(s), latest period_end '
      || coalesce((select max(period_end)::text from public.supply_health_snapshots), 'never')
      || ') read by ' || ${UIN('supply_health_snapshots')}`);

  await intel('intel-customer-behavior', 'Intelligence Center shows customer behaviour', 'customer_behavior',
    `${UIR('customer_health')} > 0 or ${UIR('customer_preference')} > 0`,
    `'customer_health read by ' || ${UIN('customer_health')} || '; customer_preference holds '
      || ${N('customer_preference')} || ' row(s) and customer_score ' || ${N('customer_score')}
      || ' row(s), read by ' || ${UIN('customer_score')}`);

  await intel('intel-ai-spending', 'Intelligence Center shows AI spending', 'ai_spending',
    `${UIR('ai_cost_log')} > 0 and ${N('ai_cost_log', "occurred_at > now() - interval '30 days'")} > 0`,
    `${N('ai_cost_log')} || ' ai_cost_log row(s), ' || ${N('ai_cost_log', "occurred_at > now() - interval '30 days'")}
      || ' in the last 30 days, read by ' || ${UIN('ai_cost_log')}
      || '; llm_calls ' || ${N('llm_calls')} || ' row(s) read by ' || ${UIN('llm_calls')}`);

  // A probability, as opposed to a point estimate: nothing reachable computes one, and the index
  // that comes closest (company_index) has no browser-reachable reader at all.
  await intel('intel-growth-probability', 'Intelligence Center shows a growth probability', 'growth_probability',
    `${EMITS('probabilit')} > 0 and ${UIR('company_index')} > 0`,
    `${EMITS('probabilit')} || ' browser-reachable routine(s) mention a probability (' || ${EMIT_NAMES('probabilit')}
      || '); company_index holds ' || ${N('company_index')} || ' measurement(s), newest '
      || coalesce((select max(measured_on)::text from public.company_index), 'never')
      || ', read by ' || ${UIN('company_index')}`);

  // ================================================================================================
  // SCREEN 12 — COMPANY MEMORY. One search box over everything the company knows, and four named
  // questions that are all "filter the memory by a subject or a period", which is the capability
  // the console does not have: fn_os_search takes a string and looks in three operational tables.
  // ================================================================================================
  const CORPORA = ['kb_chunks', 'institutional_memory', 'org_memory', 'agent_memory', 'decision_log',
                   'documents', 'customers', 'inquiries', 'leads'];
  const SEARCH_DEF = `(select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind in ('f','p') and p.proname='fn_os_search' limit 1)`;
  const SEARCH_SPAN = `(select count(*) from unnest(${sqlArr(CORPORA)}) c(n) where ${SEARCH_DEF} ~* ('\\y'||c.n||'\\y'))`;
  const SEARCH_NAMES = `coalesce((select string_agg(c.n, ',') from unnest(${sqlArr(CORPORA)}) c(n)
      where ${SEARCH_DEF} ~* ('\\y'||c.n||'\\y')), 'none')`;
  const searchCallSites = hits(allSrc, /osApi\(\s*['"]search['"]/g);
  await req(S, 'company-memory-search-anything', 'One search box that searches everything the company knows',
    `select coalesce(${B(searchCallSites > 0)} and ${SEARCH_SPAN} >= 6, false)`,
    `select ${T(`ui: ${searchCallSites} reference(s) to the search action anywhere in src/`)}
       || ' | db: fn_os_search spans ' || ${SEARCH_SPAN} || ' of ' || ${CORPORA.length} || ' corpora (' || ${SEARCH_NAMES}
       || '); unsearched: kb_chunks ' || ${N('kb_chunks')} || ', institutional_memory ' || ${N('institutional_memory')}
       || ', org_memory ' || ${N('org_memory')} || ', agent_memory ' || ${N('agent_memory')} || ' row(s)'`);

  // "Show every decision about Marketing" needs a reader that takes a subject. fn_ws_exec returns
  // the last ten by recency and takes no arguments, so the question cannot be asked at all.
  const DL_PARAM_READERS = `(select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind in ('f','p') and p.proname = any(${C.UI})
        and pg_get_functiondef(p.oid) ~* '\\ydecision_log\\y'
        and pg_get_function_arguments(p.oid) <> '')`;
  const uiTopicControl = hits(osSrc, /(topic|subject)[^\n]{0,140}(osApi|osOps)\(/gi);
  await req(S, 'company-memory-decisions-by-topic', "'Show every decision about Marketing' returns the decision history for a topic",
    `select coalesce(${B(uiTopicControl > 0)} and ${DL_PARAM_READERS} > 0, false)`,
    `select ${T(`ui: ${uiTopicControl} control(s) pass a topic or subject to a query`)}
       || ' | db: ' || ${N('decision_log')} || ' decision(s) across '
       || (select count(distinct kind) from public.decision_log) || ' kind(s) and '
       || (select count(distinct actor) from public.decision_log) || ' actor(s); browser-reachable readers '
       || ${UIN('decision_log')} || ', of which ' || ${DL_PARAM_READERS} || ' take any argument'`);

  const SUP360_RATIONALE = FN_MATCHES('fn_ws_supplier_360', '(reject|decision_record|decision_trace)');
  const uiRejectionReason = hits(osSrc, /rejection_reason|reject_reason|why_rejected/gi);
  await req(S, 'company-memory-why-rejected', "'Why did we reject Supplier X?' returns the reasoning for a past decision",
    `select coalesce(${B(uiRejectionReason > 0)}
       and (${UIR('decision_record')} > 0 or ${UIR('decision_trace')} > 0)
       and ${SUP360_RATIONALE} > 0, false)`,
    `select ${T(`ui: ${uiRejectionReason} rendered rejection-reason field(s) in the OS surface`)}
       || ' | db: decision_record ' || ${N('decision_record')} || ' row(s) read by ' || ${UIN('decision_record')}
       || ', decision_trace ' || ${N('decision_trace')} || ' row(s) read by ' || ${UIN('decision_trace')}
       || '; the reachable supplier view carries rationale: ' || ${SUP360_RATIONALE}`);

  // "When did AI change pricing?" — undo_log is the change history (3,810 rows, trg_undo_capture)
  // and os_audit_log is the action history. The founder's Audit log renders the second with dates;
  // neither can be asked about a SUBJECT such as pricing_config.
  const ACTIVITY_CHANGE = FN_MATCHES('fn_entity_activity', '\\y(undo_log|os_audit_log)\\y');
  const ACTIVITY_CONFIG = FN_MATCHES('fn_entity_activity', '\\y(pricing_config|model_policy|prompts)\\y');
  const auditComp = body('AuditLog');
  const uiChangeDates = hits(auditComp, /toLocaleString\(\)|r\.at/g);
  const uiChangeSubjectFilter = hits(auditComp, /<input|<select|onChange=/gi);
  await req(S, 'company-memory-when-changed', "'When did AI change pricing?' returns a change history with dates",
    `select coalesce(${B(uiChangeDates > 0 && uiChangeSubjectFilter > 0)}
       and ${UIR('undo_log')} > 0 and ${ACTIVITY_CONFIG} > 0, false)`,
    `select ${T(`ui: AuditLog renders ${uiChangeDates} dated field(s) and ${uiChangeSubjectFilter} subject filter control(s)`)}
       || ' | db: undo_log ' || ${N('undo_log')} || ' change(s) over '
       || (select count(distinct table_name) from public.undo_log) || ' table(s), read by ' || ${UIN('undo_log')}
       || '; os_audit_log ' || ${N('os_audit_log')} || ' row(s) read by ' || ${UIN('os_audit_log')}
       || '; fn_entity_activity reads a change history: ' || ${ACTIVITY_CHANGE}
       || ', covers config subjects: ' || ${ACTIVITY_CONFIG}`);

  const IM_PERIOD = EMITS_BOTH('\\yinstitutional_memory\\y', '\\yoccurred_at\\y');
  const uiLessons = hits(osSrc, /institutional_memory|\blessons?\b/gi);
  await req(S, 'company-memory-lessons-by-period', "'Find lessons from February' returns lessons scoped to a time period",
    `select coalesce(${B(uiLessons > 0)} and ${UIR('institutional_memory')} > 0 and ${IM_PERIOD} > 0, false)`,
    `select ${T(`ui: ${uiLessons} lesson field(s) rendered in the OS surface`)}
       || ' | db: ' || ${N('institutional_memory')} || ' lesson(s) spanning '
       || coalesce((select min(occurred_at)::date::text from public.institutional_memory), 'n/a') || '..'
       || coalesce((select max(occurred_at)::date::text from public.institutional_memory), 'n/a')
       || ', browser-reachable readers ' || ${UIN('institutional_memory')}
       || ', of which ' || ${IM_PERIOD} || ' scope by occurred_at'`);

  // ================================================================================================
  // SCREEN 13 — COMMAND PALETTE. The one screen in this half that production actually built.
  // ================================================================================================
  const kHandlerLine = lineOf(shell, /\(\s*e\.metaKey\s*\|\|\s*e\.ctrlKey\s*\)[\s\S]{0,80}?['"]k['"]/i);
  const kToggles = hits(shell, /\(\s*e\.metaKey\s*\|\|\s*e\.ctrlKey\s*\)[\s\S]{0,120}?setPaletteOpen/gi);
  const kListener = hits(shell, /addEventListener\('keydown'/g);
  const dialogLine = lineOf(shell, /<CommandDialog\s+open=\{paletteOpen\}/);
  await req(S, 'command-palette-ctrl-k', 'Ctrl+K opens a command palette',
    `select ${B(kHandlerLine > 0 && kToggles > 0 && kListener > 0 && dialogLine > 0)}`,
    `select ${T(`ui: (meta||ctrl)+k handler at OsxShell.tsx:${kHandlerLine} toggles the palette ${kToggles}x, ` +
      `${kListener} window keydown listener(s), CommandDialog bound to that state at line ${dialogLine}`)}`);

  const palette = shell.slice(shell.indexOf('<CommandDialog'), shell.indexOf('</CommandDialog>') + 17);
  const paletteFromModules = /MODULES\.map/.test(palette) ? moduleCount : 0;
  const paletteItems = hits(palette, /<CommandItem/g);
  const paletteEntitySearch = hits(palette, /osApi|fn_os_search|['"]search['"]/gi);
  const VERBS = ['Approve', 'Restart AI', 'Forecast', 'Cash Flow'];
  const paletteVerbs = VERBS.filter((v) => new RegExp(v.replace(/ /g, '\\s*'), 'i').test(palette)).length;
  await req(S, 'command-palette-everything-searchable', 'Everything is searchable from the palette — navigation, entities and actions',
    `select coalesce(${B(paletteEntitySearch > 0 && paletteVerbs >= 3)}
       and ${N('customers')} + ${N('leads')} > 0, false)`,
    `select ${T(`ui: the palette lists ${paletteFromModules} module(s) plus ${paletteItems - (paletteFromModules ? 1 : 0)} ` +
      `fixed item(s); ${paletteEntitySearch} entity-search reference(s); ${paletteVerbs} of ${VERBS.length} spec verbs ` +
      `(${VERBS.join(', ')}) reachable from it`)}
       || ' | db: ' || ${N('customers')} || ' customer(s) and ' || ${N('leads')}
       || ' supplier(s) exist to be found, fn_os_search is ' || case when ${B(REACHABLE('fn_os_search'))}
            then 'browser-reachable' else 'not browser-reachable' end`);

  // ================================================================================================
  // SCREEN 14 — NOTIFICATIONS. Four named tiers with counts, and the share the AI handled alone.
  // ================================================================================================
  const bell = body('NotificationsBell');
  const TIERS = ['Critical', 'Important', 'Suggested', 'Completed Today'];
  const tiersRendered = TIERS.filter((t) => new RegExp(t.replace(/ /g, '\\s*'), 'i').test(bell)).length;
  const tierCounts = hits(bell, /\bcount\b/g);
  const SEV_COL = `(select count(*) from information_schema.columns
      where table_schema='public' and table_name='notifications' and column_name in ('severity','priority','level','tier'))`;
  // A tiered grouping means the routine carries the tier NAME beside the notification store, not
  // merely a severity column somewhere in the schema.
  const TIER_EMITTER = EMITS_BOTH("''critical''", '\\y(notifications|founder_alerts)\\y');
  await req(S, 'notifications-grouped-four-tiers', 'Notifications are grouped into Critical / Important / Suggested / Completed Today with counts',
    `select coalesce(${B(tiersRendered === 4 && tierCounts > 0)} and ${TIER_EMITTER} > 0, false)`,
    `select ${T(`ui: NotificationsBell renders ${tiersRendered} of 4 named tiers and ${tierCounts} tier count(s)`)}
       || ' | db: notifications holds ' || ${N('notifications')} || ' row(s) with ' || ${SEV_COL}
       || ' severity column(s); founder_alerts levels: '
       || coalesce((select string_agg(distinct level, '/') from public.founder_alerts), 'none')
       || '; ' || ${TIER_EMITTER} || ' browser-reachable routine(s) emit a tiered grouping'`);

  const uiAutoShare = hits(osSrc, /auto[_ ]?(handled|resolved|cleared)|handled\s*\d+\s*%/gi);
  const AUTO_SHARE = `(select round(100.0 * count(*) filter (where coalesce(escalated,false) = false)
      / greatest(count(*),1)) from public.agent_actions where created_at > now() - interval '30 days')`;
  const SHARE_EMITTER = EMITS('\\y(auto_cleared_24h|auto_handled|auto_resolved|auto_share)\\y');
  await req(S, 'notifications-auto-handled-share', 'The share the AI handled without the founder is stated',
    `select coalesce(${B(uiAutoShare > 0)} and ${SHARE_EMITTER} > 0, false)`,
    `select ${T(`ui: ${uiAutoShare} rendered auto-handled share(s) in the OS surface`)}
       || ' | db: ' || ${AUTO_SHARE} || '% of ' || ${N('agent_actions', "created_at > now() - interval '30 days'")}
       || ' agent actions in 30d were not escalated, ' || ${SHARE_EMITTER}
       || ' browser-reachable routine(s) emit that share (' || ${EMIT_NAMES('\\yauto_cleared_24h\\y')} || ')'`);

  // ================================================================================================
  // SCREEN 15 — INTERACTIVE COMPANY MAP. graph_nodes/graph_edges are rebuilt nightly by
  // graph_rebuild_daily and read by nothing anywhere — the canonical shape this row hunts.
  // ================================================================================================
  const uiMapSurface = hits(osSrc, /graph_nodes|graph_edges|company[_ ]?map|CompanyMap/gi);
  const MAP_CLASSES = `(select count(*) from (values ('departments','department'),('processes','(process|workflow)'),
      ('employees','(employee|agent)'),('customers','customer'),('suppliers','(supplier|lead)'),
      ('knowledge','(knowledge|kb)')) c(cls,rx)
      where exists (select 1 from public.graph_nodes g where g.kind ~* c.rx))`;
  await req(S, 'company-map-entities', 'A map places departments, processes, employees, customers, suppliers and knowledge on one connected canvas',
    `select coalesce(${B(uiMapSurface > 0)} and ${MAP_CLASSES} = 6 and ${UIR('graph_nodes')} > 0, false)`,
    `select ${T(`ui: ${uiMapSurface} map surface(s) in the OS console`)}
       || ' | db: graph_nodes ' || ${N('graph_nodes')} || ' node(s) of kind '
       || coalesce((select string_agg(distinct kind, '/') from public.graph_nodes), 'none')
       || ' covering ' || ${MAP_CLASSES} || ' of the 6 named classes, ' || ${N('graph_edges')}
       || ' edge(s), rebuilt ' || coalesce((select max(updated_at)::date::text from public.graph_nodes), 'never')
       || ', browser-reachable readers: ' || ${UIN('graph_nodes')}`);

  const mapModules = hits(shell.slice(shell.indexOf('const MODULES'), shell.indexOf('const PIPELINE')), /map/gi);
  const nodeField = read(join(root, 'src', 'components', 'NodeField.tsx'));
  const canvasZoom = hits(nodeField, /onWheel|\.scale|zoom|transform:\s*`?scale/gi);
  const canvasInOs = hits(osSrc, /NodeField/g);
  await req(S, 'company-map-click-zoom-explore', 'The map supports click, zoom and free exploration',
    `select ${B(mapModules > 0 && canvasInOs > 0 && canvasZoom > 0)}`,
    `select ${T(`ui: ${mapModules} map module(s) among the ${moduleCount} sidebar modules; the only canvas-ish ` +
      `component (NodeField.tsx) carries ${canvasZoom} zoom/pan handler(s) and is referenced ${canvasInOs}x ` +
      `from the OS console`)}`);

  // ================================================================================================
  // SCREEN 16 — "WHAT IF?". fn_what_if and fn_simulate both exist and both are outside the browser
  // closure: os_api classifies 60-odd actions and none of them is a simulation.
  // ================================================================================================
  const simActions = actions.filter((a) => /simulat|what_?if|scenario/i.test(a)).length;
  const uiScenarioInput = hits(osSrc, /what[- ]?if|scenario/gi);
  await req(S, 'what-if-scenario-input', 'A natural-language what-if scenario can be entered',
    `select coalesce(${B(simActions > 0 && uiScenarioInput > 0)}
       and exists (select 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
                   where ns.nspname='public' and p.proname in ('fn_what_if','fn_simulate')), false)`,
    `select ${T(`ui: ${simActions} simulation action(s) among os_api's ${actions.length} routable actions, ` +
      `${uiScenarioInput} scenario input(s) in the OS console`)}
       || ' | db: fn_what_if(' || ${ARGS_OF('fn_what_if')} || '), fn_simulate(' || ${ARGS_OF('fn_simulate')} || ')'
       || '; browser-reachable: ' || ${B(REACHABLE('fn_what_if') || REACHABLE('fn_simulate'))}`);

  // EVERY simulation, not one of them: a per-row universal over the whole table, non-vacuous
  // because the population is asserted non-empty on the same line.
  const SIM_KEY = (rx) => `exists (select 1 from jsonb_object_keys(s.result) k where k ~* '${rx}')`;
  const SIM_DELTAS = `(select count(*) from public.simulations s where jsonb_typeof(s.result)='object'
      and ${SIM_KEY('revenue')} and ${SIM_KEY('lead')} and ${SIM_KEY('profit|margin|net_income')})`;
  await req(S, 'what-if-projected-deltas', 'The simulation returns projected deltas on revenue, leads and profit',
    `select coalesce(${SIM_DELTAS} = ${N('simulations')} and ${N('simulations')} > 0, false)`,
    `select ${SIM_DELTAS} || ' of ' || ${N('simulations')}
       || ' simulation(s) carry revenue+leads+profit keys; keys present: '
       || coalesce((select string_agg(distinct k, ',') from public.simulations s2,
             lateral jsonb_object_keys(case when jsonb_typeof(s2.result)='object' then s2.result else '{}'::jsonb end) k
             where k ~* '(revenue|lead|profit|margin)'), 'none')`);

  const SIM_CONF = `(select count(*) from public.simulations s where jsonb_typeof(s.result)='object'
      and (s.result ? 'confidence') and jsonb_typeof(s.result->'confidence') <> 'null')`;
  await req(S, 'what-if-confidence-score', 'The simulation returns a confidence score',
    `select coalesce(${SIM_CONF} = ${N('simulations')} and ${N('simulations')} > 0, false)`,
    `select ${SIM_CONF} || ' of ' || ${N('simulations')} || ' simulation(s) carry a non-null confidence; '
       || (select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
            where ns.nspname='public' and p.prokind in ('f','p') and p.proname in ('fn_what_if','fn_simulate')
              and pg_get_functiondef(p.oid) ~* '''confidence''')
       || ' of the 2 simulators emit a confidence key'`);

  const SIM_APPROVALS = `(select count(*) from public.agent_actions
      where target_table='simulations' or kind ~* '(simulat|what_?if|scenario)')`;
  const uiSimApprove = hits(osSrc, /simulat[^\n]{0,160}(Approve|approve)/g);
  await req(S, 'what-if-approve-from-simulation', 'The founder can approve the simulated action directly from the result',
    `select coalesce(${B(uiSimApprove > 0 && simActions > 0)} and ${SIM_APPROVALS} > 0, false)`,
    `select ${T(`ui: ${uiSimApprove} approve control(s) bound to a simulation, ${simActions} simulation action(s) in os_api`)}
       || ' | db: ' || ${SIM_APPROVALS} || ' approval row(s) reference a simulation, of '
       || ${N('agent_actions')} || ' agent actions'`);

  // ================================================================================================
  // SCREEN 17 — VOICE. The microphone exists in this product — in the CUSTOMER portal. Scanning
  // src/ as a whole would score that as the founder's voice input, so both numbers are printed.
  // ================================================================================================
  const VOICE_IN = /SpeechRecognition|getUserMedia|MediaRecorder/;
  const osVoiceIn = hits(osSrc, VOICE_IN);
  const allVoiceIn = hits(allSrc, VOICE_IN);
  const osTranscribe = hits(osSrc, /transcribe/gi);
  const allTranscribe = hits(allSrc, /transcribe/gi);
  const transcribeFn = existsSync(join(root, 'supabase', 'functions', 'transcribe')) ? 1 : 0;
  await req(S, 'voice-input', 'The founder can speak to the OS',
    `select ${B(osVoiceIn > 0 && osTranscribe > 0 && transcribeFn > 0)}`,
    `select ${T(`ui: ${osVoiceIn} microphone capture site(s) and ${osTranscribe} transcribe reference(s) in the OS ` +
      `console, versus ${allVoiceIn} and ${allTranscribe} across all of src/ (the customer portal); ` +
      `${transcribeFn} transcribe edge function deployed`)}`);

  const osTts = hits(osSrc, /speechSynthesis|SpeechSynthesisUtterance|text_to_speech|\btts\b/gi);
  const uiBriefRendered = hits(osSrc, /founder_alerts|morning[_ ]brief|overnight/gi);
  const BRIEF_ROW = `(select coalesce(detail::text,'') || ' ' || coalesce(event,'') from public.founder_alerts
      where event ~* 'brief' or detail::text ~* 'brief' order by created_at desc limit 1)`;
  const BRIEF_FIGS = `(select count(*) from (values ('rfqs','\\yrfq'),('suppliers','\\ysupplier'),
      ('revenue','\\yrevenue\\y'),('target','\\y(target|goal|variance)'),('cost','\\y(cost|spend)'),
      ('approvals','\\yapprov')) f(k,rx) where coalesce(${BRIEF_ROW},'') ~* f.rx)`;
  await req(S, 'voice-morning-brief-spoken', "'Good morning' returns a spoken overnight brief with concrete numbers",
    `select coalesce(${B(osTts > 0 && uiBriefRendered > 0)} and ${BRIEF_FIGS} = 6, false)`,
    `select ${T(`ui: ${osTts} speech-output path(s) and ${uiBriefRendered} rendered founder-brief field(s) in the OS console`)}
       || ' | db: newest brief ' || coalesce((select max(created_at)::date::text from public.founder_alerts
             where event ~* 'brief' or detail::text ~* 'brief'), 'never')
       || ' carries ' || ${BRIEF_FIGS} || ' of the 6 named figures; founder_alerts holds '
       || ${N('founder_alerts')} || ' row(s), read by ' || ${UIN('founder_alerts')}`);

  // ================================================================================================
  // DESIGN PRINCIPLES (explicit). "Give the AI permission to disagree with you."
  // challenge_record holds 47 judgements with stance, reasoning, evidence and alternatives. Its
  // only routine is its writer; no view, no reachable reader, no hit in src/.
  // ================================================================================================
  const uiChallenge = hits(osSrc, /challenge_record|recommend_against|violates_principle/gi);
  const CHAL_AGAINST = N('challenge_record', "stance='recommend_against'");
  // prokind in ('f','p') is not decoration: pg_get_functiondef() raises on an aggregate, and
  // public.avg exists on this database — without the filter this check ERRORs, which would leave
  // the requirement unmeasured rather than answered.
  const CHAL_CALLERS = `(select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_challenge'
        and pg_get_functiondef(p.oid) ~* '\\yfn_challenge\\s*\\(')`;
  await req(S, 'ai-may-disagree', 'The AI may recommend AGAINST a founder instruction, with reasoning and evidence',
    `select coalesce(${B(uiChallenge > 0)} and ${UIR('challenge_record')} > 0 and ${CHAL_AGAINST} > 0, false)`,
    `select ${T(`ui: ${uiChallenge} rendered challenge field(s) in the OS console`)}
       || ' | db: ' || ${CHAL_AGAINST} || ' recommend_against of ' || ${N('challenge_record')}
       || ' challenge(s), newest ' || coalesce((select max(created_at)::date::text from public.challenge_record), 'never')
       || ', with reasoning on ' || ${N('challenge_record', "coalesce(reasoning,'') <> ''")}
       || ' and evidence on ' || ${N('challenge_record', "evidence is not null and evidence::text not in ('','[]','{}','null')")}
       || '; browser-reachable readers: ' || ${UIN('challenge_record')}
       || '; ' || ${CHAL_CALLERS} || ' routine(s) invoke fn_challenge'`);

  // EVERY disagreement carries alternatives (per-row universal), they are rendered, and they can be
  // answered — founder_response is the column that proves the loop closes.
  const uiAlternatives = hits(osSrc, /alternativ/gi);
  const CHAL_NO_ALT = N('challenge_record',
    "stance='recommend_against' and (alternatives is null or alternatives::text in ('','[]','{}','null'))");
  const RESPONSE_PATH = `(select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind in ('f','p') and p.proname = any(${C.UI})
        and pg_get_functiondef(p.oid) ~* '\\yfounder_response\\y')`;
  await req(S, 'ai-offers-alternatives', 'When it disagrees, the AI supplies lower-risk alternatives',
    `select coalesce(${B(uiAlternatives > 0)} and ${CHAL_NO_ALT} = 0 and ${CHAL_AGAINST} > 0
       and ${RESPONSE_PATH} > 0, false)`,
    `select ${T(`ui: ${uiAlternatives} rendered alternative(s) in the OS console`)}
       || ' | db: ' || ${CHAL_NO_ALT} || ' of ' || ${CHAL_AGAINST}
       || ' recommend_against row(s) lack alternatives; ' || ${N('challenge_record', 'responded_at is not null')}
       || ' of ' || ${N('challenge_record')} || ' have ever been answered, through '
       || ${RESPONSE_PATH} || ' browser-reachable response path(s)'`);

  // "Strategic decisions rather than operational tasks": the four strategic queues against the
  // operational approval queue the founder is actually shown.
  const STRATEGIC = ['evolution_proposal', 'challenge_record', 'opportunity', 'board_opinion'];
  const strategicRendered = STRATEGIC.filter((t) => new RegExp(t, 'i').test(osSrc)).length;
  const STRAT_REACHABLE = STRATEGIC.map((t) => `(case when ${UIR(t)} > 0 then 1 else 0 end)`).join(' + ');
  const STRAT_OPEN = `(${N('evolution_proposal', "status='proposed'")} + ${N('challenge_record', 'responded_at is null')}
      + ${N('opportunity', "status='open'")} + ${N('board_opinion')})`;
  const OPERATIONAL_PENDING = N('agent_actions', "status in ('pending','needs_review')");
  await req(S, 'strategic-not-operational', 'The OS presents strategic decisions rather than operational tasks',
    `select coalesce(${B(strategicRendered === STRATEGIC.length)} and (${STRAT_REACHABLE}) = ${STRATEGIC.length}
       and ${STRAT_OPEN} >= ${OPERATIONAL_PENDING}, false)`,
    `select ${T(`ui: ${strategicRendered} of ${STRATEGIC.length} strategic queues (${STRATEGIC.join(', ')}) ` +
      `are named anywhere in the OS console, which shows ${moduleCount} modules`)}
       || ' | db: ' || (${STRAT_REACHABLE}) || ' of ' || ${STRATEGIC.length}
       || ' strategic queues have a browser-reachable reader; ' || ${STRAT_OPEN}
       || ' strategic item(s) open versus ' || ${OPERATIONAL_PENDING} || ' operational approval(s) pending'`);
}
