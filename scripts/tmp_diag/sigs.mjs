import { sql } from '../phase_b/lib/db.mjs';
const r = await sql(`select p.proname, pg_get_function_identity_arguments(p.oid) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('fn_phase_d_fixture_effect_payload','fn_phase_d_step_inputs','fn_phase_d_step_context','fn_phase_d_fixture_input','fn_phase_d_rule_check','fn_phase_d_fixture_value','fn_phase_d_object_read','fn_phase_d_handler_execute') order by 1`);
for (const x of r) console.log(`${x.proname}(${x.args})`);
