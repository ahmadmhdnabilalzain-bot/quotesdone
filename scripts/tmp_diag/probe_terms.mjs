import { sql } from '../lib/db.mjs';
const q = `do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text:=''; v_ref_key text; v_boid text; v_ctx jsonb; sr record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_workflow_drive','label','tm-W09'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','tm-w09','execution_context','test'));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x where x.workflow_id='W09' and coalesce(btrim(x.independent_reviewer_role_id),'')<>'' order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='W09') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>'' then (select primary_object from public.phase_b_workflow where workflow_id='W09')||':'||(v_fx->'parent_refs'->>v_ref_key) else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','W09','label','tm-w09','execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands) || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_out := 'primary_object=' || coalesce((select primary_object from public.phase_b_workflow where workflow_id='W09'),'-') || ' boid=' || coalesce(v_boid,'-') || ' ~~ ';
  v_out := v_out || 'acceptance_records=' || coalesce((select string_agg(o.object_id||' owner='||coalesce(o.owner_ref,'-')||' key='||coalesce(o.business_key,'-')||' v='||coalesce(o.payload->>'terms_version','-'), ' ; ' order by o.record_id)
     from public.phase_d_object_record o where o.superseded_by is null and o.payload ? 'terms_version'),'(none)');
  raise exception 'TM<<%>>', v_out;
end $emit$;`;
try { await sql(q); console.log('(no marker)'); }
catch (e) { const m = String(e.message); const a = m.indexOf('TM<<'); console.log(a<0 ? 'ERR:'+m.slice(0,700).replace(/\s+/g,' ') : m.slice(a+4, m.indexOf('>>',a))); }
