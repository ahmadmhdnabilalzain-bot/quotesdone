// PHASE D DELIVERABLE — PHASE_D_FRONTEND_API_CALL_GRAPH.csv
//
//   node scripts/phase_d/build_frontend_api_call_graph.mjs
//
// One row per distinct (component, edge_function) pair, traced through every layer the brief names:
//
//   component -> how it builds the URL -> deployed edge function -> canonical service -> object
//
// Every layer is resolved from the repository and the database, never asserted. A layer that cannot
// be resolved is written as the empty string and the row's status says which layer broke, because a
// call graph that quietly drops its unresolved edges is a map of the parts that already worked.
//
// ─────────────────────────────────────────────────────────────────────────────────────────────────
// WHAT THIS FILE USED TO REPORT, AND WHY IT WAS WRONG. Measured 19 Aug 2026.
//
// The committed deliverable held 26 rows over 4 files and 17 distinct edge functions. The frontend
// reaches 39. Three separate defects, each of which alone would have been enough:
//
//  1. THE WRITE CAME BEFORE THE GUARD. `writeFileSync(...)` at :169-170, then
//     `if (!rows.length) { ... process.exit(1); }` at :172. A run that resolved nothing wrote a
//     header-only CSV to the tracked path and THEN exited 1. Nobody reads the exit code of a build
//     step run by hand; the empty file is what got committed. The guard is now above the write, and
//     it is a floor rather than a non-zero test — see below.
//
//  2. ONLY ONE OF FIVE URL SHAPES WAS MATCHED. Both resolution paths looked for the literal
//     `functions/v1/<name>`. The five shapes actually in src/, all measured:
//
//       A  `${SUPA_FN}/${fn}`          per-surface call(fn, body, token) helpers — the endpoint is
//                                      the first argument at each call site, not in the helper
//       B  FN + '/' + path             the same idea written with concatenation (SupplierPortal,
//                                      CustomerPortal, and 20 supplier surfaces)
//       C  `${SUPA_FN}/customer_documents`   template with the name written in
//       D  FN + '/contact_submit'      concatenation with the name written in
//       E  SUPA_URL + '/functions/v1/os_api' the only shape the old matcher could see
//
//     src/lib/supaEnv.ts:21 declares `SUPA_FN = ${SUPA_URL}/functions/v1`, so shapes A–D never
//     contain the string `functions/v1` at all. Thirty-three files import it; the matcher saw none
//     of them.
//
//  3. `walk('src/lib')`. Four files. Every component lives under src/app and src/components.
//
// ─────────────────────────────────────────────────────────────────────────────────────────────────
// A MENTION IS NOT A CALL. Measured 20 Aug 2026.
//
// The matcher had no comment awareness, so a comment that ILLUSTRATES a call counted as one.
// src/components/portal/approvals/api.ts:5 and src/components/portal/predict/api.ts:5 each carry
// the line `call<T>('procurement_api', …)` / `call<T>('negotiation_assistant', …)` explaining why
// their helper is deliberately not generic. Neither file calls anything: each only DEFINES
// `call(fn, body, token)` at :19, and the real call sites live in ApprovalChain.tsx, OrdersList.tsx
// and NegotiationAssistant.tsx, which already contribute their own rows. The two comments were
// fabricating two edges — and the two files they fabricated them for, which is why the builder read
// 41 files where the frontend has 39.
//
// This is the same lesson this estate learned when `grep -rn "\.rpc(" src/` was quoted as evidence
// of a browser surface: a mention is not a call. Comment lines are dropped before any pattern runs.
// ─────────────────────────────────────────────────────────────────────────────────────────────────
// THE ATTRIBUTION MODEL, stated because the row count is meaningless without it.
//
// A row is a distinct (file, edge function) pair where THAT FILE'S OWN SOURCE names the endpoint.
// Two consequences worth being explicit about:
//
//   · It is not call sites. src/components/me/CustomerPortal.tsx makes 36 calls to 12 endpoints and
//     contributes 12 rows, not 36. A guard written against call sites would read ~138 and sail past
//     any floor set for pairs. The raw site count is carried in its own column instead.
//   · An endpoint reached through an imported client method is attributed to the module that holds
//     the URL, not to every component that imports it. src/lib/osClient.ts contributes its 9
//     endpoints once; the 13 methods OsxShell.tsx imports do not re-attribute them there. The
//     alternative was measured too — it yields 84 pairs — and it answers a different question
//     ("who can reach this?" rather than "where is this URL written?"). The column header says
//     which question this file answers.
//
// The realtime subscription is included as its own edge with edge_function `(realtime)`:
// src/components/osx/OsxShell.tsx:284 opens `supa.channel('osx-live')` and binds 14 postgres_changes
// listeners. It is not an edge function and is not counted as one, but a call graph that omits the
// only live-data channel in the application is not a call graph.
import { readFileSync, writeFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { sql } from '../phase_c/lib/db.mjs';
import { outPath, provenance } from './lib/deliverable.mjs';

// THE FLOOR. Independently measured 20 Aug 2026 against this working tree and used as a floor, not
// an equality: a frontend that grows must not make this build fail, and a matcher that regresses
// must. The old builder's own guard (`rows.length` non-zero) could not tell 26 from 79.
//
// `pairs` counts ROWS, and the realtime channel is a row, so 77 = 76 edge-function pairs + 1
// realtime. `functions` excludes it. The two are deliberately not the same number and the previous
// floor of 76 had them conflated — it compared a 77-row count against a 76-pair measurement and so
// sat one short of the truth it was quoting.
const FLOOR = { pairs: 77, files: 39, functions: 39 };

const rel = (p) => p.split('\\').join('/');
function walk(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (/\.(ts|tsx|js|jsx)$/.test(e)) out.push(rel(p));
  }
  return out;
}

