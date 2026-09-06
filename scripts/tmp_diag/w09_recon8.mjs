import { sql } from '../phase_b/lib/db.mjs';
import fs from 'node:fs';
const r = await sql(`select p.oid::regprocedure::text as sig, pg_get_functiondef(p.oid) as def
  from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
 where ns.nspname='public' and p.proname='fn_phase_d_fixture_scenario'`);
let out='';
for (const row of r) out += '\n\n========== ' + row.sig + ' ==========\n' + row.def;
fs.writeFileSync(new URL('./w09_scenario.txt', import.meta.url), out);
console.log('bytes', out.length);
