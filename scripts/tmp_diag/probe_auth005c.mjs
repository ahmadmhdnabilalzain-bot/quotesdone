import { q } from './q.mjs';
const sql = `
do $p$
declare
  v_fx jsonb; v_drive jsonb; v_run bigint; v_step text := 'W04-S04'; v_ovl text;
  v_res jsonb; v_out text := ''; v_owner text; v_tb bigint; v_ta bigint;
  v_trb bigint; v_tra bigint; v_srb bigint; v_sra bigint;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','probe-auth-005'));
  select b.live_role_id into v_ovl from public.phase_c_overlay_binding b order by b.overlay_id limit 1;
  select s.accountable_role_id into v_owner from public.phase_b_workflow_step s where s.step_id = v_step;
  perform set_config('app.phase_d_hold_step', v_step, true);
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','zz-probe-auth-005','execution_context','test','for_workflow','W04'));
  v_drive := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W04','scenario', v_fx, 'mode','happy'));
  v_run := (v_drive->>'run_id')::bigint;
  v_out := 'run=' || v_run || ' step=' || v_step || ' canonical=' || coalesce(v_owner,'(none)')
        || ' overlay=' || coalesce(v_ovl,'(none)')
        || ' held_step=' || coalesce(v_drive->>'held_step_id','(none)');

  select count(*) into v_tb from public.phase_c_task;
  select count(*) into v_trb from public.phase_c_trace;
  select count(*) into v_srb from public.phase_c_workflow_step_run;

  begin
    v_res := public.fn_kernel_open_step(jsonb_build_object(
      'run_id', v_run, 'step_id', v_step, 'owner_role_id', v_ovl,
      'opened_because','probe: overlay presented as accountable owner'));
    v_out := v_out || ' || INJECTED=ACCEPTED task=' || coalesce(v_res->>'task_id','?');
  exception when others then
    v_out := v_out || ' || INJECTED=REFUSED ' || SQLSTATE || ' :: ' || left(SQLERRM,200);
  end;

  select count(*) into v_ta from public.phase_c_task;
  select count(*) into v_tra from public.phase_c_trace;
  select count(*) into v_sra from public.phase_c_workflow_step_run;
  v_out := v_out || ' || after-injection tasks ' || v_tb || '->' || v_ta
        || ' traces ' || v_trb || '->' || v_tra || ' stepruns ' || v_srb || '->' || v_sra;

  begin
    v_res := public.fn_kernel_open_step(jsonb_build_object(
      'run_id', v_run, 'step_id', v_step, 'owner_role_id', v_owner,
      'opened_because','probe control: the canonical owner'));
    v_out := v_out || ' || CONTROL=ACCEPTED task=' || coalesce(v_res->>'task_id','?');
  exception when others then
    v_out := v_out || ' || CONTROL=REFUSED ' || SQLSTATE || ' :: ' || left(SQLERRM,200);
  end;

  raise exception 'PROBE %', v_out;
end $p$;`;
try { await q(sql); console.log('DID NOT RAISE'); }
catch(e){ console.log(String(e.message).slice(0,4000)); }
