// SPEC FILE #3 — the EXECUTIVE UI (OS 2.txt), scored against PRODUCTION, symmetrically.
//
// 152 requirements. This spec file is not about whether the company computes something; it is about
// whether the FOUNDER CAN SEE IT. Production computes an autonomous company every night and renders
// almost none of it: graph_nodes carries 323 nodes rebuilt by an active cron and has zero readers
// anywhere. So every check here asks FOUR questions, and conflating any two of them is how the
// previous scorecard came out wrong:
//
//   1. does the mechanism EXIST (table, column, routine, view)?
//   2. is it POPULATED, and does it RUN (a succeeded run, never a schedule)?
//   3. does anything READ its output — excluding the thing that WROTE it?
//   4. does it REACH A SCREEN the founder actually opens?
//
// A table with rows and no reader scores NO. A number returned to the browser and never rendered
// scores NO. A number rendered on one surface and absent from the other three, where the
// requirement says ANY, scores NO.
//
//   node scripts/archive/staging/verify_os2_blueprint.mjs              # read-only, PRODUCTION, zero spend
//   node scripts/archive/staging/verify_os2_blueprint.mjs --staging    # same checks against staging
//   node scripts/archive/staging/verify_os2_blueprint.mjs --only=layers-9-15
//
// EXPECT IT TO BE SLOW. Every check is a sequential management-API read and the API rate-limits
// hard; qd_guard retries with exponential backoff. Several minutes is normal. It is not a hang.
import { mgmtRead, PROD_REF } from '../../lib/qd_guard.mjs';
import { recordBlueprintRun, printBlueprintDiff } from './blueprint_history.mjs';
import { REF as STAGE } from '../../lib/demo_factory.mjs';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, dirname, relative, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { uiClosure } from './os2_blueprint/ui_closure.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..', '..');
const DIR = join(HERE, 'os2_blueprint');

const TARGET = process.argv.includes('--staging') ? STAGE : PROD_REF;
const ONLY = (process.argv.find(a => a.startsWith('--only=')) || '').slice(7);

const rows = [];
const qAll = async (sql) => await mgmtRead(TARGET, sql);
const q = async (sql) => (await qAll(sql))[0];
const one = async (sql) => { const r = await q(sql); return r ? Object.values(r)[0] : null; };

// A requirement is MET only when its evidence query returns true. `evidence` prints either way, so
// a MET verdict carries its proof and a MISSING verdict carries the number that refutes it.
async function req(section, id, name, sql, evidenceSql) {
  if (ONLY && !section.startsWith(ONLY) && !id.startsWith(ONLY)) return;
  let ok = false, ev = '';
  try {
    ok = String(await one(sql)) === 'true';
    ev = evidenceSql ? String(await one(evidenceSql)) : '';
  } catch (e) { ev = 'ERROR ' + String(e.message || e).slice(0, 110); }
  rows.push({ section, id, name, ok, ev });
  console.log(`${ok ? 'MET    ' : 'MISSING'} ${id.padEnd(34)} ${String(ev).slice(0, 120)}`);
}

// ── THE FRONTEND IS HALF THE EVIDENCE ────────────────────────────────────────────────────────────
// Row #2 could score entirely in SQL because it asked about the machine. This row asks what the
// screen shows, and no query against Postgres can answer that. So the source tree is loaded once
// and handed to every section: a check that claims "the founder sees X" must point at the line that
// renders it, and a check that claims "nothing renders X" must be a count over files, not a memory.
const SRC = new Map();
(function walk(dir) {
  let entries; try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) { if (!/^(node_modules|\.next|dist|build)$/.test(e.name)) walk(p); }
    else if (/\.(ts|tsx|js|jsx|mjs)$/.test(e.name)) {
      try { if (statSync(p).size < 4_000_000) SRC.set(relative(ROOT, p).split(sep).join('/'), readFileSync(p, 'utf8')); } catch { /* unreadable */ }
    }
  }
})(join(ROOT, 'src'));
(function walk(dir) {
  let entries; try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p);
    else if (/\.(ts|tsx|js|jsx)$/.test(e.name)) {
      try { SRC.set(relative(ROOT, p).split(sep).join('/'), readFileSync(p, 'utf8')); } catch { /* unreadable */ }
    }
  }
})(join(ROOT, 'supabase', 'functions'));

const srcPaths = (pathRe) => [...SRC.keys()].filter(p => !pathRe || pathRe.test(p));
const srcText = (pathRe) => srcPaths(pathRe).map(p => SRC.get(p)).join('\n');
const srcCount = (re, pathRe) => srcPaths(pathRe)
  .reduce((n, p) => n + (SRC.get(p).match(new RegExp(re.source, re.flags.includes('g') ? re.flags : re.flags + 'g')) || []).length, 0);
const srcHas = (re, pathRe) => srcCount(re, pathRe) > 0;

// SQL literal helpers. A frontend fact is a measured fact, and the only way it can reach a check is
// as a literal inside the statement — so it goes through one escaper, never through concatenation
// at the call site.
const Q = (s) => `'${String(s == null ? '' : s).replace(/'/g, "''")}'`;
const B = (v) => (v ? 'true' : 'false');

