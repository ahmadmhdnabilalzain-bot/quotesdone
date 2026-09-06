import { sql } from '../phase_b/lib/db.mjs';
const p = (t, r) => { console.log('=== ' + t + ' (' + (r ? r.length : 0) + ') ==='); console.log(JSON.stringify(r, null, 1)); };

p('handler_binding W09 rule/gate ids', await sql(`select step_id, handler_class, handler_routine, rule_ids, gate_ids from public.phase_d_handler_binding where step_id like 'W09-%' order by step_id`));
p('handler_binding W04 rule/gate ids', await sql(`select step_id, handler_class, handler_routine, rule_ids, gate_ids from public.phase_d_handler_binding where step_id like 'W04-%' order by step_id`));

p('rule_applies BR-025 on every W09 step', await sql(`select s.step_id, a.applies, a.why from public.phase_b_workflow_step s cross join lateral public.fn_phase_d_rule_applies('BR-025', s.step_id) a where s.workflow_id in ('W04','W09') order by s.step_id`));

p('SIMULATED skip set for_workflow=W09', await sql(`
select st.stage_no, st.stage_key, st.object_id,
       not exists (select 1 from public.phase_d_fixture_stage t where st.stage_key = any(t.requires_stages)) as is_leaf,
       exists (select 1 from public.phase_d_step_effect x where x.workflow_id='W09' and x.effect_object_id = st.object_id) as produced_by_w09
  from public.phase_d_fixture_stage st
 where exists (select 1 from public.phase_d_step_effect x where x.workflow_id='W09' and x.effect_object_id = st.object_id)
 order by st.stage_no`));

p('SIMULATED skip set for_workflow=W04', await sql(`
select st.stage_no, st.stage_key, st.object_id,
       not exists (select 1 from public.phase_d_fixture_stage t where st.stage_key = any(t.requires_stages)) as is_leaf,
       exists (select 1 from public.phase_d_step_effect x where x.workflow_id='W04' and x.effect_object_id = st.object_id) as produced_by_w04
  from public.phase_d_fixture_stage st
 where exists (select 1 from public.phase_d_step_effect x where x.workflow_id='W04' and x.effect_object_id = st.object_id)
 order by st.stage_no`));

p('catalogue rows for terms keys', await sql(`select * from public.phase_d_fixture_catalogue where field_key in ('terms_version','terms_hash') order by field_key`));
p('legal_documents versions', await sql(`select slug, version, encode(sha256(convert_to(coalesce(body_html,''),'UTF8')),'hex') as body_sha from public.legal_documents order by slug, version`));
