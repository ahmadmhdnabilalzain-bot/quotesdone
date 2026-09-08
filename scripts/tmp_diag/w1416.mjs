import { sql } from '../lib/db.mjs';
const q=async(l,t)=>{console.log(`\n### ${l}`);console.log(JSON.stringify(await sql(t),null,1).slice(0,3000));};
await q('W14/W16 step effects', `select workflow_id, step_id, effect_object_id, effect_relation, effect_operation from public.phase_d_step_effect where workflow_id in ('W14','W16') order by 1,2`);
await q('BR-018/BR-032 enforcement', `select rule_id, required_context, refusal_code from public.phase_d_rule_enforcement where rule_id in ('BR-018','BR-032')`);
await q('bindings', `select object_id, canonical_relation, relation_kind, ownership_scope, governing_workflow_id from public.phase_d_business_object_binding where object_id in ('quotation_revision','provider_event','quotation','payment_transaction')`);
await q('leafness', `select stage_key, object_id from public.phase_d_fixture_stage s where s.object_id in ('quotation_revision','provider_event') `);
