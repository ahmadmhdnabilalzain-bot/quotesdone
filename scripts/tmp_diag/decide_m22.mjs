import { sql } from '../phase_b/lib/db.mjs';
const q = async (l,s)=>{try{const r=await sql(s);console.log('=== '+l);console.log(JSON.stringify(r).slice(0,3500));}catch(e){console.log('=== '+l+' ERR '+String(e).slice(0,300));}};
await q('inquiries triggers', `select tgname, tgfoid::regproc::text f from pg_trigger where tgrelid='public.inquiries'::regclass and not tgisinternal order by tgname`);
await q('object_write kernel owned', `select (prosrc ~ 'pd_object_kernel_owned') hit, substring(prosrc from '.{0,140}pd_object_kernel_owned.{0,60}') frag from pg_proc where proname='fn_phase_d_object_write'`);
await q('phase_b freeze on step', `select tgname, tgfoid::regproc::text f from pg_trigger where tgrelid='public.phase_b_workflow_step'::regclass and not tgisinternal`);
await q('gate_evaluate handlers', `select (length(prosrc)-length(replace(lower(prosrc),'exception when','')))/14 handlers from pg_proc where proname='fn_phase_d_gate_evaluate'`);
await q('event self loops', `select count(*) n from public.phase_b_event e where e.producer_step_id is not null and e.producer_step_id = e.consumer_step_id`);
await q('phase_b_event cols', `select column_name from information_schema.columns where table_schema='public' and table_name='phase_b_event' order by ordinal_position`);
