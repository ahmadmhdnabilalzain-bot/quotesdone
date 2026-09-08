import { sql } from '../lib/db.mjs';
const r = await sql(`select pg_get_functiondef(p.oid) as def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='fn_phase_d_injected_defect_report'`);
console.log(r.map(x=>x.def).join('\n\n=====\n\n'));
