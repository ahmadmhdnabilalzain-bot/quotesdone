// SPEC FILE #8 — OPENROUTER COST OPTIMIZATION, scored against PRODUCTION.
//
// 226 requirements across five parts, enumerated in docs/sessions/ROW8_REQUIREMENTS.md.
//
//   node scripts/staging/verify_ai_router.mjs             # read-only, PRODUCTION
//   node scripts/staging/verify_ai_router.mjs --staging
//   node scripts/staging/verify_ai_router.mjs --only=cache-
//   node scripts/staging/verify_ai_router.mjs --json=x.json
//
// The runner is verify_supplier_blueprint.mjs's and verify_category_agents.mjs's, unchanged in
// every respect that matters: modules DISCOVERED not listed, each declaring its own EXPECTED,
// evidence beside every verdict, an evidence failure invalidating its verdict rather than surviving
// it, and the total asserted at the end.
//
// ── WHAT IS DIFFERENT, AND IT IS THE WHOLE POINT OF THIS ROW ─────────────────────────────────────
// Row #5 scored a screen. Row #6 scored a corpus. Row #8 scores a CONTROL SYSTEM, and a control
// system can be present, correct and NEVER EXERCISED. Both facts have to be checked separately or
// the score is a lie in one of two directions.
//
// `llm_cache` is the case that forces it. Four routines exist to read and write that table
// (fn_llm_cache_get, fn_llm_cache_lookup, fn_llm_cache_put, fn_llm_cache_store), it carries a
// semantic `embedding_gte` column, and measured on production 2026-08-09 it holds ZERO rows against
// 1,021 logged AI calls of which TWO were served from cache. A scorer that asked only "does a cache
// exist" would report the spec's §7 and §32 MET and hide the largest unrealised saving in the
// estate.
//
// So `-exists` and `-used` are different requirements with different evidence, and an `-exists` MET
// beside a `-used` MISSING is the most informative pair this file can print. They are never averaged.
//
// ── THE EVIDENCE TABLE IS ai_cost_log, NOT pg_proc ───────────────────────────────────────────────
// Every one of the spec's 45 OS items can be answered "yes, there is a routine for that", and this
// estate really does have fn_ai_route, fn_select_model, fn_llm_cache_put, fn_budget_available,
// fn_model_benchmark, fn_model_autoswitch and eight observability views. A scorer that greps pg_proc
// scores this row in the high nineties and tells the founder nothing.
//
// So every BEHAVIOURAL requirement is scored over ai_cost_log's 1,021 production rows, and the
// evidence prints the row count that backs it. USED(...) is the helper that does it and it is the
// one to reach for whenever the spec's verb is "uses", "routes", "caches" or "falls back".
import { readdirSync, existsSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { mgmtRead, PROD_REF } from './qd_guard.mjs';
import { REF as STAGE } from './demo_factory.mjs';

const TARGET = process.argv.includes('--staging') ? STAGE : PROD_REF;
const ONLY = (process.argv.find(a => a.startsWith('--only=')) || '').slice(7);
const JSON_OUT = (process.argv.find(a => a.startsWith('--json=')) || '').slice(7);
const TOTAL = 226;

const rows = [];
const q = async (sql) => (await mgmtRead(TARGET, sql))[0];
const one = async (sql) => { const r = await q(sql); return r ? Object.values(r)[0] : null; };
const many = (sql) => mgmtRead(TARGET, sql);

// Identical to rows #5 and #6, including WHY: a MET whose evidence threw is a claim with nothing
// behind it, and it was also double-counted — listed among the errored checks while still adding 1
// to `met`. The two queries are caught separately and an evidence failure forces ok=false.
async function req(section, id, name, sql, evidenceSql) {
  if (ONLY && !section.startsWith(ONLY) && !id.startsWith(ONLY)) return;
  let ok = false, ev = '';
  try { ok = String(await one(sql)) === 'true'; }
  catch (e) { ok = false; ev = 'ERROR(verdict) ' + String(e.message || e).slice(0, 100); }
  if (!String(ev).startsWith('ERROR')) {
    try { ev = evidenceSql ? String(await one(evidenceSql)) : ''; }
    catch (e) { ok = false; ev = 'ERROR(evidence) ' + String(e.message || e).slice(0, 100); }
  }
  rows.push({ section, id, name, ok, ev });
  console.log(`${ok ? 'MET    ' : 'MISSING'} ${id.padEnd(34)} ${String(ev).slice(0, 92)}`);
}

const GUARD = /\b(insert|update|delete|truncate|drop|alter|create|grant|revoke|vacuum|reindex|call|do)\b/gi;
const B = (v) => 'select ' + (v ? 'true' : 'false');
const Q = (s) => "select '" + String(s == null ? '' : s).replace(/'/g, "''")
  .replace(GUARD, (m) => m.slice(0, 1) + "'||'" + m.slice(1)) + "'";

// ── THE SOURCE SURFACE ───────────────────────────────────────────────────────────────────────────
// The spec describes an architecture that lives in edge functions and the web app, not only in SQL.
// Both trees are walked once and cached; a module that wants "is this implemented anywhere in the
// running system" asks SRC, and one that means "in a server routine" asks FN_SRC instead. Keeping
// them separate is what stops a comment in a React component from satisfying a routing requirement.
const REPO = fileURLToPath(new URL('../../', import.meta.url));
function walk(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) { if (!/node_modules|\.next|dist|\.git/.test(e.name)) walk(p, out); }
    else if (/\.(ts|tsx|mjs|js|sql)$/.test(e.name) && statSync(p).size < 900_000) out.push(p);
  }
  return out;
}
const EDGE = walk(join(REPO, 'supabase', 'functions'));
const APP = walk(join(REPO, 'src'));
const SQLF = walk(join(REPO, 'scripts', 'sql'));
const _cache = new Map();
const src = (f) => { if (!_cache.has(f)) { try { _cache.set(f, readFileSync(f, 'utf8')); } catch { _cache.set(f, ''); } } return _cache.get(f); };
const filesMatching = (re, list) => list.filter(f => re.test(src(f)));
const anyFile = (re, list) => filesMatching(re, list).length > 0;
const base = (f) => f.split(/[\\/]/).pop();
// Two tokens inside ONE file, within `win` characters. Row #5's lesson: "does this FILE contain X
// and Y" is nearly vacuous against an 80k-character monolith; adjacency inside one file is a real
// fact, adjacency across a repo is not.
const near = (text, a, b, win = 400) => {
  for (const m of text.matchAll(new RegExp(a.source, a.flags.replace('g', '') + 'g'))) {
    const s = Math.max(0, m.index - win), e = m.index + m[0].length + win;
    if (b.test(text.slice(s, e))) return true;
  }
  return false;
};
const filesNear = (a, b, win, list) => list.filter(f => near(src(f), a, b, win));

