import { sql } from '../phase_b/lib/db.mjs';
for (const n of ['fn_phase_d_object_policy_guard','fn_phase_d_object_record_contract']) {
  const r = await sql(`select pg_get_functiondef(p.oid) as d from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname='${n}'`);
  console.log('\n===== '+n+' =====\n'+(r[0]?r[0].d:'NOT FOUND'));
}
