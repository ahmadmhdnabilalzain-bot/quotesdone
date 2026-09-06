// Three checks the patch has to pass before it is handed over:
//  1. the BEFORE statuses of the four, straight off the live function;
//  2. no patch anchor touches the eight branches the other agent owns;
//  3. after the patched function runs, no outbound HTTP request is attributable to the transaction.
import { sql } from '../phase_b/lib/db.mjs';
import { PATCHES } from './fourmore_patch.mjs';

const live = (await sql(
  `select pg_get_functiondef('public.fn_phase_d_run_injected_defects()'::regprocedure) as d`))[0].d;

const OTHERS = ['PD-IDEM-002','PD-REV-002','PD-REV-004','PD-REV-005',
                'PD-STATE-002','PD-STATE-003','PD-TRACE-003','PD-TRACE-004'];
console.log('--- 2. anchor overlap with the other agent\'s eight branches');
for (const p of PATCHES) {
  const hit = OTHERS.filter(o => p.find.includes(o));
  console.log(`  ${p.name}: ${hit.length ? 'OVERLAPS ' + hit.join(',') : 'clean'}`);
}

console.log('--- 1. BEFORE (live, unpatched)');
const BEFORE = `
do $emit$
declare v_out text := ''; r record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','fourmore-before'));
  for r in select * from public.fn_phase_d_run_injected_defects()
            where defect_id in ('PD-DISP-001','PD-DISP-002','PD-DISP-004','PD-LEGAL-002')
            order by defect_id loop
    v_out := v_out || chr(10) || r.defect_id || ' [' || r.status || '] ' || left(coalesce(r.blocker,'(no blocker)'), 90);
  end loop;
  raise exception 'BEFORE<<%>>', v_out;
end $emit$;`;
try { await sql(BEFORE); } catch (e) {
  const m = /BEFORE<<([\s\S]*)>>/.exec(e.message);
  console.log(m ? m[1].split('\\n').join('\n') : e.message);
}

console.log('--- 3. outbound requests attributable to the patched run');
let body = live;
for (const p of PATCHES) body = body.replace(p.find, () => p.replace);
const NET = `
do $emit$
declare v_max bigint; v_n bigint; v_urls text;
begin
  execute $cand$${body}$cand$;
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','fourmore-net'));
  select coalesce(max(id),0) into v_max from net.http_request_queue;
  perform count(*) from public.fn_phase_d_run_injected_defects();
  select r.n, r.urls into v_n, v_urls from public.fn_phase_d_outbound_requests_by_this_transaction(v_max) r;
  raise exception 'NET<<outbound requests by this transaction = % ; %>>', coalesce(v_n,0), coalesce(v_urls,'(none)');
end $emit$;`;
try { await sql(NET); } catch (e) {
  const m = /NET<<([\s\S]*)>>/.exec(e.message);
  console.log(m ? m[1] : e.message.slice(0, 500));
}
