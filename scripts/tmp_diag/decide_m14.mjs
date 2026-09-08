import { sql } from '../lib/db.mjs';
const q = async (l,s)=>{try{const r=await sql(s);console.log('=== '+l);console.log(JSON.stringify(r).slice(0,6000));}catch(e){console.log('=== '+l+' ERR '+String(e).slice(0,400));}};
await q('ws cols', `select column_name from information_schema.columns where table_schema='public' and table_name='phase_b_workflow_step' order by ordinal_position`);
await q('compliance steps', `select step_id, step_name, actor_role_id, reviewer_role_id from public.phase_b_workflow_step where actor_role_id='compliance_and_privacy_officer' or step_name ~* 'complian' limit 20`);
await q('task state guard src', `select (prosrc ~* 'reviewer') has_reviewer, length(prosrc) from pg_proc where proname='fn_phase_c_task_state_guard'`);
