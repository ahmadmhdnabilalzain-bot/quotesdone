import { sql } from '../lib/db.mjs';
const q = `
do $emit$
declare v_fx jsonb; v_max bigint; v_out text := '';
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','diag-out'));
  select coalesce(max(id),0) into v_max from net.http_request_queue;
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','diagout','execution_context','test','for_workflow', null));
  v_out := 'outbound=' || coalesce(v_fx->>'outbound_http_requests_written_by_this_scenario','?') || chr(31)
        || 'urls=' || coalesce((select string_agg(q.method || ' ' || q.url, ' | ')
                                  from net.http_request_queue q where q.id > v_max),'(none)') || chr(31)
        || 'triggers_on_workstream_group=' || coalesce((select string_agg(t.tgname || '->' || p.proname, ', ')
             from pg_trigger t join pg_proc p on p.oid=t.tgfoid
            where t.tgrelid='public.inquiry_workstream_group'::regclass and not t.tgisinternal),'(none)') || chr(31)
        || 'triggers_on_inquiry_answer=' || coalesce((select string_agg(t.tgname || '->' || p.proname, ', ')
             from pg_trigger t join pg_proc p on p.oid=t.tgfoid
            where t.tgrelid='public.inquiry_answer'::regclass and not t.tgisinternal),'(none)') || chr(31)
        || 'triggers_on_documents=' || coalesce((select string_agg(t.tgname || '->' || p.proname, ', ')
             from pg_trigger t join pg_proc p on p.oid=t.tgfoid
            where t.tgrelid='public.documents'::regclass and not t.tgisinternal),'(none)');
  raise exception 'DIAG%', v_out;
end $emit$;`;
try { await sql(q); console.error('no raise'); }
catch (err) {
  const m = String(err?.message ?? err); const i = m.indexOf('DIAG');
  let g = m.slice(i + 4).replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\\"/g, '"').replace(/\\n/g, '\n');
  const c = g.indexOf('\nCONTEXT:'); if (c >= 0) g = g.slice(0, c);
  for (const l of g.split(String.fromCharCode(31))) if (l.trim()) console.log(l + '\n');
}
