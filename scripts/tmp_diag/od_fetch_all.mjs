import { sql } from '../phase_b/lib/db.mjs';
import fs from 'node:fs';
const n = await sql(`select count(*)::int c, sum(length(prosrc))::bigint b from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public'`);
console.error('funcs', JSON.stringify(n));
const out = {};
let off = 0;
while (true) {
  const r = await sql(`select p.proname, p.prosrc from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' order by p.oid limit 300 offset ${off}`);
  if (!r.length) break;
  for (const x of r) out[x.proname] = (out[x.proname]||'') + '\n' + x.prosrc;
  off += 300;
  console.error('off', off);
}
fs.writeFileSync(new URL('./allfns.json', import.meta.url), JSON.stringify(out));
console.error('done', Object.keys(out).length);
