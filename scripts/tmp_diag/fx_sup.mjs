import { probe } from './probe.mjs';
const WF = process.argv[2] || 'W12';
console.log(await probe(`do $p$
declare v_fx jsonb; v_sup bigint; r record; v_out text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','fxsup'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','fxsup','execution_context','test','for_workflow','${WF}'));
  v_sup := (v_fx->'parent_refs'->>'supplier_id')::bigint;
  select id, company_name, approval_status, verified, banned, matching_blocked,
         permanently_closed, license_expiry, registration_expires_at
    into r from public.leads where id = v_sup;
  v_out := format('supplier=%s approval_status=%s verified=%s banned=%s blocked=%s closed=%s lic=%s regexp=%s',
    coalesce(r.id::text,'(no row)'), coalesce(r.approval_status,'(null)'), coalesce(r.verified::text,'(null)'),
    coalesce(r.banned::text,'(null)'), coalesce(r.matching_blocked::text,'(null)'),
    coalesce(r.permanently_closed::text,'(null)'), coalesce(r.license_expiry::text,'(null)'),
    coalesce(r.registration_expires_at::text,'(null)'));
  raise exception 'FX<<%>>', v_out;
end $p$;`, 'FX'));
