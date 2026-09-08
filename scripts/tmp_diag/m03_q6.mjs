import { sql } from '../lib/db.mjs';
console.log(JSON.stringify(await sql(`
select s.step_id, s.step_no, c.kind, c.next_step_id, s.independent_reviewer_role_id, s.accountable_role_id
from public.phase_b_workflow_step s cross join lateral public.fn_kernel_step_successor(s.step_id) c
where coalesce(btrim(s.independent_reviewer_role_id),'')<>'' and c.kind='same_owner'
order by s.workflow_id, s.step_no`)));
