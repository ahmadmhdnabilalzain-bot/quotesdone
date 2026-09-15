// SPEC FILE #4, sections 19-22 — 3D/Spatial, Predictive Intelligence, UI Style, Final Structure.
//
//   19. 3D / Spatial Features      (4)  — project room, supply chain map, animation, live shipments
//   20. AI Predictive Intelligence (4)  — what will the customer need next, when, and what to do
//   21. Customer Portal UI Style   (9)  — dark mode, glass, animation, adaptive layout, 3D, graphs,
//                                         floating windows, smart search, workspace-not-pages
//   22. Final Structure           (18)  — the eighteen modules the portal is supposed to be made of
//
// ── WHAT THESE 35 REQUIREMENTS ARE ACTUALLY ABOUT ────────────────────────────────────────────────
// Almost none of them can be answered by a query against Postgres. "3D project models appear in the
// UI" is a fact about src/, not about pg_proc. So this file measures TWO populations and joins them:
// the database (does the mechanism exist, could a customer reach it) and the CUSTOMER SURFACE (does
// a component the customer opens put it on screen). A capability computed server-side and rendered
// nowhere is MISSING here however well the backend works — that is the whole point of the row.
//
// ── THREE SURFACES, AND ONLY ONE OF THEM IS THE CUSTOMER'S ───────────────────────────────────────
// /[locale]/console is the staff OS shell, /[locale]/portal is the SUPPLIER portal, /[locale]/me is
// the customer's; all three share src/components/ui. Scored globally over src/, `cmdk` certifies a
// customer command palette off OsxShell.tsx and `history_12m` certifies customer spending
// intelligence off SupplierPortal.tsx. Both are real code. Neither is on a customer's screen. So
// this file computes the /me page's own import closure and scores the style and the modules over
// THAT — while reachability legs use the runner's wider closure, which also carries the site chrome
// (background field, cookie banner, marketing chat bubble) the customer genuinely sees.
//
// The two are kept apart deliberately. The layout chrome is on the customer's page, but a cookie
// banner that fades in is not "the customer portal animates" and a marketing chat bubble is not the
// portal's AI assistant module. Counting them would turn section 21 into a test of the landing page.
//
// ── THE FIVE DEFECTS THIS FILE IS WRITTEN TO AVOID ───────────────────────────────────────────────
//  1. THE ONLY READER IS THE WRITER. Every SQL reader count excludes writers by pattern and collapses
//     pg_proc OVERLOADS with count(distinct proname) — fn_agent_context has two rows on production
//     and inflated every count in row #2 that forgot.
//  2. POPULATION STANDING IN FOR DELIVERY. No check in section 22 passes on a payload existing. Each
//     module needs the portal to FETCH it and a JSX interpolation in the SAME component to RENDER
//     it. Fetching in one place and rendering in another cannot pass by coincidence.
//  3. ONE ROW SCORING A WHOLE MECHANISM. Where a requirement enumerates contents ("projects,
//     suppliers, RFQs, documents, timelines") the verdict is a per-item coverage count over ONE
//     component. Where it says "throughout" the verdict is a coverage ratio over the portal's
//     components, never a single occurrence.
//  4. SATISFIABLE BY FLIPPING A FLAG. Dark mode needs a CONTROL and a stylesheet that has something
//     to switch to, not a dark palette. A prediction needs a routine that computes one, not a column
//     named churn_risk on 0 rows with no reader.
//  5. EVIDENCE THAT DOES NOT COMPUTE THE VERDICT. Every evidence string is built from the same
//     measured numbers as the boolean beside it. There is no prose about what is believed.
//
// ── AND THE INVERSE FAILURE, WHICH IS JUST AS BAD ────────────────────────────────────────────────
// Nothing here demands something no implementation could satisfy. The coverage thresholds are 3 of
// the portal's mounted components; the panel threshold is the 4 panels the spec itself names; the
// page-swap count is restricted to NAVIGATION state (view/tab/screen/route) because every React
// component on earth early-returns on loading and error, and counting those would make
// ui-not-sidebar-pages-tables unsatisfiable by construction.
import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { join, dirname, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

export const EXPECTED = 34;   // 35 until 14 Sep 2026; mod-approvals retired

export default async function (H) {
  const { req, one } = H;
  const ROOT = H.ROOT || join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');

  // ── literal helpers ────────────────────────────────────────────────────────────────────────────
  // Q defuses the bare write keywords qd_guard's read guard refuses. This is not cosmetic: an
  // evidence string that quotes source can easily contain `call` or `create`, the statement is then
  // refused as a write, and the check ERRORs. An errored check is an UNMEASURED requirement, which
  // is strictly worse than either verdict. The runner's EV does this; the fallback is identical in
  // effect so this module still runs under a runner that only supplies row #2's helper set.
  const GUARD = /\b(insert|update|delete|truncate|drop|alter|create|grant|revoke|vacuum|reindex|call|do)\b/gi;
  const Q = H.EV || ((s) => `'` + String(s == null ? '' : s).replace(/'/g, "''").replace(GUARD, (m) => m.slice(0, 2) + "'||'" + m.slice(2)) + `'`);
  const ARR = (a) => (a.length ? `array[${a.map(x => `'${x}'`).join(',')}]::text[]` : `array[]::text[]`);
  const B = H.B || ((v) => (v ? 'true' : 'false'));
  const SAFE = (s) => /^[A-Za-z_][A-Za-z0-9_]*$/.test(s);

  // ── the source tree ────────────────────────────────────────────────────────────────────────────
  const SRC = (H.SRC instanceof Map && H.SRC.size) ? H.SRC : (() => {
    const m = new Map();
    const walk = (d, re) => { let es; try { es = readdirSync(d, { withFileTypes: true }); } catch { return; }
      for (const e of es) { const p = join(d, e.name);
        if (e.isDirectory()) { if (!/^(node_modules|\.next|dist|build)$/.test(e.name)) walk(p, re); }
        else if (re.test(e.name)) { try { if (statSync(p).size < 4e6) m.set(relative(ROOT, p).split(sep).join('/'), readFileSync(p, 'utf8')); } catch { /* unreadable */ } } } };
    walk(join(ROOT, 'src'), /\.(ts|tsx|js|jsx)$/);
    walk(join(ROOT, 'supabase', 'functions'), /\.(ts|tsx|js|jsx)$/);
    return m;
  })();
  const text = (p) => SRC.get(p) || '';
  // The stylesheet every customer page is served under. Read from disk rather than from SRC: the
  // runner indexes .ts/.tsx only, and a theme lives in CSS, so a missing globals.css would silently
  // turn ui-dark-mode-option into a check that could never see the thing it is asking about.
  const CSS = (() => { try { return readFileSync(join(ROOT, 'src', 'app', 'globals.css'), 'utf8'); } catch { return ''; } })();

  // ── THE PORTAL'S OWN IMPORT CLOSURE ────────────────────────────────────────────────────────────
  // Walked from the customer route's page file. Computed, not listed, so a component added to the
  // portal tomorrow is scored without editing this file.
  const resolveImport = (spec, fromFile) => {
    let base;
    if (spec.startsWith('@/')) base = join(ROOT, 'src', spec.slice(2));
    else if (spec.startsWith('.')) base = join(dirname(join(ROOT, fromFile)), spec);
    else return null;
    for (const ext of ['', '.tsx', '.ts', '.jsx', '.js', '/index.tsx', '/index.ts']) {
      const rel = relative(ROOT, base + ext).split(sep).join('/');
      if (SRC.has(rel)) return rel;
    }
    return null;
  };
  const closureFrom = (entries) => {
    const seen = new Set(); const queue = entries.filter(e => SRC.has(e));
    while (queue.length) {
      const f = queue.shift();
      if (seen.has(f)) continue;
      seen.add(f);
      for (const m of text(f).matchAll(/from\s+['"]([^'"]+)['"]/g)) {
        const r = resolveImport(m[1], f);
        if (r && !seen.has(r)) queue.push(r);
      }
    }
    return [...seen].sort();
  };
  const ENTRIES = [...SRC.keys()].filter(p => /^src\/app\/.*\/me\/page\.tsx?$/.test(p));
  const PORTAL_FILES = closureFrom(ENTRIES);
  const PORTAL_TEXT = PORTAL_FILES.map(text).join('\n/*FILE*/\n');
  // The portal's OWN surfaces: its closure minus the shared shadcn primitives and plain helpers. A
  // `transition-colors` on a shared Button is not the customer portal animating, so every coverage
  // ratio in section 21 is taken over these files.
  const OWN_FILES = PORTAL_FILES.filter(p => !/^src\/(components\/ui|lib|i18n)\//.test(p));
  const OWN_TEXT = OWN_FILES.map(text).join('\n/*FILE*/\n');
  // The wider page the customer is served — portal plus site chrome — used only where the question
  // is "can the customer reach it", never where it is "does the portal look like this".
  const PAGE_FILES = H.cust && Array.isArray(H.cust.surfacePaths) && H.cust.surfacePaths.length
    ? [...new Set([...H.cust.surfacePaths, ...PORTAL_FILES])].sort() : PORTAL_FILES;
  const PAGE_TEXT = PAGE_FILES.map(text).join('\n/*FILE*/\n');

  // ── COMPONENTS, AND WHAT THEY PUT ON SCREEN ────────────────────────────────────────────────────
  // A component is sliced from its declaration to the next top-level declaration. `interps` is the
  // JSX interpolation text — the difference between a payload a component FETCHES and a figure it
  // RENDERS, which is the single distinction this row turns on.
  //
  // A CONSTANT IS NOT A COMPONENT. Taking every `const <Capital> =` made `const T = {...}` (the
  // translation table), `const S = {...}` (the style map), `const EMIRATES = [...]` and the Supabase
  // client into "components" and inflated the denominator of every coverage ratio in section 21 by
  // four. A capitalised binding counts only when what follows the `=` is a function.
  const componentsOf = (file) => {
    const t = text(file); const marks = []; let m;
    const re = /^(?:export\s+(?:default\s+)?)?(?:function\s+([A-Z][\w$]*)\s*\(|const\s+([A-Z][\w$]*)\s*(?::[^=\n]{0,140})?=\s*([\s\S]{0,40}))/gm;
    while ((m = re.exec(t))) {
      if (m[2] && !/^(\(|function\b|async\b|(React\.)?(forwardRef|memo)\s*\()/.test(m[3] || '')) continue;
      marks.push({ name: m[1] || m[2], at: m.index });
    }
    return marks.map((mk, i) => ({ name: mk.name, file, body: t.slice(mk.at, i + 1 < marks.length ? marks[i + 1].at : t.length) }));
  };
  const OWN_COMPS = OWN_FILES.flatMap(componentsOf);
  const PRIMITIVES = new Set(PORTAL_FILES.filter(p => /^src\/components\/ui\//.test(p)).flatMap(componentsOf).map(c => c.name));
  const interps = (body) => [...body.matchAll(/\{([^{}]{0,800}?)\}/g)].map(x => x[1]).join(' ; ');
  // Mounted: something renders it, or it is the route's own default export. The second clause is an
  // exact match on the export line — an earlier `text(entry).includes(name)` form was true for any
  // component whose NAME was a substring of the page file, which is a coin toss, not a measurement.
  const MOUNTED = OWN_COMPS.filter(c => new RegExp('<' + c.name + '[\\s/>]').test(PORTAL_TEXT)
    || ENTRIES.some(e => new RegExp('export default function ' + c.name + '\\b').test(text(e))));
  const names = (cs, n = 5) => (cs.length ? cs.slice(0, n).map(c => c.name).join(',') + (cs.length > n ? ',+' + (cs.length - n) : '') : 'none');

  // ── WHAT A CUSTOMER CAN REACH ON THE SERVER ────────────────────────────────────────────────────
  // The edge functions the customer's page names, then the ones those name, transitively. os_api and
  // the eighteen workspace routines behind it are reachable from the CONSOLE; nothing a console-only
  // routine computes is on a customer's screen.
  const edgeSrc = (n) => text(`supabase/functions/${n}/index.ts`);
  const CUST_EDGE = (H.cust && Array.isArray(H.cust.edgeFns) && H.cust.edgeFns.length) ? H.cust.edgeFns : (() => {
    const seen = new Set(); const queue = [];
    for (const m of PAGE_TEXT.matchAll(/(?:functions\/v1\/|call\(\s*['"])([a-z0-9_]+)/g)) queue.push(m[1]);
    while (queue.length) {
      const n = queue.shift();
      if (seen.has(n)) continue;
      seen.add(n);
      for (const m of edgeSrc(n).matchAll(/(?:BASE\}|functions\/v1)\/([a-z0-9_]+)/g)) if (!seen.has(m[1])) queue.push(m[1]);
    }
    return [...seen].filter(n => edgeSrc(n)).sort();
  })();
  const CUST_EDGE_TEXT = CUST_EDGE.map(edgeSrc).join('\n/*FILE*/\n');
  const ROOT_FNS = [...new Set([...CUST_EDGE_TEXT.matchAll(/['"](fn_[a-z0-9_]+)['"]/g)].map(m => m[1]))].filter(SAFE).sort();
  const CUST_EDGE_TABLES = [...new Set([...CUST_EDGE_TEXT.matchAll(/\.from\(\s*['"]([a-z0-9_]+)['"]/g)].map(m => m[1]))].filter(SAFE).sort();

  // The transitive closure over pg_get_functiondef from those roots — the routines a customer can
  // cause to execute. One query, computed once, reused by every reachability leg. Depth 6 is where
  // the set stops growing. If it fails, the dependent checks report ERROR rather than MISSING: an
  // unmeasured requirement is not a verdict, and calling it MISSING would be a false negative.
  let CUST_FNS = [], closureErr = '';
  try {
    const raw = String(await one(`with recursive defs as materialized (
        select p.proname, pg_get_functiondef(p.oid) d from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace
         where n.nspname='public' and p.prokind in ('f','p')
      ), edges as materialized (
        -- b.proname is CATALOG CONTENT being spliced into a regex. Postgres allows a quoted
        -- identifier to contain '.', '*', '(' and every other metacharacter, and one such routine
        -- would silently widen this pattern and pull unrelated functions into the customer's
        -- reachable closure — inflating the reachability leg of every check that uses it. The
        -- identifier is constrained to the unquoted form before it is used as a pattern.
        select distinct a.proname src, b.proname dst from defs a join defs b
          on b.proname <> a.proname and b.proname ~ '^[a-z_][a-z0-9_]*$'
         and a.d ~* ('\\y'||b.proname||'\\y')
      ), reach(proname, depth) as (
        select distinct proname, 1 from defs where proname = any(${ARR(ROOT_FNS)})
        union
        select e.dst, r.depth + 1 from reach r join edges e on e.src = r.proname where r.depth < 6
      )
      select coalesce(string_agg(distinct proname, ','), '') from reach`) || '');
    CUST_FNS = raw.split(',').filter(SAFE);
  } catch (e) { closureErr = String(e && e.message || e).slice(0, 80); }
  const UI = ARR(CUST_FNS);
  const ERRSQL = (leg) => `select ${Q('ERROR customer routine closure unavailable (' + closureErr + ') — ' + leg + ' is unmeasured, not absent')}`;

  console.log(`  portal closure: ${PORTAL_FILES.length} file(s) / ${OWN_COMPS.length} own component(s) / ${MOUNTED.length} mounted; ` +
              `customer page: ${PAGE_FILES.length} file(s); reachable: ${CUST_EDGE.length} edge fn(s), ${CUST_FNS.length} routine(s)` +
              (closureErr ? ` [CLOSURE FAILED: ${closureErr}]` : ''));

  // Reachable routines that READ a relation — writers removed by pattern, overloads collapsed. The
  // write keywords are split so the read guard does not reject the check itself.
  const NOT_WRITER = (t) => `pg_get_functiondef(p.oid) !~* ('(inse'||'rt\\s+into|upd'||'ate|del'||'ete\\s+from)\\s+(public\\.)?${t}\\y')`;
  const CUST_READS = (t) => `((select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname='public' and p.prokind in ('f','p') and p.proname = any(${UI})
          and pg_get_functiondef(p.oid) ~* '\\y${t}\\y' and ${NOT_WRITER(t)})
    + ${CUST_EDGE_TABLES.includes(t) ? 1 : 0})`;
  const ALL_READS = (t) => `((select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind in ('f','p') and pg_get_functiondef(p.oid) ~* '\\y${t}\\y' and ${NOT_WRITER(t)})
    + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '\\y${t}\\y'))`;
  const REL = (t) => `(to_regclass('public.${t}') is not null)`;
  const RELTXT = (t) => `(case when to_regclass('public.${t}') is null then 'absent' else 'exists' end)`;
  const ROWS = (t, w = 'true') => `(case when to_regclass('public.${t}') is null then 'n/a' else
      (xpath('/row/c/text()', query_to_xml('select count(*) c from public.${t} where ${w.replace(/'/g, "''")}', false, true, '')))[1]::text end)`;
  const FN = (n) => `(exists (select 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.proname='${n}'))`;
  const FNTXT = (n) => `(case when ${FN(n)} then 'exists' else 'absent' end)`;

  // ── shared frontend measurements ───────────────────────────────────────────────────────────────
  // A 3D renderer is a DEPENDENCY or a WebGL context, never the word "canvas". The portal rasterises
  // an uploaded PDF page onto a 2D canvas, and the site chrome paints an animated 2D node field —
  // counting either as a 3D model would score four requirements off a background decoration.
  const PKG = (() => { try { return readFileSync(join(ROOT, 'package.json'), 'utf8'); } catch { return ''; } })();
  const DEP3D = (PKG.match(/"(three|@react-three\/[\w-]+|babylonjs[\w/-]*|@babylonjs\/[\w-]+|cesium|deck\.gl|@google\/model-viewer)"/g) || []).map(s => s.replace(/"/g, ''));
  const WEBGL = (PAGE_TEXT.match(/getContext\(\s*['"](webgl2?|experimental-webgl)['"]|WebGLRenderingContext|<Canvas[\s>]|model-viewer/g) || []).length;
  const CANVAS2D = (PAGE_TEXT.match(/getContext\(\s*['"]2d['"]|createElement\(\s*['"]canvas['"]/g) || []).length;
  const HAS_3D = DEP3D.length > 0 || WEBGL > 0;

  // A surface reached by REPLACING the page rather than by opening a window over it. Restricted to
  // navigation state on purpose: `if (err === 'unauth') return ...` and `if (!data) return ...` are
  // an error state and a loading state, and a check that counted those could not be satisfied by any
  // React component ever written.
  const PAGE_SWAPS = (OWN_TEXT.match(/if\s*\(\s*(view|tab|page|screen|route|mode|section)\s*===\s*['"][a-z_]+['"]\s*\)\s*return/g) || []).length;
  const FLOATING = (PORTAL_TEXT.match(/<(Dialog|Sheet|Popover|Drawer|Modal)[\s>]|createPortal\(|fixed\s+inset-0|position:\s*['"]fixed['"]|role=['"]dialog['"]/g) || []).length;
  const MOTION_ANY = [...SRC.keys()].filter(p => /^src\//.test(p) && /components\/motion|from\s+['"]motion/.test(text(p)));
  const MOTION_PORTAL = PORTAL_FILES.filter(p => /components\/motion|from\s+['"]motion/.test(text(p)));

  const S19 = '19. 3D / Spatial Features';
  const S20 = '20. AI Predictive Intelligence';
  const S21 = '21. Customer Portal UI Style';
  const S22 = '22. Final Structure';

  // ══ SECTION 19 — 3D / SPATIAL FEATURES ═════════════════════════════════════════════════════════

  // "A virtual Project Room containing projects, suppliers, RFQs, documents, timelines." The
  // requirement ENUMERATES five contents, so the verdict is a per-item coverage count over ONE
  // component: a portal that shows RFQs on one screen and documents on another has not built a room.
  // A global "does the word project appear anywhere in the portal" test is defect class 3 and would
  // pass on the dashboard that exists today.
  const ROOM_SUBJECTS = [
    ['projects', /project/i], ['suppliers', /supplier/i], ['rfqs', /inquir|rfq|quote/i],
    ['documents', /document|drawing|\.pdf|file_name/i], ['timelines', /timeline|milestone|schedule|target_open/i],
  ];
  //
  // SCORED ON WHAT IT RENDERS, NOT ON WHAT ITS SOURCE MENTIONS. Scored over the whole component
  // body this leg reported NewRequest — the chat card — as covering 5/5, because its source names
  // the intake endpoint, a supplier count, a drawing upload and a timeline field somewhere among its
  // handlers and its i18n keys. That is a component that TALKS ABOUT five things, not a room that
  // SHOWS five things, and had a 3D dependency ever been added it would have scored the requirement.
  const roomScore = (c) => ROOM_SUBJECTS.filter(([, re]) => re.test(interps(c.body))).length;
  const bestRoom = MOUNTED.map(c => ({ c, n: roomScore(c) })).sort((a, b) => b.n - a.n)[0] || { c: { name: 'none', body: '' }, n: 0 };
  const roomGaps = ROOM_SUBJECTS.filter(([, re]) => !re.test(interps(bestRoom.c.body || ''))).map(([k]) => k).join('/');
  const projectEndpoint = /project_api/.test(PORTAL_TEXT) || CUST_EDGE.includes('project_api');
  await req(S19, 'spatial-project-room', 'A virtual Project Room containing projects, suppliers, RFQs, documents, timelines',
    `select ${B(HAS_3D)} and ${B(bestRoom.n === 5)} and ${B(projectEndpoint)} and ${REL('projects')}`,
    `select ${Q(`3D renderer: ${DEP3D.join(',') || 'no dependency'} (webgl/3D-scene tokens ${WEBGL}); richest mounted portal surface ${bestRoom.c.name} covers ${bestRoom.n}/5 room contents${roomGaps ? ', missing ' + roomGaps : ''}; a project endpoint the customer reaches: ${projectEndpoint ? 'yes' : 'no'}`)}
       || '; public.projects ' || ${RELTXT('projects')} || ', ' || ${ROWS('projects')} || ' row(s)'`);

  // "A supply chain map from factory to warehouse to site." A map of a chain needs rows that CARRY a
  // chain: an origin and a destination on the same row. Measured by looking for the column PAIR
  // rather than by trusting a table name — po_orders sounds like logistics and holds a date and a
  // status and no geography whatsoever.
  const LEG_WHERE = `c1.table_schema='public'
       and c1.column_name ~* '(origin|from_location|from_site|source_site|factory|dispatch_from|ship_from)'
       and c2.column_name ~* '(destination|to_location|to_site|deliver_to|warehouse|ship_to|site_id)'`;
  const LEG_SQL = `(select count(distinct c1.table_name) from information_schema.columns c1
      join information_schema.columns c2 on c2.table_schema=c1.table_schema and c2.table_name=c1.table_name
     where ${LEG_WHERE})`;
  const LEG_NAMES = `coalesce((select string_agg(distinct c1.table_name, ',') from information_schema.columns c1
      join information_schema.columns c2 on c2.table_schema=c1.table_schema and c2.table_name=c1.table_name
     where ${LEG_WHERE}), 'none')`;
  const MAP_COMPS = MOUNTED.filter(c => /(supply.?chain|shipment|logistic|<Map[\s>]|MapView|\broute\b|\bleg\b)/i.test(c.body));
  await req(S19, 'spatial-supply-chain-map', 'A supply chain map from factory to warehouse to site',
    `select ${LEG_SQL} > 0 and ${B(MAP_COMPS.length > 0)}`,
    `select 'relations carrying a chain leg (an origin and a destination on one row): ' || ${LEG_SQL} || ' [' || ${LEG_NAMES}
       || ']; po_orders holds only ' || coalesce((select string_agg(column_name, ',') from information_schema.columns
            where table_schema='public' and table_name='po_orders' and column_name ~* '(date|status)'), 'no such table')
       || '; ' || ${Q(`portal component(s) rendering a chain map: ${MAP_COMPS.length} [${names(MAP_COMPS)}]`)}`);

  // "The supply chain map is animated." The animation has to be ON THE MAP. motion is installed and
  // src/components/motion is imported by the marketing components — scoring this on the existence of
  // that file would credit the customer portal with an animation that lives on the landing page.
  const ANIMATED_MAP = MAP_COMPS.filter(c => /(motion\.|<Motion|animate-|transition-|@keyframes|requestAnimationFrame)/.test(c.body));
  await req(S19, 'spatial-animated-flow', 'The supply chain map is animated',
    `select ${B(MAP_COMPS.length > 0 && ANIMATED_MAP.length > 0)}`,
    `select ${Q(`chain-map component(s) in the portal: ${MAP_COMPS.length}, of which animated: ${ANIMATED_MAP.length}; motion primitives are imported by ${MOTION_ANY.length} file(s) in src/, ${MOTION_PORTAL.length} of them inside the portal closure (${PORTAL_FILES.length} file(s))`)}`);

  // "Live shipment status is shown on the map." The population caveat is stated in words rather than
  // left to decide the verdict: production has 0 po_orders, so no check can watch a status travel.
  // What IS measurable is whether the mechanism could deliver one — a customer-reachable reader of
  // the order store, and a surface that renders its status.
  const SHIP_RENDER = MOUNTED.filter(c => /(shipment|po_no|order_status|expected_date|in_transit|shipping)/i.test(interps(c.body)));
  await req(S19, 'spatial-live-shipment-status', 'Live shipment status ("Shipping") is shown on the map',
    closureErr ? 'select false' : `select ${CUST_READS('po_orders')} > 0 and ${B(MAP_COMPS.length > 0)} and ${B(SHIP_RENDER.length > 0)}`,
    closureErr ? ERRSQL('customer-reachable readers of po_orders')
      : `select 'po_orders ' || ${RELTXT('po_orders')} || ' with ' || ${ROWS('po_orders')}
         || ' row(s) — PRODUCTION HAS NO ORDERS, so no check can observe a status reaching a screen and this is scored on the mechanism: '
         || ${ALL_READS('po_orders')} || ' reader(s) of which ' || ${CUST_READS('po_orders')} || ' reachable by a customer; '
         || ${Q(`chain-map component(s): ${MAP_COMPS.length}, component(s) rendering a shipment status: ${SHIP_RENDER.length}`)}`);

  // ══ SECTION 20 — AI PREDICTIVE INTELLIGENCE ════════════════════════════════════════════════════

  // "The portal predicts what the customer will need next." Two separable facts and production fails
  // the first: a routine that is CUSTOMER-SCOPED and FORWARD-LOOKING, reachable by a customer, whose
  // output is rendered. fn_finance_forecast() takes no arguments — it forecasts the company's cash,
  // not a customer's next requirement. customer_score.churn_risk is per-customer but is a churn
  // probability, sits on 0 rows and has no reader anywhere. Neither is a prediction of a need.
  const FUTURE_RX = `'\\y(forecast|predict|reorder|next_order|upcoming|will_need|propensity|replenish|anticipat)'`;
  const SCOPED = `(pg_get_function_arguments(p.oid) ~* 'customer' or pg_get_functiondef(p.oid) ~* '\\ycustomer_id\\y')`;
  const PRED_ALL = `(select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.prokind in ('f','p') and ${SCOPED} and pg_get_functiondef(p.oid) ~* ${FUTURE_RX})`;
  const PRED_NAMES = `coalesce((select string_agg(distinct p.proname, ',') from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.prokind in ('f','p') and ${SCOPED} and pg_get_functiondef(p.oid) ~* ${FUTURE_RX}), 'none')`;
  const PRED_REACHABLE = `(select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.prokind in ('f','p') and p.proname = any(${UI})
        and ${SCOPED} and pg_get_functiondef(p.oid) ~* ${FUTURE_RX})`;
  // A rendered prediction is an identifier inside a JSX interpolation, never a button label. `next`
  // alone is excluded deliberately: "Next" is a pagination control, not a forecast.
  const PRED_RX = /(forecast|prediction|predicted|projected|upcoming|churn|reorder|next_need|replenish|anticipat)/i;
  const PRED_RENDERERS = MOUNTED.filter(c => PRED_RX.test(interps(c.body)));
  await req(S20, 'pred-future-requirement', 'The portal predicts what the customer will need next',
    closureErr ? 'select false' : `select ${PRED_REACHABLE} > 0 and ${B(PRED_RENDERERS.length > 0)}`,
    closureErr ? ERRSQL('customer-reachable forward-looking routines')
      : `select ${PRED_ALL} || ' customer-scoped forward-looking routine(s) [' || ${PRED_NAMES} || '], of which ' || ${PRED_REACHABLE}
         || ' reachable by a customer; fn_finance_forecast(' || coalesce((select pg_get_function_arguments(p.oid) from pg_proc p
              join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_finance_forecast' limit 1), 'absent')
         || ') is company-wide; customer_score.churn_risk is set on ' || ${ROWS('customer_score', 'churn_risk is not null')}
         || ' row(s) and has ' || ${ALL_READS('churn_risk')} || ' reader(s); '
         || ${Q(`portal component(s) rendering a prediction: ${PRED_RENDERERS.length} of ${MOUNTED.length} mounted`)}`);

  // "The prediction carries a time window." Scored over the SAME population as the requirement above
  // — a horizon is only a horizon if it belongs to a prediction, and a created_at is not one. Several
  // horizon tokens are accepted so this is not satisfiable only by a column literally named horizon.
  const HORIZON_RX = `'\\y(horizon|within|days|due_at|due_date|expected_at|expected_date|window_days|lead_days)'`;
  const PRED_HORIZON = `(select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.prokind in ('f','p') and ${SCOPED}
        and pg_get_functiondef(p.oid) ~* ${FUTURE_RX} and pg_get_functiondef(p.oid) ~* ${HORIZON_RX})`;
  // THE COMMENT ABOVE SAID "same population as pred-future-requirement" AND THE VERDICT DID NOT.
  // The old form scored on `PRED_HORIZON > 0` alone: a backend-only leg, on a spec whose subject is
  // what the CUSTOMER SEES, and loose enough that any customer-scoped routine containing the word
  // forecast and the word days satisfied it. Its sibling one requirement above demands the routine
  // be customer-reachable AND rendered; two checks about one prediction may not be scored at two
  // bars. The horizon leg is now conjoined to the same reachability and render legs, so a time
  // window on a prediction the customer never sees is not a time window the customer was shown.
  await req(S20, 'pred-time-window', 'The prediction carries a time window ("within 45 days")',
    closureErr ? 'select false' : `select ${PRED_HORIZON} > 0 and ${PRED_REACHABLE} > 0 and ${B(PRED_RENDERERS.length > 0)}`,
    closureErr ? ERRSQL('customer-reachable forward-looking routines carrying a horizon')
      : `select ${PRED_ALL} || ' customer-scoped forward-looking routine(s), of which ' || ${PRED_HORIZON}
       || ' also emit a horizon (horizon/within/days/due_at/expected_at/window_days/lead_days) and ' || ${PRED_REACHABLE}
       || ' are reachable by a customer; ' || ${Q(`portal component(s) rendering a prediction: ${PRED_RENDERERS.length} of ${MOUNTED.length} mounted — the same reachability and render legs as pred-future-requirement, scored at the same bar`)}`);

  // "The prediction recommends an action." The customer's own alert builder is where such a
  // recommendation would land, so its alert KINDS are extracted from the reachable edge source and
  // classified. edit_window is a countdown on an open edit window and quotes_ready announces quotes
  // that have already arrived; neither looks forward. The second disjunct keeps the check open to an
  // implementation that puts the recommendation in a routine instead of an alert.
  const ALERT_KINDS = [...new Set([...CUST_EDGE_TEXT.matchAll(/kind:\s*['"]([a-z0-9_]+)['"]/g)].map(m => m[1]))].sort();
  const PREDICTIVE_KINDS = ALERT_KINDS.filter(k => /(forecast|predict|upcoming|reorder|renew|expir|restock|due_soon|replenish|anticipat)/.test(k));
  const ACTION_PRED = `(select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.prokind in ('f','p') and p.proname = any(${UI})
        and pg_get_functiondef(p.oid) ~* ${FUTURE_RX}
        and pg_get_functiondef(p.oid) ~* '\\y(recommend|suggested_action|next_action|advice)')`;
  const ALERTS_RENDERED = MOUNTED.some(c => /\balerts?\b/i.test(interps(c.body)));
  await req(S20, 'pred-recommended-action', 'The prediction recommends an action ("contact suppliers now")',
    closureErr ? 'select false' : `select (${B(PREDICTIVE_KINDS.length > 0)} or ${ACTION_PRED} > 0) and ${B(ALERTS_RENDERED)}`,
    closureErr ? ERRSQL('customer-reachable routines pairing a prediction with a recommendation')
      : `select ${Q(`alert kinds emitted by the ${CUST_EDGE.length} customer-reachable edge fn(s): [${ALERT_KINDS.join(',') || 'none'}], forward-looking: ${PREDICTIVE_KINDS.length}; the portal renders the alerts array: ${ALERTS_RENDERED ? 'yes' : 'no'}`)}
         || '; customer-reachable routines pairing a prediction with a recommendation: ' || ${ACTION_PRED}`);

  // "Predictions are rendered to the customer." Both halves of one claim: the figure is on screen AND
  // it came from the server. Without the second leg a hardcoded string in a card scores the
  // requirement; without the first, a payload key nothing displays does.
  const PRED_KEYS = [...new Set(MOUNTED.flatMap(c => [...interps(c.body).matchAll(/[\w$]*(?:forecast|predict|projected|upcoming|churn|reorder|replenish)[\w$]*/gi)].map(m => m[0].replace(/[^\w]/g, ''))))].filter(Boolean);
  const PRED_KEY_RX = PRED_KEYS.length ? `'\\y(${PRED_KEYS.join('|')})\\y'` : null;
  const PRED_SERVED = PRED_KEY_RX ? `(select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.prokind in ('f','p') and p.proname = any(${UI}) and pg_get_functiondef(p.oid) ~* ${PRED_KEY_RX})` : '0';
  await req(S20, 'pred-customer-ui', 'Predictions are rendered to the customer',
    closureErr ? 'select false' : `select ${PRED_SERVED} > 0`,
    closureErr ? ERRSQL('the server side of a rendered prediction')
      : `select ${Q(`prediction figure(s) inside a JSX interpolation across ${MOUNTED.length} mounted portal component(s): ${PRED_KEYS.length} [${PRED_KEYS.slice(0, 6).join(',') || 'none'}]`)}
         || '; served by ' || ${PRED_SERVED} || ' customer-reachable routine(s)'`);

  // ══ SECTION 21 — CUSTOMER PORTAL UI STYLE ══════════════════════════════════════════════════════

  // "Dark mode is an OPTION the customer can toggle." A dark palette is not an option: the portal is
  // served under a root color-scheme with no light branch, which is a decision made FOR the customer.
  // Two things are required and neither is sufficient alone — a control on the portal, and a
  // stylesheet with something to switch to. That is what stops this being satisfiable by a flag.
  const THEME_CONTROLS = (OWN_TEXT.match(/setTheme|toggleTheme|data-theme|classList\.toggle\(\s*['"]dark|setItem\(\s*['"](theme|qd-theme|color-scheme)/g) || []).length;
  const CSS_RESPONDS = (CSS.match(/\.dark\b|\[data-theme|prefers-color-scheme/g) || []).length;
  const CSS_FORCED = /color-scheme\s*:\s*dark/.test(CSS);
  await req(S21, 'ui-dark-mode-option', 'Dark mode is an option the customer can toggle',
    `select ${B(THEME_CONTROLS > 0 && CSS_RESPONDS > 0)}`,
    `select ${Q(`theme controls across the portal's ${OWN_FILES.length} own file(s): ${THEME_CONTROLS}; globals.css (${CSS.length} bytes) theme-switch selectors (.dark / [data-theme] / prefers-color-scheme): ${CSS_RESPONDS}; color-scheme:dark forced at the root: ${CSS_FORCED ? 'yes' : 'no'}`)}`);

  // "Glass / translucent interface SURFACES" — plural, so a coverage count over the portal's mounted
  // components rather than a single occurrence. Threshold 3: low enough that any portal actually
  // built in this style clears it, high enough that one blurred header does not certify a language.
  //
  // A TINT IS NOT A SURFACE. The first form of this check counted any `bg-<colour>/<alpha>` and
  // scored 9 of 17 components — on `bg-primary/10` accent chips and `border-primary/30` badge
  // outlines, which are alpha on a swatch, not glass on a panel. What counts is a blur, or
  // translucency on a SURFACE token (card / background / popover / muted / white / black). Both
  // numbers are printed so the narrower verdict shows the wider figure it rejected.
  const GLASS = MOUNTED.filter(c => /(backdrop-blur|bg-(card|background|popover|muted|white|black)\/\d{1,3}|bg-opacity-|rgba\()/.test(c.body));
  const TINTED = MOUNTED.filter(c => /bg-[\w-]+\/\d{1,3}/.test(c.body));
  await req(S21, 'ui-glass-surfaces', 'Glass / translucent interface surfaces',
    `select ${B(GLASS.length >= 3)}`,
    `select ${Q(`${GLASS.length} of ${MOUNTED.length} mounted portal component(s) carry a translucent SURFACE (blur, or alpha on card/background/popover/muted/white/black), threshold 3: [${names(GLASS)}]; ${TINTED.length} carry an accent tint of any colour, which is not a surface: [${names(TINTED)}]`)}`);

  // "Smooth animations THROUGHOUT" — same shape, same reason. The shared shadcn primitives are
  // outside the population on purpose: a Button's transition-colors is not the portal animating.
  const ANIM = MOUNTED.filter(c => /(motion\.|<Motion|framer|animate-[\w-]+|transition-[\w-]+|duration-\d+|@keyframes|requestAnimationFrame)/.test(c.body));
  await req(S21, 'ui-smooth-animations', 'Smooth animations throughout',
    `select ${B(ANIM.length >= 3)}`,
    `select ${Q(`${ANIM.length} of ${MOUNTED.length} mounted portal component(s) animate, threshold 3: [${names(ANIM)}]; motion is a dependency and src/components/motion is imported by ${MOTION_ANY.length} file(s) in src/, ${MOTION_PORTAL.length} of them in the portal`)}`);

  // "Layouts adapt / are generated by AI per customer." Two legs: the server has to SEND a layout and
  // the client has to BUILD ITS TREE FROM IT. A fixed JSX tree that hides an empty section is not an
  // adaptive layout, and a layout payload nothing maps over is defect class 2 exactly.
  const LAYOUT_PAYLOAD = (CUST_EDGE_TEXT.match(/\b(layout|widgets?|panel_order|module_order|surface_spec|sections?_order)\b\s*[:=]/g) || []).length;
  const LAYOUT_CONSUMED = (OWN_TEXT.match(/\b(layout|widgets|panels|modules)\b[\s\S]{0,120}?\.map\(/g) || []).length;
  const LAYOUT_TBL = `(select count(*) from information_schema.tables where table_schema='public'
      and table_name ~* '(layout|ui_pref|widget|dashboard_config)')`;
  await req(S21, 'ui-ai-generated-layouts', 'Layouts adapt / are generated by AI per customer',
    `select ${B(LAYOUT_PAYLOAD > 0 && LAYOUT_CONSUMED > 0)}`,
    `select ${Q(`layout descriptor(s) emitted by the ${CUST_EDGE.length} customer-reachable edge fn(s): ${LAYOUT_PAYLOAD}; places the portal builds its tree from one: ${LAYOUT_CONSUMED}`)}
       || '; per-customer layout relation(s) in public: ' || ${LAYOUT_TBL}`);

  // "3D project models appear in the UI." Guarded against the two 2D canvases the customer's page
  // already paints — the pdf.js page raster and the decorative node field. Counting either would
  // score this requirement, ui-3d-models' three neighbours in section 19, and mod-3d-project-view
  // off a background decoration.
  const SCENE_COMPS = MOUNTED.filter(c => /(<Canvas[\s>]|\bthree\b|gltf|<mesh|model-viewer|getContext\(\s*['"]webgl)/i.test(c.body));
  await req(S21, 'ui-3d-models', '3D project models appear in the UI',
    `select ${B(HAS_3D && SCENE_COMPS.length > 0)}`,
    `select ${Q(`3D dependencies in package.json: ${DEP3D.join(',') || 'none'}; WebGL/3D-scene tokens on the customer's page: ${WEBGL}; 2D canvas uses (pdf raster + node field, not models): ${CANVAS2D}; portal component(s) rendering a 3D scene: ${SCENE_COMPS.length}`)}`);

  // "Interactive graphs in the UI." recharts is installed and src/components/ui/chart.tsx is written;
  // the question is whether either reaches a customer's screen and whether what reaches it responds
  // to the pointer. A static sparkline is a graph but it is not an interactive one.
  const CHART_ANY = [...SRC.keys()].filter(p => /^src\//.test(p) && /from\s+['"]recharts['"]|ui\/chart|from\s+['"]d3|chart\.js/.test(text(p)));
  const CHART_PORTAL = PORTAL_FILES.filter(p => /from\s+['"]recharts['"]|ui\/chart|from\s+['"]d3|chart\.js/.test(text(p)));
  const CHART_COMPS = MOUNTED.filter(c => /(recharts|<(Bar|Line|Area|Pie|Radar)Chart|<ResponsiveContainer|<svg[\s>])/i.test(c.body));
  const CHART_INTERACTIVE = CHART_COMPS.filter(c => /(<Tooltip|onMouseOver|onMouseMove|onMouseEnter|onClick|hover:)/.test(c.body));
  await req(S21, 'ui-interactive-graphs', 'Interactive graphs in the UI',
    `select ${B(CHART_COMPS.length > 0 && CHART_INTERACTIVE.length > 0)}`,
    `select ${Q(`chart importers anywhere in src/: ${CHART_ANY.length} [${CHART_ANY.slice(0, 3).join(',') || 'none'}], of which inside the portal closure: ${CHART_PORTAL.length}; portal component(s) drawing a graph: ${CHART_COMPS.length}, of which interactive: ${CHART_INTERACTIVE.length}`)}`);

  // "Floating windows rather than full-page navigation." Both halves are scored because the
  // requirement is comparative: an overlay that exists beside a page swap has not replaced it.
  //
  // PAGE_SWAPS is also a leg of ui-not-sidebar-pages-tables below, and that overlap is deliberate
  // rather than a shortcut: section 21 of the spec states the same idea twice, once as "floating
  // windows rather than full-page navigation" and once as "avoids ... pages ...". Each check carries
  // legs the other does not (an overlay container here, a sidebar/table/panel count there), so
  // neither is decided by the shared number alone — which is the thing that went wrong in row #2
  // when one view definition silently scored six separate requirements.
  await req(S21, 'ui-floating-windows', 'Floating windows rather than full-page navigation',
    `select ${B(FLOATING > 0 && PAGE_SWAPS === 0)}`,
    `select ${Q(`floating containers in the portal (Dialog/Sheet/Popover/portal/fixed overlay): ${FLOATING}; full-page view swaps (a whole-surface early return keyed on navigation state): ${PAGE_SWAPS}; ui/dialog.tsx is inside the portal closure: ${PORTAL_FILES.some(p => /ui\/dialog/.test(p)) ? 'yes' : 'no'}`)}`);

  // "A smart / command search across the customer's data." cmdk is installed and ui/command.tsx is
  // written, and its only importer is the staff console shell — which is exactly why this file
  // computes a portal closure.
  //
  // PROXIMITY IS NOT A SEARCH, AND NEITHER IS A ONE-LETTER VARIABLE. Two earlier forms of this leg
  // scored MET on nothing. The first asked for search/query/filter within 160 characters of a
  // customer noun and matched `new URLSearchParams(location.search)` a few lines above
  // `action: 'my_inquiries'` — a Stripe redirect parameter certifying a command palette. The second
  // captured query-shaped useState names and found `q`, which is the message composer in Thread and
  // also the callback parameter in `quotes.map((q) => ...)`, so `\yq\y` near a `.filter(` was true
  // by arithmetic. What is left is what cannot be faked by an incidental token: a CONTROL that is
  // marked as a search, and something for it to search.
  const PALETTE_PORTAL = PORTAL_FILES.filter(p => /from\s+['"]cmdk['"]|ui\/command/.test(text(p)));
  const PALETTE_ANY = [...SRC.keys()].filter(p => /^src\//.test(p) && /from\s+['"]cmdk['"]|ui\/command/.test(text(p)));
  const SEARCH_INPUTS = (OWN_TEXT.match(/type=['"]search['"]|role=['"]search(box)?['"]|aria-label=\{?['"][^'"]{0,40}[Ss]earch|placeholder=[^>]{0,80}[Ss]earch|<CommandInput|<Search[A-Z\s/>]/g) || []).length;
  const SEARCH_TARGET = (OWN_TEXT.match(/\b(inqs|inquiries|quotes|threads|documents|suppliers|projects)\s*\.filter\(|kb_search|fn_memory_search|action:\s*['"]search/g) || []).length;
  await req(S21, 'ui-smart-search', "A smart / command search across the customer's data",
    `select ${B(PALETTE_PORTAL.length > 0 || (SEARCH_INPUTS > 0 && SEARCH_TARGET > 0))}`,
    `select ${Q(`cmdk / ui-command importers in src/: ${PALETTE_ANY.length} [${PALETTE_ANY.join(',') || 'none'}], of which inside the portal: ${PALETTE_PORTAL.length} (a palette in the portal is sufficient on its own); search-marked controls in the portal: ${SEARCH_INPUTS}; things for one to search — a direct filter over a customer collection or a search endpoint: ${SEARCH_TARGET}`)}`);

  // "Interface avoids sidebar + pages + tables + forms in favour of a workspace." Four avoidances and
  // one positive. The panel threshold is 4 because the spec's own Command Center names four panels
  // (Projects, Procurement, Financial Intelligence, Supplier Network), and the count is of DISTINCT
  // non-primitive components a single surface mounts — which is what makes it a workspace rather
  // than a page. That count does not distinguish a panel rendered beside the others from one behind
  // an early return, so it is deliberately GENEROUS; it is the page-swap leg that carries the
  // requirement's weight, and a portal with zero page swaps has no branch for a panel to hide in.
  // FORMS are counted and printed but deliberately kept OUT of the verdict: a portal has to accept
  // input somewhere, and failing it for that is a requirement nothing could ever meet.
  const SIDEBAR = (PORTAL_TEXT.match(/<aside[\s>]|role=['"]navigation['"]|(fixed|sticky)\s+(left|right)-0[\s\S]{0,60}(inset-y|top-0|h-screen)/g) || []).length;
  const TABLES = (OWN_TEXT.match(/<table[\s>]|<thead[\s>]|<tbody[\s>]/g) || []).length;
  const FORMS = (OWN_TEXT.match(/<form[\s>]/g) || []).length;
  const childrenOf = (c) => [...new Set([...c.body.matchAll(/<([A-Z][\w$]*)[\s/>]/g)].map(m => m[1]))]
    .filter(n => n !== c.name && !PRIMITIVES.has(n) && OWN_COMPS.some(o => o.name === n));
  const RICHEST = MOUNTED.map(c => ({ name: c.name, kids: childrenOf(c) })).sort((a, b) => b.kids.length - a.kids.length)[0] || { name: 'none', kids: [] };
  await req(S21, 'ui-not-sidebar-pages-tables', 'Interface avoids sidebar + pages + tables + forms in favour of a workspace',
    `select ${B(SIDEBAR === 0 && PAGE_SWAPS === 0 && TABLES === 0 && RICHEST.kids.length >= 4)}`,
    `select ${Q(`sidebar: ${SIDEBAR}, full-page swaps: ${PAGE_SWAPS}, data tables: ${TABLES}, forms: ${FORMS} (printed, not scored — a portal must accept input); richest single surface ${RICHEST.name} mounts ${RICHEST.kids.length} distinct non-primitive panel(s) [${RICHEST.kids.slice(0, 6).join(',') || 'none'}] against a threshold of 4, the panel count the spec's own Command Center names`)}`);

  // ══ SECTION 22 — FINAL STRUCTURE: THE EIGHTEEN MODULES ═════════════════════════════════════════
  //
  // ONE BAR, APPLIED IDENTICALLY EIGHTEEN TIMES. A module is a first-class portal module when:
  //
  //   FETCH   — a component in the PORTAL asks the server for it. Not the supplier portal, not the
  //             console, not the site chrome. project_api is a complete customer-authed CRUD surface
  //             and no file the customer loads names it, so Projects is not a customer module
  //             however good the endpoint is.
  //   RENDER  — the SAME component puts it inside a JSX interpolation. This is the leg that separates
  //             the built from the delivered; scoring it per component is what stops fetching in one
  //             place and rendering in another from passing by coincidence.
  //   BACKEND — the mechanism exists in the database, so a surface wired to nothing scores nothing.
  //
  // The bar is uniform on purpose. Judging each module against a bespoke standard is how a scorer
  // ends up selecting the answer it already believed.
  const MODULE = async (id, label, fetchRe, renderRe, backendSql, backendEv) => {
    const fetchers = OWN_COMPS.filter(c => fetchRe.test(c.body));
    const renderers = fetchers.filter(c => renderRe.test(interps(c.body)));
    await req(S22, id, label,
      `select ${B(fetchers.length > 0)} and ${B(renderers.length > 0)} and (${backendSql})`,
      `select ${Q(`fetched by ${fetchers.length} portal component(s) [${names(fetchers, 4)}], of which ${renderers.length} render it [${names(renderers, 4)}]`)} || '; ' || (${backendEv})`);
  };
  const EDGE_PRESENT = (n) => existsSync(join(ROOT, 'supabase', 'functions', n, 'index.ts'));

  await MODULE('mod-ai-assistant', 'Module: AI Procurement Assistant',
    /inquiry_intake/, /(brief|category|summary|emirate|trades|timeline|question|reply|assistant)/i,
    `${REL('inquiries')} and ${B(EDGE_PRESENT('inquiry_intake'))}`,
    `select 'public.inquiries ' || ${RELTXT('inquiries')} || ${Q(`, inquiry_intake edge function ${EDGE_PRESENT('inquiry_intake') ? 'present' : 'absent'}`)}`);

  await MODULE('mod-command-center', 'Module: Command Center',
    /'customer_portal'|action:\s*'overview'/, /(alert|stats|inquiries_total|open_inquiries|quotes_received|attention)/i,
    FN('fn_customer_stats'), `select 'fn_customer_stats ' || ${FNTXT('fn_customer_stats')}`);

  await MODULE('mod-digital-twin', 'Module: Company Digital Twin',
    /(fn_twin|customer_360|digital_twin|\btwin\b)/i, /(industry|annual|preferred_supplier|buying_pattern|understanding|twin)/i,
    `(${FN('fn_twin')} or ${FN('fn_ws_customer_360')})`,
    `select 'fn_twin ' || ${FNTXT('fn_twin')} || ', fn_ws_customer_360 ' || ${FNTXT('fn_ws_customer_360')} || ', v_digital_twin ' || ${RELTXT('v_digital_twin')}
       || ', customer-reachable readers of fn_ws_customer_360: ' || ${closureErr ? `'unmeasured'`
         : `(select count(distinct p.proname)::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.prokind in ('f','p') and p.proname = any(${UI}) and pg_get_functiondef(p.oid) ~* '\\yfn_ws_customer_360\\y')`}`);

  await MODULE('mod-projects', 'Module: Projects',
    /project_api/, /(project|budget_total|rfq_count|rfq_open|target_open)/i,
    REL('projects'),
    `select 'public.projects ' || ${RELTXT('projects')} || ', public.project_summary ' || ${RELTXT('project_summary')}
       || ${Q(`, project_api edge function ${EDGE_PRESENT('project_api') ? 'present' : 'absent'}`)}`);

  await MODULE('mod-3d-project-view', 'Module: 3D Project View',
    /(three|@react-three|babylonjs|model-viewer|getContext\(\s*['"]webgl)/i, /(floor|level|mesh|scene|model)/i,
    `exists (select 1 from information_schema.columns where table_schema='public' and table_name='projects' and column_name='meta')`,
    `select ${Q(`3D dependencies: ${DEP3D.join(',') || 'none'}; a per-floor dimension would have to live in projects.meta or a BOQ line — projects.meta `)}
       || (case when exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='projects' and column_name='meta') then 'exists' else 'absent' end)`);

  await MODULE('mod-rfq-management', 'Module: RFQ Management',
    /action:\s*'my_inquiries'/, /(inquir|status|quotes|category|emirate)/i,
    REL('inquiries'), `select 'public.inquiries ' || ${RELTXT('inquiries')} || ', ' || ${ROWS('inquiries')} || ' row(s)'`);

  await MODULE('mod-supplier-discovery', 'Module: Supplier Discovery',
    /(fn_match_capability|action:\s*'(discover|find_suppliers|search_suppliers|match)')/i,
    /(similarity|match_reason|matched_suppliers|found|supplier)/i,
    `${FN('fn_match_capability')}`,
    `select 'fn_match_capability ' || ${FNTXT('fn_match_capability')}
       || ' — the one matcher on the dispatch path (the keyword matcher was dropped 15 Sep 2026); no customer action invokes discovery on its own'`);

  await MODULE('mod-quote-comparison', 'Module: Quote Comparison',
    /'quote_compare'/, /(top3|bottom_line|advice|watch_outs|analysis|tradeoff|why|rank)/i,
    REL('quotes'),
    `select 'public.quotes ' || ${RELTXT('quotes')} || ', ' || ${ROWS('quotes')}
       || ' row(s) — PRODUCTION HAS NO QUOTES, so the comparison is scored on the mechanism, not on traffic'`);

  await MODULE('mod-negotiation-ai', 'Module: Negotiation AI',
    /(negotiat|counter_offer|supplier_negotiation_policy)/i, /(target|counter|leverage|market_average|draft|negotiat)/i,
    REL('supplier_negotiation_policy'),
    `select 'public.supplier_negotiation_policy ' || ${RELTXT('supplier_negotiation_policy')} || ' with ' || ${ROWS('supplier_negotiation_policy')}
       || ' row(s) and ' || ${ALL_READS('supplier_negotiation_policy')} || ' routine/view reader(s) anywhere'`);

  await MODULE('mod-orders', 'Module: Orders',
    /(po_orders|purchase_order|action:\s*'orders'|po_no)/i, /(po_no|order_date|expected_date|order|vendor)/i,
    REL('po_orders'),
    `select 'public.po_orders ' || ${RELTXT('po_orders')} || ' with ' || ${ALL_READS('po_orders')} || ' reader(s) anywhere, of which '
       || ${closureErr ? `'unmeasured'` : CUST_READS('po_orders')} || ' customer-reachable'`);

  // mod-approvals retired 14 Sep 2026 with the Approvals tab. Founder: "i think its better just to remove the approvals tab. cause even if a company signed up, we don't wanna interfere in their approvals process and they are treated like normal individuals".

  await MODULE('mod-documents', 'Module: Documents',
    /(action:\s*'(documents|my_documents|vault|list_documents)'|fn_ws_documents|document_inventory)/i,
    /(document|kind|expiry|file_name|vault)/i,
    REL('documents'),
    `select 'public.documents ' || ${RELTXT('documents')} || ' with ' || ${ALL_READS('documents')}
       || ' routine/view reader(s); fn_ws_documents ' || ${FNTXT('fn_ws_documents')} || ' and is a workspace/staff routine'`);

  await MODULE('mod-communication', 'Module: Communication',
    /'messages_api'/, /(thread|body|subject|message|last_at|sender)/i,
    `(${REL('messages')} and ${REL('chat_threads')})`,
    `select 'public.messages ' || ${RELTXT('messages')} || ' (' || ${ROWS('messages')} || ' rows), public.chat_threads '
       || ${RELTXT('chat_threads')} || ' (' || ${ROWS('chat_threads')} || ' rows)'`);

  // Analytics is the one module whose RENDER leg is a MARK rather than a key. Six KPI numbers are not
  // an analytics module — the spec asks for a surface beyond the tiles — so the leg asks the fetching
  // component to draw a series. Everything else about the bar is identical to the other seventeen.
  {
    const fetchers = OWN_COMPS.filter(c => /('customer_portal'|fn_customer_stats|action:\s*'overview')/.test(c.body));
    const drawers = fetchers.filter(c => /(recharts|<(Bar|Line|Area|Pie)Chart|<ResponsiveContainer|<svg[\s>]|<polyline|<rect\s)/i.test(c.body));
    await req(S22, 'mod-analytics', 'Module: Analytics',
      `select ${B(fetchers.length > 0)} and ${B(drawers.length > 0)} and ${FN('fn_customer_stats')}`,
      `select ${Q(`fetched by ${fetchers.length} portal component(s) [${names(fetchers, 4)}], of which ${drawers.length} draw a series rather than a number — six KPI tiles are not an analytics surface`)}
         || '; fn_customer_stats ' || ${FNTXT('fn_customer_stats')}`);
  }

  await MODULE('mod-spending-intelligence', 'Module: Spending Intelligence',
    /(history_12m|action:\s*'overview'|fn_customer_stats)/, /(history_12m|by_month|by_category|monthly|spend_series|breakdown|trend)/i,
    `${FN('fn_customer_stats')} and (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname='public' and p.proname='fn_customer_stats' and pg_get_functiondef(p.oid) ~* '\\yhistory_12m\\y') > 0`,
    `select 'fn_customer_stats emits history_12m: ' || (case when (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
          where n.nspname='public' and p.proname='fn_customer_stats' and pg_get_functiondef(p.oid) ~* '\\yhistory_12m\\y') > 0
        then 'yes' else 'no' end)
       || ${Q(`; history_12m is rendered by [${[...SRC.keys()].filter(p => /^src\//.test(p) && /history_12m/.test(text(p))).join(',') || 'no file'}], ${PORTAL_FILES.some(p => /history_12m/.test(text(p))) ? 'inside' : 'outside'} the customer portal`)}`);

  await MODULE('mod-supplier-relationships', 'Module: Supplier Relationships',
    /action:\s*'supplier_history'/, /(projects_count|reliability|quality|relationship|rating|supplier)/i,
    REL('supplier_score'),
    `select 'public.supplier_score ' || ${RELTXT('supplier_score')} || ' with ' || ${ROWS('supplier_score')}
       || ' row(s); customer_api action=supplier_history is named by ' ||
       ${Q(String([...SRC.keys()].filter(p => /^src\//.test(p) && /supplier_history/.test(text(p))).length))} || ' file(s) in src/'`);

  await MODULE('mod-forecasting', 'Module: Forecasting',
    /(forecast|fn_finance_forecast|projection)/i, /(forecast|projected|next_year|projection)/i,
    FN('fn_finance_forecast'),
    `select 'fn_finance_forecast(' || coalesce((select pg_get_function_arguments(p.oid) from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_finance_forecast' limit 1), 'absent')
       || ') — no argument means company-wide, and there is no per-customer forecast routine'`);

  // Settings deliberately does NOT accept `save_customer`. That action is the KYC identity gate the
  // customer passes ONCE before the portal opens — a compliance step, not a settings surface — and
  // accepting it would score this requirement off an onboarding form the customer can never return
  // to. The actions that would serve a settings module are me / settings / preferences.
  await MODULE('mod-settings', 'Module: Settings',
    /action:\s*'(me|settings|preferences|save_prefs|update_profile)'/, /(setting|preference|notification|locale|language|profile)/i,
    REL('customers'),
    `select 'public.customers ' || ${RELTXT('customers')} || ', public.customer_preference ' || ${RELTXT('customer_preference')}
       || ${Q(`; the portal header offers ${/signout|sign_out|Sign out/i.test(OWN_TEXT) ? 'sign-out' : 'no sign-out'} and ${/qd-lang|setLang/.test(OWN_TEXT) ? 'a language switch' : 'no language switch'} only`)}`);
}
