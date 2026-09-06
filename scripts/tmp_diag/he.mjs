import { sql } from '../phase_b/lib/db.mjs';
import { writeFileSync } from 'node:fs';
const d = (await sql(`select pg_get_functiondef('public.fn_phase_d_handler_execute(jsonb)'::regprocedure) def`))[0].def;
writeFileSync('scripts/tmp_diag/he_body.txt', d);
console.log('lines=' + d.split('\n').length);
