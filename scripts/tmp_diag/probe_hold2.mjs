import { sql } from '../phase_b/lib/db.mjs';
const [wf, extra] = [process.argv[2] || 'W18', process.argv[3] || ''];
const q = `do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text:='';
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_workflow_drive','label','h2-${wf}'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','h2-${wf.toLowerCase()}','execution_context','test','for_workflow', case when '${wf}'='W12' then '${wf}' else null end));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x where x.workflow_id='${wf}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>'' order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','${wf}','label','h2-${wf.toLowerCase()}',
    'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands,'hold_at_first_open_step', true
    ${extra}));
  v_out := 'held='||coalesce(v->>'held_step_id','(none)')||' runstate='||coalesce((select state from public.phase_c_workflow_run where run_id=(v->>'run_id')::bigint),'?')
    ||' stepstates='||coalesce((select string_agg(step_id||':'||state,';' order by step_run_id) from public.phase_c_workflow_step_run where run_id=(v->>'run_id')::bigint),'-')
    ||' outcomes='||coalesce((select string_agg(step_id||'='||coalesce(nullif(refusal_code,''),outcome),';' order by dispatch_id) from public.phase_d_dispatch where run_id=(v->>'run_id')::bigint),'-');
  raise exception 'H2<<%>>', v_out;
end $emit$;`;
try { await sql(q); console.log('(no marker)'); }
catch (e) { const m = String(e.message); const a = m.indexOf('H2<<'); console.log(a<0 ? 'ERR:'+m.slice(0,500).replace(/\s+/g,' ') : m.slice(a+4, m.indexOf('>>',a))); }
