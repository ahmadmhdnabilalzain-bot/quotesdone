import { sql } from '../phase_b/lib/db.mjs';
const r = await sql(`select pg_get_functiondef('public.fn_phase_d_run_injected_defects()'::regprocedure) as d`);
process.stdout.write(r[0].d);
