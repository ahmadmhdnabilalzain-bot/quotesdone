import { sql } from '../lib/db.mjs';
const q=async(s,l)=>{try{console.log('\n== '+l); console.log(JSON.stringify(await sql(s),null,1).slice(0,3000));}catch(e){console.log('\n== '+l+' ERR '+e.message.slice(0,300));}};
await q(`select t.tgname, pg_get_triggerdef(t.oid) def from pg_trigger t where t.tgrelid='public.phase_d_object_record'::regclass and not t.tgisinternal`,'objrec trig defs');
await q(`select * from public.phase_d_object_state_contract where object_id in ('supplier_account','supplier_assignment','customer_terms_acceptance')`,'state contracts');
await q(`select s.step_id, s.workflow_id, s.step_no, s.step_name, b.handler_kind, b.handler_ref, b.object_id
 from public.phase_b_workflow_step s left join public.phase_d_handler_binding b on b.step_id=s.step_id
 where s.workflow_id='W12' order by s.step_no`,'W12 steps');
