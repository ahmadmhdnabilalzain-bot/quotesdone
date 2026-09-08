import { sql } from '../lib/db.mjs';
const q = `
do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text := '';
        v_srid bigint; v_t0 timestamptz := clock_timestamp(); v_t1 timestamptz;
begin
  perform set_config('app.phase_d_hold_step','W06-S05', true);
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','m03-p1'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','m03-p1','execution_context','test','for_workflow','W06'));
  v_t1 := clock_timestamp();
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='W06' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W06','label','m03-p1','execution_context','production',
    'reviewer_role_id',v_rev,'reviewer_candidates',v_cands,'hold_at_step_id','W06-S05'));
  v_srid := nullif(v->>'held_step_run_id','')::bigint;
  v_out := 'scenario_ms=' || round(extract(epoch from (v_t1-v_t0))*1000)
        || ' drive_ms=' || round(extract(epoch from (clock_timestamp()-v_t1))*1000)
        || ' run=' || coalesce(v->>'run_id','-')
        || ' held=' || coalesce(v->>'held_step_id','-') || '/' || coalesce(v_srid::text,'-')
        || ' srstate=' || coalesce((select state from public.phase_c_workflow_step_run where step_run_id=v_srid),'-')
        || ' acct=' || coalesce((select accountable_role_id from public.phase_c_workflow_step_run where step_run_id=v_srid),'-')
        || ' declrev=' || coalesce((select independent_reviewer_role_id from public.phase_b_workflow_step where step_id='W06-S05'),'-')
        || ' runstate=' || coalesce((select state from public.phase_c_workflow_run where run_id=(v->>'run_id')::bigint),'-')
        || ' nsr=' || (select count(*) from public.phase_c_workflow_step_run where run_id=(v->>'run_id')::bigint)
        || ' stopped=' || coalesce(v->'stopped'->>'refused_with','-')
        || ' reqin=' || coalesce((select required_inputs from public.phase_b_workflow_step where step_id='W06-S05'),'-');
  raise exception 'P1<<%>>', v_out;
end $emit$;`;
try { await sql(q); console.log('no raise'); } catch(e){ console.log(String(e.message).slice(0,3000)); }
