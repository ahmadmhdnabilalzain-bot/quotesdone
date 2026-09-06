import { sql } from '../phase_b/lib/db.mjs';
const r = await sql(`
  select p.oid::text as oid,
         pg_get_function_identity_arguments(p.oid) as args,
         pg_get_functiondef(p.oid) as def,
         length(pg_get_functiondef(p.oid)) as len
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='fn_phase_d_fixture_scenario'
  order by 1
`);
console.log(JSON.stringify(r.map(x=>({oid:x.oid,args:x.args,len:x.len})), null, 1));
import fs from 'fs';
r.forEach((x,i)=>fs.writeFileSync(`scripts/tmp_diag/rc_fixture_def_${i}.sql`, x.def));
