import { sql } from '../lib/db.mjs';
console.log('--- NON-LEAF stages that a workflow produces (withhold CANNOT skip these) ---');
console.log(JSON.stringify(await sql(`
 select st.stage_no, st.stage_key, st.object_id,
        (select string_agg(distinct x.workflow_id,',' order by x.workflow_id) from public.phase_d_step_effect x where x.effect_object_id=st.object_id) wf,
        (select string_agg(t.stage_key,',' order by t.stage_key) from public.phase_d_fixture_stage t where st.stage_key = any(t.requires_stages)) required_by
   from public.phase_d_fixture_stage st
  where exists (select 1 from public.phase_d_fixture_stage t where st.stage_key = any(t.requires_stages))
    and exists (select 1 from public.phase_d_step_effect x where x.effect_object_id=st.object_id)
  order by st.stage_no`),null,1));
console.log('--- grants on fn_phase_d_fixture_scenario ---');
console.log(JSON.stringify(await sql(`select grantee, privilege_type from information_schema.routine_privileges where routine_schema='public' and routine_name='fn_phase_d_fixture_scenario'`)));
console.log('--- any stage row with stage_key=notification? ---');
console.log(JSON.stringify(await sql(`select count(*) n from public.phase_d_fixture_stage where stage_key='notification'`)));
console.log('--- fixture_stage row count ---');
console.log(JSON.stringify(await sql(`select count(*) n from public.phase_d_fixture_stage`)));
