import { sql } from '../phase_b/lib/db.mjs';
const out = {};
out.residue_def = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_fixture_residue'`);
out.residue_now = await sql(`select * from public.fn_phase_d_fixture_residue()`);
console.log(JSON.stringify(out, null, 1));
