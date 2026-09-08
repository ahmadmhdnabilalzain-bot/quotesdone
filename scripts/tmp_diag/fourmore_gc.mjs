import { sql } from '../lib/db.mjs';
console.log(JSON.stringify(await sql(`select gate_id, evidence_keys, refusal_code from public.phase_d_gate_contract where gate_id in ('GATE-011','GATE-014','GATE-015')`),null,1));
const r = await sql(`select pg_get_functiondef(p.oid) as d from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname='fn_phase_d_rule_check'`);
const d = r[0].d;
const i = d.indexOf("BR-015");
console.log('--- rule_check around BR-015 ---');
console.log(d.slice(Math.max(0,i-1500), i+2500));
