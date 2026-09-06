import { sql } from '../phase_b/lib/db.mjs';
console.log('--- phase_d_step_effect columns ---');
console.log(JSON.stringify(await sql(`select column_name,data_type from information_schema.columns where table_schema='public' and table_name='phase_d_step_effect' order by ordinal_position`)));
console.log('--- rows whose effect_object_id relates to terms acceptance ---');
console.log(JSON.stringify(await sql(`select * from public.phase_d_step_effect where effect_object_id like '%terms%' order by 1`),null,1));
console.log('--- W09 step effects ---');
console.log(JSON.stringify(await sql(`select workflow_id, step_id, effect_object_id from public.phase_d_step_effect where workflow_id='W09' order by step_id`),null,1));
console.log('--- W12 step effects ---');
console.log(JSON.stringify(await sql(`select workflow_id, step_id, effect_object_id from public.phase_d_step_effect where workflow_id='W12' order by step_id`),null,1));
console.log('--- LEAF stages (not required by any other stage) x workflows that produce them ---');
console.log(JSON.stringify(await sql(`
 select st.stage_no, st.stage_key, st.object_id,
        (select string_agg(distinct x.workflow_id, ',' order by x.workflow_id)
           from public.phase_d_step_effect x where x.effect_object_id = st.object_id) as produced_by_workflows
   from public.phase_d_fixture_stage st
  where not exists (select 1 from public.phase_d_fixture_stage t where st.stage_key = any(t.requires_stages))
  order by st.stage_no`),null,1));
