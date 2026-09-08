import { sql } from '../lib/db.mjs';
const r = await sql(`select rule_id, required_context, refusal_code from public.phase_d_rule_enforcement where rule_id in ('BR-018','BR-032','BR-025','BR-012','BR-013','BR-014','BR-019','BR-020') order by 1`);
for (const x of r) console.log(`${x.rule_id}\t[${(x.required_context||[]).join(', ')}]\t${x.refusal_code}`);
const k = await sql(`select context_key, object_id from public.phase_d_context_key_object order by 1`);
console.log('\nregister:'); for (const x of k) console.log(`  ${x.context_key} -> ${x.object_id}`);
