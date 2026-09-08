import { sql } from '../lib/db.mjs';
const p = (t, r) => { console.log('=== ' + t + ' (' + (r ? r.length : 0) + ') ==='); console.log(JSON.stringify(r, null, 1)); };

p('fixture_stage all (compact)', await sql(`select stage_no, stage_key, object_id, contributes_ref, contributes_kind, reference_relation, requires_stages, working_state from public.phase_d_fixture_stage order by stage_no`));
p('fixture_stage terms rows FULL', await sql(`select * from public.phase_d_fixture_stage where stage_key ilike '%terms%' or object_id ilike '%terms%' or object_id ilike '%accept%' order by stage_no`));
p('binding terms acceptances', await sql(`select * from public.phase_d_business_object_binding where object_id in ('supplier_terms_acceptance','customer_terms_acceptance')`));
p('write map terms acceptances', await sql(`select * from public.phase_d_object_write_map where object_id in ('supplier_terms_acceptance','customer_terms_acceptance')`));
p('step_effect W09', await sql(`select * from public.phase_d_step_effect where workflow_id='W09' order by step_id`));
p('step_effect W04', await sql(`select * from public.phase_d_step_effect where workflow_id='W04' order by step_id`));
p('phase_b_workflow W04 W09', await sql(`select * from public.phase_b_workflow where workflow_id in ('W04','W09')`));