// ── SQL helpers shared with row #2, so a section written in that house style still works ─────────
const READERS = (t) => `(
    (select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> '${t}'
        and pg_get_functiondef(p.oid) ~* '\\y${t}\\y')
  + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '\\y${t}\\y')
  + (select count(*) from cron.job j where j.command ~* '\\y${t}\\y'))`;
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

// THE UI CLOSURE IS COMPUTED ONCE, HERE. It is a 700x700 regex join over pg_get_functiondef and
// paying it per section would multiply the slowest query in the run by the number of sections.
// Computing it through uiClosure() also primes ui_closure.mjs's own memo, so a module that asks for
// closure(one) instead gets the same set back without a second query.
const ui = await uiClosure(qAll, ROOT);
console.log(`\nUI closure: ${ui.edgeFns.length} browser-reachable edge function(s), ` +
            `${ui.routines.length} of ${ui.total} routine(s), ${ui.views.length} view(s)`);

const helpers = {
  req, one, q, qAll, ui, TARGET, ROOT,
  READERS, HAS_READER, N_READERS, INPROMPT, COL, NROWS, HAS_ROWS, FN_EXISTS,
  SRC, srcPaths, srcText, srcCount, srcHas, Q, B,
};

console.log(`\nSPEC FILE #3 — the executive UI (OS 2.txt), scored against ${TARGET}\n`);

// The section files partition the 152 requirements exactly. Sections are DISCOVERED rather than
// listed, because several agents write them in parallel and a hand-maintained list would go stale
// silently — which is the same failure the denominator assertion exists to catch. Each module
// declares `export const EXPECTED = <n>`; a module that registers fewer checks than it declares
// RAISES the percentage by shrinking the denominator, so both the per-module count and the total
// are asserted below.
const TOTAL = 152;
let files = [];
// ui_closure.mjs is the shared primitive, not a section, and `_`-prefixed files are throwaway
// probes: importing either as a section calls a default export that does not exist and takes the
// whole run down, which turns 152 measured requirements into zero.
try { files = readdirSync(DIR).filter(f => f.endsWith('.mjs') && !f.startsWith('_') && f !== 'ui_closure.mjs').sort(); } catch { /* none yet */ }
if (!files.length) console.log(`  !! no section modules in ${DIR}`);

let shortfall = 0, undeclared = 0;
for (const f of files) {
  // --only=<id> USED TO PAY FOR EVERY MODULE'S SETUP (3 Sep 2026). req() returned early for the
  // checks that did not match, but each module still executed its own preamble — the callable
  // screen list, the ~300 KB SURFACE payload, the source-tree scans — before it could ask. Measured
  // under a throttled management API that was ~50 minutes for one requirement. A module can only
  // register an id it names in its source, so a module whose text does not contain the --only
  // string is skipped whole. The full run (no --only) is unchanged.
  if (ONLY && !readFileSync(join(DIR, f), 'utf8').includes(ONLY)) continue;
  console.log(`\n--- ${f.replace(/\.mjs$/, '')} ---`);
  const before = rows.length;
  const mod = await import(pathToFileURL(join(DIR, f)).href);
  if (typeof mod.default !== 'function') { console.log(`  !! ${f} exports no default section function — skipped`); continue; }
  // A section that throws must not take the run down with it. Before this, one unfinished module
  // aborted the process and turned 152 measured requirements into zero measured requirements —
  // several agents write these files in parallel, so a half-written sibling is the normal state of
  // the directory, not an exceptional one. The failure is loud and it costs its own denominator.
  try { await mod.default(helpers); }
  catch (e) { shortfall++; console.log(`  !! ${f} THREW and its remaining checks did not run: ${String(e && e.message || e).slice(0, 160)}`); }
  const got = rows.length - before;
  if (ONLY) continue;
  if (typeof mod.EXPECTED !== 'number') { undeclared++; console.log(`  !! ${f} declares no EXPECTED count — its denominator is unchecked`); }
  else if (got !== mod.EXPECTED) { shortfall++; console.log(`  !! ${f} registered ${got} checks, expected ${mod.EXPECTED}`); }
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
if (shortfall || undeclared) console.log(`\n  !! ${shortfall + undeclared} section(s) have an unverified check count —` +
  ` the denominator is not trustworthy, so neither is the percentage below.`);
if (!ONLY && rows.length !== TOTAL) console.log(`  !! ${rows.length} checks ran, the spec has ${TOTAL}.`);
console.log(`\nSPEC FILE #3 (executive UI) on ${TARGET}: ${met}/${rows.length}` +
            ` (${(100 * met / (rows.length || 1)).toFixed(0)}%)`);
// WHAT MOVED. A score with no history cannot answer that; on 14 Aug 2026 this one read
// 136/152 in the morning and 135/152 in the evening and the difference was unrecoverable.
await recordBlueprintRun('row3_executive_ui', TARGET, rows);
await printBlueprintDiff('row3_executive_ui', TARGET, mgmtRead);

process.exit(met === rows.length && !shortfall && !undeclared && !errs.length ? 0 : 1);
