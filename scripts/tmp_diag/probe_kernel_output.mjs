import { sql } from '../lib/db.mjs';
const q = `do $p$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_run bigint; v_ref_key text; v_boid text;
        v_srid bigint; v_out text := '';
begin
  perform set_config('app.phase_d_hold_step','W03-S02', true);
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','dbg-ko'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','dbg-ko','execution_context','test','for_workflow','W03'));
  v_rev := 'risk_and_governance_manager';
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W03','label','dbg-ko','execution_context','production',
    'reviewer_role_id',v_rev,'reviewer_candidates',v_cands,'hold_at_step_id','W03-S02'));
  v_srid := nullif(v->>'held_step_run_id','')::bigint;
  v_out := 'held=' || coalesce(v_srid::text,'NULL');
  perform set_config('app.phase_d_hold_step','', true);
  if v_srid is not null then
    -- (a) malformed output through the kernel door
    begin
      perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_srid,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run where step_run_id=v_srid),
        'outcome','pass', 'idempotency_key','dbg-ko-malformed',
        'inputs', jsonb_build_object('a',1), 'output', '{}'::jsonb,
        'evidence_refs', jsonb_build_array(jsonb_build_object('m','x'))));
      v_out := v_out || ' | kernel_empty_output=ACCEPTED';
    exception when others then v_out := v_out || ' | kernel_empty_output=' || left(sqlerrm,180); end;
    -- (b) wrong actor through the real handler
    begin
      perform public.fn_phase_d_handler_execute(jsonb_build_object(
        'step_run_id', v_srid, 'actor_role_id','zz_not_a_canonical_role',
        'idempotency_key','dbg-ko-actor', 'inputs', jsonb_build_object('a',1),
        'execution_context','production'));
      v_out := v_out || ' | wrong_actor=ACCEPTED';
    exception when others then v_out := v_out || ' | wrong_actor=' || left(sqlerrm,180); end;
  end if;
  raise exception 'DBG<<%>>', v_out;
end $p$;`;
try { await sql(q); } catch (e) {
  const m = String(e.message); const a = m.indexOf('DBG<<');
  console.log(a>=0 ? m.slice(a+5, m.indexOf('>>', a)) : m.slice(0,2500));
}
