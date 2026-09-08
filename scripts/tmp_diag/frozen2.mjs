import { sql } from '../lib/db.mjs';
const q=async(l,t)=>{try{console.log(`\n### ${l}`);const r=await sql(t);console.log(JSON.stringify(r,null,1).slice(0,7000));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,300)}`)}};
await q('phase_c tables', `select table_name from information_schema.tables where table_schema='public' and table_name like 'phase_c_%freeze%'`);
await q('frozen subjects', `select * from public.phase_c_frozen_subject order by 1 limit 40`);
