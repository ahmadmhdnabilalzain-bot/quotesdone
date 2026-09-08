import { sql } from '../lib/db.mjs';
const q = async (label, s) => { try { console.log('\n=== '+label); console.log(JSON.stringify(await sql(s), null, 1)); } catch(e){ console.log('\n=== '+label+' ERROR '+e.message); } };
await q('phase_c_task columns', `select column_name,data_type from information_schema.columns where table_schema='public' and table_name='phase_c_task' order by ordinal_position`);
await q('routines that write phase_c_task (kernel_write_authority)', `select * from public.kernel_write_authority order by table_name, routine_name`);
await q('phase_c_workflow_run cols relevant', `select column_name from information_schema.columns where table_schema='public' and table_name='phase_c_workflow_run' and column_name in ('closed_at','status','state') order by 1`);
