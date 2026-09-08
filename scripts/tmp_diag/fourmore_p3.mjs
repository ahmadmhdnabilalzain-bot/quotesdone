import { sql } from '../lib/db.mjs';
const P = `
do $emit$
declare v_out text := ''; v_fx jsonb; v_inq text; v_r jsonb; v_sup text; v_n int; v_n2 int;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','fourmore-p3'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','fourmore3','execution_context','test'));
  v_inq := v_fx->'parent_refs'->>'inquiry_id';
  v_out := v_out || 'inq=' || coalesce(v_inq,'(null)');

  -- create an approved+verified supplier with an email through the canonical writer
  begin
    v_r := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_account','business_key','zz-fourmore-ok','owner_ref','zz-fourmore-ok',
      'created_by','defect_probe','state','approved',
      'payload', jsonb_build_object('company_name','ZZ DEMO — fourmore ok','email','zz-fourmore-ok@example.invalid','verified', true)));
    v_sup := split_part(v_r->>'result_reference','=',2);
    v_out := v_out || E'\nSUP_OK=' || v_sup || ' ref=' || (v_r->>'result_reference');
  exception when others then v_out := v_out || E'\nSUP_OK raised: ' || SQLERRM; end;

  -- assignment write, inquiry READY (control)
  select count(*) into v_n from public.inquiry_matches;
  select count(*) into v_n2 from public.notifications;
  begin
    v_r := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_assignment','business_key','zz-fourmore-asg-ok','owner_ref', v_sup,
      'created_by','defect_probe',
      'payload', jsonb_build_object('inquiry_id', v_inq, 'similarity', 0.5, 'match_reason','ZZ DEMO — fourmore control')));
    v_out := v_out || E'\nASG_OK ' || (v_r->>'result_reference');
  exception when others then v_out := v_out || E'\nASG_OK raised: ' || SQLERRM; end;
  v_out := v_out || format(E'\n  im %s->%s  notif %s->%s', v_n, (select count(*) from public.inquiry_matches), v_n2, (select count(*) from public.notifications));

  -- now make the inquiry NOT ready and try again with a fresh supplier
  update public.inquiries set status='new', rfq_ready=false where id::text = v_inq;
  v_out := v_out || E'\nafter unready: ' || (select coalesce(status,'-')||'/'||coalesce(rfq_ready::text,'-') from public.inquiries where id::text=v_inq);
  begin
    v_r := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_account','business_key','zz-fourmore-ok2','owner_ref','zz-fourmore-ok2',
      'created_by','defect_probe','state','approved',
      'payload', jsonb_build_object('company_name','ZZ DEMO — fourmore ok2','email','zz-fourmore-ok2@example.invalid','verified', true)));
    v_sup := split_part(v_r->>'result_reference','=',2);
  exception when others then v_out := v_out || E'\nSUP2 raised: ' || SQLERRM; end;
  select count(*) into v_n from public.inquiry_matches;
  select count(*) into v_n2 from public.notifications;
  begin
    v_r := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_assignment','business_key','zz-fourmore-asg-bad','owner_ref', v_sup,
      'created_by','defect_probe',
      'payload', jsonb_build_object('inquiry_id', v_inq, 'similarity', 0.5, 'match_reason','ZZ DEMO — fourmore injection')));
    v_out := v_out || E'\nASG_BAD NOT REFUSED ' || (v_r->>'result_reference');
  exception when others then v_out := v_out || E'\nASG_BAD raised: ' || left(SQLERRM,300); end;
  v_out := v_out || format(E'\n  im %s->%s  notif %s->%s', v_n, (select count(*) from public.inquiry_matches), v_n2, (select count(*) from public.notifications));
  v_out := v_out || E'\n  verdict=' || coalesce(current_setting('app.inquiry_match_gate_verdict',true),'-');
  -- gate evaluate both ways
  v_out := v_out || E'\nGATE011 unready: ' || (select state||'/'||coalesce(refusal_code,'-')||'/'||reason from public.fn_phase_d_gate_evaluate('GATE-011', jsonb_build_object('inquiry_id', v_inq)));
  update public.inquiries set status='quote_ready', rfq_ready=true,
     routing = coalesce(routing,'{}'::jsonb) || jsonb_build_object('dispatched_at', now(),'dispatched_by','phase_d_test_context','phase_d_outbound_suppressed', true)
   where id::text = v_inq;
  v_out := v_out || E'\nGATE011 ready: ' || (select state||'/'||coalesce(refusal_code,'-') from public.fn_phase_d_gate_evaluate('GATE-011', jsonb_build_object('inquiry_id', v_inq)));
  select count(*) into v_n from public.inquiry_matches; select count(*) into v_n2 from public.notifications;
  begin
    v_r := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_assignment','business_key','zz-fourmore-asg-ctl','owner_ref', v_sup,
      'created_by','defect_probe',
      'payload', jsonb_build_object('inquiry_id', v_inq, 'similarity', 0.5, 'match_reason','ZZ DEMO — fourmore control2')));
    v_out := v_out || E'\nASG_CTL ' || (v_r->>'result_reference');
  exception when others then v_out := v_out || E'\nASG_CTL raised: ' || left(SQLERRM,300); end;
  v_out := v_out || format(E'\n  im %s->%s  notif %s->%s', v_n, (select count(*) from public.inquiry_matches), v_n2, (select count(*) from public.notifications));
  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;
try { await sql(P); } catch(e) { console.log(e.message.split('\n').join('\n')); }
