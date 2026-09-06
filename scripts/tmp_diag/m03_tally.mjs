import { sql } from '../phase_b/lib/db.mjs';
const RUN = `
do $emit$
declare v_out text := ''; r record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','m03-baseline-tally'));
  for r in select * from public.fn_phase_d_run_injected_defects() order by defect_id loop
    v_out := v_out || r.defect_id || '=' ||
      case r.status when 'REFUSED_AS_REQUIRED' then 'R' when 'NOT_RUN' then 'N'
                    when 'NOT_DISCRIMINATED' then 'D' when 'NOT_REFUSED' then 'X'
                    else r.status end || ' ';
  end loop;
  raise exception 'TALLY<<%>>', v_out;
end $emit$;`;
try { await sql(RUN); console.log('did not raise'); }
catch (e) {
  const m = String(e.message ?? e);
  const a = m.indexOf('TALLY<<'), b = m.indexOf('>>', a);
  if (a < 0) { console.log(m); process.exit(1); }
  const pairs = m.slice(a+7, b).trim().split(/\s+/);
  const t = {};
  for (const p of pairs) { const s = p.split('=')[1]; t[s] = (t[s]||0)+1; }
  console.log('n=' + pairs.length, JSON.stringify(t));
  console.log(pairs.join('\n'));
}
