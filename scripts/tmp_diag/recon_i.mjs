import { sql } from '../phase_b/lib/db.mjs';
import fs from 'node:fs';
const names=['fn_phase_c_task_transition','fn_kernel_open_step','fn_kernel_workflow_start','fn_phase_c_task_create','fn_kernel_review_decide'];
const r = await sql(`select p.oid::regprocedure::text sig, pg_get_functiondef(p.oid) def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=any(array[${names.map(n=>`'${n}'`).join(',')}]) order by 1`);
let out=''; for(const x of r) out+='\n\n=========== '+x.sig+'\n'+x.def;
fs.writeFileSync('scripts/tmp_diag/recon_task_fns.sql', out);
console.log(r.map(x=>x.sig+' '+x.def.length).join('\n'));