// ---- layer 1: every file in the frontend, and the endpoints its own source names ----------------
//
// A MENTION IS NOT A CALL — see the header. Whole-line comments are blanked before any pattern in
// this file runs, so an illustrative `call<T>('procurement_api', …)` in prose cannot become an edge.
// Blanked rather than deleted so line numbers still line up with the file on disk when debugging.
//
// ponytail: line-based, not a tokeniser. It does not strip a trailing `// …` on a line that also
// carries code, nor a block-comment continuation line that does not start with `*`. Both are
// FALSE-NEGATIVE shapes for stripping — they leave a mention visible — so the floor below catches a
// regression the other way; upgrade to a real tokeniser only if a mention ever slips through one.
const stripComments = (text) => text.split('\n')
  .map((l) => (/^\s*(\/\/|\/\*|\*)/.test(l) ? '' : l)).join('\n');
const source = new Map(walk('src').map((f) => [f, stripComments(readFileSync(f, 'utf8'))]));
if (!source.size) {
  console.error('src/ holds no source files — refusing to write a call graph over nothing');
  process.exit(1);
}

const SHAPES = [
  ['functions_v1_literal', /functions\/v1\/([A-Za-z0-9_-]+)/g],
  ['template_literal', /\$\{\s*(?:SUPA_FN|FN)\s*\}\/([A-Za-z0-9_-]+)/g],
  ['string_concat', /\b(?:SUPA_FN|FN)\s*\+\s*['"]\/([A-Za-z0-9_-]+)['"]/g],
];
// A helper that builds the URL from a VARIABLE: `${SUPA_FN}/${fn}` or FN + '/' + path. The endpoint
// is at the call site, so a file carrying one of these is asked for its call(...) literals instead.
const VARIABLE_HELPER = /\$\{\s*(?:SUPA_FN|FN)\s*\}\/\$\{|\b(?:SUPA_FN|FN)\s*\+\s*['"]\/['"]\s*\+/;
// `call<T>(...)` as well as `call(...)`: src/components/portal/comms/api.ts:157 is generic, and
// missing it would drop the whole messages surface.
const CALL_SITE = /\bcall\s*(?:<[^>]*>)?\s*\(\s*['"]([A-Za-z0-9_-]+)['"]/g;

const matches = (text, re) => { const out = []; re.lastIndex = 0; let m; while ((m = re.exec(text))) out.push(m[1]); return out; };

const helperModules = new Set([...source].filter(([, s]) => VARIABLE_HELPER.test(s)).map(([f]) => f));

function importedNames(text) {
  const out = []; const re = /import\s+(?:type\s+)?\{([^}]*)\}\s*from\s*['"]([^'"]+)['"]/g; let m;
  while ((m = re.exec(text))) out.push({ spec: m[2], names: m[1].split(',').map((x) => x.trim().split(/\s+as\s+/)[0].trim()).filter(Boolean) });
  return out;
}
function resolveImport(fromFile, spec) {
  let base;
  if (spec.startsWith('@/')) base = 'src/' + spec.slice(2);
  else if (spec.startsWith('.')) base = rel(join(fromFile, '..', spec));
  else return null;
  for (const ext of ['.ts', '.tsx', '.js', '.jsx', '/index.ts', '/index.tsx']) if (source.has(base + ext)) return base + ext;
  return source.has(base) ? base : null;
}

// file -> endpoint -> { shapes:Set, sites:number }
const edges = new Map();
const addEdge = (file, endpoint, shape, sites) => {
  if (!edges.has(file)) edges.set(file, new Map());
  const m = edges.get(file);
  if (!m.has(endpoint)) m.set(endpoint, { shapes: new Set(), sites: 0 });
  m.get(endpoint).shapes.add(shape);
  m.get(endpoint).sites += sites;
};

for (const [file, text] of source) {
  for (const [shape, re] of SHAPES) {
    const found = matches(text, re);
    for (const ep of new Set(found)) addEdge(file, ep, shape, found.filter((x) => x === ep).length);
  }
  // A file resolves call(...) literals if it defines a variable-endpoint helper itself, or imports
  // `call` from a module that does. Gating it on that is what keeps an unrelated function named
  // `call` in some other file out of the graph.
  const usesHelper = helperModules.has(file)
    || importedNames(text).some((im) => im.names.includes('call') && helperModules.has(resolveImport(file, im.spec)));
  if (usesHelper) {
    const found = matches(text, CALL_SITE);
    for (const ep of new Set(found)) addEdge(file, ep, 'call_helper', found.filter((x) => x === ep).length);
  }
  // The one realtime channel in the application. `grep -rn "\.channel(" src/` returns this line only.
  const chan = matches(text, /\bsupa\.channel\(\s*['"]([A-Za-z0-9_-]+)['"]/g);
  for (const c of new Set(chan)) {
    const listeners = (text.match(/postgres_changes/g) || []).length;
    addEdge(file, '(realtime)', `realtime_channel:${c} · ${listeners} postgres_changes listener(s)`, listeners || 1);
  }
}

// ---- layer 2: does the edge function exist in the repository? -----------------------------------
const fnDir = 'supabase/functions';
const deployedNames = new Set(existsSync(fnDir) ? readdirSync(fnDir).filter((d) => {
  try { return statSync(join(fnDir, d)).isDirectory(); } catch { return false; }
}) : []);

// ---- layer 3: which canonical services does that edge function call? ----------------------------
const fnRpcs = new Map();
for (const name of deployedNames) {
  const idx = join(fnDir, name, 'index.ts');
  if (!existsSync(idx)) { fnRpcs.set(name, []); continue; }
  const src = readFileSync(idx, 'utf8');
  const rpcs = new Set();
  for (const m of src.matchAll(/\.rpc\(\s*['"]([A-Za-z0-9_]+)['"]/g)) rpcs.add(m[1]);
  for (const m of src.matchAll(/from\(\s*['"]([A-Za-z0-9_]+)['"]/g)) rpcs.add('table:' + m[1]);
  fnRpcs.set(name, [...rpcs]);
}

// ---- layer 4: the objects those services / relations are bound to -------------------------------
const bindings = await sql(`select object_id, canonical_relation, canonical_write_service
                              from public.phase_d_business_object_binding`);
const byService = new Map();
const byRelation = new Map();
for (const b of bindings) {
  if (b.canonical_write_service) {
    const fn = String(b.canonical_write_service).replace(/^public\./, '').replace(/\(.*$/, '');
    if (!byService.has(fn)) byService.set(fn, []);
    byService.get(fn).push(b.object_id);
  }
  if (b.canonical_relation) {
    const t = String(b.canonical_relation).replace(/^public\./, '');
    if (!byRelation.has(t)) byRelation.set(t, []);
    byRelation.get(t).push(b.object_id);
  }
}
const live = new Set((await sql(
  `select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'`
)).map((r) => r.proname));

// ---- assemble -----------------------------------------------------------------------------------
const rows = [];
for (const [component, byEndpoint] of edges) {
  for (const [fn, info] of byEndpoint) {
    const realtime = fn === '(realtime)';
    const fnPresent = !realtime && deployedNames.has(fn);
    const rpcs = fnPresent ? (fnRpcs.get(fn) || []) : [];
    const services = rpcs.filter((r) => !r.startsWith('table:'));
    const tables = rpcs.filter((r) => r.startsWith('table:')).map((t) => t.slice(6));
    const objects = new Set();
    for (const svc of services) for (const o of (byService.get(svc) || [])) objects.add(o);
    for (const t of tables) for (const o of (byRelation.get(t) || [])) objects.add(o);
    const servicesLive = services.filter((x) => live.has(x));

    let status;
    if (realtime) status = 'REALTIME_SUBSCRIPTION_NOT_AN_EDGE_FUNCTION';
    else if (!fnPresent) status = 'EDGE_FUNCTION_NOT_IN_REPOSITORY';
    else if (services.length === 0 && tables.length === 0) status = 'EDGE_FUNCTION_CALLS_NO_SERVICE_OR_TABLE';
    else if (services.length > 0 && servicesLive.length === 0) status = 'SERVICE_NOT_PRESENT_ON_THE_DATABASE';
    else if (objects.size === 0) status = 'NO_BOUND_PHASE_D_OBJECT_ON_THIS_PATH';
    else status = 'FULL_APPLICATION_PATH_CONNECTED';

    rows.push([component, [...info.shapes].sort().join(';'), info.sites, fn,
               realtime ? 'n/a' : (fnPresent ? 'yes' : 'no'),
               servicesLive.join(';'), tables.join(';'), [...objects].sort().join(';'), status]);
  }
}
rows.sort((a, b) => (a[0] + '|' + a[3]).localeCompare(b[0] + '|' + b[3]));

// ---- refuse BEFORE writing ----------------------------------------------------------------------
//
// The old order wrote the file and then exited 1. Everything below runs first, and nothing reaches
// disk until it passes.
const files = new Set(rows.map((r) => r[0]));
const functions = new Set(rows.map((r) => r[3]).filter((f) => f !== '(realtime)'));
const sites = rows.reduce((a, r) => a + r[2], 0);
const short = [];
if (rows.length < FLOOR.pairs) short.push(`${rows.length} (component, edge_function) pair(s), floor ${FLOOR.pairs}`);
if (files.size < FLOOR.files) short.push(`${files.size} file(s), floor ${FLOOR.files}`);
if (functions.size < FLOOR.functions) short.push(`${functions.size} edge function(s), floor ${FLOOR.functions}`);
if (short.length) {
  console.error('refusing to write the call graph — the matcher resolved less than the frontend is '
    + `independently known to reach:\n  ${short.join('\n  ')}\n`
    + '  Measured 20 Aug 2026: 39 files, 39 edge functions, 77 rows (76 pairs + 1 realtime).\n'
    + '  If a surface was genuinely deleted, lower the floor in this file and say which one in the\n'
    + '  commit; do not delete the guard. A short call graph reads as "this is what the frontend\n'
    + '  reaches" and it would not be.');
  process.exit(1);
}
const notInRepo = [...functions].filter((f) => !deployedNames.has(f));
if (notInRepo.length) {
  console.error(`the matcher resolved endpoint(s) with no function directory: ${notInRepo.join(', ')}. `
    + 'That is a matcher fault (a path fragment read as a function name), not a deployment gap; '
    + 'refusing to write it.');
  process.exit(1);
}

const cell = (v) => { const t = v == null ? '' : String(v); return /[",\n\r]/.test(t) ? '"' + t.replace(/"/g, '""') + '"' : t; };
const COLS = ['component', 'url_shape', 'call_sites', 'edge_function', 'edge_function_in_repo',
              'canonical_services', 'tables_touched', 'phase_d_objects', 'status'];
writeFileSync(outPath('PHASE_D_FRONTEND_API_CALL_GRAPH.csv'),
  provenance({
    command: 'node scripts/phase_d/build_frontend_api_call_graph.mjs',
    // ONE POPULATION ON BOTH SIDES OF THE FRACTION. This read `${rows.length} of ${sites} raw call
    // sites, collapsed into ${rows.length} pairs` — a numerator counting pairs over a denominator
    // counting call sites, which is not a fraction of anything. Every row the matcher resolved is
    // written (nothing is filtered between the two), so the honest denominator is the resolved pair
    // count itself, exactly as the sibling builders state 56 of 56 objects and 86 of 86 subjects.
    // The raw call-site count is a real measurement and keeps its place — in the prose, where it is
    // not read as a denominator, and in its own `call_sites` column.
    numerator: rows.length,
    denominator: rows.length,
    of: `distinct (component, edge_function) pairs resolved from the frontend, across `
      + `${files.size} file(s) and ${functions.size} edge function(s), written from `
      + `${sites} raw call site(s)`,
    attribution: 'one row per distinct (component, edge_function) pair, attributed to the file whose '
      + 'own source names the endpoint — not per call site, and not to importers of a client method',
  })
  + [COLS.join(',')].concat(rows.map((r) => r.map(cell).join(','))).join('\n') + '\n');

const by = {};
for (const r of rows) by[r[8]] = (by[r[8]] || 0) + 1;
const heaviest = [...edges].map(([f, m]) => [f, m.size]).sort((a, b) => b[1] - a[1]).slice(0, 5);
console.log(`PHASE_D_FRONTEND_API_CALL_GRAPH.csv  ${rows.length} pair(s) · ${files.size} file(s) · `
  + `${functions.size} edge function(s) · ${sites} raw call site(s)`);
for (const k of Object.keys(by).sort()) console.log(`  ${k.padEnd(44)} ${by[k]}`);
console.log('  heaviest files:');
for (const [f, n] of heaviest) console.log(`    ${f.padEnd(46)} ${n}`);
