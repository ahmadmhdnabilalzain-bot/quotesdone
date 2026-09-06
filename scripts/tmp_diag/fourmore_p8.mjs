import { sql } from '../phase_b/lib/db.mjs';
console.log(JSON.stringify(await sql(`select b.step_id, b.handler_routine, b.rule_ids, b.gate_ids, b.business_object_writes
 from public.phase_d_handler_binding b where b.workflow_id='W12' order by b.step_id`),null,1));
console.log(JSON.stringify(await sql(`select b.step_id, b.handler_routine, b.rule_ids, b.gate_ids from public.phase_d_handler_binding b where 'BR-015' = any(b.rule_ids) or 'GATE-014' = any(b.gate_ids)`),null,1));
