import { sql } from '../phase_b/lib/db.mjs';
const name = process.argv[2];
const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname||'.'||p.proname = '${name}'`);
for (const x of r) console.log(x.def);
