import { q } from './q.mjs';
const sql = `
do $p$
declare
  v_fx jsonb; v_drive jsonb; v_run bigint; v_step text; v_ovl text;
  v_res jsonb; v_out text := ''; v_owner text; v_tasks_before bigint; v_tasks_after bigint;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','probe-auth-005'));
  select b.live_role_id into v_ovl from public.phase_c_overlay_binding b order by b.overlay_id limit 1;
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','zz-probe-auth-005','execution_context','test','for_workflow','W04'));
  v_drive := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W04','scenario', v_fx, 'mode','happy','stop_after_steps',1));
  v_run := (v_drive->>'run_id')::bigint;

  -- an un-opened step of W04
  select s.step_id, s.accountable_role_id into v_step, v_owner
    from public.phase_b_workflow_step s
   where s.workflow_id = 'W04'
     and not exists (select 1 from public.phase_c_workflow_step_run r
                      where r.run_id = v_run and r.step_id = s.step_id)
   order by s.step_id limit 1;
  v_out := 'step=' || coalesce(v_step,'(none)') || ' canonical_owner=' || coalesce(v_owner,'(none)');

  select count(*) into v_tasks_before from public.phase_c_task;

  -- INJECTION: overlay presented as the accountable owner
  begin
    v_res := public.fn_kernel_open_step(jsonb_build_object(
      'run_id', v_run, 'step_id', v_step, 'owner_role_id', v_ovl,
      'opened_because','probe: overlay presented as accountable owner'));
    v_out := v_out || ' | INJECTED=ACCEPTED task=' || coalesce(v_res->>'task_id','?');
  exception when others then
    v_out := v_out || ' | INJECTED=REFUSED sqlstate=' || SQLSTATE || ' msg=' || left(SQLERRM,220);
  end;

  select count(*) into v_tasks_after from public.phase_c_task;
  v_out := v_out || ' | tasks ' || v_tasks_before || '->' || v_tasks_after;

  -- CONTROL: the canonical owner
  begin
    v_res := public.fn_kernel_open_step(jsonb_build_object(
      'run_id', v_run, 'step_id', v_step, 'owner_role_id', v_owner,
      'opened_because','probe control: the canonical owner'));
    v_out := v_out || ' | CONTROL=ACCEPTED task=' || coalesce(v_res->>'task_id','?');
  exception when others then
    v_out := v_out || ' | CONTROL=REFUSED sqlstate=' || SQLSTATE || ' msg=' || left(SQLERRM,200);
  end;

  raise exception 'PROBE %', v_out;
end $p$;`;
try { await q(sql); console.log('DID NOT RAISE'); }
catch(e){ console.log(String(e.message).slice(0,4000)); }
