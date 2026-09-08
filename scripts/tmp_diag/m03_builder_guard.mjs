// Does the committed deliverable builder still fit its 1800-character transport guard once the
// eight branches carry real observed text? The builder emits ONE probe per category, bounding each
// free-text field at 240 characters. This computes the same payload length for all 15 categories
// from a single run of the report wrapper.
import fs from 'node:fs';
import { sql } from '../lib/db.mjs';
const CAND = fs.readFileSync('scripts/tmp_diag/m03_injected_defects_candidate.sql', 'utf8');
const q = `do $emit$
declare v_out text := '';
begin
  execute $cand$${CAND}$cand$;
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','m03-builder-guard'));
  create temp table _r on commit drop as select * from public.fn_phase_d_injected_defect_report();
  select string_agg(c || '=' || n || case when n > 1800 then ' OVER' else '' end, ' ' order by c)
    into v_out
    from (select category c, count(*) rows_n,
                 sum(1 + length(concat_ws(chr(31), defect_id, category, status,
                   public.fn_phase_d_bounded(replace(replace(coalesce(observed,''),chr(10),' '),chr(13),' '),240),
                   public.fn_phase_d_bounded(replace(replace(coalesce(blocker,''),chr(10),' '),chr(13),' '),240)))) n
            from _r group by 1) z;
  v_out := v_out || ' | total_rows=' || (select count(*) from _r)
        || ' cats=' || (select count(distinct category) from _r)
        || ' rows_per_cat=' || (select string_agg(distinct n::text,',') from (select count(*) n from _r group by category) y);
  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;
try { console.log('NO MARKER', JSON.stringify(await sql(q)).slice(0, 2000)); }
catch (e) { const m = String(e.message); const a = m.indexOf('PROBE<<');
  console.log(a >= 0 ? m.slice(a + 7, m.lastIndexOf('>>')) : 'ERR ' + m.slice(0, 2500)); }
