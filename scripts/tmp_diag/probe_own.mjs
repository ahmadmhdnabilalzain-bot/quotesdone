import { sql } from '../phase_b/lib/db.mjs';
const q = `do $p$
declare v jsonb; v_out text := '';
begin
  v := public.fn_kernel_routine_ownership('public.trg_gate_incomplete_match','','MANIFEST');
  v_out := 'as MANIFEST: ' || left(v::text, 400);
  v := public.fn_kernel_routine_ownership('public.trg_gate_incomplete_match','','TRACKED_SQL_OUTSIDE_MANIFEST');
  v_out := v_out || E'\nas TRACKED: ' || left(v::text, 400);
  v := public.fn_kernel_routine_ownership('public.fn_unsafe_match_eligibility_guard','','MANIFEST');
  v_out := v_out || E'\nunsafe as MANIFEST: ' || left(v::text, 400);
  raise exception 'DBG<<%>>', v_out;
end $p$;`;
try { await sql(q); } catch (e) {
  const m = String(e.message); const a = m.indexOf('DBG<<');
  console.log(a>=0 ? m.slice(a+5, m.indexOf('>>', a)).replace(/\n/g,'\n') : m.slice(0,2000));
}
