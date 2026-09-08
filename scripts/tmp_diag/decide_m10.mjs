import { sql } from '../lib/db.mjs';
const rows = await sql(`select r.rule_id, r.rule_name, coalesce(e.status,'(none)') st, e.refusal_code
 from public.phase_b_business_rule r left join public.phase_d_rule_enforcement e on e.rule_id=r.rule_id order by r.rule_id`);
for (const r of rows) console.log([r.rule_id, r.rule_name, r.st, r.refusal_code].join(' | '));
