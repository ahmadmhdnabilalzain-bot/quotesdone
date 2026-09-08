import { sql } from '../lib/db.mjs';
const q = async (l,s)=>{try{console.log('\n=== '+l);console.log(JSON.stringify(await sql(s),null,1));}catch(e){console.log('\n=== '+l+' ERR '+e.message);}};
await q('pair guard + task trace committed bodies', `select p.proname, pg_get_functiondef(p.oid) def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('fn_kernel_system_execution_pair_guard','fn_phase_c_task_trace_committed','fn_phase_c_task_trace_guard')`);
await q('pd_object_kernel_owned', `select * from public.pd_object_kernel_owned limit 50`);
