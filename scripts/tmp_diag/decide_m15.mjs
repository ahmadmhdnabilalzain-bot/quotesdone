import { sql } from '../lib/db.mjs';
const q = async (l,s)=>{try{const r=await sql(s);console.log('=== '+l);console.log(JSON.stringify(r).slice(0,7000));}catch(e){console.log('=== '+l+' ERR '+String(e).slice(0,400));}};
await q('compliance steps', `select step_id, workflow_id, step_name, accountable_role_id, independent_reviewer_role_id from public.phase_b_workflow_step where accountable_role_id='compliance_and_privacy_officer' or independent_reviewer_role_id='compliance_and_privacy_officer' or step_name ~* 'complian' order by step_id limit 25`);
await q('task state guard', `select prosrc from pg_proc where proname='fn_phase_c_task_state_guard'`);
