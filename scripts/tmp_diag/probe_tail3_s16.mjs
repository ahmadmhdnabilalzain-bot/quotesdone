import { sql } from '../phase_c/lib/db.mjs';
const J=x=>JSON.stringify(x);
// role -> dept mapping candidates
console.log('org_roles cols', J(await sql(`select column_name from information_schema.columns where table_name='org_roles' and table_schema='public'`)).slice(0,600));
console.log('chief_of_staff row', J(await sql(`select role_id, dept_key, department, title from public.org_roles where role_id='chief_of_staff' limit 1`)).slice(0,300));
console.log('org_departments has assurance?', J(await sql(`select dept_key from public.org_departments where dept_key='assurance' or dept_key ilike '%assur%' limit 3`)));
// W05 founder-command start + link
const q=`do $emit$
declare v_fx jsonb; v jsonb; v_out text:=''; v_cands jsonb; v_sr bigint;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build','label','t3'));
  select jsonb_agg(distinct s.independent_reviewer_role_id) into v_cands from public.phase_b_workflow_step s where coalesce(btrim(s.independent_reviewer_role_id),'')<>'';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','t3','execution_context','test'));
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','W05','label','t3','execution_context','production','reviewer_role_id','inquiry_quality_analyst','reviewer_candidates',v_cands,'business_object_id','inquiry:'||(v_fx->'parent_refs'->>'inquiry_id')));
  v_out := v_out || 'W05 run source_kind=' || coalesce((select source_kind from public.phase_c_workflow_run where run_id=(v->>'run_id')::bigint),'?') || ' command_id=' || coalesce((select command_id::text from public.phase_c_workflow_run where run_id=(v->>'run_id')::bigint),'null') || chr(10);
  v_out := v_out || 'link rows=' || coalesce((select count(*)::text from public.founder_command_workflow_link where run_id=(v->>'run_id')::bigint),'0') || chr(10);
  select step_run_id into v_sr from public.phase_c_workflow_step_run where run_id=(v->>'run_id')::bigint and step_id='W05-S07' order by step_run_id desc limit 1;
  v_out := v_out || 'W05-S07 ctx fa_ref=' || coalesce(((public.fn_phase_d_step_context(v_sr))->'context'->>'founder_authority_ref'),'NULL') || ' unresolved=' || coalesce(((public.fn_phase_d_step_context(v_sr))->'unresolved')::text,'?') || chr(10);
  v_out := v_out || 'GATE-005 contract keys=' || coalesce((select evidence_keys::text from public.phase_d_gate_contract where gate_id='GATE-005'),'?') || chr(10);
  -- W12-S06 dispatch business_key/owner: read from the dispatch inputs_provenance and the ctx
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','W12','label','t3b','execution_context','production','reviewer_role_id','marketplace_content_privacy_reviewer','reviewer_candidates',v_cands));
  select step_run_id into v_sr from public.phase_c_workflow_step_run where run_id=(v->>'run_id')::bigint and step_id='W12-S06' order by step_run_id desc limit 1;
  v_out := v_out || 'W12-S06 ctx supplier_id=' || coalesce(((public.fn_phase_d_step_context(v_sr))->'context'->>'supplier_id'),'NULL') || ' bo=' || left(coalesce(((public.fn_phase_d_step_context(v_sr))->'business_object')::text,'{}'),260) || chr(10);
  raise exception 'T3<<%>>', left(v_out,1900);
end $emit$;`;
try{await sql(q);}catch(e){const m=String(e.message);const a=m.indexOf('T3<<');console.log(a<0?m.slice(0,900):m.slice(a+4,m.lastIndexOf('>>')).replace(/\n/g,'\n').replace(/\\"/g,'"'));}
