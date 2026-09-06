import { sql } from '../phase_b/lib/db.mjs';
for (const n of ['trg_rfq_complete','fn_rfq_required_check','fn_rfq_score']) {
  const r = await sql(`select pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname='${n}'`);
  console.log('\n===== '+n+'\n'+(r[0]?r[0].d.slice(0,3000):'NOT FOUND'));
}
