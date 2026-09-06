import { sql } from '../phase_b/lib/db.mjs';
const step = process.argv[2] || 'W09-S03', wf = step.slice(0,3);
const q = `do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text:=''; v_ref_key text; v_boid text; v_ctx jsonb; v_srid bigint;
begin
  perform set_config('app.phase_d_hold_step','${step}', true);
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_workflow_drive','label','cx2'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','cx2','execution_context','test'));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x where x.workflow_id='${wf}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>'' order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='${wf}') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>'' then (select primary_object from public.phase_b_workflow where workflow_id='${wf}')||':'||(v_fx->'parent_refs'->>v_ref_key) else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','${wf}','label','cx2','execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands,'hold_at_step_id','${step}')
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_srid := nullif(v->>'held_step_run_id','')::bigint;
  if v_srid is null then raise exception 'CX2<<no held step: %>>', coalesce(v->'stopped'->>'refused_with','-'); end if;
  v_ctx := public.fn_phase_d_step_context(v_srid);
  v_out := 'row_found=' || coalesce(v_ctx->>'row_found', v_ctx->'subject'->>'row_found','?')
        || ' row_id=' || coalesce(v_ctx->>'row_id', v_ctx->'subject'->>'row_id','?')
        || ' terms_version=' || coalesce(v_ctx->'keys'->'terms_version'->>'value', v_ctx->>'terms_version','?')
        || ' src=' || coalesce(left(v_ctx->'keys'->'terms_version'->>'source',90),'?')
        || ' ~~top=' || substr(v_ctx::text, 1, 60) || ' ||SUBJ|| ' || coalesce((select string_agg(k||'='||left(coalesce(v_ctx->k,'null'::jsonb)::text,120), ' ; ') from jsonb_object_keys(v_ctx) k where k <> 'context'),'-');
  raise exception 'CX2<<%>>', v_out;
end $emit$;`;
try { await sql(q); console.log('(no marker)'); }
catch (e) { const m = String(e.message); const a = m.indexOf('CX2<<'); console.log(a<0 ? 'ERR:'+m.slice(0,700).replace(/\s+/g,' ') : m.slice(a+5, m.indexOf('>>',a))); }
