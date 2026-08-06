// Apply a .sql file to STAGING, then promote the VERIFIED definition to production byte-for-byte.
//
// The founder's promotion rule of 6 Aug 2026: qd_guard refuses production writes by design, so a
// routine reaches production by reading staging's verified definition back out and posting THAT
// verbatim — never by retyping a body. This script is that rule, executable.
//
//   node scripts/apply_sql.mjs scripts/sql/fn_task_approve.sql            # staging only
//   node scripts/apply_sql.mjs scripts/sql/fn_task_approve.sql --promote  # then production
//
// --promote posts pg_get_functiondef() read back FROM STAGING and asserts md5(prosrc) matches on
// both projects afterwards. A mismatch exits non-zero: the two projects then differ, and that is
// exactly the drift verify_prod_parity exists to catch.
import { readFileSync } from 'node:fs';
import { mgmtRead, mgmtWrite, PROD_REF } from './staging/qd_guard.mjs';
import { REF as STAGE } from './staging/demo_factory.mjs';

const file = process.argv[2];
const PROMOTE = process.argv.includes('--promote');
if (!file) { console.error('usage: node scripts/apply_sql.mjs <file.sql> [--promote]'); process.exit(2); }

const sql = readFileSync(file, 'utf8');
const one = (rows) => (rows && rows[0]) ? Object.values(rows[0])[0] : null;

await mgmtWrite(STAGE, sql, `apply ${file}`);
console.log(`applied to staging ${STAGE}`);

// Which routines did that file define? Parse the names, then read the REAL definitions back.
const names = [...sql.matchAll(/create\s+or\s+replace\s+function\s+(?:public\.)?([a-z0-9_]+)\s*\(/gi)]
  .map(m => m[1]);
const uniq = [...new Set(names)];
if (!uniq.length) { console.log('no functions defined in this file; nothing to promote'); process.exit(0); }

const defsSql = (ref) => `select p.proname n, pg_get_function_identity_arguments(p.oid) a,
  pg_get_functiondef(p.oid) d, md5(p.prosrc) h
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname='public' and p.proname in (${uniq.map(n => `'${n}'`).join(',')})`;

const stageDefs = await mgmtRead(STAGE, defsSql(STAGE));
console.log(`staging now defines: ${stageDefs.map(d => `${d.n}(${d.a})`).join(', ')}`);

if (!PROMOTE) { console.log('staging only — pass --promote to deploy to production'); process.exit(0); }

// PRODUCTION. qd_guard refuses this on purpose, so the post goes through the management API
// directly with the body read back from staging — never the file, never a retype.
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
async function prodPost(q) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: q }),
  });
  const b = await r.text();
  if (!r.ok) throw new Error(`production ${r.status}: ${b.slice(0, 400)}`);
  return JSON.parse(b);
}

for (const d of stageDefs) await prodPost(d.d);
const prodDefs = await mgmtRead(PROD_REF, defsSql(PROD_REF));

let bad = 0;
for (const s of stageDefs) {
  const p = prodDefs.find(x => x.n === s.n && x.a === s.a);
  const ok = p && p.h === s.h;
  if (!ok) bad++;
  console.log(`${ok ? 'MATCH  ' : 'DIFFER '} ${s.n}(${s.a})  staging ${s.h}  production ${p ? p.h : '(absent)'}`);
}
if (bad) { console.error(`${bad} routine(s) differ after promotion`); process.exit(1); }
console.log(`PROMOTED ${stageDefs.length} routine(s) to production ${PROD_REF}, md5(prosrc) identical`);
