import { sql } from '../lib/db.mjs';
const cols = await sql(`
 select table_name, ordinal_position, column_name, data_type, is_nullable, column_default
 from information_schema.columns
 where table_schema='public' and table_name in ('phase_d_fixture_stage','phase_d_context_key_object')
 order by table_name, ordinal_position`);
console.log('=== COLUMNS ===');
for (const c of cols) console.log(`${c.table_name}.${c.column_name} | ${c.data_type} | null=${c.is_nullable} | def=${c.column_default??''}`);
console.log('\n=== phase_d_context_key_object (ALL ROWS) ===');
const cko = await sql(`select * from public.phase_d_context_key_object order by 1,2`);
console.log(JSON.stringify(cko, null, 1));
console.log('\n=== phase_d_fixture_stage (ALL ROWS, key cols) ===');
const st = await sql(`select stage_no, stage_key, object_id, contributes_ref, requires_stages, reference_relation, working_state, working_state_evidence from public.phase_d_fixture_stage order by stage_no`);
console.log(JSON.stringify(st, null, 1));
