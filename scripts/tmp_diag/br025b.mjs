import { sql } from '../lib/db.mjs';
const q = async (l,t)=>{try{console.log(`\n### ${l}`);console.log(JSON.stringify(await sql(t),null,1).slice(0,7000));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,400)}`)}};
await q('terms stages', `select stage_no, stage_key, object_id, contributes_ref, requires_stages from public.phase_d_fixture_stage where stage_key ilike '%terms%' or object_id ilike '%terms%'`);
await q('who requires terms stages (leaf?)', `select stage_key, requires_stages from public.phase_d_fixture_stage where 'customer_terms_acceptance' = any(requires_stages) or 'supplier_terms_acceptance' = any(requires_stages)`);
await q('step_effect W04 W09', `select workflow_id, step_id, effect_object_id, effect_kind from public.phase_d_step_effect where workflow_id in ('W04','W09') order by workflow_id, step_id`);
await q('context_key_object', `select * from public.phase_d_context_key_object order by 1,2`);
await q('required_context distinct across rules', `select unnest(required_context) k, count(*) from public.phase_d_rule_enforcement group by 1 order by 1`);
