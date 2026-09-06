import { sql } from '../phase_c/lib/db.mjs';
const q = `do $p$
declare v_fx jsonb; v_out text := '';
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','dbg-w16c'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','dbg-w16c','execution_context','test','for_workflow',null));
  v_out := 'after_scenario_invoices=' || (select count(*)::text from public.reveal_invoices)
        || ' | scenario_records_invoice=' || (select count(*)::text from public.phase_d_scenario_record
              where fixture_run_id = public.fn_phase_d_fixture_context() and object_id='invoice_receipt')
        || ' | for_w16=' ;
  raise exception 'DBG<<%>>', v_out;
end $p$;`;
try { await sql(q); } catch (e) {
  const m = String(e.message); const a = m.indexOf('DBG<<');
  console.log(a>=0 ? m.slice(a+5, m.indexOf('>>', a)) : m.slice(0,2000));
}
