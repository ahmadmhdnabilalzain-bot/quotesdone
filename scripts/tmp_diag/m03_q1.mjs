import { sql } from '../lib/db.mjs';
const r = await sql(`
select s.workflow_id, count(*) n,
  count(*) filter (where coalesce(btrim(s.independent_reviewer_role_id),'')<>'') rev,
  count(*) filter (where s.is_closure_step) clo,
  min(s.step_no) filter (where coalesce(btrim(s.independent_reviewer_role_id),'')<>'') first_rev_no
from public.phase_b_workflow_step s group by 1 order by n, 1`);
console.log(JSON.stringify(r));
