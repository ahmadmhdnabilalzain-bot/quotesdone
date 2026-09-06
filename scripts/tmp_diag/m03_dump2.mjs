import { sql } from '../phase_b/lib/db.mjs';
import fs from 'node:fs';
for (const f of ['fn_kernel_step_complete(jsonb)','fn_kernel_review_decide(jsonb)','fn_phase_c_trace_write(jsonb)','fn_kernel_step_successor(text)','fn_phase_d_drive_workflow(jsonb)']) {
  try {
    const r = await sql(`select pg_get_functiondef('public.${f}'::regprocedure) as d`);
    const n = f.split('(')[0];
    fs.writeFileSync(`scripts/tmp_diag/m03_${n}.sql`, r[0].d);
    console.log(n, r[0].d.split('\n').length);
  } catch (e) { console.log(f, 'ERR', String(e.message).slice(0,200)); }
}
