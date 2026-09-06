import { q } from './q.mjs';
const sql = `
do $p$
declare
  v_fx jsonb; v_drive jsonb; v_run bigint; v_hold text; v_next text; v_ovl text; v_alias text;
  v_res jsonb; v_out text := ''; v_owner text; v_tb bigint; v_ta bigint;
  v_trb bigint; v_tra bigint; v_srb bigint; v_sra bigint; v_hb bigint; v_ha bigint; v_eb bigint; v_ea bigint;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','probe-auth-005'));
  select b.live_role_id into v_ovl from public.phase_c_overlay_binding b order by b.overlay_id limit 1;
  select a.alias into v_alias from public.org_role_alias a where a.role_id = v_ovl limit 1;
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','zz-probe-auth-005','execution_context','test','for_workflow','W04'));
  v_drive := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W04','scenario', v_fx, 'mode','happy', 'hold_at_first_open_step', true));
  v_run := (v_drive->>'run_id')::bigint;
  v_hold := v_drive->>'held_step_id';

  select s.step_id, s.accountable_role_id into v_next, v_owner
    from public.phase_b_workflow_step s
   where s.workflow_id='W04'
     and not exists (select 1 from public.phase_c_workflow_step_run r where r.run_id=v_run and r.step_id=s.step_id)
   order by s.step_no limit 1;

  v_out := 'run=' || v_run || ' held=' || coalesce(v_hold,'(none)') || ' target=' || coalesce(v_next,'(none)')
        || ' canonical=' || coalesce(v_owner,'(none)') || ' overlay=' || coalesce(v_ovl,'(none)')
        || ' alias=' || coalesce(v_alias,'(none)');

  select count(*) into v_tb from public.phase_c_task;
  select count(*) into v_trb from public.phase_c_trace;
  select count(*) into v_srb from public.phase_c_workflow_step_run;
  select count(*) into v_hb from public.phase_c_handoff_run;
  select count(*) into v_eb from public.phase_c_event_outbox;

  -- ARM A: overlay identity presented directly as the accountable owner
  begin
    v_res := public.fn_kernel_open_step(jsonb_build_object('run_id',v_run,'step_id',v_next,
      'owner_role_id', v_ovl, 'opened_because','probe A: overlay as accountable owner'));
    v_out := v_out || ' || A=ACCEPTED task=' || coalesce(v_res->>'task_id','?');
  exception when others then
    v_out := v_out || ' || A=REFUSED ' || SQLSTATE || ' :: ' || left(SQLERRM,170);
  end;

  -- ARM B: a registered alias that resolves to the same overlay
  begin
    v_res := public.fn_kernel_open_step(jsonb_build_object('run_id',v_run,'step_id',v_next,
      'owner_role_id', v_alias, 'opened_because','probe B: overlay disguised behind its alias'));
    v_out := v_out || ' || B=ACCEPTED task=' || coalesce(v_res->>'task_id','?');
  exception when others then
    v_out := v_out || ' || B=REFUSED ' || SQLSTATE || ' :: ' || left(SQLERRM,170);
  end;

  select count(*) into v_ta from public.phase_c_task;
  select count(*) into v_tra from public.phase_c_trace;
  select count(*) into v_sra from public.phase_c_workflow_step_run;
  select count(*) into v_ha from public.phase_c_handoff_run;
  select count(*) into v_ea from public.phase_c_event_outbox;
  v_out := v_out || ' || residue tasks ' || v_tb || '->' || v_ta || ' traces ' || v_trb || '->' || v_tra
        || ' stepruns ' || v_srb || '->' || v_sra || ' handoffs ' || v_hb || '->' || v_ha
        || ' outbox ' || v_eb || '->' || v_ea;

  -- ARM C (control): the standing accountable role
  begin
    v_res := public.fn_kernel_open_step(jsonb_build_object('run_id',v_run,'step_id',v_next,
      'owner_role_id', v_owner, 'opened_because','probe C: the standing accountable role'));
    v_out := v_out || ' || C=ACCEPTED task=' || coalesce(v_res->>'task_id','?');
  exception when others then
    v_out := v_out || ' || C=REFUSED ' || SQLSTATE || ' :: ' || left(SQLERRM,170);
  end;

  raise exception 'PROBE %', v_out;
end $p$;`;
try { await q(sql); console.log('DID NOT RAISE'); }
catch(e){ console.log(String(e.message).replace(/\n/g,'\n').slice(0,4000)); }
