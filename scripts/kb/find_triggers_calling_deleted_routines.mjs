// A TRIGGER WHOSE CALLEE NO LONGER EXISTS IS A TABLE THAT CANNOT BE WRITTEN TO
//
// plpgsql resolves a called routine at RUN time. So when the 7 September deletion removed 461
// routines, every trigger that called one kept working -- until the first insert on its table, which
// then failed with "function ... does not exist". The first one found this way was on public.leads:
// no supplier could register.
//
// This finds all of them by reading each trigger function's body and checking every public.fn_*
// it calls against the live catalogue. The regex runs in JS on purpose: the SQL transport strips
// backslashes, so a pattern written into a query arrives with its escapes missing.
//
//   node scripts/kb/find_triggers_calling_deleted_routines.mjs [--fix]
//
// --fix DROPS the broken trigger. That is the right repair here and not a loss: the trigger's whole
// purpose was to call a routine the founder deleted, so the behaviour it added is gone either way.
// The choice is between a table nobody can write to and a table that works without a feature that
// no longer exists.

import { sql } from '../phase_c/lib/db.mjs';

const FIX = process.argv.includes('--fix');

const live = new Set((await sql(`select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'`)).map((x) => x.proname));

const trg = await sql(`select c.relname tbl, t.tgname, p.proname fn, p.prosrc
  from pg_trigger t join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace join pg_proc p on p.oid=t.tgfoid
 where n.nspname='public' and not t.tgisinternal order by c.relname, t.tgname`);

const CALL = /public\.(fn_[a-z0-9_]+)\s*\(/gi;
const broken = [];
for (const t of trg) {
  const missing = new Set();
  CALL.lastIndex = 0;
  let m;
  while ((m = CALL.exec(t.prosrc || ''))) if (!live.has(m[1].toLowerCase())) missing.add(m[1]);
  if (missing.size) broken.push({ ...t, missing: [...missing] });
}

console.log('triggers examined: ' + trg.length);
console.log('triggers calling a routine that no longer exists: ' + broken.length);
const tables = new Set(broken.map((b) => b.tbl));
console.log('tables that cannot be written to: ' + tables.size + (tables.size ? ' — ' + [...tables].join(', ') : ''));
for (const b of broken) console.log('  ' + b.tbl + '.' + b.tgname + '  (' + b.fn + ') -> ' + b.missing.join(', '));

if (!FIX) { console.log('\nread only — pass --fix to drop them'); process.exit(0); }

let dropped = 0;
for (const b of broken) {
  try { await sql(`drop trigger if exists "${b.tgname}" on public."${b.tbl}"`); dropped++; }
  catch (e) { console.log('  REFUSED ' + b.tbl + '.' + b.tgname + ' :: ' + String(e.message).replace(/\s+/g, ' ').slice(0, 120)); }
}
console.log('dropped ' + dropped + ' broken trigger(s)');
process.exit(0);
