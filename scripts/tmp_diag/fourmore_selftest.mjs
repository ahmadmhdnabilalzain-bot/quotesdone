// Applies scripts/tmp_diag/fourmore_patch.mjs to the LIVE body of
// public.fn_phase_d_run_injected_defects(), installs the patched body INSIDE a transaction that
// ends in `raise exception`, runs the function, and prints the status of all 75 defects.
// Nothing is applied to production: the CREATE OR REPLACE lives inside the aborted DO block.
//
//   node scripts/tmp_diag/fourmore_selftest.mjs           statuses for all 75
//   node scripts/tmp_diag/fourmore_selftest.mjs --detail  the four branches' full observed text
import { sql } from '../lib/db.mjs';
import { PATCHES } from './fourmore_patch.mjs';

const DETAIL = process.argv.includes('--detail');

const live = (await sql(
  `select pg_get_functiondef('public.fn_phase_d_run_injected_defects()'::regprocedure) as d`))[0].d;

let body = live;
for (const p of PATCHES) {
  const n = body.split(p.find).length - 1;
  if (n !== 1) { console.error(`ANCHOR MISS: ${p.name} occurs ${n} times`); process.exit(1); }
  body = body.replace(p.find, () => p.replace);
}
if (body.includes('$cand$')) { console.error('candidate body contains the $cand$ tag'); process.exit(1); }

const EMIT = DETAIL
  ? `for r in select * from public.fn_phase_d_run_injected_defects()
        where defect_id in ('PD-DISP-001','PD-DISP-002','PD-DISP-004','PD-LEGAL-002')
        order by defect_id loop
      v_out := v_out || chr(10) || r.defect_id || ' [' || r.status || '] len=' || length(coalesce(r.observed,''))::text || ' ' || coalesce(r.observed,'(null)');
    end loop;`
  : `for r in select * from public.fn_phase_d_run_injected_defects() order by defect_id loop
      v_out := v_out || ' ' || r.defect_id || ':' ||
        case r.status when 'REFUSED_AS_REQUIRED' then 'R' when 'NOT_REFUSED' then 'N'
                      when 'NOT_RUN' then 'x' else r.status end;
    end loop;
    v_out := v_out || chr(10) || 'rows=' || (select count(*) from public.fn_phase_d_run_injected_defects())::text;`;

const RUN = `
do $emit$
declare v_out text := ''; r record;
begin
  execute $cand$${body}$cand$;
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','fourmore-selftest'));
  ${EMIT}
  raise exception 'SELFTEST<<%>>', v_out;
end $emit$;`;

try {
  await sql(RUN);
  console.log('NO RAISE — the probe did not abort, which it must');
  process.exit(1);
} catch (e) {
  const m = /SELFTEST<<([\s\S]*)>>/.exec(e.message);
  if (!m) { console.log(e.message.split('\\n').join('\n')); process.exit(1); }
  console.log(m[1].split('\\n').join('\n').trim());
}
