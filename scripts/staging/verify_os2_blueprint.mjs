// SPEC FILE #3 — the EXECUTIVE UI (OS 2.txt), scored against PRODUCTION.
//
// 152 requirements. This spec is not a backend contract: it describes what the founder SEES when
// the browser is open. So the rule that governs every check in this row is narrower and harsher
// than row #2's:
//
//   A requirement is MET only when the founder can actually SEE the thing.
//
// A table with rows scores nothing. A nightly cron that recomputes an autonomous company scores
// nothing. A number that is computed, stored, verified by a gate and read by no rendered surface
// is MISSING — that is the defining defect of this spec file (graph_nodes: 323 nodes and 300 edges
// rebuilt nightly, zero readers anywhere), and every check has to be able to catch it.
//
// Each check therefore asks BOTH sides, and never conflates them:
//   1. DATABASE  — does the mechanism exist, is it populated, is it fresh, does it run?
//   2. FRONTEND  — does a rendered component actually put it in front of the founder?
// The frontend half is measured from the repository (src/ and supabase/functions/), not asserted.
// scripts/staging/os2_blueprint/ui_closure.mjs computes the one primitive every check needs:
// which routines and views a logged-in founder can cause to run at all.
//
//   node scripts/staging/verify_os2_blueprint.mjs                  # read-only, PRODUCTION
//   node scripts/staging/verify_os2_blueprint.mjs --staging        # same checks against staging
//   node scripts/staging/verify_os2_blueprint.mjs --only=screens   # one section
//
// EXPECT IT TO BE SLOW. Every check is a sequential management-API read, the API rate-limits hard,
// and qd_guard retries with exponential backoff. Several minutes is normal; it is not a hang.
import { readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { mgmtRead, PROD_REF } from './qd_guard.mjs';
import { REF as STAGE } from './demo_factory.mjs';
import { uiClosure } from './os2_blueprint/ui_closure.mjs';

const TARGET = process.argv.includes('--staging') ? STAGE : PROD_REF;
const ONLY = (process.argv.find(a => a.startsWith('--only=')) || '').slice(7);
const ROOT = fileURLToPath(new URL('../../', import.meta.url));

// THE SPEC'S OWN TOTAL. The enumeration for OS 2.txt holds 152 requirements: 40 for screens 1-9,
// 32 for screens 10-17 plus the design principles, 38 for the fifteen layers, 42 for sections
// 21-40. It is asserted at the end because a section that silently registers fewer checks than it
// owns RAISES the percentage by shrinking the denominator, which is the most dangerous way for a
// scorer to be wrong — row #2 reported a false 110/110 with exactly that class of defect nearby.
const TOTAL = 152;

const rows = [];
const qAll = async (sql) => await mgmtRead(TARGET, sql);
const q = async (sql) => (await qAll(sql))[0];
const one = async (sql) => { const r = await q(sql); return r ? Object.values(r)[0] : null; };

// A requirement is MET only when its boolean query returns true. `evidence` prints either way, so
// a MET verdict carries its proof and a MISSING verdict carries the number that refutes it. An
// ERROR is neither: it is an UNMEASURED requirement and is reported separately, because printing
// it as MISSING would be a false negative dressed up as a finding.
async function req(section, id, name, sql, evidenceSql) {
  if (ONLY && !section.startsWith(ONLY) && !id.startsWith(ONLY)) return;
  let ok = false, ev = '';
  try {
    ok = String(await one(sql)) === 'true';
    ev = evidenceSql ? String(await one(evidenceSql)) : '';
  } catch (e) { ok = false; ev = 'ERROR ' + String(e.message || e).slice(0, 140); }
  rows.push({ section, id, name, ok, ev });
  console.log(`${ok ? 'MET    ' : 'MISSING'} ${id.padEnd(34)} ${String(ev).slice(0, 150)}`);
}

// ---- generic helpers shared by every section module ------------------------------------------
// READERS() counts any routine, view or cron job that names an object. It is the WEAK form: it
// does not exclude writers and it does not know about the browser. Prefer ui.UI_READERS() for any
// question of the form "does the founder see this".
const READERS = (t) => `(
    (select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> '${t}'
        and pg_get_functiondef(p.oid) ~* '\\y${t}\\y')
  + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '\\y${t}\\y')
  + (select count(*) from cron.job j where j.command ~* '\\y${t}\\y'))`;
const HAS_READER = (t) => `select ${READERS(t)} > 0`;
const N_READERS = (t) => `select ${READERS(t)}::text || ' reader(s)'`;
// A cron ROW is a claim; a SUCCEEDED RUN is the fact.
const RAN = (rx, days) => `exists (select 1 from cron.job j join cron.job_run_details d on d.jobid=j.jobid
    where j.active and j.command ~* '\\y${rx}\\y' and d.status='succeeded'
      and d.end_time > now() - interval '${days} days')`;
const COL = (t, c) => `select exists (select 1 from information_schema.columns
  where table_schema='public' and table_name='${t}' and column_name='${c}')`;
const NROWS = (t, w = 'true') => `select (select count(*) from public.${t} where ${w})::text`;
const HAS_ROWS = (t, w = 'true') => `select (select count(*) from public.${t} where ${w}) > 0`;
const FN_EXISTS = (n) => `select exists (select 1 from pg_proc p join pg_namespace ns
  on ns.oid=p.pronamespace where ns.nspname='public' and p.proname='${n}')`;

console.log(`\nSPEC FILE #3 — QuotesDone OS X executive UI, scored against ${TARGET}\n`);
console.log('Computing the UI closure (which routines and views the browser can reach)…');
const ui = await uiClosure(qAll, ROOT);
console.log(`  ${ui.edgeFns.length} browser-reachable edge function(s), ` +
            `${ui.routines.length} reachable routine(s), ${ui.views.length} reachable view(s)\n`);

const helpers = { req, one, q, qAll, ui, ROOT, TARGET,
                  READERS, HAS_READER, N_READERS, RAN, COL, NROWS, HAS_ROWS, FN_EXISTS };

// Sections are DISCOVERED, not listed: several agents write these modules in parallel and a
// hard-coded filename table would break the moment one of them chose a different name. Each module
// declares how many checks it owns (`export const expected`), and the runner holds both halves of
// the denominator to account: per-module (did it register what it promised) and in total (do the
// modules together cover the spec).
const DIR = fileURLToPath(new URL('./os2_blueprint/', import.meta.url));
const FILES = existsSync(DIR)
  ? readdirSync(DIR).filter(f => f.endsWith('.mjs') && !f.startsWith('_') && f !== 'ui_closure.mjs').sort()
  : [];

let shortfall = 0, declared = 0;
for (const f of FILES) {
  const mod = await import('./os2_blueprint/' + f);
  if (typeof mod.default !== 'function') continue;
  const label = mod.label || f.replace(/\.mjs$/, '');
  const exp = Number(mod.expected);
  declared += Number.isFinite(exp) ? exp : 0;
  console.log(`\n--- ${label} ---`);
  const before = rows.length;
  await mod.default(helpers);
  const got = rows.length - before;
  if (!ONLY && Number.isFinite(exp) && got !== exp) {
    shortfall++;
    console.log(`  !! ${f} registered ${got} checks, declared ${exp}`);
  }
  if (!Number.isFinite(exp)) { shortfall++; console.log(`  !! ${f} declares no \`expected\` count`); }
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
if (!ONLY) {
  if (declared !== TOTAL) { shortfall++; console.log(`\n  !! section modules declare ${declared} checks, the spec has ${TOTAL}.`); }
  if (rows.length !== TOTAL) { shortfall++; console.log(`  !! ${rows.length} checks ran, the spec has ${TOTAL}.`); }
}
if (shortfall) console.log(`\n  !! the denominator is wrong, so the percentage below is NOT trustworthy.`);
console.log(`\nSPEC FILE #3 (executive UI) on ${TARGET}: ${met}/${rows.length}` +
            ` (${(100 * met / (rows.length || 1)).toFixed(0)}%)`);
process.exit(met === rows.length && !shortfall && !errs.length ? 0 : 1);
