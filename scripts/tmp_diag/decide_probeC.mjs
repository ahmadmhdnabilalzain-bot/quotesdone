import { sql } from '../phase_b/lib/db.mjs';

const body = `
do $emit$
declare v_out text := ''; v_w jsonb; v_st text; v_rc text; v_q uuid; v_bk text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_acceptance_probe','label','decide-thirteen-probeC'));

  -- can we write a supplier_safe_package object record through the canonical service?
  v_bk := 'zz-safe-' || md5('pkg');
  begin
    v_w := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_safe_package','business_key', v_bk,'owner_ref','zz-inq',
      'created_by','decide_probe','state','approved',
      'payload', jsonb_build_object('note','ZZ DEMO — safe package')));
    v_out := v_out || 'SAFEwrite=' || left(v_w::text,90) || '|';
  exception when others then v_out := v_out || 'SAFEwrite=ERR ' || left(SQLERRM,110) || '|'; end;

  -- terms acceptance object record
  begin
    v_w := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','customer_terms_acceptance','business_key','zz-acc-1','owner_ref','zz-cust',
      'created_by','decide_probe','state','accepted',
      'payload', jsonb_build_object('note','ZZ DEMO — acceptance')));
    v_out := v_out || 'ACCwrite=' || left(v_w::text,90) || '|';
  exception when others then v_out := v_out || 'ACCwrite=ERR ' || left(SQLERRM,110) || '|'; end;

  -- a quote row, incomplete then complete
  begin
    insert into public.quotes (id, quote_amount, status, source)
    values (gen_random_uuid(), 1000, '', 'zz-probe') returning id into v_q;
    v_out := v_out || 'QINCwrite=ok ' || v_q::text || '|';
  exception when others then v_out := v_out || 'QINCwrite=ERR ' || left(SQLERRM,110) || '|'; end;

  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;

try { await sql(body); console.log('did not raise'); }
catch (e) {
  const m = String(e.message); const a = m.indexOf('PROBE<<');
  console.log(a < 0 ? 'ERR: ' + m.slice(0, 2000) : m.slice(a + 7, m.indexOf('>>', a)).split('|').join('\n'));
}
