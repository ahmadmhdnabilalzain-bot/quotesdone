import { sql } from '../lib/db.mjs';
import fs from 'node:fs';
const r = await sql(`select p.oid::regprocedure::text sig, pg_get_functiondef(p.oid) def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_gate_evaluate'`);
fs.writeFileSync('scripts/tmp_diag/recon_gate_eval.sql', r[0].def);
const i = r[0].def.indexOf('GATE-011');
console.log(r[0].def.slice(Math.max(0,i-1400), i+900));
