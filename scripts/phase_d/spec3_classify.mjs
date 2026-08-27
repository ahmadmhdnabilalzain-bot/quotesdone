// SPEC FILE #3 — the same 152 checks as scripts/staging/verify_os2_blueprint.mjs, but every
// verdict is written out WHOLE.
//
// The scorer prints evidence truncated to 120 characters, which is the right length for a console
// and the wrong length for a classification: "missing: none" and a freshness cutoff both disappear
// into the same ellipsis. Classifying the 48 MISSING lines needs the full evidence string AND the
// boolean SQL that produced the verdict, so this runs the identical section modules with a `req`
// that records both, and writes JSON.
//
//   node scripts/phase_d/spec3_classify.mjs --out=<file.json>
//
// READ-ONLY. Same management-API reads as the scorer, same rate limits, same several minutes.
// It scores nothing and it prints no percentage: the score is the scorer's job, not this one's.
import { mgmtRead, PROD_REF } from '../staging/qd_guard.mjs';
import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join, dirname, relative, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { uiClosure } from '../staging/os2_blueprint/ui_closure.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..', '..');
const DIR = join(ROOT, 'scripts', 'staging', 'os2_blueprint');
const OUT = (process.argv.find(a => a.startsWith('--out=')) || '--out=spec3_full.json').slice(6);
const TARGET = PROD_REF;

const rows = [];
const qAll = async (sql) => await mgmtRead(TARGET, sql);
const q = async (sql) => (await qAll(sql))[0];
const one = async (sql) => { const r = await q(sql); return r ? Object.values(r)[0] : null; };

async function req(section, id, name, sql, evidenceSql) {
  let ok = false, ev = '', err = null;
  try { ok = String(await one(sql)) === 'true'; } catch (e) { err = 'PREDICATE ' + String(e.message || e); }
  try { ev = evidenceSql ? String(await one(evidenceSql)) : ''; } catch (e) { err = (err ? err + ' | ' : '') + 'EVIDENCE ' + String(e.message || e); }
  rows.push({ section, id, name, ok, ev, err, sql: String(sql), evidence_sql: evidenceSql ? String(evidenceSql) : null });
  console.log(`${ok ? 'MET    ' : 'MISSING'} ${id}`);
}

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

const srcPaths = (pathRe) => [...SRC.keys()].filter(p => !pathRe || pathRe.test(p));
const srcText = (pathRe) => srcPaths(pathRe).map(p => SRC.get(p)).join('\n');
const srcCount = (re, pathRe) => srcPaths(pathRe)
  .reduce((n, p) => n + (SRC.get(p).match(new RegExp(re.source, re.flags.includes('g') ? re.flags : re.flags + 'g')) || []).length, 0);
const srcHas = (re, pathRe) => srcCount(re, pathRe) > 0;
const Q = (s) => `'${String(s == null ? '' : s).replace(/'/g, "''")}'`;
const B = (v) => (v ? 'true' : 'false');
const READERS = (t) => `(
    (select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> '${t}'
        and pg_get_functiondef(p.oid) ~* '\y${t}\y')
  + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '\y${t}\y')
  + (select count(*) from cron.job j where j.command ~* '\y${t}\y'))`;
const HAS_READER = (t) => `select ${READERS(t)} > 0`;
const N_READERS = (t) => `select ${READERS(t)}::text || ' reader(s)'`;
const INPROMPT = (needle, agent = 'cfo', budget = 22000) =>
  `select public.fn_agent_context('${agent}', ${budget}) like '%${needle.replace(/'/g, "''")}%'`;
const COL = (t, c) => `select exists (select 1 from information_schema.columns
  where table_schema='public' and table_name='${t}' and column_name='${c}')`;
const NROWS = (t, w = 'true') => `select (select count(*) from public.${t} where ${w})::text`;
const HAS_ROWS = (t, w = 'true') => `select (select count(*) from public.${t} where ${w}) > 0`;
const FN_EXISTS = (n) => `select exists (select 1 from pg_proc p join pg_namespace ns
  on ns.oid=p.pronamespace where ns.nspname='public' and p.proname='${n}')`;

const ui = await uiClosure(qAll, ROOT);
const helpers = { req, one, q, qAll, ui, TARGET, ROOT,
  READERS, HAS_READER, N_READERS, INPROMPT, COL, NROWS, HAS_ROWS, FN_EXISTS,
  SRC, srcPaths, srcText, srcCount, srcHas, Q, B };

const files = readdirSync(DIR).filter(f => f.endsWith('.mjs') && !f.startsWith('_') && f !== 'ui_closure.mjs').sort();
for (const f of files) {
  const mod = await import(pathToFileURL(join(DIR, f)).href);
  if (typeof mod.default !== 'function') continue;
  try { await mod.default(helpers); }
  catch (e) { console.log(`  !! ${f} THREW: ${String(e && e.message || e).slice(0, 200)}`); }
}

writeFileSync(OUT, JSON.stringify(rows, null, 2));
console.log(`\n${rows.length} check(s), ${rows.filter(r => !r.ok).length} MISSING -> ${OUT}`);
