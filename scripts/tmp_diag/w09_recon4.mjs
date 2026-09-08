import { sql } from '../lib/db.mjs';
const p = (t, r) => { console.log('=== ' + t + ' (' + (r ? r.length : 0) + ') ==='); console.log(JSON.stringify(r, null, 1)); };

p('phase_d_rule_enforcement BR-025 & BR-026', await sql(`select * from public.phase_d_rule_enforcement where rule_id in ('BR-025','BR-026') order by rule_id`));
p('phase_d_context_key_object ALL', await sql(`select * from public.phase_d_context_key_object order by 1`));
p('W09 steps', await sql(`select step_id, step_no, step_name, step_type, accountable_role_id, actor_kind, entry_condition, required_inputs, required_action, required_output, acceptance_criteria, closure_criteria, next_step_if_pass, next_step_if_fail from public.phase_b_workflow_step where workflow_id='W09' order by step_no`));
