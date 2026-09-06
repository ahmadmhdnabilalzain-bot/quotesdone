import { sql } from '../phase_b/lib/db.mjs';
const r = await sql(`select p.oid::regprocedure::text as sig, pg_get_functiondef(p.oid) as def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='fn_phase_d_run_injected_defects'`);
console.log(JSON.stringify(r.map(x=>({sig:x.sig,len:x.def.length}))));
const fs = await import('node:fs');
for (const x of r) fs.writeFileSync('scripts/tmp_diag/LIVE_fn_phase_d_run_injected_defects.sql', x.def);
