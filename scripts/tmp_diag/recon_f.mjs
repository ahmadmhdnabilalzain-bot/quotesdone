import { sql } from '../lib/db.mjs';
import fs from 'node:fs';
const names = ['fn_workflow_step_claim','fn_phase_c_outbox_claim','fn_kernel_outbox_deliver','fn_kernel_step_complete','fn_kernel_task_accept','fn_kernel_handoff_accept'];
const r = await sql(`select p.proname, p.oid::regprocedure::text sig, pg_get_functiondef(p.oid) as def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname = any(array[${names.map(n=>`'${n}'`).join(',')}]) order by 1`);
let out=''; for(const x of r) out += '\n\n=========== '+x.sig+'\n'+x.def;
fs.writeFileSync('scripts/tmp_diag/recon_claim_fns.sql', out);
console.log(r.map(x=>x.sig+' len='+x.def.length).join('\n'));
// any routine that claims a task
const c = await sql(`select p.oid::regprocedure::text sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.prokind='f' and p.prolang<>12 and (p.proname ilike '%accept%' or p.proname ilike '%_claim%' or p.proname ilike '%claim_%') order by 1`);
console.log('\nACCEPT/CLAIM:\n'+c.map(x=>x.sig).join('\n'));
