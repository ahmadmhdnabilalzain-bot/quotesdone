import { sql } from '../lib/db.mjs';
console.log(JSON.stringify(await sql(`select * from public.fn_phase_d_disposition_state()`), null, 1).slice(0,1500));
