import { sql } from '../phase_b/lib/db.mjs';
import fs from 'node:fs';
const r = await sql(`select p.oid::regprocedure::text sig, pg_get_functiondef(p.oid) def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('fn_phase_d_object_write','fn_phase_d_gate_eval','fn_phase_c_gate_eval') order by 1`);
let out=''; for(const x of r) out+='\n\n=========== '+x.sig+'\n'+x.def;
fs.writeFileSync('scripts/tmp_diag/recon_objwrite.sql', out);
console.log(r.map(x=>x.sig+' '+x.def.length).join('\n'));
const g = await sql(`select gate_id, gate_type, gate_name, predicate_sql from public.phase_b_gate where gate_id in ('GATE-011','GATE-013','GATE-017','GATE-020')`).catch(async()=>{
  const cols = await sql(`select table_name from information_schema.columns where column_name='gate_id' and table_schema='public' group by 1`);
  return cols;
});
console.log(JSON.stringify(g,null,1).slice(0,3000));
