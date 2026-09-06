import { q } from './q.mjs';
const sql = `
do $p$
declare
  v_fx jsonb; v_drive jsonb; v_run bigint; v_ovl text; v_alias text; v_res jsonb;
  v_out text := ''; v_srid bigint; v_owner text;
  v_tb bigint; v_ta bigint; v_trb bigint; v_tra bigint; v_srb bigint; v_sra bigint;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','verify-o01'));
  select b.live_role_id into v_ovl from public.phase_c_overlay_binding b order by b.overlay_id limit 1;
  select a.alias into v_alias from public.org_role_alias a where a.role_id = v_ovl limit 1;

  -- the predicate, on all four shapes
  v_out := 'predicate:';
  for v_owner in select unnest(array[v_ovl, v_alias, 'customer_onboarding', 'zz-nobody', '']) loop
    v_out := v_out || ' [' || coalesce(nullif(v_owner,''),'(empty)') || '->'
          || coalesce((select refusal_code from public.fn_phase_d_owner_admissibility(v_owner)),'ADMISSIBLE') || ']';
  end loop;

  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','zz-verify-o01','execution_context','test','for_workflow','W04'));
  v_drive := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W04','scenario', v_fx, 'mode','happy','hold_at_first_open_step', true));
  v_run := (v_drive->>'run_id')::bigint;
  v_srid := (v_drive->>'held_step_run_id')::bigint;

  select count(*) into v_tb from public.phase_c_task;
  select count(*) into v_trb from public.phase_c_trace;
  select count(*) into v_srb from public.phase_c_workflow_step_run;

  -- FORCE THE NEW STEP-RUN TRIGGER TO FIRE. fn_kernel_open_step refuses an overlay before the
  -- insert, so the only way to reach the table with one is the write guard's audited maintenance
  -- door -- stated reason plus table owner -- inside this aborted transaction.
  begin
    perform set_config('kernel.maintenance_reason',
      'O01 verification: force a02_phase_c_step_run_owner_admissible to fire on an overlay owner', true);
    update public.phase_c_workflow_step_run set accountable_role_id = v_ovl where step_run_id = v_srid;
    v_out := v_out || ' || TRIGGER=NOT_FIRED (the update was accepted)';
  exception when others then
    v_out := v_out || ' || TRIGGER=FIRED ' || SQLSTATE || ' :: ' || left(SQLERRM,200);
  end;
  perform set_config('kernel.maintenance_reason', '', true);

  -- and it must NOT fire on a canonical owner: a guard that refuses everything measures nothing
  begin
    perform set_config('kernel.maintenance_reason', 'O01 verification: the control arm', true);
    update public.phase_c_workflow_step_run set accountable_role_id = 'customer_onboarding'
     where step_run_id = v_srid;
    v_out := v_out || ' || CONTROL=ACCEPTED';
  exception when others then
    v_out := v_out || ' || CONTROL=REFUSED ' || SQLSTATE || ' :: ' || left(SQLERRM,140);
  end;
  perform set_config('kernel.maintenance_reason', '', true);

  select count(*) into v_ta from public.phase_c_task;
  select count(*) into v_tra from public.phase_c_trace;
  select count(*) into v_sra from public.phase_c_workflow_step_run;
  v_out := v_out || ' || counts tasks ' || v_tb || '->' || v_ta || ' traces ' || v_trb || '->' || v_tra
        || ' stepruns ' || v_srb || '->' || v_sra;

  raise exception 'VERIFY %', v_out;
end $p$;`;
try { await q(sql); console.log('DID NOT RAISE'); }
catch(e){ console.log(String(e.message).replace(/\n/g,'\n').slice(0,4000)); }
