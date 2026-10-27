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
import { supabaseAccessToken } from './lib/supabase_token.mjs';
import { readFileSync } from 'node:fs';
import { mgmtRead, PROD_REF } from './lib/qd_guard.mjs';
import { REF as STAGE } from './lib/demo_factory.mjs';

const [table, keyCol, ...keys] = process.argv.slice(2);
if (!table || !keyCol || !keys.length) {
  console.error('usage: node scripts/promote_rows_to_production.mjs <table> <key_column> <key_value...>');
  process.exit(2);
}
const q = (t) => (t.includes('.') ? t : `public.${t}`);
const one = (r) => (r && r[0]) ? Object.values(r[0])[0] : null;
const inList = keys.map(k => `'${k.replace(/'/g, "''")}'`).join(',');
const where = `${keyCol} in (${inList})`;

const token = supabaseAccessToken();
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

// UPSERT, not delete-then-insert. company_goals.key is referenced by employee_kpi.serves_goal and
// department_objective.goal_key, so clearing a row to re-add it raises 23503 — the row is the same
// row, and deleting it is not a detail of "replacing" it.
//
// `on conflict DO UPDATE`, never `do nothing`: a no-op upsert preserves a key set exactly the way a
// duplicate-and-drop bug preserves a count, so a corrected value would silently never arrive while
// the row count and key digest still matched.
const cols = (await mgmtRead(STAGE,
  `select column_name from information_schema.columns
    where table_schema = '${table.includes('.') ? table.split('.')[0] : 'public'}'
      and table_name = '${table.includes('.') ? table.split('.')[1] : table}'
    order by ordinal_position`)).map(r => r.column_name);
const setList = cols.filter(c => c !== keyCol).map(c => `"${c}" = excluded."${c}"`).join(', ');

await prodPost(
  `insert into ${q(table)} select * from jsonb_populate_recordset(null::${q(table)}, '${json.replace(/'/g, "''")}'::jsonb)
   on conflict ("${keyCol}") do update set ${setList};`);

const DIGEST = `select md5(coalesce(string_agg(x, '|' order by x), '')) from
  (select md5(to_jsonb(z)::text) x from ${q(table)} z where ${where}) s`;
const sh = one(await mgmtRead(STAGE, DIGEST));
const ph = one(await mgmtRead(PROD_REF, DIGEST));
console.log(`${sh === ph ? 'MATCH ' : 'DIFFER'} ${table} [${keys.join(', ')}]  staging ${sh}  production ${ph}`);
if (sh !== ph) process.exit(1);
console.log(`PROMOTED ${n} row(s) of ${table} to production ${PROD_REF}, digest identical`);
