import { sql } from '../lib/db.mjs';
// Full (rule, step) applicability matrix, current live function.
const r = await sql(`
  select r.rule_id, s.step_id, s.workflow_id, a.applies
    from public.phase_b_business_rule r
    cross join public.phase_b_workflow_step s
    cross join lateral public.fn_phase_d_rule_applies(r.rule_id, s.step_id) a
   where a.applies
   order by 1,2`);
console.log('applies_true_pairs=' + r.length);
const byRule = {};
for (const x of r) (byRule[x.rule_id] ||= []).push(x.step_id);
const out = Object.entries(byRule).map(([k,v])=>`${k}\t${v.length}\t${[...new Set(v.map(s=>s.split('-')[0]))].join(',')}`).join('\n');
console.log(out);
require('node:fs').writeFileSync('scripts/tmp_diag/applies_before.json', JSON.stringify(r));
