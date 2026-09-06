import { sql } from '../phase_b/lib/db.mjs';
const d = await sql(`select pg_get_functiondef(p.oid) def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_step_context'`);
console.log(d[0].def);
