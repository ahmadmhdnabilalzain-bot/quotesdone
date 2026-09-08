// Apply decide_patch.mjs to the LIVE body of public.fn_phase_d_run_injected_defects(), inside one
// transaction that ends in `raise exception`, then run the patched function and print all 75
// statuses. Nothing is written: the CREATE OR REPLACE and every row the probes insert roll back.
//
//   node scripts/tmp_diag/decide_selftest.mjs
import { sql } from '../lib/db.mjs';
import { PATCHES } from './decide_patch.mjs';

const live = (await sql(`select pg_get_functiondef(p.oid) d
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='fn_phase_d_run_injected_defects'`))[0].d;

let body = live;
for (const p of PATCHES) {
  const n = body.split(p.find).length - 1;
  if (n !== 1) { console.error(`PATCH ${p.name}: find matched ${n} times, expected exactly 1`); process.exit(1); }
  body = body.replace(p.find, () => p.replace);
}
console.log(`${PATCHES.length} patches applied; ${live.length} -> ${body.length} bytes`);

// The definition goes in as a dollar-quoted literal with a tag the body cannot contain.
const TAG = 'decide_selftest_defn';
const run = `
do $emit$
declare v_out text := ''; v_n int := 0; v_ref int := 0; v_nr int := 0; v_x int := 0; r record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_acceptance_probe','label','decide-selftest'));
  execute $${TAG}$${body}$${TAG}$;
  for r in select * from public.fn_phase_d_run_injected_defects() order by defect_id loop
    v_n := v_n + 1;
    if    r.status = 'REFUSED_AS_REQUIRED' then v_ref := v_ref + 1;
    elsif r.status = 'NOT_RUN'             then v_nr  := v_nr  + 1;
    else                                        v_x   := v_x   + 1; end if;
    v_out := v_out || replace(r.defect_id,'PD-','') || '='
          || case r.status when 'REFUSED_AS_REQUIRED' then 'R' when 'NOT_RUN' then '_'
                           when 'NOT_REFUSED' then 'X' else r.status end || ' ';
  end loop;
  raise exception 'SELFTEST<<rows=% refused=% not_run=% other=% :: %>>', v_n, v_ref, v_nr, v_x, v_out;
end $emit$;`;

let summary;
try { await sql(run); summary = '(the probe did not raise)'; }
catch (e) {
  const m = String(e.message); const a = m.indexOf('SELFTEST<<');
  summary = a < 0 ? 'ERROR: ' + m.slice(0, 2500) : m.slice(a + 10, m.lastIndexOf('>>'));
}
console.log(summary.replace(' :: ', '\n\n').replace(/ (?=[A-Z])/g, '\n'));

// Second pass: the full observed text for the twenty-six cases this agent owns, so the closures can
// be read rather than counted.
const MINE = ['PD-AUTH-005','PD-DISP-003','PD-DISP-005','PD-FIN-001','PD-LEGAL-001','PD-LEGAL-003',
  'PD-LEGAL-005','PD-PRIV-001','PD-QUOTE-002','PD-QUOTE-003'];
const detail = `
do $emit$
declare v_out text := ''; r record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_acceptance_probe','label','decide-selftest-detail'));
  execute $${TAG}$${body}$${TAG}$;
  for r in select * from public.fn_phase_d_run_injected_defects()
            where defect_id = any (array[__IDS__]) order by defect_id loop
    v_out := v_out || chr(10) || r.defect_id || ' [' || r.status || '] '
          || left(coalesce(r.observed, '(no observed)'), 150);
  end loop;
  raise exception 'DETAIL<<%>>', v_out;
end $emit$;`;

for (const chunk of [MINE.slice(0, 5), MINE.slice(5)]) {
  const q = detail.replace('__IDS__', chunk.map(x => `'${x}'`).join(','));
  try { await sql(q); console.log('(no raise)'); }
  catch (e) {
    const m = String(e.message); const a = m.indexOf('DETAIL<<');
    console.log(a < 0 ? 'ERROR: ' + m.slice(0, 1200) : m.slice(a + 8, m.lastIndexOf('>>')));
  }
}
