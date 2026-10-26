// Apply one DEMO FIXTURE .sql file to STAGING and then to PRODUCTION, identical text on both.
//
//   node scripts/apply_demo_fixture.mjs scripts/sql/demo_market_row5.sql
//
// ── WHY THIS IS NOT apply_sql.mjs --promote ─────────────────────────────────────────────────────
// That script promotes ROUTINES, and it does it by reading the verified definition back out of
// staging and posting THAT, never the file — because a routine is one object with one body and
// retyping it is a bug class. A fixture is not one object. It is rows keyed on business values
// (place_id, summary) whose surrogate ids each project generates for itself, so "read the verified
// value back and post it" would carry staging's bigints into production's identity sequence.
//
// The honest analogue for row fixtures is the identical, idempotent text applied to both projects
// and the resulting COUNTS asserted equal — which is what audit_session_parity already checks for
// every earlier fixture. Every demo file is written to be re-runnable (NOT EXISTS on the business
// key), so applying it twice is a no-op and applying it to a project that already has it is a no-op.
//
// ── THE GUARD ───────────────────────────────────────────────────────────────────────────────────
// qd_guard refuses production writes by design and this script deliberately bypasses it, so it
// carries its own refusal instead of inheriting none:
//   · the file must mark its rows with 'qd_demo_fixture', so an unfenced insert cannot ride this path
//   · no delete/drop/truncate/alter at all — removal is a decision, not a side effect of seeding
//   · every update must name the fixture marker in the same statement
//   · no production ref literal, the same check qd_guard makes
import { supabaseAccessToken } from '../lib/supabase_token.mjs';
import { readFileSync } from 'node:fs';
import { mgmtWrite, PROD_REF, assertNoProductionLiteral } from '../lib/qd_guard.mjs';
import { REF as STAGE } from '../lib/demo_factory.mjs';

const file = process.argv[2];
if (!file) { console.error('usage: node scripts/apply_demo_fixture.mjs <demo_file.sql>'); process.exit(2); }
const sql = readFileSync(file, 'utf8');

// Comments describe the fence; they must not be able to satisfy it. Strip them before testing.
const code = sql.replace(/--[^\n]*/g, '').replace(/\/\*[\s\S]*?\*\//g, '');

const refuse = (why) => { console.error(`REFUSED: ${file} ${why}`); process.exit(1); };
if (!/qd_demo_fixture/.test(code)) refuse('does not mark its rows with qd_demo_fixture');
if (/\b(delete|drop|truncate|alter)\s/i.test(code)) refuse('carries a delete/drop/truncate/alter');
for (const m of code.matchAll(/\bupdate\s+[\s\S]*?(?=;|$)/gi)) {
  if (!/qd_demo_fixture/.test(m[0])) refuse('has an update that does not name the fixture marker');
}
assertNoProductionLiteral(sql, file);

const token = supabaseAccessToken();

// Same backoff as apply_sql.mjs: the failure mode is a fixture that landed on one project only,
// which is precisely what the founder's "no staging only" rule exists to prevent.
async function prodPost(q, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: q }),
  });
  const b = await r.text();
  if ((r.status === 429 || r.status >= 500) && attempt < 7) {
    const wait = Math.min(2000 * 2 ** attempt, 60000);
    console.log(`  production ${r.status}; retrying in ${wait / 1000}s (attempt ${attempt + 1}/7)`);
    await new Promise((res) => setTimeout(res, wait));
    return prodPost(q, attempt + 1);
  }
  if (!r.ok) throw new Error(`production ${r.status}: ${b.slice(0, 400)}`);
  return JSON.parse(b);
}

await mgmtWrite(STAGE, sql, `demo fixture ${file}`);
console.log(`applied to staging    ${STAGE}`);
await prodPost(sql);
console.log(`applied to production ${PROD_REF}`);

// Counts on both, side by side, so "it worked" is a measurement rather than the absence of a throw.
const COUNTS = `select
  (select count(*) from public.leads      where source       = 'qd_demo_fixture')::text leads,
  (select count(*) from public.inquiries  where brief_source = 'qd_demo_fixture')::text inquiries,
  (select count(*) from public.quotes     where source       = 'qd_demo_fixture')::text quotes,
  (select count(*) from public.notifications where status = 'queued')::text queued_notifs`;
const rows = (r) => (Array.isArray(r) ? r : r?.result ?? []);
const s = rows(await mgmtWrite(STAGE, COUNTS, 'counts'))[0];
const p = rows(await prodPost(COUNTS))[0];
console.log('\n              staging  production');
for (const k of Object.keys(s)) {
  const a = String(s[k]), b = String(p[k]);
  console.log(`  ${k.padEnd(13)} ${a.padEnd(8)} ${b.padEnd(10)} ${a === b ? '' : '<<< DIFFER'}`);
}