// ── SQL-SIDE HELPERS ─────────────────────────────────────────────────────────────────────────────
const FN_EXISTS = (n) => `select exists (select 1 from pg_proc p join pg_namespace ns
  on ns.oid=p.pronamespace where ns.nspname='public' and p.proname='${n}')`;
const FNS_MATCHING = (pat) => `(select coalesce(string_agg(p.proname, ' '), '') from pg_proc p
  join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public'
  and p.prokind in ('f','p') and pg_get_functiondef(p.oid) ~* '${pat}')`;
const TABLE_EXISTS = (t) => `select exists (select 1 from information_schema.tables
  where table_schema='public' and table_name='${t}')`;
const COL_EXISTS = (t, c) => `select exists (select 1 from information_schema.columns
  where table_schema='public' and table_name='${t}' and column_name='${c}')`;
const NROWS = (t, w = 'true') => `select (select count(*) from public.${t} where ${w})::text`;
const HAS_ROWS = (t, w = 'true') => `select (select count(*) from public.${t} where ${w}) > 0`;

// THE `-used` HELPER. Production traffic, not capability. `w` is a predicate over ai_cost_log.
const USED = (w) => `select (select count(*) from public.ai_cost_log where ${w}) > 0`;
const USED_N = (label, w) => `select '${label.replace(/'/g, "''")}: ' ||
  (select count(*) from public.ai_cost_log where ${w})::text || ' of ' ||
  (select count(*) from public.ai_cost_log)::text || ' logged AI call(s)'`;

const helpers = {
  req, one, q, many, B, Q, EDGE, APP, SQLF, src, base, filesMatching, anyFile, near, filesNear,
  FN_EXISTS, FNS_MATCHING, TABLE_EXISTS, COL_EXISTS, NROWS, HAS_ROWS, USED, USED_N, TARGET,
};

