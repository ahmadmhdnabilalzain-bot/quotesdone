// SPEC FILE #6 — SUPPLIER CATEGORIES AND THEIR AI AGENTS, scored against PRODUCTION.
//
// 283 requirements across 12 sections, enumerated in docs/sessions/ROW6_REQUIREMENTS.md.
//
//   node scripts/staging/verify_category_agents.mjs             # read-only, PRODUCTION
//   node scripts/staging/verify_category_agents.mjs --staging    # same checks against staging
//   node scripts/staging/verify_category_agents.mjs --only=quo-  # one prefix, section or id
//   node scripts/staging/verify_category_agents.mjs --json=x.json
//
// The runner is verify_supplier_blueprint.mjs's, unchanged in every respect that matters: modules
// are DISCOVERED not listed, each declares its own EXPECTED, evidence prints beside every verdict,
// an evidence failure invalidates its verdict rather than surviving it, and the 283-check total is
// asserted at the end. A module written for either file runs in both.
//
// ── WHAT IS DIFFERENT, AND WHY THE HELPER SET IS SMALLER ─────────────────────────────────────────
// Row #5 scored a SCREEN, so its helpers counted tokens across the supplier route's import closure.
// Row #6 scores a CORPUS. There is no UI in this spec — it is a taxonomy plus a knowledge contract —
// and not one check here reads a .tsx file. The whole evidence surface is four tables and the
// routines that reach them, so the helpers are SQL-shaped instead of file-shaped.
//
// ── THE TRAP THIS ROW IS MOST EXPOSED TO ─────────────────────────────────────────────────────────
// Row #5's seven false MISSINGs came from a scan whose POPULATION excluded where the fact lived.
// Row #6's equivalent is the COLUMN. The opening brief states that none of the eight knowledge
// domains is an `agent_knowledge.layer` — true — and concludes the schema cannot answer "does agent
// X cover Technical Knowledge?" — false. The eight domains are `topic` values, spelled exactly as
// the spec spells them, on 84 of 84 mapped agents. A scorer reading `layer` would have reported all
// eight domains MISSING on all 84 agents and issued a build order to regenerate 672 existing rows.
//
// So every check prints the COLUMN it read. `topic` and `content` are named in the evidence, not
// implied by it, and a verdict that cannot say which column it came from is not a verdict.
//
// ── THE TWO BARS ─────────────────────────────────────────────────────────────────────────────────
// BAR A (the eight domain-coverage checks): 84 of 84 mapped agents. The spec's "Every AI Agent Needs
//        These Knowledge Domains" is a universal claim, so its check is universal.
// BAR B (every sub-bullet): 21 of 84 (25%). The spec introduces every sub-list with "Example:", so
//        a BOQ or DEWA is an illustration of a domain, not a mandate on a translation agency.
//        Requiring all 84 would manufacture a false MISSING and then a build order to fabricate it.
// Both print the exact agent count, so a bullet at 84/84 and one at 22/84 read as what they are.
//
// EXPECT IT TO BE SLOW. Every check is a sequential management-API read and the API rate-limits
// hard; qd_guard retries with exponential backoff. Several minutes is normal. It is not a hang.
import { readdirSync, existsSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { mgmtRead, PROD_REF } from './qd_guard.mjs';
import { REF as STAGE } from './demo_factory.mjs';

const TARGET = process.argv.includes('--staging') ? STAGE : PROD_REF;
const ONLY = (process.argv.find(a => a.startsWith('--only=')) || '').slice(7);
const JSON_OUT = (process.argv.find(a => a.startsWith('--json=')) || '').slice(7);
const TOTAL = 283;

const rows = [];
const q = async (sql) => (await mgmtRead(TARGET, sql))[0];
const one = async (sql) => { const r = await q(sql); return r ? Object.values(r)[0] : null; };
const many = (sql) => mgmtRead(TARGET, sql);

// Identical to row #5's, including the reason it is written this way: a MET whose EVIDENCE threw is
// a claim with nothing behind it, and was ALSO double-counted — listed among the errored checks at
// the bottom while still adding 1 to `met` at the top. The two queries are caught separately and an
// evidence failure forces ok=false, so the check lands in ERRORED and nowhere near the numerator.
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

// ── LITERAL VERDICTS ─────────────────────────────────────────────────────────────────────────────
// 283 checks at two management-API round-trips each is 566 sequential rate-limited requests. The
// per-item sections (66 domains, 84 categories, and every sub-bullet) fetch their population ONCE
// and register their checks from that one payload, exactly as row #5's file-shaped modules did with
// B()/Q(). The GUARD split is row #5's and exists for the same reason: an evidence string that
// happens to contain the word "create" must not read as a write to mgmtRead's refusal check.
const GUARD = /\b(insert|update|delete|truncate|drop|alter|create|grant|revoke|vacuum|reindex|call|do)\b/gi;
const B = (v) => 'select ' + (v ? 'true' : 'false');
const Q = (s) => "select '" + String(s == null ? '' : s).replace(/'/g, "''")
  .replace(GUARD, (m) => m.slice(0, 1) + "'||'" + m.slice(1)) + "'";

const READERS = (t) => `(
    (select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> '${t}'
        and pg_get_functiondef(p.oid) ~* '\\y${t}\\y')
  + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '\\y${t}\\y')
  + (select count(*) from cron.job j where j.command ~* '\\y${t}\\y'))`;
const FN_EXISTS = (n) => `select exists (select 1 from pg_proc p join pg_namespace ns
  on ns.oid=p.pronamespace where ns.nspname='public' and p.proname='${n}')`;

// The population every knowledge section scores over: the 84 realistic categories that carry an
// agent. NOT the 132 agent_knowledge namespaces — 48 of those are legacy or folded agents outside
// the spec's list, and averaging them in is exactly how "1,584 rows / 132 agents = 12 each" became
// a number that hid 84 agents carrying fifteen modules apiece.
const MAPPED = `agent_key in (select 'cat:'||agent_slug from public.category_agent_map)`;
const MAPPED_N = 84;
const BAR_B = 21;

const helpers = { req, one, q, many, B, Q, READERS, FN_EXISTS, MAPPED, MAPPED_N, BAR_B, TARGET };

console.log(`\nSPEC FILE #6 — Supplier categories and their AI agents, scored against ${TARGET}\n`);

const DIR = fileURLToPath(new URL('./category_agents/', import.meta.url));
const files = existsSync(DIR) ? readdirSync(DIR).filter(f => f.endsWith('.mjs')).sort() : [];
if (!files.length) console.log(`  !! ${DIR} contains no section module.`);

let shortfall = 0;
for (const f of files) {
  console.log(`\n--- ${f} ---`);
  const before = rows.length;
  // The import is inside the guard, not only the call: a module with a SyntaxError throws at
  // EVALUATION time, before default() is reached, and unguarded it takes every requirement in the
  // run down to zero measured — which is not a low score, it is no measurement at all.
  let mod;
  try { mod = await import(new URL('./category_agents/' + f, import.meta.url)); }
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

// The per-section breakdown. Row #5 reported one number and the founder had to ask which sections
// it hid; a corpus score especially must never be one number, because a corpus averages.
const bySection = {};
for (const r of rows) { (bySection[r.section] ||= [0, 0])[r.ok ? 0 : 1]++; }
console.log('\n  per section:');
for (const [s, [ok, no]] of Object.entries(bySection)) {
  console.log(`    ${s.padEnd(26)} ${String(ok).padStart(3)}/${String(ok + no).padStart(3)}` +
    ` (${String(Math.round(100 * ok / (ok + no))).padStart(3)}%)${no ? '' : '  complete'}`);
}
console.log(`\nSPEC FILE #6 (category agents) on ${TARGET}: ${met}/${rows.length}` +
            ` (${(100 * met / (rows.length || 1)).toFixed(0)}%) of ${TOTAL} requirement(s)`);
process.exit(met === rows.length && !shortfall && !errs.length && (ONLY || rows.length === TOTAL) ? 0 : 1);
