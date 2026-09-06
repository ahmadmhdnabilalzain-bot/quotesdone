import { sql } from '../phase_b/lib/db.mjs';
const r = await sql(`select table_name, routine_name from public.kernel_write_authority where table_name in ('phase_c_task','phase_c_refund_decision','phase_c_workflow_step_run','phase_c_trace') order by 1,2`);
for (const x of r) console.log(x.table_name + ' <- ' + x.routine_name);
