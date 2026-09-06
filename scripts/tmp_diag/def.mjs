import { q } from './q.mjs';
const sig = process.argv[2];
const r = await q(`select pg_get_functiondef(p.oid) d
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = '${sig}'`);
for (const row of r) console.log(row.d);
