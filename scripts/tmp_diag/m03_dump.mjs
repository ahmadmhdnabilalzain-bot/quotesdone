import { sql } from '../phase_b/lib/db.mjs';
import fs from 'node:fs';
const r = await sql(`select pg_get_functiondef('public.fn_phase_d_run_injected_defects()'::regprocedure) as d`);
fs.writeFileSync('scripts/tmp_diag/m03_live.sql', r[0].d);
console.log(r[0].d.split('\n').length, 'lines');
