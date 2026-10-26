// DELETE WHAT DOES NOT BELONG TO THE NEW STRUCTURE
//
// Founder, 7 September 2026: "anything that doesnt belong to the current new structure need to be
// deleted. by new structure i mean today from the time i told you to remove all previous agents".
//
// The drop list comes from new_structure_closure.mjs, which keeps three things: what the founder
// named as the new structure, whatever the live product code actually calls, and -- computed by
// closure until it stopped growing -- everything those survivors depend on.
//
// NO CASCADE, deliberately. A drop that cascades will happily take a kept object with it and report
// success. Without cascade, an object that something still depends on REFUSES, and the refusal is
// printed. A refusal here is information, not an obstacle: it means the closure missed an edge, and
// the right response is to look, not to add cascade.
//
//   node scripts/kb/drop_what_is_not_the_new_structure.mjs --list <drop_list.json> [--apply]

import { readFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const at = (f) => { const i = process.argv.indexOf(f); return i >= 0 ? process.argv[i + 1] : null; };
const LIST = at('--list');
const APPLY = process.argv.includes('--apply');
if (!LIST) { console.error('--list <drop_list.json> is required'); process.exit(2); }
const { tables, routines } = JSON.parse(readFileSync(LIST, 'utf8'));
console.log('to drop: ' + routines.length + ' routine(s), ' + tables.length + ' table(s)');
if (!APPLY) { console.log('DRY RUN — nothing dropped. Re-run with --apply.'); process.exit(0); }

// ---- routines first: they reference tables, so removing them first frees the tables ------------
let rOk = 0; const rBad = [];
for (const name of routines) {
  // Every overload of the name, dropped by its exact identity arguments.
  let sigs = [];
  try {
    sigs = await sql(`select pg_get_function_identity_arguments(p.oid) a from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = '${name.replace(/'/g, "''")}'`);
  } catch { /* gone already */ }
  for (const s of sigs) {
    try { await sql(`drop function if exists public."${name}"(${s.a})`); rOk++; }
    catch (e) { rBad.push(name + '(' + s.a + ') :: ' + String(e.message).replace(/\s+/g, ' ').slice(0, 110)); }
  }
}
console.log('routines dropped: ' + rOk + (rBad.length ? ', refused ' + rBad.length : ''));
for (const b of rBad.slice(0, 10)) console.log('  ' + b);

// ---- then tables, repeatedly: order is unknown, so keep passing until nothing more will go -----
let remaining = [...tables];
let tOk = 0;
for (let pass = 1; pass <= 12 && remaining.length; pass++) {
  const next = [];
  for (const t of remaining) {
    try { await sql(`drop table if exists public."${t}"`); tOk++; }
    catch { next.push(t); }
  }
  console.log('  table pass ' + pass + ': dropped ' + (remaining.length - next.length) + ', still held ' + next.length);
  if (next.length === remaining.length) { remaining = next; break; }
  remaining = next;
}
console.log('tables dropped: ' + tOk + (remaining.length ? ', still held ' + remaining.length : ''));
for (const t of remaining.slice(0, 20)) {
  // Say WHY it is held, rather than just that it is.
  const dep = await sql(`select distinct tc.table_name from information_schema.table_constraints tc
    join information_schema.constraint_column_usage ccu on ccu.constraint_name = tc.constraint_name
   where tc.constraint_type = 'FOREIGN KEY' and ccu.table_name = '${t.replace(/'/g, "''")}'
     and tc.table_name <> '${t.replace(/'/g, "''")}' limit 4`);
  console.log('  ' + t + ' held by: ' + (dep.map((d) => d.table_name).join(', ') || '(a view or a policy)'));
}

const after = await sql(`select
  (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r') tables,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')) routines`);
console.log('\nAFTER: ' + JSON.stringify(after[0]));
process.exit(0);
