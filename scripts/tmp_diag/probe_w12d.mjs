import { sql } from '../phase_c/lib/db.mjs';
const q = `do $emit$
declare v jsonb; v_fx jsonb; v_out text := ''; v_inq uuid; v_sup bigint; v_id bigint; n int;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','dbg-w12d'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','dbg-w12d','execution_context','test','for_workflow','W12'));
  v_inq := (v_fx->'parent_refs'->>'inquiry_id')::uuid;
  v_sup := (v_fx->'parent_refs'->>'supplier_id')::bigint;
  v_out := 'inq=' || v_inq || ' sup=' || v_sup
        || ' ready=' || coalesce((select rfq_ready::text from public.inquiries where id=v_inq),'NO-ROW');
  begin
    insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, match_reason)
    values (v_inq, v_sup, 0.9, 'probe') returning id into v_id;
    v_out := v_out || ' | direct_insert_id=' || coalesce(v_id::text,'NULL-RETURNED');
  exception when others then
    v_out := v_out || ' | direct_insert_raised=' || sqlerrm;
  end;
  get diagnostics n = row_count;
  v_out := v_out || ' rows=' || n;
  v_out := v_out || ' | matches_now=' || (select count(*)::text from public.inquiry_matches where inquiry_id=v_inq);
  raise exception 'DBG<<%>>', v_out;
end $emit$;`;
try { await sql(q); } catch (e) {
  const m = String(e.message); const a = m.indexOf('DBG<<');
  console.log(a>=0 ? m.slice(a+5, m.indexOf('>>', a)) : m.slice(0,3000));
}
