import { sql } from '../lib/db.mjs';
import { writeFileSync } from 'node:fs';
const d = (await sql(`select pg_get_functiondef('public.fn_phase_d_outbound_state()'::regprocedure) def`))[0].def;
writeFileSync('scripts/tmp_diag/obs_body.txt', d);
console.log('lines=' + d.split('\n').length);
