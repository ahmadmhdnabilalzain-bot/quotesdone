import { q } from './q.mjs';
const sql = `
do $p$
declare
  v_sub uuid; v_bind jsonb; v_req bigint; v_d1 bigint; v_d2 bigint; v_res jsonb;
  v_out text := ''; v_rdb bigint; v_rda bigint; v_rfb bigint; v_rfa bigint; v_row public.phase_c_refund_decision%rowtype;
  v_before jsonb;
begin
  select count(*) into v_rdb from public.phase_c_refund_decision;
  select count(*) into v_rfb from public.refunds;

  -- ARM 0: the service refuses a caller with no verified founder subject.
  begin
    v_res := public.fn_kernel_refund_decision_record(jsonb_build_object(
      'op','record','request_id',1,'decision','approved','reason','no founder on this call'));
    v_out := v_out || 'NOFOUNDER=ACCEPTED(!!)';
  exception when others then
    v_out := v_out || 'NOFOUNDER=REFUSED ' || SQLSTATE || ' :: ' || left(SQLERRM,90);
  end;

  -- verified founder subject, transaction-local, through the estate's own server door
  select f.auth_user_id into v_sub from public.phase_c_founder_identity f
   where f.active and f.kind='email' and f.auth_user_id is not null order by f.identity limit 1;
  v_bind := public.fn_phase_c_founder_subject_bind(v_sub);
  v_out := v_out || ' || bound=' || coalesce(v_bind->>'identity','(none)');

  insert into public.founder_approval_request(action_class, subject_ref, prepared_by_role_id)
  values ('refund_decision','zz-pd-fin-004-probe','payments_and_billing_manager') returning request_id into v_req;

  -- 2. a valid founder decision THROUGH THE CANONICAL SERVICE
  v_res := public.fn_kernel_refund_decision_record(jsonb_build_object(
    'op','record','request_id',v_req,'decision','approved','reason','PD-FIN-004 probe, aborted'));
  v_d1 := (v_res->>'decision_id')::bigint;
  v_out := v_out || ' || RECORDED id=' || v_d1 || ' decided_by=' || (v_res->>'decided_by');
  select * into v_row from public.phase_c_refund_decision where decision_id = v_d1;
  v_before := to_jsonb(v_row);

  -- 3. UPDATE
  begin
    perform set_config('kernel.maintenance_reason','PD-FIN-004 probe: reach the append-only trigger', true);
    update public.phase_c_refund_decision set decision='rejected' where decision_id=v_d1;
    v_out := v_out || ' || UPDATE=ACCEPTED(!!)';
  exception when others then
    v_out := v_out || ' || UPDATE=REFUSED ' || SQLSTATE || ' :: ' || left(SQLERRM,110);
  end;

  -- 4. DELETE
  begin
    perform set_config('kernel.maintenance_reason','PD-FIN-004 probe: reach the append-only trigger on DELETE', true);
    delete from public.phase_c_refund_decision where decision_id=v_d1;
    v_out := v_out || ' || DELETE=REFUSED?';
  exception when others then
    v_out := v_out || ' || DELETE=REFUSED ' || SQLSTATE || ' :: ' || left(SQLERRM,100);
  end;
  perform set_config('kernel.maintenance_reason','', true);

  select * into v_row from public.phase_c_refund_decision where decision_id = v_d1;
  v_out := v_out || ' || ORIGINAL_UNCHANGED=' || (to_jsonb(v_row) = v_before);

  -- 5. the superseding path
  v_res := public.fn_kernel_refund_decision_record(jsonb_build_object(
    'op','record','request_id',v_req,'decision','rejected','reason','he changed his mind',
    'supersedes_decision_id', v_d1, 'supersession_reason','PD-FIN-004 probe supersession'));
  v_d2 := (v_res->>'decision_id')::bigint;
  v_out := v_out || ' || SUPERSEDE=ACCEPTED id=' || v_d2;

  -- 6. a refund may not execute against a superseded decision
  begin
    v_res := public.fn_kernel_refund_decision_record(jsonb_build_object('op','execute','decision_id',v_d1));
    v_out := v_out || ' || EXEC_SUPERSEDED=ACCEPTED(!!)';
  exception when others then
    v_out := v_out || ' || EXEC_SUPERSEDED=REFUSED ' || SQLSTATE || ' :: ' || left(SQLERRM,110);
  end;

  -- 7. a platform refund may not reach a money-moved status with no decision
  begin
    insert into public.refunds(amount_fils, currency, status, requested_by, reason_code)
    values (1000,'AED','succeeded','customer_success_director','goodwill');
    v_out := v_out || ' || REFUND_NO_DECISION=ACCEPTED(!!)';
  exception when others then
    v_out := v_out || ' || REFUND_NO_DECISION=REFUSED ' || SQLSTATE || ' :: ' || left(SQLERRM,120);
  end;

  -- 8. the control: the same refund citing an approved, non-superseded decision
  declare v_d3 bigint;
  begin
    insert into public.founder_approval_request(action_class, subject_ref, prepared_by_role_id)
    values ('refund_decision','zz-pd-fin-004-probe-2','payments_and_billing_manager') returning request_id into v_req;
    v_res := public.fn_kernel_refund_decision_record(jsonb_build_object(
      'op','record','request_id',v_req,'decision','approved','reason','the control arm'));
    v_d3 := (v_res->>'decision_id')::bigint;
    begin
      insert into public.refunds(amount_fils, currency, status, requested_by, reason_code, refund_decision_id)
      values (1000,'AED','succeeded','customer_success_director','goodwill', v_d3);
      v_out := v_out || ' || REFUND_WITH_DECISION=ACCEPTED';
    exception when others then
      v_out := v_out || ' || REFUND_WITH_DECISION=REFUSED ' || SQLSTATE || ' :: ' || left(SQLERRM,120);
    end;
  end;

  select count(*) into v_rda from public.phase_c_refund_decision;
  select count(*) into v_rfa from public.refunds;
  v_out := v_out || ' || in-txn decisions ' || v_rdb || '->' || v_rda || ' refunds ' || v_rfb || '->' || v_rfa;
  raise exception 'PROBE %', v_out;
end $p$;`;
try { await q(sql); console.log('DID NOT RAISE'); }
catch(e){ console.log(String(e.message).replace(/\n/g,'\n').slice(0,4500)); }
