// Sections 5-8 of the CUSTOMER PORTAL spec, scored against PRODUCTION.
//
//   5  Project Intelligence Workspace — the project entity that groups RFQs, and what it shows
//   6  3D Project Visualization       — the building model, floors, per-component status, drill-in
//   7  AI RFQ Creation                — natural language in, a complete structured RFQ out
//   8  RFQ Command Center             — reference, pipeline, responses, best match, liveness
//
// PRODUCTION HAS ZERO CUSTOMERS, ZERO INQUIRIES, ZERO QUOTES AND ZERO PROJECTS. Every "does the
// customer see X" question that counts customer rows reads 0 for all 26 requirements and measures
// nothing. So each check asks the three questions this row is about, separately, and its evidence
// names WHICH leg failed:
//
//   1. does the figure EXIST — a column, view, routine, or the line of the edge function emitting it?
//   2. does it reach a CUSTOMER-AUTHED payload (a customer-JWT endpoint, not a staff one)?
//   3. does a CUSTOMER SURFACE render it — the import closure of src/app/[locale]/me, which by
//      construction excludes the staff console (src/components/osx) and the supplier portal?
//
// THIS MODULE TAKES ONLY `req` FROM THE HARNESS and computes every frontend fact itself. Several
// agents write into this directory and the runner above it at the same time; a module that reads
// the repository through its own eyes keeps working when the runner is rewritten underneath it,
// and the two runner variants in this tree do not offer the same helper set.
//
// FIVE DEFECTS THIS FILE IS WRITTEN AGAINST, each of which the row #2 scorer actually shipped:
//
// A. THE ONLY READER IS THE WRITER. compliance_checklist is authored by category_reqs and read by
//    nobody; inquiry_answer_document is named only by the three fn_inquiry_answer_* routines that
//    WRITE it. Both writer sets are excluded BY NAME — the generic READERS() self-exclusion compares
//    a routine's name to a TABLE name and therefore never fires. count(DISTINCT proname) everywhere,
//    because pg_proc holds one row per OVERLOAD and a reader counted twice inflates its leg.
// B. POPULATION STANDING IN FOR DELIVERY. project_summary computes rfq_open for every project and
//    project_api returns it to a customer JWT; zero files under src/ name project_api. Computed,
//    put on the wire, rendered nowhere. Each "Project shows X" requirement is scored on its own
//    three-leg chain and prints all three, so a MISSING verdict says which leg broke instead of
//    collapsing five requirements into one screenshot.
// C. ONE ROW SCORES A WHOLE MECHANISM. Where survival of an extracted value depends on per-category
//    configuration, the check counts the CATEGORIES it holds for, not whether it works once.
// D. A CANVAS IS NOT A 3D MODEL. src/components/NodeField.tsx paints a decorative 2D canvas into the
//    layout wrapping /me, so "any <canvas> on the customer surface" would score the whole 3D section
//    MET. Every 3D check demands a WebGL context or a 3D dependency, and the evidence reports the 2D
//    canvas it deliberately did not count.
// E. NEVER WRITE A CHECK NO IMPLEMENTATION COULD SATISFY. Every MISSING verdict here is one edit
//    away: persist brief.quantity, persist brief.timeline, render matched_suppliers, populate
//    similarity, mount a projects view. None demands a rewrite.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, dirname, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

export const EXPECTED = 26;

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');

// ── the repository, read once ───────────────────────────────────────────────────────────────────
const SRC = new Map();
const load = (dir, re) => (function walk(d) {
  let entries; try { entries = readdirSync(d, { withFileTypes: true }); } catch { return; }
  for (const e of entries) {
    const p = join(d, e.name);
    if (e.isDirectory()) { if (!/^(node_modules|\.next|dist|build)$/.test(e.name)) walk(p); }
    else if (re.test(e.name)) {
      try { if (statSync(p).size < 4_000_000) SRC.set(relative(ROOT, p).split(sep).join('/'), readFileSync(p, 'utf8')); } catch { /* unreadable */ }
    }
  }
})(dir);
load(join(ROOT, 'src'), /\.(ts|tsx|js|jsx|mjs)$/);
load(join(ROOT, 'supabase', 'functions'), /\.(ts|tsx|js|jsx)$/);

const gRe = (re) => new RegExp(re.source, re.flags.includes('g') ? re.flags : re.flags + 'g');
const srcCount = (re, pathRe) => [...SRC.keys()].filter(p => !pathRe || pathRe.test(p))
  .reduce((n, p) => n + (SRC.get(p).match(gRe(re)) || []).length, 0);

// ── what the customer's page actually is ────────────────────────────────────────────────────────
// The /me route's rendered tree is the import closure of its page plus the layouts wrapping it.
// Computed rather than assumed, because "rendered somewhere in src/" is not "rendered to the
// customer" — the staff console and the supplier portal both render figures this row asks about.
function importClosure(entries) {
  const seen = new Map(); const queue = entries.filter(e => SRC.has(e));
  const resolve = (from, spec) => {
    let base = null;
    if (spec.startsWith('@/')) base = 'src/' + spec.slice(2);
    else if (spec.startsWith('.')) base = join(dirname(from), spec).split(sep).join('/');
    if (!base) return null;
    for (const ext of ['', '.tsx', '.ts', '.jsx', '.js', '/index.tsx', '/index.ts']) if (SRC.has(base + ext)) return base + ext;
    return null;
  };
  while (queue.length) {
    const p = queue.shift();
    if (seen.has(p)) continue;
    const text = SRC.get(p); if (text === undefined) continue;
    seen.set(p, text);
    for (const m of text.matchAll(/from\s+['"]([^'"]+)['"]/g)) { const r = resolve(p, m[1]); if (r && !seen.has(r)) queue.push(r); }
  }
  return seen;
}
const surface = importClosure(['src/app/[locale]/me/page.tsx', 'src/app/[locale]/layout.tsx', 'src/app/layout.tsx']);
const SURF = [...surface.values()].join('\n/*FILE*/\n');
const nSurf = surface.size;
const sCount = (re) => (SURF.match(gRe(re)) || []).length;
const sHas = (re) => sCount(re) > 0;

