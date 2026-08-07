// SPEC FILE #5 — the SUPPLIER PORTAL, scored against PRODUCTION.
//
// 234 requirements across 24 sections, enumerated in docs/sessions/ROW5_REQUIREMENTS.md. The count
// is NOT row #4's 147 and was not derived from it: §23 names fifteen technologies and §24 names
// nineteen portal modules, and those two sections carry 34 requirements that row #4 had no
// equivalent for. The runner is row #4's with three changes, and everything else — the helper
// contract, the evidence discipline, the denominator assertion — is deliberately identical so a
// module written for either file runs in both.
//
//   node scripts/staging/verify_supplier_blueprint.mjs             # read-only, PRODUCTION
//   node scripts/staging/verify_supplier_blueprint.mjs --staging    # same checks against staging
//   node scripts/staging/verify_supplier_blueprint.mjs --only=doc-  # one prefix, section or id
//
// CHANGE 1 — THE SECTION FILES ARE DISCOVERED, NOT LISTED. Several agents write into
// scripts/staging/supplier_blueprint/ at once and a hardcoded list silently drops any module whose
// name the list's author did not know. Every *.mjs in that directory is imported in name order.
//
// CHANGE 2 — EACH MODULE DECLARES ITS OWN DENOMINATOR. `export const EXPECTED = <n>` is compared
// against the number of checks the module actually registered. This is the assertion row #2 kept
// and it is the one that matters most: a section that quietly registers fewer checks RAISES the
// percentage by shrinking the denominator, which is the most dangerous way for a scorer to be
// wrong. A module with no EXPECTED is reported rather than trusted, and the 234-check total is
// asserted at the end so a section file that has not been written yet cannot be mistaken for one
// that scored zero.
//
// CHANGE 3 — THE SURFACE IS NOT A FILENAME. Section modules import SUPPLIER from portal_surface.mjs
// and count over SUPPLIER.SRC, the import closure of src/app/[locale]/supplier/page.tsx. NO MODULE
// MAY HARDCODE SupplierPortal.tsx. Row #4 had two of five modules scoring one file while three
// scored the route's closure, and reported 104/147 against a truth of 124 — one run holding two
// definitions of "the user sees it". portal_surface.mjs is parameterised (surfaceFor) rather than
// copied, so the two roots cannot drift apart: there is one implementation of "the screen".
//
// THE CONSTRAINT THAT SHAPES EVERY CHECK — AND IT IS NOT ROW #4'S CONSTRAINT.
// Measured on production 2026-08-07: 20,464 leads, 0 verified, 0 approved, 0 claimed, 0 with a
// registration submitted, 0 owner_email_verified, 0 quotes, 0 inquiries, 0 inquiry_matches,
// 0 supplier_capabilities. The estate is a SCRAPED PROSPECT LIST. Not one of the 20,464 is a
// supplier in any sense this spec means.
//
// The blocker is therefore NOT "no data" — it is "no principal". 20,464 supplier_score rows carry
// reliability non-null on ALL 20,464, and 470 catalog_subcategories / 56 category_specs /
// 25 taxonomy_trade rows are populated. §13's four bars and §3's twin have real inputs for every
// one of the 20,464 companies. What is missing is somebody who can log in and be shown them.
//
// That splits the 234 into three honestly different classes, and a check must know which it is in:
//   1. MEASURABLE NOW — the routine runs against a real lead id and returns real numbers.
//   2. NEEDS A PRINCIPAL — "the supplier sees their own X". Scored against the FENCED DEMO
//      SUPPLIER (see below), never against the scraped estate.
//   3. NET-NEW REGARDLESS — supplier_product / supplier_product_variant / supplier_catalog hold
//      0 rows AND 0 readers, confirmed by regex and ilike against a control (leads reads 137 by
//      the same scan). No amount of onboarding fixes these; §7 and §8 must be built.
//
// THE DEMO SUPPLIER IS FENCED, AND THE FENCE IS PART OF THE REQUIREMENT, NOT A COURTESY.
// A demo supplier on production that is matchable would receive real customers' RFQs, surface in
// real search results and be revealed to real customers. That is the identical harm the founder
// refused when flipping `verified` on scraped rows was proposed — arriving by a different door.
// Demo rows are marked, excluded from matching/search/reveal, and removable. A check that would
// pass only because a demo row leaked into a real customer's result set is a FAILING check.
//
// WHAT IS STILL REFUSED: setting `verified` or `approval_status='approved'` on any of the 20,464
// scraped rows. Creating a NEW, marked, fenced demo supplier is not that, and is not fabricating
// data about a real company.
//
// EXPECT IT TO BE SLOW. Every check is a sequential management-API read and the API rate-limits
// hard; qd_guard retries with exponential backoff. Several minutes is normal. It is not a hang.
import { readdirSync, existsSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { mgmtRead, PROD_REF } from './qd_guard.mjs';
import { REF as STAGE } from './demo_factory.mjs';

const TARGET = process.argv.includes('--staging') ? STAGE : PROD_REF;
const ONLY = (process.argv.find(a => a.startsWith('--only=')) || '').slice(7);
// The console line clips evidence at 96 characters, and the clipped half is where a MISSING verdict
// says WHICH leg failed. --json writes every row whole so a verdict can be acted on without a
// second run. It changes no check and no verdict.
const JSON_OUT = (process.argv.find(a => a.startsWith('--json=')) || '').slice(7);
const TOTAL = 234;

const rows = [];
const q = async (sql) => (await mgmtRead(TARGET, sql))[0];
const one = async (sql) => { const r = await q(sql); return r ? Object.values(r)[0] : null; };

// A requirement is MET only when its evidence query returns true. `evidence` prints either way, so
// a MET verdict carries its proof and a MISSING verdict carries the number that refutes it.
//
// ── AN EVIDENCE FAILURE MUST INVALIDATE THE VERDICT, NOT SURVIVE IT ─────────────────────────────
// Both queries used to share ONE try/catch. When the verdict succeeded and the EVIDENCE threw, `ok`
// kept the value it had already been assigned and the check printed:
//
//     MET     qb-routine     ERROR REFUSED: read is not read-only; use mgmtWrite against a branch
//
// A MET whose evidence errored is a claim with nothing behind it — precisely the thing this
// scorer's evidence discipline exists to prevent, arriving through the error path instead of
// through a loose regex. It was ALSO double-counted: listed among the errored checks at the bottom
// while still adding 1 to `met` at the top, so the percentage was inflated by exactly the checks
// the report said were unmeasured.
//
// The two queries are now caught separately and an evidence failure forces ok=false, so the check
// lands in the ERRORED list as an unmeasured requirement and nowhere near the numerator.
async function req(section, id, name, sql, evidenceSql) {
  if (ONLY && !section.startsWith(ONLY) && !id.startsWith(ONLY)) return;
  let ok = false, ev = '';
  try {
    ok = String(await one(sql)) === 'true';
  } catch (e) {
    ok = false; ev = 'ERROR(verdict) ' + String(e.message || e).slice(0, 100);
  }
  if (!String(ev).startsWith('ERROR')) {
    try {
      ev = evidenceSql ? String(await one(evidenceSql)) : '';
    } catch (e) {
      ok = false; ev = 'ERROR(evidence) ' + String(e.message || e).slice(0, 100);
    }
  }
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

console.log(`\nSPEC FILE #5 — Supplier Portal, scored against ${TARGET}\n`);

const DIR = fileURLToPath(new URL('./supplier_blueprint/', import.meta.url));
const files = existsSync(DIR) ? readdirSync(DIR).filter(f => f.endsWith('.mjs')).sort() : [];
if (!files.length) console.log(`  !! ${DIR} contains no section module.`);

let shortfall = 0;
for (const f of files) {
  console.log(`\n--- ${f} ---`);
  const before = rows.length;
  // THE IMPORT IS INSIDE THE GUARD, NOT ONLY THE CALL. Several agents write into this directory at
  // once, so a half-written sibling is the normal state of it — and a module with a SyntaxError
  // throws at EVALUATION time, before default() is ever reached. Unguarded, one unparseable file
  // took all 234 requirements down to zero measured, which is not a low score, it is no measurement
  // at all. A module that cannot load costs its own denominator and the run continues.
  let mod;
  try { mod = await import(new URL('./supplier_blueprint/' + f, import.meta.url)); }
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
if (JSON_OUT) { writeFileSync(JSON_OUT, JSON.stringify({ target: TARGET, total: TOTAL, met, rows }, null, 1)); console.log(`\n  full evidence written to ${JSON_OUT}`); }
console.log(`\nSPEC FILE #5 (supplier portal) on ${TARGET}: ${met}/${rows.length}` +
            ` (${(100 * met / (rows.length || 1)).toFixed(0)}%) of ${TOTAL} requirement(s)`);
process.exit(met === rows.length && !shortfall && !errs.length && (ONLY || rows.length === TOTAL) ? 0 : 1);
