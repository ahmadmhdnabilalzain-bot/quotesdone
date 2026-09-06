import { sql } from '../phase_b/lib/db.mjs';
const d = await sql(`select pg_get_functiondef('public.fn_phase_d_fixture_scenario(jsonb)'::regprocedure) as def`);
console.log(d[0].def);