// Edge functions the CUSTOMER's page can reach: the ones its surface names, then the ones those
// name, transitively. Everything a customer can cause to run, and nothing only a staff console can.
const edgeSrc = (n) => SRC.get(`supabase/functions/${n}/index.ts`) || '';
const custEdge = (() => {
  const seen = new Set(); const queue = [];
  for (const m of SURF.matchAll(/(?:call\(\s*|functions\/v1\/)['"]?([a-z0-9_]+)['"]?/g)) queue.push(m[1]);
  while (queue.length) {
    const n = queue.shift();
    if (seen.has(n) || !edgeSrc(n)) continue;
    seen.add(n);
    for (const m of edgeSrc(n).matchAll(/(?:BASE\}|functions\/v1)\/([a-z0-9_]+)/g)) if (!seen.has(m[1])) queue.push(m[1]);
  }
  return [...seen].sort();
})();
const custEdgeText = custEdge.map(edgeSrc).join('\n/*FILE*/\n');

// ── SQL literal helpers ─────────────────────────────────────────────────────────────────────────
// A measured frontend fact reaches a check as a literal inside the statement, through one escaper,
// never by concatenation at the call site. EV additionally splits the bare write keywords qd_guard
// refuses: a check whose EVIDENCE text contains the word up-date is refused as a write and ERRORs,
// and an errored check is an UNMEASURED requirement — strictly worse than either verdict. The split
// is after the FIRST character: `d'||'o`, because `do'||''` still matches \bdo\b (a quote is a word
// boundary) and would be refused anyway.
const RISKY = /\b(insert|update|delete|truncate|drop|alter|create|grant|revoke|vacuum|reindex|call|do)\b/gi;
const EV = (s) => `'${String(s == null ? '' : s).replace(/'/g, "''").replace(RISKY, (m) => m.slice(0, 1) + "'||'" + m.slice(1))}'`;
const B = (v) => (v ? 'true' : 'false');

export default async function ({ req }) {
  const S5 = '5. Project Intelligence Workspace';
  const S6 = '6. 3D Project Visualization';
  const S7 = '7. AI RFQ Creation';
  const S8 = '8. RFQ Command Center';

  const portal = SRC.get('src/components/me/CustomerPortal.tsx') || '';
  const pa = edgeSrc('project_api');
  const ca = edgeSrc('customer_api');
  const ii = edgeSrc('inquiry_intake');
  // A component's source, from `function Name(` to the next top-level function.
  const block = (name, text) => {
    const m = new RegExp('^function ' + name + '\\b', 'm').exec(text);
    if (!m) return '';
    const rest = text.slice(m.index + 1);
    const nxt = /\nfunction /.exec(rest);
    return text.slice(m.index, nxt ? m.index + 1 + nxt.index : text.length);
  };
  const newRequest = block('NewRequest', portal);
  // The intake's JSON output contract lives inside a template literal, so every key in it is
  // BACKSLASH-ESCAPED in the source: `\"quantity\":`, never `"quantity":`. The first version of
  // these checks tested the plain form, scored three requirements MISSING on a quoting detail, and
  // would have reported a defect the code does not have — the mirror image of a false MET.
  const contract = (k) => new RegExp('\\\\"' + k + '\\\\"\\s*:').test(ii);
  let deps = [];
  try { const p = JSON.parse(readFileSync(join(ROOT, 'package.json'), 'utf8')); deps = Object.keys({ ...(p.dependencies || {}), ...(p.devDependencies || {}) }); } catch { /* scored as absent */ }

  // ═══ SECTION 5 — PROJECT INTELLIGENCE WORKSPACE ═════════════════════════════════════════════════

  // The FK, not just the two tables: a project entity that cannot be joined to its RFQs groups
  // nothing. project_summary.rfq_count is the proof the grouping is expressed, not merely possible.
  const FK_TARGET = `(select ccu.table_name from information_schema.table_constraints tc
        join information_schema.key_column_usage kcu
          on kcu.constraint_name = tc.constraint_name and kcu.constraint_schema = tc.constraint_schema
        join information_schema.constraint_column_usage ccu
          on ccu.constraint_name = tc.constraint_name and ccu.constraint_schema = tc.constraint_schema
       where tc.constraint_type = 'FOREIGN KEY' and tc.table_schema = 'public'
         and tc.table_name = 'inquiries' and kcu.column_name = 'project_id' limit 1)`;
  const PS_COLS = `(select string_agg(column_name, ',' order by ordinal_position)
      from information_schema.columns where table_schema='public' and table_name='project_summary')`;
  const PS_N = (rx) => `(select count(*) from information_schema.columns
      where table_schema='public' and table_name='project_summary' and column_name ~* '${rx}')`;

  await req(S5, 'proj-entity-exists', 'A project entity exists that groups multiple RFQs',
    `select (to_regclass('public.projects') is not null)
        and (select count(*) from information_schema.columns where table_schema='public'
              and table_name='projects' and column_name in ('id','customer_id','name','status')) = 4
        and coalesce(${FK_TARGET}, '') = 'projects'
        and ${PS_N('^rfq_count$')} = 1`,
    `select ${EV('projects(')} || coalesce((select string_agg(column_name, ',' order by ordinal_position)
           from information_schema.columns where table_schema='public' and table_name='projects'), 'absent')
        || ${EV('); inquiries.project_id FK -> ')} || coalesce(${FK_TARGET}, 'none')
        || ${EV('; project_summary(')} || coalesce(${PS_COLS}, 'absent') || ${EV(')')}
        || ${EV('; production rows: projects=')} || (select count(*) from public.projects)::text
        || ${EV(', inquiries=')} || (select count(*) from public.inquiries)::text
        || ${EV(' — zero customer data, so the grouping is scored on the FK and the view, not on rows')}`);

  // Customer-authed CRUD, scoped to the caller's own rows. An endpoint that returns any project by
  // id is not "their own projects", so the ownership filter is measured per action, not once.
  const paActions = [...new Set([...pa.matchAll(/action === '([a-z_]+)'/g)].map((m) => m[1]))];
  const paAuth = /admin\.auth\.getUser\(jwt\)/.test(pa) && /from\('customers'\)/.test(pa);
  const CRUD = ['create', 'update', 'list', 'detail'];
  const paScoped = CRUD.filter((a) => new RegExp(`action === '${a}'[\\s\\S]{0,600}?customer_id['",: ]{1,3}cust\\.id`).test(pa));
  const paPresent = CRUD.filter((a) => paActions.includes(a));
  const projApiInSrc = srcCount(/\bproject_api\b/, /^src\//);
  await req(S5, 'proj-customer-crud', 'Customer can create, update and view their own projects',
    `select ${B(!!pa && paAuth && paPresent.length === 4 && paScoped.length === 4)}`,
    `select ${EV(`project_api/index.ts: ${paActions.length} action(s) [${paActions.join(' ')}]; ` +
      `${paPresent.length}/4 CRUD action(s) present [${paPresent.join(' ')}]; customer JWT -> customers row = ${paAuth}; ` +
      `own-rows filter on ${paScoped.length}/4 [${paScoped.join(' ')}]. Reachability is a separate requirement ` +
      `(proj-ui-rendered): ${projApiInSrc} file(s) under src/ name project_api.`)}`);

  // ── the five "Project shows X" requirements ─────────────────────────────────────────────────
  // Each is a three-leg chain measured for that figure alone. The render leg is shared because it is
  // one fact — no customer surface renders any project — but it is never the whole verdict: the
  // other two legs differ per requirement and every evidence string prints all three.
  const projApiOnSurf = sCount(/\bproject_api\b/);
  const projKeyOnSurf = sCount(/\b(rfq_open|rfq_count|rfq_awarded|pipeline_value|target_open_date|budget_total)\b/);
  const rendered = projApiOnSurf > 0 && projKeyOnSurf > 0;
  const legs = (figure, computed, payload) =>
    `${figure} — computed: ${computed}; in a customer-authed payload: ${payload}; ` +
    `rendered on the customer surface: ${rendered} (${nSurf} file(s) in the /me import closure, ` +
    `${projApiOnSurf} name project_api, ${projKeyOnSurf} render a project_summary key)`;
  const paListSummary = /action === 'list'[\s\S]{0,300}?from\('project_summary'\)/.test(pa);

  await req(S5, 'proj-budget', 'Project shows a total budget',
    `select ${B(rendered && paListSummary)}
        and (select count(*) from information_schema.columns where table_schema='public'
              and table_name='projects' and column_name='budget_total') = 1
        and ${PS_N('^budget_total$')} = 1`,
    `select ${EV(legs('budget_total', 'projects.budget_total, projected by project_summary.budget_total',
      `project_api action=list returns project_summary rows to a customer JWT (${paListSummary})`))}`);

  const paCatAgg = /category\]/.test(pa);
  await req(S5, 'proj-materials-list', 'Project shows the material/trade breakdown',
    `select ${B(rendered)} and ${PS_N('(trade|material|categor)')} > 0`,
    `select ${EV(legs('trade/material breakdown', 'no project_summary column names a trade, material or category',
      `project_api action=detail returns rfqs[] each carrying category but aggregates none of them (keyed rollup over category = ${paCatAgg})`))}
        || ${EV('; project_summary columns matching trade|material|categor: ')} || ${PS_N('(trade|material|categor)')}::text
        || ${EV(' of ')} || (select count(*) from information_schema.columns where table_schema='public' and table_name='project_summary')::text`);

  await req(S5, 'proj-active-rfq-count', 'Project shows count of active RFQs',
    `select ${B(rendered && paListSummary)} and ${PS_N('^rfq_open$')} = 1 and ${PS_N('^rfq_count$')} = 1`,
    `select ${EV(legs('rfq_open / rfq_count', 'project_summary computes both per project',
      `project_api action=list returns them to a customer JWT (${paListSummary})`))}`);

  // dashboard.suppliers_engaged is the near miss: it exists, it reaches the customer, and it counts
  // the WHOLE customer's revealed transactions rather than one project's matched suppliers.
  const dashWide = /suppliers_engaged: suppliers\.length/.test(pa) && /const suppliers = \[\.\.\.new Set\(txs\.map/.test(pa);
  await req(S5, 'proj-supplier-count', 'Project shows how many suppliers are engaged',
    `select ${B(rendered)} and ${PS_N('supplier')} > 0`,
    `select ${EV(legs('suppliers engaged per project', 'no project_summary column names a supplier',
      `project_api dashboard.suppliers_engaged counts distinct transactions.supplier_id for the whole customer, not per project (${dashWide})`))}
        || ${EV('; project_summary columns matching supplier: ')} || ${PS_N('supplier')}::text
        || ${EV('; routines relating inquiry_matches to a project: ')}
        || (select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.prokind in ('f','p')
               and pg_get_functiondef(p.oid) ~* '\\yinquiry_matches\\y'
               and pg_get_functiondef(p.oid) ~* '\\yproject_id\\y')::text`);

  const paPctKeys = (pa.match(/(progress|completion|timeline)_?(pct|percent)/gi) || []).length;
  await req(S5, 'proj-timeline-pct', 'Project shows a timeline completion percentage',
    `select ${B(rendered && paPctKeys > 0)} and ${PS_N('(progress|pct|percent|complet)')} > 0`,
    `select ${EV(legs('timeline completion %', 'projects.target_open_date and created_at both exist, nothing divides them',
      `project_api emits ${paPctKeys} percentage key(s)`))}
        || ${EV('; project_summary columns matching progress|pct|percent|complet: ')} || ${PS_N('(progress|pct|percent|complet)')}::text
        || ${EV('; routines naming target_open_date: ')}
        || (select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.prokind in ('f','p')
               and pg_get_functiondef(p.oid) ~* '\\ytarget_open_date\\y')::text`);

  // The section's one UI requirement, measured over the whole tree so it cannot be satisfied by the
  // SUPPLIER portal's `supplier_api action=projects` — a supplier's won-job list, not this.
  const supplierProjects = srcCount(/action: 'projects'/, /SupplierPortal/);
  await req(S5, 'proj-ui-rendered', 'A Projects workspace is rendered in the customer portal',
    `select ${B(rendered)}`,
    `select ${EV(`the /me import closure is ${nSurf} file(s) [${[...surface.keys()].filter((p) => !/components\/ui\//.test(p)).join(' ')}]; ` +
      `${projApiOnSurf} name project_api and ${projKeyOnSurf} render a project_summary key. Across all of src/, project_api is named ` +
      `${projApiInSrc} time(s); the only projects surface in src/ is SupplierPortal's supplier_api action=projects ` +
      `(${supplierProjects} site(s)), which is the supplier's won-job list.`)}`);

  // ═══ SECTION 6 — 3D PROJECT VISUALIZATION ═══════════════════════════════════════════════════════
  // D: a canvas is not a 3D model. The discriminator is a WebGL context or a 3D dependency.
  const D3 = /^(three|@react-three\/|@babylonjs\/|babylonjs|@google\/model-viewer|cesium|resium|deck\.gl|@deck\.gl\/|regl|playcanvas|aframe|troika-three|zdog|ogl)/;
  const deps3d = deps.filter((d) => D3.test(d));
  const WEBGL = /WebGLRenderer|getContext\(\s*['"]webgl|useGLTF|@react-three|from ['"]three['"]|THREE\./;
  const webglSurf = sCount(WEBGL);
  const webglSrc = srcCount(WEBGL, /^src\//);
  const canvas2d = srcCount(/getContext\(\s*['"]2d['"]/, /^src\//);
  const model3d = deps3d.length > 0 && webglSurf > 0;
  const dep3dLeg = `${deps3d.length} 3D dependenc(ies) among the ${deps.length} in package.json [${deps3d.join(' ') || 'none'}]`;
  const glLeg = `${webglSurf} customer-surface file(s) obtain a WebGL context (${webglSrc} across all of src/); ` +
    `${canvas2d} file(s) in src/ obtain a 2D canvas context and are deliberately not counted as 3D`;

  await req(S6, '3d-building-model', 'A 3D building model of the project is rendered',
    `select ${B(model3d)}`, `select ${EV(dep3dLeg + '; ' + glLeg)}`);

  const FLOOR_COLS = `(select count(*) from information_schema.columns where table_schema='public'
      and table_name in ('projects','inquiries','quotes','po_orders','documents')
      and column_name ~* '^(floor|level|storey|story|elevation)s?$')`;
  await req(S6, '3d-floor-drilldown', 'The model can be drilled into by floor',
    `select ${B(model3d && sHas(/\b(floor|storey)\b/i))} and ${FLOOR_COLS} > 0`,
    `select ${EV('nothing to drill into (' + glLeg.split(';')[0] + '); floor dimension on projects/inquiries/quotes/po_orders/documents: ')}
        || ${FLOOR_COLS}::text
        || ${EV(' column(s); routines naming a per-floor dimension: ')}
        || (select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.prokind in ('f','p')
               and pg_get_functiondef(p.oid) ~* '\\y(floor_no|floor_number|storey|per_floor|floor_level)\\y')::text
        || ${EV('; projects.meta is jsonb and production holds ')} || (select count(*) from public.projects)::text
        || ${EV(` project row(s), so no floor key can be evidenced from data; the customer surface names a floor/storey ${sCount(/\b(floor|storey)\b/i)} time(s)`)}`);

  // The statuses DO exist — per RFQ and per purchase order. What does not exist is a COMPONENT to
  // carry one. THE FIRST VERSION OF THIS CHECK SCORED MET AND WAS WRONG, twice over, and both
  // mistakes are the ones this file is written against: `column_name ~ '^component$'` matched
  // scope_marker.component and scope_component.component, two scope-detection taxonomy tables with
  // no status and no project; and a pg_proc scan for the WORDS component + status matched
  // fn_agent_context, whose "components" are the Universal OS Blueprint's 17, not a building's.
  // A word is not a mechanism. The relation must carry BOTH a status and a link to the thing being
  // visualised, asserted over the SAME table, which is satisfiable by one boq-line table.
  const COMP_COLS = (extra) => `(select count(distinct c1.table_name) from information_schema.columns c1
      where c1.table_schema='public'
        and c1.column_name ~* '^(component|component_id|line_item|line_item_id|boq_item|boq_item_id)$'${extra})`;
  const HAS_ON_SAME = (cols) => ` and exists (select 1 from information_schema.columns c2
          where c2.table_schema='public' and c2.table_name = c1.table_name and c2.column_name in (${cols}))`;
  const COMP_OK = COMP_COLS(HAS_ON_SAME(`'status','state','stage'`) + HAS_ON_SAME(`'project_id','inquiry_id'`));
  await req(S6, '3d-component-status', 'Each component per floor carries a status',
    `select ${COMP_OK} > 0`,
    `select ${EV('relations with a component/line-item identity column: ')}
        || coalesce((select string_agg(distinct c1.table_name || '.' || c1.column_name, ',') from information_schema.columns c1
             where c1.table_schema='public'
               and c1.column_name ~* '^(component|component_id|line_item|line_item_id|boq_item|boq_item_id)$'), 'none')
        || ${EV(', of which ')} || ${COMP_COLS(HAS_ON_SAME(`'status','state','stage'`))}::text
        || ${EV(' also carry a status and ')} || ${COMP_COLS(HAS_ON_SAME(`'project_id','inquiry_id'`))}::text
        || ${EV(' link to a project or RFQ, so ')} || ${COMP_OK}::text
        || ${EV(' satisfy the requirement. The statuses that DO exist are per-RFQ and per-order — inquiries.status=')}
        || (select count(*) from information_schema.columns where table_schema='public' and table_name='inquiries' and column_name='status')::text
        || ${EV(', po_orders.status=')}
        || (select count(*) from information_schema.columns where table_schema='public' and table_name='po_orders' and column_name='status')::text
        || ${EV('; inquiries.boq is a jsonb blob with no per-item status. Routines whose text merely contains the words component and status are NOT counted: ')}
        || coalesce((select string_agg(distinct p.proname, ',') from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.prokind in ('f','p')
               and pg_get_functiondef(p.oid) ~* '\\ycomponent(_status)?\\y'
               and pg_get_functiondef(p.oid) ~* '\\y(status|stage)\\y'), 'none')`);

  // Two independent legs, and the second is the interesting one: the per-RFQ timeline EXISTS — the
  // QD_RFQ_TRACE branch of fn_entity_activity returns dated milestone/decision/match/quote entries
  // with the REASON each supplier was chosen — and no customer-reachable endpoint names it.
  const custActivity = /fn_entity_activity/.test(custEdgeText);
  await req(S6, '3d-click-opens-detail', 'Clicking a component opens its RFQs, suppliers, documents, costs and timeline',
    `select ${B(model3d && custActivity)}`,
    `select ${EV('leg 1, nothing to click: ' + glLeg.split(';')[0] + '. leg 2, the detail payload exists but is staff-only — fn_entity_activity carries the rfq branch = ')}
        || (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.proname='fn_entity_activity' and p.prosrc like '%QD_RFQ_TRACE%')::text
        || ${EV(`, named by ${custActivity ? 'at least one' : '0'} of the ${custEdge.length} customer-reachable edge function(s) [${custEdge.join(' ')}], and by these routines: `)}
        || coalesce((select string_agg(distinct p.proname, ',') from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_entity_activity'
               and pg_get_functiondef(p.oid) ~* '\\yfn_entity_activity\\y'), 'none')`);

  // ═══ SECTION 7 — AI RFQ CREATION ════════════════════════════════════════════════════════════════

  // "No manual form" is a claim about the SERVER as much as the screen: a chat the client can skip
  // is a form with extra steps. The intake gate in create_inquiry is what makes it true.
  const intakeReachable = custEdge.includes('inquiry_intake');
  const chatSurface = /setMessages|messages\.map/.test(newRequest) && /<textarea/.test(newRequest);
  const fieldInputs = (newRequest.match(/<Input\b/g) || []).length;
  const serverGate = /intake_required/.test(ca) && /it\.status === 'ready'/.test(ca);
  // "No manual form" is not "zero input elements" — a stray field would not make this a form, and a
  // check that flipped on one would be over-hardened. What it means is that there is NO OTHER WAY
  // IN: every create_inquiry site in the whole frontend is the one inside the conversation.
  const createSites = srcCount(/create_inquiry/, /^src\//);
  const createInChat = /create_inquiry/.test(newRequest);
  await req(S7, 'rfq-nl-creation', 'RFQ is created from natural language, with no manual form',
    `select ${B(intakeReachable && chatSurface && serverGate && createInChat && createSites === 1)}
        and (select count(*) from public.category_specs where jsonb_typeof(fields) = 'array') > 0`,
    `select ${EV(`inquiry_intake is reachable from the customer surface = ${intakeReachable} (of ${custEdge.length} customer-reachable edge functions); ` +
      `the creation surface is a conversation, message list plus free-text box = ${chatSurface}, carrying ${fieldInputs} typed field input(s); ` +
      `${createSites} create_inquiry site(s) exist in all of src/ and the conversation owns ${createInChat ? 'it' : 'none of them'}; ` +
      `the server refuses a formless bypass, intake_required unless a server-side intake row is ready = ${serverGate}; category checklists behind the interview: `)}
        || (select count(*) from public.category_specs where jsonb_typeof(fields) = 'array')::text
        || ${EV(' of ')} || (select count(*) from public.category_specs)::text`);

  const catPersisted = /category,\s*emirate,\s*role_needed/.test(ca);
  const catRendered = /\{inq\.category/.test(SURF);
  const catStored = /\{ category, status, raw_input/.test(ii);
  await req(S7, 'rfq-product-extraction', 'AI extracts the product from the sentence',
    `select ${B(contract('category') && catStored && catPersisted && catRendered)}
        and (select count(*) from information_schema.columns where table_schema='public'
              and table_name='inquiries' and column_name='category') = 1
        and (select count(*) from information_schema.columns where table_schema='public'
              and table_name='inquiry_intake' and column_name='category') = 1`,
    `select ${EV(`inquiry_intake names a category in its JSON output contract = ${contract('category')} and stores it on inquiry_intake.category = ${catStored}; ` +
      `create_inquiry persists it to inquiries.category = ${catPersisted}; the RFQ card renders inq.category = ${catRendered}; production rows: intake=`)}
        || (select count(*) from public.inquiry_intake)::text
        || ${EV(', inquiries=')} || (select count(*) from public.inquiries)::text
        || ${EV(' — the chain is scored on the mechanism, not on rows')}`);

  // C: survival counted over categories. The intake contract emits brief.quantity at the TOP level;
  // create_inquiry merges only brief.details into inquiries.spec, so the extracted quantity survives
  // solely under a canonical required key — and the readiness gate accepts the answer at EITHER
  // place, so even a category that has such a key can pass 'ready' and still lose the number.
  const REQ_KEYS = (rx) => `(select count(distinct cs.category) from public.category_specs cs,
      jsonb_array_elements(cs.fields) f where (f->>'required')::boolean is true and f->>'key' ~* '${rx}')`;
  const CATS = `(select count(*) from public.category_specs)`;
  const QTY_RX = '(quantity|qty|area|dimension|size|volume|units?)';
  const qtyEmitted = contract('quantity');
  const detailsOnly = /spec = \(briefObj\?\.details/.test(ca);
  const qtyPersisted = /briefObj\?\.quantity|briefObj\.quantity|brief\.quantity/.test(ca);
  const gateEither = /b\[f\.key\]\s*\?\?\s*det\[f\.key\]/.test(ii);
  await req(S7, 'rfq-quantity-extraction', 'AI extracts quantity',
    `select ${B(qtyEmitted)} and (${B(qtyPersisted)} or ${REQ_KEYS(QTY_RX)} = ${CATS})`,
    `select ${EV(`the intake contract emits brief.quantity = ${qtyEmitted}; create_inquiry reads it = ${qtyPersisted} and merges only ` +
      `brief.details into inquiries.spec = ${detailsOnly}, so an extracted quantity survives only under a canonical required key — present for `)}
        || ${REQ_KEYS(QTY_RX)}::text || ${EV(' of ')} || ${CATS}::text
        || ${EV(` categories; and the readiness gate accepts the answer at brief.<key> OR brief.details.<key> = ${gateEither}, ` +
          `so even in those a top-level answer passes ready and is then dropped. The other path is a drawing: inquiries.boq holds jsonb line items on `)}
        || (select count(*) from public.inquiries where boq is not null)::text
        || ${EV(' of ')} || (select count(*) from public.inquiries)::text || ${EV(' RFQs')}`);

  const specServed = /'id,category,emirate,summary,spec/.test(ca) && /spec: i\.spec/.test(ca);
  const specRendered = /inq\.spec/.test(SURF) && /Object\.keys\(sp\)/.test(SURF);
  await req(S7, 'rfq-spec-extraction', 'AI extracts specifications',
    `select ${B(detailsOnly && specServed && specRendered)}
        and (select count(*) from information_schema.columns where table_schema='public'
              and table_name='inquiries' and column_name='spec' and data_type='jsonb') = 1`,
    `select ${EV(`inquiries.spec is jsonb; create_inquiry writes brief.details into it = ${detailsOnly}; my_inquiries selects and serves spec = ${specServed}; ` +
      `the RFQ card renders spec as key/value pairs = ${specRendered}; categories whose checklist defines at least one canonical key behind those specs: `)}
        || ${REQ_KEYS('.')}::text || ${EV(' of ')} || ${CATS}::text`);

  const emiratePersisted = /const emirate = body\.emirate \|\| \(briefObj\?\.emirate/.test(ca);
  const emirateRendered = /\{inq\.emirate/.test(SURF);
  await req(S7, 'rfq-location-extraction', 'AI extracts location/emirate',
    `select ${B((contract('emirate') || /brief\.emirate/.test(ii)) && emiratePersisted && emirateRendered)}
        and (select count(*) from information_schema.columns where table_schema='public'
              and table_name='inquiries' and column_name='emirate') = 1`,
    `select ${EV(`the intake sets brief.emirate and back-fills brief.location from it; create_inquiry persists it to inquiries.emirate = ${emiratePersisted}; ` +
      `the RFQ card header renders inq.emirate = ${emirateRendered}; categories whose checklist makes a location REQUIRED: `)}
        || ${REQ_KEYS('(location|emirate|city|site)')}::text || ${EV(' of ')} || ${CATS}::text`);

  // Extracted, shown before sending, then discarded. One line in create_inquiry closes it.
  const TIME_RX = '(timeline|deadline|delivery|lead_?time|completion|schedule|when|date)';
  const TIME_COLS = `(select count(*) from information_schema.columns where table_schema='public'
      and table_name='inquiries' and column_name ~* '^(timeline|deadline|lead_?time|required_by|due_date|delivery_.*)$')`;
  const timeEmitted = contract('timeline');
  const timeShown = /brief\.timeline/.test(newRequest);
  const timePersisted = /briefObj\?\.timeline|briefObj\.timeline/.test(ca);
  await req(S7, 'rfq-delivery-extraction', 'AI extracts a delivery window',
    `select ${B(timeEmitted)} and (${B(timePersisted)} or ${TIME_COLS} > 0 or ${REQ_KEYS(TIME_RX)} = ${CATS})`,
    `select ${EV(`the intake contract emits brief.timeline = ${timeEmitted} and the ready-brief card shows it before sending = ${timeShown}; ` +
      `create_inquiry reads it = ${timePersisted}; inquiries columns matching a delivery window: `)}
        || ${TIME_COLS}::text
        || ${EV('; so it survives only via brief.details, for the ')} || ${REQ_KEYS(TIME_RX)}::text
        || ${EV(' of ')} || ${CATS}::text || ${EV(' categories whose checklist carries a required timeline-shaped key')}`);

  // A: the only reader is the writer. compliance_checklist is authored per category by category_reqs
  // and read by nothing; the three fn_inquiry_answer_* routines naming inquiry_answer_document WRITE
  // it, so they are excluded BY NAME rather than by the inert generic self-exclusion.
  const WRITERS = `('fn_inquiry_answer_set','fn_inquiry_answer_confirm','fn_inquiry_answer_supersede')`;
  const CERT_READERS = `(select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.prokind in ('f','p') and p.proname not in ${WRITERS}
        and pg_get_functiondef(p.oid) ~* '\\y(compliance_checklist|inquiry_answer_document)\\y')`;
  const certInCreate = /compliance_checklist|inquiry_answer_document/.test(ca);
  const certEdges = custEdge.filter((f) => /compliance_checklist|inquiry_answer_document/.test(edgeSrc(f)));
  await req(S7, 'rfq-certificates', 'Required certificates are attached to the RFQ automatically',
    `select ${B(certInCreate || certEdges.length > 0)} or ${CERT_READERS} > 0`,
    `select ${EV('categories carrying a compliance checklist: ')}
        || (select count(*) from public.category_specs where compliance_checklist is not null
              and jsonb_typeof(compliance_checklist) <> 'null' and compliance_checklist::text not in ('{}','[]'))::text
        || ${EV(' of ')} || ${CATS}::text
        || ${EV('; routines reading compliance_checklist or inquiry_answer_document, with the three fn_inquiry_answer_* writers excluded by name: ')}
        || coalesce((select string_agg(distinct p.proname, ',') from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.prokind in ('f','p') and p.proname not in ${WRITERS}
               and pg_get_functiondef(p.oid) ~* '\\y(compliance_checklist|inquiry_answer_document)\\y'), 'none')
        || ${EV(`; customer-reachable edge functions naming either: ${certEdges.length} [${certEdges.join(' ') || 'none'}]; create_inquiry names either: ${certInCreate}; inquiry_answer_document rows: `)}
        || (select count(*) from public.inquiry_answer_document)::text`);

  const modeText = /<textarea/.test(newRequest) && /inquiry_intake/.test(newRequest);
  const modeFile = /type="file"/.test(newRequest) && /accept="image\/\*,application\/pdf"/.test(newRequest) && /analyze_drawing/.test(newRequest);
  const modeVoice = /MediaRecorder/.test(newRequest) && /'transcribe'/.test(newRequest);
  const backing = ['transcribe', 'cad_convert', 'drawing_boq'].filter((f) => !!edgeSrc(f));
  await req(S7, 'rfq-multimodal-intake', 'RFQ can be created from voice, photo, drawing or PDF as well as text',
    `select ${B(modeText && modeFile && modeVoice && /analyze_drawing/.test(ca))}`,
    `select ${EV(`creation-surface input modes — text=${modeText}, image/PDF upload=${modeFile}, voice=${modeVoice}; ` +
      `customer_api exposes analyze_drawing = ${/analyze_drawing/.test(ca)}; backing edge functions present: ${backing.length}/3 [${backing.join(' ')}]; documents on production: `)}
        || (select count(*) from public.documents)::text
        || ${EV(' — extraction quality is proven separately by verify_doc_extract.mjs; this check scores the reachable input modes')}`);

  // ═══ SECTION 8 — RFQ COMMAND CENTER ═════════════════════════════════════════════════════════════

  const REF_COLS = `(select count(*) from information_schema.columns where table_schema='public'
      and table_name='inquiries'
      and column_name ~* '^(ref|reference|rfq_no|rfq_number|number|code|display_id|short_id|seq|serial)$')`;
  const refRendered = sCount(/inq\.(ref|reference|rfq_no|rfq_number|display_id|short_id)\b/);
  await req(S8, 'rfqcc-reference-number', 'Each RFQ carries a human reference number',
    `select ${REF_COLS} > 0 and ${B(refRendered > 0)}`,
    `select ${EV('inquiries columns matching a human reference: ')} || ${REF_COLS}::text
        || ${EV('; the primary key is ')}
        || (select data_type from information_schema.columns where table_schema='public' and table_name='inquiries' and column_name='id')
        || ${EV(`; the customer surface renders a reference-shaped field ${refRendered} time(s) — the RFQ card header renders category and emirate`)}`);

  const pipelines = [...SURF.matchAll(/\[\s*'Sent'[^\]]*\]/g)]
    .map((m) => m[0].replace(/[[\]']/g, '').split(',').map((s) => s.trim()).filter(Boolean));
  const maxSteps = pipelines.reduce((n, p) => Math.max(n, p.length), 0);
  const analysisStage = pipelines.some((p) => p.some((l) => /analy|\bai\b/i.test(l)));
  const comparisonMounts = sCount(/<Comparison\b/);
  await req(S8, 'rfqcc-status-pipeline', 'Five-stage pipeline: Created / Sent / Quotes Received / AI Analysis / Award',
    `select ${B(maxSteps >= 5 && analysisStage)}`,
    `select ${EV(`the customer's RFQ pipeline renders ${pipelines.length} stage strip(s), the longest of ${maxSteps} stage(s): ` +
      `${pipelines.map((p) => p.join(' > ')).join(' | ') || 'none found'}; a stage naming AI analysis: ${analysisStage}. ` +
      `quote_compare does run on the same card once 2+ quotes exist (${comparisonMounts} mount site(s)), but it is not a pipeline stage.`)}`);

  const stageServed = /'id,category,emirate,summary,spec[^']*pipeline_stage/.test(ca);
  const stageClientSide = /const stepIdx = /.test(SURF) && /anyRevealed \? 2/.test(SURF);
  await req(S8, 'rfqcc-stage-from-event-log', 'Pipeline stage comes from the recorded lifecycle, not guessed client-side',
    `select ${B(stageServed || custActivity)}`,
    `select ${EV('the recorded lifecycle exists — fn_entity_activity carries the QD_RFQ_TRACE rfq branch = ')}
        || (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.proname='fn_entity_activity' and p.prosrc like '%QD_RFQ_TRACE%')::text
        || ${EV(', and inquiries carries pipeline_stage + stage_changed_at = ')}
        || (select count(*) from information_schema.columns where table_schema='public' and table_name='inquiries'
              and column_name in ('pipeline_stage','stage_changed_at'))::text
        || ${EV('/2; company_event rows for an inquiry or rfq entity: ')}
        || (select count(*) from public.company_event where entity_type ~* '(inquiry|rfq)')::text
        || ${EV(' of ')} || (select count(*) from public.company_event)::text
        || ${EV(`. None of it reaches the customer: my_inquiries serves pipeline_stage = ${stageServed}, fn_entity_activity is named by ` +
          `${custActivity ? 'at least one' : '0'} of the ${custEdge.length} customer-reachable edge function(s), and the browser derives the stage ` +
          `from quotes.length and anyRevealed = ${stageClientSide}`)}`);

  // "responded / were reached" — either half satisfies it, and the evidence names which one did.
  const respondedRendered = sHas(/\{quotes\.length\}\s*quote/);
  const quotesKpi = sHas(/quotes_received/);
  const reachedRendered = sHas(/matched_suppliers/);
  const reachedEmitted = /matched_suppliers: matchedBy/.test(ca);
  await req(S8, 'rfqcc-response-count', 'RFQ shows how many suppliers responded / were reached',
    `select ${B(respondedRendered || reachedRendered)}`,
    `select ${EV(`responded: the RFQ card renders {quotes.length} quote(s) = ${respondedRendered}, and the header KPI renders stats.quotes_received = ${quotesKpi}. ` +
      `reached: customer_api my_inquiries emits matched_suppliers per inquiry = ${reachedEmitted}, rendered by ${sCount(/matched_suppliers/)} of the ${nSurf} customer-surface file(s). ` +
      `Production holds `)}
        || (select count(*) from public.quotes)::text || ${EV(' quotes and ')}
        || (select count(*) from public.inquiry_matches)::text
        || ${EV(' inquiry_matches rows, so the verdict is taken from the render sites, not from data')}`);

  // similarity exists as a column and BOTH writer sites pass it as null, so there is no stored match
  // percentage to show. The customer gets a browser-computed "Value n/100" instead — a different
  // number from different inputs — which is why this scores on the stored match figure.
  const simNullWrites = srcCount(/similarity:\s*null/, /^supabase\/functions\/(customer_api|dispatch_inquiry)\//);
  const simRealWrites = srcCount(/inquiry_matches[\s\S]{0,200}?similarity:\s*(?!null)[A-Za-z0-9_(]/, /^supabase\/functions\//);
  const simRendered = sCount(/\b(similarity|match_reason)\b/);
  const staffSim = srcCount(/m\.similarity/, /osx/);
  const clientValue = sHas(/Value \{vscore\}/) && sHas(/Best value/);
  await req(S8, 'rfqcc-best-match-pct', 'RFQ shows the best-matching supplier with a percentage',
    `select ${B(simRealWrites > 0 && simRendered > 0)}
        and (select count(*) from information_schema.columns where table_schema='public'
              and table_name='inquiry_matches' and column_name='similarity') = 1`,
    `select ${EV(`inquiry_matches.similarity exists as a column; its two writer sites pass null (${simNullWrites} site(s)) and ${simRealWrites} site(s) pass a value, ` +
      `so no match percentage is ever stored. Production holds `)}
        || (select count(*) from public.inquiry_matches)::text || ${EV(' match row(s), ')}
        || (select count(*) from public.inquiry_matches where similarity is not null)::text
        || ${EV(` with a similarity — an empty table cannot decide this, the writer sites do. The customer surface renders similarity or match_reason ` +
          `${simRendered} time(s); the staff console renders a % match bar in ${staffSim} site(s). What the customer gets instead is a browser-computed ` +
          `Value n/100 blended from price, rating and quote completeness = ${clientValue}`)}`);

  // THE FIRST VERSION OF THIS CHECK SCORED MET AND WAS WRONG: `visibilitychange` matched twice in
  // NodeField.tsx, the decorative canvas the layout paints behind /me, which pauses its ANIMATION
  // when the tab is hidden. That is not the RFQ view updating. A liveness mechanism only counts in
  // a file that actually fetches the RFQ data, and the decorative hits are named and excluded.
  const LIVE = /setInterval|\.channel\(|removeChannel|\.subscribe\(|realtime|EventSource|new WebSocket|refreshInterval|refetchInterval|visibilitychange|useSWR/;
  const fetchesRfq = (t) => /my_inquiries|customer_portal/.test(t);
  const liveSites = [...surface.values()].filter(fetchesRfq).reduce((n, t) => n + (t.match(gRe(LIVE)) || []).length, 0);
  const decorative = [...surface.entries()]
    .filter(([, t]) => !fetchesRfq(t) && (t.match(gRe(LIVE)) || []).length)
    .map(([p]) => `${p.split('/').pop()}:${(SRC.get(p).match(gRe(LIVE)) || []).join('+')}`);
  const manualRefresh = sCount(/refresh\(\)/);
  const tokenRefresh = sHas(/autoRefreshToken/);
  await req(S8, 'rfqcc-live-workspace', 'RFQ view is a live workspace (it changes without a manual reload)',
    `select ${B(liveSites > 0)}`,
    `select ${EV(`live mechanisms — poll, realtime channel, subscription, socket, SWR/query revalidation, tab-focus refetch — in the ` +
      `${[...surface.values()].filter(fetchesRfq).length} customer-surface file(s) that actually fetch RFQ data: ${liveSites}. ` +
      `The two loaders fire on mount and on ${manualRefresh} explicit refresh site(s) bound to user actions. NOT counted: ${decorative.join(' ') || 'nothing'} ` +
      `(a decorative canvas pausing its animation is not the RFQ view changing). The Supabase client sets autoRefreshToken = ${tokenRefresh}, ` +
      `which refreshes the SESSION, not the data. Production holds `)}
        || (select count(*) from public.quotes)::text
        || ${EV(' quotes, so no arrival can be observed — the verdict is the absence of any subscription or poll, not the absence of traffic')}`);
}
