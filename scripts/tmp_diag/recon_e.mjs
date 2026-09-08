import { sql } from '../lib/db.mjs';
import fs from 'node:fs';
const names = ['fn_phase_c_trace_append_only','fn_phase_c_trace_advance','fn_phase_c_trace_write','fn_seal_decision_trace','fn_decision_trace_immutable','fn_kernel_write_guard','fn_phase_c_step_run_trace_guard'];
const r = await sql(`select p.proname, pg_get_functiondef(p.oid) as def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname = any(array[${names.map(n=>`'${n}'`).join(',')}]) order by 1`);
let out=''; for(const x of r) out += '\n\n=========== '+x.proname+'\n'+x.def;
fs.writeFileSync('scripts/tmp_diag/recon_trace_fns.sql', out);
console.log(r.map(x=>x.proname+' '+x.def.length).join('\n'));
// claim routines
const c = await sql(`select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.prokind='f' and p.prolang<>12 and (p.proname ilike '%claim%' or pg_get_functiondef(p.oid) ilike '%skip locked%' or pg_get_functiondef(p.oid) ilike '%pg_try_advisory%') order by 1`);
console.log('\nCLAIM/LOCK ROUTINES:\n'+c.map(x=>x.proname).join('\n'));
