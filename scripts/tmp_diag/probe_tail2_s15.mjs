import { writeFileSync, appendFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';
const out='scripts/tmp_diag/probe_tail2.txt'; writeFileSync(out,'');
const cases=[['W12','W12-S06'],['W05','W05-S07'],['W16','W16-S05'],['W01','W01-S07'],['W09','W09-S03']];
for (const [id,step] of cases) {
  const q=`do $emit$
declare v_fx jsonb; v jsonb; v_rev text; v_cands jsonb; v_out text:=''; v_ref_key text; v_boid text; v_sr bigint; v_cx jsonb;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build','label','t2-${id}'));
  select jsonb_agg(distinct s.independent_reviewer_role_id) into v_cands from public.phase_b_workflow_step s where coalesce(btrim(s.independent_reviewer_role_id),'')<>'';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','t2-${id}','execution_context','test','for_workflow', case when '${id}'='W12' then '${id}' else null end));
  select coalesce((select s.independent_reviewer_role_id from public.phase_b_workflow_step s where s.workflow_id='${id}' and coalesce(btrim(s.independent_reviewer_role_id),'')<>'' order by s.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='${id}') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>'' then (select primary_object from public.phase_b_workflow where workflow_id='${id}')||':'||(v_fx->'parent_refs'->>v_ref_key) else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','${id}','label','t2-${id}','execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands) || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  select step_run_id into v_sr from public.phase_c_workflow_step_run where run_id=(v->>'run_id')::bigint and step_id='${step}' order by step_run_id desc limit 1;
  v_cx := public.fn_phase_d_step_context(v_sr);
  v_out := v_out || 'run_boid=' || coalesce((select business_object_id from public.phase_c_workflow_run where run_id=(v->>'run_id')::bigint),'?') || chr(10);
  v_out := v_out || 'bo=' || left(coalesce((v_cx->'business_object')::text,'{}'),300) || chr(10);
  v_out := v_out || 'ctx=' || left(coalesce((v_cx->'context')::text,'{}'),700) || chr(10);
  v_out := v_out || 'dispatch=' || coalesce((select d.outcome||':'||coalesce(d.refusal_code,'')||' '||left(coalesce(d.reason,''),160) from public.phase_d_dispatch d where d.step_run_id=v_sr order by d.dispatch_id desc limit 1),'(none)') || chr(10);
  raise exception 'T2<<%>>', left(v_out,1900);
end $emit$;`;
  let g; try{await sql(q);g='no raise';}catch(e){const m=String(e.message);const a=m.indexOf('T2<<');g=a<0?'ERR '+m.slice(0,400):m.slice(a+4,m.lastIndexOf('>>')).replace(/\n/g,'\n').replace(/\\"/g,'"');}
  appendFileSync(out,`=== ${id} ${step}\n${g}\n\n`); process.stdout.write(id+' done\n');
}
