import { sql } from '../phase_b/lib/db.mjs';
const r = await sql(`select * from public.fn_phase_d_outbound_state()`);
for (const x of r) console.log(JSON.stringify(x));
