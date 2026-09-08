import { sql } from '../lib/db.mjs';
const J=x=>JSON.stringify(x);
console.log('org_role cols', J(await sql(`select column_name from information_schema.columns where table_name='org_role' and table_schema='public' order by ordinal_position`)));
console.log('cos dept', J(await sql("select role_id, primary_department_id from public.org_role where role_id='chief_of_staff'")));
console.log('dept match', J(await sql("select count(*) n from public.org_departments d join public.org_role r on d.dept_key = r.primary_department_id where r.role_id='chief_of_staff'")));
console.log('org_agents cols', J(await sql(`select column_name from information_schema.columns where table_name='org_agents' and table_schema='public' order by ordinal_position`)).slice(0,700));
const q=`do $emit$
declare v_fx jsonb; v jsonb; v_out text:=''; v_cands jsonb; v_sr bigint;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build','label','t3c'));
  select jsonb_agg(distinct s.independent_reviewer_role_id) into v_cands from public.phase_b_workflow_step s where coalesce(btrim(s.independent_reviewer_role_id),'')<>'';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','t3c','execution_context','test'));
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','W05','label','t3c','execution_context','production','reviewer_role_id','inquiry_quality_analyst','reviewer_candidates',v_cands,'business_object_id','inquiry:'||(v_fx->'parent_refs'->>'inquiry_id')));
  v_out := v_out || 'W05 command_id=' || coalesce((select command_id::text from public.phase_c_workflow_run where run_id=(v->>'run_id')::bigint),'null') || ' dup=' || coalesce(v->>'premature_arrival_run','?') || chr(10);
  v_out := v_out || 'link rows=' || coalesce((select count(*)::text from public.founder_command_workflow_link l join public.phase_c_workflow_run r on r.command_id = l.command_id where r.run_id=(v->>'run_id')::bigint),'0') || chr(10);
  select step_run_id into v_sr from public.phase_c_workflow_step_run where run_id=(v->>'run_id')::bigint and step_id='W05-S07' order by step_run_id desc limit 1;
  v_out := v_out || 'S07 fa_ref=' || coalesce(((public.fn_phase_d_step_context(v_sr))->'context'->>'founder_authority_ref'),'NULL') || chr(10);
  v_out := v_out || 'GATE-005 keys=' || coalesce((select evidence_keys::text from public.phase_d_gate_contract where gate_id='GATE-005'),'?') || chr(10);
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','W12','label','t3d','execution_context','production','reviewer_role_id','marketplace_content_privacy_reviewer','reviewer_candidates',v_cands));
  select step_run_id into v_sr from public.phase_c_workflow_step_run where run_id=(v->>'run_id')::bigint and step_id='W12-S06' order by step_run_id desc limit 1;
  v_out := v_out || 'W12 boid=' || coalesce((select business_object_id from public.phase_c_workflow_run where run_id=(v->>'run_id')::bigint),'?') || chr(10);
  v_out := v_out || 'W12-S06 dispatch=' || coalesce((select d.outcome||':'||coalesce(d.refusal_code,'')||' '||left(coalesce(d.reason,''),120) from public.phase_d_dispatch d where d.step_run_id=v_sr order by d.dispatch_id desc limit 1),'(none)') || chr(10);
  v_out := v_out || 'W12-S06 ctx supplier=' || coalesce(((public.fn_phase_d_step_context(v_sr))->'context'->>'supplier_id'),'NULL') || chr(10);
  raise exception 'T3<<%>>', left(v_out,1900);
end $emit$;`;
try{await sql(q);}catch(e){const m=String(e.message);const a=m.indexOf('T3<<');console.log(a<0?m.slice(0,900):m.slice(a+4,m.lastIndexOf('>>')).replace(/\n/g,'\n').replace(/\\"/g,'"'));}
