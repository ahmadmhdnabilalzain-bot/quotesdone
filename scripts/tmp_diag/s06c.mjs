import { sql } from '../lib/db.mjs';
const q = `do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text := ''; v_run bigint; v_sr bigint;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_workflow_drive','label','s06c'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','s06c','execution_context','test','for_workflow','W09'));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='W09' and coalesce(btrim(x.independent_reviewer_role_id),'')<>'' order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','W09','label','s06c',
       'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands));
  v_run := (v->>'run_id')::bigint;
  select step_run_id into v_sr from public.phase_c_workflow_step_run where run_id=v_run and step_id='W09-S06' order by step_run_id desc limit 1;
  v_out := 'EFFECT_PAYLOAD='||left(coalesce(public.fn_phase_d_fixture_effect_payload(v_sr)::text,'(null)'),1500);
  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;
try { await sql(q); } catch (e) { const m=String(e.message); const i=m.indexOf('PROBE<<'); console.log(i>=0?m.slice(i+7,m.lastIndexOf('>>')).replace(/\n/g,'\n'):m.slice(0,2500)); }
