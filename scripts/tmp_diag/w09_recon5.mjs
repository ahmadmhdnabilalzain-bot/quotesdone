import { sql } from '../lib/db.mjs';
import fs from 'node:fs';
const names = ['fn_phase_d_rule_check','fn_phase_d_rule_applies'];
let out = '';
for (const n of names) {
  const r = await sql(`select p.oid::regprocedure::text as sig, pg_get_functiondef(p.oid) as def from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname='${n}'`);
  for (const row of r) { out += '\n\n========== ' + row.sig + ' ==========\n' + row.def; }
}
fs.writeFileSync(new URL('./w09_fn_bodies.txt', import.meta.url), out);
console.log('bytes', out.length);
