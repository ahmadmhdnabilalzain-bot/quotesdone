import { sql } from '../lib/db.mjs';
const q = async (l,s)=>{try{console.log('\n=== '+l);console.log(JSON.stringify(await sql(s),null,1));}catch(e){console.log('\n=== '+l+' ERR '+e.message);}};
await q('check constraints on phase_c_trace / decision_trace / phase_c_step_completion', `
select rel.relname, con.conname, con.contype, pg_get_constraintdef(con.oid) as def
from pg_constraint con join pg_class rel on rel.oid=con.conrelid join pg_namespace n on n.oid=rel.relnamespace
where n.nspname='public' and rel.relname in ('phase_c_trace','decision_trace','phase_c_step_completion','phase_c_task','phase_c_workflow_run')
order by 1,2`);
await q('fn_kernel_system_execution_pair_guard body', `select pg_get_functiondef(p.oid) def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_kernel_system_execution_pair_guard'`);
