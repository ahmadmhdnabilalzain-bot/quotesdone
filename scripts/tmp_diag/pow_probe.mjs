import { probe } from './probe.mjs';
const call = (obj, extra = '') => `
  begin
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','${obj}','business_key','zz-pd-probe-${obj}',
      'owner_ref','system.workflow_engine','created_by','system.workflow_engine','target_state','active'${extra},
      'payload', jsonb_build_object('note','PHASE_D_FIXTURE_DO_NOT_PUBLISH')));
    v_out := v_out || '${obj}=WROTE; ';
  exception when others then
    v_out := v_out || '${obj}=' || left(regexp_replace(SQLERRM,'[|<>]',' ','g'), 190) || '; ';
  end;`;
console.log(await probe(`do $p$
declare v_out text := ''; v_fx jsonb;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','powprobe'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','powprobe','execution_context','test','for_workflow','W01'));
${call('workflow_step_run')}
${call('workflow_run')}
${call('handoff_record')}
${call('trace_policy')}
  raise exception 'POW<<%>>', v_out;
end $p$;`, 'POW'));
