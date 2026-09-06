import { sql } from '../phase_b/lib/db.mjs';
console.log(JSON.stringify(await sql(`select step_id, workflow_id, business_object_writes from public.phase_d_handler_binding where 'GATE-011' = any(gate_ids) order by step_id`)));
