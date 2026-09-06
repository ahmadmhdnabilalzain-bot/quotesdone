// Install the candidate inside an aborted transaction, run the 75 injections, report.
//   node m03_test.mjs tally
//   node m03_test.mjs slice <from> <len>   -- window over the concatenated observed text of the 8
import fs from 'node:fs';
import { sql } from '../phase_b/lib/db.mjs';

const CAND = fs.readFileSync('scripts/tmp_diag/m03_injected_defects_candidate.sql', 'utf8');
const EIGHT = process.env.ONLY ? '('+process.env.ONLY.split(',').map(x=>"'"+x+"'").join(',')+')' : "('PD-IDEM-002','PD-REV-002','PD-REV-004','PD-REV-005','PD-STATE-002','PD-STATE-003','PD-TRACE-003','PD-TRACE-004')";
const mode = process.argv[2] || 'tally';
const from = Number(process.argv[3] || 1), len = Number(process.argv[4] || 1700);

const report = mode === 'tally' ? `
  select count(*) into v_n from _r;
  select string_agg(replace(defect_id,'PD-','') || ':' ||
      case status when 'REFUSED_AS_REQUIRED' then 'R' when 'NOT_REFUSED' then 'F'
                  when 'NOT_RUN' then 'N' when 'NOT_DISCRIMINATED' then 'D'
                  else '?'||status end, ',' order by defect_id) into v_out from _r;
  v_out := format('ms=%s n=%s | %s', round(extract(epoch from clock_timestamp()-v_t0)*1000), v_n, v_out);
  select coalesce(string_agg(defect_id||'='||length(coalesce(observed,''))||'/'||coalesce(left(blocker,1),'-'), ' ' order by defect_id),'-')
    into v_x from _r where defect_id in ${EIGHT};
  v_out := v_out || ' || ' || v_x;
` : `
  select string_agg(defect_id || ' >>> ' || coalesce(observed,'(null)'), chr(10)||chr(10) order by defect_id)
    into v_x from _r where defect_id in ${EIGHT};
  v_out := format('[%s..%s of %s] ', ${from}, ${from}+${len}-1, length(v_x)) || substr(v_x, ${from}, ${len});
`;

const q = `do $emit$
declare v_out text; v_x text; v_n int; v_t0 timestamptz := clock_timestamp();
begin
  execute $cand$${CAND}$cand$;
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_acceptance_probe','label','m03-candidate-run'));
  create temp table _r on commit drop as select * from public.fn_phase_d_run_injected_defects();
  ${report}
  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;

try { const r = await sql(q); console.log('NO MARKER', JSON.stringify(r).slice(0, 3000)); }
catch (e) {
  const m = String(e.message);
  const a = m.indexOf('PROBE<<');
  if (a >= 0) { const s = m.slice(a + 7); const b = s.lastIndexOf('>>'); console.log(b >= 0 ? s.slice(0, b) : s + '  [[UNTERMINATED]]'); }
  else console.log('ERR ' + m.slice(0, 4000));
}
