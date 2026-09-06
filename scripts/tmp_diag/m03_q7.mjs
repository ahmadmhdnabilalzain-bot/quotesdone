import { sql } from '../phase_b/lib/db.mjs';
console.log(JSON.stringify(await sql(`
select s.workflow_id, s.step_id, s.step_no, coalesce(s.independent_reviewer_role_id,'-') rev,
  (select count(*) from public.phase_b_workflow_step z where z.workflow_id=s.workflow_id) n
from public.phase_b_workflow_step s where s.is_closure_step
  and s.workflow_id in ('W04','W05','W08','W09','W10','W14','W23','W25','W27')
order by s.workflow_id`)));
