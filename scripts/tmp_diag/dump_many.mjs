import { writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';
const names = process.argv.slice(2);
for (const name of names) {
  try {
    const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='${name}'`);
    if (!r.length) { console.log(`${name}: no such function`); continue; }
    writeFileSync(`scripts/tmp_diag/${name}.txt`, r.map((x) => x.def).join('\n\n-- ---- next overload ----\n\n'));
    console.log(`${name}: ${r.length} def(s), ${r.map(x=>x.def.length).join('+')} chars`);
  } catch (e) { console.log(`${name}: ERR ${String(e.message).slice(0,200)}`); }
}
