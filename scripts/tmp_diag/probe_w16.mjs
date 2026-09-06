import { sql } from '../phase_c/lib/db.mjs';
const q = `do $p$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_run bigint; v_ref_key text; v_boid text;
        v_srid bigint; v_out text := ''; r record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','dbg-w16r'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','dbg-w16r','execution_context','test','for_workflow',null));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='W16' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='W16') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>''
    then (select primary_object from public.phase_b_workflow where workflow_id='W16')||':'||(v_fx->'parent_refs'->>v_ref_key)
    else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W16','label','dbg-w16r','execution_context','production',
    'reviewer_role_id',v_rev,'reviewer_candidates',v_cands)
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_run := (v->>'run_id')::bigint;
  select sr.step_run_id into v_srid from public.phase_c_workflow_step_run sr
   where sr.run_id=v_run and sr.step_id='W16-S05' limit 1;
  v_out := 'fx_txn=' || coalesce(v_fx->'parent_refs'->>'transaction_id','-');
  for r in select e.effect_id, e.result_reference, e.effect_relation from public.phase_d_effect_ledger e
            where e.step_run_id = v_srid loop
    v_out := v_out || ' | eff=' || r.effect_id || ' ref=' || coalesce(r.result_reference,'-') || ' rel=' || coalesce(r.effect_relation,'-');
  end loop;
  for r in select ri.transaction_id, ri.invoice_no from public.reveal_invoices ri loop
    v_out := v_out || E'\nRI txn=' || r.transaction_id || ' no=' || coalesce(r.invoice_no,'-');
  end loop;
  raise exception 'DBG<<%>>', v_out;
end $p$;`;
try { await sql(q); } catch (e) {
  const m = String(e.message); const a = m.indexOf('DBG<<');
  console.log(a>=0 ? m.slice(a+5, m.indexOf('>>', a)).replace(/\n/g,'\n') : m.slice(0,3000));
}
