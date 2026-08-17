// THE COMPONENT CROSSWALK, VERIFIED IN BOTH HALVES AND IN THREE PLACES.
//
//   node scripts/checks/phase_c_component_crosswalk.test.mjs            static + live (needs a token)
//   node scripts/checks/phase_c_component_crosswalk.test.mjs --static   committed files only
//   node scripts/checks/phase_c_component_crosswalk.test.mjs --require-live
//
// THE DEFECT THIS EXISTS TO CATCH, found by the final Phase C re-acceptance on 17 Aug 2026:
//   scripts/sql/rc4_execution_and_trace_are_atomic.sql registered two new runtime components on
//   production — dbfn:fn_kernel_signal_submit(jsonb) and dbfn:fn_kernel_trigger_submit(jsonb) —
//   and did not extend docs/phase-c/PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv. Production held 1801
//   rows, the committed crosswalk held 1799, and the repository and the database disagreed about
//   what the runtime IS. Nothing in CI could see it: the one check that compares them skips
//   without a management token, and CI has none.
//
// THREE SOURCES, COMPARED PAIRWISE:
//   A  committed DECLARATIONS — every `insert into public.phase_c_component (...) values (...)`
//      in a committed .sql file, read with a scanner that understands SQL string quoting, so a
//      semicolon or a comma inside an evidence sentence cannot truncate the statement.
//   B  the committed CROSSWALK — docs/phase-c/PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv.
//   C  LIVE public.phase_c_component.
//
// WHAT FAILS:
//   A -> B   a committed declaration the crosswalk does not carry
//   B -> A   a crosswalk row no committed file declares, unless it is named in
//            docs/phase-c/COMPONENT_CROSSWALK_HISTORICAL.txt with a reason
//   C -> B   a live application component the crosswalk does not carry
//   B -> C   a crosswalk application component that is not live
//   duplicates in any of the three
//   metadata that disagrees between B and C on any crosswalk column
//
// THE CREDENTIAL RULE, which is the other half of the defect:
//   A missing management token may NOT read as success. The static half asserts and exits on its
//   own; the live half, when it is asked for, prints NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL
//   and exits 1. `--static` is the honest way to ask for the half that needs no credential — it
//   says plainly that it asserted nothing about production.
//
// READ-ONLY against production. Every statement it sends is a SELECT.
import { readdirSync, readFileSync, existsSync } from 'node:fs';

const ROOT = process.cwd().replace(/\\/g, '/');
const PROD = 'htdblwldjkcgjvmqkbeh';
const CSV = 'docs/phase-c/PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv';
const HISTORICAL = 'docs/phase-c/COMPONENT_CROSSWALK_HISTORICAL.txt';
const STATIC_ONLY = process.argv.includes('--static');
const REQUIRE_LIVE = process.argv.includes('--require-live');

const read = p => { try { return readFileSync(`${ROOT}/${p}`, 'utf8'); } catch { return null; } };

// ---------------------------------------------------------------- A: committed declarations
/**
 * Split a SQL statement's VALUES list into tuples, respecting single-quoted strings, dollar
 * quotes and line comments. A previous attempt used /values([\s\S]*?);/ and lost 1788 of 1801
 * declarations, because `'switched off after 15 runs; last 2026-08-02'` ends a statement as far
 * as a regex is concerned.
 */
