import { sql } from '../lib/db.mjs';
const a = await sql(`select count(*) n_with_reviewer from public.phase_b_workflow_step where nullif(btrim(independent_reviewer_role_id),'') is not null`);
const b = await sql(`select count(*) filter (where (next_step_if_pass='WORKFLOW_COMPLETE') <> is_closure_step) n_disagree, count(*) total, count(*) filter (where is_closure_step) n_closure from public.phase_b_workflow_step`);
const c = await sql(`select count(*) n from public.phase_b_workflow_step`);
console.log(JSON.stringify({a,b,c}));
