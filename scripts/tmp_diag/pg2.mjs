import { sql } from '../lib/db.mjs';
const q=async(l,t)=>{try{console.log(`\n### ${l}`);const r=await sql(t);console.log(typeof r==='string'?r:JSON.stringify(r).slice(0,2500));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,300)}`)}};
await q('object policy guard', `select left(prosrc,1800) src from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname='fn_phase_d_object_policy_guard'`);
await q('kernel_write_authority cols', `select column_name from information_schema.columns where table_schema='public' and table_name='kernel_write_authority' order by ordinal_position`);
