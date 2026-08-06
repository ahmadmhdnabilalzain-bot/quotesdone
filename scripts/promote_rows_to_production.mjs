// Promote CONFIG ROWS from staging to production the same way routines are promoted: read the
// verified value back out and post it, never retype it.
//
// This exists because retyping is a bug class, not a style preference. Hand-copying one
// quality_standard row through a SQL literal turned the regex \y into \\y — four backslashes
// where two were meant — and produced a criteria digest that differed from staging's while
// looking identical in every display that JSON-escapes. The row would have silently stopped
// matching word boundaries.
//
//   node scripts/promote_rows_to_production.mjs <table> <key_column> <key_value> [...]
//   node scripts/promote_rows_to_production.mjs quality_standard work_type org_task
//
// Asserts a whole-row md5 match on both projects afterwards and exits non-zero if they differ.
import { readFileSync } from 'node:fs';
import { mgmtRead, PROD_REF } from './staging/qd_guard.mjs';
import { REF as STAGE } from './staging/demo_factory.mjs';

const [table, keyCol, ...keys] = process.argv.slice(2);
if (!table || !keyCol || !keys.length) {
  console.error('usage: node scripts/promote_rows_to_production.mjs <table> <key_column> <key_value...>');
  process.exit(2);
}
const q = (t) => (t.includes('.') ? t : `public.${t}`);
const one = (r) => (r && r[0]) ? Object.values(r[0])[0] : null;
const inList = keys.map(k => `'${k.replace(/'/g, "''")}'`).join(',');
const where = `${keyCol} in (${inList})`;

const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
async function prodPost(sql) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  const b = await r.text();
  if (!r.ok) throw new Error(`production ${r.status}: ${b.slice(0, 400)}`);
  return JSON.parse(b);
}

// ::text so the payload never becomes a JavaScript value — jsonb renders numerics at their stored
// scale and parsing silently rewrites them.
const json = String(one(await mgmtRead(STAGE,
  `select coalesce(jsonb_agg(z), '[]'::jsonb)::text from ${q(table)} z where ${where}`)) ?? '[]');
const n = JSON.parse(json).length;
if (!n) { console.error(`no rows matched ${where} on staging`); process.exit(1); }

await prodPost(`delete from ${q(table)} where ${where};
  insert into ${q(table)} select * from jsonb_populate_recordset(null::${q(table)}, '${json.replace(/'/g, "''")}'::jsonb);`);

const DIGEST = `select md5(coalesce(string_agg(x, '|' order by x), '')) from
  (select md5(to_jsonb(z)::text) x from ${q(table)} z where ${where}) s`;
const sh = one(await mgmtRead(STAGE, DIGEST));
const ph = one(await mgmtRead(PROD_REF, DIGEST));
console.log(`${sh === ph ? 'MATCH ' : 'DIFFER'} ${table} [${keys.join(', ')}]  staging ${sh}  production ${ph}`);
if (sh !== ph) process.exit(1);
console.log(`PROMOTED ${n} row(s) of ${table} to production ${PROD_REF}, digest identical`);
