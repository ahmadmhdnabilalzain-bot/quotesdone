import { sql } from '../lib/db.mjs';
const names = [
 'public.fn_phase_d_gate_evaluate',
 'public.trg_gate_incomplete_match',
 'public.fn_unsafe_match_eligibility_guard',
 'public.fn_notify_matched_supplier',
 'public.a00_phase_d_object_policy_guard',
];
for (const n of names) {
  const r = await sql(`select p.oid::regprocedure::text as sig, pg_get_functiondef(p.oid) as d
    from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
    where ns.nspname||'.'||p.proname = '${n}'`);
  for (const x of r) { console.log('\n===== '+x.sig+' =====\n'+x.d); }
  if (!r.length) console.log('\n===== '+n+' : NOT FOUND =====');
}
