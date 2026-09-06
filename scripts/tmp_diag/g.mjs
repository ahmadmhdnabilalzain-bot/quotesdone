import { sql } from '../phase_b/lib/db.mjs';
console.log(JSON.stringify(await sql(`select * from public.fn_phase_d_committed_scenario_guards()`), null, 1));
