import { sql } from '../phase_b/lib/db.mjs';
import { writeFileSync } from 'node:fs';
const names = process.argv.slice(2);
for (const n of names) {
  const r = await sql(`select pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname='${n}'`);
  if (!r.length) { console.log('-- MISSING ' + n); continue; }
  writeFileSync(new URL(`./decide_src_${n}.sql`, import.meta.url), r.map(x=>x.d).join('\n\n'), 'utf8');
  console.log('wrote decide_src_' + n + '.sql', r.map(x=>x.d.length).join(','));
}