function scanValues(text, from) {
  const tuples = [];
  let i = from, depth = 0, cur = '', inStr = false, dollar = null;
  for (; i < text.length; i++) {
    const c = text[i];
    if (dollar) { if (text.startsWith(dollar, i)) { cur += dollar; i += dollar.length - 1; dollar = null; } else cur += c; continue; }
    if (inStr) {
      cur += c;
      if (c === "'") { if (text[i + 1] === "'") { cur += "'"; i++; } else inStr = false; }
      continue;
    }
    if (c === "'") { inStr = true; cur += c; continue; }
    if (c === '$') { const m = text.slice(i).match(/^\$[A-Za-z0-9_]*\$/); if (m) { dollar = m[0]; cur += m[0]; i += m[0].length - 1; continue; } }
    if (c === '-' && text[i + 1] === '-') { const e = text.indexOf('\n', i); i = e < 0 ? text.length : e; continue; }
    // The VALUES list ends at ON CONFLICT / RETURNING. Without this the `(component_id)` of an
    // upsert's conflict target is scanned as a tuple and declares a component called
    // "component_id" — 1802 declarations for 1801 components.
    if (depth === 0 && /^(on\s+conflict|returning)\b/i.test(text.slice(i, i + 14))) break;
    if (c === '(') { depth++; if (depth === 1) { cur = ''; continue; } }
    if (c === ')') { depth--; if (depth === 0) { tuples.push(cur); cur = ''; continue; } }
    if (c === ';' && depth === 0) break;
    if (depth > 0) cur += c;
  }
  return { tuples, end: i };
}

/** Split one tuple's text into its literal fields, again respecting quoting. */
function splitTuple(t) {
  const out = []; let cur = '', inStr = false, depth = 0;
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (inStr) { cur += c; if (c === "'") { if (t[i + 1] === "'") { cur += "'"; i++; } else inStr = false; } continue; }
    if (c === "'") { inStr = true; cur += c; continue; }
    if (c === '(') depth++;
    if (c === ')') depth--;
    if (c === ',' && depth === 0) { out.push(cur.trim()); cur = ''; continue; }
    cur += c;
  }
  out.push(cur.trim());
  return out.map(v => {
    const s = v.trim();
    if (s.startsWith("'") && s.endsWith("'")) return s.slice(1, -1).replace(/''/g, "'");
    if (/^(true|false)$/i.test(s)) return s.toLowerCase();
    if (/^null$/i.test(s)) return '';
    return s;
  });
}

const SQL_DIRS = ['scripts/sql', 'supabase/migrations', 'supabase/migrations_history', 'ai-organization/db-functions'];
const sqlFiles = SQL_DIRS.flatMap(d => {
  try { return readdirSync(`${ROOT}/${d}`).filter(f => f.endsWith('.sql')).map(f => `${d}/${f}`); } catch { return []; }
});

const declared = new Map();          // component_id -> {file, fields}
const declaredDupes = [];
const nonLiteralSources = [];        // insert ... select: recorded, never guessed at
for (const f of sqlFiles) {
  const t = read(f);
  if (!t || !/phase_c_component/i.test(t)) continue;
  const re = /insert\s+into\s+(?:public\.)?phase_c_component\b/gi;
  let m;
  while ((m = re.exec(t))) {
    const after = t.slice(m.index);
    const vi = after.search(/\bvalues\b/i);
    const si = after.search(/\bselect\b/i);
    if (vi < 0 || (si >= 0 && si < vi)) { nonLiteralSources.push(`${f} (insert ... select)`); continue; }
    // the parenthesised column list sits between the table name and VALUES
    const colsRaw = after.slice(0, vi);
    const co = colsRaw.indexOf('(');
    const cols = co >= 0 ? splitTuple(colsRaw.slice(co + 1, colsRaw.lastIndexOf(')'))).map(s => s.trim()) : [];
    const { tuples, end } = scanValues(after, vi + 'values'.length);
    for (const tup of tuples) {
      const vals = splitTuple(tup);
      const id = vals[0];
      if (!id) continue;
      const fields = {};
      cols.forEach((c, i) => { fields[c] = vals[i] ?? ''; });
      if (declared.has(id)) declaredDupes.push(`${id}  ${declared.get(id).file}  and  ${f}`);
      declared.set(id, { file: f, fields });
    }
    re.lastIndex = m.index + Math.max(end, m[0].length);
  }
}

// ---------------------------------------------------------------- B: the committed crosswalk
function parseCsv(text) {
  const rows = []; let cur = [], f = '', inq = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inq) { if (c === '"') { if (text[i + 1] === '"') { f += '"'; i++; } else inq = false; } else f += c; }
    else if (c === '"') inq = true;
    else if (c === ',') { cur.push(f); f = ''; }
    else if (c === '\n') { cur.push(f); rows.push(cur); cur = []; f = ''; }
    else if (c !== '\r') f += c;
  }
  if (f !== '' || cur.length) { cur.push(f); rows.push(cur); }
  return rows.filter(r => r.length > 1 || (r[0] || '').trim() !== '');
}

