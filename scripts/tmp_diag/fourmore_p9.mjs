import { sql } from '../phase_b/lib/db.mjs';
console.log(JSON.stringify(await sql(`select step_id, workflow_id, handler_routine, gate_ids, rule_ids, business_object_writes, idempotency_template, failure_code_contract
 from public.phase_d_handler_binding where 'supplier_assignment' = any(business_object_writes)`),null,1));
const r = await sql(`select pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname='fn_phase_d_handler_execute'`);
require;
console.log('LEN', r[0].d.length);
