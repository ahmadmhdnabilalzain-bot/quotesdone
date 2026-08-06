// SPEC FILE #4 — the CUSTOMER PORTAL, scored against PRODUCTION.
//
// 147 requirements across 22 sections. The runner is row #2's (verify_os_blueprint.mjs) with two
// changes, and everything else — the helper contract, the evidence discipline, the denominator
// assertion — is deliberately identical so a module written for either file runs in both.
//
//   node scripts/staging/verify_portal_blueprint.mjs             # read-only, PRODUCTION
//   node scripts/staging/verify_portal_blueprint.mjs --staging    # same checks against staging
//   node scripts/staging/verify_portal_blueprint.mjs --only=doc-  # one prefix, section or id
//
// CHANGE 1 — THE SECTION FILES ARE DISCOVERED, NOT LISTED. Several agents write into
// scripts/staging/portal_blueprint/ at once and a hardcoded list silently drops any module whose
// name the list's author did not know. Every *.mjs in that directory is imported in name order.
//
// CHANGE 2 — EACH MODULE DECLARES ITS OWN DENOMINATOR. `export const EXPECTED = <n>` is compared
// against the number of checks the module actually registered. This is the assertion row #2 kept
// and it is the one that matters most: a section that quietly registers fewer checks RAISES the
// percentage by shrinking the denominator, which is the most dangerous way for a scorer to be
// wrong. A module with no EXPECTED is reported rather than trusted, and the 147-check total is
// asserted at the end so a section file that has not been written yet cannot be mistaken for one
// that scored zero.
//
// THE CONSTRAINT THAT SHAPES EVERY CHECK: production holds ZERO customers, inquiries, quotes and
// transactions, and 20,464 leads. A check that counts customer rows reads 0 for every requirement
// and measures nothing. Score the MECHANISM — does the routine/view/endpoint/component exist, is
// it reachable by a customer, and would it render real data if data existed — and where a
// requirement genuinely cannot be evidenced without traffic, say so in the evidence string rather
// than scoring it either way by accident.
//
// EXPECT IT TO BE SLOW. Every check is a sequential management-API read and the API rate-limits
// hard; qd_guard retries with exponential backoff. Several minutes is normal. It is not a hang.
import { readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { mgmtRead, PROD_REF } from './qd_guard.mjs';
import { REF as STAGE } from './demo_factory.mjs';

const TARGET = process.argv.includes('--staging') ? STAGE : PROD_REF;
const ONLY = (process.argv.find(a => a.startsWith('--only=')) || '').slice(7);
const TOTAL = 147;

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
// is not optional. `prokind in ('f','p')` skips aggregates — and it is not only tidiness:
// pg_get_functiondef RAISES 42809 on an aggregate, so a scan without it errors out entirely and
// leaves the requirement UNMEASURED. The self-exclusion stops a function that merely mentions its
// own name from counting as its own reader; for a TABLE name it is inert, so a module scoring a
// table must exclude that table's writers by pattern instead.
const READERS = (t) => `(
    (select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> '${t}'
        and pg_get_functiondef(p.oid) ~* '\\y${t}\\y')
  + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '\\y${t}\\y')
  + (select count(*) from cron.job j where j.command ~* '\\y${t}\\y'))`;
const HAS_READER = (t) => `select ${READERS(t)} > 0`;
const N_READERS = (t) => `select ${READERS(t)}::text || ' reader(s)'`;

// Does this text reach what an agent is actually handed? A column being populated is not the same
// claim as the employee being told about it.
const INPROMPT = (needle, agent = 'cfo', budget = 22000) =>
  `select public.fn_agent_context('${agent}', ${budget}) like '%${needle.replace(/'/g, "''")}%'`;

const COL = (t, c) => `select exists (select 1 from information_schema.columns
  where table_schema='public' and table_name='${t}' and column_name='${c}')`;
const NROWS = (t, w = 'true') => `select (select count(*) from public.${t} where ${w})::text`;
const HAS_ROWS = (t, w = 'true') => `select (select count(*) from public.${t} where ${w}) > 0`;
const FN_EXISTS = (n) => `select exists (select 1 from pg_proc p join pg_namespace ns
  on ns.oid=p.pronamespace where ns.nspname='public' and p.proname='${n}')`;

const helpers = { req, one, q, READERS, HAS_READER, N_READERS, INPROMPT, COL, NROWS, HAS_ROWS, FN_EXISTS, TARGET };

console.log(`\nSPEC FILE #4 — Customer Portal, scored against ${TARGET}\n`);

const DIR = fileURLToPath(new URL('./portal_blueprint/', import.meta.url));
const files = existsSync(DIR) ? readdirSync(DIR).filter(f => f.endsWith('.mjs')).sort() : [];
if (!files.length) console.log(`  !! ${DIR} contains no section module.`);

let shortfall = 0;
for (const f of files) {
  console.log(`\n--- ${f} ---`);
  const before = rows.length;
  // THE IMPORT IS INSIDE THE GUARD, NOT ONLY THE CALL. Several agents write into this directory at
  // once, so a half-written sibling is the normal state of it — and a module with a SyntaxError
  // throws at EVALUATION time, before default() is ever reached. Unguarded, one unparseable file
  // took all 147 requirements down to zero measured, which is not a low score, it is no measurement
  // at all. A module that cannot load costs its own denominator and the run continues.
  let mod;
  try { mod = await import(new URL('./portal_blueprint/' + f, import.meta.url)); }
  catch (e) { shortfall++; console.log(`  !! ${f} FAILED TO LOAD, so none of its checks ran: ${String(e && e.message || e).slice(0, 200)}`); continue; }
  if (typeof mod.default !== 'function') { shortfall++; console.log(`  !! ${f} exports no default section function — skipped`); continue; }
  try { await mod.default(helpers); }
  catch (e) { shortfall++; console.log(`  !! ${f} THREW; its remaining checks did not run: ${String(e && e.message || e).slice(0, 200)}`); }
  const got = rows.length - before;
  const expected = mod.EXPECTED;
  if (!ONLY && typeof expected !== 'number') {
    shortfall++;
    console.log(`  !! ${f} exports no EXPECTED count — its ${got} check(s) cannot be verified`);
  } else if (!ONLY && got !== expected) {
    shortfall++;
    console.log(`  !! ${f} registered ${got} checks, expected ${expected}`);
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
if (!ONLY && rows.length !== TOTAL) console.log(`  !! ${rows.length} checks ran, the spec has ${TOTAL}` +
  ` — ${TOTAL - rows.length} requirement(s) have no section module yet and are NOT scored below.`);
console.log(`\nSPEC FILE #4 (customer portal) on ${TARGET}: ${met}/${rows.length}` +
            ` (${(100 * met / (rows.length || 1)).toFixed(0)}%) of ${TOTAL} requirement(s)`);
process.exit(met === rows.length && !shortfall && !errs.length && (ONLY || rows.length === TOTAL) ? 0 : 1);
