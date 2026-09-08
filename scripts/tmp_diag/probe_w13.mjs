import { sql } from '../lib/db.mjs';
const q = `do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text:=''; v_n0 bigint; v_ref_key text; v_boid text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_workflow_drive','label','w13probe'));
  select count(*) into v_n0 from public.notifications;
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','w13probe','execution_context','test'));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x where x.workflow_id='W13' and coalesce(btrim(x.independent_reviewer_role_id),'')<>'' order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='W13') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>'' then (select primary_object from public.phase_b_workflow where workflow_id='W13')||':'||(v_fx->'parent_refs'->>v_ref_key) else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','W13','label','w13probe','execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands)
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_out := 'ledger=' || coalesce((select string_agg(step_id||'|'||effect_type||'|'||coalesce(effect_object_id,'-')||'|'||coalesce(effect_relation,'-')||'|'||coalesce(provider_mode,'-')||'|'||coalesce(left(result_reference,70),'-'), ' ;; ' order by effect_id)
      from public.phase_d_effect_ledger where run_id=(v->>'run_id')::bigint),'(none)')
    || ' ~~notif_delta=' || ((select count(*) from public.notifications) - v_n0)::text;
  raise exception 'W13<<%>>', v_out;
end $emit$;`;
try { await sql(q); console.log('(no marker)'); }
catch (e) { const m = String(e.message); const a = m.indexOf('W13<<'); console.log(a<0 ? 'ERR:'+m.slice(0,700).replace(/\s+/g,' ') : m.slice(a+5, m.indexOf('>>',a))); }
