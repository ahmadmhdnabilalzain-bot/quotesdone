import { sql } from '../phase_b/lib/db.mjs';
const q=async(l,s)=>{try{console.log('\n=== '+l);console.log(JSON.stringify(await sql(s),null,1));}catch(e){console.log('\n=== '+l+' ERR '+e.message);}};
await q('GATE-011/013/017/020 in phase_b_gate', `select gate_id, gate_type, gate_name, left(coalesce(pass_condition,''),300) as pass_condition from public.phase_b_gate where gate_id in ('GATE-011','GATE-013','GATE-017','GATE-020')`);
await q('phase_b_gate cols', `select column_name from information_schema.columns where table_schema='public' and table_name='phase_b_gate' order by ordinal_position`);
await q('phase_d_gate_contract for GATE-011', `select * from public.phase_d_gate_contract where gate_id='GATE-011'`);
