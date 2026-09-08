import { sql } from '../lib/db.mjs';
import fs from 'node:fs';
const r = await sql(`select p.oid::regprocedure::text sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('fn_phase_c_trace_write','fn_kernel_review_decide','fn_kernel_review_record')`);
console.log(JSON.stringify(r));
for (const x of r) {
  const d = await sql(`select pg_get_functiondef('${x.sig}'::regprocedure) as d`);
  fs.appendFileSync('scripts/tmp_diag/m03_trace_write.sql', d[0].d + '\n\n');
}
