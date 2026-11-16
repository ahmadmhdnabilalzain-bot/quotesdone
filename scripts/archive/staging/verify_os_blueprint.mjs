// SPEC FILE #2 — the Universal OS Blueprint (OS.txt), scored against PRODUCTION, symmetrically.
//
// 110 requirements. The rule that governs every check here is the one that inflated the previous
// scorecard when it was broken: score MET and MISSING with EQUAL scepticism. A check that only
// looks for absence will confirm absence; a check that only looks for presence will confirm
// presence. Each requirement therefore asks all three questions and never conflates them:
//
//   1. does the mechanism EXIST (table, column, routine, view)?
//   2. is it POPULATED, and does it RUN?
//   3. does anything READ its output?
//
// A table with rows and no reader scores NO. That single rule is the entire subject of this spec
// file — nine times over, an asset was built, populated, verified by a gate, and read by nothing.
//
//   node scripts/archive/staging/verify_os_blueprint.mjs            # read-only, PRODUCTION, zero spend
//   node scripts/archive/staging/verify_os_blueprint.mjs --staging  # same checks against staging
//
// EXPECT IT TO BE SLOW. Every check is a sequential management-API read and the API rate-limits
// hard; qd_guard retries with exponential backoff. Several minutes is normal. It is not a hang.
import { mgmtRead, PROD_REF } from '../../lib/qd_guard.mjs';
import { REF as STAGE } from '../../lib/demo_factory.mjs';

const TARGET = process.argv.includes('--staging') ? STAGE : PROD_REF;
const ONLY = (process.argv.find(a => a.startsWith('--only=')) || '').slice(7);

const rows = [];
const q = async (sql) => (await mgmtRead(TARGET, sql))[0];
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
  console.log(`${ok ? 'MET    ' : 'MISSING'} ${id.padEnd(30)} ${String(ev).slice(0, 96)}`);
}

// Does ANY routine, view or cron job reference this object? Counting pg_proc and pg_views alone
// made a whole governance layer look unbuilt while it ran 1,266 times on active crons — cron.job
// is not optional. `prokind in ('f','p')` skips aggregates; the self-exclusion stops a function
// that merely mentions its own name from counting as its own reader.
const READERS = (t) => `(
    (select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> '${t}'
        and pg_get_functiondef(p.oid) ~* '\\y${t}\\y')
  + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '\\y${t}\\y')
  + (select count(*) from cron.job j where j.command ~* '\\y${t}\\y'))`;
const HAS_READER = (t) => `select ${READERS(t)} > 0`;
const N_READERS = (t) => `select ${READERS(t)}::text || ' reader(s)'`;

// Does this text reach what an agent is actually handed? A column being populated is not the same
// claim as the employee being told about it, and this spec is entirely about the difference.
const INPROMPT = (needle, agent = 'cfo', budget = 22000) =>
  `select public.fn_agent_context('${agent}', ${budget}) like '%${needle.replace(/'/g, "''")}%'`;

const COL = (t, c) => `select exists (select 1 from information_schema.columns
  where table_schema='public' and table_name='${t}' and column_name='${c}')`;
const NROWS = (t, w = 'true') => `select (select count(*) from public.${t} where ${w})::text`;
const HAS_ROWS = (t, w = 'true') => `select (select count(*) from public.${t} where ${w}) > 0`;
const FN_EXISTS = (n) => `select exists (select 1 from pg_proc p join pg_namespace ns
  on ns.oid=p.pronamespace where ns.nspname='public' and p.proname='${n}')`;

const helpers = { req, one, q, READERS, HAS_READER, N_READERS, INPROMPT, COL, NROWS, HAS_ROWS, FN_EXISTS, TARGET };

console.log(`\nSPEC FILE #2 — Universal OS Blueprint, scored against ${TARGET}\n`);

// The six section files partition the 110 requirements exactly: 30 + 11 + 21 + 21 + 12 + 15.
// The total is asserted at the end — a section that silently fails to register its checks would
// otherwise raise the percentage by shrinking the denominator, which is the most dangerous way
// for a scorer to be wrong.
const SECTIONS = [
  ['components 1-9   (Purpose .. Workflows)', './os_blueprint/components_1_9.mjs', 30],
  ['component 10     (Decision Engine)', './os_blueprint/component_10.mjs', 11],
  ['components 11-13 (KPI / Memory / Learning)', './os_blueprint/components_11_13.mjs', 21],
  ['components 14-17 (Authority / Collab / Health / Review)', './os_blueprint/components_14_17.mjs', 21],
  ['the ten OSes', './os_blueprint/the_ten_oses.mjs', 12],
  ['cross-OS contract', './os_blueprint/cross_os.mjs', 15],
];

let shortfall = 0;
for (const [label, path, expected] of SECTIONS) {
  console.log(`\n--- ${label} ---`);
  const before = rows.length;
  const mod = await import(path);
  await mod.default(helpers);
  const got = rows.length - before;
  if (!ONLY && got !== expected) {
    shortfall++;
    console.log(`  !! ${path} registered ${got} checks, expected ${expected}`);
  }
}

const met = rows.filter(r => r.ok).length;
const errs = rows.filter(r => String(r.ev).startsWith('ERROR'));
console.log(`\n${'='.repeat(78)}`);
for (const r of rows.filter(r => !r.ok)) console.log(`  NOT MET  ${r.id.padEnd(30)} ${r.name}`);
if (errs.length) {
  console.log(`\n  ${errs.length} CHECK(S) ERRORED — an errored check is NOT a MISSING verdict, it is`);
  console.log(`  an unmeasured requirement, and reporting it as MISSING would be a false negative:`);
  for (const e of errs) console.log(`    ${e.id.padEnd(30)} ${e.ev}`);
}
if (shortfall) console.log(`\n  !! ${shortfall} section(s) registered the wrong number of checks —` +
  ` the denominator is wrong, so the percentage below is NOT trustworthy.`);
if (!ONLY && rows.length !== 110) console.log(`  !! ${rows.length} checks ran, the spec has 110.`);
console.log(`\nSPEC FILE #2 (OS blueprint) on ${TARGET}: ${met}/${rows.length}` +
            ` (${(100 * met / (rows.length || 1)).toFixed(0)}%)`);
process.exit(met === rows.length && !shortfall && !errs.length ? 0 : 1);
