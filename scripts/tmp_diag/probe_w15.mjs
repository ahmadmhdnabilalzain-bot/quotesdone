import { sql } from '../phase_c/lib/db.mjs';
const q = `do $p$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_run bigint; v_srid bigint; v_out text := ''; r record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','dbg-w15'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','dbg-w15','execution_context','test','for_workflow',null));
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W15','label','dbg-w15','execution_context','production',
    'reviewer_role_id','risk_and_governance_manager','reviewer_candidates',v_cands));
  v_run := (v->>'run_id')::bigint;
  select sr.step_run_id into v_srid from public.phase_c_workflow_step_run sr
   where sr.run_id=v_run and sr.step_id='W15-S05' limit 1;
  v_out := 'scenario_comparison=' || coalesce(v_fx->'parent_refs'->>'comparison_id','-')
        || ' ctx_comparison=' || coalesce((public.fn_phase_d_step_context(v_srid))->'context'->>'comparison_id','-')
        || ' ctx_customer=' || coalesce((public.fn_phase_d_step_context(v_srid))->'context'->>'caller_customer_id','-')
        || ' prov=' || left(coalesce((public.fn_phase_d_step_context(v_srid))->'provenance'->>'comparison_id','-'),160);
  for r in select qc.id, qc.customer_id, qc.inquiry_id from public.quote_comparisons qc order by qc.id loop
    v_out := v_out || E'\nQC ' || r.id || ' cust=' || coalesce(r.customer_id::text,'NULL') || ' inq=' || coalesce(r.inquiry_id::text,'-');
  end loop;
  for r in select el.effect_id, el.effect_object_id, el.result_reference, el.step_id
             from public.phase_d_effect_ledger el where el.run_id=v_run order by el.effect_id loop
    v_out := v_out || E'\nEFF ' || r.step_id || ' ' || r.effect_object_id || ' ' || coalesce(r.result_reference,'-');
  end loop;
  raise exception 'DBG<<%>>', v_out;
end $p$;`;
try { await sql(q); } catch (e) {
  const m = String(e.message); const a = m.indexOf('DBG<<');
  console.log(a>=0 ? m.slice(a+5, m.indexOf('>>', a)).replace(/\n/g,'\n') : m.slice(0,3000));
}
