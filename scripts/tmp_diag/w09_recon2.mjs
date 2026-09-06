import { sql } from '../phase_b/lib/db.mjs';
const p = (t, r) => { console.log('=== ' + t + ' (' + (r ? r.length : 0) + ') ==='); console.log(JSON.stringify(r, null, 1)); };

p('cols phase_b_business_rule', await sql(`select column_name, data_type from information_schema.columns where table_schema='public' and table_name='phase_b_business_rule' order by ordinal_position`));
p('BR-025 row', await sql(`select * from public.phase_b_business_rule where rule_id='BR-025' or rule_key='BR-025'`).catch(async e => await sql(`select * from public.phase_b_business_rule where (to_jsonb(t)::text) like '%BR-025%'`)));
