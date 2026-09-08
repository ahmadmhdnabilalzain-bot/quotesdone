import { sql } from '../lib/db.mjs';
const [wf, step] = [process.argv[2], process.argv[3]];
const q = `do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text:=''; v_ref_key text; v_boid text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_workflow_drive','label','ef-${wf}'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','ef-${wf.toLowerCase()}','execution_context','test','for_workflow', case when '${wf}'='W12' then '${wf}' else null end));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x where x.workflow_id='${wf}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>'' order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='${wf}') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>'' then (select primary_object from public.phase_b_workflow where workflow_id='${wf}')||':'||(v_fx->'parent_refs'->>v_ref_key) else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','${wf}','label','ef-${wf.toLowerCase()}','execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands)
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_out := coalesce((select string_agg('['||d.step_id||'] '||coalesce(nullif(d.refusal_code,''),d.outcome)||' :: '||left(coalesce(d.reason,'-'),320), ' ~~ ' order by d.dispatch_id)
      from public.phase_d_dispatch d where d.run_id=(v->>'run_id')::bigint and d.step_id='${step}'),'(no dispatch)');
  raise exception 'EF<<%>>', v_out;
end $emit$;`;
try { await sql(q); console.log('(no marker)'); }
catch (e) { const m = String(e.message); const a = m.indexOf('EF<<'); console.log(a<0 ? 'ERR:'+m.slice(0,700).replace(/\s+/g,' ') : m.slice(a+4, m.indexOf('>>',a))); }
