import { sql } from '../phase_b/lib/db.mjs';
const p = (t, r) => { console.log('=== ' + t + ' (' + (r ? r.length : 0) + ') ==='); console.log(JSON.stringify(r, null, 1)); };

p('BR-025', await sql(`select * from public.phase_b_business_rule where rule_id='BR-025'`));
p('rules scoped W09', await sql(`select rule_id, rule_name, workflow_scope, rule_type, rule_text from public.phase_b_business_rule where workflow_scope like '%W09%' order by rule_id`));
p('cols phase_b_workflow_step', await sql(`select column_name, data_type from information_schema.columns where table_schema='public' and table_name='phase_b_workflow_step' order by ordinal_position`));
p('cols phase_d_rule_enforcement', await sql(`select column_name, data_type from information_schema.columns where table_schema='public' and table_name='phase_d_rule_enforcement' order by ordinal_position`));
p('cols phase_d_fixture_stage', await sql(`select column_name, data_type from information_schema.columns where table_schema='public' and table_name='phase_d_fixture_stage' order by ordinal_position`));
p('cols phase_d_business_object_binding', await sql(`select column_name, data_type from information_schema.columns where table_schema='public' and table_name='phase_d_business_object_binding' order by ordinal_position`));
p('cols phase_d_object_write_map', await sql(`select column_name, data_type from information_schema.columns where table_schema='public' and table_name='phase_d_object_write_map' order by ordinal_position`));
p('cols phase_d_context_key_object', await sql(`select column_name, data_type from information_schema.columns where table_schema='public' and table_name='phase_d_context_key_object' order by ordinal_position`));
