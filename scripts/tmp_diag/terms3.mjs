import { sql } from '../phase_b/lib/db.mjs';
const q=async(l,t)=>{try{console.log(`\n### ${l}`);console.log(JSON.stringify(await sql(t),null,1).slice(0,4000));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,300)}`)}};
await q('who produces terms acceptances', `select workflow_id, step_id, effect_object_id, expected_effect_type, effect_relation, effect_operation from public.phase_d_step_effect where effect_object_id ilike '%terms_acceptance%' order by 1,2`);
await q('W09 step effects', `select step_id, effect_object_id, expected_effect_type from public.phase_d_step_effect where workflow_id='W09' order by step_id`);
await q('W04 step effects', `select step_id, effect_object_id, expected_effect_type from public.phase_d_step_effect where workflow_id='W04' order by step_id`);
await q('leaf stages', `select stage_key from public.phase_d_fixture_stage s where not exists (select 1 from public.phase_d_fixture_stage t where s.stage_key = any(t.requires_stages)) order by 1`);
await q('catalogue PDF-3104/5', `select fixture_id, field_key, value, expected_result from public.phase_d_fixture_catalogue where fixture_id in ('PDF-3103','PDF-3104','PDF-3105')`);
