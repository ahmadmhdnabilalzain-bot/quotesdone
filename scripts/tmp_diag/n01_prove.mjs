// N01 PROVED IN BOTH DIRECTIONS, inside one transaction that ends in raise exception.
//
// Five arms on the SAME key, so a refusal cannot be "the gate refuses everything":
//   1 approved+verified supplier      -> PASS, row lands
//   2 approval_status cleared (pending) -> BLOCKED_SUPPLIER_NOT_APPROVED, no row
//   3 approval_status = 'rejected'      -> BLOCKED_SUPPLIER_NOT_APPROVED naming rejected
//   4 registration_expires_at in past   -> BLOCKED_INELIGIBLE_SUPPLIER naming registration
//   5 approved but verified = false     -> BLOCKED_SUPPLIER_NOT_APPROVED naming verification
import { probe } from './probe.mjs';

const arm = (n, setup, key) => `
  ${setup}
  perform set_config('app.inquiry_match_gate_verdict','(unset)', true);
  perform set_config('app.inquiry_match_gate_reason','(unset)', true);
  v_id := null;
  begin
    insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, match_reason)
    values (v_inq, v_sup, 0.9, 'PHASE_D_FIXTURE_DO_NOT_PUBLISH n01 arm ${n}') returning id into v_id;
  exception when others then v_id := null; end;
  v_out := v_out || '|${key}_verdict=' || current_setting('app.inquiry_match_gate_verdict', true)
        || '|${key}_landed=' || case when v_id is null then 'false' else 'true' end
        || '|${key}_reason=' || left(current_setting('app.inquiry_match_gate_reason', true), 70);
  delete from public.inquiry_matches where id = v_id;`;

console.log(await probe(`do $p$
declare v_fx jsonb; v_out text := ''; v_inq uuid; v_sup bigint; v_id bigint;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','n01'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','n01','execution_context','test','for_workflow','W12'));
  v_inq := (v_fx->'parent_refs'->>'inquiry_id')::uuid;
  v_sup := (v_fx->'parent_refs'->>'supplier_id')::bigint;
${arm(1, '-- control: the fixture supplier as built', 'approved')}
${arm(2, "update public.leads set approval_status = null where id = v_sup;", 'pending')}
${arm(3, "update public.leads set approval_status = 'rejected' where id = v_sup;", 'rejected')}
${arm(4, "update public.leads set approval_status = 'approved', verified = true, registration_expires_at = now() - interval '1 day' where id = v_sup;", 'regexpired')}
${arm(5, "update public.leads set registration_expires_at = null, approval_status = 'suspended' where id = v_sup;", 'suspended')}
${arm(6, "update public.leads set approval_status = 'approved', verified = true, banned = true where id = v_sup;", 'banned')}
  raise exception 'N01<<%>>', v_out;
end $p$;`, 'N01'));