const csvText = read(CSV);
if (csvText === null) { console.error(`FAIL: ${CSV} is missing`); process.exit(1); }
const csvRows = parseCsv(csvText);
const CSV_COLS = csvRows[0];
const crosswalk = new Map();
const crosswalkDupes = [], malformed = [];
for (const r of csvRows.slice(1)) {
  if (r.length !== CSV_COLS.length) { malformed.push(r[0]); continue; }
  const o = {}; CSV_COLS.forEach((c, i) => { o[c] = r[i]; });
  if (crosswalk.has(o.component_id)) crosswalkDupes.push(o.component_id);
  crosswalk.set(o.component_id, o);
}

const historical = new Map();
for (const line of (read(HISTORICAL) || '').split(/\r?\n/)) {
  const l = line.trim();
  if (!l || l.startsWith('#')) continue;
  const [id, ...why] = l.split('::').map(s => s.trim());
  if (id && why.join('::')) historical.set(id, why.join('::'));
}

// ---------------------------------------------------------------- the report
const F = [];                                     // failures
const fail = (kind, detail) => F.push(`${kind}  ${detail}`);

for (const d of declaredDupes) fail('DUPLICATE DECLARATION', d);
for (const d of crosswalkDupes) fail('DUPLICATE CROSSWALK ROW', d);
for (const m of malformed) fail('MALFORMED CROSSWALK ROW', m);

for (const [id, d] of declared) {
  if (!crosswalk.has(id)) fail('DECLARED, NOT IN THE CROSSWALK', `${id}   declared in ${d.file}`);
}
for (const [id] of crosswalk) {
  if (declared.has(id)) continue;
  if (historical.has(id)) continue;
  fail('IN THE CROSSWALK, NOT DECLARED', id);
}

console.log(`A committed declarations : ${declared.size}   (from ${new Set([...declared.values()].map(d => d.file)).size} file(s))`);
if (nonLiteralSources.length) {
  console.log(`  non-literal declaration sources, recorded rather than guessed at: ${nonLiteralSources.length}`);
  [...new Set(nonLiteralSources)].slice(0, 5).forEach(s => console.log(`    ${s}`));
}
console.log(`B committed crosswalk    : ${crosswalk.size}`);
console.log(`  rows accepted as historical with a stated reason: ${[...crosswalk.keys()].filter(id => !declared.has(id) && historical.has(id)).length}`);

// ---------------------------------------------------------------- C: production
const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

