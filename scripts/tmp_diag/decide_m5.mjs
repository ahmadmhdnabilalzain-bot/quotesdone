import { sql } from '../lib/db.mjs';
const q = async (label, s) => { try { const r = await sql(s); console.log('=== ' + label); console.log(JSON.stringify(r).slice(0, 8000)); } catch(e){ console.log('=== '+label+' ERR '+String(e).slice(0,600)); } };

await q('gate_contract cols', `select column_name from information_schema.columns where table_schema='public' and table_name='phase_d_gate_contract' order by ordinal_position`);
await q('gate rows 13/17/20', `select * from public.phase_d_gate_contract where gate_id in ('GATE-013','GATE-017','GATE-020','GATE-010')`);
