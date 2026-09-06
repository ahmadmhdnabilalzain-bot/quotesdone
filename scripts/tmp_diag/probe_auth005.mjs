import { q } from './q.mjs';
const sql = `
do $p$
declare
  v_fx jsonb; v_drive jsonb; v_run bigint; v_step text; v_ovl text;
  v_res jsonb; v_out text := ''; v_err text; v_owner text;
  v_task_before bigint; v_task_after bigint;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','probe-auth-005'));
  select b.live_role_id into v_ovl from public.phase_c_overlay_binding b order by b.overlay_id limit 1;
  v_out := v_out || 'overlay=' || coalesce(v_ovl,'(none)');

  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','zz-probe-auth-005','execution_context','test','for_workflow','W04'));
  v_drive := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W04','scenario', v_fx, 'mode','happy','stop_after_steps',1));
  v_out := v_out || ' | drive_keys=' || (select string_agg(k,',') from jsonb_object_keys(v_drive) k);
  v_run := nullif(v_drive->>'run_id','')::bigint;
  v_out := v_out || ' | run=' || coalesce(v_run::text,'(null)');
  raise exception 'PROBE %', v_out;
end $p$;`;
try { await q(sql); console.log('DID NOT RAISE'); }
catch(e){ console.log(String(e.message).slice(0,3000)); }