let liveChecked = false;
if (STATIC_ONLY) {
  console.log(`C live production        : NOT COMPARED (--static). This run asserts nothing about production.`);
} else if (!token) {
  // NOT a skip and NOT a pass. The static half above is asserted and reported on its own terms;
  // production is reported as unverified, by that exact name, in every mode. `--require-live` is
  // how the secure job says "the credential is mandatory here", and a missing one fails it.
  console.log(`C live production        : NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL`);
} else {
  liveChecked = true;
  const q = async text => {
    for (let a = 0; ; a++) {
      const r = await fetch(`https://api.supabase.com/v1/projects/${PROD}/database/query`, {
        method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
        body: JSON.stringify({ query: text }),
      });
      const body = await r.text();
      if ((r.status === 429 || r.status >= 500) && a < 6) { await new Promise(z => setTimeout(z, 2000 * 2 ** a)); continue; }
      if (!r.ok) throw new Error(`HTTP ${r.status}: ${body.slice(0, 400)}`);
      return JSON.parse(body);
    }
  };
  const liveRows = await q(`select ${CSV_COLS.join(', ')} from public.phase_c_component order by component_id`);
  const live = new Map();
  const liveDupes = [];
  for (const r of liveRows) {
    if (live.has(r.component_id)) liveDupes.push(r.component_id);
    live.set(r.component_id, r);
  }
  for (const d of liveDupes) fail('DUPLICATE LIVE ROW', d);

  for (const [id] of live) if (!crosswalk.has(id)) fail('LIVE, NOT IN THE CROSSWALK', id);
  for (const [id] of crosswalk) if (!live.has(id)) fail('IN THE CROSSWALK, NOT LIVE', id);

  // metadata compatibility, column by column, for the rows both sides carry
  // The crosswalk writes booleans as yes/no and the column is boolean on production, so the same
  // fact arrives as 'yes' and as true. gen_registry_load.mjs maps them with the same equivalence;
  // comparing the spellings instead of the facts would report 1801 rows as incompatible.
  const BOOL = { yes: 'true', true: 'true', no: 'false', false: 'false' };
  const norm = v => {
    const s = (v === null || v === undefined ? '' : String(v)).replace(/\s+/g, ' ').trim();
    return BOOL[s.toLowerCase()] ?? s;
  };
  let mismatched = 0;
  for (const [id, c] of crosswalk) {
    const l = live.get(id); if (!l) continue;
    for (const col of CSV_COLS) {
      if (norm(c[col]) !== norm(l[col])) {
        mismatched++;
        if (mismatched <= 20) fail('INCOMPATIBLE METADATA', `${id}  ${col}\n        crosswalk: ${norm(c[col]).slice(0, 120)}\n        live     : ${norm(l[col]).slice(0, 120)}`);
      }
    }
  }
  console.log(`C live production        : ${live.size}`);
  console.log(`  columns compared per row: ${CSV_COLS.length}   incompatible cells: ${mismatched}`);

  // --emit rewrites the committed crosswalk from production. It exists because the crosswalk is a
  // MIRROR of what the runtime is, not an independent opinion about it: when the two disagree the
  // database is the fact and the file is the stale copy. The alternative — comparing only the
  // columns that happen to agree — is the narrowing this check exists to prevent.
  if (process.argv.includes('--emit')) {
    const esc = v => {
      const s = v === null || v === undefined ? '' : String(v);
      return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    };
    const order = [...crosswalk.keys()].filter(id => live.has(id))
      .concat([...live.keys()].filter(id => !crosswalk.has(id)));   // keep the committed order
    const out = [CSV_COLS.join(',')];
    for (const id of order) out.push(CSV_COLS.map(c => esc(norm(live.get(id)[c]) === 'true' || norm(live.get(id)[c]) === 'false'
      ? (crosswalk.get(id) && /^(yes|no)$/i.test(String(crosswalk.get(id)[c] ?? '')) ? (norm(live.get(id)[c]) === 'true' ? 'yes' : 'no') : live.get(id)[c])
      : live.get(id)[c])).join(','));
    (await import('node:fs')).writeFileSync(`${ROOT}/${CSV}`, out.join('\n') + '\n', 'utf8');
    console.log(`  --emit: rewrote ${CSV} from production (${order.length} rows)`);
  }
}

console.log(`\n---------------------------------------------------------------- SUMMARY`);
console.log(`  committed declarations           ${declared.size}`);
console.log(`  committed crosswalk rows         ${crosswalk.size}`);
console.log(`  live component rows              ${liveChecked ? 'compared' : (STATIC_ONLY ? 'not compared (--static)' : 'not compared')}`);
console.log(`  findings                         ${F.length}`);
for (const f of F.slice(0, 40)) console.log(`    ${f}`);
if (F.length > 40) console.log(`    ... and ${F.length - 40} more`);

if (REQUIRE_LIVE && !liveChecked) {
  console.log(`\nThis run was asked for the production half and could not do it.`);
  console.log(`NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL`);
  process.exit(1);
}
console.log(`\n${F.length ? 'FAIL'
  : liveChecked ? 'PASS (static and production)'
    : STATIC_ONLY ? 'STATIC PASS — production NOT COMPARED (--static)'
      : 'STATIC PASS — production NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL'}`);
process.exit(F.length ? 1 : 0);
