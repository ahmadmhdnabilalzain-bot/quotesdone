import { sql } from '../lib/db.mjs';
const q = async (l,t)=>{try{console.log(`\n### ${l}`);console.log(JSON.stringify(await sql(t),null,1).slice(0,6000));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,400)}`)}};
await q('BR-025 rule', `select * from public.phase_b_business_rule where rule_id='BR-025'`);
await q('BR-025 enforcement', `select * from public.phase_d_rule_enforcement where rule_id='BR-025'`);
await q('stages with contributes_ref', `select stage_no, stage_key, object_id, contributes_ref, requires_stages, reference_relation from public.phase_d_fixture_stage order by stage_no`);
