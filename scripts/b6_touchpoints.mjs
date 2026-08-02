// Which functions do the Stage B.6 migrations create or replace, and which of
// those already existed before B.6? The second set is what a B.6 rollback must
// restore, not drop.
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
const MIG = join(process.cwd(), 'supabase', 'migrations');
const b6 = readdirSync(MIG).filter(f => /^2026080222\d{2}_/.test(f)).sort();
const pre = readdirSync(MIG).filter(f => /^2026080223\d{2}_/.test(f)).sort();

const fns = src => {
  const s = new Set();
  for (const f of src) {
    const sql = readFileSync(join(MIG, f), 'utf8');
    for (const m of sql.matchAll(/create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?([a-z0-9_]+)/gi)) s.add(m[1]);
  }
  return s;
};
const B6 = fns(b6), PRE = fns(pre);
const created = [...B6].filter(x => !PRE.has(x)).sort();
const replaced = [...B6].filter(x => PRE.has(x)).sort();

// what the current rollback actually touches
const rb = readFileSync(join(MIG, '202608022212_p2_c1_stage_b6_operator_rollback.sql'), 'utf8');
const dropped = new Set([...rb.matchAll(/drop\s+function\s+if\s+exists\s+public\.([a-z0-9_]+)/gi)].map(m => m[1]));
const restored = new Set([...rb.matchAll(/create\s+or\s+replace\s+function\s+public\.([a-z0-9_]+)/gi)].map(m => m[1]));
restored.delete('fn_p2c1_rollback_stage_b6');

console.log('B.6 CREATES (rollback must DROP):');
for (const f of created) console.log(`  ${dropped.has(f) ? 'ok   ' : 'MISS '} ${f}`);
console.log('\nB.6 REPLACES a prior-stage function (rollback must RESTORE):');
for (const f of replaced) console.log(`  ${restored.has(f) ? 'ok   ' : 'MISS '} ${f}`);

const b6tables = new Set(), b6views = new Set();
for (const f of b6) {
  const sql = readFileSync(join(MIG, f), 'utf8');
  for (const m of sql.matchAll(/create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?([a-z0-9_]+)/gi)) b6tables.add(m[1]);
  for (const m of sql.matchAll(/create\s+(?:or\s+replace\s+)?view\s+(?:public\.)?([a-z0-9_]+)/gi)) b6views.add(m[1]);
}
const rbTables = new Set([...rb.matchAll(/drop\s+table\s+if\s+exists\s+public\.([a-z0-9_]+)/gi)].map(m => m[1]));
const rbViews = new Set([...rb.matchAll(/drop\s+view\s+if\s+exists\s+public\.([a-z0-9_]+)/gi)].map(m => m[1]));
console.log('\nB.6 TABLES:');
for (const t of [...b6tables].sort()) console.log(`  ${rbTables.has(t) ? 'ok   ' : 'MISS '} ${t}`);
console.log('\nB.6 VIEWS:');
for (const v of [...b6views].sort()) console.log(`  ${rbViews.has(v) ? 'ok   ' : 'MISS '} ${v}`);
