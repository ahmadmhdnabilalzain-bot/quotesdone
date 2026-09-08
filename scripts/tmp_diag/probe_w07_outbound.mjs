import { sql } from '../lib/db.mjs';
const q = `
do $emit$
declare v_fx jsonb; v jsonb; v_max bigint; v_out text := ''; v_cands jsonb;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','diag-o7'));
  select jsonb_agg(distinct s.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step s where coalesce(btrim(s.independent_reviewer_role_id),'') <> '';
  select coalesce(max(id),0) into v_max from net.http_request_queue;
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','wfresult-w07','execution_context','test'));
  v_out := 'after_factory=' || coalesce(v_fx->>'outbound_http_requests_written_by_this_scenario','?')
        || ' urls=' || coalesce((select string_agg(q.method||' '||q.url,' | ')
             from net.http_request_queue q where q.id > v_max),'(none)') || chr(31);
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W07','label','wfresult-w07','execution_context','production',
    'reviewer_role_id','risk_and_governance_manager','reviewer_candidates', v_cands));
  v_out := v_out || 'after_drive_total=' || (select count(*) from net.http_request_queue q where q.id > v_max)::text
        || ' urls=' || coalesce((select string_agg(q.method||' '||q.url,' | ')
             from net.http_request_queue q where q.id > v_max),'(none)');
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
