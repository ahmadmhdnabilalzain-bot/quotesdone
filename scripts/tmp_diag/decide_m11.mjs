import { sql } from '../lib/db.mjs';
const q = async (l,s)=>{try{const r=await sql(s);console.log('=== '+l);console.log(JSON.stringify(r).slice(0,7000));}catch(e){console.log('=== '+l+' ERR '+String(e).slice(0,400));}};
await q('phase_b rule tables', `select table_name from information_schema.tables where table_schema='public' and table_name like 'phase_b%rule%'`);
await q('rule enforcement cols', `select column_name from information_schema.columns where table_schema='public' and table_name='phase_d_rule_enforcement' order by ordinal_position`);
await q('enf rows for my rules', `select rule_id, enforcement_kind, enforcement_point, required_context, status from public.phase_d_rule_enforcement where rule_id in ('BR-011','BR-012','BR-018','BR-019','BR-026','BR-027','BR-028','BR-031','BR-035','BR-037','BR-048') order by 1`);
await q('rule scope/anchor', `select * from public.phase_b_business_rule where rule_id in ('BR-026','BR-027','BR-028','BR-037','BR-011','BR-031','BR-018','BR-019') order by rule_id`);
