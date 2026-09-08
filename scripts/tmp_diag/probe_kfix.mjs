import { sql } from '../lib/db.mjs';
const q = `
do $emit$
declare v jsonb;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','diag-k2'));
  v := public.fn_phase_d_kernel_object_fixture(jsonb_build_object('label','diagk2'));
  raise exception 'DIAG%', v::text;
end $emit$;`;
try { await sql(q); console.error('no raise'); }
catch (err) {
  const m = String(err?.message ?? err); const i = m.indexOf('DIAG');
  console.log(m.slice(i, i + 1200).replace(/\\"/g, '"').replace(/\\n/g, '\n'));
}
