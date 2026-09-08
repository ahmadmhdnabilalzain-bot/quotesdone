import { sql } from '../lib/db.mjs';
import fs from 'node:fs';
const r = await sql(`select p.oid::regprocedure::text as sig, pg_get_functiondef(p.oid) as def
  from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
 where ns.nspname='public' and p.proname in ('fn_phase_d_handler_execute','fn_phase_d_dispatch_step') order by 1`);
let out='';
for (const row of r) out += '\n\n========== ' + row.sig + ' ==========\n' + row.def;
fs.writeFileSync(new URL('./w09_handler.txt', import.meta.url), out);
console.log('bytes', out.length, r.map(x=>x.sig).join(' | '));
