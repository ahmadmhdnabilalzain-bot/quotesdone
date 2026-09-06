import { sql } from '../phase_b/lib/db.mjs';
const q=async(s,l)=>{try{console.log('\n== '+l); console.log(JSON.stringify(await sql(s),null,1).slice(0,4000));}catch(e){console.log('\n== '+l+' ERR '+e.message.slice(0,200));}};
await q(`select column_name from information_schema.columns where table_schema='public' and table_name='phase_d_handler_binding' order by ordinal_position`,'hb cols');
await q(`select s.step_id, s.step_name, s.gate_ids, s.business_rule_ids from public.phase_b_workflow_step s where s.workflow_id='W12' order by s.step_no`,'W12 steps');
