// PHASE D DELIVERABLE — PHASE_D_FRONTEND_API_CALL_GRAPH.csv
//
// One row per FRONTEND CALL SITE, traced through every layer the brief names:
//
//   component -> client method -> deployed edge function -> canonical service -> object/effect
//
// Every layer is resolved from the repository and the database, never asserted. A layer that cannot
// be resolved is written as the empty string and the row's status says which layer broke, because a
// call graph that quietly drops its unresolved edges is a map of the parts that already worked.
//
//   node scripts/phase_d/build_frontend_api_call_graph.mjs
import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { sql } from '../phase_c/lib/db.mjs';

function walk(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    const st = statSync(p);
    if (st.isDirectory()) walk(p, out);
    else if (/\.(ts|tsx|js|jsx)$/.test(e)) out.push(p);
  }
  return out;
}

const rel = p => p.replace(/\\/g, '/');

// ---- layer 2: the client methods, and the edge function each one posts to ----------------------
const clientFiles = walk('src/lib');
const clientMethod = new Map();          // method name -> { file, fn }
for (const f of clientFiles) {
  const src = readFileSync(f, 'utf8');
  const re = /export\s+(?:async\s+)?function\s+([A-Za-z0-9_]+)/g;
  let m;
  while ((m = re.exec(src))) {
    const name = m[1];
    // the edge function is the first functions/v1/<name> reached from this declaration onward,
    // bounded by the next export so a later method's endpoint is not attributed to this one.
    const from = m.index;
    const nextExport = src.indexOf('\nexport ', from + 1);
    const body = src.slice(from, nextExport < 0 ? src.length : nextExport);
    const ep = body.match(/functions\/v1\/([A-Za-z0-9_-]+)/);
    clientMethod.set(name, { file: rel(f), fn: ep ? ep[1] : '' });
  }
}

// A client method that reaches its endpoint THROUGH ANOTHER client method resolves to the same
// endpoint. Nine methods here wrap osApi(action, body), which posts to functions/v1/os_api; leaving
// them unresolved would report a broken path for calls that work, and a call graph that drops its
// indirect edges is a map of the parts that were already easy.
for (let pass = 0; pass < 5; pass++) {
  let moved = 0;
  for (const [name, info] of clientMethod) {
    if (info.fn) continue;
    const src = readFileSync(info.file, 'utf8');
    const m = src.match(new RegExp(`export\\s+(?:async\\s+)?function\\s+${name}\\b`));
    if (!m) continue;
    const from = src.indexOf(m[0]);
    const next = src.indexOf('\nexport ', from + 1);
    const body = src.slice(from, next < 0 ? src.length : next);
    for (const [other, oi] of clientMethod) {
      if (other === name || !oi.fn) continue;
      if (new RegExp(`\\b${other}\\s*\\(`).test(body)) {
        info.fn = oi.fn; info.via = other; moved++; break;
      }
    }
  }
  if (!moved) break;
}

// ---- layer 1: the call sites -------------------------------------------------------------------
const appFiles = [...walk('src/app'), ...walk('src/components')];
const sites = [];
for (const f of appFiles) {
  const src = readFileSync(f, 'utf8');
  for (const [name, info] of clientMethod) {
    // a call, not a mention: the identifier followed by an opening parenthesis
    const called = new RegExp(`\\b${name}\\s*\\(`).test(src);
    if (called && new RegExp(`from\\s+['"][^'"]*osClient`).test(src)) {
      sites.push({ component: rel(f), method: name, fn: info.fn, methodFile: info.file });
    }
  }
  // a component that reaches an edge function directly, without going through a client method
  const direct = src.match(/functions\/v1\/([A-Za-z0-9_-]+)/g) || [];
  for (const d of new Set(direct)) {
    sites.push({ component: rel(f), method: '(direct fetch)', fn: d.split('/').pop(), methodFile: '' });
  }
}

// ---- layer 3: does the edge function exist in the repository? -----------------------------------
const fnDir = 'supabase/functions';
const deployedNames = new Set(existsSync(fnDir) ? readdirSync(fnDir).filter(d => {
  try { return statSync(join(fnDir, d)).isDirectory(); } catch { return false; }
}) : []);

// ---- layer 4: which canonical services does that edge function call? ----------------------------
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

// ---- layer 5: the objects those services / relations are bound to -------------------------------
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
)).map(r => r.proname));

// ---- assemble -----------------------------------------------------------------------------------
const seen = new Set();
const rows = [];
for (const s of sites) {
  const key = `${s.component}|${s.method}|${s.fn}`;
  if (seen.has(key)) continue;
  seen.add(key);

  const fnPresent = s.fn && deployedNames.has(s.fn);
  const rpcs = fnPresent ? (fnRpcs.get(s.fn) || []) : [];
  const services = rpcs.filter(r => !r.startsWith('table:'));
  const tables = rpcs.filter(r => r.startsWith('table:')).map(t => t.slice(6));
  const objects = new Set();
  for (const svc of services) for (const o of (byService.get(svc) || [])) objects.add(o);
  for (const t of tables) for (const o of (byRelation.get(t) || [])) objects.add(o);
  const servicesLive = services.filter(x => live.has(x));

  let status;
  if (!s.fn) status = 'CLIENT_METHOD_REACHES_NO_EDGE_FUNCTION';
  else if (!fnPresent) status = 'EDGE_FUNCTION_NOT_IN_REPOSITORY';
  else if (services.length === 0 && tables.length === 0) status = 'EDGE_FUNCTION_CALLS_NO_SERVICE_OR_TABLE';
  else if (services.length > 0 && servicesLive.length === 0) status = 'SERVICE_NOT_PRESENT_ON_THE_DATABASE';
  else if (objects.size === 0) status = 'NO_BOUND_PHASE_D_OBJECT_ON_THIS_PATH';
  else status = 'FULL_APPLICATION_PATH_CONNECTED';

  rows.push([
    s.component, s.method, s.methodFile, s.fn,
    fnPresent ? 'yes' : 'no',
    servicesLive.join(';'), tables.join(';'), [...objects].sort().join(';'), status,
  ]);
}
rows.sort((a, b) => (a[0] + a[1]).localeCompare(b[0] + b[1]));

const cell = v => { const t = v == null ? '' : String(v); return /[",\n\r]/.test(t) ? '"' + t.replace(/"/g, '""') + '"' : t; };
const COLS = ['component', 'client_method', 'client_method_file', 'edge_function',
              'edge_function_in_repo', 'canonical_services', 'tables_touched',
              'phase_d_objects', 'status'];
mkdirSync('docs/phase-d', { recursive: true });
writeFileSync('docs/phase-d/PHASE_D_FRONTEND_API_CALL_GRAPH.csv',
  [COLS.join(',')].concat(rows.map(r => r.map(cell).join(','))).join('\n') + '\n');

if (!rows.length) { console.error('no call sites resolved — refusing to write an empty call graph'); process.exit(1); }
const by = {};
for (const r of rows) by[r[8]] = (by[r[8]] || 0) + 1;
console.log(`PHASE_D_FRONTEND_API_CALL_GRAPH.csv  ${rows.length} call site(s)`);
for (const k of Object.keys(by).sort()) console.log(`  ${k.padEnd(42)} ${by[k]}`);
