import { sql } from '../phase_b/lib/db.mjs';
import { readFileSync } from 'node:fs';
const body = readFileSync('scripts/tmp_diag/m06_merged_body.sql', 'utf8');
const q = `do $emit$
declare v_out text := ''; r record;
begin
  execute $m06$${body}$m06$;
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','m06selftest'));
  create temp table zz_rep on commit drop as
    select * from public.fn_phase_d_injected_defect_report();
  for r in select status, count(*) n from zz_rep group by 1 order by 2 desc loop
    v_out := v_out || r.status || '=' || r.n || ' ;; ';
  end loop;
  v_out := v_out || 'TOTAL=' || (select count(*) from zz_rep) || ' ;; ';
  v_out := v_out || 'NOTREFUSED=' || coalesce((select string_agg(defect_id||':'||status, ',' order by defect_id)
             from zz_rep where status <> 'REFUSED_AS_REQUIRED'), '(none)');
  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;
try { await sql(q); } catch (e) {
  const m = String(e.message); const i = m.indexOf('PROBE<<');
  console.log(i >= 0 ? m.slice(i + 7, m.lastIndexOf('>>')).replace(/ ;; /g, '\n') : m.slice(0, 2000));
}
