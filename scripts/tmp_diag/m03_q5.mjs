import { sql } from '../lib/db.mjs';
console.log(JSON.stringify(await sql(`select column_name from information_schema.columns where table_name='phase_b_workflow_step' order by ordinal_position`).then(r=>r.map(x=>x.column_name))));
console.log(JSON.stringify(await sql(`select step_id, step_no, is_closure_step, independent_reviewer_role_id, next_step_if_pass from public.phase_b_workflow_step where workflow_id='W06' order by step_no`)));
console.log(JSON.stringify(await sql(`select * from public.fn_kernel_step_successor('W06-S05')`)));
console.log(JSON.stringify(await sql(`select * from public.fn_kernel_step_successor('W06-S07')`)));
