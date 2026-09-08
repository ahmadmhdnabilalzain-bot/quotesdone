import { sql } from '../lib/db.mjs';
console.log('== write map'); console.log(JSON.stringify(await sql(`select * from public.phase_d_object_write_map where object_id in ('supplier_assignment','supplier_account','inquiry')`),null,1));
console.log('== doors'); console.log(JSON.stringify(await sql(`select * from public.phase_d_outbound_door`),null,1));
