// Which COLUMNS and VIEWS differ in shape between staging and production, entry by entry.
//
// apply_sql.mjs --ddl asserts a single whole-schema digest, and a digest can only ever say "these
// differ". This says WHICH — and the brief's rule is that a red parity check is a question about
// which side is RIGHT, not an instruction to level one onto the other. Chasing one of these found
// production searching 70% of its own knowledge base; the obvious fix would have destroyed 1,506
// embeddings.
//
//   node scripts/diff_schema_shape.mjs            # columns + views
//   node scripts/diff_schema_shape.mjs --views    # view definitions only
import { mgmtRead, PROD_REF } from './lib/qd_guard.mjs';
import { REF as STAGE } from './lib/demo_factory.mjs';

const VIEWS_ONLY = process.argv.includes('--views');
const SHOW = (process.argv.find(a => a.startsWith('--show=')) || '').slice(7);
if (SHOW) {
  const d = async (ref) => (await mgmtRead(ref,
    `select definition from pg_views where schemaname='public' and viewname='${SHOW}'`))[0]?.definition ?? '(absent)';
  const [ds, dp] = [await d(STAGE), await d(PROD_REF)];
  const ls = ds.split('\n'), lp = dp.split('\n');
  console.log(`--- ${SHOW} — staging ${ls.length} lines, production ${lp.length} lines ---`);
  for (let i = 0; i < Math.max(ls.length, lp.length); i++) {
    if ((ls[i] ?? '') !== (lp[i] ?? '')) {
      console.log(`  L${i + 1} STAGING    ${(ls[i] ?? '(none)').trim()}`);
      console.log(`  L${i + 1} PRODUCTION ${(lp[i] ?? '(none)').trim()}`);
    }
  }
  process.exit(0);
}
const SQL = `${VIEWS_ONLY ? '' : `select 'c:'||table_name||'.'||column_name||':'||data_type||':'||is_nullable
       ||':'||coalesce(column_default,'-') x
  from information_schema.columns where table_schema='public'
union all`}
select 'v:'||viewname||':'||md5(definition) x from pg_views where schemaname='public'`;

const get = async (ref) => new Set((await mgmtRead(ref, SQL)).map(r => r.x));
const [s, p] = [await get(STAGE), await get(PROD_REF)];
const onlyS = [...s].filter(x => !p.has(x)).sort();
const onlyP = [...p].filter(x => !s.has(x)).sort();

console.log(`staging ${s.size} entries · production ${p.size} entries`);
console.log(`\nONLY ON STAGING (${onlyS.length}):`);
for (const x of onlyS) console.log('  ' + x.slice(0, 160));
console.log(`\nONLY ON PRODUCTION (${onlyP.length}):`);
for (const x of onlyP) console.log('  ' + x.slice(0, 160));

// A column present on both under the same name but with a different type/default appears in BOTH
// lists, which is the case most easily misread as "two unrelated drifts".
const nameOf = (x) => x.split(':').slice(0, 2).join(':');
const both = new Set(onlyS.map(nameOf).filter(n => onlyP.map(nameOf).includes(n)));
if (both.size) {
  console.log(`\nSAME OBJECT, DIFFERENT SHAPE (${both.size}) — these are ONE drift each, not two:`);
  for (const n of both) console.log('  ' + n);
}
process.exit(onlyS.length || onlyP.length ? 1 : 0);
