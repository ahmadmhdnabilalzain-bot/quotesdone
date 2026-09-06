import { q } from './q.mjs';
const sql = `
do $p$
declare
  v_fx jsonb; v_drive jsonb; v_run bigint; v_step text := 'W08-S06';
  v_owner text; v_rev text; v_alias text := 'privacy_officer';
  v_res jsonb; v_out text := ''; v_tb bigint; v_ta bigint; v_trb bigint; v_tra bigint;
  v_srb bigint; v_sra bigint; v_next text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','probe-legal-005'));
  select s.accountable_role_id, s.independent_reviewer_role_id into v_owner, v_rev
    from public.phase_b_workflow_step s where s.step_id = v_step;
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','zz-probe-legal-005','execution_context','test','for_workflow','W08'));
  v_drive := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W08','scenario', v_fx, 'mode','happy', 'hold_at_first_open_step', true));
  v_run := (v_drive->>'run_id')::bigint;

  v_next := v_step;

  v_out := 'run=' || v_run || ' held=' || coalesce(v_drive->>'held_step_id','(none)')
        || ' target=' || coalesce(v_next,'(none)')
        || ' frozen_owner=' || v_owner || ' frozen_reviewer=' || v_rev;

  select count(*) into v_tb from public.phase_c_task;
  select count(*) into v_trb from public.phase_c_trace;
  select count(*) into v_srb from public.phase_c_workflow_step_run;

  -- ARM A: the declared reviewer presented as the creator/owner of the same step
  begin
    v_res := public.fn_kernel_open_step(jsonb_build_object('run_id',v_run,'step_id',v_next,
      'owner_role_id', (select independent_reviewer_role_id from public.phase_b_workflow_step where step_id=v_next),
      'opened_because','probe A: creator is the declared reviewer'));
    v_out := v_out || ' || A=ACCEPTED task=' || coalesce(v_res->>'task_id','?');
  exception when others then
    v_out := v_out || ' || A=REFUSED ' || SQLSTATE || ' :: ' || left(SQLERRM,190);
  end;

  -- ARM B: a legacy alias resolving to the declared reviewer
  begin
    v_res := public.fn_kernel_open_step(jsonb_build_object('run_id',v_run,'step_id',v_next,
      'owner_role_id', v_alias, 'opened_because','probe B: alias of the declared reviewer'));
    v_out := v_out || ' || B=ACCEPTED task=' || coalesce(v_res->>'task_id','?');
  exception when others then
    v_out := v_out || ' || B=REFUSED ' || SQLSTATE || ' :: ' || left(SQLERRM,190);
  end;

  select count(*) into v_ta from public.phase_c_task;
  select count(*) into v_tra from public.phase_c_trace;
  select count(*) into v_sra from public.phase_c_workflow_step_run;
  v_out := v_out || ' || residue tasks ' || v_tb || '->' || v_ta || ' traces ' || v_trb || '->' || v_tra
        || ' stepruns ' || v_srb || '->' || v_sra;

  -- ARM C: the frozen canonical owner
  begin
    v_res := public.fn_kernel_open_step(jsonb_build_object('run_id',v_run,'step_id',v_next,
      'owner_role_id', (select accountable_role_id from public.phase_b_workflow_step where step_id=v_next),
      'opened_because','probe C: the frozen canonical owner'));
    v_out := v_out || ' || C=ACCEPTED task=' || coalesce(v_res->>'task_id','?');
  exception when others then
    v_out := v_out || ' || C=REFUSED ' || SQLSTATE || ' :: ' || left(SQLERRM,190);
  end;

  raise exception 'PROBE %', v_out;
end $p$;`;
try { await q(sql); console.log('DID NOT RAISE'); }
catch(e){ console.log(String(e.message).replace(/\n/g,'\n').slice(0,4000)); }
