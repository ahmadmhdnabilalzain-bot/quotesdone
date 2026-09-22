// REPLAY A MIGRATION ON STAGING AND ASSERT IT STILL MATCHES PRODUCTION.
//
// The repo file is the claim; production is the fact. Replaying the migration on staging and then
// comparing md5(prosrc) with production is how the two are held to each other. On 8 Aug 2026 this
// caught real drift: two routine comments had been edited after promotion, so the repo and
// production disagreed invisibly — every count-based check in the repo passed while the file on
// disk no longer described what was running.
//
//   node scripts/staging/replay_parity.mjs supabase/migrations/20260808010000_row5_supplier_portal.sql
//
// Read-only against production, by construction: qd_guard's mgmtRead refuses anything else.
// Exits non-zero on any mismatch. It never writes to production — promotion is apply_sql.mjs.
import { readFileSync } from 'node:fs';
import { mgmtRead, mgmtWrite, PROD_REF } from '../lib/qd_guard.mjs';
import { REF as STAGE } from '../lib/demo_factory.mjs';

const file = process.argv[2];
if (!file) { console.error('usage: node scripts/staging/replay_parity.mjs <file.sql>'); process.exit(2); }

const sql = readFileSync(file, 'utf8');
const names = [...new Set([...sql.matchAll(/create\s+or\s+replace\s+function\s+(?:public\.)?([a-z0-9_]+)\s*\(/gi)]
  .map(m => m[1].toLowerCase()))];
if (!names.length) { console.error(`${file} defines no routines; nothing to compare`); process.exit(2); }

await mgmtWrite(STAGE, sql, `replay ${file}`);
console.log(`replayed ${file} on staging ${STAGE} (${names.length} routines)\n`);

// Compare the raw body AND a comment-blind body. A comment-only difference is a documentation
// drift, not a behaviour drift, and reporting them as the same thing is how a chore gets treated
// as an incident (and vice versa).
const defs = (ref) => `select p.proname n, pg_get_function_identity_arguments(p.oid) a,
    md5(p.prosrc) raw,
    md5(regexp_replace(regexp_replace(p.prosrc,'--[^\\n]*','','g'),'\\s+',' ','g')) code
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname='public' and p.proname in (${names.map(n => `'${n}'`).join(',')})
 order by 1,2`;

const [s, p] = await Promise.all([mgmtRead(STAGE, defs(STAGE)), mgmtRead(PROD_REF, defs(PROD_REF))]);

let bad = 0, comments = 0;
for (const sd of s) {
  const pd = p.find(x => x.n === sd.n && x.a === sd.a);
  if (!pd) { bad++; console.log(`ABSENT   ${sd.n}(${sd.a})  — not on production`); continue; }
  if (pd.raw === sd.raw) { console.log(`IDENTICAL ${sd.n}(${sd.a})  ${sd.raw}`); continue; }
  if (pd.code === sd.code) { comments++; console.log(`COMMENT  ${sd.n}(${sd.a})  bodies equal, comments differ`); continue; }
  bad++;
  console.log(`DIFFER   ${sd.n}(${sd.a})  staging ${sd.raw}  production ${pd.raw}`);
}
for (const pd of p) if (!s.find(x => x.n === pd.n && x.a === pd.a)) { bad++; console.log(`EXTRA    ${pd.n}(${pd.a})  on production, not defined by this file`); }

console.log(`\n${s.length} routine(s) replayed; ${bad} differ, ${comments} comment-only`);
if (bad) process.exit(1);
