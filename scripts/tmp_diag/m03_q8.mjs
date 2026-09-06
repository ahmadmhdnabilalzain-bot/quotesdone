import { sql } from '../phase_b/lib/db.mjs';
console.log(JSON.stringify(await sql(`
select
 (select count(*) from public.phase_b_workflow_step) steps,
 (select count(*) from public.phase_b_workflow_step where coalesce(btrim(independent_reviewer_role_id),'')<>'') with_rev,
 (select count(*) from public.phase_b_workflow_step s cross join lateral public.fn_kernel_step_successor(s.step_id) c where c.kind='closure_flag_disagrees') disagree,
 (select count(*) from public.phase_b_workflow_step s cross join lateral public.fn_kernel_step_successor(s.step_id) c where c.kind='closure') closure,
 (select count(*) from public.phase_b_step_transition where from_state='completed' and to_state='completed') completed_edge
`)));