console.log(`\nSPEC FILE #8 — OpenRouter cost optimization, scored against ${TARGET}`);
console.log(`source surface: ${EDGE.length} edge file(s), ${APP.length} app file(s), ${SQLF.length} sql file(s)\n`);

const DIR = fileURLToPath(new URL('./ai_router/', import.meta.url));
const files = existsSync(DIR) ? readdirSync(DIR).filter(f => f.endsWith('.mjs')).sort() : [];
if (!files.length) console.log(`  !! ${DIR} contains no section module.`);

let shortfall = 0;
for (const f of files) {
  console.log(`\n--- ${f} ---`);
  const before = rows.length;
  let mod;
  try { mod = await import(new URL('./ai_router/' + f, import.meta.url)); }
  catch (e) { shortfall++; console.log(`  !! ${f} FAILED TO LOAD, so none of its checks ran: ${String(e && e.message || e).slice(0, 200)}`); continue; }
  if (typeof mod.default !== 'function') { shortfall++; console.log(`  !! ${f} exports no default section function — skipped`); continue; }
  try { await mod.default(helpers); }
  catch (e) { shortfall++; console.log(`  !! ${f} THREW; its remaining checks did not run: ${String(e && e.message || e).slice(0, 200)}`); }
  const got = rows.length - before;
  const expected = mod.EXPECTED;
  if (!ONLY && typeof expected !== 'number') { shortfall++; console.log(`  !! ${f} exports no EXPECTED count — its ${got} check(s) cannot be verified`); }
  else if (!ONLY && got !== expected) { shortfall++; console.log(`  !! ${f} registered ${got} checks, expected ${expected}`); }
}

const met = rows.filter(r => r.ok).length;
const errs = rows.filter(r => String(r.ev).startsWith('ERROR'));
console.log(`\n${'='.repeat(78)}`);
for (const r of rows.filter(r => !r.ok)) console.log(`  NOT MET  ${r.id.padEnd(34)} ${r.name}`);
if (errs.length) {
  console.log(`\n  ${errs.length} CHECK(S) ERRORED — an errored check is NOT a MISSING verdict, it is`);
  console.log(`  an unmeasured requirement, and reporting it as MISSING would be a false negative:`);
  for (const e of errs) console.log(`    ${e.id.padEnd(34)} ${e.ev}`);
}
if (shortfall) console.log(`\n  !! ${shortfall} section(s) registered the wrong number of checks —` +
  ` the denominator is wrong, so the percentage below is NOT trustworthy.`);
if (!ONLY && rows.length !== TOTAL) console.log(`  !! ${rows.length} checks ran, the spec has ${TOTAL}` +
  ` — ${TOTAL - rows.length} requirement(s) have no section module yet and are NOT scored below.`);
if (JSON_OUT) { writeFileSync(JSON_OUT, JSON.stringify({ target: TARGET, total: TOTAL, met, rows }, null, 1)); console.log(`\n  full evidence written to ${JSON_OUT}`); }

// THE PAIR REPORT. The whole reason this row is scored the way it is: a mechanism that exists and
// is never exercised is the finding, and a single percentage buries it.
const ex = rows.filter(r => r.id.endsWith('-exists')), us = rows.filter(r => r.id.endsWith('-used'));
if (ex.length || us.length) {
  console.log(`\n  BUILT-BUT-UNUSED: ${ex.filter(r => r.ok).length}/${ex.length} mechanisms exist,` +
    ` ${us.filter(r => r.ok).length}/${us.length} of them appear in production traffic`);
}
const bySection = {};
for (const r of rows) { (bySection[r.section] ||= [0, 0])[r.ok ? 0 : 1]++; }
console.log('\n  per section:');
for (const [s, [ok, no]] of Object.entries(bySection)) {
  console.log(`    ${s.padEnd(30)} ${String(ok).padStart(3)}/${String(ok + no).padStart(3)}` +
    ` (${String(Math.round(100 * ok / (ok + no))).padStart(3)}%)${no ? '' : '  complete'}`);
}
console.log(`\nSPEC FILE #8 (openrouter cost optimization) on ${TARGET}: ${met}/${rows.length}` +
            ` (${(100 * met / (rows.length || 1)).toFixed(0)}%) of ${TOTAL} requirement(s)`);
process.exit(met === rows.length && !shortfall && !errs.length && (ONLY || rows.length === TOTAL) ? 0 : 1);
