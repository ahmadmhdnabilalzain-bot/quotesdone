import { sql } from '../phase_b/lib/db.mjs';
const q=async(l,t)=>{try{console.log(`\n### ${l}`);console.log(JSON.stringify(await sql(t),null,1).slice(0,4000));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,300)}`)}};
await q('handler_schema W09-S06', `select * from public.phase_d_handler_schema where step_id='W09-S06'`);
await q('handler_binding W09-S06', `select * from public.phase_d_handler_binding where step_id='W09-S06'`);
await q('object_state_contract terms', `select * from public.phase_d_object_state_contract where object_id ilike '%terms_acceptance%'`);
await q('handler_schema cols', `select column_name from information_schema.columns where table_schema='public' and table_name='phase_d_handler_schema' order by ordinal_position`);
